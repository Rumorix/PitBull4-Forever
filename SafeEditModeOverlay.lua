local _G = _G
local PitBull4 = _G.PitBull4
local L = PitBull4.L

-- Patch 078-084: safe Blizzard Edit Mode overlay with pre-AceDB full-profile rollback.
--
-- This implementation is intentionally isolated from PitBull's secure unit
-- frame lifecycle. It never ForceShow()s a PitBull unit frame, never enters
-- PitBull Config Mode, never changes unit assignments, and never registers a
-- PitBull frame as a Blizzard Edit Mode system. All Edit Mode visuals are
-- addon-owned, non-secure ghost overlays. Dragging a ghost updates only the
-- corresponding saved anchor/position fields in the current PitBull profile.

local SafeEditMode = {}
PitBull4.SafeEditModeOverlay = SafeEditMode

local initialized = false
local blizzard_edit_mode_active = false
local singleton_ghosts = {}
local group_ghosts = {}
local prompt_seen_profiles = {}
local preview_panel
local inspector_panel
local selected_ghost
local preview_mode = "live"

local POSITION_FIELDS = {
	"anchor",
	"relative_to",
	"relative_point",
	"position_x",
	"position_y",
}

-- Patch 079: full-profile safety snapshots live in a dedicated SavedVariable
-- instead of inside the PitBull profile they protect. This prevents a restore
-- from overwriting its own backup and lets us restore the complete current
-- profile plus every AceDB namespace profile (including unloaded modules).
local FULL_SNAPSHOT_VERSION = 2

local function get_full_snapshot_store(create)
	local store = _G.PitBull4SafetyBackups
	if type(store) ~= "table" and create then
		store = { version = FULL_SNAPSHOT_VERSION, profiles = {} }
		_G.PitBull4SafetyBackups = store
	end
	if type(store) ~= "table" then
		return nil
	end
	if type(store.profiles) ~= "table" and create then
		store.profiles = {}
	end
	return store
end

local GROUP_ANCHOR_BY_DIRECTION = {
	down_right = "TOPLEFT",
	down_left = "TOPRIGHT",
	up_right = "BOTTOMLEFT",
	up_left = "BOTTOMRIGHT",
	right_down = "TOPLEFT",
	right_up = "BOTTOMLEFT",
	left_down = "TOPRIGHT",
	left_up = "BOTTOMRIGHT",
}

local function get_settings(create)
	local profile = PitBull4.db and PitBull4.db.profile
	if not profile then
		return nil
	end
	if type(profile.safe_edit_mode) ~= "table" and create then
		profile.safe_edit_mode = { enabled = true }
	end
	return profile.safe_edit_mode
end

local function notify_options()
	local registry = LibStub("AceConfigRegistry-3.0", true)
	if registry and PitBull4.Options and PitBull4.Options.IsRegistered and PitBull4.Options.IsRegistered() then
		registry:NotifyChange("PitBull4")
	end
end

local function copy_position(source)
	local out = {}
	for i = 1, #POSITION_FIELDS do
		local key = POSITION_FIELDS[i]
		out[key] = source[key]
	end
	return out
end

local function apply_position(destination, source)
	for i = 1, #POSITION_FIELDS do
		local key = POSITION_FIELDS[i]
		destination[key] = source[key]
	end
end

function PitBull4:HasSafeEditModeFullSnapshot()
	local store = get_full_snapshot_store(false)
	local profile_name = self.db and self.db:GetCurrentProfile()
	return store and store.profiles and profile_name and type(store.profiles[profile_name]) == "table" or false
end

function PitBull4:GetSafeEditModeFullSnapshot()
	local store = get_full_snapshot_store(false)
	local profile_name = self.db and self.db:GetCurrentProfile()
	return store and store.profiles and profile_name and store.profiles[profile_name] or nil
end

function PitBull4:CreateSafeEditModeFullSnapshot()
	if InCombatLockdown() then
		return false, 0
	end
	local profile_name = self.db and self.db:GetCurrentProfile()
	local sv = _G.PitBull4DB
	if not profile_name or type(sv) ~= "table" or type(self.db.profile) ~= "table" then
		return false, 0
	end

	-- Patch 083: snapshot the live AceDB profile table rather than relying on a
	-- raw SavedVariables alias. Position changes are applied to self.db.profile
	-- immediately, so the live table is the authoritative source at backup time.
	self:CreateSafeEditModePositionReference()
	local settings = get_settings(true)
	settings.full_snapshot_setup = "backup"
	local main_profile = self.db.profile

	local store = get_full_snapshot_store(true)
	local snapshot = {
		version = FULL_SNAPSHOT_VERSION,
		patch = 83,
		profile_name = profile_name,
		created_at = _G.date and _G.date("%Y-%m-%d %H:%M:%S") or "",
		profile = PitBull4.Utils.deep_copy(main_profile),
		position_reference = PitBull4.Utils.deep_copy(self:GetSafeEditModePositionReference()),
		namespaces = {},
	}

	-- Start with the raw AceDB namespace SavedVariables. This includes namespace
	-- profiles for load-on-demand modules that are not currently instantiated.
	for namespace_name, namespace_sv in pairs(sv.namespaces or {}) do
		local namespace_profile = namespace_sv and namespace_sv.profiles and namespace_sv.profiles[profile_name]
		if type(namespace_profile) == "table" then
			snapshot.namespaces[namespace_name] = PitBull4.Utils.deep_copy(namespace_profile)
		end
	end

	-- Refresh loaded modules from their live AceDB profile tables. This mirrors
	-- PitBull's own profile export path and guarantees the current in-memory
	-- module settings are represented even if the raw namespace table changed.
	for id, module in self:IterateModules() do
		local module_profile = module.db and module.db.profiles and module.db.profiles[profile_name]
		if type(module_profile) == "table" then
			snapshot.namespaces[id] = PitBull4.Utils.deep_copy(module_profile)
		end
	end

	local namespace_count = 0
	for _ in pairs(snapshot.namespaces) do namespace_count = namespace_count + 1 end
	snapshot.namespace_count = namespace_count
	store.profiles[profile_name] = snapshot
	store.last_restore_result = nil
	notify_options()
	return true, namespace_count
