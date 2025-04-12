-- <<<interface:kernel/driver>>>

require("interfaces/kernel/driver")

ReactorDriver = IDriver:new{
	ready = nil,

	start = nil,
	stop = nil,
	scram = nil,

	getBurnRate = nil,
	getTemperature = nil,
	getOutput = nil,

	setBurnRate = nil
}

function ReactorDriver:state()
	return "unknown"
end
