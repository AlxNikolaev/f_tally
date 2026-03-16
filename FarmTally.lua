------------------------------------------------------------------------
-- FarmTally
-- Tracks items gathered while farming with timer, gold tracking,
-- and Auctionator price integration.
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Class declarations
------------------------------------------------------------------------

---@class FarmTallyRow : Frame
---@field sep Texture
---@field icon Texture
---@field iconBorder Texture
---@field nameText FontString
---@field countText FontString
---@field qualityText FontString
---@field goldText FontString
---@field itemName string?

---@class FarmTallyMapBtn : Button
---@field background Texture
---@field icon Texture
---@field border Texture

---@class FarmTallyFilterRow : Frame
---@field text FontString
---@field removeBtn FarmTallyRemoveBtn

---@class FarmTallyRemoveBtn : Button
---@field tex Texture

---@class FarmTallyFilterContainer : Frame
---@field rows FarmTallyFilterRow[]
---@field title FontString?
---@field emptyHint FontString?

---@class FarmTallyFlatBtn : Button
---@field tex Texture

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local ADDON_NAME    = "FarmTally"
local TRADE_GOODS   = Enum.ItemClass.Tradegoods
local VENDOR_TRASH  = "Vendor Trash"
local BOE_ITEMS     = "BoE Items"
local BOP_ITEMS     = "BoP Items"
local BIND_ON_EQUIP = 2
local BIND_ON_PICKUP = 1

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

---@type FarmTallyRow[]
local rowPool = {}
local lastTickTime = GetTime()
local timerTicker = nil
local cachedTotalGold = 0
local settingsCategoryID

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
    if db.showQualityBorder == nil then db.showQualityBorder = true end
    if db.showQualityNameColor == nil then db.showQualityNameColor = false end
    if db.trackBoE == nil then db.trackBoE = false end
    if db.boeItems == nil then db.boeItems = { count = 0, copper = 0 } end
    if db.trackBoP == nil then db.trackBoP = false end
    if db.bopItems == nil then db.bopItems = { count = 0, copper = 0 } end
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

local frame = CreateFrame("Button", "FarmTallyMinimapButton", Minimap)
---@type FarmTallyMapBtn | Button
local minimapBtn = frame
minimapBtn:SetSize(31, 31)
minimapBtn:SetFrameStrata("MEDIUM")
minimapBtn:SetFixedFrameStrata(true)
minimapBtn:SetFrameLevel(8)
minimapBtn:SetFixedFrameLevel(true)
minimapBtn:RegisterForClicks("anyUp")
minimapBtn:RegisterForDrag("LeftButton")
minimapBtn:SetHighlightTexture(136477) --[[@as Texture]]

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

minimapBtn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
        if settingsCategoryID then
            if SettingsPanel:IsShown() then
                HideUIPanel(SettingsPanel)
            else
                Settings.OpenToCategory(settingsCategoryID)
            end
        end
    else
        FarmTallyDB.visible = not MainFrame:IsShown()
        MainFrame:SetShown(FarmTallyDB.visible)
    end
end)

minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Farm Tally")
    GameTooltip:AddLine("Click to toggle window", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click to open settings", 0.7, 0.7, 0.7)
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

---@return FarmTallyFlatBtn
local function CreateFlatButton(parent, size, texture, r, g, b)
    ---@class FarmTallyFlatBtn
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetAllPoints()
    btn.tex:SetTexture(texture)
    btn.tex:SetDesaturated(true)
    btn.tex:SetVertexColor(r, g, b)
    btn.tex:SetAlpha(0.8)
    btn:SetScript("OnMouseDown", function(self)
        ---@cast self FarmTallyFlatBtn
        self.tex:ClearAllPoints()
        self.tex:SetPoint("CENTER", 1, -1)
    end)
    btn:SetScript("OnMouseUp", function(self)
        ---@cast self FarmTallyFlatBtn
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
    local boe = FarmTallyDB.boeItems
    if boe and boe.copper > 0 then
        cachedTotalGold = cachedTotalGold + boe.copper
    end
    local bop = FarmTallyDB.bopItems
    if bop and bop.copper > 0 then
        cachedTotalGold = cachedTotalGold + bop.copper
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

---@return FarmTallyRow
local function AcquireRow()
    ---@type FarmTallyRow?
    local row = table.remove(rowPool)
    if row then
        row:Show()
        return row
    end


    local rowFrame = CreateFrame("Frame", nil, ListFrame)
    ---@cast frame FarmTallyRow
    row = rowFrame
    row:SetSize(CONTENT_W, ROW_H - 4)
    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", OnScrollWheel)
    row:SetScript("OnMouseUp", function(self, button)
        ---@cast self FarmTallyRow
        if button == "RightButton" and self.itemName and ExcludeItem then
            ExcludeItem(self.itemName)
        end
    end)
    row:SetScript("OnEnter", function(self)
        ---@cast self FarmTallyRow
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
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.iconBorder = row:CreateTexture(nil, "OVERLAY")
    row.iconBorder:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -2, 2)
    row.iconBorder:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 2, -2)
    row.iconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
    row.iconBorder:Hide()

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

---@param row FarmTallyRow
---@param idx integer
---@param name string
---@param icon any
---@param nameColor number[]?
---@param quality integer?
local function PlaceRow(row, idx, name, icon, nameColor, quality)
    row:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_H)
    row.itemName = name
    row.icon:SetTexture(icon or "Interface\\ICONS\\INV_Misc_Fish_02")
    row.nameText:SetText(name)
    if nameColor then
        row.nameText:SetTextColor(unpack(nameColor))
    elseif FarmTallyDB.showQualityNameColor and quality and quality > 1 then
        local r, g, b = GetItemQualityColor(quality)
        row.nameText:SetTextColor(r, g, b)
    else
        row.nameText:SetTextColor(1, 1, 1)
    end
    row.sep:SetShown(idx > 1)
    if FarmTallyDB.showQualityBorder and quality and quality > 1 then
        local r, g, b = GetItemQualityColor(quality)
        ---@cast r number
        ---@cast g number
        ---@cast b number
        row.iconBorder:SetVertexColor(r, g, b)
        row.iconBorder:Show()
    else
        row.iconBorder:Hide()
    end
    itemOrder[idx] = name
    itemRows[name] = row