end

function PitBull4:RestoreSafeEditModeFullSnapshot()
	if InCombatLockdown() then
		return false, "restore unavailable while in combat"
	end
	local snapshot = self:GetSafeEditModeFullSnapshot()
	local profile_name = self.db and self.db:GetCurrentProfile()
	if type(snapshot) ~= "table" or type(snapshot.profile) ~= "table" or not profile_name then
		return false, "snapshot missing or invalid"
	end

	-- Patch 080/081: never rewrite an active AceDB profile in-place. Mark this
	-- snapshot for recovery and reload. SafetyRestoreBootstrap.lua runs before
	-- Main.lua/AceDB initialization and restores the raw SavedVariables there.
	local store = get_full_snapshot_store(true)
	store.pending_restore = {
		profile_name = profile_name,
		requested_at = _G.date and _G.date("%Y-%m-%d %H:%M:%S") or "",
		patch = 83,
	}

	-- Patch 082: this function is now called only from PitBull's own explicit
	-- StaticPopup confirmation. Reload immediately after staging the request.
	-- This avoids depending on AceConfig's execute-confirm callback lifecycle or
	-- a zero-delay timer that may never fire while the options dialog is active.
	local reload_ui = _G.ReloadUI
	if type(reload_ui) ~= "function" then
		store.pending_restore = nil
		return false, "ReloadUI is unavailable"
	end
	self:Printf("Full PitBull safety restore staged for profile '%s'; reloading UI now...", profile_name)
	reload_ui()
	return true, snapshot.namespace_count or 0
end

function PitBull4:ShowSafeEditModeFullRestorePrompt()
	if InCombatLockdown() then
		self:Printf("Full PitBull safety restore is unavailable while in combat.")
		return false
	end
	if not self:HasSafeEditModeFullSnapshot() then
		self:Printf("No full PitBull safety snapshot exists for the current profile.")
		return false
	end
	StaticPopup_Show("PITBULL4_FULL_SAFETY_RESTORE")
	return true
end

function PitBull4:DeleteSafeEditModeFullSnapshot()
	local store = get_full_snapshot_store(false)
	local profile_name = self.db and self.db:GetCurrentProfile()
	if not store or not store.profiles or not profile_name or not store.profiles[profile_name] then
		return false
	end
	store.profiles[profile_name] = nil
	local settings = get_settings(true)
	settings.full_snapshot_setup = nil
	notify_options()
	return true
end

function PitBull4:ConsumeSafeEditModeRestoreResult()
	local store = get_full_snapshot_store(false)
	local result = store and store.last_restore_result
	if type(result) ~= "table" then
		return nil
	end
	store.last_restore_result = nil
	return result
end

function PitBull4:HasSafeEditModePositionReference()
	local settings = get_settings(false)
	return settings and type(settings.position_reference) == "table" or false
end

function PitBull4:GetSafeEditModePositionReference()
	local settings = get_settings(false)
	return settings and settings.position_reference or nil
end

function PitBull4:CreateSafeEditModePositionReference()
	local settings = get_settings(true)
	if not settings then
		return false, 0, 0
	end

	local profile = self.db.profile
	local reference = {
		version = 1,
		patch = 78,
		profile = self.db:GetCurrentProfile(),
		created_at = _G.date and _G.date("%Y-%m-%d %H:%M:%S") or "",
		units = {},
		groups = {},
	}

	local unit_count = 0
	for name, unit_db in pairs(profile.units or {}) do
		if type(unit_db) == "table" then
			reference.units[name] = copy_position(unit_db)
			unit_count = unit_count + 1
		end
	end

	local group_count = 0
	for name, group_db in pairs(profile.groups or {}) do
		if type(group_db) == "table" then
			reference.groups[name] = copy_position(group_db)
			group_count = group_count + 1
		end
	end

	reference.unit_count = unit_count
	reference.group_count = group_count
	settings.position_reference = reference
	settings.setup_state = "backup"
	notify_options()
	return true, unit_count, group_count
end

local function refresh_real_positions()
	if InCombatLockdown() then
		return
	end
	for frame in PitBull4:IterateSingletonFrames(true) do
		if frame.classification_db then
			frame:RefixSizeAndPosition()
		end
	end
	for header in PitBull4:IterateHeaders(true) do
		if header.group_db then
			header:RefixSizeAndPosition()
		end
	end
end

function PitBull4:RestoreSafeEditModePositionReference()
	local settings = get_settings(false)
	local reference = settings and settings.position_reference
	if type(reference) ~= "table" then
		return false, 0, 0
	end
	if InCombatLockdown() then
		return false, 0, 0
	end

	local profile = self.db.profile
	local unit_count = 0
	for name, snapshot in pairs(reference.units or {}) do
		local unit_db = rawget(profile.units, name)
		if type(unit_db) == "table" and type(snapshot) == "table" then
			apply_position(unit_db, snapshot)
			unit_count = unit_count + 1
		end
	end

	local group_count = 0
	for name, snapshot in pairs(reference.groups or {}) do
		local group_db = rawget(profile.groups, name)
		if type(group_db) == "table" and type(snapshot) == "table" then
			apply_position(group_db, snapshot)
			group_count = group_count + 1
		end
	end

	refresh_real_positions()
	SafeEditMode:Refresh()
	notify_options()
	return true, unit_count, group_count
