-- <<<api:kernel>>>
-- Device Manager

local kernel = require("apis/kernel")
local device = require("apis/device")

local instance


local drivers = {}

local loaded = {}

local devices = {
	sensors = {},
	controllers = {},
	actuators = {}
}


local function addDevice(class, devType, dev, name)
	-- TODO: Multiple controllers of the same type
	name = name or '_internal'

	local tab
	if class == 'sensor' or class == 'sensors' then
		tab = devices.sensors
	elseif class == 'controller' or class == 'controllers' then
		tab = devices.controllers
	elseif class == 'actuator' or class == 'actuators' then
		tab = devices.actuators
	end

	if not tab then return end

	if not tab[devType] then
		tab[devType] = {
			_default = {
				device = dev,
				source = name
			}
		}
	end

	tab[devType][name] = dev
end


local function attachHandler(name, dev)
	while not dev:ready() do
		sleep(1)
	end

	local devtab = dev:getDevices()
	loaded[name] = devtab

	for class,devList in pairs(devtab) do
		for devType,dev in pairs(devList) do
			addDevice(class, devType, dev, name)
		end
	end
end

local function detachHandler(name)
	local devtab = loaded[name]
	if not devtab then return end

	for class,devType in pairs(devtab) do
		local tab
		if class == 'sensor' then
			tab = devices.sensors
		elseif class == 'actuator' then
			tab = devices.actuators
		end

		if tab[devType] then
			tab[devType][name] = nil

			if tab[devType]._default.source == name then
				local found = false
				for name,dev in pairs(tab[devType]) do
					tab[devType]._default = {
						device = dev,
						source = name
					}
					found = true
					break
				end

				if not found then
					tab[devType] = nil
				end
			end
		end
	end
end

local function connectionHandler()
	while true do
		local event = kernel.wait(nil, 'kernel', 'driver')

		if drivers[event[4]] then
			if event[3] == 'attach' then
				local dev = kernel.driver.attach(event[5], event[4])

				kernel.nice(kernel.start(attachHandler, event[4], dev), 1)
			else
				kernel.nice(kernel.start(detachHandler, event[4]), 1)
			end
		end
	end
end




-- devices table { 'driver name' ... }
local function loadTable(devtab)
	local count = devtab.n or #devtab

	for i=1,count,1 do
		local entry = devtab[i]

		drivers[entry] = true
	end
end

local function init()
	kernel.start(connectionHandler)
end

local function getDevice(class, type, source)
	source = source or '_default'

	if not class then
		return nil, "Need device class"
	elseif not type then
		return nil, "Need device type"
	end

	local ofType = devices[class][type]
	if not ofType then
		return nil, "No "..class.." of type "..type
	end

	if not ofType[source] then
		return nil, "No matching device from source "..source
	end

	return ofType[source]
end

local function getDevices(required, present)
	present = present or {}
	local found = { sensors = {}, controllers = {}, actuators = {} }
	local missing = { sensors = {}, controllers = {}, actuators = {} }
	local good = true

	for class,req in pairs(required) do
		for _,devType in ipairs(req) do
			if not present[class] or not present[class][devType] then
				local devtab = devices[class][devType]
				if devtab then
					found[class][devType] = devtab._default.device
				else
					table.insert(missing[class], devType)
					good = false
				end
			end
		end
	end

	return found, not good and missing or nil
end

local function createController(class, name, obj)
	if not class then
		return nil, "Need class"
	end

	obj = obj or {}

	-- Get required devices from class
	local devtab, missing = getDevices(class.requiredDevices)
	if missing then
		return nil, "Missing devices", missing
	end

	-- Merge devtab with obj and create instance
	local controller = class:new(device.mergeTables(devtab, obj))

	addDevice('controller', controller.type, controller, name)
	return controller
end





instance = {
	loadTable = loadTable,
	init = init,
	getDevice = getDevice,
	getDevices = getDevices,
	createController = createController
}

return instance
