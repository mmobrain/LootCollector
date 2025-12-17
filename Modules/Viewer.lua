

local L = LootCollector
local Viewer = L:NewModule("Viewer")

function ViewerSetSelectedRow(row)
    if Viewer and Viewer.SetSelectedRow then
        Viewer:SetSelectedRow(row)
    end
end

local SOURCE_NAMES = {
    ["world_loot"] = "World Drop",
    ["mail"] = "Mail",
    ["npc_gossip"] = "NPC Gossip",
    ["emote_event"] = "Emote Event",
    ["direct"] = "Direct",
    ["quest"] = "Quest",
    ["trade"] = "Trade",
    ["crafting"] = "Crafting",
    ["unknown"] = "Unknown"
}

local QUALITY_NAMES = {
    [0] = "Poor",
    [1] = "Common",
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Epic",
    [5] = "Legendary",
    [6] = "Artifact",
    [7] = "Heirloom"
}

local CLASS_ABBREVIATIONS_REVERSE = {
  ["wa"] = "WARRIOR", ["pa"] = "PALADIN", ["hu"] = "HUNTER", ["ro"] = "ROGUE",
  ["pr"] = "PRIEST", ["dk"] = "DEATHKNIGHT", ["sh"] = "SHAMAN", ["ma"] = "MAGE",
  ["lo"] = "WARLOCK", ["dr"] = "DRUID",
}

local CLASS_OPTIONS = {
  "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","DEATHKNIGHT","SHAMAN","MAGE","WARLOCK","DRUID",
}

Viewer.lootedFilterState = nil 

local time = time or os.time

local WINDOW_WIDTH = 968
local WINDOW_HEIGHT = 630
local ROW_HEIGHT = 20
local HEADER_HEIGHT = 25
local BUTTON_HEIGHT = 22
local BUTTON_WIDTH = 80
local CONTEXT_MENU_WIDTH = 200
local FRAME_LEVEL = 1
local FRAME_STRATA = "MEDIUM"

local GRID_LAYOUT = {
    
    NAME_WIDTH = 246,
    LEVEL_WIDTH = 26,
    SLOT_WIDTH = 90,
    TYPE_WIDTH = 130,
    CLASS_WIDTH = 70,
    ZONE_WIDTH = 150,       
    FOUND_BY_WIDTH = 120,
    VENDOR_NAME_WIDTH = 250,
    VENDOR_ZONE_WIDTH = 200,
    VENDOR_INVENTORY_WIDTH = 100,

    
    COLUMN_SPACING = 5,
}

local ROW_FONT_NAME = "LootCollectorViewerRowFont"
local ROW_FONT_SIZE = 13

Viewer.window         = nil
Viewer.scrollFrame    = nil
Viewer.rows           = {}
Viewer.selectedRow    = nil
Viewer.currentFilter  = "equipment" 
Viewer.searchTerm     = ""
Viewer.sortColumn     = "name"      
Viewer.sortAscending  = true
Viewer.pendingMapAreaID = nil

Viewer.currentPage    = 1
Viewer.itemsPerPage   = 50
Viewer.totalItems     = 0

Viewer.columnFilters  = {
    eq       = { slot = {}, type = {}, class = {} },
    ms       = { class = {} },
    zone     = {},
    source   = {},
    quality  = {},
    looted   = {},
    duplicates = false,
}

Viewer.vendorInventoryFrame = nil      
Viewer.vendorInventoryLines = nil      
Viewer.selectedVendorGuid   = nil      

local function VDebug(msg)
    if L and L._debug then
        L._debug("Viewer-Debug", msg)
    end
end

local _next = next
local _getmt, _setmt = getmetatable, setmetatable
local _rawlen = rawlen or function(x) return #x end
local _tinsert = table.insert
local _tremove = table.remove
local _tsort = table.sort
local _tconcat = table.concat
local _strlower = string.lower
local _strfind = string.find
local _strmatch = string.match
local _strgsub = string.gsub

local activeTimers = {} 

local function copy(t)
    local out = {}
    for k, v in _next, t do out[k] = v end
    local mt = _getmt(t)
    if mt then _setmt(out, mt) end
    return out
end

local function createTimer(delay, callback)
    local timer = C_Timer.After(delay, callback)
    _tinsert(activeTimers, timer)
    return timer
end

local function clearAllTimers()
    for i = #activeTimers, 1, -1 do
        _tremove(activeTimers, i)
    end
end

local function concatStrings(...)
    local args = { ... }
    local result = {}
    local count = 0
    for i = 1, #args do
        if args[i] then
            count = count + 1
            result[count] = tostring(args[i])
        end
    end
    return _tconcat(result)
end

local function size(t)
    if t[1] ~= nil then
        return _rawlen(t)
    end
    local n = 0
    for _ in _next, t do n = n + 1 end
    return n
end

local function keys(t)
    local out = {}
    local i = 0
    for k in _next, t do
        i = i + 1
        out[i] = k
    end
    return out
end

local function values(t)
    local out = {}
    local i = 0
    for _, v in _next, t do
        i = i + 1
        out[i] = v
    end
    return out
end

local function filter(array, predicate)
    local n = _rawlen(array)
    local wi = 1
    for i = 1, n do
        local v = array[i]
        if predicate(v, i) then
            if wi ~= i then array[wi] = v end
            wi = wi + 1
        end
    end
    for i = wi, n do array[i] = nil end
    return array
end

local function GetQualityColor(quality)
    quality = tonumber(quality)
    if not quality then return 1, 1, 1 end
    if _G.GetItemQualityColor then
        local r, g, b = _G.GetItemQualityColor(quality)
        if r and g and b then return r, g, b end
    end
    if _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality] then
        local c = _G.ITEM_QUALITY_COLORS[quality]
        return c.r or 1, c.g or 1, c.b or 1
    end
    return 1, 1, 1
end

local Cache = {
    
    discoveries = {},
    discoveriesBuilt = false,
    discoveriesBuilding = false,

    
    itemInfo = {},

    
    characterClass = {},

    
    worldforged = {},

    
    zoneNames = {},

    
    uniqueValues = {
        slot = {},
        type = {},
        class = {},
        zone = {}
    },
    uniqueValuesValid = false,

    
    filteredResults = {},
    lastFilterState = nil,

    
    duplicateItems = {},

    
    _cleanupRequired = false,
}

L.itemInfoCache = L.itemInfoCache or {}

local function GetItemTypeIDs(itemType, itemSubType)
    local Constants = L:GetModule("Constants", true)
    if not Constants then return 0, 0 end
    
    local it = Constants.ITEM_TYPE_TO_ID[itemType] or 0
    local ist = Constants.ITEM_SUBTYPE_TO_ID[itemSubType] or 0
    return it, ist
end

local function GetItemInfoSafe(itemLink, itemID)
    if not itemLink then return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil end

    
    if itemID and Cache.itemInfo[itemID] then
        return unpack(Cache.itemInfo[itemID])
    end

    local name, link, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, texture, sellPrice =
        GetItemInfo(itemLink)

    if itemID then
        Cache.itemInfo[itemID] = { name, link, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc,
            texture, sellPrice }
        
        L.itemInfoCache[itemID] = Cache.itemInfo[itemID]
    end

    return name, link, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, texture, sellPrice
end

local function GetLocalizedZoneName(discovery)
    if not discovery then
        return "Unknown Zone"
    end

    
    local c = tonumber(discovery.c) or 0
    local z = tonumber(discovery.z) or 0
    local iz = tonumber(discovery.iz) or 0

    
    local cacheKey = string.format("%d:%d:%d", c, z, iz)
    if Cache.zoneNames[cacheKey] then
        return Cache.zoneNames[cacheKey]
    end

    local ZoneList = L:GetModule("ZoneList", true)
    local localizedZoneName = "Unknown Zone"

    if ZoneList and ZoneList.GetZoneName then
        
        localizedZoneName = ZoneList:GetZoneName(c, z, iz) or "Unknown Zone"
    end

    
    Cache.zoneNames[cacheKey] = localizedZoneName
    return localizedZoneName
end

local localClassScanTip = CreateFrame("GameTooltip", "LootCollectorClassScanTooltip", UIParent, "GameTooltipTemplate")
localClassScanTip:SetOwner(UIParent, "ANCHOR_NONE")

local VALID_CLASSES = {
    ["Warrior"] = true, ["Paladin"] = true, ["Hunter"] = true,
    ["Rogue"] = true, ["Priest"] = true, ["Shaman"] = true,
    ["Mage"] = true, ["Warlock"] = true, ["Druid"] = true
}

local function GetItemCharacterClass(itemLink, itemID)
    if not itemLink or not itemID then return "" end

    
    local cached = Cache.characterClass[itemID]
    if cached ~= nil then
        return cached
    end

    local characterClass = ""
    localClassScanTip:SetHyperlink(itemLink)
    
    local line2Text = _G["LootCollectorClassScanTooltipTextLeft2"]:GetText()
    if line2Text then
        
        local plainText = line2Text:match("^|c%x%x%x%x%x%x%x%x(.+)|r$") or line2Text
        
        local className = plainText:match("^%s*(.-)%s*$")
        
        
        if VALID_CLASSES[className] then
            characterClass = line2Text
        end
    end

    Cache.characterClass[itemID] = characterClass
    return characterClass
end

local localWorldforgedScanTip = CreateFrame("GameTooltip", "LootCollectorViewerScanTip", UIParent, "GameTooltipTemplate")
localWorldforgedScanTip:SetOwner(UIParent, "ANCHOR_NONE")

local function IsWorldforged(itemLink)
    if not itemLink then return false end

    
    local cached = Cache.worldforged[itemLink]
    if cached ~= nil then
        return cached
    end

    
    local Core = L:GetModule("Core", true)
    local tooltip, tooltipName
    
    if Core and Core._scanTip then
        tooltip = Core._scanTip
        tooltipName = "LootCollectorCoreScanTipTextLeft"
    else
        if not localWorldforgedScanTip then
            localWorldforgedScanTip = CreateFrame("GameTooltip", "LootCollectorViewerScanTip", UIParent, "GameTooltipTemplate")
            localWorldforgedScanTip:SetOwner(UIParent, "ANCHOR_NONE")
        end
        tooltip = localWorldforgedScanTip
        tooltipName = "LootCollectorViewerScanTipTextLeft"
    end

    tooltip:ClearLines()
    tooltip:SetHyperlink(itemLink)

    
    local isWorldforged = false
    for i = 2, 5 do
        local text = _G[tooltipName .. i]:GetText()
        if text and _strfind(text, "orldforged", 1, true) then
            isWorldforged = true
            break
        end
    end

    Cache.worldforged[itemLink] = isWorldforged
    return isWorldforged
end

local function IsMysticScroll(itemName)
    return itemName and _strfind(itemName, "Mystic Scroll", 1, true) ~= nil
end

function Viewer:EnsureVendorInventoryPanel()
    if self.vendorInventoryFrame then
        return
    end

    if not (self.window and self.scrollFrame) then
        
        return
    end

    local parent   = self.window
    local listArea = self.scrollFrame

    
    
    local f = CreateFrame("Frame", "LootCollectorViewerVendorInventory", parent)

    
    f:SetFrameStrata(FRAME_STRATA or "DIALOG")
    f:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
    f:EnableMouse(true)
    f:SetToplevel(true)

    f:SetPoint("TOPRIGHT",    listArea, "TOPRIGHT",   -2, 0)
    f:SetPoint("BOTTOMRIGHT", listArea, "BOTTOMRIGHT", -2, 0)
    f:SetWidth(260)

    
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)

    
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetWidth(240)
    f.title:SetJustifyH("LEFT")
    f.title:SetText("Vendor Inventory")

    
    local invScroll = CreateFrame("ScrollFrame", nil, f, "FauxScrollFrameTemplate")
    invScroll:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
    invScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 0)

    f.itemLines = {}
     for i = 1, 18 do 
        local line = CreateFrame("Button", nil, f)
        line:SetHeight(20)
        
        
        line:SetPoint("RIGHT", invScroll, "RIGHT", 0, 0)
        line:SetPoint("LEFT", invScroll, "LEFT", 8, 0)
        
        if i == 1 then
            line:SetPoint("TOPLEFT", invScroll, "TOPLEFT", 8, 0)
        else
            line:SetPoint("TOPLEFT", f.itemLines[i-1], "BOTTOMLEFT", 0, 0)
        end
        
        line.icon = line:CreateTexture(nil, "ARTWORK")
        line.icon:SetSize(18, 18)
        line.icon:SetPoint("LEFT", 0, 0)
        line.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

        line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.text:SetPoint("LEFT", line.icon, "RIGHT", 4, 0)
        line.text:SetPoint("RIGHT", 0, 0)
        line.text:SetJustifyH("LEFT")
        line.text:SetText("")

        line.itemLink         = nil
        line.parentVendorData = nil

        line:SetScript("OnEnter", function(self)
            if self.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.itemLink)
                GameTooltip:Show()
            end
        end)

        line:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        line:SetScript("OnClick", function(self)
	    
	    if IsShiftKeyDown() then
		  if self.parentVendorData then
			Viewer:ShowOnMap(self.parentVendorData)
		  end
		  return
	    end

	    
	    
	    if self.itemLink then
		  HandleModifiedItemClick(self.itemLink)
	    end
end)

        line:Hide()
        f.itemLines[i] = line
    end
    
    
    local function refreshInventory()
        if Viewer.selectedVendorGuid then
            local dbVendors = L:GetVendorsDB()
            local d = dbVendors and dbVendors[Viewer.selectedVendorGuid]
            
            if d and d.vendorItems then
                f.title:SetText(d.vendorName .. "'s Inventory")
                
                local numItems = #d.vendorItems
                FauxScrollFrame_Update(invScroll, numItems, 18, 20)
                local offset = FauxScrollFrame_GetOffset(invScroll)
                
                for i = 1, 18 do
                    local line = f.itemLines[i]
                    local idx = offset + i
                    if idx <= numItems then
                        local itemData = d.vendorItems[idx]
                        if itemData then
                            local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemData.link)
                            line.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                            line.text:SetText(itemData.link)
                            line.itemLink = itemData.link
                            line.parentVendorData = d
                            line:Show()
                        else
                            line:Hide()
                        end
                    else
                        line:Hide()
                    end
                end
            else
                f.title:SetText("Vendor Inventory")
                FauxScrollFrame_Update(invScroll, 0, 18, 20)
                for _, line in ipairs(f.itemLines) do line:Hide() end
            end
        else
            f.title:SetText("Select a vendor to view inventory")
            FauxScrollFrame_Update(invScroll, 0, 18, 20)
            for _, line in ipairs(f.itemLines) do line:Hide() end
        end
    end

    
    invScroll:SetScript("OnVerticalScroll", function(s, dlt)
        FauxScrollFrame_OnVerticalScroll(s, dlt, 20, refreshInventory)
    end)
    
    
    f.refreshInventory = refreshInventory

    f.scrollFrame   = invScroll 
    f.vendorItems   = {}

    self.vendorInventoryFrame = f
    self.vendorInventoryLines = f.itemLines

    f:Hide()
end

function Viewer:UpdateVendorInventoryScroll()
    if self.vendorInventoryFrame and self.vendorInventoryFrame.refreshInventory then
        self.vendorInventoryFrame.refreshInventory()
    end
end

function Viewer:ShowVendorInventoryForDiscovery(discovery)
    if not discovery then
        return
    end

    self:EnsureVendorInventoryPanel()
    local f     = self.vendorInventoryFrame
    local lines = self.vendorInventoryLines

    if not f or not lines then
        return
    end

    
    if not discovery.vendorItems or type(discovery.vendorItems) ~= "table" then
        self.selectedVendorGuid = discovery.g
        f.vendorItems           = {}
        f.vendorData            = discovery
        f.title:SetText("Vendor Inventory")
        self:UpdateVendorInventoryScroll()
        f:Show()
        return
    end

    self.selectedVendorGuid = discovery.g
    f.vendorItems           = discovery.vendorItems
    f.vendorData            = discovery

    
    local vendorName = discovery.vendorName or "Unknown Vendor"
    local zoneName   = GetLocalizedZoneName and GetLocalizedZoneName(discovery) or nil

    if zoneName and zoneName ~= "" and zoneName ~= "Unknown Zone" then
        f.title:SetText(vendorName .. " – " .. zoneName)
    else
        f.title:SetText(vendorName .. " Inventory")
    end

    
    if f.scrollFrame then
        f.scrollFrame.offset = 0
        f.scrollFrame:SetVerticalScroll(0)
    end

    self:UpdateVendorInventoryScroll()
    f:Show()
end

local GetCascadedFilterContext, GetFilteredDatasetForUniqueValues, GetUniqueValues

GetCascadedFilterContext = function(excludeColumn)
    local context = {
        currentFilter = Viewer.currentFilter,
        searchTerm = Viewer.searchTerm,
        excludeColumn = excludeColumn
    }

    context.activeFilters = {}

    if Viewer.currentFilter == "eq" then
        if excludeColumn ~= "slot" and size(Viewer.columnFilters.eq.slot) > 0 then
            context.activeFilters.slot = Viewer.columnFilters.eq.slot
        end
        if excludeColumn ~= "type" and size(Viewer.columnFilters.eq.type) > 0 then
            context.activeFilters.type = Viewer.columnFilters.eq.type
        end
        
        if excludeColumn ~= "class" and size(Viewer.columnFilters.eq.class) > 0 then
            context.activeFilters.class = Viewer.columnFilters.eq.class
        end
    elseif Viewer.currentFilter == "ms" then
        if excludeColumn ~= "class" and size(Viewer.columnFilters.ms.class) > 0 then
            context.activeFilters.class = Viewer.columnFilters.ms.class
        end
    end

    
    if excludeColumn ~= "zone" and size(Viewer.columnFilters.zone) > 0 then
        context.activeFilters.zone = Viewer.columnFilters.zone
    end

    
    if excludeColumn ~= "source" and size(Viewer.columnFilters.source) > 0 then
        context.activeFilters.source = Viewer.columnFilters.source
    end

    
    if excludeColumn ~= "quality" and size(Viewer.columnFilters.quality) > 0 then
        context.activeFilters.quality = Viewer.columnFilters.quality
    end

    
    if excludeColumn ~= "looted" and size(Viewer.columnFilters.looted) > 0 then
        context.activeFilters.looted = Viewer.columnFilters.looted
    end

    
    if excludeColumn ~= "duplicates" and Viewer.columnFilters.duplicates then
        context.activeFilters.duplicates = { enabled = true }
    end

    return context
end

local function removeFromSpecialFrames(windowName)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == windowName then
            _tremove(UISpecialFrames, i)
            return true
        end
    end
    return false
end

local function addToSpecialFrames(windowName)
    
    for i = 1, #UISpecialFrames do
        if UISpecialFrames[i] == windowName then
            return false 
        end
    end
    _tinsert(UISpecialFrames, windowName)
    return true
end