end

function PitBull4:DeleteSafeEditModePositionReference()
	local settings = get_settings(true)
	if not settings then
		return false
	end
	settings.position_reference = nil
	settings.setup_state = "skipped"
	notify_options()
	return true
end

function PitBull4:IsSafeEditModeReady()
	local settings = get_settings(true)
	if not settings or settings.enabled == false then
		return false
	end
	-- Patch 079 deliberately requires a full-profile safety decision. Existing
	-- Patch 078 position-only references do not silently unlock Edit Mode.
	return settings.full_snapshot_setup == "backup" or settings.full_snapshot_setup == "skipped" or self:HasSafeEditModeFullSnapshot()
end

local function get_point_coordinates(frame, point)
	if not frame then return nil end
	if point == "TOPLEFT" then
		return frame:GetLeft(), frame:GetTop()
	elseif point == "TOPRIGHT" then
		return frame:GetRight(), frame:GetTop()
	elseif point == "BOTTOMLEFT" then
		return frame:GetLeft(), frame:GetBottom()
	elseif point == "BOTTOMRIGHT" then
		return frame:GetRight(), frame:GetBottom()
	elseif point == "TOP" then
		local x = frame:GetCenter()
		return x, frame:GetTop()
	elseif point == "BOTTOM" then
		local x = frame:GetCenter()
		return x, frame:GetBottom()
	elseif point == "LEFT" then
		local _, y = frame:GetCenter()
		return frame:GetLeft(), y
	elseif point == "RIGHT" then
		local _, y = frame:GetCenter()
		return frame:GetRight(), y
	end
	return frame:GetCenter()
end

local function resolve_relative_frame(relative_to)
	local frame, relative_type = PitBull4.Utils.GetRelativeFrame(relative_to)
	if relative_type == "f" and frame and frame[1] then
		return frame[1]
	end
	return frame
end

local function save_ghost_position(ghost, db, anchor)
	if not ghost or not db or InCombatLockdown() then
		return false
	end
	ghost:StopMovingOrSizing()

	local relative_frame = resolve_relative_frame(db.relative_to)
	if not relative_frame then
		return false
	end
	local relative_point = db.relative_point or "CENTER"
	local x, y = get_point_coordinates(ghost, anchor)
	local x2, y2 = get_point_coordinates(relative_frame, relative_point)
	if not x or not y or not x2 or not y2 then
		return false
	end

	local ui_scale = UIParent:GetEffectiveScale()
	local scale = ghost:GetEffectiveScale() / ui_scale
	local relative_scale = relative_frame:GetEffectiveScale() / ui_scale
	x, y = x * scale, y * scale
	x2, y2 = x2 * relative_scale, y2 * relative_scale

	db.position_x = x - x2
	db.position_y = y - y2
	notify_options()
	return true
end

local function add_border(frame, thickness)
	local border = {}
	for i = 1, 4 do
		border[i] = frame:CreateTexture(nil, "BORDER")
		border[i]:SetColorTexture(0.15, 0.65, 1.00, 0.95)
	end
	border[1]:SetPoint("TOPLEFT")
	border[1]:SetPoint("TOPRIGHT")
	border[1]:SetHeight(thickness)
	border[2]:SetPoint("BOTTOMLEFT")
	border[2]:SetPoint("BOTTOMRIGHT")
	border[2]:SetHeight(thickness)
	border[3]:SetPoint("TOPLEFT")
	border[3]:SetPoint("BOTTOMLEFT")
	border[3]:SetWidth(thickness)
	border[4]:SetPoint("TOPRIGHT")
	border[4]:SetPoint("BOTTOMRIGHT")
	border[4]:SetWidth(thickness)
	return border
end

local function set_border_color(border, r, g, b, a)
	for i = 1, #border do
		border[i]:SetColorTexture(r, g, b, a)
	end
end

-- Patch 084: every Edit Mode preview starts locked.  Clicking a preview opens
-- one shared inspector where the frame classification/layout can be reviewed,
-- movement can be unlocked explicitly, and this one frame can be reset to the
-- newest saved Edit Mode position backup without restoring the whole profile.
local function get_saved_position(kind, name)
	local full_snapshot = PitBull4:GetSafeEditModeFullSnapshot()
	local full_reference = full_snapshot and full_snapshot.position_reference
	local quick_reference = PitBull4:GetSafeEditModePositionReference()

	local key = kind == "group" and "groups" or "units"
	local full_position = full_reference and full_reference[key] and full_reference[key][name]
	local quick_position = quick_reference and quick_reference[key] and quick_reference[key][name]
	local full_time = full_snapshot and full_snapshot.created_at or ""
	local quick_time = quick_reference and quick_reference.created_at or ""

	if type(full_position) == "table" and (type(quick_position) ~= "table" or full_time >= quick_time) then
		return full_position, L["Full safety snapshot"], full_time
	elseif type(quick_position) == "table" then
		return quick_position, L["Position reference"], quick_time
	end
	return nil, nil, nil
end

local function update_ghost_visual(ghost, hovered)
	if not ghost or not ghost.pb4_border then return end
	if hovered or ghost == selected_ghost then
		set_border_color(ghost.pb4_border, 1.00, 0.82, 0.15, 1.00)
		if ghost.pb4_shade then ghost.pb4_shade:SetColorTexture(1.00, 0.82, 0.15, 0.12) end
	elseif ghost.pb4_unlocked then
		set_border_color(ghost.pb4_border, 0.20, 0.95, 0.35, 0.95)
		if ghost.pb4_shade then ghost.pb4_shade:SetColorTexture(0.20, 0.75, 0.30, 0.12) end
	else
		set_border_color(ghost.pb4_border, 0.15, 0.65, 1.00, 0.95)
		if ghost.pb4_shade then ghost.pb4_shade:SetColorTexture(0.10, 0.45, 1.00, 0.12) end
	end
