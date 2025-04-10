local kernel = require("apis/kernel")

if not fs.exists("/init.lua") then
	print("Missing initialization file")
	return
end

kernel.start(function()
	while true do
		local event = kernel.wait(nil, 'kernel', 'process_complete')

		print("Process "..event[3].." "..event[4]..":", event[5] and event[5] or '')
	end
end)

kernel.start(function()
	while true do
		local event = kernel.wait(nil, 'kernel', 'device')

		print("Device "..event[3].."ed on side "..event[4].." with type(s):", table.unpack(event[5]))
	end
end)

kernel.exec("/init.lua")

kernel.run()
