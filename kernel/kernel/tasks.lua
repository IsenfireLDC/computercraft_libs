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


-- Lists current tasks
local function taskList()
	local tasklist = {}
	for timerID, info in pairs(tasks) do
		table.insert(tasklist, {
			tid = info.tid,
			time = info.time,
			timer = timerID,
			every = info.every
		})
	end

	return tasklist
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

	return tid
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
	if event[1] ~= "timer" then return end
	local timerID = event[2]
	if timerID == nil then return end

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
	taskList = taskList,
	schedule = schedule,
	cancel = cancel,

	dispatch = dispatch
}

return instance
