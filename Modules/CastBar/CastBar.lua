
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local EXAMPLE_VALUE = 0.4
local EXAMPLE_ICON = 136222 -- Spell_Shadow_Teleport

local PitBull4_CastBar = PitBull4:NewModule("CastBar")

local new, del = PitBull4.new, PitBull4.del
local EvaluateColorValueFromBoolean = C_CurveUtil.EvaluateColorValueFromBoolean

local function EvaluateColorValuesFromBoolean(boolean, valueIfTrue, valueIfFalse)
	local r = EvaluateColorValueFromBoolean(boolean, valueIfTrue.r, valueIfFalse.r)
	local g = EvaluateColorValueFromBoolean(boolean, valueIfTrue.g, valueIfFalse.g)
	local b = EvaluateColorValueFromBoolean(boolean, valueIfTrue.b, valueIfFalse.b)
	local a = EvaluateColorValueFromBoolean(boolean, valueIfTrue.a or 1, valueIfFalse.a or 1)
	return r, g, b, a
end

PitBull4_CastBar:SetModuleType("secret_bar")
PitBull4_CastBar:SetName(L["Cast bar"])
PitBull4_CastBar:SetDescription(L["Show a cast bar."])
PitBull4_CastBar:SetDefaults({
	size = 1,
	position = 10,
	show_icon = true,
	auto_hide = false,
	idle_background = false,
},{
	casting_interruptible_color = { 1, 0.7, 0 },
	casting_uninterruptible_color = { 1, 222/255, 144/255},
	casting_complete_color = { 0, 1, 0 },
	casting_failed_color = { 1, 0, 0 },
	channel_interruptible_color = { 0, 0, 1 },
	channel_uninterruptible_color = { 96/255, 180/255, 211/255 },
})

local unit_cast_ids = {}
local cast_data = {}

local timer_frame = CreateFrame("Frame")
timer_frame:Hide()
timer_frame:SetScript("OnUpdate", function(self)
	local current_time = GetTime()
	local cleared_units
	for unit_key, data in next, cast_data do
		if
			(data.stop_time and (data.stop_time - current_time + 1 <= 0)) or
			(not data.stop_time and not data.casting and not data.channeling)
		then
			cast_data[unit_key] = del(data)
			unit_cast_ids[unit_key] = nil
			cleared_units = cleared_units or {}
			cleared_units[unit_key] = true
		end
	end

	for frame in PitBull4:IterateFrames() do
		if cast_data[frame.unit] then
			PitBull4_CastBar:Update(frame)
		end
	end

	-- If a cast has just expired and was removed above, update the matching
	-- frames once more with empty data.  Without this final update the StatusBar
	-- can visually stick at 0.0s with the old spell name/icon after Patch 13's
	-- per-unit cast cache change.
	if cleared_units then
		for unit_key in next, cleared_units do
			PitBull4_CastBar:UpdateForUnitID(unit_key)
		end
	end

	if not next(cast_data) then
		wipe(unit_cast_ids)
		self:Hide()
	end
end)

local casting_interruptible_color = CreateColor()
local casting_uninterruptible_color = CreateColor()
local channel_interruptible_color = CreateColor()
local channel_uninterruptible_color = CreateColor()

local function update_colors()
	local db = PitBull4_CastBar.db.profile.global
	casting_interruptible_color:SetRGB(unpack(db.casting_interruptible_color))
	casting_uninterruptible_color:SetRGB(unpack(db.casting_uninterruptible_color))
	channel_interruptible_color:SetRGB(unpack(db.channel_interruptible_color))
	channel_uninterruptible_color:SetRGB(unpack(db.channel_uninterruptible_color))
end

function PitBull4_CastBar:OnEnable()
	update_colors()

	self:RegisterEvent("UNIT_SPELLCAST_START")
	self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_START")
	self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_START")

	self:RegisterEvent("UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_START")
	self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_START")
	self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_START")

	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START")
	self:RegisterEvent("UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_START")
	self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
	self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")

	self:RegisterEvent("UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_START")
	self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP")

	self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "UpdateInfo")
	self:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UpdateInfo")

	self:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("PLAYER_FOCUS_CHANGED")

	self:UpdateAll()
end

function PitBull4_CastBar:OnDisable()
	timer_frame:Hide()
end

