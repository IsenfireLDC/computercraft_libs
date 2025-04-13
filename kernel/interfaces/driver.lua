-- <<<>>>

IDriver = {
	side = 'none',
	type = { n=0 },
	device = nil
}

function IDriver:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function IDriver:cleanup()
	return
end



-- Basic driver
-- Provides direct access to peripheral functions
RawDriver = IDriver:new{}

function RawDriver:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	self.__index = self

	obj.__index = obj.device

	return obj
end

function RawDriver:getDevice()
	return self.device
end
