-- <<<api:net/channel>>>

-- L1 protocol; gets bound to a specific channel
-- L2 protocol is registered <somewhere> and and api is provided to send/receive packets
--   incoming events are handled centrally and passed back to requester
--   sent packets are attached to appropriate interface and sent via bound protocol


-- Must be able to be bound to an interface

NetLink = {
	interface = nil,
	address = os.computerID()
}


local function forMe(self, message)
	if not message then return false end

	if message.to and message.to ~= self.address and message.to ~= -1 then return false end

	return true
end

function NetLink:new(obj)
	obj = obj or {}

	if not obj.interface then return nil, "Missing bound interface" end

	obj.interface.on_recv = function(self, message)
		if not forMe(obj, data) then return end

		obj:on_recv(message.proto, message.data, message.from)
	end

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function NetLink.create(interface, address)
	return NetLink:new{
		interface = interface,
		address = address
	}
end



function NetLink:send(proto, data, to)
	self.interface:send({
		to = to,
		from = self.address,
		proto = proto,
		data = data
	})
end

function NetLink:on_recv(proto, data, from)
end
