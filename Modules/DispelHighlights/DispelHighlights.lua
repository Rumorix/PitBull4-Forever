-- PitBull4 12.1 protected dispel highlighting.
--
-- This module deliberately does not inspect aura data in addon Lua. Blizzard's
-- AuraContainer selects the aura and AuraButton:AddDispelTypeTexture owns the
-- dispel-type presentation, including its protected/secret state. PitBull only
-- supplies layout choices and a safe filter string.

local _G = _G
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local DispelHighlights = PitBull4:NewModule("DispelHighlights")

local type = type
local tostring = tostring
local tonumber = tonumber
local pcall = pcall
local pairs = pairs
local setmetatable = setmetatable

local SLOT_KEY = "pitbull-dispel-highlight"
local FRAME_LEVEL_OFFSET = 16 -- border/tint layer: below PitBull text overlay (+17), above bars
local WHITE_TEXTURE = [[Interface\Buttons\WHITE8X8]]

local STYLE = _G.Enum and _G.Enum.CustomAuraButtonDispelTypeTextureStyle
local STYLE_ICON = STYLE and STYLE.Icon or 2
local STYLE_PRESERVE_ASSET = STYLE and STYLE.PreserveAsset or 3

local ICON_ANCHORS = {
	TOPLEFT = "TOPLEFT", TOP = "TOP", TOPRIGHT = "TOPRIGHT",
	LEFT = "LEFT", CENTER = "CENTER", RIGHT = "RIGHT",
	BOTTOMLEFT = "BOTTOMLEFT", BOTTOM = "BOTTOM", BOTTOMRIGHT = "BOTTOMRIGHT",
}

local RELATION_VALUES = {
	FRIENDLY = "Friendly only",
	HOSTILE = "Hostile only",
	BOTH = "Friendly and hostile",
}

local active_states = setmetatable({}, { __mode = "k" })
local retired_states = setmetatable({}, { __mode = "k" })
local failed_frames = setmetatable({}, { __mode = "k" })

DispelHighlights:SetModuleType("custom")
DispelHighlights:SetName(L["Dispel highlights"])
DispelHighlights:SetDescription(L["Highlight unit frames with Blizzard's dispel colors and dispel-type border/icon."])
DispelHighlights:SetDefaults({
	enabled = false,
	only_dispellable_by_me = true,
	show_tint = true,
	tint_alpha = 0.18,
	show_border_icon = true,
	border_alpha = 0.90,
	border_size = 1,
	icon_size = 14,
	icon_anchor = "TOPRIGHT",
	icon_x = -3,
	icon_y = -3,
	icon_level_offset = 28,
	relation = "FRIENDLY",
})

local function in_combat_lockdown()
	return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() or false
end

local function get_unit_token(frame)
	if frame and type(frame.unit) == "string" and frame.unit ~= "" then
		return frame.unit
	end
	return "none"
end

local function get_filter(db)
	-- In 12.1 HARMFUL|RAID means harmful auras the local player can dispel.
	-- HARMFUL|DISPELLABLE means harmful auras with any dispel type, regardless
	-- of whether the local player currently has a matching dispel.
	if db.only_dispellable_by_me then
		return "HARMFUL|RAID"
	end
	return "HARMFUL|DISPELLABLE"
end

local function get_signature(db)
	return table.concat({
		tostring(db.only_dispellable_by_me and true or false),
		tostring(db.show_tint and true or false),
		tostring(tonumber(db.tint_alpha) or 0.18),
		tostring(db.show_border_icon and true or false),
		tostring(tonumber(db.border_alpha) or 0.90),
		tostring(tonumber(db.border_size) or 1),
		tostring(tonumber(db.icon_size) or 14),
		tostring(db.icon_anchor or "TOPRIGHT"),
		tostring(tonumber(db.icon_x) or -3),
		tostring(tonumber(db.icon_y) or -3),
		tostring(tonumber(db.icon_level_offset) or 28),
		tostring(db.relation or "FRIENDLY"),
	}, ":")
end

