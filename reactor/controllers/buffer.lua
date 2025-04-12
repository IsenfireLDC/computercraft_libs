-- <<<interface:reactor/controller|api:kernel,pid>>>

local kernel = require("apis/kernel")

require("interfaces/reactor/controller")

BufferController = IController:new{
	id = "unnamed",
	driverType = "ultimateEnergyCube",
	inputTarget = 0
}

function BufferController.init(id, level)
	level = level or 'ultimate'
	local driverType = level .. "EnergyCube"

	return BufferController:new{
		id = id,
		driverType = driverType
	}
end

function BufferController:resetLimits()
	self.limits = {}
end

function BufferController:updateTarget()
	self.inputTarget = self.target - self.driver:getFlow()
end
function BufferController:getInputTarget()
	return self.inputTarget
end

function BufferController:command(...)
	local cmd = table.pack(...)

	if cmd[1] == "status" then
		local status = {
			target = self.target,
			inputTarget = self.inputTarget,
			level = self.driver:getLevel(),
			flow = self.driver:getFlow(),
			max = self.driver:getMax()
		}

		if not cmd[2] or cmd[2] == 'all' then
			return true, status
		else
			return true, status[cmd[2]]
		end
	elseif cmd[1] == "target" then
		self:setTarget(cmd[2])

		return true
	elseif cmd[1] == "in_target" then
		return true, self.inputTarget
	end
end

function BufferController:run()
	if not self.driver then
		error("Controller cannot run without driver")
	end

	kernel.start(self.cmd, self)

	while true do
		self:updateTarget()

		sleep(1)
	end
end
function BufferController:cmd()
	while true do
		local event = kernel.wait(nil, "reactor", "command", "buffer", self.id)

		local response = table.pack(self:command(table.unpack(event, 5)))
		os.queueEvent("reactor", "response", "buffer", self.id, table.unpack(response))
	end
end
