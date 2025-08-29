-- <<<>>>


RoutingTable = {
	routes = nil
}

function RoutingTable:new(obj)
	obj = obj or {}

	if not obj.routes then obj.routes = {} end

	setmetatable(obj, self)
	self.__index = self

	return obj
end

-- Export the best routes
function RoutingTable:export(other, requested)
	-- Export routes for every host
	if not requested then
		for host, routes in pairs(self.routes) do
			other:add(host, routes._best, routes[routes._best])
		end

	-- Export routes for requested hosts
	else
		for host, _ in pairs(requested.routes) do
			local route = self:get(host)

			if route then
				other:add(host, route, self.routes[host][route])
			end
		end
	end
end

function RoutingTable:import(other)
	for host, routes in pairs(other.routes) do
		for route, dest in pairs(routes) do
			if route ~= '_best' then
				self:add(host, route, dist)
			end
		end
	end

	return true
end

function RoutingTable:add(host, route, distance)
	distance = distance or 0

	if not self.routes[host] then
		self.routes[host] = {
			_best = route
		}
	else
		local routes = self.routes[host]
		local bestRoute = routes._best
		local bestDist = routes[bestRoute]

		if bestRoute == route and distance > bestDist then
			-- Recalculate the shortest route
			self:recalculateBest(host)
		elseif distance < bestDist then
			routes._best = route
		end
	end

	self.routes[host][route] = distance

	return self.routes[host]._best
end


function RoutingTable:del(host, route)
	if not host then return end

	-- Delete all routes through the host if a route wasn't specified
	if not route then
		-- Delete routes for this host
		self.routes[host] = nil

		-- Delete all routes through this host
		for shost, _ in pairs(self.routes) do
			self:del(shost, host)
		end

	-- Otherwise, only delete single route
	else
		local routes = self.routes[host]
		routes[route] = nil

		-- If that was the best route, recalculate
		if routes._best == route then
			routes._best = nil

			self:recalculateBest(host)

			-- If there was no best route found, assume there are no routes
			if routes._best == nil then
				self.routes[host] = nil
			end
		end
	end
end

function RoutingTable:get(host)
	local routes = self.routes[host]
	if not routes then return nil end

	return self.routes[host]._best
end

function RoutingTable:dist(host)
	local routes = self.routes[host]
	if not routes then return nil end

	return routes[routes._best]
end



-- [Helper]
function RoutingTable:recalculateBest(host, minDist)
	local routes = self.routes[host]
	if not routes then return nil, "No routes" end

	for sroute, dist in pairs(routes) do
		if sroute ~= "_best" and not minDist or dist < minDist then
			minDist = dist
			routes._best = sroute
		end
	end
end
