local PitBull4 = _G.PitBull4
local L = PitBull4.L

local EXAMPLE_VALUE = 0.8

local unpack = _G.unpack

local PitBull4_HealthBar = PitBull4:NewModule("HealthBar")

PitBull4_HealthBar:SetModuleType("secret_bar")
PitBull4_HealthBar:SetName(L["Health bar"])
PitBull4_HealthBar:SetDescription(L["Show a bar indicating the unit's health."])
PitBull4_HealthBar.allow_animations = true
PitBull4_HealthBar:SetDefaults({
	position = 1,
	color_by_class = true,
	hostility_color = true,
	hostility_color_npcs = true,
}, {
	colors = {
		dead = { 0.6, 0.6, 0.6 },
		disconnected = { 0.7, 0.7, 0.7 },
		tapped = { 0.5, 0.5, 0.5 },
		max_health = { 0, 1, 0 },
		half_health = { 1, 1, 0 },
		min_health = { 1, 0, 0 },
	}
})

local hp_color_curve = C_CurveUtil.CreateColorCurve()
-- Smoothly interpolate between configured low, half and full health colors.
hp_color_curve:SetType(Enum.LuaCurveType.Linear)

local timerFrame = CreateFrame("Frame")
timerFrame:Hide()

local units_to_update = {}
local perf = {
	events = 0,
	coalesced = 0,
	flushes = 0,
	frame_updates = 0,
}

local function queue_unit(unit)
	if not unit then return end
	perf.events = perf.events + 1
	if units_to_update[unit] then
		perf.coalesced = perf.coalesced + 1
	else
		units_to_update[unit] = true
	end
	-- Patch 061: the batching frame sleeps when there is no work. Wake it only
	-- after an event has queued a unit, then let the next render frame coalesce
	-- any additional events for the same unit.
	timerFrame:Show()
end

local function update_hp_curve(self)
	local colors = self.db.profile.global.colors
	hp_color_curve:ClearPoints()
	hp_color_curve:AddPoint(0.0, CreateColor(unpack(colors.min_health)))
	hp_color_curve:AddPoint(0.5, CreateColor(unpack(colors.half_health)))
	hp_color_curve:AddPoint(1.0, CreateColor(unpack(colors.max_health)))

	self:UpdateAll()
end

function PitBull4_HealthBar:OnEnable()
	timerFrame:Hide()

	self:RegisterEvent("UNIT_HEALTH")
	self:RegisterEvent("UNIT_MAXHEALTH", "UNIT_HEALTH")
	self:RegisterEvent("UNIT_CONNECTION", "UNIT_HEALTH")
	self:RegisterEvent("PLAYER_ALIVE")

	update_hp_curve(self)
end

function PitBull4_HealthBar:OnDisable()
	timerFrame:Hide()
	wipe(units_to_update)
end

timerFrame:SetScript("OnUpdate", function(self)
	if not next(units_to_update) then
		self:Hide()
		return
	end

	perf.flushes = perf.flushes + 1
	for unit in pairs(units_to_update) do
		-- PitBull already maintains a UnitID -> frames index. Updating only the
		-- frames that can represent this unit avoids a full raid-frame scan for
		-- every health batch. IterateFramesForUnitID also includes matching wacky
		-- frames while skipping hidden frames.
		for frame in PitBull4:IterateFramesForUnitID(unit) do
			PitBull4_HealthBar:Update(frame)
			perf.frame_updates = perf.frame_updates + 1
		end
	end
	wipe(units_to_update)
	self:Hide()
end)

function PitBull4_HealthBar:GetValue(frame)
	return UnitHealthPercent(frame.unit, true)
end

function PitBull4_HealthBar:GetExampleValue(frame)
	return EXAMPLE_VALUE
end

function PitBull4_HealthBar:GetColor(frame)
	local color

	local unit = frame.unit
	if not unit or not UnitIsConnected(unit) then
		color = self.db.profile.global.colors.disconnected
	elseif UnitIsDeadOrGhost(unit) then
		color = self.db.profile.global.colors.dead
	elseif UnitIsTapDenied(unit) then
		color = self.db.profile.global.colors.tapped
	end
	if color then
		return color[1], color[2], color[3], nil, true
	end

	color = UnitHealthPercent(unit, true, hp_color_curve)
	if color then
		return color:GetRGB()
	end
end
function PitBull4_HealthBar:GetExampleColor(frame, value)
	return unpack(self.db.profile.global.colors.disconnected)
end

function PitBull4_HealthBar:GetSecretBackgroundColor(frame)
	-- Missing health is intentionally independent of health percentage and unit
	-- reaction. SecretBarModule still honors an explicit layout background first.
	return 0.08, 0.08, 0.08
end

function PitBull4_HealthBar:Lorenzo121StatusLine()
	return ("12.1 healthBar protectedReaction=pitbull-secret-boolean-overlays predicates=UnitIsEnemy+UnitIsFriend specialStates=tapped+dead+disconnected background=neutral-dark fallback=UnitSelectionColor perf=event-wake-unit-index events=%d coalesced=%d flushes=%d frameUpdates=%d"):format(perf.events, perf.coalesced, perf.flushes, perf.frame_updates)
end

function PitBull4_HealthBar:UNIT_HEALTH(_, unit)
	queue_unit(unit)
end

function PitBull4_HealthBar:PLAYER_ALIVE()
	queue_unit("player")
end

PitBull4_HealthBar:SetColorOptionsFunction(function(self)
	local function get(info)
		return unpack(self.db.profile.global.colors[info[#info]])
	end
	local function set(info, r, g, b)
		local color = self.db.profile.global.colors[info[#info]]
		color[1], color[2], color[3] = r, g, b
	end
	local function set_curve(info, r, g, b)
		set(info, r, g, b)
		update_hp_curve(self)
	end
	return 'dead', {
		type = 'color',
		name = L["Dead"],
		get = get,
		set = set,
	},
	'disconnected', {
		type = 'color',
		name = L["Disconnected"],
		get = get,
		set = set,
	},
	'tapped', {
		type = 'color',
		name = L["Tapped"],
		get = get,
		set = set,
	},
	'max_health', {
		type = 'color',
		name = L["Full health"],
		get = get,
		set = set_curve,
	},
	'half_health', {
		type = 'color',
		name = L["Half health"],
		get = get,
		set = set_curve,
	},
	'min_health', {
		type = 'color',
		name = L["Empty health"],
		get = get,
		set = set_curve,
	},
	function(info)
		local color = self.db.profile.global.colors.dead
		color[1], color[2], color[3] = 0.6, 0.6, 0.6

		color = self.db.profile.global.colors.disconnected
		color[1], color[2], color[3] = 0.7, 0.7, 0.7

		color = self.db.profile.global.colors.tapped
		color[1], color[2], color[3] = 0.5, 0.5, 0.5

		color = self.db.profile.global.colors.max_health
		color[1], color[2], color[3] = 0, 1, 0

		color = self.db.profile.global.colors.half_health
		color[1], color[2], color[3] = 1, 1, 0

		color = self.db.profile.global.colors.min_health
		color[1], color[2], color[3] = 1, 0, 0

		update_hp_curve(self)
	end
end)