function PitBull4_CastBar:UNIT_SPELLCAST_START(event, unit, _, _, cast_id)
	self:UpdateInfo(event, unit, cast_id)
end

function PitBull4_CastBar:UNIT_SPELLCAST_CHANNEL_STOP(event, unit, _, _, interrupted_by, cast_id)
	self:UpdateInfo(event, unit, cast_id, interrupted_by)
end

function PitBull4_CastBar:UNIT_SPELLCAST_EMPOWER_STOP(event, unit, _, _, _, interrupted_by, cast_id)
	self:UpdateInfo(event, unit, cast_id, interrupted_by)
end

function PitBull4_CastBar:INSTANCE_ENCOUNTER_ENGAGE_UNIT(event)
	-- Retail/Midnight may define fewer valid boss unit IDs than the old hard-coded
	-- 1..8 sweep.  Calling UpdateForUnitID("boss6") while PitBull4 only knows
	-- boss1..MAX_BOSS_FRAMES trips the DEBUG guard in Main.lua.
	for i = 1, _G.MAX_BOSS_FRAMES or 5 do
		local unit = ("boss%d"):format(i)
		unit_cast_ids[unit] = nil
		cast_data[unit] = cast_data[unit] and del(cast_data[unit]) or nil
		self:UpdateInfo(event, unit)
	end
end

function PitBull4_CastBar:PLAYER_TARGET_CHANGED()
	unit_cast_ids.target = nil
	cast_data.target = cast_data.target and del(cast_data.target) or nil
	self:UpdateForUnitID("target")
end

function PitBull4_CastBar:PLAYER_FOCUS_CHANGED()
	unit_cast_ids.focus = nil
	cast_data.focus = cast_data.focus and del(cast_data.focus) or nil
	self:UpdateForUnitID("focus")
end



function PitBull4_CastBar:GetValue(frame)
	local unit = frame.unit
	if unit:match("%wtarget$") then
		return nil
	end

	local data = cast_data[unit]
	if not data then
		self:UpdateInfo(nil, unit)
		data = cast_data[unit]
	end

	local db = self:GetLayoutDB(frame)
	if not data then
		if db.auto_hide then
			return nil
		end
		return 0, nil, nil
	end

	local icon = db.show_icon and data.icon or nil

	if data.casting or data.channeling then
		if data.direction == Enum.StatusBarTimerDirection.RemainingTime then
			return data.duration:GetRemainingPercent(), nil, icon
		end
		return data.duration:GetElapsedPercent(), nil, icon
	elseif data.stop_value then
		return data.stop_value, nil, icon
	end

	if db.auto_hide then
		return nil
	end
	return 0, nil, icon
end
function PitBull4_CastBar:GetExampleValue(frame)
	local db = self:GetLayoutDB(frame)
	return EXAMPLE_VALUE, nil, db.show_icon and EXAMPLE_ICON or nil
end

function PitBull4_CastBar:GetColor(frame, value)
	local data = cast_data[frame.unit]
	if not data then
		return 0, 0, 0, 0
	end

	if data.casting then
		return EvaluateColorValuesFromBoolean(data.uninterruptible, casting_uninterruptible_color, casting_interruptible_color)
	elseif data.channeling then
		return EvaluateColorValuesFromBoolean(data.uninterruptible, channel_uninterruptible_color, channel_interruptible_color)
	elseif data.stop_time then
		local alpha = data.stop_time - GetTime() + 1
		if alpha >= 1 then
			alpha = 1
		end
		if alpha <= 0 then
			return 0, 0, 0, 0
		else
			-- Decide which color to use
			local r, g, b
			if not data.was_channeling then -- Last cast was normal
				if data.failed then
					r, g, b = unpack(self.db.profile.global.casting_failed_color)
				else
					r, g, b = unpack(self.db.profile.global.casting_complete_color)
				end
			else -- Last cast channeled
				r, g, b = EvaluateColorValuesFromBoolean(data.uninterruptible, channel_uninterruptible_color, channel_interruptible_color)
			end
			return r, g, b, alpha
		end
	end
	return 0, 0, 0, 0
end

function PitBull4_CastBar:GetBackgroundColor(frame)
	local data = cast_data[frame.unit]
	if not data then
		if not self:GetLayoutDB(frame).idle_background then
			return nil, nil, nil, 0
		end
	elseif data.stop_time then
		local alpha = data.stop_time - GetTime() + 1
		return nil, nil, nil, Saturate(alpha)
	end
