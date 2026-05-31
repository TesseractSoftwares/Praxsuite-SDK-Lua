--[[
    Example: Basic RPG Game Backend
    
    This example shows how to use Praxsuite SDK as a backend for a Roblox RPG game.
    Features: player profiles, inventory, leaderboard, purchase validation.
    
    Setup:
    1. Drop PraxsuiteConfig module in ServerScriptService (see examples/PraxsuiteConfig.lua)
    2. Create tables in Praxsuite: player_profiles, inventory, game_events
    3. Create a sync endpoint: "validate-purchase"
    4. That's it — no Init() call needed!
]]

local Players = game:GetService("Players")
local Praxsuite = require(game.ServerScriptService.PraxsuiteSDK)

-- No Init() needed! SDK auto-discovers PraxsuiteConfig module.

-- ─── Player Join ─────────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
    -- Register player identity
    Praxsuite.Players.Identify(player, {
        metadata = {
            accountAge = player.AccountAge,
            premium = player.MembershipType ~= Enum.MembershipType.None,
        }
    })

    -- Load or create player profile
    local profiles = Praxsuite.Data.Query("player_profiles", {
        where = { roblox_id = player.UserId },
        limit = 1,
        asPlayer = player,
    })

    if #profiles == 0 then
        -- First time player — create profile
        Praxsuite.Data.Insert("player_profiles", {
            roblox_id = player.UserId,
            display_name = player.DisplayName,
            coins = 100,
            gems = 0,
            level = 1,
            xp = 0,
            created_at = os.time(),
        }, { asPlayer = player })

        -- Give starter inventory
        Praxsuite.Data.InsertMany("inventory", {
            { owner_id = player.UserId, item = "wooden_sword", quantity = 1, equipped = true },
            { owner_id = player.UserId, item = "health_potion", quantity = 3, equipped = false },
        }, { asPlayer = player })

        print("[Praxsuite] Created new profile for " .. player.DisplayName)
    else
        print("[Praxsuite] Loaded profile for " .. player.DisplayName .. " (Level " .. profiles[1].level .. ")")
    end
end)

-- ─── Player Leave ────────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player)
    -- Fire session-end event (processed by automation for analytics)
    Praxsuite.Endpoints.Fire("on-session-end", {
        player_id = player.UserId,
        timestamp = os.time(),
    })

    Praxsuite.Players.Forget(player)
end)

-- ─── Grant XP Function ───────────────────────────────────────────────────────
local function grantXP(player, amount)
    -- Update XP in database
    Praxsuite.Data.Update("player_profiles", {
        set = { xp = { increment = amount } },  -- Note: depends on backend support
        where = { roblox_id = player.UserId },
        asPlayer = player,
    })

    -- Log the event
    Praxsuite.Data.Insert("game_events", {
        player_id = player.UserId,
        event_type = "xp_gained",
        amount = amount,
        timestamp = os.time(),
    })
end

-- ─── Purchase Validation ─────────────────────────────────────────────────────
local function validatePurchase(player, productId, receiptInfo)
    local ok, result = pcall(function()
        return Praxsuite.Endpoints.Call("validate-purchase", {
            player_id = player.UserId,
            product_id = productId,
            receipt_token = receiptInfo.PurchaseId,
            price_paid = receiptInfo.CurrencySpent,
        }, { asPlayer = player })
    end)

    if ok and result.approved then
        return Enum.ProductPurchaseDecision.PurchaseGranted
    else
        warn("[Praxsuite] Purchase validation failed:", ok and result.reason or result)
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end

-- ─── Leaderboard ─────────────────────────────────────────────────────────────
local function getTopPlayers(limit)
    return Praxsuite.Data.Query("player_profiles", {
        select = { "display_name", "level", "xp", "coins" },
        orderBy = { { "level", "desc" }, { "xp", "desc" } },
        limit = limit or 10,
    })
end

-- ─── Inventory Check ─────────────────────────────────────────────────────────
local function getPlayerInventory(player)
    return Praxsuite.Data.Query("inventory", {
        where = { owner_id = player.UserId },
        orderBy = { "equipped", "desc" },
        asPlayer = player,
    })
end

-- ─── Export for other scripts ────────────────────────────────────────────────
return {
    grantXP = grantXP,
    validatePurchase = validatePurchase,
    getTopPlayers = getTopPlayers,
    getPlayerInventory = getPlayerInventory,
}
