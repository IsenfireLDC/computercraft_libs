-- <<<interface:kernel/driver>>>

require("interfaces/kernel/driver")

TurbineDriver = IDriver:new{
	ready = nil,

	getInput = nil,
	getOutput = nil,

	getInputBuffer = nil,
	getInputBufferMax = nil,
	getOutputBuffer = nil,
	getOutputBufferMax = nil
}
