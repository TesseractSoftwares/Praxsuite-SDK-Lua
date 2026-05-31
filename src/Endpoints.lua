--[[
    Endpoints - Sync/Async endpoint calling module.
    Calls webhook receiver endpoints (sync or async mode).
]]

local Http = require(script.Parent.Core.Http)
local Config = require(script.Parent.Core.Config)
local Players = require(script.Parent.Players)

local Endpoints = {}

--- Call a sync endpoint and wait for the automation response.
--- The endpoint must be configured in Sync mode with a linked automation.
--- @param slug string - Endpoint slug (receiver ID or friendly name)
--- @param payload table? - JSON payload to send
--- @return any - The automation's Response node output (parsed)
---
--- Example:
---   local result = Praxsuite.Endpoints.Call("validate-purchase", {
---       player_id = player.UserId,
---       product_id = "sword_of_fire",
---       receipt = receiptInfo.PurchaseId
---   })
---   if result.approved then ... end
function Endpoints.Call(slug: string, payload: any?, options: {
    asPlayer: Player?,
    headers: { [string]: string }?,
    timeout: number?,
}?): any
    Config.AssertInitialized()
    local opts = options or {}

    if opts.asPlayer then
        Players.SetContext(opts.asPlayer)
    end

    local response = Http.Request(
        "POST",
        Config.GetUrl("endpoint/" .. slug),
        payload,
        opts.headers
    )

    if opts.asPlayer then
        Players.ClearContext()
    end

    return response.body
end

--- Fire an async endpoint (fire-and-forget).
--- Returns true if the request was accepted (2xx), does not wait for automation execution.
--- @param slug string - Endpoint slug
--- @param payload table? - JSON payload to send
--- @return boolean - true if accepted
---
--- Example:
---   Praxsuite.Endpoints.Fire("on-player-leave", {
---       player_id = player.UserId,
---       play_duration = os.time() - joinTime
---   })
function Endpoints.Fire(slug: string, payload: any?, options: {
    asPlayer: Player?,
    headers: { [string]: string }?,
}?): boolean
    Config.AssertInitialized()
    local opts = options or {}

    if opts.asPlayer then
        Players.SetContext(opts.asPlayer)
    end

    local ok, response = pcall(Http.Request, "POST", Config.GetUrl("endpoint/" .. slug), payload, opts.headers)

    if opts.asPlayer then
        Players.ClearContext()
    end

    if not ok then
        -- Fire-and-forget: log warning but don't error
        warn("[PraxsuiteSDK] Endpoints.Fire failed for '" .. slug .. "': " .. tostring(response))
        return false
    end

    return response.ok
end

--- Call an endpoint via the legacy /webhook/ path.
--- Identical behavior to Call() but uses the webhook route.
--- @param receiverId string - Webhook receiver UUID
--- @param payload table? - JSON payload
--- @return any - Response body
function Endpoints.Webhook(receiverId: string, payload: any?, options: {
    asPlayer: Player?,
    headers: { [string]: string }?,
}?): any
    Config.AssertInitialized()
    local opts = options or {}

    if opts.asPlayer then
        Players.SetContext(opts.asPlayer)
    end

    local response = Http.Request(
        "POST",
        Config.GetUrl("webhook/" .. receiverId),
        payload,
        opts.headers
    )

    if opts.asPlayer then
        Players.ClearContext()
    end

    return response.body
end

return Endpoints
