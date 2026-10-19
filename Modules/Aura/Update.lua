
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local PitBull4_Aura = PitBull4:GetModule("Aura")

local GetAuraApplicationDisplayCount = C_UnitAuras.GetAuraApplicationDisplayCount
local GetAuraDuration = C_UnitAuras.GetAuraDuration
local GetAuraDispelTypeColor = C_UnitAuras.GetAuraDispelTypeColor
local GetUnitAuras = C_UnitAuras.GetUnitAuras
local IsAuraFilteredOutByInstanceID = C_UnitAuras.IsAuraFilteredOutByInstanceID

local function lorenzo_121_safe_api_call(func, ...)
	if PitBull4_Aura.Lorenzo121SafeCall then
		return PitBull4_Aura:Lorenzo121SafeCall(func, ...)
	end
	if type(func) ~= "function" then
		return false, nil, "missing-function"
	end
	return pcall(func, ...)
end

local GetItemInfo = C_Item.GetItemInfo
local GetItemQualityColor = C_Item.GetItemQualityColor

-- The table we use for gathering the aura data, filtering
-- and then sorting them.
local list = {}

-- Table we store the weapon enchant info in.
local weapon_list = PitBull4_Aura.weapon_list

local function unit_comparison_is_secret(unit_a, unit_b)
	local checker = C_Secrets and C_Secrets.ShouldUnitComparisonBeSecret
	if not checker then
		return false
	end
	local ok, secret = pcall(checker, unit_a, unit_b)
	return ok and secret or false
end

local function safe_unit_is_unit(unit_a, unit_b)
	if not unit_a or not unit_b then
		return false
	end
	-- Do not use unit_a == unit_b before this check.  In Midnight even
	-- equality on a secret unit string can throw while PitBull is tainted.
	if unit_comparison_is_secret(unit_a, unit_b) then
		return false
	end
	local ok, same = pcall(UnitIsUnit, unit_a, unit_b)
	if ok then
		return same and true or false
	end
	local ok_equal, equal = pcall(function() return unit_a == unit_b end)
	return ok_equal and equal or false
end

-- Patch 105: raid performance mode. In raids, the largest recurring cost tends
-- to be aura timer text and native cooldown swipes on many non-player raid
-- frames. Keep the player/target/party behavior untouched, but automatically
-- suppress helpful-buff timer text on raid roster units. Debuffs remain active.
local LORENZO_PATCH105_RAID_UNIT_AURA_THROTTLE = 0.12
local lorenzo_patch105_raid_perf_enabled = true
local lorenzo_patch105_next_raid_unit_aura = {}

local function lorenzo_patch105_is_raid_roster_unit(unit)
	if not unit or issecretvalue(unit) then
		return false
	end
	local ok, unit_text = pcall(tostring, unit)
	if not ok or not unit_text then
		return false
	end
	return unit_text:match("^raid%d+$") ~= nil
end

local function lorenzo_patch105_raid_perf_active()
	return lorenzo_patch105_raid_perf_enabled and IsInRaid and IsInRaid()
end

function PitBull4_Aura:LorenzoPatch105SetRaidPerformanceMode(enabled)
	lorenzo_patch105_raid_perf_enabled = enabled and true or false
	wipe(lorenzo_patch105_next_raid_unit_aura)
	if self.UpdateAll then
		self:UpdateAll()
	end
end

function PitBull4_Aura:LorenzoPatch105GetRaidPerformanceMode()
	return lorenzo_patch105_raid_perf_enabled
end

function PitBull4_Aura:LorenzoPatch105RaidPerfActiveForUnit(unit)
	return lorenzo_patch105_raid_perf_active()
		and lorenzo_patch105_is_raid_roster_unit(unit)
		and not safe_unit_is_unit(unit, "player")
end

function PitBull4_Aura:LorenzoPatch105ShouldThrottleRaidUnitAura(unit)
	if not self:LorenzoPatch105RaidPerfActiveForUnit(unit) then
		return false
	end
	local now = GetTime and GetTime() or 0
	local next_allowed = lorenzo_patch105_next_raid_unit_aura[unit]
	if next_allowed and next_allowed > now then
		return true
	end
	lorenzo_patch105_next_raid_unit_aura[unit] = now + LORENZO_PATCH105_RAID_UNIT_AURA_THROTTLE
	return false
end

local function lorenzo_patch105_suppress_raid_helpful_buff_timers(unit, is_buff)
	return is_buff and PitBull4_Aura:LorenzoPatch105RaidPerfActiveForUnit(unit)
end


local LORENZO_KNOWN_LONG_BUFF_TERMS = {
	-- Keep the old plural alias for safety, but include the real Midnight aura
	-- name: "Blessing of Potency".
	"blessing of potency",
	"blessings of potency",
	"mastery of timeways",
	"knowledge of timeways",
}

local LORENZO_KNOWN_LONG_BUFF_SPELL_IDS = {
	-- Spell IDs only for the two targeted long-buff families.  Do not add Flask of
	-- the Shattered Sun here; Flask already works and must remain untouched.
	["1272300"] = true, -- Blessing of Potency stat aura
	["1272321"] = true, -- Blessing of Potency item-effect buff (1 day)
	["423860"] = true,  -- Knowledge of Timeways
	["423861"] = true,  -- Mastery of Timeways
	["1229050"] = true, -- Mastery of Timeways, current/beta duplicate
}

