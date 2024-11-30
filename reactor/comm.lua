-- <<<kernel>>>

local kernel = require("apis/kernel")

local commChannel = 5

local modem = peripheral.find("modem")
if modem == nil then
	error("Remote logger requires an attached modem")
end

modem.open(commChannel)

local function send(...)
	modem.transmit(commChannel, commChannel, table.pack(...))
end

local msgBuf = {}
local function receive()
	if #msgBuf == 0 then return nil end

	return table.unpack(table.remove(msgBuf, 1))
end

local shouldBuffer = true
local function buffer(should)
	if should == nil then should = true end

	shouldBuffer = should
end


local function handleMsg(event)
	local msg = event[5]

	if shouldBuffer then table.insert(msgBuf, msg) end

	os.queueEvent("comm", "receive", table.unpack(msg))
end

kernel.events.addHandler(handleMsg, nil, "modem_message", peripheral.getName(modem), commChannel)

return {
	send = send,
	receive = receive,
	buffer = buffer
}
