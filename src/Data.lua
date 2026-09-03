--[[
    Data - Data operations module.

    Provides Query, Insert, Update, Delete, InsertMany, Count, and Batch.
    All operations go through the PraxQL query endpoint.

    PER-PLAYER SCOPING (`asPlayer`)

    Every call takes an optional `asPlayer = player`, and the request then goes out as that
    player's own session rather than as your server key. What that buys: the table's row filters
    apply to them, so a query returns their rows and nobody else's, without your code filtering
    by UserId and without the gateway trusting it to.

        Praxsuite.Data.Query("saves", { where = { level = { gt = 5 } } }, { asPlayer = player })

    Some history, because this option existed before and did nothing. Until 1.0.0 `asPlayer`
    set x-player-platform / x-player-id headers that no gateway code path read: it looked like a
    security boundary while scoping precisely nothing, and it was removed rather than left to
    mislead. It is back now because there is finally a real per-player session behind it
    (Auth.LoginPlayer), issued by the gateway and carrying the player's roles.

    Without `asPlayer` nothing changes: the call uses the server key, your game server is the
    trusted party, and per-player rules are yours to enforce - as with any DataStore write.
]]

local Config = require(script.Parent.Core.Config)
local Http = require(script.Parent.Core.Http)
local PraxQL = require(script.Parent.Core.PraxQL)

local Data = {}

--- Internal: resolves `asPlayer` to a session token, signing the player in if needed.
--- Returns nil when no player was given, which makes the request use the server key.
local function tokenFor(opts: { asPlayer: Player? }?): string?
    if not opts or not opts.asPlayer then
        return nil
    end
    local Auth = require(script.Parent.Auth)
    return Auth.GetTokenFor(opts.asPlayer)
end

--- Internal: one line naming what is about to happen, before Http even builds the request —
--- so a scan of the log reads "Query saves as MirkOwwO" rather than requiring the reader to
--- match up a PraxQL body with an Http line further down.
local function announce(op: string, tableName: string, opts: { asPlayer: Player? }?)
    local as = if opts and opts.asPlayer then opts.asPlayer.Name else "server key"
    Config.Log("[Data] %s %s  as %s", op, tableName, as)
end

