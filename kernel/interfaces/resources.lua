-- <<<>>>


IResource = {
	-- A table with at least a map of resource id to process id
	reservations = nil
}

function IResource:new(obj)
	obj = obj or {}

	obj.reservations = {}

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function IResource:delete()
end

-- Internal helper to allow attaching different data to a resource
function IResource:_createInstance(...)
	return {}
end

-- Reserve a single resource instance
function IResource:reserve(pid, id, ...)
	return false
end

-- Release a single resource instance
function IResource:release(pid, id)
end

-- Return information about a reservation
function IResource:check(id, ...)
	return false
end

-- Release all reservations from a specific process
function IResource:free(pid)
end




-- Basic reservation handler with no managed resources
BasicResource = IResource:new{}

function BasicResource:new(obj)
	obj = obj or {}

	obj = IResource:new(obj)

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function BasicResource:delete()
	for id, res in pairs(self.reservations) do
		self:release(res.pid, id)
	end
end

function BasicResource:reserve(pid, id, ...)
	if self.reservations[id] ~= nil and self.reservations[id].pid ~= pid then
		return nil
	end

	local reservation = {
		pid = pid,
		data = self:_createInstance(...)
	}
	self.reservations[id] = reservation

	return reservation.data
end

function BasicResource:release(pid, id)
	local reservation = self.reservations[id]
	if reservation and reservation.pid == pid then
		if reservation.data.delete then reservation.data:delete() end

		self.reservations[id] = nil
	end
end

function BasicResource:check(id)
	local reservation = self.reservations[id]
	return reservation ~= nil, reservation and { pid = reservation.pid }
end

function BasicResource:free(pid)
	for id, res in pairs(self.reservations) do
		if res.pid == pid then
			self:release(pid, id)
		end
	end
end




ShareableResource = IResource:new{}

function ShareableResource:new(obj)
	obj = obj or {}

	obj = IResource:new(obj)

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function ShareableResource:delete()
	for id, res in pairs(self.reservations) do
		for pid, p in pairs(res.pids) do
			if p then self:release(pid, id) end
		end
	end
end

function ShareableResource:reserve(pid, id, shared, ...)
	local reservation = self.reservations[id]
	if reservation ~= nil then
		if reservation.pids[pid] then
			return reservation.data
		elseif not reservation.shared or reservation.shared ~= shared then
			return nil
		end
	else
		reservation = {
			pids = {},
			shared = shared,
			instances = 0,
			data = self:_createInstance(...)
		}
		self.reservations[id] = reservation
	end

	reservation.pids[pid] = true
	reservation.instances = reservation.instances + 1

	return reservation.data
end

function ShareableResource:release(pid, id)
	local reservation = self.reservations[id]
	if reservation == nil or not reservation.pids[pid] then return end

	reservation.pids[pid] = nil
	reservation.instances = reservation.instances - 1

	if reservation.instances == 0 then
		if reservation.data.delete then reservation.data:delete() end

		self.reservations[id] = nil
	end
end

function ShareableResource:check(id)
	local reservation = self.reservations[id]
	return reservation ~= nil, reservation and { pids = reservation.pids, shared = reservation.shared }
end

function ShareableResource:free(pid)
	for id, res in pairs(self.reservations) do
		if res.pids[pid] then
			self:release(pid, id)
		end
	end
end
