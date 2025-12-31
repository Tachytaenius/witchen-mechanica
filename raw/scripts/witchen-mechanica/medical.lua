--@module = true
enableable = true

-- This was all made for and tested with the following medical materials:
-- Ingested WITCH_MEDICATION_ANALGESIC
-- Inhaled/ingested/injected WITCH_MEDICATION_GENERAL_ANAESTHETIC
-- Contact/injected WITCH_MEDICATION_LOCALISED_ANAESTHETIC

local consts = dfhack.reqscript("witchen-mechanica/consts")
local events = dfhack.reqscript("witchen-mechanica/events")
local timekeeping = dfhack.reqscript("witchen-mechanica/timekeeping")
local helpers = dfhack.reqscript("witchen-mechanica/helpers")

function applyMaterial(
	unit,
	locationType, -- "contact", "injection", "inhalation", or "ingestion"
	matType, matIndex,
	amount,
	-- For location == "contact" or location == "injected":
	spatterAmount, bodyPartId, state, evaporates, temperatureWhole, temperatureFraction
)
	-- Evaporates is "does not contaminate tile when washed away"

	-- Makes assumptions. Does not handle anything with delay, size_dilutes, muscular/vascular only, etc.
	-- In other words is not likely to be 1:1 with all DF spatter syndrome behaviour.
	-- Apply spatter
	if locationType == "contact" then
		unit.body.spatters:insert("#", {new = true,
			mat_type = matType,
			mat_index = matIndex,
			mat_state = state,
			temperature = {
				whole = temperatureWhole,
				fraction = temperatureFraction
			},
			size = spatterAmount,
			base_flags = {
				evaporates = evaporates
			},
			body_part_id = bodyPartId,
			flags = {
				water_soluble = true -- Name was changed to external in future DFHack versions
			}
		})
	end

	-- Add (if applicable) syndrome(s)
	local material = dfhack.matinfo.decode(matType, matIndex).material
	for _, syndrome in ipairs(material.syndrome) do
		if locationType == "contact" and not syndrome.flags.SYN_CONTACT then
			goto continue
		elseif locationType == "injected" and not syndrome.flags.SYN_INJECTED then
			goto continue
		elseif locationType == "inhaled" and not syndrome.flags.SYN_INHALED then
			goto continue
		elseif locationType == "ingested" and not syndrome.flags.SYN_INGESTED then
			goto continue
		end

		local syndromeInstance, newlyAdded = helpers.tryAddSyndrome(unit, syndrome)

		for symptomI, symptomRaw in ipairs(syndrome.ce) do
			local symptom = syndromeInstance.symptoms[symptomI]
			if (locationType == "contact" or locationType == "injected") and symptomRaw.flags.LOCALIZED then
				-- Increase syndrome symptom intensity on the body part's layers
				local bodyPart = unit.body.body_plan.body_parts[bodyPartId]
				for layerId = 0, #bodyPart.layers - 1 do
					-- The list is not sorted
					local found = false
					for targetI = 0, #symptom.target_bp - 1 do
						if
							symptom.target_bp[targetI] == bodyPartId and
							symptom.target_layer[targetI] == layerId
						then
							-- NOTE: The syndrome amount is duplicated across all layers in the body part and not divided
							symptom.target_quantity[targetI] = symptom.target_quantity[targetI] + amount
							found = true
							break
						end
					end
					if not found then
						symptom.target_bp:insert("#", bodyPartId)
						symptom.target_layer:insert("#", layerId)
						symptom.target_quantity:insert("#", amount)
						symptom.target_delay:insert("#", 0)
						symptom.target_ticks:insert("#", 0)
					end
				end
			else
				symptom.quantity = symptom.quantity + amount
			end
		end

	    ::continue::
	end
end

