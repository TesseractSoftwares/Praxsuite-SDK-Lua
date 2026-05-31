--[[
    PraxsuiteSDK - Main Entry Point
    Praxsuite SDK for Lua-based game engines.
    
    The SDK is a SINGLETON — call Init() once, then require() it from any script.
    
    === Option 1: Explicit Init (one script, one time) ===
    
        -- ServerScriptService/Boot.server.lua (runs once)
        local Praxsuite = require(game.ServerScriptService.PraxsuiteSDK)
        Praxsuite.Init({ workspaceId = "...", apiKeySecret = "PraxKey" })
    
        -- Any other script (already initialized, just use it):
        local Praxsuite = require(game.ServerScriptService.PraxsuiteSDK)
        Praxsuite.Data.Query("players", { where = { level = { gt = 5 } } })
    
    === Option 2: Zero-code config (drop a ModuleScript, never call Init) ===
    
        Create: ServerScriptService/PraxsuiteConfig (ModuleScript)
        Contents:
            return {
                workspaceId = "your-workspace-uuid",
                apiKeySecret = "PraxsuiteKey",  -- name in Roblox Secrets Store
            }
    
        Then ANY script just does:
            local Praxsuite = require(game.ServerScriptService.PraxsuiteSDK)
            Praxsuite.Data.Query("players", { ... })  -- auto-inits on first call!
]]

local Config = require(script.Core.Config)
local Http = require(script.Core.Http)
local Data = require(script.Data)
local Endpoints = require(script.Endpoints)
local Players = require(script.Players)
local Schema = require(script.Schema)

local Praxsuite = {}

-- ─── Auto-Discovery ──────────────────────────────────────────────────────────
-- Finds a PraxsuiteConfig ModuleScript automatically so devs never call Init().
local _autoInitAttempted = false

local function tryAutoInit()
	if Config._initialized or _autoInitAttempted then
		return
	end
	_autoInitAttempted = true

	local searchPaths = {
		game:GetService("ServerScriptService"):FindFirstChild("PraxsuiteConfig"),
		game:GetService("ServerStorage"):FindFirstChild("PraxsuiteConfig"),
		script:FindFirstChild("PraxsuiteConfig"),
	}

	for _, configModule in ipairs(searchPaths) do
		if configModule and configModule:IsA("ModuleScript") then
			local ok, cfg = pcall(require, configModule)
			if ok and type(cfg) == "table" and cfg.workspaceId then
				Praxsuite.Init(cfg)
				return
			end
		end
	end
end

-- ─── Internal: ensure SDK is ready before any operation ──────────────────────
function Praxsuite._ensureReady()
	if not Config._initialized then
		tryAutoInit()
	end
	Config.AssertInitialized()
end

-- Wire auto-init into Config so any module calling Config.AssertInitialized()
-- will attempt auto-discovery before throwing.
Config._autoInitFn = tryAutoInit

-- ─── Public API ──────────────────────────────────────────────────────────────

--- Initialize the SDK. Call once in a boot script — all other scripts share
--- this instance automatically via require() (Lua caches modules).
--- If you use PraxsuiteConfig module, you don't need to call this at all.
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

	-- Auto-fetch schema in background (non-blocking — doesn't delay game start)
	if options.autoFetchSchema ~= false then
		task.spawn(function()
			local ok, err = pcall(function()
				Schema.Fetch()
			end)
			if not ok then
				warn("[PraxsuiteSDK] Failed to fetch schema on init: " .. tostring(err))
				warn("[PraxsuiteSDK] Register tables manually with Praxsuite.Schema.Register(name, uuid)")
			end
		end)
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
