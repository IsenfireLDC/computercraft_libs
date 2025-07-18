-- <<<api:kernel,net/netlink;interface:kernel/driver,kernel/resources>>>
-- Driver for modem peripheral
-- Provides interface for opening connections on channels

local kernel = require("apis/kernel")
require("apis/net/netlink")

require("interfaces/kernel/driver")
require("interfaces/kernel/resources")


-- TODO: Move to another file
ChannelResource = ShareableResource:new{
	device = nil
}

function ChannelResource:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function ChannelResource:_createInstance(channel)
	return NetLink:new{device = self.device, channel = channel}
end

function ChannelResource:reserve(pid, channel, shared)
	local link = ShareableResource.reserve(self, pid, channel, shared, channel)

	link:open()

	return link
end



ModemDriver = IDriver:new{
	resourcePath = "net/none/channel"
}

-- Manage open channels
-- Manage connection objects on channels
function ModemDriver:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	self.__index = self

	kernel.start(obj.h_message, obj)

	obj.resourcePath = "net/"..obj.side.."/channel"
	kernel.resources.allocate(obj.resourcePath, ChannelResource, obj.device)

	return obj
end

function ModemDriver:cleanup()
	kernel.resources.deallocate(self.resourcePath)
end


function ModemDriver:h_message()
	while true do
		local event = kernel.select(0,
			table.pack("kernel", "driver", "detach", "net/modem", self.side),
			table.pack("modem_message", self.side, nil, nil)
		)

		if event[1] == 'kernel' then
			return
		elseif event[1] == "modem_message" then
			if kernel.resources.check(self.resourcePath, event[3]) then
				os.queueEvent("net", "driver", self.device, "message", event[3], event[5])
			end
		end
	end
end



function ModemDriver:open(channel, shared)
	return kernel.resources.reserve(self.resourcePath, channel, shared)
end

function ModemDriver:close(channel)
	kernel.resources.release(self.resourcePath, channel)
end