end

local function create_inspector_panel()
	local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	panel:SetSize(300, 132)
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:SetClampedToScreen(true)
	panel:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(0.03, 0.03, 0.03, 0.96)
	panel:SetBackdropBorderColor(0.35, 0.55, 0.85, 1)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText(L["PitBull Edit Mode frame"])

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function()
		local previous = selected_ghost
		selected_ghost = nil
		panel:Hide()
		update_ghost_visual(previous, false)
	end)

	local frame_text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame_text:SetPoint("TOPLEFT", 12, -34)
	frame_text:SetJustifyH("LEFT")
	panel.pb4_frame_text = frame_text

	local layout_text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	layout_text:SetPoint("TOPLEFT", frame_text, "BOTTOMLEFT", 0, -5)
	layout_text:SetJustifyH("LEFT")
	panel.pb4_layout_text = layout_text

	local backup_text = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	backup_text:SetPoint("TOPLEFT", layout_text, "BOTTOMLEFT", 0, -5)
	backup_text:SetJustifyH("LEFT")
	backup_text:SetWidth(276)
	panel.pb4_backup_text = backup_text

	local lock_button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	lock_button:SetSize(118, 24)
	lock_button:SetPoint("BOTTOMLEFT", 12, 10)
	lock_button:SetScript("OnClick", function()
		if not selected_ghost or InCombatLockdown() then return end
		selected_ghost.pb4_unlocked = not selected_ghost.pb4_unlocked
		update_ghost_visual(selected_ghost, false)
		SafeEditMode:RefreshInspector()
	end)
	panel.pb4_lock_button = lock_button

	local reset_button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset_button:SetSize(146, 24)
	reset_button:SetPoint("BOTTOMRIGHT", -12, 10)
	reset_button:SetText(L["Reset to backup"])
	reset_button:SetScript("OnClick", function()
		SafeEditMode:ResetSelectedToBackup()
	end)
	panel.pb4_reset_button = reset_button

	panel:Hide()
	return panel
end

function SafeEditMode:RefreshInspector()
	if not selected_ghost or not selected_ghost:IsShown() or not blizzard_edit_mode_active or InCombatLockdown() then
		if inspector_panel then inspector_panel:Hide() end
		if selected_ghost and (not selected_ghost:IsShown() or not blizzard_edit_mode_active) then
			local previous = selected_ghost
			selected_ghost = nil
			update_ghost_visual(previous, false)
		end
		return
	end
	if not inspector_panel then inspector_panel = create_inspector_panel() end

	local name = selected_ghost.pb4_name or "?"
	local db = selected_ghost.pb4_db
	local layout = db and db.layout or "?"
	local saved, source, timestamp = get_saved_position(selected_ghost.pb4_kind, name)
	inspector_panel.pb4_frame_text:SetText(L["Frame: %s"]:format(tostring(name)))
	inspector_panel.pb4_layout_text:SetText(L["Layout: %s"]:format(tostring(layout)))
	if saved then
		inspector_panel.pb4_backup_text:SetText(L["Backup: %s (%s)"]:format(source or "?", timestamp ~= "" and timestamp or L["unknown time"]))
		inspector_panel.pb4_reset_button:Enable()
	else
		inspector_panel.pb4_backup_text:SetText(L["Backup: none for this frame"])
		inspector_panel.pb4_reset_button:Disable()
	end
	inspector_panel.pb4_lock_button:SetText(selected_ghost.pb4_unlocked and L["Lock frame"] or L["Unlock frame"])
	inspector_panel:ClearAllPoints()
	inspector_panel:SetPoint("LEFT", selected_ghost, "RIGHT", 10, 0)
	inspector_panel:Show()
end

function SafeEditMode:SelectGhost(ghost)
	if not ghost or InCombatLockdown() then return end
	local previous = selected_ghost
	selected_ghost = ghost
	if previous and previous ~= ghost then update_ghost_visual(previous, false) end
	update_ghost_visual(ghost, false)
	self:RefreshInspector()
end

function SafeEditMode:ResetSelectedToBackup()
	local ghost = selected_ghost
	if not ghost or InCombatLockdown() then return false end
	local saved, source = get_saved_position(ghost.pb4_kind, ghost.pb4_name)
	if type(saved) ~= "table" or type(ghost.pb4_db) ~= "table" then
		PitBull4:Printf(L["No saved Edit Mode backup position exists for frame '%s'."], tostring(ghost.pb4_name or "?"))
		return false
	end
	apply_position(ghost.pb4_db, saved)
	if ghost.pb4_kind == "group" then
		local real = ghost.pb4_real_header
		if real and real.group_db == ghost.pb4_db then real:RefixSizeAndPosition() end
		self:RefreshGroupGhost(ghost.pb4_name)
	else
		local real = ghost.pb4_real_frame
		if real and real.classification_db == ghost.pb4_db then real:RefixSizeAndPosition() end
		self:RefreshSingletonGhost(ghost.pb4_name)
	end
	notify_options()
	PitBull4:Printf(L["Reset frame '%s' to the saved position from %s."], tostring(ghost.pb4_name or "?"), source or L["Edit Mode Backup"])
	self:RefreshInspector()
	return true
end

