local kernel = require("apis/kernel")

if not fs.exists("/init.lua") then
	print("Missing initialization file")
	return
end

kernel.exec("/init.lua")

print(kernel.run())
