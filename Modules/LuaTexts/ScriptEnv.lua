-- ScriptEnv.lua: Utility functions for use in Lua scripts for LuaTexts.

local PitBull4 = _G.PitBull4
local L = PitBull4.L
local PitBull4_LuaTexts = PitBull4:GetModule("LuaTexts")

local ShouldUnitAuraIndexBeSecret = C_Secrets.ShouldUnitAuraIndexBeSecret
local FloorToNearestString = C_StringUtil.FloorToNearestString
local TruncateWhenZero = C_StringUtil.TruncateWhenZero
local WrapString = C_StringUtil.WrapString

-- The ScriptEnv table serves as the environment that the scripts run
-- under LuaTexts run under.  The functions included in it are accessible
-- to this scripts as though they were local functions to it.  Functions
-- that they call will not have access to these functions.
local ScriptEnv = setmetatable({}, {__index = _G})
PitBull4_LuaTexts.ScriptEnv = ScriptEnv

local mouseover_check_cache = PitBull4_LuaTexts.mouseover_check_cache
local spell_cast_cache = PitBull4_LuaTexts.spell_cast_cache
local power_cache = PitBull4_LuaTexts.power_cache
local hp_cache = PitBull4_LuaTexts.hp_cache
local unit_cast_ids = PitBull4_LuaTexts.unit_cast_ids
local cast_data = PitBull4_LuaTexts.cast_data
local to_update = PitBull4_LuaTexts.to_update
local afk_cache = PitBull4_LuaTexts.afk_cache
local dnd_cache = PitBull4_LuaTexts.dnd_cache
local offline_cache = PitBull4_LuaTexts.offline_cache
local dead_cache = PitBull4_LuaTexts.dead_cache
local offline_times = PitBull4_LuaTexts.offline_times
local afk_times = PitBull4_LuaTexts.afk_times
local dnd = PitBull4_LuaTexts.dnd
local dead_times = PitBull4_LuaTexts.dead_times
local group_members = PitBull4_LuaTexts.group_members

local IsSecretValue = PitBull4.Utils.IsSecretValue
local IsUnitIdentitySecret = PitBull4.Utils.IsUnitIdentitySecret
local GetSafeUnitClass = PitBull4.Utils.GetSafeUnitClass
local GetSafeUnitRace = PitBull4.Utils.GetSafeUnitRace

ScriptEnv.WrapString = WrapString
ScriptEnv.TruncateWhenZero = TruncateWhenZero
ScriptEnv.FloorToNearestString = FloorToNearestString

-- Midnight 12.1: identity-adjacent predicates can themselves return secret
-- booleans even while the unit token remains public. Never branch on such a
-- result; callers receive nil when Blizzard did not provide an inspectable
-- boolean.
local function SafeBooleanCall(func, ...)
	if type(func) ~= "function" then
		return nil
	end
	local ok, value = pcall(func, ...)
	if not ok or IsSecretValue(value) then
		return nil
	end
	return value and true or false
end

local function unit_guid(unit)
	if not IsUnitIdentitySecret(unit) then
		-- Update on wacky frames if we're not locked down
		return UnitGUID(unit)
	end
	return group_members[unit]
end

-- The following functions exist to provide a method to help people moving
-- from LibDogTag.  They implement the functionality that exists in some of
-- the tags in LibDogTag.  Tags that are identical to Blizzard API calls are
-- not included and you should use the API call.  Some of them do not implement
-- all of the features of the relevent tag in LibDogTag.  People interested in
-- contributing new functions should open a ticket on the PitBull4 project as
-- a patch to the LuaTexts module.  In general tags that are simplistic work
-- on other tags should be generalized (e.g. Percent instead of PercentHP and PercentMP)
-- or should simply not exist.  A major design goal is to avoid inefficient code.
-- Functions which encourage inefficient code design will not be accepted.

-- A number of these functions are borrowed or adapted from the code implmenting
-- similar tags in DogTag.  Permission to do so granted by ckknight.

local UnitToLocale = {player = L["Player"], target = L["Target"], pet = L["%s's pet"]:format(L["Player"]), focus = L["Focus"], mouseover = L["Mouse-over"]}
setmetatable(UnitToLocale, {__index=function(self, unit)
	if unit:find("pet$") then
		local nonPet = unit:sub(1, -4)
		self[unit] = L["%s's pet"]:format(self[nonPet])
		return self[unit]
	elseif not unit:find("target$") then
		if unit:find("^party%d$") then
			local num = unit:match("^party(%d)$")
			self[unit] = L["Party member #%d"]:format(num)
			return self[unit]
		elseif unit:find("^arena%d$") then
			local num = unit:match("^arena(%d)$")
			self[unit] = L["Arena enemy #%d"]:format(num)
			return self[unit]
		elseif unit:find("^boss%d$") then
			local num = unit:match("^boss(%d)$")
			self[unit] = L["Boss #%d"]:format(num)
			return self[unit]
		elseif unit:find("^raid%d%d?$") then
			local num = unit:match("^raid(%d%d?)$")
			self[unit] = L["Raid member #%d"]:format(num)
			return self[unit]
		elseif unit:find("^partypet%d$") then
			local num = unit:match("^partypet(%d)$")
			self[unit] = UnitToLocale["party" .. num .. "pet"]
			return self[unit]
		elseif unit:find("^arenapet%d$") then
			local num = unit:match("^arenapet(%d)$")
			self[unit] = UnitToLocale["arena" .. num .. "pet"]
			return self[unit]
		elseif unit:find("^raidpet%d%d?$") then
			local num = unit:match("^raidpet(%d%d?)$")
			self[unit] = UnitToLocale["raid" .. num .. "pet"]
			return self[unit]
		end
		self[unit] = unit
		return unit
	end
	local nonTarget = unit:sub(1, -7)
	self[unit] = L["%s's target"]:format(self[nonTarget])
	return self[unit]
end})

local function VehicleName(unit)
	local name = UnitName(unit:gsub("vehicle", "pet")) or UnitName(unit) or L["Vehicle"]
	local owner_unit = unit:gsub("vehicle", "")
	if owner_unit == "" then
		owner_unit = "player"
	end
	local owner = UnitName(owner_unit)
	if owner then
		return L["%s's %s"]:format(owner, name)
	end
	return name
end
ScriptEnv.VehicleName = VehicleName

local function Name(unit, show_server)
	if unit ~= "player" and not UnitExists(unit) and not ShowBossFrameWhenUninteractable(unit) then
		return UnitToLocale[unit]
	else
		if unit:match("%d*pet%d*$") then
			local vehicle = unit:gsub("pet", "vehicle")
			if UnitIsUnit(unit, vehicle) then
				return VehicleName(vehicle)
			end
		elseif unit:match("%d*vehicle%d*$") then
			return VehicleName(unit)
		end
	end

	local name, server = UnitName(unit)
	if UnitInPartyIsAI(unit) and (C_LFGInfo.IsInLFGFollowerDungeon() or C_PartyInfo.IsPartyWalkIn()) then
		name = LFG_FOLLOWER_NAME_PREFIX:format(name)
	elseif show_server and not issecretvalue(server) and server and server ~= "" then
		name = FULL_PLAYER_NAME:format(name, server)
	end
	return name
end
ScriptEnv.Name = Name

