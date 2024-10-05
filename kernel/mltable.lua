-- <<<>>>
-- Multi-Layer Table
--
-- API for managing a set of nested tables
-- A given table is accessed by a list of keys

-- TODO: Add option to accept any key at a certain level

-- Class MLTable
MLTable = {}

-- Constructor
function MLTable:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

-- Adds a k-v pair at the given location multitable
function MLTable:add(key, value, ...)
    local vargs = {...}

    local level = self
    for _,arg in ipairs(vargs) do
        if arg == nil then
            arg = "_any"
        end

        local next_level = level[arg]
        if not next_level then
            level[arg] = {}
        end

        level = level[arg]
    end

    if not level._items then
        level._items = {}
    end

    level._items[key] = value
end

-- Removes key from the table
function MLTable:remove(key, ...)
    local vargs = {...}

    local level = self
    for _,arg in ipairs(vargs) do
        if arg == nil then
            arg = "_any"
        end

        local next_level = level[arg]
        if not next_level then
            return
        end

        level = level[arg]
    end

    if not level._items then
        return
    end

    level._items[key] = nil
end

-- Gets an item
function MLTable:get(key, ...)
    local vargs = {...}

    local level = self
    for _,arg in ipairs(vargs) do
        local next_level = level[arg]
        if not next_level then
            return nil
        end

        level = level[arg]
    end

    return level._items[key]
end

-- Removes entire table at the given layer
function MLTable:remove_table(...)
    local vargs = {...}

    local level = self
    for _,arg in ipairs(vargs) do
        local next_level = level[arg]
        if not next_level then
            return
        end

        level = level[arg]
    end

    if not level._items then
        return
    end

    level._items = nil
end

-- Gets the item table at the given layer
function MLTable:get_table(...)
    local vargs = {...}

    local level = self
    for _,arg in ipairs(vargs) do
        local next_level = level[arg]
        if not next_level then
            return nil
        end

        level = level[arg]
    end

    return level._items
end

-- Removes all items on the given path
function MLTable:remove_all(...)
    local vargs = { ... }

    local level = self
    for _,arg in ipairs(vargs) do
        local next_level = level[arg]
        if not next_level then
            return
        end

        level = level[arg]

        level._items = nil
    end
end


-- Gets all items on the given path
-- Will take value at higher layer over value at lower layer for the same key
function MLTable:get_all_set(...)
    local vargs = { ... }

    local items = {}
    local level = self
    local i = 1

    -- Recursive function to build set using _any and given arguments
    -- Was too lazy to figure out how to do this with a stack
    -- TODO: Maybe a queue-based implementation would make sense?
    local build_set
    build_set = function(level, i)
        if level._items then
            for k,v in pairs(level._items) do
                items[k] = v
            end
        end

        if level._any then
            build_set(level._any, i+1)
        elseif vargs[i] ~= nil and level[vargs[i]] then
            build_set(level[vargs[i]], i+1)
        end
    end

    build_set(self, 1)

    return items
end

-- Clears all elements
-- TODO: Implementation seems questionable; make mlt a member?
function MLTable:clear()
    self = MLTable:new()
end