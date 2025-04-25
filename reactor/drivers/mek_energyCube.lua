-- <<<interface:kernel/driver|api:device>>>

local device = require("apis/device")

require("interfaces/kernel/driver")

MekEnergyCubeDriver = IDriver:new{}

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

function MekEnergyCubeDriver:getDevices()
	return {
		sensors = device.mapDevices('sensor', self, {
			['buffer:energy'] = { self.getLevel, self.getMax }
		})
	}
end


return MekEnergyCubeDriver
