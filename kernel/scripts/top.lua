local kernel = require("apis/kernel")

local win = win
if _G._WINDOW then
	local w = peripheral.wrap(_G._WINDOW)

	win = window.create(w, 1, 1, w.getSize())
end

local function ps()
	local procs = kernel.processList()
	print("#"..#procs.." processes")

	print("    PID  NICE STATE   ARGS")
	for i,v in ipairs(procs) do
		print(string.format("[%d] %-4d %-4d %-7s %s", i, v.pid, v.nice, v.state, v.args))
	end
end

local function tasks()
	local tasks = kernel.tasks.taskList()
	print("#"..#tasks.." tasks")

	print("    TID  TIMER TIME EVERY")
	for i,v in ipairs(tasks) do
		print(string.format("[%d] %-4d %-5d %-4d", i, v.tid, v.timer, v.time), v.every)
	end
end

local function top()
	local iter = 0
	while true do
		local prev
		if win then
			prev = term.redirect(win)
		end

		term.clear()
		local size = {term.getSize()}
		term.setCursorPos(size[1]-4, 1)
		term.write(tostring(iter))

		term.setCursorPos(1, 1)
		ps()

		print()

		tasks()

		term.redirect(prev)
		iter = iter + 1

		kernel.sleep(1)
	end
end

kernel.start(top)
