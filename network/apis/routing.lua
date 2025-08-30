-- <<<api:kernel;interface:net/proto>>>

local kernel = require("apis/kernel")

require("interfaces/net/proto")

require("apis/net/routing_table")




-- Enumeration of routing packet types
local RouteType = {
	ALL = "all",
	UPDATE = "update",
	CLOSE = "close",
	REFRESH = "refresh"
}

-- Settings
local LOAD_CALC_PERIOD = 5
local UPDATE_PERIOD = 15
local LOAD_WEIGHT_PREV = .8
local UPDATES_PER_REFRESH = 20
local STARTUP_REFRESH_DELAY = 5




local helpers = {}


NetProtoRouting = NetProto:new{
	id = "routing",
	link = nil,

	inet = nil,
	routes = nil,

	-- Route changes
	doAll = false,
	updated = nil,
	closed = nil,

	-- Load metric
	packets = 0,
	load = 1
}


function NetProtoRouting:new(obj, inet)
	obj = obj or {}
	obj.inet = inet

	if not obj.link then return nil, "Need link" end

	if not obj.routes then
		obj.routes = RoutingTable:new{}
	end

	obj.updated = {}
	obj.closed = {}

	-- Add self-route to the routing table
	local address = helpers.address(obj)
	if not obj.routes:get(address) then
		NetProtoRouting.addRoute(obj, address, address, 0)
	end

	-- Replace the on_recv function of link; increment packet count and call original
	local oldRecv = obj.link.on_recv
	obj.link.on_recv = function(self, proto, data, from)
		obj.packets = obj.packets + 1

		return oldRecv(self, proto, data, from)
	end

	-- Replace the routing function of inet; fallback to original if no route found
	if obj.inet then
		local oldRouter = obj.inet.route
		obj.inet.route = function(self, to)
			local route = obj.routes:get(to)

			if not route then 
				return oldRouter(self, to)
			end

			return route
		end
	end

	obj._startupRefresh = os.clock() + STARTUP_REFRESH_DELAY

	setmetatable(obj, self)
	self.__index = self

	return obj
end

function NetProtoRouting:delete()
	self:stop()
end



function NetProtoRouting:processPacket(from, data)
	self.packets = self.packets + 1

	local hostLoad = data.load or 1

	if data.type == RouteType.ALL then
		-- Reset all routes through this host, then add all routes given
		self.routes:del(data.host)
		helpers.updateRoutes(self, data, hostLoad)
	elseif data.type == RouteType.UPDATE then
		helpers.updateRoutes(self, data, hostLoad)
	elseif data.type == RouteType.CLOSE then
		for _,route in ipairs(data.routes) do
			helpers.closeRoute(self, route)
		end
	elseif data.type == RouteType.REFRESH then
		if self._startupRefresh then
			self._startupRefresh = os.clock() + STARTUP_REFRESH_DELAY
		end

		self.doAll = true
		helpers.sendUpdate(self)
	end
end

function NetProtoRouting:send(data, to)
	self.link:send(self.id, data, to)
end



function NetProtoRouting:start()
	-- Send regular status updates
	if not self._taskUpdate then
		self._taskUpdate = kernel.start(function()
			sleep(math.random(0, UPDATE_PERIOD))

			while true do
				helpers.sendUpdate(self)

				sleep(UPDATE_PERIOD)
			end
		end)
	end

	-- Regularly calculate node load
	if not self._taskLoad then
		self._taskLoad = kernel.start(function()
			sleep(math.random(0, LOAD_CALC_PERIOD))

			while true do
				helpers.calculateLoad(self)

				sleep(LOAD_CALC_PERIOD)
			end
		end)
	end

	-- Request a full refresh on startup
	if not self._taskRefresh and self._startupRefresh then
		self._taskRefresh = kernel.start(function()
			repeat
				sleep(self._startupRefresh - os.clock())
			until not self._startupRefresh or self._startupRefresh < os.clock()

			if self._startupRefresh then
				self._startupRefresh = nil

				self:send({
					host = helpers.address(self),
					type = RouteType.REFRESH
				})
			end
		end)
	end

	self._updateCount = 0
end

function NetProtoRouting:stop()
	-- Closing route to this host closes all routes through this host
	-- TODO: Check that this works
	helpers.closeRoute(self, {to=helpers.address(self)})

	-- Kill regular tasks
	kernel.stop(self._taskLoad)
	kernel.stop(self._taskUpdate)

	self._startupRefresh = nil
	kernel.stop(self._taskRefresh)

	-- Notify network of this host closing
	helpers.sendUpdate(self)

	self._taskLoad = nil
	self._taskUpdate = nil
