
local PitBull4 = _G.PitBull4
local L = PitBull4.L

-- Forever: fail closed if a unit API returns a secret or unknown value.
local function safe_unit_boolean(api, unit)
    if type(api) ~= "function" then return nil end
    local ok, value = pcall(api, unit)
    if not ok or type(value) ~= "boolean" then return nil end
    if type(_G.issecretvalue) == "function" then
        local safe, secret = pcall(_G.issecretvalue, value)
        if not safe or secret ~= false then return nil end
    end
    return value
end


local PitBull4_Background = PitBull4:NewModule("Background")

local WORLD_MODEL_RETRY_DELAYS = { 0.2, 0.8, 2, 5 }

local function safe_debug_value(value)
	if issecretvalue(value) then
		return "<secret>"
	end
	local ok, text = pcall(tostring, value)
	return ok and text or "<error>"
end

local function debug_background_portrait(message)
	local aura_module = PitBull4:GetModule("Aura", true)
	if aura_module and aura_module.LorenzoPatch107DebugLine then
		aura_module:LorenzoPatch107DebugLine("background-portrait " .. message)
	end
end

local function model_ready(model)
	if not model or not model.GetModelFileID then
		return nil
	end
	local ok, file_id = pcall(model.GetModelFileID, model)
	if not ok or issecretvalue(file_id) then
		return nil
	end
	if file_id == nil then
		return nil
	end
	return file_id ~= 0
end

local function mark_frame_for_model_refresh(frame, reason, final_attempt)
	local portrait = frame and frame.PortraitBG
	if not portrait then
		return false
	end
	portrait.force_model_update = true
	portrait.model_refresh_pending = true
	portrait.model_refresh_reason = reason
	portrait.model_refresh_final_attempt = final_attempt or nil
	return true
end

PitBull4_Background:SetModuleType("custom")
PitBull4_Background:SetName(L["Background"])
PitBull4_Background:SetDescription(L["Show a flat background for your unit frames."])
PitBull4_Background:SetDefaults({
	portrait = false,
	fallback_style = "three_dimensional",
	color = { 0, 0, 0, 0.5 }
})

