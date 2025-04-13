-- <<<interface:kernel/driver|extension:table>>>

require("apis/table_extensions")
require("interfaces/kernel/driver")


-- TODO
--local logger = require("apis/logger_base")
--
--if not _G.log then
--	error("Kernel requires an available logger")
--end
--
--local kernelLogger = {
--	name = "kernel"
--}
--local log = logger.wrap(_G.log, kernelLogger)


local instance = {}




local function matchEventFilter(filter, event)
	-- Assume empty filter if .n is nil
	if filter.n == nil then return true end

	for i=1,filter.n,1 do
		local p = filter[i]

		if p ~= nil and p ~= event[i] then
			return false
		end
	end

	return true
end




-- Events table
local events = {
	SENTINEL = table.pack("_kernel", "event_sentinel"),
	YIELD = table.pack("_kernel", "yield")
}




-- [Enum]
local ProcessState = {
	INVALID = -1,
	INIT = 0,
	RUN = 1,
	WAIT = 2,
	SUSPEND = 3,
	STOP = 4,
	FINISH = 5,
	ERROR = 6
}

-- [Helper]
-- Converts ProcState enum to string
local function stateToStr(state)
	return table.getkey(ProcessState, state)
end


local _currentPid = 0
local function nextPid()
	local pid = _currentPid

	_currentPid = pid + 1

	return pid
end

local BAD_PID = -1
local DEFAULT_NICE = 0

local Process = {
	-- TODO: ppid?
	pid = BAD_PID,
	nice = DEFAULT_NICE,

	proc = nil,
	args = {},
	state = ProcessState.INVALID,

	events = nil,
	eventFilter = nil
}

function Process:new(obj)
	obj = obj or {}

	-- Ensure unique values for every process
	if not obj.events then obj.events = {} end
	if not obj.eventFilter then obj.eventFilter = {} end

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function Process:__eq(other)
	return self.pid == other.pid
end

function Process:queueEvent(e)
	-- If the event queue is empty, and this event does not match the filter, drop it
	if self.state == ProcessState.WAIT then
		if #self.events == 0 and not matchEventFilter(self.eventFilter, e) then
			return false
		else
			self:transition(ProcessState.RUN)
		end
	end

	table.insert(self.events, e)

	return true
end

function Process:pollEvent()
	-- Pull events from the queue until a matching event is found, or the queue is empty
	while #self.events > 0 do
		local e = table.remove(self.events, 1)

		if matchEventFilter(self.eventFilter, e) then
			return e
		end
	end

	return nil
end

function Process:runProc(...)
	local ret = table.pack( coroutine.resume(self.proc, ...) )

	local status = ret[1]
	self.eventFilter = table.pack(table.unpack(ret, 2))

	return status
end

function Process:init()
	-- Start coroutine with input arguments
	local status = self:runProc(table.unpack(self.args))

	if status and self.state == ProcessState.INIT then
		self:transition(ProcessState.RUN)
	end
end

function Process:run()
	local event = self:pollEvent()

	if event == nil then
		self:transition(ProcessState.WAIT)
		return
	end

	local status = self:runProc(table.unpack(event))
end

function Process:wait()
	if #self.events > 0 then
		self:transition(ProcessState.RUN)
	end
end

function Process:tick()
	if self.state == ProcessState.STOP or self.state == ProcessState.FINISH or self.state == ProcessState.ERROR then
		return false
	elseif self.state == ProcessState.INIT then
		self:init()
	elseif self.state == ProcessState.RUN then
		self:run()
	elseif self.state == ProcessState.WAIT then
		self:wait()
	end

	return coroutine.status(self.proc) ~= "dead"
end

function Process:transition(state)
	if self._onTransition then
		local g, msg = self:_onTransition(self.state, state)
		if not g then
			print("p["..self.pid.."]> "..msg)
		end
	end

	self.state = state
end



local ProcessTable = {
	processes = nil,
	niceLevels = nil,
	active = nil,
	inactive = nil,
	complete = nil
}

function ProcessTable:new(obj)
	obj = obj or {}

	-- Ensure unique values for every process
	if not obj.processes then obj.processes = {} end
	if not obj.niceLevels then obj.niceLevels = {} end
	if not obj.active then obj.active = {} end
	if not obj.inactive then obj.inactive = {} end
	if not obj.complete then obj.complete = {} end

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function ProcessTable:cleanup()
	for _,v in ipairs(self.complete) do
		self.processes[v] = nil
	end

	self.complete = {}
end

function ProcessTable:addNice(nice)
	local idx = 1
	for i,v in ipairs(self.niceLevels) do
		idx = i

		if nice == v then
			return
		elseif nice > v then
			break
		end
	end

	self.active[nice] = {}
	table.insert(self.niceLevels, idx, nice)
end

