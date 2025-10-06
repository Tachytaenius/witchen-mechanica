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

function enable()
	events.register("materialConversion", "onReactionComplete", materialConversionOnReactionComplete)
end

function disable()
	events.unregister("materialConversion", "onReactionComplete")
end
