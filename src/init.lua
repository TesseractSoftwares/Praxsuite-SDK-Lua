--[[
    PraxsuiteSDK - Main Entry Point
    Praxsuite SDK for Lua-based game engines.
    
    Usage (Roblox):
        local Praxsuite = require(game.ServerScriptService.PraxsuiteSDK)
        Praxsuite.Init({ workspaceId = "...", apiKeySecret = "PraxKey" })
        
        local rows = Praxsuite.Data.Query("players", { where = { level = { gt = 5 } } })
        Praxsuite.Data.Insert("events", { player_id = 123, event = "login" })
        local result = Praxsuite.Endpoints.Call("validate-purchase", { item = "sword" })
]]

local Config = require(script.Core.Config)
local Http = require(script.Core.Http)
local Data = require(script.Data)
local Endpoints = require(script.Endpoints)
local Players = require(script.Players)
local Schema = require(script.Schema)

local Praxsuite = {}

--- Initialize the SDK. Must be called once before any other method.
--- @param options table { workspaceId: string, apiKeySecret: string, baseUrl?: string }
function Praxsuite.Init(options: {
    workspaceId: string,
    apiKeySecret: string,
    baseUrl: string?,
    autoFetchSchema: boolean?,
    retryEnabled: boolean?,
    maxRetries: number?,
    timeout: number?,
})
    assert(options.workspaceId, "[PraxsuiteSDK] workspaceId is required")
    assert(options.apiKeySecret, "[PraxsuiteSDK] apiKeySecret is required")

    Config._workspaceId = options.workspaceId
    Config._apiKeySecret = options.apiKeySecret
    Config._baseUrl = options.baseUrl or "https://gateway.praxsuite.com"
    Config._retryEnabled = if options.retryEnabled ~= nil then options.retryEnabled else true
    Config._maxRetries = options.maxRetries or 3
    Config._timeout = options.timeout or 30
    Config._initialized = true

    -- Auto-fetch schema to resolve table names → UUIDs
    if options.autoFetchSchema ~= false then
        local ok, err = pcall(function()
            Schema.Fetch()
        end)
        if not ok then
            warn("[PraxsuiteSDK] Failed to fetch schema on init: " .. tostring(err))
            warn("[PraxsuiteSDK] You can register tables manually with Praxsuite.Schema.Register(name, uuid)")
        end
    end
end

--- Check if SDK has been initialized.
function Praxsuite.IsInitialized(): boolean
    return Config._initialized
end

--- Access submodules
Praxsuite.Data = Data
Praxsuite.Endpoints = Endpoints
Praxsuite.Players = Players
Praxsuite.Schema = Schema
Praxsuite.Config = Config

return Praxsuite
