
local PitBull4 = _G.PitBull4
local IsSecretValue = PitBull4.Utils.IsSecretValue

local function is_public_number(value)
	return not IsSecretValue(value) and type(value) == "number"
		and value == value and value ~= math.huge and value ~= -math.huge
end

-- The native ShardTemplate can be unavailable on the active client. Inspect the
-- template registry instead of probing CreateFrame, which logs an inherited-node
-- error even when an addon tries to catch the failed creation.
local inherit_template
local xml_util = _G.C_XMLUtil
local native_mixin = _G.WarlockShardMixin
if xml_util and type(xml_util.GetTemplateInfo) == "function"
	and native_mixin and type(native_mixin.Update) == "function" then
	local ok, info = pcall(xml_util.GetTemplateInfo, "ShardTemplate")
	if ok and type(info) == "table" and info.type == "Frame" then
		inherit_template = "ShardTemplate"
	end
end

local SHARD_TEXTURE = [[Interface\AddOns\PitBull4\Modules\SoulShards\Shard]]

-----------------------------------------------------------------------------

local SoulShard = {}
local SoulShard_scripts = {}

SoulShard.widthByFillAmount = {
	[0] = 0,
	[1] = 6,
	[2] = 12,
	[3] = 14,
	[4] = 18,
	[5] = 22,
	[6] = 22,
	[7] = 24,
	[8] = 20,
	[9] = 18,
	[10] = 0,
}

function SoulShard:UpdateFallbackVisual()
	local fill = self.pb4_shard_fill
	local fraction = self.fillAmount or 0
	local height = self:GetHeight()
	if not is_public_number(height) or height <= 0 or fraction <= 0 then
		fill:Hide()
		self.pb4_shard_height = nil
		return
	end
	if self.pb4_shard_height == height and self.pb4_shard_fraction == fraction then return end
	self.pb4_shard_height, self.pb4_shard_fraction = height, fraction
	fill:SetHeight(height * fraction)
	fill:SetTexCoord(0, 1, 1 - fraction, 1)
	fill:Show()
end

function SoulShard:UpdateFallback(power_amount)
	local fraction = 0
	if is_public_number(power_amount) and self.layoutIndex then
		fraction = math.min(1, math.max(0, power_amount - (self.layoutIndex - 1)))
		-- Match the native tenth-shard display, including floating-point edges.
		fraction = math.floor((fraction + 0.000001) * 10) / 10
	end
	self.fillAmount = fraction
	self:UpdateFallbackVisual()
end

function SoulShard_scripts:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(_G.SOUL_SHARDS_POWER)
	GameTooltip:AddLine(_G.SOUL_SHARDS_TOOLTIP, nil, nil, nil, true)
	GameTooltip:Show()
end

function SoulShard_scripts:OnLeave()
	GameTooltip:Hide()
end

PitBull4.Controls.MakeNewControlType("SoulShard", "Frame", function(control)
	-- onCreate
	for k, v in pairs(SoulShard) do
		control[k] = v
	end
	for k, v in pairs(SoulShard_scripts) do
		control:SetScript(k, v)
	end
	if not inherit_template then
		-- Use the existing packaged shard art, independent of native XML/atlases.
		local background = control:CreateTexture(nil, "BACKGROUND")
		background:SetTexture(SHARD_TEXTURE)
		background:SetAllPoints(control)
		background:SetVertexColor(0.22, 0.18, 0.24, 0.7)
		local fill = control:CreateTexture(nil, "ARTWORK")
		fill:SetTexture(SHARD_TEXTURE)
		fill:SetPoint("BOTTOMLEFT", control, "BOTTOMLEFT")
		fill:SetPoint("BOTTOMRIGHT", control, "BOTTOMRIGHT")
		fill:Hide()
		control.pb4_shard_fill = fill
		control.Update = SoulShard.UpdateFallback
		control:SetScript("OnSizeChanged", SoulShard.UpdateFallbackVisual)
	end

end, function(control, id)
	-- onRetrieve
	control.layoutIndex = id
	if control.pb4_shard_fill then
		control:Update(0)
	end

end, function(control)
	-- onDelete
	control:Update(0)
	control.layoutIndex = nil
	control.pb4_shard_height, control.pb4_shard_fraction = nil, nil

end, inherit_template)
