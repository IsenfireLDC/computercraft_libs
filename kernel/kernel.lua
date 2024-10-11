-- <<<mltable|table_extensions>>>
-- =====================================================================================================================
-- Kernel
-- =====================================================================================================================
-- Provides utilities for handling events, scheduling functions, and multiprocessing.
--
-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! IMPORTANT !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- DO NOT CALL THE FOLLOWING FUNCTIONS:
--     os.pullEvent
--     os.pullEventRaw
--
-- The kernel will handle all events.  Calling one of these functions in an event handler or task (especially with a
-- filter) will likely cause event handlers not to be called, timeouts to be ignored, and other bad things.  Calling
-- these in a process will cause your process to hang forever, and kernel to use significant resources attempting to
-- schedule it.
--
-- To use events with the kernel, register a handler using `kernel.add_handler`.  To run a function once, use
-- `kernel.add_temp_handler` or `kernel.schedule_on_event`.  Any code outside of a process must be event-driven.  In a
-- process, use the process utility `kernel.event_sleep` to wait for an event.
--
--
--
-- Subsystem Summaries
-- =====================================================================================================================
-- Generic Event Loop
-- ---------------------------------------------------------------------------------------------------------------------
-- Allows functions to be registered as handlers for given events.  Automatically runs all registered handlers whenever
-- an event is fired.  Handlers will be called for any matching events of equal or higher depth.  The depth of an event
-- is the number of parameters in the event, so an event my/fun/event would have a depth of 3.  If the max_level was set
-- when adding the handler, the handler will be only be called for matching events up to that depth.
--
-- Tasks Utility
-- ---------------------------------------------------------------------------------------------------------------------
-- Runs small functions once or on regular intervals.  The delay before the first run and the period can be different,
-- but the period cannot be changed.  Can also functions run on the next instance of an event, with a timeout.  Tasks
-- can be cancelled using the TID returned when they were scheduled initially.
--
-- Processes Utility
-- ---------------------------------------------------------------------------------------------------------------------
-- Creates processes from functions by converting them into coroutines.  Processes can be suspended, resumed, have
-- priority changed, or stopped using the PID returned when they were started. Uses a priority scheduler for running
-- coroutines (most negative == higest priority).  It is suggested not to use a higher priority than -10 (priority of
-- event handler process).  The default priority is 0.  The process utility functions do not need a PID, they will
-- automatically pull it from the running process.
--
--
--
-- Interface Documentation
-- =====================================================================================================================
-- Events
-- ---------------------------------------------------------------------------------------------------------------------
-- Pulls all events, including 'raw' events (terminate).  No user code should try to handle events directly (see
-- IMPORTANT above).
--
-- Handles: <ALL>
-- stop_kernel - Send a terminate event to all handlers, then queue terminate/stop_kernel
-- terminate/
--     stop_kernel - Stop the kernel
--
-- Generates:
-- kernel/
--     process_complete/
--         <pid>/ - PID of completed process
--             stopped - Process was stopped
--             finished - Process was not stopped
--
-- Handlers
-- ---------------------------------------------------------------------------------------------------------------------
-- Handlers will be fed all parameters of the event in a list.  An event with parameters my/fun/event will be
-- passed as { "my", "fun", "event" }.  The handler registration functions require the parameters separately, so to
-- register a handler for this event, call `kernel.add_handler(func, 0, "my", "fun", "event")`.  Handlers for my/ and
-- my/fun will also be called, unless they specify a max_depth of 1 or 2.
--
--
--
-- Internals Documentation
-- =====================================================================================================================
-- Tables
-- ---------------------------------------------------------------------------------------------------------------------
-- Task
--     [task]  - Function to call
--     [time]  - Delay for call 
--     [every] - Delay for repetition (nil for single)
--
-- Process
--     [pid]   - Process ID
--     [proc]  - Coroutine to run
--     [args]  - Arguments passed to the process
--     [state] - Status <ProcState>
-- opt [msg]   - Error message (If process errored)
--
-- Processes{nice: (entry)}
--     [_last_run]  - Index of last process to run at this priority
--     [_suspended] - List of suspended processes
--     []           - List of processes
--
-- Enums
-- ---------------------------------------------------------------------------------------------------------------------
-- ProcState
--     [INIT]    - Not yet run
--     [RUN]     - Running
--     [SUSPEND] - Suspended
--     [STOP]    - Stopped
--
-- -------------------- PROGRAM START --------------------

