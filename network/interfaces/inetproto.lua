-- <<<>>>

INetProto = {
	id = "",
	inet = nil
}


function INetProto:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function INetProto:delete()
end