function ProcessTable:addProcess(process)
	local pid = process.pid

	self.processes[pid] = process
	process._onTransition = function(proc, from, to)
		return self:transition(proc.pid, from, to)
	end

	self:transition(pid, ProcessState.INVALID, process.state)
end

function ProcessTable:getTable(pid, state)
	if state == ProcessState.INIT or state == ProcessState.RUN then
		local process = self.processes[pid]
		return self.active[process.nice]
	elseif state == ProcessState.WAIT or state == ProcessState.SUSPEND then
		return self.inactive
	elseif state == ProcessState.STOP or state == ProcessState.FINISH or state == ProcessState.ERROR then
		return self.complete
	end

	return nil
end

function ProcessTable:transition(pid, from, to)
	local process = self.processes[pid]
	if not process then return false, "Bad process" end

	-- Allow signature `transition(pid, to)`
	if to == nil then
		to = from
		from = process.state
	end

	if from == to then
		return true
	end

	local srcTable = self:getTable(pid, from)
	local destTable = self:getTable(pid, to)

	if not destTable then
		return false, "Tried to transition to bad state"
	end

	if srcTable == self.complete and destTable then
		return false, "Tried to transition completed process"
	end

	if srcTable then
		local srcIdx = table.find(srcTable, pid)
		if srcIdx then
			table.remove(srcTable, srcIdx)
		end
	end

	table.insert(destTable, pid)

	return true
end

function ProcessTable:setNice(pid, val)
	local process = self.processes[pid]
	if not process then return false, "Bad process" end

	if process.state == ProcessState.INIT or process.state == ProcessState.RUN then
		self:addNice(val)

		local oldNice = self.active[process.nice]
		if oldNice then
			table.remove(oldNice, table.find(oldNice, pid))
		else
			error("process not in a nice level")
		end

		table.insert(self.active[val], pid)
	end

	process.nice = val

	return true
end

function ProcessTable:sendEvent(pid, event)
	if pid == nil then
		for _,v in pairs(self.processes) do
			if not v:queueEvent(event) then
			end
		end
	else
		local process = self.processes[pid]
		if not process then
			error("No process with pid "..pid)
		end

		process:queueEvent(event)
	end
end

-- Number of processes that may be run by events/scheduling
-- > In state INIT, RUN, or WAIT
function ProcessTable:runnable()
	local count = #self.active

	for _,pid in ipairs(self.inactive) do
		if self.processes[pid].state == ProcessState.WAIT then
			count = count + 1
		end
	end

	return count
end

function ProcessTable:hasRunnable()
	if table.len(self.active) > 0 then
		return true
	end

	for _,pid in ipairs(self.inactive) do
		if self.processes[pid].state == ProcessState.WAIT then
			return true
		end
	end

	return false
end





local ProcessScheduler = {
	processTable = nil,

	level = 0,
	scheduling = {}
}

function ProcessScheduler:new(obj)
	obj = obj or {}

	if not obj.processTable then
		obj.processTable = ProcessTable:new{}
	end

	obj.scheduling = {}

	setmetatable(obj, self)
	self.__index = self

	for _,v in ipairs(obj.processTable.niceLevels) do
		self:addLevel(v)
	end

	return obj
end

function ProcessScheduler:addLevel(nice)
	local level = 1
	for i,v in ipairs(self.scheduling) do
		level = i

		if nice == v.nice then
			return
		elseif nice > v.nice then
			break
		end
	end

	table.insert(self.scheduling, level, {
		lastRun = 0,
		nice = nice
	})
end

function ProcessScheduler:getProcessList(level)
	if #self.scheduling < level then
		return nil
	end

	local nice = self.scheduling[level].nice
	return self.processTable.active[nice]
end

function ProcessScheduler:next()
	local level = 1
	local processList = self:getProcessList(level)
	local isEmpty = true

	-- If the last task run on the current level was the last task on that level, run a task from the next level
	while processList ~= nil and self.scheduling[level].lastRun >= #processList do
		if #processList > 0 then
			isEmpty = false
		end

		-- Reset lastRun counter
		self.scheduling[level].lastRun = 0

		level = level + 1

		if level > #self.scheduling then
			if isEmpty then
				return nil
			end

			isEmpty = true
			level = 1
		end

		processList = self:getProcessList(level)
	end

	local runIdx = self.scheduling[level].lastRun + 1
	self.scheduling[level].lastRun = runIdx

	return processList[runIdx], level
end

