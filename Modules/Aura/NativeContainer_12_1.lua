-- PitBull4 12.1 native AuraContainer renderer.
--
-- Patch 008 keeps normal runtime unit-frame auras on Blizzard's protected
-- CustomAuraContainerTemplate / CustomAuraButtonTemplate path. The Patch 114
-- renderer remains available for Config Mode, older clients, and per-frame
-- fallback when the 12.1 API rejects a container configuration.

local PitBull4 = _G.PitBull4
local PitBull4_Aura = PitBull4:GetModule("Aura")

local type = type
local tostring = tostring
local tonumber = tonumber
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local next = next
local table_concat = table.concat
local table_insert = table.insert
local math_huge = math.huge
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local native_enabled = true
local native_frames = setmetatable({}, { __mode = "k" })
local retired_states = setmetatable({}, { __mode = "k" })
local failed_frames = setmetatable({}, { __mode = "k" })
local pending_frames = setmetatable({}, { __mode = "k" })
local hidden_legacy = setmetatable({}, { __mode = "k" })
local retry_states = setmetatable({}, { __mode = "k" })
-- One initial attempt plus three automatic retries. Routine UNIT_AURA/world/
-- regen updates must not reset this budget for an incompatible native surface.
local RETRY_DELAYS = { 0.25, 1, 3 }
local retry_timer
local retry_timer_due
local schedule_recovery

local function in_combat_lockdown()
	return _G.InCombatLockdown and _G.InCombatLockdown()
end
local native_generation = 0
local dynamic_refresh_count = 0
local dynamic_refresh_mark_count = 0
local dynamic_refresh_bounce_count = 0
local container_surface_validated = false
local button_surface_validated = false
local native_surface_validated = false
local native_surface_error = nil

local GROUP_KEY = "pitbull"
local OWN_GROUP_KEY = "pitbull_own"
local OTHER_GROUP_KEY = "pitbull_other"
local NATIVE_COUNT_FONT_CAP_RATIO = 0.55
local NATIVE_DURATION_FONT_CAP_RATIO = 0.45
local NATIVE_BORDER_TEXTURE = [[Interface\AddOns\PitBull4\Modules\Aura\border]]

-- Patch 071 moved native AuraContainer duration text onto Blizzard's
-- DurationTextBinding path and proved that the visible runtime timer was not the
-- legacy PitBull updater. Live testing with W-47CH D0G also showed that forcing
-- DurationTimeModifier.BaseTime is not equivalent to Blizzard's tooltip display
-- time: a tooltip value of 34m could render as 4m.
--
-- Patch 072 therefore prefers the Cooldown widget's own countdown FontString.
-- CustomAuraButton already feeds that widget the protected aura DurationObject
-- through SetCooldownFromDurationObject(), so Blizzard remains responsible for
-- the live aura timing while PitBull only supplies presentation/formatting.
-- The Patch 071 BaseTime binding remains as a defensive fallback for clients
-- where the native Cooldown countdown text cannot be configured.
local native_compact_duration_formatter
local native_base_time_duration_options

local function get_native_compact_duration_formatter()
	if native_compact_duration_formatter ~= nil then
		return native_compact_duration_formatter or nil
	end

	if not C_StringUtil or not C_StringUtil.CreateSecondsFormatter then
		native_compact_duration_formatter = false
		return nil
	end

	local ok_formatter, formatter = pcall(C_StringUtil.CreateSecondsFormatter)
	if not ok_formatter or not formatter then
		native_compact_duration_formatter = false
		return nil
	end

	if formatter.SetDefaultAbbreviation and Enum and Enum.SecondsFormatterAbbreviation and Enum.SecondsFormatterAbbreviation.OneLetter then
		pcall(formatter.SetDefaultAbbreviation, formatter, Enum.SecondsFormatterAbbreviation.OneLetter)
	end
	if formatter.SetStripIntervalWhitespace then
		local whitespace = Enum and Enum.SecondsFormatterIntervalWhitespace and Enum.SecondsFormatterIntervalWhitespace.Strip
		pcall(formatter.SetStripIntervalWhitespace, formatter, whitespace ~= nil and whitespace or true)
	end
	if formatter.SetDesiredUnitCount then
		pcall(formatter.SetDesiredUnitCount, formatter, 1)
	end

	native_compact_duration_formatter = formatter
	return formatter
end

local function get_native_base_time_duration_options()
	if native_base_time_duration_options ~= nil then
		return native_base_time_duration_options or nil
	end

	if not C_DurationUtil or not C_DurationUtil.CreateDurationTextBinding
		or not Enum or not Enum.DurationTimeModifier or Enum.DurationTimeModifier.BaseTime == nil then
		native_base_time_duration_options = false
		return nil
	end

	local ok_binding, binding = pcall(C_DurationUtil.CreateDurationTextBinding)
	if not ok_binding or not binding then
		native_base_time_duration_options = false
		return nil
	end

	if binding.SetTimeModifier then
		local ok_modifier = pcall(binding.SetTimeModifier, binding, Enum.DurationTimeModifier.BaseTime)
		if not ok_modifier then
			native_base_time_duration_options = false
			return nil
		end
	end

	local formatter = get_native_compact_duration_formatter()
	if formatter and binding.SetFormatter then
		pcall(binding.SetFormatter, binding, formatter)
	end

	if binding.SetZeroDurationText then
		pcall(binding.SetZeroDurationText, binding, "")
	end

	native_base_time_duration_options = { binding = binding }
	return native_base_time_duration_options
end

-- Forever 1.60.1 exposes the managed AuraContainer core but not every
-- optional Midnight helper. Keep the required surface aligned with the
-- methods used by working Forever-native unit frames.
local REQUIRED_CONTAINER_METHODS = {
	"SetUnit",
	"GetUnit",
	"UpdateAllAuras",
	"AddAuraGroup",
	"SetAuraGroupEnabled",
	"SetAuraGroupFilterString",
	"SetAuraGroupMaxFrameCount",
	"SetAuraGroupLayout",
	"SetFlowLayoutAxis",
	"SetFlowLayoutAnchorPoint",
	"SetFlowLayoutGrowthDirection",
	"SetFlowLayoutMaximumLineSize",
}

local REQUIRED_BUTTON_METHODS = {
	"SetIcon",
	"SetDurationCooldown",
	"SetApplicationCount",
	"AddDispelTypeTexture",
	"SetTooltipAnchorPoint",
}

-- Keep Blizzard's 12.1.0.69111+ dispel-texture behavior explicit so a future
-- default change cannot silently alter PitBull's native aura presentation.
local NATIVE_DISPEL_TEXTURE_OPTIONS = {
	showAlways = false,
	showWhenHarmful = true,
	showWhenHelpful = false,
	showWithoutDispelType = false,
}

local growth_map = {
	left_up = { axis = "Horizontal", horizontal = "Left", vertical = "Up" },
	left_down = { axis = "Horizontal", horizontal = "Left", vertical = "Down" },
	right_up = { axis = "Horizontal", horizontal = "Right", vertical = "Up" },
	right_down = { axis = "Horizontal", horizontal = "Right", vertical = "Down" },
	up_left = { axis = "Vertical", horizontal = "Left", vertical = "Up" },
	up_right = { axis = "Vertical", horizontal = "Right", vertical = "Up" },
	down_left = { axis = "Vertical", horizontal = "Left", vertical = "Down" },
	down_right = { axis = "Vertical", horizontal = "Right", vertical = "Down" },
}

local control_point = {
	TOPLEFT_TOP = "BOTTOMLEFT",
	TOPRIGHT_TOP = "BOTTOMRIGHT",
	TOPLEFT_LEFT = "TOPRIGHT",
	TOPRIGHT_RIGHT = "TOPLEFT",
	BOTTOMLEFT_BOTTOM = "TOPLEFT",
	BOTTOMRIGHT_BOTTOM = "TOPRIGHT",
	BOTTOMLEFT_LEFT = "BOTTOMRIGHT",
	BOTTOMRIGHT_RIGHT = "BOTTOMLEFT",
}

local function get_object_method(object, method_name)
	if not object then
		return false, "missing-object"
	end
	local lookup_ok, method = pcall(function()
		return object[method_name]
	end)
	if not lookup_ok then
		return false, tostring(method)
	end
	if type(method) ~= "function" then
		return false, "missing-method:" .. tostring(method_name)
	end
	return true, method
end

local function call_method(object, method_name, ...)
	local method_ok, method = get_object_method(object, method_name)
	if not method_ok then
		return false, method
	end
	local ok, result = pcall(method, object, ...)
	if ok then
		return true, result
	end
	return false, tostring(result)
end

