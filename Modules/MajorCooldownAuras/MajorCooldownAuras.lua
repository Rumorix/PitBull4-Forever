-- PitBull4 12.1 protected player major-cooldown aura display.
--
-- Blizzard's AuraContainer owns aura selection, assignment, visibility,
-- duration, tooltip data, and updates. PitBull only supplies public layout
-- settings and public aura spell-ID allowlists; it never reads an assigned
-- aura. Helpful player cooldowns stay on their unit frame. Deathmark and
-- Kingsbane use a separate HARMFUL|PLAYER container bound to target and shown
-- only beside the local player frame. Important encounter effects remain in
-- the separate ImportantDebuffs module.
--
-- Patch 028 treats every protected container/state-driver lifecycle change as
-- out-of-combat-only. Combat updates reuse an already prepared matching state
-- or defer reconciliation until PLAYER_REGEN_ENABLED.
-- Patch 034 expands the public cast-to-aura spell-ID audit across the built-in
-- Major Cooldown preset. Configuration stays keyed to the familiar spellbook
-- ability IDs while Blizzard's protected AuraContainer can match known active
-- aura IDs. Abilities that do not produce a suitable helpful player aura are
-- removed from this aura-only preset. Existing saved per-spell settings remain
-- keyed to the original configuration IDs and require no migration.
-- Patch 033 introduced this alias model for Fortifying Brew (115203 -> 120954).
-- Patch 030 supplies this complete AceLocale option surface in every bundled
-- WoW locale; diagnostic status strings deliberately remain stable English.

local _G = _G
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local MajorCooldownAuras = PitBull4:NewModule("MajorCooldownAuras")

local type = type
local tostring = tostring
local tonumber = tonumber
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local table_concat = table.concat
local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort
local math_floor = math.floor
local math_max = math.max
local string_format = string.format

local BORDER_TEXTURE = [[Interface\AddOns\PitBull4\Modules\Aura\border]]
local FALLBACK_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]
local OFFENSIVE_GROUP_KEY = "pitbull-major-offensive"
local DEFENSIVE_GROUP_KEY = "pitbull-major-defensive"
local OWN_TARGET_EFFECT_GROUP_KEY = "pitbull-own-offensive-target-effect"
local BLIZZARD_COOLDOWN_DATA_BUILD = 69299
-- Major active cooldown effects are short. This protected candidate filter is
-- defense in depth: even if Blizzard suppresses identity matching for a
-- non-assistable unit, long food/flask/weapon-style buffs cannot fill the strip.
local MAJOR_COOLDOWN_MAX_AURA_DURATION = 300

-- PitBull's shared text/highlight overlay is frame level +17. Keep active
-- major cooldowns well above that local overlay so their icons, borders,
-- protected spiral, and duration text remain fully visible at every anchor.
-- This stays in the unit frame's own strata, so normal GameTooltip strata can
-- still render above the cooldown buttons.
local MAJOR_COOLDOWN_FRAME_LEVEL_OFFSET = 30

-- These are active throughput cooldown auras, not cooldown-ready state. The
-- baseline follows Blizzard's 12.1 Cooldown Broadcaster spell set and only
-- includes spells expected to place a helpful aura on the player.
local CLASS_ORDER = {
	"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
	"SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

local CLASS_FALLBACK_NAMES = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter",
	ROGUE = "Rogue", PRIEST = "Priest", DEATHKNIGHT = "Death Knight",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", MONK = "Monk",
	DRUID = "Druid", DEMONHUNTER = "Demon Hunter", EVOKER = "Evoker",
}

local OFFENSIVE_SPELL_IDS_BY_CLASS = {
	DEATHKNIGHT = { [1249658] = true },
	DEMONHUNTER = { [191427] = true, [1217605] = true },
	DRUID = {
		[194223] = true, [102560] = true, [390414] = true, [391528] = true,
		[102543] = true, [50334] = true, [102558] = true, [33891] = true,
		[740] = true, [1261867] = true,
	},
	EVOKER = {
		[375087] = true, [363534] = true, [403631] = true, [442204] = true,
		[404977] = true, [412713] = true,
	},
	HUNTER = { [19574] = true, [288613] = true, [1250646] = true },
	MAGE = { [365350] = true, [190319] = true },
	MONK = { [132578] = true, [123904] = true, [322118] = true, [325197] = true },
	PALADIN = { [31884] = true, [216331] = true, [389539] = true },
	PRIEST = {
		[10060] = true, [200183] = true, [64843] = true, [421453] = true,
		[472433] = true, [228260] = true,
	},
	ROGUE = { [13750] = true, [51690] = true, [121471] = true, [185313] = true },
	SHAMAN = { [114050] = true, [114051] = true, [114052] = true, [191634] = true, [384352] = true },
	WARLOCK = {},
	WARRIOR = { [107574] = true, [227847] = true, [1719] = true },
}

-- These public spell IDs were audited against Blizzard's 12.1 Cooldown Viewer
-- data through build 69299. The list intentionally favors defensive effects
-- with an active helpful aura; instant heals, interrupts, passive cheat-death
-- talents, and enemy-only debuffs do not belong in an active-aura display.
--
-- Patch 026 uses this exact public spell-ID allowlist inside Blizzard's
-- protected AuraContainer. Blizzard permits identity candidate filters for
-- helpful auras on assistable units, so defensive effects do not need the
-- narrower BIG_DEFENSIVE classification. PitBull still never reads assigned
-- aura data or branches on a protected/secret aura value.
local DEFENSIVE_SPELL_IDS_BY_CLASS = {
	DEATHKNIGHT = {
		[49028] = true, [48792] = true, [48707] = true, [51052] = true,
		[49039] = true, -- Lichborne
		[55233] = true, -- Vampiric Blood
	},
	DEMONHUNTER = {
		[198589] = true, [196718] = true, [187827] = true, [204021] = true,
		[203720] = true, -- Demon Spikes
	},
	DRUID = {
		[22812] = true, [61336] = true, [102342] = true,
		[22842] = true, -- Frenzied Regeneration
	},
	EVOKER = { [363916] = true, [357170] = true, [374227] = true },
	HUNTER = {
		[186265] = true, [264735] = true,
		[53480] = true, -- Roar of Sacrifice
	},
	MAGE = {
		[45438] = true, [414658] = true, [342245] = true,
		[235450] = true, [235313] = true, [11426] = true,
		[55342] = true, -- Mirror Image
	},
	MONK = {
		[115203] = true, [116849] = true,
		[122470] = true, -- Touch of Karma
		[322507] = true, -- Celestial Brew
	},
	PALADIN = {
		[31821] = true, [642] = true, [6940] = true, [1022] = true, [86659] = true,
		[498] = true, -- Divine Protection (Holy)
		[31850] = true, -- Ardent Defender (Protection)
		[204018] = true, -- Blessing of Spellwarding
		[403876] = true, -- Divine Protection (Retribution)
	},
	PRIEST = { [62618] = true, [19236] = true, [33206] = true, [47788] = true, [47585] = true },
	ROGUE = {
		[31224] = true, [5277] = true, [1856] = true,
		[1966] = true, -- Feint
		[185311] = true, -- Crimson Vial
	},
	SHAMAN = {
		[98008] = true, [108271] = true,
	},
	WARLOCK = { [104773] = true, [108416] = true },
	WARRIOR = {
		[97462] = true, [118038] = true, [184364] = true, [871] = true,
		[23920] = true, -- Spell Reflection
	},
}

-- Some spellbook abilities apply a helpful aura with a different public
-- spell ID. Keep configuration keyed to the familiar cast/ability ID, but let
-- Blizzard's protected AuraContainer match every known public aura ID. These
-- tables contain public constants only; PitBull never reads an assigned aura
-- to perform the mapping. Including the cast ID as well is deliberate defense
-- in depth for spec/client variants that may expose that ID directly.
local OFFENSIVE_AURA_SPELL_IDS_BY_CONFIG_ID = {
	DEMONHUNTER = {
		[191427] = { [191427] = true, [162264] = true }, -- Metamorphosis
	},
	MAGE = {
		[365350] = { [365350] = true, [365362] = true }, -- Arcane Surge
	},
	PRIEST = {
		[228260] = { [228260] = true, [194249] = true }, -- Voidform
	},
	ROGUE = {
		[185313] = { [185313] = true, [185422] = true }, -- Shadow Dance
	},
}

