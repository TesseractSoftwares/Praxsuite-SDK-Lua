--[[
    Players - Player identity module.
    Maps Roblox players to Praxsuite contacts via x-player-platform/x-player-id headers.
    Handles player context for requests.
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
                Players.SetContext(player)
                Http.Post("players/identify", {
                    platform = info.platform,
                    platformPlayerId = info.id,
                    displayName = info.displayName,
                    metadata = opts.metadata,
                })
                Players.ClearContext()
            end)
            if not ok then
                Players.ClearContext()
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

--- Set the current player context for subsequent requests.
--- Headers x-player-platform and x-player-id will be included in the next request(s).
--- @param player Player - The Roblox Player instance
function Players.SetContext(player: Player)
    local info = _identifiedPlayers[player.UserId]
    if info then
        Config._currentPlayerPlatform = info.platform
        Config._currentPlayerId = info.id
    else
        -- Player not identified yet, use raw info
        Config._currentPlayerPlatform = "roblox"
        Config._currentPlayerId = tostring(player.UserId)
    end
end

--- Clear the current player context.
--- Call after completing a player-scoped request (or use asPlayer option instead).
function Players.ClearContext()
    Config._currentPlayerPlatform = nil
    Config._currentPlayerId = nil
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
