-- <<<>>>
-- Reactor UI

local kernel = require("apis/kernel")

local logger = {}
_G.log = logger
--local controller = require("apis/controller") -- Also starts controller in kernel
local comm = require("apis/comm")
require("apis/remote_logger")

local status = {}

local statusWindow
local logWindow

local function setup()
	w, h = term.getSize()
	hStatus = 6
	statusWindow = window.create(term.current(), 1, 1, w, hStatus)
	logWindow = window.create(term.current(), 1, hStatus+1, w, h - hStatus)

	statusWindow.setCursorBlink(false)

	logWindow.setCursorBlink(false)
	logWindow.setBackgroundColor(colors.black)
	logWindow.setTextColor(colors.white)
end

local function niceUnits(val, base)
	if val == nil then val = 0 end
	if base == nil then return '' end

	local big = { 'k', 'M', 'G', 'T' }
	local small = { 'm', 'u', 'n', 'p' }

	local unit = 0
	local strUnit = base
	if math.abs(val) > 1024 then
		while math.abs(val) > 1024 do
			if unit == 4 then
				break
			end

			val = val / 1024
			unit = unit + 1
		end

		strUnit = big[unit]..base
	elseif math.abs(val) < 1 then
		while math.abs(val) < 1 do
			if unit == 4 then
				break
			end

			val = val * 1024
			unit = unit + 1
		end

		strUnit = small[unit]..base
	end

	return ("%.3f%s"):format(val, strUnit)
end

local function displayStatus()
	statusWindow.setBackgroundColor(colors.black)
	statusWindow.setTextColor(colors.white)
	statusWindow.clear()

	statusWindow.setCursorPos(2, 2)
	statusWindow.write("State: ")
	statusWindow.write(status.state)

	statusWindow.setCursorPos(14, 2)
	statusWindow.write("Burn: ")
	if status.state == "RUN" then
		statusWindow.write(niceUnits(status.burnRate / 1000, "B/t"))
	else
		statusWindow.write("N/A")
	end

	statusWindow.setCursorPos(2, 3)
	statusWindow.write("Power: ")
	statusWindow.write(niceUnits(status.production, "J/t"))

	statusWindow.setTextColor(colors.black)
	statusWindow.setCursorPos(4, 5)
	if status.state == "RUN" then
		statusWindow.setBackgroundColor(colors.lightGray)
	else
		statusWindow.setBackgroundColor(colors.green)
	end
	statusWindow.write("START")

	statusWindow.setCursorPos(12, 5)
	if status.state ~= "RUN" then
		statusWindow.setBackgroundColor(colors.lightGray)
	else
		statusWindow.setBackgroundColor(colors.red)
	end
	statusWindow.write("STOP")
end

local function handleClick(event)
	local x = event[3]
	local y = event[4]

	if y == 5 then
		if x >= 4 and x <= 9 then
			comm.send({ type = 'cmd', cmd = 'START' })
		elseif x >= 12 and x <= 16 then
			comm.send({ type = 'cmd', cmd = 'STOP' })
		end
	end
end

--kernel.events.addHandler(handleClick, nil, "monitor_touch")
kernel.events.addHandler(handleClick, nil, "mouse_click")


-- Logging functions (_G.log)
local function printRedir(...)
	local old = term.redirect(logWindow)
	print(...)
	term.redirect(old)
end

function logger.info(...)
	-- TODO: Kludge
	local args = table.pack(...)
	if type(args[1]) == "table" and args[1].type == "status" then
		status = args[1].data
	else
		printRedir("Info:  ", ...)
	end
end

function logger.warn(...)
	printRedir("Warn:  ", ...)
end

function logger.error(...)
	printRedir("Error: ", ...)
end


kernel.tasks.schedule(setup, 0)
kernel.tasks.schedule(displayStatus, 1, 1)
