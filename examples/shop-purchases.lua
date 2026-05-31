--[[
    Example: In-Game Shop with Purchase Validation
    
    Shows how to validate Roblox developer product purchases
    against a Praxsuite automation endpoint for fraud prevention.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Praxsuite = require(game.ServerScriptService.PraxsuiteSDK)

Praxsuite.Init({
    workspaceId = "YOUR_WORKSPACE_UUID",
    apiKeySecret = "PraxsuiteKey",
})

-- Product catalog (maps Roblox product IDs to your items)
local PRODUCTS = {
    [123456789] = { item = "speed_boost", duration = 300 },
    [987654321] = { item = "double_coins", duration = 600 },
    [111222333] = { item = "vip_pass", permanent = true },
}

-- Process receipt callback
local function processReceipt(receiptInfo)
    local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
    if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end

    local product = PRODUCTS[receiptInfo.ProductId]
    if not product then
        warn("[Shop] Unknown product: " .. receiptInfo.ProductId)
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    -- Validate with Praxsuite backend (anti-fraud + fulfillment)
    local ok, result = pcall(function()
        return Praxsuite.Endpoints.Call("process-purchase", {
            player_id = receiptInfo.PlayerId,
            product_id = receiptInfo.ProductId,
            purchase_id = receiptInfo.PurchaseId,
            currency_spent = receiptInfo.CurrencySpent,
            currency_type = receiptInfo.CurrencyType,
            item = product.item,
            duration = product.duration,
            permanent = product.permanent,
        }, { asPlayer = player })
    end)

    if ok and result and result.granted then
        -- Backend confirmed — grant the item
        print("[Shop] Purchase granted for " .. player.DisplayName .. ": " .. product.item)
        return Enum.ProductPurchaseDecision.PurchaseGranted
    else
        warn("[Shop] Purchase validation failed:", ok and (result and result.reason or "unknown") or tostring(result))
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end

MarketplaceService.ProcessReceipt = processReceipt