local L_DAY_ONELETTER_ABBR = DAY_ONELETTER_ABBR:gsub("%s*%%d%s*", "")
local function FormatDuration(number)
	local negative = ""
	if number < 0 then
		number = -number
		negative = "-"
	end

	if number == math.huge then
		return "**:**:**"
	elseif number >= 60*60*24 then
		return ("%s%.0f%s %d:%02d:%02d"):format(negative, math.floor(number/86400), L_DAY_ONELETTER_ABBR, number/3600 % 24, number/60 % 60, number % 60)
	elseif number >= 60*60 then
		return ("%s%d:%02d:%02d"):format(negative, number/3600, number/60 % 60, number % 60)
	end
	return ("%s%d:%02d"):format(negative, number/60 % 60, number % 60)
end
ScriptEnv.FormatDuration = FormatDuration

ScriptEnv.SeparateDigits = BreakUpLargeNumbers

local function Angle(value)
	if not value then
		return ""
	end
	-- Keep the compact AFK status readable in narrow unit-frame name fields.
	-- Existing saved Name presets call Angle(AFK(unit) or DND(unit)), so handle
	-- the AFK form here as well as in newly-created presets. DND keeps the
	-- traditional angle brackets.
	if type(value) == "string" and not IsSecretValue(value) and value:sub(1, 6) == "AFK - " then
		return value
	end
	return WrapString(value, "<", ">")
end
ScriptEnv.Angle = Angle

local function Paren(value)
	if not value then
		return ""
	end
	return WrapString(value, "(", ")")
end
ScriptEnv.Paren = Paren

local function Minus(value)
	return WrapString(TruncateWhenZero(value), "-")
end
ScriptEnv.Minus = Minus

local function UpdateIn(seconds)
	local font_string = ScriptEnv.font_string
	local current_timer = to_update[font_string]
	if not current_timer or current_timer > seconds then
		to_update[font_string] = seconds
	end
end
ScriptEnv.UpdateIn = UpdateIn

local function IsAFK(unit)
	afk_cache[ScriptEnv.font_string] = true
	return not not afk_times[unit_guid(unit)]
end
ScriptEnv.IsAFK = IsAFK

local function AFKDuration(unit)
	local afk = afk_times[unit_guid(unit)]
	afk_cache[ScriptEnv.font_string] = true
	if afk then
		UpdateIn(0.25)
		return GetTime() - afk
	end
end
ScriptEnv.AFKDuration = AFKDuration

local function AFK(unit)
	local afk = AFKDuration(unit)
	if afk then
		return ("AFK - %s"):format(FormatDuration(afk))
	end
end
ScriptEnv.AFK = AFK

local function IsDND(unit)
	dnd_cache[ScriptEnv.font_string] = true
	return not not dnd[unit_guid(unit)]
end
ScriptEnv.IsDND = IsDND

local function DND(unit)
	dnd_cache[ScriptEnv.font_string] = true
	if dnd[unit_guid(unit)] then
		return _G.DND
	end
end
ScriptEnv.DND = DND

local function IsPlayer(unit)
	-- Treat each predicate independently. A restricted identity does not imply
	-- every presentation-adjacent predicate is itself secret.
	local is_player = SafeBooleanCall(UnitIsPlayer, unit)
	if is_player == true then
		return true
	end
	local is_ai = SafeBooleanCall(UnitInPartyIsAI, unit)
	return is_ai == true
end
ScriptEnv.UnitIsPlayer = IsPlayer -- existing LuaText compat

local function WrapTextInColor(text, r, g, b)
	return WrapString(text, ("|cff%02x%02x%02x"):format(r, g, b), "|r")
end

local function WrapTextInColorCode(text, textColorCode)
	return WrapString(text, ("|cff%s"):format(textColorCode), "|r")
end

local HOSTILE_REACTION = 2
local NEUTRAL_REACTION = 4
local FRIENDLY_REACTION = 5

local function HostileColor(unit)
	local r, g, b
	if not unit or IsUnitIdentitySecret(unit) then
		r, g, b = unpack(PitBull4.ReactionColors.unknown)
	else
		if IsPlayer(unit) or UnitPlayerControlled(unit) then
			if UnitCanAttack(unit, "player") then
				-- they can attack me
				if UnitCanAttack("player", unit) then
					-- and I can attack them
					r, g, b = unpack(PitBull4.ReactionColors[HOSTILE_REACTION])
				else
					-- but I can't attack them
					r, g, b = unpack(PitBull4.ReactionColors.civilian)
				end
			elseif UnitCanAttack("player", unit) then
				-- they can't attack me, but I can attack them
				r, g, b = unpack(PitBull4.ReactionColors[NEUTRAL_REACTION])
			elseif UnitIsPVP(unit) then
				-- on my team
				r, g, b = unpack(PitBull4.ReactionColors[FRIENDLY_REACTION])
			else
				-- either enemy or friend, no violance
				r, g, b = unpack(PitBull4.ReactionColors.civilian)
			end
		elseif UnitIsTapDenied(unit) or UnitIsDead(unit) then
			r, g, b = unpack(PitBull4.ReactionColors.tapped)
		else
			local reaction = UnitReaction(unit, "player")
			if reaction then
				if reaction >= 5 then
					r, g, b = unpack(PitBull4.ReactionColors[FRIENDLY_REACTION])
				elseif reaction == 4 then
					r, g, b = unpack(PitBull4.ReactionColors[NEUTRAL_REACTION])
				else
					r, g, b = unpack(PitBull4.ReactionColors[HOSTILE_REACTION])
				end
			else
				r, g, b = unpack(PitBull4.ReactionColors.unknown)
			end
		end
	end
	return r * 255, g * 255, b * 255
end
ScriptEnv.HostileColor = HostileColor

local function ClassColor(unit)
	local _, class = GetSafeUnitClass(unit)
	local color = PitBull4.ClassColors[class] or PitBull4.ClassColors.UNKNOWN
	return color[1] * 255, color[2] * 255, color[3] * 255
end
ScriptEnv.ClassColor = ClassColor

local function Level(unit)
	if ClassicExpansionAtLeast(LE_EXPANSION_MISTS_OF_PANDARIA) then
		local wild_pet = SafeBooleanCall(UnitIsWildBattlePet, unit)
		local companion = SafeBooleanCall(UnitIsBattlePetCompanion, unit)
		if wild_pet == true or companion == true then
			local ok, pet_level = pcall(UnitBattlePetLevel, unit)
			if ok and not IsSecretValue(pet_level) then
				return pet_level
			end
			return "??"
		end
	end
	local ok, level = pcall(UnitLevel, unit)
	if not ok or IsSecretValue(level) or type(level) ~= "number" then
		return "??"
	end
	if level <= 0 then
		level = "??"
	end
	return level
end
ScriptEnv.Level = Level

local function DifficultyColor(unit)
	local level = Level(unit)
	if level == "??" then
		level = 99
	end
	local color = GetQuestDifficultyColor(level)
	return color.r * 255, color.g * 255, color.b * 255
end
ScriptEnv.DifficultyColor = DifficultyColor

local function AggroColor(unit)
	local r, g, b = UnitSelectionColor(unit)
	return r * 255, g * 255, b * 255
end
ScriptEnv.AggroColor = AggroColor

