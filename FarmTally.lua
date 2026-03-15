-- 1. БАЗА ДАННЫХ И НАСТРОЙКИ
FarmTallyDB = FarmTallyDB or { count = {}, paused = true, visible = true, totalTime = 0, pos = {"CENTER", 0, 0}, qAtlas = {} }

local FishNames = {
    ["Гуппи-живодер"] = true,
    ["Корнекраб"] = true,
    ["Маназмеерыба"] = true,
    ["Рысевка"] = true,
    ["Син'дорайский роевик"] = true,
    ["Восстановленная рыба-певунья"] = true,
    ["Грибочешуйчатая щука"] = true,
    ["Мерцающая иглоспинка"] = true,
    ["Мерцающая сирена"] = true,
    ["Мягкий светоплав"] = true,
    ["Пустоокунь"] = true,
    ["Солнечная колодезница"] = true,
    ["Цветохвостая минога"] = true,
    ["Зловещий осьминог"] = true,
    ["Искаженная ведуница"] = true,
    ["Искаженная тетра"] = true,
    ["Кровавый охотник"] = true,
    ["Нуль-рыба Бездны"] = true,
    ["Счастливый лоа"] = true,
    ["Форель Вечной Песни"] = true,
    ["Arcane Wyrmfish"] = true,
    ["Lynxfish"] = true,
    ["Root Crab"] = true,
    ["Sin'dorei Swarmer"] = true,
    ["Blood Hunter"] = true,
    ["Bloomtail Minnow"] = true,
    ["Shimmer Spinefish"] = true,
    ["Fungalskin Pike"] = true,
    ["Gore Guppy"] = true,
    ["Restored Songfish"] = true,
    ["Shimmersiren"] = true,
    ["Sunwell Fish"] = true,
    ["Tender Lumifin"] = true,
    ["Eversong Trout"] = true,
    ["Hollow Grouper"] = true,
    ["Lucky Loa"] = true,
    ["Null Voidfish"] = true,
    ["Ominous Octopus"] = true,
    ["Warping Wise"] = true,


    ["Сверкающая медная руда"] = true,
    ["Яркая серебряная руда"] = true,
    ["Теневая оловянная руда"] = true,
    ["Ослепительный торий"] = true,
    ["Refulgent Copper Ore"] = true,
    ["Dazzling Thorium"] = true,
    ["Umbral Tin Ore"] = true,
    ["Brilliant Silver Ore"] = true
}

local HUDRows, HUDOrder = {}, {}
local lastTickTime = GetTime()

local function FormatTime(seconds)
    local h, m, s = math.floor(seconds/3600), math.floor((seconds%3600)/60), math.floor(seconds%60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

-- 2. ОСНОВНОЕ ОКНО
local MainFrame = CreateFrame("Frame", "FarmTallyMain", UIParent, "BackdropTemplate")
MainFrame:SetSize(280, 60)
MainFrame:SetPoint(unpack(FarmTallyDB.pos))
MainFrame:SetMovable(true)
MainFrame:EnableMouse(true)
MainFrame:SetClampedToScreen(true)
MainFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = nil,
    tile = true, tileSize = 20, edgeSize = 20,
    insets = {left=4, right=4, top=4, bottom=4}
})
MainFrame:SetBackdropColor(0, 0, 0, 0.7)
if not FarmTallyDB.visible then MainFrame:Hide() end

-- 3. ЗАГОЛОВОК И ПЕРЕТАСКИВАНИЕ
local Title = CreateFrame("Frame", nil, MainFrame)
Title:SetPoint("TOPLEFT", 0, 22)
Title:SetPoint("TOPRIGHT", 0, 22)
Title:SetHeight(22)
Title.Text = Title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
Title.Text:SetPoint("LEFT", 8, 0)
Title.Text:SetText("Farm Tally")
Title.Text:SetTextColor(1, 1, 1, 1)
Title.Text:SetFontHeight(16)

MainFrame:RegisterForDrag("LeftButton")
Title:EnableMouse(true)
Title:SetScript("OnMouseDown", function() MainFrame:StartMoving() end)
Title:SetScript("OnMouseUp", function()
    MainFrame:StopMovingOrSizing()
    local point, _, _, x, y = MainFrame:GetPoint()
    FarmTallyDB.pos = {point, x, y}
end)

local CloseBtn = CreateFrame("Button", nil, Title, "UIPanelCloseButton")
CloseBtn:SetSize(22, 22)
CloseBtn:SetPoint("RIGHT", 0, 0)
CloseBtn:SetScript("OnClick", function() MainFrame:Hide(); FarmTallyDB.visible = false end)

-- Title auto-hide
Title:Hide()
local function HideTitleIfNeeded()
    C_Timer.After(0.1, function()
        if not MainFrame:IsMouseOver() and not Title:IsMouseOver() then
            Title:Hide()
        end
    end)
