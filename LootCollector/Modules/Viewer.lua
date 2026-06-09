local L = LootCollector
local Viewer = L:NewModule("Viewer")

Viewer._cacheBuildQueue = {}
Viewer._cacheBuildIndex = 1

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

local CUSTOM_CLASS_COLORS = {
    ["KNIGHTOFXOROTH"] = {r = 0.77, g = 0.12, b = 0.23},
    ["SONOFARUGAL"]    = {r = 0.77, g = 0.12, b = 0.23},
    ["FLESHWARDEN"]    = {r = 0.77, g = 0.12, b = 0.23},
    ["DEMONHUNTER"]    = {r = 0.64, g = 0.19, b = 0.79},
    ["BARBARIAN"]      = {r = 0.78, g = 0.61, b = 0.43},
    ["CHRONOMANCER"]   = {r = 1.00, g = 0.96, b = 0.41},
    ["CULTIST"]        = {r = 0.53, g = 0.53, b = 0.93},
    ["NECROMANCER"]    = {r = 0.67, g = 0.83, b = 0.45},
    ["PRIMALIST"]      = {r = 1.00, g = 0.49, b = 0.04},
    ["PYROMANCER"]     = {r = 1.00, g = 0.49, b = 0.04},
    ["RANGER"]         = {r = 0.67, g = 0.83, b = 0.45},
    ["REAPER"]         = {r = 0.00, g = 1.00, b = 0.59},
    ["RUNEMASTER"]     = {r = 0.41, g = 0.80, b = 0.94},
    ["STARCALLER"]     = {r = 0.41, g = 0.80, b = 0.94},
    ["STORMBRINGER"]   = {r = 0.00, g = 0.44, b = 0.87},
    ["SUNCLERIC"]      = {r = 1.00, g = 0.49, b = 0.04},
    ["TEMPLAR"]        = {r = 0.96, g = 0.55, b = 0.73},
    ["TINKER"]         = {r = 1.00, g = 0.96, b = 0.41},
    ["VENOMANCER"]     = {r = 0.67, g = 0.83, b = 0.45},
    ["WILDWALKER"]      = {r = 1.00, g = 0.49, b = 0.04},
    ["WITCHDOCTOR"]    = {r = 0.96, g = 0.55, b = 0.73},
    ["WITCHHUNTER"]    = {r = 0.53, g = 0.53, b = 0.93},
    ["GUARDIAN"]       = {r = 0.50, g = 0.50, b = 0.50},
}

Viewer.lootedFilterState = nil 
Viewer.collectedMEFilterState = nil 
Viewer.hasUncachedData = false
Viewer.lastSeenSortState = "off"

local time = time or os.time

local WINDOW_WIDTH = 1150
local WINDOW_HEIGHT = 674
local HEADER_HEIGHT = 25
local BUTTON_HEIGHT = 22
local BUTTON_WIDTH = 100
local CONTEXT_MENU_WIDTH = 200
local FRAME_LEVEL = 1
local FRAME_STRATA = "MEDIUM"

local GRID_LAYOUT = {
    
    NAME_WIDTH = 320,
    FAV_WIDTH = 10,
    LEVEL_WIDTH = 26,
    SLOT_WIDTH = 130,
    TYPE_WIDTH = 150,
    CLASS_WIDTH = 70,
    ZONE_WIDTH = 150,
    FOUND_BY_WIDTH = 120,

    VENDOR_NAME_WIDTH_INLINE = 256,
    VENDOR_NAME_WIDTH_SPLIT = 432, 
    VENDOR_PRICE_WIDTH = 60,
    VENDOR_TYPE_WIDTH = 250,
    VENDOR_INVENTORY_WIDTH = 68,
    VENDOR_ZONE_WIDTH = 150,
    VENDOR_CONTINENT_WIDTH = 128,

    
    COLUMN_SPACING = 8,
}

local ROW_HEIGHT = 24
local ROW_FONT_NAME = "LootCollectorViewerRowFont"
local ROW_FONT_SIZE = 14
local ROW_FONT_PATH = "Fonts\\ARIALN.TTF"

local UI_FONT_NAME = "LootCollectorViewerUIFont"
local UI_FONT_SIZE = 13
local UI_FONT_PATH = "Fonts\\ARIALN.TTF"

Viewer.window         = nil
Viewer.scrollFrame    = nil
Viewer.rows           = {}
Viewer._reusableCurrentFiltered = {}
Viewer._reusableFinalFiltered = {}
Viewer.selectedRow    = nil
Viewer.currentFilter  = "eq" 
Viewer.minReqLevel    = nil
Viewer.maxReqLevel    = nil
Viewer.searchTerm     = ""
Viewer.sortColumn     = "name"      
Viewer.sortAscending  = true
Viewer.pendingMapAreaID = nil

Viewer.currentPage    = 1
Viewer.itemsPerPage   = 100
Viewer.totalItems     = 0

Viewer.columnFilters  = {
    eq       = { slot = {}, type = {}, class = {} },
    ms       = { class = {} },
    zone     = {},
    source   = {},
    quality  = {},
    looted   = {},
    vendorType = {},
    duplicates = false,
}

Viewer.vendorInventoryFrame = nil      
Viewer.vendorInventoryLines = nil      
Viewer.selectedVendorGuid   = nil      

local function VDebug(msg)
    
    if LootCollector.db and LootCollector.db.profile and LootCollector.db.profile.vdebugMode then
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

local tooltipScanner = CreateFrame("GameTooltip", "LCSearchTooltipScanner", nil, "GameTooltipTemplate")
tooltipScanner:SetOwner(UIParent, "ANCHOR_NONE")

local function GetItemTooltipText(itemLink)
    if not itemLink or itemLink == "" then return nil end
    tooltipScanner:ClearLines()
    tooltipScanner:SetHyperlink(itemLink)
    local fullText = ""
    for i = 1, tooltipScanner:NumLines() do
        local left = _G["LCSearchTooltipScannerTextLeft"..i]
        if left and left:GetText() then
            fullText = fullText .. " " .. left:GetText()
        end
        local right = _G["LCSearchTooltipScannerTextRight"..i]
        if right and right:GetText() then
            fullText = fullText .. " " .. right:GetText()
        end
    end
    if fullText == "" then return nil end
    return string.lower(fullText)
