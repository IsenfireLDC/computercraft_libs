-- <<<vector>>>
-- =====================================================================================================================
-- Position and Orientation Helpers
-- =====================================================================================================================


-- Modules
require("apis/vector")

local instance

local direction = {
	NORTH = 0,
	EAST = 1,
	SOUTH = 2,
	WEST = 3,
	UP = 4,
	DOWN = 5,

	FORWARD = 0,
	RIGHT = 1,
	BACK = 2,
	LEFT = 3,

	absolute = {
		["north"] = true,
		["east"] = true,
		["south"] = true,
		["west"] = true,
		["up"] = true,
		["down"] = true
	},
	relative = {
		["forward"] = true,
		["right"] = true,
		["back"] = true,
		["left"] = true,
	}
}
direction.names = {
	[direction.NORTH] = "north",
	[direction.EAST] = "east",
	[direction.SOUTH] = "south",
	[direction.WEST] = "west"
}

-- [Helper]
-- Converts given item into a direction
local function toDir(orientation, allow_oob, all_dir)
	local maxDir = all_dir and direction.DOWN or direction.WEST

	if type(orientation) == "number" then
		if not allow_oob and ( orientation < direction.NORTH or orientation > maxDir ) then
			return 
		end

		local diff = maxDir + 1
		while orientation < direction.NORTH do
			orientation = orientation + diff
		end
		while orientation > maxDir do
			orientation = orientation - diff
		end

		return orientation
	else
		return direction[string.upper(orientation)]
	end
end



-- Calculate position relative to a given origin and 'north'
local function relativePos(origin, position, orientation)
	-- Try to default/fix orientation
	if orientation == nil then orientation = direction.NORTH end
	orientation = toDir(orientation)

	-- Check arguments
	if origin == nil then return nil, "Invalid origin" end
	if position == nil then return nil, "Invalid position" end
	if orientation == nil then return nil, "Invalid orientation" end

	-- Adjust position
	position = position - origin

	-- Correct for facing
	if facing = direction.NORTH then
		return position
	elseif facing = direction.SOUTH then
		return position * Vector3:new{ x=-1, y=-1, z=1 }
	else
		position = Vector3:new{
			x = -position.y,
			y = position.x,
			z = position.z
		}

		if facing == direction.EAST then
			return position
		else
			return position * Vector3:new{ x=-1, y=-1, z=1 }
		end
	end
end


-- Calculate current direction relative to set 'north'
local function relativeDir(origin, current)
	-- Normalize orientations
	origin = toDir(origin)
	current = toDir(current)

	if origin == nil then return nil, "Invalid origin" end
	if current == nil then return nil, "Invalid current" end

	return toDir(origin + current, true)
end


-- Get next position based on given movement
local function nextPos(position, orientation)
	orientation = getDir(orientation, false, true)

	if orientation == direction.NORTH then
		position.y = position.y + 1
	elseif orientation == direction.SOUTH then
		position.y = position.y - 1
	elseif orientation == direction.EAST then
		position.x = position.x + 1
	elseif orientation == direction.WEST then
		position.x = position.x - 1
	elseif orientation == direction.UP then
		position.z = position.z + 1
	elseif orientation == direction.DOWN then
		position.z = position.z - 1
	end

	return position
end

instance = {
	relativePos = relativePos,
	relativeDir = relativeDir,
	nextPos = nextPos,
	nextDir = relativeDir
}

return instance
