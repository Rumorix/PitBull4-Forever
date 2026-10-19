local _G = _G
local PitBull4 = _G.PitBull4
local L = PitBull4.L

-- luacheck: globals ChatFontNormal ClickCastHeader SecureButton_GetModifiedUnit

local DEBUG = PitBull4.DEBUG
local expect = PitBull4.expect
local frames_to_anchor = PitBull4.frames_to_anchor

-- CONSTANTS ----------------------------------------------------------------

local MODULE_UPDATE_ORDER = {
	"bar",
	"secret_bar",
	"bar_provider",
	"indicator",
	"text_provider",
	"custom_text",
	"custom",
	"fader",
}

-- Handles hiding and showing singleton unit frames.  Please no tabs in this code if you edit it.
-- WoW can't render tabs in FontStrings and it makes the errors from this code look awful.
local Singleton_OnAttributeChanged = [[
  if name ~= "state-pb4visibility" and name ~= "state-unitexists" and name ~= "config_mode" then return end

  if name ~= "state-pb4visibility" then
    -- Replace the value with the state handler state if we weren't called
    -- on its state change
    value = self:GetAttribute("state-pb4visibility")
  end

  if self:GetAttribute("config_mode") then
    self:Show()
  elseif value == "show" then
    self:Show()
  elseif value == "hide" then
    self:Hide()
  else
    if self:GetAttribute("state-unitexists") then
      self:Show()
    else
      self:Hide()
    end
  end
]]

-- Configure Blizzard's player-resource ping callout on PitBull player frames.
--
-- PingableUnitFrameTemplate gives every PitBull unit frame the generic unit-ping
-- behavior. Retail 12.1 uses a specialized player-frame path for the local
-- player's resource callout: GetTargetInfo must mark the target as a player
-- resource, and the radial wheel is suppressed over that resource region.
-- Keep Blizzard in charge of reading and formatting the actual health/power
-- values; PitBull only supplies the public player GUID and the resource marker.
local function ConfigurePlayerResourcePing(frame, unit)
	if unit ~= "player" then
		return
	end

	local target_info = { isPlayerResource = true }
	frame.GetTargetInfo = function()
		target_info.guid = UnitGUID("player")
		return target_info
	end
	frame.GetAllowRadialWheel = function()
		return false
	end
	frame.lorenzo_player_resource_ping = true
end

--- Make a singleton unit frame.
-- @param classification the classification of the Unit Frame
-- @usage local frame = PitBull4:MakeSingletonFrame("Player")
function PitBull4:MakeSingletonFrame(classification)
	if DEBUG then
		expect(classification, 'typeof', 'string')
	end

	local classification_db = PitBull4.db.profile.units[classification]
	if not classification_db then
		error(("Bad argument #1 to `MakeSingletonFrame'.  %q is not a singleton classification"):format(tostring(classification)),2)
	end

	local unit = classification_db.unit

	local id = PitBull4.Utils.GetBestUnitID(unit)
	if not PitBull4.Utils.IsSingletonUnitID(id) then
		error(("Bad unit set on Singleton Classification %q.  %q is not a singleton UnitID"):format(tostring(classification),tostring(unit)), 2)
	end
	unit = id

	local frame_name = "PitBull4_Frames_" .. classification
	local frame = _G[frame_name]

	if not frame then
		frame = CreateFrame("Button", frame_name, UIParent, "SecureUnitButtonTemplate,SecureHandlerBaseTemplate,PingableUnitFrameTemplate")

		if PitBull4.secure_snippets_available then
			frame:WrapScript(frame, "OnAttributeChanged", Singleton_OnAttributeChanged)
		else
			frame.lorenzo_secure_visibility_degraded = true
		end
		frame.is_singleton = true

		frame.classification = classification
		frame.classification_db = classification_db

		frame.is_wacky = PitBull4.Utils.IsWackyUnitGroup(unit)

		self:ConvertIntoUnitFrame(frame)

		ConfigurePlayerResourcePing(frame, unit)
		frame:SetAttribute("unit", unit)
	elseif frame.classification_db ~= classification_db then
		-- Previously deleted frame being reused, set the classification_db
		-- to its new classification_db.
		frame.classification_db = classification_db
	end

	frame:Activate()

	frame:RefreshLayout()

	frame:UpdateGUID(UnitGUID(unit))

	for frame_to_anchor, relative_to in pairs(frames_to_anchor) do
		local relative_frame = PitBull4.Utils.GetRelativeFrame(relative_to)
		if relative_frame == frame then
			frame_to_anchor:RefixSizeAndPosition()
		end
	end
