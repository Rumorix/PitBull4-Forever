local PitBull4 = _G.PitBull4
local L = PitBull4.L

-- Midnight-safe replacement for the legacy VisualHeal overlay.
--
-- The old PitBull4 VisualHeal control is based on manual width/height math
-- (heal / maxHealth, absorb / maxHealth).  With Midnight secret values that can
-- throw forbidden arithmetic/comparison errors.  This version uses Blizzard's
-- UnitHealPredictionCalculator and passes the returned values directly into
-- StatusBar APIs instead.
--
-- Patch 011 also fixes the Patch 010 rendering mistake where every prediction
-- StatusBar covered the complete health bar from zero.  The prediction bars are
-- now anchored to the native fill textures: incoming heals begin at current
-- health, absorbs begin after incoming heals, and heal absorbs fill backwards
-- from current health.  No secret value is inspected, compared, divided, added,
-- or used as a Lua condition to obtain those positions.
--
-- Patch 013 restores full-health damage absorbs. MissingHealth is a zero-width
-- clamp at full health, so the renderer maintains two damage-absorb segments:
-- a correctly chained MissingHealth bar and a full-width MaximumHealth
-- bar. Blizzard's secret `clamped` boolean is passed straight into
-- SetAlphaFromBoolean to select one of them without addon-side inspection.
--
-- Patch 014 aligns that full-width segment with the health bar's fill origin.
-- On Lorenzo's normal player frame it therefore grows from the left; on a
-- horizontally mirrored focus frame it grows from the right. The regular
-- partial-health segment remains attached to the current-health edge.

local CreateUnitHealPredictionCalculator = _G.CreateUnitHealPredictionCalculator
local UnitGetDetailedHealPrediction = _G.UnitGetDetailedHealPrediction
local Enum = _G.Enum
local CreateFrame = _G.CreateFrame
local UnitGetTotalHealAbsorbs = _G.UnitGetTotalHealAbsorbs
local pairs = _G.pairs
local pcall = _G.pcall
local type = _G.type
local unpack = _G.unpack

local BAR_KEYS = { "incoming", "player", "absorb", "over_absorb", "heal_absorb" }

local PitBull4_VisualHeal = PitBull4:NewModule("VisualHeal")

PitBull4_VisualHeal:SetModuleType("custom")
PitBull4_VisualHeal:SetName(L["Visual heal"] or "Visual heal")
PitBull4_VisualHeal:SetDescription(L["Visualises healing done by you and your group members before it happens."] or "Shows heal prediction and absorption shields.")
PitBull4_VisualHeal:SetDefaults({
	show_overheal = true,
	show_overabsorb = true,
}, {
	incoming_color = { 0.4, 0.6, 0.4, 0.35 },
	outgoing_color = { 0, 1, 0, 0.35 },
	outgoing_color_overheal = { 1, 0, 0, 0.35 },
	absorb_color = { 1.0, 1.0, 1.0, 0.68 },
	heal_absorb_color = { 0.88, 0.05, 1.0, 0.76 },
	auto_luminance = true,
})

local calculator
local calculator_failed
local update_all_scheduled

local function get_calculator()
	if calculator or calculator_failed then
		return calculator
	end
	if not CreateUnitHealPredictionCalculator or not UnitGetDetailedHealPrediction then
		calculator_failed = true
		return nil
	end
	local ok, value = pcall(CreateUnitHealPredictionCalculator)
	if ok and value then
		calculator = value
		if calculator.SetMaximumHealthMode and Enum and Enum.UnitMaximumHealthMode then
			pcall(calculator.SetMaximumHealthMode, calculator, Enum.UnitMaximumHealthMode.Default)
		end
		if calculator.SetDamageAbsorbClampMode and Enum and Enum.UnitDamageAbsorbClampMode then
			pcall(calculator.SetDamageAbsorbClampMode, calculator, Enum.UnitDamageAbsorbClampMode.MissingHealth)
		end
		if calculator.SetHealAbsorbClampMode and Enum and Enum.UnitHealAbsorbClampMode then
			pcall(calculator.SetHealAbsorbClampMode, calculator, Enum.UnitHealAbsorbClampMode.CurrentHealth)
		end
		if calculator.SetHealAbsorbMode and Enum and Enum.UnitHealAbsorbMode then
			pcall(calculator.SetHealAbsorbMode, calculator, Enum.UnitHealAbsorbMode.ReducedByIncomingHeals)
		end
		if calculator.SetIncomingHealClampMode and Enum and Enum.UnitIncomingHealClampMode then
			pcall(calculator.SetIncomingHealClampMode, calculator, Enum.UnitIncomingHealClampMode.MissingHealth)
		end
		if calculator.SetIncomingHealOverflowPercent then
			pcall(calculator.SetIncomingHealOverflowPercent, calculator, 1.0)
		end
	else
		calculator_failed = true
	end
	return calculator
