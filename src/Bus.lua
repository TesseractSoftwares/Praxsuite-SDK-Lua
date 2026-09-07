--[[
    Bus - the Prax Event Bus, ephemeral realtime between connected clients.

    Cross-server player positions, a shared world clock, "somebody is in the shop": state that is
    CHANGING, where losing a message is fine because a newer one is 100ms behind it.

    ─────────────────────────────────────────────────────────────────────────────
    IT AUTHENTICATES AS A PLAYER, NOT AS THE SERVER

    The hub admits only the gateway END-USER scheme. A negotiate carrying x-api-key returns 401,
    measured 2026-09-07, so the server key this SDK usually uses cannot open a bus connection.

    Bus.Connect(player) handles that: it goes through Auth.GetTokenFor, which reuses the same
    cached per-player session `asPlayer` uses and opens no second one.

        Praxsuite.Bus.Connect(player)

    If all you need is to PUSH something to connected clients from the server, with no player
    involved, you do not need this module at all. Call an endpoint whose automation carries a
    PublishRealtimeEvent node:

        Praxsuite.Endpoints.Call(endpointId, { bus = "office:hq", event = "tick", payload = {...} })

    That path uses the server key directly.

    ─────────────────────────────────────────────────────────────────────────────
    NOTHING IS PERSISTED. No history, no retry, no delivery to anyone who was not connected. The
    test is one question: if this is lost, does it matter? Yes - a purchase, a level, an inventory
    grant - means a table via Praxsuite.Data, and a server-authoritative write at that. No, because
    a newer one is coming, means the bus.

    PAYLOADS ARE HOSTILE. The bus relays opaque JSON between USERS and parses none of it, so every
    server-side check is bypassed. A position is a hint, never an authority.

    TRANSPORT. SignalR's long-polling transport. Roblox's HttpService cannot open a WebSocket at
    all, so this is the only transport available here. Long polling is not slow polling: the GET is
    held open by the server and returns the moment a message is ready.
]]

local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.Core.Config)
local BusWire = require(script.Parent.Core.BusWire)

local Bus = {}

local POLL_TIMEOUT_SECONDS = 60
local CALL_TIMEOUT_SECONDS = 30

local _accessToken: string? = nil
local _connectionToken: string? = nil
local _buffer = ""
local _nextInvocation = 0
local _pending: { [string]: any } = {}
local _handlers: { [string]: { [string]: { (any, string) -> () } } } = {}
local _presence: { [string]: { joined: { (string) -> () }, left: { (string) -> () } } } = {}
local _joined: { [string]: boolean } = {}
local _polling = false
local _warnedAboutRouting = false

local function baseUrl(): string
	return Config._baseUrl
end

local function request(method: string, url: string, body: string?): (number, string)
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = method,
			Headers = {
				["Authorization"] = "Bearer " .. tostring(_accessToken),
				["Content-Type"] = "text/plain;charset=UTF-8",
			},
			Body = body,
		})
	end)

	if not ok then
		return 0, tostring(response)
	end
	return response.StatusCode, response.Body or ""
end

local function dispatch(busKey: string, eventName: string, payload: any, fromUserId: string)
	local forBus = _handlers[busKey]
	if not forBus then
		return
	end

	for _, name in ipairs({ eventName, "*" }) do
		for _, handler in ipairs(forBus[name] or {}) do
			-- A caller's handler must never kill the poll loop: one bad listener would take every
			-- other channel down with it.
			local success, err = pcall(handler, payload, fromUserId)
			if not success then
				warn("[Praxsuite] An Event Bus handler errored: " .. tostring(err))
			end
		end
	end
end

--- Decides which buses an inbound message belongs to.
---
--- The message names its bus, and that is the whole answer. The fallback exists because a gateway
--- older than 2026-09-07 does not send the field: one connection carries every joined bus, and
--- SignalR reports which invocation arrived but never which group it came from, so on such a
--- server a client holding two buses genuinely cannot tell their traffic apart.
local function route(first: { [string]: any }): { string }
	local named = BusWire.NormalizeBusKey(first.bus)
	if named ~= "" then
		return _joined[named] and { named } or {}
	end

	local matched = {}
	for key, isJoined in pairs(_joined) do
		if isJoined then
			table.insert(matched, key)
		end
	end

	if #matched > 1 and not _warnedAboutRouting then
		_warnedAboutRouting = true
		warn("[Praxsuite] This gateway sends bus messages without naming their bus, so events "
			.. "cannot be routed to the bus they came from. Every joined bus will see them. "
			.. "Update the gateway, or hold one bus per connection until you can.")
	end
	return matched
end