function getMedicationUses(matType, matIndex)
	local flags = {
		contact = "SYN_CONTACT",
		injected = "SYN_INJECTED",
		inhaled = "SYN_INHALED",
		ingested = "SYN_INGESTED"
	}

	local info = {
		contact = {}, injected = {}, inhaled = {}, ingested = {}
	}

	local syndromes = dfhack.matinfo.decode(matType, matIndex).material.syndrome
	for typeName, typeTable in pairs(info) do
		typeTable.noOtherSyndromes = true

		typeTable.localPainRelief = false
		typeTable.internalPainRelief = false
		typeTable.generalAnaesthetic = false

		local flag = flags[typeName]

		for _, syndrome in ipairs(syndromes) do
			if not syndrome.flags[flag] then
				goto continue
			end

			if #syndrome.syn_class == 1 then
				local class = syndrome.syn_class[0].value
				-- More types can be supported if needed. This is not designed to be a super-flexible system!
				if class == "WITCH_MEDICATION_LOCALISED_ANAESTHETIC" then
					typeTable.localPainRelief = true
				elseif class == "WITCH_MEDICATION_ANALGESIC" then
					typeTable.internalPainRelief = true
				elseif class == "WITCH_MEDICATION_GENERAL_ANAESTHETIC" then
					typeTable.generalAnaesthetic = true
				else
					typeTable.noOtherSyndromes = false
				end
			else
				typeTable.noOtherSyndromes = false
			end

		    ::continue::
		end
	end

	return info
end

function medicationHasUse(matType, matIndex, use)
	local uses = getMedicationUses(matType, matIndex)
	-- Priority order is: contact, ingestion, injection, and inhalation
	for _, applicationType in ipairs(consts.applicationTypePriority) do
		local info = uses[applicationType]
		if info[use] and info.noOtherSyndromes then
			return applicationType
		end
	end
	return nil
end

function doesUnitHaveMedicalSyndromeAlready(unit, class, symptomType, bodyPartId, layerIndex)
	-- Specify no body part id to check for non-localised syndrome instances
	for _, syndromeInstance in ipairs(unit.syndromes.active) do
		local syndrome = df.syndrome.find(syndromeInstance.type)
		local rightClass = false
		for _, classStr in ipairs(syndrome.syn_class) do
			if classStr.value == class then
				rightClass = true
				break
			end
		end
		if not rightClass then
			goto continue
		end

		for symptomI, creatureEffect in ipairs(syndrome.ce) do
			if creatureEffect._type ~= df[symptomType] then
				goto continue
			end
			local symptomInstance = syndromeInstance.symptoms[symptomI]
			if not (bodyPartId and layerIndex) then
				-- Non-localised, whole-unit creature effect
				if symptomInstance.quantity > 0 then
					return true
				end
			else
				for targetI = 0, #symptomInstance.target_bp - 1 do
					if
						symptomInstance.target_bp[targetI] == bodyPartId and
						symptomInstance.target_layer[targetI] == layerIndex
					then
						-- Found body part and layer for this symptom
						if symptomInstance.target_quantity[targetI] > 0 then
							return true
						else
							break -- Assume body part and layer pair is not elsewhere in the symptom's lists
						end
					end
				end
			end
		    ::continue::
		end

	    ::continue::
	end

	return false
end

