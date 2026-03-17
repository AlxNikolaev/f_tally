------------------------------------------------------------------------
-- FarmTally - Core
-- Constants, DB initialization, utility functions, price helpers.
------------------------------------------------------------------------
local ADDON_NAME, ns = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
ns.ADDON_NAME    = ADDON_NAME
ns.TRADE_GOODS   = Enum.ItemClass.Tradegoods
ns.VENDOR_TRASH  = "Vendor Trash"
ns.BOE_ITEMS     = "BoE Items"
ns.BOP_ITEMS     = "BoP Items"
ns.BIND_ON_EQUIP = 2
ns.BIND_ON_PICKUP = 1

ns.FRAME_W       = 300
ns.PAD           = 10
ns.HEADER_H      = 42
ns.ROW_H         = 44
ns.CAT_ROW_H     = 22
ns.CAT_INDENT    = 20
ns.FOOTER_H      = 32
ns.ICON_SIZE     = 28
ns.CONTENT_W     = ns.FRAME_W - ns.PAD * 2
ns.MAX_ROWS      = 8
ns.SCROLL_STEP   = ns.ROW_H
ns.FALLBACK_ICON = 134400 -- INV_Misc_QuestionMark

------------------------------------------------------------------------
-- Debug
------------------------------------------------------------------------
ns.debugMode = false

function ns.dbg(...)
    if not ns.debugMode then return end
    print("|cff999999FarmTally [debug]:|r", ...)
end

------------------------------------------------------------------------
-- Saved variable initialization
------------------------------------------------------------------------
function ns.InitDB()
    if not FarmTallyDB then FarmTallyDB = {} end
    local db = FarmTallyDB
    if db.count == nil then db.count = {} end
    if db.paused == nil then db.paused = true end
    if db.visible == nil then db.visible = true end
    if db.totalTime == nil then db.totalTime = 0 end
    if db.pos == nil then db.pos = {"CENTER", 0, 0} end
    if db.qAtlas == nil then db.qAtlas = {} end
    if db.trackedNames == nil then db.trackedNames = {} end
    db.vendorTrash = nil -- stale field, removed in 1.2
    if db.collapsed == nil then db.collapsed = {} end
    if db.excludedNames == nil then db.excludedNames = {} end
    if db.goldRateMode == nil then db.goldRateMode = "hour" end
    if db.minimapPos == nil then db.minimapPos = 225 end
    if db.priceMode == nil or type(db.priceMode) == "string" then db.priceMode = {} end -- migrated from string in 1.1
end

------------------------------------------------------------------------
-- Utility functions
------------------------------------------------------------------------
function ns.FormatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local QUALITY_FALLBACK = { "Q1:", "Q2:", "Q3:" }

function ns.FormatQuality(data)
    if not data.q then return "" end
    local parts = {}
    local qAtlas = FarmTallyDB.qAtlas or {}
    for tier = 1, 3 do
        if data.q[tier] and data.q[tier] > 0 then
            local icon = qAtlas[tier] and CreateAtlasMarkup(qAtlas[tier], 16, 14) or QUALITY_FALLBACK[tier]
            parts[#parts + 1] = icon .. " " .. data.q[tier]
        end
    end
    return table.concat(parts, "   ")
end

function ns.HasAuctionator()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end

function ns.FormatGold(copper)
    if not copper or copper <= 0 then return "" end
    if copper >= 10000 then
        return GetCoinTextureString(math.floor(copper / 10000) * 10000)
    end
    return GetCoinTextureString(copper)
end

function ns.SafeGetPrice(itemID)
    if not itemID or not ns.HasAuctionator() then return nil end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, ns.ADDON_NAME, itemID)
    if ok then return price end
    ns.dbg("SafeGetPrice failed:", itemID, price)
    return nil
end

function ns.GetCategoryName(data)
    if data.isVendorTrash then return ns.VENDOR_TRASH end
    if data.isBoE then return ns.BOE_ITEMS end
    if data.isBoP then return ns.BOP_ITEMS end
    return data.itemSubType or "Other"
end

function ns.GetVendorPrice(data)
    if not data.itemID then return nil end
    local sellPrice = data.sellPrice
    if not sellPrice then
        sellPrice = select(11, C_Item.GetItemInfo(data.itemID))
    end
    if sellPrice and sellPrice > 0 then
        return sellPrice * data.amount
    end
    return nil
end

function ns.SnapshotBags()
    local snap = {}
    for bag = 0, 5 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local cInfo = C_Container.GetContainerItemInfo(bag, slot)
            if cInfo and cInfo.itemID then
                snap[cInfo.itemID] = (snap[cInfo.itemID] or 0) + cInfo.stackCount
            end
        end
    end
    return snap
end

function ns.GetAHPrice(data)
    if not ns.HasAuctionator() then return nil end
    local total = 0
    if data.q and data.qIDs then
        for tier = 1, 3 do
            if data.q[tier] and data.q[tier] > 0 and data.qIDs[tier] then
                local price = ns.SafeGetPrice(data.qIDs[tier])
                if price then total = total + price * data.q[tier] end
            end
        end
    end
    if total == 0 and data.itemID then
        local price = ns.SafeGetPrice(data.itemID)
        if price then total = price * data.amount end
    end
    return total > 0 and total or nil
end

function ns.GetItemValue(data)
    -- BoP: always vendor (can't AH)
    if data.isBoP then return ns.GetVendorPrice(data) end
    local catName = ns.GetCategoryName(data)
    local mode = FarmTallyDB.priceMode[catName] or "both"
    local vendor = ns.GetVendorPrice(data)
    local ah = ns.GetAHPrice(data)
    if mode == "vendor" then return vendor end
    if mode == "ah" then return ah or vendor end
    -- "both": best value for sorting/total
    if ah and vendor then return math.max(ah, vendor) end
    return ah or vendor
end