-- Modules
require("apis/mltable")
-- TODO: Move extensions to different directory: require("extensions/table")
require("apis/table_extensions")

-- Settings

-- Globals
-- Table to be filled with functions
local instance = {}

local event_handlers = MLTable:new()
local event_interfaces = MLTable:new()

-- Status flag
local running = false


-- Adds a handler for any event types
-- Pass the event parameters for the event that this will handle
-- Handler should expect a list of arguments as a table
-- All registered handlers will be called
local function add_handler(handler, max_level, ...)
	max_level = max_level or 0

	event_handlers:add(handler, max_level, ...)
end

-- Removes the given handler from the given event
-- Pass the event parameters for the event that this was added with
local function remove_handler(handler, ...)
	event_handlers:remove(handler, ...)
end

-- Register an interface class for event handling
-- Will dispatch handled events to the requested method
--
-- Arg method must be a string containing the method name
-- NOTE: Only one method per class per event
local function add_interface(class, method, ...)
	if not class or not method then
		return false, "Missing class or method"
	end

	event_interfaces:add(class, method, ...)

	return true
end

-- Remove an interface class method
local function remove_interface(class, method, ...)
	if not class or not method then return end

	event_interfaces:remove(class, method, ...)
end


-- [Helper]
-- Handles dispatching events
local function dispatch_event(event)
	local handlers = event_handlers:get_all_set(table.unpack(event))

	-- Only call event handlers at or below their max depth
	for handler,lev in pairs(handlers) do
		if lev == 0 or #event <= lev then
			handler(event)
		end
	end


	-- Also dispatch events to interfaces
	local interfaces = event_interfaces:get_all_set(table.unpack(event))

	for instance,method in pairs(interfaces) do
		method(instance, event)
	end
end


local eventQueue = {}
local function requeueEvents(single)
	-- Grab the next event and exit
	if single then
		table.insert(eventQueue, { os.pullEventRaw() })
		return 1
	end

	-- Add sentinal to the end of the queue and grab all events
	os.queueEvent("_kernel", "sched_event")
	local nEvent = -1
	repeat
		local event = { os.pullEventRaw() }
		table.insert(eventQueue, event)

		nEvent = nEvent + 1
	until event[1] == "_kernel" and event[2] == "sched_event"

	return nEvent
end

local function nextEvent()
	while #eventQueue == 0 do
		instance.suspend(0)
		coroutine.yield()
	end

	return table.remove(eventQueue, 1)
end


-- -------------------- TASKS UTILITY --------------------
-- Scheduled tasks list
-- [timer_id] {Task}
local tasks = {}
local rtasks = {}

-- Event tasks & temp handlers
local waiting_on_event = MLTable:new()
local temp_handlers = MLTable:new()
local waiting_timeouts = {}

local last_tid = 0

-- [Helper]
-- Gets the next available task id
local function next_tid()
	last_tid = last_tid + 1

	return last_tid
end

-- [Handler]
-- Handles calling a scheduled task on a timer event
local function h_task(event)
	if not event[2] then return end

	local task = tasks[event[2]]
	if not task or not task.task then return end

	task.task()

	if task.every ~= nil then
		instance.schedule(task.task, task.every, task.every, task.tid)
	else
		rtasks[task.tid] = nil
	end

	tasks[event[2]] = nil
end

-- [Utility]
-- Schedules a function as a task
local function schedule(task, time, every, tid)
	if not task or time == nil then return nil end
	tid = tid or next_tid()

	local timer = os.startTimer(time)
	tasks[timer] = {
		tid = tid,
		task = task,
		time = time,
		every = every
	}

	rtasks[tid] = timer

	return tid
end