local classification_lookup = {
	rare = L["Rare"],
	rareelite = L["Rare-Elite"],
	elite = L["Elite"],
	worldboss = L["Boss"],
	minus = L["Minus"],
	trivial = L["Trivial"],
}

local function Classification(unit)
	if IsUnitIdentitySecret(unit) then
		local ok, classification = pcall(UnitClassification, unit)
		if not ok or IsSecretValue(classification) then
			return nil
		end
		return classification_lookup[classification]
	end
	return classification_lookup[PitBull4.Utils.BetterUnitClassification(unit)]
end
ScriptEnv.Classification = Classification

local ShortClassification_abbrev = {
	[L["Rare"]] = L["Rare_short"],
	[L["Rare-Elite"]] = L["Rare-Elite_short"],
	[L["Elite"]] = L["Elite_short"],
	[L["Boss"]] = L["Boss_short"],
	[L["Minus"]] = L["Minus_short"],
	[L["Trivial"]] = L["Trivial_short"],
}

local function ShortClassification(arg)
	local short = ShortClassification_abbrev[arg]
	if not short and PitBull4.Utils.GetBestUnitID(arg) then
		-- If it's empty then maybe arg is a unit
		short = ShortClassification_abbrev[Classification(arg)]
	end
	return short
end
ScriptEnv.ShortClassification = ShortClassification

local function Class(unit)
	local _, _, class_id = GetSafeUnitClass(unit)
	if class_id then
		local class_info = C_CreatureInfo.GetClassInfo(class_id)
		if class_info and class_info.className then
			return class_info.className
		end
	end
	return UNKNOWN
end
ScriptEnv.Class = Class

local ShortClass_abbrev = {
	DEATHKNIGHT = L["Death Knight_short"],
	DEMONHUNTER = L["Demon Hunter_short"],
	DRUID = L["Druid_short"],
	EVOKER = L["Evoker_short"],
	HUNTER = L["Hunter_short"],
	MAGE = L["Mage_short"],
	MONK = L["Monk_short"],
	PALADIN = L["Paladin_short"],
	PRIEST = L["Priest_short"],
	ROGUE = L["Rogue_short"],
	SHAMAN = L["Shaman_short"],
	WARLOCK = L["Warlock_short"],
	WARRIOR = L["Warrior_short"],
}

local function ShortClass(arg)
	local short = ShortClass_abbrev[arg]
	if not short and PitBull4.Utils.GetBestUnitID(arg) then
		-- If it's empty then maybe arg is a unit
		local _, class, class_id = GetSafeUnitClass(arg)
		if IsPlayer(arg) then
			short = ShortClass_abbrev[class]
		elseif class_id then
			local class_info = C_CreatureInfo.GetClassInfo(class_id)
			if class_info then
				short = ShortClass_abbrev[class_info.classFile]
			end
		end
	end
	return short
end
ScriptEnv.ShortClass = ShortClass

-- Midnight 12.1 exposes semantic unit tooltip lines (including UnitType).
-- Blizzard may still render the creature type in its own tooltip while the raw
-- UnitCreatureType() return is secret.  Use only the structured UnitType line
-- when the line object, line type and text are all public; never parse a shared
-- GameTooltip FontString or inspect a secret tooltip value.
local function StructuredTooltipUnitType(unit)
	if not C_TooltipInfo or type(C_TooltipInfo.GetUnit) ~= "function" then
		return nil
	end
	local line_types = Enum and Enum.TooltipDataLineType
	local unit_type_line = line_types and line_types.UnitType
	if unit_type_line == nil then
		return nil
	end

	local ok, info = pcall(C_TooltipInfo.GetUnit, unit)
	if not ok or IsSecretValue(info) or type(info) ~= "table" then
		return nil
	end
	local lines = info.lines
	if IsSecretValue(lines) or type(lines) ~= "table" then
		return nil
	end

	for i = 1, #lines do
		local line = lines[i]
		if not IsSecretValue(line) and type(line) == "table" then
			local line_type = line.type
			if not IsSecretValue(line_type) and line_type == unit_type_line then
				local text = line.leftText
				if not IsSecretValue(text) and type(text) == "string" and text ~= "" and text ~= UNKNOWN then
					return text
				end
			end
		end
	end
	return nil
end
ScriptEnv.StructuredTooltipUnitType = StructuredTooltipUnitType

local function Creature(unit)
	if ClassicExpansionAtLeast(LE_EXPANSION_MISTS_OF_PANDARIA) then
		local wild_pet = SafeBooleanCall(UnitIsWildBattlePet, unit)
		local companion = SafeBooleanCall(UnitIsBattlePetCompanion, unit)
		if wild_pet == true or companion == true then
			local ok, pet_type = pcall(UnitBattlePetType, unit)
			if ok and not IsSecretValue(pet_type) then
				local pet_name = _G["BATTLE_PET_NAME_"..pet_type]
				if pet_name then
					return pet_name.." "..TOOLTIP_BATTLE_PET
				end
			end
		end
	end

	local ok_family, family = pcall(UnitCreatureFamily, unit)
	if ok_family and not IsSecretValue(family) and family then
		return family
	end
	local ok_type, creature_type = pcall(UnitCreatureType, unit)
	if ok_type and not IsSecretValue(creature_type) and creature_type and creature_type ~= "" and creature_type ~= UNKNOWN then
		return creature_type
	end

	-- 12.1 fallback: the raw identity API may be restricted while Blizzard's
	-- semantic UnitType tooltip line remains public (the default tooltip can, for
	-- example, still show "Humanoid").
	local tooltip_type = StructuredTooltipUnitType(unit)
	if tooltip_type then
		return tooltip_type
	end
	return nil
end
ScriptEnv.Creature = Creature

local SmartRace
do
	local race_pattern = _G.UNIT_TYPE_LEVEL_TEMPLATE:gsub("%%s", "(%%w+)"):gsub("%%d", "%%d+")
	function SmartRace(unit)
		if IsPlayer(unit) then
			local race = GetSafeUnitRace(unit)
			return race or UNKNOWN
		elseif SafeBooleanCall(UnitInPartyIsAI, unit) == true then
			-- UnitRace doesn't work with AI units. UnitCreatureType does, but we prefer the actual race
			local info = C_TooltipInfo.GetUnit(unit)
			if info then
				for i = 1, #info.lines do -- should be 3, but just check every line
					local text = info.lines[i] and info.lines[i].leftText
					if text and not issecretvalue(text) then
						local race = text:match(race_pattern)
						if race then
							return race
						end
					end
				end
			end
		end
		return Creature(unit)
	end
	ScriptEnv.SmartRace = SmartRace
end

local ShortRace_abbrev = {
	BloodElf = L["Blood Elf_short"],
	Draenei = L["Draenei_short"],
	Dwarf = L["Dwarf_short"],
	Gnome = L["Gnome_short"],
	Goblin = L["Goblin_short"],
	Human = L["Human_short"],
	NightElf = L["Night Elf_short"],
	Orc = L["Orc_short"],
	Pandaren = L["Pandaren_short"],
	Tauren = L["Tauren_short"],
	Troll = L["Troll_short"],
	Undead = L["Undead_short"],
	Worgen = L["Worgen_short"],
	DarkIronDwarf = L["Dark Iron Dwarf_short"],
	HighmountainTauren = L["Highmountain Tauren_short"],
	KulTiranHuman = L["Kul Tiran Human_short"],
	LightforgedDraenei = L["Lightforged Draenei_short"],
	MagharOrc = L["Mag'har Orc_short"],
	Nightborne = L["Nightborne_short"],
	VoidElf = L["Void Elf_short"],
	ZandalariTroll = L["Zandalari Troll_short"],
	Vulpera = L["Vulpera_short"],
	Mechagnome = L["Mechagnome_short"],
	Dracthyr = L["Dracthyr_short"],
}

