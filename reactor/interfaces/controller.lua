-- <<<api:model,kernel>>>

local kernel = require("apis/kernel")
require("apis/model")

-- Required overrides:
-- self:run()
--
-- Optional overrides:
-- self:resetLimits()

IController = {
	modelFile = nil,
	model = nil,
	target = 0,
	limits = {}
}

function IController:new(obj)
	obj = obj or {}

	if not obj.model then obj.model = Model:new{} end

	setmetatable(obj, self)
	self.__index = self

	obj:resetLimits()

	return obj
end

-- Start supplied processes
function IController:start()
	print("Controller start")
	if self.driverType then
		print("Finding driver...")
		self:getDriver(self.driverType)
		print("Driver:")
		for k,v in pairs(self.driver) do
			print("> "..k..":", v)
		end
	end

	print("Starting main process")
	kernel.start(self.run, self)

	-- Failsafe will be run at a higher priority
	if self.failsafe then
		print("Starting failsafe")
		local p_fs = kernel.start(self.failsafe, self)

		kernel.nice(p_fs, -2)
	end
end
function IController:getDriver(type)
	local devList = kernel.findDevices(type)
	if #devList == 0 then
		local event = kernel.wait(nil, "kernel", "driver", "attach", nil, type)

		devList = { event[4] }
	end

	local side = devList[1]
	self.driver = kernel.device(side, type)
end

function IController:getModelFile()
	return self.modelFile
end
function IController:setModelFile(path)
	if not path then return end

	self.modelFile = path
end

function IController:loadModel()
	return self.model:load(self.modelFile)
end
function IController:saveModel()
	return self.model:save(self.modelFile)
end

function IController:getTarget()
	return self.target
end
function IController:setTarget(target)
	self.target = target
end

function IController:getState()
	return self.state
end
function IController:setState(state)
	self.state = state
end


function IController:resetLimits()
	self.limits = {}
end
function IController:setLimit(name, limit, val)
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
function IController:getLimit(name, limit)
	local vals = self.limits[name]
	if not vals then return end

	if limit then
		return vals[limit]
	else
		return vals
	end
end
function IController:limit(name, value)
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
