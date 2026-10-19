local PitBull4 = _G.PitBull4
local L = PitBull4.L

-- UnitInRange returns secret booleans in Midnight combat. The legacy range
-- fader tested those values in Lua and therefore cannot be used on 12.1. This
-- implementation keeps the module in PitBull's Faders options, but renders the
-- range state through a dedicated dimming overlay. The secret boolean is passed
-- directly to SetAlphaFromBoolean and is never inspected by addon Lua.

local CreateFrame = _G.CreateFrame
local UnitInRange = _G.UnitInRange
local pairs = _G.pairs
local pcall = _G.pcall
local setmetatable = _G.setmetatable
local tonumber = _G.tonumber
local type = _G.type

local UPDATE_INTERVAL = 0.5
local OVERLAY_LEVEL_OFFSET = 100

local PitBull4_RangeFader = PitBull4:NewModule("RangeFader")

PitBull4_RangeFader:SetModuleType("fader")
PitBull4_RangeFader:SetName(L["Range fader"])
PitBull4_RangeFader:SetDescription(L["Make the unit frame fade if out of range."])
PitBull4_RangeFader:SetDefaults({
	enabled = true,
	out_of_range_opacity = 0.6,
})

local overlay_states = setmetatable({}, { __mode = "k" })
local update_timer

local function is_group_member_unit(unit)
	if type(unit) ~= "string" then
		return false
	end
	return unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil
		or unit:match("^partypet%d+$") ~= nil or unit:match("^raidpet%d+$") ~= nil
end

local function hide_state(state)
	-- Do not Show/Hide a child of a protected group frame in combat. Keeping the
	-- overlay shown and making only its texture transparent leaves the protected
	-- frame hierarchy untouched after construction.
	if state and state.texture and state.texture.SetAlpha then
		pcall(state.texture.SetAlpha, state.texture, 0)
	end
end

local function ensure_state(frame)
	local state = overlay_states[frame]
	if state and state.overlay and state.texture then
		return state
	end

	local ok, overlay = pcall(CreateFrame, "Frame", nil, frame)
	if not ok or not overlay then
		return nil
	end
	pcall(overlay.SetAllPoints, overlay, frame)
	pcall(overlay.EnableMouse, overlay, false)
	if frame.GetFrameLevel and overlay.SetFrameLevel then
		local level_ok, frame_level = pcall(frame.GetFrameLevel, frame)
		if level_ok and type(frame_level) == "number" then
			pcall(overlay.SetFrameLevel, overlay, frame_level + OVERLAY_LEVEL_OFFSET)
		end
	end

	local texture_ok, texture = pcall(overlay.CreateTexture, overlay, nil, "OVERLAY", nil, 7)
	if not texture_ok or not texture then
		pcall(overlay.Hide, overlay)
		return nil
	end
	pcall(texture.SetAllPoints, texture, overlay)
	pcall(texture.SetColorTexture, texture, 0, 0, 0, 1)
	pcall(texture.SetAlpha, texture, 0)
	pcall(overlay.Show, overlay)

	state = { overlay = overlay, texture = texture }
	overlay_states[frame] = state
	return state
end

local function get_dim_alpha(db)
	local out_of_range_opacity = tonumber(db and db.out_of_range_opacity) or 0.6
	if out_of_range_opacity < 0 then
		out_of_range_opacity = 0
	elseif out_of_range_opacity > 1 then
		out_of_range_opacity = 1
	end
	return 1 - out_of_range_opacity
end

function PitBull4_RangeFader:OnEnable()
	if update_timer then
		self:CancelTimer(update_timer)
	end
	update_timer = self:ScheduleRepeatingTimer("UpdateAll", UPDATE_INTERVAL)
	self:UpdateAll()
end

function PitBull4_RangeFader:OnDisable()
	if update_timer then
		self:CancelTimer(update_timer)
		update_timer = nil
	end
	for _, state in pairs(overlay_states) do
		hide_state(state)
	end
end

function PitBull4_RangeFader:UpdateFrame(frame)
	local unit = frame and frame.unit
	local state = overlay_states[frame]
	if not is_group_member_unit(unit) or type(UnitInRange) ~= "function" then
		hide_state(state)
		return false
	end

	state = state or ensure_state(frame)
	if not state or type(state.texture.SetAlphaFromBoolean) ~= "function" then
		hide_state(state)
		return false
	end

	-- A remote pet can report an unhelpful direct range result. For pet
	-- frames, use the owner's range state instead, passing any secret boolean
	-- straight into Blizzard's SetAlphaFromBoolean without inspecting it.
	local range_unit = unit:match("^partypet(%d+)$")
	if range_unit then
		range_unit = "party" .. range_unit
	else
		range_unit = unit:match("^raidpet(%d+)$")
		if range_unit then range_unit = "raid" .. range_unit else range_unit = unit end
	end
	local range_ok, in_range = pcall(UnitInRange, range_unit)
	if not range_ok then
		hide_state(state)
		return false
	end

	local dim_alpha = get_dim_alpha(self:GetLayoutDB(frame))
	local alpha_ok = pcall(state.texture.SetAlphaFromBoolean, state.texture, in_range, 0, dim_alpha)
	if not alpha_ok then
		hide_state(state)
		return false
	end

	return false
end

function PitBull4_RangeFader:ClearFrame(frame)
	hide_state(overlay_states[frame])
	return false
end

PitBull4_RangeFader.OnHide = PitBull4_RangeFader.ClearFrame

function PitBull4_RangeFader:Lorenzo121StatusLine()
	return "12.1 rangeFader mode=secret-boolean-overlay api=UnitInRange->SetAlphaFromBoolean interval=" .. UPDATE_INTERVAL
end

PitBull4_RangeFader:SetLayoutOptionsFunction(function(self)
	return 'out_of_range', {
		type = 'range',
		name = L["Out-of-range opacity"],
		desc = "Visual opacity for out-of-range party and raid members. The 12.1-safe implementation uses UnitInRange and a protected boolean-to-alpha overlay.",
		min = 0,
		max = 1,
		isPercent = true,
		step = 0.01,
		bigStep = 0.05,
		get = function()
			return PitBull4.Options.GetLayoutDB(self).out_of_range_opacity
		end,
		set = function(_, value)
			PitBull4.Options.GetLayoutDB(self).out_of_range_opacity = value
			PitBull4.Options.UpdateFrames()
			self:UpdateAll()
		end,
	}, 'range_method', {
		type = 'description',
		name = "12.1 uses Blizzard's UnitInRange result directly. Class-spell and interaction-distance checks are unavailable because their results can be secret in combat.",
		width = 'full',
	}
end)
