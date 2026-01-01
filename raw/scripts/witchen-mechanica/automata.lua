--@ module = true
enableable = true

local customRawTokens = require("custom-raw-tokens")
local buildingHacks = require("plugins.building-hacks")
local utils = require("utils")
local createUnit = dfhack.reqscript("modtools/create-unit")
local syndromeUtil = require("syndrome-util")

local timekeeping = dfhack.reqscript("witchen-mechanica/timekeeping")
local events = dfhack.reqscript("witchen-mechanica/events")
local helpers = dfhack.reqscript("witchen-mechanica/helpers")
local consts = dfhack.reqscript("witchen-mechanica/consts")

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

local function automatonKillCheck(automatonUnit)
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
	return kill
end

local function workOnCurrentJob(automatonUnit)
	-- The game is surprisingly compliant with our vision here. The automata actually do jobs.
	-- So we will just add some effects and speed up the process.

	local currentJobActionCount = 0
	local hasJobRecover = false
	local firstJobAction
	for _, action in ipairs(automatonUnit.actions) do
		if action.type == df.unit_action_type.Job then
			firstJobAction = firstJobAction or action
			currentJobActionCount = currentJobActionCount + 1

			action.data.job.timer = 1
		elseif action.type == df.unit_action_type.JobRecover then
			hasJobRecover = true
		end
	end
	if not hasJobRecover and currentJobActionCount == 1 then
		local noneActionSearchStart = 0
		local noNoneActionsLeft = false
		for _=1, consts.automatonInstantJobActionCount - currentJobActionCount do
			local action

			if not noNoneActionsLeft then
				local foundNoneAction = false
				for i = noneActionSearchStart, #automatonUnit.actions - 1 do
					local potentialNoneAction = automatonUnit.actions[i]
					if potentialNoneAction.type == df.unit_action_type.None then
						action = potentialNoneAction
						foundNoneAction = true
						noneActionSearchStart = i + 1
						break
					end
				end
				if not foundNoneAction then
					noNoneActionsLeft = true
				end
			end

			if not action then
				action = df.unit_action:new()
				automatonUnit.actions:insert("#", action)
			end

			action.id = automatonUnit.next_action_id
			automatonUnit.next_action_id = automatonUnit.next_action_id + 1

			action.type = df.unit_action_type.Job
			action.data.job.x = firstJobAction.data.job.x
			action.data.job.y = firstJobAction.data.job.y
			action.data.job.z = firstJobAction.data.job.z

			action.data.job.timer = 1
		end
	end

	local position = xyz2pos(dfhack.units.getPosition(automatonUnit))
	if not position then
		return
	end
	if helpers.rng:drandom() < consts.automatonWorkSmallMagicPuffChance then
		helpers.createMagicPuff(position, consts.automatonWorkSmallMagicPuffSize)
	elseif helpers.rng:drandom() < consts.automatonWorkSmallMagicPuffChance then
		helpers.createMagicPuff(position, consts.automatonWorkLargeMagicPuffSize)
	end
end

local workableBuildingTypes = utils.invert({
	df.building_workshopst,
	df.building_furnacest,
	df.building_trapst
})

function automatonWorkAtBuildingEnabled(automatonUnit, building)
	-- TODO: Is this the system we want...?
	if #building.profile.permitted_workers ~= 1 then
		return false
	end
	if building.profile.permitted_workers[0] ~= automatonUnit.id then -- TODO: Interface to assign automaton as worker
		return false
	end
	return true
end

local function automatonActivate(automatonUnit)
	-- Repeatedly called when powered
	local syndrome = helpers.findSyndromeByName("automaton deactivation")
	syndromeUtil.eraseSyndrome(automatonUnit, syndrome.id)
end
local function automatonDeactivate(automatonUnit)
	-- Repeatedly called when unpowered
	local syndrome = helpers.findSyndromeByName("automaton deactivation")
	local instance = helpers.tryAddSyndrome(automatonUnit, syndrome)
	if not instance then
		-- Shouldn't happen
		return
	end
	-- This makes it work less well?
	-- for _, symptom in ipairs(instance.symptoms) do
	-- 	symptom.quantity = 10000
	-- end
end

