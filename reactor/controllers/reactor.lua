-- <<<interface:device/controller|extensions:device/model,device/limits|api:kernel>>>

local kernel = require("apis/kernel")

require("interfaces/device/controller")
require("extensions/device/model")
require("extensions/device/limits")

ReactorController = Controller:new{
	type = 'reactor',
	extensions = { ModelExtension, LimitsExtension },
	requiredDevices = {
		sensors = {
			'reactor:burn',
			'reactor:enable',
			'reactor:temp',
			'reactor:heating'
		},
		actuators = {
			'reactor:burn',
			'reactor:enable'
		}
	},

	state = 'uninitialized',
	faults = {}
}

function ReactorController:resetLimits()
	self.limits = {
		temp = { warn = 800, safety = 1100 },
		burn = { min = 0 }
	}
end

function ReactorController:sendCommand(cmd, ...)
	local args = table.pack(...)

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
		if self.sensors['reactor:enable']:getValue() then
			return
		end

		-- enable reactor
		self.actuators['reactor:enable']:setValue(true)

		-- move to run
		self.state = 'run'

	elseif cmd == 'stop' then
		if not self.sensors['reactor:enable']:getValue() then
			return
		end

		-- disable reactor
		self.actuators['reactor:enable']:setValue(false)

		-- move to ready
		self.state = 'ready'

	elseif cmd == 'scram' then
		-- stop reactor
		self.actuators['reactor:enable']:setValue(false)

		-- move to safety
		self.state = 'safety'
	end
end

function ReactorController:getStatus(req)
	if req == 'state' then
		return self.state
	elseif req == 'faults' then
		return self.faults
	end

	return nil
end


function ReactorController:run()
	local g, dtype, name = self:checkDevices()
	if not g then
		error("Missing required "..dtype.." "..name)
	end

	local haveModel = self:loadModel()

	local maxBurn = self.sensors['reactor:burn']:getMax()
	if not self.limits.burn.max or maxBurn < self.limits.burn.max then
		self.limits.burn.max = maxBurn
	end

	local state = self.sensors['reactor:enable']:getValue()
	if state then
		self.state = 'run'
	else
		self.state = 'ready'
	end

	-- Bump the status monitor up a priority level
	local p_status = kernel.start(self.status, self)
	kernel.nice(p_status, -1)

	local count = 0
	while true do
		if self.state == "safety" then
			if self.sensors['reactor:enable']:getValue() then
				self.actuators['reactor:enable']:setValue(false)
			end
		elseif self.state == "ready" then
			-- nothing to do
		elseif self.state == "run" then
			local input = self.sensors['reactor:burn']:getValue()
			local output = self.sensors['reactor:heating']:getValue()
			self.model:tune(input, output)

			local setting = self:limit("burn", self.model:action(self.target))

			-- Try to avoid blowing up the reactor because we don't have a good model yet
			if not haveModel then
				local delta = setting - input

				-- Limit power increase to 5% per second to allow the model to tune
				if delta > self.limits.burn.max / 20 then
					setting = input + (self.limits.burn.max / 20 * (delta > 0 and 1 or -1))
				end
			end

			self.actuators['reactor:burn']:setValue(setting)

			-- Save the model every 30 seconds
			count = count + 1
			if count >= 30 then
				haveModel = true
				self:saveModel()
				count = 0
			end
		end

		sleep(1)
	end
end
function ReactorController:status()
	self.faults = {}

	while true do
		local temp = self.sensors['reactor:temp']:getValue()

		if temp > self.limits.temp.safety then
			if self.faults.temp ~= 'safety' then
				self.actuators['reactor:enable']:setValue(false)
				self.state = 'safety'
			end

			self.faults.temp = 'safety'
		elseif temp > self.limits.temp.warn then
			self.faults.temp = 'warn'
		else
			self.faults.temp = 'ok'
		end

		if self.state ~= "run" and self.sensors['reactor:enable']:getValue() then
			self.actuators['reactor:enable']:setValue(false)
			self.faults.bad_state = self.state
			self.state = 'safety'
		else
			self.faults.bad_state = nil
		end

		sleep(1)
	end
end



-- Initialize limits
ReactorController:resetLimits()
