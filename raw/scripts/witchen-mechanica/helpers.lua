--@module = true

local utils = require("utils")
local persistTable = require("persist-table")
local customRawTokens = require("custom-raw-tokens")
local syndromeUtil = require("syndrome-util")

local consts = dfhack.reqscript("witchen-mechanica/consts")

if not rng then
	rng = dfhack.random.new()
	rng:init()
end

local function xyzOrPos(x, y, z)
	if type(x) ~= "number" and not (y or z) then
		-- Assume x is actually a position object with x, y, and z fields to access
		x, y, z = pos2xyz(x)
	end
	return x, y, z
end

function doesBuildingCoverPos(building, x, y, z)
	x, y, z = xyzOrPos(x, y, z)
	return
		building.x1 <= x and x <= building.x2 and
		building.y1 <= y and y <= building.y2 and
		z == building.z
end

-- Cache added by SilasD, many thanks
-- Building cache strategy:
-- * The cache is keyed on a string composed from x, y, and z.
-- * The keys have values that are indexes into the world.buildings.all vector.
-- * The cache is checked before probing every building.
-- * If there is a cache hit, the building at world.buildings.all[index] is checked
--   against the doesBuildingCoverPos(building, x, y, z) function.
-- * That call is expected to return true, but in the case of a stale cache, it can return false.
-- * The cache will get stale when buildings are destroyed; that's okay.
local buildingCache = {}
local buildingCacheHits, buildingCacheMisses, buildingCacheStale = 0, 0, 0
function getBuildingAt(x, y, z)
	x, y, z = xyzOrPos(x, y, z)
	local _, occupancy = dfhack.maps.getTileFlags(x, y, z)
	if not occupancy or occupancy.building == 0 then
		return nil
	end

	local cacheKey = string.format("%d,%d,%d", x, y, z)
	local index = buildingCache[cacheKey]
	if index and index < #df.global.world.buildings.all then
		local building = df.global.world.buildings.all[index]
		if
			not df.building_civzonest:is_instance(building) and
			doesBuildingCoverPos(building, x, y, z)
		then
			buildingCacheHits = buildingCacheHits + 1
			return building
		else
			-- dfhack.printerr("Note: buildingCache stale at index " .. index .. "; clearing entry.")
			buildingCacheStale = buildingCacheStale + 1
			buildingCache[cacheKey] = nil
		end
	end

	for index, building in ipairs(df.global.world.buildings.all) do
		if
			not df.building_civzonest:is_instance(building) and
			doesBuildingCoverPos(building, x, y, z)
		then
			buildingCacheMisses = buildingCacheMisses + 1
			buildingCache[cacheKey] = index
			-- dfhack.printerr("New building cache entry: " .. cacheKey .. ", index " .. index .. ", " .. utils.getBuildingName(building))
			return building
		end
	end

	return nil
end

function ensurePersistStorage()
	persistTable.GlobalTable[consts.modKey] = persistTable.GlobalTable[consts.modKey] or {}
end

function getPersistNum(name)
	return tonumber(persistTable.GlobalTable[consts.modKey][name])
end

function setPersistNum(name, value)
	persistTable.GlobalTable[consts.modKey][name] = tostring(value)
end

function getPersistBool(name)
	local value = persistTable.GlobalTable[consts.modKey][name]
	if value == nil then
		return nil
	end
	return value == "true"
end

function setPersistBool(name, value)
	persistTable.GlobalTable[consts.modKey][name] = value and "true" or "false"
end

function moveItemBuildings(fromBuilding, toBuilding, fromBuildingItemRefIndex, ignoreCapacity)
	local itemRef = fromBuilding.contained_items[fromBuildingItemRefIndex]
	local item = itemRef.item

	if
		not ignoreCapacity and
		buildingHasCapacityLimit(toBuilding) and
		toBuilding:getFreeCapacity(false) < item:getVolume()
	then
		return false
	end

	fromBuilding.contained_items:erase(fromBuildingItemRefIndex)
	toBuilding.contained_items:insert("#", itemRef)

	itemRef.item.pos = xyz2pos(toBuilding.centerx, toBuilding.centery, toBuilding.z)
	local itemBuildingRef = dfhack.items.getGeneralRef(itemRef.item, df.general_ref_type.BUILDING_HOLDER)

	itemBuildingRef.building_id = toBuilding.id

	return true