GetFilteredDatasetForUniqueValues = function(context)
    local filteredData = filter(values(Cache.discoveries), function(data)
        
        if context.currentFilter == "eq" then
            if data.isVendor or data.isMystic then return false end
        elseif context.currentFilter == "ms" then
            if data.isVendor or not data.isMystic then return false end
        elseif context.currentFilter == "bmv" then
            if not data.isVendor or data.vendorType ~= "BM" then return false end
        elseif context.currentFilter == "msv" then
            if not data.isVendor or data.vendorType ~= "MS" then return false end
        end

        
        if context.searchTerm and context.searchTerm ~= "" then
            local searchLower = _strlower(context.searchTerm)
            local nameMatch = false
            if data.isVendor then
                nameMatch = _strfind(_strlower(data.vendorName or ""), searchLower, 1, true)
            else
                nameMatch = _strfind(_strlower(data.itemName or ""), searchLower, 1, true)
            end
            
            local zoneName = GetLocalizedZoneName(data.discovery)
            local zoneMatch = _strfind(_strlower(zoneName), searchLower, 1, true)
            if not (nameMatch or zoneMatch) then return false end
        end

        
        if context.activeFilters.slot then
            local slotValue = data.equipLoc and _G[data.equipLoc] or ""
            if not context.activeFilters.slot[slotValue] then return false end
        end

        
        if context.activeFilters.type then
            local typeValue = data.itemSubType or ""
            if not context.activeFilters.type[typeValue] then return false end
        end

        
        if context.activeFilters.class then
            if context.currentFilter == "eq" then
                
                local Constants = L:GetModule("Constants", true)
                if Constants and Constants.CLASS_PROFICIENCIES then
                    local subTypeID = data.ist
                    local typeID = data.it
                    
                    if subTypeID and typeID and subTypeID > 0 and typeID > 0 then
                        local canUse = false
                        for classFilterName, _ in pairs(context.activeFilters.class) do
                             
                             local classToken = nil
                             if _G.LOCALIZED_CLASS_NAMES_MALE then
                                 for token, locName in pairs(_G.LOCALIZED_CLASS_NAMES_MALE) do
                                     if locName == classFilterName then classToken = token; break end
                                 end
                             end
                             if not classToken and _G.LOCALIZED_CLASS_NAMES_FEMALE then
                                 for token, locName in pairs(_G.LOCALIZED_CLASS_NAMES_FEMALE) do
                                     if locName == classFilterName then classToken = token; break end
                                 end
                             end
                             if not classToken then classToken = string.upper(classFilterName) end
                             
                             local profs = Constants.CLASS_PROFICIENCIES[classToken]
                             if profs then
                                 local list = nil
                                 if typeID == Constants.ITEM_TYPE_TO_ID["Armor"] then list = profs.armor
                                 elseif typeID == Constants.ITEM_TYPE_TO_ID["Weapon"] then list = profs.weapons end
                                 
                                 if list then
                                     for _, allowedID in ipairs(list) do
                                         if subTypeID == allowedID then canUse = true; break end
                                     end
                                 else
                                     canUse = true 
                                 end
                             end
                             if canUse then break end
                        end
                        if not canUse then return false end
                    else
                        
                        return false
                    end
                end
            else
                
                local classValue = data.characterClass or ""
                if data.cl and data.cl ~= "cl" then
                    local classToken = CLASS_ABBREVIATIONS_REVERSE[data.cl]
                    if classToken then
                        classValue = (_G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[classToken]) or classToken
                    end
                end
                if classValue == "" then classValue = data.characterClass or "" end
                if not context.activeFilters.class[classValue] then return false end
            end
        end

        
        if context.activeFilters.zone then
            local zoneValue = GetLocalizedZoneName(data.discovery)
            if not context.activeFilters.zone[zoneValue] then return false end
        end

        
        if context.activeFilters.source then
            local source = data.discovery.src or "unknown"
            local sourceValue = SOURCE_NAMES[source] or source
            if not context.activeFilters.source[sourceValue] then return false end
        end

        
        if context.activeFilters.quality then
            local _, _, quality = GetItemInfoSafe(data.discovery.il, data.discovery.i)
            if not quality then
                if not context.activeFilters.quality["Unknown"] then return false end
            else
                local qualityValue = QUALITY_NAMES[quality] or ("Quality " .. tostring(quality))
                if not context.activeFilters.quality[qualityValue] then return false end
            end
        end

        
        if Viewer.lootedFilterState ~= nil then
            local isLooted = Viewer:IsLootedByChar(data.guid)
            if Viewer.lootedFilterState == true and not isLooted then return false end
            if Viewer.lootedFilterState == false and isLooted then return false end
        end

        
        if context.activeFilters.duplicates then
            
            if not Cache.duplicateItems[data.discovery.i] or Cache.duplicateItems[data.discovery.i] <= 1 then
                return false
            end
        end

        return true
    end)

    return filteredData
end

GetUniqueValues = function(column)
    
    local context = GetCascadedFilterContext(column)
    local cacheKey = column .. ":" .. context.currentFilter .. ":" .. context.searchTerm

    
    local filterKeys = {}
    for filterType, filters in pairs(context.activeFilters) do
        if filterType == "duplicates" then
            
            _tinsert(filterKeys, filterType .. "=enabled")
        else
            local sortedKeys = keys(filters)
            _tsort(sortedKeys)
            _tinsert(filterKeys, filterType .. "=" .. _tconcat(sortedKeys, ","))
        end
    end
    if size(filterKeys) > 0 then
        cacheKey = cacheKey .. ":" .. _tconcat(filterKeys, "|")
    end

    
    if not Cache.uniqueValuesContext then
        Cache.uniqueValuesContext = {}
    end

    if Cache.uniqueValuesContext[cacheKey] then
        return Cache.uniqueValuesContext[cacheKey]
    end
    
    
    
    
    if column == "class" and Viewer.currentFilter == "eq" then
         local values = {}
         for _, classToken in ipairs(CLASS_OPTIONS) do
             local locName = (_G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[classToken]) or classToken
             _tinsert(values, locName)
         end
         _tsort(values)
         Cache.uniqueValuesContext[cacheKey] = values
         return values
    end

    
    local filteredDataset = GetFilteredDatasetForUniqueValues(context)
    local values = {}
    local seen = {}

    
    if column == "zone" then
        local ZoneList = L:GetModule("ZoneList", true)
        local zoneByKey = {}

        
        for _, data in ipairs(filteredDataset) do
            local discovery = data.discovery
            if discovery then
                local c = tonumber(discovery.c) or 0
                local z = tonumber(discovery.z) or 0
                local iz = tonumber(discovery.iz) or 0
                local key = string.format("%d:%d:%d", c, z, iz)
                
                if not zoneByKey[key] then
                    zoneByKey[key] = { c = c, z = z, iz = iz }
                end
            end
        end

        
        for key, zoneData in pairs(zoneByKey) do
            local localizedZoneName = GetLocalizedZoneName(zoneData)

            if localizedZoneName and localizedZoneName ~= "" and not seen[localizedZoneName] then
                seen[localizedZoneName] = true
                _tinsert(values, localizedZoneName)
            end
        end
    else
        
        local NUMERIC_SOURCE_MAP = {
            [0] = "world_loot",
            [1] = "npc_gossip",
            [2] = "emote_event",
            [3] = "direct",
        }

        
       local columnExtractor = {
            slot = function(data) return data.equipLoc and _G[data.equipLoc] or "" end,
            type = function(data) return data.itemSubType or "" end,
            
            class = function(data)
                if data.cl and data.cl ~= "cl" then
                    local classToken = CLASS_ABBREVIATIONS_REVERSE[data.cl]
                    if classToken then
                        return _G.LOCALIZED_CLASS_NAMES_MALE[classToken] or _G.LOCALIZED_CLASS_NAMES_FEMALE[classToken] or ""
                    end
                end
                
                return data.characterClass or ""
            end,
            source = function(data)
                local raw = data.discovery.src
                
                if type(raw) == "number" then
                    raw = NUMERIC_SOURCE_MAP[raw] or "unknown"
                end
                
                local sourceKey = raw or "unknown"
                
                return SOURCE_NAMES[sourceKey] or tostring(sourceKey)
            end,
            quality = function(data)
                local _, _, quality = GetItemInfoSafe(data.discovery.il, data.discovery.i)
                if not quality then return "Unknown" end
                return QUALITY_NAMES[quality] or ("Quality " .. tostring(quality))
            end,
            looted = function(data)
                return Viewer:IsLootedByChar(data.guid) and "Looted" or "Not Looted"
            end
        }

        local extractor = columnExtractor[column]
        if extractor then
            for _, data in ipairs(filteredDataset) do
                local value = extractor(data)
                if value and value ~= "" and not seen[value] then
                    seen[value] = true
                    _tinsert(values, value)
                end
            end
        end
    end

    
    if column == "quality" then
        
        local qualityOrder = {
            ["Heirloom"] = 7,
            ["Artifact"] = 6,
            ["Legendary"] = 5,
            ["Epic"] = 4,
            ["Rare"] = 3,
            ["Uncommon"] = 2,
            ["Common"] = 1,
            ["Poor"] = 0,
            ["Unknown"] = -1
        }

        _tsort(values, function(a, b)
            local aOrder = qualityOrder[a] or 999
            local bOrder = qualityOrder[b] or 999
            return aOrder > bOrder 
        end)
    else
        
        _tsort(values)
    end

    
    Cache.uniqueValuesContext[cacheKey] = values

    return values
end

local scanQueue = {}
local scanCursor = 0
local scanProgressCallback = nil

local STATUS_UNCONFIRMED = "UNCONFIRMED"
local STATUS_CONFIRMED = "CONFIRMED"
local STATUS_FADING = "FADING"
local STATUS_STALE = "STALE"

local function HasDataChanged()
    
    local discoveries = L:GetDiscoveriesDB()
    if not discoveries then
        return false
    end

    local currentCount = 0
    for _ in pairs(discoveries) do
        currentCount = currentCount + 1
    end

    if not Cache.lastDiscoveryCount then
        Cache.lastDiscoveryCount = currentCount
        return true 
    end

    local hasChanged = Cache.lastDiscoveryCount ~= currentCount
    if hasChanged then
        Cache.lastDiscoveryCount = currentCount
    end

    return hasChanged
end

function Viewer:SetUIEnabled(enabled)
    if not self.window or not self.interactiveElements then return end

    for _, element in ipairs(self.interactiveElements) do
        if element then
            if enabled then
                element:Enable()
            else
                element:Disable()
            end
        end
    end

    
    if self.searchClearBtn then
        if enabled then
            self.searchClearBtn:Enable()
        else
            self.searchClearBtn:Disable()
        end
    end
end

local function CreateContextMenu(anchor, title, buttons, options)
    options = options or {}
    local menuWidth = options.width or CONTEXT_MENU_WIDTH
    local menuHeight = options.height or (20 + 5 + (25 * #buttons) + 20) 

    
    if Viewer.contextMenu then
        Viewer.contextMenu:Hide()
        Viewer.contextMenu = nil
    end

    
    local contextMenu = CreateFrame("Frame", "LootCollectorViewerContextMenu", Viewer.window)
    contextMenu:SetSize(menuWidth, menuHeight)

    
    if anchor.mouseX and anchor.mouseY then
        local uiScale = UIParent:GetEffectiveScale()
        contextMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            anchor.mouseX / uiScale, anchor.mouseY / uiScale)
    else
        
        contextMenu:SetPoint("LEFT", anchor, "RIGHT", 5, 0)
    end

    contextMenu:SetFrameStrata("TOOLTIP")
    contextMenu:EnableMouse(true)

    
    contextMenu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    contextMenu:SetBackdropColor(0.05, 0.05, 0.05, 0.98)

    
    local titleText = contextMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("TOPLEFT", 10, -10)
    titleText:SetText(title)
    titleText:SetTextColor(1, 1, 1)

    
    local separator = contextMenu:CreateTexture(nil, "OVERLAY")
    separator:SetSize(menuWidth - 20, 1)
    separator:SetPoint("TOPLEFT", 10, -30)
    separator:SetColorTexture(0.5, 0.5, 0.5, 0.8)

    
    local lastButton = nil
    for i, buttonData in ipairs(buttons) do
        local btn = CreateFrame("Button", nil, contextMenu, "UIPanelButtonTemplate")
        btn:SetSize(menuWidth - 20, 20) 
        btn:SetFrameLevel(contextMenu:GetFrameLevel() + 1)
        if lastButton then
            btn:SetPoint("TOPLEFT", lastButton, "BOTTOMLEFT", 0, -5)
        else
            btn:SetPoint("TOPLEFT", 10, -40)
        end
        btn:SetText(buttonData.text)
        btn:SetScript("OnClick", function()
            if buttonData.onClick then
                buttonData.onClick()
            end
            contextMenu:Hide()
            Viewer.contextMenu = nil
        end)
        lastButton = btn
    end

    
    contextMenu:SetScript("OnLeave", function(self)
        
        createTimer(0.1, function()
            if Viewer.contextMenu and Viewer.contextMenu:IsShown() then
                local contextMenuMouseOver = Viewer.contextMenu:IsMouseOver()
                local anchorMouseOver = anchor:IsMouseOver()
                
                if not contextMenuMouseOver and not anchorMouseOver then
                    Viewer.contextMenu:Hide()
                    Viewer.contextMenu = nil
                end
            end
        end)
    end)

    contextMenu:Show()
    Viewer.contextMenu = contextMenu

    
    local function OnMouseDown(self, button)
        if Viewer.contextMenu and not Viewer.contextMenu:IsMouseOver() and not anchor:IsMouseOver() then
            Viewer.contextMenu:Hide()
            Viewer.contextMenu = nil
        end
    end

    UIParent:SetScript("OnMouseDown", OnMouseDown)

    
    contextMenu:SetScript("OnHide", function()
        UIParent:SetScript("OnMouseDown", nil)
    end)

    return contextMenu
end

local MAX_LEVELS = 4
local lastAnchor = {}

local function GetEstimatedListHeight(list)
    local h = list:GetHeight()
    if h and h > 0 then return h end

    
    local name = list:GetName()
    local total = 0
    if name then
        for i = 1, (list.numButtons or 32) do
            local btn = _G[name .. "Button" .. i]
            if not btn then break end
            local bh = btn:GetHeight() or 0
            if bh == 0 then bh = 16 end
            total = total + bh
        end
    end
    if total > 0 then return total end

    
    return (list.numButtons or 20) * (list.buttonHeight or 16)
end

local function IsCursorAnchor(anchor)
    if not anchor then return false end
    if type(anchor) == "string" then
        local a = anchor:lower()
        return a:find("cursor") or a:find("mouse")
    end
    return false
end

local function RepositionList(level, dropDownFrame, anchorTo)
    local list = _G["DropDownList" .. (tonumber(level) or 1)]
    if not list then return end

    local needed = GetEstimatedListHeight(list)
    local screenBottom = (UIParent and UIParent:GetBottom()) or 0

    if IsCursorAnchor(anchorTo) then
        
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        x = x / scale
        y = y / scale
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y - 10)
        list:SetClampedToScreen(true)
        return
    end

    
    local anchorFrame = nil
    if type(anchorTo) == "table" and anchorTo.GetBottom then
        anchorFrame = anchorTo
    elseif dropDownFrame and dropDownFrame.GetBottom then
        anchorFrame = dropDownFrame
    elseif type(anchorTo) == "string" then
        
        anchorFrame = dropDownFrame or UIParent
    else
        anchorFrame = dropDownFrame or UIParent
    end

    local frameBottom = (anchorFrame and anchorFrame.GetBottom and anchorFrame:GetBottom()) or 0
    local spaceBelow = frameBottom - screenBottom

    if spaceBelow >= needed then
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, 0)
        list:SetClampedToScreen(true)
    end
end

hooksecurefunc("ToggleDropDownMenu", function(level, value, dropDownFrame, anchorTo, xOffset, yOffset)
    level = tonumber(level) or 1
    lastAnchor[level] = { dropDownFrame = dropDownFrame, anchorTo = anchorTo }
    local list = _G["DropDownList" .. level]
    if list and list:IsShown() then
        RepositionList(level, dropDownFrame, anchorTo)
    end
end)

for i = 1, MAX_LEVELS do
    local list = _G["DropDownList" .. i]
    if list then
        list:HookScript("OnShow", function(self)
            local info = lastAnchor[i] or {}
            RepositionList(i, info.dropDownFrame, info.anchorTo)
        end)
    end
end

local function ShowColumnFilterDropdown(column, anchor, values)
    
    HideDropDownMenu(1)

    
    if not values or #values == 0 then
        
        local fallbackValues = {}
        if Cache.discoveriesBuilt then
            local seen = {}
            if column == "zone" then
                local ZoneList = L:GetModule("ZoneList", true)
                local zoneByKey = {}

                
                for _, data in ipairs(Cache.discoveries) do
                    local discovery = data.discovery
                    if discovery then
                        local c = tonumber(discovery.c) or 0
                        local z = tonumber(discovery.z) or 0
                        local iz = tonumber(discovery.iz) or 0
                        local key = string.format("%d:%d:%d", c, z, iz)
                        
                        if not zoneByKey[key] then
                            zoneByKey[key] = { c = c, z = z, iz = iz }
                        end
                    end
                end

                
                for key, zoneData in pairs(zoneByKey) do
                    local localizedZoneName = GetLocalizedZoneName(zoneData)
                    if localizedZoneName and localizedZoneName ~= "" and not seen[localizedZoneName] then
                        seen[localizedZoneName] = true
                        _tinsert(fallbackValues, localizedZoneName)
                    end
                end
            else
                
                local NUMERIC_SOURCE_MAP = { [0]="world_loot", [1]="npc_gossip", [2]="emote_event", [3]="direct" }
                
                local columnExtractor = {
                    slot = function(data) return data.equipLoc and _G[data.equipLoc] or "" end,
                    type = function(data) return data.itemSubType or "" end,
                    class = function(data) return data.characterClass or "" end,
                    source = function(data)
                        local raw = data.discovery.src
                        if type(raw) == "number" then raw = NUMERIC_SOURCE_MAP[raw] or "unknown" end
                        local sourceKey = raw or "unknown"
                        return SOURCE_NAMES[sourceKey] or tostring(sourceKey)
                    end,
                    quality = function(data)
                        local _, _, quality = GetItemInfoSafe(data.discovery.il, data.discovery.i)
                        if not quality then return "Unknown" end
                        return QUALITY_NAMES[quality] or ("Quality " .. tostring(quality))
                    end,
                    looted = function(data)
                        return Viewer:IsLootedByChar(data.guid) and "Looted" or "Not Looted"
                    end
                }

                local extractor = columnExtractor[column]
                if extractor then
                    for _, data in ipairs(Cache.discoveries) do
                        local value = extractor(data)
                        if value and value ~= "" and not seen[value] then
                            seen[value] = true
                            _tinsert(fallbackValues, value)
                        end
                    end
                end
            end
            _tsort(fallbackValues)
        end

        values = fallbackValues
    end

    
    if not values or #values == 0 then
        return
    end
    
    
    local filterTable
    if column == "zone" then filterTable = Viewer.columnFilters.zone
    elseif column == "source" then filterTable = Viewer.columnFilters.source
    elseif column == "quality" then filterTable = Viewer.columnFilters.quality
    elseif column == "looted" then filterTable = Viewer.columnFilters.looted
    else
        
        filterTable = Viewer.columnFilters[Viewer.currentFilter][column]
    end

    
    local dropdown = CreateFrame("Frame", "LootCollectorViewerFilterDropdown", Viewer.window, "UIDropDownMenuTemplate")

    
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        
        local clearAllInfo = {
            text = "Clear All Filters",
            notCheckable = true,
            func = function()
                if filterTable then
                    wipe(filterTable)
                end

                Viewer.currentPage = 1
                
                Cache.filteredResults = {}
                Cache.lastFilterState = nil
                Cache.uniqueValuesValid = false
                Cache.uniqueValuesContext = {} 
                Viewer:UpdateSortHeaders()
                Viewer:RefreshData()
                
                Viewer:UpdateClearAllButton()
                
                Viewer:UpdateFilterButtonStates()
                HideDropDownMenu(1)
            end
        }
        UIDropDownMenu_AddButton(clearAllInfo, level)

        
        local separatorInfo = {
            text = "",
            notCheckable = true,
            disabled = true
        }
        UIDropDownMenu_AddButton(separatorInfo, level)

        
        for _, value in ipairs(values) do
            
            local isChecked = false
            if filterTable then
                isChecked = filterTable[value] ~= nil
            end

            local info = {
                text = value,
                checked = isChecked,
                func = function()
                    if not filterTable then return end
                    
                    if filterTable[value] then
                        filterTable[value] = nil
                    else
                        filterTable[value] = true
                    end

                    Viewer.currentPage = 1
                    
                    Cache.filteredResults = {}
                    Cache.lastFilterState = nil
                    Cache.uniqueValuesValid = false
                    Cache.uniqueValuesContext = {} 
                    Viewer:UpdateSortHeaders()
                    Viewer:RefreshData()
                    
                    Viewer:UpdateClearAllButton()
                    
                    Viewer:UpdateFilterButtonStates()
                    HideDropDownMenu(1)
                end
            }
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")

    
    ToggleDropDownMenu(1, nil, dropdown, anchor, 0, 0)

    
    local dropdownList = _G["DropDownList1"]
    if dropdownList then
        dropdownList:SetScript("OnLeave", function(self)
            
            createTimer(0.1, function()
                if dropdownList and dropdownList:IsShown() then
                    local dropdownMouseOver = dropdownList:IsMouseOver()
                    local anchorMouseOver = anchor:IsMouseOver()
                    
                    if not dropdownMouseOver and not anchorMouseOver then
                        HideDropDownMenu(1)
                    end
                end
            end)
        end)
    end
