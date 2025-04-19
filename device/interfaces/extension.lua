-- Extension for a device

DeviceExtension = {
	extensionName = 'generic'
}

function DeviceExtension:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	self.__index = self

	return obj
end