end

function moveItemFromBuildingToGround(item, x, y, z)
	-- v50+ detachItem works when items are in buildings, but we're on v47

	local building = dfhack.items.getHolderBuilding(item)
	if not building then
		return false
	end

	local position
	if x and y and z then
		position = xyz2pos(x, y, z)
	else
		position = xyz2pos(dfhack.items.getPosition(item))
	end

	-- Erase item link from building
	for itemRefIndex, itemRef in ipairs(building.contained_items) do
		if itemRef.item == item then
			building.contained_items:erase(itemRefIndex)
			itemRef:delete()
			break
		end
	end
	-- Erase building link from item
	for i, ref in ipairs(item.general_refs) do
		if ref._type == df.general_ref_building_holderst then
			if ref.building_id == building.id then
				item.general_refs:erase(i)
				ref:delete()
				break
			end
		end
	end

	item.pos.x = position.x
	item.pos.y = position.y
	item.pos.z = position.z
	item.flags.on_ground = true
	item.flags.in_building = false
	item:moveToGround(position.x, position.y, position.z)

	return true
end

function moveItemBuildingToContainer(fromBuilding, toContainer, fromBuildingItemRefIndex, ignoreCapacity)
	local itemRef = fromBuilding.contained_items[fromBuildingItemRefIndex]
	local item = itemRef.item

	if not ignoreCapacity then
		local space = freeSpaceInContainer(toContainer)
		if item:getVolume() > space then
			return false
		end
	end

	-- Erase item link from building
	fromBuilding.contained_items:erase(fromBuildingItemRefIndex)
	itemRef:delete()
	-- Erase building link from item
	for i, ref in ipairs(item.general_refs) do
		if ref._type == df.general_ref_building_holderst then
			if ref.building_id == fromBuilding.id then
				item.general_refs:erase(i)
				ref:delete()
				break
			end
		end
	end

	-- Add item to container

	local containsRef = df.general_ref_contains_itemst:new()
	local containedRef = df.general_ref_contained_in_itemst:new()

	item.pos.x = toContainer.pos.x
	item.pos.y = toContainer.pos.y
	item.pos.z = toContainer.pos.z

	item.flags.in_inventory = true
	item.flags.in_building = false -- If it was a permanent or semi-permanent part of the building, then undo

	toContainer.flags.container = true
	toContainer.flags.weight_computed = false

	containsRef.item_id = item.id
	toContainer.general_refs:insert("#", containsRef)

	containedRef.item_id = toContainer.id
	item.general_refs:insert("#", containedRef)

	return true
end

function moveItemContainerToBuilding(fromContainer, toBuilding, itemToTakeRefIndex, ignoreCapacity)
	local itemRef = fromContainer.general_refs[itemToTakeRefIndex]
	local item = itemRef:getItem()

	if
		not ignoreCapacity and
		buildingHasCapacityLimit(toBuilding) and
		toBuilding:getFreeCapacity(false) < item:getVolume()
	then
		return false
	end

	-- Remove container link from item
	for i, ref in ipairs(item.general_refs) do
		if
			ref._type == df.general_ref_contained_in_itemst and
			ref:getItem() == fromContainer
		then
			item.general_refs:erase(i)
			ref:delete()
			break
		end
	end
	item.flags.in_inventory = false
	-- Remove item link from container
	fromContainer.general_refs:erase(itemToTakeRefIndex)
	itemRef:delete()
	fromContainer.flags.weight_computed = false

	-- Add item to building
	item.pos = xyz2pos(toBuilding.centerx, toBuilding.centery, toBuilding.z)
	local holdRef = df.general_ref_building_holderst:new()
	holdRef.building_id = toBuilding.id
	item.general_refs:insert("#", holdRef)
	toBuilding.contained_items:insert("#", {new = true,
		item = item,
		use_mode = 0
	})

	return true