end
PitBull4.MakeSingletonFrame = PitBull4:OutOfCombatWrapper(PitBull4.MakeSingletonFrame)

--- A Unit Frame created by PitBull4
-- @class table
-- @name UnitFrame
-- @field is_singleton whether the Unit Frame is a singleton or member
-- @field classification the classification of the Unit Frame
-- @field classification_db the database table for the Unit Frame's classification
-- @field layout the layout of the Unit Frame's classification
-- @field unit the UnitID of the Unit Frame. Can be nil.
-- @field guid the current GUID of the Unit Frame. Can be nil.
-- @field overlay an overlay frame for texts to be placed on.
local UnitFrame = {}
local SingletonUnitFrame = {}
local MemberUnitFrame = {}
PitBull4.UnitFrame = UnitFrame
PitBull4.SingletonUnitFrame = SingletonUnitFrame
PitBull4.MemberUnitFrame = MemberUnitFrame

local UnitFrame__scripts = {}
local SingletonUnitFrame__scripts = {}
local MemberUnitFrame__scripts = {}
PitBull4.UnitFrame__scripts = UnitFrame__scripts
PitBull4.SingletonUnitFrame__scripts = SingletonUnitFrame__scripts
PitBull4.MemberUnitFrame__scripts = MemberUnitFrame__scripts

function UnitFrame:ProxySetAttribute(key, value)
	if self:GetAttribute(key) ~= value then
		self:SetAttribute(key, value)
		return true
	end
end

local moving_frame = nil
local moving_frame_uses_sticky = false
function SingletonUnitFrame__scripts:OnDragStart()
	local db = PitBull4.db.profile
	if db.lock_movement or InCombatLockdown() then
		return
	end

	moving_frame = self
	moving_frame_uses_sticky = false

	-- Dependent singleton frames may continue following the cursor after
	-- LibSimpleSticky drag-stop on Forever. Use native dragging for them.
	local use_native_mover = self.unit == "targettarget" or self.unit == "focustarget"
	if db.frame_snap and not use_native_mover then
		-- Preserve sticky snapping for other singleton frames.
		local sticky = LibStub("LibSimpleSticky-1.0")
		-- Bartender can supply the shared minor-3 library first. Its successful
		-- StartMoving has no return value; only our explicit false means refused.
		moving_frame_uses_sticky = sticky:StartMoving(self, PitBull4.all_frames_list, 0, 0, 0, 0) ~= false
		if not moving_frame_uses_sticky then
			self:StartMoving()
		end
	else
		self:StartMoving()
	end
end

local function get_frame_anchor_coordinates(frame, point)
	if not frame then
		return nil, nil
	end
	if point == "TOPLEFT" then
		return frame:GetLeft(), frame:GetTop()
	elseif point == "TOPRIGHT" then
		return frame:GetRight(), frame:GetTop()
	elseif point == "BOTTOMLEFT" then
		return frame:GetLeft(), frame:GetBottom()
	elseif point == "BOTTOMRIGHT" then
		return frame:GetRight(), frame:GetBottom()
	elseif point == "CENTER" then
		return frame:GetCenter()
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
	return nil, nil
end

local function restore_singleton_position_after_invalid_drag(frame)
	-- Do not persist a broken position. Re-apply the last known profile anchor so
	-- the frame stays visible and can be moved again after geometry resolves.
	frame:RefixSizeAndPosition()
end

function SingletonUnitFrame__scripts:OnDragStop()
	if moving_frame ~= self then return end
	moving_frame = nil
	if moving_frame_uses_sticky then
		LibStub("LibSimpleSticky-1.0"):StopMoving(self)
	else
		self:StopMovingOrSizing()
	end
	moving_frame_uses_sticky = false

	local db = self.classification_db
	local anchor = db.anchor
	local relative_frame = PitBull4.Utils.GetRelativeFrame(db.relative_to)
	local relative_point = db.relative_point

	local ui_scale = UIParent:GetEffectiveScale()
	local self_scale = self:GetEffectiveScale()
	local relative_scale = relative_frame and relative_frame:GetEffectiveScale()
	if not ui_scale or ui_scale == 0 or not self_scale or self_scale == 0 or not relative_scale or relative_scale == 0 then
		restore_singleton_position_after_invalid_drag(self)
		return
	end

	local x, y = get_frame_anchor_coordinates(self, anchor)
	local x2, y2 = get_frame_anchor_coordinates(relative_frame, relative_point)
	if not x or not y or not x2 or not y2 then
		restore_singleton_position_after_invalid_drag(self)
		return
	end

	local scale = self_scale / ui_scale
	local scale2 = relative_scale / ui_scale
	x, y = x * scale, y * scale
	x2, y2 = x2 * scale2, y2 * scale2

	x = x - x2
	y = y - y2

	db.position_x = x
	db.position_y = y

	LibStub("AceConfigRegistry-3.0"):NotifyChange("PitBull4")

	self:RefreshLayout()
