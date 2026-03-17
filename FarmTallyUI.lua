------------------------------------------------------------------------
-- FarmTally - UI
-- Main frame, minimap button, row pool, display logic, button scripts.
------------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- Pull frequently used ns members into locals
local VENDOR_TRASH  = ns.VENDOR_TRASH
local BOE_ITEMS     = ns.BOE_ITEMS
local BOP_ITEMS     = ns.BOP_ITEMS
local FRAME_W       = ns.FRAME_W
local PAD           = ns.PAD
local HEADER_H      = ns.HEADER_H
local ROW_H         = ns.ROW_H
local CAT_ROW_H     = ns.CAT_ROW_H
local CAT_INDENT    = ns.CAT_INDENT
local FOOTER_H      = ns.FOOTER_H
local ICON_SIZE     = ns.ICON_SIZE
local CONTENT_W     = ns.CONTENT_W
local MAX_ROWS      = ns.MAX_ROWS
local SCROLL_STEP   = ns.SCROLL_STEP
local dbg            = ns.dbg
local FormatGold     = ns.FormatGold
local FormatQuality  = ns.FormatQuality
local GetCategoryName = ns.GetCategoryName
local GetVendorPrice = ns.GetVendorPrice
local GetAHPrice     = ns.GetAHPrice
local GetItemValue   = ns.GetItemValue

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local itemRows, itemOrder = {}, {}

---@type FarmTallyRow[]
local rowPool = {}
local cachedTotalGold = 0
local totalContentH = 0

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
ns.MainFrame = MainFrame

--@do-not-package@
local devBadge = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
devBadge:SetPoint("TOP", MainFrame, "TOP", 0, -2)
devBadge:SetText("|cffff6600DEV|r")
devBadge:SetFontHeight(9)
--@end-do-not-package@

------------------------------------------------------------------------
-- Minimap button
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
minimapBtn.icon:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Artwork\\Icon")

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
ns.UpdateMinimapPosition = UpdateMinimapPosition

local function UpdateMinimapIcon()
    minimapBtn.icon:SetDesaturated(FarmTallyDB.paused)
end
ns.UpdateMinimapIcon = UpdateMinimapIcon

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
        if ns.settingsCategoryID then
            if SettingsPanel:IsShown() then
                HideUIPanel(SettingsPanel)
            else
                Settings.OpenToCategory(ns.settingsCategoryID)
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
ns.CreateFlatButton = CreateFlatButton