local DEFENSIVE_AURA_SPELL_IDS_BY_CONFIG_ID = {
	DEATHKNIGHT = {
		[51052] = { [51052] = true, [145629] = true }, -- Anti-Magic Zone
	},
	DEMONHUNTER = {
		[196718] = { [196718] = true, [209426] = true }, -- Darkness
		[203720] = { [203720] = true, [203819] = true }, -- Demon Spikes
	},
	MAGE = {
		[342245] = { [342245] = true, [342246] = true }, -- Alter Time
	},
	MONK = {
		[115203] = { [115203] = true, [120954] = true }, -- Fortifying Brew
	},
	PRIEST = {
		[62618] = { [62618] = true, [81782] = true }, -- Power Word: Barrier
	},
	ROGUE = {
		[1856] = { [1856] = true, [11327] = true, [115193] = true }, -- Vanish
	},
	SHAMAN = {
		[98008] = { [98008] = true, [325174] = true }, -- Spirit Link Totem
	},
	WARRIOR = {
		[97462] = { [97462] = true, [97463] = true }, -- Rallying Cry
	},
}

local RACIAL_OFFENSIVE_SPELL_IDS = {
	[20572] = true, -- Blood Fury
	[26297] = true, -- Berserking
	[274738] = true, -- Ancestral Call
	[265221] = true, -- Fireblood
}

-- These two Rogue cooldowns express their active window as a harmful aura on
-- the current target rather than as a helpful aura on the Rogue. They are
-- intentionally local-player-only: HARMFUL|PLAYER lets Blizzard perform the
-- caster restriction inside the protected AuraContainer without PitBull
-- reading sourceUnit, spell identity, or any assigned aura data.
local OWN_TARGET_EFFECT_SPELL_IDS_BY_CLASS = {
	ROGUE = {
		[360194] = true, -- Deathmark
		[385627] = true, -- Kingsbane
	},
}

local TEST_SPELLS_BY_CLASS = {
	WARRIOR = { offensive = 107574, defensive = 871 },
	PALADIN = { offensive = 31884, defensive = 642 },
	HUNTER = { offensive = 19574, defensive = 186265 },
	ROGUE = { offensive = 13750, own_target = 360194, defensive = 31224 },
	PRIEST = { offensive = 10060, defensive = 33206 },
	DEATHKNIGHT = { offensive = 1249658, defensive = 48792 },
	SHAMAN = { offensive = 114050, defensive = 108271 },
	MAGE = { offensive = 190319, defensive = 45438 },
	WARLOCK = { defensive = 104773 },
	MONK = { offensive = 123904, defensive = 115203 },
	DRUID = { offensive = 194223, defensive = 22812 },
	DEMONHUNTER = { offensive = 191427, defensive = 198589 },
	EVOKER = { offensive = 375087, defensive = 363916 },
}

local BORDER_COLORS = {
	offensive = { 1.00, 0.70, 0.10, 1.00 },
	own_target = { 1.00, 0.45, 0.10, 1.00 },
	defensive = { 0.15, 0.72, 1.00, 1.00 },
}

local function spell_setting_key(category, class_token, spell_id)
	return "spell_" .. category .. "_" .. class_token .. "_" .. tostring(spell_id)
end

local LAYOUTS = {
	CENTER = {
		point = "CENTER", relativePoint = "CENTER",
		axis = "Horizontal", horizontal = "Right", vertical = "Down",
	},
	RIGHT = {
		point = "LEFT", relativePoint = "RIGHT",
		axis = "Horizontal", horizontal = "Right", vertical = "Down",
	},
	LEFT = {
		point = "RIGHT", relativePoint = "LEFT",
		axis = "Horizontal", horizontal = "Left", vertical = "Down",
	},
	TOP = {
		point = "BOTTOMLEFT", relativePoint = "TOPLEFT",
		axis = "Horizontal", horizontal = "Right", vertical = "Up",
	},
	BOTTOM = {
		point = "TOPLEFT", relativePoint = "BOTTOMLEFT",
		axis = "Horizontal", horizontal = "Right", vertical = "Down",
	},
	TOPLEFT = {
		point = "BOTTOMRIGHT", relativePoint = "TOPLEFT",
		axis = "Horizontal", horizontal = "Left", vertical = "Up",
	},
	TOPRIGHT = {
		point = "BOTTOMLEFT", relativePoint = "TOPRIGHT",
		axis = "Horizontal", horizontal = "Right", vertical = "Up",
	},
	BOTTOMLEFT = {
		point = "TOPRIGHT", relativePoint = "BOTTOMLEFT",
		axis = "Horizontal", horizontal = "Left", vertical = "Down",
	},
	BOTTOMRIGHT = {
		point = "TOPLEFT", relativePoint = "BOTTOMRIGHT",
		axis = "Horizontal", horizontal = "Right", vertical = "Down",
	},
}

local active_states = setmetatable({}, { __mode = "k" })
local retired_states = setmetatable({}, { __mode = "k" })
local failed_frames = setmetatable({}, { __mode = "k" })
local test_states = setmetatable({}, { __mode = "k" })
local pending_frames = setmetatable({}, { __mode = "k" })

MajorCooldownAuras:SetModuleType("custom")
MajorCooldownAuras:SetName(L["Major cooldown auras"])
MajorCooldownAuras:SetDescription(L["Show active offensive and defensive player cooldown auras, plus the local player's selected offensive effects on the current target, using Blizzard's protected 12.1 AuraContainer."])
local defaults = {
	show_offensive = true,
	show_defensive = true,
	show_own_target_effects = true,
	show_racials = true,
	test_mode = false,
	test_class = "PALADIN",
	icon_size = 26,
	spacing = 2,
	group_spacing = 5,
	max_offensive = 5,
	max_defensive = 5,
	max_own_target_effects = 2,
	position = "RIGHT",
	offset_x = 4,
	offset_y = 0,
	zoom = true,
	show_activation_border = true,
	show_spiral = true,
	show_duration = true,
	tooltips = true,
	cooldown_options_class = "PALADIN",
	extra_offensive_spell_ids = "",
}
for _, class_token in ipairs(CLASS_ORDER) do
	defaults["class_" .. class_token] = true
	for spell_id in pairs(OFFENSIVE_SPELL_IDS_BY_CLASS[class_token] or {}) do
		defaults[spell_setting_key("offensive", class_token, spell_id)] = true
	end
	for spell_id in pairs(DEFENSIVE_SPELL_IDS_BY_CLASS[class_token] or {}) do
		defaults[spell_setting_key("defensive", class_token, spell_id)] = true
	end
	for spell_id in pairs(OWN_TARGET_EFFECT_SPELL_IDS_BY_CLASS[class_token] or {}) do
		defaults[spell_setting_key("own_target", class_token, spell_id)] = true
	end
end
MajorCooldownAuras:SetDefaults(defaults)

local function enum_value(namespace, key, fallback)
	if type(namespace) == "table" and namespace[key] ~= nil then
		return namespace[key]
	end
	return fallback
end

local function mirror_horizontal(value)
	return value:gsub("LEFT", "temp"):gsub("RIGHT", "LEFT"):gsub("temp", "RIGHT")
end

local function mirror_vertical(value)
	return value:gsub("BOTTOM", "temp"):gsub("TOP", "BOTTOM"):gsub("temp", "TOP")
end

