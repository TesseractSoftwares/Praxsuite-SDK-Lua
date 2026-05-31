<#
.SYNOPSIS
    Local development test for the Gaming Module + SDK endpoints.
    Verifies the player identity API works against a running Backend-Core.

.DESCRIPTION
    Prerequisites:
    1. Backend-Core running locally (port 5218)
    2. Migration-Gaming-Module.sql applied to a workspace DB
    3. A valid API key (sk_live_... or pk_live_...) for that workspace

.EXAMPLE
    .\test-gaming-module-local.ps1 -WorkspaceId "your-workspace-uuid" -ApiKey "sk_live_yourkey"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$BaseUrl = "http://localhost:5218",

    [Parameter(Mandatory = $false)]
    [string]$WorkspaceId = "",

    [Parameter(Mandatory = $false)]
    [string]$ApiKey = ""
)

$ErrorActionPreference = "Stop"

# ─── Colors ───────────────────────────────────────────────────────────────────
function Write-Pass($msg) { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  ✗ $msg" -ForegroundColor Red }
function Write-Info($msg) { Write-Host "  → $msg" -ForegroundColor Cyan }
function Write-Section($msg) { Write-Host "`n━━━ $msg ━━━" -ForegroundColor Yellow }

# ─── Prompt for missing params ────────────────────────────────────────────────
if (-not $WorkspaceId) {
    $WorkspaceId = Read-Host "Enter WorkspaceId (UUID)"
}
if (-not $ApiKey) {
    $ApiKey = Read-Host "Enter API Key (sk_live_... or pk_live_...)"
}

$headers = @{
    "Content-Type" = "application/json"
    "x-api-key"   = $ApiKey
}

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║   Praxsuite Gaming Module - Local Dev Test       ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""
Write-Info "Backend: $BaseUrl"
Write-Info "Workspace: $WorkspaceId"
Write-Info "API Key: $($ApiKey.Substring(0, [Math]::Min(12, $ApiKey.Length)))..."

# ─── Test 1: Identify a Player ────────────────────────────────────────────────
Write-Section "TEST 1: POST /players/identify"

$identifyBody = @{
    platform        = "roblox"
    platformPlayerId = "1516563360"
    displayName     = "TestPlayer_SDK"
    metadata        = @{
        accountAge = 365
        premium    = $true
        source     = "local-dev-test"
    }
} | ConvertTo-Json -Depth 5

try {
    $response = Invoke-RestMethod `
        -Uri "$BaseUrl/api/v1/gateway/$WorkspaceId/players/identify" `
        -Method POST `
        -Headers $headers `
        -Body $identifyBody `
        -ContentType "application/json"

    Write-Pass "Player identified successfully"
    Write-Info "ID: $($response.id)"
    Write-Info "Platform: $($response.platform)"
    Write-Info "PlayerId: $($response.platformPlayerId)"
    Write-Info "DisplayName: $($response.displayName)"
    Write-Info "Validated: $($response.isValidated)"

    $linkId = $response.id
}
catch {
    Write-Fail "Identify failed: $($_.Exception.Message)"
    if ($_.ErrorDetails.Message) {
        Write-Fail "Details: $($_.ErrorDetails.Message)"
    }
    $linkId = $null
}

# ─── Test 2: Resolve Player ──────────────────────────────────────────────────
Write-Section "TEST 2: GET /players/resolve/roblox/1516563360"

try {
    $response = Invoke-RestMethod `
        -Uri "$BaseUrl/api/v1/gateway/$WorkspaceId/players/resolve/roblox/1516563360" `
        -Method GET `
        -Headers $headers

    Write-Pass "Player resolved successfully"
    Write-Info "ID: $($response.id)"
    Write-Info "ContactId: $($response.contactId ?? 'null (not linked)')"
    Write-Info "FirstSeen: $($response.firstSeenAt)"
    Write-Info "LastSeen: $($response.lastSeenAt)"
}
catch {
    Write-Fail "Resolve failed: $($_.Exception.Message)"
    if ($_.ErrorDetails.Message) {
        Write-Fail "Details: $($_.ErrorDetails.Message)"
    }
}

# ─── Test 3: List Players ────────────────────────────────────────────────────
Write-Section "TEST 3: GET /players?platform=roblox"

try {
    $response = Invoke-RestMethod `
        -Uri "$BaseUrl/api/v1/gateway/$WorkspaceId/players?platform=roblox&pageSize=10" `
        -Method GET `
        -Headers $headers

    $count = if ($response -is [Array]) { $response.Count } else { 1 }
    Write-Pass "Listed $count player(s)"
}
catch {
    Write-Fail "List failed: $($_.Exception.Message)"
    if ($_.ErrorDetails.Message) {
        Write-Fail "Details: $($_.ErrorDetails.Message)"
    }
}

# ─── Test 4: Identify Second Player ──────────────────────────────────────────
Write-Section "TEST 4: Identify second player (Minecraft)"

$identify2Body = @{
    platform        = "minecraft"
    platformPlayerId = "f47ac10b-58cc-4372-a567-0e02b2c3d479"
    displayName     = "SteveBuilder"
    metadata        = @{
        version = "1.21"
        server  = "local-test"
    }
} | ConvertTo-Json -Depth 5

try {
    $response = Invoke-RestMethod `
        -Uri "$BaseUrl/api/v1/gateway/$WorkspaceId/players/identify" `
        -Method POST `
        -Headers $headers `
        -Body $identify2Body `
        -ContentType "application/json"

    Write-Pass "Minecraft player identified: $($response.displayName)"
}
catch {
    Write-Fail "Identify failed: $($_.Exception.Message)"
    if ($_.ErrorDetails.Message) {
        Write-Fail "Details: $($_.ErrorDetails.Message)"
    }
}

# ─── Test 5: Player Headers (SDK simulation) ─────────────────────────────────
Write-Section "TEST 5: Data query with player headers (SDK simulation)"

$playerHeaders = @{
    "Content-Type"     = "application/json"
    "x-api-key"       = $ApiKey
    "x-player-platform" = "roblox"
    "x-player-id"     = "1516563360"
}

# This would normally be a PraxQL query — just test the headers pass through
try {
    $schemaResponse = Invoke-RestMethod `
        -Uri "$BaseUrl/api/v1/gateway/$WorkspaceId/schema" `
        -Method GET `
        -Headers $playerHeaders

    Write-Pass "Schema endpoint works with player headers"
    $tableCount = if ($schemaResponse.tables) { $schemaResponse.tables.Count } else { "?" }
    Write-Info "Tables in workspace: $tableCount"
}
catch {
    if ($_.Exception.Response.StatusCode -eq 401) {
        Write-Fail "Unauthorized - check your API key"
    } else {
        Write-Fail "Schema call failed: $($_.Exception.Message)"
    }
}

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
Write-Host "  Local test complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps for Roblox Studio testing:" -ForegroundColor White
Write-Host "  1. Open Roblox Studio" -ForegroundColor Gray
Write-Host "  2. Enable HttpService (Game Settings > Security)" -ForegroundColor Gray
Write-Host "  3. Add PraxsuiteSDK to ServerScriptService" -ForegroundColor Gray
Write-Host "  4. Create PraxsuiteConfig module:" -ForegroundColor Gray
Write-Host "     return {" -ForegroundColor DarkGray
Write-Host "         workspaceId = `"$WorkspaceId`"," -ForegroundColor DarkGray
Write-Host "         apiKeySecret = `"PraxsuiteKey`"," -ForegroundColor DarkGray
Write-Host "         baseUrl = `"$BaseUrl`"," -ForegroundColor DarkGray
Write-Host "     }" -ForegroundColor DarkGray
Write-Host "  5. Store API key in Secrets Store as 'PraxsuiteKey'" -ForegroundColor Gray
Write-Host "  6. Run game — SDK auto-inits and connects!" -ForegroundColor Gray
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
