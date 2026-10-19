
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local PitBull4_Aura = PitBull4:NewModule("Aura")

PitBull4_Aura:SetModuleType("custom")
PitBull4_Aura:SetName(L["Aura"])
PitBull4_Aura:SetDescription(L["Shows buffs and debuffs for PitBull4 frames."])

PitBull4_Aura.OnProfileChanged_funcs = {}

local timerFrame = CreateFrame("Frame")
timerFrame:Hide()

local timer = 0
timerFrame:SetScript("OnUpdate",function(self, elapsed)
	timer = timer + elapsed
	if timer < 0.2 then return end
	timer = 0

	if not PitBull4_Aura.Lorenzo121ShouldRunLegacyAuraTicker or PitBull4_Aura:Lorenzo121ShouldRunLegacyAuraTicker() then
		PitBull4_Aura:UpdateWeaponEnchants()
	end
	PitBull4_Aura:UpdateFilters()
end)


function PitBull4_Aura:OnEnable()
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "Lorenzo121NativeRecoveryAfterCombat")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("UNIT_AURA")
	-- Patch 031: Blizzard's 12.1 AuraContainer tracks a unit token, not the
	-- identity behind a dynamic token. "target" therefore remains "target" when
	-- the player changes targets, and the native container needs an explicit
	-- re-parse to avoid displaying the previous unit's auras.
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "Lorenzo121DynamicAuraUnitChanged")
	self:RegisterEvent("PLAYER_FOCUS_CHANGED", "Lorenzo121DynamicAuraUnitChanged")
	self:RegisterEvent("UNIT_TARGET", "Lorenzo121DynamicAuraUnitChanged")
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "Lorenzo121DynamicAuraUnitChanged")
	-- Patch 042: a newly visible nameplate may refer to a different enemy
	-- while its literal unit token is unchanged. Request a native refresh.
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "Lorenzo121DynamicAuraUnitChanged")
	-- Roster/zone transitions can reuse party/raid unit tokens. Refresh
	-- their managed containers without inspecting protected aura payloads.
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "Lorenzo121RosterAuraUnitsChanged")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "Lorenzo121RosterAuraUnitsChanged")
	if self.Lorenzo121IsClient and self:Lorenzo121IsClient() then
		self:RegisterEvent("AURA_DATA_PROVIDER_SWITCH", "UpdateAll")
	end
	timerFrame:Show()

	-- Rescan spells that can change what we can dispel and purge.
	self:RegisterEvent("PLAYER_TALENT_UPDATE")
	self:RegisterEvent("SPELLS_CHANGED", "PLAYER_TALENT_UPDATE")
	self:PLAYER_TALENT_UPDATE()
end

function PitBull4_Aura:OnDisable()
	timerFrame:Hide()
	self:Lorenzo121CancelNativeRecovery()
	self:Lorenzo121DisableNativeFrames()
end

function PitBull4_Aura:OnProfileChanged()
	for _, func in next, self.OnProfileChanged_funcs do
		func(self)
	end
end


function PitBull4_Aura:PLAYER_REGEN_DISABLED()
	-- Forever AuraContainers own combat aura updates. Do not reconfigure them
	-- merely because combat started.
end

function PitBull4_Aura:PLAYER_ENTERING_WORLD()
	-- Midnight can populate some long player buffs, especially item/consumable
	-- buffs, a little after the initial frame build on /reload.  A few delayed
	-- rescans make existing flask/phial timers appear without requiring the buff
	-- to be reapplied.
	self:UpdateAll()
	-- Also reparse existing roster containers after an instance transfer.
	-- UpdateAll alone does not force an AuraContainer with the same unit token
	-- to re-query its current aura set. All refreshes stay in the native API.
	self:Lorenzo121RosterAuraUnitsChanged()
	if self.ScheduleTimer then
		self:ScheduleTimer("UpdateAll", 0.25)
		self:ScheduleTimer("UpdateAll", 1.0)
		self:ScheduleTimer("UpdateAll", 3.0)
		self:ScheduleTimer("Lorenzo121RosterAuraUnitsChanged", 0.25)
		self:ScheduleTimer("Lorenzo121RosterAuraUnitsChanged", 1.0)
	end
end

-- Patch 031: refresh managed containers when a dynamic unit token keeps the
-- same literal token but points at a different underlying unit. The native
-- renderer owns the actual refresh operation and never exposes aura data here.
-- v59: A target can disappear and return during combat before Blizzard's
-- managed AuraContainer has finished processing the unit transition. Retry
-- the existing, combat-safe refresh (UpdateAllAuras) after the transition;
-- never rebuild containers or change protected attributes in combat.
function PitBull4_Aura:Lorenzo59RetryTargetTargetAuras()
	if self.Lorenzo121RefreshDynamicNativeUnit then
		self:Lorenzo121RefreshDynamicNativeUnit("targettarget")
	end
