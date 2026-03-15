------------------------------------------------------------------------
-- FarmTally
-- Tracks items gathered while farming with timer, gold tracking,
-- and Auctionator price integration.
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local ADDON_NAME    = "FarmTally"
local TRADE_GOODS   = Enum.ItemClass.Tradegoods
local VENDOR_TRASH  = "Vendor Trash"

local FRAME_W       = 300
local PAD           = 10
local HEADER_H      = 42
local ROW_H         = 44
local FOOTER_H      = 32
local ICON_SIZE     = 28
local CONTENT_W     = FRAME_W - PAD * 2
local MAX_ROWS      = 8
local SCROLL_STEP   = ROW_H

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local itemRows, itemOrder = {}, {}
local rowPool = {}
local lastTickTime = GetTime()
local timerTicker = nil
local cachedTotalGold = 0

------------------------------------------------------------------------
-- Forward declarations
------------------------------------------------------------------------
local ApplyPauseVisuals
local RefreshHUD
local ExcludeItem

------------------------------------------------------------------------
-- Debug
------------------------------------------------------------------------
local debugMode = false
local function dbg(...)
    if not debugMode then return end
    print("|cff999999FarmTally [debug]:|r", ...)
end

------------------------------------------------------------------------
-- Saved variable initialization
------------------------------------------------------------------------
local function InitDB()
    if not FarmTallyDB then FarmTallyDB = {} end
    local db = FarmTallyDB
    if db.count == nil then db.count = {} end
    if db.paused == nil then db.paused = true end
    if db.visible == nil then db.visible = true end
    if db.totalTime == nil then db.totalTime = 0 end
    if db.pos == nil then db.pos = {"CENTER", 0, 0} end
    if db.qAtlas == nil then db.qAtlas = {} end
    if db.trackedNames == nil then db.trackedNames = {} end
    if db.vendorTrash == nil then db.vendorTrash = { count = 0, copper = 0 } end
    if db.excludedNames == nil then db.excludedNames = {} end
    if db.goldRateMode == nil then db.goldRateMode = "hour" end
    if db.minimapPos == nil then db.minimapPos = 225 end
end

------------------------------------------------------------------------
-- Utility functions
------------------------------------------------------------------------
local function FormatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local QUALITY_FALLBACK = { "Q1:", "Q2:", "Q3:" }

local function FormatQuality(data)
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

local function HasAuctionator()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end

local function FormatGold(copper)
    if not copper or copper <= 0 then return "" end
    return GetCoinTextureString(copper)
end

local function SafeGetPrice(itemID)
    if not itemID or not HasAuctionator() then return nil end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, ADDON_NAME, itemID)
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

------------------------------------------------------------------------
-- Main frame
------------------------------------------------------------------------
local MainFrame = CreateFrame("Frame", "FarmTallyMain", UIParent, "BackdropTemplate")
MainFrame:SetSize(FRAME_W, HEADER_H + 30)
MainFrame:SetPoint("CENTER")
MainFrame:Hide()
MainFrame:SetMovable(true)
MainFrame:EnableMouse(true)
MainFrame:SetClampedToScreen(true)
MainFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = {left=3, right=3, top=3, bottom=3}
})
MainFrame:SetBackdropColor(0.05, 0.05, 0.1, 0.85)
MainFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
MainFrame:RegisterForDrag("LeftButton")
MainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
MainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    FarmTallyDB.pos = {point, x, y}
end)

------------------------------------------------------------------------
-- Minimap button (LibDBIcon-compatible style)
------------------------------------------------------------------------
local rad, deg, cos, sin, sqrt = math.rad, math.deg, math.cos, math.sin, math.sqrt
local atan2, max, min = math.atan2, math.max, math.min

local minimapShapes = {
    ["ROUND"]                 = {true,  true,  true,  true },
    ["SQUARE"]                = {false, false, false, false},
    ["CORNER-TOPLEFT"]        = {false, false, false, true },
    ["CORNER-TOPRIGHT"]       = {false, false, true,  false},
    ["CORNER-BOTTOMLEFT"]     = {false, true,  false, false},
    ["CORNER-BOTTOMRIGHT"]    = {true,  false, false, false},
    ["SIDE-LEFT"]             = {false, true,  false, true },
    ["SIDE-RIGHT"]            = {true,  false, true,  false},
    ["SIDE-TOP"]              = {false, false, true,  true },
    ["SIDE-BOTTOM"]           = {true,  true,  false, false},
    ["TRICORNER-TOPLEFT"]     = {false, true,  true,  true },
    ["TRICORNER-TOPRIGHT"]    = {true,  false, true,  true },
    ["TRICORNER-BOTTOMLEFT"]  = {true,  true,  false, true },
    ["TRICORNER-BOTTOMRIGHT"] = {true,  true,  true,  false},
}

