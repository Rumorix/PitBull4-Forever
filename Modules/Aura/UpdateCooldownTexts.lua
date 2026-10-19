
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local PitBull4_Aura = PitBull4:GetModule("Aura")

-- constants for formating time
local DAY_ONELETTER_ABBR = _G.DAY_ONELETTER_ABBR:gsub("%s", "") -- "%dd"
local HOUR_ONELETTER_ABBR = _G.HOUR_ONELETTER_ABBR:gsub("%s", "") -- "%dh"
local MINUTE_ONELETTER_ABBR = _G.MINUTE_ONELETTER_ABBR:gsub("%s", "") -- "%dm"

local timerFrame = CreateFrame("Frame")
timerFrame:Hide()

local next_text_update
local elapsed_since_text_update = 0
timerFrame:SetScript("OnUpdate",function(self, elapsed)
	next_text_update = (next_text_update or 0) - elapsed
	elapsed_since_text_update = elapsed_since_text_update + elapsed
	if next_text_update <= 0 then
		next_text_update = PitBull4_Aura:UpdateCooldownTexts(elapsed_since_text_update)
		elapsed_since_text_update = 0
	end
	if not next_text_update then
		self:Hide()
	end
end)

local cooldown_texts = {}

-- Midnight performance constants. Keep short aura text responsive without
-- allowing a zero-delay OnUpdate loop, and throttle explicit duration re-reads
-- for secret short-buff DurationObjects.
local LORENZO_PATCH94_MIN_TEXT_UPDATE_DELAY = 0.10
local LORENZO_PATCH94_DURATION_REFRESH_INTERVAL = 0.35
local LORENZO_PATCH94_CACHE_PRUNE_INTERVAL = 60
-- Order-neutral fallback for ordinary long player auras. Do not cache ordinary
-- long auras by auraInstanceID because recycled buttons / secret aura identity
-- can make a long timer appear on a different aura. Only use the current aura's
-- own safe numeric expirationTime when it is visible.
local LORENZO_PATCH96_SAFE_LONG_AURA_MIN_SECONDS = 60
-- Ordinary long player auras can briefly alternate between a safe expirationTime
-- path and a secret DurationObject path in combat. Keep the last same-instance
-- expirationTime-derived text for a very short window when expirationTime becomes
-- secret, instead of allowing a one-minute rounding bounce from the fallback path.
local LORENZO_PATCH100_LONG_AURA_HOLD_SECONDS = 3
local LORENZO_PATCH104_GENERIC_LONG_AURA_IDENTITY_TTL = 180
local LORENZO_PATCH104_GENERIC_LONG_AURA_CACHE_PRUNE_INTERVAL = 60


-- Optional Potency/Timeways aura diagnostics. These helpers stay limited to
-- PitBull aura controls, write only to the copyable debug window, and never add
-- a global FontString hook or Flask-specific recognition.
local LORENZO_PATCH83_DEBUG_PREFIX = "[PitBull4 Forever v61] "
local lorenzo_patch83_debug_seen = {}
local lorenzo_patch83_debug_total = 0

local function lorenzo_patch83_safe_value(value)
	if value == nil then
		return "nil"
	end
	if issecretvalue and issecretvalue(value) then
		return "<secret>"
	end
	local ok, text = pcall(tostring, value)
	if ok and text ~= nil then
		if text == "" then
			return "<empty>"
		end
		return text
	end
	return "<tostring-error>"
end

local function lorenzo_patch83_is_zero_text(value)
	if value == nil then
		return false
	end
	if issecretvalue and issecretvalue(value) then
		return false
	end
	if type(value) == "number" then
		return value == 0
	end
	if type(value) ~= "string" then
		return false
	end
	local ok, text = pcall(function()
		return value:gsub("%s+", ""):lower()
	end)
	if not ok or not text then
		return false
	end
	return text == "0" or text == "0s" or text == "0sec" or text == "0secs" or text == "0sek" or text == "0sek."
end

local function lorenzo_patch83_font_text(font_string)
	if not font_string or not font_string.GetText then
		return "nil"
	end
	local ok, text = pcall(font_string.GetText, font_string)
	if ok then
		return lorenzo_patch83_safe_value(text)
	end
	return "<GetText-error>"
end

local function lorenzo_patch83_duration_summary(duration)
	if not duration then
		return "nil"
	end
	local parts = { "obj=" .. lorenzo_patch83_safe_value(duration) }
	if duration.IsZero then
		local ok_zero, is_zero = pcall(duration.IsZero, duration)
		parts[#parts + 1] = "isZero=" .. (ok_zero and lorenzo_patch83_safe_value(is_zero) or "<err>")
	end
	if duration.GetRemainingDuration then
		local ok_remaining, remaining = pcall(duration.GetRemainingDuration, duration)
		parts[#parts + 1] = "remaining=" .. (ok_remaining and lorenzo_patch83_safe_value(remaining) or "<err>")
	end
	local formatted = format_secret_duration_text and format_secret_duration_text(duration) or nil
	if formatted ~= nil then
		parts[#parts + 1] = "formatted=" .. lorenzo_patch83_safe_value(formatted)
	end
	return table.concat(parts, ";")
end

local lorenzo_patch86_append_debug_line

-- Debug collection is off by default so normal aura updates do not run
-- scan/watch diagnostics or keep a growing copy buffer. Use /pitbull debugon to
-- enable it temporarily.
local lorenzo_patch93_debug_enabled = false
local function lorenzo_patch93_is_debug_enabled()
	return lorenzo_patch93_debug_enabled
end

function PitBull4_Aura:LorenzoPatch93IsDebugEnabled()
	return lorenzo_patch93_debug_enabled
end

local function lorenzo_patch83_chat(message)
	if not lorenzo_patch93_is_debug_enabled() then
		return
	end
	if lorenzo_patch83_debug_total >= 80 then
		if lorenzo_patch83_debug_total == 80 then
			lorenzo_patch83_debug_total = lorenzo_patch83_debug_total + 1
			if lorenzo_patch86_append_debug_line then
				lorenzo_patch86_append_debug_line(LORENZO_PATCH83_DEBUG_PREFIX .. "debug line limit reached; further output muted.")
			end
		end
		return
	end
	lorenzo_patch83_debug_total = lorenzo_patch83_debug_total + 1
	if lorenzo_patch86_append_debug_line then
		lorenzo_patch86_append_debug_line(LORENZO_PATCH83_DEBUG_PREFIX .. message)
	end
end


-- Manual diagnostic layer. It dumps PitBull's currently tracked player aura
-- text state into the copyable debug window without using chat spam, global
-- FontString hooks, or any Flask-specific handling.
local LORENZO_PATCH84_DEBUG_PREFIX = "[PitBull4 Forever v61] "
local LORENZO_PATCH86_PLAIN_PREFIX = "[PitBull4 Forever v61] "
local lorenzo_patch84_debug_total = 0
local lorenzo_patch84_debug_seen = {}
local lorenzo_patch84_loaded_message_sent = false
local lorenzo_patch84_registered_controls = setmetatable({}, { __mode = "k" })


-- Copyable debug output window. The window is diagnostic-only; it does not add
-- any additional aura sanitizing or Flask-specific behavior.
local lorenzo_patch86_debug_lines = {}
local lorenzo_patch86_debug_window
local lorenzo_patch86_debug_editbox
local lorenzo_patch86_debug_scroll

local function lorenzo_patch86_strip_chat_codes(text)
	if text == nil then
		return ""
	end
	local ok, value = pcall(tostring, text)
	if not ok or not value then
		return "<tostring-error>"
	end
	value = value:gsub("|c%x%x%x%x%x%x%x%x", "")
	value = value:gsub("|r", "")
	return value
end

local function lorenzo_patch86_update_debug_window()
	if not lorenzo_patch86_debug_editbox then
		return
	end
	local text = table.concat(lorenzo_patch86_debug_lines, "\n")
	lorenzo_patch86_debug_editbox:SetText(text)
	lorenzo_patch86_debug_editbox:SetHeight(math.max(360, (#lorenzo_patch86_debug_lines + 2) * 15))
	lorenzo_patch86_debug_editbox:SetCursorPosition(0)
	lorenzo_patch86_debug_editbox:HighlightText()
	if lorenzo_patch86_debug_scroll and lorenzo_patch86_debug_scroll.SetVerticalScroll then
		lorenzo_patch86_debug_scroll:SetVerticalScroll(0)
	end
end

function lorenzo_patch86_append_debug_line(message, force)
	if not force and not lorenzo_patch93_is_debug_enabled() then
		return
	end
	lorenzo_patch86_debug_lines[#lorenzo_patch86_debug_lines + 1] = lorenzo_patch86_strip_chat_codes(message)
	if #lorenzo_patch86_debug_lines > 700 then
		table.remove(lorenzo_patch86_debug_lines, 1)
	end
	if lorenzo_patch86_debug_window and lorenzo_patch86_debug_window:IsShown() then
		lorenzo_patch86_update_debug_window()
	end
end

function PitBull4_Aura:LorenzoPatch107DebugLine(message)
	if not lorenzo_patch93_is_debug_enabled() then
		return
	end
	lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. lorenzo_patch86_strip_chat_codes(message))
end

local function lorenzo_patch86_create_debug_window()
	if lorenzo_patch86_debug_window then
		return
	end

	local frame = CreateFrame("Frame", "PitBull4_LorenzoDebugWindow", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(920, 540)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -10)
	title:SetText("PitBull4 Debug Output")

	local help = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	help:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
	help:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
	help:SetJustifyH("LEFT")
	help:SetText("Copy: click into the text box, press Ctrl+A, then Ctrl+C. Use the PitBull Debug options or: /pitbull debugon, /pitbull debug scanall, /pitbull debugoff")

	local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -58)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 48)

	local editbox = CreateFrame("EditBox", nil, scroll)
	editbox:SetMultiLine(true)
	editbox:SetAutoFocus(false)
	editbox:SetFontObject(ChatFontNormal)
	editbox:SetWidth(850)
	editbox:SetTextInsets(4, 4, 4, 4)
	editbox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	editbox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	scroll:SetScrollChild(editbox)

	local scan_button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	scan_button:SetSize(88, 24)
	scan_button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
	scan_button:SetText("Scan")
	scan_button:SetScript("OnClick", function()
		if lorenzo_patch93_is_debug_enabled() then
			PitBull4_Aura:LorenzoPatch84ScanTrackedAuras("window-scan", true)
		else
			lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "debug is off. Use /pitbull debugon before scanning.", true)
			lorenzo_patch86_update_debug_window()
		end
	end)

	local scanall_button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	scanall_button:SetSize(88, 24)
	scanall_button:SetPoint("LEFT", scan_button, "RIGHT", 8, 0)
	scanall_button:SetText("Scan All")
	scanall_button:SetScript("OnClick", function()
		if lorenzo_patch93_is_debug_enabled() then
			PitBull4_Aura:LorenzoPatch84ScanTrackedAuras("window-scanall", false)
		else
			lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "debug is off. Use /pitbull debugon before scanning.", true)
			lorenzo_patch86_update_debug_window()
		end
	end)

	local clear_button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clear_button:SetSize(88, 24)
	clear_button:SetPoint("LEFT", scanall_button, "RIGHT", 8, 0)
	clear_button:SetText("Clear")
	clear_button:SetScript("OnClick", function()
		wipe(lorenzo_patch86_debug_lines)
		lorenzo_patch86_update_debug_window()
	end)

	local select_button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	select_button:SetSize(100, 24)
	select_button:SetPoint("LEFT", clear_button, "RIGHT", 8, 0)
	select_button:SetText("Select All")
	select_button:SetScript("OnClick", function()
		editbox:SetFocus()
		editbox:HighlightText()
	end)

	local close_button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close_button:SetSize(88, 24)
	close_button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
	close_button:SetText("Close")
	close_button:SetScript("OnClick", function() frame:Hide() end)

	lorenzo_patch86_debug_window = frame
	lorenzo_patch86_debug_editbox = editbox
	lorenzo_patch86_debug_scroll = scroll
end

local function lorenzo_patch86_show_debug_window()
	lorenzo_patch86_create_debug_window()
	lorenzo_patch86_update_debug_window()
	lorenzo_patch86_debug_window:Show()
	lorenzo_patch86_debug_editbox:SetFocus()
	lorenzo_patch86_debug_editbox:HighlightText()
end


local function lorenzo_debug_notify_options()
	local registry = LibStub("AceConfigRegistry-3.0", true)
	if registry and PitBull4.Options and PitBull4.Options.IsRegistered and PitBull4.Options.IsRegistered() then
		registry:NotifyChange("PitBull4")
	end
end

function PitBull4_Aura:IsDebugModeEnabled()
	return lorenzo_patch93_is_debug_enabled()
end

function PitBull4_Aura:SetDebugMode(enabled, show_window)
	enabled = not not enabled
	if enabled then
		if not lorenzo_patch93_debug_enabled then
			lorenzo_patch93_debug_enabled = true
			lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "debug enabled. Use Scan or Scan All, then copy the output from the Debug Window.", true)
		end
	else
		if lorenzo_patch93_debug_enabled then
			lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "debug disabled. Automatic diagnostic collection is now inactive.", true)
		end
		lorenzo_patch93_debug_enabled = false
		wipe(lorenzo_patch84_registered_controls)
		wipe(lorenzo_patch84_debug_seen)
		wipe(lorenzo_patch83_debug_seen)
	end
	if show_window then
		lorenzo_patch86_show_debug_window()
	end
	lorenzo_debug_notify_options()
