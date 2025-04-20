-- <<<api:kernel>>>
-- Reactor UI

local reactor, turbine, system = ...

local kernel = require("apis/kernel")

local statusWindow
local logWindow

local function setup()
	w, h = term.getSize()
	hStatus = 7
	statusWindow = window.create(term.current(), 1, 1, w, hStatus)
	logWindow = window.create(term.current(), 1, hStatus+1, w, h - hStatus)

	statusWindow.setCursorBlink(false)

	logWindow.setCursorBlink(false)
	logWindow.setBackgroundColor(colors.black)
	logWindow.setTextColor(colors.white)
end

local function niceUnits(val, base, bin)
	if val == nil then val = 0 end
	if base == nil then return '' end

	local mul = 1000
	if bin then mul = 1024 end

	local big = { 'k', 'M', 'G', 'T' }
	local small = { 'm', 'u', 'n', 'p' }

	local unit = 0
	local strUnit = base
	if math.abs(val) > mul then
		while math.abs(val) > mul do
			if unit == 4 then
				break
			end

			val = val / mul
			unit = unit + 1
		end

		strUnit = big[unit]..base
	elseif math.abs(val) < 1 then
		while math.abs(val) < 1 do
			if unit == 4 then
				break
			end

			val = val * mul
			unit = unit + 1
		end

		strUnit = small[unit]..base
	end

	return ("%.3f%s"):format(val, strUnit)
end


-- Logging functions (_G.log)
local function printRedir(...)
	local old = term.redirect(logWindow)
	print(...)
	term.redirect(old)
end


local function displayStatus()
	statusWindow.setBackgroundColor(colors.black)
	statusWindow.setTextColor(colors.white)
	statusWindow.clear()

	statusWindow.setCursorPos(2, 2)
	statusWindow.write("State: ")
	statusWindow.write(reactor:getStatus('state'))

	statusWindow.setCursorPos(17, 2)
	statusWindow.write("Burn: ")
	if reactor:getStatus('state') == "run" then
		statusWindow.write(niceUnits(reactor.sensors['reactor:burn']:getValue() / 1000, "B/t"))
	else
		statusWindow.write("N/A")
	end

	statusWindow.setCursorPos(2, 3)
	statusWindow.write("Power: ")
	statusWindow.write(niceUnits(turbine.sensors['turbine:power']:getValue(), "J/t"))

	statusWindow.setCursorPos(2, 4)
	statusWindow.write("Buffer: ")
	statusWindow.write(niceUnits(system.sensors['buffer:energy']:getValue(), "J"))

	statusWindow.setTextColor(colors.black)
	statusWindow.setCursorPos(4, 6)
	if reactor:getStatus('state') == "run" then
		statusWindow.setBackgroundColor(colors.lightGray)
	else
		statusWindow.setBackgroundColor(colors.green)
	end
	statusWindow.write("START")

	statusWindow.setCursorPos(12, 6)
	if reactor:getStatus('state') ~= "run" then
		statusWindow.setBackgroundColor(colors.lightGray)
	else
		statusWindow.setBackgroundColor(colors.red)
	end
	statusWindow.write("STOP")

	statusWindow.setCursorPos(19, 6)
	statusWindow.setBackgroundColor(colors.black)
	if reactor:getStatus('state') ~= "safety" then
		statusWindow.setTextColor(colors.lightGray)
	else
		statusWindow.setTextColor(colors.red)
	end
	statusWindow.write("RESET")
end


local function handleClick(event)
	local x = event[3]
	local y = event[4]

	if y == 6 then
		if x >= 4 and x <= 9 then
			system:sendCommand('start')
			printRedir("Start")
		elseif x >= 12 and x <= 16 then
			system:sendCommand('stop')
			printRedir("Stop")
		elseif x >= 19 and x <= 24 then
			system:sendCommand('reset')
			printRedir("Reset")
		end
	end
end



kernel.start(function()
	while true do
		local e = kernel.select(nil,
			{"mouse_click"},
			{"monitor_touch"}
		)

		handleClick(e)
	end
end)



setup()

while true do
	displayStatus()

	sleep(1)
end
