--[[
    Data - Data operations module.

    NOTE ON PER-PLAYER SCOPING (changed in 1.0.0)

    Earlier versions accepted an `asPlayer` option on every call, which set
    x-player-platform / x-player-id request headers. No code path in the Praxsuite gateway
    reads those headers, so it scoped precisely nothing - it read like a security boundary
    while being decorative. It has been removed rather than left in place.

    This is not a loss of capability on Roblox. The SDK runs in ServerScriptService with a
    server key, so YOUR game server is the trusted party: enforce per-player rules in your own
    server code, the same way you would for any DataStore write. The gateway's row-filter
    isolation exists for untrusted clients (a browser, a Unity build) which authenticate as an
    end user - a different model from a trusted game server.
    Provides Query, Insert, Update, Delete, InsertMany, Count, and Batch.
    All operations go through the PraxQL query endpoint.
]]

local Http = require(script.Parent.Core.Http)
local PraxQL = require(script.Parent.Core.PraxQL)

local Data = {}

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
}?): { any }
    local opts = options or {}

    -- Set player context if provided

    local body = PraxQL.BuildQuery(tableName, opts)
    local response = Http.Post("query", body)

    -- Clear player context after request

    return response.body.data or response.body or {}
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
}?): any
    local opts = options or {}


    local body = PraxQL.BuildInsert(tableName, { row }, opts.returning)
    local response = Http.Post("query", body)


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
}?): { any }
    local opts = options or {}
    assert(#rows > 0, "[PraxsuiteSDK] InsertMany requires at least one row")


    local body = PraxQL.BuildInsert(tableName, rows, opts.returning)
    local response = Http.Post("query", body)


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
}): any

    local body = PraxQL.BuildUpdate(tableName, options)
    local response = Http.Post("query", body)


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
}): any

    local body = PraxQL.BuildDelete(tableName, options)
    local response = Http.Post("query", body)


    return response.body
end

--- Get the count of rows matching a condition.
--- @param tableName string - The table name
--- @param where table? - Where conditions
--- @return number - Row count
---
--- Example:
---   local online = Praxsuite.Data.Count("players", { is_online = true })
function Data.Count(tableName: string, where: { [string]: any }?): number
    local body = PraxQL.BuildQuery(tableName, {
        where = where,
        select = nil,
        limit = 1,   -- the gateway clamps limit up to a minimum of 1; a 0-row count is impossible
        includeTotalCount = true,
    })

    local response = Http.Post("query", body)
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
}?): { any }
    local opts = options or {}


    local results = {}

    for _, operation in ipairs(operations) do
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

        local response = Http.Post("query", body)
        table.insert(results, response.body)
    end


    return results
end

return Data