local function validate_object_surface(object, object_label, method_names)
	for _, method_name in ipairs(method_names) do
		local ok, err = get_object_method(object, method_name)
		if not ok then
			return false, object_label .. ":" .. tostring(err)
		end
	end
	return true
end

local function validate_container_surface(container)
	if container_surface_validated then
		return true
	end
	local ok, err = validate_object_surface(container, "container", REQUIRED_CONTAINER_METHODS)
	if not ok then
		native_surface_error = err
		return false, err
	end
	container_surface_validated = true
	return true
end

local function validate_button_surface(button)
	if button_surface_validated then
		return true
	end
	local ok, err = validate_object_surface(button, "button", REQUIRED_BUTTON_METHODS)
	if not ok then
		native_surface_error = err
		return false, err
	end
	button_surface_validated = true
	return true
end

local function reset_surface_validation()
	container_surface_validated = false
	button_surface_validated = false
	native_surface_validated = false
	native_surface_error = nil
end


local function get_unit_token(frame)
	if frame and type(frame.unit) == "string" and frame.unit ~= "" then
		return frame.unit
	end
	return "none"
end

local function get_native_text_rule(db, kind)
	if kind == "weapon" then
		return "weapon_buffs"
	end
	local my_rule = kind == "debuff" and "my_debuffs" or "my_buffs"
	local other_rule = kind == "debuff" and "other_debuffs" or "other_buffs"
	local enabled = db and db.cooldown_text
	-- A protected button may be reassigned between player and non-player auras,
	-- so ownership-specific styling cannot be selected from the aura record.
	-- Prefer the player's style unless only the other-aura timer is enabled.
	if enabled and not enabled[my_rule] and enabled[other_rule] then
		return other_rule
	end
	return my_rule
end

local function get_native_text_db(db, rule, text_kind)
	local rule_db = db and db.texts and db.texts[rule]
	return rule_db and rule_db[text_kind] or nil
end

local function get_native_border_db(db, kind)
	local borders = db and db.borders
	if type(borders) ~= "table" then
		return nil, nil, nil
	end
	if kind == "weapon" then
		return borders.weapon_buffs, "weapon_buffs", nil
	end

	-- The protected container owns the aura record, so addon code cannot safely
	-- distinguish the caster or relationship for every assigned button. Prefer
	-- PitBull's "my aura on a friendly unit" presentation: this restores the
	-- long-standing green own-buff border while keeping all secret data opaque.
	local rule = kind == "debuff" and "my_debuffs" or "my_buffs"
	local rule_db = borders[rule]
	return rule_db and rule_db.friend or nil, rule, "friend"
end

local function get_native_border_color(border_db)
	local profile = PitBull4_Aura.db and PitBull4_Aura.db.profile
	local global = profile and profile.global
	local colors = global and global.colors
	local color_type = border_db and border_db.color_type
	local color
	if color_type == "custom" then
		color = border_db.custom_color
	elseif color_type == "type" then
		color = colors and colors.type and colors.type.None
	else
		-- Caster and weapon-quality colors require protected per-aura metadata.
		-- Use PitBull's configured "my caster" color as the safe native fallback.
		color = colors and colors.caster and colors.caster.my
	end
	if type(color) ~= "table" then
		return 1, 1, 1, 1
	end
	return tonumber(color[1]) or 1, tonumber(color[2]) or 1, tonumber(color[3]) or 1, tonumber(color[4]) or 1
end

local function add_native_pitbull_border(button, db, kind)
	local border_db = get_native_border_db(db, kind)
	if not border_db or not border_db.enabled then
		return
	end

	-- This is deliberately not registered as a protected dispel texture. It is
	-- an always-present visual child of the protected aura button, so it follows
	-- the button's secret visibility without inspecting the assigned aura.
	local border = button:CreateTexture(nil, "BORDER")
	border:SetAllPoints(button)
	border:SetTexture(NATIVE_BORDER_TEXTURE)
	border:SetBlendMode("BLEND")
	border:SetVertexColor(get_native_border_color(border_db))
	border:Show()
end

local function ownership_style_enabled(db)
	return db and db.ownership_style and db.ownership_style.enabled and true or false
end

local function get_ownership_color(db, ownership)
	local style = db and db.ownership_style
	local color = style and (ownership == "own" and style.own_color or style.other_color)
	if type(color) ~= "table" then
		if ownership == "own" then
			return 0, 1, 0, 1
		end
		return 1, 0, 0, 1
	end
	return tonumber(color[1]) or 1, tonumber(color[2]) or 1, tonumber(color[3]) or 1, tonumber(color[4]) or 1
end

local function add_native_ownership_border(button, db, ownership)
	if not ownership_style_enabled(db) or (ownership ~= "own" and ownership ~= "other") then
		return false
	end
	local border = button:CreateTexture(nil, "BORDER")
	border:SetAllPoints(button)
	border:SetTexture(NATIVE_BORDER_TEXTURE)
	border:SetBlendMode("BLEND")
	border:SetVertexColor(get_ownership_color(db, ownership))
	border:Show()
	return true
end

-- A combined group has no public, per-button ownership metadata. Never color
-- every buff as "mine" or infer caster from protected aura data. Keep a
-- neutral border in strict mode, preserving the configured ownership toggle.
local function add_native_combined_border(button, db)
	if not ownership_style_enabled(db) then
		return
	end
	local border = button:CreateTexture(nil, "BORDER")
	border:SetAllPoints(button)
	border:SetTexture(NATIVE_BORDER_TEXTURE)
	border:SetBlendMode("BLEND")
	border:SetVertexColor(1, 1, 1, 1)
	border:Show()
end

local function get_ownership_icon_size(db, cfg, kind, ownership)
	local base = tonumber(cfg and cfg.size) or 16
	if ownership ~= "own" then
		return base
	end

	local style = db and db.ownership_style
	-- Patch 075: preserve the classic PitBull "Icon size for my auras"
	-- setting on the native 12.1 AuraContainer path. Patch 067 added an
	-- optional absolute ownership-size override, but the native renderer must
	-- still honor cfg.my_size whenever that explicit override is disabled.
	if style and style.different_size then
		local configured = kind == "debuff" and tonumber(style.own_debuff_size) or tonumber(style.own_buff_size)
		if configured and configured > 0 then
			return configured
		end
		-- A zero ownership override intentionally inherits the normal aura size.
		return base
	end

	local classic_my_size = tonumber(cfg and cfg.my_size)
	if classic_my_size and classic_my_size > 0 then
		return classic_my_size
	end
	return base
end

local function append_native_border_signature(parts, db, kind)
	local border_db, rule, relationship = get_native_border_db(db, kind)
	local r, g, b, a = get_native_border_color(border_db)
	parts[#parts + 1] = table_concat({
		"border",
		tostring(kind),
		tostring(rule),
		tostring(relationship),
		tostring(border_db and border_db.enabled or false),
		tostring(border_db and border_db.color_type or "none"),
		tostring(r), tostring(g), tostring(b), tostring(a),
	}, ",")
end

local function get_native_justify_h(anchor)
	if type(anchor) == "string" then
		if anchor:find("RIGHT", 1, true) then
			return "RIGHT"
		elseif anchor:find("LEFT", 1, true) then
			return "LEFT"
		end
	end
	return "CENTER"
end

local function resolve_native_text_style(owner_frame, db, kind, text_kind, icon_size)
	local rule = get_native_text_rule(db, kind)
	local text_db = get_native_text_db(db, rule, text_kind) or {}
	local fallback_anchor = text_kind == "count" and "BOTTOMRIGHT" or "TOP"
	local cap_ratio = text_kind == "count" and NATIVE_COUNT_FONT_CAP_RATIO or NATIVE_DURATION_FONT_CAP_RATIO
	local resolved_font
	local resolved_size
	if owner_frame and type(owner_frame.GetFont) == "function" then
		local ok, font, font_size = pcall(owner_frame.GetFont, owner_frame, text_db.font, text_db.size)
		if ok then
			resolved_font = font
			resolved_size = tonumber(font_size)
		end
	end
	icon_size = tonumber(icon_size) or 16
	local maximum_size = math_max(1, icon_size * cap_ratio)
	resolved_size = math_max(1, math_min(resolved_size or maximum_size, maximum_size))
	local color = type(text_db.color) == "table" and text_db.color or nil
	return {
		rule = rule,
		font = resolved_font or _G.STANDARD_TEXT_FONT,
		fontSize = resolved_size,
		anchor = type(text_db.anchor) == "string" and text_db.anchor or fallback_anchor,
		offsetX = tonumber(text_db.offset_x) or 0,
		offsetY = tonumber(text_db.offset_y) or 0,
		colorR = color and tonumber(color[1]) or 1,
		colorG = color and tonumber(color[2]) or 1,
		colorB = color and tonumber(color[3]) or 1,
		colorA = color and tonumber(color[4]) or 1,
	}