end

local itemTypeCapacities = {
	FLASK = 180,
	GOBLET = 180,

	CAGE = 6000,
	BARREL = 6000,
	COFFIN = 6000,
	BOX = 6000,
	BAG = 6000,
	BIN = 6000,
	ARMORSTAND = 6000,
	WEAPONRACK = 6000,
	CABINET = 6000,

	BUCKET = 600,

	ANIMALTRAP = 3000,
	BACKPACK = 3000,

	QUIVER = 1200

	-- TOOL is a special case
}
function getItemCapacity(item)
	local typeName = df.item_type[item:getType()]
	if typeName == "TOOL" then
		return item.subtype.container_capacity
	end
	return itemTypeCapacities[typeName] or 0
end

function freeSpaceInContainer(container)
	local capacity = getItemCapacity(container)
	local total = 0
	for _, ref in ipairs(container.general_refs) do
		if ref._type == df.general_ref_contains_itemst then
			local item = ref:getItem()
			if item then
				total = total + item:getVolume()
			end
		end
	end
	return capacity - total
end

function buildingHasCapacityLimit(building)
	local typeName = df.building_type[building:getType()]
	if
		typeName == "Box" or
		typeName == "Armorstand" or
		typeName == "Weaponrack" or
		typeName == "Cabinet"
	then
		return true
	end

	return false
end

-- function freeSpaceInBuilding(building)
-- 	if not (
		-- Would put relevant building types here (armour stand, box, etc)
-- 	) then
-- 		return nil -- No limit
-- 	end
-- 	local capacity = 0
-- 	local total = 0
-- 	for _, containedItem in ipairs(building.contained_items) do
-- 		-- We assume that only one item is the actual container,
-- 		-- but if there is more then we just use the first.
-- 		if containedItem.use_mode == 2 and not capacity then
-- 			capacity = getItemCapacity(item)
-- 		else
-- 			total = total + containedItem.item:getVolume()
-- 		end
-- 	end
-- 	return capacity - total
-- end

function isCustomWorkshopType(building, typeName)
	if not df.building_workshopst:is_instance(building) then
		return false
	end

	local customType = df.building_def.find(building.custom_type)
	if not customType then
		return false
	end

	return customType.code == typeName
end

function setItemMaterial(item, matType, matIndex)
	item:setMaterial(matType)
	item:setMaterialIndex(matIndex)
	item.flags.temps_computed = false
	item.flags.weight_computed = false
end

function getSelectedSquad() -- TODO: Allow multiple?
	if df.global.ui.main.mode ~= df.ui_sidebar_mode.Squads then
		return nil, "wrongMode"
	end
	local ret
	for i, selected in ipairs(df.global.ui.squads.sel_squads) do
		if selected then
			if ret then
				return nil, "multiple"
			else
				ret = df.global.ui.squads.list[i]
			end
		end
	end
	if not ret then
		return nil, "none"
	else
		return ret, "success"
	end
end

function findReactionByName(name)
	for _, reaction in ipairs(df.global.world.raws.reactions.reactions) do
		if reaction.code == name then
			return reaction
		end
	end
end

-- Backported from later versions of DFHack
function removeJobPostings(job, removeAll)
	assert(job, "No job specified")
	local world = df.global.world
	local removed = false
	if not removeAll then
		if job.posting_index >= 0 and job.posting_index < #world.jobs.postings then
			local posting = world.jobs.postings[job.posting_index]
			posting.flags.dead = true
			posting.job = nil
			removed = true
		end
	else
		for _, posting in ipairs(world.jobs.postings) do
			if posting.job == job then
				posting.flags.dead = true
				posting.job = nil
				removed = true
			end
		end
	end
	job.posting_index = -1
	return removed
