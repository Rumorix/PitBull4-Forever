local _G = _G
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local function get_luatexts_module()
	return PitBull4:GetModule("LuaTexts", true)
end

local function get_scan()
	local module = get_luatexts_module()
	if not module or type(module.ScanLegacyProfileCompatibility) ~= "function" then
		return nil
	end
	return module:ScanLegacyProfileCompatibility()
end

local function scan_description()
	local profile_name = PitBull4.db and PitBull4.db:GetCurrentProfile() or "?"
	local scan = get_scan()
	if not scan then
		return L["LuaTexts is unavailable, so this profile cannot be scanned for legacy text compatibility right now."]
	end
	return L["Current profile: %s\nKnown legacy stock LuaTexts: %d (Name: %d, Class: %d, Health: %d, Power: %d)\nCustom Name LuaTexts left untouched: %d"]:format(
		profile_name,
		scan.total or 0,
		scan.name or 0,
		scan.class or 0,
		scan.health or 0,
		scan.power or 0,
		scan.custom_name or 0
	)
end

function PitBull4.Options.get_profile_upgrade_options()
	return {
		type = "group",
		name = L["Profile Upgrade"],
		desc = L["Scan and update known legacy PitBull profile data for Midnight 12.1 compatibility without resetting layouts or visual settings."],
		childGroups = "tree",
		args = {
			intro = {
				type = "description",
				name = L["This tool upgrades only known legacy stock LuaTexts in the currently selected profile. Custom LuaTexts are not rewritten automatically."],
				order = 1,
				width = "full",
			},
			status_header = {
				type = "header",
				name = L["Compatibility scan"],
				order = 10,
			},
			status = {
				type = "description",
				name = scan_description,
				order = 11,
				width = "full",
			},
			upgrade = {
				type = "execute",
				name = L["Upgrade current profile"],
				desc = L["Apply known Midnight 12.1 compatibility migrations to the current profile. This includes legacy stock Name LuaTexts from older PitBull releases, plus the maintained Class, Health and Power migrations. Layout assignments, positions, fonts and sizes are preserved."],
				order = 20,
				disabled = function()
					if InCombatLockdown() then return true end
					local scan = get_scan()
					return not scan or (scan.total or 0) == 0
				end,
				confirm = true,
				confirmText = L["Upgrade known legacy settings in the current PitBull profile? If no full safety snapshot exists, PitBull will create one first. The UI will reload after changes are applied."],
				func = function()
					local module = get_luatexts_module()
					if not module or type(module.UpgradeLegacyProfileCompatibility) ~= "function" then
						PitBull4:Printf(L["Profile upgrade failed: LuaTexts is unavailable."])
						return
					end

					if not PitBull4:HasSafeEditModeFullSnapshot() then
						local ok = PitBull4:CreateSafeEditModeFullSnapshot()
						if not ok then
							PitBull4:Printf(L["Profile upgrade aborted because a safety snapshot could not be created."])
							return
						end
					end

					local result = module:UpgradeLegacyProfileCompatibility()
					if not result or (result.total or 0) == 0 then
						PitBull4:Printf(L["No known legacy profile settings required an upgrade."])
						return
					end

					PitBull4:Printf(L["Profile upgrade complete: %d LuaTexts updated (Name: %d, Class: %d, Health: %d, Power: %d)."], result.total or 0, result.name or 0, result.class or 0, result.health or 0, result.power or 0)
					if (result.custom_name or 0) > 0 then
						PitBull4:Printf(L["%d custom Name LuaText(s) were detected and intentionally left unchanged."], result.custom_name)
					end
					if _G.ReloadUI then
						_G.ReloadUI()
					end
				end,
			},
			name_note = {
				type = "description",
				name = L["Legacy stock Name presets are migrated to the current secret-safe format. Custom Name scripts are reported but preserved for manual review."],
				order = 21,
				width = "full",
			},
		},
	}
end
