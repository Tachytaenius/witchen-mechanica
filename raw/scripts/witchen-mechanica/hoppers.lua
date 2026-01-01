--@ module = true
enableable = true -- Not in the sense of the enable command

local buildingHacks = require("plugins.building-hacks")
local utils = require("utils")

local consts = dfhack.reqscript("witchen-mechanica/consts")
local helpers = dfhack.reqscript("witchen-mechanica/helpers")
local timekeeping = dfhack.reqscript("witchen-mechanica/timekeeping")

-- If two hoppers are stacked on top of each other, the one below will give its item further down, then
-- take an item from the hopper above. Afterwards, the hopper above will give an item (likely nothing)
-- to the hopper below, and then take an item from further above.

allowedHopperBuildingTypes = utils.invert({
	df.building_furnacest,
	df.building_bookcasest,
	df.building_nest_boxst,
	df.building_wagonst,
	df.building_tradedepotst,
	df.building_coffinst,
	df.building_armorstandst,
	df.building_boxst,
	df.building_hivest,
	df.building_weaponrackst,
	df.building_workshopst,
	df.building_cagest
})

function isBuildingHopperInteractable(building)
	if not building.flags.exists then
		return false
	end
	if not allowedHopperBuildingTypes[building._type] then
		return false
	end
	return true
end

function hopperCanMoveItem(item)
	return helpers.canUseItem(item, true) and not item.flags.in_building -- in_building is displayed on a pedestal etc
end

function hopperIndividualItemFilterCheck(item, filterItem)
	local match =
		item:getType() == filterItem:getType() and
		item:getSubtype() == filterItem:getSubtype() and
		item:getActualMaterial() == filterItem:getActualMaterial() and
		(
			item:getActualMaterialIndex() == filterItem:getActualMaterialIndex() or
			-- Fixing an observed bug:
			item.mat_index == -1 and filterItem.mat_index == 0 or
			item.mat_index == 0 and filterItem.mat_index == -1
		)
	return match
end

