-- <<<>>>
-- System Response Modelling
-- Auto-adjusted parameter sets for modeling the response of system components

local SER_SIZE = string.packsize("nnn")

SystemModel = {
	-- output = step * input ^ scaling
	step = 1,
	scaling = 1,

	adjustFraction = 0.2
}

function SystemModel:new(obj)
	obj = obj or {}
	setmetatable(obj, self)
	self.__index = self

	return obj
end


-- Return response for given input
function SystemModel:response(x)
	return self.step * x ^ self.scaling
end
-- Return input to make given response
function SystemModel:action(x)
	return (x / self.step) ^ (1 / self.scaling)
end


local function logBase(a, x)
	return math.log(x) / math.log(a)
end
local function clamp(x, default)
	if x ~= x or x == math.huge or x == -math.huge then
		return default
	end

	return x
end

-- Calculate the value of each parameter that would have cause a correct prediction, then adjust the parameter by a
-- fraction of the difference
function SystemModel:tune(x, actual)
	local adjustedStep = clamp(actual / x ^ self.scaling, self.step)
	local adjustedScaling = clamp(logBase(x, actual / self.step), self.scaling)

	local stepDelta = (adjustedStep - self.step) * self.adjustFraction
	local scalingDelta = (adjustedScaling - self.scaling) * self.adjustFraction

	--if _G.log then
	--	_G.log.info("SM> step: "..self.step.."; scaling: "..self.scaling.."; adjust: "..self.adjustFraction)
	--	_G.log.info("SM> step: "..adjustedStep.."; scaling: "..adjustedScaling)
	--	_G.log.info("SM> diff-st: "..stepDelta.."; diff-sc: "..scalingDelta)
	--end

	self.step = self.step + stepDelta
	self.scaling = self.scaling + scalingDelta
end


-- Helpers for saving/loading data
local function loadVals(self)
	self.file:seek('set', 0)
	self.step, self.scaling, self.adjustFraction = string.unpack("nnn", self.file:read(SER_SIZE))
end
local function saveVals(self)
	self.file:seek('set', 0)
	self.file:write(string.pack("nnn", self.step, self.scaling, self.adjustFraction))
end

function SystemModel:load(filename)
	if filename then
		self.file = io.open(filename, 'r+b')
	end

	if self.file then
		loadVals(self)
		return true
	end

	return false
end

function SystemModel:save(filename)
	if filename then
		self.file = io.open(filename, 'r+b')

		if not file then
			self.file = io.open(filename, 'w+b')
		end
	end

	if self.file then
		saveVals(self)
		return true
	end

	return false
end
