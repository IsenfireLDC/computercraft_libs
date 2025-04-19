-- <<<interface:kernel/driver|api:device>>>

local device = require("apis/device")

require("interfaces/kernel/driver")

MekReactorDriver = IDriver:new{}

function MekReactorDriver:ready()
	return self.device and self.device.isFormed()
end

function MekReactorDriver:start()
	if not self.device.getStatus() then
		self.device.activate()
	end
end
function MekReactorDriver:stop()
	if self.device.getStatus() then
		self.device.scram()
	end
end
function MekReactorDriver:scram()
	pcall(self.device.scram)
	self.device.setBurnRate(0)
end

function MekReactorDriver:state()
	if self.device.getStatus() then
		return "active"
	else
		return "inactive"
	end
end

function MekReactorDriver:getTemperature()
	return self.device.getTemperature()
end

function MekReactorDriver:getMaxBurnRate()
	return self.device.getMaxBurnRate()
end
function MekReactorDriver:getBurnRate()
	return self.device.getBurnRate()
end
function MekReactorDriver:setBurnRate(rate)
	return self.device.setBurnRate(rate)
end

function MekReactorDriver:getOutput()
	return self.device.getHeatingRate()
end


function MekReactorDriver:getDevices()
	return {
		sensors = device.mapDevices('sensor', self, {
			['reactor:burn'] = { self.getBurnRate, self.getMaxBurnRate },
			['reactor:enable'] = function(self) return self.device.getStatus() end,
			['reactor:temp'] = self.getTemperature,
			['reactor:heating'] = self.getOutput
		}),
		actuators = device.mapDevices('actuator', self, {
			['reactor:burn'] = self.setBurnRate,
			['reactor:enable'] = function(self, enable)
				if enable then
					self:start()
				else
					self:stop()
				end
			end
		})
	}
end
