-- <<<api:kernel;interface:net/proto>>>

local kernel = require("apis/kernel")

require("interfaces/net/proto")




InetProtoResource = ShareableResource:new{
	inet = nil
}

function InetProtoResource:new(inet)
	local obj = {
		inet = inet
	}

	obj = ShareableResource:new(obj)

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function InetProtoResource:_createInstance(handler, ...)
	return handler:new({inet = self.inet}, ...)
end

function InetProtoResource:reserve(pid, proto, handler, ...)
	return ShareableResource.reserve(self, pid, proto, true, handler, ...)
end

function InetProtoResource:check(id)
	local reserved, details = ShareableResource.check(self, id)

	return reserved, details, self.reservations[id].data
end





NetProtoInternet = NetProto:new{
	id = "internet",
	link = nil,

	address = os.computerID(),

    defaultTTL = 10
}

function NetProtoInternet:new(obj, address)
	obj = obj or {}
	obj.address = address

	if not obj.link then return nil, "Need link" end

	setmetatable(obj, self)
	self.__index = self

	obj.resourcePath = obj.link.interface.name .. "/" .. obj.link.interface.channel .. "/" .. obj.id
	kernel.resources.allocate(obj.resourcePath, InetProtoResource, obj)

	return obj
end

local function forMe(self, to)
	if to and to ~= self.address and to ~= -1 then return false end

	return true
end

function NetProtoInternet:processPacket(from, data)
	if not forMe(self, data.to) then
		self:forward(data)
		return nil
	end

	local proto = data.proto
	if not proto then return end

	local p, details, handler = kernel.resources.check(self.resourcePath, proto)
	if not p then return end

	handler:processPacket(data.from, data.body, { to = data.to, ttl = data.ttl })
end



function NetProtoInternet:send(proto, body, to, ttl)
	self.link:send(self.id, {
		to = to,
		from = self.address,
		proto = proto,
		ttl = ttl or self.defaultTTL,
		body = body
	}, self:route(to))
end


function NetProtoInternet:route(to)
	-- Trivial case here; replaced by routing protocol on attachment
	return to
end

function NetProtoInternet:forward(data)
	data.ttl = data.ttl - 1
	if(data.ttl <= 0) then return end

	self.link:send(self.id, data, self:route(data.to))
end



function NetProtoInternet:registerProtocol(proto, ...)
	return kernel.resources.reserve(self.resourcePath, proto.id, proto, ...)
end

function NetProtoInternet:getProtocol(id)
	if not kernel.resources.check(self.resourcePath, id) then return nil end

	return kernel.resources.reserve(self.resourcePath, id)
end

function NetProtoInternet:removeProtocol(id)
	kernel.resources.release(self.resourcePath, id)
end