function ProcessScheduler:run()
	local pid, level = self:next()

	-- Nothing to run
	if pid == nil then
		return false
	end

	local process = self.processTable.processes[pid]
	self.running = process
	if not process:tick() then
		self.scheduling[level].lastRun = self.scheduling[level].lastRun - 1

		status = "unknown"
		if process.state == ProcessState.STOP then
			status = "stopped"
		elseif process.state == ProcessState.FINISH then
			status = "finished"
		elseif process.state == ProcessState.ERROR then
			status = "errored"
		else
			status = "faulted"
			local msg = "Died in state "..stateToStr(process.state)
			if process.msg then
				process.msg = msg .. ": " .. process.msg
			else
				process.msg = msg
			end
		end

		os.queueEvent("kernel", "process_complete", process.pid, status, process.msg)
	end
	self.running = nil

	return true
end






local processes = ProcessTable:new{}
local scheduler = ProcessScheduler:new{ processTable = processes }

processes:addNice(DEFAULT_NICE)
scheduler:addLevel(DEFAULT_NICE)



-- Get the next event
local function nextEvent(...)
	return table.pack( coroutine.yield(...) )
end

local lastYield = os.clock()
local function pullEvent(all)
	if all then
		os.queueEvent(table.unpack(events.SENTINEL))

		local event = nextEvent()
		while not matchEventFilter(events.SENTINEL, event) do
			processes:sendEvent(nil, event)

			event = nextEvent()
		end
	else
		processes:sendEvent(nil, nextEvent())
	end

	lastYield = os.clock()
end

local function yield(quick)
	if quick then
		os.queueEvent(table.unpack(events.YIELD))
	end

	pullEvent()
end

local yieldPeriod = 2
local function tick()
	-- Pull all events
	pullEvent(true)

	-- Yield regularly to keep CC happy
	-- Is this necessary?
	if os.clock() - lastYield >= yieldPeriod then
		yield(true)
	end

	return scheduler:run()
end




local function start(func, ...)
	if not func then
		return nil, "Process cannot be nil"
	end

	local pid = nextPid()
	local process = Process:new{
		pid = pid,
		args = table.pack(...),
		state = ProcessState.INIT
	}

	process.proc = coroutine.create(function(...)
		local g, msg = pcall(func, ...)

		if g then
			process:transition(ProcessState.FINISH)
		else
			process:transition(ProcessState.ERROR)
		end

		process.msg = msg
	end)

	if process.proc == nil then
		return nil, "Could not create coroutine"
	end

	processes:addProcess(process)

	return pid
end

local function exec(path, ...)
	if not path then
		return nil, "Need file path"
	end

	if not fs.exists(path) then
		return nil, "Path '"..path.."' does not exist"
	end

	local func = loadfile(path, nil, _ENV)

	return start(func, ...)
end

local function resume(pid)
	return processes:transition(pid, ProcessState.RUN)
end

local function suspend(pid)
	return processes:transition(pid, ProcessState.SUSPEND)
end

local function stop(pid)
	return processes:transition(pid, ProcessState.STOP)
end

local function nice(pid, val)
	val = val or 0

	scheduler:addLevel(val)
	processes:setNice(pid, val)
end




-- Wait for an event with timeout
-- Can wait for process completion via the kernel/process_complete event
local function wait(timeout, ...)
	if timeout and timeout >= 0 then
		local tId = os.startTimer(timeout)
		local filter = table.pack(...)
		while true do
			local event = nextEvent()

			if event[1] == "timer" and event[2] == tId then
				return nil, "timeout"
			elseif matchEventFilter(filter, event) then
				return event
			end
		end
	else
		return nextEvent(...)
	end
end

-- Run a function to completion without yielding to CC
-- The function cannot handle events, wait, etc
local function atomic(func, ...)
	if func == nil then
		return false, "Function cannot be nil"
	end

	-- The ... doesn't carry into the coroutine function
	local args = table.pack(...)
	local status = {}

	local c = coroutine.create(function()
		local g, msg = pcall(func, table.unpack(args))

		status.g = g
		status.msg = msg
	end)

	repeat
		coroutine.resume(c)
	until coroutine.status(c) == "dead"

	return status.g, status.msg
end

-- Create a regularly scheduled task from the given function
-- Return value can be used to create a process
local function task(func, period)
	if not func then
		return nil, "Need function"
	elseif not period then
		return nil, "Need period"
	end

	return function(...)
		local time = os.time() * 50 -- in-game time in seconds

		while func(...) do
			time = time + period
			local aId = os.setAlarm(time / 50)

			instance.wait(nil, "alarm", aId)
		end
	end
end




local peripherals = {
	connected = {},
	drivers = {
		raw = {}
	}
}

local function attachDriver(type, side, device)
	if instance.drivers[type] ~= nil then
		peripherals.drivers[type][side] = instance.drivers[type]:new{
			side = side,
			type = type,
			device = device
		}
	end

	os.queueEvent("kernel", "driver", "attach", side, type)
