-- <<<serialize>>>
-- State Persistence
-- TODO: Support entries of multiple sizes

State = {
	file = nil,
	data = {},
	keys = { [0] = {} },

	_maxKey = 0,
	_maxLevel = 0
}


-- [Helper]
-- Gets key index from keys lists
local function getIndex(state, key)
	local start = 0
	for _, keys in ipairs(state.keys) do
		local i = 0
		for i, k in ipairs(keys) do
			if k == key then
				return start + i
			end
		end

		start = start + i
	end

	return nil
end


-- [Index]
-- Index function for state, converts name to index
-- TODO: Can this be replaced with state.data?
local function getVal(state, key)
	local index = getIndex(state, key)
	if index == nil then return nil end

	return state:get(index)
end

-- [NewIndex]
-- Writes data to file as well as internal table
local function setVal(state, key, value)
	local index = getIndex(state, key)
	if index == nil then return nil end

	return state:set(index, value)
end


function State:new(obj)
	obj = obj or {}
	setmetatable(obj, self)
	self.__index = getVal
	self.__newindex = setVal

	return obj
end

function State.init(filename, keys)
	local file = io.open(filename, "rb")

	-- Recover state from data file
	local nKeys = 0
	local data = {}
	if file then
		local val = file:read(4)

		while val ~= nil do
			data[nKeys + 1] = serialize.unserialize("number", val)

			nKeys = nKeys + 1
			val = file:read(4)
		end

		file:close()
	end

	-- Re-write state file
	file = io.open(filename, "wb")
	for i=1,nKeys,1 do
		file:write(serialize.serialize(data[i]))
	end

	return State:new{
		file = file,
		data = data,
		keys = { [0] = keys },
		_maxLevel = 1,
		_maxKey = #keys - 1
	}
end

function State:get(index)
	return self.data[index]
end

function State:set(index, value)
	value = value or 1

	self.data[index] = value

	if key > self._maxKey then
		self._maxKey = key
	end

	self.file:seek("set", index * 4)
	self.file:write(serialize.serialize(value))
end


function State:addLevel(keys)
	self._maxLevel = self._maxLevel + 1
	self._maxKey = self._maxKey + #keys
	self.data[self._maxLevel] = keys
end

function State:removeLevel()
	self._maxKey = self._maxKey - #self.data[self._maxLevel]
	self.data[self._maxLevel] = nil
	self._maxLevel = self._maxLevel - 1
end

return true
