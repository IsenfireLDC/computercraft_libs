local kernel = require("apis/kernel")

local function top()
	while true do
		term.clear()
		term.setCursorPos(1, 1)

		shell.run("ps")
	end
end

kernel.start(top)
