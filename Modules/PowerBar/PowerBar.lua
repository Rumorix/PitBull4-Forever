
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local EXAMPLE_VALUE = 0.6
local PowerBarColor = _G.PowerBarColor

local NO_RESOURCE_BG_R = 0.12
local NO_RESOURCE_BG_G = 0.12
local NO_RESOURCE_BG_B = 0.12
local NO_RESOURCE_BG_A = 0.78

local PitBull4_PowerBar = PitBull4:NewModule("PowerBar")

PitBull4_PowerBar:SetModuleType("secret_bar")
PitBull4_PowerBar:SetName(L["Power bar"])
PitBull4_PowerBar:SetDescription(L["Show a bar for your primary resource."])
PitBull4_PowerBar.allow_animations = true
PitBull4_PowerBar:SetDefaults({
	position = 2,
	hide_no_mana = false,
	-- Midnight returns an ordinary (non-secret) zero maximum for units that do
	-- not use a primary resource. Hide those empty rows by default so their
	-- attached Class/Power texts cannot look like a duplicate 0% unit frame.
	hide_no_power = true,
	use_atlas = false,
})

local units_to_update = {}
local perf = {
	events = 0,
	coalesced = 0,
	flushes = 0,
	frame_updates = 0,
}
local type_to_token = {
	"MANA", "RAGE", "FOCUS", "ENERGY", "CHI",
	"RUNES", "RUNIC_POWER", "SOUL_SHARDS", "LUNAR_POWER",
	"HOLY_POWER", "MAELSTROM", "INSANITY", "FURY", "PAIN"
}
local power_bar_atlas = {}
for power_token, info in next, PowerBarColor do
	if info.atlas then
		power_bar_atlas[power_token] = info.atlas
	end
end

local timerFrame = CreateFrame("Frame")
timerFrame:Hide()

local function queue_unit(unit)
	if not unit then return end
	perf.events = perf.events + 1
	if units_to_update[unit] then
		perf.coalesced = perf.coalesced + 1
	else
		units_to_update[unit] = true
	end
	-- Patch 061: sleep while idle and wake only when an event queued work.
	timerFrame:Show()
end

function PitBull4_PowerBar:OnEnable()
	self:RegisterEvent("UNIT_POWER_FREQUENT")
	self:RegisterEvent("UNIT_MAXPOWER", "UNIT_POWER_FREQUENT")
	self:RegisterEvent("UNIT_DISPLAYPOWER")
	self:RegisterEvent("UNIT_POWER_BAR_SHOW", "UNIT_DISPLAYPOWER")
	self:RegisterEvent("UNIT_POWER_BAR_HIDE", "UNIT_DISPLAYPOWER")

	timerFrame:Hide()
end

function PitBull4_PowerBar:OnDisable()
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
		for frame in PitBull4:IterateFramesForUnitID(unit) do
			PitBull4_PowerBar:Update(frame)
			perf.frame_updates = perf.frame_updates + 1
		end
	end
	wipe(units_to_update)
	self:Hide()
end)

function PitBull4_PowerBar:GetValue(frame)
	local unit = frame.unit
	local layout_db = self:GetLayoutDB(frame)

	-- Patch 051: resolve the unit's primary power type first and, when that
	-- value is public, query UnitPowerMax with the explicit type. Midnight's
	-- power API keeps the unsupported-resource sentinel as a public zero for
	-- explicit power-type queries. This is more reliable for hostile NPCs than
	-- the implicit-primary query while still avoiding every secret comparison.
	local power_type = UnitPowerType(unit)
	local power_type_is_secret = issecretvalue(power_type)

	if layout_db.hide_no_mana and not power_type_is_secret and power_type ~= 0 then
		return nil
	end

	-- Patch 060: keep a layout anchor for texts attached to PowerBar even when
	-- the unit has no real primary resource. Historically Lua:Class is attached
	-- to PowerBar; deleting the bar also deletes that text slot from the frame.
	-- The anchor is rendered invisible below, while Power LuaTexts are blanked.
	frame._pb4_no_resource_power_anchor = nil

	if layout_db.hide_no_power then
		local max
		if power_type_is_secret then
			max = UnitPowerMax(unit)
		else
			max = UnitPowerMax(unit, power_type)
		end

		-- Never branch on a protected maximum. A public zero is the only
		-- condition used to identify a no-resource unit. Keep a zero-valued
		-- statusbar object solely as the attachment/layout anchor instead of
		-- clearing frame.PowerBar and taking Lua:Class with it.
		if not issecretvalue(max) and max <= 0 then
			frame._pb4_no_resource_power_anchor = true
			return 0
		end
	end

	return UnitPowerPercent(unit)
