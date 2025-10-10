--@ module = true
enableable = true -- Not in the sense of the enable command

local buildingHacks = require("plugins.building-hacks")
local utils = require("utils")
local persistTable = require("persist-table")
local customRawTokens = require("custom-raw-tokens")

local consts = dfhack.reqscript("witchen-mechanica/consts")
local timekeeping = dfhack.reqscript("witchen-mechanica/timekeeping")
local helpers = dfhack.reqscript("witchen-mechanica/helpers")

local function ensureTurretSquadsTable()
	local modTable = persistTable.GlobalTable[consts.modKey]
	modTable.turretSquads = modTable.turretSquads or {}
end

local function isTurretBuilding(building)
	if not building:isActual() then
		return false
	end
	local customType = df.building_def.find(building.custom_type)
	if not customType then
		return false
	end
	if customType.code ~= "WITCH_TURRET" then
		return false
	end
	return true
end

function isTurretSquad(squad, alreadyEnsured)
	if not alreadyEnsured then
		ensureTurretSquadsTable()
	end
	return not not persistTable.GlobalTable[consts.modKey].turretSquads[tostring(squad.id)]
end

-- Creating a squad_schedule_entry[12] to insert into the schedule vector is surprisingly hard (in v47) so we have this raw memory access stuff
-- Hopefully sufficiently cross-platform!
-- TODO: Test for 32-bit DF(Hack) and also test on Windows
-- TODO: Maybe search for any remaining crashes in the turret systems
local function newScheduleBytes()
	local months = 12
	local entrySize = 64
	local bytes = df.new("uint8_t", months * entrySize)
	local _, bytesAddr = df.sizeof(bytes)
	for i = 0, months * entrySize - 1 do
		bytes[i] = 0
	end
	for i = 0, months - 1 do
		local stringStart = bytesAddr + i * entrySize
		local nameString = df.new("string")
		local nameStringSize, nameStringAddr = df.sizeof(nameString)
		dfhack.internal.memmove(stringStart, nameStringAddr, nameStringSize)
	end
	return bytes
end
local function fillSquadSchedules(squad)
	local schedule = squad.schedule
	local count = #df.global.ui.alerts.list
	schedule:resize(count)

	for scheduleVecIndex = 0, count - 1 do
		-- I believe a vec is 3 * 8 bytes: beginning address, end (actual length) address, and end of capacity (resize) address
		-- Make new squad_schedule_entry[12] and get put its address somewhere in memory for us to copy from
		local scheduleBytes = newScheduleBytes()
		local _, scheduleBytesAddress = df.sizeof(scheduleBytes)
		local addressBytes = df.new("uint8_t", 8)
		for i = 0, 7 do
			addressBytes[i] = scheduleBytesAddress >> (i * 8) & 0xFF
		end
		-- Get address in the schedule vec's pointers to set
		local scheduleAsAddresses = df.reinterpret_cast("uint64_t", schedule)
		local scheduleVecStart = scheduleAsAddresses[0]
		local destination = scheduleVecStart + scheduleVecIndex * 8
		-- Copy address of new squad_schedule_entry[12] into the first element of the vector
		dfhack.internal.memmove(destination, addressBytes, 8)
		-- Delete addressBytes since we no longer need it
		addressBytes:delete()
	end
end
function newTurretSquad(displayName, entity)
	local squad = df.squad:new()
	squad.id = df.global.squad_next_id
	df.global.squad_next_id = df.global.squad_next_id + 1
	squad.entity_id = entity.id
	squad.unk_1 = -1 -- Army controller id
	squad.alias = displayName
	entity.squads:insert("#", squad.id)
	df.global.world.squads.all:insert("#", squad)

	fillSquadSchedules(squad)

	ensureTurretSquadsTable()
	persistTable.GlobalTable[consts.modKey].turretSquads[tostring(squad.id)] = "true"
end

function getSelectedTurret()
	-- Works with squad menu cursor
	local x, y, z = pos2xyz(df.global.cursor)
	if not (x and y and z) then
		return nil
	end

	local building = helpers.getBuildingAt(x, y, z)
	if building and isTurretBuilding(building) then
		return building
	end
	return nil
end

function isTurretInSquad(turret, squad)
	for _, room in ipairs(squad.rooms) do
		if room.mode[consts.squadRoomIsTurretFlagKey] and room.building_id == turret.id then
			return true
		end
	end
	return false
end