end

local function call_value(method, object, fallback, ...)
	if not object or not method then
		return fallback
	end
	local ok, value = pcall(method, object, ...)
	if ok then
		return value
	end
	return fallback
end

local function call_value_and_clamped(method, object, fallback, ...)
	if not object or not method then
		return fallback, false
	end
	local ok, value, clamped = pcall(method, object, ...)
	if ok then
		return value, clamped
	end
	return fallback, false
end

local function call_incoming_heals(method, object)
	if not object or not method then
		return 0, 0, 0
	end
	local ok, all_healing, player_healing, other_healing = pcall(method, object)
	if ok then
		return all_healing, player_healing, other_healing
	end
	return 0, 0, 0
end

local function get_health_fill(health_bar)
	return health_bar.GetStatusBarTexture and health_bar:GetStatusBarTexture()
end

local function get_statusbar_texture_path(health_bar)
	local status_texture = get_health_fill(health_bar)
	if status_texture and status_texture.GetTexture then
		local texture = status_texture:GetTexture()
		if texture then
			return texture
		end
	end
	return [[Interface\TargetingFrame\UI-StatusBar]]
end

local function anchor_after_fill(bar, health_bar, previous_fill, orientation, reverse)
	pcall(bar.ClearAllPoints, bar)
	if orientation == "VERTICAL" then
		if reverse then
			pcall(bar.SetPoint, bar, "TOPLEFT", previous_fill, "BOTTOMLEFT", 0, 0)
			pcall(bar.SetPoint, bar, "BOTTOMRIGHT", health_bar, "BOTTOMRIGHT", 0, 0)
		else
			pcall(bar.SetPoint, bar, "BOTTOMLEFT", previous_fill, "TOPLEFT", 0, 0)
			pcall(bar.SetPoint, bar, "TOPRIGHT", health_bar, "TOPRIGHT", 0, 0)
		end
	else
		if reverse then
			pcall(bar.SetPoint, bar, "TOPRIGHT", previous_fill, "TOPLEFT", 0, 0)
			pcall(bar.SetPoint, bar, "BOTTOMLEFT", health_bar, "BOTTOMLEFT", 0, 0)
		else
			pcall(bar.SetPoint, bar, "TOPLEFT", previous_fill, "TOPRIGHT", 0, 0)
			pcall(bar.SetPoint, bar, "BOTTOMRIGHT", health_bar, "BOTTOMRIGHT", 0, 0)
		end
	end
end

local function anchor_inside_current_health(bar, health_bar, health_fill, orientation, reverse)
	pcall(bar.ClearAllPoints, bar)
	if orientation == "VERTICAL" then
		if reverse then
			pcall(bar.SetPoint, bar, "TOPLEFT", health_bar, "TOPLEFT", 0, 0)
			pcall(bar.SetPoint, bar, "BOTTOMRIGHT", health_fill, "BOTTOMRIGHT", 0, 0)
		else
			pcall(bar.SetPoint, bar, "BOTTOMLEFT", health_bar, "BOTTOMLEFT", 0, 0)
			pcall(bar.SetPoint, bar, "TOPRIGHT", health_fill, "TOPRIGHT", 0, 0)
		end
	else
		if reverse then
			pcall(bar.SetPoint, bar, "TOPRIGHT", health_bar, "TOPRIGHT", 0, 0)
			pcall(bar.SetPoint, bar, "BOTTOMLEFT", health_fill, "BOTTOMLEFT", 0, 0)
		else
			pcall(bar.SetPoint, bar, "TOPLEFT", health_bar, "TOPLEFT", 0, 0)
			pcall(bar.SetPoint, bar, "BOTTOMRIGHT", health_fill, "BOTTOMRIGHT", 0, 0)
		end
	end