function hopperItemFilterCheck(item, filterItem)
	if not hopperIndividualItemFilterCheck(item, filterItem) then
		return false
	end
	local itemContents = dfhack.items.getContainedItems(item)
	local filterItemContents = dfhack.items.getContainedItems(filterItem) -- Gets erased from as items are matched against
	if #itemContents ~= #filterItemContents then
		return false
	end
	for _, containedItem in ipairs(itemContents) do
		local foundForThisContainedItem = false
		for filterI, containedFilterItem in ipairs(filterItemContents) do
			if hopperIndividualItemFilterCheck(containedItem, containedFilterItem) then
				foundForThisContainedItem = true
				filterItemContents[filterI], filterItemContents[#filterItemContents] = filterItemContents[#filterItemContents], nil
				break
			end
		end
		if not foundForThisContainedItem then
			return false
		end
	end
	return true
end

function itemMatchesHopperFilters(item, filterItems)
	for _, filterItem in ipairs(filterItems) do
		if hopperItemFilterCheck(item, filterItem) then
			return true
		end
	end
	return false
end

function gatherHopperFilterItems(x, y, z, filterItems)
	local building = helpers.getBuildingAt(x, y, z)
	if not building then
		return
	end
	if building._type ~= df.building_workshopst then
		return
	end
	local customType = df.building_def.find(building.custom_type)
	if not customType then
		return
	end
	if customType.code ~= "WITCH_MACHINE_STORAGE" then
		return
	end
	if not helpers.isBuildingConstructed(building) then
		return
	end

	for _, itemRef in ipairs(building.contained_items) do
		if itemRef.use_mode == 0 and itemRef.item.flags.in_building then
			table.insert(filterItems, itemRef.item)
		end
	end
end

function updateHopper(hopperBuilding, takeFromAbove, giveToBelow, minecartLocations)
	if giveToBelow then
		if helpers.canMachinePassThroughFloor(hopperBuilding.centerx, hopperBuilding.centery, hopperBuilding.z) then
			local belowX, belowY, belowZ = hopperBuilding.centerx, hopperBuilding.centery, hopperBuilding.z - 1
			local belowBuilding = helpers.getBuildingAt(belowX, belowY, belowZ)
			-- Find an item to give
			local itemRefIndex, itemRef
			for i, ref in ipairs(hopperBuilding.contained_items) do
				if ref.use_mode == 0 and hopperCanMoveItem(ref.item) then
					itemRefIndex = i
					itemRef = ref
					break
				end
			end
			local item = itemRef and itemRef.item
			if item then
				local belowBuildingConstructed = belowBuilding and helpers.isBuildingConstructed(belowBuilding)
				if belowBuildingConstructed and belowBuilding._type == df.building_trapst and belowBuilding.trap_type == df.trap_type.TrackStop then
					-- Give item to a minecart, if present
					if minecartLocations[belowX] and minecartLocations[belowX][belowY] and minecartLocations[belowX][belowY][belowZ] then
						local minecart = minecartLocations[belowX][belowY][belowZ][1]
						if minecart then
							helpers.moveItemBuildingToContainer(hopperBuilding, minecart, itemRefIndex)
						end
					end
				elseif belowBuildingConstructed and isBuildingHopperInteractable(belowBuilding) and belowBuilding:getClutterLevel() <= 1 then
					-- Give item to a building
					helpers.moveItemBuildings(hopperBuilding, belowBuilding, itemRefIndex)
				end
			end
		end
	end

	if takeFromAbove then
		local filterItems = {}
		local x, y, z = hopperBuilding.centerx, hopperBuilding.centery, hopperBuilding.z
		gatherHopperFilterItems(x + 1, y, z, filterItems)
		gatherHopperFilterItems(x - 1, y, z, filterItems)
		gatherHopperFilterItems(x, y + 1, z, filterItems)
		gatherHopperFilterItems(x, y - 1, z, filterItems)
		local whitelisting = #filterItems > 0 -- Only start blocking items if a filter item is present

		-- Capacity check by item count, not volume
		local passingItemCount = 0
		for _, itemRef in ipairs(hopperBuilding.contained_items) do
			if itemRef.use_mode == 0 and not itemRef.item.flags.in_building then
				passingItemCount = passingItemCount + 1
			end
		end
		if passingItemCount < consts.hopperMaxItemCapacity then
			local aboveX, aboveY, aboveZ = hopperBuilding.centerx, hopperBuilding.centery, hopperBuilding.z + 1
			if helpers.canMachinePassThroughFloor(aboveX, aboveY, aboveZ) then
				local aboveBuilding = helpers.getBuildingAt(aboveX, aboveY, aboveZ)
				local aboveBuildingConstructed = aboveBuilding and helpers.isBuildingConstructed(aboveBuilding)
				if aboveBuildingConstructed and aboveBuilding._type == df.building_trapst and aboveBuilding.trap_type == df.trap_type.TrackStop then
					if minecartLocations[aboveX] and minecartLocations[aboveX][aboveY] and minecartLocations[aboveX][aboveY][aboveZ] then
						local minecart = minecartLocations[aboveX][aboveY][aboveZ][1]
						if minecart then
							local itemToTakeRefIndex, itemToTakeRef
							for i, ref in ipairs(minecart.general_refs) do
								if ref._type == df.general_ref_contains_itemst then
									itemToTakeRefIndex = i
									itemToTakeRef = ref
									-- Don't break, we want the last item in the list (last in first out)
								end
							end
							if itemToTakeRef then
								local item = itemToTakeRef:getItem()
								if item and hopperCanMoveItem(item) and (not whitelisting or itemMatchesHopperFilters(item, filterItems)) then
									helpers.moveItemContainerToBuilding(minecart, hopperBuilding, itemToTakeRefIndex)
								end
							end
						end
					end
				elseif aboveBuildingConstructed and isBuildingHopperInteractable(aboveBuilding) then
					for i, itemRef in ipairs(aboveBuilding.contained_items) do
						local item = itemRef.item
						-- local canTakeItem = true
						-- if item.flags.in_job then
						-- 	for _, ref in ipairs(item.specific_refs) do
						-- 		if ref.type == df.specific_ref_type.JOB then
						-- 			if dfhack.job.getHolder(ref.data.job) == aboveBuilding then
						-- 				canTakeItem = false
						-- 				break
						-- 			end
						-- 		end
						-- 	end
						-- end
						-- Better to just avoid moving any items that might cause errors
						local canTakeItem = hopperCanMoveItem(item) and (not whitelisting or itemMatchesHopperFilters(item, filterItems))
						if itemRef.use_mode == 0 and canTakeItem then
							helpers.moveItemBuildings(aboveBuilding, hopperBuilding, i)
							break
						end
					end
				end
			end
		end
	end
end

local function onTick()
	local hopperTimer = helpers.getPersistNum("hopperTimer") or 0
	local takeFromAboveNextUpdate = helpers.getPersistBool("hopperTakeFromAboveNextUpdate")
	hopperTimer = hopperTimer - 1
	local timerCompleted = false
	if hopperTimer <= 0 then
		timerCompleted = true
		hopperTimer = consts.hopperRepeatInterval
		helpers.setPersistBool("hopperTakeFromAboveNextUpdate", not takeFromAboveNextUpdate)
	end
	helpers.setPersistNum("hopperTimer", hopperTimer)

	local takeFromAbove, giveToBelow
	if timerCompleted then
		giveToBelow = true
		takeFromAbove = takeFromAboveNextUpdate
	end

	if not (takeFromAbove or giveToBelow) then
		return
	end

	local hoppersToUpdate = {}
	for _, building in ipairs(df.global.world.buildings.other.WORKSHOP_CUSTOM) do
		if not building:isActual() then
			goto continue
		end
		local customType = df.building_def.find(building.custom_type)
		if not customType then
			goto continue
		end
		if customType.code ~= "WITCH_HOPPER" then
			goto continue
		end
		if building:isUnpowered() then
			goto continue
		end
		hoppersToUpdate[#hoppersToUpdate+1] = building
		::continue::
	end

	table.sort(hoppersToUpdate, function(hopperA, hopperB)
		-- Lowest z first, then lowest y (northmost), then lowest x (westmost)

		local ax, ay, az = hopperA.centerx, hopperA.centery, hopperA.z
		local bx, by, bz = hopperB.centerx, hopperB.centery, hopperB.z
		if az ~= bz then
			return az < bz
		end
		if ay ~= by then
			return ay < by
		end
		return ax < bx
	end)

	local minecartLocations = {}
	for _, item in ipairs(df.global.world.items.other.TOOL) do
		if not item.flags.on_ground then
			goto continue
		end
		if not item:isTrackCart() then
			goto continue
		end

		local x, y, z = dfhack.items.getPosition(item)
		if not minecartLocations[x] then
			minecartLocations[x] = {}
		end
		if not minecartLocations[x][y] then
			minecartLocations[x][y] = {}
		end
		if not minecartLocations[x][y][z] then
			minecartLocations[x][y][z] = {}
		end
		table.insert(minecartLocations[x][y][z], item)

	    ::continue::
	end

	for _, hopperBuilding in ipairs(hoppersToUpdate) do
		updateHopper(hopperBuilding, takeFromAbove, giveToBelow, minecartLocations)
	end
end

function enable()
	timekeeping.register("hoppers", onTick)

	buildingHacks.registerBuilding({
		name = "WITCH_HOPPER",
		consume = 10,
		needs_power = 1,
		gears = {
			{x = 0, y = 0}
		},
		animate = {
			isMechanical = true,
			frames = {
				{
					{
						x = 0, y = 0,
						23, 7, 0, 0
					}
				},
				{
					{
						x = 0, y = 0,
						18, 7, 0, 0
					}
				}
			}
		}
	})
end

function disable()
	timekeeping.unregister("hoppers")
	buildingHacks.registerBuilding({name = "WITCH_HOPPER"})
end