end

-- Preserve the inherited SecretBar UpdateFrame implementation, then turn the
-- no-resource anchor into a visible fallback row: hide the fill, keep the
-- geometry for attached Class texts, and paint a darker less-transparent
-- background so the text does not appear to float on a fully transparent bar.
local SecretBar_UpdateFrame = PitBull4_PowerBar.UpdateFrame
function PitBull4_PowerBar:UpdateFrame(frame)
	local changed = SecretBar_UpdateFrame(self, frame)
	local control = frame[self.id]
	if not control then
		return changed
	end

	local fill = control.GetStatusBarTexture and control:GetStatusBarTexture()
	if frame._pb4_no_resource_power_anchor then
		-- Vertex alpha only: the next normal update restores it with the
		-- configured "Full opacity". Texture:SetAlpha would clobber that value.
		if fill then
			pcall(fill.SetVertexColor, fill, 1, 1, 1, 0)
		end
		control:SetBackgroundColor(NO_RESOURCE_BG_R, NO_RESOURCE_BG_G, NO_RESOURCE_BG_B, NO_RESOURCE_BG_A)
		control:Show()
	end
	return changed
end

function PitBull4_PowerBar:GetExampleValue(frame)
	return EXAMPLE_VALUE
end

function PitBull4_PowerBar:GetColor(frame, value)
	local unit = frame.unit
	local power_type, power_token, r, g, b = UnitPowerType(unit)
	local color = PitBull4.PowerColors[power_token]

	if not color then
		if not r then
			color = PitBull4.PowerColors[type_to_token[power_type]] or PitBull4.PowerColors.MANA
			r, g, b = color[1], color[2], color[3]
		end
	else
		r, g, b = color[1], color[2], color[3]
	end
	return r, g, b
end
function PitBull4_PowerBar:GetExampleColor(frame)
	return unpack(PitBull4.PowerColors.MANA)
end

function PitBull4_PowerBar:Lorenzo121StatusLine()
	return ("12.1 powerBar noResource=dark-fallback-anchor classTextPreserved=yes powerTextSuppressed=yes fallbackBg=0.12,0.12,0.12,0.78 migration=config-v10 perf=event-wake-unit-index events=%d coalesced=%d flushes=%d frameUpdates=%d"):format(perf.events, perf.coalesced, perf.flushes, perf.frame_updates)
end

function PitBull4_PowerBar:GetTexture(frame)
	if not self:GetLayoutDB(frame).use_atlas then return end

	local _, power_token = UnitPowerType(frame.unit)
	local atlas = power_bar_atlas[power_token]
	if atlas then
		return atlas, true
	end
end

function PitBull4_PowerBar:UNIT_POWER_FREQUENT(_, unit, power_type)
	if not unit then return end
	local _, power_token = UnitPowerType(unit)
	-- fix units that have a special power type but update as ENERGY
	if not PowerBarColor[power_token] then
		power_token = "ENERGY"
	end
	if power_token == power_type then
		queue_unit(unit)
	end
end

function PitBull4_PowerBar:UNIT_DISPLAYPOWER(_, unit)
	queue_unit(unit)
end

PitBull4_PowerBar:SetLayoutOptionsFunction(function(self)
	local function get(info)
		return PitBull4.Options.GetLayoutDB(self)[info[#info]]
	end
	local function set(info, value)
		PitBull4.Options.GetLayoutDB(self)[info[#info]] = value
		PitBull4.Options.UpdateFrames()
	end

	return 'hide_no_mana', {
		name = L["Hide non-mana"],
		desc = L["Hides the power bar if the unit's current power is not mana."],
		type = "toggle",
		get = get,
		set = set,
	}, 'hide_no_power', {
		name = L["Hide non-power"],
		desc = L["Hides the power bar if the unit has no power."],
		type = "toggle",
		get = get,
		set = set,
	}, 'use_atlas', {
		name = L["Use power texture"],
		desc = L["Use the provided power-specific texture if available instead of the set texture."],
		type = "toggle",
		get = get,
		set = set,
	}
end)