-- [Helper]
-- Handles dispatching tasks waiting on events
local function dispatch_event_task(event)
	-- TEMP HANDLERS
	-- Call any temporary handlers
	local handlers = temp_handlers:get_all_set(table.unpack(event))

	-- Run and cancel timeouts for handlers
	for handler,tid in pairs(handlers) do
		handler(event)

		if tid > 0 then
			os.cancelTimer(tid)
			waiting_timeouts[tid] = nil
		end
	end

	-- Remove called handlers
	temp_handlers:remove_all(table.unpack(event))


	-- TASKS
	-- Call any waiting tasks
	local waiting = waiting_on_event:get_all_set(table.unpack(event))

	-- Cancel timeouts for any called tasks
	for task,tid in pairs(waiting) do
		task(true)

		if tid > 0 then
			os.cancelTimer(tid)
			waiting_timeouts[tid] = nil
		end
	end

	-- Delete all tasks that were called
	waiting_on_event:remove_all(table.unpack(event))
end

-- [Handler]
-- Handles timer events and removes events if they time out
local function h_task_timeout(event)
	local task_info = waiting_timeouts[event[2]]
	
	-- Cancel the task if it is waiting
	if task_info then
		-- TODO: Is this correct behavior?
		task_info.handler(false)

		waiting_on_event:remove(task_info.handler, table.unpack(task_info.path))
		rtasks[task_info.tid] = nil
	end

	waiting_timeouts[event[2]] = nil
end

-- [Utility]
-- Calls a function on an event once
-- Will wait forever if timout is 0 or nil
local function schedule_on_event(task, timeout, ...)
	if not task then return end
	local tid = next_tid()

	local vargs = { ... }

	-- Setup timeout, if requested
	local timer = -1
	if timeout then
		timer = os.startTimer(timeout)

		waiting_timeouts[timer] = {
			tid = tid,
			handler = task,
			path = vargs
		}
	end

	-- Note: Had vargs here for aiding in deletion, re-add if necessary
	waiting_on_event:add(task, timer, ...)

	rtasks[tid] = {task=task, timer=timer, path=vargs}

	return tid
end

-- [Utility]
-- Cancels a scheduled task
local function cancel(task_id)
	if not task_id then return end

	local meta = rtasks[task_id]
	if not meta then return end

	-- Event task
	if type(meta) == "table" then
		if meta.timer then
			os.cancelTimer(meta.timer)
			waiting_timeouts[meta.timer] = nil
		end

		waiting_on_event:remove(meta.task, table.unpack(meta.path))
	
	-- Normal task
	else
		os.cancelTimer(meta)
		tasks[meta] = nil
		rtasks[task_id] = nil
	end
end


-- [Utility]
-- Sets a one-time temporary handler for a specific event
local function add_temp_handler(handler, timeout, ...)
	if not handler then return end

	local vargs = { ... }

	-- Setup timeout, if requested
	local tid = -1
	if timeout then
		tid = os.startTimer(timeout)

		waiting_timeouts[tid] = {
			handler = handler,
			path = vargs
		}
	end

	-- Note: Had vargs here for aiding in deletion, re-add if necessary
	temp_handlers:add(handler, tid, ...)
end

-- -------------------- END TASKS UTILITY --------------------



-- -------------------- PROCESSES UTILITY --------------------
-- [nice] { _last_run, _suspended[{Process}], [{Process}] }
local processes = { [0] = { _last_run = 0, _suspended = {} }}
local proc_id = 1 -- 0 reserved for kernel
local nice = 0 -- Initial priority for new processes
local priorities = {0}

local BAD_PID = -1

local ProcState = {
	INVALID = -1,
	INIT = 0,
	RUN = 1,
	SUSPEND = 2,
	STOP = 3,
	FINISH = 4,
	ERROR = 5
}

-- [Helper]
-- Converts ProcState enum to string
local function stateToStr(state)
	return table.getkey(ProcState, state)
end


local Process = {
	pid = BAD_PID,
	proc = nil,
	args = {},
	state = ProcState.INVALID
}
function Process:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	self.__index = self

	return obj
end
function Process:__eq(other)
	return self.pid == other.pid
end
function Process:run()
	if self.state == ProcState.STOP then
		return false
	end

	if self.state == ProcState.INIT then
		self.state = ProcState.RUN
		coroutine.resume(self.proc, table.unpack(self.args))
	elseif self.state == ProcState.RUN then
		coroutine.resume(self.proc)
	end

	return coroutine.status(self.proc) ~= "dead"
end


-- Currently running process
-- Set by scheduler and used in process utilities
local current_process = Process