end

function SingletonUnitFrame__scripts:OnMouseUp(button)
	if button == "LeftButton" then
		return SingletonUnitFrame__scripts.OnDragStop(self)
	end
end

function SingletonUnitFrame:PLAYER_REGEN_DISABLED()
	if moving_frame then
		SingletonUnitFrame__scripts.OnDragStop(moving_frame)
	end
end

function UnitFrame__scripts:OnEnter()
	if self.unit and UnitExists(self.unit) then
		local tooltip = self.classification_db.tooltip
		if tooltip == "always" or (tooltip == "ooc" and not InCombatLockdown()) then
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
			-- SetUnit is a Blizzard secure tooltip delegate in 12.1. Execute only
			-- that delegate and never recolor GameTooltipTextLeft1 from addon code:
			-- touching the global line leaves PitBull taint behind, which later makes
			-- Blizzard's UnitIsPVP color rule fail for a secret target identity.
			local secure_call = _G.securecallfunction
			local ok
			if type(secure_call) == "function" then
				ok = pcall(secure_call, GameTooltip.SetUnit, GameTooltip, self.unit)
			else
				ok = pcall(GameTooltip.SetUnit, GameTooltip, self.unit)
			end
			if not ok then
				GameTooltip:Hide()
			end
		end
	end

	PitBull4:RunFrameScriptHooks("OnEnter", self)
end

function UnitFrame__scripts:OnLeave()
	GameTooltip:Hide()

	PitBull4:RunFrameScriptHooks("OnLeave", self)
end

function UnitFrame__scripts:OnAttributeChanged(key, value)
	if key == "unit" or key == "unitsuffix" then
		local new_unit = PitBull4.Utils.GetBestUnitID(SecureButton_GetModifiedUnit(self, "LeftButton")) or nil
		-- Forever 034: on the degraded Forever client, SecureButton_GetModifiedUnit()
		-- can return nil for a singleton whose configured unit does not currently
		-- exist (for example Target while no target is selected). self.unit must still
		-- retain that configured UnitID so config previews and unit bookkeeping work.
		if not new_unit and self.is_singleton and self.classification_db then
			local configured_unit = self.classification_db.unit
			new_unit = PitBull4.Utils.GetBestUnitID(configured_unit) or configured_unit
		end

		local updated = false
		local old_unit = self.unit

		-- As of 4.0.3 the the unit watch state handler no longer calls OnShow
		-- when the frame is already visible.  So you can't use that to detect
		-- that the unit on a frame has changed.  So we need to check for the
		-- GUID changing here.  However, if the frame is not shown we can't update
		-- the GUID or it hoses the update system.  So only update the GUID if
		-- we're already visible if we're not then the unit watch will update it
		-- normally.
		if self:IsVisible() then
			local guid = new_unit and UnitGUID(new_unit) or nil
			if issecretvalue(guid) or guid ~= self.guid then
				self.unit = new_unit -- Make sure unit is set before updates happen.
				updated = true
				self:UpdateGUID(guid)
			end
		end

		if old_unit == new_unit then
			return
		end

		-- debug assertion to help try and track down ticket 475.
		-- if DEBUG then
		-- 	if not new_unit then
		-- 		expect(self.guid, '==', nil)
		-- 	end
		-- end

		if old_unit then
			PitBull4.unit_id_to_frames[old_unit][self] = nil
			PitBull4.unit_id_to_frames_with_wacky[old_unit][self] = nil
		end

		self.unit = new_unit
		if new_unit then
			PitBull4.unit_id_to_frames[new_unit][self] = true
			PitBull4.unit_id_to_frames_with_wacky[new_unit][self] = true
			if self.is_singleton then
				local is_wacky = PitBull4.Utils.IsWackyUnitGroup(new_unit)
				self.is_wacky = is_wacky
				if is_wacky then
					if not PitBull4.wacky_frames[self] then
						PitBull4.wacky_frames[self] = true
						PitBull4.num_wacky_frames = PitBull4.num_wacky_frames + 1
					end
					PitBull4.non_wacky_frames[self] = nil
				else
					if PitBull4.wacky_frames[self] then
						PitBull4.num_wacky_frames = PitBull4.num_wacky_frames - 1
						PitBull4.wacky_frames[self] = nil
					end
					PitBull4.non_wacky_frames[self] = true
				end
			end
		end

		if not updated then
			self:Update(false)
		end
	elseif key == "state-unitexists" then
		if value then
			UnitFrame__scripts.OnShow(self)
		else
			UnitFrame__scripts.OnHide(self)
		end
	end
