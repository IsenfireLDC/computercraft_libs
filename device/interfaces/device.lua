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

Device = {
	class = 'generic',
	extensions = nil,    -- list
	type = 'unknown'
}

-- ext -> ext -> obj -> self
function Device:new(obj)
	obj = obj or {}

	if obj.extensions then
		local extensions = {}
		for _,ext in ipairs(obj.extensions) do
			table.insert(extensions, ext:new{})
		end

		local mt = {
			__index = function(t, k)
				local v
				for _,ext in ipairs(extensions) do
					if ext[k] then
						v = ext[k]
						break
					end
				end

				-- Cache
				if v then
					t[k] = v
					return v
				end

				return self[k]
			end
		}

		setmetatable(obj, mt)
		obj.__index = obj
	else
		setmetatable(obj, self)
		self.__index = self
	end

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
