-- <<<>>>
-- Tasks

local instance

local tasks = {}
local r_tasks = {}

local g_tid = 0

-- [Helper]
local function getTID()
	local tid = g_tid
	g_tid = g_tid + 1

	return tid
end


-- Schedules (or reschedules) a task to run
-- The `tid` parameter is only for automatic rescheduling, and shouldn't be used otherwise
-- Set every to nil to disable repetition
local function schedule(task, time, every, tid)
	if not task or time == nil then return nil end
	tid = tid or getTID()

	local timer = os.startTimer(time)
	tasks[timer] = {
		tid = tid,
		func = func,
		time = time,
		every = every
	}

	-- Populate reverse lookup for cancelling
	r_tasks[tid] = timer
end

-- Cancels an existing task
-- Will cancel a task even if the event is already queued
local function cancel(tid)
	if tid == nil then return end

	local timerID = r_tasks[tid]
	if not timerID then return end

	os.cancelTimer(timerID)
	tasks[timerID] = nil
	r_tasks[tid] = nil
end


local function dispatch(event)
	if not event[1] == "timer" then return end
	local timerID = event[2]
	if not timerID then return end

	local task = tasks[timerID]
	tasks[timerID] = nil

	if not task or not task.func then return end

	task.func()

	if task.every ~= nil then
		instance.schedule(task.func, task.every, task.every, task.tid)
	else
		r_tasks[task.tid] = nil
	end
end


instance = {
	schedule,
	cancel,

	dispatch
}

return instance
