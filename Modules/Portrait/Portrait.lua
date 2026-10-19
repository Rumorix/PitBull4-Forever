
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


local CLASS_TEX_COORDS = {}
for k, v in pairs(_G.CLASS_ICON_TCOORDS) do
	-- zoom by 14%
	local left, right, top, bottom = unpack(v)
	left, right = left + (right - left) * 0.07, right - (right - left) * 0.07
	top, bottom = top + (bottom - top) * 0.07, bottom - (bottom - top) * 0.07
	CLASS_TEX_COORDS[k] = { left, right, top, bottom }
end

local PitBull4_Portrait = PitBull4:NewModule("Portrait")

-- PlayerModel data can arrive after the unit frame itself when zoning into an
-- instance. Refreshes are event-driven and bounded; there is no permanent
-- OnUpdate polling.
local WORLD_MODEL_RETRY_DELAYS = { 0.2, 0.8, 2, 5 }

local function safe_debug_value(value)
	if issecretvalue(value) then
		return "<secret>"
	end
	local ok, text = pcall(tostring, value)
	return ok and text or "<error>"
end

local function safe_method(object, method_name, ...)
	if not object then
		return nil
	end
	local method = object[method_name]
	if type(method) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e = pcall(method, object, ...)
	if not ok then
		return "<error>"
	end
	return a, b, c, d, e
end

local function safe_region_name(region)
	if not region then
		return "nil"
	end
	local name = safe_method(region, "GetName")
	if name then
		return safe_debug_value(name)
	end
	return safe_debug_value(region)
end

local function debug_portrait(message)
	local aura_module = PitBull4:GetModule("Aura", true)
	if aura_module and aura_module.LorenzoPatch107DebugLine then
		aura_module:LorenzoPatch107DebugLine("portrait " .. message)
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
	local portrait = frame and frame.Portrait
	if not portrait or not portrait.model then
		return false
	end
	portrait.force_model_update = true
	portrait.model_refresh_pending = true
	portrait.model_refresh_reason = reason
	portrait.model_refresh_final_attempt = final_attempt or nil
	return true
end

PitBull4_Portrait:SetModuleType("indicator")
PitBull4_Portrait:SetName(L["Portrait"])
PitBull4_Portrait:SetDescription(L["Show a portrait of the unit."])
PitBull4_Portrait:SetDefaults({
	color = { 0, 0, 0, 0.25 },
	attach_to = "root",
	location = "out_left",
	position = 1,
	full_body = false,
	camera_distance = 1,
	style = "three_dimensional",
	fallback_style = "three_dimensional",
	side = "left",
	bar_size = 4,
	enabled = false,
})
PitBull4_Portrait.can_set_side_to_center = true