end

function UnitFrame__scripts:OnShow()
	if self.unit then
		local guid = UnitGUID(self.unit)
		if self.is_wacky or issecretvalue(guid) or issecretvalue(self.guid) or guid ~= self.guid then
			self:UpdateGUID(guid)
		end
	end

	self:SetAlpha(PitBull4:GetFinalFrameOpacity(self))

	if not self.force_show then
		-- Force an update to fix the frame if the unit info wasn't ready (ticket 1251)
		PitBull4:ScheduleTimer(self.UpdateLayout, 0.5, self, true)
		PitBull4:ScheduleTimer(self.UpdateLayout, 2, self, true)
	end
end

function UnitFrame__scripts:OnHide()
	self:GetScript("OnDragStop")(self)

	local force_show = self.force_show
	-- Clear the guid without causing an update unless the frame
	-- is force_shown in which case force an update.
	self:UpdateGUID(nil, force_show and true or false)
	if force_show then
		-- Nothing more to do the frame isn't really being hidden
		return
	end

	-- Iterate the modules and call their OnHide function to tell them
	-- a frame was hidden.  They may very well be changing the frame and
	-- causing layout changes.  However, since the frame is hidden we
	-- do not track this or cause layout updates to happen.  They'll
	-- happen when the frame is shown again anyway.  Skip calling OnHide
	-- when dont_update is set becuase we're only temporarily hiding the
	-- frame for RefreshGroup().
	if not self.dont_update then
		for _, module_type in ipairs(MODULE_UPDATE_ORDER) do
			for _, module in PitBull4:IterateModulesOfType(module_type) do
				module:OnHide(self)
			end
		end
	end
end

-- Ugly hack function to allow running RegisterForClicks in cata.
-- This function is currently missing from the RestrictedFrames environment.
-- Frames created in combat won't have the ability to use the right click
-- menu on them until you leave combat the next time when this function runs.
local function register_for_clicks_helper(frame, clicks)
	frame:RegisterForClicks(clicks)
end
register_for_clicks_helper = PitBull4:OutOfCombatWrapper(register_for_clicks_helper)

-- SecureGroupHeader children can be created while reloading the UI during an
-- existing encounter. Blizzard briefly loads the UI before combat lockdown is
-- re-applied, so perform the normal clamp immediately whenever lockdown is not
-- active. Only children genuinely created after lockdown has resumed are queued
-- for the first safe out-of-combat update.
local lorenzo_pending_member_clamps = setmetatable({}, { __mode = "k" })

local function lorenzo_apply_member_clamp(frame)
	lorenzo_pending_member_clamps[frame] = nil
	if frame and frame.SetClampedToScreen and not InCombatLockdown() then
		frame:SetClampedToScreen(true)
	end
end

local function lorenzo_initialize_member_clamp(frame)
	if not InCombatLockdown() then
		frame:SetClampedToScreen(true)
		return
	end

	if lorenzo_pending_member_clamps[frame] then
		return
	end

	lorenzo_pending_member_clamps[frame] = true
	PitBull4:RunOnLeaveCombat(lorenzo_apply_member_clamp, frame)
end

