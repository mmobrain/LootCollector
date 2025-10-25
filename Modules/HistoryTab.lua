-- HistoryTab.lua
-- History list UI for LootCollector with v5 protocol awareness.
-- Shows discoveries, instance-aware zone display (iz), ACK counts, and status changes based on deletion votes.
-- 3.3.5a-safe, uses FauxScrollFrame for performance and compatibility.
-- UNK.B64.UTF-8


local L = LootCollector
local HistoryTab = L:NewModule("HistoryTab")

local ROW_HEIGHT = 20
local NUM_ROWS = 14
local PANEL_WIDTH = 980
local PANEL_HEIGHT = 420
local PADDING = 10
local SMALL_PAD = 6

local COLS = {
    { key = "item", title = "Item", width = 240 },
    { key = "zone", title = "Zone", width = 150 },
    { key = "coords", title = "Coords", width = 100 },
    { key = "status", title = "Status", width = 120 }, 
    { key = "acks", title = "ACKs", width = 40 },
    { key = "seen", title = "Seen", width = 160 },
}

local ZoneList = L:GetModule("ZoneList", true)

HistoryTab.rowsData = {}
HistoryTab._frame = nil
HistoryTab._scroll = nil
HistoryTab._rows = {}
HistoryTab._selectedGuid = nil
HistoryTab._filterBox = nil
HistoryTab._filterTimer = nil

local function safeGetItemLink(rec)
    if rec.il and rec.il ~= "" then
        return rec.il
    end
    if rec.i and rec.i > 0 then
        local link = select(2, GetItemInfo(rec.i))
        return link or ("item:" .. tostring(rec.i))
    end
    return "Unknown Item"
end

local function colorForStatus(rec)
    if rec.s == "STALE" then
        return 1.0, 0.6, 0.0 
    elseif rec.s == "FADING" then
        return 1.0, 0.8, 0.4 
    end
    return 0.55, 1.0, 0.55 
end

local function formatDate(ts)
    ts = tonumber(ts) or time()
    return date("%Y-%m-%d %H:%M", ts)
end

function HistoryTab:_ResolveZoneDisplay(rec)
    local c = tonumber(rec.c) or 0
    local z = tonumber(rec.z) or 0
    local iz = tonumber(rec.iz) or 0
    
    if z == 0 then
        return (ZoneList and ZoneList.ResolveIz and ZoneList:ResolveIz(iz)) or (GetRealZoneText and GetRealZoneText()) or "Unknown Instance"
    else
        return (ZoneList and ZoneList.GetZoneName and ZoneList:GetZoneName(c, z)) or "Unknown Zone"
    end
end

function HistoryTab:_ResolveZoneAbbrev(rec)
    local c = tonumber(rec.c) or 0
    local z = tonumber(rec.z) or 0
    local iz = tonumber(rec.iz) or 0

    if z == 0 and iz > 0 and ZoneList and ZoneList.IZ_TO_ABBREVIATIONS and ZoneList.IZ_TO_ABBREVIATIONS[iz] then
        return ZoneList.IZ_TO_ABBREVIATIONS[iz]
    end

    local zoneName = self:_ResolveZoneDisplay(rec)
    if ZoneList and ZoneList.ZONEABBREVIATIONS and ZoneList.ZONEABBREVIATIONS[zoneName] then
        return ZoneList.ZONEABBREVIATIONS[zoneName]
    end
    
    return zoneName
end

function HistoryTab:RebuildData()
    wipe(self.rowsData)
    
    if not (L.db and L.db.global and L.db.global.discoveries) then
        return
    end
    
    for _, rec in pairs(L.db.global.discoveries) do
        if type(rec) == "table" then
            table.insert(self.rowsData, rec)
        end
    end
    
    table.sort(self.rowsData, function(a, b)
        local ta = tonumber(a.ls or a.t0 or 0) or 0
        local tb = tonumber(b.ls or b.t0 or 0) or 0
        if ta == tb then
            return (tonumber(a.i) or 0) > (tonumber(b.i) or 0)
        end
        return ta > tb
    end)
end

function HistoryTab:SetSelected(guid)
    self._selectedGuid = guid
    self:Refresh()
end

function HistoryTab:GetSelection()
    return self._selectedGuid
end

function HistoryTab:_IsSelected(rec)
    if not rec or not rec.g then return false end
    return self._selectedGuid == rec.g
end

