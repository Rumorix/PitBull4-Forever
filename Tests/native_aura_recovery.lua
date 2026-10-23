-- Standalone Lua 5.1 tests. Load the real Aura lifecycle and native renderer;
-- model only public configuration, frame operations and the timer/event loop.
local root = REPOSITORY_ROOT or "."

local function harness()
	local h = { now = 0, combat = false, timers = {}, frames = {}, containers = {}, deferred = {}, violations = 0 }
	local env = setmetatable({}, { __index = _G })
	env._G = env
	local aura = { enabled = true, events = {}, legacy_updates = 0, legacy_clears = 0 }
	h.aura = aura
	local function mutate(method)
		if h.combat then
			h.violations = h.violations + 1
			error("combat mutation: " .. method)
		end
		if h.fail_method == method then
			h.failure_calls = (h.failure_calls or 0) + 1
			if not h.fail_always then h.fail_method = nil end
			error("injected failure: " .. method)
		end
	end
	local function object(kind, parent)
		local o = { kind = kind, parent = parent, shown = true, level = 1, width = 200, height = 60, groups = {}, unit = "none" }
		for _, method in ipairs({
			"ClearAllPoints", "SetPoint", "SetAllPoints", "SetIcon", "SetDurationCooldown", "SetDurationText",
			"SetApplicationCount", "AddDispelTypeTexture", "SetTooltipAnchorPoint", "SetHideTooltipInCombat",
			"SetCancelAuraButtons", "EnableMouse", "SetFont", "SetTextColor", "SetShadowColor", "SetShadowOffset",
			"SetJustifyH", "SetTexture", "SetTexCoord", "SetBlendMode", "SetVertexColor",
			"SetFlowLayoutAxis", "SetFlowLayoutAnchorPoint", "SetFlowLayoutGrowthDirection",
			"SetFlowLayoutPadding", "SetFlowLayoutMaximumLineSize", "SetAuraGroupLayout", "SetEditModePreviewEnabled",
		}) do
			o[method] = function() mutate(method) end
		end
		function o:GetFrameLevel() return self.level end
		function o:SetFrameLevel(level) mutate("SetFrameLevel"); self.level = level end
		function o:GetWidth() return self.width end
		function o:GetHeight() return self.height end
		function o:SetSize(w, height) mutate("SetSize"); self.width, self.height = w, height end
		function o:IsShown() return self.shown end
		-- The Aura ticker is an independent, unprotected root Frame. Native
		-- surfaces and their holders/buttons are descendants of a unit frame.
		function o:Show() if parent or kind ~= "Frame" then mutate("Show") end; self.shown = true end
		function o:Hide() if parent or kind ~= "Frame" then mutate("Hide") end; self.shown = false end
		function o:SetShown(shown) mutate("SetShown"); self.shown = shown end
		function o:GetName() return "TestFrame" end
		function o:GetFont() return "test-font", 12 end
		function o:SetScript(script, fn) self[script] = fn end
		function o:RegisterEvent(event) self[event] = true end
		function o:GetUnit() return self.unit end
		function o:SetUnit(unit) mutate("SetUnit"); self.unit = unit end
		function o:UpdateAllAuras() self.refreshes = (self.refreshes or 0) + 1 end
		function o:AddAuraGroup(key, filter, options)
			mutate("AddAuraGroup")
			self.groups[key] = { enabled = true, filter = filter, max = options.maxFrameCount }
			options.initializeFrame(object("AuraButton", self))
		end
		function o:SetAuraGroupEnabled(key, enabled)
			mutate("SetAuraGroupEnabled"); assert(self.groups[key]); self.groups[key].enabled = enabled
		end
		function o:SetAuraGroupFilterString(key, filter)
			mutate("SetAuraGroupFilterString"); self.groups[key].filter = filter
		end
		function o:SetAuraGroupMaxFrameCount(key, max)
			mutate("SetAuraGroupMaxFrameCount"); self.groups[key].max = max
		end
		function o:CreateTexture() mutate("CreateTexture"); return object("Texture", self) end
		function o:CreateFontString() mutate("CreateFontString"); return object("FontString", self) end
		return o
	end
	env.CreateFrame = function(kind, name, parent)
		mutate("CreateFrame")
		local o = object(kind, parent)
		if kind == "AuraContainer" then h.containers[#h.containers + 1] = o end
		return o
	end
	env.InCombatLockdown = function() return h.combat end
	env.GetTime = function() return h.now end
	env.UnitExists = function(unit) return h.absent ~= unit end
	-- Recovery must never discover identities or inspect aura payloads.
	local function forbidden_read() error("unexpected protected-data read") end
	env.UnitGUID = forbidden_read
	env.C_UnitAuras = setmetatable({}, { __index = function() return forbidden_read end })
	env.AnchorUtil = { FlowLayoutAxis = { Horizontal = 0, Vertical = 1 }, FlowDirection = { Right = 1, Left = 0, Up = 2, Down = 3 } }
	env.AuraContainerSortMethod = { Default = 0, AuraInstanceIDOnly = 1 }
	env.AuraContainerSortDirection = { Normal = 0, Reverse = 1 }
	env.STANDARD_TEXT_FONT = "test-font"
	env.C_StringUtil = false
	env.C_DurationUtil = false
	env.Enum = {}
	env.PitBull4 = {
		L = setmetatable({}, { __index = function(_, key) return key end }),
		NewModule = function() return aura end,
		GetModule = function() return aura end,
		IterateFrames = function()
			local i = 0
			return function()
				repeat i = i + 1 until not h.frames[i] or h.frames[i]:IsShown()
				return h.frames[i]
			end
		end,
		RunOnLeaveCombat = function(_, fn, ...)
			if h.combat then
				h.deferred[#h.deferred + 1] = { fn = fn, args = { ... } }
			else fn(...) end
		end,
	}
	for _, method in ipairs({ "SetModuleType", "SetName", "SetDescription", "PLAYER_TALENT_UPDATE", "UpdateFilters", "UpdateWeaponEnchants", "UpdateSkin", "LayoutAuras" }) do
		aura[method] = function() end
	end
	function aura:IsEnabled() return self.enabled end
	function aura:RegisterEvent(event, method) self.events[event] = method or event end
	function aura:ScheduleTimer(method, delay, ...)
		local timer = { method = method, due = h.now + delay, args = { ... } }
		h.timers[#h.timers + 1] = timer
		return timer
	end
	function aura:CancelTimer(timer) timer.cancelled = true end
	function aura:GetLayoutDB(frame) return frame.db end
	function aura:UpdateAuras() mutate("LegacyUpdate"); self.legacy_updates = self.legacy_updates + 1 end
	function aura:ClearAuras() mutate("LegacyClear"); self.legacy_clears = self.legacy_clears + 1 end
	function aura:Update(frame)
		if not frame.db.enabled or not frame.unit or not env.UnitExists(frame.unit) then
			self:ClearFrame(frame)
		else self:UpdateFrame(frame) end
	end
	local function load(relative)
		local fn = assert(loadfile(root .. "/" .. relative)); setfenv(fn, env); fn()
	end
	load("Modules/Aura/Aura.lua")
	load("Modules/Aura/NativeContainer_12_1.lua")
	function aura:Lorenzo121RefreshCapabilities()
		return { is121OrNewer = true, auraContainerAddonLoaded = true, nativeAPIPrerequisitesReady = true }
	end
	aura:OnEnable()
	function h:new_frame(unit)
		local frame = object("UnitFrame")
		frame.unit = unit or "targettarget"
		frame.db = {
			enabled = true, enabled_buffs = true, enabled_debuffs = true,
			max_buffs = 12, max_debuffs = 10, native_strict_limit = false,
			layout = { buff = { filter_new = "!B", size = 20 }, debuff = { filter_new = "!D", size = 18 } },
		}
		self.frames[#self.frames + 1] = frame
		return frame
	end
	function h:advance(seconds)
		local until_time = self.now + seconds
		for _ = 1, 100 do
			local chosen
			for _, t in ipairs(self.timers) do
				if not t.cancelled and not t.fired and t.due <= until_time and (not chosen or t.due < chosen.due) then chosen = t end
			end
			if not chosen then self.now = until_time; return end
			self.now = chosen.due; chosen.fired = true
			self.aura[chosen.method](self.aura, unpack(chosen.args))
		end
		error("unbounded retry loop")
	end
	function h:regen()
		self.combat = false
		local deferred = self.deferred; self.deferred = {}
		for _, action in ipairs(deferred) do action.fn(unpack(action.args)) end
		if self.aura.enabled then self.aura[self.aura.events.PLAYER_REGEN_ENABLED](self.aura) end
	end
	function h:live_timers()
		local count = 0
		for _, t in ipairs(self.timers) do if not t.cancelled and not t.fired then count = count + 1 end end
		return count
	end
	function h:assert_armed(frame)
		local count = 0
		for _, c in ipairs(self.containers) do
			if c.parent.parent == frame and c.shown and c.parent.shown then
				for _, group in pairs(c.groups) do assert(group.enabled) end
				count = count + 1
			end
		end
		assert(count == 2, "expected exactly one live buff/debuff pair")
	end
	return h
end

local tests = {}
function tests.combat_clear_and_reacquire_preserves_groups()
	local h = harness(); local f = h:new_frame(); h.aura:Update(f)
	h.combat = true; h.absent = f.unit
	h.aura:Update(f)
	local clears = h.aura.legacy_clears
	h.aura:OnHide(f)
	assert(h.aura.legacy_clears == clears, "OnHide bypassed the combat boundary")
	h.absent = nil
	h.aura:Update(f)
	h.aura:Lorenzo121RefreshDynamicNativeUnit(f.unit)
	h:assert_armed(f)
	assert(h.violations == 0 and #h.containers == 2)
	h:regen(); h:assert_armed(f)
end

function tests.precombat_unit_absence_does_not_suspend_groups()
	local h = harness(); local f = h:new_frame(); h.aura:Update(f)
	h.absent = f.unit; h.aura:Update(f)
	h.combat = true; h.absent = nil; h.aura:Update(f)
	h:assert_armed(f); assert(h.violations == 0)
end

function tests.hidden_frame_cleanup_waits_for_regen()
	local h = harness(); local f = h:new_frame(); h.aura:Update(f)
	h.combat = true; f.shown = false
	local clears = h.aura.legacy_clears
	h.aura:OnHide(f)
	assert(h.aura.legacy_clears == clears)
	h:regen()
	assert(h.aura.legacy_clears == clears + 1 and h.violations == 0)
end

function tests.combat_first_use_and_unit_change_defer_configuration()
	local h = harness(); local f = h:new_frame(); h.combat = true
	h.aura:Update(f)
	assert(#h.containers == 0 and h.aura.legacy_updates == 0)
	h:regen(); h:assert_armed(f)
	h.combat = true; f.unit = "focus"; h.aura:Update(f)
	assert(h.containers[1].unit == "targettarget" and h.violations == 0)
	h:regen(); assert(h.containers[1].unit == "focus")
end

function tests.transient_failure_recovers_without_another_aura_event()
	local h = harness(); local f = h:new_frame()
	h.fail_method = "AddAuraGroup"; h.aura:Update(f)
	assert(h.aura:Lorenzo121HasNativeFailures() and h:live_timers() == 1)
	h:advance(0.24); assert(h.failure_calls == 1 and h.aura:Lorenzo121HasNativeFailures())
	h:advance(0.02); h:assert_armed(f)
	assert(not h.aura:Lorenzo121HasNativeFailures() and h:live_timers() == 0)
	assert(h.aura:Lorenzo121NativeHandlesUnitAura(f.unit))
	assert(not h.aura:Lorenzo121ShouldRunLegacyAuraTicker())
	assert(f.db.max_buffs == 12 and f.db.layout.buff.filter_new == "!B")
end

function tests.persistent_failure_stops_after_three_retries()
	local h = harness(); local f = h:new_frame(); h.fail_method = "AddAuraGroup"; h.fail_always = true
	h.aura:Update(f)
	for _ = 1, 20 do h.aura:Update(f) end
	assert(h.failure_calls == 1 and h:live_timers() == 1)
	h:advance(10)
	assert(h.failure_calls == 4 and h:live_timers() == 0)
	for _ = 1, 5 do h:regen(); h.aura:Update(f) end
	h:advance(100); assert(h.failure_calls == 4 and h:live_timers() == 0)
	local status = table.concat(h.aura:Lorenzo121GetNativeStatusLines(), "\n")
	assert(status:find("attempts=4", 1, true) and status:find("retry=exhausted", 1, true))
	h.fail_method = nil; h.aura:Lorenzo121RebuildNativeContainers(); h:assert_armed(f)
	assert(not h.aura:Lorenzo121HasNativeFailures())
end

function tests.retry_waits_for_regen_without_spending_budget()
	local h = harness(); local f = h:new_frame(); h.fail_method = "AddAuraGroup"; h.aura:Update(f)
	h.combat = true; h:advance(1)
	for _ = 1, 10 do h.aura:Update(f) end
	assert(h.failure_calls == 1 and #h.containers == 1 and h.violations == 0)
	h:regen(); h:assert_armed(f); assert(not h.aura:Lorenzo121HasNativeFailures())
end

function tests.retry_coalesces_frames_and_pauses_hidden_or_disabled_layouts()
	local h = harness(); local a, b = h:new_frame(), h:new_frame("focus")
	h.fail_method = "AddAuraGroup"; h.fail_always = true
	h.aura:Update(a); h.aura:Update(b); assert(h:live_timers() == 1)
	a.shown = false; b.db.enabled = false; h:advance(1)
	assert(h.failure_calls == 2 and h:live_timers() == 0)
	h.fail_method = nil; a.shown = true; h.aura:Update(a); h:assert_armed(a)
	b.db.enabled = true; h.aura:Update(b); h:assert_armed(b)
end

function tests.configuration_exception_is_bounded_and_partial_groups_are_hidden()
	local h = harness(); local f = h:new_frame(); h.fail_method = "SetSize"
	h.aura:Update(f)
	assert(h.aura:Lorenzo121HasNativeFailures())
	h:advance(1); h:assert_armed(f)
	h.fail_method = "SetAuraGroupLayout"; h.fail_always = true
	h.aura:Update(f); h:advance(10)
	assert(h.aura:Lorenzo121HasNativeFailures() and h:live_timers() == 0)
	for _, c in ipairs(h.containers) do assert(not c.shown and not c.parent.shown) end
end

function tests.layout_disable_is_reconciled_after_combat()
	local h = harness(); local f = h:new_frame(); h.aura:Update(f)
	h.combat = true; f.db.enabled = false; h.aura:Update(f)
	assert(h.violations == 0)
	h:regen()
	for _, c in ipairs(h.containers) do assert(not c.shown and not c.parent.shown) end
	f.db.enabled = true; h.aura:Update(f); h:assert_armed(f)
end

function tests.module_disable_cancels_retry_and_defers_native_cleanup()
	local h = harness(); local f = h:new_frame(); h.aura:Update(f)
	local other = h:new_frame("focus"); h.fail_method = "AddAuraGroup"; h.aura:Update(other)
	assert(h:live_timers() == 1)
	h.combat = true; h.aura.enabled = false; h.aura:OnDisable()
	assert(h:live_timers() == 0 and h.violations == 0)
	h:advance(10); h:regen()
	for _, c in ipairs(h.containers) do assert(not c.shown and not c.parent.shown) end
	h.aura.enabled = true; h.aura:OnEnable(); h.aura:Update(f); h.aura:Update(other)
	h:assert_armed(f); h:assert_armed(other)
end

function tests.config_preview_and_buff_toggle_are_preserved()
	local h = harness(); local f = h:new_frame(); h.aura:Update(f)
	f.force_show = true; h.aura:UpdateFrame(f)
	assert(h.aura.legacy_updates == 1)
	for _, c in ipairs(h.containers) do assert(not c.shown) end
	f.force_show = nil; h.aura:Update(f); h:assert_armed(f)
	f.db.enabled_buffs = false; h.aura:Update(f)
	assert(not h.containers[1].shown and h.containers[2].shown)
	assert(h.containers[1].groups.pitbull_own.filter == "HELPFUL|PLAYER")
	assert(h.containers[1].groups.pitbull_other.filter == "HELPFUL|!PLAYER")
	assert(h.containers[2].groups.pitbull_own.max == 10)
end

local function legacy_control(h, protected, forbidden)
	local c = { shown = true }
	function c:IsForbidden() return forbidden end
	function c:IsProtected() assert(not forbidden); return protected end
	function c:IsShown() return self.shown end
	function c:Hide() assert(not protected and not forbidden); self.shown = false end
	function c:Show() assert(not h.combat); self.shown = true end
	return c
end

function tests.mixed_unit_aura_refreshes_native_and_suspends_failed_fallback()
	local h = harness(); local native, fallback = h:new_frame(), h:new_frame()
	h.aura:Update(native)
	h.fail_method = "AddAuraGroup"; h.fail_always = true; h.aura:Update(fallback)
	assert(h.aura:Lorenzo121NativeOwnsFrame(native))
	assert(not h.aura:Lorenzo121NativeOwnsFrame(fallback))
	assert(not h.aura:Lorenzo121NativeHandlesUnitAura(native.unit))
	local c = legacy_control(h, false); fallback.aura_buffs = { c }
	local updates = h.aura.legacy_updates
	h.combat = true; h.aura:UNIT_AURA("UNIT_AURA", native.unit)
	assert(h.containers[1].refreshes == 1 and h.containers[2].refreshes == 1)
	assert(not c.shown and h.aura.legacy_updates == updates and h.violations == 0)
	h:regen(); assert(c.shown and h.aura.legacy_updates > updates)
end

function tests.failed_initialization_clear_and_return_are_reconciled()
	local h = harness(); local f = h:new_frame()
	h.fail_method = "AddAuraGroup"; h.fail_always = true; h.aura:Update(f)
	local c = legacy_control(h, false); f.aura_debuffs = { c }
	h.combat = true; h.absent = f.unit; h.aura:Update(f)
	assert(not c.shown)
	h.absent = nil; h.aura:UNIT_AURA("UNIT_AURA", f.unit)
	assert(not c.shown and h.violations == 0)
	h:regen(); assert(c.shown)
end

function tests.fallback_onhide_defers_pool_cleanup_even_without_native_mode()
	local h = harness(); local f = h:new_frame()
	h.aura:Lorenzo121SetNativeEnabled(false)
	local c = legacy_control(h, false); f.aura_buffs = { c }
	local clears = h.aura.legacy_clears
	h.combat = true; f.shown = false; h.aura:OnHide(f)
	assert(not c.shown and h.aura.legacy_clears == clears)
	h:regen(); assert(h.aura.legacy_clears == clears + 1 and h.violations == 0)
end

function tests.protected_and_forbidden_fallback_controls_are_never_mutated()
	local h = harness(); local f = h:new_frame(); f.force_show = true
	local protected = legacy_control(h, true)
	local forbidden = legacy_control(h, false, true)
	f.aura_buffs = { protected, forbidden }; f.aura_highlight = protected
	h.combat = true; h.aura:UpdateFrame(f); h.aura:OnHide(f)
	assert(protected.shown and forbidden.shown and h.violations == 0)
end

function tests.native_combat_unit_aura_is_independent_of_other_frame_failure()
	local h = harness(); local f, other = h:new_frame(), h:new_frame("focus")
	h.aura:Update(f); h.fail_method = "AddAuraGroup"; h.aura:Update(other)
	assert(h.aura:Lorenzo121NativeHandlesUnitAura(f.unit))
	h.aura.LorenzoPatch105ShouldThrottleRaidUnitAura = function() return true end
	h.combat = true; h.aura:UNIT_AURA("UNIT_AURA", f.unit)
	assert(h.containers[1].refreshes == 1 and h.containers[2].refreshes == 1)
	h.absent = f.unit; h.aura:Update(f); h.absent = nil
	h.aura:UNIT_AURA("UNIT_AURA", f.unit)
	assert(h.containers[1].refreshes == 2 and h.violations == 0)
	h:assert_armed(f)
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
local failures = 0
for _, name in ipairs(names) do
	local ok, err = pcall(tests[name])
	if ok then print("PASS " .. name)
	else failures = failures + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
assert(failures == 0, tostring(failures) .. " native aura regression test(s) failed")
print(tostring(#names) .. " native aura recovery tests passed (" .. _VERSION .. ")")