-- When a key starts, Midnight can make the aura name/spell id secret for
-- Timeways/Potency. Remember icons that were previously identified as targeted
-- long-buffs, then use that icon match later if name/spell is hidden.
local LORENZO_KNOWN_LONG_BUFF_ICONS = {}

-- Inside a key, the same Blessing of Potency aura can keep its auraInstanceID
-- while name, spell, icon, expirationTime, timeMod, count, and duration payload
-- become secret. Remember only player auraInstanceIDs that were already proven
-- to be targeted Potency/Timeways long-buffs, then allow that ID to keep the
-- narrow long-buff guard active after zoning. This deliberately does not add any
-- Flask spell, name, or icon handling.
local LORENZO_KNOWN_LONG_BUFF_INSTANCE_IDS = {}
local LORENZO_KNOWN_LONG_BUFF_INSTANCE_TTL = 1800

local function lorenzo_safe_cache_key(value)
	if value == nil or issecretvalue(value) then
		return nil
	end
	local ok, key = pcall(tostring, value)
	if ok and key and key ~= "" then
		return key
	end
	return nil
end

local function lorenzo_known_long_buff_instance_key(aura, unit)
	if not aura or not aura.isHelpfulAura or not safe_unit_is_unit(unit, "player") then
		return nil
	end
	local instance_id = lorenzo_safe_cache_key(aura.auraInstanceID)
	if instance_id then
		return "player-id:" .. instance_id
	end
	return nil
end

local function lorenzo_remember_known_long_buff_instance(aura, unit)
	local key = lorenzo_known_long_buff_instance_key(aura, unit)
	if key then
		LORENZO_KNOWN_LONG_BUFF_INSTANCE_IDS[key] = (GetTime and GetTime() or 0) + LORENZO_KNOWN_LONG_BUFF_INSTANCE_TTL
	end
end

local function lorenzo_is_remembered_known_long_buff_instance(aura, unit)
	local key = lorenzo_known_long_buff_instance_key(aura, unit)
	if not key then
		return false
	end
	local until_time = LORENZO_KNOWN_LONG_BUFF_INSTANCE_IDS[key]
	if not until_time then
		return false
	end
	local now = GetTime and GetTime() or 0
	if until_time <= now then
		LORENZO_KNOWN_LONG_BUFF_INSTANCE_IDS[key] = nil
		return false
	end
	return true
end

local function lorenzo_remember_known_long_buff_icon(aura)
	if not aura then
		return
	end
	local icon_key = lorenzo_safe_cache_key(aura.icon)
	if icon_key then
		LORENZO_KNOWN_LONG_BUFF_ICONS[icon_key] = true
	end
end

local function lorenzo_is_known_long_buff_icon(aura)
	if not aura then
		return false
	end
	local icon_key = lorenzo_safe_cache_key(aura.icon)
	return icon_key and LORENZO_KNOWN_LONG_BUFF_ICONS[icon_key] or false
end


local function lorenzo_safe_lower(value)
	if value == nil or issecretvalue(value) or type(value) ~= "string" then
		return nil
	end
	local ok, lowered = pcall(string.lower, value)
	if ok then
		return lowered
	end
	return nil
end

local function lorenzo_is_known_long_buff(aura)
	if not aura or not aura.isHelpfulAura then
		return false
	end
	-- Keep known-long-buff recognition limited to the targeted Potency/Timeways
	-- aura families. Weapon enchants must not inherit the cache or zero guard from
	-- a recycled aura button. Recognize these long buffs by spell id before falling
	-- back to names/icons, because at key entry Midnight can expose a spell id while
	-- the duration data is incomplete.
	local spell_id = lorenzo_safe_cache_key(aura.spellId or aura.spellID)
	if spell_id and LORENZO_KNOWN_LONG_BUFF_SPELL_IDS[spell_id] then
		lorenzo_remember_known_long_buff_icon(aura)
		return true
	end

	local name = lorenzo_safe_lower(aura.name)
	if name then
		for i = 1, #LORENZO_KNOWN_LONG_BUFF_TERMS do
			if name:find(LORENZO_KNOWN_LONG_BUFF_TERMS[i], 1, true) then
				lorenzo_remember_known_long_buff_icon(aura)
				return true
			end
		end
	end
	return lorenzo_is_known_long_buff_icon(aura)
end


local function lorenzo_is_zero_duration_text(value)
	if value == nil or issecretvalue(value) then
		return false
	end
	if type(value) == "number" then
		return value == 0
	end
	if type(value) ~= "string" then
		return false
	end
	local ok, text = pcall(function()
		return value:gsub("%s+", ""):lower()
	end)
	if not ok or not text then
		return false
	end
	return text == "0" or text == "0s" or text == "0sec" or text == "0secs" or text == "0sek" or text == "0sek."
end

local function lorenzo_is_hidden_midnight_value(value)
	return value == nil or issecretvalue(value)
end

local function lorenzo_has_secret_player_helpful_identity(aura, unit)
	if not aura or not aura.isHelpfulAura then
		return false
	end
	if not safe_unit_is_unit(unit, "player") then
		return false
	end
	return lorenzo_is_hidden_midnight_value(aura.name)
		and lorenzo_is_hidden_midnight_value(aura.spellId or aura.spellID)
		and lorenzo_is_hidden_midnight_value(aura.icon)