local function setCellText(fs, text, r, g, b)
    if not fs then return end
    fs:SetText(text or "")
    if r and fs.SetTextColor then
        fs:SetTextColor(r, g or 1, b or 1)
    end
end

function HistoryTab:_RenderRow(rowIndex, dataIndex, filteredData)
    local row = self._rows[rowIndex]
    if not row then return end
    
    local rec = filteredData[dataIndex]
    row.rec = rec
    
    if not rec then
        row:Hide()
        return
    end
    
    row:Show()
    
    local link = safeGetItemLink(rec)
    local zone = self:_ResolveZoneAbbrev(rec)
    local cx = rec.xy and rec.xy.x or 0
    local cy = rec.xy and rec.xy.y or 0
    local coords = string.format("%.4f, %.4f", L:Round4(cx), L:Round4(cy))
    local status = rec.s or "UNCONFIRMED"
    if rec.adc and rec.adc > 0 then
        status = status .. " (" .. rec.adc .. ")"
    end
    local acks = tostring(tonumber(rec.ac or 0) or 0) 
    local seen = formatDate(rec.ls or rec.t0 or time())
    
    local colMap = {}
    for i, col in ipairs(COLS) do
        colMap[col.key] = i
    end
    
    setCellText(row.cols[colMap.item], link)
    setCellText(row.cols[colMap.zone], zone)
    setCellText(row.cols[colMap.coords], coords)
    
    local sr, sg, sb = colorForStatus(rec)
    setCellText(row.cols[colMap.status], status, sr, sg, sb)
    setCellText(row.cols[colMap.acks], acks)
    setCellText(row.cols[colMap.seen], seen)
    
    if self:_IsSelected(rec) then
        row.bg:SetVertexColor(1, 1, 0, 0.20) 
    elseif rec.s == "STALE" then
        row.bg:SetVertexColor(1, 0.6, 0, 0.15) 
    else
        row.bg:SetVertexColor(1, 1, 1, 0.06) 
    end
end

function HistoryTab:Refresh()
    if not self._frame or not self._frame:IsShown() then
        return
    end
    
    if not (L and L.db and L.db.global) then
        for i = 1, NUM_ROWS do
            self:_RenderRow(i, math.huge, {})
        end
        return
    end
    
    self:RebuildData()
    
    local filteredData = {}
    local filterText = self._filterBox and string.lower(self._filterBox:GetText() or "") or ""
    
    if filterText == "" then
        filteredData = self.rowsData
    else
        for _, rec in ipairs(self.rowsData) do
            local itemName = (rec.il and rec.il:match("%[(.+)%]")) or ""
            local zoneName = self:_ResolveZoneDisplay(rec) or ""
            local status = rec.s or "active"

            if string.find(string.lower(itemName), filterText, 1, true) or 
               string.find(string.lower(zoneName), filterText, 1, true) or
               string.find(string.lower(status), filterText, 1, true) then
                table.insert(filteredData, rec)
            end
        end
    end
    
    local total = #filteredData
    local offset = FauxScrollFrame_GetOffset(self._scroll)
    
    FauxScrollFrame_Update(self._scroll, total, NUM_ROWS, ROW_HEIGHT)
    
    for i = 1, NUM_ROWS do
        local dataIndex = i + offset
        self:_RenderRow(i, dataIndex, filteredData)
    end
end

local function createColumnHeader(parent, title, width, x)
    local header = CreateFrame("Button", nil, parent)
    header:SetSize(width, 20)
    header:SetPoint("TOPLEFT", x, 0)
    
    local text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetText(title)
    text:SetPoint("LEFT", 5, 0)
    
    return header
end

function HistoryTab:_LayoutColumns(headerFrame)
    local avail = PANEL_WIDTH - 2 * PADDING - SMALL_PAD
    local totalW = 0
    for _, c in ipairs(COLS) do totalW = totalW + c.width end
    
    local colW, colX = {}, {}
    local x = 0
    
    for i, c in ipairs(COLS) do
        local w = math.floor(avail * (c.width / totalW))
        if i == #COLS then
            w = avail - x
        end
        colW[i] = w
        colX[i] = x
        x = x + w
    end
    
    
    for i, c in ipairs(COLS) do
        local h = createColumnHeader(headerFrame, c.title, colW[i], colX[i])
        headerFrame.headers[i] = h
    end
    
    return colX, colW
end