local function ShortRace(arg)
	local short = ShortRace_abbrev[arg]
	if not short and PitBull4.Utils.GetBestUnitID(arg) then
		-- If it's empty then maybe arg is a unit
		local _, race = GetSafeUnitRace(arg)
		short = ShortRace_abbrev[race]
	end
	return short
end
ScriptEnv.ShortRace = ShortRace

local function IsPet(unit)
	local is_player = SafeBooleanCall(UnitIsPlayer, unit)
	local controlled = SafeBooleanCall(UnitPlayerControlled, unit)
	local in_raid = SafeBooleanCall(UnitPlayerOrPetInRaid, unit)
	if is_player == nil or controlled == nil or in_raid == nil then
		return false
	end
	return not is_player and (controlled or in_raid)
end
ScriptEnv.IsPet = IsPet

local function OfflineDuration(unit)
	local offline = offline_times[unit_guid(unit)]
	offline_cache[ScriptEnv.font_string] = true
	if offline then
		UpdateIn(0.25)
		return GetTime() - offline
	end
end
ScriptEnv.OfflineDuration = OfflineDuration

local function Offline(unit)
	local offline = OfflineDuration(unit)
	if offline then
		return ("%s (%s)"):format(_G.PLAYER_OFFLINE, FormatDuration(offline))
	end
end
ScriptEnv.Offline = Offline

local function IsOffline(unit)
	offline_cache[ScriptEnv.font_string] = true
	return not not offline_times[unit_guid(unit)]
end
ScriptEnv.IsOffline = IsOffline

local function DeadDuration(unit)
	local dead_time = dead_times[unit_guid(unit)]
	dead_cache[ScriptEnv.font_string] = true
	if dead_time then
		UpdateIn(0.25)
		return GetTime() - dead_time
	end
end
ScriptEnv.DeadDuration = DeadDuration

local function Dead(unit)
	local dead_time = DeadDuration(unit)
	local dead_type = (UnitIsGhost(unit) and L["Ghost"]) or (UnitIsDead(unit) and L["Dead"])
	if dead_time and dead_type then
		return ("%s (%s)"):format(dead_type, FormatDuration(dead_time))
	elseif dead_type then
		return dead_type
	end
end
ScriptEnv.Dead = Dead

local MOONKIN_FORM = C_Spell.GetSpellName(24858)
local TRAVEL_FORM = C_Spell.GetSpellName(783)
local TREE_OF_LIFE = C_Spell.GetSpellName(33891)

local function get_non_secret_aura_data_by_index(unit, index, filter)
	-- Midnight 12.1 rejects GetAuraDataByIndex when the requested aura index is
	-- secret and the caller is tainted. The form suffix is optional, so stop the
	-- scan instead of probing a protected aura or surfacing a LuaText error.
	if ShouldUnitAuraIndexBeSecret then
		local predicate_ok, is_secret = pcall(ShouldUnitAuraIndexBeSecret, unit, index, filter)
		if not predicate_ok or is_secret then
			return nil
		end
	end

	local ok, aura_data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
	if not ok or (issecretvalue and issecretvalue(aura_data)) then
		return nil
	end
	return aura_data
end

local function DruidForm(unit)
	local _, class = GetSafeUnitClass(unit)
	if not class then
		return nil
	end
	if class == "DRUID" then
		local ok, power = pcall(UnitPowerType, unit)
		if not ok or IsSecretValue(power) then
			return nil
		elseif power == 1 then
			return L["Bear"]
		elseif power == 3 then
			return L["Cat"]
		else
			local i = 1
			repeat
				local auraData = get_non_secret_aura_data_by_index(unit, i, "HELPFUL")
				local name = auraData and auraData.name
				if name and not issecretvalue(name) then
					if name == MOONKIN_FORM then
						return L["Moonkin"]
					elseif name == TRAVEL_FORM then
						return L["Travel"]
					elseif name == TREE_OF_LIFE then
						return L["Tree"]
					end
				end
				i = i + 1
			until not auraData
		end
	end
end
ScriptEnv.DruidForm = DruidForm

-- Build the stock Class text entirely from values that have already crossed the
-- Midnight 12.1 identity boundary.  This preserves the classic PitBull output
-- (for example: "90 Paladin Human") whenever the unit identity is public, but
-- never concatenates, colors, compares, or table-indexes secret identity data.
-- Patch 049: restore the legacy Class/identity presentation while respecting
-- Midnight 12.1 secret-value rules.  The key difference from IdentitySummary
-- is that potentially secret identity strings are not concatenated, compared,
-- colored by lookup, or otherwise inspected by addon Lua.  Instead they are
-- returned as individual arguments for FontString:SetFormattedText(), which is
-- Blizzard's supported text sink for protected values.
local function StructuredTooltipUnitLevel(unit)
	if not C_TooltipInfo or type(C_TooltipInfo.GetUnit) ~= "function" then
		return nil
	end
	local line_types = Enum and Enum.TooltipDataLineType
	local unit_level_line = line_types and line_types.UnitLevel
	if unit_level_line == nil then
		return nil
	end

	local ok, info = pcall(C_TooltipInfo.GetUnit, unit)
	if not ok or IsSecretValue(info) or type(info) ~= "table" then
		return nil
	end
	local lines = info.lines
	if IsSecretValue(lines) or type(lines) ~= "table" then
		return nil
	end

	for i = 1, #lines do
		local line = lines[i]
		if not IsSecretValue(line) and type(line) == "table" then
			local line_type = line.type
			if not IsSecretValue(line_type) and line_type == unit_level_line then
				local text = line.leftText
				if not IsSecretValue(text) and type(text) == "string" and text ~= "" then
					-- The semantic UnitLevel line may contain more than just the raw number.
					-- Keep only a public numeric level so the stock Class line remains stable.
					local number = text:match("(%d+)")
					if number then
						return tonumber(number)
					end
				end
			end
		end
	end
	return nil
end
ScriptEnv.StructuredTooltipUnitLevel = StructuredTooltipUnitLevel