-- [Helper]
-- Generates next pid
local pidOverride = BAD_PID
local function nextPID()
	local pid = proc_id

	if pidOverride >= 0 then
		pid = pidOverride
		pidOverride = BAD_PID
	else
		proc_id = proc_id + 1
	end

	return pid
end



-- [Utility]
-- Starts a coroutine on the given function
local function start(process, ...)
	if not process then return nil, "Process cannot be nil" end

	-- Create process entry
	local pid = nextPID()
	local proc = Process:new{
		pid = pid,
		args = { ... },
		state = ProcState.INIT
	}

	-- Create coroutine for the process
	proc.proc = coroutine.create(function(...)
		local g, msg = pcall(process, ...)
		if g then
			proc.state = ProcState.FINISH
		else
			proc.state = ProcState.ERROR
		end

		proc.msg = msg
	end)
	if proc.proc == nil then return nil, "Could not create coroutine" end

	-- Register the process in the process table
	table.insert(processes[nice], proc)

	return pid
end




-- [Helper]
-- Gets the process associated with the given PID
local function getProcById(pid)
	if pid == nil or pid < 0 then return nil, "Invalid PID" end

	for priority, plist in pairs(processes) do
		for _, proc in ipairs(plist) do
			if proc.pid == pid then
				return proc, priority
			end
		end

		-- Also check suspended processes
		for _, proc in ipairs(plist._suspended) do
			if proc.pid == pid then
				return proc, priority
			end
		end
	end

	return nil, "No process found"
end

-- [Helper]
-- Checks that the pid belongs to a valid process
local function checkPID(pid, nostop)
	if nostop == nil then nostop = true end

	local proc, priority = getProcById(pid)
	if proc == nil then return nil, "Invalid process" end
	if nostop and proc.state == ProcState.STOP then return nil, "Process stopped" end

	return proc, priority
end

-- [Helper]
-- Moves process to the appropriate process list
local function changeState(proc, nice, state)
	-- Suspended processes are in a sub-list
	if proc.state == ProcState.SUSPEND then
		if state == ProcState.SUSPEND then return end

		table.insert(processes[nice], proc)
		table.remove(processes[nice]._suspended, table.find(processes[nice]._suspended, proc))
	elseif state == ProcState.SUSPEND then
		table.insert(processes[nice]._suspended, proc)
		table.remove(processes[nice], table.find(processes[nice], proc))
	end

	proc.state = state
end



-- [Utility]
-- Resumes a suspended process
local function resume(pid)
	local proc, msg = checkPID(pid)
	if proc == nil then return false, msg end

	changeState(proc, msg, ProcState.RUN)

	return true
end

-- [Utility]
-- Suspends a process
local function suspend(pid)
	local proc, msg = checkPID(pid)
	if proc == nil then return false, msg end

	changeState(proc, msg, ProcState.SUSPEND)

	return true
end

-- [Utility]
-- Stops a process
local function stop(pid)
	local proc, msg = checkPID(pid, false)
	if proc == nil then return false, msg end

	changeState(proc, msg, ProcState.STOP)

	return true
end

-- [Utility]
-- Sets process priority; most negative is highest priority
local function priority(pid, nice)
	nice = nice or 0

	-- Update priorities list
	if table.find(priorities, nice) == nil then
		table.insert(priorities, nice)
		table.sort(priorities)

		processes[nice] = { _last_run = 0, _suspended = {} }
	end

	local proc, msg = checkPID(pid)
	if proc == nil then return false, msg end

	-- Temporarily move to run state to ensure the process is in the normal list
	local state = proc.state
	changeState(proc, msg, ProcState.RUN)
	table.insert(processes[nice], proc)
	table.remove(processes[msg], table.find(processes[msg], proc))
	changeState(proc, msg, state)

	return true
end


-- [Utility]
-- Returns list of all processes with their priorities
local function process_list()
	local procs = {}

	for nice, procList in pairs(processes) do
		for _, proc in ipairs(procList) do
			table.insert(procs, {
				nice = nice,
				pid = proc.pid,
				state = stateToStr(proc.state),
				args = table.concat2(proc.args, " ")
			})
		end

		-- Also list suspended processes
		for _, proc in ipairs(procList._suspended) do
			table.insert(procs, {
				nice = nice,
				pid = proc.pid,
				state = stateToStr(proc.state),
				args = table.concat2(proc.args, " ")
			})
		end
	end

	return procs
