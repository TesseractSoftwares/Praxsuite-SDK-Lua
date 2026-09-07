--[[
    BusWire - the Event Bus wire format: SignalR's JSON hub protocol, version 1.

    Everything here is pure: no HttpService, no yields, no state. That is deliberate, because it
    is the half that can be checked without a Roblox runtime, and it mirrors the shared SDK
    conformance contract's cases/event-bus.json case for case.

    The protocol is spoken directly. There is no SignalR client for Luau, and the surface used
    here is four message types wide.
]]

local BusWire = {}

--- ASCII record separator. SignalR terminates every frame with it.
BusWire.RS = "\30"

--- The handshake, byte for byte. SignalR compares it literally - a trailing newline or a space
--- after a colon fails it, with an error that does not say so.
BusWire.HANDSHAKE_FRAME = '{"protocol":"json","version":1}'

--- The hub's path. There is no workspace segment: the workspace comes from the token.
BusWire.BUS_PATH = "/hubs/event-bus"

BusWire.MSG_INVOCATION = 1
BusWire.MSG_COMPLETION = 3
BusWire.MSG_PING = 6
BusWire.MSG_CLOSE = 7

--- Splits a received buffer into whole frames.
---
--- Returns the frames and whatever trailing fragment was left unparsed.
---
--- Two things go wrong without this. One physical response can carry SEVERAL frames, so decoding
--- the whole body as JSON fails exactly when traffic picks up - the load the bus exists for. And
--- a poll may end mid-frame, so the tail is kept rather than decoded or discarded.
function BusWire.SplitFrames(buffer: string): ({ string }, string)
	local frames = {}
	if not buffer or buffer == "" then
		return frames, ""
	end

	local start = 1
	while true do
		local separator = string.find(buffer, BusWire.RS, start, true)
		if not separator then
			break
		end
		if separator > start then
			table.insert(frames, string.sub(buffer, start, separator - 1))
		end
		start = separator + 1
	end

	return frames, string.sub(buffer, start)
end

--- Wraps a frame for sending.
function BusWire.Frame(payload: string): string
	return payload .. BusWire.RS
end

--- Folds a bus key the way the server does: the TOPIC segment to lowercase, the instance
--- untouched.
---
--- BusAddress.ForCaller folds the topic both when it resolves the topic and when it builds the
--- SignalR group name, so "Office:hq" and "office:hq" are one bus. Folding the whole key instead
--- would merge "office:HQ" and "office:hq", which are two genuinely different buses. Fold the same
--- half the server folds and neither mistake is possible.
function BusWire.NormalizeBusKey(busKey: string?): string
	if not busKey then
		return ""
	end

	local key = string.gsub(busKey, "^%s*(.-)%s*$", "%1")
	if key == "" then
		return ""
	end

	local separator = string.find(key, ":", 1, true)
	if not separator or separator == 1 then
		return string.lower(key)
	end

	return string.lower(string.sub(key, 1, separator - 1)) .. string.sub(key, separator)
end

--- Rejects keys the server would reject anyway, without spending a round trip on it.
--- Returns the normalised key, or nil plus a message.
function BusWire.CheckBusKey(busKey: string?): (string?, string?)
	local key = BusWire.NormalizeBusKey(busKey)

	if key == "" then
		return nil, 'A bus key is required. It looks like "topic:instance", e.g. "office:hq".'
	end

	-- The group name is built by concatenation, so a key carrying the separator could climb out
	-- of its own segment and name another workspace's group.
	if string.find(key, "ws:", 1, true) then
		return nil, 'A bus key may not contain "ws:" (got "' .. tostring(busKey) .. '").'
	end

	if #key > 200 then
		return nil, "Bus key is too long (" .. #key .. " characters)."
	end

	return key, nil
end

--- Builds an invocation table. The caller encodes it; invocationId is a STRING, because SignalR
--- matches completions on it by value and a numeric id never matches.
function BusWire.BuildInvocation(invocationId: string, target: string, args: { any }): { [string]: any }
	return {
		type = BusWire.MSG_INVOCATION,
		invocationId = invocationId,
		target = target,
		arguments = args,
	}
end

--- Reads a completion frame into { ok, error, peers, recipients, isTransportError }.
---
--- The trap this exists for: the hub answers a REJECTED call with a SUCCESSFUL completion whose
--- result carries ok = false. Code that only inspects SignalR's own error field reports every
--- denied join as a success. And LeaveBus is void, so its result is literally null.
function BusWire.ParseBusResult(message: { [string]: any }?): { [string]: any }
	local parsed = {
		ok = true,
		error = nil :: string?,
		peers = {},
		recipients = 0,
		isTransportError = false,
	}

	if type(message) ~= "table" then
		return parsed
	end

	if type(message.error) == "string" and message.error ~= "" then
		parsed.ok = false
		parsed.error = message.error
		parsed.isTransportError = true
		return parsed
	end

	local result = message.result
	if type(result) ~= "table" then
		return parsed -- void, e.g. LeaveBus
	end

	parsed.ok = result.ok ~= false
	if type(result.error) == "string" then
		parsed.error = result.error
	end
	if type(result.recipients) == "number" then
		parsed.recipients = result.recipients
	end

	if type(result.peers) == "table" then
		for _, entry in ipairs(result.peers) do
			if type(entry) == "table" then
				table.insert(parsed.peers, {
					userId = tostring(entry.userId or ""),
					event = tostring(entry.event or ""),
					payload = entry.payload,
				})
			end
		end
	end

	return parsed
end

--- Negotiate: a zero-length POST carrying the end-user token.
function BusWire.NegotiateUrl(baseUrl: string): string
	return baseUrl .. BusWire.BUS_PATH .. "/negotiate?negotiateVersion=1"
end

--- The long-polling endpoint. GET receives, POST sends, DELETE closes.
---
--- Long polling rather than WebSockets is not a preference. Roblox's HttpService cannot open a
--- WebSocket at all, so this is the only transport available here - and the whole cycle was
--- measured working against the live hub on 2026-09-07 before a line of this was written.
function BusWire.PollUrl(baseUrl: string, connectionToken: string): string
	local escaped = string.gsub(connectionToken, "([^%w%-%.%_%~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
	return baseUrl .. BusWire.BUS_PATH .. "?id=" .. escaped
end

--- Turns a hub error code into a sentence worth reading. The codes are stable and are what
--- callers should branch on; these strings are not.
function BusWire.DescribeError(code: string?): string
	local descriptions = {
		unknown_topic = "That topic is not declared in this workspace. Buses are never auto-created "
			.. "- declare the topic under API Gateway / Event Bus first.",
		denied = "The topic refused this user. Check its access mode: Workspace, Roles (read "
			.. "straight from the JWT), or Grants (which needs a grant on this exact bus instance).",
		invalid_ticket = "The ticket was missing, expired, or minted for a different user, "
			.. "workspace or bus.",
		not_a_member = "Publish to a bus this connection has not joined. Join it first - membership "
			.. "is the authorization check on the publish path.",
		invalid_bus_key = 'The key is malformed, or it named another user\'s "user:" bus. Only '
			.. '"user:self" is addressable.',
		invalid_event_name = "The event name was empty or too long.",
		payload_too_large = "The payload is over this topic's byte limit.",
		bus_full_or_too_many_buses = "The bus is at its peer limit, or this connection already "
			.. "holds as many buses as it may.",
		rate_limited = "Too many publishes. The limit is priced by RECIPIENTS, so a large bus "
			.. "exhausts it faster than a small one.",
	}

	if not code or code == "" then
		return "The bus refused the call."
	end
	return descriptions[code] or code
end

return BusWire
