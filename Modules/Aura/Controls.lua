
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local PitBull4_Aura = PitBull4:GetModule("Aura")

-- Table of functions included into the aura controls
local Aura = {}

-- Table of scripts set on a control
local Aura_scripts = {}

-- Calculate the path to the texture for the borders.
local border_path = [[Interface\AddOns\PitBull4\Modules\Aura\border]]

-- Get the unit the aura applies to.
function Aura:GetUnit()
	return self:GetParent().unit
end


local dispel_types = tInvert({
	-- None = 0,
	Magic = 1,
	Curse = 2,
	Disease = 3,
	Poison = 4,
	Enrage = 9,
	Bleed = 11,
})

-- Update handler for tooltips.
local function get_safe_aura_tooltip_name(control)
	local name = control.name
	if name == nil or issecretvalue(name) then
		return L["Aura"] or "Aura"
	end
	return name
end

function Aura:UpdateTooltip()
	if self.slot then
		-- Weapon Enchant
		local has_item = GameTooltip:SetInventoryItem("player", self.slot)
		if not has_item then
			GameTooltip:ClearLines()
			GameTooltip:AddLine(get_safe_aura_tooltip_name(self), 1, 0.82, 0)
			GameTooltip:AddLine(L["Sample tempoary weapon enchant created by PitBull to allow you to see the results of your configuration easily."], 1, 1, 1, 1)
			GameTooltip:Show()
		end
	elseif not self.is_config_sample then
		-- Real aura.  Do not use the cooldown-text registration state to decide
		-- whether this is a real aura: duration text can be disabled while the icon
		-- and its tooltip remain active.
		local ok = pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, self:GetUnit(), self.id)
		local has_lines = ok and GameTooltip:NumLines() > 0
		if not has_lines then
			GameTooltip:ClearLines()
			GameTooltip:AddLine(get_safe_aura_tooltip_name(self), 1, 0.82, 0)
			GameTooltip:Show()
		end
	else
		-- Config Mode Sample Aura
		GameTooltip:ClearLines()
		local dispel_text = ""
		local debuff_type = self.debuff_type
		if debuff_type ~= nil and not issecretvalue(debuff_type) then
			local dispel_key = dispel_types[debuff_type]
			if dispel_key then
				dispel_text = L[dispel_key] or ""
			end
		end
		GameTooltip:AddDoubleLine(get_safe_aura_tooltip_name(self), dispel_text, 1, 0.82, 0, 1, 0.82, 0)
		GameTooltip:AddLine(L["Sample aura created by PitBull to allow you to see the results of your configuration easily."], 1, 1, 1, 1)
		if self.is_mine then
			GameTooltip:AddLine(L["Aura shown as if cast by you."], 1, 0.82, 0, 1)
		else
			GameTooltip:AddLine(L["Aura shown as if cast by someone else."], 1, 0.82, 0, 1)
		end
		GameTooltip:Show()
	end
end

local function get_current_player_aura_index_by_instance_id(instance_id)
	if instance_id == nil or issecretvalue(instance_id) then return nil end
	if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil end

	-- Do not enumerate protected aura indexes. A failed safe check means
	-- cancellation is unavailable rather than risking the wrong buff.
	for i = 1, 255 do
		if C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret then
			local ok_secret, secret = pcall(C_Secrets.ShouldUnitAuraIndexBeSecret, "player", i, "HELPFUL")
			if not ok_secret or type(secret) ~= "boolean" or (issecretvalue and issecretvalue(secret)) or secret then break end
		end
		local ok, aura_data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or not aura_data then
			break
		end

		local aura_instance_id = aura_data.auraInstanceID
		if aura_instance_id ~= nil and not issecretvalue(aura_instance_id) and aura_instance_id == instance_id then
			return i
		end
	end
end

local function get_cancelable_player_aura_index(control)
	-- PitBull's visible aura button index can be filtered/sorted and therefore is
	-- not safe for CancelUnitBuff. Resolve the clicked auraInstanceID back to the
	-- current Blizzard HELPFUL index immediately before canceling.
	local id = control.id
	local index = get_current_player_aura_index_by_instance_id(id)
	if index then
		return index
	end

	-- If the auraInstanceID is unavailable/secret, do not fall back to the visible
	-- PitBull button index or aura name. Both can remove the wrong buff or fail on
	-- Midnight. A safe no-op is better than canceling a different aura.
end

-- Click handler to allow player buffs to be canceled with right click.
-- Blizzard still protects aura cancellation during combat for normal addon
-- buttons, so combat clicks are intentionally ignored to avoid taint errors.
local function OnClick(self, button)
	if button ~= "RightButton" or not self.is_buff then return end

	local ok, is_player = pcall(UnitIsUnit, self:GetUnit(), "player")
	if not ok or not is_player then return end
	if InCombatLockdown() then return end

	local slot = self.slot
	if slot then
		if slot == _G.INVSLOT_MAINHAND then
			pcall(CancelItemTempEnchantment, 1)
		elseif slot == _G.INVSLOT_OFFHAND then
			pcall(CancelItemTempEnchantment, 2)
		end
		return
	end

	local cancel_index = get_cancelable_player_aura_index(self)
	if cancel_index then
		local cancel_ok = pcall(CancelUnitBuff, "player", cancel_index, "HELPFUL")
		if not cancel_ok then
			pcall(CancelUnitBuff, "player", cancel_index)
		end
	end