function getSquadTurrets(squad)
	local ret = {}
	for _, room in ipairs(squad.rooms) do
		if room.mode[consts.squadRoomIsTurretFlagKey] then
			local building = df.building.find(room.building_id)
			if isTurretBuilding(building) then
				ret[#ret+1] = building
			end
		end
	end
	return ret
end

function getTurretSquads(turret)
	local ret = {}
	for _, squad in ipairs(df.global.world.squads.all) do
		if isTurretInSquad(turret, squad) then
			ret[#ret+1] = squad
		end
	end
	return ret
end

function addSelectedTurretToSelectedSquad()
	local turret = getSelectedTurret()
	if not turret then
		return
	end

	local squad = helpers.getSelectedSquad()
	if not squad then
		return
	end

	if isTurretInSquad(turret, squad) then
		return
	end

	squad.rooms:insert("#", {new = true,
		building_id = turret.id,
		mode = {
			[consts.squadRoomIsTurretFlagKey] = true
		}
	})
end

function removeSelectedTurretFromSelectedSquad()
	local turret = getSelectedTurret()
	if not turret then
		return
	end

	local squad = helpers.getSelectedSquad()
	if not squad then
		return
	end

	if not isTurretInSquad(turret, squad) then
		return
	end

	for i, room in ipairs(squad.rooms) do
		if room.mode[consts.squadRoomIsTurretFlagKey] and room.building_id == turret.id then
			squad.rooms:erase(i)
			room:delete()
			break
		end
	end
end

local function getDistance(aPos, bPos)
	return math.sqrt(
		(bPos.x - aPos.x) ^ 2 +
		(bPos.y - aPos.y) ^ 2 +
		(bPos.z - aPos.z) ^ 2
	)
end

local function canTurretFireAmmo(turret, item)
	if item._type ~= df.item_ammost then
		return false
	end
	return customRawTokens.getToken(item, "WITCHEN_MECHANICA_HEXED_TURRET_FIREABLE")
end

local function getTurretStats(turret, item)
	-- TODO
	return {
		range = 20,
		hitRating = 100, -- TODO: Work out appropriate ranges?
		velocity = 1000 -- TODO?
	}
end

local function getTurretShootPos(turret)
	return xyz2pos(turret.x1 + 2, turret.y1 + 2, turret.z)
end

local function fireTurret(turret, unit)
	local ammoStack
	for _, item in ipairs(turret.contained_items) do
		if item.use_mode == 0 and canTurretFireAmmo(turret, item.item) then
			ammoStack = item.item
			break
		end
	end
	if not ammoStack then
		return
	end

	local ammoItem
	if ammoStack.stack_size > 1 then
		ammoItem = ammoStack:splitStack(1, true)
		ammoItem.flags.weight_computed = false
		ammoItem:categorize(true)
	else
		ammoItem = ammoStack
	end

	local ammoItemIndex
	for i, item in ipairs(turret.contained_items) do
		if item.item == ammoItem then
			ammoItemIndex = i
			break
		end
	end
	assert(ammoItemIndex, "Something has gone wrong!!")

	local turretShootPos = getTurretShootPos(turret)
	local unitPos = xyz2pos(dfhack.units.getPosition(unit))

	local stats = getTurretStats(turret)
	for i, ref in ipairs(ammoItem.general_refs) do
		if ref._type == df.general_ref_building_holderst then
			turret.contained_items:erase(ammoItemIndex)
			ammoItem.general_refs:erase(i)
			ammoItem:moveToGround(dfhack.items.getPosition(ammoItem))
			break
		end
	end

	local projectile = dfhack.items.makeProjectile(ammoItem)
	projectile.origin_pos = utils.clone(turretShootPos)
	projectile.target_pos = utils.clone(unitPos)
	projectile.cur_pos = utils.clone(turretShootPos)
	projectile.prev_pos = utils.clone(turretShootPos)
	projectile.fall_threshold = stats.range
	projectile.unk22 = stats.velocity
	projectile.fall_counter = 0
	projectile.bow_id = -1 -- Unless we want to specify a gun item id from the building
	projectile.hit_rating = stats.hitRating

	local flowDimension, flowTypeName, materialArgA, materialArgB, materialArgC, materialArgD =
		customRawTokens.getToken(projectile.item, "WITCHEN_MECHANICA_HEXED_TURRET_SHOOT_FLOW")
	flowDimension = tonumber(flowDimension) or 0
	-- TODO: Prevent flow from spawning inside of tiles and creating spatter (which might cause units to clean in front of the turret and get killed)
	if flowDimension > 0 then
		local matToken = table.concat({materialArgA, materialArgB, materialArgC, materialArgD}, ":") -- Avoid passing trailing nils to matinfo.find as it will error
		local matInfo = dfhack.matinfo.find(matToken)
		local matType, matIndex = matInfo and matInfo.type or -1, matInfo and matInfo.index or -1
		local flowPosition = {}
		do
			local opos, tpos = projectile.origin_pos, projectile.target_pos
			local x, y, z = tpos.x-opos.x, tpos.y-opos.y, tpos.z-opos.z
			local mag = math.sqrt(x^2+y^2+z^2)
			if mag > 0 then 
				x, y, z = x * consts.smokeEffectDistanceFromFirer / mag, y * consts.smokeEffectDistanceFromFirer / mag, z * consts.smokeEffectDistanceFromFirer / mag
				flowPosition.x, flowPosition.y, flowPosition.z = math.floor(x+0.5) + opos.x, math.floor(y+0.5) + opos.y, math.floor(z+0.5) + opos.z
			else
				flowPosition.x, flowPosition.y, flowPosition.z = opos.x, opos.y, opos.z
			end
		end
		dfhack.maps.spawnFlow(flowPosition, df.flow_type[flowTypeName], matType, matIndex, flowDimension)
	end
end

local function handleTurret(turretBuilding, killList)
	if #killList == 0 then
		return
	end

	local shootPos = getTurretShootPos(turretBuilding)

	local closestUnit, closestUnitDistance
	for _, unit in ipairs(killList) do
		if dfhack.units.isKilled(unit) then
			goto continue
		end
		if dfhack.units.isHidden(unit) then -- TODO: Anti-sneak upgrade?
			goto continue
		end

		local x, y, z = dfhack.units.getPosition(unit)
		if not (x and y and z) then
			goto continue
		end

		local unitPos = xyz2pos(x, y, z)
		local unitDistance = getDistance(shootPos, unitPos)

		if not closestUnit or unitDistance < closestUnitDistance then
			closestUnit = unit
			closestUnitDistance = unitDistance
		end

		::continue::
	end

	if not closestUnit then
		return
	end

	fireTurret(turretBuilding, closestUnit)
end

local function onTick()
	ensureTurretSquadsTable()

	local turretsToHandle = {}

	for _, squad in ipairs(df.global.world.squads.all) do
		if not isTurretSquad(squad, true) then
			goto continue
		end

		local foundUnitIds = {}
		local killList = {}
		for _, order in ipairs(squad.orders) do
			if order._type ~= df.squad_order_kill_listst then
				goto continue
			end
			for _, unitId in ipairs(order.units) do
				if foundUnitIds[unitId] then
					goto continue
				end
				foundUnitIds[unitId] = true

				local unit = df.unit.find(unitId)
				if not unit then
					goto continue
				end

				killList[#killList+1] = unit

				::continue::
			end
		    ::continue::
		end

		if #killList == 0 then
			goto continue
		end

		for _, room in ipairs(squad.rooms) do
			if not room.mode[consts.squadRoomIsTurretFlagKey] then
				goto continue
			end

			local building = df.building.find(room.building_id)
			if not building then
				goto continue
			end

			if not isTurretBuilding(building) then
				goto continue
			end
			if building:isUnpowered() then
				goto continue
			end

			-- Don't allow multiple squads to fire one turret at the same time
			local already = false
			for _, turretInfo in ipairs(turretsToHandle) do
				if turretInfo.turret == building then
					already = true
					break
				end
			end
			if not already then
				turretsToHandle[#turretsToHandle+1] = {turret = building, list = killList}
			end

		    ::continue::
		end

		::continue::
	end

	for _, turretInfo in ipairs(turretsToHandle) do
		handleTurret(turretInfo.turret, turretInfo.list)
	end
end

function enable()
	timekeeping.register("turrets", onTick)
	buildingHacks.registerBuilding({
		name = "WITCH_TURRET",
		consume = 100,
		needs_power = 100,
		gears = {
			{x = 2, y = 4}
		},
		animate = {
			isMechanical = true,
			frames = {
				{
					{
						x = 2, y = 4,
						15, 7, 0, 0
					}
				},
				{
					{
						x = 2, y = 4,
						42, 7, 0, 0
					}
				}
			}
		}
	})
end

function disable()
	timekeeping.unregister("turrets")
	buildingHacks.registerBuilding({name = "WITCH_TURRET"})
end
