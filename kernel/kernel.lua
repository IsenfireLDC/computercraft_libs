-- <<<mltable|table_extensions>>>
-- Generic Event Loop
-- Handles events based on user-provided handlers
--
-- -------------------- EVENTS --------------------
-- Pulls all events, including 'raw' events
--
-- Handles event "stop_kernel"
--     [1] - "stop_kernel"
--
-- Handles specialized version of "terminate"
--     [1] - "terminate"
--     [2] - "stop_kernel"
--
-- Kernel events:
-- kernel/
--     process_complete/
--         <pid>/ - PID of completed process
--             stopped - Process was stopped
--             finished - Process was not stopped
--
-- -------------------- HANDLERS --------------------
-- Handlers will be fed all parameters of the event in a list
--
-- -------------------- TABLES --------------------
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
--
-- Processes{nice: (entry)}
--     [_last_run] - Index of last process to run at this priority
--     [] - List of processes
--
-- -------------------- ENUMS --------------------
-- ProcState
--     [INIT]    - Not yet run
--     [RUN]     - Running
--     [SUSPEND] - Suspended
--     [STOP]    - Stopped
--
-- -------------------- PROGRAM --------------------
-- -------------------- PROGRAM --------------------

-- Modules
require("apis/mltable")
-- TODO: require("extensions/table")
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
local function getEvent(consume)
	if consume then
		if #eventQueue > 0 then
			return table.remove(eventQueue)
		else
			return { os.pullEventRaw() }
		end
	else
		table.insert(eventQueue, 1, { os.pullEventRaw() })
	end
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

    -- Only call event handlers at or below their max depth
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
-- [nice] { _last_run, [{Process}] }
local processes = { [0] = { _last_run = 0 }}
local proc_id = 1 -- 0 reserved for kernel
local nice = 0
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



-- [Utility]
-- Resumes a suspended process
local function resume(pid)
	local proc, msg = checkPID(pid)
	if proc == nil then return false, msg end

	proc.state = ProcState.RUN

	return true
end

-- [Utility]
-- Suspends a process
local function suspend(pid)
	local proc, msg = checkPID(pid)
	if proc == nil then return false, msg end

	proc.state = ProcState.SUSPEND

	return true
end

-- [Utility]
-- Stops a process
local function stop(pid)
	local proc, msg = checkPID(pid, false)
	if proc == nil then return false, msg end

	proc.state = ProcState.STOP

	return true
end

-- [Utility]
-- Sets process priority
local function priority(pid, nice)
	nice = nice or 0

	-- Update priorities list
	if table.find(priorities, nice) == nil then
		table.insert(priorities, nice)
		table.sort(priorities)

		processes[nice] = { _last_run = 0 }
	end

	local proc, msg = checkPID(pid)
	if proc == nil then return false, msg end

	table.insert(processes[nice], proc)
	table.remove(processes[msg], table.find(processes[msg], proc))

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


-- Yield tracker for scheduler.  Because it's running coroutines that yield, it doesn't actually yield automatically
local lastYield
-- Yield period in seconds
local yieldPeriod = 2

local _iterations = 0

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

	_iterations = _iterations + 1

	-- Walk up each level until we find a process to run
	while procList ~= nil and procList._last_run >= #procList do
		-- Remove empty levels
		if #procList == 0 then
			table.remove(priorities, level)
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

	-- Run the process we found
	local toRun = procList._last_run + 1
	local proc = procList[toRun]
	current_process = proc

	-- Yield regularly to keep CC happy
	if os.clock() - lastYield >= yieldPeriod then
		lastYield = os.clock()
		os.queueEvent("_kernel", "sched_yield")
		getEvent(false)
	else
		-- Wait for an event if we've spent too long on suspended processes
		if proc.state == ProcState.SUSPEND then
			suspend_count = suspend_count + 1
			if suspend_count > #priorities * table.len(processes, 2) then
				-- TODO: Run full check on process table to see if everything is suspended first
				-- TODO: Move suspended tasks to separate table/list?
				suspend_count = 0
				getEvent(false)
				lastYield = os.clock()
			end
		else
			suspend_count = 0
		end
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




-- [Process]
-- Process 0(priority -10): runs event handlers
local function p_kernel(state, require_stop, norep)
	repeat
		-- os.pullEventRaw yields
        local event = getEvent(true)

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

	local haveProc = true
	while state.running do
		if haveProc and not sched_next() then
			print("Process pool exhausted")
			haveProc = false
			--state.exitStatus = "Process pool exhausted"
			--state.running = false
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

    -- Manage interface classes
    add_interface = add_interface,
    remove_interface = remove_interface,

    -- Run the kernel
    run_until_event = run_until_event,
    run = run,
	terminate = terminate,
    is_running = is_running
}

return instance
