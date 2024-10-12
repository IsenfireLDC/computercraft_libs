-- <<<>>>
-- Serialization API

-- Serializes item based on type
local function serialize(item)
    local typestr = type(item)

    if typestr == "number" then
        return string.pack("<i4", item)
    else
        return nil
    end
end

-- Unserializes item based on type
local function unserialize(typestr, item)
    if typestr == "number" then
        return string.unpack("<i4", item)
    else
        return nil
    end
end

return {
    serialize = serialize,
    unserialize = unserialize
}