end

function Aura_scripts:OnEnter()
	if GameTooltip:IsForbidden() then return end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT") -- self:IsAnchoringRestricted() and "ANCHOR_CURSOR" or
	self:UpdateTooltip()
end

function Aura_scripts:OnLeave()
	if GameTooltip:IsForbidden() then return end
	GameTooltip:Hide()
end

-- Control for the Auras
PitBull4.Controls.MakeNewControlType("Aura", "Button", function(control)
	-- onCreate
	control:RegisterForClicks("RightButtonUp")
	control:SetScript("OnClick", OnClick)

	local texture = PitBull4.Controls.MakeTexture(control, "BACKGROUND")
	control.texture = texture
	texture:SetAllPoints(control)

	local overlay = PitBull4.Controls.MakeFrame(control, "OVERLAY")
	control.overlay = overlay
	overlay:SetAllPoints(control)

	local border = PitBull4.Controls.MakeTexture(control, "BORDER")
	control.border = border
	border:SetAllPoints(control)
	border:SetTexture(border_path)

	local stealable = PitBull4.Controls.MakeTexture(control, "OVERLAY")
	stealable:SetTexture([[Interface\TargetingFrame\UI-TargetingFrame-Stealable]])
	stealable:SetPoint("TOPLEFT", -3, 3)
	stealable:SetPoint("BOTTOMRIGHT", 3, -3)
	stealable:SetBlendMode("ADD")
	stealable:Hide()
	control.stealable = stealable

	local count_text = PitBull4.Controls.MakeFontString(overlay, "OVERLAY")
	control.count_text = count_text
	count_text.lorenzo_aura_text_kind = "count_text"
	count_text:SetShadowColor(0, 0, 0, 1)
	count_text:SetShadowOffset(0.8, -0.8)
	count_text:SetPoint("BOTTOMRIGHT", control, "BOTTOMRIGHT", 0, 0)

	local cooldown = PitBull4.Controls.MakeCooldown(control)
	control.cooldown = cooldown
	cooldown:SetReverse(true)
	-- cooldown:SetDrawBling(false)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(true)
	-- cooldown:SetMinimumCountdownDuration(0)
	cooldown:SetAllPoints(control)

	-- Set the overlay above the cooldown spinner so the fonts will be over it.
	overlay:SetFrameLevel(cooldown:GetFrameLevel()+1)

	local cooldown_text = PitBull4.Controls.MakeFontString(overlay, "OVERLAY")
	control.cooldown_text = cooldown_text
	cooldown_text.lorenzo_aura_text_kind = "cooldown_text"
	cooldown_text:SetShadowColor(0, 0, 0, 1)
	cooldown_text:SetShadowOffset(0.8, -0.8)
	cooldown_text:SetPoint("TOP", control, "TOP", 0, 0)

	for k,v in pairs(Aura) do
		control[k] = v
	end
	for k,v in pairs(Aura_scripts) do
		control:SetScript(k, v)
	end

end, function(control)
	-- onRetrieve
	-- It's important to note that you should never ever do something
	-- here that is dependent upon the actual aura being set or even
	-- the unit of the frame it is parented to.  It is fine to do things
	-- that depend upon the frame it is parented to here.  Other than
	-- that everything should be done when the actual aura is set on
	-- the control.  This is because the controls are recyled unless
	-- the number of them changes a new control will not be retrieved.

	local group = control:GetParent().masque_group
	if group then
		group:AddButton(control, {
			Icon = control.texture,
			Cooldown = control.cooldown,
			Border = control.border,
			-- Count = control.count_text,
			-- Duration = control.cooldown_text,
		}, "Legacy")
	else
		-- reset the control layout
		local texture = control.texture
		texture:SetAllPoints(control)
		texture:SetTexCoord(0, 1, 0, 1)

		local border = control.border
		border:SetAllPoints(control)
		border:SetTexture(border_path)
		border:SetBlendMode("BLEND")

		local cooldown = control.cooldown
		cooldown:SetAllPoints(control)
		cooldown:SetFrameLevel(control:GetFrameLevel() + 1)
		control.overlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)
	end
end, function(control)
	-- onDelete
	control:SetScript("OnUpdate", nil)
	PitBull4_Aura:DisableCooldownText(control)
	if PitBull4_Aura.ClearAuraControlData then
		PitBull4_Aura:ClearAuraControlData(control)
	end

	local group = control:GetParent().masque_group
	if group then
		group:RemoveButton(control)

		-- Stop frame level tampering (Masque 8.0)
		control.__MSQ_Cooldown = nil

		-- Remove the "Blizzard" skin
		local texture = control.__MSQ_Normal or control.__MSQ_NormalTexture
		if texture then
			texture:SetTexture(nil)
		end
	end
end)