end

function PitBull4_Aura:OpenDebugWindow()
	lorenzo_patch86_show_debug_window()
end

function PitBull4_Aura:RunDebugScan(scan_all, reason, show_window)
	if not lorenzo_patch93_is_debug_enabled() then
		lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "debug is off. Enable Debug Mode before running scans.", true)
		if show_window then
			lorenzo_patch86_show_debug_window()
		end
		lorenzo_debug_notify_options()
		return false
	end
	if show_window then
		lorenzo_patch86_show_debug_window()
	end
	self:LorenzoPatch84ScanTrackedAuras(reason or (scan_all and "manual-scanall" or "manual-scan"), not scan_all)
	if show_window then
		lorenzo_patch86_show_debug_window()
	end
	lorenzo_debug_notify_options()
	return true
end

function PitBull4_Aura:ClearDebugOutput(show_window)
	wipe(lorenzo_patch86_debug_lines)
	lorenzo_patch86_update_debug_window()
	if show_window then
		lorenzo_patch86_show_debug_window()
	end
	lorenzo_debug_notify_options()
end

function PitBull4_Aura:ResetDebugState(show_window)
	lorenzo_patch83_debug_total = 0
	lorenzo_patch84_debug_total = 0
	wipe(lorenzo_patch83_debug_seen)
	wipe(lorenzo_patch84_debug_seen)
	wipe(lorenzo_patch86_debug_lines)
	if lorenzo_patch93_is_debug_enabled() then
		lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "debug counters and output have been reset.", true)
	end
	lorenzo_patch86_update_debug_window()
	if show_window then
		lorenzo_patch86_show_debug_window()
	end
	lorenzo_debug_notify_options()
end

function PitBull4_Aura:GetDebugOutput()
	return table.concat(lorenzo_patch86_debug_lines, "\n")
end

function PitBull4_Aura:LorenzoPatch84RegisterAuraControl(control)
	if control then
		lorenzo_patch84_registered_controls[control] = true
	end
end

local function lorenzo_patch84_chat(message, force)
	if not force and not lorenzo_patch93_is_debug_enabled() then
		return
	end
	if not force and lorenzo_patch84_debug_total >= 120 then
		if lorenzo_patch84_debug_total == 120 then
			lorenzo_patch84_debug_total = lorenzo_patch84_debug_total + 1
			lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "debug line limit reached; use /reload or /pitbull debug reset to reset debug output.")
		end
		return
	end
	if not force then
		lorenzo_patch84_debug_total = lorenzo_patch84_debug_total + 1
	end
	lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. message, force)
end

local function lorenzo_patch84_lower(value)
	if value == nil or (issecretvalue and issecretvalue(value)) or type(value) ~= "string" then
		return nil
	end
	local ok, lowered = pcall(string.lower, value)
	return ok and lowered or nil
end

local function lorenzo_patch84_is_candidate_aura(aura)
	if not aura then
		return false
	end
	if aura.lorenzo_known_long_buff or aura.lorenzo_long_buff_zero_guard then
		return true
	end
	local name = lorenzo_patch84_lower(aura.name)
	if name and (name:find("potency", 1, true) or name:find("timeways", 1, true) or name:find("timeway", 1, true)) then
		return true
	end
	local spell = lorenzo_patch83_safe_value(aura.spell_id)
	return spell == "1272300" or spell == "1272321" or spell == "423860" or spell == "423861" or spell == "1229050"
end

local function lorenzo_patch84_unit_is_player(aura)
	if not aura or not aura.unit then
		return false
	end
	if UnitIsUnit then
		local ok, same = pcall(UnitIsUnit, aura.unit, "player")
		if ok and same then
			return true
		end
	end
	return aura.unit == "player"
end

local function lorenzo_patch84_has_zero_text(aura)
	if not aura then
		return false
	end
	local count_text = aura.count_text and aura.count_text.GetText and aura.count_text:GetText() or nil
	local cooldown_text = aura.cooldown_text and aura.cooldown_text.GetText and aura.cooldown_text:GetText() or nil
	return lorenzo_patch83_is_zero_text(aura.count)
		or lorenzo_patch83_is_zero_text(count_text)
		or lorenzo_patch83_is_zero_text(cooldown_text)
end

function PitBull4_Aura:LorenzoPatch84DebugAuraLine(aura, path, extra, force)
	if not aura then
		return
	end
	local now = GetTime and GetTime() or 0
	local key = table.concat({
		lorenzo_patch83_safe_value(path),
		lorenzo_patch83_safe_value(aura.unit),
		lorenzo_patch83_safe_value(aura.id),
		lorenzo_patch83_safe_value(aura.index),
		lorenzo_patch83_safe_value(aura.name),
		lorenzo_patch83_safe_value(aura.spell_id),
		lorenzo_patch83_safe_value(extra),
	}, "|")
	if not force and lorenzo_patch84_debug_seen[key] and lorenzo_patch84_debug_seen[key] > now then
		return
	end
	lorenzo_patch84_debug_seen[key] = now + 1.5

	local control_name = aura.GetName and lorenzo_patch83_safe_value(aura:GetName()) or "nil"
	local shown = aura.IsShown and lorenzo_patch83_safe_value(aura:IsShown()) or "nil"
	local cd_shown = "nil"
	if aura.cooldown and aura.cooldown.IsShown then
		local ok, value = pcall(aura.cooldown.IsShown, aura.cooldown)
		cd_shown = ok and lorenzo_patch83_safe_value(value) or "<err>"
	end
	lorenzo_patch84_chat(
		"path=" .. lorenzo_patch83_safe_value(path) ..
		" control=" .. control_name ..
		" shown=" .. shown ..
		" unit=" .. lorenzo_patch83_safe_value(aura.unit) ..
		" idx=" .. lorenzo_patch83_safe_value(aura.index) ..
		" id=" .. lorenzo_patch83_safe_value(aura.id) ..
		" name=" .. lorenzo_patch83_safe_value(aura.name) ..
		" spell=" .. lorenzo_patch83_safe_value(aura.spell_id) ..
		" icon=" .. lorenzo_patch83_safe_value(aura.icon) ..
		" known=" .. lorenzo_patch83_safe_value(aura.lorenzo_known_long_buff) ..
		" guard=" .. lorenzo_patch83_safe_value(aura.lorenzo_long_buff_zero_guard) ..
		" count=" .. lorenzo_patch83_safe_value(aura.count) ..
		" countText=" .. lorenzo_patch83_font_text(aura.count_text) ..
		" cdText=" .. lorenzo_patch83_font_text(aura.cooldown_text) ..
		" cdShown=" .. cd_shown ..
		" exp=" .. lorenzo_patch83_safe_value(aura.expiration_time) ..
		" timeMod=" .. lorenzo_patch83_safe_value(aura.time_mod) ..
		" duration={" .. lorenzo_patch83_duration_summary(aura.duration) .. "}" ..
		(extra and (" extra=" .. lorenzo_patch83_safe_value(extra)) or ""),
		force
	)
