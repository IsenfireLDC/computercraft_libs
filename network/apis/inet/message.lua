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

	if not self.queue[proto] then return end
	os.queueEvent("net", "inet/message", proto, body.message, from, info)

	if self.queue[proto] == "noqueue" then return end
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
	local queue = self.queue[proto]
	if not queue then return nil, "Not listening" end
	if queue == "noqueue" then return nil, "Not queueing" end
	if #queue == 0 then return nil, "No messages" end

	local data = table.remove(queue, 1)

	return data.message, data.from, data.info
end



function INetProtoMessage:listen(proto, noQueue)
	if noQueue then
		self.queue[proto] = "noqueue"
	elseif not self.queue[proto] then
		self.queue[proto] = {}
	end
end

function INetProtoMessage:deafen(proto)
	self.queue[proto] = nil
end