end

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
    if not t then return 0 end
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
    
    local useWCAG = L.db and L.db.profile and L.db.profile.viewer and L.db.profile.viewer.useWCAGColoring
    if useWCAG == nil then useWCAG = true end

    if useWCAG then
        
        local WCAG_RGB = {
            [0] = { r = 0.63, g = 0.61, b = 0.58 }, 
            [1] = { r = 1.00, g = 1.00, b = 1.00 }, 
            [2] = { r = 0.12, g = 1.00, b = 0.00 }, 
            [3] = { r = 0.33, g = 0.70, b = 1.00 }, 
            [4] = { r = 0.78, g = 0.52, b = 1.00 }, 
            [5] = { r = 1.00, g = 0.50, b = 0.00 }, 
            [6] = { r = 0.80, g = 0.68, b = 0.47 }, 
            [7] = { r = 0.90, g = 0.80, b = 0.50 }, 
        }
        local c = WCAG_RGB[quality]
        if c then return c.r, c.g, c.b end
    else
        
        if _G.GetItemQualityColor then
            local r, g, b = _G.GetItemQualityColor(quality)
            if r and g and b then return r, g, b end
        end
        if _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality] then
            local c = _G.ITEM_QUALITY_COLORS[quality]
            return c.r or 1, c.g or 1, c.b or 1
        end
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

    local parent = self.window
    local f = CreateFrame("Frame", "LootCollectorViewerVendorInventory", parent)

    f:SetFrameStrata(FRAME_STRATA)
    f:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
    f:EnableMouse(true)

    
    f:SetPoint("TOPLEFT", self.scrollFrame, "BOTTOMLEFT", 0, -10)

    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)

    f.title = f:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetWidth(400)
    f.title:SetJustifyH("LEFT")
    f.title:SetText("Select a vendor to view inventory")

    
    f.headerRow = CreateFrame("Frame", nil, f)
    f.headerRow:SetHeight(16)
    f.headerRow:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
    f.headerRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -26, -8)

    f.nameHeader = f.headerRow:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
    f.nameHeader:SetPoint("LEFT", 8, 0)
    f.nameHeader:SetText("Item Name")
    f.nameHeader:SetTextColor(0.4, 0.6, 1.0)
    f.nameHeader:SetJustifyH("LEFT")

    f.priceHeader = f.headerRow:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
    f.priceHeader:SetPoint("RIGHT", -10, 0)
    f.priceHeader:SetText("Price")
    f.priceHeader:SetTextColor(0.4, 0.6, 1.0)
    f.priceHeader:SetJustifyH("RIGHT")

    local invScroll = CreateFrame("ScrollFrame", "LootCollectorViewerVendorInventoryScroll", f, "FauxScrollFrameTemplate")
    invScroll:SetPoint("TOPLEFT", f.headerRow, "BOTTOMLEFT", 0, -4)
    invScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 6)

    f.itemLines = {}
    for i = 1, 40 do 
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

        line.text = line:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
        line.text:SetPoint("LEFT", line.icon, "RIGHT", 4, 0)
        line.text:SetPoint("RIGHT", -80, 0)
        line.text:SetJustifyH("LEFT")
        line.text:SetText("")

        line.priceText = line:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
        line.priceText:SetPoint("RIGHT", line, "RIGHT", -10, 0)
        line.priceText:SetJustifyH("RIGHT")

        line.itemLink = nil
        line.parentVendorData = nil

        line:SetScript("OnEnter", function(self)
            if self.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.itemLink)
                GameTooltip:Show()
                GameTooltip:SetFrameStrata("TOOLTIP") 
            end
        end)
        line:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

        line:SetScript("OnClick", function(self)
            if IsShiftKeyDown() and self.parentVendorData then
                Viewer:ShowOnMap(self.parentVendorData)
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
                local zoneName = GetLocalizedZoneName and GetLocalizedZoneName(d) or ""
                if zoneName ~= "" and zoneName ~= "Unknown Zone" then
                    f.title:SetText(d.vendorName .. " – " .. zoneName)
                else
                    f.title:SetText(d.vendorName .. " Inventory")
                end
                
                local numItems = #d.vendorItems
                local visibleInvRows = math.max(1, math.floor((invScroll:GetHeight()) / 20))
                
                FauxScrollFrame_Update(invScroll, numItems, visibleInvRows, 20)
                local offset = FauxScrollFrame_GetOffset(invScroll)
                
                for i = 1, 40 do
                    local line = f.itemLines[i]
                    if i <= visibleInvRows then
                        local idx = offset + i
                        if idx <= numItems then
                            local itemData = d.vendorItems[idx]
                            if itemData then
                                local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemData.link or itemData.itemID or 0)
                                line.icon:SetTexture(texture or itemData.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                                line.text:SetText(itemData.link or itemData.name)
                                
                                if itemData.price and itemData.price > 0 then
                                    line.priceText:SetText(GetCoinTextureString(itemData.price))
                                else
                                    line.priceText:SetText("")
                                end

                                line.itemLink = itemData.link
                                line.parentVendorData = d
                                line:Show()
                            else
                                line:Hide()
                            end
                        else
                            line:Hide()
                        end
                    else
                        line:Hide()
                    end
                end
            else
                f.title:SetText("Vendor Inventory")
                FauxScrollFrame_Update(invScroll, 0, 1, 20)
                for _, line in ipairs(f.itemLines) do line:Hide() end
            end
        else
            f.title:SetText("Select a vendor to view inventory")
            FauxScrollFrame_Update(invScroll, 0, 1, 20)
            for _, line in ipairs(f.itemLines) do line:Hide() end
        end
    end

    invScroll:SetScript("OnVerticalScroll", function(s, dlt)
        FauxScrollFrame_OnVerticalScroll(s, dlt, 20, refreshInventory)
    end)
    
    f.refreshInventory = refreshInventory
    f.scrollFrame = invScroll 
    f.vendorItems = {}

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
    if not discovery then return end
    self:EnsureVendorInventoryPanel()
    if not self.vendorInventoryFrame then return end

    self.selectedVendorGuid = discovery.g
    if self.vendorInventoryFrame.scrollFrame then
        self.vendorInventoryFrame.scrollFrame.offset = 0
        self.vendorInventoryFrame.scrollFrame:SetVerticalScroll(0)
    end
    self:UpdateVendorInventoryScroll()
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
        local filterGroup = Viewer.columnFilters[Viewer.currentFilter]
        if filterGroup then
            if excludeColumn ~= "slot" and size(filterGroup.slot) > 0 then
                context.activeFilters.slot = filterGroup.slot
            end
            if excludeColumn ~= "type" and size(filterGroup.type) > 0 then
                context.activeFilters.type = filterGroup.type
            end
            if excludeColumn ~= "class" and size(filterGroup.class) > 0 then
                context.activeFilters.class = filterGroup.class
            end
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

    if excludeColumn ~= "quality" then
        if size(Viewer.columnFilters.quality) > 0 then
            context.activeFilters.quality = Viewer.columnFilters.quality
        end
    end

    if excludeColumn ~= "looted" and size(Viewer.columnFilters.looted) > 0 then
        context.activeFilters.looted = Viewer.columnFilters.looted
    end

    if excludeColumn ~= "vendorType" and size(Viewer.columnFilters.vendorType) > 0 then
        context.activeFilters.vendorType = Viewer.columnFilters.vendorType
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
    local filteredData = {}
    
    
    for i = 1, #Cache.discoveries do
        local data = Cache.discoveries[i]
        if data then
            local passed = true
            
            local Constants = L:GetModule("Constants", true)
            if Constants and Constants.IsForbiddenZone and Constants:IsForbiddenZone(data.discovery.c, data.discovery.z, data.discovery.fp) then
                passed = false
            end
            
            if passed and context.currentFilter == "eq" then
                if data.isVendor or data.isMystic then passed = false end
            elseif context.currentFilter == "ms" then
                if data.isVendor or not data.isMystic then passed = false end
            elseif context.currentFilter == "bmv" then
                if not data.isVendor or data.vendorType ~= "BM" then passed = false end
            elseif context.currentFilter == "msv" then
                if not data.isVendor or data.vendorType ~= "MS" then passed = false end
            end

            if passed and context.searchTerm and context.searchTerm ~= "" then
                local searchLower = _strlower(context.searchTerm)
                local nameMatch = false
                if data.isVendor then
                    nameMatch = _strfind(_strlower(data.vendorName or ""), searchLower, 1, true)
                else
                    nameMatch = _strfind(_strlower(data.itemName or ""), searchLower, 1, true)
                end
                
                local zoneName = GetLocalizedZoneName(data.discovery)
                local zoneMatch = _strfind(_strlower(zoneName), searchLower, 1, true)
                if not (nameMatch or zoneMatch) then passed = false end
            end

            if passed and context.activeFilters.slot then
                local slotValue = data.equipLoc and _G[data.equipLoc] or ""
                if not context.activeFilters.slot[slotValue] then passed = false end
            end

            if passed and context.activeFilters.type then
                local typeValue = data.itemSubType or ""
                if not context.activeFilters.type[typeValue] then passed = false end
            end

            if passed and context.activeFilters.class then
                if context.currentFilter == "eq" then
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
                            if not canUse then passed = false end
                        else
                            passed = false
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
                    if not context.activeFilters.class[classValue] then passed = false end
                end
            end

            if passed and context.activeFilters.zone then
                local zoneValue = GetLocalizedZoneName(data.discovery)
                if not context.activeFilters.zone[zoneValue] then passed = false end
            end

            if passed and context.activeFilters.source then
                local source = data.discovery.src or "unknown"
                local sourceValue = SOURCE_NAMES[source] or source
                if not context.activeFilters.source[sourceValue] then passed = false end
            end

            if passed and context.activeFilters.quality then
                local _, _, quality = GetItemInfoSafe(data.discovery.il, data.discovery.i)
                if not quality then
                    if not context.activeFilters.quality["Unknown"] then passed = false end
                else
                    local qualityValue = QUALITY_NAMES[quality] or ("Quality " .. tostring(quality))
                    if not context.activeFilters.quality[qualityValue] then passed = false end
                end
            end

            if passed and Viewer.lootedFilterState ~= nil then
                local isLooted = Viewer:IsLootedByChar(data.guid)
                if Viewer.lootedFilterState == true and not isLooted then passed = false end
                if Viewer.lootedFilterState == false and isLooted then passed = false end
            end

            if passed and Viewer.collectedMEFilterState ~= nil then
                if Constants and data.discovery.dt == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then
                    if data.discovery.i and data.discovery.i > 0 then
                        local isCollectedME = L:IsMysticEnchantCollected(data.discovery.i)
                        if Viewer.collectedMEFilterState == true and not isCollectedME then passed = false end
                        if Viewer.collectedMEFilterState == false and isCollectedME then passed = false end
                    end
                else
                    if Viewer.collectedMEFilterState == true then passed = false end
                end
            end

            if passed and context.activeFilters.duplicates then
                if not Cache.duplicateItems[data.discovery.i] or Cache.duplicateItems[data.discovery.i] <= 1 then
                    passed = false
                end
            end

            if passed then
                table.insert(filteredData, data)
            end
        end
    end

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
         local Constants = L:GetModule("Constants", true)
         local activeClasses = Constants and Constants:GetActiveClasses() or CLASS_OPTIONS
         
         for _, classToken in ipairs(activeClasses) do
             if classToken ~= "HERO" then 
                 local locName = Constants and Constants:GetLocalizedClassName(classToken) or classToken
                 _tinsert(values, locName)
             end
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
            end,
            vendorType = function(data)
                local typeMap = { ["BM"] = "Blackmarket", ["MS"] = "Mystic Enchants" }
                local vType = data.vendorType or (data.discovery and data.discovery.vendorType)
                if not vType and data.discovery and data.discovery.g then
                    if data.discovery.g:find("BM-", 1, true) then vType = "BM"
                    elseif data.discovery.g:find("MS-", 1, true) then vType = "MS"
                    end
                end
                return typeMap[vType] or vType or "Unknown"
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

    local Core = L:GetModule("Core", true)
    local isCoA = Core and Core.IsConfirmedCoARealm and Core:IsConfirmedCoARealm()

    for _, element in ipairs(self.interactiveElements) do
        if element then
            local isMsButton = (element == self.mysticBtn)
            if isMsButton and isCoA then
                element:Disable()
            else
                if enabled then
                    element:Enable()
                else
                    element:Disable()
                end
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

    contextMenu:SetFrameStrata("DIALOG")
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

    local titleText = contextMenu:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
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
        
        local btnText = btn:GetFontString()
        if btnText then
            btnText:SetFontObject(UI_FONT_NAME)
        end
        
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

function Viewer:ShowColumnFilterDropdown(column, anchor, values)
    local dropdownList = _G["DropDownList1"]
    if Viewer.currentFilterAnchor == anchor and dropdownList and dropdownList:IsShown() then
        HideDropDownMenu(1)
        Viewer.currentFilterAnchor = nil
        return
    end
    Viewer.currentFilterAnchor = anchor

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
                        if not zoneByKey[key] then zoneByKey[key] = { c = c, z = z, iz = iz } end
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
                    looted = function(data) return Viewer:IsLootedByChar(data.guid) and "Looted" or "Not Looted" end,
                    vendorType = function(data)
                        local typeMap = { ["BM"] = "Blackmarket", ["MS"] = "Mystic Enchants" }
                        local vType = data.vendorType or (data.discovery and data.discovery.vendorType)
                        if not vType and data.discovery and data.discovery.g then
                            if data.discovery.g:find("BM-", 1, true) then vType = "BM"
                            elseif data.discovery.g:find("MS-", 1, true) then vType = "MS" end
                        end
                        return typeMap[vType] or vType or "Unknown"
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

    if not values or #values == 0 then return end
    
    local filterTable
    if column == "zone" then filterTable = Viewer.columnFilters.zone
    elseif column == "source" then filterTable = Viewer.columnFilters.source
    elseif column == "quality" then filterTable = Viewer.columnFilters.quality
    elseif column == "looted" then filterTable = Viewer.columnFilters.looted
    elseif column == "vendorType" then filterTable = Viewer.columnFilters.vendorType
    else filterTable = Viewer.columnFilters[Viewer.currentFilter][column] end

    local dropdown = CreateFrame("Frame", "LootCollectorViewerFilterDropdown", Viewer.window, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local clearAllInfo = {
            text = "Clear All Filters",
            notCheckable = true,
            func = function()
                if filterTable then wipe(filterTable) end
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
                Viewer.collectedMEFilterState = nil 
                
                Viewer.searchTerm = ""
                if Viewer.searchBox then Viewer.searchBox:SetText("") end
                
                Viewer.minReqLevel = nil
                Viewer.maxReqLevel = nil
                if Viewer.minReqLevelBox then Viewer.minReqLevelBox:SetText("") end
                if Viewer.maxReqLevelBox then Viewer.maxReqLevelBox:SetText("") end

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

        local separatorInfo = { text = "", notCheckable = true, disabled = true }
        UIDropDownMenu_AddButton(separatorInfo, level)

        for _, value in ipairs(values) do
            local isChecked = false
            if filterTable then isChecked = filterTable[value] ~= nil end

            local displayText = value
            if column == "quality" then
                local useWCAG = L.db and L.db.profile and L.db.profile.viewer and L.db.profile.viewer.useWCAGColoring
                if useWCAG == nil then useWCAG = true end

                local map
                if useWCAG then
                    map = { 
                        ["Poor"] = "FFA09C93", 
                        ["Common"] = "FFFFFFFF", 
                        ["Uncommon"] = "FF1EFF00", 
                        ["Rare"] = "FF54B2FF", 
                        ["Epic"] = "FFC884FF", 
                        ["Legendary"] = "FFFF8000", 
                        ["Artifact"] = "FFCBAE77", 
                        ["Heirloom"] = "FFE6CC80" 
                    }
                else
                    map = { 
                        ["Poor"] = "FF605C53", 
                        ["Common"] = "FFFFFFFF", 
                        ["Uncommon"] = "FF1EFF00", 
                        ["Rare"] = "FF0070DD", 
                        ["Epic"] = "FFA335EE", 
                        ["Legendary"] = "FFFF8000", 
                        ["Artifact"] = "FFCBAE77", 
                        ["Heirloom"] = "FFE6CC80" 
                    }
                end
                local hex = map[value] or "FFFFFFFF"
                displayText = "|c" .. hex .. value .. "|r"
            elseif column == "class" then
                local classFileName = value:upper():gsub("%s+", "")
                local Constants = L:GetModule("Constants", true)
                if Constants and Constants.GetClassTokenFromLocalizedName then
                    local foundToken = Constants:GetClassTokenFromLocalizedName(value)
                    if foundToken ~= value then classFileName = foundToken end
                end

                local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFileName]
                if not color and CUSTOM_CLASS_COLORS then color = CUSTOM_CLASS_COLORS[classFileName] end

                if color then displayText = string.format("|cFF%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, value) end
            end

            local info = {
                text = displayText,
                checked = isChecked,
                func = function()
                    if not filterTable then return end
                    if filterTable[value] then filterTable[value] = nil else filterTable[value] = true end

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
    self.hasUncachedData = false
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

function Viewer:UpdateAllDiscoveriesCacheSync(onCompleteCallback)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if Cache.discoveriesBuilt or Cache.discoveriesBuilding then
        VDebug("UpdateAllDiscoveriesCacheSync: skipped (built=" .. tostring(Cache.discoveriesBuilt) .. ", building=" .. tostring(Cache.discoveriesBuilding) .. ")")
        if pTime then L:ProfileStop("Viewer:UpdateAllDiscoveries", pTime) end
        return
    end

    Cache.discoveriesBuilding = true
    self.hasUncachedData = false
    Cache.uniqueValuesValid   = false
    Cache.duplicateItems      = {} 

    if self.window and self.window:IsShown() then
        self:UpdatePagination()
        self:UpdateReloadHint()
    end

    wipe(self._cacheBuildQueue)
    self.scanProgressCallback = onCompleteCallback
    
    local discoveries = L:GetDiscoveriesDB()
    local vendors = L:GetVendorsDB()
    
    for guid, discovery in pairs(discoveries or {}) do
        table.insert(self._cacheBuildQueue, { guid = guid, d = discovery, isVendor = false })
    end
    for guid, discovery in pairs(vendors or {}) do
        table.insert(self._cacheBuildQueue, { guid = guid, d = discovery, isVendor = true })
    end
    
    self._cacheBuildIndex = 1
    
    local useAsync = L.db and L.db.profile and L.db.profile.viewer and L.db.profile.viewer.asyncLoading
    if useAsync == nil then useAsync = true end

    if useAsync then
        self:ProcessCacheBuildChunk()
    else
        
        self:ProcessCacheBuildChunk(999999) 
    end
    
    if pTime then L:ProfileStop("Viewer:UpdateAllDiscoveries", pTime) end
end

function Viewer:ProcessCacheBuildChunk(budgetOverride)
    if not Cache.discoveriesBuilding then return end
    
    local budget = budgetOverride or 8.0 
    local startMs = debugprofilestop()
    
    local outIndex = self._cacheBuildIndex
    local queue = self._cacheBuildQueue
    local total = #queue
    local processedThisFrame = 0
    
    local Core = L:GetModule("Core", true)
    
    
    
    local queueCursor = self._cacheQueueCursor or 1
    
    while queueCursor <= total do
        local entry = queue[queueCursor]
        local guid = entry.guid
        local discovery = entry.d
        local isVendor = entry.isVendor
        
        local row = Cache.discoveries[outIndex]
        if not row then
            row = {}
            Cache.discoveries[outIndex] = row
        end

        local itemSuccessfullyLoaded = false

        if not isVendor then
            local itemLink = discovery.il
            local itemID = discovery.i
            local itemName = nil
            
            if (not itemLink or itemLink == "") and itemID then
                 local name, link = GetItemInfo(itemID)
                 if link then itemLink = link end
            end
            
            if itemLink and itemLink ~= "" then
                itemName = itemLink:match("%[(.+)%]")
            end
                
            if (not itemName or itemName == "") and itemID then 
                itemName = GetItemInfo(itemID) 
            end
                
            if itemName and itemName ~= "" then
                local Scanner = L:GetModule("Scanner", true)
                local itemData = Scanner and Scanner:GetItemData(discovery.i, itemLink) or {}

                local isMystic = IsMysticScroll(itemName)
                local isWorldforged = itemData.isWF or false
                
                local characterClass = ""
                local classToken = itemData.classToken
                if classToken then
                    characterClass = _G.LOCALIZED_CLASS_NAMES_MALE[classToken] or _G.LOCALIZED_CLASS_NAMES_FEMALE[classToken] or classToken
                    
                    
                    
                    local Constants = L:GetModule("Constants", true)
                    if Constants and Constants.CLASS_ABBREVIATIONS[classToken] then
                        local correctAbbr = Constants.CLASS_ABBREVIATIONS[classToken]
                        if discovery.cl ~= correctAbbr then
                            discovery.cl = correctAbbr
                            L.DataHasChanged = true
                        end
                    end
                end

                local name, _, _, itemLevelVal, minLevel, itemTypeVal, itemSubTypeVal, _, equipLocVal = GetItemInfoSafe(itemLink, discovery.i)
                local finalMinLevel = itemData.reqLevel or minLevel or 0
                
                local it, ist = discovery.it, discovery.ist
                if not it or not ist or it == 0 or ist == 0 then
                    it, ist = GetItemTypeIDs(itemTypeVal, itemSubTypeVal)
                end
                
                if not itemTypeVal and not isMystic then
                    self.hasUncachedData = true
                end

                row.guid          = guid
                row.discovery     = discovery
                row.itemName      = itemName
                row.isMystic      = isMystic
                row.isWorldforged = isWorldforged
                row.itemType      = itemTypeVal
                row.itemSubType   = itemSubTypeVal
                row.it            = it
                row.ist           = ist
                row.equipLoc      = equipLocVal
                row.characterClass= characterClass
                row.itemLevel     = itemLevelVal
                row.minLevel      = finalMinLevel
                row.cl            = discovery.cl
                row.isVendor      = false
                row.tooltipText   = itemData.fullText or ""

                
                row.zoneNameStr   = GetLocalizedZoneName(discovery)
                row.sortQuality   = tonumber(discovery.q) or 1
                row.sortName      = itemName or ""
                row.sortClass     = characterClass or ""
                row.sortType      = itemSubTypeVal or ""
                row.sortSlot      = equipLocVal and _G[equipLocVal] or ""

                if Core and discovery.i and not Core:IsItemCached(discovery.i) then
                    Core:QueueItemForCaching(discovery.i)
                end

                if discovery.i then
                    Cache.duplicateItems[discovery.i] = (Cache.duplicateItems[discovery.i] or 0) + 1
                end
                
                itemSuccessfullyLoaded = true
            end
        else
            row.guid       = guid
            row.discovery  = discovery
            row.isVendor   = true
            row.vendorType = discovery.vendorType
            row.vendorName = discovery.vendorName
            row.isMystic   = false
            row.itemName   = discovery.vendorName 

            
            row.zoneNameStr   = GetLocalizedZoneName(discovery)
            row.sortQuality   = 7
            row.sortName      = discovery.vendorName or ""
            row.sortClass     = ""
            
            
            
            local vType = discovery.vendorType
            if not vType and discovery.g then
                if discovery.g:find("MS-", 1, true) then vType = "MS"
                else vType = "BM" end
            end
            row.sortType      = vType or "BM"
            
            row.sortSlot      = ""
            
            itemSuccessfullyLoaded = true
        end

        queueCursor = queueCursor + 1
        processedThisFrame = processedThisFrame + 1
        
        
        
        if itemSuccessfullyLoaded then
            outIndex = outIndex + 1
        end
        
        if debugprofilestop() - startMs >= budget then
            break
        end
    end
    
    self._cacheBuildIndex = outIndex
    self._cacheQueueCursor = queueCursor
    
    if queueCursor <= total then
        
        if self.window and self.window:IsShown() then
            self:UpdatePagination()
        end
        C_Timer.After(0.01, function() Viewer:ProcessCacheBuildChunk(budgetOverride) end)
    else
        
        for i = outIndex, #Cache.discoveries do
            Cache.discoveries[i] = nil
        end
        
        Cache.discoveriesBuilt = true
        Cache.discoveriesBuilding = false
        
        wipe(self._cacheBuildQueue)
        self._cacheQueueCursor = nil
        
        if self.scanProgressCallback then
            self.scanProgressCallback()
            self.scanProgressCallback = nil
        end
        
        if self.window and self.window:IsShown() then
            self:UpdatePagination()
            
            Cache.lastFilterState = nil 
            self:GetFilteredDiscoveries()
            self:UpdateRows()
        end
    end
end

function Viewer:ProcessScanQueueBatch()
    if not Cache.discoveriesBuilding then return end
    self:ProcessCacheBuildChunk()
end

function Viewer:GetFilteredDiscoveries()
    local pTime = L.ProfileStart and L:ProfileStart() 

    if Cache.discoveriesBuilding then 
        if pTime then L:ProfileStop("Viewer:GetFilteredDiscoveries", pTime) end
        return {} 
    end

    if not Cache.discoveriesBuilt then
        self:UpdateAllDiscoveriesCacheSync()
    end

    if not Cache.discoveriesBuilt then 
        if pTime then L:ProfileStop("Viewer:GetFilteredDiscoveries", pTime) end
        return {} 
    end

    local filterState = self:GetFilterStateHash()

    if Cache.lastFilterState == filterState and #Cache.filteredResults > 0 then
        if pTime then L:ProfileStop("Viewer:GetFilteredDiscoveries", pTime) end
        return Cache.filteredResults
    end

    local currentFiltered = self._reusableCurrentFiltered
    wipe(currentFiltered)
    
    local discoveriesToFilter = Cache.discoveries
    local totalToFilter     = #discoveriesToFilter
    
    local context = GetCascadedFilterContext(nil)
    local isVendorView = (self.currentFilter == "bmv")

    local filterPredicates = {
        mainFilter = function(data)
            local Constants = L:GetModule("Constants", true)
            if Constants and Constants.IsForbiddenZone and Constants:IsForbiddenZone(data.discovery.c, data.discovery.z, data.discovery.fp) then
                return false
            end
            
            if self.currentFilter == "eq" then
                return not data.isMystic and not data.isVendor
            elseif self.currentFilter == "ms" then
                return data.isMystic and not data.isVendor
            elseif self.currentFilter == "bmv" then
                return data.isVendor
            end
            return false
        end,

        searchFilter = function(data)
            data.matchedViaTooltip = false
            if self.searchTerm == "" then return true end

            local searchLower  = string.lower(self.searchTerm)
            local nameToSearch = data.isVendor and data.vendorName or data.itemName
            local nameMatch    = string.find(string.lower(nameToSearch or ""), searchLower, 1, true)

            local zoneName  = GetLocalizedZoneName(data.discovery)
            local zoneMatch = string.find(string.lower(zoneName), searchLower, 1, true)

            local tooltipMatch = false
            if Viewer.searchTooltipsEnabled and data.tooltipText then
                tooltipMatch = string.find(data.tooltipText, searchLower, 1, true) ~= nil
            end
            
            data.matchedViaTooltip = (not nameMatch and not zoneMatch and tooltipMatch)
            return nameMatch or zoneMatch or tooltipMatch
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
                            classValue = _G.LOCALIZED_CLASS_NAMES_MALE[classToken] or _G.LOCALIZED_CLASS_NAMES_FEMALE[classToken] or ""
                        end
                    end
                    if classValue == "" then classValue = data.characterClass or "" end
                    return self.columnFilters.ms.class[classValue] ~= nil
                end,
            },
            vendorType = function(data)
                if size(self.columnFilters.vendorType) == 0 then return true end
                local typeMap = { ["BM"] = "Blackmarket", ["MS"] = "Mystic Enchants" }
                local vType = data.vendorType or (data.discovery and data.discovery.vendorType)
                if not vType and data.discovery and data.discovery.g then
                    if data.discovery.g:find("BM-", 1, true) then vType = "BM"
                    elseif data.discovery.g:find("MS-", 1, true) then vType = "MS" end
                end
                local typeName = typeMap[vType] or vType or "Unknown"
                return self.columnFilters.vendorType[typeName] ~= nil
            end,
            zone = function(data)
                if size(self.columnFilters.zone) == 0 then return true end
                local zoneValue = GetLocalizedZoneName(data.discovery)
                return self.columnFilters.zone[zoneValue] ~= nil
            end,
            source = function(data)
                if isVendorView then return true end
                if size(self.columnFilters.source) == 0 then return true end
                local source     = data.discovery.src or "unknown"
                local sourceValue= SOURCE_NAMES[source] or source
                return self.columnFilters.source[sourceValue] ~= nil
            end,
            quality = function(data)
                if isVendorView then return true end
                if size(self.columnFilters.quality) == 0 then return true end
                local _, _, quality = GetItemInfoSafe(data.discovery.il, data.discovery.i)
                if not quality then
                    return self.columnFilters.quality["Unknown"] ~= nil
                end
                local qualityValue = QUALITY_NAMES[quality] or ("Quality " .. tostring(quality))
                return self.columnFilters.quality[qualityValue] ~= nil
            end,
            looted = function(data)
                if isVendorView then return true end
                if size(self.columnFilters.looted) == 0 then return true end
                local lootedValue = Viewer:IsLootedByChar(data.guid) and "Looted" or "Not Looted"
                return self.columnFilters.looted[lootedValue] ~= nil
            end,
            duplicates = function(data)
                if isVendorView then return true end
                if not self.columnFilters.duplicates then return true end
                return Cache.duplicateItems[data.discovery.i] and Cache.duplicateItems[data.discovery.i] > 1
            end,
        },
    }

    for i = 1, totalToFilter do
        local data = discoveriesToFilter[i]
        if data then
            local passed = true
            
            if not filterPredicates.mainFilter(data) then passed = false end
            if passed and not filterPredicates.searchFilter(data) then passed = false end

            if passed and not data.isVendor and not data.isMystic then
                if self.minReqLevel and (data.minLevel or 0) < self.minReqLevel then passed = false end
                if self.maxReqLevel and (data.minLevel or 0) > self.maxReqLevel then passed = false end
            end

            if passed and not data.isVendor then
                if not filterPredicates.columnFilters.source(data)   then passed = false end
                if passed and not filterPredicates.columnFilters.quality(data)  then passed = false end
                if passed and not filterPredicates.columnFilters.looted(data)   then passed = false end
            end
          
            if passed and self.currentFilter == "eq" then
                local filterGroup = filterPredicates.columnFilters[self.currentFilter]
                if filterGroup then
                    if not filterGroup.slot(data) then passed = false end
                    if passed and not filterGroup.type(data) then passed = false end
                end
            elseif passed and self.currentFilter == "ms" then
                if not filterPredicates.columnFilters.ms.class(data) then passed = false end
            elseif passed and self.currentFilter == "bmv" then
                if not filterPredicates.columnFilters.vendorType(data) then passed = false end
            end
      
            if passed and context.activeFilters.class then
                if context.currentFilter == "eq" then
                    local Constants = L:GetModule("Constants", true)
                    if Constants and Constants.CLASS_PROFICIENCIES then
                        local subTypeID = data.ist
                        local typeID = data.it
                        if subTypeID and typeID and subTypeID > 0 and typeID > 0 then
                            local canUse = false
                            for classFilterName, _ in pairs(context.activeFilters.class) do
                                 local classToken = nil
                                 if Constants and Constants.GetClassTokenFromLocalizedName then
                                     local foundToken = Constants:GetClassTokenFromLocalizedName(classFilterName)
                                     if foundToken ~= classFilterName then classToken = foundToken end
                                 end
                                 if not classToken and _G.LOCALIZED_CLASS_NAMES_MALE then
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
                            if not canUse then passed = false end
                        else
                            passed = false
                        end
                    end
                end
            end

            if passed and not filterPredicates.columnFilters.zone(data) then passed = false end

            if passed and Viewer.lootedFilterState ~= nil and not isVendorView then
                local isLooted = Viewer:IsLootedByChar(data.guid)
                if Viewer.lootedFilterState == true and not isLooted then passed = false end
                if Viewer.lootedFilterState == false and isLooted then passed = false end
            end

            if passed and Viewer.favoritesFilterState == true and not isVendorView then
                if not (data.discovery.i and L.db.profile.favorites[data.discovery.i]) then passed = false end
            end

            if passed and Viewer.collectedMEFilterState ~= nil and not isVendorView then
                local Constants = L:GetModule("Constants", true)
                local isME = Constants and data.discovery.dt == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL
                if isME and data.discovery.i and data.discovery.i > 0 then
                    local isCollectedME = L:IsMysticEnchantCollected(data.discovery.i)
                    if Viewer.collectedMEFilterState == true and not isCollectedME then passed = false end
                    if Viewer.collectedMEFilterState == false and isCollectedME then passed = false end
                elseif not isME then
                    if Viewer.collectedMEFilterState == true then passed = false end
                end
            end

            if passed and not filterPredicates.columnFilters.duplicates(data) then passed = false end

            if passed then
                table.insert(currentFiltered, data)
            end
        end
    end

    table.sort(currentFiltered, function(a, b)
        if not a or not b then return false end
        if not a.discovery or not b.discovery then return false end

        if self.lastSeenSortState == "new" then
            local la = tonumber(a.discovery.ls) or 0
            local lb = tonumber(b.discovery.ls) or 0
            if la ~= lb then return la > lb end
        elseif self.lastSeenSortState == "old" then
            local la = tonumber(a.discovery.ls) or 0
            local lb = tonumber(b.discovery.ls) or 0
            if la ~= lb then return la < lb end
        end

        local a_val, b_val
        if self.sortColumn == "name" or self.sortColumn == "vendorName" then
            a_val = a.sortName; b_val = b.sortName
        elseif self.sortColumn == "zone" then
            a_val = a.zoneNameStr; b_val = b.zoneNameStr
        elseif self.sortColumn == "slot" then
            a_val = a.sortSlot; b_val = b.sortSlot
        elseif self.sortColumn == "type" then
            a_val = a.sortType; b_val = b.sortType
        elseif self.sortColumn == "class" then
            a_val = a.sortClass; b_val = b.sortClass
        elseif self.sortColumn == "foundBy" then
            a_val = a.discovery.fp or ""; b_val = b.discovery.fp or ""
        elseif self.sortColumn == "favorite" then
            local a_fav = (a.discovery and a.discovery.i and L.db.profile.favorites[a.discovery.i]) and 1 or 0
            local b_fav = (b.discovery and b.discovery.i and L.db.profile.favorites[b.discovery.i]) and 1 or 0
            if a_fav == b_fav then
                if self.sortAscending then return a.sortName < b.sortName else return a.sortName > b.sortName end
            end
            a_val = a_fav; b_val = b_fav
        elseif self.sortColumn == "level" then
            a_val = a.minLevel or 0; b_val = b.minLevel or 0
        else
            a_val = a.guid or ""; b_val = b.guid or ""
        end

        if self.sortAscending then return a_val < b_val else return a_val > b_val end
    end)

    local finalFiltered = self._reusableFinalFiltered
    wipe(finalFiltered)
    
    for _, data in ipairs(currentFiltered) do
        table.insert(finalFiltered, data)
        if self.inlineVendorView and Viewer.expandedVendors and Viewer.expandedVendors[data.guid] and data.discovery and data.discovery.vendorItems then
            for _, item in ipairs(data.discovery.vendorItems) do
                table.insert(finalFiltered, {
                    isVendorItemRow = true,
                    item = item,
                    parentVendor = data,
                })
            end
        end
    end
    
    Cache.filteredResults = finalFiltered
    Cache.lastFilterState = filterState

    if pTime then L:ProfileStop("Viewer:GetFilteredDiscoveries", pTime) end 
    return Cache.filteredResults
end

function Viewer:GetFilterStateHash()
    local hashParts = {
        self.currentFilter,
        self.searchTerm,
        self.sortColumn,
        tostring(self.sortAscending),
        tostring(self.minReqLevel),
        tostring(self.maxReqLevel),
        tostring(self.lastSeenSortState or "off")
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
    if self.collectedMEFilterState ~= nil then
        _tinsert(filterEntries, "collectedME:" .. tostring(self.collectedMEFilterState))
    end
    if self.favoritesFilterState == true then
        _tinsert(filterEntries, "favorites:true")
    end

    local hash = _tconcat(hashParts, "|")
    if size(filterEntries) > 0 then
        hash = concatStrings(hash, "|", _tconcat(filterEntries, "|"))
    end

    return hash
end

function Viewer:GetMainScrollHeight()
    if not self.window then return 450 end
    local base = self.window:GetHeight() - 200
    if self.currentFilter == "bmv" and not self.inlineVendorView then
        return base * (self.splitRatio or 0.64)
    end
    return base
end

function Viewer:UpdateLayout()
    if not self.window then return end
    local width = self.window:GetWidth()
    local height = self.window:GetHeight()
    local mainHeight = self:GetMainScrollHeight()
    
    if self.scrollFrame then 
        self.scrollFrame:SetSize(width - 60, mainHeight) 
    end
    
    if self.currentFilter == "bmv" and not self.inlineVendorView then
        self:EnsureVendorInventoryPanel()
        if self.vendorInventoryFrame then
            local invHeight = (height - 200) * (1 - self.splitRatio) - 10
            self.vendorInventoryFrame:SetSize(width - 60, invHeight)
            self.vendorInventoryFrame:Show()
            self:UpdateVendorInventoryScroll()
        end
        
        if self.splitterBar then
            self.splitterBar:SetWidth(width - 60)
            self.splitterBar:ClearAllPoints()
            
            self.splitterBar:SetPoint("TOPLEFT", self.scrollFrame, "BOTTOMLEFT", 0, 4)
            self.splitterBar:Show()
        end
    else
        if self.vendorInventoryFrame then
            self.vendorInventoryFrame:Hide()
        end
        if self.splitterBar then
            self.splitterBar:Hide()
        end
    end
end

function Viewer:GetEffectiveItemsPerPage()
    local visibleRows = 0
    if self.window then
        visibleRows = math.ceil(self:GetMainScrollHeight() / ROW_HEIGHT)
    end
    return math.max(self.itemsPerPage, visibleRows)
end

function Viewer:GetPaginatedDiscoveries()
    local allDiscoveries = self:GetFilteredDiscoveries()
    self.totalItems = #allDiscoveries

    local effectiveItemsPerPage = self:GetEffectiveItemsPerPage()
    local startIndex = (self.currentPage - 1) * effectiveItemsPerPage + 1
    local endIndex = math.min(startIndex + effectiveItemsPerPage - 1, self.totalItems)

    local pageDiscoveries = {}
    
    pageDiscoveries[math.min(effectiveItemsPerPage, self.totalItems)] = nil

    for i = startIndex, endIndex do
        if allDiscoveries[i] then
            _tinsert(pageDiscoveries, allDiscoveries[i])
        end
    end

    return pageDiscoveries
end

function Viewer:GetTotalPages()
    return math.max(1, math.ceil(self.totalItems / self:GetEffectiveItemsPerPage()))
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
    if self.searchTerm and self.searchTerm ~= "" then return true end
    if self.minReqLevel or self.maxReqLevel then return true end
    if size(self.columnFilters.zone) > 0 then return true end
 
    if self.columnFilters.eq and (size(self.columnFilters.eq.slot) > 0 or size(self.columnFilters.eq.type) > 0 or size(self.columnFilters.eq.class) > 0) then
        return true
    end

    if self.columnFilters.ms and size(self.columnFilters.ms.class) > 0 then
        return true
    end

    if size(self.columnFilters.source) > 0 then return true end
    if size(self.columnFilters.quality) > 0 then return true end
    if size(self.columnFilters.vendorType) > 0 then return true end
    if self.lootedFilterState ~= nil or size(self.columnFilters.looted) > 0 then return true end
    if self.collectedMEFilterState ~= nil then return true end
    if self.columnFilters.duplicates then return true end
    
    if self.lastSeenSortState and self.lastSeenSortState ~= "off" then return true end
    if self.favoritesFilterState == true then return true end

    return false
end

function Viewer:UpdateClearAllButton()
    if not self.clearAllBtn or not self.actionsLabel then return end

    if self:HasActiveFilters() then
        self.clearAllBtn:Show()
        self.clearAllBtn:SetText("Clear")
    else
        self.clearAllBtn:Hide()
        self.actionsLabel:Show()
    end
end

function Viewer:UpdateFilterButtonStates()
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not self.sourceFilterBtn or not self.qualityFilterBtn or not self.lootedFilterBtn then
        if pTime then L:ProfileStop("Viewer:UpdateFilterButtonStates", pTime) end
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
    else
        setButtonTextColor(self.sourceFilterBtn, 1, 1, 1) 
    end
    self.sourceFilterBtn:SetText("Source")

    local qualityActive = size(self.columnFilters.quality) > 0
    if qualityActive then
        setButtonTextColor(self.qualityFilterBtn, 1, 0.8, 0.2) 
    else
        setButtonTextColor(self.qualityFilterBtn, 1, 1, 1) 
    end
    self.qualityFilterBtn:SetText("Quality")

    if self.vendorTypeFilterBtn then
        local typeActive = size(self.columnFilters.vendorType) > 0
        if typeActive then
            setButtonTextColor(self.vendorTypeFilterBtn, 1, 0.8, 0.2)
        else
            setButtonTextColor(self.vendorTypeFilterBtn, 1, 1, 1)
        end
        self.vendorTypeFilterBtn:SetText("Type")
    end

    if self.favoritesFilterBtn then
        if self.favoritesFilterState == true then
            setButtonTextColor(self.favoritesFilterBtn, 1, 0.8, 0.2) 
        else
            setButtonTextColor(self.favoritesFilterBtn, 1, 1, 1) 
        end
        self.favoritesFilterBtn:SetText("Favorites")
        self.favoritesFilterBtn:Enable()
        self.favoritesFilterBtn:SetAlpha(1.0)
    end

    if self.lootedFilterState == true then
        setButtonTextColor(self.lootedFilterBtn, 1, 0.8, 0.2) 
        self.lootedFilterBtn:SetText("Looted: Yes")
    elseif self.lootedFilterState == false then
        setButtonTextColor(self.lootedFilterBtn, 1, 0.8, 0.2) 
        self.lootedFilterBtn:SetText("Looted: No")
    elseif size(self.columnFilters.looted) > 0 then
        setButtonTextColor(self.lootedFilterBtn, 1, 0.8, 0.2) 
        self.lootedFilterBtn:SetText("Looted [F]")
    else
        setButtonTextColor(self.lootedFilterBtn, 1, 1, 1) 
        self.lootedFilterBtn:SetText("Looted: All")
    end
    
    if self.slotsFilterBtn then
        local slotFilters = self.columnFilters[self.currentFilter] and self.columnFilters[self.currentFilter].slot
        local slotsActive = slotFilters and size(slotFilters) > 0
        if slotsActive then
            setButtonTextColor(self.slotsFilterBtn, 1, 0.8, 0.2)
        else
            setButtonTextColor(self.slotsFilterBtn, 1, 1, 1)
        end
        self.slotsFilterBtn:SetText("Slots")
    end
    
    if self.usableByFilterBtn then
        local classActive = false
        if self.currentFilter == "eq" then
            classActive = self.columnFilters[self.currentFilter] and size(self.columnFilters[self.currentFilter].class) > 0
        elseif self.currentFilter == "ms" then
            classActive = size(self.columnFilters.ms.class) > 0
        end
        
        if classActive then
            setButtonTextColor(self.usableByFilterBtn, 1, 0.8, 0.2)
        else
            setButtonTextColor(self.usableByFilterBtn, 1, 1, 1)
        end
        self.usableByFilterBtn:SetText("Usable By")
    end

    if self.collectedMEFilterBtn then
        if self.collectedMEFilterState == true then
            setButtonTextColor(self.collectedMEFilterBtn, 1, 0.8, 0.2)
            self.collectedMEFilterBtn:SetText("Collected: Yes")
        elseif self.collectedMEFilterState == false then
            setButtonTextColor(self.collectedMEFilterBtn, 1, 0.8, 0.2)
            self.collectedMEFilterBtn:SetText("Collected: No")
        else
            setButtonTextColor(self.collectedMEFilterBtn, 1, 1, 1)
            self.collectedMEFilterBtn:SetText("Collected: All")
        end
    end

    if self.lsFilterBtn then
        if self.lastSeenSortState == "new" then
            setButtonTextColor(self.lsFilterBtn, 1, 0.8, 0.2)
            self.lsFilterBtn:SetText("Date: New")
        elseif self.lastSeenSortState == "old" then
            setButtonTextColor(self.lsFilterBtn, 1, 0.8, 0.2)
            self.lsFilterBtn:SetText("Date: Old")
        else
            setButtonTextColor(self.lsFilterBtn, 1, 1, 1)
            self.lsFilterBtn:SetText("Date: Off")
        end
    end

    if self.duplicatesFilterBtn then
        local duplicatesActive = self.columnFilters.duplicates
        if duplicatesActive then
            setButtonTextColor(self.duplicatesFilterBtn, 1, 0.8, 0.2) 
        else
            setButtonTextColor(self.duplicatesFilterBtn, 1, 1, 1) 
        end
        self.duplicatesFilterBtn:SetText("Duplicates")
    end

    local isBmv = (self.currentFilter == "bmv")
    local isEq = (self.currentFilter == "eq")
    local isMs = (self.currentFilter == "ms")

    local showSlots = isEq
    local showVendorType = isBmv
    local showNormalFilters = not isBmv
    
    local Dev = L:GetModule("DevCommands", true)
    local showDuplicates = showNormalFilters and (Dev ~= nil)

    if self.vendorTypeFilterBtn then self.vendorTypeFilterBtn:SetShown(showVendorType) end
    if self.sourceFilterBtn then self.sourceFilterBtn:SetShown(showNormalFilters) end
    if self.qualityFilterBtn then self.qualityFilterBtn:SetShown(showNormalFilters) end
    if self.favoritesFilterBtn then self.favoritesFilterBtn:SetShown(showNormalFilters) end
    if self.slotsFilterBtn then self.slotsFilterBtn:SetShown(showSlots) end
    if self.usableByFilterBtn then self.usableByFilterBtn:SetShown(showNormalFilters) end
    if self.lootedFilterBtn then self.lootedFilterBtn:SetShown(showNormalFilters) end
    if self.collectedMEFilterBtn then self.collectedMEFilterBtn:SetShown(showNormalFilters) end
    if self.lsFilterBtn then self.lsFilterBtn:SetShown(showNormalFilters) end
    if self.duplicatesFilterBtn then self.duplicatesFilterBtn:SetShown(showDuplicates) end

    local lastBtn = self.filtersLabel
    if lastBtn then
        local activeBtns = {
            self.sourceFilterBtn,
            self.qualityFilterBtn,
            self.vendorTypeFilterBtn,
            self.slotsFilterBtn,
            self.usableByFilterBtn,
            self.favoritesFilterBtn,
            self.lootedFilterBtn,
            self.collectedMEFilterBtn,
            self.lsFilterBtn,          
            self.duplicatesFilterBtn   
        }

        for _, btn in ipairs(activeBtns) do
            if btn and btn:IsShown() then
                btn:ClearAllPoints()
                local spacing = (lastBtn == self.filtersLabel) and 5 or 3
                btn:SetPoint("LEFT", lastBtn, "RIGHT", spacing, 0)
                lastBtn = btn
            end
        end
    end
    
    if pTime then L:ProfileStop("Viewer:UpdateFilterButtonStates", pTime) end 
end

function Viewer:UpdateRefreshButton()
    if not self.refreshDataBtn then return end
    
    local count = self.pendingUpdatesCount or 0
    local btn = self.refreshDataBtn
    if count > 0 then
        
        if btn.label then
            btn.label:SetText("|cff00ff00Refresh (New)|r")
        end
        btn:Enable()
        if btn.bgInner then btn.bgInner:SetVertexColor(0.05, 0.22, 0.10, 1) end
    else
        
        if btn.label then
            btn.label:SetText("|cff44aaffRefresh|r")
        end
        btn:Disable()
        if btn.bgInner then btn.bgInner:SetVertexColor(0.06, 0.06, 0.10, 0.90) end
    end
end

function Viewer:UpdateReloadHint()
    if self.hasUncachedData then
        if self.reloadBtn then self.reloadBtn:Show() end
        if self.reloadText then self.reloadText:Show() end
    else
        if self.reloadBtn then self.reloadBtn:Hide() end
        if self.reloadText then self.reloadText:Hide() end
    end
end

function Viewer:CreateWindow()
    local pTime = L.ProfileStart and L:ProfileStart() 
    if not db then return end
    if self.window then return end
    
    local rowFont = _G[ROW_FONT_NAME] or CreateFont(ROW_FONT_NAME)
    rowFont:SetFont(ROW_FONT_PATH, ROW_FONT_SIZE, "")

    local uiFont = _G[UI_FONT_NAME] or CreateFont(UI_FONT_NAME)
    uiFont:SetFont(UI_FONT_PATH, UI_FONT_SIZE, "")

    local db = L.db.profile.viewer

    local window = CreateFrame("Frame", "LootCollectorViewerWindow", UIParent)
    
    window:SetSize(db.width or WINDOW_WIDTH, db.height or WINDOW_HEIGHT)
    window:SetMinResize(WINDOW_WIDTH, 400)
    window:SetMaxResize(1600, 1000) 
    window:SetScale(db.scale or 1.0)
    
    if db.point then
        window:ClearAllPoints()
        window:SetPoint(db.point, UIParent, db.point, db.x or 0, db.y or 0)
    else
        window:SetPoint("CENTER")
    end
    
    window:SetFrameStrata(FRAME_STRATA)
    window:SetFrameLevel(FRAME_LEVEL)
    window:SetMovable(true)
    window:SetResizable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()

    local point, _, _, x, y = self:GetPoint()
    L.db.profile.viewer.point = point
    L.db.profile.viewer.x = x
    L.db.profile.viewer.y = y

    if Viewer and Viewer.window == self then
        Viewer:UpdateLayout()

        local visibleRows = math.ceil(Viewer:GetMainScrollHeight() / ROW_HEIGHT)
        Viewer:CreateRows(visibleRows)

        Viewer:UpdateSortHeaders()
        Viewer:UpdateRows()
    end
end)
    window:SetScript("OnMouseDown", function(self)
        CloseDropDownMenus()
    end)
    window:SetToplevel(true)
    window:Hide()

    
    window.bg = window:CreateTexture(nil, "BACKGROUND")
    window.bg:SetAllPoints(true)
    window.bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    window.bg:SetVertexColor(0.05, 0.05, 0.08, 0.85)

    
    window.border = CreateFrame("Frame", nil, window, "BackdropTemplate")
    window.border:SetAllPoints(true)
    window.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    window.border:SetBackdropBorderColor(0.2, 0.3, 0.5, 0.6)

    
    local resizeGrip = CreateFrame("Button", nil, window)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -1, 1)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetScript("OnMouseDown", function()
        local point = window:GetPoint()
        if point ~= "TOPLEFT" then
            local left = window:GetLeft()
            local top = window:GetTop()
            window:ClearAllPoints()
            window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        window:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        window:StopMovingOrSizing()
        
        L.db.profile.viewer.width = window:GetWidth()
        L.db.profile.viewer.height = window:GetHeight()
    end)

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
        if Viewer.inMapOperation and not Viewer.allowManualClose then return end
        originalHide(self)
    end
    originalHide(window)

    window:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 16,
        edgeSize = 1,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    window:SetBackdropColor(0.05, 0.05, 0.08, 0.70)
    window:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)

    
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -5)
    title:SetText("|TInterface\\AddOns\\LootCollector\\media\\MinimapIcon:28:28|t Discoveries")
    title:SetTextColor(0.85, 0.85, 1.0, 1)

    
    local titleSep = window:CreateTexture(nil, "ARTWORK")
    titleSep:SetHeight(1)
    titleSep:SetPoint("TOPLEFT", window, "TOPLEFT", 8, -38)
    titleSep:SetPoint("TOPRIGHT", window, "TOPRIGHT", -8, -38)
    titleSep:SetTexture("Interface\\Buttons\\WHITE8X8")
    titleSep:SetVertexColor(0.28, 0.28, 0.35, 0.8)
    
    local versionText = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    versionText:SetPoint("TOPLEFT", 15, -18)    
    versionText:SetTextColor(0.90, 0.20, 0.90, 0.8)
    versionText:SetText(string.format("LootCollector %s", L.Version or "Unknown"))

    local function SkinButton(btn)
        if not btn then return end
        btn:SetNormalTexture("")
        btn:SetPushedTexture("")
        btn:SetHighlightTexture("")
        btn:SetBackdrop(nil)
        
        local fs = btn:GetFontString()
        if not fs then
            fs = btn:CreateFontString(nil, "OVERLAY")
            btn:SetFontString(fs)
        end
        fs:SetFontObject(UI_FONT_NAME)
        fs:SetTextColor(0.85, 0.85, 1.0)
        fs:SetPoint("CENTER", 0, 0)
        
        btn:HookScript("OnEnter", function(self) self:GetFontString():SetTextColor(1, 1, 1) end)
        btn:HookScript("OnLeave", function(self) self:GetFontString():SetTextColor(0.85, 0.85, 1.0) end)
    end

    local closeBtn = CreateFrame("Button", nil, window)
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetSize(22, 22)
    SkinButton(closeBtn)
    closeBtn:SetText("X")
    closeBtn:SetScript("OnClick", function()
        Viewer.allowManualClose = true
        window:Hide()
    end)
    closeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Close")
        GameTooltip:Show()
        self:SetBackdropBorderColor(1, 1, 1, 1)
    end)
    closeBtn:SetScript("OnLeave", function(self) GameTooltip:Hide() self:SetBackdropBorderColor(1, 1, 1, 0.5) end)
    
    local scaleUp = CreateFrame("Button", nil, window)
    scaleUp:SetSize(22, 22)
    scaleUp:SetPoint("RIGHT", closeBtn, "LEFT", -5, 0)
    SkinButton(scaleUp)
    scaleUp:SetText("+")
    scaleUp:SetScript("OnClick", function() 
        local newScale = math.min(window:GetScale() + 0.1, 2.0)
        window:SetScale(newScale) 
        L.db.profile.viewer.scale = newScale 
    end)
    scaleUp:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Increase Scale")
        GameTooltip:Show()
        self:SetBackdropBorderColor(1, 1, 1, 1)
    end)
    scaleUp:SetScript("OnLeave", function(self) GameTooltip:Hide() self:SetBackdropBorderColor(1, 1, 1, 0.5) end)
    
    local scaleDown = CreateFrame("Button", nil, window)
    scaleDown:SetSize(22, 22)
    scaleDown:SetPoint("RIGHT", scaleUp, "LEFT", -5, 0)
    SkinButton(scaleDown)
    scaleDown:SetText("-")
    scaleDown:SetScript("OnClick", function() 
        local newScale = math.max(window:GetScale() - 0.1, 0.5)
        window:SetScale(newScale) 
        L.db.profile.viewer.scale = newScale 
    end)
    scaleDown:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Decrease Scale")
        GameTooltip:Show()
        self:SetBackdropBorderColor(1, 1, 1, 1)
    end)
    scaleDown:SetScript("OnLeave", function(self) GameTooltip:Hide() self:SetBackdropBorderColor(1, 1, 1, 0.5) end)
    
    window.SkinScrollBar = function(self, scrollFrame)
        local name = scrollFrame:GetName()
        if not name then return end
        local scrollbar = _G[name.."ScrollBar"]
        if not scrollbar then return end
        
        local up = _G[name.."ScrollBarScrollUpButton"]
        local down = _G[name.."ScrollBarScrollDownButton"]
        if up then up:Hide() up:SetScale(0.0001) end
        if down then down:Hide() down:SetScale(0.0001) end
        
        local thumb = scrollbar:GetThumbTexture()
        if thumb then
            thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
            thumb:SetVertexColor(1, 1, 1, 0.5)
            thumb:SetWidth(8)
        end
        
        scrollbar:SetWidth(10)
    end
     
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

    
    local function CreateTabBtn(parent, label, anchorFrame, anchorPoint, tooltipText)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
        if anchorFrame then
            btn:SetPoint("LEFT", anchorFrame, anchorPoint or "RIGHT", 8, 0)
        end
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints(true)
        btn.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        btn.bg:SetVertexColor(0.10, 0.10, 0.16, 0.85)
        btn.accent = btn:CreateTexture(nil, "BORDER")
        btn.accent:SetHeight(2)
        btn.accent:SetPoint("BOTTOMLEFT", 0, 0)
        btn.accent:SetPoint("BOTTOMRIGHT", 0, 0)
        btn.accent:SetTexture("Interface\\Buttons\\WHITE8X8")
        btn.accent:SetVertexColor(0.30, 0.30, 0.40, 0.80)
        btn.bgInner = btn:CreateTexture(nil, "ARTWORK")
        btn.bgInner:SetPoint("TOPLEFT", 1, -1)
        btn.bgInner:SetPoint("BOTTOMRIGHT", -1, 2)
        btn.bgInner:SetTexture("Interface\\Buttons\\WHITE8X8")
        btn.bgInner:SetVertexColor(0.06, 0.06, 0.10, 0.90)
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 1, -1)
        hl:SetPoint("BOTTOMRIGHT", -1, 2)
        hl:SetTexture("Interface\\Buttons\\WHITE8X8")
        hl:SetVertexColor(1, 1, 1, 0.1)
        btn:SetHighlightTexture(hl)
        btn.label = btn:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
        btn.label:SetAllPoints(true)
        btn.label:SetText(label)
        btn.label:SetTextColor(0.75, 0.75, 0.80, 1)
        btn.label:SetJustifyH("CENTER")
        btn:SetScript("OnEnter", function(self)
            if not self._isActive then
                self.bgInner:SetVertexColor(0.14, 0.14, 0.22, 0.95)
                self.label:SetTextColor(1, 1, 1, 1)
            end
            if tooltipText then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText(tooltipText, 1, 1, 1)
                GameTooltip:Show()
                GameTooltip:SetFrameStrata("TOOLTIP")
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if not self._isActive then
                self.bgInner:SetVertexColor(0.06, 0.06, 0.10, 0.90)
                self.label:SetTextColor(0.75, 0.75, 0.80, 1)
            end
            GameTooltip:Hide()
        end)
        btn._isActive = false
        btn.SetActive = function(self, active)
            self._isActive = active
            if active then
                self.bgInner:SetVertexColor(0.12, 0.22, 0.38, 1)
                self.accent:SetVertexColor(0.30, 0.65, 1.0, 1)
                self.label:SetTextColor(0.30, 0.75, 1.0, 1)
            else
                self.bgInner:SetVertexColor(0.06, 0.06, 0.10, 0.90)
                self.accent:SetVertexColor(0.30, 0.30, 0.40, 0.80)
                self.label:SetTextColor(0.75, 0.75, 0.80, 1)
            end
        end
        return btn
    end

    local Core = L:GetModule("Core", true)
    local isCoA = Core and Core.IsConfirmedCoARealm and Core:IsConfirmedCoARealm()

    local equipmentBtn = CreateTabBtn(window, "Worldforged", nil, nil, nil)
    equipmentBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Worldforged items found around the world by other players.", 1, 0.82, 0)
        GameTooltip:Show()
        GameTooltip:SetFrameStrata("TOOLTIP")
    end)
    equipmentBtn:SetPoint("TOPLEFT", 20, -47)
    equipmentBtn:SetScript("OnClick", function()
        self.currentFilter = "eq"
        self.currentPage   = 1
        
        self.sortColumn    = "name"
        self.sortAscending = true
        
        self:SetSelectedRow(nil)
        if self.vendorInventoryFrame then
            self.vendorInventoryFrame:Hide()
            self.selectedVendorGuid = nil
        end
        self:UpdateFilterButtons()
        self:UpdateSortHeaders()
        self:RefreshData()
    end)

    local mysticBtn = CreateTabBtn(window, "Mystic Scrolls", equipmentBtn, "RIGHT", nil)
    mysticBtn:HookScript("OnEnter", function(self)
        if not isCoA then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Mystic Scrolls found around the world by other players.", 1, 0.82, 0)
            GameTooltip:Show()
            GameTooltip:SetFrameStrata("TOOLTIP")
        end
    end)
    mysticBtn:HookScript("OnLeave", GameTooltip_Hide)
    mysticBtn:SetScript("OnClick", function()
        self.currentFilter = "ms"
        self.currentPage   = 1
        
        self.sortColumn    = "name"
        self.sortAscending = true
        
        self:SetSelectedRow(nil)
        if self.vendorInventoryFrame then
            self.vendorInventoryFrame:Hide()
            self.selectedVendorGuid = nil
        end
        self:UpdateFilterButtons()
        self:UpdateSortHeaders()
        self:RefreshData()
    end)

    local bmvBtn
    if isCoA then
        mysticBtn:Hide()
        
        bmvBtn = CreateTabBtn(window, "Vendors", equipmentBtn, "RIGHT", nil)
    else
        bmvBtn = CreateTabBtn(window, "Vendors", mysticBtn, "RIGHT", nil)
    end
    
    bmvBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("NPCs around the world selling Mystic Enchants, Recipes and Special items.", 1, 0.82, 0)
    end)
    bmvBtn:HookScript("OnLeave", GameTooltip_Hide)
    bmvBtn:SetScript("OnClick", function()
        self.currentFilter = "bmv"
        self.currentPage   = 1
        
        self.sortColumn    = "vendorType"
        self.sortAscending = true
        
        self:SetSelectedRow(nil)
        if self.vendorInventoryFrame then
            self.vendorInventoryFrame:Hide()
            self.selectedVendorGuid = nil
        end
        self:UpdateFilterButtons()
        self:UpdateSortHeaders()
        self:RefreshData()
    end)

    if isCoA then
        mysticBtn:Disable()
        local function showCoADisabledTooltip(selfButton)
            GameTooltip:SetOwner(selfButton, "ANCHOR_TOP")
            GameTooltip:SetText("Feature Disabled", 1, 0.82, 0)
            GameTooltip:AddLine("Mystic Scrolls do not exist on Conquest of Azeroth realms.", 1, 1, 1, true)
            GameTooltip:Show()
            GameTooltip:SetFrameStrata("TOOLTIP") 
        end
        mysticBtn:SetScript("OnEnter", showCoADisabledTooltip)
        mysticBtn:SetScript("OnLeave", GameTooltip_Hide)
    end

    local refreshDataBtn = CreateFrame("Button", nil, window)
    refreshDataBtn:SetSize(60, BUTTON_HEIGHT)
    refreshDataBtn:SetPoint("TOPRIGHT", window, "TOPRIGHT", -25, -70)
    
    refreshDataBtn.bg = refreshDataBtn:CreateTexture(nil, "BACKGROUND")
    refreshDataBtn.bg:SetAllPoints(true)
    refreshDataBtn.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    refreshDataBtn.bg:SetVertexColor(0.12, 0.12, 0.16, 0.85)

    refreshDataBtn.bgInner = refreshDataBtn:CreateTexture(nil, "ARTWORK")
    refreshDataBtn.bgInner:SetPoint("TOPLEFT", 1, -1)
    refreshDataBtn.bgInner:SetPoint("BOTTOMRIGHT", -1, 1)
    refreshDataBtn.bgInner:SetTexture("Interface\\Buttons\\WHITE8X8")
    refreshDataBtn.bgInner:SetVertexColor(0.20, 0.20, 0.26, 0.90)

    refreshDataBtn.label = refreshDataBtn:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
    refreshDataBtn.label:SetAllPoints(true)
    refreshDataBtn.label:SetText("Refresh")
    refreshDataBtn.label:SetJustifyH("CENTER")
    
    refreshDataBtn:SetScript("OnEnter", function(self) self.bgInner:SetVertexColor(0.25, 0.35, 0.50, 1) end)
    refreshDataBtn:SetScript("OnLeave", function(self) self.bgInner:SetVertexColor(0.20, 0.20, 0.26, 0.90) end)
    refreshDataBtn:SetScript("OnMouseDown", function(self) self.label:SetPoint("TOPLEFT", 1, -2) end)
    refreshDataBtn:SetScript("OnMouseUp", function(self) self.label:SetPoint("TOPLEFT", 0, 0) end)
    refreshDataBtn:SetScript("OnClick", function()
        Viewer.pendingUpdatesCount = 0
        Viewer:UpdateRefreshButton()
        Cache.discoveriesBuilt = false
        Viewer:RefreshData()
    end)
    
    local searchLabel = window:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
    searchLabel:SetPoint("TOPLEFT", equipmentBtn, "BOTTOMLEFT", 0, -10)
    searchLabel:SetText("Search: ")

    local searchBox = CreateFrame("EditBox", nil, window)
    searchBox:SetSize(180, 18)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 5, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject(UI_FONT_NAME)
    searchBox:SetTextColor(1, 1, 1, 1)
    
    local sbBg = searchBox:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints(true)
    sbBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    sbBg:SetVertexColor(0.08, 0.08, 0.14, 0.90)
    local sbBorder = searchBox:CreateTexture(nil, "BORDER")
    sbBorder:SetPoint("TOPLEFT", -1, 1)
    sbBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    sbBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    sbBorder:SetVertexColor(0.30, 0.30, 0.40, 0.80)

    local clearBtn = CreateFrame("Button", nil, searchBox)
    clearBtn:SetSize(24, 24)
    clearBtn:SetPoint("RIGHT", searchBox, "RIGHT", -1, 0)
    clearBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    clearBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    clearBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    clearBtn:SetScript("OnClick", function()
        if Viewer.searchTypingTimer then C_Timer.CancelTimer(Viewer.searchTypingTimer) end
        searchBox:SetText("")
        searchBox:ClearFocus()
        Viewer.searchTerm = ""
        Viewer.currentPage = 1
        Viewer:RefreshData()
        Viewer:UpdateClearAllButton()
        clearBtn:Hide()
    end)
    clearBtn:Hide() 
    
    local reqLevelLabel = window:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
    reqLevelLabel:SetPoint("LEFT", searchBox, "RIGHT", 15, 0)
    reqLevelLabel:SetText("|cffaaaaaa Req Lvl:|r")

    local minReqLevelBox = CreateFrame("EditBox", nil, window)
    minReqLevelBox:SetSize(32, 16)
    minReqLevelBox:SetPoint("LEFT", reqLevelLabel, "RIGHT", 4, 0)
    minReqLevelBox:SetAutoFocus(false)
    minReqLevelBox:SetNumeric(true)
    minReqLevelBox:SetMaxLetters(3)
    minReqLevelBox:SetFontObject(UI_FONT_NAME)
    minReqLevelBox:SetTextColor(1, 1, 1, 1)
    minReqLevelBox:SetJustifyH("CENTER")
    
    local minBg = minReqLevelBox:CreateTexture(nil, "BACKGROUND")
    minBg:SetAllPoints(true)
    minBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    minBg:SetVertexColor(0.08, 0.08, 0.14, 0.90)
    local minBorder = minReqLevelBox:CreateTexture(nil, "BORDER")
    minBorder:SetPoint("TOPLEFT", -1, 1)
    minBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    minBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    minBorder:SetVertexColor(0.30, 0.30, 0.40, 0.80)

    local dashLabel = window:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
    dashLabel:SetPoint("LEFT", minReqLevelBox, "RIGHT", 3, 0)
    dashLabel:SetText("-")

    local maxReqLevelBox = CreateFrame("EditBox", nil, window)
    maxReqLevelBox:SetSize(32, 16)
    maxReqLevelBox:SetPoint("LEFT", dashLabel, "RIGHT", 3, 0)
    maxReqLevelBox:SetAutoFocus(false)
    maxReqLevelBox:SetNumeric(true)
    maxReqLevelBox:SetMaxLetters(3)
    maxReqLevelBox:SetFontObject(UI_FONT_NAME)
    maxReqLevelBox:SetTextColor(1, 1, 1, 1)
    maxReqLevelBox:SetJustifyH("CENTER")
    
    local maxBg = maxReqLevelBox:CreateTexture(nil, "BACKGROUND")
    maxBg:SetAllPoints(true)
    maxBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    maxBg:SetVertexColor(0.08, 0.08, 0.14, 0.90)
    local maxBorder = maxReqLevelBox:CreateTexture(nil, "BORDER")
    maxBorder:SetPoint("TOPLEFT", -1, 1)
    maxBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    maxBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    maxBorder:SetVertexColor(0.30, 0.30, 0.40, 0.80)

    local tooltipCheck = CreateFrame("CheckButton", "LCSearchTooltipCheck", window, "UICheckButtonTemplate")
    tooltipCheck:SetSize(24, 24)
    tooltipCheck:SetPoint("LEFT", maxReqLevelBox, "RIGHT", 15, 0)
    
    if L.db and L.db.profile and L.db.profile.searchTooltipsEnabled ~= nil then
        Viewer.searchTooltipsEnabled = L.db.profile.searchTooltipsEnabled
    else
        Viewer.searchTooltipsEnabled = false
    end
    tooltipCheck:SetChecked(Viewer.searchTooltipsEnabled)    
    local tooltipLabel = tooltipCheck:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
    tooltipLabel:SetPoint("LEFT", tooltipCheck, "RIGHT", 2, 0)
    tooltipLabel:SetText("Deep Search")    
    
    local function showDeepSearchTooltip(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Deep Search", 1, 1, 1)
        GameTooltip:AddLine("Searches item tooltips for stats (e.g., 'Strength', 'On use', 'Chance', 'hit').", 1, 0.82, 0, true)
        GameTooltip:Show()
        GameTooltip:SetFrameStrata("TOOLTIP") 
    end
    
    refreshDataBtn:ClearAllPoints()
    refreshDataBtn:SetPoint("LEFT", tooltipLabel, "RIGHT", 20, 0)
    refreshDataBtn:SetSize(110, BUTTON_HEIGHT)
    
    local bugBtn = CreateFrame("Button", nil, window)
    bugBtn:SetSize(24, 24)
    bugBtn:SetPoint("TOPRIGHT", window, "TOPRIGHT", -25, -73)
    
    local bugIcon = bugBtn:CreateTexture(nil, "ARTWORK")
    bugIcon:SetAllPoints()
    bugIcon:SetTexture("Interface\\Icons\\custom_55_bug_border")
    bugIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    
    local bugBorder = bugBtn:CreateTexture(nil, "OVERLAY")
    bugBorder:SetAllPoints()
    bugBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    bugBorder:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    bugBorder:SetVertexColor(0.8, 0.8, 0.8, 1)

    local bugHighlight = bugBtn:CreateTexture(nil, "HIGHLIGHT")
    bugHighlight:SetAllPoints()
    bugHighlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    bugHighlight:SetBlendMode("ADD")

    bugBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText("Report a Bug", 1, 0.4, 0.4)
        GameTooltip:AddLine("Generate a bug report and debug payload to help troubleshoot LootCollector issues.", 1, 1, 1, true)
        GameTooltip:Show()
        GameTooltip:SetFrameStrata("TOOLTIP")
    end)
    
    bugBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    bugBtn:SetScript("OnClick", function()
        local ImportExport = L:GetModule("ImportExport", true)
        if ImportExport and ImportExport.ShowReportGenerator then
            ImportExport:ShowReportGenerator()
        else
            print("|cffff0000LootCollector:|r ImportExport module is not available.")
        end
    end)

    local tooltipLabelHover = CreateFrame("Button", nil, window)
    tooltipLabelHover:SetPoint("TOPLEFT", tooltipLabel, "TOPLEFT")
    tooltipLabelHover:SetPoint("BOTTOMRIGHT", tooltipLabel, "BOTTOMRIGHT")
    tooltipLabelHover:EnableMouse(true)
    tooltipLabelHover:SetScript("OnEnter", showDeepSearchTooltip)
    tooltipLabelHover:SetScript("OnLeave", GameTooltip_Hide)
    tooltipLabelHover:SetScript("OnClick", function()
        tooltipCheck:Click()
    end)

    tooltipCheck:SetScript("OnClick", function(self)
        Viewer.searchTooltipsEnabled = self:GetChecked()
        if L.db and L.db.profile then
            L.db.profile.searchTooltipsEnabled = Viewer.searchTooltipsEnabled
        end
        Viewer.currentPage = 1
        Cache.discoveriesBuilt = false
        Viewer:RefreshData()
    end)

    local function UpdateReqLevelFilter()
        Viewer.minReqLevel = tonumber(minReqLevelBox:GetText())
        Viewer.maxReqLevel = tonumber(maxReqLevelBox:GetText())
        if Viewer.searchTypingTimer then C_Timer.CancelTimer(Viewer.searchTypingTimer) end
        Viewer.searchTypingTimer = C_Timer.After(0.4, function()
            Viewer.currentPage = 1
            Viewer:RefreshData()
            Viewer:UpdateClearAllButton()
        end)
    end

    minReqLevelBox:SetScript("OnTextChanged", UpdateReqLevelFilter)
    minReqLevelBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    minReqLevelBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    
    maxReqLevelBox:SetScript("OnTextChanged", UpdateReqLevelFilter)
    maxReqLevelBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    maxReqLevelBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local autocompleteDropdown = nil
    local autocompleteSuggestions = {}
    local selectedSuggestionIndex = 0

    local function createAutocompleteDropdown()
        if autocompleteDropdown then return autocompleteDropdown end
        autocompleteDropdown = CreateFrame("Frame", "LootCollectorSearchAutocomplete", Viewer.window)
        autocompleteDropdown:SetSize(200, 20)
        autocompleteDropdown:SetFrameStrata("DIALOG")
        autocompleteDropdown:SetFrameLevel(FRAME_LEVEL)
        autocompleteDropdown:Hide()

        autocompleteDropdown:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
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
        for i = 1, math.min(10, #candidates) do _tinsert(limitedCandidates, candidates[i]) end
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

        for _, button in ipairs(dropdown.buttons) do button:Hide() end
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

            local textObj = button:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
            textObj:SetPoint("LEFT", 5, 0)
            textObj:SetText(candidate)
            textObj:SetJustifyH("LEFT")
            textObj:SetTextColor(1, 1, 1) 

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
        if selectedSuggestionIndex > #autocompleteSuggestions then selectedSuggestionIndex = 1 end
        updateAutocompleteSelection()
    end

    local function selectPreviousSuggestion()
        if not autocompleteDropdown or not autocompleteDropdown:IsShown() then return end
        selectedSuggestionIndex = selectedSuggestionIndex - 1
        if selectedSuggestionIndex < 1 then selectedSuggestionIndex = #autocompleteSuggestions end
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
        if Viewer.searchTerm and Viewer.searchTerm ~= "" then
            clearBtn:Show()
            showAutocompleteSuggestions(Viewer.searchTerm)
        else
            clearBtn:Hide()
            hideAutocompleteDropdown()
        end
        if Viewer.searchTypingTimer then C_Timer.CancelTimer(Viewer.searchTypingTimer) end
        Viewer.searchTypingTimer = C_Timer.After(0.2, function()
            Viewer.currentPage = 1
            Viewer:RefreshData()
            Viewer:UpdateClearAllButton()
        end)
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
            if Viewer.searchTypingTimer then C_Timer.CancelTimer(Viewer.searchTypingTimer) end
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
            if key == "DOWN" then selectNextSuggestion(); return true
            elseif key == "UP" then selectPreviousSuggestion(); return true
            elseif key == "ENTER" then applySelectedSuggestion(); return true
            elseif key == "ESCAPE" then hideAutocompleteDropdown(); return true
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
            if not searchBox:HasFocus() then hideAutocompleteDropdown() end
        end)
    end)

    local additionalFiltersFrame = CreateFrame("Frame", "LootCollectorAdditionalFiltersFrame", window, "BackdropTemplate")
    additionalFiltersFrame:SetSize(700, 24) 
    additionalFiltersFrame:SetFrameStrata(FRAME_STRATA)
    additionalFiltersFrame:SetFrameLevel(FRAME_LEVEL + 1)
    additionalFiltersFrame:SetPoint("LEFT", bmvBtn, "RIGHT", 20, 0)
    additionalFiltersFrame:SetBackdrop(nil)

    local filtersLabel = additionalFiltersFrame:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
    filtersLabel:SetPoint("LEFT", 10, 0)
    filtersLabel:SetText("Filters:")

    local function CreateFlatFilterBtn(parent, label, width, anchorFrame, anchorPoint)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(width, BUTTON_HEIGHT)
        btn:SetPoint("LEFT", anchorFrame, anchorPoint or "RIGHT", anchorFrame == filtersLabel and 5 or 3, 0)
        btn:SetFrameStrata(FRAME_STRATA)
        btn:SetFrameLevel(FRAME_LEVEL + 1)
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints(true)
        btn.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        btn.bg:SetVertexColor(0.10, 0.10, 0.16, 0.85)
        btn.bgInner = btn:CreateTexture(nil, "ARTWORK")
        btn.bgInner:SetPoint("TOPLEFT", 1, -1)
        btn.bgInner:SetPoint("BOTTOMRIGHT", -1, 1)
        btn.bgInner:SetTexture("Interface\\Buttons\\WHITE8X8")
        btn.bgInner:SetVertexColor(0.06, 0.06, 0.10, 0.92)
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 1, -1)
        hl:SetPoint("BOTTOMRIGHT", -1, 1)
        hl:SetTexture("Interface\\Buttons\\WHITE8X8")
        hl:SetVertexColor(1, 1, 1, 0.1)
        btn:SetHighlightTexture(hl)
        
        btn._label = btn:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
        btn._label:SetAllPoints(true)
        btn._label:SetText(label)
        btn._label:SetTextColor(0.78, 0.78, 0.85, 1)
        btn._label:SetJustifyH("CENTER")
        
        btn.GetFontString = function(self) return self._label end
        btn.SetText = function(self, text) self._label:SetText(text) end
        btn.GetText = function(self) return self._label:GetText() end
        
        btn:SetScript("OnEnter", function(self) self.bgInner:SetVertexColor(0.14, 0.14, 0.22, 0.95) end)
        btn:SetScript("OnLeave", function(self) self.bgInner:SetVertexColor(0.06, 0.06, 0.10, 0.92) end)
        btn:SetScript("OnMouseDown", function(self) self.bgInner:SetVertexColor(0.10, 0.20, 0.35, 1) end)
        btn:SetScript("OnMouseUp", function(self) self.bgInner:SetVertexColor(0.06, 0.06, 0.10, 0.92) end)
        return btn
    end

    local sourceFilterBtn = CreateFlatFilterBtn(additionalFiltersFrame, "Source", 55, filtersLabel, "RIGHT")
    sourceFilterBtn:SetScript("OnClick", function(self, button)
        local values = GetUniqueValues("source")
        Viewer:ShowColumnFilterDropdown("source", self, values)
    end)
    sourceFilterBtn:RegisterForClicks("LeftButtonUp")

    local qualityFilterBtn = CreateFlatFilterBtn(additionalFiltersFrame, "Quality", 55, sourceFilterBtn, "RIGHT")
    qualityFilterBtn:SetScript("OnClick", function(self, button)
        local values = GetUniqueValues("quality")
        Viewer:ShowColumnFilterDropdown("quality", self, values)
    end)
    qualityFilterBtn:RegisterForClicks("LeftButtonUp")

    local vendorTypeFilterBtn = CreateFlatFilterBtn(additionalFiltersFrame, "Type", 55, qualityFilterBtn, "RIGHT")
    vendorTypeFilterBtn:SetScript("OnClick", function(self, button)
        local values = GetUniqueValues("vendorType")
        Viewer:ShowColumnFilterDropdown("vendorType", self, values)
    end)
    vendorTypeFilterBtn:RegisterForClicks("LeftButtonUp")

    local slotsFilterBtn = CreateFlatFilterBtn(additionalFiltersFrame, "Slots", 42, vendorTypeFilterBtn, "RIGHT")
    slotsFilterBtn:SetScript("OnClick", function(self, button)
        local values = GetUniqueValues("slot")
        Viewer:ShowColumnFilterDropdown("slot", self, values)
    end)
    slotsFilterBtn:RegisterForClicks("LeftButtonUp")

    local usableByFilterBtn = CreateFlatFilterBtn(additionalFiltersFrame, "Usable By", 65, slotsFilterBtn, "RIGHT")
    usableByFilterBtn:SetScript("OnClick", function(self, button)
        local values = GetUniqueValues("class")
        Viewer:ShowColumnFilterDropdown("class", self, values)
    end)
    usableByFilterBtn:RegisterForClicks("LeftButtonUp")

    local favoritesFilterBtn = CreateFlatFilterBtn(additionalFiltersFrame, "Favorites", 75, usableByFilterBtn, "RIGHT")
    favoritesFilterBtn:SetScript("OnClick", function(self, button)
        if Viewer.favoritesFilterState == nil then Viewer.favoritesFilterState = true else Viewer.favoritesFilterState = nil end
        Viewer.currentPage = 1
        Cache.filteredResults = {}
        Cache.lastFilterState = nil
        Viewer:RefreshData()
        Viewer:UpdateFilterButtonStates()
    end)
    favoritesFilterBtn:RegisterForClicks("LeftButtonUp")

    local lootedFilterBtn = CreateFlatFilterBtn(additionalFiltersFrame, "Looted", 75, favoritesFilterBtn, "RIGHT")
    lootedFilterBtn:SetScript("OnClick", function(self, button)
        if Viewer.lootedFilterState == nil then Viewer.lootedFilterState = true      
        elseif Viewer.lootedFilterState == true then Viewer.lootedFilterState = false     
        else Viewer.lootedFilterState = nil end
        Viewer.currentPage = 1
        Cache.filteredResults = {}
        Cache.lastFilterState = nil
        Viewer:RefreshData()
        Viewer:UpdateFilterButtonStates()
    end)
    lootedFilterBtn:RegisterForClicks("LeftButtonUp")

    local collectedMEFilterBtn = CreateFlatFilterBtn(additionalFiltersFrame, "Collected", 82, lootedFilterBtn, "RIGHT")
    collectedMEFilterBtn:SetScript("OnEnter", function(self) 
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Filter by Collected Mystic Enchants.\nTurn this off in CoA mode, as MEs do not exist there.")
        GameTooltip:Show() 
    end)
    collectedMEFilterBtn:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
    collectedMEFilterBtn:SetScript("OnClick", function(self, button)
        if Viewer.collectedMEFilterState == nil then Viewer.collectedMEFilterState = true
        elseif Viewer.collectedMEFilterState == true then Viewer.collectedMEFilterState = false
        else Viewer.collectedMEFilterState = nil end
        Viewer.currentPage = 1
        Cache.filteredResults = {}
        Cache.lastFilterState = nil
        Viewer:RefreshData()
        Viewer:UpdateFilterButtonStates()
    end)
    collectedMEFilterBtn:RegisterForClicks("LeftButtonUp")

    local lsFilterBtn = CreateFlatFilterBtn(additionalFiltersFrame, "Date: Off", 75, collectedMEFilterBtn, "RIGHT")
    lsFilterBtn:SetScript("OnClick", function(self, button)
        if Viewer.lastSeenSortState == "off" or not Viewer.lastSeenSortState then Viewer.lastSeenSortState = "new"
        elseif Viewer.lastSeenSortState == "new" then Viewer.lastSeenSortState = "old"
        else Viewer.lastSeenSortState = "off" end
        Viewer.currentPage = 1
        Cache.filteredResults = {}
        Cache.lastFilterState = nil
        Viewer:RefreshData()
        Viewer:UpdateFilterButtonStates()
    end)
    lsFilterBtn:RegisterForClicks("LeftButtonUp")

    local duplicatesFilterBtn = CreateFlatFilterBtn(additionalFiltersFrame, "Duplicates", 75, lsFilterBtn, "RIGHT")
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
    self.vendorTypeFilterBtn = vendorTypeFilterBtn
    self.slotsFilterBtn = slotsFilterBtn
    self.usableByFilterBtn = usableByFilterBtn
    self.favoritesFilterBtn = favoritesFilterBtn
    self.lootedFilterBtn = lootedFilterBtn
    self.collectedMEFilterBtn = collectedMEFilterBtn
    self.duplicatesFilterBtn = duplicatesFilterBtn
    self.lsFilterBtn = lsFilterBtn

    local headerFrame = CreateFrame("Frame", nil, window)
    headerFrame:SetSize(WINDOW_WIDTH - 40, HEADER_HEIGHT)
    headerFrame:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -10)
    headerFrame:SetFrameLevel(FRAME_LEVEL + 1)
    headerFrame:SetFrameStrata(FRAME_STRATA)

    headerFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 16, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    headerFrame:SetBackdropColor(0.08, 0.10, 0.14, 0.95)
    headerFrame:SetBackdropBorderColor(0.20, 0.20, 0.25, 1)

    local nameHeader = CreateFrame("Button", nil, headerFrame)
    nameHeader:SetSize(GRID_LAYOUT.NAME_WIDTH, HEADER_HEIGHT)
    nameHeader:SetPoint("LEFT", 5, 0)
    nameHeader:SetText("Name")
    nameHeader:SetNormalFontObject(UI_FONT_NAME)
    nameHeader:SetHighlightFontObject(UI_FONT_NAME)
    nameHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "name" then Viewer.sortAscending = not Viewer.sortAscending
        else Viewer.sortColumn = "name"; Viewer.sortAscending = true end
        Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
    end)

    local favHeader = CreateFrame("Button", nil, headerFrame)
    favHeader:SetSize(GRID_LAYOUT.FAV_WIDTH, HEADER_HEIGHT)
    favHeader:SetPoint("LEFT", nameHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    local favHeaderIcon = favHeader:CreateTexture(nil, "ARTWORK")
    favHeaderIcon:SetSize(14, 14)
    favHeaderIcon:SetPoint("CENTER", 0, 0)
    favHeaderIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    favHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "favorite" then Viewer.sortAscending = not Viewer.sortAscending
        else Viewer.sortColumn = "favorite"; Viewer.sortAscending = false end
        Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
    end)
    favHeader:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Favorites", 1, 1, 1)
        GameTooltip:AddLine("Click the star next to an item to favorite it.", nil, nil, nil, true)
        GameTooltip:AddLine("Your favorite items are saved per-character.", 1, 0.8, 0, true)
        GameTooltip:Show()
    end)
    favHeader:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

    local levelHeader = CreateFrame("Button", nil, headerFrame)
    levelHeader:SetSize(GRID_LAYOUT.LEVEL_WIDTH, HEADER_HEIGHT)
    levelHeader:SetPoint("LEFT", favHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    levelHeader:SetText("Level")
    levelHeader:SetNormalFontObject(UI_FONT_NAME)
    levelHeader:SetHighlightFontObject(UI_FONT_NAME)
    levelHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "level" then Viewer.sortAscending = not Viewer.sortAscending
        else Viewer.sortColumn = "level"; Viewer.sortAscending = true end
        Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
    end)

    local slotHeader = CreateFrame("Button", nil, headerFrame)
    slotHeader:SetSize(GRID_LAYOUT.SLOT_WIDTH, HEADER_HEIGHT)
    slotHeader:SetPoint("LEFT", levelHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    slotHeader:SetText("Slot")
    slotHeader:SetNormalFontObject(UI_FONT_NAME)
    slotHeader:SetHighlightFontObject(UI_FONT_NAME)
    slotHeader:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            local values = GetUniqueValues("slot")
            Viewer:ShowColumnFilterDropdown("slot", self, values)
        else
            if Viewer.sortColumn == "slot" then Viewer.sortAscending = not Viewer.sortAscending
            else Viewer.sortColumn = "slot"; Viewer.sortAscending = true end
            Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
        end
    end)
    slotHeader:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slotHeader:Hide() 

    local typeHeader = CreateFrame("Button", nil, headerFrame)
    typeHeader:SetSize(GRID_LAYOUT.TYPE_WIDTH, HEADER_HEIGHT)
    typeHeader:SetPoint("LEFT", slotHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    typeHeader:SetText("Type")
    typeHeader:SetNormalFontObject(UI_FONT_NAME)
    typeHeader:SetHighlightFontObject(UI_FONT_NAME)
    typeHeader:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            local values = GetUniqueValues("type")
            Viewer:ShowColumnFilterDropdown("type", self, values)
        else
            if Viewer.sortColumn == "type" then Viewer.sortAscending = not Viewer.sortAscending
            else Viewer.sortColumn = "type"; Viewer.sortAscending = true end
            Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
        end
    end)
    typeHeader:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    typeHeader:Hide() 

    local classHeader = CreateFrame("Button", nil, headerFrame)
    classHeader:SetSize(GRID_LAYOUT.CLASS_WIDTH, HEADER_HEIGHT)
    classHeader:SetPoint("LEFT", levelHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    classHeader:SetText("Class")
    classHeader:SetNormalFontObject(UI_FONT_NAME)
    classHeader:SetHighlightFontObject(UI_FONT_NAME)
    classHeader:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            local values = GetUniqueValues("class")
            Viewer:ShowColumnFilterDropdown("class", self, values)
        else
            if Viewer.sortColumn == "class" then Viewer.sortAscending = not Viewer.sortAscending
            else Viewer.sortColumn = "class"; Viewer.sortAscending = true end
            Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
        end
    end)
    classHeader:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    classHeader:Hide() 

    local zoneHeader = CreateFrame("Button", nil, headerFrame)
    zoneHeader:SetSize(GRID_LAYOUT.ZONE_WIDTH, HEADER_HEIGHT)
    zoneHeader:SetPoint("LEFT", classHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    zoneHeader:SetText("Zone")
    zoneHeader:SetNormalFontObject(UI_FONT_NAME)
    zoneHeader:SetHighlightFontObject(UI_FONT_NAME)
    zoneHeader:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            local values = GetUniqueValues("zone")
            Viewer:ShowColumnFilterDropdown("zone", self, values)
        else
            if Viewer.sortColumn == "zone" then Viewer.sortAscending = not Viewer.sortAscending
            else Viewer.sortColumn = "zone"; Viewer.sortAscending = true end
            Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
        end
    end)
    zoneHeader:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local foundByHeader = CreateFrame("Button", nil, headerFrame)
    foundByHeader:SetSize(GRID_LAYOUT.FOUND_BY_WIDTH, HEADER_HEIGHT)
    foundByHeader:SetPoint("LEFT", zoneHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    foundByHeader:SetText("Found By")
    foundByHeader:SetNormalFontObject(UI_FONT_NAME)
    foundByHeader:SetHighlightFontObject(UI_FONT_NAME)
    foundByHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "foundBy" then Viewer.sortAscending = not Viewer.sortAscending
        else Viewer.sortColumn = "foundBy"; Viewer.sortAscending = true end
        Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
    end)
    
    local vendorNameHeader = CreateFrame("Button", nil, headerFrame)
    vendorNameHeader:SetSize(GRID_LAYOUT.VENDOR_NAME_WIDTH_INLINE, HEADER_HEIGHT)
    vendorNameHeader:SetPoint("LEFT", 5, 0)
    vendorNameHeader:SetText("Vendor Name")
    vendorNameHeader:SetNormalFontObject(UI_FONT_NAME)
    vendorNameHeader:SetHighlightFontObject(UI_FONT_NAME)
    vendorNameHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "vendorName" then Viewer.sortAscending = not Viewer.sortAscending
        else Viewer.sortColumn = "vendorName"; Viewer.sortAscending = true end
        Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
    end)

    local inventoryHeader = headerFrame:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
    inventoryHeader:SetSize(GRID_LAYOUT.VENDOR_INVENTORY_WIDTH, HEADER_HEIGHT)
    inventoryHeader:SetPoint("LEFT", vendorNameHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    inventoryHeader:SetText("Inventory")
    
    local vendorPriceHeader = CreateFrame("Button", nil, headerFrame)
    vendorPriceHeader:SetSize(GRID_LAYOUT.VENDOR_PRICE_WIDTH, HEADER_HEIGHT)
    vendorPriceHeader:SetPoint("LEFT", inventoryHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    vendorPriceHeader:SetText("Price")
    vendorPriceHeader:SetNormalFontObject(UI_FONT_NAME)
    vendorPriceHeader:SetHighlightFontObject(UI_FONT_NAME)
    vendorPriceHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "price" then Viewer.sortAscending = not Viewer.sortAscending
        else Viewer.sortColumn = "price"; Viewer.sortAscending = true end
        Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
    end)

    local vendorTypeHeader = CreateFrame("Button", nil, headerFrame)
    vendorTypeHeader:SetSize(GRID_LAYOUT.VENDOR_TYPE_WIDTH, HEADER_HEIGHT)
    vendorTypeHeader:SetPoint("LEFT", vendorPriceHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    vendorTypeHeader:SetText("Type")
    vendorTypeHeader:SetNormalFontObject(UI_FONT_NAME)
    vendorTypeHeader:SetHighlightFontObject(UI_FONT_NAME)
    vendorTypeHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "vendorType" then Viewer.sortAscending = not Viewer.sortAscending
        else Viewer.sortColumn = "vendorType"; Viewer.sortAscending = true end
        Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
    end)

    local vendorZoneHeader = CreateFrame("Button", nil, headerFrame)
    vendorZoneHeader:SetSize(GRID_LAYOUT.VENDOR_ZONE_WIDTH, HEADER_HEIGHT)
    vendorZoneHeader:SetPoint("LEFT", vendorTypeHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    vendorZoneHeader:SetText("Zone")
    vendorZoneHeader:SetNormalFontObject(UI_FONT_NAME)
    vendorZoneHeader:SetHighlightFontObject(UI_FONT_NAME)
    vendorZoneHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "zone" then Viewer.sortAscending = not Viewer.sortAscending
        else Viewer.sortColumn = "zone"; Viewer.sortAscending = true end
        Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
    end)
    
    local vendorContinentHeader = CreateFrame("Button", nil, headerFrame)
    vendorContinentHeader:SetSize(GRID_LAYOUT.VENDOR_CONTINENT_WIDTH, HEADER_HEIGHT)
    vendorContinentHeader:SetPoint("LEFT", vendorZoneHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    vendorContinentHeader:SetText("Continent")
    vendorContinentHeader:SetNormalFontObject(UI_FONT_NAME)
    vendorContinentHeader:SetHighlightFontObject(UI_FONT_NAME)
    vendorContinentHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "continent" then Viewer.sortAscending = not Viewer.sortAscending
        else Viewer.sortColumn = "continent"; Viewer.sortAscending = true end
        Viewer.currentPage = 1; Viewer:UpdateSortHeaders(); Viewer:RefreshData()
    end)
    
    local actionsLabel = headerFrame:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
    actionsLabel:SetPoint("RIGHT", -45, 0)
    actionsLabel:SetTextColor(0.4, 0.6, 1.0)
    actionsLabel:SetText("Actions")

    local clearAllBtn = CreateFrame("Button", nil, window)
    clearAllBtn:SetSize(70, 22)
    clearAllBtn:SetPoint("TOPRIGHT", window, "TOPRIGHT", -25, -47)
    clearAllBtn:SetFrameLevel(FRAME_LEVEL + 1)
    
    clearAllBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    clearAllBtn:SetBackdropColor(0.15, 0.15, 0.25, 0.8)
    clearAllBtn:SetBackdropBorderColor(0.3, 0.3, 0.5, 0.8)
    
    local cfs = clearAllBtn:CreateFontString(nil, "OVERLAY")
    cfs:SetFontObject(UI_FONT_NAME)
    cfs:SetTextColor(1, 0.4, 0.4)
    cfs:SetPoint("CENTER", 0, 1)
    clearAllBtn:SetFontString(cfs)
    
    clearAllBtn:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.4, 0.4, 1) end)
    clearAllBtn:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(0.3, 0.3, 0.5, 0.8) end)
    
    clearAllBtn:SetText("Clear")
    clearAllBtn:SetScript("OnClick", function()
        Viewer.columnFilters.zone = {}
        Viewer.columnFilters.eq.slot = {}
        Viewer.columnFilters.eq.type = {}
        Viewer.columnFilters.eq.class = {}
        Viewer.columnFilters.ms.class = {}
        Viewer.columnFilters.source = {}
        Viewer.columnFilters.quality = {}
        Viewer.columnFilters.looted = {}
        Viewer.columnFilters.vendorType = {}
        Viewer.columnFilters.duplicates = false 
        
        Viewer.lootedFilterState = nil 
        Viewer.collectedMEFilterState = nil 
        Viewer.hasUncachedData = false
        Viewer.lastSeenSortState = "off"
        
        Viewer.searchTerm = ""
        searchBox:SetText("")
        
        Viewer.minReqLevel = nil
        Viewer.maxReqLevel = nil
        if Viewer.minReqLevelBox then Viewer.minReqLevelBox:SetText("") end
        if Viewer.maxReqLevelBox then Viewer.maxReqLevelBox:SetText("") end

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

    self.refreshDataBtn = refreshDataBtn
    
    local reloadBtn = CreateFrame("Button", nil, additionalFiltersFrame, "BackdropTemplate")
    reloadBtn:SetSize(70, 22)
    reloadBtn:SetPoint("BOTTOMRIGHT", additionalFiltersFrame, "BOTTOMRIGHT", 80, -30)
    reloadBtn:SetFrameStrata(FRAME_STRATA)
    reloadBtn:SetFrameLevel(FRAME_LEVEL + 1)
    
    reloadBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    reloadBtn:SetBackdropColor(0.15, 0.15, 0.25, 0.8)
    reloadBtn:SetBackdropBorderColor(0.5, 0.3, 0.3, 0.8)
    
    local rfs = reloadBtn:CreateFontString(nil, "OVERLAY")
    rfs:SetFontObject(UI_FONT_NAME)
    rfs:SetTextColor(1, 0.4, 0.4)
    rfs:SetPoint("CENTER", 0, 1)
    rfs:SetText("Reload")
    reloadBtn:SetFontString(rfs)
    
    reloadBtn:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.4, 0.4, 1) end)
    reloadBtn:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(0.5, 0.3, 0.3, 0.8) end)

    reloadBtn:SetScript("OnClick", function() ReloadUI() end)
    reloadBtn:Hide()
    self.reloadBtn = reloadBtn

    local reloadText = additionalFiltersFrame:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
    reloadText:SetPoint("RIGHT", reloadBtn, "LEFT", -10, 0)
    reloadText:SetText("|cffff0000If Level, Slot, or Type are empty:|r")
    reloadText:Hide()
    self.reloadText = reloadText    

    local paginationFrame = CreateFrame("Frame", nil, window)
    paginationFrame:SetSize(WINDOW_WIDTH - 32, 32)
    paginationFrame:SetPoint("BOTTOM", 0, 20)
    paginationFrame:SetFrameStrata(FRAME_STRATA)
    paginationFrame:SetFrameLevel(FRAME_LEVEL + 1)

    paginationFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 16, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    paginationFrame:SetBackdropColor(0.06, 0.06, 0.10, 0.95)
    paginationFrame:SetBackdropBorderColor(0.20, 0.20, 0.28, 1)

    local pageInfo = paginationFrame:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
    pageInfo:SetPoint("CENTER", 10, 0)
    pageInfo:SetText("Page 1 of 1")

    local function CreateFlatBtn(parent, label, width, anchorPoint, x, y)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(width, BUTTON_HEIGHT)
        if anchorPoint then btn:SetPoint(anchorPoint, x or 0, y or 0) end
        btn:SetFrameStrata(FRAME_STRATA)
        btn:SetFrameLevel(FRAME_LEVEL + 1)
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints(true)
        btn.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        btn.bg:SetVertexColor(0.10, 0.10, 0.16, 0.85)
        btn.bgInner = btn:CreateTexture(nil, "ARTWORK")
        btn.bgInner:SetPoint("TOPLEFT", 1, -1)
        btn.bgInner:SetPoint("BOTTOMRIGHT", -1, 1)
        btn.bgInner:SetTexture("Interface\\Buttons\\WHITE8X8")
        btn.bgInner:SetVertexColor(0.06, 0.06, 0.10, 0.92)
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 1, -1)
        hl:SetPoint("BOTTOMRIGHT", -1, 1)
        hl:SetTexture("Interface\\Buttons\\WHITE8X8")
        hl:SetVertexColor(1, 1, 1, 0.1)
        btn:SetHighlightTexture(hl)
        btn._label = btn:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
        btn._label:SetAllPoints(true)
        btn._label:SetText(label)
        btn._label:SetTextColor(0.78, 0.78, 0.85, 1)
        btn._label:SetJustifyH("CENTER")
        
        btn.GetFontString = function(self) return self._label end
        btn.SetText = function(self, text) self._label:SetText(text) end
        btn.GetText = function(self) return self._label:GetText() end
        btn:SetScript("OnEnter", function(self) self.bgInner:SetVertexColor(0.14, 0.14, 0.22, 0.95) end)
        btn:SetScript("OnLeave", function(self) self.bgInner:SetVertexColor(0.06, 0.06, 0.10, 0.92) end)
        btn:SetScript("OnMouseDown", function(self) self.bgInner:SetVertexColor(0.10, 0.20, 0.35, 1) end)
        btn:SetScript("OnMouseUp", function(self) self.bgInner:SetVertexColor(0.06, 0.06, 0.10, 0.92) end)
        return btn
    end

    local prevBtn = CreateFlatBtn(paginationFrame, "Previous", 80, "LEFT", 5, 0)
    prevBtn:SetScript("OnClick", function()
        if self.currentPage > 1 then
            self.currentPage = self.currentPage - 1
            self:UpdatePagination()
            self:UpdateRows()
        end
    end)

    local nextBtn = CreateFlatBtn(paginationFrame, "Next", 80, "RIGHT", -10, 0)
    nextBtn:SetScript("OnClick", function()
        local totalPages = self:GetTotalPages()
        if self.currentPage < totalPages then
            self.currentPage = self.currentPage + 1
            self:UpdatePagination()
            self:UpdateRows()
        end
    end)

    local itemsLabel = paginationFrame:CreateFontString(nil, "OVERLAY", UI_FONT_NAME)
    itemsLabel:SetPoint("LEFT", prevBtn, "RIGHT", 20, 0)
    itemsLabel:SetText("Items per page:")

    local items25Btn = CreateFlatBtn(paginationFrame, "25", 30)
    items25Btn:SetPoint("LEFT", itemsLabel, "RIGHT", 5, 0)
    items25Btn:SetScript("OnClick", function()
        local oldItemsPerPage = Viewer.itemsPerPage
        Viewer.itemsPerPage = 25
        local currentItemIndex = (Viewer.currentPage - 1) * oldItemsPerPage + 1
        Viewer.currentPage = math.ceil(currentItemIndex / Viewer.itemsPerPage)
        Viewer:UpdateItemsPerPageButtons()
        Viewer:UpdatePagination()
        Viewer:RefreshData()
    end)

    local items50Btn = CreateFlatBtn(paginationFrame, "50", 30)
    items50Btn:SetPoint("LEFT", items25Btn, "RIGHT", 2, 0)
    items50Btn:SetScript("OnClick", function()
        local oldItemsPerPage = Viewer.itemsPerPage
        Viewer.itemsPerPage = 50
        local currentItemIndex = (Viewer.currentPage - 1) * oldItemsPerPage + 1
        Viewer.currentPage = math.ceil(currentItemIndex / Viewer.itemsPerPage)
        Viewer:UpdateItemsPerPageButtons()
        Viewer:UpdatePagination()
        Viewer:RefreshData()
    end)

    local items100Btn = CreateFlatBtn(paginationFrame, "100", 35)
    items100Btn:SetPoint("LEFT", items50Btn, "RIGHT", 2, 0)
    items100Btn:SetScript("OnClick", function()
        local oldItemsPerPage = Viewer.itemsPerPage
        Viewer.itemsPerPage = 100
        local currentItemIndex = (Viewer.currentPage - 1) * oldItemsPerPage + 1
        Viewer.currentPage = math.ceil(currentItemIndex / Viewer.itemsPerPage)
        Viewer:UpdateItemsPerPageButtons()
        Viewer:UpdatePagination()
        Viewer:RefreshData()
    end)

    local items500Btn = CreateFlatBtn(paginationFrame, "500", 35)
    items500Btn:SetPoint("LEFT", items100Btn, "RIGHT", 2, 0)
    items500Btn:SetScript("OnClick", function()
        local oldItemsPerPage = Viewer.itemsPerPage
        Viewer.itemsPerPage = 500
        local currentItemIndex = (Viewer.currentPage - 1) * oldItemsPerPage + 1
        Viewer.currentPage = math.ceil(currentItemIndex / Viewer.itemsPerPage)
        Viewer:UpdateItemsPerPageButtons()
        Viewer:UpdatePagination()
        Viewer:RefreshData()
    end)

    local itemsAllBtn = CreateFlatBtn(paginationFrame, "All", 35)
    itemsAllBtn:SetPoint("LEFT", items500Btn, "RIGHT", 2, 0)
    itemsAllBtn:SetScript("OnClick", function()
        local oldItemsPerPage = Viewer.itemsPerPage
        Viewer.itemsPerPage = 99999
        local currentItemIndex = (Viewer.currentPage - 1) * oldItemsPerPage + 1
        Viewer.currentPage = math.ceil(currentItemIndex / Viewer.itemsPerPage)
        Viewer:UpdateItemsPerPageButtons()
        Viewer:UpdatePagination()
        Viewer:RefreshData()
    end)

    local scrollFrame = CreateFrame("ScrollFrame", "LootCollectorViewerScrollFrame", window, "FauxScrollFrameTemplate")
    scrollFrame:SetSize(WINDOW_WIDTH - 60, WINDOW_HEIGHT - 200) 
    scrollFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -5)
    scrollFrame:SetFrameLevel(FRAME_LEVEL + 1)
    scrollFrame:SetFrameStrata(FRAME_STRATA)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() Viewer:UpdateRows() end)
    end)
    window:SkinScrollBar(scrollFrame)
    
    self.window = window
    self.scrollFrame = scrollFrame
    self.equipmentBtn = equipmentBtn
    self.mysticBtn = mysticBtn
    self.bmvBtn = bmvBtn
    self.searchBox = searchBox
    self.minReqLevelBox = minReqLevelBox
    self.maxReqLevelBox = maxReqLevelBox
    self.searchClearBtn = clearBtn
    self.additionalFiltersFrame = additionalFiltersFrame
    self.filtersLabel = filtersLabel
    self.sourceFilterBtn = sourceFilterBtn
    self.qualityFilterBtn = qualityFilterBtn
    self.favoritesFilterBtn = favoritesFilterBtn
    self.lootedFilterBtn = lootedFilterBtn
    self.nameHeader = nameHeader
    self.favHeader = favHeader
    self.levelHeader = levelHeader
    self.slotHeader = slotHeader
    self.typeHeader = typeHeader
    self.classHeader = classHeader
    self.zoneHeader = zoneHeader    
    self.foundByHeader = foundByHeader
    
    vendorNameHeader:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.vendorNameHeader = vendorNameHeader    
    vendorNameHeader:Hide()
    
    vendorPriceHeader:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.vendorPriceHeader = vendorPriceHeader
    vendorPriceHeader:Hide()
    
    vendorTypeHeader:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.vendorTypeHeader = vendorTypeHeader
    vendorTypeHeader:Hide()
    
    inventoryHeader:SetTextColor(1, 0.82, 0)
    inventoryHeader:SetJustifyH("LEFT")
    self.inventoryHeader = inventoryHeader
    inventoryHeader:Hide()
    
    vendorZoneHeader:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.vendorZoneHeader = vendorZoneHeader
    vendorZoneHeader:Hide()
    
    vendorContinentHeader:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.vendorContinentHeader = vendorContinentHeader
    vendorContinentHeader:Hide()
    
    self.clearAllBtn = clearAllBtn
    self.actionsLabel = actionsLabel
    self.pageInfo = pageInfo
    self.prevBtn = prevBtn
    self.nextBtn = nextBtn
    self.items25Btn = items25Btn    
    self.items50Btn = items50Btn
    self.items100Btn = items100Btn
    self.items500Btn = items500Btn
    self.itemsAllBtn = itemsAllBtn
    self.paginationFrame = paginationFrame
    self.duplicatesFilterBtn = duplicatesFilterBtn 
    self.vendorTypeFilterBtn = vendorTypeFilterBtn
    self.slotsFilterBtn = slotsFilterBtn
    self.usableByFilterBtn = usableByFilterBtn
    self.lsFilterBtn = lsFilterBtn
    
    self.interactiveElements = {
        equipmentBtn, mysticBtn, bmvBtn,
        searchBox, sourceFilterBtn, qualityFilterBtn, lootedFilterBtn, duplicatesFilterBtn, vendorTypeFilterBtn, collectedMEFilterBtn, lsFilterBtn,
        nameHeader, levelHeader, slotHeader, typeHeader, classHeader, zoneHeader,  foundByHeader,
        vendorNameHeader, vendorPriceHeader, vendorZoneHeader, vendorContinentHeader, vendorTypeHeader,
        clearAllBtn, prevBtn, nextBtn, items25Btn, items50Btn, items100Btn, items500Btn, itemsAllBtn,
        slotsFilterBtn, usableByFilterBtn, favoritesFilterBtn
    }

    
    
    
    local splitter = CreateFrame("Button", "LootCollectorViewerSplitter", window)
    splitter:SetHeight(8)
    splitter:SetFrameStrata("HIGH")
    splitter:SetFrameLevel(window:GetFrameLevel() + 20)
    
    splitter.tex = splitter:CreateTexture(nil, "OVERLAY")
    splitter.tex:SetHeight(2)
    splitter.tex:SetPoint("LEFT", 5, 0)
    splitter.tex:SetPoint("RIGHT", -5, 0)
    splitter.tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    splitter.tex:SetVertexColor(0.25, 0.3, 0.4, 0.6)
    
    splitter:SetScript("OnEnter", function(self)        
        SetCursor("Interface\\CURSOR\\UI-Cursor-Size.blp")
        self.tex:SetVertexColor(0.3, 0.6, 1.0, 1.0)
    end)
    splitter:SetScript("OnLeave", function(self)
        ResetCursor()
        self.tex:SetVertexColor(0.25, 0.3, 0.4, 0.6)
    end)
    
    splitter:SetMovable(true)
    splitter:RegisterForDrag("LeftButton")
    
    splitter:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:SetScript("OnUpdate", function(s)
            local _, cy = GetCursorPosition()
            local effScale = window:GetEffectiveScale()
            cy = cy / effScale
            
            local topY = Viewer.scrollFrame:GetTop() or (window:GetTop() - 100)
            local bottomY = paginationFrame:GetTop() or (window:GetBottom() + 40)
            local totalHeight = topY - bottomY
            
            if totalHeight > 50 then
                local cursorDist = topY - cy
                local ratio = cursorDist / totalHeight
                ratio = math.max(0.15, math.min(0.85, ratio))
                
                Viewer.splitRatio = ratio
                L.db.profile.viewer.splitRatio = ratio
                
                Viewer:UpdateLayout()
                Viewer:UpdateRows()
            end
        end)
    end)
    
    splitter:SetScript("OnDragStop", function(self)
        self.isDragging = false
        self:SetScript("OnUpdate", nil)
        ResetCursor()
        if L.db and L.db.profile and L.db.profile.viewer then
            L.db.profile.viewer.splitRatio = Viewer.splitRatio
        end
    end)
    
    self.splitterBar = splitter
    splitter:Hide()

    self:CreateRows()

    self.currentFilter = "eq"
    self:UpdateFilterButtons()
    self:UpdateSortHeaders()
    self:UpdateItemsPerPageButtons()
    self:UpdateFilterButtonStates()
	
    window:SetScript("OnSizeChanged", function(self, width, height)
        if headerFrame then headerFrame:SetWidth(width - 40) end
        if paginationFrame then paginationFrame:SetWidth(width - 32) end
        
        Viewer:UpdateLayout()
        Viewer:CreateRows()

        local innerWidth = width - 60

        
        local staticEq = GRID_LAYOUT.FAV_WIDTH + GRID_LAYOUT.LEVEL_WIDTH + GRID_LAYOUT.SLOT_WIDTH + 
                         GRID_LAYOUT.TYPE_WIDTH + GRID_LAYOUT.ZONE_WIDTH + GRID_LAYOUT.FOUND_BY_WIDTH + 
                         (GRID_LAYOUT.COLUMN_SPACING * 6) + 162
        
        
        local currentNameWidth = math.max(GRID_LAYOUT.NAME_WIDTH, innerWidth - staticEq)
        local flexAmount = currentNameWidth - GRID_LAYOUT.NAME_WIDTH
        
        
        local baseVendorNameWidth = Viewer.inlineVendorView and GRID_LAYOUT.VENDOR_NAME_WIDTH_INLINE or GRID_LAYOUT.VENDOR_NAME_WIDTH_SPLIT
        local currentVendorNameWidth = baseVendorNameWidth + flexAmount
        
        if Viewer.nameHeader then Viewer.nameHeader:SetWidth(currentNameWidth) end
        if Viewer.vendorNameHeader then Viewer.vendorNameHeader:SetWidth(currentVendorNameWidth) end

        for _, row in ipairs(Viewer.rows) do
            row:SetWidth(innerWidth)
            if row.nameFrame then row.nameFrame:SetWidth(currentNameWidth) end
            if row.nameText then row.nameText:SetWidth(currentNameWidth) end
            if row.vendorNameText then row.vendorNameText:SetWidth(currentVendorNameWidth) end
        end
        Viewer:UpdateRows()
    end)
    
    if WorldMapFrame then
        self.window:SetFrameLevel(WorldMapFrame:GetFrameLevel() -1)
    end
    if pTime then L:ProfileStop("Scanner:ExtractClassToken", pTime) end