end

function PitBull4_Aura:LorenzoPatch84ScanTrackedAuras(reason, only_candidates)
	local seen = {}
	local tracked = 0
	local printed = 0
	local zeros = 0
	local candidates = 0
	local tree_zeros = 0

	local function visit(aura, source)
		if not aura or seen[aura] then
			return
		end
		seen[aura] = true
		tracked = tracked + 1
		local is_player = lorenzo_patch84_unit_is_player(aura)
		local is_candidate = lorenzo_patch84_is_candidate_aura(aura)
		local has_zero = lorenzo_patch84_has_zero_text(aura)
		local has_tree_zero = false
		if is_player and self.LorenzoPatch83ScanZeroText then
			-- Reuse the deeper region scan so scan/scanall can catch zero text
			-- attached to cooldown child regions or recycled control FontStrings too.
			has_tree_zero = self:LorenzoPatch83ScanZeroText(aura, (reason or "scan") .. "-tree")
		end
		if is_candidate then
			candidates = candidates + 1
		end
		if has_zero then
			zeros = zeros + 1
		end
		if has_tree_zero then
			tree_zeros = tree_zeros + 1
		end
		if is_player and (has_zero or has_tree_zero or is_candidate or not only_candidates) then
			printed = printed + 1
			if printed <= 60 then
				local extra = (has_zero or has_tree_zero) and ("tracked-zero source=" .. source) or ("tracked source=" .. source)
				self:LorenzoPatch84DebugAuraLine(aura, reason or "scan", extra, true)
			end
		end
	end

	for aura in pairs(cooldown_texts) do
		visit(aura, "cooldown_texts")
	end
	for aura in pairs(lorenzo_patch84_registered_controls) do
		visit(aura, "registered")
	end

	local portrait_module = PitBull4:GetModule("Portrait", true)
	if portrait_module and portrait_module.LorenzoPatch107DebugSnapshot then
		portrait_module:LorenzoPatch107DebugSnapshot(reason or "scan")
	end
	local background_module = PitBull4:GetModule("Background", true)
	if background_module and background_module.LorenzoPatch107DebugSnapshot then
		background_module:LorenzoPatch107DebugSnapshot(reason or "scan")
	end

	if PitBull4_Aura.Lorenzo121GetStatusLines then
		for _, line in ipairs(PitBull4_Aura:Lorenzo121GetStatusLines()) do
			lorenzo_patch84_chat(line, true)
		end
	end

	lorenzo_patch84_chat(
		"scan-summary reason=" .. lorenzo_patch83_safe_value(reason) ..
		" tracked=" .. tracked ..
		" playerPrinted=" .. printed ..
		" candidates=" .. candidates ..
		" directZeros=" .. zeros ..
		" treeZeros=" .. tree_zeros ..
		" onlyCandidates=" .. lorenzo_patch83_safe_value(only_candidates) ..
		". Use /pitbull debugon, then /pitbull debug scanall to dump registered player aura texts.",
		true
	)
end

local lorenzo_patch89_original_pitbull_slash
local lorenzo_patch89_pitbull_slash_wrapped = false

local function lorenzo_patch89_debug_command(msg)
	msg = msg and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
	if msg == "on" or msg == "enable" or msg == "enabled" or msg == "debugon" then
		PitBull4_Aura:SetDebugMode(true, true)
		return
	elseif msg == "off" or msg == "disable" or msg == "disabled" or msg == "debugoff" then
		PitBull4_Aura:SetDebugMode(false, true)
		return
	elseif msg == "status" then
		lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "debug status: " .. (lorenzo_patch93_is_debug_enabled() and "enabled" or "disabled"), true)
		lorenzo_patch86_show_debug_window()
		return
	end

	if not lorenzo_patch93_is_debug_enabled() then
		if msg == "" or msg == "window" or msg == "show" or msg == "copy" then
			lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "debug is off. Use /pitbull debugon to enable copyable aura diagnostics.", true)
			lorenzo_patch86_show_debug_window()
		else
			lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "debug is off. Use /pitbull debugon before running scans.", true)
			lorenzo_patch86_show_debug_window()
		end
		return
	end

	if msg == "scanall" or msg == "all" then
		PitBull4_Aura:RunDebugScan(true, "slash-scanall", true)
	elseif msg == "scan" then
		PitBull4_Aura:RunDebugScan(false, "slash-scan", true)
	elseif msg == "" or msg == "window" or msg == "show" or msg == "copy" then
		PitBull4_Aura:OpenDebugWindow()
	elseif msg == "clear" then
		PitBull4_Aura:ClearDebugOutput(true)
	elseif msg == "reset" then
		PitBull4_Aura:ResetDebugState(true)
	else
		lorenzo_patch84_chat("commands: /pitbull debugon, /pitbull debug, /pitbull debug scan, /pitbull debug scanall, /pitbull debug clear, /pitbull debug reset, /pitbull debugoff, /pitbull raidperf on|off|status, /pitbull foreverstatus, /pitbull forevernative on|off|status|rebuild", true)
		lorenzo_patch86_show_debug_window()
	end
end
local function lorenzo_121_status_command()
	if PitBull4_Aura.Lorenzo121GetStatusLines then
		for _, line in ipairs(PitBull4_Aura:Lorenzo121GetStatusLines()) do
			lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. line, true)
		end
	else
		lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "12.1 compatibility scaffold is not loaded.", true)
	end
	lorenzo_patch86_show_debug_window()
end

-- v47: Read-only configuration diagnostics for cross-layout ownership styling.
-- Does not inspect Blizzard's protected aura records.
local function lorenzo_121_aura_colors_command()
    local profile = PitBull4_Aura.db and PitBull4_Aura.db.profile
    local layouts = profile and profile.layouts
    lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX ..
        "v47 aura owner-color diagnostics: strict is PER LAYOUT; strict=true uses neutral combined borders.", true)
    if type(layouts) == "table" then
        local names = {}
        for name, layout in pairs(layouts) do
            if type(layout) == "table" then
                names[#names + 1] = name
            end
        end
        table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
        for _, name in ipairs(names) do
            local layout = layouts[name]
            local style = layout.ownership_style
            local own = type(style) == "table" and style.own_color or nil
            local other = type(style) == "table" and style.other_color or nil
            local function fmt(color)
                if type(color) ~= "table" then return "default" end
                return table.concat({
                    tostring(color[1]), tostring(color[2]),
                    tostring(color[3]), tostring(color[4]),
                }, ",")
            end
            lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX ..
                "aura layout=" .. tostring(name) ..
                " strict=" .. tostring(layout.native_strict_limit ~= false) ..
                " borders=" .. tostring(type(style) == "table" and style.enabled or false) ..
                " ownRGBA=" .. fmt(own) ..
                " otherRGBA=" .. fmt(other), true)
        end
    else
        lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX ..
            "Aura layout database not initialized.", true)
    end
    lorenzo_patch86_show_debug_window()
end

local function lorenzo_121_native_command(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "on" or msg == "enable" or msg == "enabled" then
		if PitBull4_Aura.Lorenzo121SetNativeEnabled then
			PitBull4_Aura:Lorenzo121SetNativeEnabled(true)
		end
		lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "12.1 native AuraContainer renderer enabled.", true)
	elseif msg == "off" or msg == "disable" or msg == "disabled" then
		if PitBull4_Aura.Lorenzo121SetNativeEnabled then
			PitBull4_Aura:Lorenzo121SetNativeEnabled(false)
		end
		lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "12.1 native AuraContainer renderer disabled; Patch 114 legacy fallback is active.", true)
	elseif msg == "rebuild" or msg == "reset" then
		if PitBull4_Aura.Lorenzo121RebuildNativeContainers then
			PitBull4_Aura:Lorenzo121RebuildNativeContainers()
		end
		lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "12.1 native AuraContainer frames rebuilt.", true)
	else
		local enabled = PitBull4_Aura.Lorenzo121GetNativeEnabled and PitBull4_Aura:Lorenzo121GetNativeEnabled()
		local active = PitBull4_Aura.Lorenzo121NativeRendererActive and PitBull4_Aura:Lorenzo121NativeRendererActive()
		lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "12.1 native renderer requested=" .. tostring(enabled) .. " active=" .. tostring(active) .. ". Use /pitbull forevernative on|off|rebuild.", true)
	end
	lorenzo_121_status_command()
end

