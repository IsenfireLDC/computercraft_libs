-- <<<interface:kernel/driver|api:device>>>

local device = require("apis/device")

require("interfaces/kernel/driver")

MekTurbineDriver = IDriver:new{}

function MekTurbineDriver:ready()
	return self.device and self.device.isFormed()
end

function MekTurbineDriver:getInputMax()
	return self.device.getMaxFlowRate()
end
function MekTurbineDriver:getInput()
	return self.device.getFlowRate()
end
function MekTurbineDriver:getOutput()
	return self.device.getProductionRate()
end

function MekTurbineDriver:getInputBuffer()
	return self.device.getSteam()
end
function MekTurbineDriver:getInputBufferMax()
	return self.device.getSteamCapacity()
end
function MekTurbineDriver:getOutputBuffer()
	return self.device.getEnergy()
end
function MekTurbineDriver:getOutputBufferMax()
	return self.device.getMaxEnergy()
end

function MekTurbineDriver:getDevices()
	return {
		sensors = device.mapDevices('sensor', self, {
			['turbine:flow'] = { self.getInput, self.getInputMax },
			['turbine:power'] = self.getOutput
		})
	}
end
