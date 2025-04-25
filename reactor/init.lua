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
	local event = kernel.wait(nil, "kernel", "process_complete", nil, "errored")
	print("Process "..event[3].." errored"..(event[5] and ' ('..event[5]..')' or '')..", terminating")

	kernel.terminate()

	term.redirect(oldTerm)
end)


local driverTable = {
	{ type = 'fissionReactorLogicAdapter', file = '/drivers/reactor/mek_reactor.lua' },
	{ type = 'turbineValve', file = '/drivers/reactor/mek_turbine.lua' },
	{ type = 'basicEnergyCube', file = '/drivers/reactor/mek_energyCube.lua' }
}

print("Setting up controllers")
require("controllers/reactor")
require("controllers/turbine")
require("controllers/system")

devman.loadTable(driverTable)

devman.init()

local function createController(class, obj)
	local controller = devman.createController(class, obj)

	while not controller do
		sleep(1)

		controller, msg, missing = devman.createController(class, obj)

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
local reactor = createController(ReactorController, { modelFile = "/data/model/reactor.dat" })
local turbine = createController(TurbineController, { modelFile = "/data/model/turbine.dat" })
local system = createController(SystemController)

print("Sending initialization commands")
system:sendCommand('init')

kernel.exec("/bin/reactor_ui.lua", reactor, turbine, system)

return true