end

local function sync_bars_to_healthbar(bars, health_bar, show_overabsorb)
	local orientation = health_bar.GetOrientation and health_bar:GetOrientation() or "HORIZONTAL"
	local reverse = false
	if health_bar.GetReverse then
		reverse = health_bar:GetReverse()
	elseif health_bar.reverse then
		reverse = true
	end
	local texture = get_statusbar_texture_path(health_bar)
	local health_fill = get_health_fill(health_bar)
	local frame_level = health_bar.GetFrameLevel and health_bar:GetFrameLevel()
	if not health_fill then
		return false
	end
	if bars._health_bar == health_bar and bars._health_fill == health_fill and bars._orientation == orientation and bars._reverse == reverse and bars._texture == texture and bars._frame_level == frame_level and bars._show_overabsorb == show_overabsorb then
		return
	end
	for i = 1, #BAR_KEYS do
		local key = BAR_KEYS[i]
		local bar = bars[key]
		if bar then
			if bar.SetOrientation then
				pcall(bar.SetOrientation, bar, orientation)
			end
			if bar.SetReverseFill then
				local bar_reverse = reverse
				-- Healing absorbs consume current health backwards. The full-health
				-- damage-absorb segment deliberately follows the HealthBar origin so
				-- mirrored frames remain mirrored instead of swapping sides twice.
				if key == "heal_absorb" or key == "over_absorb" then
					-- Forever 030: the full-health damage-absorb fallback starts at
					-- the max-health edge, matching the previously live-confirmed
					-- shield orientation instead of jumping to the left side.
					bar_reverse = not reverse
				end
				pcall(bar.SetReverseFill, bar, bar_reverse)
			end
			pcall(bar.SetStatusBarTexture, bar, texture)
			if frame_level and bar.SetFrameLevel then
				pcall(bar.SetFrameLevel, bar, frame_level + i)
			end
		end
	end

	-- Incoming and player heals share the same region.  The player bar is drawn
	-- above the total bar, leaving the remaining portion in the incoming color.
	anchor_after_fill(bars.incoming, health_bar, health_fill, orientation, reverse)
	anchor_after_fill(bars.player, health_bar, health_fill, orientation, reverse)

	-- The regular absorb segment occupies only the remaining health region.
	local incoming_fill = bars.incoming.GetStatusBarTexture and bars.incoming:GetStatusBarTexture()
	if incoming_fill then
		anchor_after_fill(bars.absorb, health_bar, incoming_fill, orientation, reverse)
	else
		anchor_after_fill(bars.absorb, health_bar, health_fill, orientation, reverse)
	end

	-- The alternate segment can represent a shield even when the regular
	-- MissingHealth region has zero width. Its alpha is selected later from the
	-- calculator's secret clamped flag.
	pcall(bars.over_absorb.ClearAllPoints, bars.over_absorb)
	pcall(bars.over_absorb.SetAllPoints, bars.over_absorb, health_bar)

	-- Healing absorbs consume the end of current health, so this bar uses the
	-- current-health region and the opposite fill direction.
	anchor_inside_current_health(bars.heal_absorb, health_bar, health_fill, orientation, reverse)

	bars._health_bar = health_bar
	bars._health_fill = health_fill
	bars._orientation = orientation
	bars._reverse = reverse
	bars._texture = texture
	bars._frame_level = frame_level
	bars._show_overabsorb = show_overabsorb
	bars._layout_mode = show_overabsorb and "clamped-switch-statusbars" or "chained-native-statusbars"
	return true
