-- Patch 080-083: pre-AceDB full-profile safety restore bootstrap.
--
-- This file is loaded before Main.lua creates the AceDB database.  A full
-- safety restore is therefore applied directly to the raw SavedVariables while
-- no PitBull/AceDB profile references exist yet.  This avoids live profile
-- aliases reintroducing post-backup settings during ReloadUI.

local store = _G.PitBull4SafetyBackups
local sv = _G.PitBull4DB

if type(store) ~= "table" or type(store.pending_restore) ~= "table" then
	return
end

local request = store.pending_restore
store.pending_restore = nil

local profile_name = request.profile_name
local snapshot = type(store.profiles) == "table" and profile_name and store.profiles[profile_name] or nil

local function plain_copy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local copy = {}
	seen[value] = copy
	for k, v in pairs(value) do
		copy[plain_copy(k, seen)] = plain_copy(v, seen)
	end
	return copy
end

local function finish(status, message, namespace_count)
	store.last_restore_result = {
		status = status,
		message = message,
		profile_name = profile_name,
		namespace_count = namespace_count or 0,
		completed_at = _G.date and _G.date("%Y-%m-%d %H:%M:%S") or "",
	}
end

if type(profile_name) ~= "string" or profile_name == "" then
	finish("failed", "missing profile name")
	return
end
if type(snapshot) ~= "table" or type(snapshot.profile) ~= "table" then
	finish("failed", "snapshot missing or invalid")
	return
end
if type(sv) ~= "table" then
	finish("failed", "PitBull4DB missing")
	return
end

sv.profiles = type(sv.profiles) == "table" and sv.profiles or {}
sv.profiles[profile_name] = plain_copy(snapshot.profile)

-- Patch 083: positions are also stored as an independent reference inside the
-- full snapshot. Apply that reference explicitly after restoring the profile so
-- unit/group anchors cannot remain at post-backup Edit Mode positions even if
-- an older AceDB/raw-SavedVariables alias did not contain the latest geometry.
local restored_profile = sv.profiles[profile_name]
local position_reference = snapshot.position_reference
if type(restored_profile) == "table" and type(position_reference) == "table" then
	local fields = { "anchor", "relative_to", "relative_point", "position_x", "position_y" }
	for name, saved in pairs(position_reference.units or {}) do
		local unit_db = restored_profile.units and restored_profile.units[name]
		if type(unit_db) == "table" and type(saved) == "table" then
			for i = 1, #fields do unit_db[fields[i]] = saved[fields[i]] end
		end
	end
	for name, saved in pairs(position_reference.groups or {}) do
		local group_db = restored_profile.groups and restored_profile.groups[name]
		if type(group_db) == "table" and type(saved) == "table" then
			for i = 1, #fields do group_db[fields[i]] = saved[fields[i]] end
		end
	end
end

sv.namespaces = type(sv.namespaces) == "table" and sv.namespaces or {}

-- Make the restored profile exact: remove this profile from every namespace,
-- then put back only the namespace profile data that existed in the snapshot.
for _, namespace_sv in pairs(sv.namespaces) do
	if type(namespace_sv) == "table" and type(namespace_sv.profiles) == "table" then
		namespace_sv.profiles[profile_name] = nil
	end
end

local namespace_count = 0
for namespace_name, namespace_profile in pairs(snapshot.namespaces or {}) do
	local namespace_sv = sv.namespaces[namespace_name]
	if type(namespace_sv) ~= "table" then
		namespace_sv = {}
		sv.namespaces[namespace_name] = namespace_sv
	end
	namespace_sv.profiles = type(namespace_sv.profiles) == "table" and namespace_sv.profiles or {}
	namespace_sv.profiles[profile_name] = plain_copy(namespace_profile)
	namespace_count = namespace_count + 1
end

finish("success", "full profile restored before AceDB initialization", namespace_count)
