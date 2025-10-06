--@module = true
enableable = true

local eventful = require("plugins.eventful")

local consts = dfhack.reqscript("witchen-mechanica/consts")

local eventTypes = {
	"onProjItemCheckMovement",
	"onProjItemCheckImpact",
	"onConstructionCreatedDestroyed",
	"onJobCompleted",
	"onWorkshopFillSidebarMenu",
	"postWorkshopFillSidebarMenu",
	"onJobInitiated",
	"onUnload",
	"onInventoryChange",
	"onUnitDeath",
	"onInteraction",
	"onSyndrome",
	"onJobStarted",
	"onUnitAttack",
	"onReport",
	"onReactionCompleting",
	"onReactionComplete",
	"onItemContaminateWound",
	"onProjUnitCheckMovement",
	"onInvasion",
	"onProjUnitCheckImpact",
	"onItemCreated",
	"onUnitNewActive",
	"onBuildingCreatedDestroyed"
}

local registered = {}

function register(name, event, func, enableName, enableNumber)
	unregister(name, event)
	if enableName then
		eventful.enableEvent(eventful.eventType[enableName], enableNumber)
	end
	registered[event] = registered[event] or {}
	table.insert(registered[event], {
		name = name,
		func = func
	})
end

function unregister(name, event)
	local subtable = registered[event]
	if not subtable then
		return false
	end
	for i, v in ipairs(subtable) do
		if v.name == name then
			table.remove(subtable, i)
			return true
		end
	end
	return false
end

function enable()
	registered = {}
	for _, eventTypeName in ipairs(eventTypes) do
		eventful[eventTypeName][consts.modKey] = function(...)
			local subtable = registered[eventTypeName]
			if not subtable then
				return
			end
			for _, entry in ipairs(subtable) do
				entry.func(...)
			end
		end
	end
end

function disable()
	registered = {}
	for _, eventTypeName in ipairs(eventTypes) do
		eventful[eventTypeName][consts.modKey] = nil
	end
end
