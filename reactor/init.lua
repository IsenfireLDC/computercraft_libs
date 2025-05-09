-- <<<api:kernel,devman>>>
-- <<<controller:reactor,turbine,system>>>

local kernel = require("apis/kernel")
local devman = require("apis/devman")

kernel.addPlugin("/plugins/kernel/driver.lua")

local monitor = peripheral.find('monitor')
local oldTerm = term.current()
if monitor then
	oldTerm = term.redirect(monitor)
end

kernel.start(function()
	while true do
		local event = kernel.wait(nil, "kernel", "driver")
		print("Driver "..event[4].." "..event[3].."ed on "..event[5])
	end
end)
kernel.start(function()
	local event = kernel.wait(nil, "kernel", "process_complete", nil, "errored")
	print("Process "..event[3].." errored"..(event[5] and ' ('..event[5]..')' or '')..", terminating")

	kernel.terminate()

	term.redirect(oldTerm)
end)


-- Table for loading drivers
local driverTable = {
	{ name = 'mekanism/reactor', types = { 'fissionReactorLogicAdapter' }, file = '/drivers/reactor/mek_reactor.lua' },
	{ name = 'mekanism/turbine', types = { 'turbineValve' }, file = '/drivers/reactor/mek_turbine.lua' },
	{ name = 'mekanism/energyCube', types = {
		'basicEnergyCube',
		'advancedEnergyCube',
		'eliteEnergyCube',
		'ultimateEnergyCube',
	}, file = '/drivers/reactor/mek_energyCube.lua' }
}

-- Table for automatically attaching devices
local deviceFilters = {}
for i,v in ipairs(driverTable) do
	deviceFilters[i] = { name = v.name, types = v.types }
end

-- Device-supporting driver list
local deviceDrivers = {}
for i,v in ipairs(driverTable) do
	table.insert(deviceDrivers, v.name)
end

kernel.driver.loadTable(driverTable)
kernel.driver.register(deviceFilters)

print("Setting up controllers")
require("controllers/reactor")
require("controllers/turbine")
require("controllers/system")

devman.loadTable(deviceDrivers)

devman.init()

local function createController(class, name, obj)
	local controller = devman.createController(class, name, obj)

	while not controller do
		sleep(1)

		controller, msg, missing = devman.createController(class, name, obj)

		if not controller then
			print(msg)

			if missing then
				for type,devs in pairs(missing) do
					print("> "..type..":", table.unpack(devs))
				end
			end
		end
	end

	return controller
end

print("Creating reactor controller")
local reactor = createController(ReactorController, 'reactor', { modelFile = "/data/model/reactor.dat" })
local turbine = createController(TurbineController, 'turbine', { modelFile = "/data/model/turbine.dat" })
local system = createController(SystemController, 'system')

print("Sending initialization commands")
system:sendCommand('init')

kernel.exec("/bin/reactor_ui.lua", reactor, turbine, system)

return true