end
local function detachDriver(type, side)
	if instance.drivers[type] ~= nil and peripherals.drivers[type][side] ~= nil then
		peripherals.drivers[type][side]:cleanup()
		peripherals.drivers[type][side] = nil
	end

	os.queueEvent("kernel", "driver", "detach", side, type)
end

local function addDriver(type, driver)
	if instance.drivers[type] then
		return false, "Already have a driver for type "..type
	end

	instance.drivers[type] = driver
	peripherals.drivers[type] = {}

	-- Attach this driver to any existing peripherals with this type
	for side,info in pairs(peripherals.connected) do
		for i=1,info.types.n,1 do
			local t = info.types[i]

			if t == type then
				attachDriver(t, side, info.device)
			end
		end
	end

	return true
end
local function removeDriver(type)
	if not instance.drivers[type] then
		return false, "No driver with type "..type
	end

	-- Cleanup all driver instances first
	for side,driver in pairs(peripherals.drivers[type]) do
		driver:cleanup()
	end

	peripherals.drivers[type] = nil
	instance.drivers[type] = nil

	return true
end

local function attachPeripheral(side)
	local types = table.pack(peripheral.getType(side))
	local periph = peripheral.wrap(side)

	peripherals.connected[side] = {
		types = types,
		device = periph
	}

	-- Always provide a 'raw' driver as default
	peripherals.drivers.raw[side] = RawDriver:new{
		side = side,
		type = 'raw',
		device = periph
	}

	for i=1,types.n,1 do
		local type = types[i]

		attachDriver(type, side, periph)
	end

	os.queueEvent("kernel", "device", "attach", side, types)
end
local function detachPeripheral(side)
	local device = peripherals.connected[side]
	if not device then return end

	for i=1,device.types.n,1 do
		local type = device.types[i]

		detachDriver(type, side)
	end

	peripherals.drivers.raw[side]:cleanup()
	peripherals.drivers.raw[side] = nil

	peripherals.connected[side] = nil

	os.queueEvent("kernel", "device", "detach", side, device.types)
end


local function findDevices(type)
	local ofType = peripherals.drivers[type]
	if not ofType then
		return nil, "No driver for type "..type
	end

	local sideList = {}
	for side, dev in pairs(ofType) do
		table.insert(sideList, side)
	end

	return sideList
end
local function device(side, type)
	if not side then
		return nil, "Invalid side"
	end

	if not peripherals.connected[side] then
		return nil, "No device on side "..side
	end

	local ofType = peripherals.drivers[type]
	if not ofType then
		return nil, "No driver for type "..type
	end

	local dev = ofType[side]
	if not dev then
		return nil, "Device is not of type "..type
	end

	return dev
end




local function p_kernel(state, require_stop, norep)
	for _,name in ipairs(peripheral.getNames()) do
		attachPeripheral(name)
	end

	repeat
		local event = nextEvent()

		if event[1] == 'peripheral' then
			attachPeripheral(event[2])
		elseif event[1] == 'peripheral_detach' then
			detachPeripheral(event[2])
		end

		if event[1] == "stop_kernel" then
			-- Send a terminate event before exiting
			os.queueEvent("terminate", "stop_kernel")
		elseif event[1] == "terminate" then
			-- If require_stop then exit only on handling the special terminate
			-- event.  Otherwise exit on any terminate event
			if not require_stop or event[2] == "stop_kernel" then
				state.running = false
				state.exitStatus = "Kernel stopped"
			end
		end
	until norep or not state.running

	for name,device in pairs(peripherals.connected) do
		detachPeripheral(name)
	end
end

local function run(require_stop)
	if instance.running then
		return "Already running"
	end

	instance.running = true

	local state = {
		running = true,
		exitStatus = "Unknown"
	}

	-- Setup scheduler yield tracking
	lastYield = os.clock()

	-- Start kernel plugin process
	local pid = instance.start(p_kernel, state, require_stop)
	instance.nice(pid, -10)

	-- Run until exit or no processes remaining
	while state.running do
		if not tick() then
			-- Remove completed processes from table while idle
			processes:cleanup()

			if processes:hasRunnable() then
				yield()
			else
				state.exitStatus = "Process pool exhausted"
				state.running = false
			end
		end
	end

	instance.running = false

	return state.exitStatus
end

local function terminate()
	os.queueEvent("stop_kernel")
end



-- Seed RNG
math.randomseed(os.computerID() * os.clock() + os.computerID())

instance = {
	-- Manage process state
	start = start,
	exec = exec,
	resume = resume,
	suspend = suspend,
	stop = stop,
	nice = nice,

	-- Misc utilities
	wait = wait,
	atomic = atomic,
	task = task,

	-- Peripheral drivers
	drivers = {},
	addDriver = addDriver,
	removeDriver = removeDriver,

	findDevices = findDevices,
	device = device,

	-- Run the kernel
	run = run,
	running = running,
	terminate = terminate
}

return instance
