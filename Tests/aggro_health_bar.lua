-- Run from the repository root: lua5.1 Tests/aggro_health_bar.lua
local function read(path)
	local file = assert(io.open(path, "r"))
	local source = file:read("*a")
	file:close()
	return source
end

-- Exercise the production enablement/layout wrapper without loading AceAddon.
local Module = {}
local update = assert(read("ModuleHandling/Module.lua"):match(
	"(function Module:Update%(frame, return_changed, same_guid%).-)\nend"))
setfenv(assert(loadstring(update .. "\nend")), setmetatable({
	Module = Module,
	module_types_to_update_texts = { secret_bar = true },
}, { __index = _G }))()

local frame = { unit = "player" }
local layout_updates = 0
function frame:UpdateLayout(update_texts)
	assert(update_texts)
	layout_updates = layout_updates + 1
end
function UnitExists(unit) return unit == "player" end

local health_enabled = false
local health = { module_type = "secret_bar", Update = Module.Update }
function health:IsEnabled() return true end
function health:GetLayoutDB() return { enabled = health_enabled } end
function health:UpdateFrame(f)
	local created = not f.HealthBar
	f.HealthBar = true
	return created
end
function health:ClearFrame(f)
	local existed = f.HealthBar
	f.HealthBar = nil
	return existed
end

local aggro = {}
for _, method in ipairs({ "SetModuleType", "SetName", "SetDescription",
	"SetDefaults", "SetLayoutOptionsFunction", "SetColorOptionsFunction",
	"RegisterEvent", "RawHook" }) do
	aggro[method] = function() end
end
local aggro_enabled = true
function aggro:GetLayoutDB() return { enabled = aggro_enabled, kind = "HealthBar" } end
PitBull4 = { L = setmetatable({}, { __index = function(_, key) return key end }) }
function PitBull4:NewModule() return aggro end
function PitBull4:GetModule(id) if id == "HealthBar" then return health end end
function PitBull4:IterateFramesForUnitID(unit)
	assert(unit == "player")
	local pending = true
	return function() if pending then pending = false; return frame end end
end
assert(loadfile("Modules/Aggro/Aggro.lua"))()
aggro:OnEnable()

local function threat_event()
	aggro:UNIT_THREAT_SITUATION_UPDATE("UNIT_THREAT_SITUATION_UPDATE", "player")
end

-- A threat event must not create a bar disabled in this frame's layout.
threat_event()
assert(not frame.HealthBar and layout_updates == 0)
-- Clear a stale control and refresh geometry/text attachment through Update.
frame.HealthBar = true
threat_event()
assert(not frame.HealthBar and layout_updates == 1)
-- Enabled health bars still refresh, including layout on creation.
health_enabled = true
threat_event()
assert(frame.HealthBar and layout_updates == 2)
threat_event()
assert(frame.HealthBar and layout_updates == 2)
aggro_enabled = false
health_enabled = false
threat_event()
assert(frame.HealthBar and layout_updates == 2)
print("Aggro health bar regression checks passed")
