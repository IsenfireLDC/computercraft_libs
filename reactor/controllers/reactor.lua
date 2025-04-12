-- <<<interface:reactor/controller|api:kernel>>>

local kernel = require("apis/kernel")

require("interfaces/reactor/controller")

ReactorController = IController:new{
	id = "unnamed",
	driverType = "fissionReactorLogicAdapter",
	modelFile = "/data/models/reactor.dat",
	state = 'ready'
}

function ReactorController.init(id)
	return ReactorController:new{
		id = id,
		modelFile = "/data/models/reactor-"..id..".dat"
	}
end

function ReactorController:resetLimits()
	self.limits = {
		temp = { warn = 800, safety = 1100 },
		burn = { min = 0 }
	}
end

function ReactorController:transition(state)
	self.state = state
	os.queueEvent("reactor", "state", self.id, state)
end

function ReactorController:command(...)
	local cmd = table.pack(...)

	if cmd[1] == "status" then
		local status = {
			status = self.driver:state(),
			state = self.state,
			faults = self.faults,
			target = self.target,
			burn = self.driver:getBurnRate(),
			temp = self.driver:getTemperature(),
			output = self.driver:getOutput()
		}

		if not cmd[2] or cmd[2] == 'all' then
			return true, status
		else
			return true, status[cmd[2]]
		end
	elseif cmd[1] == "reset" then
		self:transition("reset")
		return true
	elseif cmd[1] == "scram" then
		self:transition("scram")
		return true

	elseif self.state == "safety" then
		return false, "Must clear safety fault"
	elseif cmd[1] == "start" then
		if self.driver:state() == "inactive" then
			self.driver:start()

			self:transition("run")
			return true
		else
			return false, "Already running"
		end
	elseif cmd[1] == "stop" then
		if self.driver:state() == "active" then
			self.driver:stop()

			self:transition("ready")
			return true
		else
			return false, "Not running"
		end
	elseif cmd[1] == "target" then
		self:setTarget(cmd[2])
		return true
	end
end

function ReactorController:fault(name, level)
	if self.faults[name] ~= level then
		os.queueEvent("fault", level, "reactor", self.id, name)

		self.faults[name] = level

		return true
	end

	return false
end

function ReactorController:run()
	if not self.driver then
		error("Controller cannot run without driver")
	end

	self:loadModel()

	local maxBurn = self.driver:getMaxBurnRate()
	if not self.limits.burn.max or maxBurn < self.limits.burn.max then
		self.limits.burn.max = maxBurn
	end

	if self.driver:state() == 'active' then
		self:transition('run')
	end

	kernel.start(self.cmd, self)

	local count = 0
	while true do
		if self.state == "scram" then
			if self.driver:state() == 'active' then
				self.driver:scram()
			end
			self:transition("safety")
		elseif self.state == "reset" then
			self.driver:stop()
			self:transition("ready")
		elseif self.state == "run" then
			-- TODO: getInput?
			local input = self.driver:getBurnRate()
			local output = self.driver:getOutput()
			self.model:tune(input, output)

			local setting = self:limit("burn", self.model:action(self.target))
			local delta = setting - self.driver:getBurnRate()
			if delta > self.limits.burn.max / 4 then
				setting = self.driver:getBurnRate() + (self.limits.burn.max / 4 * (delta > 0 and 1 or -1))
			end

			self.driver:setBurnRate(setting)
		end

		count = count + 1
		if count >= 30 then
			self:saveModel()
			count = 0
		end

		sleep(1)
	end
end
function ReactorController:failsafe()
	if not self.driver then
		error("Controller cannot run without driver")
	end

	self.faults = {}

	while true do
		local temp = self.driver:getTemperature()

		if temp > self.limits.temp.safety then
			if self:fault('hi_temp', 'safety') then
				self.driver:scram()
				self:transition('safety')
			end
		elseif temp > self.limits.temp.warn then
			self:fault('hi_temp', 'warn')
		else
			self:fault('hi_temp', 'ok')
		end

		if self.state ~= "run" and self.driver:state() == 'active' then
			self.driver:scram()
			self:fault('bad_state', self.state)
			self:transition('safety')
		else
			self:fault('bad_state', nil)
		end

		sleep(1)
	end
end
function ReactorController:cmd()
	while true do
		local event = kernel.wait(nil, "reactor", "command", "reactor", self.id)

		local response = table.pack(self:command(table.unpack(event, 5)))
		os.queueEvent("reactor", "response", "reactor", self.id, table.unpack(response))
	end
end