function PitBull4_Background:OnEnable()
	self:RegisterEvent("UNIT_PORTRAIT_UPDATE")
	self:RegisterEvent("UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self.lorenzo_model_refresh_generation = 0
	self.lorenzo_unit_retry_tokens = {}
	self.lorenzo_unit_retry_throttle = {}
end

function PitBull4_Background:MarkUnit3DModelsForRefresh(unit, reason, final_attempt)
	local marked = 0
	for frame in PitBull4:IterateFrames() do
		if frame.unit == unit and mark_frame_for_model_refresh(frame, reason, final_attempt) then
			marked = marked + 1
		end
	end
	return marked
end

function PitBull4_Background:RetryUnit3DModels(unit, token, final_attempt)
	if not unit or self.lorenzo_unit_retry_tokens[unit] ~= token then
		return
	end
	local marked = self:MarkUnit3DModelsForRefresh(unit, "unit-event-retry", final_attempt)
	if marked > 0 then
		self:UpdateForUnitID(unit)
	end
end

function PitBull4_Background:ScheduleUnit3DModelRetries(unit)
	if not self.ScheduleTimer or not unit then
		return
	end
	local now = GetTime()
	local next_allowed = self.lorenzo_unit_retry_throttle[unit]
	if next_allowed and now < next_allowed then
		return
	end
	self.lorenzo_unit_retry_throttle[unit] = now + 0.75
	local token = (self.lorenzo_unit_retry_tokens[unit] or 0) + 1
	self.lorenzo_unit_retry_tokens[unit] = token
	self:ScheduleTimer("RetryUnit3DModels", 0.25, unit, token, false)
	self:ScheduleTimer("RetryUnit3DModels", 1.0, unit, token, true)
end

function PitBull4_Background:UNIT_PORTRAIT_UPDATE(_, unit)
	if not unit then
		return
	end
	local marked = self:MarkUnit3DModelsForRefresh(unit, "unit-model-event", false)
	if marked > 0 then
		self:UpdateForUnitID(unit)
		self:ScheduleUnit3DModelRetries(unit)
	else
		self:UpdateForUnitID(unit)
	end
end

function PitBull4_Background:DelayedWorldModelRefresh(generation, delay, final_attempt)
	if generation ~= self.lorenzo_model_refresh_generation then
		return
	end
	self:ForceRefresh3DModels("enter-world+" .. safe_debug_value(delay) .. "s", final_attempt, false)
end

function PitBull4_Background:PLAYER_ENTERING_WORLD()
	self.lorenzo_model_refresh_generation = self.lorenzo_model_refresh_generation + 1
	local generation = self.lorenzo_model_refresh_generation
	self:ForceRefresh3DModels("enter-world", false, false)
	if self.ScheduleTimer then
		for index, delay in ipairs(WORLD_MODEL_RETRY_DELAYS) do
			self:ScheduleTimer("DelayedWorldModelRefresh", delay, generation, delay, index == #WORLD_MODEL_RETRY_DELAYS)
		end
	end
end

function PitBull4_Background:PLAYER_REGEN_ENABLED()
	self:ForceRefresh3DModels("combat-ended", true, true)
end

function PitBull4_Background:ForceRefresh3DModels(reason, final_attempt, only_pending)
	local marked = 0
	for frame in PitBull4:IterateFrames() do
		local portrait = frame.PortraitBG
		if portrait and (not only_pending or portrait.model_refresh_pending) then
			if mark_frame_for_model_refresh(frame, reason, final_attempt) then
				marked = marked + 1
			end
		end
	end
	if marked > 0 then
		self:UpdateAll()
	end
	debug_background_portrait("refresh reason=" .. safe_debug_value(reason) .. " marked=" .. marked .. " final=" .. safe_debug_value(final_attempt) .. " pendingOnly=" .. safe_debug_value(only_pending))
end

function PitBull4_Background:LorenzoPatch107DebugSnapshot(reason)
	local printed = 0
	for frame in PitBull4:IterateFrames() do
		local portrait = frame.PortraitBG
		if portrait then
			printed = printed + 1
			local frame_name = frame.GetName and frame:GetName() or "<unnamed>"
			debug_background_portrait(
				"snapshot reason=" .. safe_debug_value(reason) ..
				" frame=" .. safe_debug_value(frame_name) ..
				" unit=" .. safe_debug_value(frame.unit) ..
				" ready=" .. safe_debug_value(model_ready(portrait)) ..
				" pending=" .. safe_debug_value(portrait.model_refresh_pending) ..
				" lastReason=" .. safe_debug_value(portrait.model_refresh_reason)
			)
		end
	end
	debug_background_portrait("snapshot-summary reason=" .. safe_debug_value(reason) .. " models=" .. printed)
end

-- this is here to allow it to be overridden, e.g., aggro module
function PitBull4_Background:GetColor(frame)
	return unpack(PitBull4_Background:GetLayoutDB(frame).color)
end

function PitBull4_Background:UpdateFrame(frame)
	local background = frame.Background
	if not background then
		background = PitBull4.Controls.MakeTexture(frame, "BACKGROUND")
		frame.Background = background
		background:SetAllPoints(frame)
	end

	local r, g, b, a = self:GetColor(frame)
	if r and g and b then
		background:SetColorTexture(r, g, b, a)
		background:Show()
	else
		background:Hide()
	end

	-- 3D Portrait
	local layout_db = self:GetLayoutDB(frame)
	if not layout_db.portrait then
		return false
	end

	local unit = frame.unit
	local falling_back = false
	if not unit or (safe_unit_boolean(UnitExists, unit) ~= true and not ShowBossFrameWhenUninteractable(unit)) or safe_unit_boolean(UnitIsConnected, unit) ~= true or safe_unit_boolean(UnitIsVisible, unit) ~= true then
		falling_back = true
	end

	local portrait = frame.PortraitBG
	local created = not portrait
	if created then
		portrait = PitBull4.Controls.MakePlayerModel(frame)
		portrait:SetFrameLevel(frame:GetFrameLevel()) -- don't go above bars and indicators
		portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
		portrait:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
		portrait.guid = frame.guid
		frame.PortraitBG = portrait
	end

	local should_update = portrait.force_model_update or created or (not issecretvalue(frame.guid) and not issecretvalue(portrait.guid) and portrait.guid ~= frame.guid)
	if should_update then
		local refresh_reason = portrait.model_refresh_reason or (created and "created" or "guid-changed")
		local final_attempt = portrait.model_refresh_final_attempt
		portrait.force_model_update = nil
		portrait.model_refresh_final_attempt = nil
		pcall(portrait.ClearModel, portrait)
		local set_ok = true
		local refresh_ok = true
		if not falling_back then
			set_ok = pcall(portrait.SetUnit, portrait, unit)
			if portrait.RefreshUnit then
				refresh_ok = pcall(portrait.RefreshUnit, portrait)
			end
			pcall(portrait.SetPortraitZoom, portrait, 1)
			pcall(portrait.SetPosition, portrait, 0, 0, 0)
		elseif layout_db.fallback_style == "three_dimensional" then
			pcall(portrait.SetModelScale, portrait, 1)
			set_ok = pcall(portrait.SetModel, portrait, [[Interface\Buttons\talktomequestionmark.m2]])
			pcall(portrait.SetPosition, portrait, -0.55, 0, 0)
		end
		local ready = model_ready(portrait)
		if falling_back or not set_ok or not refresh_ok or ready == false then
			-- Keep one deferred retry while zoning or while combat is active, but do
			-- not leave permanently unavailable/out-of-range models pending forever.
			portrait.model_refresh_pending = (not final_attempt or InCombatLockdown()) and true or nil
		elseif ready == true then
			portrait.model_refresh_pending = nil
		elseif final_attempt then
			portrait.model_refresh_pending = InCombatLockdown() and true or nil
		end
		portrait.guid = frame.guid
		debug_background_portrait(
			"update unit=" .. safe_debug_value(unit) ..
			" reason=" .. safe_debug_value(refresh_reason) ..
			" fallback=" .. safe_debug_value(falling_back) ..
			" setOk=" .. safe_debug_value(set_ok) ..
			" refreshOk=" .. safe_debug_value(refresh_ok) ..
			" ready=" .. safe_debug_value(ready) ..
			" pending=" .. safe_debug_value(portrait.model_refresh_pending)
		)
	end
	portrait:Show()

	return created
end

function PitBull4_Background:ClearFrame(frame)
	if frame.Background then
		frame.Background = frame.Background:Delete()
	end
	if frame.PortraitBG then
		frame.PortraitBG = frame.PortraitBG:Delete()
		return true
	end
	return false
end

function PitBull4_Background:OnHide(frame)
	if frame.Background then
		frame.Background:Hide()
	end
	if frame.PortraitBG then
		frame.PortraitBG:Hide()
	end
end

PitBull4_Background:SetLayoutOptionsFunction(function(self)
	return 'color', {
		type = 'color',
		name = L["Color"],
		desc = L["Color that the background should be."],
		hasAlpha = true,
		get = function(info)
			return unpack(PitBull4.Options.GetLayoutDB(self).color)
		end,
		set = function(info, r, g, b, a)
			local color = PitBull4.Options.GetLayoutDB(self).color
			color[1], color[2], color[3], color[4] = r, g, b, a

			PitBull4.Options.UpdateFrames()
		end,
	}, 'portrait', {
		type = 'toggle',
		name = L["Portrait"],
		desc = L["Show a portrait of the unit."],
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).portrait
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).portrait = value

			for frame in PitBull4:IterateFrames() do
				if self:GetLayoutDB(frame).enabled then
					self:Clear(frame)
					self:Update(frame)
				end
			end
		end,
	}, 'fallback_style', {
		type = 'select',
		name = L["Fallback style"],
		desc = L["Set the portrait style for when the normal style can't be shown, such as if they are out of visibility."],
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).fallback_style
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).fallback_style = value

			for frame in PitBull4:IterateFrames() do
				if self:GetLayoutDB(frame).portrait then
					self:Clear(frame)
					self:Update(frame)
				end
			end
		end,
		values = {
			["three_dimensional"] = L["3D question mark"],
			["blank"] = L["Blank"],
		},
	}
end)
