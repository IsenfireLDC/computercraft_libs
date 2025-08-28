-- <<<>>>

NetProto = {
	id = "",
	link = nil
}


function NetProto:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function NetProto:delete()
end