local function apply_relation_visibility(state, frame, db)
	if not state or not state.holder then return end
	local relation = db.relation or "FRIENDLY"
	if relation == "BOTH" then
		state.holder:SetAlpha(1)
		return
	end

	local unit = get_unit_token(frame)
	local predicate
	if relation == "HOSTILE" and type(_G.UnitCanAttack) == "function" then
		local ok, value = pcall(_G.UnitCanAttack, "player", unit)
		if ok then predicate = value end
	elseif relation == "FRIENDLY" and type(_G.UnitCanAssist) == "function" then
		local ok, value = pcall(_G.UnitCanAssist, "player", unit)
		if ok then predicate = value end
	end

	if predicate == nil then
		state.holder:SetAlpha(0)
		return
	end

	-- UnitCanAssist/UnitCanAttack may be protected in 12.1. Forward the
	-- predicate directly to Blizzard's boolean-alpha sink instead of branching.
	if type(state.holder.SetAlphaFromBoolean) == "function" then
		local ok = pcall(state.holder.SetAlphaFromBoolean, state.holder, predicate, 1, 0)
		if ok then return end
	end

	-- Public fallback only. Never branch on a secret relationship predicate.
	if not issecretvalue(predicate) then
		state.holder:SetAlpha(predicate and 1 or 0)
	else
		state.holder:SetAlpha(0)
	end
end

local function hide_state(state)
	if not state then return end
	if state.container then
		pcall(state.container.SetEnabled, state.container, false)
		pcall(state.container.Hide, state.container)
	end
	if state.holder then
		pcall(state.holder.Hide, state.holder)
	end
end

local function show_state(state, frame, db)
	if not state or not state.container then return end
	local unit = get_unit_token(frame)
	if state.unit ~= unit then
		state.unit = unit
		state.container:SetUnit(unit)
	end
	state.container:SetEnabled(true)
	state.container:Show()
	state.holder:Show()
	apply_relation_visibility(state, frame, db)
end

