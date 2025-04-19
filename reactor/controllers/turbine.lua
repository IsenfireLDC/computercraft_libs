-- <<<interface:device/controller|extensions:device/model,device/limits|api:kernel>>>

local kernel = require("apis/kernel")

require("interfaces/device/controller")
require("extensions/device/model")
require("extensions/device/limits")

TurbineController = Controller:new{
	type = 'turbine',
	extensions = { ModelExtension, LimitsExtension },
	requiredDevices = {
		sensors = {
			'turbine:flow',
			'turbine:power'
		},
		controllers = {
			'reactor'
		}
	},

	state = 'uninitialized'
}


function TurbineController:resetLimits()
	self.limits = {
		flow = { min = 0 }
	}
end

function TurbineController:sendCommand(cmd, ...)
	local args = table.pack(...)

	-- Forward command to reactor
	self.controllers['reactor']:sendCommand(cmd, ...)

	if cmd == 'init' then
		-- start handler
		kernel.start(self.run, self)

		-- move to ready
		self.state = 'ready'
	elseif cmd == 'reset' then
		-- clear faults
		self.faults = {}

		-- move to ready
		self.state = 'ready'
	elseif cmd == 'start' then
		-- move to run
		self.state = 'run'
	elseif cmd == 'stop' then
		-- move to ready
		self.state = 'ready'
	elseif cmd == 'scram' then
		-- move to safety
		self.state = 'safety'
	end
end

function TurbineController:run()
	local g, dtype, name = self:checkDevices()
	if not g then
		error("Missing required "..dtype.." "..name)
	end

	self:loadModel()

	local maxFlow = self.sensors['turbine:flow']:getMax()
	if not self.limits.flow.max or maxFlow < self.limits.flow.max then
		self.limits.flow.max = maxFlow
	end

	-- Match reactor state
	self.state = self.controllers['reactor']:getStatus('state')

	local count = 0
	while true do
		if self.state == 'safety' then
			self.controllers['reactor']:setTarget(0)
		elseif self.state == 'ready' then
			-- nothing to do
		elseif self.state == 'run' then
			local input = self.sensors['turbine:flow']:getValue()
			local output = self.sensors['turbine:power']:getValue()
			self.model:tune(input, output)

			local setting = self:limit("flow", self.model:action(self.target))
			self.controllers['reactor']:setTarget(setting)
		end

		local rState = self.controllers['reactor']:getStatus('state')
		if rState ~= self.state then
			self.state = rState
		end

		-- Save the model every 30 seconds
		count = count + 1
		if count >= 30 then
			self:saveModel()
			count = 0
		end

		sleep(1)
	end
end

-- Initialize limits
TurbineController:resetLimits()
