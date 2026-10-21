-- Dropdown items that preview LibSharedMedia media: statusbar rows show the
-- texture with its name on top, font rows show the name in that font.
-- Used through the `itemControl` field of AceConfig select options.

local PitBull4 = _G.PitBull4
local AceGUI = LibStub("AceGUI-3.0")
local LibSharedMedia = LibStub("LibSharedMedia-3.0", true)

local FONT_SIZE = 12

--- Return a select `values` table of { name = name } for a media type.
-- Labels are the media names, so preview items can Fetch the media by label.
function PitBull4.Options.GetMediaValues(kind)
	local values = {}
	if LibSharedMedia then
		for _, name in ipairs(LibSharedMedia:List(kind)) do
			values[name] = name
		end
	end
	return values
end

if not LibSharedMedia then
	return
end

-- Build on the stock checkbox item so selection, sounds and pooling behave the
-- same as every other dropdown.
local function register_item(widget_type, decorate)
	local make_toggle = AceGUI.WidgetRegistry["Dropdown-Item-Toggle"]
	AceGUI:RegisterWidgetType(widget_type, function()
		local self = make_toggle()
		self.type = widget_type -- pool under our own type, not the stock one
		decorate(self)
		return self
	end, 1)
end

register_item("PitBull4-Item-Statusbar", function(self)
	local bar = self.frame:CreateTexture(nil, "ARTWORK")
	bar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 18, -1)
	bar:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -8, 1)

	self.text:ClearAllPoints()
	self.text:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 21, 0)
	self.text:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -10, 0)

	local base_set_text = self.SetText
	function self:SetText(name)
		base_set_text(self, name)
		bar:SetTexture(LibSharedMedia:Fetch("statusbar", name))
	end

	-- ItemBase resets enabled text to white; keep it black on the texture.
	local base_set_disabled = self.SetDisabled
	function self:SetDisabled(disabled)
		base_set_disabled(self, disabled)
		if not disabled then
			self.text:SetTextColor(0, 0, 0)
		end
	end
	self.text:SetTextColor(0, 0, 0)
end)

register_item("PitBull4-Item-Font", function(self)
	local base_set_text = self.SetText
	function self:SetText(name)
		if not self.text:SetFont(LibSharedMedia:Fetch("font", name), FONT_SIZE, "") then
			self.text:SetFontObject(GameFontNormalSmall)
		end
		base_set_text(self, name)
	end
end)
