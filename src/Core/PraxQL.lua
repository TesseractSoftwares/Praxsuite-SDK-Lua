--[[
    PraxQL - Query builder.
    Converts Lua-friendly syntax into PraxQL JSON format.
    This is an internal module — game developers never interact with it directly.
]]

local Config = require(script.Parent.Config)

local PraxQL = {}

--- Operator mapping for where clauses.
--- Simple value: { column = value } → op: "eq"
--- Object value: { column = { gt = 5 } } → op: "gt", value: 5
---
--- Only the operators the gateway's PraxQL parser actually accepts appear here. Until 1.0.0
--- this table also offered notIn, isNull, isNotNull, startsWith and endsWith - the server
--- implements none of them, so every call using one failed at runtime, in a live game.
---
--- Where a concept has no operator of its own it is TRANSLATED below into one that exists,
--- rather than passed through and rejected.
local OPERATORS = {
    eq = "eq",
    neq = "neq",
    gt = "gt",
    gte = "gte",
    lt = "lt",
    lte = "lte",
    like = "like",
    ilike = "ilike",
    ["in"] = "in",
    is = "is",
    between = "between",
    contains = "contains",
    textsearch = "textsearch",
}

--- Convenience operators with no server-side equivalent, rewritten into one that has.
--- Each returns the op and value to send.
local TRANSLATIONS = {
    -- "is" only tests for null server-side.
    isNull      = function() return "is", nil, false end,
    isNotNull   = function() return "neq", nil, false end,
    startsWith  = function(v) return "like", tostring(v) .. "%", true end,
    endsWith    = function(v) return "like", "%" .. tostring(v), true end,
    notIn       = nil,  -- deliberately absent: see the error below
}

--- Build a PraxQL where array from a Lua-friendly where table.
--- Supports:
---   { player_id = 123 }                    → eq
---   { score = { gt = 100 } }               → gt
---   { name = { like = "%john%" } }         → like
---   { status = { ["in"] = {"active","pending"} } } → in
function PraxQL.BuildWhere(where: { [string]: any }?): { any }?
    if not where or next(where) == nil then
        return nil
    end

    local conditions = {}

    for column, value in pairs(where) do
        if typeof(value) == "table" and not (typeof(value[1]) ~= "nil") then
            -- Operator object: { gt = 5 } or { ["in"] = {1,2,3} }
            for op, opValue in pairs(value) do
                if OPERATORS[op] then
                    table.insert(conditions, {
                        field = column,
                        op = OPERATORS[op],
                        value = opValue,
                    })
                elseif TRANSLATIONS[op] then
                    -- A convenience name with no server-side operator: rewrite it.
                    local mappedOp, mappedValue, hasValue = TRANSLATIONS[op](opValue)
                    local condition = { field = column, op = mappedOp }
                    if hasValue then
                        condition.value = mappedValue
                    else
                        -- isNull / isNotNull compare against null, which must be sent explicitly.
                        condition.value = nil
                    end
                    table.insert(conditions, condition)
                elseif op == "notIn" then
                    error(
                        "[PraxsuiteSDK] There is no 'notIn' operator - the gateway does not "
                        .. "implement one. Express it as a positive 'in' over the values you do "
                        .. "want, or filter the result set in Lua."
                    )
                else
                    error(
                        "[PraxsuiteSDK] Unknown operator '" .. tostring(op) .. "' for column '"
                        .. column .. "'. Supported: eq neq gt gte lt lte like ilike in is "
                        .. "between contains textsearch, plus isNull isNotNull startsWith "
                        .. "endsWith which are translated for you."
                    )
                end
            end
        else
            -- Simple equality: { player_id = 123 }
            table.insert(conditions, {
                field = column,
                op = "eq",
                value = value,
            })
        end
    end

    return conditions
end

--- Build orderBy array from Lua-friendly syntax.
--- Supports:
---   "score"                        → { column = "score", direction = "desc" }
---   { "score", "asc" }            → { column = "score", direction = "asc" }
---   { column = "score", dir = "asc" }
function PraxQL.BuildOrderBy(orderBy: any?): { any }?
    if not orderBy then
        return nil
    end

    local result = {}

    if typeof(orderBy) == "string" then
        -- Single column, default desc
        table.insert(result, { field = orderBy, dir = "desc" })
    elseif typeof(orderBy) == "table" then
        -- Could be single { "col", "dir" } or array of order specs
        if typeof(orderBy[1]) == "string" and typeof(orderBy[2]) == "string" and #orderBy == 2 then
            -- Single: { "score", "desc" }
            table.insert(result, { field = orderBy[1], dir = orderBy[2] })
        elseif typeof(orderBy[1]) == "table" then
            -- Array of specs: { {"score","desc"}, {"name","asc"} }
            for _, spec in ipairs(orderBy) do
                if typeof(spec) == "string" then
                    table.insert(result, { field = spec, dir = "desc" })
                elseif typeof(spec) == "table" then
                    table.insert(result, {
                        field = spec[1] or spec.column or spec.field,
                        dir = spec[2] or spec.dir or "desc",
                    })
                end
            end
        elseif orderBy.column or orderBy.field then
            -- Single object: { column = "score", dir = "desc" }
            table.insert(result, { field = orderBy.column or orderBy.field, dir = orderBy.dir or "desc" })
        end
    end

    return if #result > 0 then result else nil
end

--- Build a full PraxQL query request body.
function PraxQL.BuildQuery(tableName: string, options: {
    select: { string }?,
    where: { [string]: any }?,
    orderBy: any?,
    limit: number?,
    offset: number?,
    includeTotalCount: boolean?,
}?): any
    local opts = options or {}
    local tableUuid = Config.ResolveTable(tableName)

    return {
        refs = { t1 = tableUuid },
        query = {
            from = "t1",
            select = opts.select,
            where = PraxQL.BuildWhere(opts.where),
            orderBy = PraxQL.BuildOrderBy(opts.orderBy),
            limit = opts.limit,
            offset = opts.offset,
        },
        includeTotalCount = opts.includeTotalCount or false,
    }
end

--- Build a PraxQL insert mutation request body.
function PraxQL.BuildInsert(tableName: string, rows: { { [string]: any } }, returning: boolean?): any
    local tableUuid = Config.ResolveTable(tableName)

    return {
        refs = { t1 = tableUuid },
        mutation = {
            type = "insert",
            table = "t1",
            values = rows,
            returning = if returning ~= false then true else nil,
        },
    }
end

--- Build a PraxQL update mutation request body.
function PraxQL.BuildUpdate(tableName: string, options: {
    set: { [string]: any },
    where: { [string]: any },
}): any
    local tableUuid = Config.ResolveTable(tableName)

    assert(options.set and next(options.set), "[PraxsuiteSDK] Update requires 'set' with at least one field")
    assert(options.where and next(options.where), "[PraxsuiteSDK] Update requires 'where' clause (no unscoped updates)")

    return {
        refs = { t1 = tableUuid },
        mutation = {
            type = "update",
            table = "t1",
            set = options.set,
            where = PraxQL.BuildWhere(options.where),
        },
    }
end

--- Build a PraxQL delete mutation request body.
function PraxQL.BuildDelete(tableName: string, options: {
    where: { [string]: any },
}): any
    local tableUuid = Config.ResolveTable(tableName)

    assert(options.where and next(options.where), "[PraxsuiteSDK] Delete requires 'where' clause (no unscoped deletes)")

    return {
        refs = { t1 = tableUuid },
        mutation = {
            type = "delete",
            table = "t1",
            where = PraxQL.BuildWhere(options.where),
        },
    }
end

return PraxQL