local function create_singleton_ghost(name)
	local ghost = CreateFrame("Button", nil, UIParent)
	ghost:SetFrameStrata("DIALOG")
	ghost:SetMovable(true)
	ghost:EnableMouse(true)
	ghost:RegisterForClicks("LeftButtonUp")
	ghost:RegisterForDrag("LeftButton")
	ghost:SetClampedToScreen(true)
	ghost.pb4_kind = "unit"
	ghost.pb4_unlocked = false

	local shade = ghost:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0.10, 0.45, 1.00, 0.12)
	ghost.pb4_shade = shade
	ghost.pb4_border = add_border(ghost, 2)

	local label = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	label:SetText("PitBull4: " .. tostring(name))
	ghost.pb4_label = label

	ghost:SetScript("OnEnter", function(self) update_ghost_visual(self, true) end)
	ghost:SetScript("OnLeave", function(self) update_ghost_visual(self, false) end)
	ghost:SetScript("OnClick", function(self) SafeEditMode:SelectGhost(self) end)
	ghost:SetScript("OnDragStart", function(self)
		if self.pb4_unlocked and not InCombatLockdown() then
			self:StartMoving()
		end
	end)
	ghost:SetScript("OnDragStop", function(self)
		local db = self.pb4_db
		if db and save_ghost_position(self, db, db.anchor or "CENTER") then
			local real = self.pb4_real_frame
			if real and real.classification_db == db then
				real:RefixSizeAndPosition()
			end
		end
		SafeEditMode:RefreshSingletonGhost(self.pb4_name)
		SafeEditMode:RefreshInspector()
	end)
	ghost:Hide()
	return ghost
end

function SafeEditMode:RefreshSingletonGhost(name)
	local profile = PitBull4.db and PitBull4.db.profile
	local unit_db = profile and profile.units and rawget(profile.units, name)
	local ghost = singleton_ghosts[name]
	if not unit_db or unit_db.enabled == false or not blizzard_edit_mode_active or not PitBull4:IsSafeEditModeReady() or InCombatLockdown() then
		if ghost then ghost:Hide() end
		return
	end

	local layout_db = profile.layouts and profile.layouts[unit_db.layout]
	if not layout_db then
		if ghost then ghost:Hide() end
		return
	end

	if not ghost then
		ghost = create_singleton_ghost(name)
		singleton_ghosts[name] = ghost
	end

	local real_frame
	for frame in PitBull4:IterateSingletonFrames(true) do
		if frame.classification == name then
			real_frame = frame
			break
		end
	end

	local scale = (tonumber(layout_db.scale) or 1) * (tonumber(unit_db.scale) or 1)
	local width = (tonumber(layout_db.size_x) or 200) * (tonumber(unit_db.size_x) or 1)
	local height = (tonumber(layout_db.size_y) or 60) * (tonumber(unit_db.size_y) or 1)
	local relative_frame = resolve_relative_frame(unit_db.relative_to) or UIParent

	ghost.pb4_name = name
	ghost.pb4_kind = "unit"
	ghost.pb4_db = unit_db
	ghost.pb4_real_frame = real_frame
	ghost.pb4_label:SetText("PitBull4: " .. tostring(name))
	ghost:SetScale(scale)
	ghost:SetSize(width, height)
	ghost:ClearAllPoints()
	ghost:SetPoint(unit_db.anchor or "CENTER", relative_frame, unit_db.relative_point or "CENTER", (unit_db.position_x or 0) / scale, (unit_db.position_y or 0) / scale)
	ghost:Show()
	update_ghost_visual(ghost, false)
end

local function get_group_kind(group_db)
	local unit_group = tostring(group_db and group_db.unit_group or "")
	if unit_group:sub(1, 5) == "party" then
		return "party"
	elseif unit_group:sub(1, 4) == "raid" then
		return "raid"
	end
	return nil
end

local function get_live_group_mode()
	if _G.IsInRaid and _G.IsInRaid() then
		local count = _G.GetNumGroupMembers and _G.GetNumGroupMembers() or 40
		if count <= 10 then return "raid10" end
		if count <= 20 then return "raid20" end
		return "raid40"
	elseif _G.IsInGroup and _G.IsInGroup() then
		return "party"
	end
	return "none"
end

local function get_preview_count(group_db, mode)
	local kind = get_group_kind(group_db)
	if mode == "live" then
		mode = get_live_group_mode()
	end
	if kind == "party" and mode == "party" then
		local unit_group = tostring(group_db.unit_group or "")
		if unit_group == "party" then
			return group_db.include_player and 5 or 4
		end
		return 4
	elseif kind == "raid" and mode:sub(1, 4) == "raid" then
		return tonumber(mode:sub(5)) or 10
	end
	return 0
end

local function create_preview_member(parent, index)
	local member = CreateFrame("Frame", nil, parent)
	member:SetFrameLevel(parent:GetFrameLevel() + 1)
	local bg = member:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.12, 0.25, 0.42, 0.55)
	member.pb4_border = add_border(member, 1)
	set_border_color(member.pb4_border, 0.30, 0.68, 1.00, 0.80)
	local text = member:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER")
	text:SetText(tostring(index))
	member.pb4_text = text
	member:EnableMouse(false)
	return member
end