end
function canBeAddedToJob(unit)
	if unit.job.current_job then
		return false
	end
	return true
end
function addJobWorker(job, unit)
	assert(job, "No job specified")
	assert(unit, "No unit specified")

	if not canBeAddedToJob(unit) then
		return false
	end

	if job.posting_index ~= -1 then
		removeJobPostings(job)
	end

	job.general_refs:insert("#", {new = df.general_ref_unit_workerst, unit_id = unit.id})
	job.recheck_cntdn = 0

	unit.job.current_job = job

	return true
end

function spawnUnit(raceName, casteName, x, y, z)
	local expectedId = df.global.unit_next_id

	local raceId, casteId
	for i, raceRaw in ipairs(df.global.world.raws.creatures.all) do
		if raceRaw.creature_id == raceName then
			raceId = i

			for j, casteRaw in ipairs(raceRaw.caste) do
				if casteRaw.caste_id == casteName then
					casteId = j
					break
				end
			end

			break
		end
	end

	if not raceId then
		error("Invalid race " .. raceName)
	end
	if not casteId then
		error("Invalid caste " .. casteName)
	end

	dfhack.run_command("summon " .. table.concat({raceId, casteId, x, y, z}, " "))

	if df.global.unit_next_id == expectedId + 1 then
		return df.unit.find(expectedId)
	end
end

function canMachinePassThroughFloor(x, y, z)
	-- Return false if not a valid tile
	local tiletype = dfhack.maps.getTileType(x, y, z)
	if not tiletype then
		return false
	end
	-- Return true if open space
	local tileShapeAttrs = df.tiletype_shape.attrs[
		df.tiletype.attrs[tiletype].shape
	]
	if tileShapeAttrs.basic_shape == df.tiletype_shape_basic.Open then
		return true
	end

	-- Return false if not phasing block (lunium) construction
	local construction = dfhack.constructions.findAtTile(x, y, z)
	if not construction then
		return false
	end

	if construction.item_type ~= df.item_type.BLOCKS then
		return false
	end

	if construction.mat_type ~= 0 then -- Not an inorganic
		return false
	end

	local inorganic = df.inorganic_raw.find(construction.mat_index)
	if not inorganic then
		return false
	end

	return customRawTokens.getToken(inorganic, "WITCHEN_MECHANICA_PHASING")
end

function getDistance(x1, y1, z1, x2, y2, z2)
	-- Allow passing in two objects with x y z fields
	if type(x1) ~= "number" then
		local aPos = x1
		local bPos = y1
		return math.sqrt(
			(bPos.x - aPos.x) ^ 2 +
			(bPos.y - aPos.y) ^ 2 +
			(bPos.z - aPos.z) ^ 2
		)
	end

	return math.sqrt(
			(x2 - x1) ^ 2 +
			(y2 - y1) ^ 2 +
			(z2 - z1) ^ 2
		)
end

function getMat(token)
	local matinfo = dfhack.matinfo.find(token)
	if not matinfo then
		return
	end
	return matinfo.type, matinfo.index
end

function createMagicPuff(position, amount)
	-- Would use vapour or dust here but the dust/vapour flows settle into spatter
	local aAmount = amount
	local aMatType, aMatIndex = getMat("INORGANIC:MAGINCIUM")
	local aType = df.flow_type.MaterialGas
	dfhack.maps.spawnFlow(position, aType, aMatType, aMatIndex, aAmount)

	local bAmount = math.floor(amount / 4)
	if bAmount > 0 then
		local bMatType, bMatIndex = getMat("INORGANIC:ZEFRANNIUM")
		local bType = df.flow_type.MaterialGas
		dfhack.maps.spawnFlow(position, bType, bMatType, bMatIndex, bAmount)
	end
end

function getNumberInFlags(flags, startBit, endBit)
	local total = 0
	for i = startBit, endBit do
		if flags[i] then
			total = total + 2 ^ (i - startBit)
		end
	end
	return total