--- Add the proper functions and scripts to a SecureUnitButton, as well as some various initialization.
-- @param frame a Button which inherits from SecureUnitButton
-- @param isExampleFrame whether the button is an example frame, thus not a real unit frame
-- @usage PitBull4:ConvertIntoUnitFrame(frame)
function PitBull4:ConvertIntoUnitFrame(frame, isExampleFrame)
	if DEBUG then
		expect(frame, 'typeof', 'frame')
		expect(frame, 'frametype', 'Button')
		expect(isExampleFrame, 'typeof', 'nil;boolean')
	end

	self.all_frames[frame] = true
	table.insert(self.all_frames_list, frame)

	self.classification_to_frames[frame.classification][frame] = true

	if frame.is_wacky then
		self.wacky_frames[frame] = true
		PitBull4.num_wacky_frames = PitBull4.num_wacky_frames + 1
	else
		self.non_wacky_frames[frame] = true
	end

	if frame.is_singleton then
		self.singleton_frames[frame] = true
	else
		self.member_frames[frame] = true
	end

	local overlay = PitBull4.Controls.MakeFrame(frame)
	frame.overlay = overlay
	overlay:SetFrameLevel(frame:GetFrameLevel() + 17)

	for k, v in pairs(UnitFrame__scripts) do
		frame:HookScript(k, v)
	end

	for k, v in pairs(frame.is_singleton and SingletonUnitFrame__scripts or MemberUnitFrame__scripts) do
		frame:HookScript(k, v)
	end

	for k, v in pairs(UnitFrame) do
		frame[k] = v
	end

	for k, v in pairs(frame.is_singleton and SingletonUnitFrame or MemberUnitFrame) do
		frame[k] = v
	end

	if not isExampleFrame then
		if frame:CanChangeAttribute() then
			frame:SetAttribute("*type1", "target")
			frame:SetAttribute("*type2", "togglemenu")
			if frame.is_singleton then
				frame:SetMovable(true)
			end
			frame:RegisterForDrag("LeftButton")
			frame:RegisterForClicks("AnyUp")
		elseif not ClickCastHeader then
			-- if we can't set attributes directly and Clique isn't running
			-- then RegisterForClicks upon leaving combat.  Works around
			-- the lack of RegisterForClicks in the RestrictedFrames environment
			-- for cata.
			register_for_clicks_helper(frame, "AnyUp")
		end
	end
	frame:RefreshVehicle()

	if frame.is_singleton or isExampleFrame then
		frame:SetClampedToScreen(true)
	else
		-- During an in-combat UI reload this normally still executes in the short
		-- pre-lockdown loading window. Frames created later in the encounter are
		-- safely completed after combat instead of issuing a protected call.
		lorenzo_initialize_member_clamp(frame)
	end

	if frame.is_singleton then
		if not frame.classification_db.click_through then
			-- Only enable click casting if the frame isn't click_through.
			_G.ClickCastFrames[frame] = true
		end
	else
		if not ClickCastHeader then
			-- member unit frames are handled differently in cata.
			-- See the initialConfigFunction attribute on the GroupHeader.
			_G.ClickCastFrames[frame] = true
		end
	end
end

-- we store layout_db instead of layout, since if a new profile comes up, it'll be a distinct table
local seen_layout_dbs = setmetatable({}, {__mode='k'})
PitBull4.seen_layout_dbs = seen_layout_dbs

--- Reheck the toggleForVehicle attribute for the unit frame
-- @usage frame:RefreshVehicle()
function UnitFrame:RefreshVehicle()
	local classification_db = self.classification_db
	if not classification_db then
		return
	end

	local config_value = classification_db.vehicle_swap
	if self:CanChangeAttribute() then
		self:SetAttribute("pb4-vehicleswap", config_value)
		if self:ProxySetAttribute("toggleForVehicle", config_value) and self.unit then
			PitBull4:UNIT_ENTERED_VEHICLE(nil, self.unit)
		end
	end
end

--- Recheck the layout of the unit frame, make sure it's up to date, and update the frame.
-- @usage frame:RefreshLayout()
function UnitFrame:_RefreshLayout()
	local old_layout = self.layout

	local classification_db = self.classification_db
	if not classification_db then
		return
	end

	local layout = classification_db.layout
	self.layout = layout
	self.layout_db = PitBull4.db.profile.layouts[layout]
	if not seen_layout_dbs[self.layout_db] then
		seen_layout_dbs[self.layout_db] = true
		PitBull4:CallMethodOnModules("OnNewLayout", layout)
	end

	self:SetClickThroughState(classification_db.click_through)

	self:RefixSizeAndPosition()
	self:UpdateConfigAnchorLine()

	if old_layout then
		self:Update(true, true)
	end
end
UnitFrame.RefreshLayout = PitBull4:OutOfCombatWrapper(UnitFrame._RefreshLayout)

-- Set the frame as able to be clicked through or not.
-- @usage frame:SetClickThroughState(true)
function SingletonUnitFrame:SetClickThroughState(state)
	local mouse_state = not not self:IsMouseEnabled()
	if (not state) ~= mouse_state then
		_G.ClickCastFrames[self] = not mouse_state
		self:EnableMouse(not mouse_state)
		self:SetAttribute("ping-receiver", not mouse_state or nil)
	end
end
SingletonUnitFrame.SetClickThroughState= PitBull4:OutOfCombatWrapper(SingletonUnitFrame.SetClickThroughState)

