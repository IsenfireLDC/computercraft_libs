-- <<<mltable>>>
-- CC Modules
local expect = require("cc.expect")

-- Modules
require("apis/mltable")

-- Globals
local instance = {}

local handlers = MLTable:new()
local interfaces = MLTable:new()

-- Adds a handler for any event types
-- Pass the event parameters for the event that this will handle
-- Handler should expect a list of arguments as a table
-- All registered handlers will be called
local function addHandler(handler, maxLevel, ...)
	expect(1, handler, "function")
	expect(2, maxLevel, "number", "nil")

	maxLevel = maxLevel or 0

	handlers:add(handler, maxLevel, ...)
end

-- Removes the given handler from the given event
-- Pass the event parameters for the event that this was added with
local function removeHandler(handler, ...)
	handlers:remove(handler, ...)
end



-- Register an interface class for event handling
-- Will dispatch handled events to the requested method
-- TODO: Is this necessary?
--
-- Arg method must be a string containing the method name
-- NOTE: Only one method per class per event
local function addInterface(class, method, ...)
	if not class or not method then
		return false, "Missing class or method"
	end

	interfaces:add(class, method, ...)

	return true
end

-- Remove an interface class method
local function removeInterface(class, method, ...)
	if not class or not method then return end

	interfaces:remove(class, method, ...)
end


-- [Helper]
-- Handles dispatching events
local function dispatch(event)
	local handlerSet = handlers:get_all_set(table.unpack(event))

	-- Only call event handlers at or below their max depth
	for handler,lev in pairs(handlerSet) do
		if lev == 0 or #event <= lev then
			handler(event)
		end
	end


	-- Also dispatch events to interfaces
	local interfaceSet = interfaces:get_all_set(table.unpack(event))

	for instance, method in pairs(interfaceSet) do
		method(instance, event)
	end
end

instance = {
	addHandler = addHandler,
	removeHandler = removeHandler,
	addInterface = addInterface,
	removeInterface = removeInterface,

	dispatch = dispatch
}

return instance
