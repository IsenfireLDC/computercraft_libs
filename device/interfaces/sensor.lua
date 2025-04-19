-- <<<interface:device/device>>>

require("interfaces/device/device")

Sensor = Device:new{
	class = 'sensor'
}

function Sensor:getValue()
	return nil
end

function Sensor:getMax()
	return nil
end