local MINIMAP_OFFSET = 5

local minimapBtn = CreateFrame("Button", "FarmTallyMinimapButton", Minimap)
minimapBtn:SetSize(31, 31)
minimapBtn:SetFrameStrata("MEDIUM")
minimapBtn:SetFixedFrameStrata(true)
minimapBtn:SetFrameLevel(8)
minimapBtn:SetFixedFrameLevel(true)
minimapBtn:RegisterForClicks("anyUp")
minimapBtn:RegisterForDrag("LeftButton")
minimapBtn:SetHighlightTexture(136477)

minimapBtn.background = minimapBtn:CreateTexture(nil, "BACKGROUND")
minimapBtn.background:SetSize(24, 24)
minimapBtn.background:SetPoint("CENTER")
minimapBtn.background:SetTexture(136467)

minimapBtn.icon = minimapBtn:CreateTexture(nil, "ARTWORK")
minimapBtn.icon:SetSize(18, 18)
minimapBtn.icon:SetPoint("CENTER")
minimapBtn.icon:SetTexture("Interface\\AddOns\\FarmTally\\Artwork\\Icon")

minimapBtn.border = minimapBtn:CreateTexture(nil, "OVERLAY")
minimapBtn.border:SetSize(50, 50)
minimapBtn.border:SetPoint("TOPLEFT")
minimapBtn.border:SetTexture(136430)

local function UpdateMinimapPosition(pos)
    local angle = rad(pos or 225)
    local x, y, q = cos(angle), sin(angle), 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local quadTable = minimapShapes[shape] or minimapShapes["ROUND"]
    local w = (Minimap:GetWidth() / 2) + MINIMAP_OFFSET
    local h = (Minimap:GetHeight() / 2) + MINIMAP_OFFSET
    if quadTable[q] then
        x, y = x * w, y * h
    else
        local dw = sqrt(2 * w ^ 2) - 10
        local dh = sqrt(2 * h ^ 2) - 10
        x = max(-w, min(x * dw, w))
        y = max(-h, min(y * dh, h))
    end
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function UpdateMinimapIcon()
    minimapBtn.icon:SetDesaturated(FarmTallyDB.paused)
end

minimapBtn:SetScript("OnMouseDown", function(self) self.icon:SetSize(16, 16) end)
minimapBtn:SetScript("OnMouseUp", function(self) self.icon:SetSize(18, 18) end)

minimapBtn:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", function(btn)
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local pos = deg(atan2(cy - my, cx - mx)) % 360
        FarmTallyDB.minimapPos = pos
        UpdateMinimapPosition(pos)
    end)
end)
minimapBtn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self:UnlockHighlight()
    self.icon:SetSize(18, 18)
end)

minimapBtn:SetScript("OnClick", function()
    FarmTallyDB.visible = not MainFrame:IsShown()
    MainFrame:SetShown(FarmTallyDB.visible)
end)

minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Farm Tally")
    GameTooltip:AddLine("Click to toggle window", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag to reposition", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
minimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

------------------------------------------------------------------------
-- Header (timer + controls)
------------------------------------------------------------------------
local ControlBar = CreateFrame("Frame", nil, MainFrame)
ControlBar:SetSize(CONTENT_W, 24)
ControlBar:SetPoint("TOPLEFT", PAD, -8)

MainFrame.TimerText = ControlBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
MainFrame.TimerText:SetPoint("LEFT")
MainFrame.TimerText:SetText("00:00:00")
MainFrame.TimerText:SetTextColor(0.5, 0.5, 0.5)

local function CreateFlatButton(parent, size, texture, r, g, b)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetAllPoints()
    btn.tex:SetTexture(texture)
    btn.tex:SetDesaturated(true)
    btn.tex:SetVertexColor(r, g, b)
    btn.tex:SetAlpha(0.8)
    btn:SetScript("OnMouseDown", function(self)
        self.tex:ClearAllPoints()
        self.tex:SetPoint("CENTER", 1, -1)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self.tex:ClearAllPoints()
        self.tex:SetPoint("TOPLEFT")
        self.tex:SetPoint("BOTTOMRIGHT")
    end)
    return btn
end

local btnReset = CreateFlatButton(ControlBar, 18, "Interface\\TimeManager\\ResetButton", 0.7, 0.7, 0.7)
btnReset:SetPoint("RIGHT", ControlBar, "RIGHT", 0, 0)

local btnPause = CreateFlatButton(ControlBar, 18, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", 0.5, 0.9, 0.5)
btnPause:SetPoint("RIGHT", btnReset, "LEFT", -8, 0)

local headerSep = MainFrame:CreateTexture(nil, "ARTWORK")
headerSep:SetHeight(1)
headerSep:SetColorTexture(0.4, 0.4, 0.4, 0.4)
headerSep:SetPoint("TOPLEFT", PAD, -36)
headerSep:SetPoint("TOPRIGHT", -PAD, -36)

local emptyHint = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
emptyHint:SetPoint("CENTER", MainFrame, "CENTER", 0, -16)
emptyHint:SetTextColor(0.45, 0.45, 0.45)
emptyHint:SetFontHeight(11)
emptyHint:SetText("Hit start and begin gathering")
emptyHint:Hide()

------------------------------------------------------------------------
-- Footer (total gold + rate toggle)
------------------------------------------------------------------------
local footerSep = MainFrame:CreateTexture(nil, "ARTWORK")
footerSep:SetHeight(1)
footerSep:SetColorTexture(0.4, 0.4, 0.4, 0.4)
footerSep:SetPoint("BOTTOMLEFT", PAD, FOOTER_H - 4)
footerSep:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H - 4)
footerSep:Hide()

MainFrame.totalGoldText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
MainFrame.totalGoldText:SetPoint("BOTTOMLEFT", PAD, 8)
MainFrame.totalGoldText:SetTextColor(1, 0.82, 0, 1)
MainFrame.totalGoldText:SetFontHeight(11)

local btnRate = CreateFrame("Button", nil, MainFrame)
btnRate:SetPoint("BOTTOMRIGHT", -PAD, 4)
btnRate:SetSize(130, 20)
btnRate.text = btnRate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
btnRate.text:SetPoint("RIGHT")
btnRate.text:SetTextColor(0.7, 0.7, 0.7, 1)
btnRate.text:SetFontHeight(11)

------------------------------------------------------------------------
-- Scroll frame & item list
------------------------------------------------------------------------
local ScrollFrame = CreateFrame("ScrollFrame", nil, MainFrame)
ScrollFrame:SetPoint("TOPLEFT", PAD, -HEADER_H)
ScrollFrame:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H)
ScrollFrame:Hide()

local ListFrame = CreateFrame("Frame", nil, ScrollFrame)
ListFrame:SetSize(CONTENT_W, 1)
ScrollFrame:SetScrollChild(ListFrame)

local function OnScrollWheel(_, delta)
    local current = ScrollFrame:GetVerticalScroll()
    local maxScroll = max(0, ListFrame:GetHeight() - ScrollFrame:GetHeight())
    local newScroll = max(0, min(current - (delta * SCROLL_STEP), maxScroll))
    ScrollFrame:SetVerticalScroll(newScroll)
end

ScrollFrame:EnableMouseWheel(true)
ScrollFrame:SetScript("OnMouseWheel", OnScrollWheel)
ListFrame:EnableMouseWheel(true)
ListFrame:SetScript("OnMouseWheel", OnScrollWheel)

------------------------------------------------------------------------
-- Display logic
------------------------------------------------------------------------
local function UpdateFrameHeight()
    local n = #itemOrder
    if n == 0 then
        MainFrame:SetHeight(HEADER_H + 30)
        ScrollFrame:Hide()
        headerSep:Hide()
        footerSep:Hide()
        emptyHint:Show()
    else
        local visible = min(n, MAX_ROWS)
        MainFrame:SetHeight(HEADER_H + (visible * ROW_H) + FOOTER_H)
        ListFrame:SetSize(CONTENT_W, n * ROW_H)
        ScrollFrame:Show()
        headerSep:Show()
        footerSep:Show()
        emptyHint:Hide()
    end
end