end

function Viewer:UpdateAllDiscoveriesCache(onCompleteCallback)
    VDebug("UpdateAllDiscoveriesCache(async): start")

    Cache.discoveriesBuilding = true
    Cache.discoveriesBuilt    = false

    scanQueue            = {}
    scanCursor           = 0
    scanProgressCallback = onCompleteCallback
    Cache.uniqueValuesValid = false

    Cache.discoveries    = {}
    Cache.duplicateItems = {}

    local totalItems  = 0
    local itemCount   = 0
    local vendorCount = 0

    
    local discoveries = L:GetDiscoveriesDB()
    local vendors = L:GetVendorsDB()

    for guid, discovery in pairs(discoveries or {}) do
        _tinsert(scanQueue, { guid = guid, discovery = discovery, type = "item" })
        itemCount  = itemCount  + 1
        totalItems = totalItems + 1
    end

    for guid, discovery in pairs(vendors or {}) do
        _tinsert(scanQueue, { guid = guid, discovery = discovery, type = "vendor" })
        vendorCount = vendorCount + 1
        totalItems  = totalItems  + 1
    end

    VDebug("UpdateAllDiscoveriesCache(async): queued items=" ..
        tostring(itemCount) .. ", vendors=" .. tostring(vendorCount) ..
        ", total=" .. tostring(totalItems))

    if self.window and self.window:IsShown() then
        self:UpdatePagination()
    end

    self:ProcessScanQueueBatch()
end

