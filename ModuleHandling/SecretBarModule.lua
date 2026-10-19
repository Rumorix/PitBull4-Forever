-- This file provides the template for the bar and bar_provider modules.

local _G = _G
local PitBull4 = _G.PitBull4

local LibSharedMedia = LibStub("LibSharedMedia-3.0", true)

local expect = PitBull4.expect
local new, del = PitBull4.new, PitBull4.del
local call_color_function, call_background_color_function, call_texture_function

local HOSTILE_REACTION = 2
local NEUTRAL_REACTION = 4
local FRIENDLY_REACTION = 5

local UnitSelectionColor = _G.UnitSelectionColor
local UnitIsEnemy = _G.UnitIsEnemy
local UnitIsFriend = _G.UnitIsFriend
local UnitIsTapDenied = _G.UnitIsTapDenied
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsConnected = _G.UnitIsConnected

local PROTECTED_REACTION_OVERLAY_KEYS = {
	"hostile",
	"friendly",
	"tapped",
	"dead",
	"disconnected",
}

local function wants_identity_color(bar_db)
	return bar_db.color_by_class or bar_db.hostility_color or bar_db.hostility_color_npcs
end

-- Midnight can turn unit-reaction predicates into secret booleans during
-- combat. Lua must not branch on those values, but Region:SetAlphaFromBoolean
-- is an approved render sink. These textures therefore restore PitBull's
-- configured reaction colors without comparing, indexing, converting, or
-- caching a protected identity value.
local function hide_protected_reaction_overlays(control)
	local state = control and control._pb4_protected_reaction_overlays
	if not state then
		return
	end
	for i = 1, #PROTECTED_REACTION_OVERLAY_KEYS do
		local texture = state[PROTECTED_REACTION_OVERLAY_KEYS[i]]
		if texture then
			pcall(texture.Hide, texture)
		end
	end
	state.active = false
end

local function create_protected_reaction_texture(control, fill, sublevel)
	local ok, texture = pcall(control.CreateTexture, control, nil, "ARTWORK", nil, sublevel)
	if not ok or not texture then
		return nil
	end
	pcall(texture.SetAllPoints, texture, fill)
	pcall(texture.Hide, texture)
	return texture
end

local function ensure_protected_reaction_overlays(control)
	local fill = control and control.GetStatusBarTexture and control:GetStatusBarTexture()
	if not fill then
		return nil
	end

	local state = control._pb4_protected_reaction_overlays
	if not state then
		state = {
			hostile = create_protected_reaction_texture(control, fill, 1),
			friendly = create_protected_reaction_texture(control, fill, 2),
			tapped = create_protected_reaction_texture(control, fill, 3),
			dead = create_protected_reaction_texture(control, fill, 4),
			disconnected = create_protected_reaction_texture(control, fill, 5),
		}
		control._pb4_protected_reaction_overlays = state
		for i = 1, #PROTECTED_REACTION_OVERLAY_KEYS do
			if not state[PROTECTED_REACTION_OVERLAY_KEYS[i]] then
				hide_protected_reaction_overlays(control)
				control._pb4_protected_reaction_overlays = nil
				return nil
			end
		end
	end

	if state.fill ~= fill then
		for i = 1, #PROTECTED_REACTION_OVERLAY_KEYS do
			local texture = state[PROTECTED_REACTION_OVERLAY_KEYS[i]]
			pcall(texture.ClearAllPoints, texture)
			pcall(texture.SetAllPoints, texture, fill)
		end
		state.fill = fill
	end

	local atlas = fill.GetAtlas and fill:GetAtlas()
	local media = not atlas and fill.GetTexture and fill:GetTexture()
	for i = 1, #PROTECTED_REACTION_OVERLAY_KEYS do
		local texture = state[PROTECTED_REACTION_OVERLAY_KEYS[i]]
		if atlas and texture.SetAtlas then
			pcall(texture.SetAtlas, texture, atlas)
		else
			pcall(texture.SetTexture, texture, media)
		end
	end

	return state
end

local function set_static_texture_color(texture, color, fallback_r, fallback_g, fallback_b)
	local r, g, b = fallback_r, fallback_g, fallback_b
	if type(color) == "table" then
		r, g, b = color[1], color[2], color[3]
	end
	return pcall(texture.SetVertexColor, texture, r, g, b, 1)
end

local function set_predicate_alpha(texture, predicate, alpha_if_true, alpha_if_false)
	if not texture or type(texture.SetAlphaFromBoolean) ~= "function" then
		return false
	end
	return pcall(texture.SetAlphaFromBoolean, texture, predicate, alpha_if_true, alpha_if_false)
end

