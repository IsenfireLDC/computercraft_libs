-- <<<interface:device/controller|api:model>>>

require("interfaces/device/controller")

require("apis/model")


ModelExtension = DeviceExtension:new{
	extensionName = 'model',

	modelFile = nil,
	model = nil
}


function ModelExtension:getModelFile()
	return self.modelFile
end
function ModelExtension:setModelFile(path)
	if not path then return end

	self.modelFile = path
end

function ModelExtension:loadModel()
	return self.model:load(self.modelFile)
end
function ModelExtension:saveModel()
	return self.model:save(self.modelFile)
end