end

local function configure_native_font_string(font_string, button, owner_frame, db, kind, text_kind, icon_size)
	local style = resolve_native_text_style(owner_frame, db, kind, text_kind, icon_size)
	font_string:SetFont(style.font, style.fontSize, "OUTLINE")
	font_string:SetTextColor(style.colorR, style.colorG, style.colorB, style.colorA)
	font_string:SetShadowColor(0, 0, 0, 1)
	font_string:SetShadowOffset(0.8, -0.8)
	font_string:SetJustifyH(get_native_justify_h(style.anchor))
	font_string:ClearAllPoints()
	font_string:SetPoint(style.anchor, button, style.anchor, style.offsetX, style.offsetY)
	return style
end

local function append_native_text_style_signature(parts, owner_frame, db, kind, text_kind, icon_size)
	local style = resolve_native_text_style(owner_frame, db, kind, text_kind, icon_size)
	parts[#parts + 1] = table_concat({
		tostring(kind),
		tostring(text_kind),
		tostring(style.rule),
		tostring(style.font),
		tostring(style.fontSize),
		tostring(style.anchor),
		tostring(style.offsetX),
		tostring(style.offsetY),
		tostring(style.colorR),
		tostring(style.colorG),
		tostring(style.colorB),
		tostring(style.colorA),
	}, ",")
end

local function get_native_capabilities()
	local state = PitBull4_Aura.Lorenzo121
	if PitBull4_Aura.Lorenzo121RefreshCapabilities then
		state = PitBull4_Aura:Lorenzo121RefreshCapabilities()
	end
	return state
end

local function native_methods_ready(state)
	return state and state.nativeAPIPrerequisitesReady
		and type(_G.CreateFrame) == "function"
		and type(_G.AnchorUtil) == "table"
		and type(_G.AnchorUtil.FlowLayoutAxis) == "table"
		and type(_G.AnchorUtil.FlowDirection) == "table"
end

local function should_use_native(frame)
	if not native_enabled or not frame or frame.force_show then
		return false
	end
	local state = get_native_capabilities()
	return state and state.is121OrNewer and state.auraContainerAddonLoaded and native_methods_ready(state)
end

local function enum_value(container, key, fallback)
	if type(container) == "table" and container[key] ~= nil then
		return container[key]
	end
	return fallback
end

local function get_sort_method(cfg, is_buff)
	local method_name = cfg and cfg.sort_rule or "Default"
	local methods = _G.AuraContainerSortMethod
	-- PitBull's legacy/API sort rule is named Unsorted. Blizzard's 12.1 native
	-- AuraContainer exposes the equivalent stable instance order as
	-- AuraInstanceIDOnly, so a direct enum-name lookup would otherwise fall back
	-- to Default and visibly reshuffle the user's auras.
	if method_name == "Unsorted" then
		method_name = "AuraInstanceIDOnly"
	end
	local method = enum_value(methods, method_name, nil)
	if method == nil and not is_buff then
		method = enum_value(methods, "UnitFrameDebuff", nil)
	end
	return method or enum_value(methods, "Default", 0)
end

local function get_sort_direction(cfg)
	local directions = _G.AuraContainerSortDirection
	if cfg and cfg.reverse then
		return enum_value(directions, "Reverse", 1)
	end
	return enum_value(directions, "Normal", 0)
end

local function get_filter_string(cfg, is_buff)
	local base = is_buff and "HELPFUL" or "HARMFUL"
	local filter_name = cfg and cfg.filter_new or ""
	-- PitBull's built-in "mine" filters can be represented by Blizzard's filter
	-- string without reading the protected aura record in addon code.
	if filter_name == "!C" or filter_name == "!E" then
		return base .. "|PLAYER", "native-mine"
	end
	if filter_name == nil or filter_name == "" or filter_name == "!B" or filter_name == "!D"
		or filter_name == "!N" or filter_name == "!P" or filter_name == "!Q" then
		return base, "native-builtin"
	end
	-- Arbitrary PitBull meta/Lua filters cannot safely inspect protected aura
	-- records. Keep the frame functional with the base Blizzard filter and expose
	-- the approximation in /pitbull 121status.
	return base, "approximate:" .. tostring(filter_name)
end

-- Cross-zone fallback (v48): UnitIsVisible(false) is only a conservative
-- reachability signal, not proof of a different zone. Never inspect aura
-- ownership data or make protected layout changes in combat.
local function safe_plain_boolean_api(api, unit)
    if type(api) ~= "function" then return nil end
    local ok, result = pcall(api, unit)
    if not ok or type(result) ~= "boolean" then return nil end
    -- A secret boolean cannot be tested, negated or compared in Lua.
    if type(_G.issecretvalue) == "function" then
        local checked, secret = pcall(_G.issecretvalue, result)
        if not checked or secret ~= false then return nil end
    end
    return result
end

local function should_combine_unreachable_roster(owner_frame)
    local unit = owner_frame and get_unit_token(owner_frame)
    if type(unit) ~= "string" then return false end
    local party_owner = unit:match("^partypet(%d+)$")
    local roster_unit = party_owner and ("party" .. party_owner) or unit
    if not (roster_unit:match("^party%d+$") or roster_unit:match("^raid%d+$")) then
        return false
    end
    -- Party pets inherit their owner's cross-zone reachability. Querying only
    -- the pet can give an inconclusive result while its owner is out of phase.
    if safe_plain_boolean_api(_G.UnitExists, roster_unit) ~= true then return false end
    if safe_plain_boolean_api(_G.UnitInPhase, roster_unit) == false then return true end
    if safe_plain_boolean_api(_G.UnitIsVisible, roster_unit) == false then return true end
    if party_owner and safe_plain_boolean_api(_G.UnitExists, unit) == true then
        if safe_plain_boolean_api(_G.UnitInPhase, unit) == false then return true end
        if safe_plain_boolean_api(_G.UnitIsVisible, unit) == false then return true end
    end
    return false
end

local function get_ownership_group_filters(db, cfg, is_buff, owner_frame)
	local base_filter, mode = get_filter_string(cfg, is_buff)
	-- A single native AuraGroup is the only way to enforce a true combined
	-- limit without reading protected per-group counts. It also removes any
	-- possibility of cross-group duplication during cross-instance transitions.
	-- PLAYER-only filters are naturally single-group and retain own styling.
	if mode == "native-mine" then
		return base_filter, nil, mode
	end
	if db and db.native_strict_limit ~= false then
		return base_filter, nil, "native-combined:" .. mode
	end
	-- Avoid two native AuraGroups on inaccessible roster units. Blizzard
	-- may return overlapping ownership results for these units.
	if should_combine_unreachable_roster(owner_frame) then
		return base_filter, nil, "native-crosszone-combined:" .. mode
	end
	-- Optional legacy appearance: separate own/other sizes and borders.
	-- Blizzard's maxFrameCount is PER GROUP, not a combined cap.
	local base = is_buff and "HELPFUL" or "HARMFUL"
	return base .. "|PLAYER", base .. "|!PLAYER", mode
end

local function mirror_horizontal_point(value)
	return value:gsub("LEFT", "temp"):gsub("RIGHT", "LEFT"):gsub("temp", "RIGHT")
end

local function mirror_vertical_point(value)
	return value:gsub("BOTTOM", "temp"):gsub("TOP", "BOTTOM"):gsub("temp", "TOP")
end

local function mirror_horizontal_growth(value)
	return value:gsub("left", "temp"):gsub("right", "left"):gsub("temp", "right")
end

local function mirror_vertical_growth(value)
	return value:gsub("down", "temp"):gsub("up", "down"):gsub("temp", "up")
end

local function get_effective_layout(owner_frame, cfg)
	local anchor = type(cfg and cfg.anchor) == "string" and cfg.anchor or "BOTTOMLEFT"
	local side = type(cfg and cfg.side) == "string" and cfg.side or "BOTTOM"
	local growth_name = type(cfg and cfg.growth) == "string" and cfg.growth or "right_down"
	local offset_x = tonumber(cfg and cfg.offset_x) or 0
	local offset_y = tonumber(cfg and cfg.offset_y) or 0
	local classification_db = owner_frame and owner_frame.classification_db
	local horizontal_mirror = classification_db and classification_db.horizontal_mirror and true or false
	local vertical_mirror = classification_db and classification_db.vertical_mirror and true or false

	-- Match Layout.lua exactly. Mirrored unit classifications transform the aura
	-- anchor, attachment side, growth direction, and signed offset together.
	-- The protected AuraContainer can then perform the layout without PitBull
	-- touching any assigned aura data.
	if horizontal_mirror then
		anchor = mirror_horizontal_point(anchor)
		side = mirror_horizontal_point(side)
		growth_name = mirror_horizontal_growth(growth_name)
		offset_x = -offset_x
	end
	if vertical_mirror then
		anchor = mirror_vertical_point(anchor)
		side = mirror_vertical_point(side)
		growth_name = mirror_vertical_growth(growth_name)
		offset_y = -offset_y
	end

	local growth = growth_map[growth_name]
	if not growth then
		growth_name = "right_down"
		growth = growth_map.right_down
	end
	local point = control_point[anchor .. "_" .. side] or anchor
	return {
		anchor = anchor,
		side = side,
		point = point,
		growthName = growth_name,
		growth = growth,
		offsetX = offset_x,
		offsetY = offset_y,
		horizontalMirror = horizontal_mirror,
		verticalMirror = vertical_mirror,
	}