end

function setNumberInFlags(flags, number, startBit, endBit)
	for i = startBit, endBit do
		local mask = 2 ^ (i - startBit)
		flags[i] = bit32.band(number, mask) ~= 0
	end
end

function weightedRandomChoice(choices)
	local randomNumber = rng:drandom()
	local weightSum = 0
	for _, choice in ipairs(choices) do
		weightSum = weightSum + choice.weight
	end
	local x = randomNumber * weightSum
	for _, choice in ipairs(choices) do
		if x < choice.weight then
			return choice.value
		end
		x = x - choice.weight
	end
	-- Return nil, I guess
end

-- canCreatePlant and createPlant are based on the plants plugin
function canCreatePlant(x, y, z)
	local block = dfhack.maps.getTileBlock(x, y, z)
	local column = df.global.world.map.column_index[math.floor(x / 48) * 3][math.floor(y / 48) * 3]
	if not block or not column then
		return false
	end

	local lx, ly = x % 16, y % 16

	local designation = block.designation[lx][ly]
	if designation.flow_size ~= 0 then
		-- Can't spawn in liquids
		return false
	end
	local occupancy = block.occupancy[lx][ly]
	if
		occupancy.building ~= 0
		-- occupancy.no_grow ?
	then
		return false
	end

	local tiletype = block.tiletype[lx][ly]
	local tileAttrs = df.tiletype.attrs[tiletype]
	local matName = df.tiletype_material[tileAttrs.material]
	if
		tileAttrs.shape ~= df.tiletype_shape.FLOOR or
		(
			matName ~= "SOIL" and
			matName ~= "GRASS_DARK" and
			matName ~= "GRASS_LIGHT"
		)
	then
		return false
	end

	return true
end
function createPlant(plantTypeId, x, y, z, disableCheck) -- disableCheck is good if you've already checked the tile
	if not disableCheck and not canCreatePlant(x, y, z) then
		return false
	end

	local raw = df.global.world.raws.plants.all[plantTypeId]
	if not raw then
		return false
	end
	if raw.flags.GRASS then
		return false
	end

	local plant = df.plant:new()
	if raw.flags.TREE then
		plant.hitpoints = 400000
	else
		plant.hitpoints = 100000
		plant.flags.is_shrub = true
	end

	-- The plants plugin's code sets the watery flag for
	-- WET-type plants even if they're spawned away from water.
	-- According to the code (for v47), the proper method is unclear.
	if raw.flags.WET then
		plant.flags.watery = true
	end
	plant.material = plantTypeId
	plant.pos.x = x
	plant.pos.y = y
	plant.pos.z = z
	plant.update_order = rng:random(10)

	local plants = df.global.world.plants
	plants.all:insert("#", plant)
	local vec =
		plant.flags.is_shrub and (
			plant.flags.watery and plants.shrub_wet or
			plants.shrub_dry
		) or (
			plant.flags.watery and plants.tree_wet or
			plants.tree_dry
		)
	vec:insert("#", plant)

	local block = dfhack.maps.getTileBlock(x, y, z)
	local column = df.global.world.map.column_index[math.floor(x / 48) * 3][math.floor(y / 48) * 3]
	column.plants:insert("#", plant)
	block.tiletype[x % 16][y % 16] = plant.flags.is_shrub and
		df.tiletype.Shrub or df.tiletype.Sapling

	return true
end

-- By "distance" it's not actually considering pathfinding distance...
-- If you just want the closest, you can get the first value in the returned table (if present)
function sortPathableBuildingsInSetByDistance(set, x, y, z)
	local pos
	if type(x) == "number" and y and z then
		pos = xyz2pos(x, y, z)
	else
		pos = x
	end

	local pathableChoices = {}
	for _, building in ipairs(set) do
		if dfhack.maps.canWalkBetween(pos, xyz2pos(building.centerx, building.centery, building.z)) then
			table.insert(pathableChoices, building)
		end
	end

	table.sort(pathableChoices, function(a, b)
		if a.z ~= b.z then
			if a.z == z then
				return true
			elseif b.z == z then
				return false
			end
		end
		return
			math.sqrt((a.centerx - x) ^ 2 + (a.centery - y) ^ 2) <
			math.sqrt((b.centerx - x) ^ 2 + (b.centery - y) ^ 2)
	end)
	return pathableChoices