end

local function schedule_targettarget_aura_retries(module)
	if module.ScheduleTimer and _G.InCombatLockdown and _G.InCombatLockdown() then
		module:ScheduleTimer("Lorenzo59RetryTargetTargetAuras", 0.12)
		module:ScheduleTimer("Lorenzo59RetryTargetTargetAuras", 0.4)
	end
end

function PitBull4_Aura:Lorenzo121DynamicAuraUnitChanged(event, unit)
	if not self.Lorenzo121RefreshDynamicNativeUnit then
		return
	end
	if event == "PLAYER_TARGET_CHANGED" then
		self:Lorenzo121RefreshDynamicNativeUnit("target")
		self:Lorenzo121RefreshDynamicNativeUnit("targettarget")
		schedule_targettarget_aura_retries(self)
	elseif event == "PLAYER_FOCUS_CHANGED" then
		self:Lorenzo121RefreshDynamicNativeUnit("focus")
		self:Lorenzo121RefreshDynamicNativeUnit("focustarget")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		self:Lorenzo121RefreshDynamicNativeUnit("mouseover")
	elseif event == "UNIT_TARGET" and type(unit) == "string" then
		self:Lorenzo121RefreshDynamicNativeUnit(unit .. "target")
		-- A newly acquired target can change targettarget without a separate
		-- PLAYER_TARGET_CHANGED event (notably after clearing target in combat).
		if unit == "target" then
			self:Lorenzo121RefreshDynamicNativeUnit("targettarget")
			schedule_targettarget_aura_retries(self)
		end
	elseif event == "NAME_PLATE_UNIT_ADDED" and type(unit) == "string" then
		self:Lorenzo121RefreshDynamicNativeUnit(unit)
	end
end

-- Refresh only existing native roster containers. Never rebuild or change
-- ownership filters while in combat; Blizzard owns protected aura state.
function PitBull4_Aura:Lorenzo121RosterAuraUnitsChanged()
	-- Native groups may need to switch between split and combined ownership
	-- when a roster unit becomes unreachable. Rebuild only out of combat.
	if not (_G.InCombatLockdown and _G.InCombatLockdown()) then
		self:UpdateAll()
	end
	if self.Lorenzo121RefreshRosterNativeUnits then
		self:Lorenzo121RefreshRosterNativeUnits()
	end
end

function PitBull4_Aura:UNIT_AURA(_, unit, update_info)
	-- 12.1 native containers own UNIT_AURA registration and process protected
	-- update payloads inside Blizzard's secure implementation. Avoid duplicate
	-- legacy frame scans while the native path is healthy.
	if self.Lorenzo121NativeHandlesUnitAura and self:Lorenzo121NativeHandlesUnitAura(unit) then
		return
	end

	-- Patch 105: raid UNIT_AURA storms can be very expensive with many visible
	-- group frames. When raid performance mode is active, coalesce repeated aura
	-- updates for non-player raid roster units by a tiny interval. Player/party/target
	-- frames and debuffs remain responsive; this only reduces duplicate raid spam.
	if self.LorenzoPatch105ShouldThrottleRaidUnitAura and self:LorenzoPatch105ShouldThrottleRaidUnitAura(unit) then
		return
	end
	for frame in PitBull4:IterateFrames() do
		local same_unit
		if self.Lorenzo121UnitsMatch then
			same_unit = self:Lorenzo121UnitsMatch(frame.unit, unit)
		else
			same_unit = frame.unit == unit
		end
		if same_unit then
			if self:GetLayoutDB(frame).enabled then
				self:UpdateFrame(frame)
			else
				self:ClearFrame(frame)
			end
		end
	end
end

function PitBull4_Aura:ClearFrame(frame)
	self:ClearAuras(frame)
	if frame.aura_highlight then
		frame.aura_highlight = frame.aura_highlight:Delete()
	end
end
PitBull4_Aura.OnHide = PitBull4_Aura.ClearFrame

function PitBull4_Aura:UpdateFrame(frame)
	self:UpdateSkin(frame)
	self:UpdateAuras(frame)
	self:LayoutAuras(frame)
end

function PitBull4_Aura:UpdateAll()
	for frame in PitBull4:IterateFrames() do
		self:Update(frame)
	end
end

function PitBull4_Aura:LibSharedMedia_Registered(event, mediatype, key)
	if mediatype == "font" then
		self:UpdateAll()
	end
end