local function create_group_ghost(name)
	local ghost = CreateFrame("Button", nil, UIParent)
	ghost:SetFrameStrata("DIALOG")
	ghost:SetMovable(true)
	ghost:EnableMouse(true)
	ghost:RegisterForClicks("LeftButtonUp")
	ghost:RegisterForDrag("LeftButton")
	ghost:SetClampedToScreen(true)
	ghost.pb4_kind = "group"
	ghost.pb4_unlocked = false
	ghost.pb4_members = {}

	local shade = ghost:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0.08, 0.30, 0.48, 0.10)
	ghost.pb4_shade = shade
	ghost.pb4_border = add_border(ghost, 2)

	local label = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("BOTTOMLEFT", ghost, "TOPLEFT", 0, 3)
	label:SetText("PitBull4: " .. tostring(name))
	ghost.pb4_label = label

	ghost:SetScript("OnEnter", function(self) update_ghost_visual(self, true) end)
	ghost:SetScript("OnLeave", function(self) update_ghost_visual(self, false) end)
	ghost:SetScript("OnClick", function(self) SafeEditMode:SelectGhost(self) end)
	ghost:SetScript("OnDragStart", function(self)
		if self.pb4_unlocked and not InCombatLockdown() then self:StartMoving() end
	end)
	ghost:SetScript("OnDragStop", function(self)
		local db = self.pb4_db
		local anchor = db and db.anchor
		if db and (not anchor or anchor == "") then
			anchor = GROUP_ANCHOR_BY_DIRECTION[db.direction] or "TOPLEFT"
		end
		if db and save_ghost_position(self, db, anchor or "TOPLEFT") then
			local real = self.pb4_real_header
			if real and real.group_db == db then
				real:RefixSizeAndPosition()
			end
		end
		SafeEditMode:RefreshGroupGhost(self.pb4_name)
		SafeEditMode:RefreshInspector()
	end)
	ghost:Hide()
	return ghost
end

local function position_preview_member(member, ghost, direction, row, col, unit_w, unit_h, gap_x, gap_y)
	member:ClearAllPoints()
	if direction == "down_left" then
		member:SetPoint("TOPRIGHT", ghost, "TOPRIGHT", -col * (unit_w + gap_x), -row * (unit_h + gap_y))
	elseif direction == "up_right" then
		member:SetPoint("BOTTOMLEFT", ghost, "BOTTOMLEFT", col * (unit_w + gap_x), row * (unit_h + gap_y))
	elseif direction == "up_left" then
		member:SetPoint("BOTTOMRIGHT", ghost, "BOTTOMRIGHT", -col * (unit_w + gap_x), row * (unit_h + gap_y))
	elseif direction == "right_down" then
		member:SetPoint("TOPLEFT", ghost, "TOPLEFT", col * (unit_w + gap_x), -row * (unit_h + gap_y))
	elseif direction == "right_up" then
		member:SetPoint("BOTTOMLEFT", ghost, "BOTTOMLEFT", col * (unit_w + gap_x), row * (unit_h + gap_y))
	elseif direction == "left_down" then
		member:SetPoint("TOPRIGHT", ghost, "TOPRIGHT", -col * (unit_w + gap_x), -row * (unit_h + gap_y))
	elseif direction == "left_up" then
		member:SetPoint("BOTTOMRIGHT", ghost, "BOTTOMRIGHT", -col * (unit_w + gap_x), row * (unit_h + gap_y))
	else
		member:SetPoint("TOPLEFT", ghost, "TOPLEFT", col * (unit_w + gap_x), -row * (unit_h + gap_y))
	end
end

function SafeEditMode:RefreshGroupGhost(name)
	local profile = PitBull4.db and PitBull4.db.profile
	local group_db = profile and profile.groups and rawget(profile.groups, name)
	local ghost = group_ghosts[name]
	local count = group_db and get_preview_count(group_db, preview_mode) or 0
	if not group_db or group_db.enabled == false or count <= 0 or not blizzard_edit_mode_active or not PitBull4:IsSafeEditModeReady() or InCombatLockdown() then
		if ghost then ghost:Hide() end
		return
	end

	local layout_db = profile.layouts and profile.layouts[group_db.layout]
	if not layout_db then
		if ghost then ghost:Hide() end
		return
	end
	if not ghost then
		ghost = create_group_ghost(name)
		group_ghosts[name] = ghost
	end

	local direction = group_db.direction or "down_right"
	local vertical_first = direction:sub(1, 4) == "down" or direction:sub(1, 2) == "up"
	local per_line = math.max(1, math.floor(tonumber(group_db.units_per_column) or count))
	local primary_count = math.min(count, per_line)
	local secondary_count = math.ceil(count / per_line)
	local unit_w = (tonumber(layout_db.size_x) or 200) * (tonumber(group_db.size_x) or 1)
	local unit_h = (tonumber(layout_db.size_y) or 60) * (tonumber(group_db.size_y) or 1)
	local gap_x = tonumber(group_db.horizontal_spacing) or 0
	local gap_y = tonumber(group_db.vertical_spacing) or 0
	local width, height
	if vertical_first then
		width = secondary_count * unit_w + math.max(0, secondary_count - 1) * gap_x
		height = primary_count * unit_h + math.max(0, primary_count - 1) * gap_y
	else
		width = primary_count * unit_w + math.max(0, primary_count - 1) * gap_x
		height = secondary_count * unit_h + math.max(0, secondary_count - 1) * gap_y
	end

	for i = 1, count do
		local member = ghost.pb4_members[i]
		if not member then
			member = create_preview_member(ghost, i)
			ghost.pb4_members[i] = member
		end
		member:SetSize(unit_w, unit_h)
		member.pb4_text:SetText(tostring(i))
		local line = math.floor((i - 1) / per_line)
		local pos = (i - 1) % per_line
		local row, col
		if vertical_first then
			row, col = pos, line
		else
			row, col = line, pos
		end
		position_preview_member(member, ghost, direction, row, col, unit_w, unit_h, gap_x, gap_y)
		member:Show()
	end
	for i = count + 1, #ghost.pb4_members do
		ghost.pb4_members[i]:Hide()
	end

	local real_header
	for header in PitBull4:IterateHeaders(true) do
		if header.name == name then
			real_header = header
			break
		end
	end

	local scale = (tonumber(layout_db.scale) or 1) * (tonumber(group_db.scale) or 1)
	local anchor = group_db.anchor
	if not anchor or anchor == "" then
		anchor = GROUP_ANCHOR_BY_DIRECTION[direction] or "TOPLEFT"
	end
	local relative_frame = resolve_relative_frame(group_db.relative_to) or UIParent

	ghost.pb4_name = name
	ghost.pb4_kind = "group"
	ghost.pb4_db = group_db
	ghost.pb4_real_header = real_header
	ghost.pb4_label:SetText("PitBull4: " .. tostring(name) .. " (" .. tostring(count) .. ")")
	ghost:SetScale(scale)
	ghost:SetSize(math.max(width, 8), math.max(height, 8))
	ghost:ClearAllPoints()
	ghost:SetPoint(anchor, relative_frame, group_db.relative_point or "CENTER", (group_db.position_x or 0) / scale, (group_db.position_y or 0) / scale)
	ghost:Show()
	update_ghost_visual(ghost, false)
