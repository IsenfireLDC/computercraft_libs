-- <<<interface:device/device>>>

require("interfaces/device/device")

Controller = Device:new{
	class = 'controller',
	state = 'unknown',
	requiredDevices = {
		sensors = {},
		controllers = {},
		actuators = {}
	},
	sensors = {},
	controllers = {},
	actuators = {},

	target = 0
}

function Controller:checkDevices()
	if self.requiredDevices.sensors then
		for _,v in ipairs(self.requiredDevices.sensors) do
			if not self.sensors[v] then
				return false, 'sensor', v
			end
		end
	end

	if self.requiredDevices.controllers then
		for _,v in ipairs(self.requiredDevices.controllers) do
			if not self.controllers[v] then
				return false, 'controller', v
			end
		end
	end

	if self.requiredDevices.actuators then
		for _,v in ipairs(self.requiredDevices.actuators) do
			if not self.actuators[v] then
				return false, 'actuator', v
			end
		end
	end

	return true
end

function Controller:setTarget(target)
	self.target = target
end

function Controller:getTarget()
	return self.target
end


function Controller:sendCommand(cmd, ...)
	local args = table.pack(...)

	if cmd == 'state' then
		self.state = args[1]
	end
end

function Controller:getStatus(req)
	if req == 'state' then
		return self.state
	end

	return nil
end