-- Patch 055: restricted identities still expose useful display values as secret
-- strings. Addon Lua must not inspect those values, but FontString:SetFormattedText
-- is an approved sink. Keep the ordinary public renderer for unrestricted units;
-- for restricted units, build only the *shape* of the format string in Lua and
-- forward class/race/creature strings untouched. type() is explicitly safe on
-- secret values and is used only to determine whether an API returned a value.
local function RestrictedIdentityDisplay(unit, player_classes_only)
	if player_classes_only then
		-- "Player classes only" is intentionally conservative for a restricted
		-- compound token: determining player-vs-NPC would itself require identity
		-- inspection. The normal Standard renderer below remains fully useful.
		return nil
	end

	local format_parts = {}
	local values = {}

	-- Classification is currently public in the relevant 12.1 restricted NPC
	-- cases. Keep it only when it can be inspected normally.
	local ok_classification, classification = pcall(Classification, unit)
	local has_public_classification = ok_classification and not IsSecretValue(classification)
		and type(classification) == "string" and classification ~= ""
	local is_boss_classification = has_public_classification and classification == L["Boss"]

	if is_boss_classification then
		-- Patch 065: a public Boss classification is enough to reproduce the
		-- Blizzard skull-level presentation without inspecting a protected level.
		format_parts[#format_parts + 1] = "??"
		format_parts[#format_parts + 1] = "%s"
		values[#values + 1] = classification
	else
		if has_public_classification then
			format_parts[#format_parts + 1] = "%s"
			values[#values + 1] = classification
		end

		-- UnitLevel may be public or secret depending on context. A number can be
		-- forwarded directly to the text sink without comparing or formatting it in Lua.
		local ok_level, level = pcall(UnitLevel, unit)
		if ok_level and type(level) == "number" then
			if not IsSecretValue(level) then
				if level > 0 then
					format_parts[#format_parts + 1] = "%d"
					values[#values + 1] = level
				end
			else
				format_parts[#format_parts + 1] = "%d"
				values[#values + 1] = level
			end
		else
			local tooltip_level = StructuredTooltipUnitLevel(unit)
			if type(tooltip_level) == "number" and tooltip_level > 0 then
				format_parts[#format_parts + 1] = "%d"
				values[#values + 1] = tooltip_level
			end
		end
	end

	-- Patch 057: determine the display *shape* before forwarding any restricted
	-- identity strings. Player-like units expose a race string, while hostile NPCs
	-- normally do not. This lets us keep the classic "90 Paladin Human" player
	-- text without comparing a protected class string against UnitName().
	--
	-- On restricted NPCs UnitClass() can yield a localized string that is simply
	-- the NPC's own name (for example "Shivan Punisher" or "Defiled Golem").
	-- Forwarding that produced redundant lines such as
	-- "Elite 91 Shivan Punisher Demon". For the NPC-shaped branch we therefore
	-- omit the localized UnitClass string entirely and keep classification + level
	-- + creature type/family information instead. No secret value is inspected.
	local ok_race, race_name = pcall(UnitRace, unit)
	local has_race_shape = ok_race and type(race_name) == "string"

	if has_race_shape then
		local ok_class, class_name = pcall(UnitClass, unit)
		if ok_class and type(class_name) == "string" then
			format_parts[#format_parts + 1] = "%s"
			values[#values + 1] = class_name
		end

		format_parts[#format_parts + 1] = "%s"
		values[#values + 1] = race_name
	else
		local ok_creature, creature_type = pcall(UnitCreatureType, unit)
		local identity_tail
		if ok_creature and type(creature_type) == "string" then
			identity_tail = creature_type
		else
			identity_tail = StructuredTooltipUnitType(unit)
		end
		if type(identity_tail) == "string" then
			format_parts[#format_parts + 1] = "%s"
			values[#values + 1] = identity_tail
		end
	end

	if #format_parts == 0 then
		return nil
	end

	local fmt = table.concat(format_parts, " ")
	return fmt, values[1], values[2], values[3], values[4]
end
ScriptEnv.RestrictedIdentityDisplay = RestrictedIdentityDisplay

local function IdentityDisplay(unit, player_classes_only)
	if IsUnitIdentitySecret(unit) then
		return RestrictedIdentityDisplay(unit, player_classes_only)
	end

	-- Patch 058: Unit-level secrecy can be narrower than the broad identity
	-- predicate for direct tokens such as target. If UnitLevel itself is secret,
	-- keep the stock Class line renderable by switching to the approved
	-- SetFormattedText sink path instead of discarding the level. This restores
	-- at least the level (and any renderable creature type) for restricted NPCs
	-- such as Felwyrms in M+/raid combat.
	local ok_probe_level, probe_level = pcall(UnitLevel, unit)
	if ok_probe_level and IsSecretValue(probe_level) then
		return RestrictedIdentityDisplay(unit, player_classes_only)
	end

	local parts = {}

	local classification = Classification(unit)
	local is_boss_classification = classification == L["Boss"]
	if classification and not is_boss_classification and not IsSecretValue(classification) and type(classification) == "string" and classification ~= "" then
		parts[#parts + 1] = classification
	end

	local ok_level, level = pcall(UnitLevel, unit)
	if not ok_level or IsSecretValue(level) or type(level) ~= "number" or level <= 0 then
		level = StructuredTooltipUnitLevel(unit)
	end
	if is_boss_classification then
		-- Patch 065: match Blizzard's skull/worldboss presentation. The exact
		-- numeric level is intentionally not meaningful for these units.
		parts[#parts + 1] = "??"
		parts[#parts + 1] = classification
	elseif type(level) == "number" and level > 0 then
		local color = GetQuestDifficultyColor(level)
		if color and not IsSecretValue(color.r) and not IsSecretValue(color.g) and not IsSecretValue(color.b) then
			parts[#parts + 1] = ("|cff%02x%02x%02x%d|r"):format(color.r * 255, color.g * 255, color.b * 255, level)
		else
			parts[#parts + 1] = tostring(level)
		end
	end

	local class_name, class_file = GetSafeUnitClass(unit)
	if player_classes_only and IsPlayer(unit) ~= true then
		class_name = nil
	end

	-- Patch 063: on public NPC identities UnitClass() can return the NPC's own
	-- localized name as its class label (for example "Row Rat").  That made the
	-- stock Class line duplicate the unit name: "90 Row Rat Humanoid".  In the
	-- public renderer both values may be compared safely, so suppress only this
	-- exact redundant case.  Real class labels such as Warrior remain intact.
	if class_name and not IsSecretValue(class_name) and type(class_name) == "string" then
		local ok_name, unit_name = pcall(UnitName, unit)
		if ok_name and not IsSecretValue(unit_name) and type(unit_name) == "string" and class_name == unit_name then
			class_name = nil
		end
	end

	if class_name and not IsSecretValue(class_name) and type(class_name) == "string" and class_name ~= "" and class_name ~= UNKNOWN then
		local class_color = class_file and PitBull4.ClassColors[class_file]
		if class_color then
			parts[#parts + 1] = ("|cff%02x%02x%02x%s|r"):format(class_color[1] * 255, class_color[2] * 255, class_color[3] * 255, class_name)
		else
			parts[#parts + 1] = class_name
		end
	end

	local form = DruidForm(unit)
	if form and not IsSecretValue(form) and type(form) == "string" and form ~= "" then
		parts[#parts + 1] = "(" .. form .. ")"
	end

	local race_or_type = GetSafeUnitRace(unit)
	if not race_or_type then
		race_or_type = Creature(unit)
	end
	if not race_or_type then
		race_or_type = StructuredTooltipUnitType(unit)
	end
	if race_or_type and not IsSecretValue(race_or_type) and type(race_or_type) == "string" and race_or_type ~= "" and race_or_type ~= UNKNOWN then
		parts[#parts + 1] = race_or_type
	end

	if #parts == 0 then
		return nil
	end
	return "%s", table.concat(parts, " ")
end
ScriptEnv.IdentityDisplay = IdentityDisplay

-- Keep IdentitySummary for compatibility with existing custom LuaTexts. Public
-- identities retain the traditional fully assembled string. Restricted values
-- are intentionally not reconstructed here; stock Class texts use IdentityDisplay.
local function IdentitySummary(unit, player_classes_only)
	if IsUnitIdentitySecret(unit) then
		return nil
	end
	local fmt, a,b,c,d,e,f,g,h,i,j,k,l,m,n,o = IdentityDisplay(unit, player_classes_only)
	-- Patch 056: IdentityDisplay may legitimately return nil when no safe/public
	-- components are available. Older saved Class LuaTexts can still call
	-- IdentitySummary directly, so never assume a format string exists.
	if type(fmt) ~= "string" then
		return nil
	end
	return fmt:format(a,b,c,d,e,f,g,h,i,j,k,l,m,n,o)
end
ScriptEnv.IdentitySummary = IdentitySummary

local function Status(unit)
	return Offline(unit) or (UnitIsFeignDeath(unit) and L["Feigned Death"]) or Dead(unit)
end
ScriptEnv.Status = Status

local function HP(unit, no_fast)
	local hp = UnitHealth(unit)
	if not no_fast then
		hp_cache[ScriptEnv.font_string] = true
	end
	-- if hp == 1 and UnitIsGhost(unit) then
	-- 	return 0
	-- end
	return hp
end
ScriptEnv.HP = HP

local MaxHP = UnitHealthMax
ScriptEnv.MaxHP = MaxHP

local MissingHP = UnitHealthMissing
ScriptEnv.MissingHP = MissingHP

local function PercentHP(unit)
	local hpp = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
	return FloorToNearestString(hpp)
end
ScriptEnv.PercentHP = PercentHP

local Power = UnitPower
ScriptEnv.Power = Power

local MaxPower = UnitPowerMax
ScriptEnv.MaxPower = MaxPower

local MissingPower = UnitPowerMissing
ScriptEnv.MissingPower = MissingPower

local function PercentPower(unit, powerType, unmodified)
	local pp = UnitPowerPercent(unit, powerType, unmodified, CurveConstants.ScaleTo100)
	return FloorToNearestString(pp)
end
ScriptEnv.PercentPower = PercentPower

local function Round(number, digits)
	if issecretvalue(number) then
		return "?"
	end

	local mantissa = 10^(digits or 0)
	local norm = number * mantissa + 0.5
	local norm_floor = math.floor(norm)
	if norm == norm_floor and (norm_floor % 2) == 1 then
		return (norm_floor - 1) / mantissa
	end
	return norm_floor / mantissa
end
ScriptEnv.Round = Round

local Short, Shorter, VeryShort
do
	local short_opts, shorter_opts, very_short_opts
	local locale = GetLocale()
	if locale == "zhCN" or locale == "zhTW" or locale == "koKR" then
		short_opts = {
			config = CreateAbbreviateConfig({
				{ breakpoint = 100000000000, abbreviation = "SECOND_NUMBER_CAP_NO_SPACE", significandDivisor = 100000000, fractionDivisor = 1   },
				{ breakpoint = 10000000000,  abbreviation = "SECOND_NUMBER_CAP_NO_SPACE", significandDivisor = 10000000,  fractionDivisor = 10  },
				{ breakpoint = 100000000,    abbreviation = "SECOND_NUMBER_CAP_NO_SPACE", significandDivisor = 1000000,   fractionDivisor = 100 },
				{ breakpoint = 10000000,     abbreviation = "FIRST_NUMBER_CAP_NO_SPACE",  significandDivisor = 10000,     fractionDivisor = 1   },
				{ breakpoint = 1000000,      abbreviation = "FIRST_NUMBER_CAP_NO_SPACE",  significandDivisor = 1000,      fractionDivisor = 10  },
				{ breakpoint = 10000,        abbreviation = "FIRST_NUMBER_CAP_NO_SPACE",  significandDivisor = 100,       fractionDivisor = 100 },
			})
		}

		shorter_opts = {
			config = CreateAbbreviateConfig({
				{ breakpoint = 100000000000, abbreviation = "SECOND_NUMBER_CAP_NO_SPACE", significandDivisor = 100000000, fractionDivisor = 1   },
				{ breakpoint = 10000000000,  abbreviation = "SECOND_NUMBER_CAP_NO_SPACE", significandDivisor = 10000000,  fractionDivisor = 10  },
				{ breakpoint = 100000000,    abbreviation = "SECOND_NUMBER_CAP_NO_SPACE", significandDivisor = 1000000,   fractionDivisor = 100 },
				{ breakpoint = 10000000,     abbreviation = "FIRST_NUMBER_CAP_NO_SPACE",  significandDivisor = 10000,     fractionDivisor = 1   },
				{ breakpoint = 1000000,      abbreviation = "FIRST_NUMBER_CAP_NO_SPACE",  significandDivisor = 1000,      fractionDivisor = 10  },
				{ breakpoint = 10000,        abbreviation = "FIRST_NUMBER_CAP_NO_SPACE",  significandDivisor = 100,       fractionDivisor = 100 },
				{ breakpoint = 1000,         abbreviation = "FIRST_NUMBER_CAP_NO_SPACE",  significandDivisor = 100,       fractionDivisor = 10  },
			})
		}

		very_short_opts = {
			config = CreateAbbreviateConfig({
				{ breakpoint = 100000000, abbreviation = "SECOND_NUMBER_CAP_NO_SPACE", significandDivisor = 100000000, fractionDivisor = 1 },
				{ breakpoint = 10000,     abbreviation = "FIRST_NUMBER_CAP_NO_SPACE",  significandDivisor = 10000,     fractionDivisor = 1 },
			})
		}
	else
		local BILLION_NUMBER = 10^9
		-- Use the correct symbol for long scale number locales
		if locale == "frFR" or locale == "esMX" or locale == "esES" then
			BILLION_NUMBER = 10^12
		end

		short_opts = {
			config = CreateAbbreviateConfig({
				{ breakpoint = BILLION_NUMBER, abbreviation = "b", significandDivisor = BILLION_NUMBER/10, fractionDivisor = 10,  abbreviationIsGlobal = false},
				{ breakpoint = 1000000000,     abbreviation = "m", significandDivisor = 10000000, fractionDivisor = 1,   abbreviationIsGlobal = false },
				{ breakpoint = 10000000,       abbreviation = "m", significandDivisor = 100000,   fractionDivisor = 10,  abbreviationIsGlobal = false },
				{ breakpoint = 1000000,        abbreviation = "m", significandDivisor = 10000,    fractionDivisor = 100, abbreviationIsGlobal = false },
				{ breakpoint = 100000,         abbreviation = "k", significandDivisor = 1000,     fractionDivisor = 1,   abbreviationIsGlobal = false },
				{ breakpoint = 10000,          abbreviation = "k", significandDivisor = 100,      fractionDivisor = 10,  abbreviationIsGlobal = false },
			})
		}

		shorter_opts = {
			config = CreateAbbreviateConfig({
				{ breakpoint = BILLION_NUMBER, abbreviation = "b", significandDivisor = BILLION_NUMBER/10, fractionDivisor = 10,  abbreviationIsGlobal = false},
				{ breakpoint = 1000000000,     abbreviation = "m", significandDivisor = 10000000, fractionDivisor = 1,   abbreviationIsGlobal = false },
				{ breakpoint = 10000000,       abbreviation = "m", significandDivisor = 100000,   fractionDivisor = 10,  abbreviationIsGlobal = false },
				{ breakpoint = 1000000,        abbreviation = "m", significandDivisor = 10000,    fractionDivisor = 100, abbreviationIsGlobal = false },
				{ breakpoint = 100000,         abbreviation = "k", significandDivisor = 1000,     fractionDivisor = 1,   abbreviationIsGlobal = false },
				{ breakpoint = 10000,          abbreviation = "k", significandDivisor = 100,      fractionDivisor = 10,  abbreviationIsGlobal = false },
				{ breakpoint = 1000,           abbreviation = "k", significandDivisor = 100,      fractionDivisor = 10,  abbreviationIsGlobal = false },
			})
		}

		very_short_opts = {
			config = CreateAbbreviateConfig({
				{ breakpoint = BILLION_NUMBER, abbreviation = "b", significandDivisor = BILLION_NUMBER, fractionDivisor = 1, abbreviationIsGlobal = false },
				{ breakpoint = 1000000,        abbreviation = "m", significandDivisor = 1000000,        fractionDivisor = 1, abbreviationIsGlobal = false },
				{ breakpoint = 1000,           abbreviation = "k", significandDivisor = 1000,           fractionDivisor = 1, abbreviationIsGlobal = false },
			})
		}
	end

	function Short(value)
		local success, result = pcall(AbbreviateNumbers, value, short_opts)
		if not success then
			result = ""
		end
		return result
	end
	ScriptEnv.Short = Short

	function Shorter(value)
		return AbbreviateNumbers(value, shorter_opts)
	end
	ScriptEnv.Shorter = Shorter

	function VeryShort(value)
		return AbbreviateNumbers(value, very_short_opts)
	end
	ScriptEnv.VeryShort = VeryShort
end

-- Midnight 12.1: raw UnitPower/UnitPowerMax/UnitPowerMissing values may be
-- secret on protected units. Formatting or comparing those values in addon Lua
-- is forbidden. These helpers only return public display strings; callers can
-- fall back to PercentPower(), which uses Blizzard's supported percentage API.
local function PowerText(unit, powerType, abbreviated)
	local current = UnitPower(unit, powerType)
	local maximum = UnitPowerMax(unit, powerType)
	if hasanysecretvalues(current, maximum) then
		return nil
	end
	if abbreviated then
		return ("%s/%s"):format(Short(current), Short(maximum))
	end
	return ("%s/%s"):format(current, maximum)
end
ScriptEnv.PowerText = PowerText

local function CurrentPowerText(unit, powerType, very_short)
	local current = UnitPower(unit, powerType)
	if issecretvalue(current) then
		return nil
	end
	return very_short and VeryShort(current) or Short(current)
end
ScriptEnv.CurrentPowerText = CurrentPowerText

local function PublicMissingPower(unit, powerType)
	local missing = UnitPowerMissing(unit, powerType)
	if issecretvalue(missing) then
		return nil
	end
	return missing
end
ScriptEnv.PublicMissingPower = PublicMissingPower

local function MissingPowerText(unit, powerType, color)
	local missing = PublicMissingPower(unit, powerType)
	if missing == nil then
		return nil
	end
	local text = Short(missing)
	if color then
		return WrapTextInColorCode(text, color)
	end
	return text
end
ScriptEnv.MissingPowerText = MissingPowerText

local function ShouldShowDruidMana(unit)
	local power_type = UnitPowerType(unit)
	if issecretvalue(power_type) then
		return nil
	end
	return power_type ~= 0
end
ScriptEnv.ShouldShowDruidMana = ShouldShowDruidMana

local function HasPublicPower(unit, powerType)
	local maximum = UnitPowerMax(unit, powerType)
	if issecretvalue(maximum) then
		return nil
	end
	return maximum > 0
end
ScriptEnv.HasPublicPower = HasPublicPower

local function IsMouseOver()
	local font_string = ScriptEnv.font_string
	local frame = font_string.frame
	mouseover_check_cache[font_string] = frame
	return PitBull4_LuaTexts.mouseover == frame
end
ScriptEnv.IsMouseOver = IsMouseOver

local function Combos()
	if UnitHasVehicleUI("player") then
		return GetComboPoints("vehicle")
	end
	return UnitPower("player", Enum.PowerType.ComboPoints)
end
ScriptEnv.Combos = Combos

local function ComboSymbols(symbol)
	return string.rep(symbol or "@", Combos())
end
ScriptEnv.ComboSymbols = ComboSymbols

local function Percent(x, y)
	if hasanysecretvalues(x, y) then
		error("Percent cannot be used with secret values.")
	end
	if x and y and y ~= 0 then
		return Round(x / y * 100, 1)
	end
	return 0
end
ScriptEnv.Percent = Percent

local function XP(unit)
	if unit == "player" then
		return UnitXP(unit)
	elseif unit == "pet" or unit == "playerpet" then
		return GetPetExperience()
	end
	return 0
end
ScriptEnv.XP = XP

local function MaxXP(unit)
	if unit == "player" then
		return UnitXPMax(unit)
	elseif unit == "pet" or unit == "playerpet" then
		local _, max = GetPetExperience()
		return max
	end
	return 0
end
ScriptEnv.MaxXP = MaxXP

local function RestXP(unit)
	if unit == "player" then
		return GetXPExhaustion() or 0
	end
	return 0
end
ScriptEnv.RestXP = RestXP

-- Pre-Dragonflight API wrapper for old texts
local function GetFriendshipReputation(id)
	if ClassicExpansionAtLeast(LE_EXPANSION_MISTS_OF_PANDARIA) then
		local info = C_GossipInfo.GetFriendshipReputation(id)
		if info.friendshipFactionID > 0 then
			return info.friendshipFactionID, info.standing, info.maxRep, info.name, info.text, info.texture, info.reaction, info.reactionThreshold, info.nextThreshold
		end
	end
end
ScriptEnv.GetFriendshipReputation = GetFriendshipReputation

local function WatchedFactionInfo()
	local name, reaction, min, max, value, faction_id
	if GetWatchedFactionInfo then
		name, reaction, min, max, value, faction_id = GetWatchedFactionInfo()
	else -- XXX wow_tww
		local watchedFactionData = C_Reputation.GetWatchedFactionData()
		if watchedFactionData then
			name = watchedFactionData.name
			reaction =  watchedFactionData.reaction
			min = watchedFactionData.currentReactionThreshold
			max = watchedFactionData.nextReactionThreshold
			value = watchedFactionData.currentStanding
			faction_id = watchedFactionData.factionID
		end
	end
	if not name then
		return nil
	end

	if ClassicExpansionAtLeast(LE_EXPANSION_LEGION) and C_Reputation.IsFactionParagon(faction_id) then
		local paragon_value, threshold, _, has_reward = C_Reputation.GetFactionParagonInfo(faction_id)
		min, max = 0, threshold
		value = paragon_value % threshold
		if has_reward then
			value = value + threshold
		end
	elseif ClassicExpansionAtLeast(LE_EXPANSION_DRAGONFLIGHT) and C_Reputation.IsMajorFaction(faction_id) then
		local faction_info = C_MajorFactions.GetMajorFactionData(faction_id)
		min, max = 0, faction_info.renownLevelThreshold
	elseif ClassicExpansionAtLeast(LE_EXPANSION_MISTS_OF_PANDARIA) then
		local rep_info = C_GossipInfo.GetFriendshipReputation(faction_id)
		local friendship_id = rep_info.friendshipFactionID
		if friendship_id > 0 then
			if rep_info.nextThreshold then
				min, max, value = rep_info.reactionThreshold, rep_info.nextThreshold, rep_info.standing
			else -- max, show full amount?
				min, max, value = 0, rep_info.standing, rep_info.standing
			end
		end
	end

	-- Normalize values
	max = max - min
	value = value - min
	min = 0
	return name, reaction, min, max, value, faction_id
end
ScriptEnv.WatchedFactionInfo = WatchedFactionInfo

local function ArtifactPower()
	local azeriteItemLocation = C_AzeriteItem.FindActiveAzeriteItem()
	if azeriteItemLocation then
		-- api can error if the active item is in your bank
		if azeriteItemLocation.bagID and (azeriteItemLocation.bagID < 0 or azeriteItemLocation.bagID > NUM_BAG_SLOTS) then
			return 0, 1, 0, -1
		end
		local artifactXP, totalLevelXP = C_AzeriteItem.GetAzeriteItemXPInfo(azeriteItemLocation)
		local numPoints = AzeriteUtil.GetEquippedItemsUnselectedPowersCount()
		local level = C_AzeriteItem.GetPowerLevel(azeriteItemLocation)
		return artifactXP, totalLevelXP, numPoints, level
	end
	return 0, 0, 0, 0
end
ScriptEnv.ArtifactPower = ArtifactPower

local function ThreatPair(unit)
	if UnitIsFriend("player", unit) then
		if UnitExists("target") then
			return unit, "target"
		end
		return nil
	end
	return "player", unit
end
ScriptEnv.ThreatPair = ThreatPair

ScriptEnv.ThreatSituation = UnitDetailedThreatSituation

local function ThreatStatusColor(status)
	local r, g, b = GetThreatStatusColor(status)
	return r * 255, g * 255, b * 255
end
ScriptEnv.ThreatStatusColor = ThreatStatusColor

local function CastData(unit)
	spell_cast_cache[ScriptEnv.font_string] = true
	return cast_data[unit_cast_ids[unit] or unit]
end
ScriptEnv.CastData = CastData

local function InterruptedBy(interrupted_by)
	if interrupted_by then
		local name = UnitNameFromGUID(interrupted_by)
		if name then
			local _, class = UnitClassFromGUID(interrupted_by)
			local classColor = C_ClassColor.GetClassColor(class)
			if classColor then
				name = C_ColorUtil.WrapTextInColor(name, classColor)
			end
			return _G.SPELL_INTERRUPTED_BY:format(name)
		end
	end
end
ScriptEnv.InterruptedBy = InterruptedBy

local function Alpha(number)
	PitBull4_LuaTexts.alpha = Saturate(number)
end
ScriptEnv.Alpha = Alpha

local function SecretAlpha(value, alphaIfTrue, alphaIfFalse)
	PitBull4_LuaTexts.secret_alpha = value
	PitBull4_LuaTexts.secret_alpha_if_true = alphaIfTrue
	PitBull4_LuaTexts.secret_alpha_if_false = alphaIfFalse
end
ScriptEnv.SecretAlpha = SecretAlpha

local function Outline()
	PitBull4_LuaTexts.outline = "OUTLINE"
end
ScriptEnv.Outline = Outline

local function ThickOutline()
	PitBull4_LuaTexts.outline = "OUTLINE, THICKOUTLINE"
end
ScriptEnv.ThickOutline = ThickOutline

local function WordWrap()
	PitBull4_LuaTexts.word_wrap = true
end
ScriptEnv.WordWrap = WordWrap

local function FontFlags(flags)
	PitBull4_LuaTexts.outline = flags -- MONOCHROME, OUTLINE, THICKOUTLINE, SLUG
end
ScriptEnv.FontFlags = FontFlags

local function abbreviate(text)
	local b = text:byte(1)
	if b <= 127 then
		return text:sub(1, 1)
	elseif b <= 223 then
		return text:sub(1, 2)
	elseif b <= 239 then
		return text:sub(1, 3)
	else
		return text:sub(1, 4)
	end
end
local function Abbreviate(value)
	if not issecretvalue(value) and value:find(" ") then
		return value:gsub(" *([^ ]+) *", abbreviate)
	end
	return value
end
ScriptEnv.Abbreviate = Abbreviate

local function PVPDuration(unit)
	if unit == "player" and IsPVPTimerRunning() then
		UpdateIn(0.25)
		return GetPVPTimer() / 1000
	end
end
ScriptEnv.PVPDuration = PVPDuration

local hp_color_curve = C_CurveUtil.CreateColorCurve()
hp_color_curve:AddPoint(0, CreateColor(1, 0, 0))
hp_color_curve:AddPoint(0.5, CreateColor(1, 1, 0))
hp_color_curve:AddPoint(1, CreateColor(0, 1, 0))
local function HPColor(value)
	local color = hp_color_curve:Evaluate(value)
	return color:GetRGBAsBytes()
end
ScriptEnv.HPColor = HPColor

local power_type_to_string = {
	[Enum.PowerType.Mana] = "MANA",
	[Enum.PowerType.Rage] = "RAGE",
	[Enum.PowerType.Focus] = "FOCUS",
	[Enum.PowerType.Energy] = "ENERGY",
	[Enum.PowerType.ComboPoints] = "COMBO_POINTS",
	[Enum.PowerType.Runes] = "RUNES",
	[Enum.PowerType.RunicPower] = "RUNIC_POWER",
	[Enum.PowerType.SoulShards] = "SOUL_SHARDS",
	[Enum.PowerType.LunarPower] = "LUNAR_POWER",
	[Enum.PowerType.HolyPower] = "HOLY_POWER",
	[Enum.PowerType.Maelstrom] = "MAELSTROM",
	[Enum.PowerType.Chi] = "CHI",
	[Enum.PowerType.Insanity] = "INSANITY",
	[Enum.PowerType.ArcaneCharges] = "ARCANE_CHARGES",
	[Enum.PowerType.Fury] = "FURY",
	[Enum.PowerType.Pain] = "PAIN",
}
local function PowerColor(power_type)
	if IsSecretValue(power_type) then
		return 178.5, 178.5, 178.5
	end
	if type(power_type) == "number" then
		power_type = power_type_to_string[power_type]
	end
	local color = PitBull4.PowerColors[power_type]
	if not color then
		return 178.5, 178.5, 178.5
	end
	return color[1] * 255, color[2] * 255, color[3] * 255
end
ScriptEnv.PowerColor = PowerColor

local function ReputationColor(reaction)
	if IsSecretValue(reaction) then
		return nil
	end
	local color = PitBull4.ReactionColors[reaction]
	if color then
		return color[1] * 255, color[2] * 255, color[3] * 255
	end
end
ScriptEnv.ReputationColor = ReputationColor

local function ConfigMode()
	local font_string = ScriptEnv.font_string
	local frame = font_string.frame
	if frame.force_show then
		return ("{%s}"):format(font_string.luatexts_name)
	end
end
ScriptEnv.ConfigMode = ConfigMode