end

local function get_maximum_line_size(owner_frame, cfg, growth)
	local width_type = cfg and cfg.width_type or "percent"
	if width_type == "fixed" then
		local value = tonumber(cfg and cfg.width)
		return value and value > 0 and value or math_huge
	end
	local percent = tonumber(cfg and cfg.width_percent) or 0.5
	if percent > 1 then
		percent = percent / 100
	end
	local side_size
	if growth.axis == "Vertical" then
		side_size = owner_frame:GetHeight()
	else
		side_size = owner_frame:GetWidth()
	end
	if not side_size or side_size <= 0 then
		return math_huge
	end
	return side_size * percent
end

local function get_size_to_fit(owner_frame, cfg, growth, base_size)
	local size = tonumber(base_size) or tonumber(cfg and cfg.size) or 16
	if not (cfg and cfg.size_to_fit) then
		return size
	end
	local maximum = get_maximum_line_size(owner_frame, cfg, growth)
	if not maximum or maximum == math_huge or maximum <= 0 then
		return size
	end
	local spacing = tonumber(cfg and cfg.col_spacing) or 0
	-- Match Layout.lua's classic Size to fit calculation: determine how many
	-- icons of the requested size fit on the configured side, then expand them
	-- evenly to consume that side. Native own/other aura groups are calculated
	-- independently because they may use different icon sizes.
	local count = math_floor(maximum / (size + spacing))
	if count > 0 then
		return size * maximum / ((size + spacing) * count)
	end
	return size
end

local function raid_perf_suppresses(owner_frame, kind)
	return kind == "buff"
		and PitBull4_Aura.LorenzoPatch105RaidPerfActiveForUnit
		and PitBull4_Aura:LorenzoPatch105RaidPerfActiveForUnit(get_unit_token(owner_frame))
end

local function get_display_policy(owner_frame, db, kind)
	local is_buff = kind ~= "debuff"
	local show_cooldown
	local show_text
	if kind == "weapon" then
		show_cooldown = db.cooldown and db.cooldown.weapon_buffs
		show_text = db.cooldown_text and db.cooldown_text.weapon_buffs
	elseif is_buff then
		show_cooldown = db.cooldown and (db.cooldown.my_buffs or db.cooldown.other_buffs)
		show_text = db.cooldown_text and (db.cooldown_text.my_buffs or db.cooldown_text.other_buffs)
	else
		show_cooldown = db.cooldown and (db.cooldown.my_debuffs or db.cooldown.other_debuffs)
		show_text = db.cooldown_text and (db.cooldown_text.my_debuffs or db.cooldown_text.other_debuffs)
	end
	if raid_perf_suppresses(owner_frame, kind) then
		show_cooldown = false
		show_text = false
	end
	return show_cooldown and true or false, show_text and true or false
end

local function initialize_native_button(button, owner_frame, kind, ownership)
	local surface_ok, surface_err = validate_button_surface(button)
	if not surface_ok then
		error(surface_err, 0)
	end
	local db = PitBull4_Aura:GetLayoutDB(owner_frame)
	local is_buff = kind ~= "debuff"
	local cfg = is_buff and db.layout.buff or db.layout.debuff
	local size = get_ownership_icon_size(db, cfg, kind, ownership)
	local show_cooldown, show_text = get_display_policy(owner_frame, db, kind)

	button:SetSize(size, size)
	button:SetFrameLevel((owner_frame:GetFrameLevel() or 1) + 10)

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetAllPoints(button)
	if db.zoom_aura then
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	else
		icon:SetTexCoord(0, 1, 0, 1)
	end
	button:SetIcon(icon)
	if ownership == "combined" then
		add_native_combined_border(button, db)
	elseif not add_native_ownership_border(button, db, ownership) then
		add_native_pitbull_border(button, db, kind)
	end

	local overlay = _G.CreateFrame("Frame", nil, button)
	overlay:SetAllPoints(button)
	overlay:SetFrameLevel(button:GetFrameLevel() + 2)

	local native_cooldown_text_active = false
	if show_cooldown or show_text then
		local cooldown = _G.CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		cooldown:SetAllPoints(button)
		cooldown:SetReverse(true)
		cooldown:SetDrawEdge(false)
		if cooldown.SetDrawSwipe then
			cooldown:SetDrawSwipe(show_cooldown)
		end
		if not show_cooldown and cooldown.SetDrawBling then
			cooldown:SetDrawBling(false)
		end

		-- Keep the template's countdown hidden until the Patch 072 presentation
		-- setup succeeds. This prevents duplicate text if we need the Patch 071
		-- DurationTextBinding fallback below.
		cooldown:SetHideCountdownNumbers(true)
		cooldown.noCooldownCount = (db.suppress_occ or show_text) and true or nil

		if show_text and cooldown.GetCountdownFontString then
			if cooldown.SetMinimumCountdownDuration then
				pcall(cooldown.SetMinimumCountdownDuration, cooldown, 0)
			end
			local ok_font_string, countdown_text = pcall(cooldown.GetCountdownFontString, cooldown)
			if ok_font_string and countdown_text then
				configure_native_font_string(countdown_text, button, owner_frame, db, kind, "cooldown_text", size)
				local formatter = get_native_compact_duration_formatter()
				if formatter and cooldown.SetCountdownFormatter then
					pcall(cooldown.SetCountdownFormatter, cooldown, formatter)
				end
				cooldown:SetHideCountdownNumbers(false)
				native_cooldown_text_active = true
			end
		end

		-- CustomAuraButton owns the protected DurationObject and updates this
		-- Cooldown with SetCooldownFromDurationObject(). Do not additionally call
		-- SetUseAuraDisplayTime here: DurationObject cooldowns already carry their
		-- aura timing semantics. PitBull does not inspect, compare, or transform
		-- the aura's protected timing values.
		button:SetDurationCooldown(cooldown)
		overlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)
	end

	local count = overlay:CreateFontString(nil, "OVERLAY")
	configure_native_font_string(count, button, owner_frame, db, kind, "count", size)
	button:SetApplicationCount(count, nil)

	if show_text and not native_cooldown_text_active then
		local duration_text = overlay:CreateFontString(nil, "OVERLAY")
		configure_native_font_string(duration_text, button, owner_frame, db, kind, "cooldown_text", size)
		-- Patch 071 fallback only. BaseTime was useful for proving the active native
		-- duration path, but live testing showed it does not match tooltip display
		-- time for all externally time-scaled auras.
		local duration_options = get_native_base_time_duration_options()
		if type(button.SetDurationText) == "function" then
			local ok_duration = pcall(button.SetDurationText, button, duration_text, duration_options)
			if not ok_duration then
				pcall(button.SetDurationText, button, duration_text, nil)
			end
		end
	end

	local dispel = button:CreateTexture(nil, "BORDER")
	dispel:SetAllPoints(button)
	button:AddDispelTypeTexture(dispel, NATIVE_DISPEL_TEXTURE_OPTIONS)

	button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT", 0, 0)
	if type(button.SetHideTooltipInCombat) == "function" then button:SetHideTooltipInCombat(false) end
	if db.click_through then
		button:EnableMouse(false)
	elseif get_unit_token(owner_frame) == "player" and is_buff then
		-- The protected AuraButton cancels auras and temporary weapon enchants
		-- internally without exposing the aura instance to PitBull.
		button:SetCancelAuraButtons("RightButtonUp")
	else
		button:SetCancelAuraButtons(nil)
	end
end

