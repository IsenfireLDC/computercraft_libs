-- <<<>>>

local instance

local drivers = {} -- [name] = { types = types, driver = driver }
local devices = {} -- [side] = { refcount = 0, name = name, driver = driver }

local registered = {} -- { type?, side?, name }


local function loadFile(path)
	local f = loadfile(path, nil, _ENV)

	local res = table.pack(pcall(f))
	if not res[1] then
		return nil, table.unpack(res, 2)
	end

	return res[2]
end

local function listToSet(list)
	local set = {}
	local count = list.n or #list

	for i=1,count,1 do
		set[list[i]] = true
	end

	return set
end


local function attachDevice(side, name, device, driver)
	devices[side] = {
		refcount = 1,
		name = name,
		driver = driver:new{
			side = side,
			device = device
		}
	}

	os.queueEvent('kernel', 'driver', 'attach', name, side)
end
local function detachDevice(side, force)
	local device = devices[side]
	if not device then return end
	if not force and device.refcount > 1 then
		device.refcount = device.refcount - 1
		return
	end

	local name = devices[side].name

	devices[side].driver:cleanup()
	devices[side] = nil
	
	-- TODO: get name
	os.queueEvent('kernel', 'driver', 'detach', name, side)
end




-- driver table { { name = 'mekanism/turbine', types = { 'turbineValve' } } }
-- optional file field
local function loadTable(driverTable)
	local count = driverTable.n or #driverTable

	for i=1,count,1 do
		local entry = driverTable[i]

		instance.add(entry.name, entry.types, entry.file and loadFile(entry.file))
	end
end


local function add(name, types, driver)
	if not types then
		return nil, "Need peripheral types"
	elseif not name then
		return nil, "Need driver name"
	end

	if drivers[name] then
		return nil, "Have driver with name "..name
	end

	if not driver then
		driver, msg = loadFile('/drivers/'..name..'.lua')

		if not driver then
			return nil, "Failed to load driver", msg
		end
	end

	drivers[name] = {
		types = listToSet(types),
		driver = driver
	}

	return name
end

local function remove(name)
	if not name then
		return nil, "Need driver name"
	end

	if not drivers[name] then
		return nil, "No driver "..name
	end

	drivers[name] = nil
	return name
end


local function attach(side, name)
	-- Return cached driver instance if it exists
	if devices[side] then
		local device = devices[side]
		if device.name == name then
			device.refcount = device.refcount + 1
			return device.driver
		else
			return nil, "Driver "..device.name.." already attached to "..side
		end
	end

	local device = peripheral.wrap(side)
	if not device then
		return nil, "Could not wrap device "..side
	end

	local driver = drivers[name]
	if not driver then
		return nil, "No driver "..name
	end

	-- Check driver compatibility
	local deviceTypes = { peripheral.getType(device) }
	local found = false
	for _,v in ipairs(deviceTypes) do
		if driver.types[v] then
			found = true
		end
	end

	if not found then
		return nil, "Driver "..name.." does not support device type(s)", deviceTypes
	end

	attachDevice(side, name, device, driver)

	return devices[side].driver
end

local function detach(side)
	detachDevice(side, false)
end


local function checkFilter(filter, side, types)
	if filter.side and side ~= filter.side then
		return false
	end

	if filter.types then
		for _,v in ipairs(types) do
			if filter.types[v] then
				return true
			end
		end

		return false
	end

	return true
end

local function checkFilters(side)
	local device = peripheral.wrap(side)
	local types = { peripheral.getType(device) }

	for _,v in ipairs(registered) do
		local name = v.name
		if checkFilter(v, side, types) then
			attachDevice(side, name, device, drivers[name].driver)
			break
		end
	end
end


-- deviceTable { types?, side?, name }
local function register(deviceTable)
	local count = deviceTable.n or #deviceTable

	for i=1,count,1 do
		local entry = deviceTable[i]

		-- Merge into registered
		if entry.name then
			table.insert(registered, {
				types = listToSet(entry.types),
				side = entry.side,
				name = entry.name
			})
		end
	end

	-- Recheck all devices against new filters
	local devices = peripheral.getNames()
	for _,dev in ipairs(devices) do
		checkFilters(dev)
	end
end



instance = {
	loadTable = loadTable,
	add = add,
	remove = remove,
	attach = attach,
	detach = detach,
	register = register
}

return {
	handlers = {
		tick = function(event)
			if event[1] == 'peripheral' then
				checkFilters(event[2])
			elseif event[1] == 'peripheral_detach' then
				detachDevice(event[2], true)
			end
		end,
		shutdown = function()
			for side,device in pairs(devices) do
				detachDevice(side, true)
			end
		end
	},
	interface = instance
}