end



function NetProtoRouting:addRoute(to, router, cost)
	if not to then return end
	cost = cost or 1

	helpers.updateRoute(self, {to=to, dist=cost}, router)
end

function NetProtoRouting:closeRoute(to)
	if not to then return end

	helpers.closeRoute(self, {to=to})
end









function helpers.address(self)
	return self.inet and self.inet.address or nil
end


function helpers.calculateLoad(self)
	self.load =
		(LOAD_WEIGHT_PREV * self.load) +
		((1 - LOAD_WEIGHT_PREV) * self.packets / LOAD_CALC_PERIOD)

	self.packets = 0
end


-- Send a full update
function helpers.sendUpdate(self)
	local address = helpers.address(self)

	-- Send a full refresh after a fixed number of updates
	if self._updateCount >= UPDATES_PER_REFRESH then
		-- Don't bother with a special request if it's been this long
		self._startupRefresh = nil

		self._updateCount = 0
		self.doAll = true
	end

	if self.doAll then
		-- Fill self.updated with all routes
		local fauxRoutingTable = {
			add = function(_, host)
				if host == -1 then return end

				self.updated[host] = true
			end
		}
		self.routes:export(fauxRoutingTable)
	end


	-- Create entries for updated routes
	local updated = {}
	for dest, _ in pairs(self.updated) do
		table.insert(updated, {
			to = dest,
			dist = self.routes:dist(dest) or 1,
			next = self.routes:get(dest)
		})
	end

	-- Always send an update packet so there is a heartbeat
	self:send({
		host = address,
		type = self.doAll and RouteType.ALL or RouteType.UPDATE,
		routes = updated,
		load = self.load
	})


	-- Send separate packet for closed routes unless this is a full update
	if not self.doAll then
		local closed = {}
		for dest, _ in pairs(self.closed) do
			table.insert(closed, {
				to = dest
			})
		end

		-- Don't send a closed packet if nothing was closed
		if #closed > 0 then
			self:send({
				host = address,
				type = RouteType.CLOSE,
				routes = closed,
				load = self.load
			})
		end
	end

	self.updated = {}
	self.closed = {}
	self.doAll = false

	self._updateCount = self._updateCount + 1
end


-- Send a packet to update a set of routes
function helpers.sendSwap(self, routes)
	if not routes then return end
	local address = helpers.address(self)

	-- Create entries for changed routes
	local swapped = {}
	for dest, _ in pairs(routes) do
		table.insert(swapped, {
			to = dest,
			dist = self.routes:dist(dest),
			next = self.routes:get(dest)
		})
	end

	if #swapped <= 0 then return end

	self:send({
		host = helpers.address(self),
		type = self.doAll and RouteType.ALL or RouteType.UPDATE,
		routes = swapped,
		load = self.load
	})
end


-- Update a single route or add to a set to send as a batch later
function helpers.updateRoute(self, route, router, _hostLoad, _batch)
	if type(route.to) ~= 'number' then
		error("BAD TYPE: "..type(route.to))
	end

	_hostLoad = _hostLoad or 0

	local oldRoute = self.routes:get(route.to)
	local newRoute = self.routes:add(route.to, router, route.dist + _hostLoad)

	if oldRoute and oldRoute ~= newRoute then
		if _batch then
			if not self._toSwap then self._toSwap = {} end

			self._toSwap[route.to] = true
		else
			helpers.sendSwap(self, {[route.to] = true})
		end
	end

	self.updated[route.to] = true
end


-- Update a set of routes from an update packet
function helpers.updateRoutes(self, packet, hostLoad)
	local updated = {}
	for _,route in ipairs(packet.routes) do
		--print("rn> update["..packet.host.."]: to "..route.to.." via "..route.next.." with cost", route.dist)
		if route.next ~= helpers.address(self) then
			helpers.updateRoute(self, route, packet.host, hostLoad, true)

			table.insert(updated, route.to)
		end
	end

	if self._toSwap then
		helpers.sendSwap(self, self._toSwap)
		self._toSwap = {}
	end
end


-- Close a route and add it to the set for the next update
function helpers.closeRoute(self, route)
	self.routes:del(route.to)
	self.closed[route.to] = true
end
