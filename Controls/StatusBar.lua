local StatusBar = {}


function StatusBar:SetIcon(value)
	-- if self.icon_path == value then
	-- 	return
	-- end

	self.icon_path = value
	-- if value then
	-- 	if not self.icon then
	-- 		self.icon = PitBull4.Controls.MakeTexture(self, "ARTWORK")
	-- 		self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	-- 		-- fix_orientation(self)
	-- 	end
	-- 	self.icon:SetTexture(value)
	-- else
	-- 	if self.icon then
	-- 		self.icon = self.icon:Delete()
	-- 		-- fix_orientation(self)
	-- 	end
	-- end
end
function StatusBar:GetIcon()
	return self.icon_path
end

function StatusBar:SetIconPosition(value)
	if value == self.icon_position then
		return
	end

	self.icon_position = value
	-- fix_orientation(self)
end
function StatusBar:GetIconPosition()
	return self.icon_position
end

function StatusBar:SetReverse(isReverseFill)
	if self.reverse == isReverseFill then
		return
	end

	self.reverse = isReverseFill
	self:SetReverseFill(isReverseFill)
	-- self:SetValue(self.value)
end
function StatusBar:GetReverse()
	return self:GetReverseFill()
end

function StatusBar:SetDeficit(deficit)
	if self.deficit == deficit then
		return
	end

	self.deficit = deficit
	-- self:SetValue(self.value)
end
function StatusBar:GetDeficit()
	return self.deficit
end

function StatusBar:SetBackgroundColor(r, g, b, a)
	self.bg:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
end
function StatusBar:GetBackgroundColor()
	return self.bg:GetVertexColor()
end

-- The value may be secret, so Lua can't size the background itself. Anchor it
-- to the native fill texture's leading edge instead: the client resizes the
-- fill, and the background covers only the remaining (empty) part.
local function anchor_bg(control)
	local bg = control.bg
	local fill = control:GetStatusBarTexture()
	bg:ClearAllPoints()
	if not fill then
		bg:SetAllPoints(control)
		return
	end
	local vertical = control:GetOrientation() == "VERTICAL"
	local reverse = control:GetReverseFill()
	if vertical and not reverse then -- fills from the bottom
		bg:SetPoint("TOPLEFT", control, "TOPLEFT")
		bg:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT")
	elseif vertical then -- fills from the top
		bg:SetPoint("TOPLEFT", fill, "BOTTOMLEFT")
		bg:SetPoint("BOTTOMRIGHT", control, "BOTTOMRIGHT")
	elseif reverse then -- fills from the right
		bg:SetPoint("TOPLEFT", control, "TOPLEFT")
		bg:SetPoint("BOTTOMRIGHT", fill, "BOTTOMLEFT")
	else -- fills from the left
		bg:SetPoint("TOPLEFT", fill, "TOPRIGHT")
		bg:SetPoint("BOTTOMRIGHT", control, "BOTTOMRIGHT")
	end
end

local StatusBar_scripts = {}

function StatusBar:OnSizeChanged()
	self:SetValue(self.value)
end


PitBull4.Controls.MakeNewControlType("StatusBar", "StatusBar", function(control)
	-- onCreate
	control:EnableMouse(false)
	control:SetMinMaxValues(0, 1)

	local control_bg = PitBull4.Controls.MakeTexture(control, "BACKGROUND")
	control.bg = control_bg

	for k,v in pairs(StatusBar) do
		control[k] = v
	end
	for k,v in pairs(StatusBar_scripts) do
		control:SetScript(k, v)
	end

	anchor_bg(control)
	hooksecurefunc(control, "SetStatusBarTexture", anchor_bg)
	hooksecurefunc(control, "SetOrientation", anchor_bg)
	hooksecurefunc(control, "SetReverseFill", anchor_bg)
end, function(control)
	-- onRetrieve
end, function(control)
	-- onDelete
end)