local function automatonWork(automatonUnit)
	local x, y, z = dfhack.units.getPosition(automatonUnit)
	if not (x and y and z) then
		return
	end
	local building = helpers.getBuildingAt(x, y, z)
	if not building then
		return
	end
	if not workableBuildingTypes[building._type] then
		return
	end
	if not (x == building.centerx and y == building.centery) then
		-- centerx and centery appear to actually be the work location, which we want the automaton to sit at
		return
	end
	if not automatonWorkAtBuildingEnabled(automatonUnit, building) then
		return
	end

	-- We have an appropriate workshop assigned to the automaton
	local currentJob = automatonUnit.job.current_job
	if currentJob then
		-- Check that current job is indeed in the building
		for _, job in ipairs(building.jobs) do
			if job == currentJob then
				workOnCurrentJob(automatonUnit)
				break
			end
		end
		return -- Either way, don't continue to find a new job
	end

	-- Find new job
	local jobToWorkOn
	for _, job in ipairs(building.jobs) do
		if job.flags.working then
			return -- Abort looking for new job and do nothing
		end
		if job.flags.suspend then
			goto continue
		end
		-- If there aren't jobs being worked on (which would mean the workshop isn't available),
		-- then pick the first job, or, if there are do-now jobs, pick the first of those.
		-- I'm fairly sure that's the vanilla behaviour.
		if not jobToWorkOn then
			jobToWorkOn = job
		elseif job.flags.do_now and not jobToWorkOn.flags.do_now then
			jobToWorkOn = job
		end
		::continue::
	end
	if not jobToWorkOn then
		return
	end

	-- Get set into new job
	helpers.addJobWorker(jobToWorkOn, automatonUnit)
end

local function updateAutomaton(automatonUnit, powerLocations)
	if automatonKillCheck(automatonUnit) then
		return
	end

	-- TODO: Wipe soul struct. Apparently they can experience trauma etc
	-- TODO: Wipe physical attributes too
	-- TODO: Zero fat? Or do so on creation?

	local position = xyz2pos(dfhack.units.getPosition(automatonUnit))
	local powered = false
	if position then
		for _, powerLocation in ipairs(powerLocations) do
			-- Keep it to a cuboid for easier area coverage. Would be a sphere with the condition below
			-- helpers.getDistance(position, powerLocation) <= powerLocation.radius
			local diffX, diffY, diffZ = position.x - powerLocation.x, position.y - powerLocation.y, position.z - powerLocation.z
			if math.max(math.abs(diffX), math.abs(diffY), math.abs(diffZ)) <= powerLocation.radius then
				powered = true
				break
			end
		end
	end

	if powered then
		automatonActivate(automatonUnit)
		automatonWork(automatonUnit)
	else
		automatonDeactivate(automatonUnit)
	end
end

local function onTick()
	local powerLocations = {}
	for _, building in ipairs(df.global.world.buildings.other.WORKSHOP_CUSTOM) do
		if not building:isActual() then
			goto continue
		end
		local customType = df.building_def.find(building.custom_type)
		if not customType then
			goto continue
		end
		if customType.code ~= "AUTOMATON_PYLON_BASE" then
			goto continue
		end
		if not helpers.isBuildingConstructed(building) then
			goto continue
		end
		if building:isUnpowered() then
			goto continue
		end

		-- Find tile above pylon base centre
		-- centerx and centery refer to the work location, so we calculate the centre ourselves
		local ox, oy = math.floor(customType.dim_x / 2), math.floor(customType.dim_y / 2)
		local x, y, z = building.x1 + ox, building.y1 + oy, building.z + 1

		-- Phasing floor required
		if not helpers.canMachinePassThroughFloor(x, y, z) then
			goto continue
		end
		-- Pylon top required
		local topBuilding = helpers.getBuildingAt(x, y, z)
		if not topBuilding then
			goto continue
		end
		if topBuilding._type ~= df.building_workshopst then
			goto continue
		end
		local topCustomType = df.building_def.find(topBuilding.custom_type)
		if not topCustomType then
			goto continue
		end
		if topCustomType.code ~= "AUTOMATON_PYLON_TOP" then
			goto continue
		end
		if not helpers.isBuildingConstructed(topBuilding) then
			goto continue
		end

		-- Add power location at pylon top
		table.insert(powerLocations, {
			x = x, y = y, z = z,
			radius = consts.automatonPylonRadius
		})

		::continue::
	end

	for _, unit in ipairs(df.global.world.units.active) do
		if dfhack.units.isActive(unit) then
			if customRawTokens.getToken(unit, "WITCHEN_MECHANICA_IS_AUTOMATON") then
				updateAutomaton(unit, powerLocations)
			end
		end
	end