local function update_protected_reaction_overlays(self, frame, control, alpha)
	if self.id ~= "HealthBar"
		or type(UnitIsEnemy) ~= "function"
		or type(UnitIsFriend) ~= "function"
		or type(UnitIsTapDenied) ~= "function"
		or type(UnitIsDeadOrGhost) ~= "function"
		or type(UnitIsConnected) ~= "function" then
		hide_protected_reaction_overlays(control)
		return false
	end

	local state = ensure_protected_reaction_overlays(control)
	if not state then
		return false
	end

	local global_colors = self.db and self.db.profile and self.db.profile.global and self.db.profile.global.colors
	if not set_static_texture_color(state.hostile, PitBull4.ReactionColors[HOSTILE_REACTION], 1, 0, 0)
		or not set_static_texture_color(state.friendly, PitBull4.ReactionColors[FRIENDLY_REACTION], 0, 1, 0)
		or not set_static_texture_color(state.tapped, global_colors and global_colors.tapped, 0.5, 0.5, 0.5)
		or not set_static_texture_color(state.dead, global_colors and global_colors.dead, 0.6, 0.6, 0.6)
		or not set_static_texture_color(state.disconnected, global_colors and global_colors.disconnected, 0.7, 0.7, 0.7) then
		hide_protected_reaction_overlays(control)
		return false
	end

	-- The pcall success flags below are ordinary booleans. The returned unit
	-- predicates may be secret and are forwarded untouched to the render sink.
	local enemy_ok, enemy = pcall(UnitIsEnemy, "player", frame.unit)
	local friend_ok, friend = pcall(UnitIsFriend, "player", frame.unit)
	local tapped_ok, tapped = pcall(UnitIsTapDenied, frame.unit)
	local dead_ok, dead = pcall(UnitIsDeadOrGhost, frame.unit)
	local connected_ok, connected = pcall(UnitIsConnected, frame.unit)
	for i = 1, #PROTECTED_REACTION_OVERLAY_KEYS do
		pcall(state[PROTECTED_REACTION_OVERLAY_KEYS[i]].Show, state[PROTECTED_REACTION_OVERLAY_KEYS[i]])
	end
	if not enemy_ok or not friend_ok or not tapped_ok or not dead_ok or not connected_ok
		or not set_predicate_alpha(state.hostile, enemy, alpha, 0)
		or not set_predicate_alpha(state.friendly, friend, alpha, 0)
		or not set_predicate_alpha(state.tapped, tapped, alpha, 0)
		or not set_predicate_alpha(state.dead, dead, alpha, 0)
		or not set_predicate_alpha(state.disconnected, connected, 0, alpha) then
		hide_protected_reaction_overlays(control)
		return false
	end

	state.active = true
	return true
end

--
-- secret bar module implementation
--

local BarModule = PitBull4:NewModuleType("secret_bar", {
	size = 2,
	reverse = false,
	alpha = 1,
	background_alpha = 1,
	position = 1,
	side = "center",
	enabled = true,
	custom_color = nil,
	custom_background = nil,
	icon_on_left = true,
	color_by_class = false,
	color_pvp_by_class = false,
	hostility_color = false,
	hostility_color_npcs = false,
	animated = false,
}, true)

--- Handle the frame being hidden
-- @param frame the Unit Frame hidden.
-- @usage MyModule:OnHide(frame)
function BarModule:OnHide(frame)
	if PitBull4.DEBUG then
		expect(frame, 'typeof', 'frame')
	end

	local id = self.id
	local control = frame[id]
	if control then
		control:Hide()
	end
end

--- Clear the status bar for the current module if it exists.
-- @param frame the Unit Frame to clear
-- @usage local update_layout = MyModule:ClearFrame(frame)
-- @return whether the update requires :UpdateLayout to be called
function BarModule:ClearFrame(frame)
	if PitBull4.DEBUG then
		expect(frame, 'typeof', 'frame')
	end

	local id = self.id
	local control = frame[id]
	if not control then
		return false
	end

	frame[id] = control:Delete()
	return true
end

