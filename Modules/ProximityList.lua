
local L = LootCollector
local ProximityList = L:NewModule("ProximityList", "AceEvent-3.0")

local PANEL_WIDTH = 280
local ROW_HEIGHT = 22
local MAX_VISIBLE_ROWS = 15
local CLUSTER_RADIUS_PIXELS = 20
local CLUSTER_RADIUS_SQ = CLUSTER_RADIUS_PIXELS * CLUSTER_RADIUS_PIXELS

ProximityList._frame = nil
ProximityList._buttons = {}
ProximityList._lastHoveredPin = nil
ProximityList.currentCluster = nil
ProximityList.currentVendorData = nil
ProximityList.displayMode = nil 
ProximityList._mouseOverButton = false

local function GetQualityColor(quality)
  quality = tonumber(quality)
  if not quality then return 1, 1, 1 end
  if _G.GetItemQualityColor then
    local r, g, b = GetItemQualityColor(quality)
    if r and g and b then return r, g, b end
  end
  if _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality] then
    local c = _G.ITEM_QUALITY_COLORS[quality]
    return c.r or 1, c.g or 1, c.b or 1
  end
  return 1, 1, 1
end

function ProximityList:CreateFrame()
    if self._frame then return end

    local parent = UIParent
    if not parent then return end
    
    local f = CreateFrame("Frame", "LootCollectorProximityList", parent)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:EnableMouse(true)
    f:SetMovable(true) 
    f:SetClampedToScreen(true) 
    f:SetWidth(PANEL_WIDTH)
    f:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -45, -70)
    f:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", -45, 70)
    f:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.95) 
    f:Hide()
    self._frame = f

    
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -8)
    title:SetText("Nearby Discoveries")
    f.title = title

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        ProximityList:Hide("CloseButton")
    end)

    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -38)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 12)

    f.content = CreateFrame("Frame", nil, f.scroll)
    f.scroll:SetScrollChild(f.content)
    f.content:SetWidth(PANEL_WIDTH - 50)
    f.content:SetHeight(1)

    for i = 1, MAX_VISIBLE_ROWS do
        local btn = CreateFrame("Button", nil, f.content)
        btn:SetSize(PANEL_WIDTH - 50, ROW_HEIGHT)
        btn:EnableMouse(true)
        btn:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
        
        
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints(true)
        btn.bg:SetTexture("Interface/Buttons/WHITE8x8")
        btn.bg:SetVertexColor(1, 1, 1, 0)

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
        btn.icon:SetPoint("LEFT", 2, 0)
        
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 4, 0)
        btn.text:SetPoint("RIGHT", -2, 0)
        btn.text:SetJustifyH("LEFT")
        
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        btn:SetScript("OnClick", function(self, button)
            if self.discovery then
                local Map = L:GetModule("Map", true)
                if button == "RightButton" then
                     if Map and Map.OpenPinMenu then
                        Map:OpenPinMenu(self)
                     end
                else
                    if Map and Map.FocusOnDiscovery then
                        Map:FocusOnDiscovery(self.discovery)
                    end
                end
            end
        end)
        
        btn:SetScript("OnEnter", function(self)
            ProximityList._mouseOverButton = true
            
            local link = (ProximityList.displayMode == "VENDOR" and self.itemData and self.itemData.link) or (self.discovery and (self.discovery.il or self.discovery.i))
            
            
            if link and not IsAltKeyDown() then
                local tooltip = GameTooltip
                
                if f:GetParent() == WorldMapFrame then
                    tooltip:SetParent(WorldMapFrame)
                    tooltip:SetFrameLevel(f:GetFrameLevel() + 10)
                else
                    tooltip:SetParent(UIParent)
                end
                tooltip:SetFrameStrata("TOOLTIP")
                
                tooltip:SetOwner(self, "ANCHOR_RIGHT")
                
                if type(link) == "number" then
                    tooltip:SetHyperlink("item:" .. link)
                else
                    tooltip:SetHyperlink(link)
                end
                
                tooltip:Show()
            end

            
            if self.mapPin and self.mapPin:IsShown() then
                 local Map = L:GetModule("Map", true)
                 if Map and Map.HighlightPin then
                    Map:HighlightPin(self.mapPin)
                 else
                    self.mapPin:SetScale(1.5)
                 end
            end
        end)
        
        btn:SetScript("OnLeave", function(self)
            ProximityList._mouseOverButton = false
            GameTooltip:Hide()
            
            
            if f:GetParent() == WorldMapFrame then
                 GameTooltip:SetParent(UIParent)
            end
            
            
            if self.mapPin then
                 local Map = L:GetModule("Map", true)
                 if Map and Map.ClearPinHighlight then
                    Map:ClearPinHighlight()
                 end
                 self.mapPin:SetScale(1.0)
            end
        end)
        
        table.insert(self._buttons, btn)
    end
    
    f:SetScript("OnEnter", nil)
    f:SetScript("OnLeave", nil)

    self:UnregisterEvent("WORLD_MAP_UPDATE")
