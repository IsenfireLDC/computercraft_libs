-- <<<api:kernel,net/link>>>

local kernel = require("apis/kernel")

require("interfaces/kernel/resources")
require("apis/net/link")




ProtoResource = ShareableResource:new{
	link = nil
}

function ProtoResource:new(link)
	local obj = {
		link = link
	}

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function ProtoResource:_createInstance(handler, ...)
	return handler:new({link = self.link}, ...)
end

function ProtoResource:reserve(pid, proto, handler, ...)
	return ShareableResource.reserve(self, pid, proto, true, handler, ...)
end

function ProtoResource:check(id)
	local reserved, details = ShareableResource.check(self, id)

	return reserved, details, self.reservations[id].data
end





Network = {
	link = nil,
	protocols = nil,

	resourcePath = "net/none/-1"
}


function Network:new(obj)
	obj = obj or {}

	if not obj.link then return nil, "Need link" end

	obj.link.on_recv = function(link, proto, data, from)
		obj:processPacket(proto, from, data)
	end

	obj.resourcePath = obj.link.interface.name .. "/" .. obj.link.interface.channel
	kernel.resources.allocate(obj.resourcePath, ProtoResource, obj.link)

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function Network:delete()
	kernel.resources.deallocate(self.resourcePath)
	obj.link:delete()
end

function Network.create(interface, address)
	return Network:new{
		link = NetLink.create(interface, address)
	}
end



function Network:registerProtocol(proto, ...)
	return kernel.resources.reserve(self.resourcePath, proto.id, proto, ...)
end

function Network:getProtocol(id)
	if not kernel.resources.check(self.resourcePath, id) then return nil end

	return kernel.resources.reserve(self.resourcePath, id)
end

function Network:removeProtocol(id)
	kernel.resources.release(self.resourcePath, id)
end



function Network:processPacket(proto, from, data)
	local p, details, handler = kernel.resources.check(self.resourcePath, proto)
	if not p then return end

	handler:processPacket(from, data)
end
