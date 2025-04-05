-- <<<table_extensions>>>

require("apis/table_extensions")


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




function matchEventFilter(filter, event)
	for i, p in ipairs(filter) do
		if p ~= event[i] then
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
	if #self.events == 0 then
		if not matchEventFilter(self.eventFilter, e) then
			return false
		elseif self.state == ProcessState.WAIT then
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

	self:transition(ProcessState.RUN)
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
	if self.state == ProcessState.STOP then
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
		self:_onTransition(self.state, state)
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
		self:transition(proc.pid, from, to)
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
	if #self.active > 0 then
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
			status = "bad:" .. stateToStr(process.state)
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
local function nextEvent()
	return table.pack( coroutine.yield() )
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
	if not func then return nil, "Process cannot be nil" end

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




local function p_kernel(state, require_stop, norep)
	repeat
		local event = nextEvent()

		-- Send a terminate event before exiting
		if event[1] == "stop_kernel" then
			os.queueEvent("terminate", "stop_kernel")
		end

		if event[1] == "terminate" then
			-- If require_stop then exit only on handling the special terminate
			-- event.  Otherwise exit on any terminate event
			if not require_stop or event[2] == "stop_kernel" then
				state.running = false
				state.exitStatus = "Kernel stopped"
			end
		end
	until norep or not state.running
end

local function run(require_stop)
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

	return state.exitStatus
end

local function terminate()
	os.queueEvent("stop_kernel")
end




instance = {
	-- Manage process state
	start = start,
	resume = resume,
	suspend = suspend,
	stop = stop,
	nice = nice,

	-- Run the kernel
	run = run,
	terminate = terminate
}

return instance
