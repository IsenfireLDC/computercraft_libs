local localLogger = _G.log

local logger = {}
_G.log = logger

local kernel = require("apis/kernel")
local comm = require("apis/comm")

comm.buffer(false)

local Level = {
	None = 0,
	Info = 1,
	Warn = 2,
	Error = 3
}

-- Local -> Remote
local function callIf(func, ...)
	if func then func(...) end
end
local function logRemote(level, ...)
	comm.send({ type = 'log', level = level, data = table.pack(...) })
end

function logger.info(...)
	callIf(localLogger.info, ...)
	logRemote(Level.Info, ...)
end

function logger.warn(...)
	callIf(localLogger.warn, ...)
	logRemote(Level.Warn, ...)
end

function logger.error(...)
	callIf(localLogger.error, ...)
	logRemote(Level.Error, ...)
end



local function receiveLog(event)
	local msg = event[3]
	if msg.type ~= 'log' then return end

	local logFunc
	if msg.level == Level.Info then
		logFunc = localLogger.info
	elseif msg.level == Level.Warn then
		logFunc = localLogger.warn
	elseif msg.level == Level.Error then
		logFunc = localLogger.error
	end

	callIf(logFunc, table.unpack(msg.data))
end

kernel.events.addHandler(receiveLog, nil, "comm", "receive")

return true
