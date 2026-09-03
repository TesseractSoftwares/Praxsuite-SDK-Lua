--[[
    Http - Transport layer.
    Handles HTTP requests with retry logic and error handling.
    Automatically adapts to the runtime environment (Roblox, FiveM, generic).
]]

local Config = require(script.Parent.Config)

local Http = {}

-- Detect runtime and get appropriate services
local HttpService = game:GetService("HttpService")

-- ─── Optimization: cache the resolved API key (secrets don't change at runtime) ──
local _cachedApiKey: string? = nil

local function getApiKey(): string
	if _cachedApiKey then
		return _cachedApiKey
	end

	-- If a raw API key was provided (Studio testing), use it directly
	if Config._apiKey then
		_cachedApiKey = Config._apiKey
		return _cachedApiKey
	end

	-- Otherwise, resolve from Roblox Secrets Store (published game servers)
	_cachedApiKey = HttpService:GetSecret(Config._apiKeySecret)
	return _cachedApiKey
end

--- Internal: Build default headers for every request.
--- Reuses cached API key — zero repeated Secret Store lookups.
---
--- With an authToken (a player's session from Auth.LoginPlayer) the request goes out AS THAT
--- PLAYER and the server key is left out entirely. That is not a style choice: the gateway
--- reads one token per request, so sending both would just mean one of them is ignored — and
--- the whole point of a player session is that the request carries the player's own scopes and
--- row filters instead of the server key's.
local function buildHeaders(authToken: string?): { [string]: string }
	if authToken then
		return {
			["Content-Type"] = "application/json",
			["Authorization"] = "Bearer " .. authToken,
		}
	end

	local headers = {
		["Content-Type"] = "application/json",
		["x-api-key"] = getApiKey(),
	}

	return headers
end

--- Internal: Parse JSON response body.
local function parseBody(body: string): any
    if not body or body == "" then
        return nil
    end
    local ok, result = pcall(HttpService.JSONDecode, HttpService, body)
    if ok then
        return result
    end
    return body
end

--- Internal: Determine if a status code is retryable.
local function isRetryable(status: number): boolean
    return status == 429 or status >= 500
end

--- Internal: Calculate delay for exponential backoff.
local function getBackoffDelay(attempt: number): number
    local base = 1
    local delay = base * (2 ^ (attempt - 1))
    -- Add jitter (±25%)
    local jitter = delay * 0.25 * (math.random() * 2 - 1)
    return math.min(delay + jitter, 30)
end

export type HttpResponse = {
    status: number,
    body: any,
    headers: { [string]: string }?,
    ok: boolean,
}

export type HttpError = {
    code: string,
    message: string,
    status: number,
    details: any?,
}

--- Make an HTTP request with automatic retry on transient failures.
--- @param authToken string? - a player's session token; sent instead of the server key.
function Http.Request(method: string, url: string, body: any?, extraHeaders: { [string]: string }?, authToken: string?): HttpResponse
    Config.AssertInitialized()

    local headers = buildHeaders(authToken)
    if extraHeaders then
        for k, v in pairs(extraHeaders) do
            headers[k] = v
        end
    end

    local requestBody = nil
    if body ~= nil then
        requestBody = HttpService:JSONEncode(body)
    end

    -- Which credential this request rides on, in the words a human reads: not which header
    -- (that's an implementation detail this log intentionally hides), but who is asking.
    local asWhom = if authToken
        then "player session (" .. Config.MaskSecret(authToken) .. ")"
        else "server key (" .. Config.MaskSecret(Config._apiKey or Config._apiKeySecret) .. ")"
    Config.Log("[Http] -> %s %s  as %s", method, url, asWhom)

    local lastError = nil
    local maxAttempts = if Config._retryEnabled then Config._maxRetries + 1 else 1

    for attempt = 1, maxAttempts do
        local success, response = pcall(HttpService.RequestAsync, HttpService, {
            Url = url,
            Method = method,
            Headers = headers,
            Body = requestBody,
        })

        if success then
            local parsed = parseBody(response.Body)

            if response.Success then
                Config.Log("[Http] <- %d %s", response.StatusCode, url)
                return {
                    status = response.StatusCode,
                    body = parsed,
                    headers = response.Headers,
                    ok = true,
                }
            end

            -- Non-success status
            if isRetryable(response.StatusCode) and attempt < maxAttempts then
                local delay = getBackoffDelay(attempt)
                Config.Log("[Http] <- %d %s  retrying in %.1fs (attempt %d/%d)",
                    response.StatusCode, url, delay, attempt, maxAttempts)
                task.wait(delay)
                lastError = {
                    code = "HTTP_" .. tostring(response.StatusCode),
                    message = if typeof(parsed) == "table" and parsed.message
                        then parsed.message
                        else response.StatusMessage or "Request failed",
                    status = response.StatusCode,
                    details = parsed,
                }
            else
                -- Non-retryable or exhausted retries
                local code = if typeof(parsed) == "table" and parsed.code
                    then parsed.code
                    else "HTTP_" .. tostring(response.StatusCode)
                local msg = if typeof(parsed) == "table" and parsed.message
                    then parsed.message
                    else response.StatusMessage or "Request failed"
                local detail = ""
                if typeof(parsed) == "table" then
                    local ok2, json = pcall(HttpService.JSONEncode, HttpService, parsed)
                    if ok2 then detail = " | " .. json end
                elseif typeof(parsed) == "string" then
                    detail = " | " .. parsed
                end
                Config.Log("[Http] <- %d %s  %s", response.StatusCode, url, code)
                error("[PraxsuiteSDK] " .. code .. ": " .. msg .. detail)
            end
        else
            -- pcall failed (network error, timeout, etc.)
            if attempt < maxAttempts then
                local delay = getBackoffDelay(attempt)
                Config.Log("[Http] xx %s  network error, retrying in %.1fs (attempt %d/%d): %s",
                    url, delay, attempt, maxAttempts, tostring(response))
                task.wait(delay)
                lastError = {
                    code = "NETWORK_ERROR",
                    message = tostring(response),
                    status = 0,
                }
            else
                Config.Log("[Http] xx %s  network error, giving up: %s", url, tostring(response))
                error("[PraxsuiteSDK] NETWORK_ERROR: " .. tostring(response))
            end
        end
    end

    -- Should not reach here, but just in case
    error("[PraxsuiteSDK] UNKNOWN: Request failed after all retries")
end

--- Shorthand POST request.
--- @param authToken string? - a player's session token; sent instead of the server key.
function Http.Post(path: string, body: any?, authToken: string?): HttpResponse
    return Http.Request("POST", Config.GetUrl(path), body, nil, authToken)
end

--- Shorthand GET request.
--- @param authToken string? - a player's session token; sent instead of the server key.
function Http.Get(path: string, authToken: string?): HttpResponse
    return Http.Request("GET", Config.GetUrl(path), nil, nil, authToken)
end

return Http
