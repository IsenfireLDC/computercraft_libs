-- <<<interface:net/inetproto>>>

require("interfaces/net/inetproto")


INetProtoMessage = INetProto:new{
	id = "message",
	inet = nil,

	queue = nil,

	ttl = 10
}

function INetProtoMessage:new(obj)
	obj = obj or {}

	if not obj.inet then return nil, "Need inet" end

	obj.queue = {}

	setmetatable(obj, self)
	self.__index = self

	return obj
end


function INetProtoMessage:processPacket(from, body, info)
	local proto = body.proto
	if not proto then return end

	table.insert(self.queue[proto], {
		from = from,
		info = info,
		message = body.message
	})
end

function INetProtoMessage:send(proto, message, to)
	self.inet:send(self.id, {
		proto = proto,
		message = message
	}, to, self.ttl)
end

function INetProtoMessage:recv(proto)
	if not self.queue[proto] or #self.queue[proto] == 0 then return nil, "No messages" end

	local data = table.remove(self.queue[proto], 1)

	return data.message, data.from, data.info
end