function PitBull4_Portrait:OnEnable()
	self:RegisterEvent("UNIT_PORTRAIT_UPDATE")
	self:RegisterEvent("UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("PLAYER_FOCUS_CHANGED")
	self.lorenzo_model_refresh_generation = 0
	self.lorenzo_unit_retry_tokens = {}
	self.lorenzo_unit_retry_throttle = {}
	self.lorenzo_classification_retry_tokens = {}
	self.lorenzo_classification_retry_throttle = {}
end

function PitBull4_Portrait:MarkUnit3DModelsForRefresh(unit, reason, final_attempt)
	local marked = 0
	for frame in PitBull4:IterateFrames() do
		if frame.unit == unit and mark_frame_for_model_refresh(frame, reason, final_attempt) then
			marked = marked + 1
		end
	end
	return marked
end

function PitBull4_Portrait:RetryUnit3DModels(unit, token, final_attempt)
	if not unit or self.lorenzo_unit_retry_tokens[unit] ~= token then
		return
	end
	local marked = self:MarkUnit3DModelsForRefresh(unit, "unit-event-retry", final_attempt)
	if marked > 0 then
		self:UpdateForUnitID(unit)
	end
end

function PitBull4_Portrait:ScheduleUnit3DModelRetries(unit)
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

function PitBull4_Portrait:UNIT_PORTRAIT_UPDATE(_, unit)
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

-- Target and focus frames can already exist in their fallback state before a
-- real unit becomes available.  Refresh only the canonical classification that
-- received the event.  Updating every singleton that happens to use the same
-- UnitID can wake a second custom target frame and make two 3D models overlap.
function PitBull4_Portrait:MarkClassification3DModelsForRefresh(classification, reason, final_attempt)
	local marked = 0
	for frame in PitBull4:IterateFramesForClassification(classification, true) do
		if mark_frame_for_model_refresh(frame, reason, final_attempt) then
			marked = marked + 1
		end
	end
	return marked
end

function PitBull4_Portrait:UpdateClassification3DModels(classification)
	for frame in PitBull4:IterateFramesForClassification(classification, true) do
		if frame.Portrait and frame.Portrait.model then
			self:Update(frame)
		end
	end
end

function PitBull4_Portrait:RetryClassification3DModels(classification, token, final_attempt)
	if not classification or self.lorenzo_classification_retry_tokens[classification] ~= token then
		return
	end
	local marked = self:MarkClassification3DModelsForRefresh(classification, "classification-event-retry", final_attempt)
	if marked > 0 then
		self:UpdateClassification3DModels(classification)
	end
end

function PitBull4_Portrait:ScheduleClassification3DModelRetries(classification)
	if not self.ScheduleTimer or not classification then
		return
	end
	local now = GetTime()
	local next_allowed = self.lorenzo_classification_retry_throttle[classification]
	if next_allowed and now < next_allowed then
		return
	end
	self.lorenzo_classification_retry_throttle[classification] = now + 0.75
	local token = (self.lorenzo_classification_retry_tokens[classification] or 0) + 1
	self.lorenzo_classification_retry_tokens[classification] = token
	self:ScheduleTimer("RetryClassification3DModels", 0.25, classification, token, false)
	self:ScheduleTimer("RetryClassification3DModels", 1.0, classification, token, true)
end

function PitBull4_Portrait:RefreshDynamic3DClassification(classification, reason)
	if not classification then
		return
	end
	local marked = self:MarkClassification3DModelsForRefresh(classification, reason, false)
	if marked > 0 then
		self:UpdateClassification3DModels(classification)
	end
	self:ScheduleClassification3DModelRetries(classification)
end

function PitBull4_Portrait:PLAYER_TARGET_CHANGED()
	self:RefreshDynamic3DClassification("Target", "player-target-changed")
end

function PitBull4_Portrait:PLAYER_FOCUS_CHANGED()
	self:RefreshDynamic3DClassification("Focus", "player-focus-changed")
end

function PitBull4_Portrait:DelayedWorldModelRefresh(generation, delay, final_attempt)
	if generation ~= self.lorenzo_model_refresh_generation then
		return
	end
	self:ForceRefresh3DModels("enter-world+" .. safe_debug_value(delay) .. "s", final_attempt, false)
end

function PitBull4_Portrait:PLAYER_ENTERING_WORLD()
	self.lorenzo_model_refresh_generation = self.lorenzo_model_refresh_generation + 1
	local generation = self.lorenzo_model_refresh_generation
	self:ForceRefresh3DModels("enter-world", false, false)
	if self.ScheduleTimer then
		for index, delay in ipairs(WORLD_MODEL_RETRY_DELAYS) do
			self:ScheduleTimer("DelayedWorldModelRefresh", delay, generation, delay, index == #WORLD_MODEL_RETRY_DELAYS)
		end
	end
end

function PitBull4_Portrait:PLAYER_REGEN_ENABLED()
	self:ForceRefresh3DModels("combat-ended", true, true)
end

function PitBull4_Portrait:ForceRefresh3DModels(reason, final_attempt, only_pending)
	local marked = 0
	for frame in PitBull4:IterateFrames() do
		local portrait = frame.Portrait
		if portrait and portrait.model and (not only_pending or portrait.model_refresh_pending) then
			if mark_frame_for_model_refresh(frame, reason, final_attempt) then
				marked = marked + 1
			end
		end
	end
	if marked > 0 then
		self:UpdateAll()
	end
	debug_portrait("refresh reason=" .. safe_debug_value(reason) .. " marked=" .. marked .. " final=" .. safe_debug_value(final_attempt) .. " pendingOnly=" .. safe_debug_value(only_pending))
end

function PitBull4_Portrait:LorenzoPatch107DebugSnapshot(reason)
	local printed = 0
	local member_frames = 0
	local singleton_units = {}

	-- Include hidden frames as well.  A missing party frame is precisely the case
	-- where the normal shown-frame iterator would omit the most useful evidence.
	for frame in PitBull4:IterateFrames(true) do
		local portrait = frame.Portrait
		if portrait and portrait.model then
			printed = printed + 1
			if not frame.is_singleton then
				member_frames = member_frames + 1
			end

			local frame_name = safe_region_name(frame)
			local parent = safe_method(frame, "GetParent")
			local header = frame.header
			local point, relative_to, relative_point, x, y = safe_method(frame, "GetPoint", 1)
			local shown = safe_method(frame, "IsShown")
			local visible = safe_method(frame, "IsVisible")
			local alpha = safe_method(frame, "GetAlpha")
			local effective_alpha = safe_method(frame, "GetEffectiveAlpha")
			local width = safe_method(frame, "GetWidth")
			local height = safe_method(frame, "GetHeight")
			local protected = safe_method(frame, "IsProtected")
			local header_shown = safe_method(header, "IsShown")
			local header_visible = safe_method(header, "IsVisible")
			local header_alpha = safe_method(header, "GetAlpha")

			debug_portrait(
				"snapshot reason=" .. safe_debug_value(reason) ..
					" frame=" .. frame_name ..
					" classification=" .. safe_debug_value(frame.classification) ..
					" unit=" .. safe_debug_value(frame.unit) ..
					" singleton=" .. safe_debug_value(frame.is_singleton) ..
					" shown=" .. safe_debug_value(shown) ..
					" visible=" .. safe_debug_value(visible) ..
					" alpha=" .. safe_debug_value(alpha) ..
					" effectiveAlpha=" .. safe_debug_value(effective_alpha) ..
					" size=" .. safe_debug_value(width) .. "x" .. safe_debug_value(height) ..
					" point=" .. safe_debug_value(point) ..
					" relativeTo=" .. safe_region_name(relative_to) ..
					" relativePoint=" .. safe_debug_value(relative_point) ..
					" offset=" .. safe_debug_value(x) .. "," .. safe_debug_value(y) ..
					" parent=" .. safe_region_name(parent) ..
					" header=" .. safe_region_name(header) ..
					" headerShown=" .. safe_debug_value(header_shown) ..
					" headerVisible=" .. safe_debug_value(header_visible) ..
					" headerAlpha=" .. safe_debug_value(header_alpha) ..
					" protected=" .. safe_debug_value(protected) ..
					" ready=" .. safe_debug_value(model_ready(portrait.model)) ..
					" pending=" .. safe_debug_value(portrait.model_refresh_pending) ..
					" lastReason=" .. safe_debug_value(portrait.model_refresh_reason)
			)

			local unit = frame.unit
			if frame.is_singleton and type(unit) == "string" and not issecretvalue(unit) then
				local frames = singleton_units[unit]
				if not frames then
					frames = {}
					singleton_units[unit] = frames
				end
				frames[#frames + 1] = frame_name .. "(" .. safe_debug_value(frame.classification) .. ")"
			end
		end
	end

	for unit, frames in pairs(singleton_units) do
		if #frames > 1 then
			debug_portrait(
				"duplicate-unit unit=" .. safe_debug_value(unit) ..
					" count=" .. #frames ..
					" frames=" .. table.concat(frames, ";")
			)
		end
	end

	debug_portrait(
		"snapshot-summary reason=" .. safe_debug_value(reason) ..
			" models=" .. printed ..
			" memberModels=" .. member_frames
	)
end

function PitBull4_Portrait:ClearFrame(frame)
	if not frame.Portrait then
		return false
	end

	local portrait = frame.Portrait

	if portrait.model then
		portrait.model = portrait.model:Delete()
	end
	if portrait.texture then
		portrait.texture = portrait.texture:Delete()
	end

	portrait.bg = portrait.bg:Delete()

	portrait.style = nil
	portrait.height = nil
	portrait.guid = nil
	portrait.full_body = nil
	frame.Portrait = portrait:Delete()

	return true
end

function PitBull4_Portrait:OnHide(frame)
	if frame.Portrait then
		frame.Portrait:Hide()
	end
end

function PitBull4_Portrait:UpdateFrame(frame)
	local layout_db = self:GetLayoutDB(frame)
	local style = layout_db.style
	local falling_back = false

	local unit = frame.unit

	if style == "class" then
		if not unit or (not UnitIsPlayer(unit) and not UnitInPartyIsAI(unit)) then
			style = layout_db.fallback_style
			falling_back = true
		end
	else
		if not unit or (safe_unit_boolean(UnitExists, unit) ~= true and not ShowBossFrameWhenUninteractable(unit)) or safe_unit_boolean(UnitIsConnected, unit) ~= true or safe_unit_boolean(UnitIsVisible, unit) ~= true then
			style = layout_db.fallback_style
			falling_back = true
		end
	end

	if style == "hide" then
		return self:ClearFrame(frame)
	end

	local portrait = frame.Portrait

	if portrait and portrait.style ~= style then
		self:ClearFrame(frame)
		portrait = nil
	end

	local created = not portrait
	if created then
		portrait = PitBull4.Controls.MakeFrame(frame)
		frame.Portrait = portrait
		portrait:SetFrameLevel(frame:GetFrameLevel() + 5)
		portrait:SetWidth(60)
		portrait:SetHeight(60)
		portrait.height = 4
		portrait.style = style
		portrait.guid = frame.guid

		if style == "three_dimensional" then
			local model = PitBull4.Controls.MakePlayerModel(frame)
			model:SetFrameLevel(frame:GetFrameLevel() + 5)
			model:SetAllPoints(portrait)
			portrait.model = model
		else -- two_dimensional or class
			local texture = PitBull4.Controls.MakeTexture(portrait, "ARTWORK")
			portrait.texture = texture
			texture:SetAllPoints(portrait)
		end

		local bg = PitBull4.Controls.MakeTexture(frame, "BACKGROUND")
		portrait.bg = bg
		bg:SetAllPoints(portrait)
		bg:SetColorTexture(unpack(layout_db.color))
	end

	local full_body = layout_db.full_body
	portrait.full_body = full_body
	if style == "three_dimensional" then
		local identity_secret = unit and PitBull4.Utils.IsUnitIdentitySecret(unit)
		local should_update = portrait.force_model_update or created or (not issecretvalue(frame.guid) and not issecretvalue(portrait.guid) and portrait.guid ~= frame.guid)
		if identity_secret then
			-- PlayerModel:SetUnit requires a declassified unit identity in Midnight 12.1.
			-- Never leave the previous unit's model visible when the new target/focus is
			-- protected. Hide only the model region and retry after combat/declassification.
			pcall(portrait.model.ClearModel, portrait.model)
			portrait.model:Hide()
			portrait.model_refresh_pending = true
			portrait.force_model_update = true
			portrait.model_refresh_reason = "secret-unit-identity"
			portrait.guid = frame.guid
			debug_portrait("update unit=" .. safe_debug_value(unit) .. " reason=secret-unit-identity hidden=true pending=true")
		elseif should_update then
			local refresh_reason = portrait.model_refresh_reason or (created and "created" or "guid-changed")
			local final_attempt = portrait.model_refresh_final_attempt
			portrait.force_model_update = nil
			portrait.model_refresh_final_attempt = nil
			portrait.model:Show()
			pcall(portrait.model.ClearModel, portrait.model)
			local set_ok = true
			local refresh_ok = true
			if not falling_back then
				set_ok = pcall(portrait.model.SetUnit, portrait.model, unit)
				if portrait.model.RefreshUnit then
					refresh_ok = pcall(portrait.model.RefreshUnit, portrait.model)
				end
				pcall(portrait.model.SetPortraitZoom, portrait.model, full_body and 0 or 1)
				pcall(portrait.model.SetPosition, portrait.model, 0, 0, 0)
				pcall(portrait.model.SetCamDistanceScale, portrait.model, layout_db.camera_distance)
			else
				pcall(portrait.model.SetModelScale, portrait.model, 1) -- the scale gets screwed up if not reset before SetModel
				set_ok = pcall(portrait.model.SetModel, portrait.model, [[Interface\Buttons\talktomequestionmark.m2]])
				pcall(portrait.model.SetModelScale, portrait.model, 3)
				pcall(portrait.model.SetPosition, portrait.model, 0, 0, -0.15)
			end
			local ready = model_ready(portrait.model)
			if falling_back or not set_ok or not refresh_ok or ready == false then
				if not falling_back then
					pcall(portrait.model.ClearModel, portrait.model)
					portrait.model:Hide()
				end
				-- Keep one deferred retry while zoning or while combat is active, but do
				-- not leave permanently unavailable/out-of-range models pending forever.
				portrait.model_refresh_pending = (not final_attempt or InCombatLockdown()) and true or nil
			elseif ready == true then
				portrait.model_refresh_pending = nil
			elseif final_attempt then
				-- If the API cannot expose model readiness, retain one retry until combat
				-- ends; otherwise stop after the bounded zoning retry sequence.
				portrait.model_refresh_pending = InCombatLockdown() and true or nil
			end
			portrait.guid = frame.guid
			debug_portrait(
				"update unit=" .. safe_debug_value(unit) ..
				" reason=" .. safe_debug_value(refresh_reason) ..
				" fallback=" .. safe_debug_value(falling_back) ..
				" setOk=" .. safe_debug_value(set_ok) ..
				" refreshOk=" .. safe_debug_value(refresh_ok) ..
				" ready=" .. safe_debug_value(ready) ..
				" pending=" .. safe_debug_value(portrait.model_refresh_pending)
			)
		end
	elseif style == "two_dimensional" then
		portrait.texture:SetTexCoord(0.14644660941, 0.85355339059, 0.14644660941, 0.85355339059)
		if unit then
			SetPortraitTexture(portrait.texture, unit)
		else
			-- No unit so just use a blank portrait
			portrait.texture:SetTexture("")
		end
	elseif style == "blank" then
		portrait.texture:SetTexture("")
	else -- class
		local _, class
		if unit then
			_, class = PitBull4.Utils.GetSafeUnitClass(unit)
		end
		if class then
			local tex_coord = CLASS_TEX_COORDS[class]
			portrait.texture:SetTexture([[Interface\Glues\CharacterCreate\UI-CharacterCreate-Classes]])
			portrait.texture:SetTexCoord(unpack(tex_coord))
		else
			-- Pets. Work out a better icon?
			portrait.texture:SetTexture([[Interface\Icons\Ability_Hunter_BeastCall]])
			portrait.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		end
	end
	portrait:Show()

	return created
end


PitBull4_Portrait:SetLayoutOptionsFunction(function(self)
	return 'color', {
		type = 'color',
		name = L["Background color"],
		desc = L["Color that the background behind the portrait should be."],
		hasAlpha = true,
		get = function(info)
			return unpack(PitBull4.Options.GetLayoutDB(self).color)
		end,
		set = function(info, r, g, b, a)
			local color = PitBull4.Options.GetLayoutDB(self).color
			color[1], color[2], color[3], color[4] = r, g, b, a

			for frame in PitBull4:IterateFrames() do
				self:Clear(frame)
			end
			self:UpdateAll()
		end,
	}, 'style', {
		type = 'select',
		name = L["Style"],
		desc = L["Set the portrait style."],
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).style
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).style = value

			for frame in PitBull4:IterateFrames() do
				self:Clear(frame)
			end
			self:UpdateAll()
		end,
		values = {
			["two_dimensional"] = L["2D"],
			["three_dimensional"] = L["3D"],
			["class"] = L["Class"],
		},
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
				self:Clear(frame)
			end
			self:UpdateAll()
		end,
		values = {
			["two_dimensional"] = L["2D"],
			["three_dimensional"] = L["3D question mark"],
			["class"] = L["Class"],
			["blank"] = L["Blank"],
			["hide"] = L["Hide completely"],
		},
	}, 'camera_distance', {
		type = 'range', min = 0.5, softMax = 10, step = 0.1,
		name = L["Camera distance"],
		desc = L["Set the camera distance when in 3D mode."],
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).camera_distance
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).camera_distance = value

			for frame in PitBull4:IterateFrames() do
				self:Clear(frame)
			end
			self:UpdateAll()
		end,
		disabled = function(info)
			return PitBull4.Options.GetLayoutDB(self).style ~= "three_dimensional"
		end,
	}, 'full_body', {
		type = 'toggle',
		name = L["Full body"],
		desc = L["Show the full body of the unit when in 3D mode."],
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).full_body
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).full_body = value

			for frame in PitBull4:IterateFrames() do
				self:Clear(frame)
			end
			self:UpdateAll()
		end,
		disabled = function(info)
			return PitBull4.Options.GetLayoutDB(self).style ~= "three_dimensional"
		end,
	}
end)