end

function canUseItem(item)
	local flags = item.flags
	if
		flags.hostile or
		flags.on_fire or
		flags.trader or
		flags.construction or
		flags.in_job or
		flags.owned or
		flags.removed or
		flags.encased or
		flags.spider_web or
		flags.garbage_collect
	then
		return false
	end
	if #item.specific_refs > 0 then
		return false
	end
	return true
end

function addItemToJob(job, item, role, filterIdx, insertIdx) -- Backported from a later DFHack version
	if role ~= df.job_item_ref.T_role.TargetContainer then
		if item.flags.in_job then
			return false
		end
		item.flags.in_job = true
	end

	local itemLink = df.specific_ref:new()
	itemLink.type = df.specific_ref_type.JOB
	itemLink.data.job = job
	item.specific_refs:insert("#", itemLink)

	local jobLink = df.job_item_ref:new()
	jobLink.item = item
	jobLink.role = role
	jobLink.job_item_idx = filterIdx

	if insertIdx >= 0 and insertIdx < #job.items then
		job.items:insert(insertIdx, jobLink)
	else
		job.items:insert("#", jobLink)
	end

	return true
end

function iterateJobs(func)
	local listLink = df.global.world.jobs.list
	while true do
		if listLink.item then
			func(listLink.item)
		end
		if listLink.next then
			listLink = listLink.next
		else
			break
		end
	end
end

function tryAddSyndrome(unit, syndromeId) -- Returns instance of syndrome and boolean for whether it was newly added
	local existingInstance = syndromeUtil.findUnitSyndrome(unit, syndromeId)
	if existingInstance then
		return existingInstance, false
	end

	if not syndromeUtil.infectWithSyndromeIfValidTarget(unit, syndromeId) then
		return
	end

	-- I assume the reinfection list is sorted.
	local oldReinfectionCount
	local added = false
	for i, reinfectionSyndromeId in ipairs(unit.syndromes.reinfection_type) do
		if reinfectionSyndromeId == syndromeId then
			oldReinfectionCount = unit.syndromes.reinfection_count[i]
			unit.syndromes.reinfection_count[i] = oldReinfectionCount + 1
			added = true
			break
		elseif reinfectionSyndromeId > syndromeId then
			oldReinfectionCount = 0
			unit.syndromes.reinfection_type:insert(i, syndromeId)
			unit.syndromes.reinfection_count:insert(i, 1) -- More like "next reinfection count"
			added = true
			break
		end
	end
	if not added then
		oldReinfectionCount = 0
		unit.syndromes.reinfection_type:insert("#", syndromeId)
		unit.syndromes.reinfection_count:insert("#", 1)
	end

	-- Set the reinfection count on the syndrome itself
	local syndromeInstance = unit.syndromes.active[#unit.syndromes.active - 1]
	if not syndromeInstance or syndromeInstance.type ~= syndromeId then
		-- ???
		return
	end
	syndromeInstance.reinfection_count = oldReinfectionCount

	return syndromeInstance, true
end

function iterateMaterials(func)
	local raws = df.global.world.raws
	for _, builtin in ipairs(raws.mat_table.builtin) do
		if builtin then
			func(builtin)
		end
	end
	for _, inorganic in ipairs(raws.inorganics) do
		func(inorganic.material)
	end
	for _, creature in ipairs(raws.creatures.all) do
		for _, material in ipairs(creature.material) do
			func(material)
		end
	end
	for _, plant in ipairs(raws.plants.all) do
		for _, material in ipairs(plant.material) do
			func(material)
		end
	end
end