end

local function lorenzo_clear_zero_font_string(font_string)
	if not font_string or not font_string.GetText or not font_string.SetText then
		return
	end
	local ok, text = pcall(font_string.GetText, font_string)
	if ok and lorenzo_is_zero_duration_text(text) then
		-- Do not Hide() PitBull's own FontStrings here; later valid cached/formatted
		-- timer text must be able to reappear normally.  The short guard window will
		-- keep clearing any native cooldown number that tries to rewrite 0s.
		font_string:SetText("")
	end
end

local function lorenzo_clear_zero_regions(frame, depth)
	if not frame or depth > 2 then
		return
	end
	if frame.GetRegions then
		local regions = { frame:GetRegions() }
		for i = 1, #regions do
			local region = regions[i]
			if region and region.GetObjectType then
				local ok_type, object_type = pcall(region.GetObjectType, region)
				if ok_type and object_type == "FontString" then
					lorenzo_clear_zero_font_string(region)
				end
			end
		end
	end
	if frame.GetChildren then
		local children = { frame:GetChildren() }
		for i = 1, #children do
			lorenzo_clear_zero_regions(children[i], depth + 1)
		end
	end
end

local function lorenzo_clear_known_long_buff_zero_text(control)
	if not control then
		return
	end
	lorenzo_clear_zero_font_string(control.count_text)
	lorenzo_clear_zero_font_string(control.cooldown_text)
	lorenzo_clear_zero_regions(control.cooldown, 0)
end

-- Reduce the remaining cleanup cost in normal play. The known-long-buff zero
-- guard is still available for secret Mythic+ rebuilds, but it is throttled and
-- only runs when the current aura payload looks incomplete/secret.
local LORENZO_PATCH94_ZERO_GUARD_DURATION = 3
local LORENZO_PATCH94_ZERO_GUARD_INTERVAL = 0.20

local function lorenzo_known_long_buff_zero_guard_on_update(control, elapsed)
	local until_time = control.lorenzo_long_buff_zero_guard_until
	if not until_time or until_time <= GetTime() then
		control.lorenzo_long_buff_zero_guard_until = nil
		control.lorenzo_long_buff_zero_guard_elapsed = nil
		control:SetScript("OnUpdate", nil)
		return
	end
	control.lorenzo_long_buff_zero_guard_elapsed = (control.lorenzo_long_buff_zero_guard_elapsed or 0) + (elapsed or 0)
	if control.lorenzo_long_buff_zero_guard_elapsed < LORENZO_PATCH94_ZERO_GUARD_INTERVAL then
		return
	end
	control.lorenzo_long_buff_zero_guard_elapsed = 0
	lorenzo_clear_known_long_buff_zero_text(control)
end

local function lorenzo_start_known_long_buff_zero_guard(control, run_timed_guard)
	if not control then
		return
	end
	local cooldown = control.cooldown
	if cooldown then
		cooldown.noCooldownCount = true
		if cooldown.SetHideCountdownNumbers then
			pcall(cooldown.SetHideCountdownNumbers, cooldown, true)
		end
	end
	lorenzo_clear_known_long_buff_zero_text(control)
	if run_timed_guard then
		control.lorenzo_long_buff_zero_guard_until = GetTime() + LORENZO_PATCH94_ZERO_GUARD_DURATION
		control.lorenzo_long_buff_zero_guard_elapsed = LORENZO_PATCH94_ZERO_GUARD_INTERVAL
		control:SetScript("OnUpdate", lorenzo_known_long_buff_zero_guard_on_update)
	else
		control.lorenzo_long_buff_zero_guard_until = nil
		control.lorenzo_long_buff_zero_guard_elapsed = nil
		control:SetScript("OnUpdate", nil)
	end
end

local function lorenzo_stop_known_long_buff_zero_guard(control, db)
	if not control then
		return
	end
	control.lorenzo_long_buff_zero_guard_until = nil
	control.lorenzo_long_buff_zero_guard_elapsed = nil
	control:SetScript("OnUpdate", nil)
	if control.cooldown then
		control.cooldown.noCooldownCount = db and db.suppress_occ or nil
		if control.cooldown.SetHideCountdownNumbers then
			pcall(control.cooldown.SetHideCountdownNumbers, control.cooldown, true)
		end
	end
end


-- Optional focused scanner for key-entry aura diagnostics. It stays dormant
-- unless /pitbull debugon enabled the debug mode.
local function lorenzo_patch93_debug_enabled()
	return PitBull4_Aura.LorenzoPatch93IsDebugEnabled and PitBull4_Aura:LorenzoPatch93IsDebugEnabled()
end

local LORENZO_PATCH83_DEBUG_CONTROLS = {}
local lorenzo_patch83_debug_scan_frame = CreateFrame("Frame")
lorenzo_patch83_debug_scan_frame:Hide()
local lorenzo_patch83_debug_elapsed = 0
lorenzo_patch83_debug_scan_frame:SetScript("OnUpdate", function(self, elapsed)
	if not lorenzo_patch93_debug_enabled() then
		wipe(LORENZO_PATCH83_DEBUG_CONTROLS)
		self:Hide()
		return
	end
	lorenzo_patch83_debug_elapsed = lorenzo_patch83_debug_elapsed + elapsed
	if lorenzo_patch83_debug_elapsed < 0.20 then
		return
	end
	lorenzo_patch83_debug_elapsed = 0
	local now = GetTime()
	local any = false
	for control in pairs(LORENZO_PATCH83_DEBUG_CONTROLS) do
		if not control or not control.lorenzo_patch83_debug_until or control.lorenzo_patch83_debug_until <= now then
			LORENZO_PATCH83_DEBUG_CONTROLS[control] = nil
		else
			any = true
			if PitBull4_Aura.LorenzoPatch83ScanZeroText then
				PitBull4_Aura:LorenzoPatch83ScanZeroText(control, "watch-zero")
			end
		end
	end
	if not any then
		self:Hide()
	end
end)