local function handleFrame(raw: string)
	local ok, message = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(message) ~= "table" then
		warn("[Praxsuite] Discarded an Event Bus frame that is not JSON.")
		return
	end

	if message.type == BusWire.MSG_PING then
		return -- keepalive; never surface it
	end

	if message.type == BusWire.MSG_COMPLETION then
		local invocationId = tostring(message.invocationId or "")
		if _pending[invocationId] ~= nil then
			_pending[invocationId] = BusWire.ParseBusResult(message)
		end
		return
	end

	if message.type == BusWire.MSG_INVOCATION then
		local args = message.arguments
		local first = (type(args) == "table" and type(args[1]) == "table") and args[1] or {}

		if message.target == "bus-event" then
			for _, key in ipairs(route(first)) do
				dispatch(key, tostring(first.event or ""), first.payload, tostring(first.fromUserId or ""))
			end
		elseif message.target == "peer-joined" or message.target == "peer-left" then
			local userId = tostring(first.userId or "")
			local isJoin = message.target == "peer-joined"
			for _, key in ipairs(route(first)) do
				local hooks = _presence[key]
				if hooks then
					for _, handler in ipairs(isJoin and hooks.joined or hooks.left) do
						pcall(handler, userId)
					end
				end
			end
		elseif message.target == "bus-evicted" then
			-- The topic was disabled or re-scoped while this connection held it. Membership is
			-- dropped and NOT re-joined: that would be arguing with a decision the server has
			-- just made.
			local key = BusWire.NormalizeBusKey(first.bus)
			_joined[key] = nil
			warn('[Praxsuite] Evicted from bus "' .. key .. '".')
		end
		return
	end

	if message.type == BusWire.MSG_CLOSE then
		warn("[Praxsuite] The hub closed the connection: " .. tostring(message.error or "no reason given"))
	end
end

local function pollLoop()
	if _polling then
		return
	end
	_polling = true

	task.spawn(function()
		while _connectionToken do
			local status, body = request("GET", BusWire.PollUrl(baseUrl(), _connectionToken))
			if status ~= 200 then
				warn("[Praxsuite] Event Bus poll failed (HTTP " .. status .. "); the connection is closed.")
				_connectionToken = nil
				for key in pairs(_joined) do
					_joined[key] = nil
				end
				break
			end

			local frames
			frames, _buffer = BusWire.SplitFrames(_buffer .. body)
			for _, frame in ipairs(frames) do
				handleFrame(frame)
			end
		end
		_polling = false
	end)
end

local function invoke(target: string, args: { any }): { [string]: any }
	if not _connectionToken then
		return { ok = false, error = "not_connected", peers = {}, recipients = 0, isTransportError = true }
	end

	_nextInvocation += 1
	local invocationId = tostring(_nextInvocation)
	_pending[invocationId] = false

	local frame = BusWire.Frame(HttpService:JSONEncode(BusWire.BuildInvocation(invocationId, target, args)))
	local status = request("POST", BusWire.PollUrl(baseUrl(), _connectionToken), frame)
	if status ~= 200 then
		_pending[invocationId] = nil
		return { ok = false, error = "send_failed", peers = {}, recipients = 0, isTransportError = true }
	end

	local deadline = os.clock() + CALL_TIMEOUT_SECONDS
	while _pending[invocationId] == false do
		if os.clock() > deadline or not _connectionToken then
			_pending[invocationId] = nil
			return { ok = false, error = "timeout", peers = {}, recipients = 0, isTransportError = true }
		end
		task.wait(0.05)
	end

	local result = _pending[invocationId]
	_pending[invocationId] = nil
	return result
end

