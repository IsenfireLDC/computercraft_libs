-- <<<interface:device/controller|api:kernel,pid>>>

local kernel = require("apis/kernel")
require("apis/pid")


SystemController = Controller:new{
	type = 'system:fission',
	extensions = {},
	requiredDevices = {
		sensors = {
			'buffer:energy'
		},
		controllers = {
			'turbine'
		}
	},

	state = 'uninitialized',
	target = 0.5
}


function SystemController:sendCommand(cmd, ...)
	local args = table.pack(...)

	-- Forward command to turbine
	self.controllers['turbine']:sendCommand(cmd, ...)

	if cmd == 'init' then
		-- start handler
		kernel.start(self.run, self)

		self.state = 'run'
	end
end

function SystemController:setTarget(target)
	Controller.setTarget(self, target)

	self.pid:setTarget(self.sensors['buffer:energy']:getMax() * target)
end

local systemPeriod = 5
function SystemController:run()
	local g, dtype, name = self:checkDevices()
	if not g then
		error("Missing required "..dtype.." "..name)
	end

	-- Setup PID
	-- TODO: Create extension for PID
	self.pid = PID.init(0.1, 0.0001, 0.1, 0.05, 20*systemPeriod)
	self:setTarget(self.target)

	while true do
		local target = self.pid:tick(self.sensors['buffer:energy']:getValue())
		self.controllers['turbine']:setTarget(target)

		sleep(systemPeriod)
	end
end
