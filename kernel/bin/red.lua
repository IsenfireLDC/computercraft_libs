-- <<<api:kernel>>>
-- Remote Events Daemon

-- TODO: Send/receive via net/message
-- TODO: Update to use drivers & net/message

local kernel = require("apis/kernel")
require("apis/table_extensions")

local commChannel = 13

local modem

local redCmds = {
	table.pack("ipc", "red"),
	table.pack("modem_message", nil, commChannel, commChannel)
}

local remoteEvents = {}
local selectList = table.merge(redCmds, remoteEvents)

local function eventEqual(e1, e2)
	if e1.n ~= e2.n then
		return false
	end

	for i=1,e1.n,1 do
		if e1[i] ~= e2[i] then
			return false
		end
	end

	return true
end

local function addEvent(...)
	table.insert(remoteEvents, table.pack(...))

	selectList = table.merge(redCmds, remoteEvents)
end
local function removeEvent(...)
	local event = table.pack(...)

	local idx
	for i,e in ipairs(remoteEvents) do
		if eventEqual(event, e) then
			idx = i
			break
		end
	end

	if idx then
		table.remove(remoteEvents, idx)

		selectList = table.merge(redCmds, remoteEvents)
	end
end

local function handleCommand(...)
	local cmd = table.pack(...)

	if cmd[1] == 'add' then
		addEvent(table.unpack(cmd, 2))
	elseif cmd[1] == 'remove' then
		removeEvent(table.unpack(cmd, 2))
	end
end


local function sendMessage(event)
	local msg = {
		type = 'remote_event',
		event = event
	}

	modem.transmit(commChannel, commChannel, msg)
end
local function processMessage(msg)
	print("received msg")
	if msg.type ~= 'remote_event' then
		print("bad msg type", msg.type)
		return
	end

	os.queueEvent(table.unpack(msg.event))
end



modem = peripheral.find('modem')
if not modem then
	error("Requires an attached modem")
end

modem.open(commChannel)

while true do
	-- Wait for selected events and transmit
	local event = kernel.select(nil, table.unpack(selectList))

	if event[1] == 'ipc' and event[2] == 'red' then
		handleCommand(table.unpack(event, 3))
	elseif event[1] == 'modem_message' then
		processMessage(event[5])
	else
		sendMessage(event)
	end
end

modem.close(commChannel)
