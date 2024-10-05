local kernel = require("apis/kernel")

local procs = kernel.process_list()
print("#"..#procs.." processes")

print("    PID  NICE STATE   ARGS")
for i,v in ipairs(procs) do
	print(string.format("[%d] %-4d %-4d %-7s %s", i, v.pid, v.nice, v.state, v.args))
end

