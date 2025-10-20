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

function enable()
	events.register("materialConversion", "onReactionComplete", materialConversionOnReactionComplete)
	events.register("magicPuffs", "onJobCompleted", onMagicPuffJob, "JOB_COMPLETED", 0)
end

function disable()
	events.unregister("materialConversion", "onReactionComplete")
	events.unregister("magicPuffs", "onJobCompleted")
end
