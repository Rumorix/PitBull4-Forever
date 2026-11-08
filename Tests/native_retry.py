"""Run the native recovery control flow under Lua 5.1 with public API stubs."""
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

HARNESS = r'''
local combat, available, failing = false, true, true
local attempts, legacy, cleared = 0, 0, 0
local config_failing = false
local module = { Lorenzo121 = {} }
PitBull4 = { GetModule = function() return module end }
AnchorUtil = { FlowLayoutAxis = {}, FlowDirection = {} }
function CreateFrame() error('unexpected allocation') end
function InCombatLockdown() return combat end
function module:Lorenzo121RefreshCapabilities()
    return { is121OrNewer = true, auraContainerAddonLoaded = available,
        nativeAPIPrerequisitesReady = available }
end
function module:UpdateFrame(frame, marker)
    assert(marker == 'filtered fallback')
    legacy = legacy + 1
end
function module:ClearFrame() end
function module:ClearAuras() cleared = cleared + 1 end
function module:UpdateAll() end
dofile('Modules/Aura/NativeContainer_12_1.lua')
-- Replace only container construction/configuration, retaining the real wrapper,
-- failure bookkeeping, retirement decisions, and native update success path.
local function replace(func, name, value)
    for i = 1, 100 do
        local key = debug.getupvalue(func, i)
        if not key then break end
        if key == name then debug.setupvalue(func, i, value); return end
    end
    error('missing upvalue ' .. name)
end
replace(module.Lorenzo121UpdateNativeFrame, 'create_native_state', function()
    attempts = attempts + 1
    if failing then return nil, 'temporary creation failure' end
    return { groups = { buff = {}, debuff = {} } }
end)
replace(module.Lorenzo121UpdateNativeFrame, 'configure_group', function()
    return not config_failing, 'temporary configuration failure'
end)
replace(module.Lorenzo121UpdateNativeFrame, 'retire_state', function() end)
function module:GetLayoutDB() return {} end
local frame = { unit = 'player' }
local function update() module:UpdateFrame(frame, 'filtered fallback') end
update(); assert(attempts == 1 and legacy == 1 and module:Lorenzo121HasNativeFailures())
for i = 1, 10 do update() end
assert(attempts == 1 and module:Lorenzo121ShouldRunLegacyAuraTicker())
combat = true
module:Lorenzo121RetryNativeFailures(); update(); assert(attempts == 1)
combat = false; available = false
module:Lorenzo121RetryNativeFailures(); update(); assert(attempts == 1)
available = true
module:Lorenzo121RetryNativeFailures()
-- A combat transition after granting a retry must still defer allocation.
combat = true; update(); assert(attempts == 1)
combat = false; update(); assert(attempts == 2)
for i = 1, 10 do module:Lorenzo121RetryNativeFailures(); update() end
assert(attempts == 2 and module:Lorenzo121HasNativeFailures())
-- Explicit rebuild re-arms recovery, and successful native configuration clears
-- failure status and pooled legacy output.
module:Lorenzo121RebuildNativeContainers()
update(); assert(attempts == 3)
failing = false; module:Lorenzo121RetryNativeFailures(); update()
assert(attempts == 4 and cleared == 1 and not module:Lorenzo121HasNativeFailures())
assert(not module:Lorenzo121ShouldRunLegacyAuraTicker())
-- A later independent failure gets its own single retry.
failing = true; update(); assert(attempts == 5)
failing = false; module:Lorenzo121RetryNativeFailures(); update()
assert(attempts == 6 and cleared == 2 and not module:Lorenzo121HasNativeFailures())
config_failing = true; update(); assert(attempts == 7)
module:Lorenzo121RetryNativeFailures(); update(); assert(attempts == 8)
for i = 1, 10 do module:Lorenzo121RetryNativeFailures(); update() end
assert(attempts == 8 and module:Lorenzo121HasNativeFailures())
module:Lorenzo121SetNativeEnabled(false)
module:Lorenzo121SetNativeEnabled(true)
update(); assert(attempts == 9)
config_failing = false; module:Lorenzo121RetryNativeFailures(); update()
assert(attempts == 10 and not module:Lorenzo121HasNativeFailures())
print('Native retry control-flow checks passed')
'''


class NativeRetryTests(unittest.TestCase):
    def test_lua51_recovery(self):
        subprocess.run(['lua5.1', '-'], input=HARNESS, text=True, cwd=ROOT, check=True)


if __name__ == '__main__':
    unittest.main()