end

local PREVIEW_MODES = {
	{ key = "live", label = "Live" },
	{ key = "party", label = "Party" },
	{ key = "raid10", label = "Raid 10" },
	{ key = "raid20", label = "Raid 20" },
	{ key = "raid40", label = "Raid 40" },
}

local function save_panel_position(panel)
	local settings = get_settings(true)
	local x, y = panel:GetCenter()
	if settings and x and y then
		settings.panel_x = x - UIParent:GetWidth() / 2
		settings.panel_y = y - UIParent:GetHeight() / 2
	end
end

local function update_panel_buttons()
	if not preview_panel or not preview_panel.pb4_buttons then return end
	for key, button in pairs(preview_panel.pb4_buttons) do
		if key == preview_mode then button:LockHighlight() else button:UnlockHighlight() end
	end
end

function PitBull4:SetSafeEditModePreviewMode(mode)
	if mode ~= "live" and mode ~= "party" and mode ~= "raid10" and mode ~= "raid20" and mode ~= "raid40" then
		return false
	end
	preview_mode = mode
	SafeEditMode:RefreshGroups()
	SafeEditMode:RefreshInspector()
	update_panel_buttons()
	return true
end

local function create_preview_panel()
	local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	panel:SetSize(340, 58)
	panel:SetFrameStrata("DIALOG")
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetClampedToScreen(true)
	panel:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(0.03, 0.03, 0.03, 0.94)
	panel:SetBackdropBorderColor(0.35, 0.55, 0.85, 1)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOP", 0, -7)
	title:SetText(L["PitBull Edit Mode preview"])

	panel.pb4_buttons = {}
	local x = 8
	for i = 1, #PREVIEW_MODES do
		local data = PREVIEW_MODES[i]
		local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		button:SetSize(60, 22)
		button:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x, 7)
		button:SetText(data.label)
		button:SetScript("OnClick", function() PitBull4:SetSafeEditModePreviewMode(data.key) end)
		panel.pb4_buttons[data.key] = button
		x = x + 64
	end

	panel:SetScript("OnDragStart", function(self)
		if not InCombatLockdown() then self:StartMoving() end
	end)
	panel:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		save_panel_position(self)
	end)
	panel:Hide()
	return panel
end

local function show_panel()
	if not preview_panel then preview_panel = create_preview_panel() end
	local settings = get_settings(true)
	preview_panel:ClearAllPoints()
	if settings.panel_x and settings.panel_y then
		preview_panel:SetPoint("CENTER", UIParent, "CENTER", settings.panel_x, settings.panel_y)
	else
		preview_panel:SetPoint("TOP", UIParent, "TOP", 0, -170)
	end
	update_panel_buttons()
	preview_panel:Show()
end

local function hide_all()
	for _, ghost in pairs(singleton_ghosts) do ghost:Hide() end
	for _, ghost in pairs(group_ghosts) do ghost:Hide() end
	if preview_panel then preview_panel:Hide() end
	if inspector_panel then inspector_panel:Hide() end
end

function SafeEditMode:RefreshSingletons()
	local profile = PitBull4.db and PitBull4.db.profile
	if not profile then return end
	local seen = {}
	for name, unit_db in pairs(profile.units or {}) do
		if type(unit_db) == "table" and unit_db.enabled ~= false then
			seen[name] = true
			self:RefreshSingletonGhost(name)
		end
	end
	for name, ghost in pairs(singleton_ghosts) do
		if not seen[name] then ghost:Hide() end
	end
end

function SafeEditMode:RefreshGroups()
	local profile = PitBull4.db and PitBull4.db.profile
	if not profile then return end
	local seen = {}
	for name, group_db in pairs(profile.groups or {}) do
		if type(group_db) == "table" and group_db.enabled ~= false then
			seen[name] = true
			self:RefreshGroupGhost(name)
		end
	end
	for name, ghost in pairs(group_ghosts) do
		if not seen[name] then ghost:Hide() end
	end
end

function SafeEditMode:Refresh()
	if not blizzard_edit_mode_active or InCombatLockdown() or not PitBull4:IsSafeEditModeReady() then
		hide_all()
		return
	end
	self:RefreshSingletons()
	self:RefreshGroups()
	show_panel()
	self:RefreshInspector()
end

function SafeEditMode:OnEditModeEnter()
	blizzard_edit_mode_active = true
	preview_mode = "live"
	selected_ghost = nil
	for _, ghost in pairs(singleton_ghosts) do ghost.pb4_unlocked = false end
	for _, ghost in pairs(group_ghosts) do ghost.pb4_unlocked = false end
	self:Refresh()