local function get_signature(owner_frame, db, cfg, is_buff)
	local layout = get_effective_layout(owner_frame, cfg)
	local growth = layout.growth
	local kind = is_buff and "buff" or "debuff"
	local show_cooldown, show_text = get_display_policy(owner_frame, db, kind)
	local weapon_cooldown, weapon_text = get_display_policy(owner_frame, db, "weapon")
	local icon_size = tonumber(cfg and cfg.size) or 16
	local own_layout_size = get_size_to_fit(owner_frame, cfg, growth, get_ownership_icon_size(db, cfg, kind, "own"))
	local other_layout_size = get_size_to_fit(owner_frame, cfg, growth, get_ownership_icon_size(db, cfg, kind, "other"))
	local own_filter, other_filter, filter_mode = get_ownership_group_filters(db, cfg, is_buff, owner_frame)
	local parts = {
		kind,
		tostring(db.native_strict_limit ~= false),
		tostring(cfg and cfg.filter_new or ""),
		tostring(own_filter), tostring(other_filter), tostring(filter_mode),
		tostring(layout.point), tostring(layout.anchor), tostring(layout.side), tostring(layout.growthName),
		tostring(growth.axis), tostring(growth.horizontal), tostring(growth.vertical),
		tostring(layout.offsetX), tostring(layout.offsetY),
		tostring(layout.horizontalMirror), tostring(layout.verticalMirror),
		tostring(icon_size), tostring(cfg and cfg.my_size or 0), tostring(cfg and cfg.col_spacing or 0), tostring(cfg and cfg.row_spacing or 0),
		tostring(cfg and cfg.size_to_fit or false), tostring(cfg and cfg.width_type or "percent"),
		tostring(cfg and cfg.width or 0), tostring(cfg and cfg.width_percent or 0),
		tostring(own_layout_size), tostring(other_layout_size),
		tostring(db.zoom_aura), tostring(db.click_through), tostring(db.suppress_occ),
		tostring(show_cooldown), tostring(show_text),
		tostring(owner_frame and get_unit_token(owner_frame) == "player"),
		tostring(is_buff and db.enabled_weapons or false),
		tostring(is_buff and weapon_cooldown or false), tostring(is_buff and weapon_text or false),
	}
	append_native_border_signature(parts, db, kind)
	append_native_text_style_signature(parts, owner_frame, db, kind, "count", icon_size)
	if show_text then
		append_native_text_style_signature(parts, owner_frame, db, kind, "cooldown_text", icon_size)
	end
	if is_buff and get_unit_token(owner_frame) == "player" and db.enabled_weapons then
		append_native_border_signature(parts, db, "weapon")
		append_native_text_style_signature(parts, owner_frame, db, "weapon", "count", icon_size)
		if weapon_text then
			append_native_text_style_signature(parts, owner_frame, db, "weapon", "cooldown_text", icon_size)
		end
	end
	local ownership_style = db and db.ownership_style or nil
	local own_r, own_g, own_b, own_a = get_ownership_color(db, "own")
	local other_r, other_g, other_b, other_a = get_ownership_color(db, "other")
	parts[#parts + 1] = table_concat({
		"ownership", tostring(ownership_style and ownership_style.enabled or false),
		tostring(own_r), tostring(own_g), tostring(own_b), tostring(own_a),
		tostring(other_r), tostring(other_g), tostring(other_b), tostring(other_a),
		tostring(ownership_style and ownership_style.different_size or false),
		tostring(ownership_style and ownership_style.own_buff_size or 0),
		tostring(ownership_style and ownership_style.own_debuff_size or 0),
	}, ",")
	return table_concat(parts, ":")
end

local function configure_holder(holder, owner_frame, cfg)
	local layout = get_effective_layout(owner_frame, cfg)
	holder:ClearAllPoints()
	holder:SetPoint(layout.point, owner_frame, layout.anchor, layout.offsetX, layout.offsetY)
	holder:SetSize(1, 1)
	holder:SetFrameLevel((owner_frame:GetFrameLevel() or 1) + (cfg.frame_level or 9))
	return layout.point, layout
end

local function layout_options(cfg, is_buff, size_override, layout_index)
	local element_size = tonumber(size_override) or tonumber(cfg and cfg.size) or 16
	return {
		elementSpacing = tonumber(cfg and cfg.col_spacing) or 0,
		lineSpacing = tonumber(cfg and cfg.row_spacing) or 0,
		groupSpacing = 0,
		groupLineSpacing = 0,
		forceNewLine = false,
		elementWidth = element_size,
		elementHeight = element_size,
		layoutIndex = layout_index or 1,
	}
end

local function configure_container_layout(container, owner_frame, db, cfg, is_buff)
	local layout = get_effective_layout(owner_frame, cfg)
	local growth = layout.growth
	local axis = enum_value(_G.AnchorUtil.FlowLayoutAxis, growth.axis, _G.AnchorUtil.FlowLayoutAxis.Horizontal)
	local horizontal = enum_value(_G.AnchorUtil.FlowDirection, growth.horizontal, _G.AnchorUtil.FlowDirection.Right)
	local vertical = enum_value(_G.AnchorUtil.FlowDirection, growth.vertical, _G.AnchorUtil.FlowDirection.Down)
	local ok, err = call_method(container, "SetFlowLayoutAxis", axis)
	if not ok then return false, err end
	ok, err = call_method(container, "SetFlowLayoutAnchorPoint", layout.point)
	if not ok then return false, err end
	ok, err = call_method(container, "SetFlowLayoutGrowthDirection", horizontal, vertical)
	if not ok then return false, err end
	ok, err = call_method(container, "SetFlowLayoutPadding", 0, 0, 0, 0)
	if not ok then return false, err end
	ok, err = call_method(container, "SetFlowLayoutMaximumLineSize", get_maximum_line_size(owner_frame, cfg, growth))
	if not ok then return false, err end
	local kind = is_buff and "buff" or "debuff"
	local primary_filter, other_filter = get_ownership_group_filters(db, cfg, is_buff, owner_frame)
	local primary_ownership = other_filter and "own" or (primary_filter:find("|PLAYER", 1, true) and "own" or "combined")
	local own_size = get_size_to_fit(owner_frame, cfg, growth, get_ownership_icon_size(db, cfg, kind, primary_ownership))
	ok, err = call_method(container, "SetAuraGroupLayout", OWN_GROUP_KEY, layout_options(cfg, is_buff, own_size, 1))
	if not ok then return false, err end
	if other_filter then
		local other_size = get_size_to_fit(owner_frame, cfg, growth, get_ownership_icon_size(db, cfg, kind, "other"))
		ok, err = call_method(container, "SetAuraGroupLayout", OTHER_GROUP_KEY, layout_options(cfg, is_buff, other_size, 2))
		if not ok then return false, err end
	end
	return true, nil, layout
end

local function add_weapon_enchantments(container, owner_frame, db, cfg)
	if get_unit_token(owner_frame) ~= "player" or not db.enabled_weapons then
		return false
	end
	local slots = _G.AuraContainerItemEnchantmentSlot
	if type(slots) ~= "table" or type(container.AddItemEnchantment) ~= "function" then
		return false
	end
	local options = {
		hidePermanent = false,
		initializeFrame = function(aura_button)
			initialize_native_button(aura_button, owner_frame, "weapon")
		end,
	}
	container:AddItemEnchantment(slots.MainHand, options)
	container:AddItemEnchantment(slots.OffHand, options)
	if type(_G.AuraContainerItemEnchantmentSortMethod) == "table" then
		container:SetItemEnchantmentSortMethod(
			enum_value(_G.AuraContainerItemEnchantmentSortMethod, "Slot", 0),
			enum_value(_G.AuraContainerSortDirection, "Normal", 0)
		)
	end
	if type(_G.CustomAuraContainerItemEnchantmentPlacement) == "table" then
		local item_layout = layout_options(cfg, true)
		item_layout.layoutIndex = 0
		item_layout.placement = enum_value(_G.CustomAuraContainerItemEnchantmentPlacement, "BeforeAuraGroups", 0)
		container:SetItemEnchantmentLayout(item_layout)
	end
	return true
end

local function get_group_enabled(db, is_buff)
	-- Do not write this as `is_buff and db.enabled_buffs or
	-- db.enabled_debuffs`. Lua's common and/or ternary idiom falls through to
	-- the debuff value when enabled_buffs is false. With Buffs off and Debuffs
	-- on, that made the native buff group remain enabled.
	if is_buff then
		return db.enabled_buffs
	end
	return db.enabled_debuffs
end