end

function ProximityList:Refresh()
    if not self._frame then return end
    
    
    if WorldMapFrame and WorldMapFrame:IsShown() then
         local mapSize = WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.size
         if mapSize == WORLDMAP_QUESTLIST_SIZE or mapSize == WORLDMAP_FULLMAP_SIZE then
             self._frame:SetParent(WorldMapFrame)
             self._frame:SetFrameStrata("FULLSCREEN_DIALOG")
             self._frame:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 200)
         else
             self._frame:SetParent(UIParent)
             self._frame:SetFrameStrata("DIALOG")
         end
    else
         self._frame:SetParent(UIParent)
         self._frame:SetFrameStrata("DIALOG")
    end

    if not self._frame:IsShown() then return end

    local Map = L:GetModule("Map", true)
    if not Map then return end

    if self._lastHoveredPin then
        self._lastHoveredPin:SetScale(1.0)
        self._lastHoveredPin = nil
    end

    if self.displayMode == "CLUSTER" then
        if not self.currentCluster then self:Hide("Refresh-NoClusterData"); return end
        self._frame.title:SetText("Nearby Discoveries")
        self._frame.title:SetTextColor(1, 1, 1)
        local total = #self.currentCluster

        for i = 1, MAX_VISIBLE_ROWS do
            local btn = self._buttons[i]
            local pin = self.currentCluster[i]

            if pin and pin.discovery then
                local d = pin.discovery
                btn.discovery = d
                btn.itemData = nil
                btn.mapPin = pin
                
                if i % 2 == 0 then
                    btn.bg:SetVertexColor(0.1, 0.1, 0.1, 0.3)
                else
                    btn.bg:SetVertexColor(0, 0, 0, 0.1)
                end
                
                local iconTexture = Map:GetDiscoveryIcon(d)
                btn.icon:SetTexture(iconTexture)
                
                local Constants = L:GetModule("Constants", true)
                local isVendor = d.dt and Constants and d.dt == Constants.DISCOVERY_TYPE.BLACKMARKET
                
                if isVendor then
                    local vendorName = d.vendorName or "Unknown Vendor"
                    btn.text:SetText(vendorName)
                    if d.vendorType == "MS" or (d.g and d.g:find("MS-", 1, true)) then
                        btn.text:SetTextColor(1, 0.82, 0)
                    else
                        btn.text:SetTextColor(0.85, 0.44, 0.85)
                    end
                else
                    local _, _, quality = GetItemInfo(d.il or d.i or 0)
                    local r, g, b = GetQualityColor(quality)
                    btn.text:SetText(d.il or d.n or "Unknown")
                    btn.text:SetTextColor(r, g, b)
                end
                
                btn:ClearAllPoints()
                if i == 1 then
                    btn:SetPoint("TOPLEFT", self._frame.content, "TOPLEFT", 0, 0)
                else
                    btn:SetPoint("TOPLEFT", self._buttons[i-1], "BOTTOMLEFT", 0, -2)
                end
                btn:Show()
            else
                btn:Hide()
                btn.discovery = nil
                btn.mapPin = nil
            end
        end
        self._frame.content:SetHeight(total * (ROW_HEIGHT + 2))

    elseif self.displayMode == "VENDOR" then
        if not self.currentVendorData or not self.currentVendorData.vendorItems then self:Hide("Refresh-NoVendorData"); return end
        
        local v = self.currentVendorData
        if v.vendorType == "BM" or (v.g and v.g:find("BM-", 1, true)) then
            self._frame.title:SetText(v.vendorName .. "'s Items")
            self._frame.title:SetTextColor(0.85, 0.44, 0.85)
        else
            self._frame.title:SetText(v.vendorName .. "'s Items")
            self._frame.title:SetTextColor(1, 0.82, 0)
        end

        local items = self.currentVendorData.vendorItems
        local total = #items

        for i = 1, MAX_VISIBLE_ROWS do
            local btn = self._buttons[i]
            local itemData = items[i]

            if itemData then
                btn.discovery = self.currentVendorData
                btn.itemData = itemData
                btn.mapPin = nil
                
                if i % 2 == 0 then
                    btn.bg:SetVertexColor(0.1, 0.1, 0.1, 0.3)
                else
                    btn.bg:SetVertexColor(0, 0, 0, 0.1)
                end

                local _, _, quality, _, _, _, _, _, _, iconTexture = GetItemInfo(itemData.link)
                btn.icon:SetTexture(iconTexture)
                
                local r, g, b = GetQualityColor(quality)
                btn.text:SetText(itemData.link)
                btn.text:SetTextColor(r, g, b)
                
                btn:ClearAllPoints()
                if i == 1 then
                    btn:SetPoint("TOPLEFT", self._frame.content, "TOPLEFT", 0, 0)
                else
                    btn:SetPoint("TOPLEFT", self._buttons[i-1], "BOTTOMLEFT", 0, -2)
                end
                btn:Show()
            else
                btn:Hide()
                btn.discovery = nil
                btn.itemData = nil
                btn.mapPin = nil
            end
        end
        self._frame.content:SetHeight(total * (ROW_HEIGHT + 2))
    else
        self:Hide("Refresh-UnknownMode")
    end
