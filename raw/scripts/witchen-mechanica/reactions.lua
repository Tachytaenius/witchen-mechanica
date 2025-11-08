--@module = true
enableable = true

local customRawTokens = require("custom-raw-tokens")

local events = dfhack.reqscript("witchen-mechanica/events")
local helpers = dfhack.reqscript("witchen-mechanica/helpers")

local function materialConversionOnReactionComplete(reaction, reactionProduct, unit, inputItems, inputReagents, outputItems)
	local baseChance, chanceMultiplierType, materialArgA, materialArgB, materialArgC, materialArgD =
		customRawTokens.getToken(reaction, "WITCHEN_MECHANICA_CONVERT_PRODUCT_MAT")
	if not baseChance then
		return
	end

	local chance = baseChance
	if chanceMultiplierType == "MOON_PHASE" then
		local phase = df.global.world.world_data.moon_phase % 28
		chance = chance * math.abs(14 - phase) / 14
	end

	local token = table.concat({materialArgA, materialArgB, materialArgC, materialArgD}, ":") -- Avoid passing trailing nils to the function as it will error
	local matInfo = dfhack.matinfo.find(token)
	if not matInfo then
		return
	end

	for _, item in ipairs(outputItems) do
		if helpers.rng:drandom() < chance then
			helpers.setItemMaterial(item, matInfo.type, matInfo.index)
		end
	end
end

local function onMagicPuffJob(job)
	if job.job_type ~= df.job_type.CustomReaction then
		return
	end
	local reaction = helpers.findReactionByName(job.reaction_name)
	local amount, xOffset, yOffset = customRawTokens.getToken(reaction, "WITCHEN_MECHANICA_MAGIC_PUFF")
	amount = tonumber(amount)
	xOffset = tonumber(xOffset) or 0
	yOffset = tonumber(yOffset) or 0
	if not (amount and amount > 0) then
		return
	end

	local worker = dfhack.job.getWorker(job)
	if not worker then
		return
	end
	local x, y, z = dfhack.units.getPosition(worker)
	if not (x and y and z) then
		return
	end
	x, y = x + xOffset, y + yOffset
	local position = xyz2pos(x, y, z)
	if not position then
		return
	end

	helpers.createMagicPuff(position, amount)
end

local function onReagentMatToReactionProductJob(job)
	if job.job_type ~= df.job_type.CustomReaction then
		return
	end
	local reaction = helpers.findReactionByName(job.reaction_name)
	local reagentName, materialReactionProduct = customRawTokens.getToken(reaction, "WITCHEN_MECHANICA_SET_REAGENT_MAT_TO_MAT_REACTION_PRODUCT")

	if not reagentName and materialReactionProduct then
		return
	end

	for _, jobItemRef in ipairs(job.items) do
		if jobItemRef.role ~= df.job_item_ref.T_role.Reagent then
			goto continue
		end
		if jobItemRef.job_item_idx == -1 then
			goto continue
		end
		local jobItem = job.job_items[jobItemRef.job_item_idx]
		if jobItem.reaction_id ~= reaction.index then
			--- ???
			goto continue
		end
		if jobItem.reagent_index == -1 then
			goto continue
		end
		local reagent = reaction.reagents[jobItem.reagent_index]
		if reagent.code ~= reagentName then
			goto continue
		end

		if not reagent.flags.PRESERVE_REAGENT then
			goto continue
		end
		local item = jobItemRef.item -- Preserved (job is a copy, would deleted items be dangling pointers?)

		local matinfo = dfhack.matinfo.decode(item.mat_type, item.mat_index)
		if not matinfo then
			goto continue
		end
		local material = matinfo.material

		local newMatType, newMatIndex
		for i, id in ipairs(material.reaction_product.id) do
			if id.value == materialReactionProduct then
				newMatType = material.reaction_product.material.mat_type[i]
				newMatIndex = material.reaction_product.material.mat_index[i]
				break
			end
		end
		if not (newMatType and newMatIndex) then
			goto continue
		end

		helpers.setItemMaterial(item, newMatType, newMatIndex)

	    ::continue::
	end
end

function enable()
	events.register("materialConversion", "onReactionComplete", materialConversionOnReactionComplete)
	events.register("magicPuffs", "onJobCompleted", onMagicPuffJob, "JOB_COMPLETED", 0)
	events.register("reagentMatToReactionProductConversion", "onJobCompleted", onReagentMatToReactionProductJob, "JOB_COMPLETED", 0)
end

function disable()
	events.unregister("materialConversion", "onReactionComplete")
	events.unregister("magicPuffs", "onJobCompleted")
	events.unregister("reagentMatToReactionProductConversion", "onJobCompleted")
end
