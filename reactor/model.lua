-- <<<>>>
-- System Response Modelling
-- Auto-adjusted parameter sets for modeling the response of system components

local SER_SIZE = string.packsize("nnnn")

Model = {
	-- output = step * input ^ scaling
	step = 1,
	scaling = 1,

	adjustFraction = 0.7,
	sampleCount = 15,

	samples = nil
}

function Model:new(obj)
	obj = obj or {}

	if not obj.samples then
		obj.samples = {}
	end

	setmetatable(obj, self)
	self.__index = self

	return obj
end


-- Return response for given input
function Model:response(x)
	return self.step * x ^ self.scaling
end
-- Return input to make given response
function Model:action(x)
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

local function sampleReplacementCost(self, idx)
	local sample = self.samples[idx]

	-- Calculate distance to closest neighbor
	local minNeighborDist
	local hasNeighbor = false
	for i,v in ipairs(self.samples) do
		if i ~= idx then
			local dist = math.abs(sample.x - v.x)
			if not hasNeighbor or dist < minNeighborDist then
				hasNeighbor = true
				minNeighborDist = dist
			end
		end
	end

	local cost = 0

	-- Distance from average x adds cost
	cost = cost + math.abs(self.samples[idx].x - self._xAvg)

	-- Distance from closest neighbor adds cost
	if hasNeighbor then
		cost = cost + minNeighborDist
	end

	return cost
end
local function addSample(self, x, y)
--	if x ~= x or y ~= y then
--		log.warn("Sample contains nan: ("..x..", "..y..")")
--		return
--	elseif math.abs(x) >= math.huge or math.abs(y) >= math.huge then
--		log.warn("Sample contains inf: ("..x..", "..y..")")
--		return
--	end

	-- Add sample to buffer
	local idx
	if #self.samples < self.sampleCount then
		table.insert(self.samples, {x = x, y = y})
		idx = #self.samples
	else
		self.samples.new = {x = x, y = y}
		idx = "new"
	end

	-- Calculate and cache average x value
	self._xAvg = 0
	for _,v in ipairs(self.samples) do
		self._xAvg = self._xAvg + v.x
	end
	self._xAvg = self._xAvg / #self.samples

	-- Fill buffer before replacement
	if #self.samples < self.sampleCount then
		return
	end

	-- Replace point with the lowest cost
	local replaceIdx = idx
	local minCost = sampleReplacementCost(self, idx)
	for i,v in ipairs(self.samples) do
		local cost = sampleReplacementCost(self, idx)
		if cost < minCost then
			minCost = cost
			replaceIdx = i
		end
	end

	self.samples[replaceIdx] = self.samples[idx]
	self.samples[idx] = nil
end

local function calcMse(self, coeff, exp)
	local mse = 0
	for _,v in ipairs(self.samples) do
		local model = coeff * v.x ^ exp

		mse = mse + (v.y - model) ^ 2
	end

	return mse / #self.samples
end

-- Calculate the `true` values based on one sample per parameter, then check if the adjustment produces a better MSE
-- If it does, use the new model
function Model:tune(x, actual)
	addSample(self, x, actual)

	if #self.samples < 4 then return end

	-- Make copy of samples
	local samples = {}
	for _,v in ipairs(self.samples) do
		table.insert(samples, v)
	end

	while #samples >= 2 do
		local points = {}
		for i=1,2,1 do
			local idx = math.random(1, #samples)
			points[i] = table.remove(samples, idx)
		end

		local ln_x0 = math.log(points[1].x)
		local ln_y0 = math.log(points[1].y)
		local ln_x1 = math.log(points[2].x)
		local ln_y1 = math.log(points[2].y)

		local tCoeff = math.exp( ( ln_y0 * ln_x1 - ln_y1 * ln_x0 ) / ( ln_x1 - ln_x0 ) )
		local tExp = ( ln_y0 - math.log(tCoeff) ) / ln_x0
		
		local aCoeff = self.step + (tCoeff - self.step) * self.adjustFraction
		local aExp = self.scaling + (tExp - self.scaling) * self.adjustFraction

		local newMse = calcMse(self, tCoeff, tExp)
		local adjMse = calcMse(self, aCoeff, aExp)
		local oldMse = calcMse(self, self.step, self.scaling)

		if newMse < oldMse and adjMse < oldMse then
			self.step = aCoeff
			self.scaling = aExp
		end
	end
end


-- Helpers for saving/loading data
local function loadVals(self)
	self.file:seek('set', 0)
	self.step, self.scaling, self.adjustFraction, self.sampleCount = string.unpack("nnnn", self.file:read(SER_SIZE))
end
local function saveVals(self)
	self.file:seek('set', 0)
	self.file:write(string.pack("nnnn", self.step, self.scaling, self.adjustFraction, self.sampleCount))
end

function Model:load(filename)
	if filename then
		self.file = io.open(filename, 'r+b')
	end

	if self.file then
		loadVals(self)
		return true
	end

	return false
end

function Model:save(filename)
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
