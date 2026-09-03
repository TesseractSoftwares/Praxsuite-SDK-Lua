--[[
    Config - Internal configuration store.
    Set by Praxsuite.Init(), read by all other modules.
    Game developers do not interact with this directly.
]]

local Config = {}

-- Internal state (set during Init)
Config._workspaceId = nil :: string?
Config._apiKeySecret = nil :: string?
Config._apiKey = nil :: string?  -- Raw API key (for Studio testing; bypasses Secrets Store)
-- Praxsuite runs several independent tiers and a workspace exists on exactly one. The wrong
-- host returns 404, not a diagnosable error, so Init() requires this explicitly rather than
-- defaulting a dedicated-tier workspace onto the cloud host.
Config._baseUrl = nil :: string?
Config._retryEnabled = true
Config._maxRetries = 3
Config._timeout = 30
Config._initialized = false

-- Which registered provider Auth.LoginPlayer asserts against. "roblox" is what the provider is
-- called in a workspace that added it from the portal; override only if yours uses another slug.
Config._authProvider = "roblox"

-- When true, Http/Auth/Data narrate every request and every session decision to the output —
-- what URL, which credential (server key or a specific player's token, always masked), the
-- status that came back. Off by default: a shipped game should not spam its own console. Turn
-- it on with Init({ debug = true }) while you are learning the SDK or diagnosing a workspace.
Config._debug = false

-- Table registry: maps table names → UUIDs
Config._tableRegistry = {} :: { [string]: string }

-- Auto-init callback (set by init.lua to enable auto-discovery)
Config._autoInitFn = nil :: (() -> ())?

--- Assert that Init() has been called. Fast path: single boolean check.
--- Slow path (first call only): attempts auto-init from PraxsuiteConfig.
function Config.AssertInitialized()
	if Config._initialized then
		return -- Fast path: 1 table lookup, 1 branch. Zero allocations.
	end

	-- Slow path: only runs once (auto-init sets _initialized = true)
	if Config._autoInitFn then
		Config._autoInitFn()
	end

	if not Config._initialized then
		error(
			"[PraxsuiteSDK] Not initialized. Either:\n"
			.. "  1. Call Praxsuite.Init({ workspaceId = '...', apiKeySecret = '...' }) once, OR\n"
			.. "  2. Create a 'PraxsuiteConfig' ModuleScript in ServerScriptService returning your config."
		)
	end
end

-- Cached URL prefix (computed once on Init, avoids repeated string concat)
Config._urlPrefix = nil :: string?

--- Get the full API path for a gateway route. Uses cached prefix.
function Config.GetUrl(path: string): string
	if not Config._urlPrefix then
		Config._urlPrefix = Config._baseUrl .. "/api/v1/gateway/" .. Config._workspaceId .. "/"
	end
	return Config._urlPrefix .. path
end

--- Internal: prints when debug mode is on, and only then. Every call site prefixes its own tag
--- ([Http], [Auth], [Data]) so a busy log stays scannable.
function Config.Log(fmt: string, ...: any)
	if Config._debug then
		print("[PraxsuiteSDK]" .. string.format(fmt, ...))
	end
end

--- Internal: the last N characters of a secret, never the secret itself. Used to show that two
--- log lines are talking about the same credential without ever printing one whole.
function Config.MaskSecret(secret: string?): string
	if not secret or #secret == 0 then
		return "<none>"
	end
	if #secret <= 12 then
		return string.rep("*", #secret)
	end
	return secret:sub(1, 8) .. "…" .. secret:sub(-4) .. " (" .. #secret .. " chars)"
end

--- Resolve a table name to its UUID from the registry.
--- If schema is still loading (async), waits briefly (up to 5s) before erroring.
function Config.ResolveTable(tableName: string): string
	local uuid = Config._tableRegistry[tableName]
	if uuid then
		return uuid -- Fast path: direct lookup
	end

	-- Schema might still be loading (async fetch). Wait briefly.
	local waited = 0
	while waited < 5 do
		task.wait(0.1)
		waited += 0.1
		uuid = Config._tableRegistry[tableName]
		if uuid then
			return uuid
		end
		-- If registry has ANY entries but not ours, schema loaded — table doesn't exist
		if next(Config._tableRegistry) then
			break
		end
	end

	error(
		"[PraxsuiteSDK] Table '" .. tableName .. "' not found in registry. "
		.. "Either enable autoFetchSchema or call Praxsuite.Schema.Register('" .. tableName .. "', 'uuid')"
	)
end

return Config
