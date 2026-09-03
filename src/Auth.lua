--[[
    Auth - Per-player sessions, without a login screen.

    A Roblox experience has no browser, so a player cannot complete an OAuth redirect and
    cannot be asked for a password without you building the whole form yourself. What it does
    have is a server you control: your ServerScript reads `player.UserId`, which the player
    cannot tamper with, and tells Praxsuite "this session belongs to that player". Praxsuite
    creates the account the first time and returns a token scoped to it.

    So: `Auth.LoginPlayer(player)` on PlayerAdded and that is the whole sign-in.

    WHAT IS BEING TRUSTED. Your server key, not the player. Anyone holding the key can claim to
    be any player, which is why the gateway refuses this call from a publishable key and why the
    key belongs in the Roblox Secrets Store (`apiKeySecret`) and never in a LocalScript. Sessions
    minted this way are marked "server asserted": enough to be an account and carry roles, and
    deliberately less than a player who completed the platform's own OAuth from a browser.

    Example:
        local Praxsuite = require(game.ServerScriptService.PraxsuiteSDK)

        game.Players.PlayerAdded:Connect(function(player)
            Praxsuite.Auth.LoginPlayer(player)
        end)

        game.Players.PlayerRemoving:Connect(function(player)
            Praxsuite.Auth.Forget(player)
        end)

    And then, anywhere:
        Praxsuite.Data.Query("saves", { where = { level = { gt = 5 } } }, { asPlayer = player })

    The player's own token goes with that request, so a row filter on the table (`__SELF__`, or
    an Enduser column compared against the session) returns their rows and nobody else's —
    without your game having to filter by UserId and without trusting it to.
]]

local Config = require(script.Parent.Core.Config)

local Auth = {}

export type PlayerSession = {
	accessToken: string,
	refreshToken: string?,
	endUserId: string,
	expiresAt: number, -- os.time() seconds
}

-- Sessions live per UserId, in server memory only. A server restart re-logs everyone on join,
-- which costs one request and is simpler than persisting tokens anywhere.
local _sessions: { [number]: PlayerSession } = {}

-- Renew this long before the token actually expires, so a request never leaves with a token
-- that dies in flight.
local REFRESH_MARGIN_SECONDS = 60

-- Used when the response carries no usable expiry. Deliberately short: a gateway access token
-- lives 15 minutes by default, so guessing generously would mean caching a dead token and
-- failing every request until it was re-issued. Re-logging in too often costs one request.
local FALLBACK_LIFETIME_SECONDS = 300

--- Internal: when the access token dies, as epoch seconds.
--- The gateway reports "accessTokenExpiresAt" as an ISO 8601 instant, not a duration.
local function absoluteExpiry(payload: any): number
	local iso = payload.accessTokenExpiresAt
	if typeof(iso) == "string" then
		local ok, parsed = pcall(DateTime.fromIsoDate, iso)
		if ok and parsed then
			return parsed.UnixTimestamp
		end
	end

	-- Tolerated for forward compatibility, in case the field is ever reported as a duration.
	local seconds = tonumber(payload.expiresIn)
	if seconds then
		return os.time() + seconds
	end

	warn("[PraxsuiteSDK] No token expiry in the auth response; assuming "
		.. tostring(FALLBACK_LIFETIME_SECONDS) .. "s.")
	return os.time() + FALLBACK_LIFETIME_SECONDS
end

--- Internal: the provider slug this game asserts against. Defaults to "roblox", which is what
--- the provider is called in a workspace that registered it from the portal.
local function providerSlug(): string
	return Config._authProvider or "roblox"
end

--- Signs a player in and caches their session. Safe to call again: an existing, unexpired
--- session is returned as-is rather than opening a second one.
--- @param player Player - the Roblox Player instance
--- @param options table? - { displayName?: string, metadata?: table, force?: boolean }
--- @return PlayerSession
function Auth.LoginPlayer(player: Player, options: {
	displayName: string?,
	metadata: { [string]: any }?,
	force: boolean?,
}?): PlayerSession
	Config.AssertInitialized()
	local opts = options or {}

	local existing = _sessions[player.UserId]
	if existing and not opts.force and existing.expiresAt - REFRESH_MARGIN_SECONDS > os.time() then
		Config.Log("[Auth] %s (%d): cached session, %ds left — no request made",
			player.Name, player.UserId, existing.expiresAt - os.time())
		return existing
	end

	Config.Log("[Auth] %s (%d): %s — asserting against provider '%s'",
		player.Name, player.UserId,
		if existing then "session expired or forced" else "no session yet",
		providerSlug())

	local Http = require(script.Parent.Core.Http)

	local response = Http.Post("auth/" .. providerSlug() .. "/assert", {
		platformPlayerId = tostring(player.UserId),
		displayName = opts.displayName or player.DisplayName,
		metadata = opts.metadata,
	})

	-- The gateway wraps successful payloads; both shapes are accepted so a change in the
	-- envelope does not silently produce a session with no token.
	local payload = response.body
	if typeof(payload) == "table" and payload.data ~= nil then
		payload = payload.data
	end

	if typeof(payload) ~= "table" or not payload.accessToken then
		error("[PraxsuiteSDK] AUTH_FAILED: no access token in the response for player "
			.. tostring(player.UserId))
	end

	local session: PlayerSession = {
		accessToken = payload.accessToken,
		refreshToken = payload.refreshToken,
		endUserId = payload.endUserId or (typeof(payload.user) == "table" and payload.user.id) or "",
		expiresAt = absoluteExpiry(payload),
	}

	_sessions[player.UserId] = session
	Config.Log("[Auth] %s (%d): session opened — account %s, expires in %ds",
		player.Name, player.UserId, session.endUserId, session.expiresAt - os.time())
	return session
end

--- The cached session for a player, or nil if they have none (or it expired).
function Auth.GetSession(player: Player): PlayerSession?
	local session = _sessions[player.UserId]
	if not session then
		return nil
	end
	if session.expiresAt - REFRESH_MARGIN_SECONDS <= os.time() then
		return nil
	end
	return session
end

--- The access token for a player, signing them in if needed. This is what the data modules
--- call, so `{ asPlayer = player }` works whether or not you called LoginPlayer yourself.
function Auth.GetTokenFor(player: Player): string
	local session = Auth.GetSession(player)
	if session then
		return session.accessToken
	end
	return Auth.LoginPlayer(player, { force = true }).accessToken
end

--- Drops a player's cached session. Call on PlayerRemoving: nothing breaks if you forget, but
--- the table would keep every player the server has ever seen.
function Auth.Forget(player: Player)
	if _sessions[player.UserId] then
		Config.Log("[Auth] %s (%d): session forgotten", player.Name, player.UserId)
	end
	_sessions[player.UserId] = nil
end

--- Drops every cached session. For tests, and for a server that wants to force a re-login.
function Auth.ForgetAll()
	_sessions = {}
end

return Auth
