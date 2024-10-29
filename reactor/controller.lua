-- <<<kernel|system>>>
-- Reactor Controller (Mekanism)

local kernel = require("apis/kernel")
require("apis/system")

local instance

-- =================== Adjustable IO =======================
local reactor = peripheral.wrap("fissionReactorLogicAdapter_1")
local turbine = peripheral.wrap("turbineValve_1")
local buffer = peripheral.wrap("ultimateEnergyCube_1")

local maxBurnRate = 20

local defaultBurnRate = 0.5

if _G.log == nil then
	_G.log = {
		info = function(...) print("Info:  ", ...) end,
		warn = function(...) print("Warn:  ", ...) end,
		error = function(...) printError("Err:   ", ...) end
	}
end

-- Return if the reactor is in an unsafe state
local protectMsg
local function reactorUnsafe()
	if reactor.getTemperature() > 1100 then
		protectMsg = "High temperature"
		return true
	end

	return false
end

-- Kill the reactor (emergency shutdown)
local function scram()
	if reactor.getStatus() then
		reactor.scram()
	end

	if protectMsg then
		log.error(protectMsg)
	end
end

-- Shutdown reactor (also scram in mekanism)
local shutdown = scram

-- Start the reactor
local function startup()
	reactor.setBurnRate(defaultBurnRate)
	reactor.activate()
end

-- Return if reactor is active
local function reactorRunning()
	return reactor.getStatus()
end

-- Return power setting of the reactor
local function getPowerSetting()
	return reactor.getBurnRate()
end

-- Return reactor steam output / tick
local function getSteamProduction()
	return reactor.getHeatingRate()
end

-- Return turbine steam usage / tick
local function getSteamConsumption()
	return turbine.getFlowRate()
end

-- Return turbine power production / tick
local function getPowerProduction()
	return turbine.getProductionRate()
end

-- Return buffer power output / tick
-- 'ingame' epoch doesn't change
local lastBufferReading = os.epoch('utc') / 50
local lastBufferLevel = buffer.getEnergy()
local function getPowerConsumption()
	local reading = os.epoch('utc') / 50
	local level = buffer.getEnergy()

	local deltaT = reading - lastBufferReading
	local deltaV = level - lastBufferLevel
	local output = getPowerProduction() - (deltaV / deltaT)

	-- If buffer is overflowing, read a lower output value to reduce power
	if output > 256000 then
		output = 256000 -- Hardcode max rate; don't know why it's working so badly
	end
	--log.info("C> dT "..tostring(deltaT).."> dV "..tostring(deltaV).."> OUT "..tostring(output))

	lastBufferReading = reading
	lastBufferLevel = level

	return output
end

-- Return buffer fill fraction
local function getBufferLevel()
	return buffer.getEnergyFilledPercentage()
end

-- Return buffer capacity
local function getBufferMax()
	return buffer.getMaxEnergy()
end
-- ================= End Adjustable IO =====================