end
MainFrame:SetScript("OnEnter", function() Title:Show() end)
MainFrame:SetScript("OnLeave", HideTitleIfNeeded)
Title:SetScript("OnEnter", function() Title:Show() end)
Title:SetScript("OnLeave", HideTitleIfNeeded)

-- 4. ПАНЕЛЬ УПРАВЛЕНИЯ (в линию: Таймер - Старт - Ресет)
local ControlBar = CreateFrame("Frame", nil, MainFrame)
ControlBar:SetSize(270, 30)
ControlBar:SetPoint("TOPLEFT", 10, -8)

MainFrame.TimerText = ControlBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
MainFrame.TimerText:SetPoint("LEFT", 0, 0)
MainFrame.TimerText:SetText(FormatTime(FarmTallyDB.totalTime))

-- Кнопка Старт/Пауза (иконка)
local btnPause = CreateFrame("Button", nil, ControlBar)
btnPause:SetSize(20, 20)
btnPause:SetPoint("LEFT", MainFrame.TimerText, "RIGHT", 15, 0)
btnPause.tex = btnPause:CreateTexture(nil, "ARTWORK")
btnPause.tex:SetAllPoints()
btnPause.tex:SetTexture(FarmTallyDB.paused and "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up" or "Interface\\TimeManager\\PauseButton")

btnPause:SetScript("OnClick", function()
    FarmTallyDB.paused = not FarmTallyDB.paused
    lastTickTime = GetTime()
    btnPause.tex:SetTexture(FarmTallyDB.paused and "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up" or "Interface\\TimeManager\\PauseButton")
end)

-- Кнопка Ресет (иконка)
local btnReset = CreateFrame("Button", nil, ControlBar)
btnReset:SetSize(20, 20)
btnReset:SetPoint("LEFT", btnPause, "RIGHT", 10, 0)
btnReset.tex = btnReset:CreateTexture(nil, "ARTWORK")
btnReset.tex:SetAllPoints()
btnReset.tex:SetTexture("Interface\\TimeManager\\ResetButton")

-- 5. QUALITY HELPERS
local QUALITY_FALLBACK = { "Q1:", "Q2:", "Q3:" }

local function FormatCount(data)
    if not data.q then
        return tostring(data.amount)
    end
    local parts = {}
    local qAtlas = FarmTallyDB.qAtlas or {}
    for tier = 1, 3 do
        if data.q[tier] and data.q[tier] > 0 then
            local icon = qAtlas[tier] and CreateAtlasMarkup(qAtlas[tier], 14, 12) or QUALITY_FALLBACK[tier]
            parts[#parts + 1] = icon .. data.q[tier]
        end
    end
    if #parts > 0 then
        return data.amount .. "  " .. table.concat(parts, " ")
    end
    return tostring(data.amount)
end

-- 6. PRICING HELPERS (Auctionator)
local cachedTotalGold = 0

local function HasAuctionator()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end

local function FormatGold(copper)
    if not copper or copper <= 0 then return "" end
    return GetCoinTextureString(copper)
end

local function SafeGetPrice(itemID)
    if not itemID or not HasAuctionator() then return nil end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "FarmTally", itemID)
    if ok then return price end
    return nil
end

local function GetItemValue(data)
    if not HasAuctionator() then return nil end
    local total = 0
    if data.q and data.qIDs then
        for tier = 1, 3 do
            if data.q[tier] and data.q[tier] > 0 and data.qIDs[tier] then
                local price = SafeGetPrice(data.qIDs[tier])
                if price then total = total + price * data.q[tier] end
            end
        end
    end
    if total == 0 and data.itemID then
        local price = SafeGetPrice(data.itemID)
        if price then total = price * data.amount end
    end
    return total > 0 and total or nil
end

-- Summary bar (bottom)
MainFrame.totalGoldText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
MainFrame.totalGoldText:SetPoint("BOTTOMLEFT", MainFrame, "BOTTOMLEFT", 10, 8)
MainFrame.totalGoldText:SetTextColor(1, 0.82, 0, 1)
MainFrame.totalGoldText:SetFontHeight(11)

MainFrame.gpmText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
MainFrame.gpmText:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -10, 8)
MainFrame.gpmText:SetTextColor(0.7, 0.7, 0.7, 1)
MainFrame.gpmText:SetFontHeight(11)

local function UpdateGPM()
    if cachedTotalGold <= 0 then
        MainFrame.gpmText:SetText("")
        return
    end
    local minutes = FarmTallyDB.totalTime / 60
    if minutes > 0 then
        MainFrame.gpmText:SetText(FormatGold(math.floor(cachedTotalGold / minutes)) .. "/min")
    end
end

