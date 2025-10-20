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
	helpers.ensurePersistStorage()
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
-- Credit to SilasD for this version of the idea
-- TODO: Maybe search for any remaining crashes in the turret systems
local function newSchedule(positionCount)
	-- Returns an array of 12 instances of a populated df.squad_schedule_entry
	-- The return type is df.squad_schedule_entry, not df.squad_schedule_entry[12]

	local months = 12
	local entrySize = df.squad_schedule_entry:sizeof()
	local bytesSize = months * entrySize
	local bytes = df.new("uint8_t", bytesSize)
	for i = 0, bytesSize - 1 do
		bytes[i] = 0
	end

	local squadScheduleEntries = df.reinterpret_cast(df.squad_schedule_entry, bytes)
	for i = 0, months - 1 do
		local assignments = {}
		for _=1, positionCount do
			table.insert(assignments, {new = true, value = -1})
		end

		local tempSquadScheduleEntry = df.squad_schedule_entry:new()
		tempSquadScheduleEntry:assign({
			new = true,
			order_assignments = assignments
		})

		local thisSquadScheduleEntry = squadScheduleEntries:_displace(i)
		local useAssign = false -- assign crashes on my machine so we will use memmove
		if useAssign then
			thisSquadScheduleEntry:assign(tempSquadScheduleEntry)
		else
			dfhack.internal.memmove(thisSquadScheduleEntry, tempSquadScheduleEntry, df.squad_schedule_entry:sizeof())
		end
		-- Don't delete tempSquadScheduleEntry, let it leak
	end
	return squadScheduleEntries
end
local function fillSquadSchedules(squad)
	local count = #df.global.ui.alerts.list
	squad.schedule:resize(0) -- Clear schedule in case there were members. If there were members then this will leak memory, but there shouldn't be any anyway
	squad.schedule:resize(count)

	for scheduleVecIndex = 0, count - 1 do
		local schedule = newSchedule(#squad.positions)
		local _, newScheduleAddress = schedule:sizeof()

		-- A vector is 3 pointers: beginning address, end (actual length) address, and end of capacity (resize) address
		-- Casting one as uint64_t or uint32_t lets us get raw access to those pointers
		local uintSize = squad.schedule:sizeof() == 24 and "uint64_t" or "uint32_t" -- Depending on 64-bit or 32-bit DF (32-bit was tested (on Linux) and worked)
		local vec = df.reinterpret_cast(uintSize, squad.schedule)
		-- Get the first pointer from the vector
		local beginningAddress = vec.value
		-- Cast the number into a useful pointer type
		beginningAddress = df.reinterpret_cast(uintSize, beginningAddress)

		beginningAddress[scheduleVecIndex] = newScheduleAddress
	end
end
function newTurretSquad(displayName, entity)
	local squad = df.squad:new()
	squad.id = df.global.squad_next_id
	df.global.squad_next_id = df.global.squad_next_id + 1
	squad.entity_id = entity.id
	squad.unk_1 = -1 -- Army controller id
	squad.alias = displayName
	fillSquadSchedules(squad)

	ensureTurretSquadsTable()
	persistTable.GlobalTable[consts.modKey].turretSquads[tostring(squad.id)] = "true"

	df.global.world.squads.all:insert("#", squad)
	entity.squads:insert("#", squad.id)
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

local function canTurretFireAmmo(turret, item)
	if item._type ~= df.item_ammost then
		return false
	end
	return customRawTokens.getToken(item, "WITCHEN_MECHANICA_HEX_TURRET_FIREABLE")
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

	-- Move ammo to ground
	for i, ref in ipairs(ammoItem.general_refs) do
		if ref._type == df.general_ref_building_holderst then
			turret.contained_items:erase(ammoItemIndex)
			ammoItem.general_refs:erase(i)
			ammoItem:moveToGround(dfhack.items.getPosition(ammoItem))
			break
		end
	end

	-- Make projectile
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

	-- Set cooldown
	helpers.setNumberInFlags(turret.machine.flags, consts.turretCooldownTimerLength, consts.turretCooldownMachineInfoBitsStart, consts.turretCooldownMachineInfoBitsEnd)

	-- Spawn flow
	-- In this part of the code we used to just spawn a flow with material determined by the item, now we are also spawning general magic flow that many things in this mod will do
	-- So it may look a bit odd
	local flowDimension, flowTypeName, materialArgA, materialArgB, materialArgC, materialArgD =
		customRawTokens.getToken(projectile.item, "WITCHEN_MECHANICA_HEX_TURRET_SHOOT_FLOW")
	flowDimension = tonumber(flowDimension) or 0
	local matToken = table.concat({materialArgA, materialArgB, materialArgC, materialArgD}, ":") -- Avoid passing trailing nils to matinfo.find as it will error
	local matInfo = dfhack.matinfo.find(matToken)
	local matType, matIndex = matInfo and matInfo.type or -1, matInfo and matInfo.index or -1
	local flowPosition = {}
	do
		-- We prevent flow from spawning inside of tiles and creating spatter (which might cause units to clean in front of the turret and get killed) by ignoring z.
		local smokeEffectDistanceFromFirer = 1.9 -- The flow will be spawned within the building's tiles, which is definitely safe.
		local opos, tpos = projectile.origin_pos, projectile.target_pos
		flowPosition.z = opos.z
		local x, y = tpos.x-opos.x, tpos.y-opos.y
		local mag = math.sqrt(x^2+y^2)
		if mag > 0 then
			x, y = x * smokeEffectDistanceFromFirer / mag, y * smokeEffectDistanceFromFirer / mag
			flowPosition.x, flowPosition.y = math.floor(x+0.5) + opos.x, math.floor(y+0.5) + opos.y
		else
			flowPosition.x, flowPosition.y = opos.x, opos.y
		end
	end
	if flowDimension > 0 then
		dfhack.maps.spawnFlow(flowPosition, df.flow_type[flowTypeName], matType, matIndex, flowDimension)
	end
	helpers.createMagicPuff(flowPosition, consts.turretMagicPuffSize)
end

local function handleTurret(turretBuilding, killList)
	local cooldownTimer = helpers.getNumberInFlags(turretBuilding.machine.flags, consts.turretCooldownMachineInfoBitsStart, consts.turretCooldownMachineInfoBitsEnd)
	if cooldownTimer ~= 0 then
		cooldownTimer = math.max(0, cooldownTimer - 1)
		helpers.setNumberInFlags(turretBuilding.machine.flags, cooldownTimer, consts.turretCooldownMachineInfoBitsStart, consts.turretCooldownMachineInfoBitsEnd)
		return
	end

	if #killList == 0 then
		return
	end

	local shootPos = getTurretShootPos(turretBuilding)

	local closestUnit, closestUnitDistance
	for _, unit in ipairs(killList) do
		if dfhack.units.isKilled(unit) then
			goto continue
		end
		if dfhack.units.isHidden(unit) then
			goto continue
		end

		local x, y, z = dfhack.units.getPosition(unit)
		if not (x and y and z) then
			goto continue
		end

		local unitPos = xyz2pos(x, y, z)
		local unitDistance = helpers.getDistance(shootPos, unitPos)

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
		consume = 300,
		needs_power = 300,
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