local function _CreateRow(parent, i, colX, colW)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(colW[#colW] + colX[#colX], ROW_HEIGHT)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i-1) * ROW_HEIGHT)
    
    
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints(r)
    r.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    r.bg:SetVertexColor(0, 0, 0, 0)
    
    
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    
    
    r.cols = {}
    for col = 1, #colX do
        local txt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", r, "LEFT", colX[col] + 4, 0)
        txt:SetSize(colW[col] - 8, ROW_HEIGHT)
        txt:SetJustifyH("LEFT")
        txt:SetJustifyV("MIDDLE")
        r.cols[col] = txt
    end
    
    r:SetScript("OnClick", function(self, button)
        local d = self.rec
        if not d then return end

        if IsControlKeyDown() and IsAltKeyDown() then
            if button == "LeftButton" and d.il then
                SetItemRef(d.il, d.il, button)
            elseif button == "RightButton" and d.il then
                local zoneName = HistoryTab:_ResolveZoneDisplay(d)
                local coords = string.format("%.1f, %.1f", (d.xy.x or 0) * 100, (d.xy.y or 0) * 100)
                local msg = string.format("%s @ %s (%s)", d.il, zoneName, coords)
                ChatFrame_SendChatMessage(msg)
            end
            return
        elseif IsShiftKeyDown() and IsAltKeyDown() and button == "LeftButton" then
            local Map = L:GetModule("Map", true)
            if Map and Map.OpenShowToDialog then
                Map:OpenShowToDialog(d)
            end
            return
        end
        
        if d.g then
            HistoryTab:SetSelected(d.g)
        end
    end)
    
    r:Hide()
    return r
end

function HistoryTab:_CreateUI()
    if self._frame then return end
    
    local f = CreateFrame("Frame", "LootCollector_HistoryTab", UIParent)
    f:SetWidth(PANEL_WIDTH)
    f:SetHeight(PANEL_HEIGHT)
    f:SetPoint("CENTER")

    
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95) 
    
 

    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    
    
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, -PADDING)
    title:SetText("LootCollector History")
    
    
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    
    
    local filterLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    filterLabel:SetText("Filter:")

    local filterBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    filterBox:SetSize(200, 20)
    filterBox:SetPoint("LEFT", filterLabel, "RIGHT", 4, 0)
    filterBox:SetScript("OnTextChanged", function()
        if HistoryTab._filterTimer then
            C_Timer.CancelTimer(HistoryTab._filterTimer)
            HistoryTab._filterTimer = nil
        end
        HistoryTab._filterTimer = C_Timer.After(0.5, function()
            HistoryTab:Refresh()
            HistoryTab._filterTimer = nil
        end)
    end)
    self._filterBox = filterBox

    
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, -PADDING - 50)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADDING, -PADDING - 50)
    header:SetHeight(16)
    header.headers = {}
    
    
    local scroll = CreateFrame("ScrollFrame", "LootCollector_HistoryScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, -PADDING - 50 - 18)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PADDING - 20, 40)
    
    
    local rowsHolder = CreateFrame("Frame", nil, f)
    rowsHolder:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    rowsHolder:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
    rowsHolder:SetHeight(NUM_ROWS * ROW_HEIGHT + 2)
    
    
    local colX, colW = self:_LayoutColumns(header)
    
    self._rows = {}
    for i = 1, NUM_ROWS do
        local row = _CreateRow(rowsHolder, i, colX, colW)
        
        if i == 1 then
            row:SetPoint("TOPLEFT", rowsHolder, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", self._rows[i - 1], "BOTTOMLEFT", 0, -1)
        end
        
        table.insert(self._rows, row)
    end
    
    
    scroll:SetScript("OnVerticalScroll", function(selfScroll, offset)
        FauxScrollFrame_OnVerticalScroll(selfScroll, offset, ROW_HEIGHT, function()
            HistoryTab:Refresh()
        end)
    end)
    
    
    f:SetScript("OnShow", function()
        HistoryTab:Refresh()
    end)
    
    self._frame = f
    self._scroll = scroll
end

function HistoryTab:Show()
    self:_CreateUI()
    self._frame:Show()
    self:Refresh()
end

function HistoryTab:Hide()
    if self._frame then
        self._frame:Hide()
    end
end

function HistoryTab:Toggle()
    if not self._frame or not self._frame:IsShown() then
        self:Show()
    else
        self:Hide()
    end
end

function HistoryTab:GetFrame()
    self:_CreateUI()
    return self._frame
end

function HistoryTab:OnInitialize()
    
end

return HistoryTab

-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl