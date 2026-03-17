------------------------------------------------------------------------
-- FarmTally - Main
-- Events, loot processing, timer, slash commands.
------------------------------------------------------------------------
local _, ns = ...

local ADDON_NAME    = ns.ADDON_NAME
local TRADE_GOODS   = ns.TRADE_GOODS
local VENDOR_TRASH  = ns.VENDOR_TRASH
local BOE_ITEMS     = ns.BOE_ITEMS
local BOP_ITEMS     = ns.BOP_ITEMS
local BIND_ON_EQUIP = ns.BIND_ON_EQUIP
local BIND_ON_PICKUP = ns.BIND_ON_PICKUP
local dbg            = ns.dbg
local FormatTime     = ns.FormatTime
local MainFrame      = ns.MainFrame
local EventFrame

------------------------------------------------------------------------
-- Loot processing
-- Uses loot link captured from LOOT_READY for item info and tracking.
-- Sell prices for equipment come from bag links (loot links give scaled
-- values), resolved by a deferred UpdatePricesFromBags pass.
------------------------------------------------------------------------
local function ProcessLootItems(pendingItems)
    local changed = false
    local needsPriceUpdate = false
    dbg("ProcessLoot: items=" .. #pendingItems)

    for _, pending in ipairs(pendingItems) do
        local itemID = pending.itemID
        local added = pending.qty
        local link = pending.link

        local name, _, quality, _, _, _, itemSubType, _, _, icon, sellPrice, classID, _, bindType = C_Item.GetItemInfo(link)
        if not name then
            name = string.match(link, "%[(.-)%]")
            _, _, _, _, icon, classID = C_Item.GetItemInfoInstant(itemID)
        end
        dbg("  Loot:", tostring(name), "qty=" .. added, "q=" .. tostring(quality),
            "class=" .. tostring(classID), "bind=" .. tostring(bindType), "sell=" .. tostring(sellPrice))

        if not name or not classID then
            dbg("  -> No info for itemID:", tostring(itemID))
        else
            local shouldTrack = false
            if quality == 0 and sellPrice and sellPrice > 0 then
                shouldTrack = not FarmTallyDB.excludedNames[VENDOR_TRASH] and not FarmTallyDB.excludedNames[name]
            elseif classID == TRADE_GOODS
                or FarmTallyDB.trackedNames[name]
                or (bindType == BIND_ON_EQUIP and not FarmTallyDB.excludedNames[BOE_ITEMS])
                or (bindType == BIND_ON_PICKUP and quality and quality > 0 and not FarmTallyDB.excludedNames[BOP_ITEMS]) then
                shouldTrack = not FarmTallyDB.excludedNames[name]
            end

            if shouldTrack then
                local data = FarmTallyDB.count[name]
                local isNew = not data
                if not data then
                    data = {icon = icon, amount = 0}
                    FarmTallyDB.count[name] = data
                end
                data.amount = data.amount + added
                data.quality = quality or data.quality
                data.itemSubType = itemSubType or data.itemSubType
                if quality == 0 then data.isVendorTrash = true end
                if bindType == BIND_ON_EQUIP then data.isBoE = true end
                if bindType == BIND_ON_PICKUP then data.isBoP = true end
                data.itemID = data.itemID or itemID
                data.itemLink = link
                -- Only trust loot-link sell price for trade goods.
                -- All other items (equipment, junk weapons/armor) have level-scaled
                -- prices in loot links — defer to bag link lookup.
                if sellPrice and sellPrice > 0 and classID == TRADE_GOODS then
                    data.sellPrice = sellPrice
                else
                    needsPriceUpdate = true
                end

                local tag = data.isVendorTrash and "VT" or data.isBoE and "BoE" or data.isBoP and "BoP" or ""
                dbg("  -> Tracked:", name, isNew and "(new)" or "(update)", "amt=" .. data.amount, "id=" .. tostring(itemID), tag)

                if C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityInfo then
                    local ok, qualityInfo = pcall(C_TradeSkillUI.GetItemReagentQualityInfo, link)
                    if ok and qualityInfo then
                        local tier = qualityInfo.quality
                        data.q = data.q or {0, 0, 0}
                        data.q[tier] = (data.q[tier] or 0) + added
                        data.qIDs = data.qIDs or {}
                        data.qIDs[tier] = itemID
                        FarmTallyDB.qAtlas = FarmTallyDB.qAtlas or {}
                        FarmTallyDB.qAtlas[tier] = qualityInfo.iconChat
                    end
                end
                changed = true
            else
                dbg("  -> Skipped:", tostring(name))
            end
        end
    end

    if changed then
        dbg("ProcessLoot: done, refreshing HUD")
        ns.RefreshHUD()
        if needsPriceUpdate and not ns.pendingPriceUpdate then
            ns.pendingPriceUpdate = true
            priceRetryCount = 0
            EventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        end
    elseif #pendingItems > 0 then
        dbg("ProcessLoot: no new tracked items")
    end
end

------------------------------------------------------------------------
-- Deferred price update — scans bags for correct sell prices on
-- equipment items (loot links give level-scaled values).
-- Triggered by BAG_UPDATE_DELAYED after items land in bags.
------------------------------------------------------------------------
local PRICE_MAX_RETRIES = 3
local priceRetryCount = 0

function ns.CleanupPriceUpdate()
    if ns.pendingPriceUpdate then
        EventFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
        ns.pendingPriceUpdate = false
    end
    priceRetryCount = 0
end

function ns.UpdatePricesFromBags()
    dbg("PriceUpdate: scanning bags")
    local updated = false
    local stillMissing = false
    for name, data in pairs(FarmTallyDB.count) do
        if data.itemID and not data.sellPrice then
            local found = false
            for bag = 0, 5 do
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    local cInfo = C_Container.GetContainerItemInfo(bag, slot)
                    if cInfo and cInfo.itemID == data.itemID then
                        found = true
                        local bagLink = C_Container.GetContainerItemLink(bag, slot)
                        if bagLink then
                            local _, _, _, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(bagLink)
                            dbg("PriceUpdate:", name, "sell=" .. tostring(sellPrice))
                            if sellPrice and sellPrice > 0 then
                                data.sellPrice = sellPrice
                                data.itemLink = bagLink
                                updated = true
                            end
                        end
                        break
                    end
                end
                if data.sellPrice then break end
            end
            if not found then
                stillMissing = true
                dbg("PriceUpdate:", name, "not in bags")
            end
        end
    end
    if not stillMissing or priceRetryCount >= PRICE_MAX_RETRIES then
        EventFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
        ns.pendingPriceUpdate = false
        priceRetryCount = 0
    else
        priceRetryCount = priceRetryCount + 1
        dbg("PriceUpdate: " .. priceRetryCount .. "/" .. PRICE_MAX_RETRIES .. " retries, waiting for bags")
    end
    if updated then
        ns.RefreshHUD()
    end
end

------------------------------------------------------------------------
-- Timer
------------------------------------------------------------------------
local lastTickTime = GetTime()
local timerTicker = nil

local function UpdateTimer()
    local now = GetTime()
    FarmTallyDB.totalTime = (FarmTallyDB.totalTime or 0) + (now - lastTickTime)
    lastTickTime = now
    MainFrame.TimerText:SetText(FormatTime(FarmTallyDB.totalTime))
    ns.UpdateGoldRate()
end

function ns.StartTimer()
    if timerTicker then return end
    lastTickTime = GetTime()
    timerTicker = C_Timer.NewTicker(1, UpdateTimer)
end

function ns.StopTimer()
    if timerTicker then
        timerTicker:Cancel()
        timerTicker = nil
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
EventFrame = CreateFrame("Frame")
local lootProcessed = false
local pendingLootItems = nil

EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("PLAYER_LOGIN")
EventFrame:RegisterEvent("LOOT_READY")
EventFrame:RegisterEvent("LOOT_CLOSED")
EventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        ns.InitDB()
        ns.InitSettings()
        MainFrame:ClearAllPoints()
        MainFrame:SetPoint(unpack(FarmTallyDB.pos))
        MainFrame.TimerText:SetText(FormatTime(FarmTallyDB.totalTime))
        ns.ApplyPauseVisuals()
        ns.UpdateMinimapPosition(FarmTallyDB.minimapPos)
        if FarmTallyDB.visible then MainFrame:Show() end
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        if not FarmTallyDB.paused then
            ns.StartTimer()
        end
        ns.RefreshHUD()

    elseif event == "BAG_UPDATE_DELAYED" and ns.pendingPriceUpdate then
        ns.UpdatePricesFromBags()

    elseif event == "LOOT_CLOSED" then
        dbg("LOOT_CLOSED")
        lootProcessed = false
        local items = pendingLootItems
        pendingLootItems = nil
        if items and #items > 0 then
            ProcessLootItems(items)
        end

    elseif event == "LOOT_READY" and lootProcessed then
        dbg("LOOT_READY: blocked (duplicate)")

    elseif event == "LOOT_READY" and not lootProcessed and not FarmTallyDB.paused then
        lootProcessed = true
        pendingLootItems = {}
        local numItems = GetNumLootItems()
        dbg("LOOT_READY: slots=" .. numItems)
        for slot = 1, numItems do
            local link = GetLootSlotLink(slot)
            if link then
                local _, _, lootQuantity = GetLootSlotInfo(slot)
                local itemID = tonumber(string.match(link, "item:(%d+)"))
                local name = string.match(link, "%[(.-)%]")
                dbg("  Slot " .. slot .. ":", tostring(name), "qty=" .. tostring(lootQuantity))
                if itemID then
                    pendingLootItems[#pendingLootItems + 1] = { itemID = itemID, qty = lootQuantity or 1, link = link }
                end
            end
        end
    end
end)

------------------------------------------------------------------------
-- Mock data for testing
------------------------------------------------------------------------

--@do-not-package@
local function LoadMockData()
    ns.Reset()
    FarmTallyDB.paused = false
    ns.StartTimer()
    FarmTallyDB.totalTime = 754 -- ~12 min for rate display

    -- Quality tier atlas for crafting reagents
    FarmTallyDB.qAtlas = {
        [1] = "Professions-ChatIcon-Quality-Tier1",
        [2] = "Professions-ChatIcon-Quality-Tier2",
        [3] = "Professions-ChatIcon-Quality-Tier3",
    }

    local function icon(itemID)
        return C_Item.GetItemIconByID(itemID) or 134400
    end

    local function add(name, fields)
        fields.icon = icon(fields.itemID)
        FarmTallyDB.count[name] = fields
    end

    -- Cloth (trade goods subtype)
    add("Linen Cloth",     { amount = 42, quality = 1, itemID = 2589,  itemSubType = "Cloth", sellPrice = 13 })
    add("Wool Cloth",      { amount = 28, quality = 1, itemID = 2592,  itemSubType = "Cloth", sellPrice = 33 })
    add("Silk Cloth",      { amount = 15, quality = 1, itemID = 4306,  itemSubType = "Cloth", sellPrice = 150 })

    -- Herb (trade goods subtype, with quality tiers)
    add("Hochenblume",     { amount = 30, quality = 1, itemID = 191461, itemSubType = "Herb",
        q = {12, 10, 8}, qIDs = {191461, 191462, 191463} })

    -- Metal & Stone (trade goods subtype)
    add("Copper Ore",      { amount = 20, quality = 1, itemID = 2770,  itemSubType = "Metal & Stone", sellPrice = 10 })
    add("Tin Ore",         { amount = 8,  quality = 1, itemID = 2771,  itemSubType = "Metal & Stone", sellPrice = 25 })

    -- Elemental (trade goods subtype)
    add("Elemental Fire",  { amount = 3,  quality = 1, itemID = 7068,  itemSubType = "Elemental", sellPrice = 500 })
    add("Core of Earth",   { amount = 2,  quality = 1, itemID = 7075,  itemSubType = "Elemental", sellPrice = 400 })

    -- BoE Items
    add("Bandit Jerkin of the Aurora",  { amount = 1, quality = 2, itemID = 6582,   isBoE = true, itemSubType = "Leather", sellPrice = 463 })
    add("Noble's Robe",                 { amount = 1, quality = 3, itemID = 63345,  isBoE = true, itemSubType = "Cloth",   sellPrice = 199 })
    add("Sentry's Surcoat",            { amount = 1, quality = 2, itemID = 9832,   isBoE = true, itemSubType = "Mail",    sellPrice = 1250 })

    -- BoP Items
    add("Stolen Jailer's Greaves",     { amount = 1, quality = 3, itemID = 132569, isBoP = true, itemSubType = "Plate",  sellPrice = 1905 })
    add("Hogger's Trousers",           { amount = 1, quality = 3, itemID = 6180,   isBoP = true, itemSubType = "Cloth",  sellPrice = 882 })
    add("Cast Iron Waistplate",        { amount = 1, quality = 3, itemID = 151077, isBoP = true, itemSubType = "Plate",  sellPrice = 950 })

    -- Vendor Trash (grey items)
    add("Shoddy Blunderbuss",   { amount = 1, quality = 0, itemID = 2879,  isVendorTrash = true, itemSubType = "Gun",     sellPrice = 1096 })
    add("Broken Longsword",     { amount = 3, quality = 0, itemID = 2214,  isVendorTrash = true, itemSubType = "Sword",   sellPrice = 32 })
    add("Cracked Leather Belt", { amount = 2, quality = 0, itemID = 3363,  isVendorTrash = true, itemSubType = "Leather", sellPrice = 18 })
    add("Ruined Pelt",          { amount = 5, quality = 0, itemID = 3262,  isVendorTrash = true, itemSubType = "Other",   sellPrice = 8 })

    ns.ApplyPauseVisuals()
    ns.RefreshHUD()
    MainFrame:Show()
    FarmTallyDB.visible = true
    print("|cff00ff00FarmTally:|r Mock data loaded — all categories populated.")
end
--@end-do-not-package@

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_FARMTALLY1 = "/farmtally"
SLASH_FARMTALLY2 = "/fta"
SlashCmdList["FARMTALLY"] = function(msg)
    msg = strtrim(msg or "")
    if msg == "" then
        FarmTallyDB.visible = not MainFrame:IsShown()
        MainFrame:SetShown(FarmTallyDB.visible)
        return
    end

    local command, arg = msg:match("^(%S+)%s*(.-)%s*$")
    command = command:lower()

    --@do-not-package@
    if command == "debug" then
        ns.debugMode = not ns.debugMode
        print("|cff00ff00FarmTally:|r Debug " .. (ns.debugMode and "|cff44ff44ON|r" or "|cffff4444OFF|r"))
        if ns.debugMode then
            print("|cff999999  paused=" .. tostring(FarmTallyDB.paused),
                "height=" .. math.floor(MainFrame:GetHeight()),
                "visible=" .. tostring(MainFrame:IsShown()) .. "|r")
        end
        return
    elseif command == "mock" then
        LoadMockData()
        return
    end
    --@end-do-not-package@
    if command == "reset" then
        ns.Reset()
    elseif command == "rate" then
        FarmTallyDB.goldRateMode = FarmTallyDB.goldRateMode == "min" and "hour" or "min"
        ns.UpdateGoldRate()
        print("|cff00ff00FarmTally:|r Rate display: gold/" .. FarmTallyDB.goldRateMode)
    elseif command == "add" and arg ~= "" then
        local name = arg:match("%[(.-)%]") or arg
        if name ~= "" then
            FarmTallyDB.trackedNames[name] = true
            print("|cff00ff00FarmTally:|r Added '" .. name .. "' to tracked items.")
        end
    elseif command == "remove" and arg ~= "" then
        local name = arg:match("%[(.-)%]") or arg
        if FarmTallyDB.trackedNames[name] then
            FarmTallyDB.trackedNames[name] = nil
            print("|cff00ff00FarmTally:|r Removed '" .. name .. "'.")
        else
            print("|cff00ff00FarmTally:|r '" .. name .. "' is not in custom list.")
        end
    elseif command == "exclude" and arg ~= "" then
        local name = arg:match("%[(.-)%]") or arg
        if name ~= "" then
            ns.ExcludeItem(name)
            print("|cff00ff00FarmTally:|r Excluded '" .. name .. "' from this session.")
        end
    elseif command == "list" then
        print("|cff00ff00FarmTally:|r Custom tracked items:")
        local any = false
        for name in pairs(FarmTallyDB.trackedNames) do
            print("  - " .. name)
            any = true
        end
        if not any then print("  (none — trade goods are tracked automatically)") end
        if next(FarmTallyDB.excludedNames) then
            print("|cff00ff00FarmTally:|r Excluded this session:")
            for name in pairs(FarmTallyDB.excludedNames) do
                print("  - |cff999999" .. name .. "|r")
            end
        end
    elseif command == "settings" or command == "options" then
        if ns.settingsCategoryID then
            Settings.OpenToCategory(ns.settingsCategoryID)
        end
    else
        print("|cff00ff00FarmTally:|r Commands:")
        print("  /fta — toggle window")
        print("  /fta reset — reset session")
        print("  /fta rate — toggle gold/min or gold/hr")
        print("  /fta add [item] — track a custom item")
        print("  /fta remove [item] — stop tracking custom item")
        print("  /fta exclude [item] — exclude from session")
        print("  /fta list — show tracked & excluded items")
        --@do-not-package@
        print("  /fta debug — toggle debug logging")
        print("  /fta mock — load test data")
        --@end-do-not-package@
    end
end
