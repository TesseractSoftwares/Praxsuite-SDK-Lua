--[[
    Players - Player identity module.

    Records a Roblox player's identity against the workspace, for analytics, dashboards and
    cross-platform account linking.

    Read this before treating it as an authorisation mechanism, because it is not one. The
    gateway does verify a Roblox UserId against the Roblox users API, so IsValidated means
    something here - but the record is a label, not a permission. Nothing about it scopes a
    query.

    On Roblox that is fine: this SDK runs in ServerScriptService with a server key, so your
    game server is the trusted party and enforces its own rules. The SetContext/ClearContext
    functions that used to live here set x-player-platform / x-player-id headers which no
    gateway code path reads; they have been removed rather than left to mislead.
]]

local Config = require(script.Parent.Core.Config)

local Players = {}

-- Internal: cache of identified players { [UserId] = { platform, id, displayName } }
local _identifiedPlayers: { [number]: { platform: string, id: string, displayName: string } } = {}

--- Identify a player. Caches their platform info for subsequent requests.
--- Optionally calls the identity endpoint to register them in Praxsuite.
--- @param player Player - The Roblox Player instance
--- @param options table? - { register?: boolean }
---
--- Example:
---   game.Players.PlayerAdded:Connect(function(player)
---       Praxsuite.Players.Identify(player)
---   end)
function Players.Identify(player: Player, options: {
    register: boolean?,
    metadata: { [string]: any }?,
}?)
    Config.AssertInitialized()
    local opts = options or {}

    local info = {
        platform = "roblox",
        id = tostring(player.UserId),
        displayName = player.DisplayName,
    }

    _identifiedPlayers[player.UserId] = info

    -- Optionally register with Praxsuite backend (creates contact link)
    if opts.register ~= false then
        -- Defer registration to avoid blocking PlayerAdded
        task.spawn(function()
            local Http = require(script.Parent.Core.Http)
            local ok, err = pcall(function()
                Http.Post("players/identify", {
                    platform = info.platform,
                    platformPlayerId = info.id,
                    displayName = info.displayName,
                    metadata = opts.metadata,
                })
            end)
            if not ok then
                warn("[PraxsuiteSDK] Failed to register player " .. info.id .. ": " .. tostring(err))
            end
        end)
    end
end

--- Remove a player from the identity cache (call on PlayerRemoving).
--- @param player Player - The Roblox Player instance
function Players.Forget(player: Player)
    _identifiedPlayers[player.UserId] = nil
end

--- Get the cached identity info for a player.
--- @param player Player - The Roblox Player instance
--- @return table? - { platform, id, displayName } or nil if not identified
function Players.GetInfo(player: Player): { platform: string, id: string, displayName: string }?
    return _identifiedPlayers[player.UserId]
end

--- Check if a player has been identified.
--- @param player Player - The Roblox Player instance
--- @return boolean
function Players.IsIdentified(player: Player): boolean
    return _identifiedPlayers[player.UserId] ~= nil
end

return Players
