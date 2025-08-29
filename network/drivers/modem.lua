-- <<<api:kernel,net/interface;interface:kernel/driver,kernel/resources>>>
-- Driver for modem peripheral
-- Provides interface for opening connections on channels

local kernel = require("apis/kernel")
require("apis/net/interface")

require("interfaces/kernel/driver")
require("interfaces/kernel/resources")


-- TODO: Move to another file
ChannelResource = ShareableResource:new{
	device = nil
}

function ChannelResource:new(device, path)
	local obj = {
		device = device,
		path = path
	}

	obj = ShareableResource:new(obj)

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function ChannelResource:_createInstance(channel)
	return NetInterface:new{device = self.device, channel = channel, name = self.path}
end

function ChannelResource:reserve(pid, channel, shared)
	local interface = ShareableResource.reserve(self, pid, channel, shared, channel)

	interface:open()

	return interface
end

function ChannelResource:check(id)
	local reserved, details = ShareableResource.check(self, id)

	return reserved, details, self.reservations[id].data
end



ModemDriver = IDriver:new{
	resourcePath = "net/none"
}

-- Manage open channels
-- Manage connection objects on channels
function ModemDriver:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	self.__index = self

	kernel.start(obj.h_message, obj)

	obj.resourcePath = "net/"..obj.side
	kernel.resources.allocate(obj.resourcePath, ChannelResource, obj.device, obj.resourcePath)

	return obj
end

function ModemDriver:cleanup()
	kernel.resources.deallocate(self.resourcePath)
end


function ModemDriver:h_message()
	while true do
		local event, msg = kernel.select(nil,
			table.pack("kernel", "driver", "detach", "net/modem", self.side),
			table.pack("modem_message", self.side, nil, nil)
		)

		if event[1] == 'kernel' then
			return
		elseif event[1] == "modem_message" then
			local p, details, interface = kernel.resources.check(self.resourcePath, event[3])

			if p and interface.on_recv then
				interface:on_recv(event[5])
			end
			--if kernel.resources.check(self.resourcePath, event[3]) then
			--	os.queueEvent("net", "driver", self.device, "message", event[3], event[5])
			--end
		end
	end
end



function ModemDriver:open(channel, shared)
	return kernel.resources.reserve(self.resourcePath, channel, shared, self.resourcePath)
end

function ModemDriver:close(channel)
	kernel.resources.release(self.resourcePath, channel)
end


return ModemDriver
