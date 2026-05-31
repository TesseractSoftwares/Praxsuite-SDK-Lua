# Praxsuite SDK for Lua

Official SDK for connecting Lua-based game engines to [Praxsuite](https://praxsuite.com) as a backend.

Supports **Roblox**, **FiveM/GTA**, **Garry's Mod**, and any Lua 5.1+ runtime.

## Quick Start (Roblox)

### 1. Install

**Via Wally (recommended):**
```toml
# wally.toml
[dependencies]
PraxsuiteSDK = "tesseract/praxsuite-sdk@0.1.0"
```

**Or copy `src/` folder** into `game.ServerScriptService.PraxsuiteSDK`.

### 2. Store your API Key

In Roblox Studio → Game Settings → Security → Secrets Store:
- Name: `PraxsuiteKey`
- Value: Your `pk_live_...` or `sk_live_...` key from Praxsuite Gateway

### 3. Initialize

```lua
-- ServerScript
local Praxsuite = require(game.ServerScriptService.PraxsuiteSDK)

Praxsuite.Init({
    workspaceId = "your-workspace-uuid",
    apiKeySecret = "PraxsuiteKey",  -- Name in Secrets Store
})
```

### 4. Use It

```lua
-- Identify players when they join
game.Players.PlayerAdded:Connect(function(player)
    Praxsuite.Players.Identify(player)
end)

game.Players.PlayerRemoving:Connect(function(player)
    Praxsuite.Players.Forget(player)
end)

-- Query data
local items = Praxsuite.Data.Query("inventory", {
    where = { owner_id = player.UserId, rarity = "legendary" },
    orderBy = { "created_at", "desc" },
    limit = 20
})

-- Insert data
Praxsuite.Data.Insert("game_events", {
    player_id = player.UserId,
    event = "boss_killed",
    boss_name = "Dragon",
    damage_dealt = 4500
})

-- Update data
Praxsuite.Data.Update("players", {
    set = { coins = 1500, level = 12 },
    where = { player_id = player.UserId }
})

-- Delete data
Praxsuite.Data.Delete("expired_buffs", {
    where = { expires_at = { lt = os.time() } }
})

-- Call a sync endpoint (runs automation, returns result)
local result = Praxsuite.Endpoints.Call("validate-purchase", {
    player_id = player.UserId,
    product_id = "sword_of_fire",
    receipt = receiptInfo.PurchaseId
})
if result.approved then
    -- Grant item
end

-- Fire-and-forget event
Praxsuite.Endpoints.Fire("on-player-leave", {
    player_id = player.UserId,
    play_duration = os.time() - joinTime
})
```

## API Reference

### `Praxsuite.Init(options)`

Initialize the SDK. Must be called once before any other method.

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `workspaceId` | string | ✅ | — | Your Praxsuite workspace UUID |
| `apiKeySecret` | string | ✅ | — | Name of the secret in Roblox Secrets Store |
| `baseUrl` | string | ❌ | `https://gateway.praxsuite.com` | Gateway URL (override for self-hosted) |
| `autoFetchSchema` | boolean | ❌ | `true` | Auto-fetch table name→UUID mapping on init |
| `retryEnabled` | boolean | ❌ | `true` | Enable automatic retry with exponential backoff |
| `maxRetries` | number | ❌ | `3` | Maximum retry attempts on 429/5xx |
| `timeout` | number | ❌ | `30` | Request timeout in seconds |

---

### `Praxsuite.Data`

#### `.Query(tableName, options?) → rows[]`

Read rows from a table.

```lua
local rows = Praxsuite.Data.Query("scores", {
    where = { level = { gte = 5 } },
    select = { "player_name", "score", "created_at" },
    orderBy = { "score", "desc" },
    limit = 10,
    offset = 0,
    asPlayer = player,  -- optional: attach player identity
})
```

#### `.Insert(tableName, row, options?) → insertedRow`

Insert a single row.

```lua
local inserted = Praxsuite.Data.Insert("inventory", {
    owner_id = player.UserId,
    item_name = "Fire Sword",
    rarity = "epic",
    damage = 150
})
print(inserted.Id)  -- UUID of the new row
```

#### `.InsertMany(tableName, rows, options?) → insertedRows[]`

Insert multiple rows in one request.

```lua
Praxsuite.Data.InsertMany("kill_log", {
    { killer = 1, victim = 2, weapon = "sword" },
    { killer = 3, victim = 4, weapon = "bow" },
})
```

#### `.Update(tableName, options) → result`

Update rows matching conditions.

```lua
Praxsuite.Data.Update("players", {
    set = { coins = 500 },
    where = { player_id = player.UserId }
})
```

#### `.Delete(tableName, options) → result`

Delete rows matching conditions.

```lua
Praxsuite.Data.Delete("sessions", {
    where = { expires_at = { lt = os.time() } }
})
```

#### `.Count(tableName, where?) → number`

Count rows matching conditions.

```lua
local online = Praxsuite.Data.Count("players", { is_online = true })
```

#### `.Batch(operations, options?) → results[]`

Execute multiple operations sequentially in one call.

```lua
Praxsuite.Data.Batch({
    { op = "insert", table = "scores", values = { player_id = 1, score = 100 } },
    { op = "update", table = "players", set = { last_active = os.time() }, where = { id = 1 } },
    { op = "delete", table = "temp_data", where = { session_id = "abc" } },
})
```

---

### `Praxsuite.Endpoints`

#### `.Call(slug, payload?, options?) → response`

Call a sync endpoint and wait for the response. The endpoint must have `Mode=Sync` with a linked automation.

```lua
local result = Praxsuite.Endpoints.Call("validate-trade", {
    from_player = player1.UserId,
    to_player = player2.UserId,
    items = { "sword_123", "shield_456" }
})
```

#### `.Fire(slug, payload?, options?) → boolean`

Fire-and-forget. Returns `true` if accepted (2xx).

```lua
Praxsuite.Endpoints.Fire("analytics-event", {
    event = "round_end",
    winner = player.UserId,
    duration = 180
})
```

---

### `Praxsuite.Players`

#### `.Identify(player, options?)`

Register a player with Praxsuite. Call on `PlayerAdded`.

```lua
Praxsuite.Players.Identify(player, {
    metadata = { accountAge = player.AccountAge }
})
```

#### `.Forget(player)`

Remove from local cache. Call on `PlayerRemoving`.

#### `.SetContext(player)` / `.ClearContext()`

Manually set player context for requests. Prefer using `asPlayer` option on Data/Endpoints methods instead.

---

### `Praxsuite.Schema`

#### `.Register(name, uuid)`

Manually register a table name → UUID mapping.

```lua
Praxsuite.Schema.Register("players", "a1b2c3d4-...")
```

#### `.RegisterMany(tables)`

Register multiple tables at once.

```lua
Praxsuite.Schema.RegisterMany({
    players = "uuid-1",
    inventory = "uuid-2",
    scores = "uuid-3",
})
```

#### `.Fetch() → registry`

Fetch schema from gateway (called automatically on init).

---

## Where Clause Operators

| Operator | Lua Syntax | Description |
|----------|-----------|-------------|
| Equals | `{ col = value }` | Exact match |
| Not equals | `{ col = { neq = value } }` | Not equal |
| Greater than | `{ col = { gt = value } }` | Greater than |
| Greater or equal | `{ col = { gte = value } }` | Greater than or equal |
| Less than | `{ col = { lt = value } }` | Less than |
| Less or equal | `{ col = { lte = value } }` | Less than or equal |
| Like | `{ col = { like = "%text%" } }` | Pattern match |
| Case-insensitive like | `{ col = { ilike = "%text%" } }` | Case-insensitive pattern |
| In array | `{ col = { ["in"] = {1,2,3} } }` | Value in list |
| Not in array | `{ col = { notIn = {1,2,3} } }` | Value not in list |
| Is null | `{ col = { isNull = true } }` | Column is null |
| Is not null | `{ col = { isNotNull = true } }` | Column is not null |
| Contains | `{ col = { contains = "text" } }` | Contains substring |
| Starts with | `{ col = { startsWith = "pre" } }` | Starts with prefix |
| Ends with | `{ col = { endsWith = "suf" } }` | Ends with suffix |

---

## Error Handling

All methods throw on error. Use `pcall` for safe error handling:

```lua
local ok, result = pcall(function()
    return Praxsuite.Data.Query("players", { where = { id = 123 } })
end)

if not ok then
    -- result is an error table: { code, message, status, details? }
    warn("Query failed:", result.message)
end
```

---

## Roblox Limits

- **500 HTTP requests/min** per game server (Roblox platform limit)
- **~500KB max response** size per request
- **HTTPS required** (gateway is HTTPS by default)
- API key must be in **Secrets Store** (never hardcode)

Use `Data.Batch()` to combine operations and stay under the 500 req/min limit.

---

## License

MIT © Tesseract Softwares