end

local function apply_bar_color(bar, color)
	if not bar or type(color) ~= "table" then return end
	local r, g, b, a = color[1], color[2], color[3], color[4]
	if bar._pb4_vh_r == r and bar._pb4_vh_g == g and bar._pb4_vh_b == b and bar._pb4_vh_a == a then
		return
	end
	if pcall(bar.SetStatusBarColor, bar, r, g, b, a) then
		bar._pb4_vh_r, bar._pb4_vh_g, bar._pb4_vh_b, bar._pb4_vh_a = r, g, b, a
	end
end

local function make_prediction_bar(parent, r, g, b, a, level_offset)
	local ok, bar = pcall(CreateFrame, "StatusBar", nil, parent)
	if not ok or not bar then
		return nil
	end
	pcall(bar.EnableMouse, bar, false)
	pcall(bar.SetMinMaxValues, bar, 0, 1)
	pcall(bar.SetValue, bar, 0)
	pcall(bar.SetStatusBarColor, bar, r, g, b, a)
	if parent.GetFrameLevel and bar.SetFrameLevel then
		pcall(bar.SetFrameLevel, bar, parent:GetFrameLevel() + (level_offset or 1))
	end
	pcall(bar.Hide, bar)
	return bar
end

local function ensure_bars(frame, health_bar, show_overabsorb)
	local bars = frame.VisualHealMidnight
	local db = PitBull4_VisualHeal.db.profile.global
	if bars and bars._health_bar and bars._health_bar ~= health_bar then
		-- Layout changes can replace PitBull's HealthBar control. Prediction bars
		-- are children of that control, so retire the old set and create a new one
		-- under the replacement instead of cross-parent anchoring hidden frames.
		for i = 1, #BAR_KEYS do
			local old_bar = bars[BAR_KEYS[i]]
			if old_bar and old_bar.Hide then
				pcall(old_bar.Hide, old_bar)
			end
		end
		bars = nil
		frame.VisualHealMidnight = nil
	end
	if not bars then
		bars = {}
		local r, g, b, a = unpack(db.incoming_color)
		bars.incoming = make_prediction_bar(health_bar, r, g, b, a, 1)
		r, g, b, a = unpack(db.outgoing_color)
		bars.player = make_prediction_bar(health_bar, r, g, b, a, 2)
		r, g, b, a = unpack(db.absorb_color)
		bars.absorb = make_prediction_bar(health_bar, r, g, b, a, 3)
		bars.over_absorb = make_prediction_bar(health_bar, r, g, b, a, 4)
		r, g, b, a = unpack(db.heal_absorb_color)
		bars.heal_absorb = make_prediction_bar(health_bar, r, g, b, a, 5)
		if not bars.incoming or not bars.player or not bars.absorb or not bars.over_absorb or not bars.heal_absorb then
			for _, bar in pairs(bars) do
				if bar and bar.Hide then
					pcall(bar.Hide, bar)
				end
			end
			return nil
		end
		frame.VisualHealMidnight = bars
	else
		if not bars.over_absorb then
			local r, g, b, a = unpack(db.absorb_color)
			bars.over_absorb = make_prediction_bar(health_bar, r, g, b, a, 4)
			if not bars.over_absorb then
				return nil
			end
		end
		if not bars.heal_absorb then
			local r, g, b, a = unpack(db.heal_absorb_color)
			bars.heal_absorb = make_prediction_bar(health_bar, r, g, b, a, 5)
			if not bars.heal_absorb then
				return nil
			end
		end
	end

	sync_bars_to_healthbar(bars, health_bar, show_overabsorb)
	return bars
end

local function hide_bars(frame)
	local bars = frame.VisualHealMidnight
	if not bars then
		return
	end
	for i = 1, #BAR_KEYS do
		local bar = bars[BAR_KEYS[i]]
		if bar and bar.Hide then
			pcall(bar.Hide, bar)
		end
	end
end

