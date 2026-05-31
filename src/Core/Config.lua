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

--- Assert that Init() has been called.
function Config.AssertInitialized()
    assert(Config._initialized, "[PraxsuiteSDK] Not initialized. Call Praxsuite.Init() first.")
end

--- Get the full API path for a gateway route.
function Config.GetUrl(path: string): string
    return Config._baseUrl .. "/api/v1/gateway/" .. Config._workspaceId .. "/" .. path
end

--- Resolve a table name to its UUID from the registry.
function Config.ResolveTable(tableName: string): string
    local uuid = Config._tableRegistry[tableName]
    if not uuid then
        error(
            "[PraxsuiteSDK] Table '" .. tableName .. "' not found in registry. "
            .. "Either enable autoFetchSchema or call Praxsuite.Schema.Register('" .. tableName .. "', 'uuid')"
        )
    end
    return uuid
end

return Config
