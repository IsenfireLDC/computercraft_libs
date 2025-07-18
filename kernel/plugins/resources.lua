-- <<<api:kernel,interface:kernel/resources>>>

local kernel = require("apis/kernel")
require("interfaces/kernel/resources")

local instance

local reservations = {}



local function allocate(name, handler, ...)
	if handler == nil then handler = BasicResource end

	reservations[name] = handler:new(...)
end

local function deallocate(name)
	reservations[name]:delete()
	reservations[name] = nil
end



local function reserve(name, id, ...)
	return reservations[name]:reserve(kernel.pid(), id, ...)
end

local function release(name, id)
	reservations[name]:release(kernel.pid(), id)
end

local function check(name, id, ...)
	return reservations[name]:check(id, ...)
end



local function free(pid)
	pid = pid or kernel.pid()
	for name, handler in pairs(reservations) do
		handler:free(pid)
	end
end



instance = {
	allocate = allocate,
	deallocate = deallocate,
	reserve = reserve,
	release = release,
	check = check,
	free = free
}

return {
	handlers = {
		tick = function(event)
			if event[1] == 'kernel' and event[2] == 'process_complete' then
				instance.free(event[3])
			end
		end
		shutdown = function()
			for name,handler in pairs(reservations) do
				deallocate(name)
			end
		end
	},
	interface = instance
}
