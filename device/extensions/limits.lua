-- <<<interface:device/extension>>>

require("interfaces/device/extension")

LimitsExtension = DeviceExtension:new{
	extensionName = 'limits',

	limits = {}
}


function LimitsExtension:resetLimits()
	self.limits = {}
end
function LimitsExtension:setLimit(name, limit, val)
	if not self.limits[name] then
		return false
	end

	if val == nil then
		self.limits[name] = limit
	else
		self.limits[name][limit] = val
	end

	return true
end
function LimitsExtension:getLimit(name, limit)
	local vals = self.limits[name]
	if not vals then return end

	if limit then
		return vals[limit]
	else
		return vals
	end
end
function LimitsExtension:limit(name, value)
	local limits = self.limits[name]
	if not limits then
		return value, "No limit for value"
	end

	if limits.min and value < limits.min then
		return limits.min
	elseif limits.max and value > limits.max then
		return limits.max
	else
		return value
	end
end
