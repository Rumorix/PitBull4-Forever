-- PitBull4 12.1 protected important-debuff display.
--
-- Blizzard's AuraContainer owns every aura read, importance decision,
-- assignment, visibility update, duration, and tooltip. PitBull only selects
-- public Blizzard classifications and supplies visual layout settings.
--
-- This module intentionally does not use spell-ID identity filters. Blizzard
-- disables those filters for harmful auras on assistable units so addons
-- cannot turn encounter mechanics into exact custom warnings. Keeping boss,
-- role, and priority debuffs in this independent module prevents those auras
-- from leaking into the player-cooldown strip.
-- Patch 030 supplies this complete AceLocale option surface in every bundled
-- WoW locale; diagnostic status strings deliberately remain stable English.

local _G = _G
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local ImportantDebuffs = PitBull4:NewModule("ImportantDebuffs")

local type = type
local tostring = tostring
local tonumber = tonumber
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local table_concat = table.concat
local table_insert = table.insert
local table_remove = table.remove
local math_floor = math.floor
local math_max = math.max
local string_format = string.format

local BORDER_TEXTURE = [[Interface\AddOns\PitBull4\Modules\Aura\border]]
local TEST_BOSS_ICON = [[Interface\Icons\Spell_Shadow_DeathScream]]
local TEST_PRIORITY_ICON = [[Interface\Icons\Ability_Creature_Poison_03]]
local BOSS_ROLE_GROUP_KEY = "pitbull-important-boss-role-debuffs"
local PRIORITY_GROUP_KEY = "pitbull-important-priority-debuffs"
local IMPORTANT_DEBUFF_FRAME_LEVEL_OFFSET = 32

local BORDER_COLORS = {
	boss_role = { 1.00, 0.15, 0.08, 1.00 },
	priority = { 0.78, 0.22, 1.00, 1.00 },
}

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

ImportantDebuffs:SetModuleType("custom")
ImportantDebuffs:SetName(L["Important debuffs"])
ImportantDebuffs:SetDescription(L["Show Blizzard-classified boss, role, and priority debuffs independently of player cooldown auras."])
ImportantDebuffs:SetDefaults({
	enabled = false,
	show_boss_role = true,
	show_priority = true,
	test_mode = false,
	icon_size = 30,
	spacing = 2,
	group_spacing = 5,
	max_boss_role = 5,
	max_priority = 5,
	position = "TOP",
	offset_x = 0,
	offset_y = 4,
	zoom = true,
	show_warning_border = true,
	show_spiral = true,
	show_duration = true,
	tooltips = true,
})

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
	local source = LAYOUTS[db.position] or LAYOUTS.TOP
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

local function get_signature(frame, db)
	local layout = get_effective_layout(frame, db)
	return table_concat({
		tostring(db.show_boss_role), tostring(db.show_priority),
		tostring(db.icon_size), tostring(db.spacing), tostring(db.group_spacing),
		tostring(db.max_boss_role), tostring(db.max_priority),
		tostring(db.position), tostring(layout.point), tostring(layout.relativePoint),
		tostring(layout.horizontal), tostring(layout.vertical),
		tostring(layout.offsetX), tostring(layout.offsetY),
		tostring(db.zoom), tostring(db.show_warning_border),
		tostring(db.show_spiral), tostring(db.show_duration), tostring(db.tooltips),
	}, ":")
end

local function in_combat_lockdown()
	return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() or false
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

local function get_font_size(icon_size)
	return math_max(8, math_floor(icon_size * 0.38 + 0.5))
end

