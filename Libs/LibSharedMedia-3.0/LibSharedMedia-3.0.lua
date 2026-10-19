-- Minimal embedded LibSharedMedia-3.0 compatibility library for the
-- PitBull4 Forever standalone package.
--
-- The deliberately low minor version lets a newer standalone copy of
-- LibSharedMedia-3.0 upgrade this library through LibStub without conflicts.

local MAJOR, MINOR = "LibSharedMedia-3.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
	return
end

local media_types = {
	background = true,
	border = true,
	font = true,
	sound = true,
	statusbar = true,
}

lib.MediaTable = lib.MediaTable or {
	background = {},
	border = {},
	font = {},
	sound = {},
	statusbar = {},
}
lib.MediaList = lib.MediaList or {
	background = {},
	border = {},
	font = {},
	sound = {},
	statusbar = {},
}
lib.DefaultMedia = lib.DefaultMedia or {
	background = "Blizzard Dialog Background",
	border = "Blizzard Tooltip",
	font = "Arial Narrow",
	sound = "None",
	statusbar = "Blizzard",
}
lib.GlobalMedia = lib.GlobalMedia or {}
lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)

local function assert_media_type(mediatype)
	if type(mediatype) ~= "string" or not media_types[mediatype] then
		error(("Invalid media type: %s"):format(tostring(mediatype)), 3)
	end
end

local function rebuild_list(mediatype)
	local list = lib.MediaList[mediatype]
	for i = #list, 1, -1 do
		list[i] = nil
	end
	for key in pairs(lib.MediaTable[mediatype]) do
		list[#list + 1] = key
	end
	table.sort(list)
end

function lib:Register(mediatype, key, data)
	assert_media_type(mediatype)
	if type(key) ~= "string" or key == "" then
		error("Media key must be a non-empty string", 2)
	end
	if type(data) ~= "string" then
		error("Media data must be a string", 2)
	end

	local media = self.MediaTable[mediatype]
	local is_new = media[key] == nil
	media[key] = data
	if is_new then
		rebuild_list(mediatype)
	end
	self.callbacks:Fire("LibSharedMedia_Registered", mediatype, key)
	return true
end

function lib:Fetch(mediatype, key, no_default)
	assert_media_type(mediatype)
	local media = self.MediaTable[mediatype]
	local selected = self.GlobalMedia[mediatype] or key
	local value = selected and media[selected]
	if value == nil and not no_default then
		value = media[self.DefaultMedia[mediatype]]
	end
	return value
end

function lib:IsValid(mediatype, key)
	assert_media_type(mediatype)
	return key ~= nil and self.MediaTable[mediatype][key] ~= nil
end

function lib:HashTable(mediatype)
	assert_media_type(mediatype)
	return self.MediaTable[mediatype]
end

function lib:List(mediatype)
	assert_media_type(mediatype)
	return self.MediaList[mediatype]
end

function lib:GetDefault(mediatype)
	assert_media_type(mediatype)
	return self.DefaultMedia[mediatype]
end

function lib:SetDefault(mediatype, key)
	assert_media_type(mediatype)
	if not self:IsValid(mediatype, key) then
		return false
	end
	self.DefaultMedia[mediatype] = key
	return true
end

function lib:SetGlobal(mediatype, key)
	assert_media_type(mediatype)
	if key ~= nil and not self:IsValid(mediatype, key) then
		return false
	end
	self.GlobalMedia[mediatype] = key
	self.callbacks:Fire("LibSharedMedia_SetGlobal", mediatype, key)
	return true
end

function lib:GetGlobal(mediatype)
	assert_media_type(mediatype)
	return self.GlobalMedia[mediatype]
end

lib:Register("background", "Blizzard Dialog Background", [[Interface\DialogFrame\UI-DialogBox-Background]])
lib:Register("border", "Blizzard Tooltip", [[Interface\Tooltips\UI-Tooltip-Border]])
lib:Register("font", "Arial Narrow", [[Fonts\ARIALN.TTF]])
lib:Register("font", "Friz Quadrata TT", [[Fonts\FRIZQT__.TTF]])
lib:Register("sound", "None", "")
lib:Register("statusbar", "Blizzard", [[Interface\TargetingFrame\UI-StatusBar]])