local function retire_state(frame, state)
	if not state then return end
	hide_state(state)
	local list = retired_states[frame]
	if not list then
		list = {}
		retired_states[frame] = list
	end
	list[#list + 1] = state
end

local function acquire_retired_state(frame, signature)
	local list = retired_states[frame]
	if not list then return nil end
	for i = #list, 1, -1 do
		local state = list[i]
		if state.signature == signature then
			table.remove(list, i)
			return state
		end
	end
	return nil
end

local function initialize_button(button, owner_frame, db)
	button:EnableMouse(false)
	button:SetAllPoints(owner_frame)
	button:SetFrameLevel((owner_frame:GetFrameLevel() or 1) + FRAME_LEVEL_OFFSET)
	button:SetCancelAuraButtons(nil)

	-- Keep the actual aura icon invisible. The protected AuraButton only carries
	-- Blizzard's dispel-type state into render sinks; PitBull never reads it.
	local hidden_icon = button:CreateTexture(nil, "BACKGROUND")
	hidden_icon:SetAllPoints(button)
	hidden_icon:SetTexture(WHITE_TEXTURE)
	hidden_icon:SetAlpha(0)
	button:SetIcon(hidden_icon)

	if db.show_tint then
		-- Patch 065: put opacity on a parent frame. AddDispelTypeTexture owns the
		-- child texture's protected presentation and may update its alpha itself;
		-- parent alpha remains an ordinary PitBull layout choice and reliably
		-- keeps the full-frame tint subtle.
		local tint_holder = _G.CreateFrame("Frame", nil, button)
		tint_holder:SetAllPoints(owner_frame)
		tint_holder:SetAlpha(math.max(0, math.min(1, tonumber(db.tint_alpha) or 0.18)))
		local tint = tint_holder:CreateTexture(nil, "ARTWORK", nil, 1)
		tint:SetAllPoints(tint_holder)
		tint:SetTexture(WHITE_TEXTURE)
		button:AddDispelTypeTexture(tint, {
			showAlways = false,
			showWhenHarmful = true,
			showWhenHelpful = false,
			showWithoutDispelType = false,
			style = STYLE_PRESERVE_ASSET,
		})
		button.PitBull4DispelTintHolder = tint_holder
		button.PitBull4DispelTint = tint
	end

	if db.show_border_icon then
		-- BorderWithIcon is a square AuraButton asset. Stretching it over a wide
		-- unit frame produced the large neon blocks seen in P064. Build a proper
		-- rectangular PitBull border from four plain textures instead and let
		-- Blizzard color each texture from the protected dispel type.
		local border_holder = _G.CreateFrame("Frame", nil, button)
		border_holder:SetAllPoints(owner_frame)
		border_holder:SetAlpha(math.max(0, math.min(1, tonumber(db.border_alpha) or 0.90)))
		local thickness = math.max(1, math.min(6, tonumber(db.border_size) or 1))

		local top = border_holder:CreateTexture(nil, "OVERLAY", nil, 5)
		top:SetTexture(WHITE_TEXTURE); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(thickness)
		local bottom = border_holder:CreateTexture(nil, "OVERLAY", nil, 5)
		bottom:SetTexture(WHITE_TEXTURE); bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(thickness)
		local left = border_holder:CreateTexture(nil, "OVERLAY", nil, 5)
		left:SetTexture(WHITE_TEXTURE); left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(thickness)
		local right = border_holder:CreateTexture(nil, "OVERLAY", nil, 5)
		right:SetTexture(WHITE_TEXTURE); right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(thickness)

		for _, edge in ipairs({top, bottom, left, right}) do
			button:AddDispelTypeTexture(edge, {
				showAlways = false, showWhenHarmful = true, showWhenHelpful = false,
				showWithoutDispelType = false, style = STYLE_PRESERVE_ASSET,
			})
		end

		-- Keep Blizzard's own dispel-type icon, but constrain it to a small square
		-- in the top-right corner instead of stretching BorderWithIcon over the frame.
		local icon_size = math.max(8, math.min(32, tonumber(db.icon_size) or 14))
		local icon_anchor = ICON_ANCHORS[db.icon_anchor] and db.icon_anchor or "TOPRIGHT"
		local icon_x = math.max(-100, math.min(100, tonumber(db.icon_x) or -3))
		local icon_y = math.max(-100, math.min(100, tonumber(db.icon_y) or -3))
		local icon_level_offset = math.max(1, math.min(80, tonumber(db.icon_level_offset) or 28))

		-- Patch 066: the icon owns a separate high-frame-level parent so it can
		-- sit above PitBull LuaTexts instead of being covered by the text overlay.
		local icon_holder = _G.CreateFrame("Frame", nil, button)
		icon_holder:SetSize(icon_size, icon_size)
		icon_holder:SetPoint(icon_anchor, owner_frame, icon_anchor, icon_x, icon_y)
		icon_holder:SetFrameLevel((owner_frame:GetFrameLevel() or 1) + icon_level_offset)
		local dispel_icon = icon_holder:CreateTexture(nil, "OVERLAY", nil, 7)
		dispel_icon:SetAllPoints(icon_holder)
		button:AddDispelTypeTexture(dispel_icon, {
			showAlways = false,
			showWhenHarmful = true,
			showWhenHelpful = false,
			showWithoutDispelType = false,
			style = STYLE_ICON,
		})
		button.PitBull4DispelBorderHolder = border_holder
		button.PitBull4DispelBorder = {top, bottom, left, right}
		button.PitBull4DispelIconHolder = icon_holder
		button.PitBull4DispelIcon = dispel_icon
	end
end

local function create_state(frame, db, signature)
	if type(_G.CreateFrame) ~= "function" then
		error("CreateFrame is unavailable", 0)
	end

	local holder = _G.CreateFrame("Frame", nil, frame)
	holder:SetAllPoints(frame)
	holder:SetFrameLevel((frame:GetFrameLevel() or 1) + FRAME_LEVEL_OFFSET)
	holder:Hide()

	local container = _G.CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
	container:SetPoint("CENTER", frame, "CENTER", 0, 0)
	container:SetSize(1, 1)
	container:SetFrameLevel(holder:GetFrameLevel())
	container:Hide()

	if type(container.AddAuraSlot) ~= "function" then
		error("AuraContainer:AddAuraSlot is unavailable", 0)
	end

	local filter = get_filter(db)
	container:AddAuraSlot(SLOT_KEY, filter, {
		initializeFrame = function(button)
			initialize_button(button, frame, db)
		end,
		sortMethod = (_G.AuraContainerSortMethod and (_G.AuraContainerSortMethod.ImportantOnly or _G.AuraContainerSortMethod.ExpirationOnly)) or 0,
		sortDirection = (_G.AuraContainerSortDirection and _G.AuraContainerSortDirection.Normal) or 0,
	})

	local unit = get_unit_token(frame)
	container:SetUnit(unit)
	container:SetEnabled(true)
	container:Show()
	holder:Show()

	return {
		holder = holder,
		container = container,
		signature = signature,
		unit = unit,
		filter = filter,
	}
end

local function refresh_dynamic_containers()
	for frame, state in pairs(active_states) do
		if frame and state and state.container then
			local unit = get_unit_token(frame)
			if unit == "target" or unit == "focus" or unit == "targettarget" or unit == "focustarget" then
				local ok, method = pcall(function() return state.container.UpdateAllAuras end)
				if ok and type(method) == "function" then
					pcall(method, state.container)
				end
			end
		end
	end
end

function DispelHighlights:OnEnable()
	if _G.C_AddOns and type(_G.C_AddOns.LoadAddOn) == "function" then
		pcall(_G.C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	elseif type(_G.LoadAddOn) == "function" then
		pcall(_G.LoadAddOn, "Blizzard_AuraContainer")
	end
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "UpdateAll")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", refresh_dynamic_containers)
	self:RegisterEvent("PLAYER_FOCUS_CHANGED", refresh_dynamic_containers)
	self:RegisterEvent("UNIT_TARGET", refresh_dynamic_containers)
	self:RegisterEvent("UNIT_FACTION", "UpdateAll")
end

function DispelHighlights:OnDisable()
	for frame, state in pairs(active_states) do
		retire_state(frame, state)
	end
	active_states = setmetatable({}, { __mode = "k" })
end

function DispelHighlights:PLAYER_ENTERING_WORLD()
	failed_frames = setmetatable({}, { __mode = "k" })
	self:UpdateAll()
end

function DispelHighlights:ADDON_LOADED(_, addon_name)
	if addon_name == "Blizzard_AuraContainer" then
		failed_frames = setmetatable({}, { __mode = "k" })
		self:UpdateAll()
	end
end

function DispelHighlights:UpdateFrame(frame)
	local db = self:GetLayoutDB(frame)
	if not db.show_tint and not db.show_border_icon then
		return self:ClearFrame(frame)
	end

	local signature = get_signature(db)
	local state = active_states[frame]
	if state and state.signature ~= signature then
		retire_state(frame, state)
		active_states[frame] = nil
		state = nil
	end

	if not state then
		state = acquire_retired_state(frame, signature)
	end

	if not state then
		-- AuraButton creation/configuration must happen before Blizzard applies
		-- forbidden aspects. Avoid creating replacement protected surfaces while
		-- combat lockdown is already active; PLAYER_REGEN_ENABLED retries it.
		if in_combat_lockdown() then
			return false
		end
		local failure = failed_frames[frame]
		if failure and failure.signature == signature then
			return false
		end
		local ok, result = pcall(create_state, frame, db, signature)
		if not ok then
			failed_frames[frame] = { signature = signature, error = tostring(result) }
			return false
		end
		state = result
		failed_frames[frame] = nil
	end

	active_states[frame] = state
	local ok, err = pcall(show_state, state, frame, db)
	if not ok then
		hide_state(state)
		failed_frames[frame] = { signature = signature, error = tostring(err) }
	end
	return false
end

function DispelHighlights:ClearFrame(frame)
	local state = active_states[frame]
	if state then
		hide_state(state)
	end
	return false
end

function DispelHighlights:OnHide(frame)
	local state = active_states[frame]
	if state then
		hide_state(state)
	end
end

function DispelHighlights:Lorenzo121StatusLine()
	local configured = 0
	local failures = 0
	for _ in pairs(active_states) do configured = configured + 1 end
	for _ in pairs(failed_frames) do failures = failures + 1 end
	return "12.1 dispelHighlights protected=yes configured=" .. configured .. " failures=" .. failures .. " auraDataReadByAddon=no filter=HARMFUL|RAID-or-DISPELLABLE relation=UnitCanAssist/UnitCanAttack->SetAlphaFromBoolean tint=parent-alpha+PreserveAsset border=rect-PreserveAsset icon=Blizzard-Icon movable=yes iconLevel=configurable borderLevelOffset=" .. FRAME_LEVEL_OFFSET
end

DispelHighlights:SetLayoutOptionsFunction(function(self)
	local function get(info)
		return PitBull4.Options.GetLayoutDB(self)[info[#info]]
	end
	local function set(info, value)
		PitBull4.Options.GetLayoutDB(self)[info[#info]] = value
		PitBull4.Options.UpdateFrames()
	end
	local function disabled()
		return not PitBull4.Options.GetLayoutDB(self).enabled
	end
	local function tint_disabled()
		local db = PitBull4.Options.GetLayoutDB(self)
		return not db.enabled or not db.show_tint
	end
	local function border_disabled()
		local db = PitBull4.Options.GetLayoutDB(self)
		return not db.enabled or not db.show_border_icon
	end

	return
	'info', {
		type = 'description',
		name = L["Uses Blizzard's protected 12.1 AuraContainer and dispel-type rendering. PitBull never reads the protected aura or dispel type itself."],
		width = 'full', order = 1,
	},
	'only_dispellable_by_me', {
		type = 'toggle',
		name = L["Only debuffs I can dispel"],
		desc = L["Highlight only harmful auras Blizzard reports as dispellable by your current character. Disable this to highlight any harmful aura with a dispel type."],
		get = get, set = set, disabled = disabled, width = 'full', order = 2,
	},
	'relation', {
		type = 'select',
		name = L["Unit relationship"],
		desc = L["Choose whether dispel highlights are shown on friendly units, hostile units, or both."],
		values = { FRIENDLY = L["Friendly only"], HOSTILE = L["Hostile only"], BOTH = L["Friendly and hostile"] },
		get = get, set = set, disabled = disabled, order = 3,
	},
	'show_tint', {
		type = 'toggle',
		name = L["Tint frame with dispel color"],
		desc = L["Apply a subtle full-frame tint using Blizzard's dispel color for the selected debuff."],
		get = get, set = set, disabled = disabled, width = 'full', order = 4,
	},
	'tint_alpha', {
		type = 'range',
		name = L["Tint opacity"],
		desc = L["Set the opacity of the full-frame dispel color tint."],
		min = 0.05, max = 0.80, step = 0.01, isPercent = true,
		get = get, set = set, disabled = tint_disabled, order = 5,
	},
	'show_border_icon', {
		type = 'toggle',
		name = L["Dispel border and icon"],
		desc = L["Show a rectangular frame border colored by Blizzard's dispel type plus Blizzard's matching corner icon."],
		get = get, set = set, disabled = disabled, width = 'full', order = 6,
	},
	'border_alpha', {
		type = 'range', name = L["Border opacity"],
		min = 0.10, max = 1.00, step = 0.05, isPercent = true,
		get = get, set = set, disabled = border_disabled, order = 7,
	},
	'border_size', {
		type = 'range', name = L["Border thickness"],
		min = 1, max = 6, step = 1,
		get = get, set = set, disabled = border_disabled, order = 8,
	},
	'icon_size', {
		type = 'range', name = L["Dispel icon size"],
		min = 8, max = 32, step = 1,
		get = get, set = set, disabled = border_disabled, order = 9,
	},
	'icon_anchor', {
		type = 'select', name = L["Dispel icon anchor"],
		values = { TOPLEFT = L["Top left"], TOP = L["Top"], TOPRIGHT = L["Top right"], LEFT = L["Left"], CENTER = L["Center"], RIGHT = L["Right"], BOTTOMLEFT = L["Bottom left"], BOTTOM = L["Bottom"], BOTTOMRIGHT = L["Bottom right"] },
		get = get, set = set, disabled = border_disabled, order = 10,
	},
	'icon_x', {
		type = 'range', name = L["Dispel icon X offset"],
		min = -100, max = 100, step = 1,
		get = get, set = set, disabled = border_disabled, order = 11,
	},
	'icon_y', {
		type = 'range', name = L["Dispel icon Y offset"],
		min = -100, max = 100, step = 1,
		get = get, set = set, disabled = border_disabled, order = 12,
	},
	'icon_level_offset', {
		type = 'range', name = L["Dispel icon frame level"],
		desc = L["Raise or lower the dispel icon relative to the unit frame. Increase this if texts or other PitBull elements cover the icon."],
		min = 1, max = 80, step = 1,
		get = get, set = set, disabled = border_disabled, order = 13,
	}

end)
