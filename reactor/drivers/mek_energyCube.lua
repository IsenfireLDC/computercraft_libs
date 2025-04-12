-- <<<interface:reactor/buffer>>>

require("interfaces/reactor/buffer")

MekEnergyCubeDriver = BufferDriver:new{}

function MekEnergyCubeDriver:ready()
	return self.device and true or false
end

function MekEnergyCubeDriver:getLevel()
	return self.device.getEnergy()
end
function MekEnergyCubeDriver:getMax()
	return self.device.getMaxEnergy()
end
function MekEnergyCubeDriver:getFraction()
	return self.device.getEnergyFilledPercentage()
end