local function UpdateGoldRate()
    if cachedTotalGold <= 0 or FarmTallyDB.totalTime <= 0 then
        btnRate.text:SetText("")
        return
    end
    local seconds = FarmTallyDB.totalTime
    if FarmTallyDB.goldRateMode == "min" then
        btnRate.text:SetText(FormatGold(math.floor(cachedTotalGold / (seconds / 60))) .. "/min")
    else
        btnRate.text:SetText(FormatGold(math.floor(cachedTotalGold / (seconds / 3600))) .. "/hr")
    end
end

local function UpdateSummary()
    cachedTotalGold = 0
    if HasAuctionator() then
        for _, data in pairs(FarmTallyDB.count) do
            local value = GetItemValue(data)
            if value then cachedTotalGold = cachedTotalGold + value end
        end
    end
    local vt = FarmTallyDB.vendorTrash
    if vt and vt.copper > 0 then
        cachedTotalGold = cachedTotalGold + vt.copper
    end
    MainFrame.totalGoldText:SetText(cachedTotalGold > 0 and FormatGold(cachedTotalGold) or "")
    UpdateGoldRate()
end

------------------------------------------------------------------------
-- Row pool
------------------------------------------------------------------------
local function AcquireRow()
    local row = table.remove(rowPool)
    if row then
        row:Show()
        return row
    end

    row = CreateFrame("Frame", nil, ListFrame)
    row:SetSize(CONTENT_W, ROW_H - 4)
    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", OnScrollWheel)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and self.itemName and ExcludeItem then
            ExcludeItem(self.itemName)
        end
    end)
    row:SetScript("OnEnter", function(self)
        if self.itemName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.itemName, 1, 1, 1)
            GameTooltip:AddLine("Right-click to disable tracking", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.sep = row:CreateTexture(nil, "ARTWORK")
    row.sep:SetHeight(1)
    row.sep:SetColorTexture(0.3, 0.3, 0.3, 0.3)
    row.sep:SetPoint("TOPLEFT", row, "TOPLEFT", ICON_SIZE + 6, 2)
    row.sep:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 2)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -2)
    row.nameText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -45, -2)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetFontHeight(12)
    row.nameText:SetWordWrap(false)

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.countText:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
    row.countText:SetJustifyH("RIGHT")
    row.countText:SetFontHeight(13)

    row.qualityText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.qualityText:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 2)
    row.qualityText:SetTextColor(0.75, 0.75, 0.75, 1)
    row.qualityText:SetFontHeight(10)

    row.goldText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.goldText:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
    row.goldText:SetJustifyH("RIGHT")
    row.goldText:SetTextColor(1, 0.82, 0, 0.9)
    row.goldText:SetFontHeight(10)

    return row
end

local function ReleaseRow(row)
    row:Hide()
    row:ClearAllPoints()
    row.itemName = nil
    table.insert(rowPool, row)
end

local function PlaceRow(row, idx, name, icon, nameColor)
    row:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_H)
    row.itemName = name
    row.icon:SetTexture(icon or "Interface\\ICONS\\INV_Misc_Fish_02")
    row.nameText:SetText(name)
    row.nameText:SetTextColor(unpack(nameColor or {1, 1, 1}))
    row.sep:SetShown(idx > 1)
    itemOrder[idx] = name
    itemRows[name] = row
end

