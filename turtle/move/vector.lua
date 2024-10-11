-- <<<>>>
--
-- Vectors

Vector3 = {
	x = 0,
	y = 0,
	z = 0
}


-- Vector constructor
function Vector3:new(obj)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self

    return obj
end

function Vector3.zero()
	return Vector3:new{ x=0, y=0, z=0 }
end

function Vector3:magnitude()
	return math.sqrt( self.x ^ 2 + self.y ^ 2 + self.z ^ 2 )
end

function Vector3:normalize()
	local magnitude = self.magnitude()

	return Vector3:new{
		self.x / magnitude,
		self.y / magnitude,
		self.z / magnitude
	}
end

function Vector3:abs()
	return Vector3:new{
		x = math.abs(self.x),
		y = math.abs(self.y),
		z = math.abs(self.z)
	}
end

function Vector3:max()
	return Vector3:new{
		x = self.x >= self.y and self.x >= self.z and self.x or 0,
		y = self.y > self.x and self.y >= self.z and self.y or 0,
		z = self.z > self.x and self.z > self.y and self.z or 0
	}
end


function Vector3:dot(other)
	return self.x*other.x + self.y*other.y + self.z*other.z
end
function Vector3:__mul(other)
	if type(other) == "number" then
		return Vector3:new{
			x = self.x * other,
			y = self.y * other,
			z = self.z * other
		}
	else
		return Vector3:new{
			x = self.x * other.x,
			y = self.y * other.y,
			z = self.z * other.z
		}
		--return self:dot(other)
	end
end

function Vector3:cross(other)
	return Vector3:new{
		x = self.y*other.z - self.z*other.y,
		y = self.z*other.x - self.x*other.z,
		z = self.x*other.y - self.y*other.x,
	}
end
Vector3.__pow = Vector3.cross

function Vector3:__div(other)
	if type(other) == "number" then
		return Vector3:new{
			x = self.x / other,
			y = self.y / other,
			z = self.z / other
		}
	else
		return Vector3:new{
			x = self.x / other.x,
			y = self.y / other.y,
			z = self.z / other.z
		}
	end
end

function Vector3:__idiv(other)
	if type(other) == "number" then
		return Vector3:new{
			x = math.floor(self.x / other),
			y = math.floor(self.y / other),
			z = math.floor(self.z / other)
		}
	else
		return Vector3:new{
			x = math.floor(self.x / other.x),
			y = math.floor(self.y / other.y),
			z = math.floor(self.z / other.z)
		}
	end
end


function Vector3:__add(other)
	if type(other) == "number" then
		return Vector3:new{
			x = self.x + other,
			y = self.y + other,
			z = self.z + other
		}
	else
		return Vector3:new{
			x = self.x + other.x,
			y = self.y + other.y,
			z = self.z + other.z
		}
	end
end

function Vector3:__sub(other)
	if type(other) == "number" then
		return Vector3:new{
			x = self.x - other,
			y = self.y - other,
			z = self.z - other
		}
	else
		return Vector3:new{
			x = self.x - other.x,
			y = self.y - other.y,
			z = self.z - other.z
		}
	end
end


function Vector3:__unm()
	return Vector3:new{
		x = -self.x,
		y = -self.y,
		z = -self.z
	}
end


function Vector3:__eq(other)
	return self.x == other.x and self.y == other.y and self.z == other.z
end

function Vector3:__lt(other)
	return self:magnitude() < other:magnitude()
end

function Vector3:__lt(other)
	return self == other or self < other
end


function Vector3:__concat(other)
	local str = "{ x="..self.x..", y="..self.y..", z="..self.z.." }"

	if other ~= nil then
		str = str .. other
	end

	return str
end