--- Query rows from a table.
--- @param tableName string - The table name (must be registered in schema)
--- @param options table? - { where?, select?, orderBy?, limit?, offset?, includeTotalCount? }
--- @return { [any] } - Array of row objects
---
--- Example:
---   local rows = Praxsuite.Data.Query("inventory", {
---       where = { owner_id = player.UserId, rarity = "legendary" },
---       orderBy = { "created_at", "desc" },
---       limit = 50
---   })
function Data.Query(tableName: string, options: {
    where: { [string]: any }?,
    select: { string }?,
    orderBy: any?,
    limit: number?,
    offset: number?,
    includeTotalCount: boolean?,
}?, requestOptions: { asPlayer: Player? }?): { any }
    local opts = options or {}
    announce("Query", tableName, requestOptions)

    local body = PraxQL.BuildQuery(tableName, opts)
    local response = Http.Post("query", body, tokenFor(requestOptions))

    local rows = response.body.data or response.body or {}
    Config.Log("[Data] Query %s  -> %d row(s)", tableName, typeof(rows) == "table" and #rows or -1)
    return rows
end

--- Insert a single row into a table.
--- @param tableName string - The table name
--- @param row table - Column-value pairs to insert
--- @return table? - The inserted row (if returning enabled)
---
--- Example:
---   local inserted = Praxsuite.Data.Insert("game_events", {
---       player_id = player.UserId,
---       event = "boss_killed",
---       boss_name = "Dragon"
---   })
function Data.Insert(tableName: string, row: { [string]: any }, options: {
    returning: boolean?,
}?, requestOptions: { asPlayer: Player? }?): any
    local opts = options or {}
    announce("Insert", tableName, requestOptions)

    local body = PraxQL.BuildInsert(tableName, { row }, opts.returning)
    local response = Http.Post("query", body, tokenFor(requestOptions))


    local data = response.body.data or response.body
    if typeof(data) == "table" and data[1] then
        return data[1]
    end
    return data
end

--- Insert multiple rows into a table in one request.
--- @param tableName string - The table name
--- @param rows table - Array of row objects
--- @return { any } - Array of inserted rows
---
--- Example:
---   Praxsuite.Data.InsertMany("scores", {
---       { player_id = 1, score = 100 },
---       { player_id = 2, score = 200 },
---   })
function Data.InsertMany(tableName: string, rows: { { [string]: any } }, options: {
    returning: boolean?,
}?, requestOptions: { asPlayer: Player? }?): { any }
    local opts = options or {}
    assert(#rows > 0, "[PraxsuiteSDK] InsertMany requires at least one row")
    announce("InsertMany (" .. #rows .. " rows)", tableName, requestOptions)

    local body = PraxQL.BuildInsert(tableName, rows, opts.returning)
    local response = Http.Post("query", body, tokenFor(requestOptions))


    return response.body.data or response.body or {}
end

--- Update rows in a table.
--- @param tableName string - The table name
--- @param options table - { set: {column=value}, where: {conditions} }
--- @return table - Update result (affected count)
---
--- Example:
---   Praxsuite.Data.Update("players", {
---       set = { coins = 1500, level = 12 },
---       where = { player_id = player.UserId }
---   })
function Data.Update(tableName: string, options: {
    set: { [string]: any },
    where: { [string]: any },
}, requestOptions: { asPlayer: Player? }?): any
    announce("Update", tableName, requestOptions)
    local body = PraxQL.BuildUpdate(tableName, options)
    local response = Http.Post("query", body, tokenFor(requestOptions))


    return response.body
end

--- Delete rows from a table.
--- @param tableName string - The table name
--- @param options table - { where: {conditions} }
--- @return table - Delete result (affected count)
---
--- Example:
---   Praxsuite.Data.Delete("expired_buffs", {
---       where = { expires_at = { lt = os.time() } }
---   })
function Data.Delete(tableName: string, options: {
    where: { [string]: any },
}, requestOptions: { asPlayer: Player? }?): any
    announce("Delete", tableName, requestOptions)
    local body = PraxQL.BuildDelete(tableName, options)
    local response = Http.Post("query", body, tokenFor(requestOptions))


    return response.body
end

--- Get the count of rows matching a condition.
--- @param tableName string - The table name
--- @param where table? - Where conditions
--- @return number - Row count
---
--- Example:
---   local online = Praxsuite.Data.Count("players", { is_online = true })
function Data.Count(tableName: string, where: { [string]: any }?, requestOptions: { asPlayer: Player? }?): number
    announce("Count", tableName, requestOptions)
    local body = PraxQL.BuildQuery(tableName, {
        where = where,
        select = nil,
        limit = 1,   -- the gateway clamps limit up to a minimum of 1; a 0-row count is impossible
        includeTotalCount = true,
    })

    local response = Http.Post("query", body, tokenFor(requestOptions))
    local meta = response.body.meta or {}

    -- The gateway names this field "total" (PraxQLResultMeta). Reading "totalCount", as this
    -- SDK did until now, silently returned 0 forever - no error, just a wrong number.
    if meta.total == nil then
        error(
            "[PraxsuiteSDK] The gateway returned no total count. Aggregations may be disabled "
            .. "on this table's scope - enable them in API Gateway settings."
        )
    end
    return meta.total
end

export type BatchOperation = {
    op: "insert" | "update" | "delete",
    table: string,
    values: { [string]: any }?,  -- for insert
    set: { [string]: any }?,     -- for update
    where: { [string]: any }?,   -- for update/delete
}

--- Execute multiple data operations in sequence.
--- Operations are executed one by one (server-side batch endpoint planned for future).
--- If any operation fails, subsequent operations are NOT executed.
--- @param operations table - Array of BatchOperation
--- @return { any } - Array of results (one per operation)
---
--- Example:
---   Praxsuite.Data.Batch({
---       { op = "insert", table = "scores", values = { player_id = 1, score = 100 } },
---       { op = "update", table = "players", set = { last_active = os.time() }, where = { id = 1 } },
---   })
function Data.Batch(operations: { BatchOperation }, options: {
}?, requestOptions: { asPlayer: Player? }?): { any }
    local opts = options or {}
    Config.Log("[Data] Batch (%d operations)  as %s",
        #operations, if requestOptions and requestOptions.asPlayer then requestOptions.asPlayer.Name else "server key")

    -- Resolved once, not per operation: the session is the same for every request in the batch,
    -- and asking for it inside the loop would re-check expiry on each one.
    local token = tokenFor(requestOptions)

    local results = {}

    for i, operation in ipairs(operations) do
        Config.Log("[Data]   %d/%d: %s %s", i, #operations, operation.op, operation.table)
        local body

        if operation.op == "insert" then
            local rows = if operation.values and operation.values[1]
                then operation.values
                else { operation.values }
            body = PraxQL.BuildInsert(operation.table, rows)
        elseif operation.op == "update" then
            body = PraxQL.BuildUpdate(operation.table, {
                set = operation.set,
                where = operation.where,
            })
        elseif operation.op == "delete" then
            body = PraxQL.BuildDelete(operation.table, {
                where = operation.where,
            })
        else
            error("[PraxsuiteSDK] Unknown batch operation: " .. tostring(operation.op))
        end

        local response = Http.Post("query", body, token)
        table.insert(results, response.body)
    end


    return results
end

return Data