local function lorenzo_patch105_raidperf_command(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local aura_module = PitBull4_Aura
	if msg == "on" or msg == "enable" or msg == "enabled" then
		if aura_module.LorenzoPatch105SetRaidPerformanceMode then
			aura_module:LorenzoPatch105SetRaidPerformanceMode(true)
		end
		lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "raid performance mode enabled. Helpful buff timer text on non-player raid roster frames is suppressed while in raid; debuffs and player timers stay active.", true)
		lorenzo_patch86_show_debug_window()
		return
	elseif msg == "off" or msg == "disable" or msg == "disabled" then
		if aura_module.LorenzoPatch105SetRaidPerformanceMode then
			aura_module:LorenzoPatch105SetRaidPerformanceMode(false)
		end
		lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "raid performance mode disabled.", true)
		lorenzo_patch86_show_debug_window()
		return
	end
	local enabled = aura_module.LorenzoPatch105GetRaidPerformanceMode and aura_module:LorenzoPatch105GetRaidPerformanceMode()
	lorenzo_patch86_append_debug_line(LORENZO_PATCH86_PLAIN_PREFIX .. "raid performance mode is " .. (enabled and "enabled" or "disabled") .. ". Use /pitbull raidperf on or /pitbull raidperf off.", true)
	lorenzo_patch86_show_debug_window()
end

local function lorenzo_patch89_pitbull_slash_handler(msg)
	local raw_msg = msg or ""
	local lowered = raw_msg:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if lowered == "auracolors" or lowered == "121auracolors" then
        lorenzo_121_aura_colors_command()
        return
    end
	if lowered == "foreverstatus" or lowered == "121status" or lowered == "12.1status" or lowered == "ptrstatus" then
		lorenzo_121_status_command()
		return
	end
	if lowered == "forevernative" or lowered:match("^forevernative%s+") or lowered == "121native" or lowered:match("^121native%s+") then
		local native_rest = lowered:gsub("^forevernative%s*", ""):gsub("^121native%s*", "")
		lorenzo_121_native_command(native_rest)
		return
	end
	if lowered == "raidperf" or lowered:match("^raidperf%s+") then
		local raidperf_rest = lowered:gsub("^raidperf%s*", "")
		lorenzo_patch105_raidperf_command(raidperf_rest)
		return
	end
	if lowered == "debugon" then
		lorenzo_patch89_debug_command("on")
		return
	elseif lowered == "debugoff" then
		lorenzo_patch89_debug_command("off")
		return
	end
	local debug_rest = lowered:match("^debug%s*(.*)$")
	if debug_rest ~= nil then
		lorenzo_patch89_debug_command(debug_rest)
		return
	end
	if lorenzo_patch89_original_pitbull_slash then
		return lorenzo_patch89_original_pitbull_slash(raw_msg)
	end
	if PitBull4.Options and PitBull4.Options.OpenConfig then
		return PitBull4.Options.OpenConfig()
	end
end

local function lorenzo_patch84_install_slash_command()
	-- Keep the supported PitBull command only. Legacy /pb4pXX debug aliases from
	-- earlier diagnostic builds are intentionally not registered anymore so normal
	-- play has less command clutter and fewer persistent hooks.
	if not lorenzo_patch89_pitbull_slash_wrapped and SlashCmdList.PITBULLFOUR ~= lorenzo_patch89_pitbull_slash_handler then
		lorenzo_patch89_original_pitbull_slash = SlashCmdList.PITBULLFOUR
		SlashCmdList.PITBULLFOUR = lorenzo_patch89_pitbull_slash_handler
		lorenzo_patch89_pitbull_slash_wrapped = true
	end