------------------------------------------------------------------------
-- RefreshHUD — rebuilds sorted display
------------------------------------------------------------------------
RefreshHUD = function()
    -- Release all rows
    for _, row in pairs(itemRows) do ReleaseRow(row) end
    itemRows, itemOrder = {}, {}

    -- Collect and sort items (gold desc, then count desc, then name)
    local sorted = {}
    for name, data in pairs(FarmTallyDB.count) do
        sorted[#sorted + 1] = { name = name, data = data, gold = GetItemValue(data) }
    end
    table.sort(sorted, function(a, b)
        if a.gold and b.gold then return a.gold > b.gold end
        if a.gold then return true end
        if b.gold then return false end
        if a.data.amount ~= b.data.amount then return a.data.amount > b.data.amount end
        return a.name < b.name
    end)

    -- Create rows in sorted order
    for _, entry in ipairs(sorted) do
        local row = AcquireRow()
        local idx = #itemOrder + 1
        PlaceRow(row, idx, entry.name, entry.data.icon)
        row.countText:SetText(tostring(entry.data.amount))
        row.qualityText:SetText(FormatQuality(entry.data))
        row.goldText:SetText(entry.gold and FormatGold(entry.gold) or "")
    end

    -- Vendor trash always last
    local vt = FarmTallyDB.vendorTrash
    if vt and vt.count > 0 then
        local row = AcquireRow()
        local idx = #itemOrder + 1
        PlaceRow(row, idx, VENDOR_TRASH, "Interface\\ICONS\\INV_Misc_Coin_17", {0.62, 0.62, 0.62})
        row.countText:SetText(tostring(vt.count))
        row.qualityText:SetText("")
        row.goldText:SetText(FormatGold(vt.copper))
    end

    ScrollFrame:SetVerticalScroll(0)
    UpdateFrameHeight()
    UpdateSummary()
end

------------------------------------------------------------------------
-- Timer
------------------------------------------------------------------------
local function UpdateTimer()
    local now = GetTime()
    FarmTallyDB.totalTime = (FarmTallyDB.totalTime or 0) + (now - lastTickTime)
    lastTickTime = now
    MainFrame.TimerText:SetText(FormatTime(FarmTallyDB.totalTime))
    UpdateGoldRate()
end

local function StartTimer()
    if timerTicker then return end
    lastTickTime = GetTime()
    timerTicker = C_Timer.NewTicker(1, UpdateTimer)
end

local function StopTimer()
    if timerTicker then
        timerTicker:Cancel()
        timerTicker = nil
    end
end

------------------------------------------------------------------------
-- Session controls
------------------------------------------------------------------------
local function Reset()
    dbg("Reset: rows=" .. #itemOrder)
    FarmTallyDB.count = {}
    FarmTallyDB.vendorTrash = { count = 0, copper = 0 }
    FarmTallyDB.excludedNames = {}
    FarmTallyDB.totalTime = 0
    FarmTallyDB.qAtlas = {}
    FarmTallyDB.paused = true
    StopTimer()
    lastTickTime = GetTime()
    for _, row in pairs(itemRows) do ReleaseRow(row) end
    itemRows, itemOrder = {}, {}
    MainFrame.TimerText:SetText("00:00:00")
    MainFrame.totalGoldText:SetText("")
    btnRate.text:SetText("")
    cachedTotalGold = 0
    ScrollFrame:SetVerticalScroll(0)
    UpdateFrameHeight()
    ApplyPauseVisuals()
end

ApplyPauseVisuals = function()
    if FarmTallyDB.paused then
        btnPause.tex:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        btnPause.tex:SetVertexColor(0.5, 0.9, 0.5)
        MainFrame.TimerText:SetTextColor(0.5, 0.5, 0.5)
        emptyHint:SetText("Hit start and begin gathering")
    else
        btnPause.tex:SetTexture("Interface\\TimeManager\\PauseButton")
        btnPause.tex:SetVertexColor(0.9, 0.9, 0.4)
        MainFrame.TimerText:SetTextColor(1, 0.82, 0)
        emptyHint:SetText("Gathering... loot will appear here")
    end
    UpdateMinimapIcon()
end

ExcludeItem = function(name)
    dbg("ExcludeItem:", name)
    FarmTallyDB.excludedNames[name] = true
    if name == VENDOR_TRASH then
        FarmTallyDB.vendorTrash = { count = 0, copper = 0 }
    else
        FarmTallyDB.count[name] = nil
    end
    RefreshHUD()
end

------------------------------------------------------------------------
-- Button scripts
------------------------------------------------------------------------
local function ShowPauseTooltip(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    if FarmTallyDB.paused then
        GameTooltip:SetText("Start tracking")
        GameTooltip:AddLine("Begin counting looted items and tracking time", 0.7, 0.7, 0.7, true)
    else
        GameTooltip:SetText("Pause tracking")
        GameTooltip:AddLine("Stop counting new items and pause the timer", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

btnPause:SetScript("OnClick", function(self)
    FarmTallyDB.paused = not FarmTallyDB.paused
    if FarmTallyDB.paused then
        StopTimer()
    else
        StartTimer()
    end
    ApplyPauseVisuals()
    ShowPauseTooltip(self)
end)
btnPause:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    ShowPauseTooltip(self)
end)
btnPause:SetScript("OnLeave", function(self)
    self.tex:SetAlpha(0.8)
    GameTooltip:Hide()
end)

btnReset:SetScript("OnClick", Reset)
btnReset:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Reset session")
    GameTooltip:AddLine("Clear all gathered items and reset the timer", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
btnReset:SetScript("OnLeave", function(self)
    self.tex:SetAlpha(0.8)
    GameTooltip:Hide()
end)

btnRate:SetScript("OnClick", function()
    FarmTallyDB.goldRateMode = FarmTallyDB.goldRateMode == "min" and "hour" or "min"
    UpdateGoldRate()
end)
btnRate:SetScript("OnEnter", function(self)
    self.text:SetTextColor(1, 1, 1, 1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Click to toggle gold/min and gold/hr")
    GameTooltip:Show()
end)
btnRate:SetScript("OnLeave", function(self)
    self.text:SetTextColor(0.7, 0.7, 0.7, 1)
    GameTooltip:Hide()
end)

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("PLAYER_LOGIN")
EventFrame:RegisterEvent("LOOT_OPENED")
EventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        InitDB()
        MainFrame:ClearAllPoints()
        MainFrame:SetPoint(unpack(FarmTallyDB.pos))
        MainFrame.TimerText:SetText(FormatTime(FarmTallyDB.totalTime))
        ApplyPauseVisuals()
        UpdateMinimapPosition(FarmTallyDB.minimapPos)
        if FarmTallyDB.visible then MainFrame:Show() end
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        if not FarmTallyDB.paused then
            StartTimer()
        end
        RefreshHUD()

    elseif event == "LOOT_OPENED" and not FarmTallyDB.paused then
        for slot = 1, GetNumLootItems() do
            local link = GetLootSlotLink(slot)
            if link then
                local _, _, lootQuantity = GetLootSlotInfo(slot)
                local name, _, quality, _, _, _, _, _, _, icon, sellPrice, classID = GetItemInfo(link)
                if not name then
                    name = link:match("%[(.-)%]")
                    local id = tonumber(link:match("item:(%d+)"))
                    if id then _, _, _, _, icon, classID = GetItemInfoInstant(id) end
                end
                dbg("Loot:", tostring(name), "q=" .. tostring(quality), "class=" .. tostring(classID))

                if quality == 0 and sellPrice and sellPrice > 0 and not FarmTallyDB.excludedNames[VENDOR_TRASH] then
                    local vt = FarmTallyDB.vendorTrash
                    local qty = lootQuantity or 1
                    vt.count = vt.count + qty
                    vt.copper = vt.copper + (sellPrice * qty)

                elseif name and (classID == TRADE_GOODS or FarmTallyDB.trackedNames[name]) and not FarmTallyDB.excludedNames[name] then
                    local data = FarmTallyDB.count[name]
                    if not data then
                        data = {icon = icon, amount = 0}
                        FarmTallyDB.count[name] = data
                    end
                    data.amount = data.amount + (lootQuantity or 1)

                    local itemID = tonumber(link:match("item:(%d+)"))
                    data.itemID = data.itemID or itemID
                    if C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityInfo then
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
        end
        RefreshHUD()
    end
end)

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

    if command == "debug" then
        debugMode = not debugMode
        print("|cff00ff00FarmTally:|r Debug " .. (debugMode and "|cff44ff44ON|r" or "|cffff4444OFF|r"))
        if debugMode then
            print("|cff999999  rows=" .. #itemOrder, "paused=" .. tostring(FarmTallyDB.paused),
                "height=" .. math.floor(MainFrame:GetHeight()),
                "visible=" .. tostring(MainFrame:IsShown()),
                "poolSize=" .. #rowPool .. "|r")
        end
    elseif command == "reset" then
        Reset()
    elseif command == "rate" then
        FarmTallyDB.goldRateMode = FarmTallyDB.goldRateMode == "min" and "hour" or "min"
        UpdateGoldRate()
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
            ExcludeItem(name)
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
    else
        print("|cff00ff00FarmTally:|r Commands:")
        print("  /fta — toggle window")
        print("  /fta reset — reset session")
        print("  /fta rate — toggle gold/min or gold/hr")
        print("  /fta add [item] — track a custom item")
        print("  /fta remove [item] — stop tracking custom item")
        print("  /fta exclude [item] — exclude from session")
        print("  /fta list — show tracked & excluded items")
        print("  /fta debug — toggle debug logging")
    end
end