end


-- [Process Utility]
-- Causes the current process to sleep for the given duration
local function sleep(time)
	local pid = current_process.pid
	if pid == BAD_PID then
		return false, "Not in a process"
	end

	instance.suspend(pid)

	-- Resume this process after the specified time
	instance.schedule(function() instance.resume(pid) end, time)

	-- Yield the process
	coroutine.yield()

	return true
end


-- [Process Utility]
-- Waits for the given PID to complete
local function wait(pid, timeout)
	local pid = current_process.pid
	if pid == BAD_PID then
		return nil, "Not in a process"
	end

	instance.suspend(pid)

	-- Resume this process after the specified event or timeout
	instance.add_temp_handler(function(e) instance.resume(pid, e[4] == "finished") end, timeout, "kernel", "process_complete", pid)

	-- Yield the process, return whether finished successfully
	return coroutine.yield()
end


-- [Process Utility]
-- Creates a copy of the current process
-- TODO: Untested, seems super jank and unlikely to work
local function fork()
	local pid = current_process.pid
	if pid == BAD_PID then
		return nil, "Not in a process"
	end

	local parent, nice = getProcById(pid)
	local child = Process:new{
		pid = nextPID(),
		proc = table.deepcopy(parent.proc),
		args = { 0 },
		state = ProcState.INIT
	}
	table.insert(processes[nice], child)

	return child.pid
end


-- [Process Utility]
-- Suspends process until event occurs or timeout
-- Timeout of nil/0 will wait forever
local function event_sleep(timeout, ...)
	local pid = current_process.pid
	if pid == BAD_PID then
		return false, "Not in a process"
	end

	instance.suspend(pid)

	-- Resume this process after the specified event or timeout
	instance.schedule_on_event(function() instance.resume(pid) end, timeout, ...)

	-- Yield the process
	coroutine.yield()

	return true
end


-- Yield tracker for scheduler.  Because it's running coroutines that yield, it doesn't actually yield automatically
local lastYield
-- Yield period in seconds
local yieldPeriod = 2

-- Scheduler iteration count, used for testing performance (down from 4M to 13 on a test program :D)
local _iterations = 0

-- [Helper]
-- Requeue events and wake the event handler process if there were any
local function sched_event(single)
	if requeueEvents(single) > 0 then
		local g, msg = instance.resume(0)
	end
end
-- [Helper]
-- An event handling a day keeps the "Too long without yielding" away!
-- Yields from the kernel to CC so we can keep running
-- Quick mode queues an event so the scheduler is guaranteed to restart immediately
-- Non-quick mode yields until the next natural event for when all processes are suspended
local function sched_yield(quick)
	if quick then
		os.queueEvent("_kernel", "sched_yield")
	end

	sched_event(true)
	lastYield = os.clock()
end

