-- <<<api:kernel>>>

local kernel = require("apis/kernel")

NetLink = {
	device = nil,
	channel = nil
}


function NetLink:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function NetLink:delete()
	self:close()
end


function NetLink:open()
	if self.isOpen then return true end

	local good, msg = pcall(self.device.open, self.channel)
	self.isOpen = good

	return good, msg
end

function NetLink:close()
	if not self.isOpen then return true end

	self.device.close(self.channel)
	self.isOpen = false
end



function NetLink:send(data)
	self.device.transmit(self.channel, self.channel, data)
end

function NetLink:recv(timeout)
	local event = kernel.wait(timeout, "net", "driver", self.device, "message", self.channel)

	return event[6]
end
