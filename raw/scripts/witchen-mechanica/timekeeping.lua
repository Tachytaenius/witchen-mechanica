--@ module = true
enableable = true

local repeatUtil = require("repeat-util")

local consts = dfhack.reqscript("witchen-mechanica/consts")
local helpers = dfhack.reqscript("witchen-mechanica/helpers")

-- Gets around the issue of repeat-util being retriggerable within a tick by repeatedly rescheduling.

local registered = {}

function register(name, func) -- TODO: Interval and offset
	unregister(name)
	registered[#registered+1] = {
		name = name,
		func = func
	}
end

function unregister(name)
	for i, v in ipairs(registered) do
		if v.name == name then
			table.remove(registered, i)
			return true
		end
	end
	return false
end

function enable()
	registered = {}
	repeatUtil.scheduleEvery(consts.modKey, 1, "ticks", function()
		helpers.ensurePersistStorage()

		if
			helpers.getPersistNum("lastRunYear") == df.global.cur_year and
			helpers.getPersistNum("lastRunYearTick") == df.global.cur_year_tick and
			helpers.getPersistNum("lastRunYearTickAdv") == df.global.cur_year_tick_advmode
		then
			return
		end

		for _, v in ipairs(registered) do
			v.func()
		end

		helpers.setPersistNum("lastRunYear", df.global.cur_year)
		helpers.setPersistNum("lastRunYearTick", df.global.cur_year_tick)
		helpers.setPersistNum("lastRunYearTickAdv", df.global.cur_year_tick_advmode)
	end)
end

function disable()
	registered = {}
	repeatUtil.cancel(consts.modKey)
end
