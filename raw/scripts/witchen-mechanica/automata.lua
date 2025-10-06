--@ module = true
enableable = true

local customRawTokens = require("custom-raw-tokens")

local createUnit = dfhack.reqscript("modtools/create-unit")

local timekeeping = dfhack.reqscript("witchen-mechanica/timekeeping")
local events = dfhack.reqscript("witchen-mechanica/events")

local function deathFlowOnUnitDeath(unitId)
	local unit = df.unit.find(unitId)
	if not unit then
		return
	end

	local flowDimension, flowTypeName, materialArgA, materialArgB, materialArgC, materialArgD =
		customRawTokens.getToken(unit, "WITCHEN_MECHANICA_DEATH_FLOW")
	if not flowDimension then
		return
	end

	local position = xyz2pos(dfhack.units.getPosition(unit))
	if not position then
		return
	end

	local token = table.concat({materialArgA, materialArgB, materialArgC, materialArgD}, ":") -- Avoid passing trailing nils to the function as it will error
	local matInfo = dfhack.matinfo.find(token)

	dfhack.maps.spawnFlow(position, df.flow_type[flowTypeName], matInfo and matInfo.type or -1, matInfo and matInfo.index or -1, flowDimension)
end

local function updateAutomaton(automatonUnit)
	local kill = false
	local requiredItemSubtype, requiredItemMode, bodyPart = customRawTokens.getToken(automatonUnit, "WITCHEN_MECHANICA_AUTOMATON_REQUIRED_TOOL")
	if requiredItemMode then
		local found = false
		for _, inventoryItem in ipairs(automatonUnit.inventory) do
			if
				inventoryItem.mode == df.unit_inventory_item.T_mode[requiredItemMode] and
				inventoryItem.item._type == df.item_toolst and
				inventoryItem.item.subtype.id == requiredItemSubtype and
				(
					not bodyPart or
					inventoryItem.body_part_id ~= -1 and
					automatonUnit.body.body_plan.body_parts[inventoryItem.body_part_id].token == bodyPart
				)
			then
				found = true
				break
			end
		end
		if not found then
			kill = true
		end
	end
	if kill then
		automatonUnit.animal.vanish_countdown = 1
	end

	-- TODO: Wipe soul struct. Apparently they can experience trauma
end

local function onTick()
	for _, unit in ipairs(df.global.world.units.active) do
		if customRawTokens.getToken(unit, "WITCHEN_MECHANICA_IS_AUTOMATON") then
			updateAutomaton(unit)
		end
	end
end

function createAutomaton(x, y, z, core)
	-- TODO: What about advfort (adventure mode), will domestication work?
	local createdUnits = createUnit.createUnit(
		"WITCH_AUTOMATON", -- raceStr,
		nil, -- casteStr,
		{x = x, y = y, z = z}, -- pos,
		nil, -- locationRange,
		nil, -- locationType,
		nil, -- age,
		true, -- domesticate,
		nil, -- civ_id,
		nil, -- group_id,
		nil, -- entityRawName,
		nil, -- nickname,
		nil, -- vanishDelay,
		nil, -- quantity,
		nil, -- equip,
		nil, -- skills,
		nil, -- profession,
		nil, -- customProfession,
		nil, -- flagSet,
		{"scuttle"} -- flagClear
	)
	local newAutomaton = createdUnits[1]
	if not newAutomaton then
		return
	end

	if not core then
		return
	end
	if not dfhack.items.moveToGround(core, xyz2pos(dfhack.items.getPosition(core))) then
		return
	end
	local coreReceptacleBodyPartId = 1 -- TODO: Find by "WITCH_AUTOMATON_CORE_RECEPTACLE"
	if not dfhack.items.moveToInventory(core, newAutomaton, df.unit_inventory_item.T_mode.SewnInto, coreReceptacleBodyPartId) then
		return
	end
end

function enable()
	-- Assume loading world, if reenabling this is OK too
	-- TODO: How to run code automatically during worldgen, since init.d isn't checked?
	for _, creature in ipairs(df.global.world.raws.creatures.all) do
		if customRawTokens.getToken(creature, "WITCHEN_MECHANICA_NOT_WAGON") then
			creature.flags.EQUIPMENT_WAGON = false
			-- Assume EQUIPMENT, NOPAIN, etc are true because of [EQUIPMENT_WAGON]
		end
	end

	-- TEMP
	local x, y, z = pos2xyz(df.global.cursor)
	createAutomaton(x, y, z, dfhack.gui.getSelectedItem())

	events.register("deathFlows", "onUnitDeath", deathFlowOnUnitDeath, "UNIT_DEATH", 1)
	timekeeping.register("automata", onTick)
end

function disable()
	-- Assume unloading world, do nothing regarding the WITCHEN_MECHANICA_NOT_WAGON custom raw token

	events.unregister("deathFlows", "onUnitDeath")
	timekeeping.unregister("automata")
end
