-- <<<api:kernel,device>>>
-- <<<driver:reactor/mek_reactor,reactor/mek_turbine,reactor/mek_energyCube>>>
-- <<<controller:reactor,turbine,system>>>
-- <<<extension:table>>>

local kernel = require("apis/kernel")
local device = require("apis/device")

require("extensions/table")

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


-- Setup drivers
print("Setting up drivers")
require("drivers/reactor/mek_reactor")
require("drivers/reactor/mek_turbine")
require("drivers/reactor/mek_energyCube")

print("Adding drivers")
local types = {
	reactor = "fissionReactorLogicAdapter",
	turbine = "turbineValve",
	buffer = "basicEnergyCube"
}
kernel.addDriver(types.reactor, MekReactorDriver)
kernel.addDriver(types.turbine, MekTurbineDriver)
kernel.addDriver(types.buffer, MekEnergyCubeDriver)


-- Setup devices
print("Setting up devices")
local devices = {}
while not devices.reactor or not devices.turbine or not devices.buffer do
	local event = kernel.select(nil,
		table.pack('kernel', 'driver', 'attach', nil, types.reactor),
		table.pack('kernel', 'driver', 'attach', nil, types.turbine),
		table.pack('kernel', 'driver', 'attach', nil, types.buffer)
	)

	for k,v in pairs(types) do
		if event[5] == v then
			devices[k] = kernel.device(event[4], event[5])
			break
		end
	end
end

print("Creating device table")
local deviceTabs = {
	reactor = devices.reactor:getDevices(),
	turbine = devices.turbine:getDevices(),
	buffer = devices.buffer:getDevices()
}
local deviceTable = table.mergeall(
	deviceTabs.reactor,
	deviceTabs.turbine,
	deviceTabs.buffer
)


-- Setup controllers
print("Setting up controllers")
require("controllers/reactor")
require("controllers/turbine")
require("controllers/system")


local reactor = ReactorController:new(device.mergeTables(
	devices.reactor:getDevices(),
	{ modelFile = "/data/model/reactor.dat" }
))
local turbine = TurbineController:new(device.mergeTables(
	devices.turbine:getDevices(),
	{ controllers = { reactor = reactor }, modelFile = "/data/model/turbine.dat" }
))
local system = SystemController:new(device.mergeTables(
	devices.buffer:getDevices(),
	{ controllers = { turbine = turbine } }
))

local function printDevices(controller)
	if controller.sensors then
		print("Sensors")
		for k,v in pairs(controller.sensors) do
			print("> "..k)
		end
	end

	if controller.controllers then
		print("Controllers")
		for k,v in pairs(controller.controllers) do
			print("> "..k)
		end
	end

	if controller.actuators then
		print("Actuators")
		for k,v in pairs(controller.actuators) do
			print("> "..k)
		end
	end
end


print("Sending initialization commands")
system:sendCommand('init')

kernel.exec("/bin/reactor_ui.lua", reactor, turbine, system)
