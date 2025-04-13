-- <<<api:kernel,pid>>>
-- Reactor Controller

local kernel = require("apis/kernel")
require("apis/pid")

Controller = {
	id = 'default',
	reactor = nil, -- ReactorController
	turbine = nil, -- TurbineController
	buffer = nil   -- BufferDriver
}

function Controller:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function Controller.init(reactor, turbine, buffer, id, pid)
	return Controller:new{
		id = id or 'default',
		reactor = reactor,
		turbine = turbine,
		buffer = buffer,
		pid = pid or PID.init(0.1, 0.0001, 0.1, 0.05, 20*5)
	}
end

function Controller:start()
	self.reactor:start()
	self.turbine:start()

	while not self.buffer:ready() do
		sleep(1)
	end

	kernel.start(self.run, self)
end

function Controller:command(...)
	local cmd = table.pack(...)

	if cmd[1] == 'status' then
		local g, reactor = self.reactor:command('status')
		local g, turbine = self.turbine:command('status')

		local status = {
			reactor = reactor,
			turbine = turbine,
			buffer = {
				level = self.buffer:getLevel(),
				max = self.buffer:getMax(),
			}
		}

		if not cmd[2] or cmd[2] == 'all' then
			return true, status
		else
			return true, status[cmd[2]]
		end
	end

	return self.reactor:command(...)
end

function Controller:run()
	kernel.start(self.cmd, self)

	self.pid:setTarget(self.buffer:getMax() * 0.5)

	print("Controller running")
	while true do
		local powerTarget = self.pid:tick(self.buffer:getLevel())
		self.turbine:setTarget(powerTarget)

		local steamTarget = self.turbine:getInputTarget()
		self.reactor:setTarget(steamTarget)

		sleep(5)
	end
end
function Controller:cmd()
	while true do
		local event = kernel.wait(nil, "reactor", "command", "controller", self.id)

		local response = table.pack(self:command(table.unpack(event, 5)))
		os.queueEvent("reactor", "response", "controller", self.id, table.unpack(response))
	end
end
