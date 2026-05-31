--[[
    Config - Internal configuration store.
    Set by Praxsuite.Init(), read by all other modules.
    Game developers do not interact with this directly.
]]

local Config = {}

-- Internal state (set during Init)
Config._workspaceId = nil :: string?
Config._apiKeySecret = nil :: string?
Config._baseUrl = "https://gateway.praxsuite.com"
Config._retryEnabled = true
Config._maxRetries = 3
Config._timeout = 30
Config._initialized = false

-- Table registry: maps table names → UUIDs
Config._tableRegistry = {} :: { [string]: string }

-- Player context (set per-request by Players module)
Config._currentPlayerPlatform = nil :: string?
Config._currentPlayerId = nil :: string?

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
