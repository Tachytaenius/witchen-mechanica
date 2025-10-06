--@ module = true
enableable = true -- Not in the sense of the enable command

local buildingHacks = require("plugins.building-hacks")
local utils = require("utils")
local customRawTokens = require("custom-raw-tokens")

local consts = dfhack.reqscript("witchen-mechanica/consts")
local helpers = dfhack.reqscript("witchen-mechanica/helpers")
local timekeeping = dfhack.reqscript("witchen-mechanica/timekeeping")

-- TODO: Cache hopper adjacent buildings

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
	if allowedHopperBuildingTypes[building._type] then
		return true
	end
end

function canHopperPassThroughTile(x, y, z)
	-- Return true if open space
	local tiletype = dfhack.maps.getTileType(x, y, z)
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

function hopperCanMoveItem(item)
	local flags = item.flags
	if
		flags.in_building or -- Like displayed on a pedestal
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

function updateHopper(hopperBuilding, takeFromAbove, giveToBelow, minecartLocations)
	if giveToBelow then
		local belowX, belowY, belowZ = hopperBuilding.centerx, hopperBuilding.centery, hopperBuilding.z - 1
		if canHopperPassThroughTile(belowX, belowY, belowZ) then
			local belowBuilding = helpers.getBuildingAt(belowX, belowY, belowZ)
			-- Find an item to give
			local itemRefIndex, itemRef
			for i, ref in ipairs(hopperBuilding.contained_items) do
				if ref.use_mode == 0 then
					itemRefIndex = i
					itemRef = ref
					break
				end
			end
			local item = itemRef:getItem()
			if item and hopperCanMoveItem(item) then
				if belowBuilding and belowBuilding._type == df.building_trapst and belowBuilding.trap_type == df.trap_type.TrackStop then
					-- Give item to a minecart, if present
					if minecartLocations[belowX] and minecartLocations[belowX][belowY] and minecartLocations[belowX][belowY][belowZ] then
						local minecart = minecartLocations[belowX][belowY][belowZ][1]
						if minecart then
							helpers.moveItemBuildingToContainer(hopperBuilding, minecart, itemRefIndex)
						end
					end
				elseif belowBuilding and isBuildingHopperInteractable(belowBuilding) then
					-- Give item to a building
					helpers.moveItemBuildings(hopperBuilding, belowBuilding, itemRefIndex)
				end
			end
		end
	end

	if takeFromAbove then
		-- Capacity check by item count, not volume
		local passingItemCount = 0
		for _, itemRef in ipairs(hopperBuilding.contained_items) do
			if itemRef.use_mode == 0 and not itemRef.item.flags.in_building then
				passingItemCount = passingItemCount + 1
			end
		end
		if passingItemCount < consts.hopperMaxItemCapacity then
			local aboveX, aboveY, aboveZ = hopperBuilding.centerx, hopperBuilding.centery, hopperBuilding.z + 1
			if canHopperPassThroughTile(aboveX, aboveY, aboveZ) then
				local aboveBuilding = helpers.getBuildingAt(aboveX, aboveY, aboveZ)
				if aboveBuilding and aboveBuilding._type == df.building_trapst and aboveBuilding.trap_type == df.trap_type.TrackStop then
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
							local item = itemToTakeRef:getItem()
							if item and hopperCanMoveItem(item) then
								helpers.moveItemContainerToBuilding(minecart, hopperBuilding, itemToTakeRefIndex)
							end
						end
					end
				elseif aboveBuilding and isBuildingHopperInteractable(aboveBuilding) then
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
						canTakeItem = hopperCanMoveItem(item)
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
	if hopperTimer < 0 then
		hopperTimer = consts.hopperTimerLength
		helpers.setPersistBool("hopperTakeFromAboveNextUpdate", not takeFromAboveNextUpdate)
	end
	helpers.setPersistNum("hopperTimer", hopperTimer)

	local takeFromAbove, giveToBelow
	if hopperTimer == 0 then
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
		needs_power = 10,
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
