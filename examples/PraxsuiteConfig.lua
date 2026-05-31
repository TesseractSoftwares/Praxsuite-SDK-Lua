--[[
    PraxsuiteConfig - Drop this ModuleScript into ServerScriptService.
    
    The SDK auto-discovers this file. You never need to call Init() manually.
    Just require the SDK from any script and start using it immediately.
    
    Instructions:
    1. Place this ModuleScript at: game.ServerScriptService.PraxsuiteConfig
    2. Set your workspace ID (from Praxsuite dashboard → Settings → API Gateway)
    3. Store your API key in Roblox Secrets Store as "PraxsuiteKey"
       (Game Settings → Security → Secrets → Add Secret)
    4. Done! Every script that requires the SDK will work automatically.
]]

return {
    -- REQUIRED: Your workspace ID (UUID from Praxsuite dashboard)
    workspaceId = "YOUR_WORKSPACE_UUID_HERE",

    -- REQUIRED: Name of the secret in Roblox Secrets Store containing your API key
    -- The actual key value (sk_live_...) is stored securely in Roblox, not here.
    apiKeySecret = "PraxsuiteKey",

    -- OPTIONAL: Override the gateway URL (default: https://gateway.praxsuite.com)
    -- baseUrl = "https://gateway.praxsuite.com",

    -- OPTIONAL: Auto-fetch table schema on init (default: true)
    -- Set to false if you want to register tables manually for faster cold starts.
    -- autoFetchSchema = true,

    -- OPTIONAL: Retry configuration
    -- retryEnabled = true,  -- Retry on 429/5xx (default: true)
    -- maxRetries = 3,       -- Max retry attempts (default: 3)
    -- timeout = 30,         -- Request timeout in seconds (default: 30)
}
