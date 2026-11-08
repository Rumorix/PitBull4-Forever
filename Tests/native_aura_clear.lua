-- Run from the repository root: lua5.1 Tests/native_aura_clear.lua
-- Lifecycle mocks cannot establish WoW protected/secret API legality.
local combat, mutations, legacy_clears = false, 0, 0
function InCombatLockdown() return combat end
local module = {}
function module:GetLayoutDB() return {} end
function module:ClearFrame() legacy_clears = legacy_clears + 1 end
PitBull4 = { GetModule = function() return module end }
dofile('Modules/Aura/NativeContainer_12_1.lua')

local function upvalue(fn, wanted)
    for index = 1, math.huge do
        local name, value = debug.getupvalue(fn, index)
        assert(name, 'missing upvalue: ' .. wanted)
        if name == wanted then return value end
    end
end
local states = upvalue(module.Lorenzo121ClearNativeFrame, 'native_frames')
local function mutate()
    mutations = mutations + 1
    assert(not combat, 'unexpected combat mutation')
end
local function group(enabled, split)
    local container = { shown = enabled, own = enabled, other = split and enabled or false }
    function container:GetUnit() return 'targettarget' end
    function container:SetUnit() mutate() end
    function container:SetAuraGroupEnabled(key, value)
        mutate()
        self[key == 'pitbull_own' and 'own' or 'other'] = value
    end
    function container:Hide() mutate(); self.shown = false end
    local holder = { shown = enabled }
    function holder:Hide() mutate(); self.shown = false end
    return { enabled = enabled, container = container, holder = holder,
        otherFilterString = split and 'HELPFUL' or nil }
end

-- Repeated same-token disappearance/reappearance, all enablement combinations,
-- with both combined and split ownership groups.
for _, split in ipairs({false, true}) do
    for _, buffs in ipairs({false, true}) do
        for _, debuffs in ipairs({false, true}) do
            local frame = { unit = 'targettarget' }
            local state = { groups = {buff = group(buffs, split), debuff = group(debuffs, split)} }
            states[frame] = state
            combat = true
            local before = mutations
            for cycle = 1, 3 do
                module:ClearFrame(frame)
                assert(module:Lorenzo121UpdateNativeFrame(frame))
                assert(states[frame] == state)
                for _, g in pairs(state.groups) do
                    assert(g.container.own == g.enabled)
                    assert(g.container.shown == g.enabled and g.holder.shown == g.enabled)
                    assert(g.container.other == (split and g.enabled or false))
                end
            end
            -- pcall containment must not conceal attempted mutations.
            assert(mutations == before)
            combat = false
            module:ClearFrame(frame)
            assert(mutations > before)
            for _, g in pairs(state.groups) do
                assert(not g.container.own and not g.container.other)
                assert(not g.container.shown and not g.holder.shown)
            end
            assert(states[frame] == state)
        end
    end
end
combat = true
module:ClearFrame({unit = 'targettarget'}) -- no cached state
assert(legacy_clears == 33, 'legacy clear must still run')
print('native aura clear lifecycle: OK')