function Viewer:ProcessScanQueueBatch()
 
    if InCombatLockdown() then
        
        createTimer(1.0, function() Viewer:ProcessScanQueueBatch() end)
        return
    end
    local totalQueued = #scanQueue
    VDebug("ProcessScanQueueBatch: start, cursor=" .. tostring(scanCursor) ..
        ", totalQueued=" .. tostring(totalQueued))

    
    if not Cache.discoveriesBuilding or scanCursor >= totalQueued then
        Cache.discoveriesBuilding = false
        Cache.discoveriesBuilt    = (scanCursor >= totalQueued)

        
        scanQueue  = {}
        scanCursor = 0

        
        if self.window and self.window:IsShown() then
            self:UpdatePagination()
        end

        VDebug("ProcessScanQueueBatch: finished all batches, total discoveries in cache=" ..
            tostring(#Cache.discoveries))

        if scanProgressCallback and Cache.discoveriesBuilt then
            VDebug("ProcessScanQueueBatch: invoking scanProgressCallback")
            scanProgressCallback()
            scanProgressCallback = nil
        end

        return
    end

    
    
    
    local MAX_BATCH_ITEMS = 20      
    local MAX_BATCH_MS    = 20      

    local startMs
    if debugprofilestop then
        startMs = debugprofilestop()
    else
        startMs = (GetTime and GetTime() or 0) * 1000
    end

    local processedInBatch = 0
    local Core             = L:GetModule("Core", true)

    for i = 1, MAX_BATCH_ITEMS do
        scanCursor = scanCursor + 1
        if scanCursor > totalQueued then
            break
        end

        local entry     = scanQueue[scanCursor]
        local guid      = entry.guid
        local discovery = entry.discovery

        if entry.type == "item" then
            if discovery and type(discovery) == "table" then
                
                local itemLink = discovery.il
                local itemName = nil
                
                
                if itemLink then
                    itemName = itemLink:match("%[(.+)%]")
                end
                
                
                if (not itemName or itemName == "") and discovery.i then
                    local name, link = GetItemInfo(discovery.i)
                    if name then
                        itemName = name
                        
                        if (not itemLink or itemLink == "") and link then
                            
                            discovery.il = link
                            itemLink = link 
                            
                            
                        end
                    end
                end

                if itemName and itemName ~= "" then
                    local isMystic       = IsMysticScroll(itemName)
                    local isWorldforged  = IsWorldforged(itemLink)
                    local characterClass = GetItemCharacterClass(itemLink, discovery.i)
                    local name, _, _, _, minLevel, itemTypeVal, itemSubTypeVal, _, equipLocVal =
                        GetItemInfoSafe(itemLink, discovery.i)
                    
                    
                    local it, ist = discovery.it, discovery.ist
                    if not it or not ist or it == 0 or ist == 0 then
                        it, ist = GetItemTypeIDs(itemTypeVal, itemSubTypeVal)
                    end

                    _tinsert(Cache.discoveries, {
                        guid          = guid,
                        discovery     = discovery,
                        itemName      = itemName,
                        isMystic      = isMystic,
                        isWorldforged = isWorldforged,
                        itemType      = itemTypeVal,
                        itemSubType   = itemSubTypeVal,
                        it            = it,
                        ist           = ist,
                        equipLoc      = equipLocVal,
                        characterClass= characterClass,
                        minLevel      = minLevel,
                        cl            = discovery.cl,
                        isVendor      = false,
                    })

                    processedInBatch = processedInBatch + 1

                    if Core and discovery.i and not Core:IsItemCached(discovery.i) then
                        Core:QueueItemForCaching(discovery.i)
                    end

                    local itemID = discovery.i
                    if itemID then
                        Cache.duplicateItems[itemID] = (Cache.duplicateItems[itemID] or 0) + 1
                    end
                end
            end

        elseif entry.type == "vendor" then
            if discovery and type(discovery) == "table" then
                _tinsert(Cache.discoveries, {
                    guid       = guid,
                    discovery  = discovery,
                    isVendor   = true,
                    vendorType = discovery.vendorType,
                    vendorName = discovery.vendorName,
                    isMystic   = false,
                    itemName   = discovery.vendorName,
                })

                processedInBatch = processedInBatch + 1
            end
        end

        
        if processedInBatch % 5 == 0 then
            local nowMs
            if debugprofilestop then
                nowMs = debugprofilestop()
            else
                nowMs = (GetTime and GetTime() or 0) * 1000
            end

            if nowMs - startMs > MAX_BATCH_MS then
                VDebug("ProcessScanQueueBatch: time budget reached after " ..
                    tostring(processedInBatch) .. " items, elapsed=" ..
                    tostring(nowMs - startMs) .. "ms")
                break
            end
        end
    end

    local endMs
    if debugprofilestop then
        endMs = debugprofilestop()
    else
        endMs = (GetTime and GetTime() or 0) * 1000
    end

    VDebug("ProcessScanQueueBatch: processed batch, count=" ..
        tostring(processedInBatch) ..
        ", cursorNow=" .. tostring(scanCursor) ..
        ", elapsedBatchMs=" .. tostring(endMs - startMs))

    
    if scanCursor < totalQueued and Cache.discoveriesBuilding then
        createTimer(0.02, function() Viewer:ProcessScanQueueBatch() end)
    else
        
        self:ProcessScanQueueBatch()
    end
end

function Viewer:UpdateAllDiscoveriesCacheSync()
    if Cache.discoveriesBuilt or Cache.discoveriesBuilding then
        return
    end

    local t0 = time()
    VDebug("UpdateAllDiscoveriesCacheSync: start")

    Cache.discoveriesBuilding = true
    Cache.discoveries         = {}
    Cache.uniqueValuesValid   = false
    Cache.duplicateItems      = {} 

    if self.window and self.window:IsShown() then
        self:UpdatePagination()
    end

    local processedItems = 0

    
    local discoveries = L:GetDiscoveriesDB()
    local vendors = L:GetVendorsDB()

    
    for guid, discovery in pairs(discoveries or {}) do
        if discovery and type(discovery) == "table" then
            local itemLink = discovery.il
            local itemID = discovery.i
            
            
            if (not itemLink or itemLink == "") and itemID then
                 local name, link = GetItemInfo(itemID)
                 if link then
                     itemLink = link
                     
                     
                 end
            end
            
            if itemLink and itemLink ~= "" then
                local itemName = itemLink:match("%[(.+)%]")
                
                if not itemName and itemID then
                    itemName = GetItemInfo(itemID)
                end
                
                if itemName and itemName ~= "" then
                    local isMystic       = IsMysticScroll(itemName)
                    local isWorldforged  = IsWorldforged(itemLink)
                    local characterClass = GetItemCharacterClass(itemLink, discovery.i)
                    local name, _, _, _, minLevel, itemTypeVal, itemSubTypeVal, _, equipLocVal =
                        GetItemInfoSafe(itemLink, discovery.i)
                    
                    
                    local it, ist = discovery.it, discovery.ist
                    if not it or not ist or it == 0 or ist == 0 then
                        it, ist = GetItemTypeIDs(itemTypeVal, itemSubTypeVal)
                    end

                    _tinsert(Cache.discoveries, {
                        guid          = guid,
                        discovery     = discovery,
                        itemName      = itemName,
                        isMystic      = isMystic,
                        isWorldforged = isWorldforged,
                        itemType      = itemTypeVal,
                        itemSubType   = itemSubTypeVal,
                        it            = it,
                        ist           = ist,
                        equipLoc      = equipLocVal,
                        characterClass= characterClass,
                        minLevel      = minLevel,
                        cl            = discovery.cl,
                        isVendor      = false, 
                    })

                    processedItems = processedItems + 1
                    if processedItems % 200 == 0 then
                        VDebug("UpdateAllDiscoveriesCacheSync: processed items=" ..
                            tostring(processedItems))
                    end

                    if discovery.i then
                        Cache.duplicateItems[discovery.i] = (Cache.duplicateItems[discovery.i] or 0) + 1
                    end
                end
            end
        end
    end

    
    for guid, discovery in pairs(vendors or {}) do
        if discovery and type(discovery) == "table" then
            _tinsert(Cache.discoveries, {
                guid       = guid,
                discovery  = discovery,
                isVendor   = true,
                vendorType = discovery.vendorType,
                vendorName = discovery.vendorName,
                isMystic   = false,
                itemName   = discovery.vendorName, 
            })
            processedItems = processedItems + 1
        end
    end

    Cache.discoveriesBuilt    = true
    Cache.discoveriesBuilding = false

    if self.window and self.window:IsShown() then
        self:UpdatePagination()
    end

    VDebug("UpdateAllDiscoveriesCacheSync: end, totalProcessed=" ..
        tostring(processedItems) ..
        ", elapsed=" .. tostring(time() - t0) .. "s")
end

function Viewer:GetFilteredDiscoveries()
    local t0 = time()
    VDebug("GetFilteredDiscoveries: start, cacheBuilt=" ..
        tostring(Cache.discoveriesBuilt) ..
        ", building=" .. tostring(Cache.discoveriesBuilding))

    if Cache.discoveriesBuilding then return {} end

    if not Cache.discoveriesBuilt then
        self:UpdateAllDiscoveriesCacheSync()
    end

    if not Cache.discoveriesBuilt then return {} end

    
    local filterState = self:GetFilterStateHash()

    if Cache.lastFilterState == filterState and #Cache.filteredResults > 0 then
        return Cache.filteredResults
    end

    local currentFiltered   = {}
    local discoveriesToFilter = Cache.discoveries
    local totalToFilter     = #discoveriesToFilter

    
    
    local context = GetCascadedFilterContext(nil)

    
    local filterPredicates = {
        
        mainFilter = function(data)
            if self.currentFilter == "eq" then
                return not data.isMystic and not data.isVendor
            elseif self.currentFilter == "ms" then
                return data.isMystic and not data.isVendor
            elseif self.currentFilter == "bmv" then
                return data.isVendor and (data.vendorType == "BM" or (data.discovery.g and data.discovery.g:find("BM-", 1, true)))
            elseif self.currentFilter == "msv" then
                return data.isVendor and (data.vendorType == "MS" or (data.discovery.g and data.discovery.g:find("MS-", 1, true)))
            end
            return false
        end,

        
        searchFilter = function(data)
            if self.searchTerm == "" then return true end

            local searchLower  = _strlower(self.searchTerm)
            local nameToSearch = data.isVendor and data.vendorName or data.itemName
            local nameMatch    = _strfind(_strlower(nameToSearch or ""), searchLower, 1, true)

            
            local zoneName  = GetLocalizedZoneName(data.discovery)
            local zoneMatch = _strfind(_strlower(zoneName), searchLower, 1, true)

            return nameMatch or zoneMatch
        end,

        
        columnFilters = {
            eq = {
                slot = function(data)
                    if size(self.columnFilters.eq.slot) == 0 then return true end
                    local slotValue = data.equipLoc and _G[data.equipLoc] or ""
                    return self.columnFilters.eq.slot[slotValue] ~= nil
                end,
                type = function(data)
                    if size(self.columnFilters.eq.type) == 0 then return true end
                    local typeValue = data.itemSubType or ""
                    return self.columnFilters.eq.type[typeValue] ~= nil
                end,
            },
            ms = {
                class = function(data)
                    if size(self.columnFilters.ms.class) == 0 then return true end

                    local classValue = ""
                    if data.cl and data.cl ~= "cl" then
                        local classToken = CLASS_ABBREVIATIONS_REVERSE[data.cl]
                        if classToken then
                            classValue = _G.LOCALIZED_CLASS_NAMES_MALE[classToken] or
                                         _G.LOCALIZED_CLASS_NAMES_FEMALE[classToken] or ""
                        end
                    end

                    if classValue == "" then
                        classValue = data.characterClass or ""
                    end

                    return self.columnFilters.ms.class[classValue] ~= nil
                end,
            },

            zone = function(data)
                if size(self.columnFilters.zone) == 0 then return true end
                local zoneValue = GetLocalizedZoneName(data.discovery)
                return self.columnFilters.zone[zoneValue] ~= nil
            end,

            source = function(data)
                if size(self.columnFilters.source) == 0 then return true end
                local source     = data.discovery.src or "unknown"
                local sourceValue= SOURCE_NAMES[source] or source
                return self.columnFilters.source[sourceValue] ~= nil
            end,

            quality = function(data)
                if size(self.columnFilters.quality) == 0 then return true end
                local _, _, quality = GetItemInfoSafe(data.discovery.il, data.discovery.i)
                if not quality then
                    return self.columnFilters.quality["Unknown"] ~= nil
                end
                local qualityValue = QUALITY_NAMES[quality] or ("Quality " .. tostring(quality))
                return self.columnFilters.quality[qualityValue] ~= nil
            end,

            looted = function(data)
                if size(self.columnFilters.looted) == 0 then return true end
                local lootedValue = Viewer:IsLootedByChar(data.guid) and "Looted" or "Not Looted"
                return self.columnFilters.looted[lootedValue] ~= nil
            end,

            duplicates = function(data)
                if not self.columnFilters.duplicates then return true end
                return Cache.duplicateItems[data.discovery.i] and Cache.duplicateItems[data.discovery.i] > 1
            end,
        },
    }

    local startFilterTime = time()

    
    currentFiltered = filter(values(discoveriesToFilter), function(data)
        
        if not filterPredicates.mainFilter(data) then return false end
        
        if not filterPredicates.searchFilter(data) then return false end

        
        if self.currentFilter == "eq" then
            if not filterPredicates.columnFilters.eq.slot(data) then return false end
            if not filterPredicates.columnFilters.eq.type(data) then return false end
        elseif self.currentFilter == "ms" then
            if not filterPredicates.columnFilters.ms.class(data) then return false end
        end

        
        if not data.isVendor then
            if not filterPredicates.columnFilters.source(data)   then return false end
            if not filterPredicates.columnFilters.quality(data)  then return false end
            if not filterPredicates.columnFilters.looted(data)   then return false end
        end
        
        
        
        
        if context.activeFilters.class then
            if context.currentFilter == "eq" then
                
                local Constants = L:GetModule("Constants", true)
                if Constants and Constants.CLASS_PROFICIENCIES then
                    local subTypeID = data.ist
                    local typeID = data.it
                    
                    if subTypeID and typeID and subTypeID > 0 and typeID > 0 then
                        local canUse = false
                        for classFilterName, _ in pairs(context.activeFilters.class) do
                             
                             local classToken = nil
                             if _G.LOCALIZED_CLASS_NAMES_MALE then
                                 for token, locName in pairs(_G.LOCALIZED_CLASS_NAMES_MALE) do
                                     if locName == classFilterName then classToken = token; break end
                                 end
                             end
                             if not classToken and _G.LOCALIZED_CLASS_NAMES_FEMALE then
                                 for token, locName in pairs(_G.LOCALIZED_CLASS_NAMES_FEMALE) do
                                     if locName == classFilterName then classToken = token; break end
                                 end
                             end
                             if not classToken then classToken = string.upper(classFilterName) end
                             
                             local profs = Constants.CLASS_PROFICIENCIES[classToken]
                             if profs then
                                 local list = nil
                                 if typeID == Constants.ITEM_TYPE_TO_ID["Armor"] then list = profs.armor
                                 elseif typeID == Constants.ITEM_TYPE_TO_ID["Weapon"] then list = profs.weapons end
                                 
                                 if list then
                                     for _, allowedID in ipairs(list) do
                                         if subTypeID == allowedID then canUse = true; break end
                                     end
                                 else
                                     canUse = true 
                                 end
                             end
                             if canUse then break end
                        end
                        if not canUse then return false end
                    else
                        
                        return false
                    end
                end
            end
            
            
            
            
            
            
            
        end

        
        if not filterPredicates.columnFilters.zone(data) then return false end

        
        if Viewer.lootedFilterState ~= nil then
            local isLooted = Viewer:IsLootedByChar(data.guid)
            if Viewer.lootedFilterState == true and not isLooted then return false end
            if Viewer.lootedFilterState == false and isLooted then return false end
        end

        
        if not filterPredicates.columnFilters.duplicates(data) then return false end

        return true
    end)

    local filteredCount = #currentFiltered

    
    _tsort(currentFiltered, function(a, b)
        if not a or not b then return false end
        if not a.discovery or not b.discovery then return false end

        local a_val, b_val

        if self.sortColumn == "name" or self.sortColumn == "vendorName" then
            a_val = a.isVendor and a.vendorName or a.itemName or ""
            b_val = b.isVendor and b.vendorName or b.itemName or ""
        elseif self.sortColumn == "zone" then
            a_val = GetLocalizedZoneName(a.discovery)
            b_val = GetLocalizedZoneName(b.discovery)
        elseif self.sortColumn == "slot" then
            a_val = a.equipLoc and _G[a.equipLoc] or ""
            b_val = b.equipLoc and _G[b.equipLoc] or ""
        elseif self.sortColumn == "type" then
            a_val = a.itemSubType or ""
            b_val = b.itemSubType or ""
        elseif self.sortColumn == "class" then
            a_val = a.characterClass or ""
            b_val = b.characterClass or ""
        elseif self.sortColumn == "foundBy" then
            a_val = a.discovery.fp or ""
            b_val = b.discovery.fp or ""
        elseif self.sortColumn == "level" then
            a_val = a.minLevel or 0
            b_val = b.minLevel or 0
        else
            a_val = a.guid or ""
            b_val = b.guid or ""
        end

        if self.sortAscending then
            return a_val < b_val
        else
            return a_val > b_val
        end
    end)

    
    Cache.filteredResults = currentFiltered
    Cache.lastFilterState = filterState

    return Cache.filteredResults
end

function Viewer:GetFilterStateHash()
    local hashParts = {
        self.currentFilter,
        self.searchTerm,
        self.sortColumn,
        tostring(self.sortAscending)
    }

    
    local filterEntries = {}
    for filterType, filters in pairs(self.columnFilters) do
        if type(filters) == "table" then
            for column, values in pairs(filters) do
                if type(values) == "table" and size(values) > 0 then
                    local sortedValues = keys(values)
                    _tsort(sortedValues)
                    _tinsert(filterEntries, concatStrings(filterType, ":", column, ":", _tconcat(sortedValues, ",")))
                end
            end
        elseif filterType == "duplicates" and filters then
            
            _tinsert(filterEntries, "duplicates:true")
        end
    end
    
    
    if self.lootedFilterState ~= nil then
        _tinsert(filterEntries, "looted:" .. tostring(self.lootedFilterState))
    end

    
    local hash = _tconcat(hashParts, "|")
    if size(filterEntries) > 0 then
        hash = concatStrings(hash, "|", _tconcat(filterEntries, "|"))
    end

    return hash
end

function Viewer:GetPaginatedDiscoveries()
    local allDiscoveries = self:GetFilteredDiscoveries()
    self.totalItems = #allDiscoveries

    
    local startIndex = (self.currentPage - 1) * self.itemsPerPage + 1
    local endIndex = math.min(startIndex + self.itemsPerPage - 1, self.totalItems)

    local pageDiscoveries = {}
    
    pageDiscoveries[math.min(self.itemsPerPage, self.totalItems)] = nil

    for i = startIndex, endIndex do
        if allDiscoveries[i] then
            _tinsert(pageDiscoveries, allDiscoveries[i])
        end
    end

    return pageDiscoveries
end

function Viewer:GetTotalPages()
    return math.ceil(self.totalItems / self.itemsPerPage)
end

local function GetColorForDiscovery(discovery, itemID)
    
    local _, _, q = GetItemInfoSafe(discovery.il, itemID)
    
    
    if not q and discovery.q then
        q = tonumber(discovery.q)
    end
    
    
    q = q or 1 
    
    return GetQualityColor(q)
end

function Viewer:HasActiveFilters()
    
    if self.searchTerm and self.searchTerm ~= "" then
        return true
    end

    
    if size(self.columnFilters.zone) > 0 then
        return true
    end

    
    
    if self.columnFilters.eq and (size(self.columnFilters.eq.slot) > 0 or size(self.columnFilters.eq.type) > 0 or size(self.columnFilters.eq.class) > 0) then
        return true
    end

    
    if self.columnFilters.ms and size(self.columnFilters.ms.class) > 0 then
        return true
    end
    

    
    if size(self.columnFilters.source) > 0 then
        return true
    end

    
    if size(self.columnFilters.quality) > 0 then
        return true
    end

    
    if self.lootedFilterState ~= nil or size(self.columnFilters.looted) > 0 then
        return true
    end

    
    if self.columnFilters.duplicates then
        return true
    end

    return false
end

function Viewer:UpdateClearAllButton()
    if not self.clearAllBtn or not self.actionsLabel then
        return 
    end

    if self:HasActiveFilters() then
        self.clearAllBtn:Show()
        self.clearAllBtn:SetText("Clear All Filters")
    else
        self.clearAllBtn:Hide()
        
        self.actionsLabel:Show()
    end
end

function Viewer:UpdateFilterButtonStates()
    if not self.sourceFilterBtn or not self.qualityFilterBtn or not self.lootedFilterBtn then
        return 
    end

    
    local function setButtonTextColor(button, r, g, b)
        local fontString = button:GetFontString()
        if fontString then
            fontString:SetTextColor(r, g, b)
        end
    end

    
    local sourceActive = size(self.columnFilters.source) > 0
    if sourceActive then
        setButtonTextColor(self.sourceFilterBtn, 1, 0.8, 0.2) 
        self.sourceFilterBtn:SetText("Source [F]")
    else
        setButtonTextColor(self.sourceFilterBtn, 1, 1, 1) 
        self.sourceFilterBtn:SetText("Source")
    end

    
    local qualityActive = size(self.columnFilters.quality) > 0
    if qualityActive then
        setButtonTextColor(self.qualityFilterBtn, 1, 0.8, 0.2) 
        self.qualityFilterBtn:SetText("Quality [F]")
    else
        setButtonTextColor(self.qualityFilterBtn, 1, 1, 1) 
        self.qualityFilterBtn:SetText("Quality")
    end

    
    if self.lootedFilterState == true then
        setButtonTextColor(self.lootedFilterBtn, 1, 0.8, 0.2) 
        self.lootedFilterBtn:SetText("Looted: Yes")
    elseif self.lootedFilterState == false then
        setButtonTextColor(self.lootedFilterBtn, 1, 0.8, 0.2) 
        self.lootedFilterBtn:SetText("Looted: No")
    else
        setButtonTextColor(self.lootedFilterBtn, 1, 1, 1) 
        self.lootedFilterBtn:SetText("Looted: All")
    end
    
    
    if self.slotsFilterBtn then
            local slotsActive = size(self.columnFilters.eq.slot) > 0
            if slotsActive then
            setButtonTextColor(self.slotsFilterBtn, 1, 0.8, 0.2)
            self.slotsFilterBtn:SetText("Slots [F]")
            else
            setButtonTextColor(self.slotsFilterBtn, 1, 1, 1)
            self.slotsFilterBtn:SetText("Slots")
            end
    end
    
    
    if self.usableByFilterBtn then
            local classActive = false
            if self.currentFilter == "eq" then
                classActive = size(self.columnFilters.eq.class) > 0
            elseif self.currentFilter == "ms" then
                classActive = size(self.columnFilters.ms.class) > 0
            end
            
            if classActive then
            setButtonTextColor(self.usableByFilterBtn, 1, 0.8, 0.2)
            self.usableByFilterBtn:SetText("Usable By [F]")
            else
            setButtonTextColor(self.usableByFilterBtn, 1, 1, 1)
            self.usableByFilterBtn:SetText("Usable By")
            end
    end

    
    if self.duplicatesFilterBtn then
        local duplicatesActive = self.columnFilters.duplicates
        if duplicatesActive then
            setButtonTextColor(self.duplicatesFilterBtn, 1, 0.8, 0.2) 
            self.duplicatesFilterBtn:SetText("Duplicates [F]")
        else
            setButtonTextColor(self.duplicatesFilterBtn, 1, 1, 1) 
            self.duplicatesFilterBtn:SetText("Duplicates")
        end
    end
end

    
function Viewer:UpdateRefreshButton()
    if not self.refreshDataBtn then return end
    
    local count = self.pendingUpdatesCount or 0
    if count > 0 then
        
        self.refreshDataBtn:SetText("Refresh *")
        self.refreshDataBtn:Enable()
        if self.refreshDataBtn.GetFontString then
             local fs = self.refreshDataBtn:GetFontString()
             if fs then fs:SetTextColor(0, 1, 0) end 
        end
    else
        self.refreshDataBtn:SetText("Refresh")
        self.refreshDataBtn:Disable()
         if self.refreshDataBtn.GetFontString then
             local fs = self.refreshDataBtn:GetFontString()
             if fs then fs:SetTextColor(0.5, 0.5, 0.5) end 
        end
    end
end

  

function Viewer:CreateWindow()
    if self.window then return end
    
    local rowFont = CreateFont(ROW_FONT_NAME)
    local baseFont, baseSize, baseFlags = GameFontHighlightSmall:GetFont()
    rowFont:SetFont(baseFont, ROW_FONT_SIZE, baseFlags)

    
    local window = CreateFrame("Frame", "LootCollectorViewerWindow", UIParent)
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata(FRAME_STRATA)
    window:SetFrameLevel(FRAME_LEVEL)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)

    
    local hiddenCloseBtn = CreateFrame("Button", "LootCollectorViewerHiddenClose", window)
    hiddenCloseBtn:SetScript("OnClick", function()
        
        if Viewer.contextMenu then
            Viewer.contextMenu:Hide()
            Viewer.contextMenu = nil
            return
        elseif Viewer.filterDropdown then
            Viewer.filterDropdown:Hide()
            Viewer.filterDropdown = nil
            return
        else
            
            Viewer.allowManualClose = true
            window:Hide()
        end
    end)
    hiddenCloseBtn:Hide()

    
    window.closeBtn = hiddenCloseBtn

    
    window:SetScript("OnShow", function(self)
        
        _tinsert(UISpecialFrames, self:GetName())
    end)

    window:SetScript("OnHide", function(self)
        
        if Viewer.inMapOperation and not Viewer.allowManualClose then
            if Viewer.window and not Viewer.window:IsShown() then
                Viewer.window:Show()
            end
            return
        end

        
        if Viewer.restoreToSpecialFrames and Viewer.windowNameToRestore and not Viewer.allowManualClose then
            createTimer(0.01, function()
                if Viewer.window and not Viewer.window:IsShown() then
                    Viewer.window:Show()
                end
            end)
            return
        end

        
        for i = #UISpecialFrames, 1, -1 do
            if UISpecialFrames[i] == self:GetName() then
                _tremove(UISpecialFrames, i)
                break
            end
        end

        
        Viewer.allowManualClose = false
    end)

    
    local originalHide = window.Hide
    window.Hide = function(self)
        if Viewer.inMapOperation and not Viewer.allowManualClose then
            return 
        end
        originalHide(self)
    end

    
    originalHide(window)

    
    window:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    window:SetBackdropColor(0.1, 0.1, 0.1, 0.95)

    
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("LootCollector Discoveries")

    
    local closeBtn = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function()
        Viewer.allowManualClose = true
        window:Hide()
    end)
    
     
    self.SetSelectedRow = function(self, row)
        if self.selectedRow and self.selectedRow.highlight then
            self.selectedRow.highlight:Hide()
        end
        if row and row.highlight then
            row.highlight:Show()
            self.selectedRow = row
        else
            self.selectedRow = nil
        end
    end

    
    local equipmentBtn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    equipmentBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    equipmentBtn:SetPoint("TOPLEFT", 20, -50)
    equipmentBtn:SetText("EQ")
    equipmentBtn:SetScript("OnClick", function()
    self.currentFilter = "eq"
    self.currentPage   = 1
    self:SetSelectedRow(nil)

    
    if self.vendorInventoryFrame then
        self.vendorInventoryFrame:Hide()
        self.selectedVendorGuid = nil
    end

    self:UpdateFilterButtons()
    self:UpdateSortHeaders()
    self:RefreshData()
	end)

    local mysticBtn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    mysticBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    mysticBtn:SetPoint("LEFT", equipmentBtn, "RIGHT", 10, 0)
    mysticBtn:SetText("MS")
    mysticBtn:SetScript("OnClick", function()
    self.currentFilter = "ms"
    self.currentPage   = 1
    self:SetSelectedRow(nil)

    if self.vendorInventoryFrame then
        self.vendorInventoryFrame:Hide()
        self.selectedVendorGuid = nil
    end

    self:UpdateFilterButtons()
    self:UpdateSortHeaders()
    self:RefreshData()
	end)

    
    local bmvBtn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    bmvBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    bmvBtn:SetPoint("LEFT", mysticBtn, "RIGHT", 10, 0)
    bmvBtn:SetText("BMv")
    bmvBtn:SetScript("OnClick", function()
    self.currentFilter = "bmv"
    self.currentPage   = 1
    self:SetSelectedRow(nil)

    if self.vendorInventoryFrame then
        self.vendorInventoryFrame:Hide()
        self.selectedVendorGuid = nil
    end

    self:UpdateFilterButtons()
    self:UpdateSortHeaders()
    self:RefreshData()
	end)

    local msvBtn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    msvBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    msvBtn:SetPoint("LEFT", bmvBtn, "RIGHT", 10, 0)
    msvBtn:SetText("MSv")
    msvBtn:SetScript("OnClick", function()
    self.currentFilter = "msv"
    self.currentPage   = 1
    self:SetSelectedRow(nil)

    if self.vendorInventoryFrame then
        self.vendorInventoryFrame:Hide()
        self.selectedVendorGuid = nil
    end

    self:UpdateFilterButtons()
    self:UpdateSortHeaders()
    self:RefreshData()
	end)

    
    local searchLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    searchLabel:SetPoint("TOPLEFT", equipmentBtn, "BOTTOMLEFT", 0, -10)
    searchLabel:SetText("Search:")

    local searchBox = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 5, 0)
    searchBox:SetAutoFocus(false)

    
    local clearBtn = CreateFrame("Button", nil, searchBox)
    clearBtn:SetSize(24, 24)
    clearBtn:SetPoint("RIGHT", searchBox, "RIGHT", -1, 0)
    clearBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    clearBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    clearBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    clearBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
        Viewer.searchTerm = ""
        Viewer.currentPage = 1
        Viewer:RefreshData()
        Viewer:UpdateClearAllButton()
        clearBtn:Hide()
    end)
    clearBtn:Hide() 
        

    local autocompleteDropdown = nil
    local autocompleteSuggestions = {}
    local selectedSuggestionIndex = 0

    local function createAutocompleteDropdown()
        if autocompleteDropdown then
            return autocompleteDropdown
        end

        
        autocompleteDropdown = CreateFrame("Frame", "LootCollectorSearchAutocomplete", Viewer.window)
        autocompleteDropdown:SetSize(200, 20)
        autocompleteDropdown:SetFrameStrata("TOOLTIP")
        autocompleteDropdown:SetFrameLevel(FRAME_LEVEL)
        autocompleteDropdown:Hide()

        
        autocompleteDropdown:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        autocompleteDropdown:SetBackdropColor(0.1, 0.1, 0.1, 0.95)

        
        local content = CreateFrame("Frame", nil, autocompleteDropdown)
        content:SetPoint("TOPLEFT", 5, -5)
        content:SetPoint("BOTTOMRIGHT", -5, 5)
        content:SetFrameLevel(autocompleteDropdown:GetFrameLevel())

        autocompleteDropdown.content = content
        autocompleteDropdown.buttons = {}

        return autocompleteDropdown
    end

    local function hideAutocompleteDropdown()
        if autocompleteDropdown then
            autocompleteDropdown:Hide()
            selectedSuggestionIndex = 0
        end
    end

    local function getSearchCandidates(text)
        if not text or text == "" then return {} end

        local textLower = _strlower(text)
        
        local candidates = {}
        candidates[math.min(#Cache.discoveries, 100)] = nil 
        local seen = {}

        if Cache.discoveriesBuilt then
            for _, data in ipairs(Cache.discoveries) do
                
                if data.itemName then
                    local nameLower = _strlower(data.itemName)
                    if string.sub(nameLower, 1, string.len(textLower)) == textLower then
                        if not seen[data.itemName] then
                            _tinsert(candidates, data.itemName)
                            seen[data.itemName] = true
                        end
                    end
                end

                
                local zoneName = GetLocalizedZoneName(data.discovery)
                if zoneName then
                    local zoneLower = _strlower(zoneName)
                    if string.sub(zoneLower, 1, string.len(textLower)) == textLower then
                        if not seen[zoneName] then
                            _tinsert(candidates, zoneName)
                            seen[zoneName] = true
                        end
                    end
                end
            end
        end

        
        _tsort(candidates)

        
        local limitedCandidates = {}
        for i = 1, math.min(10, #candidates) do
            _tinsert(limitedCandidates, candidates[i])
        end

        return limitedCandidates
    end

    local function updateAutocompleteSelection()
        if not autocompleteDropdown or not autocompleteDropdown:IsShown() then return end

        for i, button in ipairs(autocompleteDropdown.buttons) do
            if i == selectedSuggestionIndex then
                button:GetHighlightTexture():SetVertexColor(0.5, 0.5, 0.8, 0.8)
            else
                button:GetHighlightTexture():SetVertexColor(0.3, 0.3, 0.3, 0.8)
            end
        end
    end

    local function showAutocompleteSuggestions(text)
        local candidates = getSearchCandidates(text)

        if #candidates == 0 then
            hideAutocompleteDropdown()
            return
        end

        autocompleteSuggestions = candidates
        selectedSuggestionIndex = 0

        local dropdown = createAutocompleteDropdown()
        local content = dropdown.content

        
        for _, button in ipairs(dropdown.buttons) do
            button:Hide()
        end
        dropdown.buttons = {}
        
        dropdown.buttons[math.min(#candidates, 20)] = nil 

        
        local buttonHeight = 16
        local maxHeight = 160 
        local totalHeight = math.min(#candidates * buttonHeight, maxHeight)

        dropdown:SetSize(200, totalHeight + 10)

        for i, candidate in ipairs(candidates) do
            local button = CreateFrame("Button", nil, content)
            button:SetSize(190, buttonHeight)
            button:SetPoint("TOPLEFT", 5, -(i - 1) * buttonHeight)
            button:SetFrameLevel(FRAME_LEVEL)

            
            local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("LEFT", 5, 0)
            text:SetText(candidate)
            text:SetJustifyH("LEFT")
            text:SetTextColor(1, 1, 1) 

            
            button:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
            button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
            button:GetNormalTexture():SetVertexColor(0.1, 0.1, 0.1, 0.8)
            button:GetHighlightTexture():SetVertexColor(0.3, 0.3, 0.3, 0.8)

            
            button:SetScript("OnClick", function()
                searchBox:SetText(candidate)
                searchBox:ClearFocus()
                hideAutocompleteDropdown()
                Viewer.searchTerm = candidate
                Viewer.currentPage = 1
                Viewer:RefreshData()
                Viewer:UpdateClearAllButton()
            end)

            button:SetScript("OnEnter", function()
                selectedSuggestionIndex = i
                updateAutocompleteSelection()
            end)

            button:Show()
            _tinsert(dropdown.buttons, button)
        end

        
        dropdown:ClearAllPoints()
        dropdown:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -2)
        dropdown:Show()
    end

    local function selectNextSuggestion()
        if not autocompleteDropdown or not autocompleteDropdown:IsShown() then return end

        selectedSuggestionIndex = selectedSuggestionIndex + 1
        if selectedSuggestionIndex > #autocompleteSuggestions then
            selectedSuggestionIndex = 1
        end
        updateAutocompleteSelection()
    end

    local function selectPreviousSuggestion()
        if not autocompleteDropdown or not autocompleteDropdown:IsShown() then return end

        selectedSuggestionIndex = selectedSuggestionIndex - 1
        if selectedSuggestionIndex < 1 then
            selectedSuggestionIndex = #autocompleteSuggestions
        end
        updateAutocompleteSelection()
    end

    local function applySelectedSuggestion()
        if not autocompleteDropdown or not autocompleteDropdown:IsShown() then return end
        if selectedSuggestionIndex < 1 or selectedSuggestionIndex > #autocompleteSuggestions then return end

        local suggestion = autocompleteSuggestions[selectedSuggestionIndex]
        searchBox:SetText(suggestion)
        searchBox:ClearFocus()
        hideAutocompleteDropdown()
        Viewer.searchTerm = suggestion
        Viewer.currentPage = 1
        Viewer:RefreshData()
        Viewer:UpdateClearAllButton()
    end

    searchBox:SetScript("OnTextChanged", function(self)
        Viewer.searchTerm = self:GetText() or ""
        Viewer.currentPage = 1
        Viewer:RefreshData()
        
        Viewer:UpdateClearAllButton()

        
        if Viewer.searchTerm and Viewer.searchTerm ~= "" then
            clearBtn:Show()
            
            showAutocompleteSuggestions(Viewer.searchTerm)
        else
            clearBtn:Hide()
            hideAutocompleteDropdown()
        end
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        if autocompleteDropdown and autocompleteDropdown:IsShown() and selectedSuggestionIndex > 0 then
            applySelectedSuggestion()
        else
            self:ClearFocus()
        end
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        if autocompleteDropdown and autocompleteDropdown:IsShown() then
            hideAutocompleteDropdown()
        else
            self:SetText("")
            self:ClearFocus()
            Viewer.searchTerm = ""
            Viewer.currentPage = 1
            Viewer:RefreshData()
            Viewer:UpdateClearAllButton()
            clearBtn:Hide()
        end
    end)
    searchBox:SetScript("OnTabPressed", function(self)
        if autocompleteDropdown and autocompleteDropdown:IsShown() then
            
            if #autocompleteSuggestions > 0 then
                local suggestion = autocompleteSuggestions[1]
                searchBox:SetText(suggestion)
                searchBox:ClearFocus()
                hideAutocompleteDropdown()
                Viewer.searchTerm = suggestion
                Viewer.currentPage = 1
                Viewer:RefreshData()
                Viewer:UpdateClearAllButton()
            end
        end
    end)
    searchBox:SetScript("OnKeyDown", function(self, key)
        if autocompleteDropdown and autocompleteDropdown:IsShown() then
            if key == "DOWN" then
                selectNextSuggestion()
                return true
            elseif key == "UP" then
                selectPreviousSuggestion()
                return true
            elseif key == "ENTER" then
                applySelectedSuggestion()
                return true
            elseif key == "ESCAPE" then
                hideAutocompleteDropdown()
                return true
            elseif key == "TAB" then
                
                if #autocompleteSuggestions > 0 then
                    local suggestion = autocompleteSuggestions[1]
                    searchBox:SetText(suggestion)
                    searchBox:ClearFocus()
                    hideAutocompleteDropdown()
                    Viewer.searchTerm = suggestion
                    Viewer.currentPage = 1
                    Viewer:RefreshData()
                    Viewer:UpdateClearAllButton()
                end
                return true
            end
        end
    end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        
        createTimer(0.1, function()
            if not searchBox:HasFocus() then
                hideAutocompleteDropdown()
            end
        end)
    end)

    
    
    local additionalFiltersFrame = CreateFrame("Frame", nil, window)
    additionalFiltersFrame:SetSize(556, 30) 
    additionalFiltersFrame:SetFrameStrata(FRAME_STRATA)
    additionalFiltersFrame:SetFrameLevel(FRAME_LEVEL)
    additionalFiltersFrame:SetPoint("LEFT", msvBtn, "RIGHT", 20, 0)

    
    additionalFiltersFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    additionalFiltersFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.7)

    
    local filtersLabel = additionalFiltersFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    filtersLabel:SetPoint("LEFT", 10, 0)
    filtersLabel:SetText("Filters:")

    
    local sourceFilterBtn = CreateFrame("Button", nil, additionalFiltersFrame, "UIPanelButtonTemplate")
    sourceFilterBtn:SetSize(70, BUTTON_HEIGHT)
    sourceFilterBtn:SetPoint("LEFT", filtersLabel, "RIGHT", 10, 0)
    sourceFilterBtn:SetText("Source")
    sourceFilterBtn:SetFrameStrata(FRAME_STRATA)
    sourceFilterBtn:SetFrameLevel(FRAME_LEVEL + 1)
    sourceFilterBtn:SetScript("OnClick", function(self, button)
        local values = GetUniqueValues("source")
        ShowColumnFilterDropdown("source", self, values)
    end)
    sourceFilterBtn:RegisterForClicks("LeftButtonUp")
    
    
    local qualityFilterBtn = CreateFrame("Button", nil, additionalFiltersFrame, "UIPanelButtonTemplate")
    qualityFilterBtn:SetSize(70, BUTTON_HEIGHT)
    qualityFilterBtn:SetPoint("LEFT", sourceFilterBtn, "RIGHT", 5, 0)
    qualityFilterBtn:SetText("Quality")
    qualityFilterBtn:SetFrameStrata(FRAME_STRATA)
    qualityFilterBtn:SetFrameLevel(FRAME_LEVEL + 1)
    qualityFilterBtn:SetScript("OnClick", function(self, button)
        local values = GetUniqueValues("quality")
        ShowColumnFilterDropdown("quality", self, values)
    end)
    qualityFilterBtn:RegisterForClicks("LeftButtonUp")
    
    
    local slotsFilterBtn = CreateFrame("Button", nil, additionalFiltersFrame, "UIPanelButtonTemplate")
    slotsFilterBtn:SetSize(60, BUTTON_HEIGHT)
    slotsFilterBtn:SetPoint("LEFT", qualityFilterBtn, "RIGHT", 5, 0)
    slotsFilterBtn:SetText("Slots")
    slotsFilterBtn:SetFrameStrata(FRAME_STRATA)
    slotsFilterBtn:SetFrameLevel(FRAME_LEVEL + 1)
    slotsFilterBtn:SetScript("OnClick", function(self, button)
        local values = GetUniqueValues("slot")
        ShowColumnFilterDropdown("slot", self, values)
    end)
    slotsFilterBtn:RegisterForClicks("LeftButtonUp")
    
    
    local usableByFilterBtn = CreateFrame("Button", nil, additionalFiltersFrame, "UIPanelButtonTemplate")
    usableByFilterBtn:SetSize(80, BUTTON_HEIGHT)
    usableByFilterBtn:SetPoint("LEFT", slotsFilterBtn, "RIGHT", 5, 0)
    usableByFilterBtn:SetText("Usable By")
    usableByFilterBtn:SetFrameStrata(FRAME_STRATA)
    usableByFilterBtn:SetFrameLevel(FRAME_LEVEL + 1)
    usableByFilterBtn:SetScript("OnClick", function(self, button)
        local values = GetUniqueValues("class")
        ShowColumnFilterDropdown("class", self, values)
    end)
    usableByFilterBtn:RegisterForClicks("LeftButtonUp")

    
    local lootedFilterBtn = CreateFrame("Button", nil, additionalFiltersFrame, "UIPanelButtonTemplate")
    lootedFilterBtn:SetSize(90, BUTTON_HEIGHT)
    lootedFilterBtn:SetPoint("LEFT", usableByFilterBtn, "RIGHT", 5, 0)
    lootedFilterBtn:SetText("Looted: All")
    lootedFilterBtn:SetFrameStrata(FRAME_STRATA)
    lootedFilterBtn:SetFrameLevel(FRAME_LEVEL + 1)
    lootedFilterBtn:SetScript("OnClick", function(self, button)
        
        if Viewer.lootedFilterState == nil then
            Viewer.lootedFilterState = true
        elseif Viewer.lootedFilterState == true then
            Viewer.lootedFilterState = false
        else
            Viewer.lootedFilterState = nil
        end
        
        Viewer.currentPage = 1
        Cache.filteredResults = {}
        Cache.lastFilterState = nil
        Viewer:RefreshData()
        Viewer:UpdateFilterButtonStates()
    end)
    lootedFilterBtn:RegisterForClicks("LeftButtonUp")

    
    local duplicatesFilterBtn = CreateFrame("Button", nil, additionalFiltersFrame, "UIPanelButtonTemplate")
    duplicatesFilterBtn:SetSize(90, BUTTON_HEIGHT)
    duplicatesFilterBtn:SetPoint("LEFT", lootedFilterBtn, "RIGHT", 5, 0)
    duplicatesFilterBtn:SetText("Duplicates")
    duplicatesFilterBtn:SetFrameStrata(FRAME_STRATA)
    duplicatesFilterBtn:SetFrameLevel(FRAME_LEVEL + 1)
    duplicatesFilterBtn:SetScript("OnClick", function(self, button)
        Viewer.columnFilters.duplicates = not Viewer.columnFilters.duplicates
        Viewer.currentPage = 1
        Cache.filteredResults = {}
        Cache.lastFilterState = nil
        Viewer:RefreshData()
        Viewer:UpdateClearAllButton()
        Viewer:UpdateFilterButtonStates()
    end)
    duplicatesFilterBtn:RegisterForClicks("LeftButtonUp")
    
    self.sourceFilterBtn = sourceFilterBtn
    self.qualityFilterBtn = qualityFilterBtn
    self.slotsFilterBtn = slotsFilterBtn
    self.usableByFilterBtn = usableByFilterBtn
    self.lootedFilterBtn = lootedFilterBtn
    self.duplicatesFilterBtn = duplicatesFilterBtn

    
    local headerFrame = CreateFrame("Frame", nil, window)
    headerFrame:SetSize(WINDOW_WIDTH - 40, HEADER_HEIGHT)
    headerFrame:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -15)
    headerFrame:SetFrameLevel(FRAME_LEVEL)
    headerFrame:SetFrameStrata(FRAME_STRATA)

    
    headerFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    headerFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

    
    local nameHeader = CreateFrame("Button", nil, headerFrame)
    nameHeader:SetSize(GRID_LAYOUT.NAME_WIDTH, HEADER_HEIGHT)
    nameHeader:SetPoint("LEFT", 5, 0)
    nameHeader:SetText("Name")
    nameHeader:SetNormalFontObject("GameFontNormalSmall")
    nameHeader:SetHighlightFontObject("GameFontHighlightSmall")
    nameHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "name" then
            Viewer.sortAscending = not Viewer.sortAscending
        else
            Viewer.sortColumn = "name"
            Viewer.sortAscending = true
        end
        Viewer.currentPage = 1
        Viewer:UpdateSortHeaders()
        Viewer:RefreshData()
    end)

    
    local levelHeader = CreateFrame("Button", nil, headerFrame)
    levelHeader:SetSize(GRID_LAYOUT.LEVEL_WIDTH, HEADER_HEIGHT)
    levelHeader:SetPoint("LEFT", nameHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    levelHeader:SetText("Level")
    levelHeader:SetNormalFontObject("GameFontNormalSmall")
    levelHeader:SetHighlightFontObject("GameFontHighlightSmall")
    levelHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "level" then
            Viewer.sortAscending = not Viewer.sortAscending
        else
            Viewer.sortColumn = "level"
            Viewer.sortAscending = true
        end
        Viewer.currentPage = 1
        Viewer:UpdateSortHeaders()
        Viewer:RefreshData()
    end)

    
    local slotHeader = CreateFrame("Button", nil, headerFrame)
    slotHeader:SetSize(GRID_LAYOUT.SLOT_WIDTH, HEADER_HEIGHT)
    slotHeader:SetPoint("LEFT", levelHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    slotHeader:SetText("Slot")
    slotHeader:SetNormalFontObject("GameFontNormalSmall")
    slotHeader:SetHighlightFontObject("GameFontHighlightSmall")
    slotHeader:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            
            local values = GetUniqueValues("slot")
            ShowColumnFilterDropdown("slot", self, values)
        else
            
            if Viewer.sortColumn == "slot" then
                Viewer.sortAscending = not Viewer.sortAscending
            else
                Viewer.sortColumn = "slot"
                Viewer.sortAscending = true
            end
            Viewer.currentPage = 1
            Viewer:UpdateSortHeaders()
            Viewer:RefreshData()
        end
    end)
    slotHeader:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slotHeader:Hide() 

    
    local typeHeader = CreateFrame("Button", nil, headerFrame)
    typeHeader:SetSize(GRID_LAYOUT.TYPE_WIDTH, HEADER_HEIGHT)
    typeHeader:SetPoint("LEFT", slotHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    typeHeader:SetText("Type")
    typeHeader:SetNormalFontObject("GameFontNormalSmall")
    typeHeader:SetHighlightFontObject("GameFontHighlightSmall")
    typeHeader:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            
            local values = GetUniqueValues("type")
            ShowColumnFilterDropdown("type", self, values)
        else
            
            if Viewer.sortColumn == "type" then
                Viewer.sortAscending = not Viewer.sortAscending
            else
                Viewer.sortColumn = "type"
                Viewer.sortAscending = true
            end
            Viewer.currentPage = 1
            Viewer:UpdateSortHeaders()
            Viewer:RefreshData()
        end
    end)
    typeHeader:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    typeHeader:Hide() 

    
    local classHeader = CreateFrame("Button", nil, headerFrame)
    classHeader:SetSize(GRID_LAYOUT.CLASS_WIDTH, HEADER_HEIGHT)
    classHeader:SetPoint("LEFT", levelHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    classHeader:SetText("Class")
    classHeader:SetNormalFontObject("GameFontNormalSmall")
    classHeader:SetHighlightFontObject("GameFontHighlightSmall")
    classHeader:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            
            local values = GetUniqueValues("class")
            ShowColumnFilterDropdown("class", self, values)
        else
            
            if Viewer.sortColumn == "class" then
                Viewer.sortAscending = not Viewer.sortAscending
            else
                Viewer.sortColumn = "class"
                Viewer.sortAscending = true
            end
            Viewer.currentPage = 1
            Viewer:UpdateSortHeaders()
            Viewer:RefreshData()
        end
    end)
    classHeader:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    classHeader:Hide() 

    
    local zoneHeader = CreateFrame("Button", nil, headerFrame)
    zoneHeader:SetSize(GRID_LAYOUT.ZONE_WIDTH, HEADER_HEIGHT)
    zoneHeader:SetPoint("LEFT", classHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    zoneHeader:SetText("Zone")
    zoneHeader:SetNormalFontObject("GameFontNormalSmall")
    zoneHeader:SetHighlightFontObject("GameFontHighlightSmall")
    zoneHeader:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            
            local values = GetUniqueValues("zone")
            ShowColumnFilterDropdown("zone", self, values)
        else
            
            if Viewer.sortColumn == "zone" then
                Viewer.sortAscending = not Viewer.sortAscending
            else
                Viewer.sortColumn = "zone"
                Viewer.sortAscending = true
            end
            Viewer.currentPage = 1
            Viewer:UpdateSortHeaders()
            Viewer:RefreshData()
        end
    end)
    zoneHeader:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    
    local foundByHeader = CreateFrame("Button", nil, headerFrame)
    foundByHeader:SetSize(GRID_LAYOUT.FOUND_BY_WIDTH, HEADER_HEIGHT)
    foundByHeader:SetPoint("LEFT", zoneHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    foundByHeader:SetText("Found By")
    foundByHeader:SetNormalFontObject("GameFontNormalSmall")
    foundByHeader:SetHighlightFontObject("GameFontHighlightSmall")
    foundByHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "foundBy" then
            Viewer.sortAscending = not Viewer.sortAscending
        else
            Viewer.sortColumn = "foundBy"
            Viewer.sortAscending = true
        end
        Viewer.currentPage = 1
        Viewer:UpdateSortHeaders()
        Viewer:RefreshData()
    end)
    
    
    local vendorNameHeader = CreateFrame("Button", nil, headerFrame)
    vendorNameHeader:SetSize(GRID_LAYOUT.VENDOR_NAME_WIDTH, HEADER_HEIGHT)
    vendorNameHeader:SetPoint("LEFT", 5, 0)
    vendorNameHeader:SetText("Vendor Name")
    vendorNameHeader:SetNormalFontObject("GameFontNormalSmall")
    vendorNameHeader:SetHighlightFontObject("GameFontHighlightSmall")
    vendorNameHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "vendorName" then Viewer.sortAscending = not Viewer.sortAscending
        else Viewer.sortColumn = "vendorName"; Viewer.sortAscending = true end
        Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
    end)

    local vendorZoneHeader = CreateFrame("Button", nil, headerFrame)
    vendorZoneHeader:SetSize(GRID_LAYOUT.VENDOR_ZONE_WIDTH, HEADER_HEIGHT)
    vendorZoneHeader:SetPoint("LEFT", vendorNameHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    vendorZoneHeader:SetText("Zone")
    vendorZoneHeader:SetNormalFontObject("GameFontNormalSmall")
    vendorZoneHeader:SetHighlightFontObject("GameFontHighlightSmall")
    vendorZoneHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "zone" then Viewer.sortAscending = not Viewer.sortAscending
        else Viewer.sortColumn = "zone"; Viewer.sortAscending = true end
        Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
    end)
    
    local inventoryHeader = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    inventoryHeader:SetSize(GRID_LAYOUT.VENDOR_INVENTORY_WIDTH, HEADER_HEIGHT)
    inventoryHeader:SetPoint("LEFT", vendorZoneHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    inventoryHeader:SetText("Inventory")
    
    
    local actionsLabel = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    actionsLabel:SetPoint("RIGHT", -5, 0)
    actionsLabel:SetText("Actions")

    
    local clearAllBtn = CreateFrame("Button", nil, headerFrame, "UIPanelButtonTemplate")
    clearAllBtn:SetSize(100, 20)
    clearAllBtn:SetPoint("RIGHT", -5, 0)
    clearAllBtn:SetText("Clear All Filters")
    clearAllBtn:SetScript("OnClick", function()
        
        Viewer.columnFilters.zone = {}
        Viewer.columnFilters.eq.slot = {}
        Viewer.columnFilters.eq.type = {}
        Viewer.columnFilters.eq.class = {}
        Viewer.columnFilters.ms.class = {}
        Viewer.columnFilters.source = {}
        Viewer.columnFilters.quality = {}
        Viewer.columnFilters.looted = {}
        Viewer.columnFilters.duplicates = false 
        
        Viewer.lootedFilterState = nil 

        
        Viewer.searchTerm = ""
        searchBox:SetText("")

        
        Viewer.currentPage = 1

        
        Cache.filteredResults = {}
        Cache.lastFilterState = nil
        Cache.uniqueValuesValid = false
        Cache.uniqueValuesContext = {}

        
        Viewer:UpdateSortHeaders()
        Viewer:RefreshData()

        
        Viewer:UpdateClearAllButton()
        
        Viewer:UpdateFilterButtonStates()
    end)

     local refreshDataBtn = CreateFrame("Button", nil, additionalFiltersFrame, "UIPanelButtonTemplate")
    refreshDataBtn:SetSize(100, 22) 
    refreshDataBtn:SetPoint("BOTTOM", duplicatesFilterBtn, "CENTER", -10, -40)
    refreshDataBtn:SetText("Refresh")
    refreshDataBtn:SetFrameStrata(FRAME_STRATA)
    refreshDataBtn:SetFrameLevel(FRAME_LEVEL + 1)
    refreshDataBtn:SetScript("OnClick", function()
        Viewer.pendingUpdatesCount = 0
        Viewer:UpdateRefreshButton()
        Viewer:RefreshData()
    end)
    self.refreshDataBtn = refreshDataBtn

    
    local paginationFrame = CreateFrame("Frame", nil, window)
    paginationFrame:SetSize(WINDOW_WIDTH - 32, 32)
    paginationFrame:SetPoint("BOTTOM", 0, 20)
    paginationFrame:SetFrameStrata(FRAME_STRATA)
    paginationFrame:SetFrameLevel(FRAME_LEVEL)

    
    paginationFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    paginationFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)

    
    local pageInfo = paginationFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pageInfo:SetPoint("CENTER", 10, 0)
    pageInfo:SetText("Page 1 of 1")

    
    local prevBtn = CreateFrame("Button", nil, paginationFrame, "UIPanelButtonTemplate")
    prevBtn:SetSize(80, BUTTON_HEIGHT)
    prevBtn:SetPoint("LEFT", 5, 0)
    prevBtn:SetText("Previous")
    prevBtn:SetFrameStrata(FRAME_STRATA)
    prevBtn:SetFrameLevel(FRAME_LEVEL + 1)
    prevBtn:SetScript("OnClick", function()
        if self.currentPage > 1 then
            self.currentPage = self.currentPage - 1
            self:UpdatePagination()
            self:UpdateRows()
        end
    end)

    
    local nextBtn = CreateFrame("Button", nil, paginationFrame, "UIPanelButtonTemplate")
    nextBtn:SetSize(80, BUTTON_HEIGHT)
    nextBtn:SetPoint("RIGHT", -10, 0)
    nextBtn:SetText("Next")
    nextBtn:SetFrameStrata(FRAME_STRATA)
    nextBtn:SetFrameLevel(FRAME_LEVEL + 1)
    nextBtn:SetScript("OnClick", function()
        local totalPages = self:GetTotalPages()
        if self.currentPage < totalPages then
            self.currentPage = self.currentPage + 1
            self:UpdatePagination()
            self:UpdateRows()
        end
    end)

    
    local itemsLabel = paginationFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemsLabel:SetPoint("LEFT", prevBtn, "RIGHT", 20, 0)
    itemsLabel:SetText("Items per page:")

    local items25Btn = CreateFrame("Button", nil, paginationFrame, "UIPanelButtonTemplate")
    items25Btn:SetSize(30, BUTTON_HEIGHT)
    items25Btn:SetPoint("LEFT", itemsLabel, "RIGHT", 5, 0)
    items25Btn:SetText("25")
    items25Btn:SetFrameStrata(FRAME_STRATA)
    items25Btn:SetFrameLevel(FRAME_LEVEL + 1)
    items25Btn:SetScript("OnClick", function()
        local oldItemsPerPage = Viewer.itemsPerPage
        Viewer.itemsPerPage = 25
        
        local currentItemIndex = (Viewer.currentPage - 1) * oldItemsPerPage + 1
        Viewer.currentPage = math.ceil(currentItemIndex / Viewer.itemsPerPage)
        Viewer:UpdateItemsPerPageButtons()
        Viewer:UpdatePagination()
        Viewer:RefreshData()
    end)

    local items50Btn = CreateFrame("Button", nil, paginationFrame, "UIPanelButtonTemplate")
    items50Btn:SetSize(30, BUTTON_HEIGHT)
    items50Btn:SetPoint("LEFT", items25Btn, "RIGHT", 2, 0)
    items50Btn:SetText("50")
    items50Btn:SetFrameStrata(FRAME_STRATA)
    items50Btn:SetFrameLevel(FRAME_LEVEL + 1)
    items50Btn:SetScript("OnClick", function()
        local oldItemsPerPage = Viewer.itemsPerPage
        Viewer.itemsPerPage = 50
        
        local currentItemIndex = (Viewer.currentPage - 1) * oldItemsPerPage + 1
        Viewer.currentPage = math.ceil(currentItemIndex / Viewer.itemsPerPage)
        Viewer:UpdateItemsPerPageButtons()
        Viewer:UpdatePagination()
        Viewer:RefreshData()
    end)

    local items100Btn = CreateFrame("Button", nil, paginationFrame, "UIPanelButtonTemplate")
    items100Btn:SetSize(35, BUTTON_HEIGHT)
    items100Btn:SetPoint("LEFT", items50Btn, "RIGHT", 2, 0)
    items100Btn:SetText("100")
    items100Btn:SetFrameStrata(FRAME_STRATA)
    items100Btn:SetFrameLevel(FRAME_LEVEL + 1)
    items100Btn:SetScript("OnClick", function()
        local oldItemsPerPage = Viewer.itemsPerPage
        Viewer.itemsPerPage = 100
        
        local currentItemIndex = (Viewer.currentPage - 1) * oldItemsPerPage + 1
        Viewer.currentPage = math.ceil(currentItemIndex / Viewer.itemsPerPage)
        Viewer:UpdateItemsPerPageButtons()
        Viewer:UpdatePagination()
        Viewer:RefreshData()
    end)

    
    local scrollFrame = CreateFrame("ScrollFrame", nil, window, "FauxScrollFrameTemplate")
    scrollFrame:SetSize(WINDOW_WIDTH - 40, WINDOW_HEIGHT - 200)
    scrollFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -5)
    scrollFrame:SetFrameLevel(FRAME_LEVEL)
    scrollFrame:SetFrameStrata(FRAME_STRATA)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() Viewer:UpdateRows() end)
    end)

    
    self.window = window
    self.scrollFrame = scrollFrame
    self.equipmentBtn = equipmentBtn
    self.mysticBtn = mysticBtn
    self.bmvBtn = bmvBtn
    self.msvBtn = msvBtn
    self.searchBox = searchBox
    self.searchClearBtn = clearBtn
    self.additionalFiltersFrame = additionalFiltersFrame
    self.sourceFilterBtn = sourceFilterBtn
    self.qualityFilterBtn = qualityFilterBtn
    self.lootedFilterBtn = lootedFilterBtn
    self.nameHeader = nameHeader
    self.levelHeader = levelHeader
    self.slotHeader = slotHeader
    self.typeHeader = typeHeader
    self.classHeader = classHeader
    self.zoneHeader = zoneHeader    
    self.foundByHeader = foundByHeader
    self.vendorNameHeader = vendorNameHeader
    self.vendorZoneHeader = vendorZoneHeader
    self.inventoryHeader = inventoryHeader
    self.clearAllBtn = clearAllBtn
    self.actionsLabel = actionsLabel
    self.pageInfo = pageInfo
    self.prevBtn = prevBtn
    self.nextBtn = nextBtn
    self.items25Btn = items25Btn
    self.items50Btn = items50Btn
    self.items100Btn = items100Btn
    self.duplicatesFilterBtn = duplicatesFilterBtn 
    self.slotsFilterBtn = slotsFilterBtn
    self.usableByFilterBtn = usableByFilterBtn
    
     
    self.interactiveElements = {
        equipmentBtn, mysticBtn, bmvBtn, msvBtn,
        searchBox, sourceFilterBtn, qualityFilterBtn, lootedFilterBtn, duplicatesFilterBtn,
        nameHeader, levelHeader, slotHeader, typeHeader, classHeader, zoneHeader,  foundByHeader,
        vendorNameHeader, vendorZoneHeader,
        clearAllBtn, prevBtn, nextBtn, items25Btn, items50Btn, items100Btn,
        slotsFilterBtn, usableByFilterBtn
    }

    
    self:CreateRows()

    
    self.currentFilter = "eq"
    self:UpdateFilterButtons()
    self:UpdateSortHeaders()
    self:UpdateItemsPerPageButtons()
    self:UpdateFilterButtonStates()
	

    
    if WorldMapFrame then
        self.window:SetFrameLevel(WorldMapFrame:GetFrameLevel() -1)
    end
