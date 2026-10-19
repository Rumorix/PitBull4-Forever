local _G = _G
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local function get_safe_edit_mode_status()
	local settings = PitBull4.db.profile.safe_edit_mode
	local reference = PitBull4:GetSafeEditModePositionReference()
	if reference then
		return L["Position reference: %s (%d unit frames, %d groups)"]:format(reference.created_at or L["unknown time"], reference.unit_count or 0, reference.group_count or 0)
	elseif settings and settings.setup_state == "skipped" then
		return L["Position reference: none (safety prompt was skipped)"]
	end
	return L["Position reference: none (setup is pending)"]
end

local function get_full_snapshot_status()
	local settings = PitBull4.db.profile.safe_edit_mode
	local snapshot = PitBull4:GetSafeEditModeFullSnapshot()
	if snapshot then
		return L["Full safety snapshot: %s (%d module namespaces)"]:format(snapshot.created_at or L["unknown time"], snapshot.namespace_count or 0)
	elseif settings and settings.full_snapshot_setup == "skipped" then
		return L["Full safety snapshot: none (safety prompt was skipped)"]
	end
	return L["Full safety snapshot: none (required before safe Edit Mode use)"]
end

function PitBull4.Options.get_edit_mode_backup_options()
	return {
		type = "group",
		name = L["Edit Mode Backup"],
		desc = L["Manage the safety backup and position reference used by PitBull's Blizzard Edit Mode overlay."],
		childGroups = "tree",
		args = {
			enabled = {
				type = 'toggle',
				name = L["Enable safe Edit Mode overlay"],
				desc = L["Show independent non-secure PitBull mover previews while Blizzard Edit Mode is open. Real PitBull unit frames are never force-shown and PitBull Config Mode is never changed."],
				order = 1,
				get = function()
					local settings = PitBull4.db.profile.safe_edit_mode
					return not settings or settings.enabled ~= false
				end,
				set = function(_, value)
					local settings = PitBull4.db.profile.safe_edit_mode
					if type(settings) ~= "table" then
						settings = {}
						PitBull4.db.profile.safe_edit_mode = settings
					end
					settings.enabled = value
					if value and settings.full_snapshot_setup == nil and not PitBull4:HasSafeEditModeFullSnapshot() then
						PitBull4:ShowSafeEditModeBackupPrompt(true)
					elseif PitBull4.SafeEditModeOverlay then
						PitBull4.SafeEditModeOverlay:Refresh()
					end
				end,
			},
			full_snapshot_header = {
				type = 'header',
				name = L["Full profile safety snapshot"],
				order = 10,
			},
			full_snapshot_status = {
				type = 'description',
				name = get_full_snapshot_status,
				order = 11,
				width = 'full',
			},
			create_full_snapshot = {
				type = 'execute',
				name = L["Create / update full safety snapshot"],
				desc = L["Save the complete current PitBull profile and all module profile settings in a separate SavedVariable. This includes frame positions, layouts, texts, auras, sizes, visibility, group settings, colors and module options."],
				order = 12,
				disabled = function() return InCombatLockdown() end,
				confirm = function()
					if PitBull4:HasSafeEditModeFullSnapshot() then
						return L["Replace the existing full PitBull safety snapshot for this profile with the current configuration?"]
					end
				end,
				func = function()
					local ok, namespaces = PitBull4:CreateSafeEditModeFullSnapshot()
					if ok then
						local snapshot = PitBull4:GetSafeEditModeFullSnapshot()
						PitBull4:Printf(L["Full PitBull safety snapshot saved for profile '%s' (%d module namespaces)."], snapshot and snapshot.profile_name or "", namespaces or 0)
						if PitBull4.SafeEditModeOverlay then PitBull4.SafeEditModeOverlay:Refresh() end
					end
				end,
			},
			restore_full_snapshot = {
				type = 'execute',
				name = L["Restore full safety snapshot"],
				desc = L["Completely restore this PitBull profile and all saved module profile settings from the safety snapshot. Restore is staged and applied before PitBull/AceDB initializes on the following UI reload, preventing live profile references from overwriting the recovery data."],
				order = 13,
				disabled = function() return InCombatLockdown() or not PitBull4:HasSafeEditModeFullSnapshot() end,
				func = function()
					PitBull4:ShowSafeEditModeFullRestorePrompt()
				end,
			},
			delete_full_snapshot = {
				type = 'execute',
				name = L["Delete full safety snapshot"],
				desc = L["Delete the separately stored full-profile safety snapshot for the current PitBull profile. This does not change the active configuration."],
				order = 14,
				disabled = function() return not PitBull4:HasSafeEditModeFullSnapshot() end,
				confirm = true,
				confirmText = L["Delete the full PitBull safety snapshot for this profile?"],
				func = function()
					if PitBull4:DeleteSafeEditModeFullSnapshot() then
						PitBull4:Printf(L["Full PitBull safety snapshot deleted."])
					end
				end,
			},
			position_header = {
				type = 'header',
				name = L["Position reference"],
				order = 20,
			},
			status = {
				type = 'description',
				name = get_safe_edit_mode_status,
				order = 21,
				width = 'full',
			},
			create_reference = {
				type = 'execute',
				name = L["Create / update position reference"],
				desc = L["Save only the current anchor and X/Y position of all configured PitBull singleton frames and groups for this profile."],
				order = 22,
				disabled = function() return InCombatLockdown() end,
				func = function()
					local ok, units, groups = PitBull4:CreateSafeEditModePositionReference()
					if ok then
						PitBull4:Printf(L["Edit Mode position reference saved for %d unit frames and %d groups."], units, groups)
						if PitBull4.SafeEditModeOverlay then PitBull4.SafeEditModeOverlay:Refresh() end
					end
				end,
			},
			restore_reference = {
				type = 'execute',
				name = L["Restore reference positions"],
				desc = L["Restore only saved anchor and X/Y positions. Layouts, texts, auras, visibility, group growth and module settings are not changed."],
				order = 23,
				disabled = function() return InCombatLockdown() or not PitBull4:HasSafeEditModePositionReference() end,
				confirm = true,
				confirmText = L["Restore all PitBull frame positions from the saved safe Edit Mode reference?"],
				func = function()
					local ok, units, groups = PitBull4:RestoreSafeEditModePositionReference()
					if ok then PitBull4:Printf(L["Restored reference positions for %d unit frames and %d groups."], units, groups) end
				end,
			},
			delete_reference = {
				type = 'execute',
				name = L["Delete position reference"],
				desc = L["Delete the saved position-only Edit Mode reference for this profile. This does not move any frames."],
				order = 24,
				disabled = function() return not PitBull4:HasSafeEditModePositionReference() end,
				confirm = true,
				confirmText = L["Delete the saved safe Edit Mode position reference?"],
				func = function()
					PitBull4:DeleteSafeEditModePositionReference()
					PitBull4:Printf(L["Edit Mode position reference deleted."])
				end,
			},
		},
	}
end