end

function PitBull4_CastBar:GetExampleColor(frame)
	return 0, 1, 0, 1
end


function PitBull4_CastBar:UpdateInfo(event, unit, event_cast_id, interrupted_by)
	local spell, _, icon, _, _, _, _, uninterruptible, _, cast_id = UnitCastingInfo(unit)
	local channeling = false
	local direction, duration = Enum.StatusBarTimerDirection.ElapsedTime
	if spell then
		duration = UnitCastingDuration(unit)
	else
		local is_empowered
		spell, _, icon, _, _, _, uninterruptible, _, is_empowered, _, cast_id = UnitChannelInfo(unit)
		if is_empowered then
			channeling = true
			duration = UnitEmpoweredChannelDuration(unit)
		elseif spell then
			channeling = true
			duration = UnitChannelDuration(unit)
			direction = Enum.StatusBarTimerDirection.RemainingTime
		end
	end

	local id = cast_id or event_cast_id

	-- Midnight/12.x cast IDs are not a safe global key: different units can
	-- reuse the same cast ID, which made a player frame sometimes display a
	-- party member's cast.  Keep the current cast state per unit token instead.
	local data = cast_data[unit]
	if not spell and not id then
		if data then
			cast_data[unit] = del(data)
		end
		unit_cast_ids[unit] = nil
		-- When this is an actual spellcast event, force one visible update so the
		-- old spell text/icon is cleared.  Do not do this for lazy nil-event refreshes
		-- from GetValue(), otherwise that can recurse through Update().
		if event then
			self:UpdateForUnitID(unit)
		end
		return
	end

	unit_cast_ids[unit] = unit
	if not data then
		data = new()
		cast_data[unit] = data
	end

	if interrupted_by or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED"  then
		data.failed = true
		data.interrupted_by = interrupted_by
	end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
	-- This is necessary because if the interrupt happens just as the cast finishes
	-- it can look to the client like it failed but the server sends the success
	-- message after.
		data.failed = false
	end

	-- casting
	if spell then
		data.spell = spell
		data.icon = icon
		data.duration = duration
		data.direction = direction

		data.casting = not channeling
		data.channeling = channeling
		data.uninterruptible = uninterruptible
		data.was_channeling = channeling -- persistent state even after interrupted

		if data.stop_time then
			data.failed = nil
			data.interrupted_by = nil
		end
		data.cast_id = id

		data.stop_time = nil
		data.stop_value = nil

		timer_frame:Show()
		return
	end

	-- not casting
	if not data.spell then
		cast_data[unit] = del(data)
		unit_cast_ids[unit] = nil
		if event then
			self:UpdateForUnitID(unit)
		end
		return
	end

	data.casting = false
	data.channeling = false
	if not data.stop_time then
		data.stop_time = GetTime()
		if data.direction == Enum.StatusBarTimerDirection.RemainingTime then
			data.stop_value = data.duration:GetRemainingPercent()
		else
			data.stop_value = data.duration:GetElapsedPercent()
		end
	end
end


PitBull4_CastBar:SetLayoutOptionsFunction(function(self)
	return "auto_hide", {
		name = L["Auto-hide"],
		desc = L["Automatically hide the cast bar when not casting."],
		type = "toggle",
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).auto_hide
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).auto_hide = value
			PitBull4.Options.UpdateFrames()
		end,
	}, "show_icon", {
		name = L["Show icon"],
		desc = L["Whether to show the icon that is being cast."],
		type = "toggle",
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).show_icon
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).show_icon = value
			PitBull4.Options.RefreshFrameLayouts()
		end,
	}, "icon_on_left", {
		name = L["Icon position"],
		desc = L["What side of the bar to show the icon on."],
		type = "select",
		values = function(info)
			local db = PitBull4.Options.GetLayoutDB(self)
			local icon_on_left = db.icon_on_left
			local side = db.side
			local reverse = db.reverse

			if not reverse then
				if side == "center" then
					return {
						left = L["Left"],
						right = L["Right"],
					}
				else
					return {
						left = L["Bottom"],
						right = L["Top"],
					}
				end
			else
				if side == "center" then
					return {
						left = L["Right"],
						right = L["Left"],
					}
				else
					return {
						left = L["Top"],
						right = L["Bottom"],
					}
				end
			end
		end,
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).icon_on_left and "left" or "right"
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).icon_on_left = (value == "left")
			PitBull4.Options.RefreshFrameLayouts()
		end,
		hidden = function(info)
			return not PitBull4.Options.GetLayoutDB(self).show_icon
		end
	}, "idle_background", {
		name = L["Idle background"],
		desc = L["Show background on the cast bar when nothing is being cast."],
		type = "toggle",
		get = function(info)
			local db = PitBull4.Options.GetLayoutDB(self)
			return db.idle_background and not db.auto_hide
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).idle_background = value
			PitBull4.Options.RefreshFrameLayouts()
		end,
		disabled = function(info)
			return PitBull4.Options.GetLayoutDB(self).auto_hide
		end,
	}