-- ====================== Settings =========================
local bufferTarget = 0.5 -- Target fill fraction
local timestep = 20      -- Timestep (ticks) for following parameters
local closingFrac = 0.8  -- Buffer delta close rate goal (try to reduce the delta to target by x fraction per timestep)
local maxPower = 256000  -- Max allowed power output for adjusting buffer
-- Buffer max delta (don't exceed this fraction of the buffer per timestep while closing delta)
local maxDelta = maxPower / getBufferMax()
-- ==================== End Settings =======================





-- Response Tuning
local reactorModel = SystemModel:new{step=4000}
local turbineModel = SystemModel:new{step=10}
local flowModel = SystemModel:new{step=0.5, adjustFraction=0.05}

local flowSamples = 5
local flowSteps = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local function predictFlow(steps)
	local y = 0
	for i=1,#steps,1 do
		y = y + flowModel:response(i) * steps[i]
	end
	return y
end
local function slice(t, first, last)
	local newT = {}
	for i=first,last,1 do
		table.insert(newT, t[i])
	end

	return newT
end
local function updateFlow(val)
	-- Shift flow data queue
	if #flowSteps >= 2*flowSamples then table.remove(flowSteps) end
	table.insert(flowSteps, 1, val)

	-- Tune a fixed step based on each of the positions in the window
	for i=1,flowSamples,1 do
		local steps = slice(flowSteps, i, i+flowSamples)
		steps[flowSamples - i + 1] = 0 -- Zero out the tuning location
		local carry = predictFlow(steps)

		local current = flowSteps[flowSamples] - carry -- Current tick effects only
		local resp = current / flowSteps[flowSamples]  -- Convert to value 0-1
		flowModel:tune(i, resp)
	end
end

local files = {
	reactor = "data/model/reactor.dat",
	turbine = "data/model/turbine.dat",
	flow = "data/model/flow.dat"
}

if not reactorModel:load(files.reactor) then log.warn("No reactor model data") end
if not turbineModel:load(files.turbine) then log.warn("No turbine model data") end
if not flowModel:load(files.flow) then log.warn("No flow model data") end


-- Expected values from last timestep
local eReactor
local eTurbine
local eFlow

-- Tune the models with this tick's data
local function tune()
	local iReactor = getPowerSetting()
	local oReactor = getSteamProduction()
	--log.info("Reactor> IN "..tostring(iReactor).."> OUT "..tostring(oReactor).."> EXP "..tostring(eReactor))
	log.info("Tuning reactor; last error: "..(eReactor - oReactor))
	reactorModel:tune(iReactor, oReactor, eReactor)

	local iTurbine = getSteamConsumption()
	local oTurbine = getPowerProduction()
	--log.info("Turbine> IN "..tostring(iTurbine).."> OUT "..tostring(oTurbine).."> EXP "..tostring(eTurbine))
	log.info("Tuning turbine; last error: "..(eTurbine - oTurbine))
	turbineModel:tune(iTurbine, oTurbine, eTurbine)

	local iFlow = oReactor;
	local oFlow = iTurbine;
	log.info("Tuning flow; last error: "..(eFlow - oFlow))
	updateFlow(oFlow)
end

-- Adjust the reactor settings
local function adjust(noUpdate)
	-- Calculate next target level
	local level = getBufferLevel()
	local targetDelta = (bufferTarget - level) * closingFrac
	if math.abs(targetDelta) > maxDelta then
		targetDelta = maxDelta * (targetDelta < 0 and -1 or 1)
	end

	-- Calculate new power production
	local output = getPowerConsumption() * timestep
	local targetPowerProduction = (targetDelta * getBufferMax() + output) / timestep
	--log.info("A> OUT "..tostring(output).."> DELTA "..tostring(targetDelta).."> BUF "..tostring(getBufferMax()))
	log.info("Target power: "..targetPowerProduction)

	-- Calculate new input levels
	local targetSteamFlow = turbineModel:action(targetPowerProduction)
	log.info("Target steam: "..targetSteamFlow)

	local expectedFlow = predictFlow(slice(flowSteps, 1, flowSamples-1))
	local targetSteamProduction = targetSteamFlow / flowModel:response(1)

	local targetPowerLevel = reactorModel:action(targetSteamFlow)
	log.info("Target setting: "..targetPowerLevel)

	if not noUpdate then
		if targetPowerLevel > maxBurnRate then
			targetPowerLevel = maxBurnRate
		end

		reactor.setBurnRate(targetPowerLevel)
	end

	return targetSteamFlow, targetPowerProduction, targetSteamProduction
end


-- Handle commands and manage reactor
local function manage()
	local lastCmd = "NONE"

	log.info("Manager started")
	if reactorRunning() then
		instance.cmd = "RUN"
	end

	while true do
		--log.info("<Loop>")

		-- A mutex would be nice...
		local cmd = instance.cmd

		if cmd == "SCRAM" then
			scram()
			log.info("Reactor scrammed")
			instance.cmd = "NONE"
		elseif cmd == "STOP" then
			log.info("Stopping reactor")
			shutdown()
			instance.cmd = "NONE"
		elseif cmd == "START" then
			log.info("Starting reactor")
			startup()
			log.info("Started reactor")
			instance.cmd = "RUN"
		elseif cmd == "EXIT" then
			log.info("Manager exiting")
			if reactorRunning() then
				log.info("Shutting down reactor")
				shutdown()
			end

			return
		elseif cmd == "RUN" then
			log.info(">RUN")
			if lastCmd ~= "RUN" then
				log.info("Managing reactor")

				-- Initialize expected values
				eReactor, eTurbine, eFlow = adjust(true)
			end

			tune()
			eReactor, eTurbine, eFlow = adjust()
		end

		lastCmd = cmd

		kernel.sleep(timestep / 20)
	end
end

-- Save current model tuning parameters
local function saveModels()
	reactorModel:save(files.reactor)
	turbineModel:save(files.turbine)
	flowModel:save(files.flow)
end

-- Check reactor conditions and scram if unsafe
local function failsafe()
	if reactorUnsafe() then
		scram()
	end
end

instance = {
	cmd = "NONE"
}

-- Schedule services and process
kernel.tasks.schedule(failsafe, 1, 1)
kernel.tasks.schedule(saveModels, 30, 30)
kernel.start(manage, "MANAGER")

return instance
