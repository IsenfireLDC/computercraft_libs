-- <<<api:kernel>>>

-- modem  channel  neighbor  networked
-- address: right/1/4/25
-- > right modem
-- > channel 1
-- > message for link address 4
-- > message for internet address 25


-- can logically send an ip packet to any link, but not a link packet to any interface (targeting the same endpoint)
-- IP must abstract link address, which is a special case; most protocols are agnostic to addresses of layers below

-- Hard-bind link to every interface, don't allow other L1 protocols
-- Provide a method for link to support handlers for each protocol

-- Attach driver
-- Reserve interface
-- Setup net on interface (binds link instance)
-- Register/bind protocol (creates instance)
-- Send/receive packets



local kernel = require("apis/kernel")

NetInterface = {
	device = nil,
	name = nil,
	channel = nil
}

-- For L2 protocols
-- resourcePath = self.name .. "/" .. self.channel


function NetInterface:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function NetInterface:delete()
	self:close()
end


function NetInterface:open()
	if self.isOpen then return true end

	local good, msg = pcall(self.device.open, self.channel)
	self.isOpen = good

	return good, msg
end

function NetInterface:close()
	if not self.isOpen then return true end

	self.device.close(self.channel)
	self.isOpen = false
end



function NetInterface:send(data)
	self.device.transmit(self.channel, self.channel, data)
end

function NetInterface:on_recv(data)
end

--function NetInterface:on_recv(timeout)
--	local event = kernel.wait(timeout, "net", "driver", self.device, "message", self.channel)
--
--	return event[6]
--end
