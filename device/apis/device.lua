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
	elseif deviceClass == 'actuator' then
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


local function mergeTables(...)
	local devTables = table.pack(...)

	local merged = {
		sensors = {},
		controllers = {},
		actuators = {}
	}
	for i=1,devTables.n,1 do
		local tab = devTables[i]

		for k,v in pairs(tab) do
			if k == 'sensors' then
				for k,v in pairs(tab.sensors) do
					merged.sensors[k] = v
				end
			elseif k == 'controllers' then
				for k,v in pairs(tab.controllers) do
					merged.controllers[k] = v
				end
			elseif k == 'actuators' then
				for k,v in pairs(tab.actuators) do
					merged.actuators[k] = v
				end
			else
				merged[k] = v
			end
		end
	end

	return merged
end


instance = {
	mapDevices = mapDevices,
	mergeTables = mergeTables
}

return instance
