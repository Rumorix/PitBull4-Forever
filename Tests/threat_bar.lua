-- Lua 5.1 regression harness; sentinels do not emulate WoW secret enforcement.
local legacy = arg[1] == "legacy"
local secret = setmetatable({}, {
    __div = function() error("secret percentage reached arithmetic") end,
})
local checked
if not legacy then
    function issecretvalue(value)
        checked = value
        return rawequal(value, secret)
    end
end
local module = {}
for _, name in ipairs({"SetModuleType", "SetName", "SetDescription", "SetDefaults", "SetLayoutOptionsFunction", "UpdateAll", "RegisterEvent"}) do
    module[name] = function() end
end
local layout = {show_solo = true}
function module:GetLayoutDB() return layout end
PitBull4 = {L = setmetatable({}, {__index = function(_, key) return key end})}
function PitBull4:NewModule() return module end
local exists, grouped = true, false
function UnitExists() return exists end
function IsInGroup() return grouped end
local status, percent, calls = 0, 60, 0
function UnitDetailedThreatSituation(unit, target)
    assert(unit == "player" and target == "target")
    calls = calls + 1
    return false, status, percent
end
function GetThreatStatusColor(value)
    assert(not rawequal(value, secret), "secret status reached color API")
    return value, 0.5, 1
end
dofile("Modules/ThreatBar/ThreatBar.lua")
local frame = {is_singleton = true, unit = "player"}
for _, value in ipairs({0, 60, 100}) do
    percent = value
    assert(module:GetValue(frame) == value / 100)
end
percent = nil; assert(module:GetValue(frame) == nil)
for value = 0, 3 do
    status = value
    local r, g, b = module:GetColor(frame)
    assert(r == value and g == 0.5 and b == 1)
end
status = nil; assert(module:GetColor(frame) == 0)
if not legacy then
    percent = secret; checked = nil
    assert(module:GetValue(frame) == nil and rawequal(checked, secret))
    status = secret; checked = nil
    assert(module:GetColor(frame) == 0 and rawequal(checked, secret))
    -- Recovery on the next update, including public zero.
    percent = 0; status = 2
    assert(module:GetValue(frame) == 0 and module:GetColor(frame) == 2)
end
local before = calls
assert(module:GetValue({is_singleton = true, unit = "target"}) == nil)
layout.show_solo = false
assert(module:GetValue(frame) == nil and calls == before)
grouped = true; module:GROUP_ROSTER_UPDATE()
percent = 60; assert(module:GetValue(frame) == 0.6)
exists = false; assert(module:GetColor(frame) == 0)
assert(module:GetExampleValue(frame) == 0.6)
assert(module:GetExampleColor(frame) == 0)
print("ThreatBar regression checks passed (" .. (legacy and "legacy" or "secret API") .. ")")
