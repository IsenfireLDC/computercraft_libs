local kernel = require("apis/kernel")


local instance

local oldPrint



instance = {
}

return {
	handlers = {
		startup = function()
			oldPrint = print

			print = function(...)
				return oldPrint("["..kernel.pid().."]", ...)
			end
		end,
		shutdown = function()
			print = oldPrint
		end
	},
	interface = instance
}