local function set_warning_border(button, enabled)
	local overlay = button.PitBull4ImportantDebuffWarningOverlay
	local glow = button.PitBull4ImportantDebuffWarningBorder
	local animation_group = button.PitBull4ImportantDebuffWarningAnimation

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
		-- The decoration carries no aura identity. It is an addon-owned child of
		-- the protected Blizzard button and only follows that button's visibility.
		overlay = _G.CreateFrame("Frame", nil, button)
		overlay:SetAllPoints(button)
		overlay:EnableMouse(false)

		glow = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
		glow:SetPoint("TOPLEFT", overlay, "TOPLEFT", -2, 2)
		glow:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 2, -2)
		glow:SetTexture(BORDER_TEXTURE)
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(1.00, 0.18, 0.05, 1.00)
		glow:SetAlpha(1)

		if type(glow.CreateAnimationGroup) == "function" then
			animation_group = glow:CreateAnimationGroup()
			if animation_group and type(animation_group.CreateAnimation) == "function" then
				local fade_out = animation_group:CreateAnimation("Alpha")
				fade_out:SetFromAlpha(1.00)
				fade_out:SetToAlpha(0.28)
				fade_out:SetDuration(0.45)
				fade_out:SetSmoothing("IN_OUT")
				fade_out:SetOrder(1)

				local fade_in = animation_group:CreateAnimation("Alpha")
				fade_in:SetFromAlpha(0.28)
				fade_in:SetToAlpha(1.00)
				fade_in:SetDuration(0.45)
				fade_in:SetSmoothing("IN_OUT")
				fade_in:SetOrder(2)
				animation_group:SetLooping("REPEAT")
			end
		end

		button.PitBull4ImportantDebuffWarningOverlay = overlay
		button.PitBull4ImportantDebuffWarningBorder = glow
		button.PitBull4ImportantDebuffWarningAnimation = animation_group
	end

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
	set_warning_border(button, visual.showWarningBorder)

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
		button:SetHideTooltipInCombat(true)
	else
		button:EnableMouse(false)
	end
	button:SetCancelAuraButtons(nil)
end

local function group_layout(db, layout_index)
	local icon_size = tonumber(db.icon_size) or 30
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

