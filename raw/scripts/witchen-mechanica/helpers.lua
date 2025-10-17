--@module = true

local persistTable = require("persist-table")

local consts = dfhack.reqscript("witchen-mechanica/consts")

if not rng then
	rng = dfhack.random.new()
	rng:init()
end

function doesBuildingCoverPos(building, x, y, z)
	return
		building.x1 <= x and x <= building.x2 and
		building.y1 <= y and y <= building.y2 and
		z == building.z
end

-- TODO: Cache buildings
function getBuildingAt(x, y, z)
	local _, occupancy = dfhack.maps.getTileFlags(x, y, z)
	if not occupancy or occupancy.building == 0 then
		return nil
	end

	for _, building in ipairs(df.global.world.buildings.all) do
		if doesBuildingCoverPos(building, x, y, z) then
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