local function lorenzo_patch83_start_debug_watch(control)
	if not control or not lorenzo_patch93_debug_enabled() then
		return
	end
	control.lorenzo_patch83_debug_until = GetTime() + 10
	LORENZO_PATCH83_DEBUG_CONTROLS[control] = true
	lorenzo_patch83_debug_scan_frame:Show()
end

local function is_player_owned_aura(entry, unit, player_filter, is_buff)
	if entry.auraInstanceID then
		local filtered_ok, filtered = lorenzo_121_safe_api_call(IsAuraFilteredOutByInstanceID, unit, entry.auraInstanceID, player_filter)
		if filtered_ok and not filtered then
			return true
		end
	end

	-- Midnight exposes several aura sources differently depending on spell/item.
	-- Consumables such as flasks/phials can fail the HELPFUL|PLAYER filter even
	-- though they are effectively the player's own buff.  Prefer explicit source
	-- fields when Blizzard provides them, then fall back to self-buffs without a
	-- source so their cooldown text follows the "my buffs" settings.
	if entry.isFromPlayerOrPlayerPet then
		return true
	end
	if safe_unit_is_unit(entry.sourceUnit, "player") then
		return true
	end

	-- On /reload Midnight can restore long player buffs such as flasks/phials
	-- without a reliable sourceUnit/player-filter match.  If the aura is helpful
	-- and it is on the actual player frame, treat it as a player aura so it uses
	-- the "my buffs" text/cooldown settings.  This fixes existing flask timers
	-- that otherwise only appear after reapplying the consumable.
	if is_buff and safe_unit_is_unit(unit, "player") then
		return true
	end
	return false
end

-- constants for the slot ids
local INVSLOT_MAINHAND = _G.INVSLOT_MAINHAND
local INVSLOT_OFFHAND = _G.INVSLOT_OFFHAND

-- constants for building sample auras
local sample_buff_icon   = [[Interface\Icons\Spell_ChargePositive]]
local sample_debuff_icon = [[Interface\Icons\Spell_ChargeNegative]]
local sample_debuff_types = { "Poison", "Magic", "Disease", "Curse", "Enrage", "Bleed", "None" }
local sample_duration = C_DurationUtil.CreateDuration()

-- color curve for the dispel type
local dispel_color_curve = C_CurveUtil.CreateColorCurve()
dispel_color_curve:SetType(Enum.LuaCurveType.Step)
PitBull4_Aura.dispel_color_curve = dispel_color_curve

local dispel_types = {
	None = 0,
	Magic = 1,
	Curse = 2,
	Disease = 3,
	Poison = 4,
	Enrage = 9,
	Bleed = 11,
}

-- Fills an array of arrays with the information about the auras
local function get_aura_list(list, unit, db, is_buff, frame)
	if not unit then
		wipe(list)
		return list
	end
	local filter = is_buff and "HELPFUL" or "HARMFUL"
	local player_filter = is_buff and "HELPFUL|PLAYER" or "HARMFUL|PLAYER"
	local max_auras = is_buff and db.max_buffs or db.max_debuffs
	local sort_rule = Enum.UnitAuraSortRule[(is_buff and db.layout.buff.sort_rule or db.layout.debuff.sort_rule) or "Unsorted"]
	local sort_direction = (is_buff and db.layout.buff.reverse or db.layout.debuff.reverse) and 1 or 0 -- Enum.UnitAuraSortDirection
	local filter_name = is_buff and db.layout.buff.filter_new or db.layout.debuff.filter_new

	-- Loop through the auras.  In Midnight, some aura reads can fail when the
	-- unit/aura is secret or the call is made on a restricted path.  A failed aura
	-- update should clear the displayed aura list instead of breaking all frames.
	local ok, auras = lorenzo_121_safe_api_call(GetUnitAuras, unit, filter, max_auras, sort_rule, sort_direction)
	if not ok or not auras then
		wipe(list)
		return list
	end

	local index = 1
	for _, entry in next, auras do
		entry.index = index
		entry.id = entry.auraInstanceID
		entry.isPlayerAura = is_player_owned_aura(entry, unit, player_filter, is_buff)
		entry.isHelpfulAura = is_buff
		entry.isHarmfulAura = not is_buff

		-- Filter the list if not true
		local filter_ok, passes = pcall(PitBull4_Aura.FilterEntry, PitBull4_Aura, filter_name, entry, frame)
		if filter_ok and passes then
			list[index] = entry
			index = index + 1
		end
	end

	-- Clear the list of extra entries
	for i = index, #list do
		list[i] = nil
	end

	return list
end

