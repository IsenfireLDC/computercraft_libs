-- <<<interface:reactor/turbine>>>

require("interfaces/reactor/turbine")

MekTurbineDriver = TurbineDriver:new{}

function MekTurbineDriver:ready()
	return self.device and self.device.isFormed()
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
