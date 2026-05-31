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
	_cachedApiKey = HttpService:GetSecret(Config._apiKeySecret)
	return _cachedApiKey
end

--- Internal: Build default headers for every request.
--- Reuses cached API key — zero repeated Secret Store lookups.
local function buildHeaders(): { [string]: string }
	local headers = {
		["Content-Type"] = "application/json",
		["x-api-key"] = getApiKey(),
	}

	-- Inject player identity headers if context is set
	if Config._currentPlayerPlatform then
		headers["x-player-platform"] = Config._currentPlayerPlatform
		headers["x-player-id"] = Config._currentPlayerId
	end

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
function Http.Request(method: string, url: string, body: any?, extraHeaders: { [string]: string }?): HttpResponse
    Config.AssertInitialized()

    local headers = buildHeaders()
    if extraHeaders then
        for k, v in pairs(extraHeaders) do
            headers[k] = v
        end
    end

    local requestBody = nil
    if body ~= nil then
        requestBody = HttpService:JSONEncode(body)
    end

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
                error({
                    code = if typeof(parsed) == "table" and parsed.code
                        then parsed.code
                        else "HTTP_" .. tostring(response.StatusCode),
                    message = if typeof(parsed) == "table" and parsed.message
                        then parsed.message
                        else response.StatusMessage or "Request failed",
                    status = response.StatusCode,
                    details = parsed,
                })
            end
        else
            -- pcall failed (network error, timeout, etc.)
            if attempt < maxAttempts then
                local delay = getBackoffDelay(attempt)
                task.wait(delay)
                lastError = {
                    code = "NETWORK_ERROR",
                    message = tostring(response),
                    status = 0,
                }
            else
                error({
                    code = "NETWORK_ERROR",
                    message = tostring(response),
                    status = 0,
                })
            end
        end
    end

    -- Should not reach here, but just in case
    error(lastError or { code = "UNKNOWN", message = "Request failed", status = 0 })
end

--- Shorthand POST request.
function Http.Post(path: string, body: any?): HttpResponse
    return Http.Request("POST", Config.GetUrl(path), body)
end

--- Shorthand GET request.
function Http.Get(path: string): HttpResponse
    return Http.Request("GET", Config.GetUrl(path))
end

return Http
