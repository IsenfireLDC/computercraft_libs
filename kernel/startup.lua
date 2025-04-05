local kernel = require("apis/kernel2")

if not fs.exists("/init.lua") then
	print("Missing initialization file")
	return
end

-- Put require into _G so it is available in 'dofile'
_G.require = require

kernel.start(function()
	while true do
		local event = kernel.wait(nil, 'kernel', 'process_complete', nil, 'errored')

		print("Process "..event[3].." errored:", event[5] and event[5] or '')
	end
end)

kernel.start(function()
	print("Running initialization file")
	dofile("/init.lua")
end)

kernel.run()
