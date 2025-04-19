-- device:
-- type >
--
-- sensor (device):
-- value >
--
-- actuator (device):
-- > value
--
-- controller (device):
-- > target >
-- > command
-- status >    state, faults, etc.

-- TODO: getCommands?
-- TODO: How to link controllers and sensors/actuators/controllers
-- TODO: Required devices lists for controllers

Device = {
	class = 'generic',
	extensions = nil,    -- list
	type = 'unknown'
}

function Device:new(obj)
	obj = obj or {}

	-- TODO: Test this
	local meta = obj
	for _,ext in ipairs(obj.extensions) do
		meta = setmetatable(meta, ext:new{})
	end

	setmetatable(meta, self)
	self.__index = self

	return obj
end

function Device:getClass()
	return self.class
end

function Device:getExtensions()
	return self.extensions or {}
end

function Device:getType()
	return self.type
end


DeviceExtension = {
	extensionName = 'generic'
}

function DeviceExtension:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	self.__index = self

	return obj
end