local function get_effective_layout(frame, db)
	local source = LAYOUTS[db.position] or LAYOUTS.RIGHT
	local layout = {
		point = source.point,
		relativePoint = source.relativePoint,
		axis = source.axis,
		horizontal = source.horizontal,
		vertical = source.vertical,
		offsetX = tonumber(db.offset_x) or 0,
		offsetY = tonumber(db.offset_y) or 0,
	}
	local classification_db = frame and frame.classification_db
	if classification_db and classification_db.horizontal_mirror then
		layout.point = mirror_horizontal(layout.point)
		layout.relativePoint = mirror_horizontal(layout.relativePoint)
		layout.horizontal = layout.horizontal == "Right" and "Left" or "Right"
		layout.offsetX = -layout.offsetX
	end
	if classification_db and classification_db.vertical_mirror then
		layout.point = mirror_vertical(layout.point)
		layout.relativePoint = mirror_vertical(layout.relativePoint)
		layout.vertical = layout.vertical == "Down" and "Up" or "Down"
		layout.offsetY = -layout.offsetY
	end
	return layout
end

local function get_unit_token(frame)
	if frame and type(frame.unit) == "string" and frame.unit ~= "" then
		return frame.unit
	end
	return "none"
end

local function get_help_visibility_driver(unit)
	-- RegisterStateDriver evaluates reaction/exists in Blizzard's secure macro
	-- environment. Never call UnitCanAssist from tainted addon execution: 12.1
	-- can make that result secret. Restrict interpolation to literal public unit
	-- tokens so no macro syntax can enter the condition string.
	if type(unit) ~= "string" or not unit:match("^[a-z][a-z0-9]*$") then
		return nil
	end
	return "[@" .. unit .. ",exists,help] show; hide"
end

local function is_player_frame(frame)
	-- frame.unit is PitBull's public configuration token. Do not call UnitIsUnit
	-- or inspect GUID/class data here: this feature deliberately belongs only to
	-- a literal player frame and never attempts to identify another caster.
	return frame and frame.unit == "player"
end

local function class_enabled(db, class_token)
	return db["class_" .. class_token] ~= false
end

local function spell_enabled(db, category, class_token, spell_id)
	return db[spell_setting_key(category, class_token, spell_id)] ~= false
end

local function get_class_name(class_token)
	local localized = _G.LOCALIZED_CLASS_NAMES_MALE
	if type(localized) == "table" and type(localized[class_token]) == "string" then
		return localized[class_token]
	end
	return CLASS_FALLBACK_NAMES[class_token] or class_token
end