local function set_bar_value(bar, max_value, value)
	if not bar then return end
	local interpolation = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
	local ok
	if interpolation then
		ok = pcall(bar.SetMinMaxValues, bar, 0, max_value, interpolation)
	else
		ok = pcall(bar.SetMinMaxValues, bar, 0, max_value)
	end
	if not ok then
		pcall(bar.Hide, bar)
		return
	end
	if interpolation then
		ok = pcall(bar.SetValue, bar, value, interpolation)
	else
		ok = pcall(bar.SetValue, bar, value)
	end
	if ok then
		pcall(bar.Show, bar)
	else
		pcall(bar.Hide, bar)
	end
end

local function set_alpha_from_boolean(bar, value, alpha_if_true, alpha_if_false)
	if not bar or type(bar.SetAlphaFromBoolean) ~= "function" then
		return false
	end
	return pcall(bar.SetAlphaFromBoolean, bar, value, alpha_if_true, alpha_if_false)
end

local function update_calculator(unit)
	local calc = get_calculator()
	if not calc then
		return nil
	end
	if calc.SetDamageAbsorbClampMode and Enum and Enum.UnitDamageAbsorbClampMode then
		pcall(calc.SetDamageAbsorbClampMode, calc, Enum.UnitDamageAbsorbClampMode.MissingHealth)
	end
	-- Reusing one calculator is fine, but reset it before switching units so
	-- party/raid frames do not inherit stale player/target data.
	if calc.ResetPredictedValues then
		pcall(calc.ResetPredictedValues, calc)
	end

	-- The calculator always includes all incoming heals and absorbs.  "player"
	-- only identifies which portion belongs in PitBull's outgoing-heal color.
	local ok = pcall(UnitGetDetailedHealPrediction, unit, "player", calc)
	if not ok then
		return nil
	end
	return calc
end

local function queue_update_all(self)
	if update_all_scheduled then
		return
	end
	update_all_scheduled = true
	if self.ScheduleTimer then
		self:ScheduleTimer(function()
			update_all_scheduled = nil
			self:UpdateAll()
		end, 0.05)
	else
		update_all_scheduled = nil
		self:UpdateAll()
	end
end

local function colors_match(color, r, g, b, a)
	return type(color) == "table" and color[1] == r and color[2] == g and color[3] == b and color[4] == a
end

local function apply_visualheal_defaults_if_needed(db)
	if not db then return end
	if db.absorb_color == nil or colors_match(db.absorb_color, .55, .35, .85, 0.55) or colors_match(db.absorb_color, 0.98, 0.98, 1.0, 0.42) then
		db.absorb_color = { 1.0, 1.0, 1.0, 0.68 }
	end
	if db.heal_absorb_color == nil or colors_match(db.heal_absorb_color, 0.70, 0.20, 1.0, 0.58) then
		db.heal_absorb_color = { 0.88, 0.05, 1.0, 0.76 }
	end
end

local function get_heal_absorbs(calc, unit)
	-- Blizzard iterated the Midnight prediction calculator API during testing,
	-- so accept several likely method names and fall back to the legacy unit API.
	-- The returned value may be secret; do not compare or do arithmetic on it.
	if calc and calc.GetHealAbsorbs then
		return call_value(calc.GetHealAbsorbs, calc, 0)
	end
	if calc and calc.GetHealingAbsorbs then
		return call_value(calc.GetHealingAbsorbs, calc, 0)
	end
	if calc and calc.GetTotalHealAbsorbs then
		return call_value(calc.GetTotalHealAbsorbs, calc, 0)
	end
	if UnitGetTotalHealAbsorbs then
		local ok, total = pcall(UnitGetTotalHealAbsorbs, unit)
		if ok then return total end
	end
	return 0
end

function PitBull4_VisualHeal:OnEnable()
	apply_visualheal_defaults_if_needed(self.db and self.db.profile and self.db.profile.global)
	self:RegisterEvent("UNIT_HEAL_PREDICTION")
	self:RegisterEvent("UNIT_HEALTH", "UNIT_HEAL_PREDICTION")
	self:RegisterEvent("UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION")
	self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
	self:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_ABSORB_AMOUNT_CHANGED")