end

------------------------------------------------------------------------
-- RefreshHUD
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
        PlaceRow(row, idx, entry.name, entry.data.icon, nil, entry.data.quality)
        row.countText:SetText(tostring(entry.data.amount))
        row.qualityText:SetText(FormatQuality(entry.data))
        row.goldText:SetText(entry.gold and FormatGold(entry.gold) or "")
    end

    -- BoE items section
    local boe = FarmTallyDB.boeItems
    if boe and boe.count > 0 then
        local row = AcquireRow()
        local idx = #itemOrder + 1
        PlaceRow(row, idx, BOE_ITEMS, "Interface\\ICONS\\INV_Sword_04", {0.5, 0.7, 1.0})
        row.countText:SetText(tostring(boe.count))
        row.qualityText:SetText("")
        row.goldText:SetText(FormatGold(boe.copper))
    end

    -- BoP items section
    local bop = FarmTallyDB.bopItems
    if bop and bop.count > 0 then
        local row = AcquireRow()
        local idx = #itemOrder + 1
        PlaceRow(row, idx, BOP_ITEMS, "Interface\\ICONS\\INV_Misc_Key_04", {0.9, 0.3, 0.3})
        row.countText:SetText(tostring(bop.count))
        row.qualityText:SetText("")
        row.goldText:SetText(FormatGold(bop.copper))
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
    FarmTallyDB.boeItems = { count = 0, copper = 0 }
    FarmTallyDB.bopItems = { count = 0, copper = 0 }
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
    elseif name == BOE_ITEMS then
        FarmTallyDB.boeItems = { count = 0, copper = 0 }
    elseif name == BOP_ITEMS then
        FarmTallyDB.bopItems = { count = 0, copper = 0 }
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
-- Settings panel
------------------------------------------------------------------------
local function InitSettings()
    local category = Settings.RegisterVerticalLayoutCategory("Farm Tally")

    -- Toggle: Quality border coloring
    do
        local function GetValue() return FarmTallyDB.showQualityBorder end
        local function SetValue(value)
            FarmTallyDB.showQualityBorder = value
            RefreshHUD()
        end
        local setting = Settings.RegisterProxySetting(category,
            "FARMTALLY_QUALITY_BORDER", Settings.VarType.Boolean,
            "Quality Icon Borders", Settings.Default.True,
            GetValue, SetValue)
        Settings.CreateCheckbox(category, setting,
            "Show colored borders around item icons based on item quality.")
    end

    -- Toggle: Name coloring by quality
    do
        local function GetValue() return FarmTallyDB.showQualityNameColor end
        local function SetValue(value)
            FarmTallyDB.showQualityNameColor = value
            RefreshHUD()
        end
        local setting = Settings.RegisterProxySetting(category,
            "FARMTALLY_QUALITY_NAME_COLOR", Settings.VarType.Boolean,
            "Color Item Names by Quality", Settings.Default.False,
            GetValue, SetValue)
        Settings.CreateCheckbox(category, setting,
            "Color item name text according to quality. Vendor Trash always stays grey.")
    end

    -- Toggle: BoE tracking
    do
        local function GetValue() return FarmTallyDB.trackBoE end
        local function SetValue(value)
            FarmTallyDB.trackBoE = value
            RefreshHUD()
        end
        local setting = Settings.RegisterProxySetting(category,
            "FARMTALLY_TRACK_BOE", Settings.VarType.Boolean,
            "Track Bind on Equip Items", Settings.Default.False,
            GetValue, SetValue)
        Settings.CreateCheckbox(category, setting,
            "Track BoE items as a separate section with their vendor sell value.")
    end

    -- Toggle: BoP tracking
    do
        local function GetValue() return FarmTallyDB.trackBoP end
        local function SetValue(value)
            FarmTallyDB.trackBoP = value
            RefreshHUD()
        end
        local setting = Settings.RegisterProxySetting(category,
            "FARMTALLY_TRACK_BOP", Settings.VarType.Boolean,
            "Track Bind on Pickup Items", Settings.Default.False,
            GetValue, SetValue)
        Settings.CreateCheckbox(category, setting,
            "Track BoP items as a separate section with their vendor sell value.")
    end

    -- Filter management subcategory (canvas with scroll)
    local filterFrame = CreateFrame("Frame")
    filterFrame:SetSize(600, 100)

    local filterScroll = CreateFrame("ScrollFrame", nil, filterFrame)
    filterScroll:SetPoint("TOPLEFT", 0, -4)
    filterScroll:SetPoint("TOPRIGHT", 0, -4)
    filterScroll:SetHeight(1) -- resized in RefreshFilters

    local filterContent = CreateFrame("Frame", nil, filterScroll)
    filterContent:SetWidth(580)
    filterContent:SetHeight(1)
    filterScroll:SetScrollChild(filterContent)
    filterScroll:EnableMouseWheel(true)
    filterScroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxS = math.max(0, filterContent:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(cur - delta * 24, maxS)))
    end)

    ---@type FarmTallyFilterRow[]
    local filterRowPool = {}

    ---@param parent FarmTallyFilterContainer
    local function ReleaseFilterRows(parent)
        for i = #parent.rows, 1, -1 do
            local row = table.remove(parent.rows, i)
            row:Hide()
            row:ClearAllPoints()
            table.insert(filterRowPool, row)
        end
    end

    ---@param parent FarmTallyFilterContainer
    ---@return FarmTallyFilterRow
    local function AcquireFilterRow(parent)
        local row = table.remove(filterRowPool)
        if not row then
            ---@class FarmTallyFilterRow
            row = CreateFrame("Frame", nil, parent)
            row:SetHeight(22)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.text:SetPoint("LEFT", 4, 0)
            row.text:SetJustifyH("LEFT")

            ---@class FarmTallyRemoveBtn
            row.removeBtn = CreateFrame("Button", nil, row)
            row.removeBtn:SetSize(16, 16)
            row.removeBtn:SetPoint("RIGHT", -4, 0)
            row.removeBtn.tex = row.removeBtn:CreateTexture(nil, "ARTWORK")
            row.removeBtn.tex:SetAllPoints()
            row.removeBtn.tex:SetTexture("Interface\\Buttons\\UI-StopButton")
            row.removeBtn.tex:SetDesaturated(true)
            row.removeBtn.tex:SetVertexColor(0.8, 0.2, 0.2)
            row.removeBtn:SetScript("OnEnter", function(self)
                ---@cast self FarmTallyRemoveBtn
                self.tex:SetDesaturated(false)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Remove")
                GameTooltip:Show()
            end)
            row.removeBtn:SetScript("OnLeave", function(self)
                ---@cast self FarmTallyRemoveBtn
                self.tex:SetDesaturated(true)
                GameTooltip:Hide()
            end)
        end
        row:SetParent(parent)
        row:Show()
        return row
    end

    ---@param parent FarmTallyFilterContainer
    ---@param title string
    ---@param tbl table<string, boolean>
    ---@param onRemove fun(name: string)
    ---@param emptyText string
    local function BuildList(parent, title, tbl, onRemove, emptyText)
        parent.rows = parent.rows or {}
        ReleaseFilterRows(parent)

        local yOff = 0

        -- Section title
        if not parent.title then
            parent.title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            parent.title:SetPoint("TOPLEFT", 10, 0)
        end
        parent.title:SetText(title)
        yOff = yOff - 24

        local any = false
        for name in pairs(tbl) do
            any = true
            local row = AcquireFilterRow(parent)
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOff)
            row:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
            row.text:SetText(name)
            row.removeBtn:SetScript("OnClick", function()
                onRemove(name)
            end)
            table.insert(parent.rows, row)
            yOff = yOff - 24
        end

        if not any then
            if not parent.emptyHint then
                parent.emptyHint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                parent.emptyHint:SetPoint("TOPLEFT", 14, -24)
            end
            parent.emptyHint:SetText(emptyText)
            parent.emptyHint:Show()
            yOff = yOff - 20
        elseif parent.emptyHint then
            parent.emptyHint:Hide()
        end

        parent:SetHeight(math.abs(yOff) + 8)
    end

    -- Container frames for each list
    ---@type FarmTallyFilterContainer
    local trackedContainer = CreateFrame("Frame", nil, filterContent) --[[@as FarmTallyFilterContainer]]
    trackedContainer:SetPoint("TOPLEFT", 0, -10)
    trackedContainer:SetPoint("RIGHT")
    trackedContainer:SetHeight(40)

    ---@type FarmTallyFilterContainer
    local excludedContainer = CreateFrame("Frame", nil, filterContent) --[[@as FarmTallyFilterContainer]]
    excludedContainer:SetPoint("TOPLEFT", trackedContainer, "BOTTOMLEFT", 0, -12)
    excludedContainer:SetPoint("RIGHT")
    excludedContainer:SetHeight(40)

    local function RefreshFilters()
        BuildList(trackedContainer, "Tracked Items (persistent)",
            FarmTallyDB.trackedNames,
            function(name)
                FarmTallyDB.trackedNames[name] = nil
                RefreshFilters()
            end,
            "(none -- trade goods are tracked automatically)")

        BuildList(excludedContainer, "Excluded Items (this session)",
            FarmTallyDB.excludedNames,
            function(name)
                FarmTallyDB.excludedNames[name] = nil
                RefreshFilters()
            end,
            "(none)")

        -- Resize to fit content
        local totalH = (trackedContainer:GetHeight() or 40) + 12 + (excludedContainer:GetHeight() or 40) + 20
        filterContent:SetHeight(totalH)
        local maxVisible = 400
        local scrollH = math.min(totalH, maxVisible)
        filterScroll:SetHeight(scrollH)
        filterFrame:SetHeight(scrollH + 8)
    end

    filterFrame:SetScript("OnShow", RefreshFilters)

    Settings.RegisterCanvasLayoutSubcategory(category, filterFrame, "Filters")
    Settings.RegisterAddOnCategory(category)
    settingsCategoryID = category:GetID()
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("PLAYER_LOGIN")
EventFrame:RegisterEvent("LOOT_READY")
EventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        InitDB()
        InitSettings()
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

    elseif event == "LOOT_READY" and not FarmTallyDB.paused then
        for slot = 1, GetNumLootItems() do
            local link = GetLootSlotLink(slot)
            if link then
                local _, _, lootQuantity = GetLootSlotInfo(slot)
                local name, _, quality, _, _, _, _, _, _, icon, sellPrice, classID, _, bindType = GetItemInfo(link)
                if not name then
                    name = link:match("%[(.-)%]")
                    local id = tonumber(link:match("item:(%d+)"))
                    if id then _, _, _, _, icon, classID = GetItemInfoInstant(id) end
                end
                dbg("Loot:", tostring(name), "q=" .. tostring(quality), "class=" .. tostring(classID), "bind=" .. tostring(bindType))

                if quality == 0 and sellPrice and sellPrice > 0 and not FarmTallyDB.excludedNames[VENDOR_TRASH] then
                    local vt = FarmTallyDB.vendorTrash
                    local qty = lootQuantity or 1
                    vt.count = vt.count + qty
                    vt.copper = vt.copper + (sellPrice * qty)

                elseif FarmTallyDB.trackBoE and bindType == BIND_ON_EQUIP and sellPrice and sellPrice > 0 and not FarmTallyDB.excludedNames[BOE_ITEMS] then
                    local boe = FarmTallyDB.boeItems
                    local qty = lootQuantity or 1
                    boe.count = boe.count + qty
                    boe.copper = boe.copper + (sellPrice * qty)

                elseif FarmTallyDB.trackBoP and bindType == BIND_ON_PICKUP and sellPrice and sellPrice > 0 and quality and quality > 0 and not FarmTallyDB.excludedNames[BOP_ITEMS] then
                    local bop = FarmTallyDB.bopItems
                    local qty = lootQuantity or 1
                    bop.count = bop.count + qty
                    bop.copper = bop.copper + (sellPrice * qty)

                elseif name and (classID == TRADE_GOODS or FarmTallyDB.trackedNames[name]) and not FarmTallyDB.excludedNames[name] then
                    local data = FarmTallyDB.count[name]
                    if not data then
                        data = {icon = icon, amount = 0}
                        FarmTallyDB.count[name] = data
                    end
                    data.amount = data.amount + (lootQuantity or 1)
                    data.quality = quality or data.quality

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
    elseif command == "settings" or command == "options" then
        if settingsCategoryID then
            Settings.OpenToCategory(settingsCategoryID)
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
        print("  /fta settings — open settings panel")
        print("  /fta debug — toggle debug logging")
    end
end