--- Update the status bar for the current module
-- @param frame the Unit Frame to update
-- @usage local update_layout = MyModule:UpdateStatusBar(frame)
-- @return whether the update requires :UpdateLayout to be called
function BarModule:UpdateFrame(frame)
	if PitBull4.DEBUG then
		expect(frame, 'typeof', 'frame')
	end

	local value, extra, icon
	if frame.unit and UnitExists(frame.unit) then
		value, extra, icon = self:GetValue(frame)
	end
	if frame.unit and not UnitExists(frame.unit) and frame.force_show and self.GetExampleValue then
		value, extra, icon = self:GetExampleValue(frame)
	end
	if not value then
		return self:ClearFrame(frame)
	end
	self.value = value

	local db = self:GetLayoutDB(frame)
	local id = self.id
	local control = frame[id]
	local made_control = not control
	if made_control then
		control = PitBull4.Controls.MakeStatusBar(frame)
		frame[id] = control
	end

	local texture, isAtlas = call_texture_function(self, frame)
	control:SetStatusBarTexture(texture)
	local r, g, b, a, protected_reaction_color = call_color_function(self, frame)
	if isAtlas then
		control:SetStatusBarColor(1, 1, 1, 1) -- a * db.alpha
		control.bg:SetAtlas(texture)
	else
		control:GetStatusBarTexture():SetVertexColor(r, g, b, a)
		control.bg:SetTexture(texture)
	end

	if protected_reaction_color and update_protected_reaction_overlays(self, frame, control, a) then
		-- Neutral is the base layer. Hostile and friendly textures sit above it
		-- and Blizzard selects their alpha without exposing the secret predicate
		-- to addon Lua. Special-state layers (tapped/dead/disconnected) win last.
		local neutral = PitBull4.ReactionColors[NEUTRAL_REACTION]
		local neutral_r, neutral_g, neutral_b = neutral[1], neutral[2], neutral[3]
		if isAtlas then
			control:SetStatusBarColor(neutral_r, neutral_g, neutral_b, a)
		else
			control:GetStatusBarTexture():SetVertexColor(neutral_r, neutral_g, neutral_b, a)
		end
	else
		hide_protected_reaction_overlays(control)
	end

	control:SetBackgroundColor(call_background_color_function(self, frame, r, g, b))

	control:SetIcon(icon)
	control:SetIconPosition(db.icon_on_left)

	-- local reverse = db.reverse
	-- if extra == Enum.StatusBarTimerDirection.RemainingTime then
	-- 	reverse = not reverse
	-- end
	-- control:SetDeficiet(reverse)

	local interpolation
	if self.allow_animations and db.animated then
		interpolation = Enum.StatusBarInterpolation.ExponentialEaseOut
	else
		interpolation = Enum.StatusBarInterpolation.Immediate
	end
	control:SetValue(value, interpolation)
	control:Show()

	return made_control
end

--- Handle a new media key being added to SharedMedia
-- @param event the event from LibSharedMedia
-- @param mediatype the type of the media being added (e.g. "font", "statusbar")
-- @param key the name of the new media
function BarModule:LibSharedMedia_Registered(event, mediatype, key)
	if mediatype == "statusbar" then
		self:UpdateAll()
	end
end


function call_color_function(self, frame)
	local unit = frame.unit
	local bar_db = self:GetLayoutDB(frame)

	local alpha = bar_db.alpha
	local custom_color = bar_db.custom_color

	if custom_color then
		return custom_color[1], custom_color[2], custom_color[3], alpha
	end

	local identity_secret = unit and PitBull4.Utils.IsUnitIdentitySecret(unit)
	if identity_secret and wants_identity_color(bar_db) and type(UnitSelectionColor) == "function" then
		-- UnitSelectionColor is safe to pass straight into a restricted render
		-- sink. Do not inspect or transform its possibly secret RGB components.
		-- This preserves a stable reaction color instead of falling through to
		-- the health-percentage curve when class/reaction identity is protected.
		local ok, selection_r, selection_g, selection_b = pcall(UnitSelectionColor, unit)
		if ok then
			-- Keep Blizzard's protected color as a fail-safe. UpdateFrame overlays
			-- it with PitBull's configured reaction colors only when every native
			-- boolean-to-alpha sink succeeds.
			return selection_r, selection_g, selection_b, alpha, self.id == "HealthBar"
		end
	end

	local r, g, b, _, override
	if frame.unit and UnitExists(unit) then
		r, g, b, _, override = self:GetColor(frame)
	end

	-- Identity-derived class and reaction overrides cannot inspect target or
	-- compound-unit identity in restricted 12.1 content. The protected path
	-- above forwards UnitSelectionColor directly; this legacy table lookup is
	-- retained only for ordinary, inspectable identities.
	if not override and unit and not identity_secret then
		if UnitIsPlayer(unit) or UnitInPartyIsAI(unit) then
			if bar_db.color_by_class and (bar_db.color_pvp_by_class or UnitIsFriend("player", unit)) then
				local _, class = PitBull4.Utils.GetSafeUnitClass(unit)
				local t = PitBull4.ClassColors[class]
				if t then
					r, g, b = t[1], t[2], t[3]
				end
			elseif bar_db.hostility_color then
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
				elseif UnitIsFriend("player", unit) then
					-- on my team
					r, g, b = unpack(PitBull4.ReactionColors[FRIENDLY_REACTION])
				else
					-- either enemy or friend, no violence
					r, g, b = unpack(PitBull4.ReactionColors.civilian)
				end
			end
		elseif bar_db.hostility_color_npcs then
			local reaction = UnitReaction(unit, "player")
			if reaction then
				if reaction > FRIENDLY_REACTION then
					r, g, b = unpack(PitBull4.ReactionColors[FRIENDLY_REACTION])
				elseif reaction > HOSTILE_REACTION then
					r, g, b = unpack(PitBull4.ReactionColors[reaction])
				else
					r, g, b = unpack(PitBull4.ReactionColors[HOSTILE_REACTION])
				end
			else
				if UnitIsFriend("player", unit) then
					r, g, b = unpack(PitBull4.ReactionColors[FRIENDLY_REACTION])
				elseif UnitIsEnemy("player", unit) then
					r, g, b = unpack(PitBull4.ReactionColors[HOSTILE_REACTION])
				end
			end
		end
	end
	if unit and not UnitExists(unit) and frame.force_show and self.GetExampleColor then
		r, g, b = self:GetExampleColor(frame)
	end
	return r, g, b, alpha