local btnPause = CreateFlatButton(ControlBar, 18, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", 0.5, 0.9, 0.5)
btnPause:SetPoint("LEFT", ControlBar, "LEFT", 0, 0)

MainFrame.TimerText:ClearAllPoints()
MainFrame.TimerText:SetPoint("LEFT", btnPause, "RIGHT", 6, 0)

local btnClose = CreateFlatButton(ControlBar, 14, "Interface\\Buttons\\UI-StopButton", 0.8, 0.3, 0.3)
btnClose:SetPoint("RIGHT", ControlBar, "RIGHT", 0, 0)

local btnHelp = CreateFlatButton(ControlBar, 14, "Interface\\GossipFrame\\ActiveQuestIcon", 0.7, 0.7, 0.7)
btnHelp:SetPoint("RIGHT", btnClose, "LEFT", -6, 0)

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

local btnReset = CreateFlatButton(MainFrame, 14, "Interface\\TimeManager\\ResetButton", 0.6, 0.6, 0.6)
btnReset:SetPoint("BOTTOMLEFT", PAD, 7)

MainFrame.totalGoldText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
MainFrame.totalGoldText:SetPoint("LEFT", btnReset, "RIGHT", 4, 0)
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
        btnReset:Hide()
        emptyHint:Show()
    else
        local maxVisibleH = MAX_ROWS * ROW_H
        local visibleH = min(totalContentH, maxVisibleH)
        MainFrame:SetHeight(HEADER_H + visibleH + FOOTER_H)
        ListFrame:SetSize(CONTENT_W, totalContentH)
        ScrollFrame:Show()
        headerSep:Show()
        footerSep:Show()
        btnReset:Show()
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
ns.UpdateGoldRate = UpdateGoldRate

local function UpdateSummary()
    cachedTotalGold = 0
    for _, data in pairs(FarmTallyDB.count) do
        local value = GetItemValue(data)
        if value then cachedTotalGold = cachedTotalGold + value end
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

    row.catBg = row:CreateTexture(nil, "BACKGROUND")
    row.catBg:SetAllPoints()
    row.catBg:SetColorTexture(1, 1, 1, 0.06)
    row.catBg:Hide()

    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", OnScrollWheel)
    row:SetScript("OnMouseUp", function(self, button)
        ---@cast self FarmTallyRow
        if self.isCategoryHeader and button == "LeftButton" and IsShiftKeyDown() then
            -- Cycle price mode for this category: both -> ah -> vendor -> both
            local catName = self.categoryName
            local modes = { both = "ah", ah = "vendor", vendor = "both" }
            local labels = { both = "AH + Vendor", ah = "AH only", vendor = "Vendor only" }
            local current = FarmTallyDB.priceMode[catName] or "both"
            FarmTallyDB.priceMode[catName] = modes[current] or "both"
            print("|cff00ff00FarmTally:|r " .. catName .. " price: " .. labels[FarmTallyDB.priceMode[catName]])
            ns.RefreshHUD()
        elseif self.isCategoryHeader and button == "LeftButton" then
            FarmTallyDB.collapsed[self.categoryName] = not FarmTallyDB.collapsed[self.categoryName]
            ns.RefreshHUD()
        elseif button == "RightButton" and self.itemName and ns.ExcludeItem then
            ns.ExcludeItem(self.itemName)
        end
    end)
    row:SetScript("OnEnter", function(self)
        ---@cast self FarmTallyRow
        if self.isCategoryHeader then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local labels = { both = "AH + Vendor", ah = "AH only", vendor = "Vendor only" }
            local catMode = FarmTallyDB.priceMode[self.categoryName] or "both"
            GameTooltip:AddLine(self.categoryName, 1, 1, 1)
            GameTooltip:AddLine("Click to expand/collapse", 0.5, 0.5, 0.5)
            GameTooltip:AddLine("Shift+click to cycle price (" .. labels[catMode] .. ")", 0.5, 0.5, 0.5)
            GameTooltip:AddLine("Right-click to exclude", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        elseif self.itemName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.itemName, 1, 1, 1)
            GameTooltip:AddLine("Right-click to disable tracking", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)

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

    row.goldText2 = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.goldText2:SetPoint("BOTTOMRIGHT", row.goldText, "TOPLEFT", 0, -2)
    row.goldText2:SetJustifyH("RIGHT")
    row.goldText2:SetTextColor(0.67, 0.83, 0.45, 0.9)
    row.goldText2:SetFontHeight(10)
    row.goldText2:Hide()

    return row
end

local function ReleaseRow(row)
    row:Hide()
    row:ClearAllPoints()
    row.itemName = nil
    row.isCategoryHeader = nil
    row.categoryName = nil
    if row.goldText2 then row.goldText2:Hide(); row.goldText2:SetText("") end
    if row.catBg then row.catBg:Hide() end
    -- Reset to default item row layout (category headers change these)
    row:SetSize(CONTENT_W, ROW_H - 4)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:Show()
    row.nameText:ClearAllPoints()
    row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -2)
    row.nameText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -45, -2)
    row.nameText:SetFontHeight(12)
    row.goldText:ClearAllPoints()
    row.goldText:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
    row.goldText:SetFontHeight(10)
    table.insert(rowPool, row)
end