end

function SafeEditMode:OnEditModeExit()
	blizzard_edit_mode_active = false
	selected_ghost = nil
	hide_all()
end

local function is_blizzard_edit_mode_active()
	local manager = _G.EditModeManagerFrame
	if manager and type(manager.IsEditModeActive) == "function" then
		local ok, active = pcall(manager.IsEditModeActive, manager)
		return ok and active and true or false
	end
	return false
end

local function reference_saved_message(unit_count, group_count)
	PitBull4:Printf(L["Edit Mode position reference saved for %d unit frames and %d groups."], unit_count or 0, group_count or 0)
end

function PitBull4:ShowSafeEditModeBackupPrompt(force)
	local settings = get_settings(true)
	if not settings or settings.enabled == false then return end
	if not force and (settings.full_snapshot_setup ~= nil or self:HasSafeEditModeFullSnapshot()) then return end
	local profile_name = self.db:GetCurrentProfile()
	if not force and prompt_seen_profiles[profile_name] then return end
	if InCombatLockdown() then return end
	prompt_seen_profiles[profile_name] = true
	StaticPopup_Show("PITBULL4_SAFE_EDIT_MODE_REFERENCE_BACKUP", profile_name)
end

function PitBull4:ScheduleSafeEditModeBackupPrompt(force)
	local profile_name = self.db and self.db:GetCurrentProfile()
	if not profile_name then return end
	C_Timer.After(1.5, function()
		if PitBull4 and PitBull4.db and PitBull4.db:GetCurrentProfile() == profile_name then
			PitBull4:ShowSafeEditModeBackupPrompt(force)
		end
	end)
end

StaticPopupDialogs["PITBULL4_FULL_SAFETY_RESTORE"] = {
	text = L["Restore the complete PitBull profile from the full safety snapshot? All current changes to this profile since the snapshot will be overwritten and the UI will reload immediately."],
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function()
		local ok, detail = PitBull4:RestoreSafeEditModeFullSnapshot()
		if not ok then
			PitBull4:Printf(L["Full PitBull safety snapshot restore FAILED for profile '%s': %s"], PitBull4.db:GetCurrentProfile() or "", tostring(detail or "restore could not be staged"))
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["PITBULL4_SAFE_EDIT_MODE_REFERENCE_BACKUP"] = {
	text = L["PitBull can show safe, non-secure mover previews inside Blizzard Edit Mode. Create a full safety snapshot of profile '%s' before enabling them? The snapshot includes the complete PitBull profile and all module profile settings."],
	button1 = L["Create full backup"],
	button2 = L["Later"],
	button3 = L["Continue without backup"],
	OnAccept = function()
		local ok, namespaces = PitBull4:CreateSafeEditModeFullSnapshot()
		if ok then
			local snapshot = PitBull4:GetSafeEditModeFullSnapshot()
			PitBull4:Printf(L["Full PitBull safety snapshot saved for profile '%s' (%d module namespaces)."], snapshot and snapshot.profile_name or "", namespaces or 0)
			SafeEditMode:Refresh()
		end
	end,
	OnCancel = function() end,
	OnAlt = function()
		local settings = get_settings(true)
		settings.full_snapshot_setup = "skipped"
		notify_options()
		PitBull4:Printf(L["Safe Edit Mode overlay enabled without a full-profile safety snapshot."])
		SafeEditMode:Refresh()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function SafeEditMode:OnProfileChanged()
	hide_all()
	preview_mode = "live"
	blizzard_edit_mode_active = is_blizzard_edit_mode_active()
	self:Refresh()
	PitBull4:ScheduleSafeEditModeBackupPrompt()
end

function SafeEditMode:Initialize()
	if initialized then return end
	initialized = true

	if _G.EventRegistry and type(_G.EventRegistry.RegisterCallback) == "function" then
		_G.EventRegistry:RegisterCallback("EditMode.Enter", function() SafeEditMode:OnEditModeEnter() end)
		_G.EventRegistry:RegisterCallback("EditMode.Exit", function() SafeEditMode:OnEditModeExit() end)
	end

	if PitBull4.db and type(PitBull4.db.RegisterCallback) == "function" then
		PitBull4.db.RegisterCallback(self, "OnProfileChanged")
		PitBull4.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
		PitBull4.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	end

	blizzard_edit_mode_active = is_blizzard_edit_mode_active()
	PitBull4:ScheduleSafeEditModeBackupPrompt()
	self:Refresh()
end

local event_frame = CreateFrame("Frame")
event_frame:RegisterEvent("PLAYER_LOGIN")
event_frame:RegisterEvent("PLAYER_REGEN_DISABLED")
event_frame:RegisterEvent("PLAYER_REGEN_ENABLED")
event_frame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		local restore_result = PitBull4:ConsumeSafeEditModeRestoreResult()
		if restore_result then
			if restore_result.status == "success" then
				PitBull4:Printf(L["Full PitBull safety snapshot restored for profile '%s' (%d module namespaces)."], restore_result.profile_name or "", restore_result.namespace_count or 0)
			else
				PitBull4:Printf(L["Full PitBull safety snapshot restore FAILED for profile '%s': %s"], restore_result.profile_name or "", restore_result.message or "unknown error")
			end
		end
		SafeEditMode:Initialize()
	elseif event == "PLAYER_REGEN_DISABLED" then
		hide_all()
	elseif event == "PLAYER_REGEN_ENABLED" then
		blizzard_edit_mode_active = is_blizzard_edit_mode_active()
		SafeEditMode:Refresh()
	end
end)
