local kernel = require("apis/kernel")

if not fs.exists("/init.lua") then
	print("Missing initialization file")
	return
end

local pid, msg = kernel.exec("/init.lua")
if not pid then
	error("Could not create initialization process: "..msg)
end

print(kernel.run())