local function create_native_group(owner_frame, db, is_buff, groups)
	local cfg = is_buff and db.layout.buff or db.layout.debuff
	local initially_enabled = get_group_enabled(db, is_buff)
	local holder = _G.CreateFrame("Frame", nil, owner_frame)
	-- Retain partial allocations so an exception anywhere in construction can
	-- retire both surfaces before a bounded retry creates their replacements.
	local group = { holder = holder }
	groups[is_buff and "buff" or "debuff"] = group
	local point, effective_layout = configure_holder(holder, owner_frame, cfg)
	local container = _G.CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
	group.container = container
	if type(container.SetEditModePreviewEnabled) == "function" then
		container:SetEditModePreviewEnabled(false)
	end
	local surface_ok, surface_err = validate_container_surface(container)
	if not surface_ok then
		error(surface_err, 0)
	end
	container:SetPoint(point, holder, point, 0, 0)
	container:SetFrameLevel(holder:GetFrameLevel())

	local own_filter, other_filter, filter_mode = get_ownership_group_filters(db, cfg, is_buff, owner_frame)
	group.otherFilterString = other_filter
	local kind = is_buff and "buff" or "debuff"
	local primary_ownership = other_filter and "own" or (filter_mode == "native-mine" and "own" or "combined")
	local own_size = get_ownership_icon_size(db, cfg, kind, primary_ownership)
	local other_size = get_ownership_icon_size(db, cfg, kind, "other")
	container:AddAuraGroup(OWN_GROUP_KEY, own_filter, {
		maxFrameCount = is_buff and db.max_buffs or db.max_debuffs,
		initializeFrame = function(aura_button)
			initialize_native_button(aura_button, owner_frame, kind, primary_ownership)
		end,
		sortMethod = get_sort_method(cfg, is_buff),
		sortDirection = get_sort_direction(cfg),
		layout = layout_options(cfg, is_buff, own_size, 1),
	})
	if other_filter then
		container:AddAuraGroup(OTHER_GROUP_KEY, other_filter, {
			maxFrameCount = is_buff and db.max_buffs or db.max_debuffs,
			initializeFrame = function(aura_button)
				initialize_native_button(aura_button, owner_frame, kind, "other")
			end,
			sortMethod = get_sort_method(cfg, is_buff),
			sortDirection = get_sort_direction(cfg),
			layout = layout_options(cfg, is_buff, other_size, 2),
		})
	end
	local has_weapon_enchants = is_buff and add_weapon_enchantments(container, owner_frame, db, cfg) or false
	local layout_ok, layout_err, container_layout = configure_container_layout(container, owner_frame, db, cfg, is_buff)
	if not layout_ok then
		error(layout_err, 0)
	end
	effective_layout = container_layout or effective_layout
	container:SetUnit(get_unit_token(owner_frame))
	container:SetAuraGroupEnabled(OWN_GROUP_KEY, initially_enabled and true or false)
	if other_filter then
		container:SetAuraGroupEnabled(OTHER_GROUP_KEY, initially_enabled and true or false)
	end
	holder:SetShown(initially_enabled and true or false)
	container:SetShown(initially_enabled and true or false)
	native_surface_validated = container_surface_validated and button_surface_validated
	native_surface_error = nil

	return {
		holder = holder,
		container = container,
		isBuff = is_buff,
		filterString = own_filter,
		otherFilterString = other_filter,
		filterMode = filter_mode,
		ownershipMode = primary_ownership == "combined" and "combined" or (other_filter and "split" or "mine-only"),
		hasWeaponEnchantments = has_weapon_enchants,
		enabled = initially_enabled and true or false,
		effectiveLayout = effective_layout,
		signature = get_signature(owner_frame, db, cfg, is_buff),
	}
end

local function hide_group(group)
	if not group then
		return
	end
	if group.container then
		call_method(group.container, "SetAuraGroupEnabled", OWN_GROUP_KEY, false)
		if group.otherFilterString then
			call_method(group.container, "SetAuraGroupEnabled", OTHER_GROUP_KEY, false)
		end
		pcall(group.container.Hide, group.container)
	end
	if group.holder then
		pcall(group.holder.Hide, group.holder)
	end
end

local function retire_state(frame, state)
	if not state then
		return
	end
	for _, group in pairs(state.groups or {}) do
		hide_group(group)
	end
	retired_states[state] = true
	native_frames[frame] = nil
end

