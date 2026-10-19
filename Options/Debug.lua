local _G = _G
local PitBull4 = _G.PitBull4
local L = PitBull4.L

local function get_aura_module()
	return PitBull4:GetModule("Aura", true)
end

local function notify_options()
	local registry = LibStub("AceConfigRegistry-3.0", true)
	if registry and PitBull4.Options and PitBull4.Options.IsRegistered and PitBull4.Options.IsRegistered() then
		registry:NotifyChange("PitBull4")
	end
end

local function debug_is_enabled()
	local module = get_aura_module()
	return module and module.IsDebugModeEnabled and module:IsDebugModeEnabled() or false
end

local function set_debug_enabled(value)
	local module = get_aura_module()
	if module and module.SetDebugMode then
		module:SetDebugMode(value, false)
	end
	notify_options()
end

local function open_debug_window()
	local module = get_aura_module()
	if module and module.OpenDebugWindow then
		module:OpenDebugWindow()
	end
end

local function run_debug_scan(scan_all)
	local module = get_aura_module()
	if module and module.RunDebugScan then
		module:RunDebugScan(scan_all, scan_all and "options-scanall" or "options-scan", false)
	end
	notify_options()
end

local function clear_debug_output()
	local module = get_aura_module()
	if module and module.ClearDebugOutput then
		module:ClearDebugOutput(false)
	end
	notify_options()
end

local function reset_debug_state()
	local module = get_aura_module()
	if module and module.ResetDebugState then
		module:ResetDebugState(false)
	end
	notify_options()
end

local function get_debug_output()
	local module = get_aura_module()
	if module and module.GetDebugOutput then
		local output = module:GetDebugOutput()
		if output and output ~= "" then
			return output
		end
	end
	return L["No debug output has been collected yet."]
end

local function make_debug_actions(start_order)
	local order = start_order or 1
	local function next_order()
		local current = order
		order = order + 1
		return current
	end

	return {
		open_window = {
			type = "execute",
			name = L["Open Debug Window"],
			desc = L["Open the standalone copyable debug output window."],
			order = next_order(),
			func = open_debug_window,
		},
		scan = {
			type = "execute",
			name = L["Scan"],
			desc = L["Collect focused aura and portrait diagnostics."],
			order = next_order(),
			disabled = function() return not debug_is_enabled() end,
			func = function() run_debug_scan(false) end,
		},
		scan_all = {
			type = "execute",
			name = L["Scan All"],
			desc = L["Collect all currently registered player aura and portrait diagnostics."],
			order = next_order(),
			disabled = function() return not debug_is_enabled() end,
			func = function() run_debug_scan(true) end,
		},
		refresh = {
			type = "execute",
			name = L["Refresh Output"],
			desc = L["Refresh the debug text shown in the configuration window."],
			order = next_order(),
			func = notify_options,
		},
		clear = {
			type = "execute",
			name = L["Clear Output"],
			desc = L["Remove all currently collected debug text."],
			order = next_order(),
			func = clear_debug_output,
		},
		reset = {
			type = "execute",
			name = L["Reset Debug State"],
			desc = L["Reset debug counters, duplicate suppression, and collected output."],
			order = next_order(),
			func = reset_debug_state,
		},
	}
end

function PitBull4.Options.get_debug_options()
	local options = {
		type = "group",
		name = L["Debug"],
		desc = L["Enable diagnostics and collect copyable information for bug reports."],
		childGroups = "tree",
		args = {
			mode_header = {
				type = "header",
				name = L["Debug Mode"],
				order = 1,
			},
			enabled = {
				type = "toggle",
				name = L["Enable Debug Mode"],
				desc = L["Enable diagnostic collection. Leave this disabled during normal gameplay."],
				order = 2,
				get = debug_is_enabled,
				set = function(_, value) set_debug_enabled(value) end,
			},
			status = {
				type = "description",
				name = function()
					return debug_is_enabled() and L["Debug mode is currently enabled."] or L["Debug mode is currently disabled."]
				end,
				order = 3,
			},
			actions_header = {
				type = "header",
				name = L["Actions"],
				order = 10,
			},
			window = {
				type = "group",
				name = L["Debug Window"],
				desc = L["View and copy the collected debug output."],
				order = 100,
				args = {},
			},
		},
	}

	local actions = make_debug_actions(11)
	for key, value in pairs(actions) do
		options.args[key] = value
	end

	local window_actions = make_debug_actions(2)
	options.args.window.args.instructions = {
		type = "description",
		name = L["Enable debug mode, reproduce the problem, run Scan or Scan All, then copy the output below. You can also open the standalone window for easier copying."],
		order = 1,
		width = "full",
	}
	for key, value in pairs(window_actions) do
		options.args.window.args[key] = value
	end
	options.args.window.args.output = {
		type = "input",
		name = L["Debug Output"],
		desc = L["Click inside the field and press Ctrl+A, then Ctrl+C to copy the complete output."],
		order = 20,
		width = "full",
		multiline = 22,
		get = get_debug_output,
		set = function() end,
	}

	return options
end