end

function PitBull4_VisualHeal:UpdateFrame(frame)
	local unit = frame.unit
	local health_bar = frame.HealthBar
	if not unit or not health_bar then
		hide_bars(frame)
		return false
	end

	local layout_db = self:GetLayoutDB(frame)
	local show_overabsorb = not layout_db or layout_db.show_overabsorb ~= false
	local calc = update_calculator(unit)
	if not calc then
		hide_bars(frame)
		return false
	end

	local maximum_incoming = call_value(calc.GetMaximumIncomingHeals, calc, 1)
	local maximum_absorbs = call_value(calc.GetMaximumDamageAbsorbs, calc, 1)
	local maximum_heal_absorbs = call_value(calc.GetMaximumHealAbsorbs, calc, 1)
	local all_healing, player_healing = call_incoming_heals(calc.GetIncomingHeals, calc)
	local damage_absorbs, damage_absorbs_clamped = call_value_and_clamped(calc.GetDamageAbsorbs, calc, 0)
	local maximum_over_absorbs = maximum_absorbs
	local over_absorbs = damage_absorbs
	if show_overabsorb and calc.SetDamageAbsorbClampMode and Enum and Enum.UnitDamageAbsorbClampMode then
		-- The predicted values stay on the calculator while only the public clamp
		-- mode changes. This yields a full-health maximum for the alternate bar.
		pcall(calc.SetDamageAbsorbClampMode, calc, Enum.UnitDamageAbsorbClampMode.MaximumHealth)
		maximum_over_absorbs = call_value(calc.GetMaximumDamageAbsorbs, calc, 1)
		over_absorbs = call_value(calc.GetDamageAbsorbs, calc, 0)
	end
	local heal_absorbs = get_heal_absorbs(calc, unit)
	local bars = ensure_bars(frame, health_bar, show_overabsorb)
	if not bars then
		return false
	end

	local db = self.db.profile.global
	apply_bar_color(bars.incoming, db.incoming_color)
	apply_bar_color(bars.player, db.outgoing_color)
	apply_bar_color(bars.absorb, db.absorb_color)
	apply_bar_color(bars.over_absorb, db.absorb_color)
	apply_bar_color(bars.heal_absorb, db.heal_absorb_color)

	-- Do not compare, add, divide, or boolean-test these values. In Midnight they
	-- can be secret. The calculator supplies a native maximum for each relative
	-- region, and StatusBar performs the fill calculation internally.
	set_bar_value(bars.incoming, maximum_incoming, all_healing)
	set_bar_value(bars.player, maximum_incoming, player_healing)
	set_bar_value(bars.absorb, maximum_absorbs, damage_absorbs)
	set_bar_value(bars.over_absorb, maximum_over_absorbs, over_absorbs)
	set_bar_value(bars.heal_absorb, maximum_heal_absorbs, heal_absorbs)

	if show_overabsorb then
		-- `damage_absorbs_clamped` may be a secret boolean. It is never tested by
		-- Lua; Blizzard maps it directly to each bar's alpha. Exactly one damage
		-- absorb representation is therefore visible.
		local regular_ok = set_alpha_from_boolean(bars.absorb, damage_absorbs_clamped, 0, 1)
		local over_ok = set_alpha_from_boolean(bars.over_absorb, damage_absorbs_clamped, 1, 0)
		if not regular_ok or not over_ok then
			pcall(bars.absorb.SetAlpha, bars.absorb, 1)
			pcall(bars.over_absorb.SetAlpha, bars.over_absorb, 0)
		end
	else
		pcall(bars.absorb.SetAlpha, bars.absorb, 1)
		pcall(bars.over_absorb.SetAlpha, bars.over_absorb, 0)
	end

	return false
end

function PitBull4_VisualHeal:UNIT_HEAL_PREDICTION(_, unit)
	if not unit then
		return
	end
	self:UpdateForUnitID(unit)
end