local function snapshot_native_states()
	local snapshot = {}
	for frame, state in pairs(native_frames) do
		snapshot[#snapshot + 1] = { frame = frame, state = state }
	end
	return snapshot
end

local function retire_all_states()
	local snapshot = snapshot_native_states()
	for index = 1, #snapshot do
		retire_state(snapshot[index].frame, snapshot[index].state)
	end
end

local function record_failure(frame, error_text)
	failed_frames[frame] = tostring(error_text or "unknown")
	local retry = retry_states[frame] or { attempts = 0 }
	retry_states[frame] = retry
	retry.attempts = retry.attempts + 1
	local delay = RETRY_DELAYS[retry.attempts]
	retry.due = delay and (_G.GetTime() + delay) or nil
	local state = native_frames[frame]
	if state then
		state.lastError = failed_frames[frame]
	end
	schedule_recovery()
end

local function clear_failure(frame)
	failed_frames[frame] = nil
	retry_states[frame] = nil
end

local function create_native_state(frame, db)
	native_generation = native_generation + 1
	local state = {
		generation = native_generation,
		groups = {},
		unit = get_unit_token(frame),
		lastError = nil,
	}
	native_frames[frame] = state
	local ok, result = pcall(function()
		state.groups.buff = create_native_group(frame, db, true, state.groups)
		state.groups.debuff = create_native_group(frame, db, false, state.groups)
	end)
	if not ok then
		retire_state(frame, state)
		return nil, result
	end
	return state
end

local function group_needs_rebuild(group, owner_frame, db, cfg, is_buff)
	return not group or group.signature ~= get_signature(owner_frame, db, cfg, is_buff)
end

local function configure_group(group, frame, db, is_buff)
	local cfg = is_buff and db.layout.buff or db.layout.debuff
	local enabled = get_group_enabled(db, is_buff)
	if not group or not group.container then
		return false, "missing-group"
	end
	local _, effective_layout = configure_holder(group.holder, frame, cfg)
	local own_filter, other_filter, filter_mode = get_ownership_group_filters(db, cfg, is_buff, frame)
	if group.filterString ~= own_filter then
		local ok, err = call_method(group.container, "SetAuraGroupFilterString", OWN_GROUP_KEY, own_filter)
		if not ok then return false, err end
		group.filterString = own_filter
	end
	if group.otherFilterString and other_filter and group.otherFilterString ~= other_filter then
		local ok, err = call_method(group.container, "SetAuraGroupFilterString", OTHER_GROUP_KEY, other_filter)
		if not ok then return false, err end
		group.otherFilterString = other_filter
	end
	group.filterMode = filter_mode
	-- Keep a disabled group detached from the real unit throughout the update;
	-- assigning the unit first can briefly repopulate a previously disabled
	-- protected container before SetEnabled(false) is processed.
	local desired_unit = get_unit_token(frame)
	local current_unit = group.container:GetUnit()
	local ok, err = true, nil
	if current_unit ~= desired_unit then
		ok, err = call_method(group.container, "SetUnit", desired_unit)
		if not ok then return false, err end
	end
	local max_count = is_buff and db.max_buffs or db.max_debuffs
	ok, err = call_method(group.container, "SetAuraGroupMaxFrameCount", OWN_GROUP_KEY, max_count)
	if not ok then return false, err end
	if type(group.container.SetAuraGroupSortMethod) == "function" then
		ok, err = call_method(group.container, "SetAuraGroupSortMethod", OWN_GROUP_KEY, get_sort_method(cfg, is_buff), get_sort_direction(cfg))
		if not ok then return false, err end
	end
	if group.otherFilterString then
		ok, err = call_method(group.container, "SetAuraGroupMaxFrameCount", OTHER_GROUP_KEY, max_count)
		if not ok then return false, err end
		if type(group.container.SetAuraGroupSortMethod) == "function" then
			ok, err = call_method(group.container, "SetAuraGroupSortMethod", OTHER_GROUP_KEY, get_sort_method(cfg, is_buff), get_sort_direction(cfg))
			if not ok then return false, err end
		end
	end
	local container_layout
	ok, err, container_layout = configure_container_layout(group.container, frame, db, cfg, is_buff)
	if not ok then
		return false, err
	end
	group.effectiveLayout = container_layout or effective_layout
	ok, err = call_method(group.container, "SetAuraGroupEnabled", OWN_GROUP_KEY, enabled and true or false)
	if not ok then return false, err end
	if group.otherFilterString then
		ok, err = call_method(group.container, "SetAuraGroupEnabled", OTHER_GROUP_KEY, enabled and true or false)
		if not ok then return false, err end
	end
	group.holder:SetShown(enabled and true or false)
	group.container:SetShown(enabled and true or false)
	group.enabled = enabled and true or false
	return true
end

function PitBull4_Aura:Lorenzo121NativeRendererAvailable()
	local state = get_native_capabilities()
	return state and state.is121OrNewer and state.auraContainerAddonLoaded and native_methods_ready(state)
end

function PitBull4_Aura:Lorenzo121NativeRendererActive()
	return native_enabled and self:Lorenzo121NativeRendererAvailable()
end

local function can_recover_frame(frame)
	return frame:IsShown() and not frame.force_show and frame.unit
		and _G.UnitExists(frame.unit) and PitBull4_Aura:GetLayoutDB(frame).enabled
end

function PitBull4_Aura:Lorenzo121CancelNativeRecovery()
	if retry_timer then
		self:CancelTimer(retry_timer)
	end
	retry_timer = nil
	retry_timer_due = nil
end

function PitBull4_Aura:Lorenzo121DisableNativeFrames()
	-- AceEvent unregisters module events on disable. Use the core's deferred
	-- queue so disabling in combat still tears down safely after regen, even
	-- though this module will no longer receive PLAYER_REGEN_ENABLED itself.
	if in_combat_lockdown() then
		PitBull4:RunOnLeaveCombat(self.Lorenzo121DisableNativeFrames, self)
		return
	end
	if not self:IsEnabled() then
		retire_all_states()
	end
end

schedule_recovery = function()
	if in_combat_lockdown() or not PitBull4_Aura:IsEnabled()
		or not PitBull4_Aura:Lorenzo121NativeRendererActive() then
		return
	end
	local due
	for frame, retry in pairs(retry_states) do
		if retry.due and can_recover_frame(frame) and (not due or retry.due < due) then
			due = retry.due
		end
	end
	if not due then
		PitBull4_Aura:Lorenzo121CancelNativeRecovery()
		return
	end
	if retry_timer and retry_timer_due <= due then return end
	PitBull4_Aura:Lorenzo121CancelNativeRecovery()
	retry_timer_due = due
	retry_timer = PitBull4_Aura:ScheduleTimer("Lorenzo121RetryNativeFrames", math_max(0.01, due - _G.GetTime()))
end

function PitBull4_Aura:Lorenzo121RetryNativeFrames()
	retry_timer = nil
	retry_timer_due = nil
	-- If combat began after scheduling, retain the budget and resume on regen.
	if in_combat_lockdown() or not self:IsEnabled() or not self:Lorenzo121NativeRendererActive() then
		return
	end
	local now = _G.GetTime()
	local frames = {}
	for frame, retry in pairs(retry_states) do
		if retry.due and retry.due <= now and can_recover_frame(frame) then
			frames[#frames + 1] = frame
		end
	end
	for _, frame in ipairs(frames) do
		self:Update(frame)
	end
	schedule_recovery()
end

function PitBull4_Aura:Lorenzo121NativeRecoveryAfterCombat()
	if in_combat_lockdown() or not self:IsEnabled() then return end
	-- Re-evaluate current visibility/layout/unit state, never replay a stale
	-- combat-time clear after the unit has already returned.
	for frame in pairs(pending_frames) do
		pending_frames[frame] = nil
		if not frame:IsShown() then
			self:ClearFrame(frame)
		end
	end
	self:UpdateAll()
	schedule_recovery()
end

function PitBull4_Aura:Lorenzo121GetNativeEnabled()
	return native_enabled
end

function PitBull4_Aura:Lorenzo121SetNativeEnabled(enabled)
	if in_combat_lockdown() then
		PitBull4:RunOnLeaveCombat(self.Lorenzo121SetNativeEnabled, self, enabled)
		return
	end
	local was_enabled = native_enabled
	native_enabled = enabled and true or false
	if native_enabled ~= was_enabled then
		reset_surface_validation()
	end
	if not native_enabled then
		self:Lorenzo121CancelNativeRecovery()
		retire_all_states()
		for frame in pairs(failed_frames) do
			failed_frames[frame] = nil
			retry_states[frame] = nil
		end
	end
	if self.Lorenzo121 then
		self.Lorenzo121.nativeRendererRequested = native_enabled
		self.Lorenzo121.legacyAuraPath = not native_enabled
	end
	self:UpdateAll()
end

function PitBull4_Aura:Lorenzo121RebuildNativeContainers()
	if in_combat_lockdown() then
		PitBull4:RunOnLeaveCombat(self.Lorenzo121RebuildNativeContainers, self)
		return
	end
	self:Lorenzo121CancelNativeRecovery()
	reset_surface_validation()
	retire_all_states()
	for frame in pairs(failed_frames) do
		failed_frames[frame] = nil
		retry_states[frame] = nil
	end
	self:UpdateAll()
end

function PitBull4_Aura:Lorenzo121HasNativeFailures()
	return next(failed_frames) ~= nil
end

function PitBull4_Aura:Lorenzo121NativeOwnsFrame(frame)
	local state = native_frames[frame]
	return state ~= nil and not frame.force_show and not failed_frames[frame]
		and state.unit == frame.unit and self:Lorenzo121NativeRendererActive()
end

function PitBull4_Aura:Lorenzo121NativeHandlesUnitAura(unit)
	local found = false
	for frame in PitBull4:IterateFrames() do
		if frame.unit == unit then
			found = true
			if not self:Lorenzo121NativeOwnsFrame(frame) then return false end
		end
	end
	return found
end

function PitBull4_Aura:Lorenzo121ShouldRunLegacyAuraTicker()
	return not self:Lorenzo121NativeRendererActive() or self:Lorenzo121HasNativeFailures()
end

local function refresh_dynamic_group(group)
	if not group or not group.enabled or not group.container then
		return false
	end
	local container = group.container
	dynamic_refresh_count = dynamic_refresh_count + 1

	-- Blizzard's managed AuraContainer marks its parse dirty through
	-- UpdateAllAuras(). In addon context this is the only combat-safe nudge.
	-- Outside combat, a Hide/Show bounce executes the intrinsic OnShow path in
	-- Blizzard's secure partition and forces an immediate re-parse of the unit.
	if _G.InCombatLockdown and _G.InCombatLockdown() then
		local method_ok, method = get_object_method(container, "UpdateAllAuras")
		if method_ok then
			local ok = pcall(method, container)
			if ok then
				dynamic_refresh_mark_count = dynamic_refresh_mark_count + 1
				return true
			end
		end
		return false
	end

	local hide_ok = pcall(container.Hide, container)
	local show_ok = pcall(container.Show, container)
	if hide_ok and show_ok then
		dynamic_refresh_bounce_count = dynamic_refresh_bounce_count + 1
		return true
	end
	return false
end

function PitBull4_Aura:Lorenzo121RefreshDynamicNativeUnit(unit)
	if not self:Lorenzo121NativeRendererActive() or type(unit) ~= "string" then
		return
	end
	for frame, state in pairs(native_frames) do
		-- frame.unit is PitBull-owned public configuration state; do not query or
		-- compare the protected identity behind the unit token.
		if frame and frame.unit == unit and state and state.groups then
			refresh_dynamic_group(state.groups.buff)
			refresh_dynamic_group(state.groups.debuff)
		end
	end
end

-- A roster refresh is limited to native containers that already exist.
-- Do not access protected aura identity or rebuild layouts during combat.
function PitBull4_Aura:Lorenzo121RefreshRosterNativeUnits()
	if not self:Lorenzo121NativeRendererActive() then return end
	for frame, state in pairs(native_frames) do
		local unit = frame and frame.unit
		if type(unit) == "string" and (unit:match("^party%d+$") or unit:match("^raid%d+$")) and state and state.groups then
			refresh_dynamic_group(state.groups.buff)
			refresh_dynamic_group(state.groups.debuff)
		end
	end
end

function PitBull4_Aura:Lorenzo121UpdateNativeFrame(frame)
	local db = self:GetLayoutDB(frame)
	local state = native_frames[frame]
	-- Forever managed containers own UNIT_AURA. Once built, do not push layout,
	-- filters or enabled state through the container during combat.
	if in_combat_lockdown() then
		pending_frames[frame] = true
		return true
	end
	pending_frames[frame] = nil
	if state then
		local buff_rebuild = group_needs_rebuild(state.groups.buff, frame, db, db.layout.buff, true)
		local debuff_rebuild = group_needs_rebuild(state.groups.debuff, frame, db, db.layout.debuff, false)
		if buff_rebuild or debuff_rebuild then
			retire_state(frame, state)
			state = nil
		end
	end
	if not state then
		local created, err = create_native_state(frame, db)
		if not created then
			return false, err
		end
		state = created
	end
	state.unit = get_unit_token(frame)
	local ok_buff, err_buff = configure_group(state.groups.buff, frame, db, true)
	local ok_debuff, err_debuff = configure_group(state.groups.debuff, frame, db, false)
	if not ok_buff or not ok_debuff then
		local err = err_buff or err_debuff or "native-config-failed"
		retire_state(frame, state)
		return false, err
	end
	clear_failure(frame)
	return true
end

function PitBull4_Aura:Lorenzo121ClearNativeFrame(frame)
	if in_combat_lockdown() then
		-- A transient missing unit is not a renderer teardown. Its secure parent
		-- owns immediate visibility; keep native groups armed for reacquisition.
		pending_frames[frame] = true
		return
	end
	pending_frames[frame] = nil
	local state = native_frames[frame]
	if not state then
		return
	end
	-- Do not suspend an enabled renderer for temporary unit absence, including
	-- just before combat starts. Native containers and the secure parent already
	-- track unit/parent visibility; retaining their groups lets them recover in
	-- combat without an insecure Show/SetAuraGroupEnabled call.
	if native_enabled and self:IsEnabled() and not frame.force_show and self:GetLayoutDB(frame).enabled then
		return
	end
	for _, group in pairs(state.groups or {}) do
		hide_group(group)
	end
end

local function safe_frame_name(frame)
	local ok, name = pcall(frame.GetName, frame)
	return ok and name or "<unnamed>"
end

function PitBull4_Aura:Lorenzo121GetNativeStatusLines()
	local frame_count, container_count, approximation_count, failure_count, weapon_count = 0, 0, 0, 0, 0
	local lines = {}
	for frame, state in pairs(native_frames) do
		frame_count = frame_count + 1
		for _, group in pairs(state.groups or {}) do
			container_count = container_count + 1
			if group.hasWeaponEnchantments then
				weapon_count = weapon_count + 1
			end
			if group.filterMode and group.filterMode:match("^approximate:") then
				approximation_count = approximation_count + 1
			end
		end
		if #lines < 12 then
			local buff_layout = state.groups.buff and state.groups.buff.effectiveLayout
			local debuff_layout = state.groups.debuff and state.groups.debuff.effectiveLayout
			local profile_layouts = self.db and self.db.profile and self.db.profile.layouts
			local active_layout_db = profile_layouts and profile_layouts[frame.layout]
			lines[#lines + 1] = "12.1 native frame=" .. safe_frame_name(frame)
				.. " unit=" .. tostring(frame.unit)
				.. " generation=" .. tostring(state.generation)
                .. " layout=" .. tostring(frame.layout)
                .. " strict=" .. tostring(active_layout_db and active_layout_db.native_strict_limit ~= false)
                .. " ownerBorders=" .. tostring(ownership_style_enabled(active_layout_db))
				.. " buffMode=" .. tostring(state.groups.buff and state.groups.buff.ownershipMode)
				.. " buffFilter=" .. tostring(state.groups.buff and state.groups.buff.filterMode)
				.. " debuffMode=" .. tostring(state.groups.debuff and state.groups.debuff.ownershipMode)
				.. " debuffFilter=" .. tostring(state.groups.debuff and state.groups.debuff.filterMode)
				.. " buffEnabled=" .. tostring(state.groups.buff and state.groups.buff.enabled)
				.. " debuffEnabled=" .. tostring(state.groups.debuff and state.groups.debuff.enabled)
				.. " mirrorH=" .. tostring(buff_layout and buff_layout.horizontalMirror or false)
				.. " mirrorV=" .. tostring(buff_layout and buff_layout.verticalMirror or false)
				.. " buffLayout=" .. tostring(buff_layout and buff_layout.point) .. "/" .. tostring(buff_layout and buff_layout.growthName)
				.. " debuffLayout=" .. tostring(debuff_layout and debuff_layout.point) .. "/" .. tostring(debuff_layout and debuff_layout.growthName)
		end
	end
	for frame, err in pairs(failed_frames) do
		failure_count = failure_count + 1
		if #lines < 16 then
			local retry = retry_states[frame]
			lines[#lines + 1] = "12.1 native failure frame=" .. safe_frame_name(frame) .. " error=" .. tostring(err)
				.. " attempts=" .. tostring(retry and retry.attempts or 0)
				.. " retry=" .. (retry and retry.due and "pending" or "exhausted")
		end
	end
	table_insert(lines, 1, "12.1 native renderer requested=" .. tostring(native_enabled)
		.. " available=" .. tostring(self:Lorenzo121NativeRendererAvailable())
		.. " runtimeSurfaceValidated=" .. tostring(native_surface_validated)
		.. " surfaceError=" .. tostring(native_surface_error)
		.. " textStyle=pitbull-capped"
		.. " borderStyle=combined-neutral-or-split-ownership"
		.. " mirrorStyle=pitbull-effective"
		.. " sortStyle=pitbull-native-aliases"
		.. " frames=" .. tostring(frame_count)
		.. " containers=" .. tostring(container_count)
		.. " weaponContainers=" .. tostring(weapon_count)
		.. " approximateFilters=" .. tostring(approximation_count)
		.. " dynamicRefresh=" .. tostring(dynamic_refresh_count)
		.. " dynamicRefreshBounce=" .. tostring(dynamic_refresh_bounce_count)
		.. " dynamicRefreshMark=" .. tostring(dynamic_refresh_mark_count)
		.. " failures=" .. tostring(failure_count))
	return lines
end

-- Replace only the Aura module's renderer entry points. Config Mode, older
-- clients, disabled native mode, and per-frame API failures use Patch 114.
local legacy_update_frame = PitBull4_Aura.UpdateFrame
local legacy_clear_frame = PitBull4_Aura.ClearFrame

-- Never run the legacy allocator/layout/pool teardown during lockdown.
-- Hide only controls explicitly reported unprotected; protected/forbidden
-- surfaces remain owned by their secure parent until post-combat reconciliation.
local function suspend_legacy(frame)
	local hidden = hidden_legacy[frame] or {}
	hidden_legacy[frame] = hidden
	local function suspend(control)
		if control and (not control.IsForbidden or not control:IsForbidden())
			and control.IsProtected and not control:IsProtected() then
			if control:IsShown() then
				control:Hide()
				hidden[control] = true
			end
		end
	end
	for _, controls in pairs({ frame.aura_buffs or {}, frame.aura_debuffs or {} }) do
		for _, control in ipairs(controls) do suspend(control) end
	end
	suspend(frame.aura_highlight)
end

local function restore_legacy(frame)
	local hidden = hidden_legacy[frame]
	if not hidden then return end
	hidden_legacy[frame] = nil
	for control in pairs(hidden) do control:Show() end
end

function PitBull4_Aura:UpdateFrame(frame, ...)
	if in_combat_lockdown() then
		pending_frames[frame] = true
		if self:Lorenzo121NativeOwnsFrame(frame) then
			local state = native_frames[frame]
			refresh_dynamic_group(state.groups.buff)
			refresh_dynamic_group(state.groups.debuff)
		else
			suspend_legacy(frame)
		end
		return
	end
	restore_legacy(frame)
	if frame and frame.force_show then
		-- Config Mode intentionally uses the legacy sample-aura renderer. Hide the
		-- persistent native containers while those samples are visible so the user
		-- never sees a second stale set underneath the preview. The same native state
		-- is reconfigured/re-enabled when config mode ends.
		self:Lorenzo121ClearNativeFrame(frame)
	end
	if should_use_native(frame) then
		local retry = retry_states[frame]
		if retry and (not retry.due or retry.due > _G.GetTime()) then
			schedule_recovery()
			return legacy_update_frame(self, frame, ...)
		end
		local called, ok, err = pcall(self.Lorenzo121UpdateNativeFrame, self, frame)
		if called and ok then
			-- Remove pooled legacy buttons once so both renderers cannot overlap.
			if self.ClearAuras then
				self:ClearAuras(frame)
			end
			if frame.aura_highlight then
				frame.aura_highlight = frame.aura_highlight:Delete()
			end
			schedule_recovery()
			return
		end
		-- Count once per attempt, including unexpected configuration exceptions.
		retire_state(frame, native_frames[frame])
		record_failure(frame, called and err or ok)
	end
	return legacy_update_frame(self, frame, ...)
end

function PitBull4_Aura:ClearFrame(frame, ...)
	self:Lorenzo121ClearNativeFrame(frame)
	if in_combat_lockdown() then
		suspend_legacy(frame)
		return
	end
	hidden_legacy[frame] = nil
	return legacy_clear_frame(self, frame, ...)
end

-- Aura.lua originally aliases OnHide to its legacy ClearFrame function. Route
-- the hook through the native boundary too, including pooled fallback cleanup.
function PitBull4_Aura:OnHide(frame, ...)
	return self:ClearFrame(frame, ...)
end

if PitBull4_Aura.Lorenzo121 then
	PitBull4_Aura.Lorenzo121.nativeRendererRequested = native_enabled
	PitBull4_Aura.Lorenzo121.managedAuraPrototype = true
	PitBull4_Aura.Lorenzo121.legacyAuraPath = false
end
