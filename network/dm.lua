-- <<<interface:net/proto>>>

require("interfaces/net/proto")

 
NetProtoDM = NetProto:new{
	id = "dm",
	link = nil
}


function NetProtoDM:new(obj)
	obj = obj or {}

	if not obj.link then return nil, "Need link" end

	setmetatable(obj, self)
	self.__index = self

	return obj
end


function NetProtoDM:processPacket(from, data)
	os.queueEvent("net/dm", from, data)
end

function NetProtoDM:send(data, to)
	self.link:send(self.id, data, to)
end
