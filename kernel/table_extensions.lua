-- <<<>>>
-- Lua Table Library Extensions
-- Adds additional functions to the lua table library
function table.find(t, value)
	for i,v in ipairs(t) do
		if v == value then
			return i
		end
	end

	return nil
end

function table.copy(t)
	local cpy = {}

	for k,v in pairs(t) do
		cpy[k] = v
	end

	return cpy
end

function table.deepcopy(t, items)
	local cpy = {}
	items = items or {}

	-- Keep cache of previously copied items, use cached if present
	-- TODO: Make this work
	local iCpy = items[t]
	if iCpy ~= nil then
		return iCpy
	else
		items[t] = {}
	end

	for k,v in pairs(t) do
		if type(k) == "table" then
			k = table.deepcopy(k, items)
		end

		if type(v) == "table" then
			v = table.deepcopy(v, items)
		end

		cpy[k] = v
	end

	items[t].value = cpy

	return cpy
end

function table.getkey(t, value)
	for k, v in pairs(t) do
		if v == value then
			return k
		end
	end

	return nil
end

function table.ser(t) --, items)
	kvpairs = {}
	--items = items or {_idx=0}

	-- TODO: Keep cache of previously seen items
	-- WARN: Until TODO, cannot support recursive
	--local iCpy = items[t]
	--if iCpy ~= nil then
	--	return "{["..iCpy.."]=''}"
	--else
	--	items[t] = items._idx
	--	items._idx = items._idx + 1
	--end

	for k,v in pairs(t) do
		if type(k) == "table" then
			k = table.ser(k)
		elseif type(k) == "boolean" then
			k = k and "true" or "false"
		elseif type(k) == "thread" then
			k = "<thread>"
		elseif type(k) == "string" then
			k = '"'..k..'"'
		end

		if type(v) == "table" then
			v = table.ser(v)
		elseif type(v) == "boolean" then
			v = v and "true" or "false"
		elseif type(v) == "thread" then
			v = "<thread>"
		elseif type(v) == "string" then
			v = '"'..v..'"'
		end

		table.insert(kvpairs, k.."="..v)
	end

	return "{ "..table.concat(kvpairs, ", ").." }"
end

function table.concat2(t, sep)
	sep = sep or ""

	fixed = {}
	for _,v in ipairs(t) do
		if type(v) == "table" then
			v = table.ser(v)
		elseif type(v) == "boolean" then
			v = v and "true" or "false"
		end

		table.insert(fixed, v)
	end

	return table.concat(fixed, sep)
end

function table.len(t, level, found)
	local len = 0
	found = found or {}

	if level ~= nil then
		level = level - 1
		if level < 0 then
			return 0
		end
	end

	if found[t] then
		return 0
	else
		found[t] = true
	end

	for k,v in pairs(t) do
		if type(v) == "table" then
			len = len + table.len(v, level, found)
		else
			len = len + 1
		end
	end

	return len
end