-- Fills up to the maximum number of auras with sample auras
local function get_aura_list_sample(list, unit, max, db, is_buff, is_player)
	-- figure the slot to use for the mainhand and offhand slots
	local mainhand, offhand
	if is_buff and db.enabled_weapons and unit and is_player then
		local mh, oh = weapon_list[INVSLOT_MAINHAND], weapon_list[INVSLOT_OFFHAND]
		if not mh or not mh[2] then
			mainhand = #list + 1
		end
		if not oh or not oh[2] then
			offhand = (mainhand and mainhand + 1) or #list + 1
		end
	end

	local num_entries = #list
	for i = num_entries + 1, max do
		local entry = list[i]
		if not entry then
			entry = {}
			list[i] = entry
		end

		-- Create our bogus aura entry
		entry.index = 0 -- index 0 means PitBull generated aura
		if i == mainhand then
			entry.weaponEnchantSlot = INVSLOT_MAINHAND
			entry.weaponEnchantQuality = GetInventoryItemQuality("player", entry.weaponEnchantSlot) or Enum.ItemQuality.Epic
			entry.name = L["Sample Weapon Enchant"]
			entry.debuffType = nil -- no debuff type
			entry.isPlayerAura = true
		elseif i == offhand then
			entry.weaponEnchantSlot = INVSLOT_OFFHAND
			entry.weaponEnchantQuality = GetInventoryItemQuality("player", entry.weaponEnchantSlot) or Enum.ItemQuality.Epic
			entry.name = L["Sample Weapon Enchant"]
			entry.debuffType = nil -- no debuff type
			entry.isPlayerAura = true
		else
			entry.weaponEnchantSlot = nil -- not a weapon enchant
			entry.weaponEnchantQuality = nil -- no quality color
			entry.name = is_buff and L["Sample Buff"] or L["Sample Debuff"]
			entry.debuffType = dispel_types[sample_debuff_types[(i - 1) % #sample_debuff_types]]
			entry.isPlayerAura = (i - num_entries < 5) and true or false -- (show 4 player entries)
		end
		entry.isHelpfulAura = is_buff
		entry.isHarmfulAura = not is_buff
		entry.icon = is_buff and sample_buff_icon or sample_debuff_icon
		entry.applications = i -- count set to index to make order show
		entry.duration = sample_duration
	end
end

local aura_sort__is_only

local function aura_sort(a, b)
	if not a then
		return false
	elseif not b then
		return true
	end

	-- item buffs
	local a_slot, b_slot = a.weaponEnchantSlot, b.weaponEnchantSlot
	if a_slot and not b_slot then
		return true
	elseif not a_slot and b_slot then
		return false
	elseif a_slot and b_slot then
		return a_slot < b_slot
	end

	-- player auras (skip for NameOnly/ExpirationOnly)
	if not aura_sort__is_only then
		local a_mine, b_mine = a.isPlayerAura, b.isPlayerAura
		if a_mine ~= b_mine then
			if a_mine then
				return true
			elseif b_mine then
				return false
			end
		end
	end

	-- real auras
	local a_index, b_index = a.index, b.index
	if a_index ~= 0 and b_index == 0 then
		return true
	elseif a_index == 0 and b_index ~= 0 then
		return false
	end

	-- name
	if a_index == 0 and b_index == 0 then
		local a_name, b_name = a.name, b.name
		if a_name ~= b_name then
			if not a_name then
				return true
			elseif not b_name then
				return false
			end
			return a_name < b_name
		end
	end

	-- index order
	return a_index < b_index
end

-- Setups up the aura frame and fill it with the proper data
-- to display the proper aura.
local function set_aura(frame, db, aura_controls, aura, i, is_friend)
	local control = aura_controls[i]
	if not control then
		control = PitBull4.Controls.MakeAura(frame)
		control.cooldown.noCooldownCount = db.suppress_occ or nil
		aura_controls[i] = control
	end

	local unit = frame.unit
	local is_mine = aura.isPlayerAura
	local who = is_mine and "my" or "other"
	-- No way to know who applied a weapon buff so we have a separate category for them.
	if aura.weaponEnchantSlot then who = "weapon" end
	local rule = who .. '_' .. (aura.isHelpfulAura and "buffs" or "debuffs")
	local lorenzo_patch105_skip_raid_buff_timers = lorenzo_patch105_suppress_raid_helpful_buff_timers(unit, aura.isHelpfulAura)

	local layout = aura.isHelpfulAura and db.layout.buff or db.layout.debuff
	control:SetFrameLevel(frame:GetFrameLevel() + layout.frame_level)

	control.unit = unit
	control.index = aura.index
	control.is_config_sample = aura.index == 0
	control.id = aura.auraInstanceID
	control.is_mine = aura.isPlayerAura
	control.is_buff = aura.isHelpfulAura
	control.slot = aura.weaponEnchantSlot
	control.expiration_time = aura.expirationTime
	control.time_mod = aura.timeMod or 1
	control.name = aura.name
	control.icon = aura.icon
	control.spell_id = aura.spellId or aura.spellID
	control.lorenzo_secret_player_helpful_identity = lorenzo_has_secret_player_helpful_identity(aura, unit)
	if control.count_text then
		control.count_text.lorenzo_aura_control = control
	end
	if control.cooldown_text then
		control.cooldown_text.lorenzo_aura_control = control
	end
	local lorenzo_known_long_buff_by_identity = lorenzo_is_known_long_buff(aura)
	if lorenzo_known_long_buff_by_identity then
		lorenzo_remember_known_long_buff_instance(aura, unit)
	end
	control.lorenzo_known_long_buff = lorenzo_known_long_buff_by_identity or lorenzo_is_remembered_known_long_buff_instance(aura, unit)
	if control.lorenzo_known_long_buff then
		control.lorenzo_last_known_long_buff_seen = GetTime()
	end
	-- Do not keep the functional zero guard alive merely because this aura button
	-- recently displayed Potency/Timeways. A recycled button could carry cached
	-- Potency text onto another player buff with no real duration, so the guard now
	-- requires a confirmed Potency/Timeways identity, including the player
	-- auraInstanceID cache.
	control.lorenzo_long_buff_zero_guard = control.lorenzo_known_long_buff
	if control.lorenzo_long_buff_zero_guard then
		local lorenzo_patch94_timed_guard = control.lorenzo_secret_player_helpful_identity
			or lorenzo_is_hidden_midnight_value(aura.expirationTime)
			or (aura.timeMod ~= nil and issecretvalue(aura.timeMod))
			or lorenzo_is_zero_duration_text(aura.applications)
		lorenzo_start_known_long_buff_zero_guard(control, lorenzo_patch94_timed_guard)
	else
		lorenzo_stop_known_long_buff_zero_guard(control, db)
	end
	if aura.isHelpfulAura and safe_unit_is_unit(unit, "player") then
		if PitBull4_Aura.LorenzoPatch90RememberPlayerAuraDisplay then
			-- Cache the safe pre-instance display state for each confirmed Potency/Timeways
			-- player auraInstanceID. This functional cache stays active, but diagnostics
			-- below only run while /pitbull debugon is enabled.
			PitBull4_Aura:LorenzoPatch90RememberPlayerAuraDisplay(control)
		end
		if lorenzo_patch93_debug_enabled() then
			lorenzo_patch83_start_debug_watch(control)
			if PitBull4_Aura.LorenzoPatch84RegisterAuraControl then
				PitBull4_Aura:LorenzoPatch84RegisterAuraControl(control)
			end
			if PitBull4_Aura.LorenzoPatch84DebugAuraLine then
				local lorenzo_patch84_debug_this = control.lorenzo_long_buff_zero_guard or lorenzo_is_zero_duration_text(control.count)
				if not lorenzo_patch84_debug_this then
					local lorenzo_name = lorenzo_safe_lower(control.name)
					lorenzo_patch84_debug_this = lorenzo_name and (lorenzo_name:find("potency", 1, true) or lorenzo_name:find("timeways", 1, true) or lorenzo_name:find("timeway", 1, true))
				end
				if lorenzo_patch84_debug_this then
					PitBull4_Aura:LorenzoPatch84DebugAuraLine(control, "set-aura", "player-helpful")
				end
			end
		end
	end
	if aura.auraInstanceID then
		local duration_ok, duration = lorenzo_121_safe_api_call(GetAuraDuration, unit, aura.auraInstanceID)
		control.duration = duration_ok and duration or nil
		if not control.duration then
			control.duration = aura.duration
		end
		if control.lorenzo_long_buff_zero_guard then
			-- These specific long buffs can make GetAuraApplicationDisplayCount surface
			-- timer-like values instead of real stacks during Midnight combat/reorder
			-- paths. Keep this hidden during the short recycled-button guard window,
			-- because Potency can enter the key with incomplete aura data.
			control.count = nil
		else
			local count_ok, count = lorenzo_121_safe_api_call(GetAuraApplicationDisplayCount, unit, aura.auraInstanceID, 2)
			-- Defensive guard: real stack counts should not be formatted as 0s. If
			-- Midnight leaks a timer-like zero through the display-count API, do not
			-- render it as a count on the icon. This does not touch Flask duration
			-- logic or valid stack counts.
			control.count = count_ok and not lorenzo_is_zero_duration_text(count) and count or nil
		end
	else -- used in config mode
		control.name = aura.name
		control.duration = aura.duration
		control.count = C_StringUtil.TruncateWhenZero(aura.applications)
		control.debuff_type = aura.debuffType
	end

	if aura.isHelpfulAura and safe_unit_is_unit(unit, "player") and PitBull4_Aura.LorenzoPatch90RememberPlayerAuraDisplay then
		-- Run this again after GetAuraDuration(), so no-duration buffs with nil
		-- expirationTime can still cache an intentional blank via DurationObject:IsZero().
		PitBull4_Aura:LorenzoPatch90RememberPlayerAuraDisplay(control)
	end

	local class_db = frame.classification_db
	if not db.click_through and class_db and not class_db.click_through then
		control:EnableMouse(true)
	else
		control:EnableMouse(false)
	end

	local texture = control.texture
	texture:SetTexture(aura.icon)
	if not frame.masque_group then
		if db.zoom_aura then
			texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		else
			texture:SetTexCoord(0, 1, 0, 1)
		end
	end

	if db.cooldown[rule] and not lorenzo_patch105_skip_raid_buff_timers and control.duration and control.cooldown.SetCooldownFromDurationObject then
		-- PitBull draws its own aura duration text. Hide native Cooldown countdown
		-- numbers so permanent/secret zero-duration auras cannot leak Blizzard's
		-- internal "0s" text over the icon.
		if control.cooldown.SetHideCountdownNumbers then
			pcall(control.cooldown.SetHideCountdownNumbers, control.cooldown, true)
		end
		if control.lorenzo_long_buff_zero_guard then
			-- For the Timeways/Potency long-buff path, do not feed the native Blizzard
			-- Cooldown during key-start/re-entry rebuilds. PitBull's own cooldown_text
			-- remains enabled below, so valid cached or formatted long-buff timers can
			-- still be shown.
			control.cooldown:Hide()
			lorenzo_clear_known_long_buff_zero_text(control)
		else
			local ok = pcall(control.cooldown.SetCooldownFromDurationObject, control.cooldown, control.duration, true)
			if ok then
				control.cooldown:Show()
			else
				control.cooldown:Hide()
			end
		end
	else
		control.cooldown:Hide()
	end

	local texts_db = db.texts[rule]

	local count_db = texts_db.count
	local font, font_size = frame:GetFont(count_db.font, count_db.size)
	local count_text = control.count_text
	count_text:ClearAllPoints()
	count_text:SetPoint(count_db.anchor, control, count_db.anchor, count_db.offset_x, count_db.offset_y)
	count_text:SetFont(font, font_size, "OUTLINE")
	count_text:SetTextColor(unpack(count_db.color))
	count_text:SetText(control.count)
	if lorenzo_patch93_debug_enabled() and PitBull4_Aura.LorenzoPatch83ScanZeroText then
		PitBull4_Aura:LorenzoPatch83ScanZeroText(control, "after-count-text")
	end
	if control.lorenzo_long_buff_zero_guard then
		lorenzo_clear_known_long_buff_zero_text(control)
	end

	if db.cooldown_text[rule] and not lorenzo_patch105_skip_raid_buff_timers then
		local cooldown_text = control.cooldown_text
		local cooldown_text_db = texts_db.cooldown_text
		font,font_size = frame:GetFont(cooldown_text_db.font, cooldown_text_db.size)
		cooldown_text:SetFont(font, font_size, "OUTLINE")
		cooldown_text:ClearAllPoints()
		cooldown_text:SetPoint(cooldown_text_db.anchor, control, cooldown_text_db.anchor, cooldown_text_db.offset_x, cooldown_text_db.offset_y)
		if not cooldown_text_db.color_by_time then
			cooldown_text:SetTextColor(unpack(cooldown_text_db.color))
		end
		cooldown_text.color_by_time = cooldown_text_db.color_by_time
		cooldown_text.lorenzo_known_long_buff = control.lorenzo_known_long_buff
		cooldown_text.lorenzo_long_buff_zero_guard = control.lorenzo_long_buff_zero_guard
		if not control.lorenzo_known_long_buff then
			-- This FontString may have belonged to Potency one frame ago. Clear only the
			-- local long-buff leftovers when the current aura is not a confirmed
			-- Potency/Timeways entry; the normal cooldown-text updater will immediately
			-- write the current aura's own timer if it has one.
			cooldown_text.lorenzo_last_known_long_text = nil
			cooldown_text.lorenzo_last_known_long_key = nil
			cooldown_text:SetText("")
			pcall(cooldown_text.SetAlpha, cooldown_text, 1)
		end
		if control.lorenzo_known_long_buff then
			-- The aura button can be recycled while Midnight is still rebuilding key-start
			-- aura data. Clear stale 0s immediately for the known Timeways/Potency path
			-- before the timed updater runs.
			cooldown_text:SetText("")
			pcall(cooldown_text.SetAlpha, cooldown_text, 1)
		end
		PitBull4_Aura:EnableCooldownText(control)
		if control.lorenzo_long_buff_zero_guard then
			lorenzo_clear_known_long_buff_zero_text(control)
		end
		if control.lorenzo_known_long_buff and PitBull4_Aura.LorenzoPatch87PrimeKnownLongBuffText then
			-- Show the safe expirationTime-derived value immediately after the FontString
			-- is configured, instead of leaving a blank/recycled value until the next
			-- periodic cooldown-text tick.
			PitBull4_Aura:LorenzoPatch87PrimeKnownLongBuffText(control)
		end
	else
		PitBull4_Aura:DisableCooldownText(control)
	end
	if lorenzo_patch93_debug_enabled() and PitBull4_Aura.LorenzoPatch83ScanZeroText then
		PitBull4_Aura:LorenzoPatch83ScanZeroText(control, "after-cooldown-text")
	end

	local border_db
	if who == "weapon" then
		border_db = db.borders[rule]
	else
		border_db = db.borders[rule][is_friend and "friend" or "enemy"]
	end
	if border_db.enabled then
		local border = control.border
		local colors = PitBull4_Aura.db.profile.global.colors
		border:Show()

		local color_type = border_db.color_type
		if color_type == "weapon" and aura.weaponEnchantQuality then
			local r, g, b = GetItemQualityColor(aura.weaponEnchantQuality)
			border:SetVertexColor(r, g, b)

		elseif color_type == "type" then
			-- Use the Other color if there's not a color for the specific debuff type.
			local color = nil
			if aura.auraInstanceID then
				local color_ok, aura_color = lorenzo_121_safe_api_call(GetAuraDispelTypeColor, unit, aura.auraInstanceID, dispel_color_curve)
				color = color_ok and aura_color or nil
			elseif aura.debuffType then
				color = dispel_color_curve:Evaluate(aura.debuffType)
			end
			if color == nil then
				color = dispel_color_curve:Evaluate(0)
			end
			border:SetVertexColor(color:GetRGB())

		elseif color_type == "caster" then
			border:SetVertexColor(unpack(colors.caster[who]))

		elseif color_type == "custom" and border_db.custom_color then
			border:SetVertexColor(unpack(border_db.custom_color))
		else
			-- Unknown color type just set it to red, shouldn't actually ever get here.
			border:SetVertexColor(1,0,0)
		end
	else
		control.border:Hide()
	end
end

local compare_units = safe_unit_is_unit

-- If the src table has a valid weapon enchant entry for the slot
-- copy it to the dst table.  Uses #dst + 1 to determine next entry
local function copy_weapon_entry(src, dst, slot)
	local entry = src[slot]
	if entry and entry.weaponEnchantSlot then
		dst[#dst + 1] = CopyTable(entry)
	end
end

local function update_auras(frame, db, is_buff)
	-- Get the controls table
	local controls
	if is_buff then
		controls = frame.aura_buffs
		if not controls then
			controls = {}
			frame.aura_buffs = controls
		end
	else
		controls = frame.aura_debuffs
		if not controls then
			controls = {}
			frame.aura_debuffs = controls
		end
	end

	local unit = frame.unit
	local is_player = compare_units(unit, "player")
	local is_friend = unit and UnitIsFriend("player", unit)
	local max_auras = is_buff and db.max_buffs or db.max_debuffs

	get_aura_list(list, unit, db, is_buff, frame)

	-- If weapons are enabled and the unit is the player
	-- copy the weapon entries into the aura list
	if is_buff and db.enabled_weapons and is_player then
		local filter = db.layout.buff.filter_new
		copy_weapon_entry(weapon_list, list, INVSLOT_MAINHAND)
		if list[#list] and not PitBull4_Aura:FilterEntry(filter, list[#list], frame) then
			list[#list] = nil
		end
		copy_weapon_entry(weapon_list, list, INVSLOT_OFFHAND)
		if list[#list] and not PitBull4_Aura:FilterEntry(filter, list[#list], frame) then
			list[#list] = nil
		end
	end

	if frame.force_show then
		-- config mode so treat sample frames as friendly
		if not unit or not UnitExists(unit) then
			is_friend = true
		end

		-- Fill extra auras if we're in config mode
		get_aura_list_sample(list, unit, max_auras, db, is_buff, is_player)

		local layout_db = is_buff and db.layout.buff or db.layout.debuff
		if layout_db.sort_rule ~= "Unsorted" then
			aura_sort__is_only = layout_db.sort_rule == "NameOnly" or layout_db.sort_rule == "ExpirationOnly"
			table.sort(list, aura_sort)
		end
	end

	-- Limit the number of displayed buffs here after we
	-- have filtered and sorted to allow the most important
	-- auras to be displayed rather than randomly tossing
	-- some away that may not be our prefered auras
	local buff_count = (#list > max_auras) and max_auras or #list

	for i = 1, buff_count do
		set_aura(frame, db, controls, list[i], i, is_friend)
	end

	-- Remove unnecessary aura frames
	for i = buff_count + 1, #controls do
		PitBull4_Aura:DisableCooldownText(controls[i])
		controls[i] = controls[i]:Delete()
	end
end

local function clear_auras(frame, is_buff)
	local controls
	if is_buff then
		controls = frame.aura_buffs
	else
		controls = frame.aura_debuffs
	end

	if not controls then
		return
	end

	for i = 1, #controls do
		controls[i].cooldown.noCooldownCount = nil
		PitBull4_Aura:DisableCooldownText(controls[i])
		controls[i] = controls[i]:Delete()
	end
end

function PitBull4_Aura:ClearAuras(frame)
	clear_auras(frame, true) -- Buffs
	clear_auras(frame, false) -- Debuffs
end

function PitBull4_Aura:UpdateAuras(frame)
	local db = self:GetLayoutDB(frame)
	local highlight = db.highlight

	-- Start the Highlight Filter System
	if highlight then
		self:ResetHighlightFilter()
	end

	-- Buffs
	if db.enabled_buffs then
		update_auras(frame, db, true)
	else
		clear_auras(frame, true)
	end
	if highlight then
		self:HighlightFilterIterator(frame, db, true)
	end

	-- Debuffs
	if db.enabled_debuffs then
		update_auras(frame, db, false)
	else
		clear_auras(frame, false)
	end
	if highlight then
		self:HighlightFilterIterator(frame, db, false)
	end

	-- Finish the Highlight Filter System
	if highlight then
		self:SetHighlight(frame, db)
	end
end

-- table of frames to be updated on next filter update
local timed_filter_update = {}

--- Request that a frame is updated on the next timed update
-- The frame will only be updated once.  This is useful for
-- filters to request they be rerun on a frame for data that
-- changes with time.
-- @param frame the frame to update
-- @usage PitBull4_aura:RequestTimeFilterUpdate(my_frame)
-- @return nil
function PitBull4_Aura:RequestTimedFilterUpdate(frame)
	timed_filter_update[frame] = true
end

function PitBull4_Aura:UpdateFilters()
	for frame in pairs(timed_filter_update) do
		timed_filter_update[frame] = nil
		self:UpdateAuras(frame)
		self:LayoutAuras(frame)
	end
end
