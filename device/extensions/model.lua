-- <<<interface:device/extension|api:model>>>

require("interfaces/device/extension")

require("apis/model")


ModelExtension = DeviceExtension:new{
	extensionName = 'model',

	modelFile = nil,
	model = nil
}

function ModelExtension:new(obj)
	obj = obj or {}

	if not obj.model then obj.model = Model:new{} end

	setmetatable(obj, self)
	self.__index = self

	return obj
end


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