end)

PitBull4_CastBar:SetColorOptionsFunction(function(self)
	return "casting", {
		type = "group",
		name = L["Casting"],
		inline = true,
		args = {
			casting_interruptible_color = {
				type = "color",
				name = L["Interruptible"],
				desc = L["Sets which color to use on casting bar of casts that are interruptible."],
				get = function(info)
					return unpack(self.db.profile.global.casting_interruptible_color)
				end,
				set = function(info, r, g, b)
					self.db.profile.global.casting_interruptible_color = { r, g, b }
					casting_interruptible_color:SetRGB(r, g, b)
					self:UpdateAll()
				end,
				order = 1,
			},
			casting_uninterruptible_color = {
				type = "color",
				name = L["Uninterruptible"],
				desc = L["Sets which color to use on casting bar of casts that are not interruptible."],
				get = function(info)
					return unpack(self.db.profile.global.casting_uninterruptible_color)
				end,
				set = function(info, r, g, b)
					self.db.profile.global.casting_uninterruptible_color = { r, g, b }
					casting_interruptible_color:SetRGB(r, g, b)
					self:UpdateAll()
				end,
				order = 2,
			},
			casting_complete_color = {
				type = "color",
				name = L["Complete"],
				desc = L["Sets which color to use on casting bar of casts that completed."],
				get = function(info)
					return unpack(self.db.profile.global.casting_complete_color)
				end,
				set = function(info, r, g, b)
					self.db.profile.global.casting_complete_color = { r, g, b }
					self:UpdateAll()
				end,
				order = 3,
			},
			casting_failed_color = {
				type = "color",
				name = L["Failed"],
				desc = L["Sets which color to use on casting bar of casts that failed."],
				get = function(info)
					return unpack(self.db.profile.global.casting_failed_color)
				end,
				set = function(info, r, g, b)
					self.db.profile.global.casting_failed_color = { r, g, b }
					self:UpdateAll()
				end,
				order = 4,
			},
		},
	}, "channeling", {
		type = "group",
		name = L["Channeling"],
		inline = true,
		args = {
			channel_interruptible_color = {
				type = "color",
				name = L["Interruptible"],
				desc = L["Sets which color to use on casting bar of channeled casts that are interruptible."],
				get = function(info)
					return unpack(self.db.profile.global.channel_interruptible_color)
				end,
				set = function(info, r, g, b)
					self.db.profile.global.channel_interruptible_color = { r, g, b }
					channel_interruptible_color:SetRGB(r, g, b)
					self:UpdateAll()
				end,
				order = 1,
			},
			channel_uninterruptible_color = {
				type = "color",
				name = L["Uninterruptible"],
				desc = L["Sets which color to use on casting bar of channeled casts that are not interruptible."],
				get = function(info)
					return unpack(self.db.profile.global.channel_uninterruptible_color)
				end,
				set = function(info, r, g, b)
					self.db.profile.global.channel_uninterruptible_color = { r, g, b }
					channel_uninterruptible_color:SetRGB(r, g, b)
					self:UpdateAll()
				end,
				order = 2,
			},
		},
	},
	function(info)
		self.db.profile.global.casting_interruptible_color = { 1, 0.7, 0 }
		self.db.profile.global.casting_uninterruptible_color = { 1, 222/255, 144/255 }
		self.db.profile.global.casting_complete_color = { 0, 1, 0 }
		self.db.profile.global.casting_failed_color = { 1, 0, 0 }
		self.db.profile.global.channel_interruptible_color = { 0, 0, 1 }
		self.db.profile.global.channel_uninterruptible_color = { 96/255, 180/255, 211/255 }
		update_colors()
	end
end)
