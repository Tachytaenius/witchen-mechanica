--@ module = true
enableable = true -- Not in the sense of the enable command

local utils = require("utils")

local timekeeping = dfhack.reqscript("witchen-mechanica/timekeeping")

machines = utils.invert({
	"WITCH_HOPPER",
	"WITCH_TURRET",
	"AUTOMATON_SUMMONARY"
})

local function onTick()
	-- Seems to fix building-hacks, but you still need to build the machine part that the custom machine connects to afterwards (TODO: fix further?)
	local buildingsToRecategorise = {}
	for _, building in ipairs(df.global.world.buildings.other.WORKSHOP_CUSTOM) do
		local customType = df.building_def.find(building.custom_type)
		-- if customType and customRawTokens.getToken(customType, "WITCHEN_MECHANICA_MACHINE") then -- There are no raws strings saved on workshops!
		if customType and machines[customType.code] then
			buildingsToRecategorise[#buildingsToRecategorise+1] = building
		end
	end
	for _, building in ipairs(buildingsToRecategorise) do
		building:uncategorize()
		building:categorize(true)
	end
end

function enable()
	timekeeping.register("machines", onTick)
end

function disable()
	timekeeping.unregister("machines")
end