-- Priority scheduler
-- Runs each item in a level before running an item in a higher (lower priority) level
-- Example { [-1]#2, [0]#3, [1]#2, [2]#1 }:
--  2:                                    1                                   1
--  1:            1           2                       1           2            
--  0:   1  2  3     1  2  3     1  2  3     1  2  3     1  2  3     1  2  3   
-- -1: 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 
--
-- Returns whether there are processes remaining
local function sched_next()
	local level = 1
	local procList = processes[priorities[level]]
	local is_suspended = {}

	-- Grab all available events
	sched_event(false)

	_iterations = _iterations + 1

	-- Walk up each level until we find a process to run
	while procList ~= nil and not is_suspended[level] and procList._last_run >= #procList do
		-- Remove empty levels
		if #procList == 0 then
			-- If all processes are suspended, level wil appear empty, but should not be deleted
			if #procList._suspended > 0 then
				is_suspended[level] = true
			else
				table.remove(priorities, level)
			end
		else
			level = level + 1

			-- Reset _last_run to 0 so we know to run the first task next time
			procList._last_run = 0
		end

		-- Wrap around if we pass the end
		if level > #priorities then
			level = 1
		end

		-- Refresh the local pointer
		procList = processes[priorities[level]]
	end

	-- If we ran out of levels, there's nothing else to do
	if procList == nil then return false end

	-- If there are only suspended processes, wait for an event and try again
	if is_suspended[level] then
		sched_yield()
		return true
	end

	-- Run the process we found
	local toRun = procList._last_run + 1
	local proc = procList[toRun]
	current_process = proc

	-- Yield regularly to keep CC happy
	if os.clock() - lastYield >= yieldPeriod then
		sched_yield(true)
	end

	if not proc:run() then
		-- Remove stopped or finished processes
		table.remove(procList, toRun)

		-- Don't skip the following process
		toRun = toRun - 1

		-- Queue event to indicate process completion
		proc_status = "unknown"
		if proc.state == ProcState.STOP then
			proc_status = "stopped"
		elseif proc.state == ProcState.FINISH then
			proc_status = "finished"
		elseif proc.state == ProcState.ERROR then
			proc_status = "errored"
		end
		os.queueEvent("kernel", "process_complete", proc.pid, proc_status)
	end
	procList._last_run = toRun

	-- Reset to default to indicate that the program is not in a process
	current_process = Process

	-- There might be more to do
	return true
end
-- -------------------- END PROCESSES UTILITY --------------------




-- -------------------- MISC UTILITY --------------------
-- [Utility]
-- Runs a function atomically (without yielding to CC)
local function atomic(func)
	local status = {}
	local c = coroutine.create(function()
		local g, msg = pcall(func)

		status.g = g
		status.msg = msg
	end)

	repeat
		coroutine.resume(c)
	until coroutine.status(c) == "dead"

	return status.g, status.msg
end
-- -------------------- END MISC UTILITY --------------------




-- -------------------- KERNEL MAIN --------------------
-- [Process]
-- Process 0(priority -10): runs event handlers
local function p_kernel(state, require_stop, norep)
	repeat
		-- os.pullEventRaw yields
		local event = nextEvent()

		dispatch_event(event)
		dispatch_event_task(event)

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

-- [Utility]
-- If kernel is not running, handles events until the given event happens
local function run_until_event(timeout, ...)
	if not running then
		local function did_run(success) end
		schedule_on_event(did_run, timeout, ...)

		-- Handle events until task is triggered or times out
		while waiting_on_event:get(did_run, ...) do
			local event = {os.pullEventRaw()}

			dispatch_event(event)
			dispatch_event_task(event)
		end
	end
end


-- Performs system-wide initialization
local function init()
	-- Seed RNG
	math.randomseed(os.computerID() * os.clock() + os.computerID())
end

-- Main program
-- Handle events with registered handlers
local function run(require_stop)
	instance.add_handler(h_task, 0, "timer")
	instance.add_handler(h_task_timeout, 0, "timer")

	local state = {
		running = true,
		exitStatus = "Unknown"
	}

	-- Setup scheduler yield tracking
	lastYield = os.clock()

	pidOverride = 0
	local pid = instance.start(p_kernel, state, require_stop)
	instance.priority(pid, -10)
	--instance.suspend(pid)

	while state.running do
		if not sched_next() then
			state.exitStatus = "Process pool exhausted"
			state.running = false
		end

		--p_kernel(state, require_stop, true)
	end

	return state.exitStatus, _iterations
end

local function terminate()
	os.queueEvent("stop_kernel")
end

-- Returns the running status flag
local function is_running()
	return running
end




-- Initialize system
init()

instance = {
	-- Manage event handlers
	add_handler = add_handler,
	remove_handler = remove_handler,
	add_temp_handler = add_temp_handler, -- Part of tasks utility, but handles event and cannot be canceled

	-- Tasks utility
	schedule = schedule,
	schedule_on_event = schedule_on_event,
	cancel = cancel,

	-- Processes utility
	start = start,
	resume = resume,
	suspend = suspend,
	stop = stop,
	priority = priority,
	process_list = process_list,
	-- Process-specific utilties (should only be called in a process)
	sleep = sleep,
	wait = wait, -- Use the kernel/process_complete event outside of a process
	fork = fork,
	event_sleep = event_sleep,

	-- Manage interface classes
	add_interface = add_interface,
	remove_interface = remove_interface,

	-- Misc utilites
	atomic = atomic,

	-- Run the kernel
	run_until_event = run_until_event,
	run = run,
	terminate = terminate,
	is_running = is_running
}

return instance