--- Reset the size and position of the unit frame.
-- @usage frame:RefixSizeAndPosition()
function SingletonUnitFrame:RefixSizeAndPosition()
	local layout_db = self.layout_db
	local classification_db = self.classification_db

	self:SetWidth(layout_db.size_x * classification_db.size_x)
	self:SetHeight(layout_db.size_y * classification_db.size_y)
	self:SetScale(layout_db.scale * classification_db.scale)
	self:SetFrameStrata(layout_db.strata)
	self:SetFrameLevel(layout_db.level)

	-- Check if the frame we will be anchoring to exists and if not
	-- delay setting the anchor until it does.
	local rel_to = classification_db.relative_to
	local rel_frame, rel_type = PitBull4.Utils.GetRelativeFrame(rel_to)
	if not rel_frame then
		frames_to_anchor[self] = rel_to
		if rel_type == "~" then
			PitBull4.anchor_timer:Show()
		end
		return
	else
		frames_to_anchor[self] = nil
	end

	local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
	self:ClearAllPoints()
	if rel_type == "f" then
		rel_frame:AnchorFrameToFirstUnit(self, classification_db.anchor, classification_db.relative_point, classification_db.position_x / scale, classification_db.position_y / scale)
	else
		self:SetPoint(classification_db.anchor, rel_frame, classification_db.relative_point, classification_db.position_x / scale, classification_db.position_y / scale)
	end
end
SingletonUnitFrame.RefixSizeAndPosition = PitBull4:OutOfCombatWrapper(SingletonUnitFrame.RefixSizeAndPosition)

--- Activate the unit frame.
-- This handles UnitWatch and the custom StateDriver
-- @usage frame:Activate()
function SingletonUnitFrame:Activate()
	RegisterUnitWatch(self, true)
	-- A previously deactivated singleton can remain hidden after UnitWatch
	-- is registered again. Restore it only when its real unit exists.
	if self.lorenzo_deactivated and self.classification_db and self.classification_db.enabled then
		self.lorenzo_deactivated = nil
		if not self.force_show and UnitExists(self.classification_db.unit) then
			self:Show()
		end
	end
	if PitBull4.secure_snippets_available then
		RegisterAttributeDriver(self, "state-pb4visibility", "[petbattle] hide; default")
	end
end
SingletonUnitFrame.Activate = PitBull4:OutOfCombatWrapper(SingletonUnitFrame.Activate)

--- Deactivate the unit frame.
-- This handles UnitWatch and the custom StateDriver
-- @usage frame:Deactivate()
function SingletonUnitFrame:Deactivate()
	self.lorenzo_deactivated = true
	UnregisterUnitWatch(self)
	if PitBull4.secure_snippets_available then
		UnregisterAttributeDriver(self, "state-pb4visibility")
		self:SetAttribute("state-pb4visibility", nil)
		self:SetAttribute("state-unitexists", nil)
	end
	self:Hide()
end
SingletonUnitFrame.Deactivate = PitBull4:OutOfCombatWrapper(SingletonUnitFrame.Deactivate)

