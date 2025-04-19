-- <<<interface:device/sensor,device/actuator>>>

require("interfaces/device/sensor")
require("interfaces/device/actuator")

local instance = {}

local function mapDevices(deviceClass, driver, map)
	local devices = {}

	if deviceClass == 'sensor' then
		for name,method in pairs(map) do
			local max
			if type(method) == 'table' then
				method, max = table.unpack(method)
			end

			local sensor = Sensor:new{}

			function sensor:getValue()
				return method(driver)
			end

			if max then
				function sensor:getMax()
					return max(driver)
				end
			end

			devices[name] = sensor
		end
	elseif deviceClass == 'sensor' then
		for name,method in pairs(map) do
			local actuator = Actuator:new{}

			function actuator:setValue(...)
				return method(driver, ...)
			end

			devices[name] = actuator
		end
	end

	return devices
end


instance = {
	mapDevices = mapDevices
}

return instance