local function UpdateSummary()
    if not HasAuctionator() then
        MainFrame.totalGoldText:SetText("")
        MainFrame.gpmText:SetText("")
        cachedTotalGold = 0
        return
    end
    cachedTotalGold = 0
    for _, data in pairs(FarmTallyDB.count) do
        local value = GetItemValue(data)
        if value then cachedTotalGold = cachedTotalGold + value end
    end
    MainFrame.totalGoldText:SetText(cachedTotalGold > 0 and FormatGold(cachedTotalGold) or "")
    UpdateGPM()
end

-- 7. СПИСОК РЫБ
local ListFrame = CreateFrame("Frame", nil, MainFrame)
ListFrame:SetPoint("TOPLEFT", 10, -40)
ListFrame:SetSize(260, 1)

local function CreateFishRow(name, icon)
    if HUDRows[name] then return HUDRows[name] end
    local row = CreateFrame("Frame", nil, ListFrame)
    row:SetSize(260, 34)
    table.insert(HUDOrder, name)
    row:SetPoint("TOPLEFT", 0, -(#HUDOrder - 1) * 38)

    row.icon = row:CreateTexture(nil, "BACKGROUND")
    row.icon:SetSize(24, 24); row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetTexture(icon or "Interface\\ICONS\\INV_Misc_Fish_02")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 5, 0); row.nameText:SetText(name)
    row.nameText:SetTextColor(1, 1, 1, 1)
    row.nameText:SetFontHeight(12)

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.countText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -5, -2)
    row.countText:SetFontHeight(12)

    row.goldText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.goldText:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -5, 2)
    row.goldText:SetTextColor(1, 0.82, 0, 1)
    row.goldText:SetFontHeight(10)

    HUDRows[name] = row
    MainFrame:SetHeight(50 + (#HUDOrder * 38) + 25)
    return row
end

local function RefreshHUD()
    for name, data in pairs(FarmTallyDB.count) do
        local row = CreateFishRow(name, data.icon)
        row.countText:SetText(FormatCount(data))
        local value = GetItemValue(data)
        row.goldText:SetText(value and FormatGold(value) or "")
    end
    UpdateSummary()
end

local function Reset()
    FarmTallyDB.count, FarmTallyDB.totalTime, FarmTallyDB.qAtlas = {}, 0, {}
    lastTickTime = GetTime()
    for _, row in pairs(HUDRows) do row:Hide() end
    HUDRows, HUDOrder = {}, {}
    MainFrame.TimerText:SetText("00:00:00")
    MainFrame.totalGoldText:SetText("")
    MainFrame.gpmText:SetText("")
    cachedTotalGold = 0
    MainFrame:SetHeight(60)
end
btnReset:SetScript("OnClick", Reset)

-- 8. ЛОГИКА СОБЫТИЙ
local function UpdateTimer()
    if FarmTallyDB.paused then lastTickTime = GetTime(); return end
    local now = GetTime()
    FarmTallyDB.totalTime = (FarmTallyDB.totalTime or 0) + (now - (lastTickTime or now))
    lastTickTime = now
    MainFrame.TimerText:SetText(FormatTime(FarmTallyDB.totalTime))
    UpdateGPM()
end

local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("LOOT_OPENED"); EventFrame:RegisterEvent("PLAYER_LOGIN")
EventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.NewTicker(1, UpdateTimer)
        RefreshHUD()
    elseif event == "LOOT_OPENED" and not FarmTallyDB.paused then
        for slot = 1, GetNumLootItems() do
            local link = GetLootSlotLink(slot)
            if link then
                local _, _, lootQuantity = GetLootSlotInfo(slot)
                local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(link)
                if name and FishNames[name] then
                    local data = FarmTallyDB.count[name]
                    if not data then
                        data = {icon = icon, amount = 0}
                        FarmTallyDB.count[name] = data
                    end
                    data.amount = data.amount + (lootQuantity or 1)
                    -- Quality tracking
                    local itemID = tonumber(link:match("item:(%d+)"))
                    data.itemID = data.itemID or itemID
                    local ok, qualityInfo = pcall(C_TradeSkillUI.GetItemReagentQualityInfo, link)
                    if ok and qualityInfo then
                        local tier = qualityInfo.quality
                        data.q = data.q or {0, 0, 0}
                        data.q[tier] = (data.q[tier] or 0) + (lootQuantity or 1)
                        data.qIDs = data.qIDs or {}
                        data.qIDs[tier] = itemID
                        FarmTallyDB.qAtlas = FarmTallyDB.qAtlas or {}
                        FarmTallyDB.qAtlas[tier] = qualityInfo.iconChat
                    end
                end
            end
        end
        RefreshHUD()
    end
end)

-- Команды
SLASH_FARMTALLY1 = "/farmtally"
SlashCmdList["FARMTALLY"] = function(msg)
    if msg == "reset" then Reset() else
        FarmTallyDB.visible = not MainFrame:IsShown()
        MainFrame:SetShown(FarmTallyDB.visible)
    end
end