end

local function normal_to_bg_color(r, g, b, a)
	return (r + 0.2)/3, (g + 0.2)/3, (b + 0.2)/3, a
end

function call_background_color_function(self, frame, fg_r, fg_g, fg_b)
	local bar_db = self:GetLayoutDB(frame)

	local is_secret_fg_color = hasanysecretvalues(fg_r, fg_g, fg_b)
	local alpha = bar_db.background_alpha
	local custom_background = bar_db.custom_background
	local unit = frame.unit

	-- HealthBar empty space is deliberately identity-neutral. This applies both
	-- in and out of combat so a hostile red, friendly blue/green, or neutral
	-- yellow foreground never paints the missing-health region. Explicit layout
	-- background colors continue to take precedence.
	if self.id == "HealthBar" then
		-- Patch 056: An opaque empty-bar texture behind a translucent fill
		-- prevents the game world from showing through the filled area.
		-- When the background is still at its default opacity, make it
		-- transparent for translucent health fills. A deliberately configured
		-- background opacity (other than 1) remains under user control.
		if bar_db.alpha and bar_db.alpha < 1 and alpha == 1 then
			alpha = 0
		end
		if custom_background then
			return custom_background[1], custom_background[2], custom_background[3], alpha
		end
		return 0.08, 0.08, 0.08, alpha
	end

	if is_secret_fg_color and unit and PitBull4.Utils.IsUnitIdentitySecret(unit) and wants_identity_color(bar_db) then
		-- Avoid replacing the reaction-colored foreground with a second
		-- health-percentage curve. A configured background still wins; otherwise
		-- use a static dark backdrop that requires no secret-value arithmetic.
		if custom_background then
			return custom_background[1], custom_background[2], custom_background[3], alpha
		end
		return 0.08, 0.08, 0.08, alpha
	end

	local r, g, b, _, override
	if is_secret_fg_color and self.GetSecretBackgroundColor then
		r, g, b = self:GetSecretBackgroundColor(frame)
		if r then
			return r, g, b, alpha
		end
	end
	if not self.GetBackgroundColor then
		if custom_background then
			return custom_background[1], custom_background[2], custom_background[3], alpha
		end
		if not is_secret_fg_color then
			return normal_to_bg_color(fg_r, fg_g, fg_b, alpha)
		end
		return nil, nil, nil, alpha
	end
	if frame.unit and UnitExists(frame.unit) then
		r, g, b, _, override = self:GetBackgroundColor(frame)
	end
	if not override and custom_background then
		return custom_background[1], custom_background[2], custom_background[3], alpha
	end
	if (not frame.unit or not UnitExists(frame.unit)) and frame.force_show and self.GetExampleBackgroundColor then
		r, g, b = self:GetExampleBackgroundColor(frame)
	end
	if not r and not is_secret_fg_color then
		r, g, b = normal_to_bg_color(fg_r, fg_g, fg_b)
	end
	return r, g, b, alpha
end

function call_texture_function(self, frame)
	local texture, isAtlas
	if frame.unit and UnitExists(frame.unit) and self.GetTexture then
		texture, isAtlas = self:GetTexture(frame)
	end
	if not texture and LibSharedMedia then
		texture = LibSharedMedia:Fetch("statusbar", self:GetLayoutDB(frame).texture or frame.layout_db.bar_texture or "Blizzard")
		isAtlas = false
	end
	if not texture then
		texture = [[Interface\TargetingFrame\UI-StatusBar]]
		isAtlas = false
	end
	return texture, isAtlas
end
