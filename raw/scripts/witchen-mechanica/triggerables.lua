--@ module = true
enableable = true -- Not in the sense of the enable command

local helpers = dfhack.reqscript("witchen-mechanica/helpers")
local signalMechanics = dfhack.reqscript("signal-mechanics")
local buildingHacks = require("plugins.building-hacks")

local funcs = {}

table.insert(funcs, function(building, state) -- Vehicle pusher
	if not helpers.isCustomWorkshopType(building, "WITCH_VEHICLE_PUSHER") then
		return
	end

	if not state then
		return
	end

	if building:isUnpowered() then
		return
	end

	helpers.createMagicPuff(xyz2pos(building.centerx, building.centery, building.z), 10)

	for _, item in ipairs(df.global.world.items.other.TOOL) do
		if not item.flags.on_ground then
			goto continue
		end
		if not item:isTrackCart() then
			goto continue
		end
		local x, y, z = dfhack.items.getPosition(item)
		if not (x and y and z) then
			goto continue
		end
		if z ~= building.z then
			goto continue
		end
		local dx = x - building.centerx
		local dy = y - building.centery
		local adx = math.abs(dx)
		local ady = math.abs(dy)
		if adx + ady == 1 then
			if dfhack.maps.isValidTilePos(x + dx, y + dy, z) then
				dfhack.items.moveToGround(item, xyz2pos(x + dx, y + dy, z))
			end
		end

		::continue::
	end
end)

local function callback(building, state)
	for _, func in ipairs(funcs) do
		func(building, state)
	end
end

function enable()
	signalMechanics.registerNewCallback("witchen-mechanica", callback)

	buildingHacks.registerBuilding({
		name = "WITCH_VEHICLE_PUSHER",
		consume = 15,
		needs_power = 1,
		gears = {
			{x = 0, y = 0}
		},
		animate = {
			isMechanical = true,
			frames = {}
		}
	})
end

function disable()
	signalMechanics.unregisterCallback("witchen-mechanica")

	buildingHacks.registerBuilding({name = "WITCH_VEHICLE_PUSHER"})
end