local function get_signature(frame, db)
	local layout = get_effective_layout(frame, db)
	local parts = {
		tostring(db.show_offensive), tostring(db.show_defensive),
		tostring(db.show_own_target_effects), tostring(is_player_frame(frame)),
		tostring(db.show_racials),
		tostring(db.icon_size), tostring(db.spacing), tostring(db.group_spacing),
		tostring(db.max_offensive), tostring(db.max_defensive),
		tostring(db.max_own_target_effects),
		tostring(db.position), tostring(layout.point), tostring(layout.relativePoint),
		tostring(layout.horizontal), tostring(layout.vertical),
		tostring(layout.offsetX), tostring(layout.offsetY),
		tostring(db.zoom), tostring(db.show_activation_border),
		tostring(db.show_spiral), tostring(db.show_duration),
		tostring(db.tooltips), tostring(db.extra_offensive_spell_ids or ""),
	}
	for _, class_token in ipairs(CLASS_ORDER) do
		parts[#parts + 1] = tostring(class_enabled(db, class_token))
		for spell_id in pairs(OFFENSIVE_SPELL_IDS_BY_CLASS[class_token] or {}) do
			parts[#parts + 1] = tostring(spell_id)
			parts[#parts + 1] = tostring(spell_enabled(db, "offensive", class_token, spell_id))
		end
		for spell_id in pairs(DEFENSIVE_SPELL_IDS_BY_CLASS[class_token] or {}) do
			parts[#parts + 1] = tostring(spell_id)
			parts[#parts + 1] = tostring(spell_enabled(db, "defensive", class_token, spell_id))
		end
		for spell_id in pairs(OWN_TARGET_EFFECT_SPELL_IDS_BY_CLASS[class_token] or {}) do
			parts[#parts + 1] = tostring(spell_id)
			parts[#parts + 1] = tostring(spell_enabled(db, "own_target", class_token, spell_id))
		end
	end
	return table_concat(parts, ":")
end

local function merge_spell_ids(result, source)
	for spell_id in pairs(source or {}) do
		result[spell_id] = true
	end
end

local function build_class_spell_ids(source_by_class, db, category, aura_ids_by_config_id)
	local result = {}
	for _, class_token in ipairs(CLASS_ORDER) do
		if class_enabled(db, class_token) then
			local class_aliases = aura_ids_by_config_id and aura_ids_by_config_id[class_token]
			for spell_id in pairs(source_by_class[class_token] or {}) do
				if spell_enabled(db, category, class_token, spell_id) then
					local aura_spell_ids = class_aliases and class_aliases[spell_id]
					if type(aura_spell_ids) == "table" then
						merge_spell_ids(result, aura_spell_ids)
					else
						result[spell_id] = true
					end
				end
			end
		end
	end
	return result
end

local function build_offensive_spell_ids(extra_ids, db)
	local result = build_class_spell_ids(
		OFFENSIVE_SPELL_IDS_BY_CLASS,
		db,
		"offensive",
		OFFENSIVE_AURA_SPELL_IDS_BY_CONFIG_ID
	)
	if db.show_racials ~= false then
		merge_spell_ids(result, RACIAL_OFFENSIVE_SPELL_IDS)
	end
	if type(extra_ids) == "string" then
		for text in extra_ids:gmatch("%d+") do
			local spell_id = tonumber(text)
			if spell_id and spell_id > 0 then
				result[spell_id] = true
			end
		end
	end
	return result
end

local function build_defensive_spell_ids(db)
	return build_class_spell_ids(
		DEFENSIVE_SPELL_IDS_BY_CLASS,
		db,
		"defensive",
		DEFENSIVE_AURA_SPELL_IDS_BY_CONFIG_ID
	)
end

local function build_own_target_effect_spell_ids(db)
	return build_class_spell_ids(OWN_TARGET_EFFECT_SPELL_IDS_BY_CLASS, db, "own_target")
end

local function has_spell_ids(spell_ids)
	for _ in pairs(spell_ids or {}) do
		return true
	end
	return false
end

local function in_combat_lockdown()
	return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() or false
end

local function defer_frame_until_combat_ends(frame)
	if frame then
		pending_frames[frame] = true
	end
end

local function get_spell_texture(spell_id)
	local spell_api = _G.C_Spell
	if type(spell_api) == "table" and type(spell_api.GetSpellTexture) == "function" then
		local ok, texture = pcall(spell_api.GetSpellTexture, spell_id)
		if ok and texture then
			return texture
		end
	end
	if type(_G.GetSpellTexture) == "function" then
		local ok, texture = pcall(_G.GetSpellTexture, spell_id)
		if ok and texture then
			return texture
		end
	end
	return FALLBACK_ICON
end

local function get_spell_name(spell_id)
	local spell_api = _G.C_Spell
	if type(spell_api) == "table" and type(spell_api.GetSpellName) == "function" then
		local ok, name = pcall(spell_api.GetSpellName, spell_id)
		if ok and type(name) == "string" and name ~= "" then
			return name
		end
	end
	if type(spell_api) == "table" and type(spell_api.GetSpellInfo) == "function" then
		local ok, info = pcall(spell_api.GetSpellInfo, spell_id)
		if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
			return info.name
		end
	end
	return string_format(L["Spell %d"], spell_id)
end

local function get_test_duration_text(seconds)
	if type(_G.SecondsToTimeAbbrev) == "function" then
		local ok, text = pcall(_G.SecondsToTimeAbbrev, seconds)
		if ok and type(text) == "string" and text ~= "" then
			return text
		end
	end
	return string_format(L["%ds"], seconds)
end

local function get_spell_option_name(spell_id)
	return "|T" .. tostring(get_spell_texture(spell_id)) .. ":16:16:0:0|t "
		.. get_spell_name(spell_id) .. " (" .. tostring(spell_id) .. ")"
end

local function sorted_spell_ids(source)
	local result = {}
	for spell_id in pairs(source or {}) do
		result[#result + 1] = spell_id
	end
	table_sort(result)
	return result
end

local function get_test_spell(db, category, class_token, preferred_spell_id)
	local source_by_class
	if category == "offensive" then
		source_by_class = OFFENSIVE_SPELL_IDS_BY_CLASS
	elseif category == "own_target" then
		source_by_class = OWN_TARGET_EFFECT_SPELL_IDS_BY_CLASS
	else
		source_by_class = DEFENSIVE_SPELL_IDS_BY_CLASS
	end
	local source = source_by_class[class_token] or {}
	if preferred_spell_id and source[preferred_spell_id]
		and spell_enabled(db, category, class_token, preferred_spell_id) then
		return preferred_spell_id
	end
	for _, spell_id in ipairs(sorted_spell_ids(source)) do
		if spell_enabled(db, category, class_token, spell_id) then
			return spell_id
		end
	end
end

local function get_font_size(icon_size)
	return math_max(8, math_floor(icon_size * 0.38 + 0.5))
end

local function set_activation_border(button, enabled)
	local overlay = button.PitBull4MajorCooldownActivationOverlay
	local glow = button.PitBull4MajorCooldownActivationBorder
	local animation_group = button.PitBull4MajorCooldownActivationAnimation

	if not enabled then
		if animation_group and type(animation_group.Stop) == "function" then
			animation_group:Stop()
		end
		if overlay then
			overlay:Hide()
		end
		return
	end

	if not overlay then
		-- This decoration contains no aura data. It is an addon-owned child of
		-- Blizzard's protected AuraButton and simply inherits that button's
		-- visibility; no assigned aura, spell identity, or secret value is read.
		overlay = _G.CreateFrame("Frame", nil, button)
		overlay:SetAllPoints(button)
		overlay:EnableMouse(false)

		glow = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
		glow:SetPoint("TOPLEFT", overlay, "TOPLEFT", -2, 2)
		glow:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 2, -2)
		glow:SetTexture(BORDER_TEXTURE)
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(1.00, 0.82, 0.08, 1.00)
		glow:SetAlpha(1)

		-- AnimationGroup provides the pulse without an addon OnUpdate. If a
		-- future client omits this optional surface, the yellow border remains
		-- visible as a static fallback instead of disabling the protected icon.
		if type(glow.CreateAnimationGroup) == "function" then
			animation_group = glow:CreateAnimationGroup()
			if animation_group and type(animation_group.CreateAnimation) == "function" then
				local fade_out = animation_group:CreateAnimation("Alpha")
				fade_out:SetFromAlpha(1.00)
				fade_out:SetToAlpha(0.30)
				fade_out:SetDuration(0.55)
				fade_out:SetSmoothing("IN_OUT")
				fade_out:SetOrder(1)

				local fade_in = animation_group:CreateAnimation("Alpha")
				fade_in:SetFromAlpha(0.30)
				fade_in:SetToAlpha(1.00)
				fade_in:SetDuration(0.55)
				fade_in:SetSmoothing("IN_OUT")
				fade_in:SetOrder(2)
				animation_group:SetLooping("REPEAT")
			end
		end

		button.PitBull4MajorCooldownActivationOverlay = overlay
		button.PitBull4MajorCooldownActivationBorder = glow
		button.PitBull4MajorCooldownActivationAnimation = animation_group
	end

	-- The overlay frame sits above the protected cooldown swipe and duration
	-- text while remaining in the unit frame's normal strata.
	overlay:SetFrameLevel(button:GetFrameLevel() + 3)
	overlay:Show()
	if glow then
		glow:SetAlpha(1)
	end
	if animation_group and type(animation_group.Play) == "function" then
		animation_group:Play()
	end
end

local function initialize_button(button, visual, category)
	local icon_size = visual.iconSize
	button:SetSize(icon_size, icon_size)
	button:SetFrameLevel(visual.frameLevel)

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetAllPoints(button)
	if visual.zoom then
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	else
		icon:SetTexCoord(0, 1, 0, 1)
	end
	button:SetIcon(icon)

	local border = button:CreateTexture(nil, "BORDER")
	border:SetAllPoints(button)
	border:SetTexture(BORDER_TEXTURE)
	border:SetBlendMode("BLEND")
	local color = BORDER_COLORS[category]
	border:SetVertexColor(color[1], color[2], color[3], color[4])
	set_activation_border(button, visual.showActivationBorder)

	if visual.showSpiral then
		local cooldown = _G.CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		cooldown:SetAllPoints(button)
		cooldown:SetReverse(true)
		cooldown:SetDrawEdge(false)
		cooldown:SetHideCountdownNumbers(true)
		cooldown.noCooldownCount = true
		button:SetDurationCooldown(cooldown)
	end

	if visual.showDuration then
		local duration = button:CreateFontString(nil, "OVERLAY")
		duration:SetFont(_G.STANDARD_TEXT_FONT, get_font_size(icon_size), "OUTLINE")
		duration:SetTextColor(1, 1, 1, 1)
		duration:SetShadowColor(0, 0, 0, 1)
		duration:SetShadowOffset(1, -1)
		duration:SetPoint("CENTER", button, "CENTER", 0, 0)
		button:SetDurationText(duration, nil)
	end

	if visual.tooltips then
		button:EnableMouse(true)
		button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT", 0, 0)
		-- Hiding the protected tooltip in combat avoids propagating secret tooltip
		-- state through Blizzard_GameTooltip on restricted encounters.
		button:SetHideTooltipInCombat(true)
	else
		button:EnableMouse(false)
	end
	button:SetCancelAuraButtons(nil)
end

local function group_layout(db, layout_index)
	local icon_size = tonumber(db.icon_size) or 26
	return {
		elementSpacing = tonumber(db.spacing) or 2,
		lineSpacing = tonumber(db.spacing) or 2,
		groupSpacing = tonumber(db.group_spacing) or 5,
		groupLineSpacing = tonumber(db.group_spacing) or 5,
		forceNewLine = false,
		elementWidth = icon_size,
		elementHeight = icon_size,
		layoutIndex = layout_index,
	}
end

local function add_group(container, key, filter_string, max_count, candidate_filters, visual, category, db, layout_index)
	local options = {
		maxFrameCount = math_max(1, tonumber(max_count) or 1),
		initializeFrame = function(button)
			initialize_button(button, visual, category)
		end,
		sortMethod = enum_value(_G.AuraContainerSortMethod, "ExpirationOnly", 0),
		sortDirection = enum_value(_G.AuraContainerSortDirection, "Normal", 0),
		layout = group_layout(db, layout_index),
	}
	if candidate_filters then
		options.candidateFilters = candidate_filters
	end
	container:AddAuraGroup(key, filter_string, options)
	container:SetAuraGroupLayout(key, options.layout)
end

local function configure_container_layout(container, frame, db)
	local layout = get_effective_layout(frame, db)
	local flow_axis = _G.AnchorUtil and _G.AnchorUtil.FlowLayoutAxis
	local flow_direction = _G.AnchorUtil and _G.AnchorUtil.FlowDirection
	container:SetFlowLayoutAxis(enum_value(flow_axis, layout.axis, 0))
	container:SetFlowLayoutAnchorPoint(layout.point)
	container:SetFlowLayoutGrowthDirection(
		enum_value(flow_direction, layout.horizontal, 1),
		enum_value(flow_direction, layout.vertical, 3)
	)
	container:SetFlowLayoutPadding(0, 0, 0, 0)
	local icon_size = tonumber(db.icon_size) or 26
	local count = (db.show_offensive and (tonumber(db.max_offensive) or 5) or 0)
		+ (db.show_defensive and (tonumber(db.max_defensive) or 5) or 0)
	local maximum_line_size = math_max(icon_size, count * (icon_size + (tonumber(db.spacing) or 2)))
	container:SetFlowLayoutMaximumLineSize(maximum_line_size)
	return layout
end

local function configure_own_target_container_layout(container, primary_container, holder, frame, db)
	local layout = get_effective_layout(frame, db)
	local flow_axis = _G.AnchorUtil and _G.AnchorUtil.FlowLayoutAxis
	local flow_direction = _G.AnchorUtil and _G.AnchorUtil.FlowDirection
	local anchor_point = layout.point
	local protected_anchor
	container:ClearAllPoints()
	if primary_container then
		-- Blizzard's secure aura groups resize their container. A frame following
		-- that protected size must opt into the corresponding forbidden layout
		-- aspect at creation time; otherwise combat updates can be blocked.
		protected_anchor = _G.CreateFrame("Frame", nil, holder, "DisableUntrustedLayoutScriptsTemplate")
		protected_anchor:SetSize(1, 1)
		protected_anchor:SetFrameLevel(holder:GetFrameLevel())
		protected_anchor:EnableMouse(false)
		local gap = tonumber(db.group_spacing) or 5
		if layout.horizontal == "Left" then
			anchor_point = "RIGHT"
			protected_anchor:SetPoint("RIGHT", primary_container, "LEFT", -gap, 0)
		else
			anchor_point = "LEFT"
			protected_anchor:SetPoint("LEFT", primary_container, "RIGHT", gap, 0)
		end
		container:SetPoint(anchor_point, protected_anchor, anchor_point, 0, 0)
	else
		container:SetPoint(layout.point, holder, layout.point, 0, 0)
	end
	container:SetFlowLayoutAxis(enum_value(flow_axis, layout.axis, 0))
	container:SetFlowLayoutAnchorPoint(anchor_point)
	container:SetFlowLayoutGrowthDirection(
		enum_value(flow_direction, layout.horizontal, 1),
		enum_value(flow_direction, layout.vertical, 3)
	)
	container:SetFlowLayoutPadding(0, 0, 0, 0)
	local icon_size = tonumber(db.icon_size) or 26
	local count = tonumber(db.max_own_target_effects) or 2
	container:SetFlowLayoutMaximumLineSize(math_max(icon_size, count * (icon_size + (tonumber(db.spacing) or 2))))
	return protected_anchor
end

local function create_state(frame, db, signature)
	if type(_G.CreateFrame) ~= "function"
		or type(_G.AuraContainerSortMethod) ~= "table"
		or type(_G.AuraContainerSortDirection) ~= "table"
		or type(_G.AnchorUtil) ~= "table"
		or type(_G.AnchorUtil.FlowLayoutAxis) ~= "table"
		or type(_G.AnchorUtil.FlowDirection) ~= "table" then
		error("Blizzard 12.1 AuraContainer prerequisites are unavailable", 0)
	end

	local layout = get_effective_layout(frame, db)
	local unit = get_unit_token(frame)
	local visibility_driver = get_help_visibility_driver(unit)
	if not visibility_driver or type(_G.RegisterStateDriver) ~= "function" then
		error("secure helpful-unit visibility driver is unavailable", 0)
	end

	-- Blizzard ignores exact helpful spell-ID filters on non-assistable units by
	-- policy. A secure help/exists state driver therefore hides the entire live
	-- cooldown display when target/focus becomes hostile instead of exposing
	-- unrelated helpful auras. The addon never receives the reaction result.
	local visibility_gate = _G.CreateFrame("Frame", nil, frame, "SecureHandlerStateTemplate")
	visibility_gate:SetAllPoints(frame)
	visibility_gate:SetFrameLevel((frame:GetFrameLevel() or 1) + MAJOR_COOLDOWN_FRAME_LEVEL_OFFSET)
	visibility_gate:EnableMouse(false)
	_G.RegisterStateDriver(visibility_gate, "visibility", visibility_driver)

	local holder = _G.CreateFrame("Frame", nil, visibility_gate)
	holder:SetPoint(layout.point, frame, layout.relativePoint, layout.offsetX, layout.offsetY)
	holder:SetSize(1, 1)
	holder:SetFrameLevel((frame:GetFrameLevel() or 1) + MAJOR_COOLDOWN_FRAME_LEVEL_OFFSET)
	holder:Hide()

	local visual = {
		iconSize = tonumber(db.icon_size) or 26,
		frameLevel = holder:GetFrameLevel() + 1,
		zoom = db.zoom and true or false,
		showActivationBorder = db.show_activation_border and true or false,
		showSpiral = db.show_spiral and true or false,
		showDuration = db.show_duration and true or false,
		tooltips = db.tooltips and true or false,
	}
	local has_primary_groups = db.show_offensive or db.show_defensive
	local container
	if has_primary_groups then
		container = _G.CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
		container:SetPoint(layout.point, holder, layout.point, 0, 0)
		container:SetFrameLevel(holder:GetFrameLevel())
		container:Hide()
	end
	local layout_index = 1
	if db.show_offensive then
		add_group(
			container,
			OFFENSIVE_GROUP_KEY,
			"HELPFUL",
			db.max_offensive,
			{
				includeSpellIDs = build_offensive_spell_ids(db.extra_offensive_spell_ids, db),
				maxDuration = MAJOR_COOLDOWN_MAX_AURA_DURATION,
			},
			visual,
			"offensive",
			db,
			layout_index
		)
		layout_index = layout_index + 1
	end
	if db.show_defensive then
		-- HELPFUL supplies the permitted friendly-aura domain; includeSpellIDs is
		-- the exact defensive allowlist. Do not add BIG_DEFENSIVE here: Blizzard's
		-- classification omits valid active defensives such as Feint, Evasion and
		-- Crimson Vial on the 12.1 live client.
		add_group(
			container,
			DEFENSIVE_GROUP_KEY,
			"HELPFUL",
			db.max_defensive,
			{
				includeSpellIDs = build_defensive_spell_ids(db),
				maxDuration = MAJOR_COOLDOWN_MAX_AURA_DURATION,
			},
			visual,
			"defensive",
			db,
			layout_index
		)
	end

	if container then
		configure_container_layout(container, frame, db)
		container:SetUnit(unit)
		container:SetEnabled(true)
		container:Show()
	end

	local own_target_container
	local own_target_anchor
	local own_target_spell_ids = build_own_target_effect_spell_ids(db)
	local has_own_target_effects = is_player_frame(frame)
		and db.show_own_target_effects
		and has_spell_ids(own_target_spell_ids)
	if has_own_target_effects then
		own_target_container = _G.CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
		own_target_container:SetFrameLevel(holder:GetFrameLevel())
		own_target_container:Hide()
		add_group(
			own_target_container,
			OWN_TARGET_EFFECT_GROUP_KEY,
			"HARMFUL|PLAYER",
			db.max_own_target_effects,
			{ includeSpellIDs = own_target_spell_ids },
			visual,
			"own_target",
			db,
			1
		)
		own_target_anchor = configure_own_target_container_layout(own_target_container, container, holder, frame, db)
		own_target_container:SetUnit("target")
		own_target_container:SetEnabled(true)
		own_target_container:Show()
	end

	holder:Show()

	return {
		visibilityGate = visibility_gate,
		visibilityDriver = visibility_driver,
		holder = holder,
		container = container,
		ownTargetContainer = own_target_container,
		ownTargetAnchor = own_target_anchor,
		signature = signature,
		unit = unit,
		ownTargetUnit = own_target_container and "target" or "none",
	}
end

local function hide_state(state)
	if not state then
		return
	end
	if state.container then
		pcall(state.container.SetEnabled, state.container, false)
		pcall(state.container.SetUnit, state.container, "none")
		pcall(state.container.Hide, state.container)
	end
	if state.ownTargetContainer then
		pcall(state.ownTargetContainer.SetEnabled, state.ownTargetContainer, false)
		pcall(state.ownTargetContainer.SetUnit, state.ownTargetContainer, "none")
		pcall(state.ownTargetContainer.Hide, state.ownTargetContainer)
	end
	if state.holder then
		pcall(state.holder.Hide, state.holder)
	end
	state.unit = "none"
	state.ownTargetUnit = "none"
end

local function retire_state(frame, state)
	if not state then
		return
	end
	hide_state(state)
	local retired = retired_states[frame]
	if not retired then
		retired = {}
		retired_states[frame] = retired
	end
	table_insert(retired, state)
end

local function acquire_retired_state(frame, signature)
	local retired = retired_states[frame]
	if not retired then
		return nil
	end
	for index, state in ipairs(retired) do
		if state.signature == signature then
			table_remove(retired, index)
			return state
		end
	end
	return nil
end

local function show_state(state, frame)
	local unit = get_unit_token(frame)
	if state.container then
		state.container:SetUnit(unit)
		state.container:SetEnabled(true)
		state.container:Show()
	end
	if state.ownTargetContainer then
		state.ownTargetContainer:SetUnit("target")
		state.ownTargetContainer:SetEnabled(true)
		state.ownTargetContainer:Show()
	end
	state.holder:Show()
	state.unit = unit
	state.ownTargetUnit = state.ownTargetContainer and "target" or "none"
end

local function create_test_button(holder)
	local button = _G.CreateFrame("Frame", nil, holder)
	button:Hide()

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetAllPoints(button)
	button.testIcon = icon

	local border = button:CreateTexture(nil, "BORDER")
	border:SetAllPoints(button)
	border:SetTexture(BORDER_TEXTURE)
	border:SetBlendMode("BLEND")
	button.testBorder = border

	local cooldown = _G.CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints(button)
	cooldown:SetReverse(true)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(true)
	cooldown.noCooldownCount = true
	button.testCooldown = cooldown

	local duration = button:CreateFontString(nil, "OVERLAY")
	duration:SetTextColor(1, 1, 1, 1)
	duration:SetShadowColor(0, 0, 0, 1)
	duration:SetShadowOffset(1, -1)
	duration:SetPoint("CENTER", button, "CENTER", 0, 0)
	button.testDuration = duration

	return button
end

local function create_test_state(frame)
	local holder = _G.CreateFrame("Frame", nil, frame)
	holder:SetSize(1, 1)
	holder:Hide()
	local state = {
		holder = holder,
		buttons = {
			create_test_button(holder),
			create_test_button(holder),
			create_test_button(holder),
		},
		visibleCount = 0,
	}
	test_states[frame] = state
	return state
end

local function hide_test_state(state)
	if not state then
		return
	end
	for _, button in ipairs(state.buttons or {}) do
		set_activation_border(button, false)
		button:Hide()
	end
	state.visibleCount = 0
	state.holder:Hide()
end

local function configure_test_button(button, db, spell_id, category)
	local icon_size = tonumber(db.icon_size) or 26
	button:ClearAllPoints()
	button:SetSize(icon_size, icon_size)
	button:SetFrameLevel(button:GetParent():GetFrameLevel() + 1)
	button.testIcon:SetTexture(get_spell_texture(spell_id))
	if db.zoom then
		button.testIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	else
		button.testIcon:SetTexCoord(0, 1, 0, 1)
	end
	local color = BORDER_COLORS[category]
	button.testBorder:SetVertexColor(color[1], color[2], color[3], color[4])
	set_activation_border(button, db.show_activation_border)

	if db.show_spiral then
		if type(button.testCooldown.SetCooldown) == "function" then
			local now = type(_G.GetTime) == "function" and _G.GetTime() or 1800
			button.testCooldown:SetCooldown(now - 1800, 3600)
		end
		button.testCooldown:Show()
	else
		button.testCooldown:Hide()
	end

	if db.show_duration then
		button.testDuration:SetFont(_G.STANDARD_TEXT_FONT, get_font_size(icon_size), "OUTLINE")
		if category == "offensive" then
			button.testDuration:SetText(get_test_duration_text(15))
		elseif category == "own_target" then
			button.testDuration:SetText(get_test_duration_text(16))
		else
			button.testDuration:SetText(get_test_duration_text(8))
		end
		button.testDuration:Show()
	else
		button.testDuration:Hide()
	end
	button:Show()
end

local function update_test_state(frame, db)
	local state = test_states[frame] or create_test_state(frame)
	hide_test_state(state)
	local class_token = type(db.test_class) == "string" and db.test_class or "PALADIN"
	local samples = TEST_SPELLS_BY_CLASS[class_token]
	if not samples or not class_enabled(db, class_token) then
		return false
	end

	local layout = get_effective_layout(frame, db)
	state.holder:ClearAllPoints()
	state.holder:SetPoint(layout.point, frame, layout.relativePoint, layout.offsetX, layout.offsetY)
	state.holder:SetFrameLevel((frame:GetFrameLevel() or 1) + MAJOR_COOLDOWN_FRAME_LEVEL_OFFSET)

	local entries = {}
	local offensive_spell_id = get_test_spell(db, "offensive", class_token, samples.offensive)
	local own_target_spell_id = get_test_spell(db, "own_target", class_token, samples.own_target)
	local defensive_spell_id = get_test_spell(db, "defensive", class_token, samples.defensive)
	if db.show_offensive and offensive_spell_id then
		entries[#entries + 1] = { spellID = offensive_spell_id, category = "offensive" }
	end
	if db.show_defensive and defensive_spell_id then
		entries[#entries + 1] = { spellID = defensive_spell_id, category = "defensive" }
	end
	if is_player_frame(frame) and db.show_own_target_effects and own_target_spell_id then
		entries[#entries + 1] = { spellID = own_target_spell_id, category = "own_target" }
	end
	if #entries == 0 then
		return false
	end

	local previous
	local gap = tonumber(db.group_spacing) or 5
	for index, entry in ipairs(entries) do
		local button = state.buttons[index]
		configure_test_button(button, db, entry.spellID, entry.category)
		if not previous then
			if layout.point == "CENTER" and #entries > 1 then
				if layout.horizontal == "Left" then
					button:SetPoint("LEFT", state.holder, "CENTER", gap / 2, 0)
				else
					button:SetPoint("RIGHT", state.holder, "CENTER", -gap / 2, 0)
				end
			else
				button:SetPoint(layout.point, state.holder, layout.point, 0, 0)
			end
		elseif layout.horizontal == "Left" then
			button:SetPoint("RIGHT", previous, "LEFT", -gap, 0)
		else
			button:SetPoint("LEFT", previous, "RIGHT", gap, 0)
		end
		previous = button
	end
	state.visibleCount = #entries
	state.holder:Show()
	return false
end

function MajorCooldownAuras:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function MajorCooldownAuras:PLAYER_REGEN_DISABLED()
	-- Static previews are ordinary addon frames and may be hidden safely. Never
	-- run UpdateAll here: a frame discovered on combat entry would otherwise
	-- reach RegisterStateDriver after combat lockdown has already begun.
	for _, state in pairs(test_states) do
		hide_test_state(state)
	end
end

function MajorCooldownAuras:PLAYER_REGEN_ENABLED()
	-- Apply every deferred create, retire, unit, layout, and visibility change
	-- only after protected-frame mutations are legal again.
	self:UpdateAll()
end

function MajorCooldownAuras:PLAYER_TARGET_CHANGED()
	-- Blizzard explicitly exposes UpdateAllAuras for external target-change
	-- refreshes. The protected container performs the parse; PitBull neither
	-- reads nor branches on the selected target's aura data.
	for _, state in pairs(active_states) do
		local container = state.ownTargetContainer
		if container and type(container.UpdateAllAuras) == "function" then
			pcall(container.UpdateAllAuras, container)
		end
	end
end

function MajorCooldownAuras:OnDisable()
	for frame, state in pairs(active_states) do
		retire_state(frame, state)
	end
	for _, state in pairs(test_states) do
		hide_test_state(state)
	end
	active_states = setmetatable({}, { __mode = "k" })
	test_states = setmetatable({}, { __mode = "k" })
	pending_frames = setmetatable({}, { __mode = "k" })
end

function MajorCooldownAuras:PLAYER_ENTERING_WORLD()
	failed_frames = setmetatable({}, { __mode = "k" })
	self:UpdateAll()
end

function MajorCooldownAuras:ADDON_LOADED(_, addon_name)
	if addon_name == "Blizzard_AuraContainer" then
		failed_frames = setmetatable({}, { __mode = "k" })
		self:UpdateAll()
	end
end

function MajorCooldownAuras:UpdateFrame(frame)
	local db = self:GetLayoutDB(frame)
	local state = active_states[frame]
	local combat_locked = in_combat_lockdown()
	if db.test_mode then
		if combat_locked then
			-- Do not hide or detach an existing protected live state in combat.
			-- The preview itself is insecure and can still be hidden immediately.
			defer_frame_until_combat_ends(frame)
			hide_test_state(test_states[frame])
			return false
		end
		pending_frames[frame] = nil
		if state then
			hide_state(state)
		end
		return update_test_state(frame, db)
	end
	hide_test_state(test_states[frame])

	local has_primary = db.show_offensive or db.show_defensive
	local has_own_target_effects = is_player_frame(frame)
		and db.show_own_target_effects
		and class_enabled(db, "ROGUE")
		and (spell_enabled(db, "own_target", "ROGUE", 360194)
			or spell_enabled(db, "own_target", "ROGUE", 385627))
	if not has_primary and not has_own_target_effects then
		if combat_locked then
			defer_frame_until_combat_ends(frame)
			return false
		end
		pending_frames[frame] = nil
		return self:ClearFrame(frame)
	end

	local signature = get_signature(frame, db)
	if combat_locked then
		-- RegisterStateDriver creates attributes on Blizzard's protected state
		-- manager and is forbidden once combat lockdown starts. Existing matching
		-- states are already driven securely and need no insecure refresh here.
		-- Every missing, hidden, or changed state is rebuilt after regen instead.
		local desired_unit = get_unit_token(frame)
		if not state
			or state.signature ~= signature
			or state.unit ~= desired_unit
			or (state.ownTargetContainer and state.ownTargetUnit ~= "target") then
			defer_frame_until_combat_ends(frame)
		end
		return false
	end
	pending_frames[frame] = nil
	if state and state.signature ~= signature then
		retire_state(frame, state)
		active_states[frame] = nil
		state = nil
	end

	if not state then
		state = acquire_retired_state(frame, signature)
	end
	if not state then
		local failure = failed_frames[frame]
		if failure and failure.signature == signature then
			return false
		end
		local ok, result = pcall(create_state, frame, db, signature)
		if not ok then
			failed_frames[frame] = { signature = signature, error = tostring(result) }
			return false
		end
		state = result
		failed_frames[frame] = nil
	end

	active_states[frame] = state
	local ok, err = pcall(show_state, state, frame)
	if not ok then
		hide_state(state)
		failed_frames[frame] = { signature = signature, error = tostring(err) }
	end
	return false
end

function MajorCooldownAuras:ClearFrame(frame)
	if in_combat_lockdown() then
		defer_frame_until_combat_ends(frame)
		hide_test_state(test_states[frame])
		return false
	end
	pending_frames[frame] = nil
	local state = active_states[frame]
	if state then
		hide_state(state)
	end
	hide_test_state(test_states[frame])
	return false
end

function MajorCooldownAuras:OnHide(frame)
	if in_combat_lockdown() then
		-- The parent unit frame owns immediate combat visibility. Leave protected
		-- AuraContainer attributes untouched and reconcile after combat.
		defer_frame_until_combat_ends(frame)
		hide_test_state(test_states[frame])
		return
	end
	pending_frames[frame] = nil
	local state = active_states[frame]
	if state then
		hide_state(state)
	end
	hide_test_state(test_states[frame])
end

function MajorCooldownAuras:Lorenzo121StatusLine()
	local configured = 0
	local own_target_containers = 0
	local failures = 0
	local previews = 0
	local deferred = 0
	for _, state in pairs(active_states) do
		configured = configured + 1
		if state.ownTargetContainer then
			own_target_containers = own_target_containers + 1
		end
	end
	for _ in pairs(failed_frames) do
		failures = failures + 1
	end
	for _, state in pairs(test_states) do
		if state.visibleCount and state.visibleCount > 0 then
			previews = previews + 1
		end
	end
	for _ in pairs(pending_frames) do
		deferred = deferred + 1
	end
	return "12.1 majorCooldownAuras protected=yes configured=" .. configured .. " ownTargetContainers=" .. own_target_containers .. " previews=" .. previews .. " failures=" .. failures .. " deferred=" .. deferred .. " stateDriverInit=ooc-only combatRebuild=deferred-until-regen-enabled helpfulGroups=yes assistGate=secure-help-only longBuffGuard=maxDuration" .. MAJOR_COOLDOWN_MAX_AURA_DURATION .. " ownTargetEffects=HARMFUL|PLAYER:Deathmark+Kingsbane playerFrameOnly=yes currentTargetOnly=yes encounterDebuffLeak=no targetRefresh=UpdateAllAuras importantDebuffs=separate-module normalBuffs=independent classFilters=per-spell classOptions=flat anchors=9 center=yes topLayer=yes levelOffset=" .. MAJOR_COOLDOWN_FRAME_LEVEL_OFFSET .. " activationBorder=optional-yellow-pulse testMode=static-ooc offensivePreset=blizzard-12.1 defensivePreset=blizzard-cdm-" .. BLIZZARD_COOLDOWN_DATA_BUILD .. " spellIdAudit=P034 castAuraAliases=13 removedNoAura=4 defensives=HELPFUL+exactSpellIDs bigDefensiveGate=no"
end

MajorCooldownAuras:SetLayoutOptionsFunction(function(self)
	local function get(info)
		return PitBull4.Options.GetLayoutDB(self)[info[#info]]
	end
	local function set(info, value)
		PitBull4.Options.GetLayoutDB(self)[info[#info]] = value
		PitBull4.Options.UpdateFrames()
	end
	local function disabled()
		return not PitBull4.Options.GetLayoutDB(self).enabled
	end
	local function test_class_disabled()
		local db = PitBull4.Options.GetLayoutDB(self)
		return not db.enabled or not db.test_mode
	end
	local class_values = {}
	local class_filter_options = {}
	local function add_class_filter_option(key, option)
		class_filter_options[#class_filter_options + 1] = key
		class_filter_options[#class_filter_options + 1] = option
	end
	for _, class_token in ipairs(CLASS_ORDER) do
		local class_key = "class_" .. class_token
		local class_name = get_class_name(class_token)
		class_values[class_token] = class_name
		local function class_hidden()
			local db = PitBull4.Options.GetLayoutDB(self)
			return db.cooldown_options_class ~= class_token
		end
		local function class_spell_disabled()
			local db = PitBull4.Options.GetLayoutDB(self)
			return not db.enabled or db[class_key] == false
		end

		add_class_filter_option(class_key, {
			type = 'toggle',
			name = string_format(L["Enable all %s cooldowns"], class_name),
			desc = L["Master switch for this class. Individual offensive, defensive, and supported own-target effect choices below are retained when it is disabled."],
			get = get, set = set, disabled = disabled, hidden = class_hidden,
			width = 'full', order = 32,
		})

		local offensive_ids = sorted_spell_ids(OFFENSIVE_SPELL_IDS_BY_CLASS[class_token])
		add_class_filter_option("offensive_header_" .. class_token, {
			type = 'description',
			name = #offensive_ids > 0 and "|cffffb319" .. L["Offensive / throughput"] .. "|r" or "|cff888888" .. L["No offensive preset for this class."] .. "|r",
			hidden = class_hidden, width = 'full', order = 33,
		})
		for index, spell_id in ipairs(offensive_ids) do
			local key = spell_setting_key("offensive", class_token, spell_id)
			add_class_filter_option(key, {
				type = 'toggle',
				name = get_spell_option_name(spell_id),
				desc = string_format(L["Allow this offensive or throughput aura for %s."], class_name),
				get = get, set = set, disabled = class_spell_disabled, hidden = class_hidden,
				width = 'full', order = 33 + index,
			})
		end

		local own_target_ids = sorted_spell_ids(OWN_TARGET_EFFECT_SPELL_IDS_BY_CLASS[class_token])
		if #own_target_ids > 0 then
			add_class_filter_option("own_target_header_" .. class_token, {
				type = 'description',
				name = "|cffff731a" .. L["Own offensive effects on current target"] .. "|r",
				desc = L["Shown only beside the local player's PitBull frame and only while the local player has the selected effect active on the current target."],
				hidden = class_hidden, width = 'full', order = 50,
			})
		end
		for index, spell_id in ipairs(own_target_ids) do
			local key = spell_setting_key("own_target", class_token, spell_id)
			add_class_filter_option(key, {
				type = 'toggle',
				name = get_spell_option_name(spell_id),
				desc = string_format(L["Allow this %s effect when you applied it to your current target. This does not infer effects cast by another player."], class_name),
				get = get, set = set, disabled = class_spell_disabled, hidden = class_hidden,
				width = 'full', order = 50 + index,
			})
		end

		local defensive_ids = sorted_spell_ids(DEFENSIVE_SPELL_IDS_BY_CLASS[class_token])
		add_class_filter_option("defensive_header_" .. class_token, {
			type = 'description',
			name = #defensive_ids > 0 and "|cff269fff" .. L["Defensive"] .. "|r" or "|cff888888" .. L["No defensive preset for this class."] .. "|r",
			hidden = class_hidden, width = 'full', order = 60,
		})
		for index, spell_id in ipairs(defensive_ids) do
			local key = spell_setting_key("defensive", class_token, spell_id)
			add_class_filter_option(key, {
				type = 'toggle',
				name = get_spell_option_name(spell_id),
				desc = string_format(L["Allow this defensive aura for %s."], class_name),
				get = get, set = set, disabled = class_spell_disabled, hidden = class_hidden,
				width = 'full', order = 60 + index,
			})
		end
	end

	local options = {
	'test_mode', {
		type = 'toggle',
		name = L["Static test mode (out of combat)"],
		desc = L["Replace live cooldown auras with safe static preview icons. The preview reads no unit or aura data and is always hidden in combat."],
		get = get, set = set, disabled = disabled, order = 1,
	},
	'test_class', {
		type = 'select',
		name = L["Test class"],
		desc = L["Choose the class used for static sample icons. Rogue also previews one own-target effect on a player frame. A disabled class intentionally shows no preview."],
		values = class_values,
		get = get, set = set, disabled = test_class_disabled, order = 2,
	},
	'show_offensive', {
		type = 'toggle',
		name = L["Offensive and throughput cooldowns"],
		desc = L["Show active major offensive and healing cooldown auras, including Avenging Wrath."],
		get = get, set = set, disabled = disabled, order = 3,
	},
	'show_own_target_effects', {
		type = 'toggle',
		name = L["Own offensive effects on current target"],
		desc = L["On the local player frame, append selected effects that you applied to your current target. Patch 025 includes Deathmark and Kingsbane and uses Blizzard's protected HARMFUL|PLAYER path."],
		get = get, set = set, disabled = disabled, width = 'full', order = 4,
	},
	'show_defensive', {
		type = 'toggle',
		name = L["Defensive cooldowns"],
		desc = L["Show the selected helpful defensive cooldown auras through Blizzard's protected container and exact spell-ID filter."],
		get = get, set = set, disabled = disabled, order = 5,
	},
	'show_racials', {
		type = 'toggle',
		name = L["Offensive racial auras"],
		desc = L["Allow the public offensive racial aura preset independently of class filters."],
		get = get, set = set, disabled = disabled, order = 6,
	},
	'cooldown_options_source', {
		type = 'description',
		name = "|cffffd200" .. L["Classes and cooldowns"] .. "|r\n" .. string_format(L["The built-in preset is a curated active-aura subset audited against Blizzard's 12.1 Cooldown Viewer data through build %d. It is not a list of every action cooldown. Deathmark and Kingsbane are exact local-player effects on the current target; other players are not inferred. Live display remains Blizzard-gated through the protected AuraContainer; custom spell IDs are user additions."], BLIZZARD_COOLDOWN_DATA_BUILD),
		width = 'full',
		order = 30,
	},
	'cooldown_options_class', {
		type = 'select',
		name = L["Class cooldown options"],
		desc = L["Choose a class, then enable or disable its known major cooldown auras directly below."],
		values = class_values,
		get = get, set = set, disabled = disabled, width = 'full', order = 31,
	},
	'position', {
		type = 'select',
		name = L["Position"],
		desc = L["Attach the cooldown strip to the center, a side, or an outside corner. Mirrored layouts are mirrored automatically."],
		values = {
			CENTER = L["Center"],
			RIGHT = L["Right"], LEFT = L["Left"], TOP = L["Top"], BOTTOM = L["Bottom"],
			TOPLEFT = L["Top-left corner"], TOPRIGHT = L["Top-right corner"],
			BOTTOMLEFT = L["Bottom-left corner"], BOTTOMRIGHT = L["Bottom-right corner"],
		},
		get = get, set = set, disabled = disabled, order = 10,
	},
	'offset_x', {
		type = 'range', name = L["Horizontal offset"], min = -100, max = 100, step = 1,
		get = get, set = set, disabled = disabled, order = 11,
	},
	'offset_y', {
		type = 'range', name = L["Vertical offset"], min = -100, max = 100, step = 1,
		get = get, set = set, disabled = disabled, order = 12,
	},
	'icon_size', {
		type = 'range', name = L["Icon size"], min = 8, max = 64, step = 1,
		get = get, set = set, disabled = disabled, order = 13,
	},
	'spacing', {
		type = 'range', name = L["Icon spacing"], min = 0, max = 20, step = 1,
		get = get, set = set, disabled = disabled, order = 14,
	},
	'group_spacing', {
		type = 'range', name = L["Category spacing"], min = 0, max = 30, step = 1,
		get = get, set = set, disabled = disabled, order = 15,
	},
	'max_offensive', {
		type = 'range', name = L["Maximum offensive icons"], min = 1, max = 20, step = 1,
		get = get, set = set, disabled = disabled, order = 16,
	},
	'max_own_target_effects', {
		type = 'range', name = L["Maximum own target-effect icons"], min = 1, max = 5, step = 1,
		get = get, set = set, disabled = disabled, order = 17,
	},
	'max_defensive', {
		type = 'range', name = L["Maximum defensive icons"], min = 1, max = 20, step = 1,
		get = get, set = set, disabled = disabled, order = 18,
	},
	'zoom', {
		type = 'toggle', name = L["Zoom icons"], get = get, set = set, disabled = disabled, order = 19,
	},
	'show_activation_border', {
		type = 'toggle',
		name = L["Animated yellow activation border"],
		desc = L["Pulse a gold-yellow border around every active Major Cooldown icon. The class and per-spell switches define which cooldowns are important."],
		get = get, set = set, disabled = disabled, width = 'full', order = 20,
	},
	'show_spiral', {
		type = 'toggle', name = L["Cooldown spiral"], get = get, set = set, disabled = disabled, order = 21,
	},
	'show_duration', {
		type = 'toggle', name = L["Remaining duration text"], get = get, set = set, disabled = disabled, order = 22,
	},
	'tooltips', {
		type = 'toggle',
		name = L["Tooltips out of combat"],
		desc = L["Protected aura tooltips are disabled during combat to avoid secret tooltip taint."],
		get = get, set = set, disabled = disabled, order = 23,
	},
	'extra_offensive_spell_ids', {
		type = 'input',
		name = L["Additional offensive aura spell IDs"],
		desc = L["Optional spell IDs separated by spaces or commas. These must be aura spell IDs, not merely cast spell IDs. Custom IDs are not class-assigned and remain allowed independently of the class switches."],
		multiline = true,
		width = 'full',
		get = get, set = set, disabled = disabled, order = 90,
	}
}
	for index = 1, #class_filter_options do
		options[#options + 1] = class_filter_options[index]
	end
	return unpack(options)
end)