---@param row FarmTallyRow
---@param yOffset number
---@param name string
---@param icon any
---@param nameColor number[]?
---@param quality integer?
local function PlaceRow(row, yOffset, name, icon, nameColor, quality)
    row:SetPoint("TOPLEFT", 0, -yOffset)
    row.itemName = name
    row.icon:SetTexture(icon or ns.FALLBACK_ICON)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:Show()
    row.nameText:SetText(name)
    if nameColor then
        row.nameText:SetTextColor(unpack(nameColor))
    elseif quality == 0 then
        row.nameText:SetTextColor(0.62, 0.62, 0.62)
    elseif quality and quality > 1 then
        local r, g, b = GetItemQualityColor(quality)
        row.nameText:SetTextColor(r, g, b)
    else
        row.nameText:SetTextColor(1, 1, 1)
    end
    row.sep:SetShown(yOffset > 0)
    if quality and quality > 1 then
        local r, g, b = GetItemQualityColor(quality)
        ---@cast r number
        ---@cast g number
        ---@cast b number
        row.iconBorder:SetVertexColor(r, g, b)
        row.iconBorder:Show()
    else
        row.iconBorder:Hide()
    end
    itemOrder[#itemOrder + 1] = name
    itemRows[name] = row
end

------------------------------------------------------------------------
-- RefreshHUD
------------------------------------------------------------------------
ns.RefreshHUD = function()
    -- Release all rows
    for _, row in pairs(itemRows) do ReleaseRow(row) end
    itemRows, itemOrder = {}, {}

    -- Helper: show dual price on a row
    local function SetDualGold(row, ahCopper, vendorCopper)
        if ahCopper and ahCopper > 0 and vendorCopper and vendorCopper > 0 and ahCopper ~= vendorCopper then
            row.goldText:SetText("Vendor: " .. FormatGold(vendorCopper) .. " AH: " .. FormatGold(ahCopper))
        elseif ahCopper and ahCopper > 0 then
            row.goldText:SetText(FormatGold(ahCopper))
        elseif vendorCopper and vendorCopper > 0 then
            row.goldText:SetText(FormatGold(vendorCopper))
        else
            row.goldText:SetText("")
        end
    end

    -- Group all items by category
    local categories = {}
    for name, data in pairs(FarmTallyDB.count) do
        local catName = GetCategoryName(data)
        if not categories[catName] then
            categories[catName] = { items = {}, totalCount = 0, totalGold = 0, totalVendor = 0, totalAH = 0 }
        end
        local cat = categories[catName]
        local gold = GetItemValue(data) or 0
        local vendor = GetVendorPrice(data) or 0
        local ah = GetAHPrice(data) or 0
        cat.items[#cat.items + 1] = { name = name, data = data, gold = gold }
        cat.totalCount = cat.totalCount + data.amount
        cat.totalGold = cat.totalGold + gold
        cat.totalVendor = cat.totalVendor + vendor
        cat.totalAH = cat.totalAH + ah
    end

    -- Sort items within each category
    for _, cat in pairs(categories) do
        table.sort(cat.items, function(a, b)
            local ag, bg = (a.gold or 0), (b.gold or 0)
            if ag ~= bg then return ag > bg end
            if a.data.amount ~= b.data.amount then return a.data.amount > b.data.amount end
            return a.name < b.name
        end)
    end

    -- Sort categories by totalGold descending, Vendor Trash always last
    local sortedCats = {}
    for catName, cat in pairs(categories) do
        sortedCats[#sortedCats + 1] = { name = catName, cat = cat }
    end
    table.sort(sortedCats, function(a, b)
        if a.name == VENDOR_TRASH then return false end
        if b.name == VENDOR_TRASH then return true end
        return a.cat.totalGold > b.cat.totalGold
    end)

    -- Create rows for each category using running yOffset
    local yOffset = 0
    for _, catEntry in ipairs(sortedCats) do
        local catName = catEntry.name
        local cat = catEntry.cat
        local isCollapsed = FarmTallyDB.collapsed[catName]

        -- Category header: compact single-line row
        local headerRow = AcquireRow()
        headerRow:SetSize(CONTENT_W, CAT_ROW_H)
        PlaceRow(headerRow, yOffset, catName, nil, {0.7, 0.7, 0.7})
        headerRow.icon:Hide()
        headerRow.iconBorder:Hide()
        headerRow.countText:SetText("")
        headerRow.qualityText:SetText("")
        headerRow.isCategoryHeader = true
        headerRow.categoryName = catName
        headerRow.catBg:Show()
        -- Single centered line: name left, gold right
        local prefix = isCollapsed and "+ " or "- "
        headerRow.nameText:ClearAllPoints()
        headerRow.nameText:SetPoint("LEFT", 4, 0)
        headerRow.nameText:SetPoint("RIGHT", headerRow, "RIGHT", -80, 0)
        headerRow.nameText:SetText(prefix .. catName)
        headerRow.nameText:SetFontHeight(11)
        headerRow.goldText:ClearAllPoints()
        headerRow.goldText:SetPoint("RIGHT", headerRow, "RIGHT", 0, 0)
        headerRow.goldText:SetFontHeight(11)

        -- Total price on header (per-category priceMode)
        local mode = FarmTallyDB.priceMode[catName] or "both"
        if mode == "both" and cat.totalAH > 0 and cat.totalVendor > 0 then
            SetDualGold(headerRow, cat.totalAH, cat.totalVendor)
        elseif mode == "ah" and cat.totalAH > 0 then
            headerRow.goldText:SetText(FormatGold(cat.totalAH))
        elseif mode == "vendor" and cat.totalVendor > 0 then
            headerRow.goldText:SetText(FormatGold(cat.totalVendor))
        else
            headerRow.goldText:SetText(cat.totalGold > 0 and FormatGold(cat.totalGold) or "")
        end
        yOffset = yOffset + CAT_ROW_H

        -- Item rows (indented, if not collapsed)
        if not isCollapsed then
            for _, entry in ipairs(cat.items) do
                local row = AcquireRow()
                PlaceRow(row, yOffset, entry.name, entry.data.icon, nil, entry.data.quality)
                -- Indent: shift icon (nameText follows via anchor)
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", 2 + CAT_INDENT, 0)
                row.countText:SetText(tostring(entry.data.amount))
                row.qualityText:SetText(FormatQuality(entry.data))

                -- Item gold based on priceMode
                if entry.data.isBoP then
                    row.goldText:SetText(entry.gold and entry.gold > 0 and FormatGold(entry.gold) or "")
                elseif mode == "both" then
                    local ah = GetAHPrice(entry.data)
                    local vendor = GetVendorPrice(entry.data)
                    if ah and vendor and ah ~= vendor then
                        SetDualGold(row, ah, vendor)
                    else
                        row.goldText:SetText(FormatGold(ah or vendor or 0))
                    end
                elseif mode == "ah" then
                    local ah = GetAHPrice(entry.data)
                    row.goldText:SetText(ah and ah > 0 and FormatGold(ah) or "")
                else
                    local vendor = GetVendorPrice(entry.data)
                    row.goldText:SetText(vendor and vendor > 0 and FormatGold(vendor) or "")
                end
                yOffset = yOffset + ROW_H
            end
        end
    end

    totalContentH = yOffset
    ScrollFrame:SetVerticalScroll(0)
    UpdateFrameHeight()
    UpdateSummary()
end

------------------------------------------------------------------------
-- Session controls
------------------------------------------------------------------------
function ns.Reset()
    dbg("Reset: rows=" .. #itemOrder)
    FarmTallyDB.count = {}
    FarmTallyDB.collapsed = {}
    FarmTallyDB.excludedNames = {}
    FarmTallyDB.totalTime = 0
    FarmTallyDB.qAtlas = {}
    FarmTallyDB.paused = true
    ns.StopTimer()
    ns.CleanupPriceUpdate()
    for _, row in pairs(itemRows) do ReleaseRow(row) end
    itemRows, itemOrder = {}, {}
    MainFrame.TimerText:SetText("00:00:00")
    MainFrame.totalGoldText:SetText("")
    btnRate.text:SetText("")
    cachedTotalGold = 0
    ScrollFrame:SetVerticalScroll(0)
    UpdateFrameHeight()
    ns.ApplyPauseVisuals()
end

function ns.ApplyPauseVisuals()
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

function ns.ExcludeItem(name)
    dbg("ExcludeItem:", name)
    FarmTallyDB.excludedNames[name] = true
    for itemName, data in pairs(FarmTallyDB.count) do
        if itemName == name or GetCategoryName(data) == name then
            FarmTallyDB.count[itemName] = nil
        end
    end
    ns.RefreshHUD()
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
        ns.StopTimer()
    else
        ns.StartTimer()
    end
    ns.ApplyPauseVisuals()
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

btnReset:SetScript("OnClick", ns.Reset)
btnReset:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Reset session")
    GameTooltip:AddLine("Clear all gathered items and reset the timer", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
btnReset:SetScript("OnLeave", function(self)
    self.tex:SetAlpha(0.8)
    GameTooltip:Hide()
end)

btnClose:SetScript("OnClick", function()
    FarmTallyDB.visible = false
    MainFrame:Hide()
end)
btnClose:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Close")
    GameTooltip:Show()
end)
btnClose:SetScript("OnLeave", function(self)
    self.tex:SetAlpha(0.8)
    GameTooltip:Hide()
end)


btnHelp:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine("Farm Tally", 1, 0.82, 0)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Category headers:", 1, 1, 1)
    GameTooltip:AddLine("  Click to expand/collapse", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("  Shift+click to cycle price mode", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("  Right-click to exclude category", 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Items:", 1, 1, 1)
    GameTooltip:AddLine("  Right-click to exclude item", 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Footer:", 1, 1, 1)
    GameTooltip:AddLine("  Click gold rate to toggle /min and /hr", 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("/fta — toggle window  |  /fta reset — reset", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)
btnHelp:SetScript("OnLeave", function(self)
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
