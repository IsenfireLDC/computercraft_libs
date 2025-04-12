-- <<<interface:reactor/controller|api:kernel>>>

local kernel = require("apis/kernel")

require("interfaces/reactor/controller")

TurbineController = IController:new{
	id = "unnamed",
	driverType = "turbineValve",
	modelFile = "/data/models/turbine.dat"
}

function TurbineController.init(id)
	return TurbineController:new{
		id = id,
		modelFile = "/data/models/turbine-"..id..".dat"
	}
end

function TurbineController:resetLimits()
	self.limits = {
		flow = { min = 0 }
	}
end

function TurbineController:updateTarget()
	local input = self.driver:getInput()
	local output = self.driver:getOutput()
	self.model:tune(input, output)

	local setting = self:limit("flow", self.model:action(self.target))
	self.inputTarget = setting
end
function TurbineController:getInputTarget()
	return self.inputTarget
end

function TurbineController:command(...)
	local cmd = table.pack(...)

	if cmd[1] == "status" then
		local status = {
			target = self.target,
			inputTarget = self.inputTarget,
			input = self.driver:getInput(),
			output = self.driver:getOutput()
		}

		if not cmd[2] or cmd[2] == 'all' then
			return true, status
		else
			return true, status[cmd[2]]
		end
	elseif cmd[1] == "target" then
		self:setTarget(cmd[2])
		self:updateTarget()
		return true
	elseif cmd[1] == "in_target" then
		return true, self.inputTarget
	end
end

function TurbineController:run()
	if not self.driver then
		error("Controller cannot run without driver")
	end

	self:loadModel()

	kernel.start(self.cmd, self)

	local count = 0
	while true do
		self:updateTarget()

		count = count + 1
		if count >= 30 then
			count = 0
		end

		sleep(1)
	end
end
function ReactorController:cmd()
	while true do
		local event = kernel.wait(nil, "reactor", "command", "turbine", self.id)

		local response = table.pack(self:command(table.unpack(event, 5)))
		os.queueEvent("reactor", "response", "turbine", self.id, table.unpack(response))
	end
end
