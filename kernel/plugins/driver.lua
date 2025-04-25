local peripherals = {
	connected = {},
	drivers = {
		raw = {}
	}
}

local drivers = {}

local function attachDriver(type, side, device)
	print("> attach driver for "..type.." to "..side)
	if drivers[type] ~= nil then
		peripherals.drivers[type][side] = drivers[type]:new{
			side = side,
			type = type,
			device = device
		}
	end

	os.queueEvent("kernel", "driver", "attach", side, type)
end
local function detachDriver(type, side)
	print("> detach driver for "..type.." from "..side)
	if drivers[type] ~= nil and peripherals.drivers[type][side] ~= nil then
		peripherals.drivers[type][side]:cleanup()
		peripherals.drivers[type][side] = nil
	end

	os.queueEvent("kernel", "driver", "detach", side, type)
end

local function addDriver(type, driver)
	print("> add driver for "..type)
	if drivers[type] then
		return false, "Already have a driver for type "..type
	end

	drivers[type] = driver
	peripherals.drivers[type] = {}

	-- Attach this driver to any existing peripherals with this type
	for side,info in pairs(peripherals.connected) do
		for i=1,info.types.n,1 do
			local t = info.types[i]

			if t == type then
				attachDriver(t, side, info.device)
			end
		end
	end

	return true
end
local function removeDriver(type)
	print("> remove driver for "..type)
	if not drivers[type] then
		return false, "No driver with type "..type
	end

	-- Cleanup all driver instances first
	for side,driver in pairs(peripherals.drivers[type]) do
		driver:cleanup()
	end

	peripherals.drivers[type] = nil
	drivers[type] = nil

	return true
end

local function attachPeripheral(side)
	local types = table.pack(peripheral.getType(side))
	local periph = peripheral.wrap(side)

	peripherals.connected[side] = {
		types = types,
		device = periph
	}

	-- Always provide a 'raw' driver as default
	peripherals.drivers.raw[side] = RawDriver:new{
		side = side,
		type = 'raw',
		device = periph
	}

	for i=1,types.n,1 do
		local type = types[i]

		attachDriver(type, side, periph)
	end

	os.queueEvent("kernel", "device", "attach", side, types)
end
local function detachPeripheral(side)
	local device = peripherals.connected[side]
	if not device then return end

	for i=1,device.types.n,1 do
		local type = device.types[i]

		detachDriver(type, side)
	end

	peripherals.drivers.raw[side]:cleanup()
	peripherals.drivers.raw[side] = nil

	peripherals.connected[side] = nil

	os.queueEvent("kernel", "device", "detach", side, device.types)
end


local function findDevices(type)
	local ofType = peripherals.drivers[type]
	if not ofType then
		return nil, "No driver for type "..type
	end

	local sideList = {}
	for side, dev in pairs(ofType) do
		table.insert(sideList, side)
	end

	return sideList
end
local function device(side, type)
	if not side then
		return nil, "Invalid side"
	end

	if not peripherals.connected[side] then
		return nil, "No device on side "..side
	end

	local ofType = peripherals.drivers[type]
	if not ofType then
		return nil, "No driver for type "..type
	end

	local dev = ofType[side]
	if not dev then
		return nil, "Device is not of type "..type
	end

	return dev
end



return {
	handlers = {
		startup = function()
			print("> startup")
			for _,name in ipairs(peripheral.getNames()) do
				attachPeripheral(name)
			end
		end,
		tick = function(event)
			if event[1] == 'peripheral' then
				attachPeripheral(event[2])
			elseif event[1] == 'peripheral_detach' then
				detachPeripheral(event[2])
			end
		end,
		shutdown = function()
			print("> shutdown")
			for name,device in pairs(peripherals.connected) do
				detachPeripheral(name)
			end
		end
	},
	interface = {
		add = addDriver,
		remove = removeDriver,
		find = findDevices,
		get = device
	}
}