function getMedicationNeeds(unit)
	-- Get pain totals
	local bodyParts = unit.body.body_plan.body_parts
	local needs = {
		externalPartsTotalPain = {totalThisCategory = 0},
		internalPartsTotalPain = {totalThisCategory = 0},
		totalPainByPartAndLayer = {},
		totalPain = 0
	}
	local totalPainByPartAndLayer = needs.totalPainByPartAndLayer
	for _, wound in ipairs(unit.body.wounds) do
		needs.totalPain = needs.totalPain + wound.pain
		for _, part in ipairs(wound.parts) do
			local partId = part.body_part_id
			local layerIdx = part.layer_idx

			needs.totalPain = needs.totalPain + part.pain

			local t = bodyParts[part.body_part_id].flags.INTERNAL and
				needs.internalPartsTotalPain or
				needs.externalPartsTotalPain
			t[partId] = (t[partId] or 0) + part.pain
			t.totalThisCategory = t.totalThisCategory + part.pain

			totalPainByPartAndLayer[partId] = totalPainByPartAndLayer[partId] or {}
			totalPainByPartAndLayer[partId][layerIdx] = (totalPainByPartAndLayer[layerIdx] or 0) + part.pain
		end
	end

	-- Get pain relief needs
	needs.needsInternalPainRelief = needs.internalPartsTotalPain.totalThisCategory >= consts.internalAnalgesicPainThreshold and not doesUnitHaveMedicalSyndromeAlready(unit, "WITCH_MEDICATION_ANALGESIC", "creature_interaction_effect_reduce_painst")
	needs.needsGeneralAnaesthetic = needs.totalPain >= consts.generalAnaestheticPainThreshold and not doesUnitHaveMedicalSyndromeAlready(unit, "WITCH_MEDICATION_GENERAL_ANAESTHETIC", "creature_interaction_effect_reduce_painst")
	needs.localisedAnaestheticNeedInfo = {}
	for i, t in ipairs({needs.externalPartsTotalPain, needs.internalPartsTotalPain}) do
		local internal = i == 2
		for partId, pain in pairs(t) do
			if type(partId) ~= "number" then
				goto continue
			end
			if pain >= consts.bodyPartLocalAnaestheticPainThreshold then
				-- Pain may be over the threshold, but now check against syndromes to see whether any medical pain relief syndromes point to the affected layers and remove their contribution if so
				local unfilteredTotalPain = 0 -- For debug
				local filteredTotalPain = 0 -- Pain without considering preexisting pain relief
				assert(totalPainByPartAndLayer[partId], "witchen-mechanica: Missing info?")
				for layerIdx, layerPain in pairs(totalPainByPartAndLayer[partId]) do
					unfilteredTotalPain = unfilteredTotalPain + layerPain
					if not doesUnitHaveMedicalSyndromeAlready(unit, "WITCH_MEDICATION_LOCALISED_ANAESTHETIC", "creature_interaction_effect_reduce_painst", partId, layerIdx) then
						filteredTotalPain = filteredTotalPain + layerPain
					end
				end
				assert(unfilteredTotalPain == pain, "witchen-mechanica: Inconsistent info?")

				if filteredTotalPain >= consts.bodyPartLocalAnaestheticPainThreshold then
					table.insert(needs.localisedAnaestheticNeedInfo, {partId = partId, pain = filteredTotalPain, needLocalisedAnaesthetic = true, internal = internal})
				end
			end
		    ::continue::
		end
		break -- In the end we won't assess internal body part pains for local anaesthesia since that is intended to be external only. Initially the code was written to do so
	end
	table.sort(needs.localisedAnaestheticNeedInfo, function(a, b)
		if a.pain ~= b.pain then
			return a.pain < b.pain
		end
		if a.internal ~= b.internal then
			return not a.internal
		end
		return a.partId < b.partId
	end)

	local internalPainHigher = needs.internalPartsTotalPain.totalThisCategory > needs.externalPartsTotalPain.totalThisCategory

	-- Get needs in order of priority
	needs.priority = {}
	if needs.needsGeneralAnaesthetic then
		table.insert(needs.priority, {type = "generalAnaesthetic"})
	end
	if internalPainHigher and needs.needsInternalPainRelief then -- If higher then do before localised
		table.insert(needs.priority, {type = "internalPainRelief"})
	end
	if #needs.localisedAnaestheticNeedInfo > 0 then
		table.insert(needs.priority, {
			type = "localPainRelief",
			bodyPart = needs.localisedAnaestheticNeedInfo[1].partId
		})
	end
	if not internalPainHigher and needs.needsInternalPainRelief then -- If not high then do after localised
		table.insert(needs.priority, {type = "internalPainRelief"})
	end

	return needs
end