local function add_group(container, key, max_count, candidate_filters, visual, category, db, layout_index)
	local options = {
		maxFrameCount = math_max(1, tonumber(max_count) or 1),
		initializeFrame = function(button)
			initialize_button(button, visual, category)
		end,
		sortMethod = enum_value(_G.AuraContainerSortMethod, "ImportantOnly",
			enum_value(_G.AuraContainerSortMethod, "ExpirationOnly", 0)),
		sortDirection = enum_value(_G.AuraContainerSortDirection, "Normal", 0),
		candidateFilters = candidate_filters,
		layout = group_layout(db, layout_index),
	}
	container:AddAuraGroup(key, "HARMFUL", options)
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
	local icon_size = tonumber(db.icon_size) or 30
	local count = (db.show_boss_role and (tonumber(db.max_boss_role) or 5) or 0)
		+ (db.show_priority and (tonumber(db.max_priority) or 5) or 0)
	container:SetFlowLayoutMaximumLineSize(math_max(icon_size, count * (icon_size + (tonumber(db.spacing) or 2))))
	return layout
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
	local holder = _G.CreateFrame("Frame", nil, frame)
	holder:SetPoint(layout.point, frame, layout.relativePoint, layout.offsetX, layout.offsetY)
	holder:SetSize(1, 1)
	holder:SetFrameLevel((frame:GetFrameLevel() or 1) + IMPORTANT_DEBUFF_FRAME_LEVEL_OFFSET)
	holder:Hide()

	local container = _G.CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
	container:SetPoint(layout.point, holder, layout.point, 0, 0)
	container:SetFrameLevel(holder:GetFrameLevel())
	container:Hide()

	local visual = {
		iconSize = tonumber(db.icon_size) or 30,
		frameLevel = holder:GetFrameLevel() + 1,
		zoom = db.zoom and true or false,
		showWarningBorder = db.show_warning_border and true or false,
		showSpiral = db.show_spiral and true or false,
		showDuration = db.show_duration and true or false,
		tooltips = db.tooltips and true or false,
	}
	local layout_index = 1
	if db.show_boss_role then
		add_group(
			container,
			BOSS_ROLE_GROUP_KEY,
			db.max_boss_role,
			{ isBossOrRoleAura = true },
			visual,
			"boss_role",
			db,
			layout_index
		)
		layout_index = layout_index + 1
	end
	if db.show_priority then
		-- isBossOrRoleAura=false makes the second set disjoint so an aura that
		-- carries both Blizzard flags is never displayed twice.
		add_group(
			container,
			PRIORITY_GROUP_KEY,
			db.max_priority,
			{ isPriorityAura = true, isBossOrRoleAura = false },
			visual,
			"priority",
			db,
			layout_index
		)
	end

	configure_container_layout(container, frame, db)
	local unit = get_unit_token(frame)
	container:SetUnit(unit)
	container:SetEnabled(true)
	container:Show()
	holder:Show()

	return {
		holder = holder,
		container = container,
		signature = signature,
		unit = unit,
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
	if state.holder then
		pcall(state.holder.Hide, state.holder)
	end
	state.unit = "none"
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
	state.container:SetUnit(unit)
	state.container:SetEnabled(true)
	state.container:Show()
	state.holder:Show()
	state.unit = unit
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
		set_warning_border(button, false)
		button:Hide()
	end
	state.visibleCount = 0
	state.holder:Hide()
end

local function configure_test_button(button, db, texture, category, duration_text)
	local icon_size = tonumber(db.icon_size) or 30
	button:ClearAllPoints()
	button:SetSize(icon_size, icon_size)
	button:SetFrameLevel(button:GetParent():GetFrameLevel() + 1)
	button.testIcon:SetTexture(texture)
	if db.zoom then
		button.testIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	else
		button.testIcon:SetTexCoord(0, 1, 0, 1)
	end
	local color = BORDER_COLORS[category]
	button.testBorder:SetVertexColor(color[1], color[2], color[3], color[4])
	set_warning_border(button, db.show_warning_border)

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
		button.testDuration:SetText(duration_text)
		button.testDuration:Show()
	else
		button.testDuration:Hide()
	end
	button:Show()
end

local function update_test_state(frame, db)
	local state = test_states[frame] or create_test_state(frame)
	hide_test_state(state)

	local entries = {}
	if db.show_boss_role then
		entries[#entries + 1] = { texture = TEST_BOSS_ICON, category = "boss_role", duration = get_test_duration_text(10) }
	end
	if db.show_priority then
		entries[#entries + 1] = { texture = TEST_PRIORITY_ICON, category = "priority", duration = get_test_duration_text(6) }
	end
	if #entries == 0 then
		return false
	end

	local layout = get_effective_layout(frame, db)
	state.holder:ClearAllPoints()
	state.holder:SetPoint(layout.point, frame, layout.relativePoint, layout.offsetX, layout.offsetY)
	state.holder:SetFrameLevel((frame:GetFrameLevel() or 1) + IMPORTANT_DEBUFF_FRAME_LEVEL_OFFSET)

	local previous
	local gap = tonumber(db.group_spacing) or 5
	for index, entry in ipairs(entries) do
		local button = state.buttons[index]
		configure_test_button(button, db, entry.texture, entry.category, entry.duration)
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

function ImportantDebuffs:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "UpdateAll")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "UpdateAll")
end

function ImportantDebuffs:OnDisable()
	for frame, state in pairs(active_states) do
		retire_state(frame, state)
	end
	for _, state in pairs(test_states) do
		hide_test_state(state)
	end
	active_states = setmetatable({}, { __mode = "k" })
	test_states = setmetatable({}, { __mode = "k" })
end

function ImportantDebuffs:PLAYER_ENTERING_WORLD()
	failed_frames = setmetatable({}, { __mode = "k" })
	self:UpdateAll()
end

function ImportantDebuffs:ADDON_LOADED(_, addon_name)
	if addon_name == "Blizzard_AuraContainer" then
		failed_frames = setmetatable({}, { __mode = "k" })
		self:UpdateAll()
	end
end

function ImportantDebuffs:UpdateFrame(frame)
	local db = self:GetLayoutDB(frame)
	local state = active_states[frame]
	if db.test_mode then
		if state then
			hide_state(state)
		end
		if in_combat_lockdown() then
			hide_test_state(test_states[frame])
			return false
		end
		return update_test_state(frame, db)
	end
	hide_test_state(test_states[frame])

	if not db.show_boss_role and not db.show_priority then
		return self:ClearFrame(frame)
	end

	local signature = get_signature(frame, db)
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

function ImportantDebuffs:ClearFrame(frame)
	local state = active_states[frame]
	if state then
		hide_state(state)
	end
	hide_test_state(test_states[frame])
	return false
end

function ImportantDebuffs:OnHide(frame)
	local state = active_states[frame]
	if state then
		hide_state(state)
	end
	hide_test_state(test_states[frame])
end

function ImportantDebuffs:Lorenzo121StatusLine()
	local configured = 0
	local failures = 0
	local previews = 0
	for _ in pairs(active_states) do
		configured = configured + 1
	end
	for _ in pairs(failed_frames) do
		failures = failures + 1
	end
	for _, state in pairs(test_states) do
		if state.visibleCount and state.visibleCount > 0 then
			previews = previews + 1
		end
	end
	return "12.1 importantDebuffs protected=yes configured=" .. configured .. " previews=" .. previews .. " failures=" .. failures .. " defaultEnabled=no cooldowns=separate-module harmfulOnly=yes bossRoleFilter=yes priorityFilter=yes duplicateSets=no identitySpellFilters=no friendlyDebuffLeakPrevented=yes anchors=9 center=yes topLayer=yes levelOffset=" .. IMPORTANT_DEBUFF_FRAME_LEVEL_OFFSET .. " warningBorder=optional-red-pulse testMode=static-ooc"
end

ImportantDebuffs:SetLayoutOptionsFunction(function(self)
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

	return
	'test_mode', {
		type = 'toggle',
		name = L["Static test mode (out of combat)"],
		desc = L["Replace live important debuffs with safe static preview icons. The preview reads no unit or aura data and is always hidden in combat."],
		get = get, set = set, disabled = disabled, width = 'full', order = 1,
	},
	'important_source', {
		type = 'description',
		name = "|cffffd200" .. L["Important debuffs"] .. "|r\n" .. L["This display is independent of offensive and defensive player cooldowns. Blizzard's protected boss, role, and priority flags decide which debuffs are important; PitBull does not inspect aura identities."],
		width = 'full', order = 2,
	},
	'show_boss_role', {
		type = 'toggle',
		name = L["Boss and role debuffs"],
		desc = L["Show harmful auras that Blizzard classifies as boss or role mechanics, such as encounter movement and targeting effects."],
		get = get, set = set, disabled = disabled, width = 'full', order = 3,
	},
	'show_priority', {
		type = 'toggle',
		name = L["Blizzard priority debuffs"],
		desc = L["Also show Blizzard's priority-debuff set. Effects already classified as boss or role debuffs are excluded here to prevent duplicates."],
		get = get, set = set, disabled = disabled, width = 'full', order = 4,
	},
	'position', {
		type = 'select',
		name = L["Position"],
		desc = L["Attach the important-debuff strip to the center, a side, or an outside corner. Mirrored layouts are mirrored automatically."],
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
	'max_boss_role', {
		type = 'range', name = L["Maximum boss/role icons"], min = 1, max = 20, step = 1,
		get = get, set = set, disabled = disabled, order = 16,
	},
	'max_priority', {
		type = 'range', name = L["Maximum priority icons"], min = 1, max = 20, step = 1,
		get = get, set = set, disabled = disabled, order = 17,
	},
	'zoom', {
		type = 'toggle', name = L["Zoom icons"], get = get, set = set, disabled = disabled, order = 18,
	},
	'show_warning_border', {
		type = 'toggle',
		name = L["Animated red warning border"],
		desc = L["Pulse a red warning border around important debuffs independently of the yellow player-cooldown border."],
		get = get, set = set, disabled = disabled, width = 'full', order = 19,
	},
	'show_spiral', {
		type = 'toggle', name = L["Cooldown spiral"], get = get, set = set, disabled = disabled, order = 20,
	},
	'show_duration', {
		type = 'toggle', name = L["Remaining duration text"], get = get, set = set, disabled = disabled, order = 21,
	},
	'tooltips', {
		type = 'toggle',
		name = L["Tooltips out of combat"],
		desc = L["Protected aura tooltips are disabled during combat to avoid secret tooltip taint."],
		get = get, set = set, disabled = disabled, order = 22,
	}
end)
