-- <<<interface:kernel/driver>>>

require("interfaces/kernel/driver")

BufferDriver = IDriver:new{
	ready = nil,

	getLevel = nil,
	getMax = nil
}

function BufferDriver:getFraction()
	return self:getLevel() / self:getMax()
end
function BufferDriver:getFlow()
	local level = self:getLevel()
	if not self._level then
		self._level = level
		return 0
	end

	local flow = level - self._level

	self._level = level

	return flow
end
