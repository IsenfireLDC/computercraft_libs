-- <<<interface:device/device>>>

require("interfaces/device/device")

Actuator = Device:new{
	class = 'actuator'
}

function Actuator:setValue(...)
end