end

function ProximityList:Hide(reason)
    reason = reason or "unknown"
    L._debug("ProximityList", "Hide() called. Reason: " .. tostring(reason))
    self._mouseOverButton = false
    if self._frame then
        self._frame:Hide()
    end
    if self._lastHoveredPin then
        self._lastHoveredPin:SetScale(1.0)
        self._lastHoveredPin = nil
    end
    self.displayMode = nil
    self.currentCluster = nil
    self.currentVendorData = nil
end

function ProximityList:IsShown()
    return self._frame and self._frame:IsShown()
end

function ProximityList:UpdateForPin(hoveredPin)
    
    if self.displayMode == "VENDOR" then return end
    
    
    
    if not hoveredPin or not hoveredPin:IsShown() or not hoveredPin.discovery then
        
        return
    end

    self._lastHoveredPin = hoveredPin

    local Map = L:GetModule("Map", true)
    if not Map then return end

    
    local hd = hoveredPin.discovery
    if not hd or not hd.xy then return end
    
    local hx, hy = hd.xy.x, hd.xy.y
    
    local mapW, mapH = WorldMapDetailFrame:GetWidth(), WorldMapDetailFrame:GetHeight()
    if not mapW or mapW == 0 or not mapH or mapH == 0 then return end
    
    local cluster = {}
    
    for _, pin in ipairs(Map.pins) do
        if pin:IsShown() and pin.discovery and pin.discovery.xy then
            local pd = pin.discovery
            
            local dx = (hx - pd.xy.x) * mapW
            local dy = (hy - pd.xy.y) * mapH
            local distSq = dx*dx + dy*dy
            
            if distSq <= CLUSTER_RADIUS_SQ then
                table.insert(cluster, pin)
            end
        end
    end
    
    L._debug("ProximityList", "Found " .. #cluster .. " pins in cluster.")

    if #cluster > 1 then
        self.displayMode = "CLUSTER"
        self.currentCluster = cluster
        self.currentVendorData = nil 
        if not self._frame then self:CreateFrame() end
        self._frame:Show()
        self:Refresh()
        L._debug("ProximityList", "Showing proximity list for CLUSTER.")
        return true 
    else
        self.currentCluster = nil
        
        self:Hide("UpdateForPin-NoCluster")
        L._debug("ProximityList", "Not a cluster, hiding proximity list.")
        return false 
    end
end

function ProximityList:ShowVendorInventory(vendorDiscovery)
    if not vendorDiscovery or not vendorDiscovery.vendorItems or #vendorDiscovery.vendorItems == 0 then
        self:Hide("ShowVendorInventory-Invalid")
        return
    end
    L._debug("ProximityList", "ShowVendorInventory called for: " .. (vendorDiscovery.vendorName or "Unknown Vendor"))

    self.displayMode = "VENDOR"
    self.currentVendorData = vendorDiscovery
    self.currentCluster = nil

    if not self._frame then self:CreateFrame() end
    self._frame:Show()
    self:Refresh()
end

function ProximityList:OnInitialize()
    if L.LEGACY_MODE_ACTIVE then return end
    
    if not self._frame then
        self:RegisterEvent("WORLD_MAP_UPDATE", "CreateFrame")
    end
end

return ProximityList