function selectRequiredMedication(needs, position)
	local toUse = {}
	local toUsePriorityIndex

	local availableStorage = helpers.sortPathableBuildingsInSetByDistance(df.global.world.buildings.other.ANY_HOSPITAL_STORAGE, position)
	for _, building in ipairs(availableStorage) do
		for _, contained in ipairs(building.contained_items) do
			if contained.use_mode ~= 0 then
				goto continue
			end

			if not helpers.canUseItem(contained.item) then
				goto continue
			end

			if not df.item_flaskst:is_instance(contained.item) then
				goto continue
			end

			for _, ref in ipairs(contained.item.general_refs) do
				if ref._type ~= df.general_ref_contains_itemst then
					goto continue
				end

				local containedItem = ref:getItem()
				if not containedItem then
					goto continue
				end

				if not df.item_liquid_miscst:is_instance(containedItem) then
					goto continue
				end

				for i = 1, (toUsePriorityIndex and (toUsePriorityIndex - 1) or #needs.priority) do -- If not already found medication for a need then iterate over all of them, else iterate from highest priority to the next most important priority
					assert(i ~= toUsePriorityIndex, "Still searching for medication at a priority that we've already found medication at?")
					local need = needs.priority[i]
					if medicationHasUse(containedItem.mat_type, containedItem.mat_index, need.type) then
						toUse = {} -- Replace any previous medication items (for the previous priority). NOTE: Was originally intended to gather up a required amount over multiple items, but that's scrapped.
						table.insert(toUse, contained.item) -- The flask, not the medication inside it
						toUsePriorityIndex = i
						break
					end
				end

				::continue::
			end

			::continue::
		end
	end

	return toUse
end

function createAdministerMedicationJob(patient, administerer, toUse)
	if not helpers.canBeAddedToJob(administerer) then
		return false, "administererCantJob"
	end

	local patientPos = xyz2pos(dfhack.units.getPosition(patient))
	if not patientPos then
		return false, "patientPositionUnknown"
	end
	local administererPos = xyz2pos(dfhack.units.getPosition(administerer))
	if not administererPos then
		return false, "administererPositionUnknown"
	end
	if not dfhack.maps.canWalkBetween(patientPos, administererPos) then
		return false, "noPathToPatient"
	end

	if #toUse == 0 then
		return false, "noMedicationSelected"
	end

	local bedBuilding = helpers.getBuildingAt(dfhack.units.getPosition(patient))
	if not bedBuilding or bedBuilding._type ~= df.building_bedst then
		return false, "notSafelyInBed"
	end

	local reactionName = consts.administerMedicationReactionName
	local reaction = helpers.findReactionByName(reactionName)
	if not reaction then
		dfhack.printerr("No administer medication reaction found; is the mod installed properly?")
		return false, "noReaction"
	end
	local reactionId = reaction.index

	local job = df.job:new()

	job.general_refs:insert("#", {
		new = df.general_ref_unit_patientst,
		unit_id = patient.id
	})

	job.pos.x = bedBuilding.centerx
	job.pos.y = bedBuilding.centery
	job.pos.z = bedBuilding.z

	job.job_type = df.job_type.CustomReaction
	job.reaction_name = reactionName
	job.job_items:insert("#", {new = true, reagent_index = 0, reaction_id = reactionId}) -- Assume reagent index 0 to be the preserver

	for _, medicationVial in ipairs(toUse) do
		helpers.addItemToJob(job, medicationVial, df.job_item_ref.T_role.Reagent, 0, -1)
	end

	-- Without this, the unit picks up a random item!
	administerer.path.goal = df.unit_path_goal.GrabJobResources
	administerer.path.path.x:resize(0)
	administerer.path.path.y:resize(0)
	administerer.path.path.z:resize(0)
	administerer.path.dest.x, administerer.path.dest.y, administerer.path.dest.z =
		dfhack.items.getPosition(toUse[1])

	job.flags.do_now = true
	job.flags.fetching = true
	job.items[0].is_fetching = 1

	job.completion_timer = 0

	-- A building to "perform the reaction" at is required by the game
	local buildingRef = df.general_ref_building_holderst:new()
	buildingRef.building_id = bedBuilding.id
	job.general_refs:insert("#", buildingRef)
	bedBuilding.jobs:insert("#", job)

	dfhack.job.linkIntoWorld(job, true)
	helpers.addJobWorker(job, administerer)
	return true
end

function createStoreInHospitalJob(item, worker)
	if not helpers.canBeAddedToJob(worker) then
		return false
	end
	if not helpers.canUseItem(item) then
		return false
	end
	local workerPos = xyz2pos(dfhack.units.getPosition(worker))
	if not workerPos then
		return
	end
	local boxes = helpers.sortPathableBuildingsInSetByDistance(df.global.world.buildings.other.ANY_HOSPITAL_STORAGE, workerPos)
	local box
	for _, potentialBox in ipairs(boxes) do
		if true then -- Make a capacity check or whatever
			box = potentialBox
			break
		end
	end
	if not box then
		return false
	end
	local job = df.job:new()
	job.general_refs:insert("#", {
		new = df.general_ref_building_destinationst,
		building_id = box.id
	})
	job.flags.store_item = true
	job.pos.x = box.centerx
	job.pos.y = box.centery
	job.pos.z = box.z
	helpers.addItemToJob(job, item, df.job_item_ref.T_role.Hauled, -1, -1)
	job.job_type = df.job_type.StoreItemInHospital
	dfhack.job.linkIntoWorld(job, true)
	helpers.addJobWorker(job, worker)
	return true
end

local function administerJobOnComplete(job)
	if not (
		job.job_type == df.job_type.CustomReaction and
		job.reaction_name == consts.administerMedicationReactionName
	) then
		return
	end

	local patientRef = dfhack.job.getGeneralRef(job, df.general_ref_type.UNIT_PATIENT)
	local patient = patientRef:getUnit()

	local possibleUses = {}
	local preservedReagentItems = {}

	local itemsToDelete = {}
	local function finish()
		for _, item in ipairs(itemsToDelete) do
			dfhack.items.remove(item)
		end
		local administerer = dfhack.job.getWorker(job)
		if preservedReagentItems[1] and administerer then
			createStoreInHospitalJob(preservedReagentItems[1], administerer)
		end
	end

	for _, jobItemRef in ipairs(job.items) do
		if jobItemRef.role ~= df.job_item_ref.T_role.Reagent then
			goto continue
		end
		if jobItemRef.job_item_idx == -1 then
			goto continue
		end
		local jobItem = job.job_items[jobItemRef.job_item_idx]
		if jobItem.reagent_index == -1 then
			goto continue
		end
		local reaction = df.global.world.raws.reactions.reactions[jobItem.reaction_id]
		local reagent = reaction.reagents[jobItem.reagent_index]
		if not reagent.flags.PRESERVE_REAGENT then
			goto continue
		end
		local item = jobItemRef.item -- Preserved (job is a copy, would deleted items be dangling pointers?)
		table.insert(preservedReagentItems, jobItemRef.item)

		for _, ref in ipairs(item.general_refs) do
			if ref._type ~= df.general_ref_contains_itemst then
				goto continue
			end

			local containedItem = ref:getItem()
			if not containedItem then
				goto continue
			end

			if not df.item_liquid_miscst:is_instance(containedItem) then
				goto continue
			end

			table.insert(possibleUses, containedItem)

			::continue::
		end

		::continue::
	end

	-- Drop the items from the bed building
	for _, item in ipairs(preservedReagentItems) do
		local x, y, z = dfhack.items.getPosition(item)
		helpers.moveItemFromBuildingToGround(item, x, y, z)
	end

	local needs = getMedicationNeeds(patient)
	for _, medicationItem in ipairs(possibleUses) do
		local useType, usePart
		for _, priority in ipairs(needs.priority) do
			useType = medicationHasUse(medicationItem.mat_type, medicationItem.mat_index, priority.type)
			usePart = priority.bodyPart
			if useType then
				break
			end
		end
		if useType then
			local state = df.matter_state[medicationItem:isLiquid() and "Liquid" or "Solid"]
			local useAmount = usePart and 50 or 150 -- Don't use too much for localised medication
			applyMaterial(
				patient,
				useType,
				medicationItem.mat_type,
				medicationItem.mat_index,
				math.floor(useAmount / 10),

				-- If spatter/injection:
				useAmount,
				usePart,
				-- If spatter:
				state,
				true,
				medicationItem.temperature.whole,
				medicationItem.temperature.fraction
			)
			medicationItem:subtractDimension(useAmount)
			if medicationItem:getDimension() <= 0 then
				table.insert(itemsToDelete, medicationItem)
			end

			-- NOTE: Intent was to originally use up a total required quantity in an flexible system
			finish()
			return
		end
	end

	finish()
end

function checkForPainReliefNeeds()
	local patientsWithMedicationComing = {}
	helpers.iterateJobs(function(job)
		if job.job_type ~= df.job_type.CustomReaction then
			return
		end
		if job.reaction_name ~= consts.administerMedicationReactionName then
			return
		end
		local patientRef = dfhack.job.getGeneralRef(job, df.general_ref_type.UNIT_PATIENT)
		local patient = patientRef:getUnit()
		if not patient then
			return
		end
		patientsWithMedicationComing[patient] = true
	end)
	helpers.iterateJobs(function(job)
		if job.job_type ~= df.job_type.Rest then
			return
		end
		local patient = dfhack.job.getWorker(job)
		if not patient then
			return
		end
		if patientsWithMedicationComing[patient] then
			return
		end
		local needs = getMedicationNeeds(patient)
		if #needs.priority == 0 then
			return
		end
		local patientPos = xyz2pos(dfhack.units.getPosition(patient))
		local toUse = selectRequiredMedication(needs, patientPos)
		local possibleUnits = {}
		for _, unit in ipairs(df.global.world.units.active) do
			if
				dfhack.units.isActive(unit) and
				dfhack.units.isCitizen(unit) and
				helpers.canBeAddedToJob(unit) and
				unit.status.labors.RECOVER_WOUNDED
			then
				table.insert(possibleUnits, unit)
			end
		end
		local availableUnits = helpers.sortPathableUnitsInSetByDistance(possibleUnits, patientPos)
		local administerer = availableUnits[1]
		local err
		local patientName = dfhack.TranslateName(dfhack.units.getVisibleName(patient))
		if not administerer then
			err = patientName .. " needs medication but there is nobody available to give any."
		end

		local success, errType = createAdministerMedicationJob(patient, administerer, toUse)
		if not success then
			-- Only bother with error types that we haven't already checked for
			if errType == "notSafelyInBed" then
				err = patientName .. " needs medication but is not safely resting in bed."
			elseif errType == "noMedicationSelected" then
				err = patientName .. " needs medication but there is no appropriate medication available."
			end
		end

		if err and consts.enableMedicationFailureAnnouncements then
			local announcements = df.global.world.status.announcements
			local prevLength = #announcements
			dfhack.gui.showZoomAnnouncement(-1, patientPos, err, COLOR_RED, 1)
			for i = prevLength, #announcements - 1 do -- Get continuations
				local announcement = announcements[i]
				announcement.zoom_type = df.report_zoom_type.Unit
			end
		end
	end)
end

function createRecoverWoundedJob(patient, recoverer, bed)
	if not helpers.canBeAddedToJob(recoverer) then
		return false, "recovererCantJob"
	end

	local patientPos = xyz2pos(dfhack.units.getPosition(patient))
	if not patientPos then
		return false, "patientPositionUnknown"
	end
	local recovererPos = xyz2pos(dfhack.units.getPosition(recoverer))
	if not recovererPos then
		return false, "recovererPositionUnknown"
	end
	if not dfhack.maps.canWalkBetween(patientPos, recovererPos) then
		return false, "noPathToPatient"
	end

	local job = df.job:new()

	job.job_type = df.job_type.RecoverWounded

	job.pos.x, job.pos.y, job.pos.z =
		bed.centerx,
		bed.centery,
		bed.z

	job.flags.special = true

	job.general_refs:insert("#", {
		new = df.general_ref_unit_patientst,
		unit_id = patient.id
	})

	job.general_refs:insert("#", {
		new = df.general_ref_building_use_target_1st,
		building_id = bed.id
	})

	dfhack.job.linkIntoWorld(job, true)
	helpers.addJobWorker(job, recoverer)

	return true
end

local function handleFlooredRestingWounded()
	local occupiedBeds = {}
	local patientsWithoutBeds = {}
	helpers.iterateJobs(function(job)
		-- Mark any beds that a unit is being taken to as occupied too (presumbly they're beds, but it's fine if whatever created the recover unit job intentionally doesn't use a bed)
		-- I don't think the game itself checks for beds having recover wounded jobs pointed at them, though
		if job.job_type == df.job_type.RecoverWounded then
			local bedBuildingRef = dfhack.job.getGeneralRef(job, df.general_ref_type.BUILDING_USE_TARGET_1)
			if bedBuildingRef then
				local building = bedBuildingRef:getBuilding()
				if building then
					occupiedBeds[building.id] = true
				end
			end
			return
		end

		if job.job_type ~= df.job_type.Rest then
			return
		end
		local patient = dfhack.job.getWorker(job)
		if not patient then
			return
		end
		local bedBuilding = helpers.getBuildingAt(dfhack.units.getPosition(patient))
		if not bedBuilding or bedBuilding._type ~= df.building_bedst then
			table.insert(patientsWithoutBeds, patient)
			return
		end
		occupiedBeds[bedBuilding.id] = true
	end)

	local availableBeds = {}
	for _, building in ipairs(df.global.world.buildings.other.ANY_HOSPITAL) do
		if
			building._type == df.building_bedst and
			not occupiedBeds[building.id] and
			helpers.canUseFurniture(building)
		then
			table.insert(availableBeds, building)
		end
	end

	if #patientsWithoutBeds == 0 or #availableBeds == 0 then
		return
	end

	local availableUnits = {}
	for _, unit in ipairs(df.global.world.units.active) do
		if
			dfhack.units.isActive(unit) and
			dfhack.units.isCitizen(unit) and
			helpers.canBeAddedToJob(unit) and
			unit.status.labors.RECOVER_WOUNDED
		then
			table.insert(availableUnits, unit)
		end
	end

	for _, patient in ipairs(patientsWithoutBeds) do
		local patientPos = xyz2pos(dfhack.units.getPosition(patient))
		local pathableAvailableBedsSorted = helpers.sortPathableBuildingsInSetByDistance(availableBeds, patientPos)

		if #pathableAvailableBedsSorted == 0 then
			goto continue
		end

		local pathableAvailableUnitsSorted = helpers.sortPathableUnitsInSetByDistance(availableUnits, patientPos)

		local bed = pathableAvailableBedsSorted[1]
		local worker = pathableAvailableUnitsSorted[1]

		if bed and worker then
			createRecoverWoundedJob(patient, worker, bed)
			-- Cut now-unavailable worker and bed from their unsorted sets (which have not been filtered by pathabiity)
			-- No need to mark a bed as occupied in occupiedBeds because we don't use that at this point in the function
			for i, unit in ipairs(availableUnits) do
				if unit == worker then
					local len = #availableUnits
					availableUnits[i], availableUnits[len] = availableUnits[len], nil
					break
				end
			end
			for i, possibleBed in ipairs(availableBeds) do
				if possibleBed == bed then
					local len = #availableBeds
					availableBeds[i], availableBeds[len] = availableBeds[len], nil
					break
				end
			end
		end

	    ::continue::
	end
end

-- Unit wound pain goes down to 0 very fast (1/30 chance to go down per tick apparently). This changes that (if enabled).
local function recordPainInFlags(flags, pain)
	local maxStoredPain = 2 ^ (consts.woundPainRecordBitsEnd - consts.woundPainRecordBitsStart) - 1
	helpers.setNumberInFlags(
		flags,
		math.min(maxStoredPain, pain),
		consts.woundPainRecordBitsStart,
		consts.woundPainRecordBitsEnd
	)
	assert(helpers.getNumberInFlags(
		flags,
		consts.woundPainRecordBitsStart,
		consts.woundPainRecordBitsEnd
	) == math.min(maxStoredPain, pain))
end
local function handleWoundStructPain(struct, flagsKey, decrement)
	local flags = struct[flagsKey]
	if not flags[consts.woundPainInitialisedBit] then
		flags[consts.woundPainInitialisedBit] = true
		recordPainInFlags(flags, math.floor(struct.pain * consts.painFixInitialRecordedPainMultiplier))
		return
	end

	local lastRecordedPain = helpers.getNumberInFlags(
		flags,
		consts.woundPainRecordBitsStart,
		consts.woundPainRecordBitsEnd
	)
	local diff = struct.pain - lastRecordedPain

	if diff < 0 and struct.pain > 0 then -- Don't rewind if we hit zero
		local painLoss = -diff
		local maxNaturalPainLoss = consts.painFixRepeatInterval
		local painLossToTryToRewind = math.min(painLoss, maxNaturalPainLoss)
		local painLossToRewind = 0
		for _=1, painLossToTryToRewind do -- 1/30 chance to reduce pain per tick
			if helpers.rng:drandom() < consts.painRewindChancePerTick then
				painLossToRewind = painLossToRewind + 1 -- Not got the mental toolkit for probability stuff yet
			else
				break
			end
		end
		struct.pain = struct.pain + painLossToRewind
	end

	if diff <= 0 and decrement then -- Don't decrement if we went up
		struct.pain = math.max(0, struct.pain - consts.painFixDecrementAmount)
	end

	if lastRecordedPain ~= struct.pain then
		recordPainInFlags(flags, struct.pain)
	end
end
local function fixPain(decrement)
	for _, unit in ipairs(df.global.world.units.active) do
		if not dfhack.units.isActive(unit) then
			goto continue
		end

		-- We still fix (increase) wound pain even if creature has [NOPAIN], because when the game recalculates total pain it will be zero but the game doesn't zero pain in the wounds (or wound parts) themselves

		-- The previous attempt would recalculate starting wound pain from the wound's information, but I don't know if there is enough information in a wound, nor the formula.
		-- local bodyParts = unit.body.body_plan.body_parts
		-- for _, wound in ipairs(unit.body.wounds) do
		-- 	local woundAgeMultiplier -- Would go down from 1 to 0 as wound age increases
		-- 	for _, woundPart in ipairs(wound.parts) do
		-- 		local basePartPain -- Also not implemented
		-- 		local targetPain = math.floor(consts.painFixRecalculatedPainMultiplier * woundAgeMultiplier * basePartPain)
		-- 		if woundPart.pain < targetPain then
		-- 			woundPart.pain = math.min(targetPain, woundPart.pain + consts.painFixPainIncreasePerRepeat)
		-- 		end
		-- 	end
		-- end

		-- Another idea was to save the wound pain on wound creation and use that along with wound age information etc, but wounds can worsen

		-- What we're going to do is save the pain (into flags2's bits) repeatedly and rewind the pain tick-down that the game does so we can do it ourselves at our own rate

		for _, wound in ipairs(unit.body.wounds) do
			-- Don't modify pain syndrome wounds since the game overwrites our changes
			if wound.syndrome_id ~= -1 then
				goto continue
			end

			-- First handle the wound itself if it has any pain
			handleWoundStructPain(wound, "flags", decrement)
			-- Then the parts
			for _, part in ipairs(wound.parts) do
				handleWoundStructPain(part, "flags2", decrement)
			end

		    ::continue::
		end

		-- unit.counters.pain gets recalculated from the changed values. If we need to we can probably do that ourselves.

	    ::continue::
	end
end

-- Resting causes unconsciousness, which means units in hospital feel no pain. This changes that (if enabled).
local function fixRestJobUnconscious(job)
	local unit = dfhack.job.getWorker(job)
	if not unit then
		return
	end

	-- Check we are at the values for a non-tired resting citizen each tick. If so, wake them up
	if
		unit.counters.unconscious <= 2 and
		unit.counters2.sleepiness_timer <= 1
	then
		unit.counters.unconscious = 0
		-- Allow sleepiness timer to decrease
		unit.counters2.sleepiness_timer = math.max(0, unit.counters2.sleepiness_timer - consts.sleepinessTimerDecrease)
	end
end

local function administerMedicationJobOnTick(job)
	local patientRef = dfhack.job.getGeneralRef(job, df.general_ref_type.UNIT_PATIENT)
	local patient = patientRef:getUnit()
	if
		not patient or
		not patient.job.current_job or
		patient.job.current_job.job_type ~= df.job_type.Rest
	then
		helpers.cancelJob(job)
		return
	end

	local administerer = dfhack.job.getWorker(job)
	if not administerer then
		helpers.cancelJob(job)
		return
	end
end

local function onTick()
	helpers.iterateJobs(function(job)
		if
			job.job_type == df.job_type.CustomReaction and
			job.reaction_name == consts.administerMedicationReactionName
		then
			administerMedicationJobOnTick(job)
		elseif
			consts.restConscious and
			job.job_type == df.job_type.Rest
		then
			fixRestJobUnconscious(job)
		end
	end)

	local painFixTimer = helpers.getPersistNum("painFixTimer") or 0
	painFixTimer = painFixTimer - 1
	if painFixTimer <= 0 then
		local painFixDecrementTimer = helpers.getPersistNum("painFixDecrementTimer") or 0
		painFixDecrementTimer = painFixDecrementTimer - 1
		local decrement = painFixDecrementTimer <= 0
		if decrement then
			painFixDecrementTimer = consts.painFixDecrementRate
		end
		helpers.setPersistNum("painFixDecrementTimer", painFixDecrementTimer)

		if consts.enablePainFix then
			fixPain(decrement)
		end
		painFixTimer = consts.painFixRepeatInterval
	end
	helpers.setPersistNum("painFixTimer", painFixTimer)

	local handleFlooredRestingTimer = helpers.getPersistNum("handleFlooredRestingTimer") or 0
	handleFlooredRestingTimer = handleFlooredRestingTimer - 1
	if handleFlooredRestingTimer <= 0 then
		if consts.enableBringToBedWhenRestingOnFloor then
			handleFlooredRestingWounded()
		end
		handleFlooredRestingTimer = consts.handleFlooredRestingRepeatInterval
	end
	helpers.setPersistNum("handleFlooredRestingTimer", handleFlooredRestingTimer)

	local checkMedicationNeededTimer = helpers.getPersistNum("checkMedicationNeededTimer") or 0
	checkMedicationNeededTimer = checkMedicationNeededTimer - 1
	if checkMedicationNeededTimer <= 0 then
		checkForPainReliefNeeds()
		checkMedicationNeededTimer = consts.checkMedicationNeededRepeatInterval
	end
	helpers.setPersistNum("checkMedicationNeededTimer", checkMedicationNeededTimer)

end

function enable()
	timekeeping.register("medical", onTick)
	events.register("medicationAdministering", "onJobCompleted", administerJobOnComplete, "JOB_COMPLETED", 0)
end

function disable()
	timekeeping.unregister("medical")
	events.unregister("medicationAdministering", "onJobCompleted")
end