end

function Viewer:CreateRows(count)
    local pTime = L.ProfileStart and L:ProfileStart() 
    
    local innerWidth = self.window:GetWidth() - 60
    count = count or math.ceil(self:GetMainScrollHeight() / ROW_HEIGHT)

    
    
    local staticEq = GRID_LAYOUT.FAV_WIDTH + GRID_LAYOUT.LEVEL_WIDTH + GRID_LAYOUT.SLOT_WIDTH + 
                     GRID_LAYOUT.TYPE_WIDTH + GRID_LAYOUT.ZONE_WIDTH + GRID_LAYOUT.FOUND_BY_WIDTH + 
                     (GRID_LAYOUT.COLUMN_SPACING * 6) + 162
                     
    local currentNameWidth = math.max(GRID_LAYOUT.NAME_WIDTH, innerWidth - staticEq)
    local baseVendorNameWidth = self.inlineVendorView and GRID_LAYOUT.VENDOR_NAME_WIDTH_INLINE or GRID_LAYOUT.VENDOR_NAME_WIDTH_SPLIT
    local currentVendorNameWidth = baseVendorNameWidth + (currentNameWidth - GRID_LAYOUT.NAME_WIDTH)

    for i = 1, count do
        local row = self.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, self.scrollFrame:GetParent())
            row:SetHeight(ROW_HEIGHT)
            row:SetFrameLevel(self.scrollFrame:GetFrameLevel() + 1)
            row:SetFrameStrata(FRAME_STRATA)
            
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.scrollFrame, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
            
            row.rowBg = row:CreateTexture(nil, "ARTWORK", nil, -1)
            row.rowBg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            row.rowBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
            row.rowBg:SetTexture("Interface\\Buttons\\WHITE8X8")
            if i % 2 == 0 then
                row.rowBg:SetVertexColor(0.12, 0.14, 0.20, 0.65)
            else
                row.rowBg:SetVertexColor(0.06, 0.06, 0.10, 0.40)
            end
            row.isEvenRow = (i % 2 == 0)

            row.hoverTex = row:CreateTexture(nil, "ARTWORK", nil, 0)
            row.hoverTex:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            row.hoverTex:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
            row.hoverTex:SetTexture("Interface\\Buttons\\WHITE8X8")
            row.hoverTex:SetVertexColor(0.20, 0.45, 0.80, 0.0)

            row.highlight = row:CreateTexture(nil, "OVERLAY")
            row.highlight:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            row.highlight:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
            row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            row.highlight:SetBlendMode("ADD")
            row.highlight:Hide()

            local nameFrame = CreateFrame("Frame", nil, row)
            nameFrame:SetSize(currentNameWidth, ROW_HEIGHT) 
            
            nameFrame:SetPoint("LEFT", row, "LEFT", 5, 0)
            nameFrame:EnableMouse(true)

            local iconFrame = CreateFrame("Frame", nil, nameFrame)
            iconFrame:SetSize(20, 20)
            iconFrame:SetPoint("LEFT", 0, 0)
            iconFrame:SetFrameLevel(row:GetFrameLevel() + 10)
            row.iconFrame = iconFrame

            local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
            iconTex:SetAllPoints(iconFrame)
            
            local rawSetDesaturated = iconTex.SetDesaturated
            iconTex.SetDesaturated = function(self, desaturated) rawSetDesaturated(self, false) end
            local rawSetVertexColor = iconTex.SetVertexColor
            iconTex.SetVertexColor = function(self, r, g, b, a) rawSetVertexColor(self, 1, 1, 1, 1) end
            local rawSetAlpha = iconTex.SetAlpha
            iconTex.SetAlpha = function(self, alpha) rawSetAlpha(self, 1.0) end

            row.iconTex = iconTex

            local nameText = nameFrame:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
            nameText:SetPoint("LEFT", iconFrame, "RIGHT", 4, 0)
            nameText:SetPoint("RIGHT", 0, 0)
            nameText:SetJustifyH("LEFT")

            nameFrame:SetScript("OnEnter", function(self)
                local parentRow = self:GetParent()
                if parentRow and parentRow.hoverTex then
                    parentRow.hoverTex:SetVertexColor(0.20, 0.40, 0.70, 0.12)
                end
                if self.discoveryData then
                    if self.discoveryData.isVendorItemRow then
                        local item = self.discoveryData.item
                        if item and item.link then
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 20, 10)
                            GameTooltip:SetHyperlink(item.link)
                            GameTooltip:Show()
                            GameTooltip:SetFrameStrata("TOOLTIP") 
                        end
                    else
                        local d = self.discoveryData.discovery
                        if d and d.il then
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 20, 10)
                            GameTooltip:SetHyperlink(d.il)
                            GameTooltip:Show()
                            GameTooltip:SetFrameStrata("TOOLTIP") 
                        elseif d and d.i then
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 20, 10)
                            GameTooltip:SetHyperlink("item:" .. d.i)
                            GameTooltip:Show()
                            GameTooltip:SetFrameStrata("TOOLTIP") 
                        end
                    end
                end
            end)

            nameFrame:SetScript("OnLeave", function(self)
                local parentRow = self:GetParent()
                if parentRow and parentRow.hoverTex then
                    parentRow.hoverTex:SetVertexColor(0.20, 0.40, 0.70, 0.0)
                end
                GameTooltip:Hide()
            end)	  

            nameFrame:SetScript("OnMouseUp", function(self, button)
                if not self.discoveryData then return end
                
                local guid = self.discoveryData.guid
                local db = L:GetDiscoveriesDB()
                local dbV = L:GetVendorsDB()
                local currentRecord = (db and db[guid]) or (dbV and dbV[guid])
                
                if not currentRecord then
                    print("|cffff7f00LootCollector:|r This discovery no longer exists. Refreshing list...")
                    Cache.discoveriesBuilt = false
                    Viewer:RefreshData()
                    return
                end
                
                self.discoveryData.discovery = currentRecord
                local data = self.discoveryData
                local r  = self:GetParent()
                Viewer:SetSelectedRow(r)

                local isVendorView = (Viewer.currentFilter == "bmv")
                if isVendorView and data.isVendor and button == "LeftButton" and not IsShiftKeyDown() and not IsControlKeyDown() then
                    if Viewer.inlineVendorView then
                        Viewer.expandedVendors = Viewer.expandedVendors or {}
                        if Viewer.expandedVendors[data.guid] then
                            Viewer.expandedVendors[data.guid] = nil
                        else
                            Viewer.expandedVendors[data.guid] = true
                        end
                        Cache.lastFilterState = nil
                        Viewer:RefreshData()
                    else
                        if Viewer.ShowVendorInventoryForDiscovery and data.discovery then
                            Viewer:ShowVendorInventoryForDiscovery(data.discovery)
                        end
                    end
                    return
                end

                if IsShiftKeyDown() and data then
                    Viewer:ShowOnMap(data)
                    return
                end

                local isCtrlDown = IsControlKeyDown()

                if button == "LeftButton" then
                    if isCtrlDown then self:LinkItemToChat() end
                elseif button == "RightButton" then
                    if isCtrlDown then
                        local zoneName = GetLocalizedZoneName(data.discovery)
                        local coords = ""
                        if data.discovery.xy then                        
                            coords = string.format("%.2f, %.2f", (data.discovery.xy.x or 0) * 100, (data.discovery.xy.y or 0) * 100)
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

            local favBtn = CreateFrame("Button", nil, row)
            favBtn:SetSize(GRID_LAYOUT.FAV_WIDTH, ROW_HEIGHT)
            favBtn:SetPoint("LEFT", nameFrame, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
            local favIcon = favBtn:CreateTexture(nil, "ARTWORK")
            favIcon:SetSize(16, 16)
            favIcon:SetPoint("CENTER", 0, 0)
            favIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
            row.favIcon = favIcon
            row.favBtn = favBtn

            favBtn:SetScript("OnClick", function(self)
                local data = row.discoveryData
                if data and data.discovery and data.discovery.i then
                    local itemId = data.discovery.i
                    
                    local guid = data.guid
                    local db = L:GetDiscoveriesDB()
                    if not (db and db[guid]) then
                        print("|cffff7f00LootCollector:|r This discovery no longer exists. Refreshing list...")
                        Cache.discoveriesBuilt = false
                        Viewer:RefreshData()
                        return
                    end

                    PlaySound("igMainMenuOptionCheckBoxOn")
                    if L.db.profile.favorites[itemId] then
                        L.db.profile.favorites[itemId] = nil
                        favIcon:SetDesaturated(true)
                        favIcon:SetVertexColor(0.5, 0.5, 0.5, 0.5)
                    else
                        L.db.profile.favorites[itemId] = true
                        favIcon:SetDesaturated(false)
                        favIcon:SetVertexColor(1, 1, 1, 1)
                    end
                    if Viewer.favoritesFilterState then Viewer:RefreshData() end
                end
            end)

            local levelText = row:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
            levelText:SetPoint("LEFT", favBtn, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
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
                if not self.discoveryData or not self.discoveryData.discovery.fp then return end
                local playerName = self.discoveryData.discovery.fp
                local buttons = { { text = "Delete all from " .. playerName, onClick = function() Viewer:ConfirmDeleteAllFromPlayer(playerName) end } }
                CreateContextMenu(self, "Player: " .. playerName, buttons)
            end

            
            
            
            local vendorNameText = row:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
            
            vendorNameText:SetPoint("LEFT", row, "LEFT", 5, 0)
            vendorNameText:SetSize(currentVendorNameWidth, ROW_HEIGHT) 
            vendorNameText:SetJustifyH("LEFT")
            vendorNameText:Hide()

            local vendorNameFrame = CreateFrame("Frame", nil, row)
            vendorNameFrame:SetPoint("TOPLEFT", vendorNameText, "TOPLEFT", 0, 0)
            vendorNameFrame:SetPoint("BOTTOMRIGHT", vendorNameText, "BOTTOMRIGHT", 0, 0)
            vendorNameFrame:EnableMouse(true)
            vendorNameFrame:Hide()

            local vendorIconFrame = CreateFrame("Frame", nil, row)
            vendorIconFrame:SetSize(20, 20)
            
            vendorIconFrame:SetPoint("LEFT", row, "LEFT", 5, 0)
            vendorIconFrame:SetFrameLevel(row:GetFrameLevel() + 10)
            row.vendorIconFrame = vendorIconFrame

            local vendorIconTex = vendorIconFrame:CreateTexture(nil, "ARTWORK")
            vendorIconTex:SetAllPoints(vendorIconFrame)
            local rawSetDesaturated = vendorIconTex.SetDesaturated
            vendorIconTex.SetDesaturated = function(self, desaturated) rawSetDesaturated(self, false) end
            local rawSetVertexColor = vendorIconTex.SetVertexColor
            vendorIconTex.SetVertexColor = function(self, r, g, b, a) rawSetVertexColor(self, 1, 1, 1, 1) end
            local rawSetAlpha = vendorIconTex.SetAlpha
            vendorIconTex.SetAlpha = function(self, alpha) rawSetAlpha(self, 1.0) end
            row.vendorIconTex = vendorIconTex

            local vendorPriceText = row:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
            vendorPriceText:SetSize(GRID_LAYOUT.VENDOR_PRICE_WIDTH, ROW_HEIGHT)
            vendorPriceText:SetJustifyH("LEFT")
            vendorPriceText:Hide()

            local vendorTypeText = row:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
            vendorTypeText:SetSize(GRID_LAYOUT.VENDOR_TYPE_WIDTH, ROW_HEIGHT)
            vendorTypeText:SetJustifyH("LEFT")
            vendorTypeText:Hide()

            local inventoryFrame = CreateFrame("Button", nil, row)
            inventoryFrame:SetSize(GRID_LAYOUT.VENDOR_INVENTORY_WIDTH, ROW_HEIGHT)
            inventoryFrame:EnableMouse(true)
            inventoryFrame:Hide()

            local inventoryText = inventoryFrame:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
            inventoryText:SetAllPoints(true)
            inventoryText:SetJustifyH("LEFT")
            inventoryText:SetText("|cff00ff00View Items...|r")

            local vendorZoneText = row:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
            vendorZoneText:SetSize(GRID_LAYOUT.VENDOR_ZONE_WIDTH, ROW_HEIGHT)
            vendorZoneText:SetJustifyH("LEFT")
            vendorZoneText:Hide()

            local vendorContinentText = row:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
            vendorContinentText:SetSize(GRID_LAYOUT.VENDOR_CONTINENT_WIDTH, ROW_HEIGHT)
            vendorContinentText:SetJustifyH("LEFT")
            vendorContinentText:Hide()

            
            local function OnVendorInteraction(self, button)
                if not self.discoveryData then return end
                
                local guid = self.discoveryData.guid
                local dbV = L:GetVendorsDB()
                local currentRecord = dbV and dbV[guid]
                
                if not currentRecord then
                    print("|cffff7f00LootCollector:|r This vendor no longer exists. Refreshing list...")
                    Cache.discoveriesBuilt = false
                    Viewer:RefreshData()
                    return
                end
                
                self.discoveryData.discovery = currentRecord
                local data = self.discoveryData
                local r  = self:GetParent()
                Viewer:SetSelectedRow(r)

                local isVendorView = (Viewer.currentFilter == "bmv")
                if isVendorView and data.isVendor and button == "LeftButton"
                   and not IsControlKeyDown() then
                    if Viewer.inlineVendorView then
                        Viewer.expandedVendors = Viewer.expandedVendors or {}
                        if Viewer.expandedVendors[data.guid] then
                            Viewer.expandedVendors[data.guid] = nil
                        else
                            Viewer.expandedVendors[data.guid] = true
                        end
                        Cache.lastFilterState = nil
                        Viewer:RefreshData()
                    else
                        if Viewer.ShowVendorInventoryForDiscovery and data.discovery then
                            Viewer:ShowVendorInventoryForDiscovery(data.discovery)
                        end
                    end
                end
            end

            vendorNameFrame:SetScript("OnMouseUp", OnVendorInteraction)
            inventoryFrame:SetScript("OnMouseUp", OnVendorInteraction)

            inventoryFrame:SetScript("OnEnter", function(self)
                if self.discoveryData and self.discoveryData.isVendor and self.discoveryData.discovery.vendorItems then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine("Inventory", 1, 1, 0)
                    for _, item in ipairs(self.discoveryData.discovery.vendorItems) do
                        GameTooltip:AddLine(item.link)
                    end
                    GameTooltip:Show()
                    GameTooltip:SetFrameStrata("TOOLTIP") 
                end
            end)
            inventoryFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

            
            local function CreateFlatActionBtn(parent, label, r, g, b, tooltipText, anchorTo, anchorPoint)
                local btn = CreateFrame("Button", nil, parent)
                btn:SetSize(18, 16)
                if anchorTo then
                    btn:SetPoint("RIGHT", anchorTo, "LEFT", -3, 0)
                end
                btn.bg = btn:CreateTexture(nil, "BACKGROUND")
                btn.bg:SetAllPoints(true)
                btn.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
                btn.bg:SetVertexColor(r * 0.30, g * 0.30, b * 0.30, 0.85)
                btn.border = btn:CreateTexture(nil, "BORDER")
                btn.border:SetAllPoints(true)
                btn.border:SetTexture("Interface\\Buttons\\WHITE8X8")
                btn.border:SetVertexColor(r * 0.70, g * 0.70, b * 0.70, 0.80)
                btn.border:SetAlpha(0)
                btn.bgInner = btn:CreateTexture(nil, "ARTWORK")
                btn.bgInner:SetPoint("TOPLEFT", 1, -1)
                btn.bgInner:SetPoint("BOTTOMRIGHT", -1, 1)
                btn.bgInner:SetTexture("Interface\\Buttons\\WHITE8X8")
                btn.bgInner:SetVertexColor(r * 0.18, g * 0.18, b * 0.18, 0.90)
                btn.label = btn:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
                btn.label:SetAllPoints(true)
                btn.label:SetText(label)
                btn.label:SetTextColor(r, g, b, 1)
                btn.label:SetJustifyH("CENTER")

                btn:SetScript("OnEnter", function(self)
                    self.bg:SetVertexColor(r * 0.55, g * 0.55, b * 0.55, 1)
                    self.bgInner:SetVertexColor(r * 0.30, g * 0.30, b * 0.30, 1)
                    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
                    GameTooltip:SetText(tooltipText)
                    GameTooltip:Show()
                    GameTooltip:SetFrameStrata("TOOLTIP")
                end)
                btn:SetScript("OnLeave", function(self)
                    self.bg:SetVertexColor(r * 0.30, g * 0.30, b * 0.30, 0.85)
                    self.bgInner:SetVertexColor(r * 0.18, g * 0.18, b * 0.18, 0.90)
                    GameTooltip:Hide()
                end)
                btn:SetScript("OnMouseDown", function(self) self.label:SetPoint("TOPLEFT", 1, -2) end)
                btn:SetScript("OnMouseUp", function(self) self.label:SetPoint("TOPLEFT", 0, 0) end)
                return btn
            end

            local deleteBtn = CreateFlatActionBtn(row, "D", 1.0, 0.3, 0.3, "Delete", nil, nil)
            deleteBtn:SetPoint("RIGHT", -5, 0)
            deleteBtn:SetScript("OnClick", function(self)
                Viewer:SetSelectedRow(self:GetParent())
                local r = self:GetParent()
                if r.discoveryData then 
                    local guid = r.discoveryData.guid
                    local db = L:GetDiscoveriesDB()
                    local dbV = L:GetVendorsDB()
                    if not (db and db[guid]) and not (dbV and dbV[guid]) then
                        print("|cffff7f00LootCollector:|r This discovery no longer exists. Refreshing list...")
                        Cache.discoveriesBuilt = false
                        Viewer:RefreshData()
                        return
                    end

                    r.deleteBtn:SetEnabled(false)
                    r.navBtn:SetEnabled(false)
                    r.showBtn:SetEnabled(false)
                    r.lootedBtn:SetEnabled(false)
                    r.unlootedBtn:SetEnabled(false)
                    r:SetAlpha(0.4)
                    
                    Viewer:ConfirmDelete(r.discoveryData) 
                end
            end)

            local unlootedBtn = CreateFlatActionBtn(row, "U", 1.0, 0.65, 0.1, "Mark as Unlooted", deleteBtn, nil)
            unlootedBtn:SetScript("OnClick", function(self)
                Viewer:SetSelectedRow(self:GetParent())
                local r = self:GetParent()
                if r.discoveryData then 
                    local guid = r.discoveryData.guid
                    local db = L:GetDiscoveriesDB()
                    if not (db and db[guid]) then
                        print("|cffff7f00LootCollector:|r This discovery no longer exists. Refreshing list...")
                        Cache.discoveriesBuilt = false
                        Viewer:RefreshData()
                        return
                    end
                    Viewer:ToggleLootedState(guid, r.discoveryData) 
                end
            end)

            local lootedBtn = CreateFlatActionBtn(row, "L", 0.6, 1.0, 0.2, "Mark as Looted", unlootedBtn, nil)
            lootedBtn:SetScript("OnClick", function(self)
                Viewer:SetSelectedRow(self:GetParent())
                local r = self:GetParent()
                if r.discoveryData then 
                    local guid = r.discoveryData.guid
                    local db = L:GetDiscoveriesDB()
                    if not (db and db[guid]) then
                        print("|cffff7f00LootCollector:|r This discovery no longer exists. Refreshing list...")
                        Cache.discoveriesBuilt = false
                        Viewer:RefreshData()
                        return
                    end
                    Viewer:ToggleLootedState(guid, r.discoveryData) 
                end
            end)

            local navBtn = CreateFlatActionBtn(row, "N", 0.2, 0.8, 1.0, "Navigate", lootedBtn, nil)
            navBtn:SetScript("OnClick", function(self)
                Viewer:SetSelectedRow(self:GetParent())
                local r = self:GetParent()
                if r.discoveryData then
                    local guid = r.discoveryData.guid
                    local db = L:GetDiscoveriesDB()
                    local dbV = L:GetVendorsDB()
                    local currentRecord = (db and db[guid]) or (dbV and dbV[guid])
                    if not currentRecord then
                        print("|cffff7f00LootCollector:|r This discovery no longer exists. Refreshing list...")
                        Cache.discoveriesBuilt = false
                        Viewer:RefreshData()
                        return
                    end
                    local Arrow = L:GetModule("Arrow", true)
                    if Arrow and Arrow.NavigateTo then Arrow:NavigateTo(currentRecord) end
                end
            end)

            local showBtn = CreateFlatActionBtn(row, "S", 0.5, 0.5, 1.0, "Show on Map", navBtn, nil)
            showBtn:SetScript("OnClick", function(self)
                Viewer:SetSelectedRow(self:GetParent())
                local r = self:GetParent()
                if r.discoveryData then 
                    local guid = r.discoveryData.guid
                    local db = L:GetDiscoveriesDB()
                    local dbV = L:GetVendorsDB()
                    local currentRecord = (db and db[guid]) or (dbV and dbV[guid])
                    if not currentRecord then
                        print("|cffff7f00LootCollector:|r This discovery no longer exists. Refreshing list...")
                        Cache.discoveriesBuilt = false
                        Viewer:RefreshData()
                        return
                    end
                    Viewer:ShowOnMap(currentRecord) 
                end
            end)

            nameFrame.ShowContextMenu = function(self)
                if not self.discoveryData then return end
                local isLooted = Viewer:IsLootedByChar(self.discoveryData.guid)
                local buttons = {
                    { text = "Show", onClick = function() Viewer:ShowOnMap(self.discoveryData) end },
                    { text = isLooted and "Set as unlooted" or "Set as looted", onClick = function() Viewer:ToggleLootedState(self.discoveryData.guid, self.discoveryData) end },
                    { text = "Delete", onClick = function() Viewer:ConfirmDelete(self.discoveryData) end },
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
                    if id then itemID = tonumber(id) end
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
            row.vendorPriceText = vendorPriceText
            row.vendorTypeText  = vendorTypeText
            row.vendorZoneText  = vendorZoneText
            row.vendorContinentText = vendorContinentText
            row.inventoryFrame  = inventoryFrame
            row.inventoryText   = inventoryText

            row.deleteBtn      = deleteBtn
            row.unlootedBtn    = unlootedBtn
            row.lootedBtn      = lootedBtn
            row.navBtn         = navBtn
            row.showBtn        = showBtn

            self.rows[i] = row
        end
        
        row:SetSize(innerWidth, ROW_HEIGHT)
    end
    
    if pTime then L:ProfileStop("Viewer:CreateRows", pTime) end 
end

function Viewer:UpdateFilterButtons()
    
    if self.equipmentBtn and self.equipmentBtn.SetActive then self.equipmentBtn:SetActive(false) end
    if self.mysticBtn    and self.mysticBtn.SetActive    then self.mysticBtn:SetActive(false) end
    if self.bmvBtn       and self.bmvBtn.SetActive       then self.bmvBtn:SetActive(false) end

    
    if self.currentFilter == "eq" and self.equipmentBtn and self.equipmentBtn.SetActive then
        self.equipmentBtn:SetActive(true)
    elseif self.currentFilter == "ms" and self.mysticBtn and self.mysticBtn.SetActive then
        self.mysticBtn:SetActive(true)
    elseif self.currentFilter == "bmv" and self.bmvBtn and self.bmvBtn.SetActive then
        self.bmvBtn:SetActive(true)
    end
end

function Viewer:UpdateSortHeaders()
    local pTime = L.ProfileStart and L:ProfileStart() 

    local function setButtonTextColor(button, r, g, b)
        local fontString = button:GetFontString()
        if fontString then
            fontString:SetTextColor(r, g, b)
        end
    end

    local isEqView = (self.currentFilter == "eq" or self.currentFilter == "msv")
    local isMsView = (self.currentFilter == "ms")
    local isVendorView = (self.currentFilter == "bmv")

    self.nameHeader:Hide(); self.favHeader:Hide(); self.slotHeader:Hide(); self.typeHeader:Hide(); self.classHeader:Hide()
    self.zoneHeader:Hide(); self.levelHeader:Hide(); self.foundByHeader:Hide()
    
    self.vendorNameHeader:Hide()
    if self.vendorPriceHeader then self.vendorPriceHeader:Hide() end
    self.vendorTypeHeader:Hide()
    self.vendorZoneHeader:Hide()
    self.vendorContinentHeader:Hide()
    self.inventoryHeader:Hide()
    
    local lastHeader = nil

    if isVendorView then
        self.vendorNameHeader:Show()
        self.vendorTypeHeader:Show()
        self.vendorZoneHeader:Show()
        self.vendorContinentHeader:Show()
        
        if self.inlineVendorView then
            self.inventoryHeader:Show()
            if self.vendorPriceHeader then self.vendorPriceHeader:Show() end
        end
        
        self.vendorNameHeader:ClearAllPoints()
        self.vendorNameHeader:SetPoint("LEFT", 5, 0)
        lastHeader = self.vendorNameHeader

        if self.inlineVendorView then
            self.inventoryHeader:ClearAllPoints()
            self.inventoryHeader:SetPoint("LEFT", lastHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
            lastHeader = self.inventoryHeader

            if self.vendorPriceHeader then
                self.vendorPriceHeader:ClearAllPoints()
                self.vendorPriceHeader:SetPoint("LEFT", lastHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
                lastHeader = self.vendorPriceHeader
            end
        end

        self.vendorTypeHeader:ClearAllPoints()
        self.vendorTypeHeader:SetPoint("LEFT", lastHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        lastHeader = self.vendorTypeHeader

        self.vendorZoneHeader:ClearAllPoints()
        self.vendorZoneHeader:SetPoint("LEFT", lastHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        lastHeader = self.vendorZoneHeader

        self.vendorContinentHeader:ClearAllPoints()
        self.vendorContinentHeader:SetPoint("LEFT", lastHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        
        local sortIndicator = self.sortAscending and " \124TInterface\\Buttons\\UI-SortArrow-Up:12:12:0:0\124t" or " \124TInterface\\Buttons\\UI-SortArrow-Down:12:12:0:0\124t"
        local sortColor = {0.2, 0.8, 1}
        local defaultColor = {1, 1, 1}

        setButtonTextColor(self.vendorNameHeader, self.sortColumn == "vendorName" and sortColor[1] or defaultColor[1], self.sortColumn == "vendorName" and sortColor[2] or defaultColor[2], self.sortColumn == "vendorName" and sortColor[3] or defaultColor[3])
        if self.inlineVendorView and self.vendorPriceHeader then
            setButtonTextColor(self.vendorPriceHeader, self.sortColumn == "price" and sortColor[1] or defaultColor[1], self.sortColumn == "price" and sortColor[2] or defaultColor[2], self.sortColumn == "price" and sortColor[3] or defaultColor[3])
        end
        setButtonTextColor(self.vendorTypeHeader, self.sortColumn == "vendorType" and sortColor[1] or defaultColor[1], self.sortColumn == "vendorType" and sortColor[2] or defaultColor[2], self.sortColumn == "vendorType" and sortColor[3] or defaultColor[3])
        setButtonTextColor(self.vendorZoneHeader, self.sortColumn == "zone" and sortColor[1] or defaultColor[1], self.sortColumn == "zone" and sortColor[2] or defaultColor[2], self.sortColumn == "zone" and sortColor[3] or defaultColor[3])
        
        self.vendorNameHeader:SetText(self.sortColumn == "vendorName" and "Vendor Name" .. sortIndicator or "Vendor Name")
        if self.inlineVendorView and self.vendorPriceHeader then
            self.vendorPriceHeader:SetText(self.sortColumn == "price" and "Price" .. sortIndicator or "Price")
        end
        self.vendorTypeHeader:SetText(self.sortColumn == "vendorType" and "Type" .. sortIndicator or "Type")
        self.vendorZoneHeader:SetText(self.sortColumn == "zone" and "Zone" .. sortIndicator or "Zone")

    else 
        self.nameHeader:Show(); self.favHeader:Show(); self.levelHeader:Show(); self.zoneHeader:Show(); self.foundByHeader:Show()
        
        self.nameHeader:ClearAllPoints()
        self.nameHeader:SetPoint("LEFT", 5, 0)
        lastHeader = self.nameHeader
        
        self.favHeader:ClearAllPoints()
        self.favHeader:SetPoint("LEFT", lastHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        lastHeader = self.favHeader

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
    
    if pTime then L:ProfileStop("Viewer:UpdateSortHeaders", pTime) end 
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
    local pTime = L.ProfileStart and L:ProfileStart() 

    local discoveries = self:GetPaginatedDiscoveries()
    local numDiscoveries = #discoveries
    
    local visibleRows = math.ceil(self:GetMainScrollHeight() / ROW_HEIGHT)
    if #self.rows < visibleRows then
        self:CreateRows(visibleRows)
    end

    self:UpdatePagination()

    local isEqView = (self.currentFilter == "eq" or self.currentFilter == "msv")
    local isMsView = (self.currentFilter == "ms")
    local isVendorView = (self.currentFilter == "bmv")
    
    local isLoading = Cache.discoveriesBuilding

    FauxScrollFrame_Update(self.scrollFrame, numDiscoveries, visibleRows, ROW_HEIGHT)
    
    if self.scrollFrame.ScrollBar and self.scrollFrame.ScrollBar.ScrollUpButton then
        self.scrollFrame.ScrollBar.ScrollUpButton:SetFrameStrata(FRAME_STRATA)
        self.scrollFrame.ScrollBar.ScrollUpButton:SetFrameLevel(FRAME_LEVEL)
    end
    if self.scrollFrame.ScrollBar and self.scrollFrame.ScrollBar.ScrollDownButton then
        self.scrollFrame.ScrollBar.ScrollDownButton:SetFrameStrata(FRAME_STRATA)
        self.scrollFrame.ScrollBar.ScrollDownButton:SetFrameLevel(FRAME_LEVEL)
    end

    local innerWidth = self.window:GetWidth() - 60
    local staticEq = GRID_LAYOUT.FAV_WIDTH + GRID_LAYOUT.LEVEL_WIDTH + GRID_LAYOUT.SLOT_WIDTH + 
                     GRID_LAYOUT.TYPE_WIDTH + GRID_LAYOUT.ZONE_WIDTH + GRID_LAYOUT.FOUND_BY_WIDTH + 
                     (GRID_LAYOUT.COLUMN_SPACING * 6) + 162
                     
    local currentNameWidth = math.max(GRID_LAYOUT.NAME_WIDTH, innerWidth - staticEq)
    local baseVendorNameWidth = self.inlineVendorView and GRID_LAYOUT.VENDOR_NAME_WIDTH_INLINE or GRID_LAYOUT.VENDOR_NAME_WIDTH_SPLIT
    local currentVendorNameWidth = baseVendorNameWidth + (currentNameWidth - GRID_LAYOUT.NAME_WIDTH)

    for i = 1, #self.rows do
        local row = self.rows[i]
        
        if i > visibleRows then
            row:Hide()
        else
            local offset = FauxScrollFrame_GetOffset(self.scrollFrame)
            local data = discoveries[i + offset]

            if data then
                row:SetAlpha(1.0) 
                
                local discovery = data.discovery
                row.discoveryData = data
                row.nameFrame.discoveryData       = data
                row.foundByFrame.discoveryData    = data
                row.vendorNameFrame.discoveryData = data
                row.inventoryFrame.discoveryData  = data

                local isVendorItem = data.isVendorItemRow

                row.nameFrame:SetShown(not isVendorView and not isVendorItem)
                row.levelText:SetShown(not isVendorView and not isVendorItem)
                row.zoneText:SetShown((isEqView or isMsView) and not isVendorItem)
                row.foundByFrame:SetShown((isEqView or isMsView) and not isVendorItem)
                row.slotText:SetShown(isEqView and not isVendorItem)
                row.typeText:SetShown(isEqView and not isVendorItem)
                row.classText:SetShown(isMsView and not isVendorItem)
                
                row.vendorNameText:SetShown(isVendorView and not isVendorItem)
                row.vendorNameFrame:SetShown(isVendorView and not isVendorItem)
                row.vendorPriceText:SetShown(isVendorView)
                row.vendorTypeText:SetShown(isVendorView and not isVendorItem)
                row.vendorZoneText:SetShown(isVendorView and not isVendorItem)
                row.vendorContinentText:SetShown(isVendorView and not isVendorItem)
                row.inventoryFrame:SetShown(isVendorView and not isVendorItem and self.inlineVendorView)

                if self.selectedRow == row then
                    row.highlight:Show()
                else
                    row.highlight:Hide()
                end
                
                if isVendorView then
                    
                    row.vendorNameText:SetWidth(currentVendorNameWidth)
                    row.vendorNameFrame:SetWidth(currentVendorNameWidth)
                    
                    
                    
                    local currentX = 5 + currentVendorNameWidth + GRID_LAYOUT.COLUMN_SPACING
                    
                    if self.inlineVendorView then
                        row.inventoryFrame:ClearAllPoints()
                        row.inventoryFrame:SetPoint("LEFT", row, "LEFT", currentX, 0)
                        currentX = currentX + GRID_LAYOUT.VENDOR_INVENTORY_WIDTH + GRID_LAYOUT.COLUMN_SPACING
                        
                        row.vendorPriceText:ClearAllPoints()
                        row.vendorPriceText:SetPoint("LEFT", row, "LEFT", currentX, 0)
                        currentX = currentX + GRID_LAYOUT.VENDOR_PRICE_WIDTH + GRID_LAYOUT.COLUMN_SPACING
                    end
                    
                    row.vendorTypeText:ClearAllPoints()
                    row.vendorTypeText:SetPoint("LEFT", row, "LEFT", currentX, 0)
                    currentX = currentX + GRID_LAYOUT.VENDOR_TYPE_WIDTH + GRID_LAYOUT.COLUMN_SPACING
                    
                    row.vendorZoneText:ClearAllPoints()
                    row.vendorZoneText:SetPoint("LEFT", row, "LEFT", currentX, 0)
                    currentX = currentX + GRID_LAYOUT.VENDOR_ZONE_WIDTH + GRID_LAYOUT.COLUMN_SPACING
                    
                    row.vendorContinentText:ClearAllPoints()
                    row.vendorContinentText:SetPoint("LEFT", row, "LEFT", currentX, 0)
                end
                
                if isVendorItem then
                    if row.toggleText then row.toggleText:Hide() end
                    if row.vendorIconTex then row.vendorIconTex:Hide() end
                    if row.vendorIconFrame then row.vendorIconFrame:Hide() end
                    
                    local icon = data.item.icon or (data.item.itemID and GetItemIcon(data.item.itemID)) or "Interface\\Icons\\INV_Misc_QuestionMark"
                    row.iconTex:SetTexture(icon)
                    row.iconTex:SetAlpha(1.0)
                    row.iconTex:SetVertexColor(1, 1, 1, 1)
                    row.iconTex:SetDesaturated(false)
                    row.iconTex:Show()
                    
                    row:SetAlpha(1.0)
                    row.nameFrame:SetShown(true)
                    row.nameText:SetText(data.item.link or data.item.name)
                    row.nameText:SetAlpha(1.0)
                    row.nameText:SetTextColor(1, 1, 1, 1)
                    row.nameFrame:ClearAllPoints()
                    
                    row.nameFrame:SetPoint("LEFT", row, "LEFT", 20, 0)
                    
                    row.nameFrame:SetWidth(currentVendorNameWidth)
                    row.nameText:SetWidth(currentVendorNameWidth)
                    row.nameText:ClearAllPoints()
                    row.nameText:SetPoint("LEFT", row.iconFrame or row.iconTex, "RIGHT", 4, 0)
                    row.nameText:SetPoint("RIGHT", 0, 0)
                    
                    row.vendorPriceText:SetText(data.item.price and data.item.price > 0 and GetCoinTextureString(data.item.price) or "")
                    row.vendorPriceText:SetAlpha(1.0)
                    
                    row.deleteBtn:Hide()
                    row.navBtn:Hide()
                    row.showBtn:Hide()
                    row.unlootedBtn:Hide()
                    row.lootedBtn:Hide()
                    
                    if row.favBtn then row.favBtn:Hide() end

                elseif isVendorView then
                    row:SetAlpha(1.0)
                    
                    local vType = discovery.vendorType or (discovery.g and discovery.g:find("MS-", 1, true) and "MS") or (discovery.g and discovery.g:find("EX-", 1, true) and "EX") or (discovery.g and discovery.g:find("RING-", 1, true) and "RING") or "BM"
                    local icon
                    if vType == "MS" then
                        icon = "Interface\\Icons\\INV_Scroll_03"
                    else
                        icon = discovery.il and GetItemIcon(discovery.il) or nil
                        if not icon and discovery.i then icon = GetItemIcon(discovery.i) end
                        if not icon then
                            if vType == "EX" then
                                icon = "Interface\\Icons\\INV_Ascend_Gems_2"
                            elseif vType == "RING" then
                                icon = "Interface\\Icons\\inv_misc_diamondring2"
                            else
                                icon = "Interface\\Icons\\ability_priest_darkness"
                            end
                        end
                    end

                    if icon then
                        row.vendorIconTex:SetTexture(icon)
                        row.vendorIconTex:SetAlpha(1.0)
                        row.vendorIconTex:SetVertexColor(1, 1, 1, 1)
                        row.vendorIconTex:SetDesaturated(false)
                        if row.vendorIconFrame then
                            row.vendorIconFrame:ClearAllPoints()
                            
                            row.vendorIconFrame:SetPoint("LEFT", row, "LEFT", 16, 0)
                            row.vendorIconFrame:Show()
                        else
                            row.vendorIconTex:ClearAllPoints()
                            
                            row.vendorIconTex:SetPoint("LEFT", row, "LEFT", 16, 0)
                        end
                        row.vendorIconTex:Show()
                        row.vendorNameText:ClearAllPoints()
                        
                        row.vendorNameText:SetPoint("LEFT", row, "LEFT", 38, 0)
                    else
                        row.vendorIconTex:Hide()
                        if row.vendorIconFrame then row.vendorIconFrame:Hide() end
                        row.vendorNameText:ClearAllPoints()
                        
                        row.vendorNameText:SetPoint("LEFT", row, "LEFT", 16, 0)
                    end
                    
                    if not row.toggleText then
                        row.toggleText = row:CreateFontString(nil, "OVERLAY", ROW_FONT_NAME)
                        row.toggleText:SetJustifyH("LEFT")
                    end

                    if self.inlineVendorView then
                        row.toggleText:Show()
                        local toggle = (Viewer.expandedVendors and Viewer.expandedVendors[data.guid]) and "-" or "+"
                        row.toggleText:SetText(toggle)
                        
                        row.toggleText:SetPoint("LEFT", row, "LEFT", 4, 0)
                    else
                        row.toggleText:Hide()
                    end
                    
                    row.vendorNameText:SetText(discovery.vendorName or "Unknown")
                    row.vendorNameText:SetTextColor(1, 0.82, 0)
                    row.vendorPriceText:SetText("")
                    
                    local typeText = discovery.vendorSubname or ""
                    if typeText == "" then
                        if discovery.vendorType == "BM" then typeText = "Blackmarket Artisan Supplies"
                        elseif discovery.vendorType == "EX" then typeText = "Exquisite Collectables"
                        elseif discovery.vendorType == "RING" then typeText = "Ring Vendor"
                        elseif discovery.vendorType == "MS" then typeText = "Mystic Enchants"
                        end
                    end
                    row.vendorTypeText:SetText(typeText)
                    
                    row.vendorZoneText:SetText(GetLocalizedZoneName(discovery))
                    local continentNames = { [1] = "Kalimdor", [2] = "Eastern Kingdoms", [3] = "Outland", [4] = "Northrend" }
                    row.vendorContinentText:SetText(discovery.c and continentNames[discovery.c] or "Unknown")
                    local invCount = (discovery.vendorItems and #discovery.vendorItems) or 0
                    row.inventoryText:SetText(string.format("(%d items)", invCount))
                    
                    if row.favBtn then row.favBtn:Hide() end
                else
                    if row.toggleText then row.toggleText:Hide() end
                    if row.vendorIconTex then row.vendorIconTex:Hide() end
                    if row.vendorIconFrame then row.vendorIconFrame:Hide() end
                    
                    row.nameFrame:SetWidth(currentNameWidth)
                    row.nameText:SetWidth(currentNameWidth)
                    
                    local isLooted = self:IsLootedByChar(data.guid)
                    local alpha = (not isLooted) and 1.0 or 0.5
                    local itemName = data.itemName
                    
                    local r, g, b = GetColorForDiscovery(discovery, discovery.i)
                    itemName = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, itemName)
                    
                    if data.matchedViaTooltip then
                        itemName = itemName .. " |cffffd100[DS]|r"
                    end
                    
                    local icon = data.discovery.il and GetItemIcon(data.discovery.il) or nil
                    if not icon and data.discovery.i then icon = GetItemIcon(data.discovery.i) end
                    if icon then
                        row.iconTex:SetTexture(icon)
                        row.iconTex:SetAlpha(1.0)
                        row.iconTex:SetVertexColor(1, 1, 1, 1)
                        row.iconTex:SetDesaturated(false)
                        row.iconTex:Show()
                    else
                        row.iconTex:Hide()
                    end
                    
                    row.nameFrame:ClearAllPoints()
                    row.nameFrame:SetPoint("LEFT", 5, 0)
                    row.nameText:ClearAllPoints()
                    row.nameText:SetPoint("LEFT", row.iconFrame or row.iconTex, "RIGHT", 4, 0)
                    row.nameText:SetPoint("RIGHT", 0, 0)
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
                                classDisplay = (_G.LOCALIZED_CLASS_NAMES_MALE[classToken] or _G.LOCALIZED_CLASS_NAMES_FEMALE[classToken] or "")
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
                    
                    if row.favIcon then
                        row.favBtn:Show()
                        if discovery.i and L.db.profile.favorites[discovery.i] then
                            row.favIcon:SetDesaturated(false)
                            row.favIcon:SetVertexColor(1, 1, 1, 1)
                        else
                            row.favIcon:SetDesaturated(true)
                            row.favIcon:SetVertexColor(0.5, 0.5, 0.5, 0.5)
                        end
                    end
                end
                
                local isLooted = self:IsLootedByChar(data.guid)
                row.lootedBtn:SetEnabled(not isVendorView and not isLooted and not isLoading)
                row.unlootedBtn:SetEnabled(not isVendorView and isLooted and not isLoading)
                row.lootedBtn:SetShown(not isVendorView)
                row.unlootedBtn:SetShown(not isVendorView)
                row.lootedBtn:SetAlpha((isLooted and not isLoading) and 1.0 or 0.3)
                row.unlootedBtn:SetAlpha((not isLooted and not isLoading) and 1.0 or 0.3)
                
                row.deleteBtn:SetEnabled(not isLoading)
                row.navBtn:SetEnabled(not isLoading)
                row.showBtn:SetEnabled(not isLoading)
                row.nameFrame:EnableMouse(not isLoading)
                if not isVendorItem then
                    row.deleteBtn:Show()
                    row.navBtn:Show()
                    row.showBtn:Show()
                end
                row:Show()
            else
                row:Hide()
                row.discoveryData = nil
                row.nameFrame.discoveryData = nil
                row.foundByFrame.discoveryData = nil
                if row.highlight then row.highlight:Hide() end
                if row.bg then row.bg:Hide() end
                row.deleteBtn:Hide()
                row.navBtn:Hide()
                row.showBtn:Hide()
                row.lootedBtn:Hide()
                row.unlootedBtn:Hide()
            end
        end
    end

    local shownCount = 0
    for i = 1, #self.rows do
        local row = self.rows[i]
        if row:IsShown() then
            shownCount = shownCount + 1
            if shownCount % 2 == 0 then
                row.rowBg:SetVertexColor(0.12, 0.14, 0.20, 0.65)
            else
                row.rowBg:SetVertexColor(0.06, 0.06, 0.10, 0.40)
            end
        end
    end

    if pTime then L:ProfileStop("Viewer:UpdateRows", pTime) end 
end

function Viewer:PrewarmCache()
    if Cache.discoveriesBuilt or Cache.discoveriesBuilding then
        VDebug("PrewarmCache: skipped (built=" .. tostring(Cache.discoveriesBuilt) .. ", building=" .. tostring(Cache.discoveriesBuilding) .. ")")
        return
    end

    VDebug("PrewarmCache: starting async cache build in background")
    self:UpdateAllDiscoveriesCache(function()
        VDebug("PrewarmCache: async cache build complete (discoveries=" .. tostring(#Cache.discoveries) .. ")")
    end)
end

function Viewer:InvalidateFilterCache()
    Cache.filteredResults = {}
    Cache.lastFilterState = nil
end

function Viewer:RefreshData()
local pTime = L.ProfileStart and L:ProfileStart() 
    local t0 = time()
    VDebug("RefreshData: start, cacheBuilt=" .. tostring(Cache.discoveriesBuilt) ..
        ", building=" .. tostring(Cache.discoveriesBuilding))
    if not self.window or not self.window:IsShown() then return end

    self:UpdateFilterButtonStates()
	self:UpdateLayout()

    local now = time()
    local dataHasChanged = HasDataChanged()
    
    
    local shouldRebuildCache = false
    if not Cache.discoveriesBuilt or dataHasChanged then
        shouldRebuildCache = true
    end
    
    VDebug("RefreshData: dataHasChanged=" .. tostring(dataHasChanged) ..
        ", shouldRebuild=" .. tostring(shouldRebuildCache))

    if shouldRebuildCache and not Cache.discoveriesBuilding then
        VDebug("RefreshData: calling UpdateAllDiscoveriesCache(async)")
        self:UpdateAllDiscoveriesCacheSync(function()
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
    if pTime then L:ProfileStop("Viewer:RefreshData", pTime) end 
end

function Viewer:IsLootedByChar(guid)
    if not guid or not (L.db and L.db.char and L.db.char.looted) then return false end
    return L.db.char.looted[guid] and true or false
end

function Viewer:ToggleLootedState(guid, discoveryData)
    if not guid or not (L.db and L.db.char) then return false end

    L.db.char.looted = L.db.char.looted or {}
    local isCurrentlyLooted = self:IsLootedByChar(guid)

    if isCurrentlyLooted then
        L.db.char.looted[guid] = nil
        print(string.format("|cff00ff00LootCollector:|r Marked '%s' as unlooted.", discoveryData.itemName or "Unknown Item"))
    else
        L.db.char.looted[guid] = time()
        print(string.format("|cff00ff00LootCollector:|r Marked '%s' as looted.", discoveryData.itemName or "Unknown Item"))
    end

    local Map = L:GetModule("Map", true)
    if Map then
        Map.cacheIsDirty = true 
        if Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end
        if Map.UpdateMinimap then Map:UpdateMinimap() end
    end

    self:RefreshData()
    return not isCurrentlyLooted 
end

function Viewer:ClearCaches()
    clearAllTimers()

    local cacheKeys = keys(Cache)
    for _, key in ipairs(cacheKeys) do
        if key == "discoveries" then Cache[key] = {}
        elseif key == "discoveriesBuilt" or key == "discoveriesBuilding" then Cache[key] = false
        elseif key == "uniqueValuesValid" then Cache[key] = false
        elseif key == "uniqueValues" then Cache[key] = { slot = {}, type = {}, class = {}, zone = {} }
        elseif key == "uniqueValuesContext" then Cache[key] = {}
        elseif key == "filteredResults" then Cache[key] = {}
        elseif key == "lastFilterState" then Cache[key] = nil
        elseif type(Cache[key]) == "table" then Cache[key] = {}
        end
    end

    local defaultFilters = {
        eq = { slot = {}, type = {}, class = {} },
        ms = { class = {} },
        zone = {},
        source = {},
        quality = {},
        looted = {},
        vendorType = {},
        duplicates = false 
    }
    self.columnFilters = copy(defaultFilters)

    Cache.duplicateItems = {}
    Cache.lastDiscoveryCount = nil
    L.itemInfoCache = {}
    Cache._cleanupRequired = true
    
    self.searchTerm = ""
    self.minReqLevel = nil
    self.maxReqLevel = nil
    self.lastSeenSortState = "off"
    self.lootedFilterState = nil
    self.collectedMEFilterState = nil
    self.favoritesFilterState = nil
    
    if self.minReqLevelBox then self.minReqLevelBox:SetText("") end
    if self.maxReqLevelBox then self.maxReqLevelBox:SetText("") end    
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

    if localClassScanTip then localClassScanTip:Hide() end
    if localWorldforgedScanTip then localWorldforgedScanTip:Hide() end

    scanQueue = {}
    scanCursor = 0
    scanProgressCallback = nil

    self.window = nil
    self.scrollFrame = nil
    self.rows = {}
    self.currentFilter = "eq"
    self.searchTerm = ""
    self.sortColumn = "name"
    self.sortAscending = true    
    self.pendingMapAreaID = nil
    self.currentPage = 1
    self.totalItems = 0
    self.lastSeenSortState = "off"
end

function Viewer:AddDiscoveryToCache(guid, discovery)
    
    
    return true
end

function Viewer:RemoveDiscoveryFromCache(guid)
    
    return true
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
    if not Core then return end

    self.ignoreNextRemoveMessage = guid 

    local isVendor = false
    local dbV = L:GetVendorsDB()
    if dbV and dbV[guid] then
        isVendor = true
    end

    if isVendor then
        if Core.RemoveBlackmarketVendorByGuid then
            Core:RemoveBlackmarketVendorByGuid(guid)
        end
    else
        if Core.ReportDiscoveryAsGone then
            Core:ReportDiscoveryAsGone(guid)
        end
    end

    
    
    Cache.discoveriesBuilt = false
    self:RefreshData()
    self:UpdateClearAllButton()
end

function Viewer:FindDiscoveriesByPlayer(playerName)
    if not playerName or playerName == "" then return {} end
    local discoveriesByPlayer = {}
    local discoveries = L:GetDiscoveriesDB()
    for guid, discovery in pairs(discoveries or {}) do
        if discovery and type(discovery) == "table" and discovery.fp == playerName then
            _tinsert(discoveriesByPlayer, { guid = guid, discovery = discovery })
        end
    end
    return discoveriesByPlayer
end

function Viewer:DeleteAllFromPlayer(playerName)
    if not playerName or playerName == "" then return 0 end

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
        print(string.format("|cff00ff00LootCollector:|r Deleted %d discoveries from player '%s'.", deletedCount, playerName))
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
    if not playerName or playerName == "" then return end

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
    if not discovery.g and discoveryData.guid then discovery.g = discoveryData.guid end
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

function Viewer:ApplySettings()
    if L.db and L.db.profile and L.db.profile.viewer then
        ROW_HEIGHT = L.db.profile.viewer.rowHeight or 28
        ROW_FONT_SIZE = L.db.profile.viewer.rowFontSize or 14
        ROW_FONT_PATH = L.db.profile.viewer.rowFont or "Fonts\\ARIALN.TTF"
        UI_FONT_SIZE = L.db.profile.viewer.uiFontSize or 13
        UI_FONT_PATH = L.db.profile.viewer.uiFont or "Fonts\\ARIALN.TTF"
        self.inlineVendorView = L.db.profile.viewer.inlineVendorView or false
        self.splitRatio = L.db.profile.viewer.splitRatio or 0.64
    end
    
    local listFont = _G[ROW_FONT_NAME]
    if listFont then
        listFont:SetFont(ROW_FONT_PATH, ROW_FONT_SIZE, "OUTLINE")
        listFont:SetShadowColor(0, 0, 0, 0.8)
        listFont:SetShadowOffset(1, -1)
    end
    
    local uiFont = _G[UI_FONT_NAME]
    if uiFont then
        uiFont:SetFont(UI_FONT_PATH, UI_FONT_SIZE, "OUTLINE")
        uiFont:SetShadowColor(0, 0, 0, 0.8)
        uiFont:SetShadowOffset(1, -1)
    end
    
    
    if self.window then
        self:UpdateSortHeaders()
        for i, row in ipairs(self.rows) do
            row:SetHeight(ROW_HEIGHT)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.scrollFrame, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
            for _, child in ipairs({row:GetChildren()}) do
                if child.SetHeight then child:SetHeight(ROW_HEIGHT) end
            end
        end
        self:UpdateLayout()
        self:UpdateRows()
    end
end

function Viewer:OnInitialize()
    local pTime = L.ProfileStart and L:ProfileStart() 

    
    
    self:CreateWindow() 
    self:ApplySettings()

    L:RegisterMessage("LootCollector_DiscoveriesUpdated", function(event, action, guid, discoveryData)
        if not Viewer.window or not Viewer.window:IsShown() then
            Cache.discoveriesBuilt = false
            return
        end
        
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
            if self.ignoreNextRemoveMessage == guid then
                self.ignoreNextRemoveMessage = nil
            else
                if Cache.discoveriesBuilt and not Cache.discoveriesBuilding then
                    updated = self:RemoveDiscoveryFromCache(guid)
                end
            end
        elseif action == "clear" then
            Cache.discoveriesBuilt = false
            Cache.discoveries = {}
            Cache.filteredResults = {}
            Cache.lastFilterState = nil
            Cache.uniqueValuesValid = false
            Cache.uniqueValuesContext = {}
            Cache.duplicateItems = {}
            
            self.pendingUpdatesCount = 0
            self:UpdateRefreshButton()
            self:RefreshData()
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
            self.pendingUpdatesCount = (self.pendingUpdatesCount or 0) + 1
            self:UpdateRefreshButton()
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
    
    if pTime then L:ProfileStop("Viewer:OnInitialize", pTime) end 
end

function Viewer:Show()
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not self.window then self:CreateWindow() end
    
    local t0 = time()
    VDebug("Show: start, currentFilter=" .. tostring(self.currentFilter) .. ", cacheBuilt=" .. tostring(Cache.discoveriesBuilt) .. ", building=" .. tostring(Cache.discoveriesBuilding))

    local Core = L:GetModule("Core", true)
    local isCoA = Core and Core.IsConfirmedCoARealm and Core:IsConfirmedCoARealm()
    
    self.currentFilter = self.currentFilter or "eq"
    if isCoA and self.currentFilter == "ms" then self.currentFilter = "eq" end
    
    if WorldMapFrame and WorldMapFrame.GetFrameLevel then
        local level = WorldMapFrame:GetFrameLevel() - 1
        if level < 1 then level = 1 end
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
    
    if pTime then L:ProfileStop("Viewer:Show", pTime) end 
end

function Viewer:Hide()
    if self.window then self.window:Hide() end
    self.pendingMapAreaID = nil
end

function Viewer:Toggle()
    if self.window and self.window:IsShown() then self:Hide() else self:Show() end
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
    OnCancel = function(self, data)
        if data and data.viewer then
            data.viewer:UpdateRows() 
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    showAlert = true,
}

function Viewer:Hide()
    if self.window then self.window:Hide() end
    self.pendingMapAreaID = nil
    
    
    Cache.discoveriesBuilding = false
    scanQueue = {}
    scanCursor = 0
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
    OnCancel = function(self, data)
        if data and data.viewer then
            data.viewer:UpdateRows() 
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