function PitBull4_VisualHeal:UNIT_ABSORB_AMOUNT_CHANGED(_, unit)
	if unit then
		self:UpdateForUnitID(unit)
	end
	-- Party/raid absorb events are not always enough to hit the exact PitBull4
	-- SecureGroupHeader unit token.  A throttled full refresh is cheap for M+ and
	-- makes absorbs appear on member frames as well as singleton frames.
	queue_update_all(self)
end

function PitBull4_VisualHeal:ClearFrame(frame)
	hide_bars(frame)
	return false
end

PitBull4_VisualHeal.OnHide = PitBull4_VisualHeal.ClearFrame

function PitBull4_VisualHeal:Lorenzo121StatusLine()
	return "12.1 visualHeal renderer=secret-safe-segments calculator=" .. (get_calculator() and "yes" or "no") .. " damageAbsorb=missing+maximum-health clampedSwitch=SetAlphaFromBoolean overAbsorbOrigin=healthbar mirrorAware=yes"
end

PitBull4_VisualHeal:SetColorOptionsFunction(function(self)
	local function get(info)
		return unpack(self.db.profile.global[info[#info]])
	end
	local function set(info, r, g, b, a)
		local color = self.db.profile.global[info[#info]]
		color[1], color[2], color[3], color[4] = r, g, b, a
		self:UpdateAll()
	end
	return 'incoming_color', {
		type = 'color',
		name = L["Incoming color"] or "Incoming color",
		desc = L["The color of the bar that shows incoming heals from other players."] or "Incoming heal overlay color.",
		get = get,
		set = set,
		hasAlpha = true,
		width = 'double',
	}, 'outgoing_color', {
		type = 'color',
		name = L["Outgoing color (no overheal)"] or "Outgoing color",
		desc = L["The color of the bar that shows your own heals, when no overhealing is due."] or "Your incoming heal overlay color.",
		get = get,
		set = set,
		hasAlpha = true,
		width = 'double',
	}, 'absorb_color', {
		type = 'color',
		name = L["Absorb color"] or "Absorb color",
		desc = L["The color of the bar that shows absorption shields."] or "Absorption shield overlay color.",
		get = get,
		set = set,
		hasAlpha = true,
		width = 'double',
	}, 'heal_absorb_color', {
		type = 'color',
		name = L["Heal absorb color"] or "Heal absorb color",
		desc = L["The color of the bar that shows healing absorbs."] or "Healing absorb overlay color.",
		get = get,
		set = set,
		hasAlpha = true,
		width = 'double',
	}, function(info)
		self.db.profile.global.incoming_color = { 0.4, 0.6, 0.4, 0.35 }
		self.db.profile.global.outgoing_color = { 0, 1, 0, 0.35 }
		self.db.profile.global.outgoing_color_overheal = { 1, 0, 0, 0.35 }
		self.db.profile.global.absorb_color = { 0.98, 0.98, 1.0, 0.42 }
		self.db.profile.global.heal_absorb_color = { 0.70, 0.20, 1.0, 0.58 }
		self.db.profile.global.auto_luminance = true
		self:UpdateAll()
	end
end)


PitBull4_VisualHeal:SetLayoutOptionsFunction(function(self)
	local function disabled(info)
		return not PitBull4.Options.GetLayoutDB(self).enabled
	end

	return 'show_overheal', {
		type = 'toggle',
		name = L["Show overheals"] or "Show overheals",
		desc = L["Show overheals past the end of the health bar."] or "Show overheals past the end of the health bar.",
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).show_overheal
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).show_overheal = value
			self:UpdateAll()
		end,
		disabled = disabled,
	}, 'show_overabsorb', {
		type = 'toggle',
		name = L["Show overabsorb"] or "Show overabsorb",
		desc = "When a shield no longer fits in missing health, switch to a full-width absorb segment aligned with the health bar's origin. This also keeps absorbs visible at full health.",
		get = function(info)
			return PitBull4.Options.GetLayoutDB(self).show_overabsorb
		end,
		set = function(info, value)
			PitBull4.Options.GetLayoutDB(self).show_overabsorb = value
			self:UpdateAll()
		end,
		disabled = disabled,
	}
end)
