-- Local Lua 5.1 regression harness; does not emulate Blizzard secret enforcement.
local secret = {}
local legacy = arg[1] == 'legacy'
if not legacy then
    function issecretvalue(value) return rawequal(value, secret) end
end
COMBATFEEDBACK_FADEINTIME = 1
COMBATFEEDBACK_HOLDTIME = 1
COMBATFEEDBACK_FADEOUTTIME = 1
CombatFeedbackText = { IMMUNE = 'Immune', BLOCK = 'Block', ABSORB = 'Absorb', RESIST = 'Resist', DODGE = 'Dodge' }
local now, group = 0, false
function GetTime() return now end
function UnitInAnyGroup() return group end
function UnitExists() return true end
local timer
function CreateFrame()
    timer = { Hide = function(self) self.shown = false end, Show = function(self) self.shown = true end, SetScript = function() end }
    return timer
end
local module = {}
for _, name in ipairs({'SetModuleType', 'SetName', 'SetDescription', 'SetDefaults', 'RegisterEvent'}) do
    module[name] = function() end
end
function module:GetFont() return 'font', 12 end
local frame = {unit = 'targettarget', overlay = {}}
local lookups, writes = 0, 0
local font = {text = ''}
for _, name in ipairs({'SetShadowColor', 'SetShadowOffset', 'SetNonSpaceWrap', 'SetFont', 'SetTextColor'}) do
    font[name] = function() end
end
function font:SetText(text) self.text = text; writes = writes + 1 end
function font:GetText() return self.text end
function font:SetAlpha(alpha) self.alpha = alpha end
function font:Delete() self.text = ''; return nil end
PitBull4 = {L = setmetatable({}, {__index = function(_, key) return key end}), Controls = {MakeFontString = function() return font end}}
function PitBull4:NewModule() return module end
function PitBull4:IterateFramesForUnitID(unit)
    assert(unit == 'targettarget')
    lookups = lookups + 1
    local done = false
    return function() if not done then done = true; return frame end end
end
dofile('Modules/CombatText/CombatText.lua')
assert(module:UpdateFrame(frame))
local function combat(event, flags, amount, school, expected)
    module:UNIT_COMBAT(nil, 'targettarget', event, flags, amount, school)
    assert(font.text == expected, event)
end
combat('WOUND', '', 12, 1, '-12')
combat('WOUND', 'CRITICAL', 12, 1, '-12'); assert(font.size_modifier == 1.5)
combat('WOUND', 'CRUSHING', 12, 1, '-12'); assert(font.size_modifier == 1.5)
combat('WOUND', 'GLANCING', 12, 1, '-12'); assert(font.size_modifier == 0.75)
for _, flag in ipairs({'ABSORB', 'BLOCK', 'RESIST'}) do combat('WOUND', flag, 0, 0, CombatFeedbackText[flag]) end
combat('HEAL', 'CRITICAL', 12, 0, '+12'); assert(font.size_modifier == 1.3)
combat('ENERGIZE', '', 12, 0, '12')
combat('IMMUNE', '', 0, 0, 'Immune')
combat('BLOCK', '', 0, 0, 'Block')
combat('DODGE', '', 0, 0, 'Dodge')
if not legacy then
    for index = 1, 5 do
        local args = {'targettarget', 'WOUND', '', 12, 1}
        args[index] = secret
        local before, before_lookups = writes, lookups
        module:UNIT_COMBAT(nil, unpack(args))
        assert(writes == before and lookups == before_lookups)
    end
    for _, event in ipairs({'HEAL', 'ENERGIZE', 'IMMUNE', 'BLOCK', 'DODGE'}) do
        local before = writes
        module:UNIT_COMBAT(nil, 'targettarget', event, '', secret, 1)
        assert(writes == before)
    end
    group = secret
    local before = writes
    module:UNIT_COMBAT(nil, 'targettarget', 'WOUND', '', 12, 1)
    assert(writes == before)
    group = false
    font.text = secret
    module:UpdateFrame(frame)
    assert(rawequal(font.text, secret))
end
-- Public preview cleanup, real event replacement, and fade after skipped events.
frame.force_show = true; frame.unit = nil
module:UpdateFrame(frame); assert(font.text == '123')
frame.force_show = false; frame.unit = 'targettarget'
module:UpdateFrame(frame); assert(font.text == '')
combat('WOUND', '', 123, 1, '-123')
module:UpdateFrame(frame); assert(font.text == '-123')
now = 1.5; module:UpdateAlphas(); assert(font.alpha == 0.6)
now = 4; module:UpdateAlphas(); assert(font.alpha == 0 and not timer.shown)
assert(module:ClearFrame(frame)); assert(frame.CombatText == nil)
assert(module:UpdateFrame(frame)); assert(font.size_modifier == 1)
print('CombatText regression checks passed (' .. (legacy and 'legacy' or 'secret API') .. ')')