end

function createAutomaton(x, y, z, core, languageId, civId)
	local newAutomaton = helpers.spawnUnit("WITCH_AUTOMATON", "DEFAULT", x, y, z) -- modtools/create-unit can cause crashes if run when core is suspended (like in a job hook)
	if not newAutomaton then
		return
	end

	local nextAutomatonNumber = helpers.getPersistNum("nextAutomatonNumber") or 1
	local name = "Automaton #" .. nextAutomatonNumber
	nextAutomatonNumber = nextAutomatonNumber + 1
	helpers.setPersistNum("nextAutomatonNumber", nextAutomatonNumber)

	newAutomaton.flags3.scuttle = false
	newAutomaton.civ_id = civId
	createUnit.setAge(newAutomaton, 0)
	createUnit.induceBodyComputations(newAutomaton)
	createUnit.domesticateUnit(newAutomaton) -- TODO: What about advfort (adventure mode), will domestication work?
	if languageId then
		local function setName(nameStruct)
			nameStruct.first_name = name
			nameStruct.language = languageId
			nameStruct.type = df.language_name_type.Figure
			nameStruct.has_name = true
		end

		setName(newAutomaton.name)

		local histfig = df.historical_figure.find(newAutomaton.hist_figure_id)
		if histfig then
			setName(histfig.name)
		end

		local soul = newAutomaton.status.current_soul
		if soul then
			setName(soul.name)
		end
	end
	newAutomaton.counters2.stored_fat = 0

	if not core then
		return
	end
	for i, part in ipairs(newAutomaton.body.body_plan.body_parts) do
		if part.token == "CORE_RECEPTACLE" then
			dfhack.items.moveToInventory(core, newAutomaton, df.unit_inventory_item.T_mode.SewnInto, i)
			break
		end
	end
end

local function onConstructAutomatonJob(job)
	if job.job_type ~= df.job_type.CustomReaction then
		return
	end
	local reaction = helpers.findReactionByName(job.reaction_name)
	local reagentName = customRawTokens.getToken(reaction, "WITCHEN_MECHANICA_CONSTRUCT_AUTOMATON_WITH_CORE_REAGENT")
	if not reagentName then
		return
	end

	-- Get language id for name
	-- Names having an unset language id can cause crashes
	local worker = dfhack.job.getWorker(job)
	if not worker then
		return
	end
	local civId = worker.civ_id
	local civ = df.historical_entity.find(civId)
	local languageId
	if civ then
		local languageName = civ.entity_raw.translation
		for i, translation in ipairs(df.global.world.raws.language.translations) do
			if translation.name == languageName then
				languageId = i
				break
			end
		end
	elseif worker.name.has_name then
		languageId = worker.name.language
	end
	if not languageId then
		return
	end

	local building = dfhack.job.getHolder(job)
	if not building then
		return
	end
	local x, y, z = building.x1 + 2, building.y1 + 0, building.z

	local coreItem
	for _, itemRef in ipairs(job.items) do
		if itemRef.role == df.job_item_ref.T_role.Reagent then
			local jobItem = job.job_items[itemRef.job_item_idx]
			if jobItem.reagent_index ~= -1 then
				local reagent = reaction.reagents[jobItem.reagent_index]
				if reagent and reagent.code == reagentName then
					coreItem = itemRef.item
					break
				end
			end
		end
	end

	if not coreItem then
		return
	end

	if not helpers.moveItemFromBuildingToGround(coreItem, x, y, z) then
		return
	end

	createAutomaton(x, y, z, coreItem, languageId, civId)
end


