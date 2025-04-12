-- <<<interface:reactor/reactor>>>

require("interfaces/reactor/reactor")

MekReactorDriver = ReactorDriver:new{}

function MekReactorDriver:ready()
	return self.device and self.device.isFormed()
end

function MekReactorDriver:start()
	self.device.setBurnRate(0)

	if not self.device.getStatus() then
		self.device.activate()
	end
end
function MekReactorDriver:stop()
	self.device.setBurnRate(0)
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