--- Opens the connection for a player.
---
--- Pass a Player and the token comes from Auth.GetTokenFor, which reuses their cached session.
--- A raw end-user token is accepted too, for a caller that already holds one.
---
--- The server key is deliberately NOT accepted: an API key does not authenticate the hub, and
--- letting it through here would turn a 401 from the negotiate into the caller's problem.
---
--- Returns true, or false plus a message.
function Bus.Connect(playerOrToken: any): (boolean, string?)
	local accessToken: string? = nil

	if typeof(playerOrToken) == "Instance" and playerOrToken:IsA("Player") then
		local Auth = require(script.Parent.Auth)
		local ok, tokenOrError = pcall(Auth.GetTokenFor, playerOrToken)
		if not ok then
			return false, "Could not sign the player in for the Event Bus: " .. tostring(tokenOrError)
		end
		accessToken = tokenOrError
	elseif type(playerOrToken) == "string" and playerOrToken ~= "" then
		accessToken = playerOrToken
	end

	if not accessToken or accessToken == "" then
		return false,
			"The Event Bus needs a Player (or an end-user token). The server key does not "
				.. "authenticate the hub - a negotiate carrying x-api-key returns 401."
	end

	_accessToken = accessToken
	_buffer = ""

	local status, body = request("POST", BusWire.NegotiateUrl(baseUrl()), "")
	if status ~= 200 then
		return false, "The hub refused the negotiate (HTTP " .. status .. "). An expired or "
			.. "rejected token is the commonest cause."
	end

	local ok, negotiated = pcall(HttpService.JSONDecode, HttpService, body)
	if not ok or type(negotiated) ~= "table" or not negotiated.connectionToken then
		return false, "The hub's negotiate response carried no connectionToken."
	end

	_connectionToken = tostring(negotiated.connectionToken)

	-- The first GET is what actually establishes the long-polling connection; the handshake
	-- cannot be posted before it exists.
	request("GET", BusWire.PollUrl(baseUrl(), _connectionToken))
	request("POST", BusWire.PollUrl(baseUrl(), _connectionToken), BusWire.Frame(BusWire.HANDSHAKE_FRAME))

	local handshakeStatus, handshakeBody = request("GET", BusWire.PollUrl(baseUrl(), _connectionToken))
	if handshakeStatus ~= 200 then
		_connectionToken = nil
		return false, "The Event Bus handshake failed (HTTP " .. handshakeStatus .. ")."
	end

	local frames
	frames, _buffer = BusWire.SplitFrames(handshakeBody)
	for _, frame in ipairs(frames) do
		local decoded = select(2, pcall(HttpService.JSONDecode, HttpService, frame))
		if type(decoded) == "table" and decoded.error then
			_connectionToken = nil
			return false, "The hub rejected the handshake: " .. tostring(decoded.error)
		end
	end

	pollLoop()
	return true, nil
end

--- Closes the connection. Handlers are kept, so a later Connect resumes with them.
function Bus.Disconnect()
	if _connectionToken then
		request("DELETE", BusWire.PollUrl(baseUrl(), _connectionToken))
	end
	_connectionToken = nil
	for key in pairs(_joined) do
		_joined[key] = nil
	end
end

--- Joins a bus. Returns the peers already present, or nil plus a message.
---
--- A refused join returns an error worth checking: a publish that does not land is one dropped
--- frame, whereas a join that does not land leaves this client silently absent for the session.
---
--- The peers it returns are every peer's LAST retained message, which is what stops a late joiner
--- staring at an empty room until somebody moves.
function Bus.Join(busKey: string, ticket: string?): ({ any }?, string?)
	local key, invalid = BusWire.CheckBusKey(busKey)
	if not key then
		return nil, invalid
	end

	local result = invoke("JoinBus", { key, ticket })
	if not result.ok then
		return nil, 'Could not join "' .. key .. '": ' .. BusWire.DescribeError(result.error)
	end

	_joined[key] = true
	return result.peers, nil
end

--- Sends an event to every OTHER peer in the bus.
---
--- Returns { ok, error, recipients }. A refusal is NOT an error: dropping an ephemeral frame is
--- ordinary operation, and a loop that treats a rate limit as a failure is worse than one that
--- skips a frame. recipients = 0 means it went out and nobody was joined.
---
--- You will not receive your own event back. Apply your own change locally.
function Bus.Publish(busKey: string, eventName: string, payload: any): { [string]: any }
	local key, invalid = BusWire.CheckBusKey(busKey)
	if not key then
		return { ok = false, error = invalid, recipients = 0, peers = {}, isTransportError = false }
	end
	return invoke("Publish", { key, eventName, payload or {} })
end

--- Leaves a bus. Idempotent.
function Bus.Leave(busKey: string)
	local key = BusWire.NormalizeBusKey(busKey)
	_joined[key] = nil
	if _connectionToken then
		invoke("LeaveBus", { key })
	end
end

--- Subscribes to one event name on one bus. Pass "*" to receive every event on it.
--- The handler is called with (payload, fromUserId).
function Bus.On(busKey: string, eventName: string, handler: (any, string) -> ())
	local key = BusWire.NormalizeBusKey(busKey)
	_handlers[key] = _handlers[key] or {}
	_handlers[key][eventName] = _handlers[key][eventName] or {}
	table.insert(_handlers[key][eventName], handler)
end

--- Presence. Fires only when the topic has presence enabled.
function Bus.OnPeerJoined(busKey: string, handler: (string) -> ())
	local key = BusWire.NormalizeBusKey(busKey)
	_presence[key] = _presence[key] or { joined = {}, left = {} }
	table.insert(_presence[key].joined, handler)
end

function Bus.OnPeerLeft(busKey: string, handler: (string) -> ())
	local key = BusWire.NormalizeBusKey(busKey)
	_presence[key] = _presence[key] or { joined = {}, left = {} }
	table.insert(_presence[key].left, handler)
end

--- True while the connection is open.
function Bus.IsConnected(): boolean
	return _connectionToken ~= nil
end

return Bus
