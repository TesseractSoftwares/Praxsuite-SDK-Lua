--[[
    Schema - Table registry and auto-discovery.
    Resolves table names to UUIDs by fetching the gateway schema endpoint.
    Allows manual registration for environments where auto-fetch isn't desired.
]]

local Config = require(script.Parent.Core.Config)
local Http = require(script.Parent.Core.Http)

local Schema = {}

--- Fetch the workspace schema from the gateway and populate the table registry.
--- Called automatically during Init() unless autoFetchSchema = false.
--- @return { [string]: string } - Map of table names → UUIDs
function Schema.Fetch(): { [string]: string }
    Config.AssertInitialized()

    local response = Http.Get("schema")
    local schema = response.body

    -- Parse schema response — extract table names and IDs
    if typeof(schema) == "table" then
        local tables = schema.tables or schema

        if typeof(tables) == "table" then
            for _, tbl in ipairs(tables) do
                if tbl.name and tbl.id then
                    Config._tableRegistry[tbl.name] = tbl.id
                elseif tbl.Name and tbl.Id then
                    Config._tableRegistry[tbl.Name] = tbl.Id
                end
            end
        end
    end

    return Config._tableRegistry
end

--- Manually register a table name → UUID mapping.
--- Use this when autoFetchSchema is disabled or for tables not yet in schema.
--- @param name string - The table name to use in Data operations
--- @param uuid string - The table's UUID in Praxsuite
---
--- Example:
---   Praxsuite.Schema.Register("players", "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
---   Praxsuite.Schema.Register("inventory", "f9e8d7c6-b5a4-3210-fedc-ba0987654321")
function Schema.Register(name: string, uuid: string)
    assert(name and #name > 0, "[PraxsuiteSDK] Schema.Register: name is required")
    assert(uuid and #uuid > 0, "[PraxsuiteSDK] Schema.Register: uuid is required")
    Config._tableRegistry[name] = uuid
end

--- Register multiple tables at once.
--- @param tables table - Map of { name = uuid, name2 = uuid2, ... }
---
--- Example:
---   Praxsuite.Schema.RegisterMany({
---       players = "uuid-1",
---       inventory = "uuid-2",
---       scores = "uuid-3",
---   })
function Schema.RegisterMany(tables: { [string]: string })
    for name, uuid in pairs(tables) do
        Config._tableRegistry[name] = uuid
    end
end

--- Get the current table registry (for debugging).
--- @return { [string]: string } - Current name → UUID mappings
function Schema.GetRegistry(): { [string]: string }
    return Config._tableRegistry
end

--- Check if a table is registered.
--- @param name string - Table name
--- @return boolean
function Schema.Has(name: string): boolean
    return Config._tableRegistry[name] ~= nil
end

return Schema
