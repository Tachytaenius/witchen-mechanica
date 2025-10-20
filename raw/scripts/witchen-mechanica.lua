--@ enable = true

local dialogs = require("gui.dialogs")

local usage = [[
Usage
-----

enable witchen-mechanica
disable witchen-mechanica
]]

enabled = enabled or false

function isEnabled()
	return enabled
end

local loadedModuleList = {}
local loadedModulesByName = {}
local loadedModuleNames = {}
for _, name in ipairs({
	-- All module names go here. Order should determine order of running
	"consts",
	"helpers",
	"timekeeping",
	"events",
	"reactions",
	"machines",
	"hoppers",
	"turrets",
	"automata"
}) do
	local loadedModule = dfhack.reqscript("witchen-mechanica/" .. name)
	table.insert(loadedModuleList, loadedModule)
	loadedModulesByName[name] = loadedModule
	loadedModuleNames[loadedModule] = name
end

local consts = loadedModulesByName.consts

if not dfhack_flags.enable then
	print(usage .. "\n")
	print("Witchen Mechanica is currently " .. (isEnabled() and "enabled" or "disabled"))
	return
end

local function disable()
	for _, module in ipairs(loadedModuleList) do
		if module.enableable then
			module.disable()
		end
	end
	print("Witchen Mechanica disabled. Behaviour may break.")
	enabled = false
end

local function enable()
	for _, module in ipairs(loadedModuleList) do
		if module.enableable then
			-- Attempt to disable everything if a module has an error while enabling
			local result, message = pcall(function() module.enable() end)
			if not result then
				dfhack.printerr("Error while enabling Witchen Mechanica module \"" .. loadedModuleNames[module] .. "\"")
				dfhack.printerr(message)
				disable()
				return
			end
		end
	end
	print("Witchen Mechanica enabled")
	enabled = true
end

if dfhack_flags.enable_state then
	local currentDFVersion = dfhack.getDFVersion():match("^v([%d.]+) ") -- Remove v and OS, leaving only the numbers
	if consts.DFVersion ~= currentDFVersion then
		dialogs.showMessage("Error",
			"This version of Witchen Mechanica is for DF version " .. consts.DFVersion .. ",\n" ..
			"current DF version is " .. currentDFVersion .. ". The script will now disable.\n" ..
			"Behaviour may break."
		)
		disable()
		return
	end
	enable()
else
	disable()
end