end
local lorenzo_patch84_event_frame = CreateFrame("Frame")
lorenzo_patch84_event_frame:RegisterEvent("PLAYER_LOGIN")
lorenzo_patch84_event_frame:RegisterEvent("PLAYER_ENTERING_WORLD")
lorenzo_patch84_event_frame:RegisterEvent("CHALLENGE_MODE_START")
lorenzo_patch84_event_frame:SetScript("OnEvent", function(_, event)
	if not lorenzo_patch84_loaded_message_sent and (event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD") then
		lorenzo_patch84_loaded_message_sent = true
		lorenzo_patch84_install_slash_command()
	end
	if not lorenzo_patch93_is_debug_enabled() then
		return
	end
	if event == "PLAYER_ENTERING_WORLD" or event == "CHALLENGE_MODE_START" then
		lorenzo_patch84_chat("event=" .. event .. " scheduled focused debug-window scan in 1s/4s.", true)
		if C_Timer and C_Timer.After then
			C_Timer.After(1, function()
				if lorenzo_patch93_is_debug_enabled() then
					PitBull4_Aura:LorenzoPatch84ScanTrackedAuras(event .. "+1s", true)
				end
			end)
			C_Timer.After(4, function()
				if lorenzo_patch93_is_debug_enabled() then
					PitBull4_Aura:LorenzoPatch84ScanTrackedAuras(event .. "+4s", true)
				end
			end)
		end
	end
end)

-- Make the command available even if PLAYER_LOGIN already fired during a reload path.
lorenzo_patch84_install_slash_command()

function PitBull4_Aura:LorenzoPatch83DebugAura(control, path, extra)
	if not control then
		return
	end
	local now = GetTime and GetTime() or 0
	local key = table.concat({
		lorenzo_patch83_safe_value(path),
		lorenzo_patch83_safe_value(control.unit),
		lorenzo_patch83_safe_value(control.id),
		lorenzo_patch83_safe_value(control.name),
		lorenzo_patch83_safe_value(control.spell_id),
		lorenzo_patch83_safe_value(extra),
	}, "|")
	if lorenzo_patch83_debug_seen[key] and lorenzo_patch83_debug_seen[key] > now then
		return
	end
	lorenzo_patch83_debug_seen[key] = now + 2.0

	local cd_shown = "nil"
	if control.cooldown and control.cooldown.IsShown then
		local ok, shown = pcall(control.cooldown.IsShown, control.cooldown)
		cd_shown = ok and lorenzo_patch83_safe_value(shown) or "<err>"
	end
	local control_name = control.GetName and lorenzo_patch83_safe_value(control:GetName()) or "nil"
	lorenzo_patch83_chat(
		"path=" .. lorenzo_patch83_safe_value(path) ..
		" control=" .. control_name ..
		" unit=" .. lorenzo_patch83_safe_value(control.unit) ..
		" idx=" .. lorenzo_patch83_safe_value(control.index) ..
		" id=" .. lorenzo_patch83_safe_value(control.id) ..
		" name=" .. lorenzo_patch83_safe_value(control.name) ..
		" spell=" .. lorenzo_patch83_safe_value(control.spell_id) ..
		" icon=" .. lorenzo_patch83_safe_value(control.icon) ..
		" known=" .. lorenzo_patch83_safe_value(control.lorenzo_known_long_buff) ..
		" guard=" .. lorenzo_patch83_safe_value(control.lorenzo_long_buff_zero_guard) ..
		" count=" .. lorenzo_patch83_safe_value(control.count) ..
		" countText=" .. lorenzo_patch83_font_text(control.count_text) ..
		" cdText=" .. lorenzo_patch83_font_text(control.cooldown_text) ..
		" cooldownShown=" .. cd_shown ..
		" exp=" .. lorenzo_patch83_safe_value(control.expiration_time) ..
		" timeMod=" .. lorenzo_patch83_safe_value(control.time_mod) ..
		" duration={" .. lorenzo_patch83_duration_summary(control.duration) .. "}" ..
		(extra and (" extra=" .. lorenzo_patch83_safe_value(extra)) or "")
	)
end

local function lorenzo_patch83_scan_font_string(font_string, label, out)
	if not font_string or not font_string.GetText then
		return
	end
	local ok, text = pcall(font_string.GetText, font_string)
	if ok and lorenzo_patch83_is_zero_text(text) then
		local name = font_string.GetName and font_string:GetName() or nil
		out[#out + 1] = label .. ":" .. lorenzo_patch83_safe_value(name) .. "=" .. lorenzo_patch83_safe_value(text)
	end
end

local function lorenzo_patch83_scan_regions(frame, label, out, depth)
	if not frame or depth > 3 then
		return
	end
	if frame.GetRegions then
		local regions = { frame:GetRegions() }
		for i = 1, #regions do
			local region = regions[i]
			if region and region.GetObjectType then
				local ok_type, object_type = pcall(region.GetObjectType, region)
				if ok_type and object_type == "FontString" then
					lorenzo_patch83_scan_font_string(region, label .. ".region" .. i, out)
				end
			end
		end
	end
	if frame.GetChildren then
		local children = { frame:GetChildren() }
		for i = 1, #children do
			lorenzo_patch83_scan_regions(children[i], label .. ".child" .. i, out, depth + 1)
		end
	end
end

function PitBull4_Aura:LorenzoPatch83ScanZeroText(control, path)
	if not control then
		return false
	end
	local zeros = {}
	lorenzo_patch83_scan_font_string(control.count_text, "count_text", zeros)
	lorenzo_patch83_scan_font_string(control.cooldown_text, "cooldown_text", zeros)
	lorenzo_patch83_scan_regions(control.cooldown, "cooldown", zeros, 0)
	lorenzo_patch83_scan_regions(control, "control", zeros, 0)
	if #zeros > 0 then
		self:LorenzoPatch83DebugAura(control, path or "zero-scan", "zero=" .. table.concat(zeros, ","))
		return true
	end
	return false
end

-- Stable Midnight aura update path. Use Blizzard's DurationObject formatter
-- when Midnight returns a secret remaining duration. This preserves normal
-- stacks/short aura behavior while avoiding raw/invalid timer text in combat.
local lorenzo_duration_formatters = {}

-- Patch 068: AuraData.timeMod can intentionally slow or pause consumable
-- durations (for example the W-47CH D0G effect). PitBull previously converted
-- the visible remaining time through the real-time modifier, which can turn a
-- paused one-hour food/flask aura into a multi-day display. Blizzard's
-- DurationObject API exposes BaseTime specifically for displaying the
-- unmodified aura time. Use it only when a public timeMod says the aura is
-- time-scaled; ordinary auras retain the existing RealTime path.
local LORENZO_PATCH68_BASE_TIME = Enum and Enum.DurationTimeModifier and Enum.DurationTimeModifier.BaseTime or 1

local function lorenzo_patch68_uses_modified_time(aura, duration)
	-- Patch 070: AuraData.timeMod is not guaranteed to refresh when an external
	-- effect changes the live speed of an existing aura. W-47CH D0G is a concrete
	-- example: the tooltip follows the DurationObject's current mod rate while the
	-- cached AuraData field can remain at its previous value. Prefer either public
	-- signal, but never inspect a secret numeric value.
	if aura then
		local time_mod = aura.time_mod
		if time_mod ~= nil and not issecretvalue(time_mod) and type(time_mod) == "number" and time_mod ~= 1 then
			return true
		end
	end

	if duration and duration.GetModRate then
		local ok, mod_rate = pcall(duration.GetModRate, duration)
		if ok and mod_rate ~= nil and not issecretvalue(mod_rate) and type(mod_rate) == "number" and mod_rate ~= 1 then
			return true
		end
	end

	return false
end

local function get_duration_formatter()
	if not C_StringUtil or not C_StringUtil.CreateSecondsFormatter then
		return nil
	end
	if lorenzo_duration_formatters.default ~= nil then
		return lorenzo_duration_formatters.default or nil
	end
	local ok, formatter = pcall(C_StringUtil.CreateSecondsFormatter)
	if not ok or not formatter then
		lorenzo_duration_formatters.default = false
		return nil
	end
	if formatter.SetDefaultAbbreviation and Enum and Enum.SecondsFormatterAbbreviation and Enum.SecondsFormatterAbbreviation.OneLetter then
		pcall(formatter.SetDefaultAbbreviation, formatter, Enum.SecondsFormatterAbbreviation.OneLetter)
	end
	if formatter.SetStripIntervalWhitespace then
		pcall(formatter.SetStripIntervalWhitespace, formatter, true)
	end
	if formatter.SetDesiredUnitCount then
		pcall(formatter.SetDesiredUnitCount, formatter, 1)
	end
	lorenzo_duration_formatters.default = formatter
	return formatter
end

local function set_cooldown_text(font_string, value)
	if not font_string then
		return
	end
	-- Hide only literal non-secret zero-duration text. Do this late in the
	-- cooldown update path, after PitBull has already configured the font, so we
	-- do not reintroduce the old 'Font not set' issue.
	if value ~= nil and not issecretvalue(value) then
		if value == 0 or value == "0" or value == "0s" or value == "0 s" then
			if PitBull4_Aura.LorenzoPatch83DebugAura then
				PitBull4_Aura:LorenzoPatch83DebugAura(font_string.lorenzo_aura_control, "cooldown_text:SetText-zero", "incoming=" .. lorenzo_patch83_safe_value(value) .. ";kind=" .. lorenzo_patch83_safe_value(font_string.lorenzo_aura_text_kind))
			end
			font_string:SetText("")
			return
		end
	end
	font_string:SetText(value)
end

-- Narrow cache/suppression for targeted Potency/Timeways long-buffs that can
-- briefly format as 0s when a key starts. This is intentionally limited to auras
-- already flagged as lorenzo_known_long_buff, so normal short buffs, permanent
-- buffs, stacks, group frames, and Flask behavior are left alone.
local function lorenzo_is_zero_text(value)
	if value == nil or issecretvalue(value) then
		return false
	end
	if type(value) == "number" then
		return value == 0
	end
	if type(value) ~= "string" then
		return false
	end
	local ok, text = pcall(function()
		return value:gsub("%s+", ""):lower()
	end)
	if not ok or not text then
		return false
	end
	return text == "0" or text == "0s" or text == "0sec" or text == "0secs" or text == "0sek" or text == "0sek."
end

local lorenzo_known_long_buff_text_cache = {}
local lorenzo_prune_known_long_buff_text_cache

local function lorenzo_safe_cache_part(value)
	if value == nil or issecretvalue(value) then
		return nil
	end
	local ok, text = pcall(tostring, value)
	if ok and text and text ~= "" then
		return text
	end
	return nil
end

local function lorenzo_cache_aura_is_player(aura)
	if not aura or not aura.unit then
		return false
	end
	if UnitIsUnit then
		local ok, same = pcall(UnitIsUnit, aura.unit, "player")
		if ok and same then
			return true
		end
	end
	return false
end

local function lorenzo_get_known_long_buff_cache_keys(aura)
	if not aura or not aura.lorenzo_known_long_buff then
		return nil
	end

	-- Store/read all safe aliases instead of only the first one. Outside a key
	-- Midnight often exposes name/spell id, while at key start it can hide those
	-- and leave only the icon. Keeping the icon alias lets the cached good timer
	-- survive that transition without adding Flask-specific logic.
	local keys = {}
	local spell_id = lorenzo_safe_cache_part(aura.spell_id)
	if spell_id then
		keys[#keys + 1] = "spell:" .. spell_id
	end
	local name = lorenzo_safe_cache_part(aura.name)
	if name then
		keys[#keys + 1] = "name:" .. name
	end
	local icon = lorenzo_safe_cache_part(aura.icon)
	if icon then
		keys[#keys + 1] = "icon:" .. icon
	end

	-- Inside a Mythic+ key, Midnight can hide name/spell/icon/expiration while
	-- keeping the same player auraInstanceID. Cache the last proven good
	-- Potency/Timeways text by that instance ID so the secret rebuild can display
	-- the cached timer instead of falling back to a secret/zero DurationObject.
	if lorenzo_cache_aura_is_player(aura) then
		local instance_id = lorenzo_safe_cache_part(aura.id)
		if instance_id then
			keys[#keys + 1] = "player-id:" .. instance_id
		end
	end

	return #keys > 0 and keys or nil
end

local function lorenzo_get_cached_known_long_buff_text(cooldown_text, aura)
	-- Do not trust the FontString-local cache first. Aura buttons are recycled
	-- aggressively during Mythic+ entry, so only use identity-keyed cache entries
	-- from the current aura (spell/name/icon/player-id).
	local cached
	local keys = lorenzo_get_known_long_buff_cache_keys(aura)
	if lorenzo_prune_known_long_buff_text_cache then
		lorenzo_prune_known_long_buff_text_cache()
	end
	if keys then
		for i = 1, #keys do
			cached = lorenzo_known_long_buff_text_cache[keys[i]]
			if cached and not lorenzo_is_zero_text(cached) then
				return cached
			end
		end
	end
	return nil
end

local function lorenzo_store_cached_known_long_buff_text(cooldown_text, aura, value)
	if not aura or not aura.lorenzo_known_long_buff then
		return
	end
	if value == nil or value == "" or issecretvalue(value) or lorenzo_is_zero_text(value) then
		return
	end
	-- Keep this informational only; do not read it as a fallback without a matching
	-- aura identity. The real cache is keyed below.
	cooldown_text.lorenzo_last_known_long_text = value
	cooldown_text.lorenzo_last_known_long_key = nil
	local keys = lorenzo_get_known_long_buff_cache_keys(aura)
	if keys then
		for i = 1, #keys do
			lorenzo_known_long_buff_text_cache[keys[i]] = value
		end
	end
end

local function set_known_long_buff_text(cooldown_text, aura, value)
	local zero_guard = aura and (aura.lorenzo_known_long_buff or aura.lorenzo_long_buff_zero_guard)
	if zero_guard then
		if value ~= nil and issecretvalue(value) then
			-- The remaining visible 0s can be a secret FontString payload. Because secret
			-- strings cannot be inspected for "0s", never write them while the narrow
			-- long-buff/secret-player guard is active. Use a cached known long-buff value
			-- when available; otherwise blank the text.
			local cached = aura.lorenzo_known_long_buff and lorenzo_get_cached_known_long_buff_text(cooldown_text, aura) or nil
			if cached then
				pcall(cooldown_text.SetAlpha, cooldown_text, 1)
				set_cooldown_text(cooldown_text, cached)
			else
				set_cooldown_text(cooldown_text, "")
				pcall(cooldown_text.SetAlpha, cooldown_text, 0)
			end
			return
		end
		if lorenzo_is_zero_text(value) then
			local cached = aura.lorenzo_known_long_buff and lorenzo_get_cached_known_long_buff_text(cooldown_text, aura) or nil
			if cached then
				pcall(cooldown_text.SetAlpha, cooldown_text, 1)
				set_cooldown_text(cooldown_text, cached)
			else
				set_cooldown_text(cooldown_text, "")
				pcall(cooldown_text.SetAlpha, cooldown_text, 0)
			end
			return
		end
		pcall(cooldown_text.SetAlpha, cooldown_text, 1)
		if aura.lorenzo_known_long_buff then
			lorenzo_store_cached_known_long_buff_text(cooldown_text, aura, value)
		end
	end
	set_cooldown_text(cooldown_text, value)
end

local function format_secret_duration_text(duration, aura)
	if not duration or not duration.FormatRemainingDuration then
		return nil
	end
	local formatter = get_duration_formatter()
	if not formatter then
		return nil
	end
	local ok, text
	if lorenzo_patch68_uses_modified_time(aura, duration) then
		ok, text = pcall(duration.FormatRemainingDuration, duration, formatter, LORENZO_PATCH68_BASE_TIME)
	else
		ok, text = pcall(duration.FormatRemainingDuration, duration, formatter)
	end
	if ok and text ~= nil then
		return text
	end
	return nil
end

local time_left_color_curve = C_CurveUtil.CreateColorCurve()
time_left_color_curve:AddPoint(0.1, CreateColor(1,0,0)) -- less than 10% so stay red.
time_left_color_curve:AddPoint(0.2, CreateColor(1,1,0)) -- fade from yellow to red between 20% left to 10% left
time_left_color_curve:AddPoint(0.3, CreateColor(0,1,0)) -- fade from green to yellow betwee 30% left to 20% left

local function format_time(seconds, threshold)
	threshold = threshold or 1.5
	if seconds >= 86400 * threshold then
		return DAY_ONELETTER_ABBR,floor(seconds/86400)
	elseif seconds >= 3600 * threshold then
		return HOUR_ONELETTER_ABBR,ceil(seconds/3600)
	elseif seconds >= 120 * threshold then
		return MINUTE_ONELETTER_ABBR,ceil(seconds/60)
	elseif seconds > 60 then
		seconds = ceil(seconds)
		return "%d:%02d",seconds/60,seconds%60
	elseif seconds < 3 then
		return "%.1f",seconds
	end
	return "%d",ceil(seconds)
end

-- Targeted per-player-aura display cache. During a Mythic+ transition Midnight
-- can hide name/spell/icon/expiration while keeping the auraInstanceID visible.
-- This cache is restricted to confirmed Potency/Timeways long-buffs only so
-- ordinary short buffs keep their normal secret-duration formatter path. This is
-- not Flask-specific and does not add Flask spell/name/icon recognition.
local lorenzo_player_aura_display_cache = {}
local LORENZO_PLAYER_AURA_DISPLAY_CACHE_TTL = 1800
local lorenzo_player_aura_cache_next_prune = 0
local lorenzo_known_long_buff_text_cache_next_prune = 0

local function lorenzo_prune_player_aura_display_cache(now)
	now = now or (GetTime and GetTime() or 0)
	if lorenzo_player_aura_cache_next_prune > now then
		return
	end
	lorenzo_player_aura_cache_next_prune = now + LORENZO_PATCH94_CACHE_PRUNE_INTERVAL
	for key, cached in pairs(lorenzo_player_aura_display_cache) do
		if not cached or not cached.expires or cached.expires <= now then
			lorenzo_player_aura_display_cache[key] = nil
		end
	end
end

lorenzo_prune_known_long_buff_text_cache = function(now)
	now = now or (GetTime and GetTime() or 0)
	if lorenzo_known_long_buff_text_cache_next_prune > now then
		return
	end
	lorenzo_known_long_buff_text_cache_next_prune = now + LORENZO_PATCH94_CACHE_PRUNE_INTERVAL
	-- The identity text cache is intentionally tiny, but remove orphaned explicit
	-- player-id entries if no matching player display cache exists anymore.
	for key in pairs(lorenzo_known_long_buff_text_cache) do
		if key:sub(1, 10) == "player-id:" and not lorenzo_player_aura_display_cache[key] then
			lorenzo_known_long_buff_text_cache[key] = nil
		end
	end
end

local function lorenzo_player_aura_cache_key(aura)
	if not lorenzo_cache_aura_is_player(aura) then
		return nil
	end
	local instance_id = lorenzo_safe_cache_part(aura.id)
	if instance_id then
		return "player-id:" .. instance_id
	end
	return nil
end

local function lorenzo_format_time_text(time_left)
	local fmt, a, b, c = format_time(time_left)
	local ok, text = pcall(string.format, fmt, a, b, c)
	if ok and text and not lorenzo_is_zero_text(text) then
		return text
	end
	return nil
end

local function lorenzo_cache_player_aura_display(aura, text, has_timer)
	local key = lorenzo_player_aura_cache_key(aura)
	if not key then
		return
	end
	local now = GetTime and GetTime() or 0
	lorenzo_prune_player_aura_display_cache(now)
	lorenzo_player_aura_display_cache[key] = {
		text = text or "",
		has_timer = has_timer and true or false,
		expires = now + LORENZO_PLAYER_AURA_DISPLAY_CACHE_TTL,
	}
end

-- Forward-declare this helper because Lua does not expose a later `local function`
-- declaration to earlier local functions.
local lorenzo_get_next_text_update_delay

local function lorenzo_get_current_safe_long_aura_remaining(aura, duration)
	-- Order-neutral fallback for ordinary long player buffs. This uses only the
	-- currently assigned aura's own expirationTime; it never reuses cached text
	-- across recycled aura buttons, so aura order/layout is not influenced.
	if not aura or aura.lorenzo_known_long_buff or aura.slot or not aura.is_buff then
		return nil
	end
	if not lorenzo_cache_aura_is_player(aura) then
		return nil
	end
	-- Patch 069: do not use the legacy expirationTime/timeMod shortcut for
	-- intentionally slowed or paused auras. This helper runs before the
	-- DurationObject path; dividing the wall-clock expiration delta by a tiny
	-- timeMod is what recreated multi-day text (for example 46m -> 4d) even
	-- after Patch 068 added the correct BaseTime DurationObject formatter.
	-- Let modified-time auras fall through to get_remaining_time(), which uses
	-- Blizzard's BaseTime path without inspecting protected duration payloads.
	if lorenzo_patch68_uses_modified_time(aura, duration) then
		return nil
	end
	local expiration_time = aura.expiration_time
	if expiration_time == nil or issecretvalue(expiration_time) or type(expiration_time) ~= "number" or expiration_time <= 0 then
		return nil
	end
	local now = GetTime and GetTime() or 0
	local time_left = expiration_time - now
	local time_mod = aura.time_mod or 1
	if time_mod ~= nil and not issecretvalue(time_mod) and type(time_mod) == "number" and time_mod > 0 then
		time_left = time_left / time_mod
	end
	if type(time_left) == "number" and time_left >= LORENZO_PATCH96_SAFE_LONG_AURA_MIN_SECONDS then
		return time_left
	end
	return nil
end

local function lorenzo_clear_safe_long_aura_hold(aura)
	if not aura then
		return
	end
	aura.lorenzo_safe_long_hold_id = nil
	aura.lorenzo_safe_long_hold_text = nil
	aura.lorenzo_safe_long_hold_until = nil
end

local function lorenzo_store_safe_long_aura_hold(aura, text)
	if not aura or not text or text == "" or lorenzo_is_zero_text(text) then
		return
	end
	local instance_id = lorenzo_safe_cache_part(aura.id)
	if not instance_id then
		return
	end
	aura.lorenzo_safe_long_hold_id = instance_id
	aura.lorenzo_safe_long_hold_text = text
	aura.lorenzo_safe_long_hold_until = (GetTime and GetTime() or 0) + LORENZO_PATCH100_LONG_AURA_HOLD_SECONDS
end

-- Generic, identity-keyed display cache for ordinary long player auras.
-- This is intentionally not a per-spell list: any helpful player aura that had a
-- safe numeric expirationTime and at least 60 seconds remaining can store its own
-- last display text under spell/name identity. If Midnight hides expirationTime
-- during combat and the secret DurationObject would otherwise show 0s, this lets
-- the same aura keep its last sane minute/hour text. We do not use the visible
-- PitBull button index and we avoid a generic auraInstanceID cache so recycled
-- buttons cannot pass Food/Flask/Sentinel timers to unrelated buffs.
local lorenzo_generic_long_aura_text_cache = {}
local lorenzo_generic_long_aura_next_prune = 0

local function lorenzo_get_generic_long_aura_cache_keys(aura)
	if not aura or aura.lorenzo_known_long_buff or aura.slot or not aura.is_buff then
		return nil
	end
	if not lorenzo_cache_aura_is_player(aura) then
		return nil
	end
	local keys = {}
	local spell_id = lorenzo_safe_cache_part(aura.spell_id)
	if spell_id then
		keys[#keys + 1] = "spell:" .. spell_id
	end
	local name = lorenzo_safe_cache_part(aura.name)
	if name then
		keys[#keys + 1] = "name:" .. name
	end
	-- Icon-only is deliberately a last-resort key and only used when no stronger
	-- identity is visible. This helps with some Midnight secret transitions while
	-- keeping collision risk low.
	if #keys == 0 then
		local icon = lorenzo_safe_cache_part(aura.icon)
		if icon then
			keys[#keys + 1] = "icon:" .. icon
		end
	end
	return #keys > 0 and keys or nil
end

local function lorenzo_prune_generic_long_aura_text_cache(now)
	now = now or (GetTime and GetTime() or 0)
	if lorenzo_generic_long_aura_next_prune > now then
		return
	end
	lorenzo_generic_long_aura_next_prune = now + LORENZO_PATCH104_GENERIC_LONG_AURA_CACHE_PRUNE_INTERVAL
	for key, cached in pairs(lorenzo_generic_long_aura_text_cache) do
		if not cached or not cached.expires or cached.expires <= now then
			lorenzo_generic_long_aura_text_cache[key] = nil
		end
	end
end

local function lorenzo_store_generic_long_aura_text(aura, text)
	if not text or text == "" or issecretvalue(text) or lorenzo_is_zero_text(text) then
		return
	end
	local keys = lorenzo_get_generic_long_aura_cache_keys(aura)
	if not keys then
		return
	end
	local now = GetTime and GetTime() or 0
	lorenzo_prune_generic_long_aura_text_cache(now)
	for i = 1, #keys do
		lorenzo_generic_long_aura_text_cache[keys[i]] = {
			text = text,
			expires = now + LORENZO_PATCH104_GENERIC_LONG_AURA_IDENTITY_TTL,
		}
	end
end

local function lorenzo_get_cached_generic_long_aura_text(aura)
	local keys = lorenzo_get_generic_long_aura_cache_keys(aura)
	if not keys then
		return nil
	end
	local now = GetTime and GetTime() or 0
	lorenzo_prune_generic_long_aura_text_cache(now)
	for i = 1, #keys do
		local cached = lorenzo_generic_long_aura_text_cache[keys[i]]
		if cached and cached.expires and cached.expires > now and cached.text and cached.text ~= "" and not lorenzo_is_zero_text(cached.text) then
			return cached.text
		end
	end
	return nil
end

local function lorenzo_apply_cached_generic_long_aura_text(aura)
	local cooldown_text = aura and aura.cooldown_text
	if not cooldown_text then
		return nil
	end
	-- If the current expirationTime is readable, the normal safe expiration path is
	-- the source of truth and will refresh the cache. Only use the cache while the
	-- current long aura timer data is hidden/incomplete.
	local expiration_time = aura.expiration_time
	if expiration_time ~= nil and not issecretvalue(expiration_time) and type(expiration_time) == "number" then
		return nil
	end
	local text = lorenzo_get_cached_generic_long_aura_text(aura)
	if not text then
		return nil
	end
	pcall(cooldown_text.SetAlpha, cooldown_text, 1)
	set_cooldown_text(cooldown_text, text)
	return 1
end

local function lorenzo_apply_safe_long_aura_hold(aura)
	local cooldown_text = aura and aura.cooldown_text
	if not cooldown_text then
		return nil
	end
	local held_text = aura.lorenzo_safe_long_hold_text
	local held_id = aura.lorenzo_safe_long_hold_id
	local held_until = aura.lorenzo_safe_long_hold_until
	if not held_text or not held_id or not held_until then
		return nil
	end
	local now = GetTime and GetTime() or 0
	if held_until <= now then
		lorenzo_clear_safe_long_aura_hold(aura)
		return nil
	end
	local current_id = lorenzo_safe_cache_part(aura.id)
	if not current_id or current_id ~= held_id then
		lorenzo_clear_safe_long_aura_hold(aura)
		return nil
	end
	-- Only hold ordinary long player auras while the current expirationTime is not
	-- safely readable. If it is readable, the normal expirationTime path below will
	-- recompute the display text and refresh this short hold.
	local expiration_time = aura.expiration_time
	if expiration_time ~= nil and not issecretvalue(expiration_time) and type(expiration_time) == "number" then
		return nil
	end
	pcall(cooldown_text.SetAlpha, cooldown_text, 1)
	set_cooldown_text(cooldown_text, held_text)
	return 0.5
end

local function lorenzo_apply_current_safe_long_aura_expiration_text(aura, duration)
	local cooldown_text = aura and aura.cooldown_text
	if not cooldown_text then
		return nil
	end
	local time_left = lorenzo_get_current_safe_long_aura_remaining(aura, duration)
	if not time_left then
		return lorenzo_apply_safe_long_aura_hold(aura)
	end
	pcall(cooldown_text.SetAlpha, cooldown_text, 1)
	local fmt, a, b, c = format_time(time_left)
	local ok_text, text = pcall(string.format, fmt, a, b, c)
	if ok_text then
		set_cooldown_text(cooldown_text, text)
		lorenzo_store_safe_long_aura_hold(aura, text)
		lorenzo_store_generic_long_aura_text(aura, text)
	else
		cooldown_text:SetFormattedText(format_time(time_left))
		lorenzo_clear_safe_long_aura_hold(aura)
	end
	return lorenzo_get_next_text_update_delay(time_left)
end

function PitBull4_Aura:LorenzoPatch90RememberPlayerAuraDisplay(aura)
	-- Keep the player auraInstanceID display cache functional only for confirmed
	-- Potency/Timeways long-buffs. Ordinary long buffs such as food/flask are
	-- handled order-neutrally from the current aura expirationTime in the text
	-- updater, not by a reusable auraInstanceID display cache.
	if not aura or not aura.lorenzo_known_long_buff then
		return
	end
	local key = lorenzo_player_aura_cache_key(aura)
	if not key then
		return
	end
	local expiration_time = aura.expiration_time
	if issecretvalue(expiration_time) or expiration_time == nil or type(expiration_time) ~= "number" then
		-- Do not inspect DurationObject:IsZero() here. In Midnight, IsZero() can
		-- return a secret boolean and comparing that value taints/errors. Keep the
		-- last identity-keyed display cache instead of overwriting it from secret aura
		-- data during Mythic+ entry/rebuilds.
		return
	end
	if expiration_time <= 0 then
		lorenzo_cache_player_aura_display(aura, "", false)
		return
	end
	local time_left = expiration_time - (GetTime and GetTime() or 0)
	local time_mod = aura.time_mod or 1
	if time_mod ~= nil and not issecretvalue(time_mod) and type(time_mod) == "number" and time_mod > 0 then
		time_left = time_left / time_mod
	end
	if type(time_left) ~= "number" or time_left <= 0 then
		lorenzo_cache_player_aura_display(aura, "", false)
		return
	end
	local text = lorenzo_format_time_text(time_left)
	if text then
		lorenzo_cache_player_aura_display(aura, text, true)
	end
end

local function lorenzo_get_cached_player_aura_display(aura)
	local key = lorenzo_player_aura_cache_key(aura)
	if not key then
		return nil
	end
	local cached = lorenzo_player_aura_display_cache[key]
	if not cached then
		return nil
	end
	local now = GetTime and GetTime() or 0
	lorenzo_prune_player_aura_display_cache(now)
	lorenzo_prune_known_long_buff_text_cache(now)
	if cached.expires and cached.expires <= now then
		lorenzo_player_aura_display_cache[key] = nil
		return nil
	end
	return cached.text or "", cached.has_timer and true or false
end

local function lorenzo_apply_cached_player_aura_display(aura)
	if not aura or not aura.cooldown_text or not aura.lorenzo_secret_player_helpful_identity then
		return nil
	end
	-- Do not apply the cached player-aura blank/text state to ordinary short buffs.
	-- Only the targeted known long-buff path needs this cache when Midnight hides
	-- name/spell/icon/expiration during M+ entry.
	if not aura.lorenzo_known_long_buff then
		return nil
	end
	local text, has_timer = lorenzo_get_cached_player_aura_display(aura)
	if text == nil then
		return nil
	end
	if has_timer and text ~= "" and not lorenzo_is_zero_text(text) then
		pcall(aura.cooldown_text.SetAlpha, aura.cooldown_text, 1)
		set_cooldown_text(aura.cooldown_text, text)
		return 5
	end
	set_cooldown_text(aura.cooldown_text, "")
	pcall(aura.cooldown_text.SetAlpha, aura.cooldown_text, 0)
	return 5
end

-- Potency/Timeways can expose a valid expirationTime while the Midnight
-- DurationObject reports remaining=0 during key transitions. For the targeted
-- known long-buffs, prefer expirationTime-based text whenever it is safe and
-- positive so the DurationObject cannot reintroduce 0s for Blessing of Potency.
local function lorenzo_get_safe_expiration_remaining(aura)
	if not aura or not aura.lorenzo_known_long_buff then
		return nil
	end
	local expiration_time = aura.expiration_time
	if expiration_time == nil or issecretvalue(expiration_time) or type(expiration_time) ~= "number" or expiration_time <= 0 then
		return nil
	end
	local now = GetTime and GetTime() or 0
	local time_left = expiration_time - now
	local time_mod = aura.time_mod or 1
	if time_mod ~= nil and not issecretvalue(time_mod) and type(time_mod) == "number" and time_mod > 0 then
		time_left = time_left / time_mod
	end
	if type(time_left) == "number" and time_left > 0 then
		return time_left
	end
	return nil
end

function lorenzo_get_next_text_update_delay(time_left)
	if time_left >= 3600 then
		return 30
	elseif time_left >= 180 then
		return 1
	elseif time_left >= 60 then
		return 0.5
	elseif time_left < 3 then
		-- Avoid a zero-delay OnUpdate loop for sub-3-second auras. 10 updates/second
		-- keeps decimal short-buff text responsive while reducing CPU churn in heavy
		-- combat frames.
		return LORENZO_PATCH94_MIN_TEXT_UPDATE_DELAY
	end
	return 0.25
end

local function lorenzo_apply_known_long_buff_expiration_text(aura)
	local cooldown_text = aura and aura.cooldown_text
	if not cooldown_text then
		return nil
	end
	local time_left = lorenzo_get_safe_expiration_remaining(aura)
	if not time_left then
		-- When the key instance secrets expirationTime as well, use the player
		-- auraInstanceID cache filled while the buff was visible outside the key. This
		-- keeps the fix narrow to auras already marked as known long-buffs.
		local cached = lorenzo_get_cached_known_long_buff_text(cooldown_text, aura)
		if cached then
			pcall(cooldown_text.SetAlpha, cooldown_text, 1)
			set_cooldown_text(cooldown_text, cached)
			return 1
		end
		return nil
	end
	pcall(cooldown_text.SetAlpha, cooldown_text, 1)
	local fmt, a, b, c = format_time(time_left)
	local ok_text, text = pcall(string.format, fmt, a, b, c)
	if ok_text then
		set_known_long_buff_text(cooldown_text, aura, text)
	else
		cooldown_text:SetFormattedText(format_time(time_left))
	end
	return lorenzo_get_next_text_update_delay(time_left)
end

function PitBull4_Aura:LorenzoPatch87PrimeKnownLongBuffText(aura)
	return lorenzo_apply_known_long_buff_expiration_text(aura) and true or false
end

local function refresh_aura_duration(aura)
	-- DurationObjects can go stale when Midnight only sends a partial UNIT_AURA
	-- update. Keep the re-read fallback, but throttle it per aura so every visible
	-- short buff is not calling C_UnitAuras.GetAuraDuration on every text tick.
	-- UNIT_AURA/set-aura still refreshes duration immediately.
	if aura.unit and aura.id and GetAuraDuration then
		local now = GetTime and GetTime() or 0
		if aura.duration and aura.lorenzo_next_duration_refresh and aura.lorenzo_next_duration_refresh > now then
			return aura.duration
		end
		aura.lorenzo_next_duration_refresh = now + LORENZO_PATCH94_DURATION_REFRESH_INTERVAL
		local ok, duration = pcall(GetAuraDuration, aura.unit, aura.id)
		if ok and duration then
			aura.duration = duration
		end
	end
	return aura.duration
end

local function get_remaining_time(aura, duration)
	-- Patch 068: when a public AuraData.timeMod indicates a slowed/paused aura,
	-- prefer DurationObject BaseTime. RealTime intentionally expands the
	-- remaining wall-clock duration and is what produced displays such as 5d for
	-- a paused 60m food/flask buff. BaseTime matches the aura's displayed
	-- remaining duration without inspecting protected duration values in Lua.
	if lorenzo_patch68_uses_modified_time(aura, duration) and duration and duration.GetRemainingDuration then
		local ok, time_left = pcall(duration.GetRemainingDuration, duration, LORENZO_PATCH68_BASE_TIME)
		if ok then
			if issecretvalue(time_left) then
				return time_left
			end
			if time_left ~= nil then
				return time_left
			end
		end
	end

	-- Many permanent/no-duration buffs have a normal expiration_time=0 but a
	-- Midnight DurationObject can still format as "0s". Check the safe payload
	-- first so these auras produce an empty timer instead of visible 0s.
	local expiration_time = aura.expiration_time
	local time_mod = aura.time_mod or 1
	if expiration_time ~= nil and not issecretvalue(expiration_time) and type(expiration_time) == "number" then
		if expiration_time == 0 then
			return 0
		end
		if time_mod ~= nil and not issecretvalue(time_mod) and type(time_mod) == "number" then
			local time_left = expiration_time - GetTime()
			if time_mod > 0 then
				time_left = time_left / time_mod
			end
			return time_left
		end
	end

	if duration and duration.GetRemainingDuration then
		local ok, time_left = pcall(duration.GetRemainingDuration, duration)
		if ok then
			-- Secret remaining values are valid input for Blizzard's secret-safe
			-- formatter below; do not discard them here or short auras can end up with
			-- no seconds shown.
			if issecretvalue(time_left) then
				return time_left
			end
			if time_left ~= nil then
				return time_left
			end
		end
	end

	return nil
end

local function update_cooldown_text(aura)
	local cooldown_text = aura.cooldown_text
	if not cooldown_text or not cooldown_text.IsShown or not cooldown_text:IsShown() then return end
	local duration = refresh_aura_duration(aura)

	local lorenzo_cached_player_delay = lorenzo_apply_cached_player_aura_display(aura)
	if lorenzo_cached_player_delay then
		return lorenzo_cached_player_delay
	end

	if duration and cooldown_text.color_by_time and duration.EvaluateRemainingPercent then
		local ok, color = pcall(duration.EvaluateRemainingPercent, duration, time_left_color_curve)
		if ok and color then
			cooldown_text:SetTextColor(color:GetRGB())
		end
	end

	local lorenzo_expiration_delay = lorenzo_apply_known_long_buff_expiration_text(aura)
	if lorenzo_expiration_delay then
		return lorenzo_expiration_delay
	end

	-- Hide zero-duration/permanent aura timers using Blizzard's secret-safe UI
	-- path. Do not negate or compare the boolean returned by IsZero(), because in
	-- Midnight that boolean can itself be secret.
	if duration and duration.IsZero and cooldown_text.SetAlphaFromBoolean then
		local ok_zero, is_zero = pcall(duration.IsZero, duration)
		if ok_zero then
			-- Do not compare is_zero with true/false/nil. Midnight can mark the
			-- boolean as secret; passing it directly into Blizzard's secret-aware
			-- SetAlphaFromBoolean path is safe, but Lua comparisons are not.
			pcall(cooldown_text.SetAlphaFromBoolean, cooldown_text, is_zero, 0, 1)
		else
			pcall(cooldown_text.SetAlpha, cooldown_text, 1)
		end
	else
		pcall(cooldown_text.SetAlpha, cooldown_text, 1)
	end

	local lorenzo_current_safe_long_delay = lorenzo_apply_current_safe_long_aura_expiration_text(aura, duration)
	if lorenzo_current_safe_long_delay then
		return lorenzo_current_safe_long_delay
	end

	local lorenzo_generic_long_cache_delay = lorenzo_apply_cached_generic_long_aura_text(aura)
	if lorenzo_generic_long_cache_delay then
		return lorenzo_generic_long_cache_delay
	end

	local time_left = get_remaining_time(aura, duration)
	-- Check the secret case before nil/zero comparisons. Short aura durations
	-- inside keys can be secret values, and the stable formatter path handles them
	-- through Blizzard's secret-safe formatter instead of blanking them.
	if issecretvalue(time_left) then
		local text = format_secret_duration_text(duration, aura)
		if text ~= nil then
			set_known_long_buff_text(cooldown_text, aura, text)
		else
			set_known_long_buff_text(cooldown_text, aura, C_StringUtil.TruncateWhenZero(time_left)) -- Secret-safe Blizzard formatter.
		end
		return 1
	end
	if time_left == nil then
		if aura.lorenzo_known_long_buff or aura.lorenzo_long_buff_zero_guard then
			-- If Midnight gives no reliable timer during key start/re-entry, do not
			-- leave a recycled 0s text on this known long-buff FontString.
			set_known_long_buff_text(cooldown_text, aura, 0)
			return 0.5
		end
		return
	end
	if time_left == 0 then
		if aura.lorenzo_known_long_buff or aura.lorenzo_long_buff_zero_guard then
			set_known_long_buff_text(cooldown_text, aura, 0)
			return 0.5
		end
		set_cooldown_text(cooldown_text, "")
		return 10
	elseif type(time_left) == "number" and time_left >= 0 then
		local fmt, a, b, c = format_time(time_left)
		local ok_text, text = pcall(string.format, fmt, a, b, c)
		if ok_text then
			set_known_long_buff_text(cooldown_text, aura, text)
		else
			cooldown_text:SetFormattedText(format_time(time_left))
		end
		return lorenzo_get_next_text_update_delay(time_left)
	end
end

function PitBull4_Aura:EnableCooldownText(aura)
	local cooldown_text = aura.cooldown_text
	if not cooldown_text then return end
	cooldown_text:Show()
	cooldown_texts[aura] = 0
	next_text_update = 0
	timerFrame:Show()
end

function PitBull4_Aura:DisableCooldownText(aura)
	-- Aura controls can disappear from a recycled controls array while an aura
	-- update is still cleaning up the remaining slots. Treat that as already
	-- disabled instead of indexing a nil control.
	if not aura then
		return
	end

	local cooldown_text = aura.cooldown_text
	if cooldown_text then
		-- A newly-created or freshly-reset pooled FontString may not have a font yet.
		-- Calling SetText on such a FontString raises "Font not set". Hiding is
		-- sufficient here; the normal enable path configures the font and clears or
		-- replaces the text before showing it again.
		cooldown_text:Hide()
	end
	cooldown_texts[aura] = nil

	-- Disabling the duration text must not erase the identity of a still-visible
	-- aura button. Tooltips, right-click cancellation and debug inspection still
	-- need unit/auraInstanceID/name data even when duration text is disabled.
	aura.lorenzo_next_duration_refresh = nil
	lorenzo_clear_safe_long_aura_hold(aura)
	if cooldown_text then
		cooldown_text.lorenzo_last_known_long_text = nil
		cooldown_text.lorenzo_last_known_long_key = nil
	end
end

function PitBull4_Aura:ClearAuraControlData(aura)
	aura.unit = nil
	aura.index = nil
	aura.id = nil
	aura.duration = nil
	aura.expiration_time = nil
	aura.time_mod = nil
	aura.name = nil
	aura.icon = nil
	aura.spell_id = nil
	aura.is_mine = nil
	aura.is_buff = nil
	aura.is_config_sample = nil
	aura.lorenzo_known_long_buff = nil
	aura.lorenzo_long_buff_zero_guard = nil
	aura.lorenzo_secret_player_helpful_identity = nil
	aura.lorenzo_next_duration_refresh = nil
	lorenzo_clear_safe_long_aura_hold(aura)
	aura.slot = nil
end

function PitBull4_Aura:UpdateCooldownTexts(elapsed)
	local min_time
	for aura, time in pairs(cooldown_texts) do
		time = (time or 0) - elapsed
		if time <= 0 then
			time = update_cooldown_text(aura,elapsed)
		end
		time = time or 0.25
		if time <= 0 then
			time = LORENZO_PATCH94_MIN_TEXT_UPDATE_DELAY
		end
		cooldown_texts[aura] = time
		if not min_time or time < min_time then
			min_time = time
		end
	end
	return min_time
end