end

function Viewer:CreateRows()
    local visibleRows = math.floor((WINDOW_HEIGHT - 200) / ROW_HEIGHT)

    for i = 1, visibleRows do
        local row = CreateFrame("Frame", nil, self.scrollFrame:GetParent())
        row:SetSize(WINDOW_WIDTH - 40, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", self.scrollFrame, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetFrameLevel(FRAME_LEVEL)
        row:SetFrameStrata(FRAME_STRATA)

        
        row.highlight = row:CreateTexture(nil, "OVERLAY")
        row.highlight:SetAllPoints(true)
        row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.highlight:SetBlendMode("ADD")
        row.highlight:Hide()

        
        
        
        local nameFrame = CreateFrame("Frame", nil, row)
        nameFrame:SetSize(GRID_LAYOUT.NAME_WIDTH, ROW_HEIGHT)
        nameFrame:SetPoint("LEFT", 5, 0)
        nameFrame:EnableMouse(true)

        local nameText = nameFrame:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
        nameText:SetPoint("LEFT", 0, 0)
        nameText:SetSize(GRID_LAYOUT.NAME_WIDTH, ROW_HEIGHT)
        nameText:SetJustifyH("LEFT")

        
        nameFrame:SetScript("OnEnter", function(self)
            if self.discoveryData then
                local d = self.discoveryData.discovery
                
                if d.il then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 20, 10)
                    GameTooltip:SetHyperlink(d.il)
                    GameTooltip:Show()
                elseif d.i then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 20, 10)
                    GameTooltip:SetHyperlink("item:" .. d.i)
                    GameTooltip:Show()
                end
            end
        end)

        nameFrame:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)	  
	  

        nameFrame:SetScript("OnMouseUp", function(self, button)
            if not self.discoveryData then
                return
            end

            local data = self.discoveryData
            local row  = self:GetParent()

            
            Viewer:SetSelectedRow(row)

            
            local isVendorView = (Viewer.currentFilter == "bmv" or Viewer.currentFilter == "msv")
            if isVendorView and data.isVendor and button == "LeftButton" and not IsShiftKeyDown() and not IsControlKeyDown() then
                if Viewer.ShowVendorInventoryForDiscovery and data.discovery then
                    Viewer:ShowVendorInventoryForDiscovery(data.discovery)
                end
                return
            end

            
            if IsShiftKeyDown() and data then
                
                Viewer:ShowOnMap(data)
                return
            end

            local isCtrlDown = IsControlKeyDown()

            if button == "LeftButton" then
                if isCtrlDown then
                    
                    self:LinkItemToChat()
                end
            elseif button == "RightButton" then
                if isCtrlDown then
                    
                    local zoneName = GetLocalizedZoneName(data.discovery)
                    local coords = ""
                    if data.discovery.xy then
                        coords = string.format("%.1f, %.1f", (data.discovery.xy.x or 0) * 100, (data.discovery.xy.y or 0) * 100)
                    end
                    local msg = string.format("%s @ %s (%s)", data.discovery.il or "Item", zoneName, coords)
                    if ChatFrame1EditBox:IsVisible() then
                        ChatFrame1EditBox:Insert(msg)
                    else
                        ChatFrame_OpenChat(msg)
                    end
                else
                    
                    self:ShowContextMenu()
                end
            end
        end)

        nameFrame:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" then
                local x, y = GetCursorPosition()
                self.mouseX = x
                self.mouseY = y
            end
        end)

        
        
        

        
        local levelText = row:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
        levelText:SetPoint("LEFT", nameFrame, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        levelText:SetSize(GRID_LAYOUT.LEVEL_WIDTH, ROW_HEIGHT)
        levelText:SetJustifyH("LEFT")

        
        local slotText = row:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
        slotText:SetPoint("LEFT", levelText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        slotText:SetSize(GRID_LAYOUT.SLOT_WIDTH, ROW_HEIGHT)
        slotText:SetJustifyH("LEFT")
        slotText:Hide()

        
        local typeText = row:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
        typeText:SetPoint("LEFT", slotText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        typeText:SetSize(GRID_LAYOUT.TYPE_WIDTH, ROW_HEIGHT)
        typeText:SetJustifyH("LEFT")
        typeText:Hide()

        
        
        local classText = row:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
        classText:SetPoint("LEFT", levelText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        classText:SetSize(GRID_LAYOUT.CLASS_WIDTH, ROW_HEIGHT)
        classText:SetJustifyH("LEFT")
        classText:Hide()

        
        local zoneText = row:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
        zoneText:SetPoint("LEFT", typeText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        zoneText:SetSize(GRID_LAYOUT.ZONE_WIDTH, ROW_HEIGHT)
        zoneText:SetJustifyH("LEFT")

        
        
        
        local foundByFrame = CreateFrame("Frame", nil, row)
        foundByFrame:SetSize(GRID_LAYOUT.FOUND_BY_WIDTH, ROW_HEIGHT)
        foundByFrame:SetPoint("LEFT", zoneText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        foundByFrame:EnableMouse(true)

        local foundByText = foundByFrame:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
        foundByText:SetPoint("LEFT", 2, 0)
        foundByText:SetSize(GRID_LAYOUT.FOUND_BY_WIDTH - 4, ROW_HEIGHT)
        foundByText:SetJustifyH("LEFT")

        foundByFrame:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" and self.discoveryData then
                local x, y = GetCursorPosition()
                self.mouseX = x
                self.mouseY = y
                self:ShowFoundByContextMenu()
            end
        end)

        foundByFrame.ShowFoundByContextMenu = function(self)
            if not self.discoveryData or not self.discoveryData.discovery.fp then
                return
            end

            local playerName = self.discoveryData.discovery.fp
            local buttons = {
                {
                    text = "Delete all from " .. playerName,
                    onClick = function()
                        Viewer:ConfirmDeleteAllFromPlayer(playerName)
                    end,
                },
            }

            CreateContextMenu(self, "Player: " .. playerName, buttons)
        end

        
        
        
        local vendorNameText = row:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
        vendorNameText:SetPoint("LEFT", 5, 0)
        vendorNameText:SetSize(GRID_LAYOUT.VENDOR_NAME_WIDTH, ROW_HEIGHT)
        vendorNameText:SetJustifyH("LEFT")
        vendorNameText:Hide()

        
        local vendorNameFrame = CreateFrame("Frame", nil, row)
        vendorNameFrame:SetPoint("TOPLEFT", vendorNameText, "TOPLEFT", 0, 0)
        vendorNameFrame:SetPoint("BOTTOMRIGHT", vendorNameText, "BOTTOMRIGHT", 0, 0)
        vendorNameFrame:EnableMouse(true)
        vendorNameFrame:Hide()

        vendorNameFrame:SetScript("OnMouseUp", function(self, button)
            if not self.discoveryData then
                return
            end

            local data = self.discoveryData
            local row  = self:GetParent()

            Viewer:SetSelectedRow(row)

            
            if IsShiftKeyDown() and data then        
                    Viewer:ShowOnMap(data)        
                return
            end

            local isVendorView = (Viewer.currentFilter == "bmv" or Viewer.currentFilter == "msv")
            if isVendorView and data.isVendor and button == "LeftButton"
               and not IsControlKeyDown() then
                if Viewer.ShowVendorInventoryForDiscovery and data.discovery then
                    Viewer:ShowVendorInventoryForDiscovery(data.discovery)
                end
            end
        end)

        local vendorZoneText = row:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
        vendorZoneText:SetPoint("LEFT", vendorNameText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        vendorZoneText:SetSize(GRID_LAYOUT.VENDOR_ZONE_WIDTH, ROW_HEIGHT)
        vendorZoneText:SetJustifyH("LEFT")
        vendorZoneText:Hide()

        local inventoryFrame = CreateFrame("Frame", nil, row)
        inventoryFrame:SetSize(GRID_LAYOUT.VENDOR_INVENTORY_WIDTH, ROW_HEIGHT)
        inventoryFrame:SetPoint("LEFT", vendorZoneText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        inventoryFrame:EnableMouse(true)
        inventoryFrame:Hide()

        local inventoryText = inventoryFrame:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
        inventoryText:SetAllPoints(true)
        inventoryText:SetJustifyH("LEFT")
        inventoryText:SetText("|cff00ff00View Items...|r")

        inventoryFrame:SetScript("OnEnter", function(self)
            if self.discoveryData and self.discoveryData.isVendor and self.discoveryData.discovery.vendorItems then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Inventory", 1, 1, 0)
                for _, item in ipairs(self.discoveryData.discovery.vendorItems) do
                    GameTooltip:AddLine(item.link)
                end
                GameTooltip:Show()
            end
        end)

        inventoryFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        inventoryFrame:SetScript("OnMouseUp", function(self, button)
            if not self.discoveryData then
                return
            end

            local data = self.discoveryData
            local row  = self:GetParent()

            Viewer:SetSelectedRow(row)

            local isVendorView = (Viewer.currentFilter == "bmv" or Viewer.currentFilter == "msv")
            if isVendorView and data.isVendor and button == "LeftButton"
               and not IsShiftKeyDown() and not IsControlKeyDown() then
                if Viewer.ShowVendorInventoryForDiscovery and data.discovery then
                    Viewer:ShowVendorInventoryForDiscovery(data.discovery)
                end
            end
        end)

        
        
        
        local actionButtonSize = 22
        local actionButtonSpacing = 4

        
        local deleteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        deleteBtn:SetSize(actionButtonSize, actionButtonSize)
        deleteBtn:SetPoint("RIGHT", -5, 0)
        deleteBtn:SetText("D")
        deleteBtn:SetScript("OnClick", function(self)
            Viewer:SetSelectedRow(self:GetParent())
            local r = self:GetParent()
            if r.discoveryData then
                Viewer:ConfirmDelete(r.discoveryData)
            end
        end)

        deleteBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:SetText("Delete")
            GameTooltip:Show()
        end)
        deleteBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        
        local unlootedBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        unlootedBtn:SetSize(actionButtonSize, actionButtonSize)
        unlootedBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -actionButtonSpacing, 0)
        unlootedBtn:SetText("U")
        unlootedBtn:SetScript("OnClick", function(self)
            Viewer:SetSelectedRow(self:GetParent())
            local r = self:GetParent()
            if r.discoveryData then
                Viewer:ToggleLootedState(r.discoveryData.guid, r.discoveryData)
            end
        end)
        unlootedBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:SetText("Mark as Unlooted")
            GameTooltip:Show()
        end)
        unlootedBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        
        local lootedBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        lootedBtn:SetSize(actionButtonSize, actionButtonSize)
        lootedBtn:SetPoint("RIGHT", unlootedBtn, "LEFT", -actionButtonSpacing, 0)
        lootedBtn:SetText("L")
        lootedBtn:SetScript("OnClick", function(self)
            Viewer:SetSelectedRow(self:GetParent())
            local r = self:GetParent()
            if r.discoveryData then
                Viewer:ToggleLootedState(r.discoveryData.guid, r.discoveryData)
            end
        end)
        lootedBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:SetText("Mark as Looted")
            GameTooltip:Show()
        end)
        lootedBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        
        local navBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        navBtn:SetSize(actionButtonSize, actionButtonSize)
        navBtn:SetPoint("RIGHT", lootedBtn, "LEFT", -actionButtonSpacing, 0)
        navBtn:SetText("N")
        navBtn:SetScript("OnClick", function(self)
            Viewer:SetSelectedRow(self:GetParent())
            local r = self:GetParent()
            if r.discoveryData then
                local Arrow = L:GetModule("Arrow", true)
                if Arrow and Arrow.NavigateTo then
                    Arrow:NavigateTo(r.discoveryData.discovery)
                end
            end
        end)
        navBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:SetText("Navigate")
            GameTooltip:Show()
        end)
        navBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        
        local showBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        showBtn:SetSize(actionButtonSize, actionButtonSize)
        showBtn:SetPoint("RIGHT", navBtn, "LEFT", -actionButtonSpacing, 0)
        showBtn:SetText("S")
        showBtn:SetScript("OnClick", function(self)
            Viewer:SetSelectedRow(self:GetParent())
            local r = self:GetParent()
            if r.discoveryData then
                Viewer:ShowOnMap(r.discoveryData)
            end
        end)
        showBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:SetText("Show on Map")
            GameTooltip:Show()
        end)
        showBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        
        
        
        nameFrame.ShowContextMenu = function(self)
            if not self.discoveryData then return end

            local isLooted = Viewer:IsLootedByChar(self.discoveryData.guid)
            local buttons = {
                {
                    text = "Show",
                    onClick = function()
                        Viewer:ShowOnMap(self.discoveryData)
                    end,
                },
                {
                    text = isLooted and "Set as unlooted" or "Set as looted",
                    onClick = function()
                        Viewer:ToggleLootedState(self.discoveryData.guid, self.discoveryData)
                    end,
                },
                {
                    text = "Delete",
                    onClick = function()
                        Viewer:ConfirmDelete(self.discoveryData)
                    end,
                },
            }

            CreateContextMenu(self, self.discoveryData.itemName or "Unknown Item", buttons)
        end

        nameFrame.LinkItemToChat = function(self)
            if not self.discoveryData or not self.discoveryData.discovery then return end

            local discovery = self.discoveryData.discovery
            local itemID = discovery.i
            local itemLink = discovery.il

            if not itemID and itemLink and type(itemLink) == "string" then
                local id = itemLink:match("item:(%d+)")
                if id then
                    itemID = tonumber(id)
                end
            end

            if not itemID then return end

            if IsShiftKeyDown() and ChatFrameEditBox and ChatFrameEditBox:IsShown() then
                ChatFrameEditBox:Insert(itemLink or ("item:" .. itemID))
            end
        end

        
        
        
        row.nameFrame      = nameFrame
        row.nameText       = nameText
        row.levelText      = levelText
        row.slotText       = slotText
        row.typeText       = typeText
        row.classText      = classText
        row.zoneText       = zoneText
        row.foundByFrame   = foundByFrame
        row.foundByText    = foundByText

        row.vendorNameText  = vendorNameText
	row.vendorNameFrame = vendorNameFrame
	row.vendorZoneText  = vendorZoneText
	row.inventoryFrame  = inventoryFrame
	row.inventoryText   = inventoryText

        row.deleteBtn      = deleteBtn
        row.unlootedBtn    = unlootedBtn
        row.lootedBtn      = lootedBtn
        row.navBtn         = navBtn
        row.showBtn        = showBtn

        self.rows[i] = row
    end
end    

function Viewer:UpdateFilterButtons()
    
    local function setButtonTextColor(button, r, g, b)
        local fontString = button:GetFontString()
        if fontString then
            fontString:SetTextColor(r, g, b)
        end
    end

    
    setButtonTextColor(self.equipmentBtn, 1, 1, 1)
    setButtonTextColor(self.mysticBtn, 1, 1, 1)
    setButtonTextColor(self.bmvBtn, 1, 1, 1)
    setButtonTextColor(self.msvBtn, 1, 1, 1)

    
    if self.currentFilter == "eq" then
        setButtonTextColor(self.equipmentBtn, 0.2, 0.8, 1)
    elseif self.currentFilter == "ms" then
        setButtonTextColor(self.mysticBtn, 0.2, 0.8, 1)
    elseif self.currentFilter == "bmv" then
        setButtonTextColor(self.bmvBtn, 0.2, 0.8, 1)
    elseif self.currentFilter == "msv" then
        setButtonTextColor(self.msvBtn, 0.2, 0.8, 1)
    end
end

function Viewer:UpdateSortHeaders()
    
    local function setButtonTextColor(button, r, g, b)
        local fontString = button:GetFontString()
        if fontString then
            fontString:SetTextColor(r, g, b)
        end
    end

    local isEqView = (self.currentFilter == "eq")
    local isMsView = (self.currentFilter == "ms")
    local isVendorView = (self.currentFilter == "bmv" or self.currentFilter == "msv")

    
    self.nameHeader:Hide(); self.slotHeader:Hide(); self.typeHeader:Hide(); self.classHeader:Hide()
    self.zoneHeader:Hide(); self.levelHeader:Hide(); self.foundByHeader:Hide()
    self.vendorNameHeader:Hide(); self.vendorZoneHeader:Hide(); self.inventoryHeader:Hide()
    
    local lastHeader = nil

    if isVendorView then
        self.vendorNameHeader:Show(); self.vendorZoneHeader:Show(); self.inventoryHeader:Show()
        
        
        self.vendorNameHeader:ClearAllPoints()
        self.vendorNameHeader:SetPoint("LEFT", 5, 0)
        lastHeader = self.vendorNameHeader

        self.vendorZoneHeader:ClearAllPoints()
        self.vendorZoneHeader:SetPoint("LEFT", lastHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        lastHeader = self.vendorZoneHeader

        self.inventoryHeader:ClearAllPoints()
        self.inventoryHeader:SetPoint("LEFT", lastHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        lastHeader = self.inventoryHeader

        
        local sortIndicator = self.sortAscending and " ↑" or " ↓"
        local sortColor = {0.2, 0.8, 1}
        local defaultColor = {1, 1, 1}

        setButtonTextColor(self.vendorNameHeader, self.sortColumn == "vendorName" and sortColor[1] or defaultColor[1], self.sortColumn == "vendorName" and sortColor[2] or defaultColor[2], self.sortColumn == "vendorName" and sortColor[3] or defaultColor[3])
        setButtonTextColor(self.vendorZoneHeader, self.sortColumn == "zone" and sortColor[1] or defaultColor[1], self.sortColumn == "zone" and sortColor[2] or defaultColor[2], self.sortColumn == "zone" and sortColor[3] or defaultColor[3])
        
        self.vendorNameHeader:SetText(self.sortColumn == "vendorName" and "Vendor Name" .. sortIndicator or "Vendor Name")
        self.vendorZoneHeader:SetText(self.sortColumn == "zone" and "Zone" .. sortIndicator or "Zone")

    else 
        
        self.nameHeader:Show(); self.levelHeader:Show(); self.zoneHeader:Show(); self.foundByHeader:Show()
        
        
        self.nameHeader:ClearAllPoints()
        self.nameHeader:SetPoint("LEFT", 5, 0)
        lastHeader = self.nameHeader

        self.levelHeader:ClearAllPoints()
        self.levelHeader:SetPoint("LEFT", lastHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        lastHeader = self.levelHeader

        if isEqView then
            self.slotHeader:Show()
            self.typeHeader:Show()

            self.slotHeader:ClearAllPoints()
            self.slotHeader:SetPoint("LEFT", lastHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
            lastHeader = self.slotHeader

            self.typeHeader:ClearAllPoints()
            self.typeHeader:SetPoint("LEFT", lastHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
            lastHeader = self.typeHeader
        elseif isMsView then
            self.classHeader:Show()

            self.classHeader:ClearAllPoints()
            self.classHeader:SetPoint("LEFT", lastHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
            lastHeader = self.classHeader
        end
        
        
        self.zoneHeader:ClearAllPoints()
        self.zoneHeader:SetPoint("LEFT", lastHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        lastHeader = self.zoneHeader

        self.foundByHeader:ClearAllPoints()
        self.foundByHeader:SetPoint("LEFT", lastHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        
        
        local sortIndicator = self.sortAscending and " ↑" or " ↓"
        local headerMap = { name=self.nameHeader, level=self.levelHeader, slot=self.slotHeader, type=self.typeHeader, class=self.classHeader, zone=self.zoneHeader,  foundBy=self.foundByHeader }
        local headerTextMap = { name="Name", level="Level", slot="Slot", type="Type", class="Class", zone="Zone", foundBy="Found By" }
        
        for col, header in pairs(headerMap) do
            if header:IsShown() then
                local isSorted = (col == self.sortColumn)
                local isFiltered = false
                if (self.currentFilter == "eq" and self.columnFilters.eq[col] and next(self.columnFilters.eq[col])) or
                   (self.currentFilter == "ms" and self.columnFilters.ms[col] and next(self.columnFilters.ms[col])) or
                   (self.columnFilters[col] and next(self.columnFilters[col])) then
                    isFiltered = true
                end

                if isSorted then
                    setButtonTextColor(header, 0.2, 0.8, 1) 
                elseif isFiltered then
                    setButtonTextColor(header, 1, 0.8, 0.2) 
                else
                    setButtonTextColor(header, 1, 1, 1) 
                end

                local text = headerTextMap[col]
                if isSorted then text = text .. sortIndicator end
                if isFiltered then text = text .. " [F]" end
                header:SetText(text)
            end
        end
    end
end

function Viewer:UpdatePagination()
    local totalPages = self:GetTotalPages()
    local totalItems = self.totalItems

    
    if self.pageInfo then
        
        if Cache.discoveriesBuilding then
            self.pageInfo:SetText("Loading...")
        else
            self.pageInfo:SetText(string.format("Page %d of %d (%d total items)", self.currentPage, totalPages,
                totalItems))
        end
    end

    
    if self.prevBtn then
        
        self.prevBtn:SetEnabled(not Cache.discoveriesBuilding and self.currentPage > 1)
    end
    if self.nextBtn then
        
        self.nextBtn:SetEnabled(not Cache.discoveriesBuilding and self.currentPage < totalPages)
    end
end

function Viewer:UpdateItemsPerPageButtons()
    
    local function setButtonTextColor(button, r, g, b)
        local fontString = button:GetFontString()
        if fontString then
            fontString:SetTextColor(r, g, b)
        end
    end

    
    if self.items25Btn then setButtonTextColor(self.items25Btn, 1, 1, 1) end
    if self.items50Btn then setButtonTextColor(self.items50Btn, 1, 1, 1) end
    if self.items100Btn then setButtonTextColor(self.items100Btn, 1, 1, 1) end

    
    if self.itemsPerPage == 25 and self.items25Btn then
        setButtonTextColor(self.items25Btn, 0.2, 0.8, 1)
    elseif self.itemsPerPage == 50 and self.items50Btn then
        setButtonTextColor(self.items50Btn, 0.2, 0.8, 1)
    elseif self.itemsPerPage == 100 and self.items100Btn then
        setButtonTextColor(self.items100Btn, 0.2, 0.8, 1)
    end
end

function Viewer:UpdateRows()
    local discoveries = self:GetPaginatedDiscoveries()
    local numDiscoveries = #discoveries
    local numRows = #self.rows

    
    self:UpdatePagination()

    local isEqView = (self.currentFilter == "eq")
    local isMsView = (self.currentFilter == "ms")
    local isVendorView = (self.currentFilter == "bmv" or self.currentFilter == "msv")
    
    local isLoading = Cache.discoveriesBuilding

    
    FauxScrollFrame_Update(self.scrollFrame, numDiscoveries, numRows, ROW_HEIGHT)
    
     if self.scrollFrame.ScrollBar and self.scrollFrame.ScrollBar.ScrollUpButton then
        self.scrollFrame.ScrollBar.ScrollUpButton:SetFrameStrata(FRAME_STRATA)
        self.scrollFrame.ScrollBar.ScrollUpButton:SetFrameLevel(FRAME_LEVEL)
    end
    if self.scrollFrame.ScrollBar and self.scrollFrame.ScrollBar.ScrollDownButton then
        self.scrollFrame.ScrollBar.ScrollDownButton:SetFrameStrata(FRAME_STRATA)
        self.scrollFrame.ScrollBar.ScrollDownButton:SetFrameLevel(FRAME_LEVEL)
    end

    for i = 1, numRows do
        local row = self.rows[i]
        local offset = FauxScrollFrame_GetOffset(self.scrollFrame)
        local data = discoveries[i + offset]

        if data then
            local discovery = data.discovery
           row.discoveryData = data
		row.nameFrame.discoveryData       = data
		row.foundByFrame.discoveryData    = data
		row.vendorNameFrame.discoveryData = data
		row.inventoryFrame.discoveryData  = data

            
            
            row.nameFrame:SetShown(not isVendorView)
            row.levelText:SetShown(not isVendorView)
            row.zoneText:SetShown(isEqView or isMsView)
            row.foundByFrame:SetShown(isEqView or isMsView)
            row.slotText:SetShown(isEqView)
            row.typeText:SetShown(isEqView)
            row.classText:SetShown(isMsView)
		
            row.vendorNameText:SetShown(isVendorView)
		row.vendorNameFrame:SetShown(isVendorView)
		row.vendorZoneText:SetShown(isVendorView)
		row.inventoryFrame:SetShown(isVendorView)

            
            if self.selectedRow == row then
                row.highlight:Show()
            else
                row.highlight:Hide()
            end
            
            if isVendorView then
                
                row.vendorNameText:SetText(discovery.vendorName or "Unknown")
                row.vendorZoneText:SetText(GetLocalizedZoneName(discovery))
                local invCount = (discovery.vendorItems and #discovery.vendorItems) or 0
                row.inventoryText:SetText(string.format("(%d items)", invCount))
            else
                
                local isLooted = self:IsLootedByChar(data.guid)
                local alpha = isLooted and 0.5 or 1.0
                local itemName = data.itemName
                
                
                local r, g, b = GetColorForDiscovery(discovery, discovery.i)
                itemName = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, itemName)
                
                row.nameText:SetText(itemName)
                row.nameText:SetAlpha(alpha)

                local lastElement = row.levelText
                
                if isEqView then
                    row.slotText:SetText(data.equipLoc and _G[data.equipLoc] or "")
                    row.slotText:SetAlpha(alpha)
                    row.typeText:SetText(data.itemSubType or "")
                    row.typeText:SetAlpha(alpha)
                    
                    row.zoneText:ClearAllPoints()
                    row.zoneText:SetPoint("LEFT", row.typeText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
                    lastElement = row.typeText
                elseif isMsView then
                    local classDisplay = ""
                    if data.cl and data.cl ~= "cl" then
                        local classToken = CLASS_ABBREVIATIONS_REVERSE[data.cl]
                        if classToken then
                            classDisplay = (_G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[classToken]) or (_G.LOCALIZED_CLASS_NAMES_FEMALE and _G.LOCALIZED_CLASS_NAMES_FEMALE[classToken]) or ""
                        end
                    end
                    if classDisplay == "" then classDisplay = data.characterClass or "" end
                    row.classText:SetText(classDisplay)
                    row.classText:SetAlpha(alpha)
                    
                    row.zoneText:ClearAllPoints()
                    row.zoneText:SetPoint("LEFT", row.classText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
                    lastElement = row.classText
                end
                
                
                if lastElement ~= row.levelText then
                     row.zoneText:SetPoint("LEFT", lastElement, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
                else 
                     row.zoneText:SetPoint("LEFT", row.levelText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
                end

                row.zoneText:SetText(GetLocalizedZoneName(discovery))
                row.zoneText:SetAlpha(alpha)
                local levelTextVal = data.minLevel or 0
                row.levelText:SetText(levelTextVal > 0 and tostring(levelTextVal) or "")
                row.levelText:SetAlpha(alpha)
                row.foundByText:SetText(discovery.fp or "Unknown")
                row.foundByText:SetAlpha(alpha)
            end
            
            
            local isLooted = self:IsLootedByChar(data.guid)
            row.lootedBtn:SetEnabled(not isVendorView and not isLooted and not isLoading)
            row.unlootedBtn:SetEnabled(not isVendorView and isLooted and not isLoading)
            row.lootedBtn:SetShown(not isVendorView)
            row.unlootedBtn:SetShown(not isVendorView)
            
            row.deleteBtn:SetEnabled(not isLoading)
            row.navBtn:SetEnabled(not isLoading)
            row.showBtn:SetEnabled(not isLoading)
            row.nameFrame:EnableMouse(not isLoading)
            
            row.deleteBtn:Show()
            row.navBtn:Show()
            row.showBtn:Show()
            
            row:Show()
        else
            row:Hide()
            row.discoveryData = nil
            row.nameFrame.discoveryData = nil
            row.foundByFrame.discoveryData = nil
            if row.highlight then row.highlight:Hide() end
            row.deleteBtn:Hide()
            row.navBtn:Hide()
            row.showBtn:Hide()
            row.lootedBtn:Hide()
            row.unlootedBtn:Hide()
        end
    end
end

function Viewer:PrewarmCache()
    
    if Cache.discoveriesBuilt or Cache.discoveriesBuilding then
        VDebug("PrewarmCache: skipped (built=" ..
            tostring(Cache.discoveriesBuilt) ..
            ", building=" .. tostring(Cache.discoveriesBuilding) .. ")")
        return
    end

    VDebug("PrewarmCache: starting async cache build in background")

    self:UpdateAllDiscoveriesCache(function()
        
        VDebug("PrewarmCache: async cache build complete (discoveries=" ..
            tostring(#Cache.discoveries) .. ")")

        
        
        
        
    end)
end

function Viewer:RefreshData()
 local t0 = time()
    VDebug("RefreshData: start, cacheBuilt=" .. tostring(Cache.discoveriesBuilt) ..
        ", building=" .. tostring(Cache.discoveriesBuilding))
    if not self.window or not self.window:IsShown() then return end

    
    local now = time()
    local dataHasChanged = HasDataChanged()
    local shouldRebuildCache = not Cache.discoveriesBuilt or dataHasChanged
    
     VDebug("RefreshData: dataHasChanged=" .. tostring(dataHasChanged) ..
        ", shouldRebuild=" .. tostring(shouldRebuild))

    if shouldRebuildCache and not Cache.discoveriesBuilding then
    VDebug("RefreshData: calling UpdateAllDiscoveriesCache(async)")
        self:UpdateAllDiscoveriesCache(function()
	      VDebug("RefreshData callback: async cache build complete, running GetFilteredDiscoveries + UpdateRows")
		local t1 = time()
            self:GetFilteredDiscoveries() 
            self:UpdateRows()
		VDebug("RefreshData callback: GetFilteredDiscoveries+UpdateRows took " ..
                tostring(time() - t1) .. "s")
        end)
    elseif Cache.discoveriesBuilt then
    VDebug("RefreshData: cache already built, running GetFilteredDiscoveries + UpdateRows")
        
	  local t1 = time()
        self:GetFilteredDiscoveries()
        self:UpdateRows()
	  VDebug("RefreshData: GetFilteredDiscoveries+UpdateRows took " ..
            tostring(time() - t1) .. "s")
    else
        VDebug("RefreshData: cache neither built nor rebuilding, nothing to do")
    end
    VDebug("RefreshData: end, total elapsed=" .. tostring(time() - t0) .. "s")
end

function Viewer:IsLootedByChar(guid)
    if not guid or not (L.db and L.db.char and L.db.char.looted) then
        return false
    end
    return L.db.char.looted[guid] and true or false
end

function Viewer:ToggleLootedState(guid, discoveryData)
    if not guid or not (L.db and L.db.char) then
        return false
    end

    L.db.char.looted = L.db.char.looted or {}
    local isCurrentlyLooted = self:IsLootedByChar(guid)

    if isCurrentlyLooted then
        
        L.db.char.looted[guid] = nil
        print(string.format("|cff00ff00LootCollector:|r Marked '%s' as unlooted.",
            discoveryData.itemName or "Unknown Item"))
    else
        
        L.db.char.looted[guid] = time()
        print(string.format("|cff00ff00LootCollector:|r Marked '%s' as looted.", discoveryData.itemName or "Unknown Item"))
    end

    
    local Map = L:GetModule("Map", true)
    if Map then
        Map.cacheIsDirty = true 
        if Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
            Map:Update()
        end
        if Map.UpdateMinimap then
            Map:UpdateMinimap()
        end
    end

    
    self:RefreshData()

    return not isCurrentlyLooted 
end

function Viewer:ClearCaches()
    
    clearAllTimers()

    
    local cacheKeys = keys(Cache)
    for _, key in ipairs(cacheKeys) do
        if key == "discoveries" then
            Cache[key] = {}
        elseif key == "discoveriesBuilt" or key == "discoveriesBuilding" then
            Cache[key] = false
        elseif key == "uniqueValuesValid" then
            Cache[key] = false
        elseif key == "uniqueValues" then
            Cache[key] = {
                slot = {},
                type = {},
                class = {},
                zone = {}
            }
        elseif key == "uniqueValuesContext" then
            Cache[key] = {}
        elseif key == "filteredResults" then
            Cache[key] = {}
        elseif key == "lastFilterState" then
            Cache[key] = nil
        elseif type(Cache[key]) == "table" then
            Cache[key] = {}
        end
    end

    
    local defaultFilters = {
        equipment = { slot = {}, type = {}, class = {} },
        mystic_scrolls = { class = {} },
        zone = {},
        source = {},
        quality = {},
        looted = {},
        duplicates = false 
    }
    self.columnFilters = copy(defaultFilters)

    
    Cache.duplicateItems = {}

    
    Cache.lastDiscoveryCount = nil

    
    L.itemInfoCache = {}

    
    Cache._cleanupRequired = true
end

function Viewer:OnDisable()
    
    clearAllTimers()

    
    self:ClearCaches()

    
    if self.window then
        self.window:Hide()
        
        self.window:SetScript("OnShow", nil)
        self.window:SetScript("OnHide", nil)
        self.window:SetScript("OnDragStart", nil)
        self.window:SetScript("OnDragStop", nil)
    end

    
    if self.contextMenu then
        self.contextMenu:Hide()
        self.contextMenu = nil
    end

    
    if self.filterDropdown then
        self.filterDropdown:Hide()
        self.filterDropdown = nil
    end

    
    if self.autocompleteDropdown then
        self.autocompleteDropdown:Hide()
        self.autocompleteDropdown = nil
    end

    
    if self.mapCleanupFrame then
        self.mapCleanupFrame:UnregisterAllEvents()
        self.mapCleanupFrame:SetScript("OnEvent", nil)
        self.mapCleanupFrame = nil
    end

    
    if localClassScanTip then
        localClassScanTip:Hide()
    end
    if localWorldforgedScanTip then
        localWorldforgedScanTip:Hide()
    end

    
    scanQueue = {}
    scanCursor = 0
    scanProgressCallback = nil

    
    self.window = nil
    self.scrollFrame = nil
    self.rows = {}
    self.currentFilter = "equipment"
    self.searchTerm = ""
    self.sortColumn = "name"
    self.sortAscending = true
    self.pendingMapAreaID = nil
    self.currentPage = 1
    self.totalItems = 0
end

function Viewer:AddDiscoveryToCache(guid, discovery)
    if not guid or not discovery then
        return false
    end
	
	if not discovery.il then return false end

    
    if not Cache.discoveriesBuilt or Cache.discoveriesBuilding then
        return false
    end

    
    if discovery.vendorType or (discovery.g and (discovery.g:find("BM-", 1, true) or discovery.g:find("MS-", 1, true))) then
        local vendorName = discovery.vendorName or "Unknown Vendor"
        
        
        for _, data in ipairs(Cache.discoveries) do
            if data.guid == guid then
                data.discovery = discovery
                data.isVendor = true
                data.vendorType = discovery.vendorType
                data.vendorName = vendorName
                data.itemName = vendorName
                
                
                Cache.filteredResults = {}
                Cache.lastFilterState = nil
                Cache.uniqueValuesValid = false
                Cache.uniqueValuesContext = {} 
                return true
            end
        end
        
        
        _tinsert(Cache.discoveries, {
            guid = guid,
            discovery = discovery,
            isVendor = true,
            vendorType = discovery.vendorType,
            vendorName = vendorName,
            isMystic = false,
            itemName = vendorName,
        })
        
        
        if #Cache.discoveries > 10000 then
            _tremove(Cache.discoveries, 1)
        end

        Cache.filteredResults = {}
        Cache.lastFilterState = nil
        Cache.uniqueValuesValid = false
        Cache.uniqueValuesContext = {} 
        
        return true
    end

    
    if not discovery.il then return false end
    
    local itemName = discovery.il:match("%[(.+)%]") or ""
    if not itemName or itemName == "" then
        return false
    end

    
    for _, data in ipairs(Cache.discoveries) do
        if data.guid == guid then
            
            data.discovery = discovery
            data.itemName = itemName
            data.isMystic = IsMysticScroll(itemName)
            data.isWorldforged = IsWorldforged(discovery.il)
            data.characterClass = GetItemCharacterClass(discovery.il, discovery.i)
            data.isVendor = false 

            
            local name, _, _, _, minLevel, itemTypeVal, itemSubTypeVal, _, equipLocVal = GetItemInfoSafe(discovery.il,
                discovery.i)
            data.itemType = itemTypeVal
            data.itemSubType = itemSubTypeVal
            
            
            local it, ist = discovery.it, discovery.ist
            if not it or not ist or it == 0 or ist == 0 then
                it, ist = GetItemTypeIDs(itemTypeVal, itemSubTypeVal)
            end
            data.it = it
            data.ist = ist
            
            data.equipLoc = equipLocVal
            data.minLevel = minLevel

            
            Cache.filteredResults = {}
            Cache.lastFilterState = nil
            Cache.uniqueValuesValid = false
            Cache.uniqueValuesContext = {} 
            return true
        end
    end

    
    local isMystic = IsMysticScroll(itemName)
    local isWorldforged = IsWorldforged(discovery.il)
    local characterClass = GetItemCharacterClass(discovery.il, discovery.i)

    
    local name, _, _, _, minLevel, itemTypeVal, itemSubTypeVal, _, equipLocVal = GetItemInfoSafe(discovery.il,
        discovery.i)

    
    local it, ist = discovery.it, discovery.ist
    if not it or not ist or it == 0 or ist == 0 then
        it, ist = GetItemTypeIDs(itemTypeVal, itemSubTypeVal)
    end

    _tinsert(Cache.discoveries, {
        guid = guid,
        discovery = discovery,
        itemName = itemName,
        isMystic = isMystic,
        isWorldforged = isWorldforged,
        itemType = itemTypeVal,
        itemSubType = itemSubTypeVal,
        it = it,
        ist = ist,
        equipLoc = equipLocVal,
        characterClass = characterClass,
        minLevel = minLevel,
        isVendor = false, 
    })

    
    if #Cache.discoveries > 10000 then
        _tremove(Cache.discoveries, 1)
    end

    
    Cache.filteredResults = {}
    Cache.lastFilterState = nil
    Cache.uniqueValuesValid = false

    return true
end

function Viewer:RemoveDiscoveryFromCache(guid)
    if not guid then return false end

    local cache = Cache
    if not cache or not cache.discoveriesBuilt then return false end
    local discoveries = cache.discoveries
    if not discoveries then return false end

    local n = #discoveries
    if n == 0 then return false end

    for i = 1, n do
        local data = discoveries[i]
        if data and data.guid == guid then
            
            discoveries[i] = discoveries[n]
            discoveries[n] = nil

            
            cache.filteredResults = {}
            cache.lastFilterState = nil
            cache.uniqueValuesValid = false
            cache.uniqueValuesContext = {}

            return true
        end
    end

    return false
end

function Viewer:ConfirmDelete(discoveryData)
    local itemName = discoveryData.itemName
    local zone = GetLocalizedZoneName(discoveryData.discovery)

    StaticPopup_Show("LOOTCOLLECTOR_VIEWER_DELETE",
        string.format("Delete discovery for '%s' in '%s'?", itemName, zone),
        nil,
        { guid = discoveryData.guid, viewer = self }
    )
end

function Viewer:DeleteDiscovery(guid)
    local Core = L:GetModule("Core", true)
    
    if Core and Core.ReportDiscoveryAsGone then
        Core:ReportDiscoveryAsGone(guid)
    end
end

function Viewer:FindDiscoveriesByPlayer(playerName)
    if not playerName or playerName == "" then
        return {}
    end

    local discoveriesByPlayer = {}

    
    local discoveries = L:GetDiscoveriesDB()
    for guid, discovery in pairs(discoveries or {}) do
        
        if discovery and type(discovery) == "table" and discovery.fp == playerName then
            _tinsert(discoveriesByPlayer, {
                guid = guid,
                discovery = discovery
            })
        end
    end

    return discoveriesByPlayer
end

function Viewer:DeleteAllFromPlayer(playerName)
    if not playerName or playerName == "" then
        return 0
    end

    local discoveriesToDelete = self:FindDiscoveriesByPlayer(playerName)
    local deletedCount = 0

    local Core = L:GetModule("Core", true)
    if Core and Core.RemoveDiscovery then
        for _, data in ipairs(discoveriesToDelete) do
            if Core:RemoveDiscovery(data.guid) then
                deletedCount = deletedCount + 1
            end
        end
    end

    if deletedCount > 0 then
        print(string.format("|cff00ff00LootCollector:|r Deleted %d discoveries from player '%s'.", deletedCount,
            playerName))

        
        if self.window and self.window:IsShown() then
            self:UpdateAllDiscoveriesCache(function()
                self:GetFilteredDiscoveries()
                self:UpdateRows()
            end)
        end
    end

    return deletedCount
end

function Viewer:ConfirmDeleteAllFromPlayer(playerName)
    if not playerName or playerName == "" then
        return
    end

    local discoveriesByPlayer = self:FindDiscoveriesByPlayer(playerName)
    local count = #discoveriesByPlayer

    if count == 0 then
        print(string.format("|cffff7f00LootCollector:|r No discoveries found for player '%s'.", playerName))
        return
    end

    StaticPopup_Show("LOOTCOLLECTOR_VIEWER_DELETE_ALL_FROM_PLAYER",
        string.format("Delete all %d discoveries from player '%s'?", count, playerName),
        nil,
        { playerName = playerName, viewer = self, count = count }
    )
end

function Viewer:ShowOnMap(discoveryData)
    local discovery = discoveryData.discovery or discoveryData
    if not discovery then
        print("LootCollector Viewer: No map data available for this discovery.")
        return
    end

    local Map = L:GetModule("Map", true)
    if not (Map and Map.FocusOnDiscovery) then
        print("LootCollector Viewer: Map module is not available.")
        return
    end

    
    local windowName = self.window and self.window:GetName()
    local wasInSpecialFrames = false
    if windowName then
        wasInSpecialFrames = removeFromSpecialFrames(windowName)
    end

    
    Map:FocusOnDiscovery(discovery)
    
    
    if wasInSpecialFrames and windowName then
        self.restoreToSpecialFrames = true
        self.windowNameToRestore = windowName
        self.inMapOperation = true 
    end
end

function Viewer:OnInitialize()
    self:CreateWindow()
    L:RegisterMessage("LootCollector_DiscoveriesUpdated", function(event, action, guid, discoveryData)

        
        local updated = false
        
        if action == "add" and guid and discoveryData then
            
            if Cache.discoveriesBuilt and not Cache.discoveriesBuilding then
                updated = self:AddDiscoveryToCache(guid, discoveryData)
            end
        elseif action == "update" and guid and discoveryData then
            
            if Cache.discoveriesBuilt and not Cache.discoveriesBuilding then
                updated = self:AddDiscoveryToCache(guid, discoveryData) 
            end
        elseif action == "remove" and guid then
            
            if Cache.discoveriesBuilt and not Cache.discoveriesBuilding then
                updated = self:RemoveDiscoveryFromCache(guid)
            end
        elseif action == "clear" then
            
            Cache.discoveriesBuilt = false
            Cache.discoveriesBuilding = false
            Cache.discoveries = {}
            Cache.filteredResults = {}
            Cache.lastFilterState = nil
            Cache.uniqueValuesValid = false
            Cache.uniqueValuesContext = {}
            Cache.duplicateItems = {}
            
            if self.window and self.window:IsShown() then
                
                self.pendingUpdatesCount = 0
                self:UpdateRefreshButton()
                self:RefreshData()
            end
            return
        else
            
            if Cache.discoveriesBuilt and not Cache.discoveriesBuilding then
                Cache.filteredResults = {}
                Cache.lastFilterState = nil
                Cache.uniqueValuesValid = false
                Cache.uniqueValuesContext = {}
                updated = true
            end
        end
        
        if updated then
            if self.window and self.window:IsShown() then
                
                self.pendingUpdatesCount = (self.pendingUpdatesCount or 0) + 1
                self:UpdateRefreshButton()
            else
                
                self.pendingUpdatesCount = 0
            end
        end
    end)

    
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnHide", function()
            
            if Viewer.restoreToSpecialFrames and Viewer.windowNameToRestore then
                
                createTimer(0.1, function()
                    
                    if Viewer.window and Viewer.window:IsShown() then
                        addToSpecialFrames(Viewer.windowNameToRestore)
                    end
                    
                    Viewer.restoreToSpecialFrames = false
                    Viewer.windowNameToRestore = nil
                    Viewer.inMapOperation = false 
                end)
            end
        end)
    end

    
    self:UpdateClearAllButton()
    
    self:UpdateFilterButtonStates()
end

function Viewer:Show()
    if not self.window then
        self:CreateWindow()
    end
    
      local t0 = time()
    VDebug("Show: start, currentFilter=" .. tostring(self.currentFilter) ..
        ", cacheBuilt=" .. tostring(Cache.discoveriesBuilt) ..
        ", building=" .. tostring(Cache.discoveriesBuilding))

    
    
    
    if WorldMapFrame and WorldMapFrame.GetFrameLevel then
        local level = WorldMapFrame:GetFrameLevel() - 1
        
		if level < 1 then 
            level = 1
        end
        self.window:SetFrameLevel(level)
    else
        
        self.window:SetFrameLevel(FRAME_LEVEL or 1)
    end
    

    
    self.pendingUpdatesCount = 0
    self:UpdateRefreshButton()

    self.window:Show()
    self.currentPage = self.currentPage or 1
    self.currentFilter = self.currentFilter or "eq"
    self:UpdateFilterButtons()
    self:UpdateSortHeaders()
    self:UpdateFilterButtonStates()
    self:RefreshData()

    
    self.pendingMapAreaID = nil
    VDebug("Show: end, elapsed=" .. tostring(time() - t0) .. "s")
end

function Viewer:Hide()
    if self.window then
        self.window:Hide()
    end
    
    self.pendingMapAreaID = nil
end

function Viewer:Toggle()
    if self.window and self.window:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

StaticPopupDialogs["LOOTCOLLECTOR_VIEWER_DELETE"] = {
    text = "%s",
    button1 = "Yes, Delete",
    button2 = "No, Cancel",
    OnAccept = function(self, data)
        if data and data.viewer and data.guid then
            data.viewer:DeleteDiscovery(data.guid)
            
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    showAlert = true,
}

StaticPopupDialogs["LOOTCOLLECTOR_VIEWER_DELETE_ALL_FROM_PLAYER"] = {
    text = "%s",
    button1 = "Yes, Delete All",
    button2 = "No, Cancel",
    OnAccept = function(self, data)
        if data and data.viewer and data.playerName then
            data.viewer:DeleteAllFromPlayer(data.playerName)
            
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    showAlert = true,
}

SLASH_LootCollectorVIEWER1 = "/lcviewer"
SLASH_LootCollectorVIEWER2 = "/lcv"
SlashCmdList["LootCollectorVIEWER"] = function(msg)
    local cmd = string.lower(msg or "")

    if cmd == "" then
        Viewer:Toggle()
    elseif cmd == "clear" then
        Viewer:ClearCaches()
        print("LootCollector Viewer: All caches cleared")
    elseif cmd == "rebuild" then
        Viewer:ClearCaches()
        Viewer:UpdateAllDiscoveriesCache(function()
            print("LootCollector Viewer: Cache rebuilt")
            if Viewer.window and Viewer.window:IsShown() then
                Viewer:RefreshData()
            end
        end)
    else
        print("LootCollector Viewer commands:")
        print("/lcviewer - Toggles viewer window")
        print("/lcviewer clear - Clears all caches")
        print("/lcviewer rebuild - Rebuilds all caches")
    end
end

return Viewer