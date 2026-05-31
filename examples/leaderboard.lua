--[[
    Example: Leaderboard System
    
    Shows how to build a competitive leaderboard with Praxsuite.
    Scores are stored in the database and queried in real-time.
    
    Prerequisite: PraxsuiteConfig module in ServerScriptService.
]]

local Players = game:GetService("Players")
local Praxsuite = require(game.ServerScriptService.PraxsuiteSDK)

-- No Init() needed — auto-discovers PraxsuiteConfig.

local Leaderboard = {}

--- Submit a score for a player.
function Leaderboard.SubmitScore(player, score, gameMode)
    Praxsuite.Data.Insert("leaderboard_scores", {
        player_id = player.UserId,
        player_name = player.DisplayName,
        score = score,
        game_mode = gameMode or "default",
        submitted_at = os.time(),
    }, { asPlayer = player })
end

--- Get top N scores for a game mode.
function Leaderboard.GetTop(gameMode, limit)
    return Praxsuite.Data.Query("leaderboard_scores", {
        select = { "player_name", "score", "submitted_at" },
        where = { game_mode = gameMode or "default" },
        orderBy = { "score", "desc" },
        limit = limit or 25,
    })
end

--- Get a player's best score.
function Leaderboard.GetPlayerBest(player, gameMode)
    local results = Praxsuite.Data.Query("leaderboard_scores", {
        where = {
            player_id = player.UserId,
            game_mode = gameMode or "default",
        },
        orderBy = { "score", "desc" },
        limit = 1,
        asPlayer = player,
    })
    return results[1]
end

--- Get total number of unique players on leaderboard.
function Leaderboard.GetPlayerCount(gameMode)
    return Praxsuite.Data.Count("leaderboard_scores", {
        game_mode = gameMode or "default",
    })
end

return Leaderboard