function SingletonUnitFrame:ForceShow()
	if not self.force_show then
		self.force_show = true
		-- Forever 009: UnitWatch can re-hide a force-shown unit that does not
		-- actually exist (most visibly Player's pet) as soon as a drag/layout
		-- update occurs. Suspend UnitWatch for config mode on both healthy and
		-- degraded secure runtimes; config_mode/Show remains responsible for the
		-- preview until config mode ends.
		UnregisterUnitWatch(self)
		self.lorenzo_unitwatch_suspended_for_config = true
		if PitBull4.secure_snippets_available then
			self:SetAttribute("config_mode", true)
		else
			self:Show()
		end
	end
	-- Forever 034: ForceShow is idempotent. A protected/unit-watch transition can
	-- hide an already force-shown singleton; config mode must restore it even when
	-- force_show was already set on a previous pass.
	self:Show()
end
SingletonUnitFrame.ForceShow = PitBull4:OutOfCombatWrapper(SingletonUnitFrame.ForceShow)

-- Restore the live visibility lifecycle after a forced config preview.
-- Do not rely on RegisterUnitWatch immediately firing a new state transition:
-- if no target existed when the preview ended, the prior hidden state can
-- persist until another visibility event. Reconcile with the current unit.
function SingletonUnitFrame:UnforceShow()
	if not self.force_show and not self.lorenzo_unitwatch_suspended_for_config then
		return
	end
	self.force_show = nil
	if PitBull4.secure_snippets_available then
		self:SetAttribute("config_mode", nil)
	end
	if self.lorenzo_unitwatch_suspended_for_config then
		self.lorenzo_unitwatch_suspended_for_config = nil
		if self.classification_db and self.classification_db.enabled then
			RegisterUnitWatch(self, true)
		end
	end

	-- Do not manually Show/Hide here: that can leave a forced preview's
	-- visibility out of sync with UnitWatch, particularly when exiting
	-- config mode without a target. Re-arm the native watch so subsequent
	-- unit acquisition drives visibility through the secure system.
	local unit = self.classification_db and self.classification_db.unit
	if self.classification_db and self.classification_db.enabled and unit then
		self:ProxySetAttribute("unit", unit)
		UnregisterUnitWatch(self)
		RegisterUnitWatch(self, true)
		self:UpdateGUID(UnitGUID(unit))
	elseif not (self.classification_db and self.classification_db.enabled) then
		UnregisterUnitWatch(self)
		self:Hide()
	end
end
SingletonUnitFrame.UnforceShow = PitBull4:OutOfCombatWrapper(SingletonUnitFrame.UnforceShow)

function UnitFrame:RecheckConfigMode()
	if PitBull4.config_mode and self.classification_db.enabled then
		self:ForceShow()
	else
		self:UnforceShow()
	end
	self:Update(true, true)
	self:UpdateConfigAnchorLine()
end

--- Visually show a line connecting anchored frames
function UnitFrame:UpdateConfigAnchorLine()
	if not self.is_singleton then return end
	local db = self.classification_db
	if not self.force_show or not db then
		if self.anchor_line then
			self.anchor_line:Hide()
		end
		return
	end

	local relative_frame, relative_type = PitBull4.Utils.GetRelativeFrame(db.relative_to)
	if relative_type ~= "0" then -- UIParent
		if not self.anchor_line then
			local line = self:CreateLine(nil, "BACKGROUND", nil, -2)
			line:SetThickness(4)
			line:SetTexture([[Interface/Artifacts/_Artifacts-DependencyBar-Fill]])
			line:SetHorizTile(true)
			line:SetIgnoreParentAlpha(true)
			line:SetIgnoreParentScale(true)
			self.anchor_line = line
		end
		-- Forever 034: the config helper line is cosmetic. On the degraded secure
		-- runtime, making a Line depend on another protected singleton can be
		-- rejected by the restricted frame system. Skip only that visual helper.
		local protected_relative = PitBull4.secure_group_headers_degraded and relative_frame and relative_frame.IsProtected and relative_frame:IsProtected()
		if protected_relative then
			self.anchor_line:Hide()
		else
			self.anchor_line:SetStartPoint(db.anchor, self)
			self.anchor_line:SetEndPoint(db.relative_point, relative_frame)
			self.anchor_line:Show()
		end
	elseif self.anchor_line then
		self.anchor_line:Hide()
	end
end
UnitFrame.UpdateConfigAnchorLine = PitBull4:OutOfCombatWrapper(UnitFrame.UpdateConfigAnchorLine)

function UnitFrame:Rename(name)
	local old_name = self.classification
	if old_name == name then
		return
	end

	-- Look for groups and units that are anchored to this frame and update their
	-- relative_to reference, there is no need to actually update the anchors
	-- because the frame will already be anchored properly and changing the
	-- name won't break the anchor.
	for group, group_db in pairs(PitBull4.db.profile.groups) do
		local rel_to = group_db.relative_to
		local rel_type = rel_to:sub(1,1)
		if rel_type == "S" then
			local rel_name = rel_to:sub(2)
			if rel_name == old_name then
				group_db.relative_to = rel_type .. name
			end
		end
	end
	for unit, unit_db in pairs(PitBull4.db.profile.units) do
		local rel_to = unit_db.relative_to
		local rel_type = rel_to:sub(1,1)
		if rel_type == "S" then
			local rel_name = rel_to:sub(2)
			if rel_name == old_name then
				unit_db.relative_to = rel_type .. name
			end
		end
	end

	local old_frame_name = "PitBull4_Frames_" .. old_name
	local new_frame_name = "PitBull4_Frames_" .. name

	PitBull4.classification_to_frames[old_name][self] = nil
	PitBull4.classification_to_frames[name][self] = true
	_G[old_frame_name] = nil
	_G[new_frame_name] = self
	self.classification = name
end

local LibSharedMedia = LibStub("LibSharedMedia-3.0", true)
local DEFAULT_FONT, DEFAULT_FONT_SIZE = ChatFontNormal:GetFont()

--- Get the font of the unit frame.
-- @param font_override nil or the LibSharedMedia name of a font
-- @param size_multiplier how much to multiply the default font size by. Defaults to 1.
-- @return path to the font
-- @return size of the font
-- @usage local font, size = frame:GetFont(db.font, db.size)
-- frame.MyModule:SetFont(font, size)
function UnitFrame:GetFont(font_override, size_multiplier)
	-- Profile changes can briefly leave group frames with an incomplete
	-- layout table (e.g. { exists = true }). Never abort frame updates.
	local layout_db = self.layout_db or {}
	local classification_db = self.classification_db or {}
	local font
	if LibSharedMedia then
		font = LibSharedMedia:Fetch("font", font_override or layout_db.font or "")
	end
	local layout_size = type(layout_db.font_size) == "number" and layout_db.font_size or 1
	local classification_size = type(classification_db.font_multiplier) == "number" and classification_db.font_multiplier or 1
	local multiplier = type(size_multiplier) == "number" and size_multiplier or 1
	return font or DEFAULT_FONT, (DEFAULT_FONT_SIZE or 14) * layout_size * multiplier * classification_size
end

--- Update all details about the UnitFrame, possibly after a GUID change
-- @param same_guid whether the previous GUID is the same as the current, at which point is less crucial to update
-- @param update_layout whether to update the layout no matter what
-- @usage frame:Update()
-- @usage frame:Update(true)
-- @usage frame:Update(false, true)
function UnitFrame:Update(same_guid, update_layout)
	if self.dont_update then
		return
	end

	local classification_db = self.classification_db
	if not classification_db or not self.layout_db then
		-- Possibly unused frame made for another profile
		return
	end

	-- Update the unit if it changed, only applicable to singleton units,
	-- member units don't have a configured unit but a unit_group and
	-- the unit is set by the SecureGroupHeaderTemplate instead.
	if self.is_singleton then
		self:ProxySetAttribute("unit", classification_db.unit)
	end

	if self.guid == nil and not self.force_show then
		if self.populated then
			self.populated = nil

			for _, module in PitBull4:IterateEnabledModules() do
				module:Clear(self)
			end
		end
		return
	end
	self.populated = true

	local changed = update_layout
	for _, module_type in ipairs(MODULE_UPDATE_ORDER) do
		for _, module in PitBull4:IterateModulesOfType(module_type) do
			changed = module:Update(self, true, same_guid) or changed
		end
	end

	if changed then
		self:UpdateLayout(false)
	end
end

--- Check the guid of the Unit Frame, if it is changed, then update the frame.
-- @param guid result from UnitGUID(unit)
-- @param update when true force an update even if the guid isn't changed, but is non-nil, when false never cause an update and when update is empty or nil let the function decide on its own if an update is needed.
-- @usage frame:UpdateGUID(UnitGUID(frame.unit))
-- @usage frame:UpdateGUID(UnitGUID(frame.unit), true)
function UnitFrame:UpdateGUID(guid, update)
	-- if DEBUG then
	-- 	expect(guid, 'typeof', 'string;nil')
	-- end

	-- if the guids are the same, cut out, but don't if it's a wacky unit that has a guid.
	if update ~= true and not issecretvalue(guid) and not issecretvalue(self.guid) and self.guid == guid and not (guid and self.is_wacky) then
		return
	end
	local old_guid = self.guid
	self.guid = guid
	if update ~= false then
		if issecretvalue(guid) or issecretvalue(old_guid) then
			self:Update(not self.is_wacky)
		else
			self:Update(old_guid == guid)
		end
	end
end

local function iter(frame, id)
	local func, t = PitBull4:IterateEnabledModules()
	local module
	id, module = func(t, id)
	if id == nil then
		return nil
	end
	if not frame[id] then
		return iter(frame, id)
	end
	return id, frame[id], module
end

--- Iterate over all controls on this frame
-- @usage for id, control, module in PitBull4.IterateControls() do
--     doSomethingWith(control)
-- end
-- @return iterator which returns the id, control, and module
function UnitFrame:IterateControls()
	return iter, self, nil
end

local iters = setmetatable({}, {__index=function(iters, module_type)
	local function iter(frame, id)
		local func, t = PitBull4:IterateModulesOfType(module_type)
		local module
		id, module = func(t, id)
		if id == nil then
			return nil
		end
		if not frame[id] then
			return iter(frame, id)
		end
		return id, frame[id], module
	end
	iters[module_type] = iter
	return iter
end})

--- Iterate over all controls on this frame of the given type
-- @param module_type one of "bar", "indicator", "custom"
-- @usage for id, control, module in PitBull4.IterateControlsOfType("bar") do
--     doSomethingWith(control)
-- end
-- @return iterator which returns the id, control, and module
function UnitFrame:IterateControlsOfType(module_type)
	return iters[module_type], self, nil
end