function enable()
	-- Assume loading world, if reenabling this is OK too
	-- TODO: How to run code automatically during worldgen, since init.d isn't checked?
	for _, creature in ipairs(df.global.world.raws.creatures.all) do
		-- Used by automata. Can move if needed

		local creatureFlags = {customRawTokens.getToken(creature, "WITCHEN_MECHANICA_UNSET_CREATURE_FLAGS")}
		if creatureFlags[1] then
			for _, flag in ipairs(creatureFlags) do
				creature.flags[flag] = false
			end
		end

		for i, caste in ipairs(creature.caste) do
			local casteFlags = {customRawTokens.getToken(creature, i, "WITCHEN_MECHANICA_UNSET_CASTE_FLAGS")}
			if casteFlags[1] then
				for _, flag in ipairs(casteFlags) do
					caste.flags[flag] = false
				end
			end
		end
	end

	events.register("deathFlows", "onUnitDeath", deathFlowOnUnitDeath, "UNIT_DEATH", 1)
	events.register("automatonCreation", "onJobCompleted", onConstructAutomatonJob, "JOB_COMPLETED", 0)
	timekeeping.register("automata", onTick)

	-- Construct the frames for the automaton summonary
	local animRNG = dfhack.random.new() -- Random generator for the animation
	animRNG:init(0)
	local frames = {}
	for i = 1, 50 do
		local leftColour = animRNG:drandom() < 0.5 and "lightRed" or (animRNG:drandom() < 1 / 3 and "black" or "red")
		local rightColour = animRNG:drandom() < 0.5 and "lightRed" or (animRNG:drandom() < 1 / 3 and "black" or "red")
		frames[i] = {
			{
				x = 1, y = 0,
				196, leftColour == "black" and 0 or 4, 0, leftColour == "lightRed" and 1 or 0
			},
			{
				x = 3, y = 0,
				196, rightColour == "black" and 0 or 4, 0, rightColour == "lightRed" and 1 or 0
			}
		}
	end
	buildingHacks.registerBuilding({
		name = "AUTOMATON_SUMMONARY",
		consume = 120,
		needs_power = 1,
		gears = {
			{x = 2, y = 0}
		},
		animate = {
			frameLength = 1,
			frames = frames
		}
	})

	-- Construct the frames for the sorcerous pylon base
	local positions = {
		{1, 1},
		{2, 1},
		{3, 1},
		{3, 2},
		{3, 3},
		{2, 3},
		{1, 3},
		{1, 2}
	}
	local chars = {
		[1] = {
			[1] = 218,
			[2] = 179,
			[3] = 192
		},
		[2] = {
			[1] = 196,
			[3] = 196
		},
		[3] = {
			[1] = 191,
			[2] = 179,
			[3] = 217
		}
	}
	local chain = {
		{4, 0, 1},
		{5, 0, 1},
		{1, 0, 1},
		{7, 0, 1, char = 249},
		{3, 0, 1},
		{2, 0, 1},
		{6, 0, 1},
		{7, 0, 1, char = 249}
	}
	local frames = {}
	for frameNum = 1, 8 do
		local frame = {}
		frames[frameNum] = frame
		for positionNumber, position in ipairs(positions) do
			local x, y = position[1], position[2]
			local chainIndex = ((frameNum - 1) + (positionNumber - 1)) % 8 + 1
			local chainEntry = chain[chainIndex]
			local char = chainEntry.char or chars[x][y]
			table.insert(frame, {
				x = x, y = y,
				char, table.unpack(chainEntry)
			})
		end
	end
	buildingHacks.registerBuilding({
		name = "AUTOMATON_PYLON_BASE",
		consume = 500,
		needs_power = 1,
		gears = {
			{x = 2, y = 0},
			{x = 0, y = 2},
			{x = 4, y = 2},
			-- {x = 2, y = 4} Replaced with the work location.
		},
		animate = {
			frameLength = 16,
			frames = frames
		}
	})
end

function disable()
	-- Assume unloading world, do nothing regarding the WITCHEN_MECHANICA_NOT_WAGON custom raw token etc

	events.unregister("deathFlows", "onUnitDeath")
	events.unregister("automatonCreation", "onJobCompleted")
	timekeeping.unregister("automata")

	buildingHacks.registerBuilding({name = "AUTOMATON_SUMMONARY"})
	buildingHacks.registerBuilding({name = "AUTOMATON_PYLON_BASE"})
end
