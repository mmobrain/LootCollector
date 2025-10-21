-- Viewer.lua
-- Provides a comprehensive interface for browsing, searching, filtering, and managing discoveries

local L = LootCollector
local Viewer = L:NewModule("Viewer")

-- Upvalues
local time = time

-- Window layout constants
local WINDOW_WIDTH = 900
local WINDOW_HEIGHT = 630
local ROW_HEIGHT = 20
local HEADER_HEIGHT = 25
local BUTTON_HEIGHT = 22
local BUTTON_WIDTH = 120
local CONTEXT_MENU_WIDTH = 200
local FRAME_LEVEL = 5

-- Grid layout constants
local GRID_LAYOUT = {
    -- Column widths
    NAME_WIDTH = 170,
    SLOT_WIDTH = 70,
    TYPE_WIDTH = 100,
    CLASS_WIDTH = 100,
    ZONE_WIDTH = 150,
    DATE_WIDTH = 100,
    FOUND_BY_WIDTH = 120,

    -- Spacing between columns
    COLUMN_SPACING = 5,
}

-- UI State
Viewer.window = nil
Viewer.scrollFrame = nil
Viewer.rows = {}
Viewer.currentFilter = "equipment" -- "equipment", "mystic_scrolls"
Viewer.searchTerm = ""
Viewer.sortColumn = "name"         -- "name", "slot", "type", "zone", "date", "foundBy"
Viewer.sortAscending = true
Viewer.pendingMapAreaID = nil

-- Pagination
Viewer.currentPage = 1
Viewer.itemsPerPage = 50
Viewer.totalItems = 0

-- Column filters
Viewer.columnFilters = {
    equipment = { slot = {}, type = {} },
    mystic_scrolls = { class = {} },
    zone = {},
    source = {},
    quality = {},
    looted = {},
    duplicates = false,
}

-- Utility functions
local _next = next
local _getmt, _setmt = getmetatable, setmetatable
local _rawlen = rawlen or function(x) return #x end

-- Creates a shallow copy of a table, preserving its metatable if present.
local function copy(t)
    local out = {}
    for k, v in _next, t do out[k] = v end
    local mt = _getmt(t)
    if mt then _setmt(out, mt) end
    return out
end

-- Returns the number of elements in a table.
local function size(t)
    if t[1] ~= nil then
        return _rawlen(t)
    end
    local n = 0
    for _ in _next, t do n = n + 1 end
    return n
end

-- Returns a new array containing all keys from the input table.
local function keys(t)
    local out = {}
    local i = 0
    for k in _next, t do
        i = i + 1
        out[i] = k
    end
    return out
end

-- Returns a new array containing all values from the input table.
local function values(t)
    local out = {}
    local i = 0
    for _, v in _next, t do
        i = i + 1
        out[i] = v
    end
    return out
end

-- Filters an array in-place based on a predicate function.
-- NOTE: Mutates the input array and assumes a dense 1..n sequence.
local function filter(array, predicate)
    local a = array
    local p = predicate
    local n = _rawlen(a)
    local wi = 1
    for i = 1, n do
        local v = a[i]
        if p(v, i) then
            if wi ~= i then a[wi] = v end
            wi = wi + 1
        end
    end
    for i = wi, n do a[i] = nil end
    return a
end

-- Forward declarations for cascading filter functions
local GetCascadedFilterContext, GetFilteredDatasetForUniqueValues, GetUniqueValues, GetItemInfoSafe

-- Unified caching system
local Cache = {
    -- Main discoveries cache with processed data
    discoveries = {},
    discoveriesBuilt = false,
    discoveriesBuilding = false,

    -- Item info cache (reusing L.itemInfoCache but with better structure)
    itemInfo = {},

    -- Character class detection cache
    characterClass = {},

    -- Worldforged detection cache
    worldforged = {},

    -- Zone name cache
    zoneNames = {},

    -- Unique values cache for filter dropdowns
    uniqueValues = {
        slot = {},
        type = {},
        class = {},
        zone = {}
    },
    uniqueValuesValid = false,

    -- Filtered results cache
    filteredResults = {},
    lastFilterState = nil,

    -- Cache for tracking duplicate itemIDs
    duplicateItems = {},
}

-- Retrieves item information safely, utilizing a unified cache.
local function GetItemInfoSafe(itemLink, itemID)
    if not itemLink then return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil end

    -- Check unified cache first
    if itemID and Cache.itemInfo[itemID] then
        return unpack(Cache.itemInfo[itemID])
    end

    local name, link, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, texture, sellPrice =
        GetItemInfo(itemLink)

    if itemID then
        Cache.itemInfo[itemID] = { name, link, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc,
            texture, sellPrice }
        -- Ensures backward compatibility with the old itemInfoCache.
        L.itemInfoCache[itemID] = Cache.itemInfo[itemID]
    end

    return name, link, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, texture, sellPrice
end

-- Retrieves the localized zone name for a given discovery, utilizing a unified cache.
local function GetLocalizedZoneName(discovery)
    if not discovery or not discovery.worldMapID or discovery.worldMapID <= 0 then
        return discovery and discovery.zone or "Unknown Zone"
    end

    local worldMapID = discovery.worldMapID
    if Cache.zoneNames[worldMapID] then
        return Cache.zoneNames[worldMapID]
    end

    local ZoneResolver = L:GetModule("ZoneResolver", true)
    local localizedZoneName = discovery.zone or "Unknown Zone"

    if ZoneResolver and ZoneResolver.isReady then
        local resolvedName = ZoneResolver:GetZoneNameByWorldMapID(worldMapID)
        if resolvedName and resolvedName ~= "" then
            localizedZoneName = resolvedName
        end
    end

    -- Stores the resolved zone name in the cache.
    Cache.zoneNames[worldMapID] = localizedZoneName
    return localizedZoneName
end

-- Generates a context table for cascading filters, excluding a specified column.
GetCascadedFilterContext = function(excludeColumn)
    local context = {
        currentFilter = Viewer.currentFilter,
        searchTerm = Viewer.searchTerm,
        excludeColumn = excludeColumn
    }

    -- Populates active column filters, excluding the column being generated.
    context.activeFilters = {}

    if Viewer.currentFilter == "equipment" then
        if excludeColumn ~= "slot" and size(Viewer.columnFilters.equipment.slot) > 0 then
            context.activeFilters.slot = Viewer.columnFilters.equipment.slot
        end
        if excludeColumn ~= "type" and size(Viewer.columnFilters.equipment.type) > 0 then
            context.activeFilters.type = Viewer.columnFilters.equipment.type
        end
    elseif Viewer.currentFilter == "mystic_scrolls" then
        if excludeColumn ~= "class" and size(Viewer.columnFilters.mystic_scrolls.class) > 0 then
            context.activeFilters.class = Viewer.columnFilters.mystic_scrolls.class
        end
    end

    -- Includes global zone filter if not the excluded column.
    if excludeColumn ~= "zone" and size(Viewer.columnFilters.zone) > 0 then
        context.activeFilters.zone = Viewer.columnFilters.zone
    end

    -- Includes global source filter if not the excluded column.
    if excludeColumn ~= "source" and size(Viewer.columnFilters.source) > 0 then
        context.activeFilters.source = Viewer.columnFilters.source
    end

    -- Includes global quality filter if not the excluded column.
    if excludeColumn ~= "quality" and size(Viewer.columnFilters.quality) > 0 then
        context.activeFilters.quality = Viewer.columnFilters.quality
    end

    -- Includes global looted filter if not the excluded column.
    if excludeColumn ~= "looted" and size(Viewer.columnFilters.looted) > 0 then
        context.activeFilters.looted = Viewer.columnFilters.looted
    end

    -- Includes global duplicates filter if not the excluded column.
    if excludeColumn ~= "duplicates" and Viewer.columnFilters.duplicates then
        context.activeFilters.duplicates = { enabled = true }
    end

    return context
end

-- Applies cascading filters to the discovery cache to generate a filtered dataset for unique value extraction.
GetFilteredDatasetForUniqueValues = function(context)
    local filteredData = filter(values(Cache.discoveries), function(data)
        -- Applies the main filter based on the current viewer filter setting.
        if context.currentFilter == "equipment" then
            if data.isMystic then return false end
        elseif context.currentFilter == "mystic_scrolls" then
            if not data.isMystic then return false end
        end

        -- Applies the search term filter to item names and localized zone names.
        if context.searchTerm and context.searchTerm ~= "" then
            local searchLower = string.lower(context.searchTerm)
            local nameMatch = string.find(string.lower(data.itemName or ""), searchLower, 1, true)
            local zoneName = GetLocalizedZoneName(data.discovery)
            local zoneMatch = string.find(string.lower(zoneName), searchLower, 1, true)
            if not (nameMatch or zoneMatch) then return false end
        end

        -- Applies active column filters for 'slot'.
        if context.activeFilters.slot then
            local slotValue = data.equipLoc and _G[data.equipLoc] or ""
            if not context.activeFilters.slot[slotValue] then return false end
        end

        -- Applies active column filters for 'type'.
        if context.activeFilters.type then
            local typeValue = data.itemSubType or ""
            if not context.activeFilters.type[typeValue] then return false end
        end

        -- Applies active column filters for 'class'.
        if context.activeFilters.class then
            local classValue = data.characterClass or ""
            if not context.activeFilters.class[classValue] then return false end
        end

        -- Applies active column filters for 'zone'.
        if context.activeFilters.zone then
            local zoneValue = GetLocalizedZoneName(data.discovery)
            if not context.activeFilters.zone[zoneValue] then return false end
        end

        -- Applies global source filter.
        if context.activeFilters.source then
            local source = data.discovery.source or "unknown"

            -- Converts source to user-friendly name.
            local sourceNames = {
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

            local sourceValue = sourceNames[source] or source
            if not context.activeFilters.source[sourceValue] then return false end
        end

        -- Applies global quality filter.
        if context.activeFilters.quality then
            local _, _, quality = GetItemInfoSafe(data.discovery.itemLink, data.discovery.itemID)
            if not quality then
                if not context.activeFilters.quality["Unknown"] then return false end
            else
                -- Converts quality number to user-friendly name.
                local qualityNames = {
                    [0] = "Poor",
                    [1] = "Common",
                    [2] = "Uncommon",
                    [3] = "Rare",
                    [4] = "Epic",
                    [5] = "Legendary",
                    [6] = "Artifact",
                    [7] = "Heirloom"
                }

                local qualityValue = qualityNames[quality] or ("Quality " .. tostring(quality))
                if not context.activeFilters.quality[qualityValue] then return false end
            end
        end

        -- Applies global looted filter.
        if context.activeFilters.looted then
            local lootedValue = Viewer:IsLootedByChar(data.guid) and "Looted" or "Not Looted"
            if not context.activeFilters.looted[lootedValue] then return false end
        end

        -- Applies global duplicates filter.
        if context.activeFilters.duplicates then
            -- Only shows discoveries with a duplicate count greater than one.
            if not Cache.duplicateItems[data.discovery.itemID] or Cache.duplicateItems[data.discovery.itemID] <= 1 then
                return false
            end
        end

        return true
    end)

    return filteredData
end

-- Generates unique values for a specified column, supporting cascading filters.
GetUniqueValues = function(column)
    -- Generates a cache key that includes the filter context.
    local context = GetCascadedFilterContext(column)
    local cacheKey = column .. ":" .. context.currentFilter .. ":" .. context.searchTerm

    -- Appends active filters to the cache key.
    local filterKeys = {}
    for filterType, filters in pairs(context.activeFilters) do
        if filterType == "duplicates" then
            -- Handles the duplicates filter as a special case.
            table.insert(filterKeys, filterType .. "=enabled")
        else
            local sortedKeys = keys(filters)
            table.sort(sortedKeys)
            table.insert(filterKeys, filterType .. "=" .. table.concat(sortedKeys, ","))
        end
    end
    if size(filterKeys) > 0 then
        cacheKey = cacheKey .. ":" .. table.concat(filterKeys, "|")
    end

    -- Checks if cached values exist for the current context.
    if not Cache.uniqueValuesContext then
        Cache.uniqueValuesContext = {}
    end

    if Cache.uniqueValuesContext[cacheKey] then
        return Cache.uniqueValuesContext[cacheKey]
    end

    -- Retrieves the filtered dataset for this context.
    local filteredDataset = GetFilteredDatasetForUniqueValues(context)
    local values = {}
    local seen = {}

    -- For the 'zone' column, deduplicates by WorldMapID and retrieves localized names.
    if column == "zone" then
        local ZoneResolver = L:GetModule("ZoneResolver", true)
        local zoneByWorldMapID = {}

        -- Collects zones by WorldMapID from the filtered dataset.
        for _, data in ipairs(filteredDataset) do
            local discovery = data.discovery
            if discovery and discovery.worldMapID and discovery.worldMapID > 0 then
                if not zoneByWorldMapID[discovery.worldMapID] then
                    zoneByWorldMapID[discovery.worldMapID] = {
                        worldMapID = discovery.worldMapID,
                        rawZone = discovery.zone or ""
                    }
                end
            end
        end

        -- Retrieves localized zone names.
        for worldMapID, zoneData in pairs(zoneByWorldMapID) do
            local localizedZoneName = GetLocalizedZoneName({ worldMapID = worldMapID, zone = zoneData.rawZone })

            if localizedZoneName and localizedZoneName ~= "" and not seen[localizedZoneName] then
                seen[localizedZoneName] = true
                table.insert(values, localizedZoneName)
            end
        end
    else
        -- Extracts values for other columns from the filtered dataset.
        local columnExtractor = {
            slot = function(data) return data.equipLoc and _G[data.equipLoc] or "" end,
            type = function(data) return data.itemSubType or "" end,
            class = function(data) return data.characterClass or "" end,
            source = function(data)
                local source = data.discovery.source or "unknown"

                -- Converts source to user-friendly name.
                local sourceNames = {
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

                return sourceNames[source] or source
            end,
            quality = function(data)
                local _, _, quality = GetItemInfoSafe(data.discovery.itemLink, data.discovery.itemID)
                if not quality then return "Unknown" end

                -- Converts quality number to user-friendly name.
                local qualityNames = {
                    [0] = "Poor",
                    [1] = "Common",
                    [2] = "Uncommon",
                    [3] = "Rare",
                    [4] = "Epic",
                    [5] = "Legendary",
                    [6] = "Artifact",
                    [7] = "Heirloom"
                }

                return qualityNames[quality] or ("Quality " .. tostring(quality))
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
                    table.insert(values, value)
                end
            end
        end
    end

    -- Sorts values based on column type.
    if column == "quality" then
        -- Sorts quality values by rarity order (highest to lowest).
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

        table.sort(values, function(a, b)
            local aOrder = qualityOrder[a] or 999
            local bOrder = qualityOrder[b] or 999
            return aOrder > bOrder -- Higher rarity first
        end)
    else
        -- Default alphabetical sorting for other columns.
        table.sort(values)
    end

    -- Caches the results with a context key.
    Cache.uniqueValuesContext[cacheKey] = values

    return values
end

-- Tooltip for class scanning.
local localClassScanTip = CreateFrame("GameTooltip", "LootCollectorClassScanTooltip", UIParent, "GameTooltipTemplate")
localClassScanTip:SetOwner(UIParent, "ANCHOR_NONE")

-- Initializes itemInfoCache for backward compatibility.
L.itemInfoCache = L.itemInfoCache or {}

-- Tooltip for IsWorldforged fallback.
local localWorldforgedScanTip = CreateFrame("GameTooltip", "LootCollectorViewerScanTip", UIParent, "GameTooltipTemplate")
localWorldforgedScanTip:SetOwner(UIParent, "ANCHOR_NONE")

-- Processing state for deferred full database scan.
local scanQueue = {}
local scanCursor = 0
local scanProgressCallback = nil


-- Status constants (matching Core.lua).
local STATUS_UNCONFIRMED = "UNCONFIRMED"
local STATUS_CONFIRMED = "CONFIRMED"
local STATUS_FADING = "FADING"
local STATUS_STALE = "STALE"

-- Detects if the discovery data has changed since last cache build.
local function HasDataChanged()
    if not L.db or not L.db.global or not L.db.global.discoveries then
        return false
    end
    
    -- Count the number of discoveries as a simple change detection mechanism
    local currentCount = 0
    for _ in pairs(L.db.global.discoveries) do
        currentCount = currentCount + 1
    end
    
    -- Store the count in the cache for comparison
    if not Cache.lastDiscoveryCount then
        Cache.lastDiscoveryCount = currentCount
        return true -- First time, consider it changed
    end
    
    local hasChanged = Cache.lastDiscoveryCount ~= currentCount
    if hasChanged then
        Cache.lastDiscoveryCount = currentCount
    end
    
    return hasChanged
end

-- Creates a reusable context menu.
local function CreateContextMenu(anchor, title, buttons, options)
    options = options or {}
    local menuWidth = options.width or CONTEXT_MENU_WIDTH
    local menuHeight = options.height or (20 + 5 + (25 * #buttons) + 20) -- title + separator + buttons + padding

    -- Closes any existing context menu.
    if Viewer.contextMenu then
        Viewer.contextMenu:Hide()
        Viewer.contextMenu = nil
    end

    -- Creates the context menu frame.
    local contextMenu = CreateFrame("Frame", "LootCollectorViewerContextMenu", Viewer.window)
    contextMenu:SetSize(menuWidth, menuHeight)

    -- Positions the context menu at the mouse cursor or anchor.
    if anchor.mouseX and anchor.mouseY then
        local uiScale = UIParent:GetEffectiveScale()
        contextMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            anchor.mouseX / uiScale, anchor.mouseY / uiScale)
    else
        -- Fallback to the right side of the anchor.
        contextMenu:SetPoint("LEFT", anchor, "RIGHT", 5, 0)
    end

    contextMenu:SetFrameStrata("TOOLTIP")
    contextMenu:EnableMouse(true)


    -- Sets the background for the context menu.
    contextMenu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    contextMenu:SetBackdropColor(0.05, 0.05, 0.05, 0.98)

    -- Sets the title of the context menu.
    local titleText = contextMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("TOPLEFT", 10, -10)
    titleText:SetText(title)
    titleText:SetTextColor(1, 1, 1)

    -- Draws a separator line.
    local separator = contextMenu:CreateTexture(nil, "OVERLAY")
    separator:SetSize(menuWidth - 20, 1)
    separator:SetPoint("TOPLEFT", 10, -30)
    separator:SetColorTexture(0.5, 0.5, 0.5, 0.8)

    -- Creates and positions the buttons within the context menu.
    local lastButton = nil
    for i, buttonData in ipairs(buttons) do
        local btn = CreateFrame("Button", nil, contextMenu, "UIPanelButtonTemplate")
        btn:SetSize(menuWidth - 20, 20) -- Uses full menu width minus padding.
        btn:SetFrameLevel(contextMenu:GetFrameLevel() + 5)
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

    -- Adds a mouse leave event to close the context menu with a slight delay.
    contextMenu:SetScript("OnLeave", function(self)
        -- Small delay to prevent accidental closing when moving between buttons.
        C_Timer.After(0.1, function()
            if Viewer.contextMenu and Viewer.contextMenu:IsShown() then
                local contextMenuMouseOver = Viewer.contextMenu:IsMouseOver()
                local anchorMouseOver = anchor:IsMouseOver()
                -- Checks if the mouse is still over the context menu or its parent.
                if not contextMenuMouseOver and not anchorMouseOver then
                    Viewer.contextMenu:Hide()
                    Viewer.contextMenu = nil
                end
            end
        end)
    end)

    contextMenu:Show()
    Viewer.contextMenu = contextMenu

    -- Closes the context menu when clicking outside its bounds.
    local function OnMouseDown(self, button)
        if Viewer.contextMenu and not Viewer.contextMenu:IsMouseOver() and not anchor:IsMouseOver() then
            Viewer.contextMenu:Hide()
            Viewer.contextMenu = nil
        end
    end

    UIParent:SetScript("OnMouseDown", OnMouseDown)

    -- Cleans up the OnMouseDown script when the context menu is hidden.
    contextMenu:SetScript("OnHide", function()
        UIParent:SetScript("OnMouseDown", nil)
    end)

    return contextMenu
end

-- Defines the maximum number of dropdown levels.
local MAX_LEVELS = 4
local lastAnchor = {}

-- Estimates the height of a dropdown list.
local function GetEstimatedListHeight(list)
    local h = list:GetHeight()
    if h and h > 0 then return h end

    -- Attempts to sum real button heights if available.
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

    -- Provides a fallback estimate for the list height.
    return (list.numButtons or 20) * (list.buttonHeight or 16)
end

-- Checks if the anchor is set to the cursor or mouse position.
local function IsCursorAnchor(anchor)
    if not anchor then return false end
    if type(anchor) == "string" then
        local a = anchor:lower()
        return a:find("cursor") or a:find("mouse")
    end
    return false
end

-- Repositions the dropdown list to ensure it stays on screen, preferring to drop downwards.
local function RepositionList(level, dropDownFrame, anchorTo)
    local list = _G["DropDownList" .. (tonumber(level) or 1)]
    if not list then return end

    local needed = GetEstimatedListHeight(list)
    local screenBottom = (UIParent and UIParent:GetBottom()) or 0

    if IsCursorAnchor(anchorTo) then
        -- Anchors the list to the cursor position, expanding downwards.
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        x = x / scale
        y = y / scale
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y - 10)
        list:SetClampedToScreen(true)
        return
    end

    -- Determines the anchor frame, prioritizing the provided dropDownFrame.
    local anchorFrame = nil
    if type(anchorTo) == "table" and anchorTo.GetBottom then
        anchorFrame = anchorTo
    elseif dropDownFrame and dropDownFrame.GetBottom then
        anchorFrame = dropDownFrame
    elseif type(anchorTo) == "string" then
        -- If anchor is a string token, use dropDownFrame if available, otherwise fallback to UIParent.
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

-- Helper functions for managing standard WoW dropdown menus.
local function ShowColumnFilterDropdown(column, anchor, values)
    -- Closes any existing dropdown.
    HideDropDownMenu(1)

    -- Checks if values are empty and attempts a fallback.
    if not values or #values == 0 then
        -- Attempts to retrieve values without cascading filters.
        local fallbackValues = {}
        if Cache.discoveriesBuilt then
            local seen = {}
            if column == "zone" then
                local ZoneResolver = L:GetModule("ZoneResolver", true)
                local zoneByWorldMapID = {}

                -- Collects zones by WorldMapID from the cached discoveries.
                for _, data in ipairs(Cache.discoveries) do
                    local discovery = data.discovery
                    if discovery and discovery.worldMapID and discovery.worldMapID > 0 then
                        if not zoneByWorldMapID[discovery.worldMapID] then
                            zoneByWorldMapID[discovery.worldMapID] = {
                                worldMapID = discovery.worldMapID,
                                rawZone = discovery.zone or ""
                            }
                        end
                    end
                end

                -- Retrieves localized zone names.
                for worldMapID, zoneData in pairs(zoneByWorldMapID) do
                    local localizedZoneName = GetLocalizedZoneName({ worldMapID = worldMapID, zone = zoneData.rawZone })
                    if localizedZoneName and localizedZoneName ~= "" and not seen[localizedZoneName] then
                        seen[localizedZoneName] = true
                        table.insert(fallbackValues, localizedZoneName)
                    end
                end
            else
                local columnExtractor = {
                    slot = function(data) return data.equipLoc and _G[data.equipLoc] or "" end,
                    type = function(data) return data.itemSubType or "" end,
                    class = function(data) return data.characterClass or "" end
                }

                local extractor = columnExtractor[column]
                if extractor then
                    for _, data in ipairs(Cache.discoveries) do
                        local value = extractor(data)
                        if value and value ~= "" and not seen[value] then
                            seen[value] = true
                            table.insert(fallbackValues, value)
                        end
                    end
                end
            end
            table.sort(fallbackValues)
        end

        values = fallbackValues
    end

    -- If no values are available after fallback, returns silently.
    if not values or #values == 0 then
        return
    end

    -- Creates the dropdown menu using the standard WoW UI system.
    local dropdown = CreateFrame("Frame", "LootCollectorViewerFilterDropdown", Viewer.window, "UIDropDownMenuTemplate")

    -- Initializes the dropdown menu.
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        -- Adds the "Clear All Filters" option.
        local clearAllInfo = {
            text = "Clear All Filters",
            notCheckable = true,
            func = function()
                if column == "zone" then
                    Viewer.columnFilters.zone = {}
                elseif column == "source" then
                    Viewer.columnFilters.source = {}
                elseif column == "quality" then
                    Viewer.columnFilters.quality = {}
                elseif column == "looted" then
                    Viewer.columnFilters.looted = {}
                else
                    Viewer.columnFilters[Viewer.currentFilter][column] = {}
                end
                Viewer.currentPage = 1
                -- Invalidates the filtered cache to force a refresh.
                Cache.filteredResults = {}
                Cache.lastFilterState = nil
                Cache.uniqueValuesValid = false
                Cache.uniqueValuesContext = {} -- Clears the cascading cache.
                Viewer:UpdateSortHeaders()
                Viewer:RefreshData()
                -- Updates the visibility of the Clear All button.
                Viewer:UpdateClearAllButton()
                -- Updates the states of the filter buttons.
                Viewer:UpdateFilterButtonStates()
                HideDropDownMenu(1)
            end
        }
        UIDropDownMenu_AddButton(clearAllInfo, level)

        -- Adds a separator.
        local separatorInfo = {
            text = "",
            notCheckable = true,
            disabled = true
        }
        UIDropDownMenu_AddButton(separatorInfo, level)

        -- Adds filter options with checkboxes.
        for _, value in ipairs(values) do
            -- Checks if the current value is selected.
            local isChecked = false
            if column == "zone" then
                isChecked = Viewer.columnFilters.zone[value] ~= nil
            elseif column == "source" then
                isChecked = Viewer.columnFilters.source[value] ~= nil
            elseif column == "quality" then
                isChecked = Viewer.columnFilters.quality[value] ~= nil
            elseif column == "looted" then
                isChecked = Viewer.columnFilters.looted[value] ~= nil
            else
                isChecked = Viewer.columnFilters[Viewer.currentFilter][column][value] ~= nil
            end

            local info = {
                text = value,
                checked = isChecked,
                func = function()
                    local currentValue = false
                    if column == "zone" then
                        currentValue = Viewer.columnFilters.zone[value]
                    elseif column == "source" then
                        currentValue = Viewer.columnFilters.source[value]
                    elseif column == "quality" then
                        currentValue = Viewer.columnFilters.quality[value]
                    elseif column == "looted" then
                        currentValue = Viewer.columnFilters.looted[value]
                    else
                        currentValue = Viewer.columnFilters[Viewer.currentFilter][column][value]
                    end

                    if currentValue then
                        if column == "zone" then
                            Viewer.columnFilters.zone[value] = nil
                        elseif column == "source" then
                            Viewer.columnFilters.source[value] = nil
                        elseif column == "quality" then
                            Viewer.columnFilters.quality[value] = nil
                        elseif column == "looted" then
                            Viewer.columnFilters.looted[value] = nil
                        else
                            Viewer.columnFilters[Viewer.currentFilter][column][value] = nil
                        end
                    else
                        if column == "zone" then
                            Viewer.columnFilters.zone[value] = true
                        elseif column == "source" then
                            Viewer.columnFilters.source[value] = true
                        elseif column == "quality" then
                            Viewer.columnFilters.quality[value] = true
                        elseif column == "looted" then
                            Viewer.columnFilters.looted[value] = true
                        else
                            Viewer.columnFilters[Viewer.currentFilter][column][value] = true
                        end
                    end

                    Viewer.currentPage = 1
                    -- Invalidates the filtered cache to force a refresh.
                    Cache.filteredResults = {}
                    Cache.lastFilterState = nil
                    Cache.uniqueValuesValid = false
                    Cache.uniqueValuesContext = {} -- Clears the cascading cache
                    Viewer:UpdateSortHeaders()
                    Viewer:RefreshData()
                    -- Updates the visibility of the Clear All button.
                    Viewer:UpdateClearAllButton()
                    -- Updates the states of the filter buttons.
                    Viewer:UpdateFilterButtonStates()
                    HideDropDownMenu(1)
                end
            }
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")

    -- Displays the dropdown menu.
    ToggleDropDownMenu(1, nil, dropdown, anchor, 0, 0)

    -- Adds a mouse leave event to close the dropdown with a slight delay.
    local dropdownList = _G["DropDownList1"]
    if dropdownList then
        dropdownList:SetScript("OnLeave", function(self)
            -- Small delay to prevent accidental closing.
            C_Timer.After(0.1, function()
                if dropdownList and dropdownList:IsShown() then
                    local dropdownMouseOver = dropdownList:IsMouseOver()
                    local anchorMouseOver = anchor:IsMouseOver()
                    -- Checks if the mouse is still over the dropdown or its anchor.
                    if not dropdownMouseOver and not anchorMouseOver then
                        HideDropDownMenu(1)
                    end
                end
            end)
        end)
    end
end

-- Retrieves the color associated with a given item quality.
local function GetQualityColor(quality)
    quality = tonumber(quality)
    if not quality then return 1, 1, 1 end
    if GetItemQualityColor then
        local r, g, b = GetItemQualityColor(quality)
        if r and g and b then return r, g, b end
    end
    if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local c = ITEM_QUALITY_COLORS[quality]
        return c.r or 1, c.g or 1, c.b or 1
    end
    return 1, 1, 1
end

-- Retrieves the color associated with a given discovery status.
local function GetStatusColor(status)
    if status == STATUS_CONFIRMED then
        return 0.2, 1.0, 0.2
    elseif status == STATUS_UNCONFIRMED then
        return 1.0, 0.75, 0.0
    elseif status == STATUS_FADING then
        return 1.0, 0.5, 0.0
    elseif status == STATUS_STALE then
        return 0.6, 0.6, 0.6
    else
        return 1.0, 1.0, 1.0
    end
end

-- Checks if an item name corresponds to a "Mystic Scroll".
local function IsMysticScroll(itemName)
    return itemName and string.find(itemName, "Mystic Scroll", 1, true) ~= nil
end

-- Detects the character class required for an item, utilizing a unified cache.
local function GetItemCharacterClass(itemLink, itemID)
    if not itemLink then return "" end
    if not itemID then return "" end

    -- Checks the unified cache first.
    if Cache.characterClass[itemID] ~= nil then
        return Cache.characterClass[itemID]
    end

    local characterClass = ""

    localClassScanTip:SetHyperlink(itemLink)
    -- Checks the second line of the tooltip by referencing the global text frame.
    local line2Text = _G["LootCollectorClassScanTooltipTextLeft2"]:GetText()
    if line2Text then
        characterClass = string.gsub(line2Text, "^%s*(.-)%s*$", "%1") -- Trims whitespace.
    end

    -- Caches the result in the unified cache.
    Cache.characterClass[itemID] = characterClass
    return characterClass
end

-- Detects if an item is "Worldforged", utilizing a unified cache.
local function IsWorldforged(itemLink)
    if not itemLink then return false end

    -- Checks the unified cache first.
    if Cache.worldforged[itemLink] ~= nil then
        return Cache.worldforged[itemLink]
    end

    -- Attempts to use Core's existing tooltip system.
    local Core = L:GetModule("Core", true)
    local isWorldforged = false

    if Core and Core._scanTip then
        -- Uses Core's existing tooltip.
        Core._scanTip:ClearLines()
        Core._scanTip:SetHyperlink(itemLink)

        for i = 2, 5 do
            local fs = _G["LootCollectorCoreScanTipTextLeft" .. i]
            local text = fs and fs:GetText()
            if text and string.find(string.lower(text), "worldforged", 1, true) then
                isWorldforged = true
                break
            end
        end
    else
        -- Fallback: creates a new tooltip if Core's is unavailable.
        if not localWorldforgedScanTip then
            localWorldforgedScanTip = CreateFrame("GameTooltip", "LootCollectorViewerScanTip", UIParent,
                "GameTooltipTemplate")
            localWorldforgedScanTip:SetOwner(UIParent, "ANCHOR_NONE")
        end

        localWorldforgedScanTip:ClearLines()
        localWorldforgedScanTip:SetHyperlink(itemLink)

        for i = 2, 5 do
            local fs = _G["LootCollectorViewerScanTipTextLeft" .. i]
            local text = fs and fs:GetText()
            if text and string.find(string.lower(text), "worldforged", 1, true) then
                isWorldforged = true
                break
            end
        end
    end

    -- Caches the result in the unified cache.
    Cache.worldforged[itemLink] = isWorldforged
    return isWorldforged
end

-- Builds the cache of all discoveries asynchronously.
function Viewer:UpdateAllDiscoveriesCache(onCompleteCallback)
    Cache.discoveriesBuilding = true
    Cache.discoveriesBuilt = false
    scanQueue = {}
    scanCursor = 0
    scanProgressCallback = onCompleteCallback
    Cache.uniqueValuesValid = false

    -- Clears the existing discoveries cache.
    Cache.discoveries = {}

    -- Clears the duplicate items cache.
    Cache.duplicateItems = {}

    -- Populates the scanQueue with all discoveries from the global database.
    for guid, discovery in pairs(L.db.global.discoveries or {}) do
        table.insert(scanQueue, { guid = guid, discovery = discovery })
    end

    -- Updates pagination to show loading state immediately
    if self.window and self.window:IsShown() then
        self:UpdatePagination()
    end

    self:ProcessScanQueueBatch()
end

function Viewer:ProcessScanQueueBatch()
    if not Cache.discoveriesBuilding or scanCursor >= #scanQueue then
        Cache.discoveriesBuilding = false
        Cache.discoveriesBuilt = true
        
        -- Updates pagination to show normal state when cache building completes
        if self.window and self.window:IsShown() then
            self:UpdatePagination()
        end
        
        if scanProgressCallback then
            scanProgressCallback()
            scanProgressCallback = nil
        end
        return
    end

    local batchSize = 50 -- Processes 50 items per batch for background scan.
    local processedCount = 0
    local Core = L:GetModule("Core", true)

    for i = 1, batchSize do
        scanCursor = scanCursor + 1
        if scanCursor > #scanQueue then break end

        local entry = scanQueue[scanCursor]
        local guid = entry.guid
        local discovery = entry.discovery

        -- Validates discovery data before processing.
        if discovery and type(discovery) == "table" and discovery.itemLink and discovery.itemLink ~= "" then
            local itemName = discovery.itemLink:match("%[(.+)%]") or ""
            if itemName and itemName ~= "" then
                local isMystic = IsMysticScroll(itemName)
                local isWorldforged = IsWorldforged(discovery.itemLink)
                local characterClass = GetItemCharacterClass(discovery.itemLink, discovery.itemID)

                -- Retrieves additional item information for Slot and Type.
                local name, _, _, _, _, itemTypeVal, itemSubTypeVal, _, equipLocVal = GetItemInfoSafe(discovery.itemLink,
                    discovery.itemID)

                table.insert(Cache.discoveries, {
                    guid = guid,
                    discovery = discovery,
                    itemName = itemName,
                    isMystic = isMystic,
                    isWorldforged = isWorldforged,
                    itemType = itemTypeVal,
                    itemSubType = itemSubTypeVal,
                    equipLoc = equipLocVal,
                    characterClass = characterClass,
                })
                processedCount = processedCount + 1

                -- Ensures the item is cached in Core for GetItemInfo.
                if Core and discovery.itemID and not Core:IsItemCached(discovery.itemID) then
                    Core:QueueItemForCaching(discovery.itemID)
                end

                -- Tracks duplicate items by itemID.
                if discovery.itemID then
                    Cache.duplicateItems[discovery.itemID] = (Cache.duplicateItems[discovery.itemID] or 0) + 1
                end
            end
        end
    end

    -- Defers next batch processing to prevent UI freezing.
    if scanCursor < #scanQueue then
        C_Timer.After(0.01, function() Viewer:ProcessScanQueueBatch() end)
    else
        self:ProcessScanQueueBatch() -- Final call to complete processing.
    end
end

-- Builds the cache of all discoveries synchronously for immediate use.
function Viewer:UpdateAllDiscoveriesCacheSync()
    if Cache.discoveriesBuilt or Cache.discoveriesBuilding then
        return
    end

    Cache.discoveriesBuilding = true
    Cache.discoveries = {}
    Cache.uniqueValuesValid = false

    -- Updates pagination to show loading state immediately
    if self.window and self.window:IsShown() then
        self:UpdatePagination()
    end

    -- Populates the cache with all discoveries from the global database.
    for guid, discovery in pairs(L.db.global.discoveries or {}) do
        if discovery and type(discovery) == "table" and discovery.itemLink and discovery.itemLink ~= "" then
            local itemName = discovery.itemLink:match("%[(.+)%]") or ""
            if itemName and itemName ~= "" then
                local isMystic = IsMysticScroll(itemName)
                local isWorldforged = IsWorldforged(discovery.itemLink)
                local characterClass = GetItemCharacterClass(discovery.itemLink, discovery.itemID)

                -- Retrieves additional item information for Slot and Type.
                local name, _, _, _, _, itemTypeVal, itemSubTypeVal, _, equipLocVal = GetItemInfoSafe(discovery.itemLink,
                    discovery.itemID)

                table.insert(Cache.discoveries, {
                    guid = guid,
                    discovery = discovery,
                    itemName = itemName,
                    isMystic = isMystic,
                    isWorldforged = isWorldforged,
                    itemType = itemTypeVal,
                    itemSubType = itemSubTypeVal,
                    equipLoc = equipLocVal,
                    characterClass = characterClass,
                })
            end
        end
    end

    -- Populates the duplicate items cache.
    for _, data in ipairs(Cache.discoveries) do
        if data.discovery.itemID then
            Cache.duplicateItems[data.discovery.itemID] = (Cache.duplicateItems[data.discovery.itemID] or 0) + 1
        end
    end

    Cache.discoveriesBuilt = true
    Cache.discoveriesBuilding = false
    
    -- Updates pagination to show normal state when cache building completes
    if self.window and self.window:IsShown() then
        self:UpdatePagination()
    end
end

-- Filters the cached discoveries based on current filter settings.
function Viewer:GetFilteredDiscoveries()
    -- Returns an empty array if the cache is currently being rebuilt.
    if Cache.discoveriesBuilding then
        return {}
    end

    -- Attempts to build the cache synchronously if it hasn't been built yet.
    if not Cache.discoveriesBuilt then
        -- Builds the cache synchronously for immediate display.
        self:UpdateAllDiscoveriesCacheSync()
    end

    -- Returns an empty array if the cache is still not built after a synchronous attempt.
    if not Cache.discoveriesBuilt then
        return {}
    end

    -- Generates a filter state hash for cache validation.
    local filterState = self:GetFilterStateHash()

    -- Returns cached results if the filter state matches.
    if Cache.lastFilterState == filterState and #Cache.filteredResults > 0 then
        return Cache.filteredResults
    end

    local currentFiltered = {}
    local discoveriesToFilter = Cache.discoveries

    -- Defines filter predicates.
    local filterPredicates = {
        -- Main filter predicate based on the current viewer filter.
        mainFilter = function(data)
            if self.currentFilter == "equipment" then
                return not data.isMystic
            elseif self.currentFilter == "mystic_scrolls" then
                return data.isMystic
            end
            return false
        end,

        -- Search filter predicate that matches item names or localized zone names.
        searchFilter = function(data)
            if self.searchTerm == "" then return true end

            local searchLower = string.lower(self.searchTerm)
            local nameMatch = string.find(string.lower(data.itemName or ""), searchLower, 1, true)

            -- Retrieves localized zone name for search.
            local zoneName = GetLocalizedZoneName(data.discovery)
            local zoneMatch = string.find(string.lower(zoneName), searchLower, 1, true)

            return nameMatch or zoneMatch
        end,

        -- Column filter predicates for tab-specific and global filters.
        columnFilters = {
            equipment = {
                slot = function(data)
                    if size(self.columnFilters.equipment.slot) == 0 then return true end
                    local slotValue = data.equipLoc and _G[data.equipLoc] or ""
                    return self.columnFilters.equipment.slot[slotValue] ~= nil
                end,
                type = function(data)
                    if size(self.columnFilters.equipment.type) == 0 then return true end
                    local typeValue = data.itemSubType or ""
                    return self.columnFilters.equipment.type[typeValue] ~= nil
                end
            },
            mystic_scrolls = {
                class = function(data)
                    if size(self.columnFilters.mystic_scrolls.class) == 0 then return true end
                    local classValue = data.characterClass or ""
                    return self.columnFilters.mystic_scrolls.class[classValue] ~= nil
                end
            },
            zone = function(data)
                if size(self.columnFilters.zone) == 0 then return true end
                local zoneValue = GetLocalizedZoneName(data.discovery)
                return self.columnFilters.zone[zoneValue] ~= nil
            end,
            source = function(data)
                if size(self.columnFilters.source) == 0 then return true end
                local source = data.discovery.source or "unknown"

                -- Converts source to user-friendly name.
                local sourceNames = {
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

                local sourceValue = sourceNames[source] or source
                return self.columnFilters.source[sourceValue] ~= nil
            end,
            quality = function(data)
                if size(self.columnFilters.quality) == 0 then return true end
                local _, _, quality = GetItemInfoSafe(data.discovery.itemLink, data.discovery.itemID)
                if not quality then
                    return self.columnFilters.quality["Unknown"] ~= nil
                end

                -- Converts quality number to user-friendly name.
                local qualityNames = {
                    [0] = "Poor",
                    [1] = "Common",
                    [2] = "Uncommon",
                    [3] = "Rare",
                    [4] = "Epic",
                    [5] = "Legendary",
                    [6] = "Artifact",
                    [7] = "Heirloom"
                }

                local qualityValue = qualityNames[quality] or ("Quality " .. tostring(quality))
                return self.columnFilters.quality[qualityValue] ~= nil
            end,
            looted = function(data)
                if size(self.columnFilters.looted) == 0 then return true end
                local lootedValue = self:IsLootedByChar(data.guid) and "Looted" or "Not Looted"
                return self.columnFilters.looted[lootedValue] ~= nil
            end,
            duplicates = function(data)
                if not self.columnFilters.duplicates then return true end
                -- Only shows discoveries with a duplicate count greater than one.
                return Cache.duplicateItems[data.discovery.itemID] and Cache.duplicateItems[data.discovery.itemID] > 1
            end
        }
    }

    -- Applies all filters.
    currentFiltered = filter(values(discoveriesToFilter), function(data)
        -- Applies main filter.
        if not filterPredicates.mainFilter(data) then return false end

        -- Applies search filter.
        if not filterPredicates.searchFilter(data) then return false end

        -- Applies tab-specific column filters.
        if self.currentFilter == "equipment" then
            if not filterPredicates.columnFilters.equipment.slot(data) then return false end
            if not filterPredicates.columnFilters.equipment.type(data) then return false end
        elseif self.currentFilter == "mystic_scrolls" then
            if not filterPredicates.columnFilters.mystic_scrolls.class(data) then return false end
        end

        -- Applies global zone filter.
        if not filterPredicates.columnFilters.zone(data) then return false end

        -- Applies global source filter.
        if not filterPredicates.columnFilters.source(data) then return false end

        -- Applies global quality filter.
        if not filterPredicates.columnFilters.quality(data) then return false end

        -- Applies global looted filter.
        if not filterPredicates.columnFilters.looted(data) then return false end

        -- Applies duplicates filter.
        if not filterPredicates.columnFilters.duplicates(data) then return false end

        return true
    end)

    -- Sorts filtered discoveries.
    table.sort(currentFiltered, function(a, b)
        if not a or not b then return false end
        if not a.discovery or not b.discovery then return false end

        local a_val, b_val

        if self.sortColumn == "name" then
            a_val = a.itemName or ""
            b_val = b.itemName or ""
        elseif self.sortColumn == "zone" then
            a_val = a.discovery.zone or ""
            b_val = b.discovery.zone or ""
        elseif self.sortColumn == "date" then
            a_val = tonumber(a.discovery.timestamp) or 0
            b_val = tonumber(b.discovery.timestamp) or 0
        elseif self.sortColumn == "slot" then
            a_val = a.equipLoc or ""
            b_val = b.equipLoc or ""
        elseif self.sortColumn == "type" then
            a_val = a.itemSubType or ""
            b_val = b.itemSubType or ""
        elseif self.sortColumn == "class" then
            a_val = a.characterClass or ""
            b_val = b.characterClass or ""
        elseif self.sortColumn == "foundBy" then
            a_val = a.discovery.foundBy_player or ""
            b_val = b.discovery.foundBy_player or ""
        else
            -- Defaults to sorting by GUID if sortColumn is unrecognized, to maintain a stable order.
            a_val = a.guid or ""
            b_val = b.guid or ""
        end

        if self.sortAscending then
            return a_val < b_val
        else
            return a_val > b_val
        end
    end)

    -- Caches results and updates filter state.
    Cache.filteredResults = currentFiltered
    Cache.lastFilterState = filterState

    return Cache.filteredResults
end

-- Helper function to create filter state hash for cache validation.
function Viewer:GetFilterStateHash()
    local hashParts = {
        self.currentFilter,
        self.searchTerm,
        self.sortColumn,
        tostring(self.sortAscending)
    }

    -- Adds column filters to hash.
    local filterEntries = {}
    for filterType, filters in pairs(self.columnFilters) do
        if type(filters) == "table" then
            for column, values in pairs(filters) do
                if type(values) == "table" and size(values) > 0 then
                    local sortedValues = keys(values)
                    table.sort(sortedValues)
                    table.insert(filterEntries, filterType .. ":" .. column .. ":" .. table.concat(sortedValues, ","))
                end
            end
        elseif filterType == "duplicates" and filters then
            -- Handles the duplicates filter as a special case.
            table.insert(filterEntries, "duplicates:true")
        end
    end

    -- Combines all hash parts.
    local hash = table.concat(hashParts, "|")
    if size(filterEntries) > 0 then
        hash = hash .. "|" .. table.concat(filterEntries, "|")
    end

    return hash
end

function Viewer:GetPaginatedDiscoveries()
    local allDiscoveries = self:GetFilteredDiscoveries()
    self.totalItems = #allDiscoveries



    -- Calculates pagination.
    local startIndex = (self.currentPage - 1) * self.itemsPerPage + 1
    local endIndex = math.min(startIndex + self.itemsPerPage - 1, self.totalItems)

    local pageDiscoveries = {}
    for i = startIndex, endIndex do
        if allDiscoveries[i] then
            table.insert(pageDiscoveries, allDiscoveries[i])
        end
    end

    return pageDiscoveries
end

function Viewer:GetTotalPages()
    return math.ceil(self.totalItems / self.itemsPerPage)
end

-- Helper function to temporarily remove window from UISpecialFrames
local function removeFromSpecialFrames(windowName)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == windowName then
            table.remove(UISpecialFrames, i)
            return true
        end
    end
    return false
end

-- Helper function to add window back to UISpecialFrames
local function addToSpecialFrames(windowName)
    -- Check if already in the list
    for i = 1, #UISpecialFrames do
        if UISpecialFrames[i] == windowName then
            return false -- Already in list
        end
    end
    table.insert(UISpecialFrames, windowName)
    return true
end

-- UI Creation functions
function Viewer:CreateWindow()
    if self.window then return end



    -- Main window
    local window = CreateFrame("Frame", "LootCollectorViewerWindow", UIParent)
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("LOW")
    window:SetFrameLevel(FRAME_LEVEL)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)

    -- Creates a hidden button for ESC handling
    local hiddenCloseBtn = CreateFrame("Button", "LootCollectorViewerHiddenClose", window)
    hiddenCloseBtn:SetScript("OnClick", function()
        -- Closes the context menu or dropdown first if they're open.
        if Viewer.contextMenu then
            Viewer.contextMenu:Hide()
            Viewer.contextMenu = nil
            return
        elseif Viewer.filterDropdown then
            Viewer.filterDropdown:Hide()
            Viewer.filterDropdown = nil
            return
        else
            -- Closes the main window.
            Viewer.allowManualClose = true
            window:Hide()
        end
    end)
    hiddenCloseBtn:Hide()

    -- Stores reference to close button for access from other parts of the window.
    window.closeBtn = hiddenCloseBtn

    -- Show/hide handlers for ESC key handling
    window:SetScript("OnShow", function(self)
        -- Adds the frame to UISpecialFrames so ESC key works
        table.insert(UISpecialFrames, self:GetName())
    end)

    window:SetScript("OnHide", function(self)
        -- Prevent closing during map operations unless manually closed
        if Viewer.inMapOperation and not Viewer.allowManualClose then
            if Viewer.window and not Viewer.window:IsShown() then
                Viewer.window:Show()
            end
            return
        end
        
        -- Check if this is an unwanted close during map operation
        if Viewer.restoreToSpecialFrames and Viewer.windowNameToRestore and not Viewer.allowManualClose then
            C_Timer.After(0.01, function()
                if Viewer.window and not Viewer.window:IsShown() then
                    Viewer.window:Show()
                end
            end)
            return
        end
        
        -- Normal close - remove from UISpecialFrames when hidden
        for i = #UISpecialFrames, 1, -1 do
            if UISpecialFrames[i] == self:GetName() then
                table.remove(UISpecialFrames, i)
                break
            end
        end
        
        -- Clear the manual close flag after successful close
        Viewer.allowManualClose = false
    end)

    -- Override the window's Hide method to prevent unwanted closes
    local originalHide = window.Hide
    window.Hide = function(self)
        if Viewer.inMapOperation and not Viewer.allowManualClose then
            return -- Don't actually hide during map operations unless manually closed
        end
        originalHide(self)
    end

    -- Hide the window initially (this will work since inMapOperation is not set yet)
    originalHide(window)

    -- Sets the background.
    window:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    window:SetBackdropColor(0.1, 0.1, 0.1, 0.95)

    -- Sets the title.
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("LootCollector Discoveries")

    -- Sets the close button
    local closeBtn = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function()
        Viewer.allowManualClose = true
        window:Hide()
    end)

    -- Sets up filter buttons.
    local equipmentBtn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    equipmentBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    equipmentBtn:SetPoint("TOPLEFT", 20, -50)
    equipmentBtn:SetText("Equipment")
    equipmentBtn:SetScript("OnClick", function()
        self.currentFilter = "equipment"
        self.currentPage = 1
        self:UpdateFilterButtons()
        self:UpdateSortHeaders()
        self:RefreshData()
    end)

    local mysticBtn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    mysticBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    mysticBtn:SetPoint("LEFT", equipmentBtn, "RIGHT", 10, 0)
    mysticBtn:SetText("Mystic Scrolls")
    mysticBtn:SetScript("OnClick", function()
        self.currentFilter = "mystic_scrolls"
        self.currentPage = 1
        self:UpdateFilterButtons()
        self:UpdateSortHeaders()
        self:RefreshData()
    end)

    -- Sets up the search box.
    local searchLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    searchLabel:SetPoint("TOPLEFT", equipmentBtn, "BOTTOMLEFT", 0, -10)
    searchLabel:SetText("Search:")

    local searchBox = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 5, 0)
    searchBox:SetAutoFocus(false) -- Prevents auto-focus to avoid keyboard input conflicts.

    -- Creates a clear button inside the search box.
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
    clearBtn:Hide() -- Hidden by default.

    -- Initializes auto-completion functionality.
    local autocompleteDropdown = nil
    local autocompleteSuggestions = {}
    local selectedSuggestionIndex = 0

    local function createAutocompleteDropdown()
        if autocompleteDropdown then
            return autocompleteDropdown
        end

        -- Creates the dropdown frame for auto-completion.
        autocompleteDropdown = CreateFrame("Frame", "LootCollectorSearchAutocomplete", Viewer.window)
        autocompleteDropdown:SetSize(200, 20)
        autocompleteDropdown:SetFrameStrata("TOOLTIP")
        autocompleteDropdown:SetFrameLevel(FRAME_LEVEL)
        autocompleteDropdown:Hide()

        -- Sets the background for the auto-complete dropdown.
        autocompleteDropdown:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        autocompleteDropdown:SetBackdropColor(0.1, 0.1, 0.1, 0.95)

        -- Creates a content frame directly within the dropdown for simplicity.
        local content = CreateFrame("Frame", nil, autocompleteDropdown)
        content:SetPoint("TOPLEFT", 5, -5)
        content:SetPoint("BOTTOMRIGHT", -5, 5)
        content:SetFrameLevel(autocompleteDropdown:GetFrameLevel() + 5)

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

        local textLower = string.lower(text)
        local candidates = {}
        local seen = {}

        if Cache.discoveriesBuilt then
            for _, data in ipairs(Cache.discoveries) do
                -- Adds item names.
                if data.itemName then
                    local nameLower = string.lower(data.itemName)
                    if string.sub(nameLower, 1, string.len(textLower)) == textLower then
                        if not seen[data.itemName] then
                            table.insert(candidates, data.itemName)
                            seen[data.itemName] = true
                        end
                    end
                end

                -- Adds zone names.
                local zoneName = GetLocalizedZoneName(data.discovery)
                if zoneName then
                    local zoneLower = string.lower(zoneName)
                    if string.sub(zoneLower, 1, string.len(textLower)) == textLower then
                        if not seen[zoneName] then
                            table.insert(candidates, zoneName)
                            seen[zoneName] = true
                        end
                    end
                end
            end
        end

        -- Sorts candidates alphabetically.
        table.sort(candidates)

        -- Limits suggestions to 10.
        local limitedCandidates = {}
        for i = 1, math.min(10, #candidates) do
            table.insert(limitedCandidates, candidates[i])
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

        -- Clears existing buttons.
        for _, button in ipairs(dropdown.buttons) do
            button:Hide()
        end
        dropdown.buttons = {}

        -- Creates suggestion buttons.
        local buttonHeight = 16
        local maxHeight = 160 -- Maximum 10 suggestions.
        local totalHeight = math.min(#candidates * buttonHeight, maxHeight)

        dropdown:SetSize(200, totalHeight + 10)

        for i, candidate in ipairs(candidates) do
            local button = CreateFrame("Button", nil, content)
            button:SetSize(190, buttonHeight)
            button:SetPoint("TOPLEFT", 5, -(i - 1) * buttonHeight)
            button:SetFrameLevel(content:GetFrameLevel() + 5)

            -- Sets button text.
            local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("LEFT", 5, 0)
            text:SetText(candidate)
            text:SetJustifyH("LEFT")
            text:SetTextColor(1, 1, 1) -- Ensures text is visible.

            -- Sets button background.
            button:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
            button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
            button:GetNormalTexture():SetVertexColor(0.1, 0.1, 0.1, 0.8)
            button:GetHighlightTexture():SetVertexColor(0.3, 0.3, 0.3, 0.8)

            -- Handles button click.
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
            table.insert(dropdown.buttons, button)
        end

        -- Positions dropdown below search box.
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
        -- Updates Clear All button visibility.
        Viewer:UpdateClearAllButton()

        -- Shows/hides clear button based on text content.
        if Viewer.searchTerm and Viewer.searchTerm ~= "" then
            clearBtn:Show()
            -- Shows auto-complete suggestions.
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
            -- Always applies the first suggestion immediately on Tab press.
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
                -- Always applies the first suggestion immediately on Tab press.
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
        -- Hides dropdown when search box loses focus.
        C_Timer.After(0.1, function()
            if not searchBox:HasFocus() then
                hideAutocompleteDropdown()
            end
        end)
    end)

    -- Group frame for additional filters, positioned to the right of the Mystic Scrolls button.
    local additionalFiltersFrame = CreateFrame("Frame", nil, window)
    additionalFiltersFrame:SetSize(430, 30)
    additionalFiltersFrame:SetPoint("TOPLEFT", mysticBtn, "TOPRIGHT", 20, 0)

    -- Background for the additional filters group.
    additionalFiltersFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    additionalFiltersFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.7)

    -- Label for filters.
    local filtersLabel = additionalFiltersFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    filtersLabel:SetPoint("LEFT", 10, 0)
    filtersLabel:SetText("Filters:")

    -- Button for the Source filter.
    local sourceFilterBtn = CreateFrame("Button", nil, additionalFiltersFrame, "UIPanelButtonTemplate")
    sourceFilterBtn:SetSize(80, BUTTON_HEIGHT)
    sourceFilterBtn:SetPoint("LEFT", filtersLabel, "RIGHT", 10, 0)
    sourceFilterBtn:SetText("Source")
    sourceFilterBtn:SetScript("OnClick", function(self, button)
        -- Activates filtering for the 'source' column.
        local values = GetUniqueValues("source")
        ShowColumnFilterDropdown("source", self, values)
    end)
    sourceFilterBtn:RegisterForClicks("LeftButtonUp")

    -- Button for the Quality filter.
    local qualityFilterBtn = CreateFrame("Button", nil, additionalFiltersFrame, "UIPanelButtonTemplate")
    qualityFilterBtn:SetSize(80, BUTTON_HEIGHT)
    qualityFilterBtn:SetPoint("LEFT", sourceFilterBtn, "RIGHT", 10, 0)
    qualityFilterBtn:SetText("Quality")
    qualityFilterBtn:SetScript("OnClick", function(self, button)
        -- Activates filtering for the 'quality' column.
        local values = GetUniqueValues("quality")
        ShowColumnFilterDropdown("quality", self, values)
    end)
    qualityFilterBtn:RegisterForClicks("LeftButtonUp")

    -- Button for the Looted Status filter.
    local lootedFilterBtn = CreateFrame("Button", nil, additionalFiltersFrame, "UIPanelButtonTemplate")
    lootedFilterBtn:SetSize(80, BUTTON_HEIGHT)
    lootedFilterBtn:SetPoint("LEFT", qualityFilterBtn, "RIGHT", 10, 0)
    lootedFilterBtn:SetText("Looted")
    lootedFilterBtn:SetScript("OnClick", function(self, button)
        -- Activates filtering for the 'looted' column.
        local values = GetUniqueValues("looted")
        ShowColumnFilterDropdown("looted", self, values)
    end)
    lootedFilterBtn:RegisterForClicks("LeftButtonUp")

    -- Button for the Duplicates filter.
    local duplicatesFilterBtn = CreateFrame("Button", nil, additionalFiltersFrame, "UIPanelButtonTemplate")
    duplicatesFilterBtn:SetSize(90, BUTTON_HEIGHT)
    duplicatesFilterBtn:SetPoint("LEFT", lootedFilterBtn, "RIGHT", 10, 0)
    duplicatesFilterBtn:SetText("Duplicates")
    duplicatesFilterBtn:SetScript("OnClick", function(self, button)
        Viewer.columnFilters.duplicates = not Viewer.columnFilters.duplicates
        Viewer.currentPage = 1
        -- Invalidates filtered cache to force refresh.
        Cache.filteredResults = {}
        Cache.lastFilterState = nil
        Cache.uniqueValuesValid = false
        Cache.uniqueValuesContext = {} -- Clears the cascading cache.
        Viewer:RefreshData()
        Viewer:UpdateClearAllButton()
        Viewer:UpdateFilterButtonStates()
    end)
    duplicatesFilterBtn:RegisterForClicks("LeftButtonUp")

    -- Frame for table headers.
    local headerFrame = CreateFrame("Frame", nil, window)
    headerFrame:SetSize(WINDOW_WIDTH - 40, HEADER_HEIGHT)
    headerFrame:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -15)
    headerFrame:SetFrameLevel(FRAME_LEVEL)

    -- Background for table headers.
    headerFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    headerFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

    -- Name column header.
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

    -- Slot column header (visible for Equipment only).
    local slotHeader = CreateFrame("Button", nil, headerFrame)
    slotHeader:SetSize(GRID_LAYOUT.SLOT_WIDTH, HEADER_HEIGHT)
    slotHeader:SetPoint("LEFT", nameHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    slotHeader:SetText("Slot")
    slotHeader:SetNormalFontObject("GameFontNormalSmall")
    slotHeader:SetHighlightFontObject("GameFontHighlightSmall")
    slotHeader:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            -- Right-click for filtering.
            local values = GetUniqueValues("slot")
            ShowColumnFilterDropdown("slot", self, values)
        else
            -- Left-click for sorting.
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
    slotHeader:Hide() -- Hidden by default.

    -- Type column header (visible for Equipment only).
    local typeHeader = CreateFrame("Button", nil, headerFrame)
    typeHeader:SetSize(GRID_LAYOUT.TYPE_WIDTH, HEADER_HEIGHT)
    typeHeader:SetPoint("LEFT", slotHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    typeHeader:SetText("Type")
    typeHeader:SetNormalFontObject("GameFontNormalSmall")
    typeHeader:SetHighlightFontObject("GameFontHighlightSmall")
    typeHeader:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            -- Right-click for filtering.
            local values = GetUniqueValues("type")
            ShowColumnFilterDropdown("type", self, values)
        else
            -- Left-click for sorting.
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
    typeHeader:Hide() -- Hidden by default.

    -- Class column header (visible for Mystic Scrolls only).
    local classHeader = CreateFrame("Button", nil, headerFrame)
    classHeader:SetSize(GRID_LAYOUT.CLASS_WIDTH, HEADER_HEIGHT)
    classHeader:SetPoint("LEFT", nameHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    classHeader:SetText("Class")
    classHeader:SetNormalFontObject("GameFontNormalSmall")
    classHeader:SetHighlightFontObject("GameFontHighlightSmall")
    classHeader:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            -- Right-click for filtering.
            local values = GetUniqueValues("class")
            ShowColumnFilterDropdown("class", self, values)
        else
            -- Left-click for sorting.
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
    classHeader:Hide() -- Hidden by default.

    -- Zone column header.
    local zoneHeader = CreateFrame("Button", nil, headerFrame)
    zoneHeader:SetSize(GRID_LAYOUT.ZONE_WIDTH, HEADER_HEIGHT)
    zoneHeader:SetPoint("LEFT", typeHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    zoneHeader:SetText("Zone")
    zoneHeader:SetNormalFontObject("GameFontNormalSmall")
    zoneHeader:SetHighlightFontObject("GameFontHighlightSmall")
    zoneHeader:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            -- Right-click for filtering.
            local values = GetUniqueValues("zone")
            ShowColumnFilterDropdown("zone", self, values)
        else
            -- Left-click for sorting.
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

    -- Date column header.
    local dateHeader = CreateFrame("Button", nil, headerFrame)
    dateHeader:SetSize(GRID_LAYOUT.DATE_WIDTH, HEADER_HEIGHT)
    dateHeader:SetPoint("LEFT", zoneHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    dateHeader:SetText("Discovery Date")
    dateHeader:SetNormalFontObject("GameFontNormalSmall")
    dateHeader:SetHighlightFontObject("GameFontHighlightSmall")
    dateHeader:SetScript("OnClick", function()
        if Viewer.sortColumn == "date" then
            Viewer.sortAscending = not Viewer.sortAscending
        else
            Viewer.sortColumn = "date"
            Viewer.sortAscending = true
        end
        Viewer.currentPage = 1
        Viewer:UpdateSortHeaders()
        Viewer:RefreshData()
    end)

    -- "Found By" column header.
    local foundByHeader = CreateFrame("Button", nil, headerFrame)
    foundByHeader:SetSize(GRID_LAYOUT.FOUND_BY_WIDTH, HEADER_HEIGHT)
    foundByHeader:SetPoint("LEFT", dateHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
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


    -- Actions label, visible when no filters are active.
    local actionsLabel = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    actionsLabel:SetPoint("RIGHT", -5, 0)
    actionsLabel:SetText("Actions")

    -- Button to clear all filters.
    local clearAllBtn = CreateFrame("Button", nil, headerFrame, "UIPanelButtonTemplate")
    clearAllBtn:SetSize(100, 20)
    clearAllBtn:SetPoint("RIGHT", -5, 0)
    clearAllBtn:SetText("Clear All Filters")
    clearAllBtn:SetScript("OnClick", function()
        -- Clears all column filters.
        Viewer.columnFilters.zone = {}
        Viewer.columnFilters.equipment.slot = {}
        Viewer.columnFilters.equipment.type = {}
        Viewer.columnFilters.mystic_scrolls.class = {}
        Viewer.columnFilters.source = {}
        Viewer.columnFilters.quality = {}
        Viewer.columnFilters.looted = {}
        Viewer.columnFilters.duplicates = false -- Clears duplicates filter.

        -- Clears the search term.
        Viewer.searchTerm = ""
        searchBox:SetText("")

        -- Resets to the first page.
        Viewer.currentPage = 1

        -- Invalidates all caches to force a refresh.
        Cache.filteredResults = {}
        Cache.lastFilterState = nil
        Cache.uniqueValuesValid = false
        Cache.uniqueValuesContext = {}

        -- Updates the UI.
        Viewer:UpdateSortHeaders()
        Viewer:RefreshData()

        -- Updates button visibility after clearing filters.
        Viewer:UpdateClearAllButton()
        -- Updates the states of the filter buttons.
        Viewer:UpdateFilterButtonStates()
    end)

    -- Checks if any filters are currently active.
    function Viewer:HasActiveFilters()
        -- Checks the search term.
        if self.searchTerm and self.searchTerm ~= "" then
            return true
        end

        -- Checks zone filters.
        if size(self.columnFilters.zone) > 0 then
            return true
        end

        -- Checks equipment filters.
        if size(self.columnFilters.equipment.slot) > 0 or size(self.columnFilters.equipment.type) > 0 then
            return true
        end

        -- Checks mystic scroll filters.
        if size(self.columnFilters.mystic_scrolls.class) > 0 then
            return true
        end

        -- Checks source filters.
        if size(self.columnFilters.source) > 0 then
            return true
        end

        -- Checks quality filters.
        if size(self.columnFilters.quality) > 0 then
            return true
        end

        -- Checks looted filters.
        if size(self.columnFilters.looted) > 0 then
            return true
        end

        -- Checks the duplicates filter.
        if self.columnFilters.duplicates then
            return true
        end

        return false
    end

    -- Updates the "Clear All" button's visibility and text.
    function Viewer:UpdateClearAllButton()
        if not self.clearAllBtn or not self.actionsLabel then
            return -- UI elements not created yet.
        end

        if self:HasActiveFilters() then
            self.clearAllBtn:Show()
            self.clearAllBtn:SetText("Clear All Filters")
        else
            self.clearAllBtn:Hide()
            -- Shows the Actions label when no filters are active.
            self.actionsLabel:Show()
        end
    end

    -- Updates the visual states of the filter buttons.
    function Viewer:UpdateFilterButtonStates()
        if not self.sourceFilterBtn or not self.qualityFilterBtn or not self.lootedFilterBtn then
            return -- UI elements not created yet.
        end

        -- Helper function to set button text color.
        local function setButtonTextColor(button, r, g, b)
            local fontString = button:GetFontString()
            if fontString then
                fontString:SetTextColor(r, g, b)
            end
        end

        -- Updates the Source filter button.
        local sourceActive = size(self.columnFilters.source) > 0
        if sourceActive then
            setButtonTextColor(self.sourceFilterBtn, 1, 0.8, 0.2) -- Orange for active.
            self.sourceFilterBtn:SetText("Source [F]")
        else
            setButtonTextColor(self.sourceFilterBtn, 1, 1, 1) -- White for inactive.
            self.sourceFilterBtn:SetText("Source")
        end

        -- Updates the Quality filter button.
        local qualityActive = size(self.columnFilters.quality) > 0
        if qualityActive then
            setButtonTextColor(self.qualityFilterBtn, 1, 0.8, 0.2) -- Orange for active.
            self.qualityFilterBtn:SetText("Quality [F]")
        else
            setButtonTextColor(self.qualityFilterBtn, 1, 1, 1) -- White for inactive.
            self.qualityFilterBtn:SetText("Quality")
        end

        -- Updates the Looted filter button.
        local lootedActive = size(self.columnFilters.looted) > 0
        if lootedActive then
            setButtonTextColor(self.lootedFilterBtn, 1, 0.8, 0.2) -- Orange for active.
            self.lootedFilterBtn:SetText("Looted [F]")
        else
            setButtonTextColor(self.lootedFilterBtn, 1, 1, 1) -- White for inactive.
            self.lootedFilterBtn:SetText("Looted")
        end

        -- Updates the Duplicates filter button.
        if self.duplicatesFilterBtn then
            local duplicatesActive = self.columnFilters.duplicates
            if duplicatesActive then
                setButtonTextColor(self.duplicatesFilterBtn, 1, 0.8, 0.2) -- Orange for active.
                self.duplicatesFilterBtn:SetText("Duplicates [F]")
            else
                setButtonTextColor(self.duplicatesFilterBtn, 1, 1, 1) -- White for inactive.
                self.duplicatesFilterBtn:SetText("Duplicates")
            end
        end
    end

    -- Pagination controls for navigating through discovery pages.
    local paginationFrame = CreateFrame("Frame", nil, window)
    paginationFrame:SetSize(WINDOW_WIDTH - 32, 32)
    paginationFrame:SetPoint("BOTTOM", 0, 20)

    -- Adds background to the pagination section for visual separation.
    paginationFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    paginationFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)

    -- Displays current page information.
    local pageInfo = paginationFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pageInfo:SetPoint("CENTER", 10, 0)
    pageInfo:SetText("Page 1 of 1")

    -- Button to navigate to the previous page.
    local prevBtn = CreateFrame("Button", nil, paginationFrame, "UIPanelButtonTemplate")
    prevBtn:SetSize(80, BUTTON_HEIGHT)
    prevBtn:SetPoint("LEFT", 5, 0)
    prevBtn:SetText("Previous")
    prevBtn:SetScript("OnClick", function()
        if self.currentPage > 1 then
            self.currentPage = self.currentPage - 1
            self:UpdatePagination()
            self:UpdateRows()
        end
    end)

    -- Button to navigate to the next page.
    local nextBtn = CreateFrame("Button", nil, paginationFrame, "UIPanelButtonTemplate")
    nextBtn:SetSize(80, BUTTON_HEIGHT)
    nextBtn:SetPoint("RIGHT", -10, 0)
    nextBtn:SetText("Next")
    nextBtn:SetScript("OnClick", function()
        local totalPages = self:GetTotalPages()
        if self.currentPage < totalPages then
            self.currentPage = self.currentPage + 1
            self:UpdatePagination()
            self:UpdateRows()
        end
    end)

    -- Selector for items per page.
    local itemsLabel = paginationFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemsLabel:SetPoint("LEFT", prevBtn, "RIGHT", 20, 0)
    itemsLabel:SetText("Items per page:")

    local items25Btn = CreateFrame("Button", nil, paginationFrame, "UIPanelButtonTemplate")
    items25Btn:SetSize(30, BUTTON_HEIGHT)
    items25Btn:SetPoint("LEFT", itemsLabel, "RIGHT", 5, 0)
    items25Btn:SetText("25")
    items25Btn:SetScript("OnClick", function()
        local oldItemsPerPage = Viewer.itemsPerPage
        Viewer.itemsPerPage = 25
        -- Calculates which page to show to maintain the same logical position.
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
    items50Btn:SetScript("OnClick", function()
        local oldItemsPerPage = Viewer.itemsPerPage
        Viewer.itemsPerPage = 50
        -- Calculates which page to show to maintain the same logical position.
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
    items100Btn:SetScript("OnClick", function()
        local oldItemsPerPage = Viewer.itemsPerPage
        Viewer.itemsPerPage = 100
        -- Calculates which page to show to maintain the same logical position.
        local currentItemIndex = (Viewer.currentPage - 1) * oldItemsPerPage + 1
        Viewer.currentPage = math.ceil(currentItemIndex / Viewer.itemsPerPage)
        Viewer:UpdateItemsPerPageButtons()
        Viewer:UpdatePagination()
        Viewer:RefreshData()
    end)

    -- Scroll frame for table content, necessary when items per page exceed visible rows.
    local scrollFrame = CreateFrame("ScrollFrame", nil, window, "FauxScrollFrameTemplate")
    scrollFrame:SetSize(WINDOW_WIDTH - 40, WINDOW_HEIGHT - 200)
    scrollFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -5)
    scrollFrame:SetFrameLevel(FRAME_LEVEL)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() Viewer:UpdateRows() end)
    end)

    -- Stores UI element references.
    self.window = window
    self.scrollFrame = scrollFrame
    self.equipmentBtn = equipmentBtn
    self.mysticBtn = mysticBtn
    self.searchBox = searchBox
    self.searchClearBtn = clearBtn
    self.additionalFiltersFrame = additionalFiltersFrame
    self.sourceFilterBtn = sourceFilterBtn
    self.qualityFilterBtn = qualityFilterBtn
    self.lootedFilterBtn = lootedFilterBtn
    self.nameHeader = nameHeader
    self.slotHeader = slotHeader
    self.typeHeader = typeHeader
    self.classHeader = classHeader
    self.zoneHeader = zoneHeader
    self.dateHeader = dateHeader
    self.foundByHeader = foundByHeader
    self.clearAllBtn = clearAllBtn
    self.actionsLabel = actionsLabel
    self.pageInfo = pageInfo
    self.prevBtn = prevBtn
    self.nextBtn = nextBtn
    self.items25Btn = items25Btn
    self.items50Btn = items50Btn
    self.items100Btn = items100Btn
    self.duplicatesFilterBtn = duplicatesFilterBtn -- Stores reference to the duplicates filter button.

    -- Creates initial table rows.
    self:CreateRows()

    -- Sets the initial filter.
    self.currentFilter = "equipment"
    self:UpdateFilterButtons()
    self:UpdateSortHeaders()
    self:UpdateItemsPerPageButtons()
    self:UpdateFilterButtonStates()
end

function Viewer:CreateRows()
    local visibleRows = math.floor((WINDOW_HEIGHT - 200) / ROW_HEIGHT)

    for i = 1, visibleRows do
        local row = CreateFrame("Frame", nil, self.scrollFrame:GetParent())
        row:SetSize(WINDOW_WIDTH - 40, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", self.scrollFrame, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetFrameLevel(FRAME_LEVEL)

        -- Name column, with tooltip support.
        local nameFrame = CreateFrame("Frame", nil, row)
        nameFrame:SetSize(GRID_LAYOUT.NAME_WIDTH, ROW_HEIGHT)
        nameFrame:SetPoint("LEFT", 5, 0)
        nameFrame:EnableMouse(true)

        local nameText = nameFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", 0, 0)
        nameText:SetSize(GRID_LAYOUT.NAME_WIDTH, ROW_HEIGHT)
        nameText:SetJustifyH("LEFT")

        -- Sets up tooltip functionality.
        nameFrame:SetScript("OnEnter", function(self)
            if self.discoveryData and self.discoveryData.discovery.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 20, 10)
                GameTooltip:SetHyperlink(self.discoveryData.discovery.itemLink)
                GameTooltip:Show()
            end
        end)

        nameFrame:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        nameFrame:SetScript("OnMouseUp", function(self, button)
            if not self.discoveryData then return end

            local isCtrlDown = IsControlKeyDown()

            if button == "LeftButton" then
                if isCtrlDown then
                    -- Ctrl + Left Click: Links item in chat.
                    self:LinkItemToChat()
                end
            elseif button == "RightButton" then
                if isCtrlDown then
                    -- Ctrl +  Right Click: Pastes zone name and coordinates into chat.
                    self:PasteLocationToChat()
                else
                    -- Regular right click: Shows context menu.
                    self:ShowContextMenu()
                end
            end
        end)

        -- Stores mouse position for context menu positioning.
        nameFrame:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" then
                local x, y = GetCursorPosition()
                self.mouseX = x
                self.mouseY = y
            end
        end)

        -- Slot column, visible for Equipment only.
        local slotText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slotText:SetPoint("LEFT", nameFrame, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        slotText:SetSize(GRID_LAYOUT.SLOT_WIDTH, ROW_HEIGHT)
        slotText:SetJustifyH("LEFT")
        slotText:Hide()

        -- Type column, visible for Equipment only.
        local typeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        typeText:SetPoint("LEFT", slotText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        typeText:SetSize(GRID_LAYOUT.TYPE_WIDTH, ROW_HEIGHT)
        typeText:SetJustifyH("LEFT")
        typeText:Hide()

        -- Class column, visible for Mystic Scrolls only.
        local classText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        classText:SetPoint("LEFT", nameFrame, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        classText:SetSize(GRID_LAYOUT.CLASS_WIDTH, ROW_HEIGHT)
        classText:SetJustifyH("LEFT")
        classText:Hide()

        -- Zone column.
        local zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        zoneText:SetPoint("LEFT", typeText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        zoneText:SetSize(GRID_LAYOUT.ZONE_WIDTH, ROW_HEIGHT)
        zoneText:SetJustifyH("LEFT")

        -- Date column.
        local dateText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dateText:SetPoint("LEFT", zoneText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        dateText:SetSize(GRID_LAYOUT.DATE_WIDTH, ROW_HEIGHT)
        dateText:SetJustifyH("LEFT")

        -- "Found By" column, an interactive frame for context menu.
        local foundByFrame = CreateFrame("Frame", nil, row)
        foundByFrame:SetSize(GRID_LAYOUT.FOUND_BY_WIDTH, ROW_HEIGHT)
        foundByFrame:SetPoint("LEFT", dateText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        foundByFrame:EnableMouse(true)

        local foundByText = foundByFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        foundByText:SetPoint("LEFT", 2, 0)
        foundByText:SetSize(GRID_LAYOUT.FOUND_BY_WIDTH - 4, ROW_HEIGHT)
        foundByText:SetJustifyH("LEFT")

        -- Adds a right-click context menu for the "Found By" column.
        foundByFrame:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" and self.discoveryData then
                -- Stores mouse position for context menu positioning.
                local x, y = GetCursorPosition()
                self.mouseX = x
                self.mouseY = y
                self:ShowFoundByContextMenu()
            end
        end)

        -- Adds context menu method to foundByFrame.
        foundByFrame.ShowFoundByContextMenu = function(self)
            if not self.discoveryData or not self.discoveryData.discovery.foundBy_player then
                return
            end

            local playerName = self.discoveryData.discovery.foundBy_player

            local buttons = {
                {
                    text = "Delete all from " .. playerName,
                    onClick = function()
                        Viewer:ConfirmDeleteAllFromPlayer(playerName)
                    end
                }
            }

            CreateContextMenu(self, "Player: " .. playerName, buttons)
        end

        -- Displays a button.
        local showBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        showBtn:SetSize(50, ROW_HEIGHT - 2)
        showBtn:SetPoint("RIGHT", -70, 0) -- Positions to the left of the delete button.
        showBtn:SetText("Show")
        showBtn:SetScript("OnClick", function()
            if row.discoveryData then
                self:ShowOnMap(row.discoveryData)
            end
        end)

        -- Delete button.
        local deleteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        deleteBtn:SetSize(60, ROW_HEIGHT - 2)
        deleteBtn:SetPoint("RIGHT", -5, 0)
        deleteBtn:SetText("Delete")
        deleteBtn:SetScript("OnClick", function()
            if row.discoveryData then
                self:ConfirmDelete(row.discoveryData)
            end
        end)

        -- Adds a context menu method to nameFrame.
        nameFrame.ShowContextMenu = function(self)
            if not self.discoveryData then return end

            -- Checks if this discovery is currently looted.
            local isLooted = Viewer:IsLootedByChar(self.discoveryData.guid)

            local buttons = {
                {
                    text = "Show",
                    onClick = function()
                        Viewer:ShowOnMap(self.discoveryData)
                    end
                },
                {
                    text = isLooted and "Set as unlooted" or "Set as looted",
                    onClick = function()
                        Viewer:ToggleLootedState(self.discoveryData.guid, self.discoveryData)
                    end
                },
                {
                    text = "Delete",
                    onClick = function()
                        Viewer:ConfirmDelete(self.discoveryData)
                    end
                }
            }

            CreateContextMenu(self, self.discoveryData.itemName or "Unknown Item", buttons)
        end

        -- Adds new click action methods to nameFrame.
        nameFrame.LinkItemToChat = function(self)
            if not self.discoveryData or not self.discoveryData.discovery then return end

            local discovery = self.discoveryData.discovery
            local itemID = discovery.itemID
            local itemLink = discovery.itemLink

            -- Validate itemID exists
            if not itemID then
                -- Try to extract from itemLink if available
                if itemLink and type(itemLink) == "string" then
                    itemID = itemLink:match("item:(%d+)")
                    itemID = itemID and tonumber(itemID)
                end
            end

            if not itemID then return end

            -- Send item link reliably (tries cache first, primes if needed)
            local function SendItemLinkReliable(itemID, chatType, language)
                chatType = chatType or "SAY"
                language = language or nil
                local name, link = GetItemInfo(itemID)
                if link then
                    if ChatEdit_InsertLink then
                        ChatEdit_InsertLink(link)
                    elseif ChatFrame1EditBox:IsVisible() then
                        ChatFrame1EditBox:Insert(link)
                    else
                        ChatFrame_OpenChat(link)
                    end
                    return
                end
                -- prime cache
                GameTooltip:Hide()
                GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
                GameTooltip:SetHyperlink("item:"..tostring(itemID))
                local start = GetTime()
                local f = CreateFrame("Frame")
                f:SetScript("OnUpdate", function(self)
                    local n, l = GetItemInfo(itemID)
                    if l then
                        if ChatEdit_InsertLink then
                            ChatEdit_InsertLink(l)
                        elseif ChatFrame1EditBox:IsVisible() then
                            ChatFrame1EditBox:Insert(l)
                        else
                            ChatFrame_OpenChat(l)
                        end
                        self:SetScript("OnUpdate", nil)
                        self:Hide()
                        return
                    end
                    if GetTime() - start > 3 then
                        -- fallback to safe constructed link (no error)
                        local fallback = "|cffffffff|Hitem:"..itemID..":0:0:0:0:0:0:0|h["..(n or ("Item:"..itemID)).."]|h|r"
                        if ChatEdit_InsertLink then
                            ChatEdit_InsertLink(fallback)
                        elseif ChatFrame1EditBox:IsVisible() then
                            ChatFrame1EditBox:Insert(fallback)
                        else
                            ChatFrame_OpenChat(fallback)
                        end
                        self:SetScript("OnUpdate", nil)
                        self:Hide()
                    end
                end)
            end

            -- Use the reliable function
            SendItemLinkReliable(itemID)
        end

        nameFrame.PasteLocationToChat = function(self)
            if not self.discoveryData or not self.discoveryData.discovery then return end

            local discovery = self.discoveryData.discovery
            local coords = discovery.coords

            if not coords or not coords.x or not coords.y then
                return -- No coordinates available.
            end

            -- Gets localized zone name.
            local zoneName = GetLocalizedZoneName(discovery)

            -- Formats coordinates with 2 decimal places for display.
            -- Converts from normalized coordinates (0.0-1.0) to percentage (0-100).
            local x = math.floor(coords.x * 10000 + 0.5) / 100
            local y = math.floor(coords.y * 10000 + 0.5) / 100

            -- Creates location string in format "Zone Name [X.XX, Y.YY]".
            local locationString = string.format("%s [%.2f, %.2f]", zoneName, x, y)

            -- Uses ChatEdit_InsertLink for WoW 3.3.5 compatibility.
            if ChatEdit_InsertLink then
                ChatEdit_InsertLink(locationString)
            elseif ChatFrame1EditBox:IsVisible() then
                ChatFrame1EditBox:Insert(locationString)
            else
                -- Opens chat with the location string.
                ChatFrame_OpenChat(locationString)
            end
        end

        -- Stores references to row elements.
        row.nameFrame = nameFrame
        row.nameText = nameText
        row.slotText = slotText
        row.typeText = typeText
        row.classText = classText
        row.zoneText = zoneText
        row.dateText = dateText
        row.foundByFrame = foundByFrame
        row.foundByText = foundByText
        row.showBtn = showBtn
        row.deleteBtn = deleteBtn

        table.insert(self.rows, row)
    end
end

function Viewer:UpdateFilterButtons()
    -- Helper function to set button text color.
    local function setButtonTextColor(button, r, g, b)
        local fontString = button:GetFontString()
        if fontString then
            fontString:SetTextColor(r, g, b)
        end
    end



    -- Resets all button text colors.
    setButtonTextColor(self.equipmentBtn, 1, 1, 1)
    setButtonTextColor(self.mysticBtn, 1, 1, 1)

    -- Highlights the selected button with a distinct text color.
    if self.currentFilter == "equipment" then
        setButtonTextColor(self.equipmentBtn, 0.2, 0.8, 1)
    elseif self.currentFilter == "mystic_scrolls" then
        setButtonTextColor(self.mysticBtn, 0.2, 0.8, 1)
    end
end

function Viewer:UpdateSortHeaders()
    -- Helper function to set button text color.
    local function setButtonTextColor(button, r, g, b)
        local fontString = button:GetFontString()
        if fontString then
            fontString:SetTextColor(r, g, b)
        end
    end



    -- Resets all header text colors.
    setButtonTextColor(self.nameHeader, 1, 1, 1)
    setButtonTextColor(self.slotHeader, 1, 1, 1)
    setButtonTextColor(self.typeHeader, 1, 1, 1)
    setButtonTextColor(self.classHeader, 1, 1, 1)
    setButtonTextColor(self.zoneHeader, 1, 1, 1)
    setButtonTextColor(self.dateHeader, 1, 1, 1)
    setButtonTextColor(self.foundByHeader, 1, 1, 1)

    -- Sets conditional visibility for headers based on the current filter.
    local isEquipmentView = (self.currentFilter == "equipment")
    local isMysticScrollsView = (self.currentFilter == "mystic_scrolls")
    self.slotHeader:SetShown(isEquipmentView)
    self.typeHeader:SetShown(isEquipmentView)
    self.classHeader:SetShown(isMysticScrollsView)

    -- Adjusts positions and sizes based on visibility using master controls.
    if isEquipmentView then
        -- Equipment view: Name + Slot + Type + Zone + Date + Found By.
        self.nameHeader:SetSize(GRID_LAYOUT.NAME_WIDTH, HEADER_HEIGHT)
        self.slotHeader:SetPoint("LEFT", self.nameHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        self.typeHeader:SetPoint("LEFT", self.slotHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        self.zoneHeader:SetPoint("LEFT", self.typeHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        self.dateHeader:SetPoint("LEFT", self.zoneHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        self.foundByHeader:SetPoint("LEFT", self.dateHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    elseif isMysticScrollsView then
        -- Mystic Scrolls view: Name + Class + Zone + Date + Found By.
        self.nameHeader:SetSize(GRID_LAYOUT.NAME_WIDTH, HEADER_HEIGHT)
        self.classHeader:SetPoint("LEFT", self.nameHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        self.zoneHeader:SetPoint("LEFT", self.classHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        self.dateHeader:SetPoint("LEFT", self.zoneHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        self.foundByHeader:SetPoint("LEFT", self.dateHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    else
        -- Default view: Name + Zone + Date + Found By (wider name column).
        self.nameHeader:SetSize(GRID_LAYOUT.NAME_WIDTH + 100, HEADER_HEIGHT) -- Wider for default view.
        self.zoneHeader:SetPoint("LEFT", self.nameHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        self.dateHeader:SetPoint("LEFT", self.zoneHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
        self.foundByHeader:SetPoint("LEFT", self.dateHeader, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
    end

    -- Highlights the selected header and adds a sort indicator.
    local sortIndicator = self.sortAscending and " ↑" or " ↓"

    if self.sortColumn == "name" then
        setButtonTextColor(self.nameHeader, 0.2, 0.8, 1)
        self.nameHeader:SetText("Name" .. sortIndicator)
    else
        self.nameHeader:SetText("Name")
    end

    if self.sortColumn == "slot" and isEquipmentView then
        setButtonTextColor(self.slotHeader, 0.2, 0.8, 1)
        local filterIndicator = next(self.columnFilters.equipment.slot) and " [F]" or ""
        self.slotHeader:SetText("Slot" .. sortIndicator .. filterIndicator)
    else
        local filterIndicator = next(self.columnFilters.equipment.slot) and " [F]" or ""
        if filterIndicator ~= "" then
            setButtonTextColor(self.slotHeader, 1, 0.8, 0.2) -- Orange color for filtered columns.
        end
        self.slotHeader:SetText("Slot" .. filterIndicator)
    end

    if self.sortColumn == "type" and isEquipmentView then
        setButtonTextColor(self.typeHeader, 0.2, 0.8, 1)
        local filterIndicator = next(self.columnFilters.equipment.type) and " [F]" or ""
        self.typeHeader:SetText("Type" .. sortIndicator .. filterIndicator)
    else
        local filterIndicator = next(self.columnFilters.equipment.type) and " [F]" or ""
        if filterIndicator ~= "" then
            setButtonTextColor(self.typeHeader, 1, 0.8, 0.2) -- Orange color for filtered columns.
        end
        self.typeHeader:SetText("Type" .. filterIndicator)
    end

    if self.sortColumn == "class" and isMysticScrollsView then
        setButtonTextColor(self.classHeader, 0.2, 0.8, 1)
        local filterIndicator = next(self.columnFilters.mystic_scrolls.class) and " [F]" or ""
        self.classHeader:SetText("Class" .. sortIndicator .. filterIndicator)
    else
        local filterIndicator = next(self.columnFilters.mystic_scrolls.class) and " [F]" or ""
        if filterIndicator ~= "" then
            setButtonTextColor(self.classHeader, 1, 0.8, 0.2) -- Orange color for filtered columns.
        end
        self.classHeader:SetText("Class" .. filterIndicator)
    end

    if self.sortColumn == "zone" then
        setButtonTextColor(self.zoneHeader, 0.2, 0.8, 1)
        local filterIndicator = next(self.columnFilters.zone) and " [F]" or ""
        self.zoneHeader:SetText("Zone" .. sortIndicator .. filterIndicator)
    else
        local filterIndicator = next(self.columnFilters.zone) and " [F]" or ""
        if filterIndicator ~= "" then
            setButtonTextColor(self.zoneHeader, 1, 0.8, 0.2) -- Orange color for filtered columns.
        end
        self.zoneHeader:SetText("Zone" .. filterIndicator)
    end

    if self.sortColumn == "date" then
        setButtonTextColor(self.dateHeader, 0.2, 0.8, 1)
        self.dateHeader:SetText("Discovery Date" .. sortIndicator)
    else
        self.dateHeader:SetText("Discovery Date")
    end

    if self.sortColumn == "foundBy" then
        setButtonTextColor(self.foundByHeader, 0.2, 0.8, 1)
        self.foundByHeader:SetText("Found By" .. sortIndicator)
    else
        self.foundByHeader:SetText("Found By")
    end
end

function Viewer:UpdatePagination()
    local totalPages = self:GetTotalPages()
    local totalItems = self.totalItems

    -- Updates page information.
    if self.pageInfo then
        -- Shows loading indicator when cache is building
        if Cache.discoveriesBuilding then
            self.pageInfo:SetText("Loading...")
        else
            self.pageInfo:SetText(string.format("Page %d of %d (%d total items)", self.currentPage, totalPages, totalItems))
        end
    end

    -- Updates button states for pagination controls.
    if self.prevBtn then
        -- Disables buttons during loading
        self.prevBtn:SetEnabled(not Cache.discoveriesBuilding and self.currentPage > 1)
    end
    if self.nextBtn then
        -- Disables buttons during loading
        self.nextBtn:SetEnabled(not Cache.discoveriesBuilding and self.currentPage < totalPages)
    end
end

function Viewer:UpdateItemsPerPageButtons()
    -- Helper function to set button text color.
    local function setButtonTextColor(button, r, g, b)
        local fontString = button:GetFontString()
        if fontString then
            fontString:SetTextColor(r, g, b)
        end
    end



    -- Resets all button text colors.
    if self.items25Btn then setButtonTextColor(self.items25Btn, 1, 1, 1) end
    if self.items50Btn then setButtonTextColor(self.items50Btn, 1, 1, 1) end
    if self.items100Btn then setButtonTextColor(self.items100Btn, 1, 1, 1) end

    -- Highlights selected button.
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



    -- Updates pagination information.
    self:UpdatePagination()

    local isEquipmentView = (self.currentFilter == "equipment")
    local isMysticScrollsView = (self.currentFilter == "mystic_scrolls")

    -- Updates the scroll frame.
    FauxScrollFrame_Update(self.scrollFrame, numDiscoveries, numRows, ROW_HEIGHT)

    -- Shows rows for the current page with scrolling support.
    for i = 1, numRows do
        local row = self.rows[i]
        local offset = FauxScrollFrame_GetOffset(self.scrollFrame)

        if i + offset <= numDiscoveries then
            local data = discoveries[i + offset]
            local discovery = data.discovery

            -- Stores discovery data for the delete button and tooltip.
            row.discoveryData = data
            row.nameFrame.discoveryData = data
            row.foundByFrame.discoveryData = data

            -- Checks if this discovery is looted by the current character.
            local isLooted = self:IsLootedByChar(data.guid)
            local alpha = isLooted and 0.5 or 1.0 -- Reduces alpha for looted items.

            -- Sets item name with quality color.
            local itemName = data.itemName
            local _, _, quality, _, _, itemType, itemSubType, _, equipLoc, _, _ = GetItemInfoSafe(discovery.itemLink,
                discovery.itemID)
            if quality then
                local r, g, b = GetQualityColor(quality)
                itemName = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, itemName)
            end

            row.nameText:SetText(itemName)
            row.nameText:SetAlpha(alpha)

            -- Sets conditional visibility for columns.
            row.slotText:SetShown(isEquipmentView)
            row.typeText:SetShown(isEquipmentView)
            row.classText:SetShown(isMysticScrollsView)

            if isEquipmentView then
                -- Adjusts column positions and widths for Equipment view using master controls.
                row.nameFrame:SetSize(GRID_LAYOUT.NAME_WIDTH, ROW_HEIGHT)
                row.nameText:SetSize(GRID_LAYOUT.NAME_WIDTH, ROW_HEIGHT)
                row.slotText:SetPoint("LEFT", row.nameFrame, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
                row.typeText:SetPoint("LEFT", row.slotText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
                row.zoneText:SetPoint("LEFT", row.typeText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
                row.dateText:SetPoint("LEFT", row.zoneText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
                row.foundByFrame:SetPoint("LEFT", row.dateText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)

                row.slotText:SetText(equipLoc and _G[equipLoc] or "") -- Localized slot name.
                row.slotText:SetAlpha(alpha)
                row.typeText:SetText(itemSubType or "")
                row.typeText:SetAlpha(alpha)
            elseif isMysticScrollsView then
                -- Adjusts column positions and widths for Mystic Scrolls view using master controls.
                row.nameFrame:SetSize(GRID_LAYOUT.NAME_WIDTH, ROW_HEIGHT)
                row.nameText:SetSize(GRID_LAYOUT.NAME_WIDTH, ROW_HEIGHT)
                row.classText:SetPoint("LEFT", row.nameFrame, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
                row.zoneText:SetPoint("LEFT", row.classText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
                row.dateText:SetPoint("LEFT", row.zoneText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
                row.foundByFrame:SetPoint("LEFT", row.dateText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)

                row.classText:SetText(data.characterClass or "")
                row.classText:SetAlpha(alpha)
            else
                -- Restores default column positions and widths for other views using master controls.
                row.nameFrame:SetSize(GRID_LAYOUT.NAME_WIDTH + 100, ROW_HEIGHT) -- Wider for default view.
                row.nameText:SetSize(GRID_LAYOUT.NAME_WIDTH + 100, ROW_HEIGHT)
                row.zoneText:SetPoint("LEFT", row.nameFrame, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
                row.dateText:SetPoint("LEFT", row.zoneText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
                row.foundByFrame:SetPoint("LEFT", row.dateText, "RIGHT", GRID_LAYOUT.COLUMN_SPACING, 0)
            end

            -- Displays zone information.
            local zoneText = GetLocalizedZoneName(discovery)
            if discovery.worldMapID and discovery.worldMapID > 0 then
                zoneText = zoneText .. string.format(" (ID: %d)", discovery.worldMapID)
            end
            row.zoneText:SetText(zoneText)
            row.zoneText:SetAlpha(alpha)

            -- Displays date information.
            local timestamp = tonumber(discovery.timestamp) or 0
            local dateText = timestamp > 0 and date("%Y-%m-%d %H:%M", timestamp) or "Unknown"
            row.dateText:SetText(dateText)
            row.dateText:SetAlpha(alpha)

            -- Displays "Found By" player information.
            local foundByText = discovery.foundBy_player or "Unknown"
            row.foundByText:SetText(foundByText)
            row.foundByText:SetAlpha(alpha)

            row:Show()
        else
            row:Hide()
            row.discoveryData = nil
            row.nameFrame.discoveryData = nil
            row.foundByFrame.discoveryData = nil
        end
    end
end

-- Refreshes the data in the viewer.
function Viewer:RefreshData()
    if not self.window or not self.window:IsShown() then return end

    -- Only rebuilds cache if data has actually changed or if it hasn't been built yet.
    local now = time()
    local dataHasChanged = HasDataChanged()
    local shouldRebuildCache = not Cache.discoveriesBuilt or dataHasChanged

    if shouldRebuildCache and not Cache.discoveriesBuilding then
        self:UpdateAllDiscoveriesCache(function()
            self:GetFilteredDiscoveries() -- Filters/sorts after cache is built.
            self:UpdateRows()
        end)
    elseif Cache.discoveriesBuilt then
        -- If cache is built, just filters/sorts and updates rows.
        self:GetFilteredDiscoveries()
        self:UpdateRows()
    end
end

-- Checks if a discovery is looted by the current character.
function Viewer:IsLootedByChar(guid)
    if not guid or not (L.db and L.db.char and L.db.char.looted) then
        return false
    end
    return L.db.char.looted[guid] and true or false
end

-- Toggles the looted state for a discovery.
function Viewer:ToggleLootedState(guid, discoveryData)
    if not guid or not (L.db and L.db.char) then
        return false
    end

    L.db.char.looted = L.db.char.looted or {}
    local isCurrentlyLooted = self:IsLootedByChar(guid)

    if isCurrentlyLooted then
        -- Sets as unlooted.
        L.db.char.looted[guid] = nil
        print(string.format("|cff00ff00LootCollector:|r Marked '%s' as unlooted.",
            discoveryData.itemName or "Unknown Item"))
    else
        -- Sets as looted.
        L.db.char.looted[guid] = time()
        print(string.format("|cff00ff00LootCollector:|r Marked '%s' as looted.", discoveryData.itemName or "Unknown Item"))
    end

    -- Updates the map if it's shown.
    local Map = L:GetModule("Map", true)
    if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
        Map:Update()
    end

    -- Refreshes the viewer data.
    self:RefreshData()

    return not isCurrentlyLooted -- Returns the new state.
end

-- Clears all internal caches and resets filter states.
function Viewer:ClearCaches()
    -- Iterates through cache keys to reset relevant data structures.
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

    -- Resets column filters to their default states.
    local defaultFilters = {
        equipment = { slot = {}, type = {} },
        mystic_scrolls = { class = {} },
        zone = {},
        source = {},
        quality = {},
        looted = {},
        duplicates = false -- Resets the duplicates filter.
    }
    self.columnFilters = copy(defaultFilters)

    -- Clears the duplicate items cache.
    Cache.duplicateItems = {}
    
    -- Resets data change tracking
    Cache.lastDiscoveryCount = nil

    -- Maintains backward compatibility for item info cache.
    L.itemInfoCache = {}
end

-- Manages a single discovery within the cache, either adding a new one or updating an existing entry.
function Viewer:AddDiscoveryToCache(guid, discovery)
    if not guid or not discovery or not discovery.itemLink then
        return false
    end

    -- Only proceeds if the cache is already built and not currently undergoing a build process.
    if not Cache.discoveriesBuilt or Cache.discoveriesBuilding then
        return false
    end

    local itemName = discovery.itemLink:match("%[(.+)%]") or ""
    if not itemName or itemName == "" then
        return false
    end

    -- Checks if this discovery already exists in the cache.
    for _, data in ipairs(Cache.discoveries) do
        if data.guid == guid then
            -- Updates an existing entry.
            data.discovery = discovery
            data.itemName = itemName
            data.isMystic = IsMysticScroll(itemName)
            data.isWorldforged = IsWorldforged(discovery.itemLink)
            data.characterClass = GetItemCharacterClass(discovery.itemLink, discovery.itemID)

            -- Retrieves additional item information.
            local name, _, _, _, _, itemTypeVal, itemSubTypeVal, _, equipLocVal = GetItemInfoSafe(discovery.itemLink,
                discovery.itemID)
            data.itemType = itemTypeVal
            data.itemSubType = itemSubTypeVal
            data.equipLoc = equipLocVal

            -- Invalidates the filtered cache to force a refresh.
            Cache.filteredResults = {}
            Cache.lastFilterState = nil
            Cache.uniqueValuesValid = false
            Cache.uniqueValuesContext = {} -- Clears the cascading cache.
            return true
        end
    end

    -- Adds a new discovery to the cache.
    local isMystic = IsMysticScroll(itemName)
    local isWorldforged = IsWorldforged(discovery.itemLink)
    local characterClass = GetItemCharacterClass(discovery.itemLink, discovery.itemID)

    -- Retrieves additional item information.
    local name, _, _, _, _, itemTypeVal, itemSubTypeVal, _, equipLocVal = GetItemInfoSafe(discovery.itemLink,
        discovery.itemID)

    table.insert(Cache.discoveries, {
        guid = guid,
        discovery = discovery,
        itemName = itemName,
        isMystic = isMystic,
        isWorldforged = isWorldforged,
        itemType = itemTypeVal,
        itemSubType = itemSubTypeVal,
        equipLoc = equipLocVal,
        characterClass = characterClass,
    })

    -- Invalidates the filtered cache to force a refresh.
    Cache.filteredResults = {}
    Cache.lastFilterState = nil
    Cache.uniqueValuesValid = false

    return true
end

-- Removes a discovery from the cache based on its GUID.
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
            -- Uses swap-pop to efficiently remove the element: moves the last element into position `i` and nils the last slot.
            discoveries[i] = discoveries[n]
            discoveries[n] = nil

            -- Invalidates dependent caches to ensure data consistency.
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
    local zone = discoveryData.discovery.zone or "Unknown Zone"



    StaticPopup_Show("LOOTCOLLECTOR_VIEWER_DELETE",
        string.format("Delete discovery for '%s' in '%s'?", itemName, zone),
        nil,
        { guid = discoveryData.guid, viewer = self }
    )
end

function Viewer:DeleteDiscovery(guid)
    local Core = L:GetModule("Core", true)
    if Core and Core.RemoveDiscovery then
        Core:RemoveDiscovery(guid)
    end
end

-- Finds all discoveries associated with a specific player.
function Viewer:FindDiscoveriesByPlayer(playerName)
    if not playerName or playerName == "" then
        return {}
    end

    local discoveriesByPlayer = {}

    -- Searches through the global database to find matching discoveries.
    for guid, discovery in pairs(L.db.global.discoveries or {}) do
        if discovery and discovery.foundBy_player == playerName then
            table.insert(discoveriesByPlayer, {
                guid = guid,
                discovery = discovery
            })
        end
    end

    return discoveriesByPlayer
end

-- Deletes all discoveries associated with a specific player.
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
        
        -- Rebuilds the cache and refreshes the UI.
        if self.window and self.window:IsShown() then
            self:UpdateAllDiscoveriesCache(function()
                self:GetFilteredDiscoveries()
                self:UpdateRows()
            end)
        end
    end

    return deletedCount
end

-- Provides a confirmation dialog for deleting all discoveries from a player.
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
    local discovery = discoveryData.discovery
    if not discovery or not discovery.worldMapID then
        print("LootCollector Viewer: No map data available for this discovery.")
        return
    end

    -- Temporarily remove window from UISpecialFrames to prevent auto-closing when World Map opens
    local windowName = self.window and self.window:GetName()
    local wasInSpecialFrames = false
    if windowName then
        wasInSpecialFrames = removeFromSpecialFrames(windowName)
    end

    -- Clears any existing overlay pin before displaying a new one.
    if WorldMapFrame.viewerOverlayPin then
        WorldMapFrame.viewerOverlayPin:Hide()
    end
    Viewer.currentOverlayTarget = nil

    -- Opens the World Map to the correct area.
    local success, errorMsg = self:OpenWorldMapToArea(discovery.worldMapID)
    if not success then
        print(string.format("LootCollector Viewer: Failed to open map - %s", errorMsg or "unknown error"))
        -- Restore window to UISpecialFrames if map opening failed
        if wasInSpecialFrames and windowName then
            addToSpecialFrames(windowName)
        end
        return
    end

    -- Finds the existing map pin and attaches the overlay to it.
    if discovery.coords and discovery.coords.x and discovery.coords.y then
        -- Finds the existing map pin for this discovery.
        local Map = L:GetModule("Map", true)
        local targetPin = nil

        if Map and Map.pins then
            for _, pin in ipairs(Map.pins) do
                if pin.discovery and pin.discovery.guid == discovery.guid then
                    targetPin = pin
                    break
                end
            end
        end

        if targetPin and targetPin:IsShown() then
            -- Creates an overlay frame attached to the existing pin.
            if not WorldMapFrame.viewerOverlayPin then
                WorldMapFrame.viewerOverlayPin = CreateFrame("Frame", "LootCollectorViewerOverlayPin", targetPin)
                WorldMapFrame.viewerOverlayPin:SetSize(32, 32)
                WorldMapFrame.viewerOverlayPin:SetFrameStrata("TOOLTIP")
                WorldMapFrame.viewerOverlayPin:SetFrameLevel(targetPin:GetFrameLevel() + 10)

                -- Creates a red square background.
                WorldMapFrame.viewerOverlayPin.backgroundTexture = WorldMapFrame.viewerOverlayPin:CreateTexture(nil,
                    "BACKGROUND")
                WorldMapFrame.viewerOverlayPin.backgroundTexture:SetAllPoints()
                WorldMapFrame.viewerOverlayPin.backgroundTexture:SetTexture("Interface\\Buttons\\WHITE8X8")
                WorldMapFrame.viewerOverlayPin.backgroundTexture:SetVertexColor(1, 0, 0, 0.8)

                -- Disables mouse events to allow the original pin to handle tooltips.
                WorldMapFrame.viewerOverlayPin:EnableMouse(false)
            else
                -- Reparent the overlay to the new target pin
                WorldMapFrame.viewerOverlayPin:SetParent(targetPin)
                WorldMapFrame.viewerOverlayPin:SetFrameLevel(targetPin:GetFrameLevel() + 10)
            end

            -- Positions the overlay centered on the existing pin.
            WorldMapFrame.viewerOverlayPin:ClearAllPoints()
            WorldMapFrame.viewerOverlayPin:SetPoint("CENTER", targetPin, "CENTER", 0, 0)
            WorldMapFrame.viewerOverlayPin:Show()

            -- Stores discovery data for the tooltip and tracks current overlay target.
            WorldMapFrame.viewerOverlayPin.discoveryData = discoveryData
            Viewer.currentOverlayTarget = discovery.guid
        else
            -- Fallback: retries after a short delay in case pins haven't loaded yet.
            C_Timer.After(0.5, function()
                local Map = L:GetModule("Map", true)
                local targetPin = nil

                if Map and Map.pins then
                    for _, pin in ipairs(Map.pins) do
                        if pin.discovery and pin.discovery.guid == discovery.guid then
                            targetPin = pin
                            break
                        end
                    end
                end

                if targetPin and targetPin:IsShown() then
                    -- Creates an overlay frame attached to the existing pin.
                    if not WorldMapFrame.viewerOverlayPin then
                        WorldMapFrame.viewerOverlayPin = CreateFrame("Frame", "LootCollectorViewerOverlayPin", targetPin)
                        WorldMapFrame.viewerOverlayPin:SetSize(32, 32)
                        WorldMapFrame.viewerOverlayPin:SetFrameStrata("TOOLTIP")
                        WorldMapFrame.viewerOverlayPin:SetFrameLevel(targetPin:GetFrameLevel() + 10)

                        -- Creates a red square background.
                        WorldMapFrame.viewerOverlayPin.backgroundTexture = WorldMapFrame.viewerOverlayPin:CreateTexture(
                            nil, "BACKGROUND")
                        WorldMapFrame.viewerOverlayPin.backgroundTexture:SetAllPoints()
                        WorldMapFrame.viewerOverlayPin.backgroundTexture:SetTexture("Interface\\Buttons\\WHITE8X8")
                        WorldMapFrame.viewerOverlayPin.backgroundTexture:SetVertexColor(1, 0, 0, 0.8)

                        -- Disables mouse events to allow the original pin to handle tooltips.
                        WorldMapFrame.viewerOverlayPin:EnableMouse(false)
                    else
                        -- Change the overlay to the new target pin
                        WorldMapFrame.viewerOverlayPin:SetParent(targetPin)
                        WorldMapFrame.viewerOverlayPin:SetFrameLevel(targetPin:GetFrameLevel() + 10)
                    end

                    -- Positions the overlay centered on the existing pin.
                    WorldMapFrame.viewerOverlayPin:ClearAllPoints()
                    WorldMapFrame.viewerOverlayPin:SetPoint("CENTER", targetPin, "CENTER", 0, 0)
                    WorldMapFrame.viewerOverlayPin:Show()

                    -- Stores discovery data for the tooltip and tracks current overlay target.
                    WorldMapFrame.viewerOverlayPin.discoveryData = discoveryData
                    Viewer.currentOverlayTarget = discovery.guid
                else
                    -- If no pin is found after retry, hides the overlay.
                    if WorldMapFrame.viewerOverlayPin then
                        WorldMapFrame.viewerOverlayPin:Hide()
                    end
                end
            end)
        end
    end

    -- Retrieves the localized zone name using ZoneResolver.
    local ZoneResolver = L:GetModule("ZoneResolver", true)
    local zoneName = "Unknown Zone"
    if ZoneResolver then
        zoneName = ZoneResolver:GetZoneNameByWorldMapID(discovery.worldMapID) or "Unknown Zone"
    end

    -- Store the restoration state for the World Map hooks
    if wasInSpecialFrames and windowName then
        self.restoreToSpecialFrames = true
        self.windowNameToRestore = windowName
        self.inMapOperation = true -- Persistent flag for window protection
    end
end

-- Helper function to open the world map to a specific areaID.
function Viewer:OpenWorldMapToArea(areaID)
    if not areaID or areaID == 0 then return false, "invalid areaID" end

    -- Stores the areaID to be set when the map frame becomes available.
    Viewer.pendingMapAreaID = areaID

    -- If WorldMapFrame is already open, attempts to set the map immediately.
    if WorldMapFrame and WorldMapFrame:IsShown() then
        self:SetWorldMapToPendingArea()
        return true, "map set immediately"
    end

    -- Ensures the WorldMapFrame is shown. The map setting will be handled by a hook when it's displayed.
    if InCombatLockdown() then
        -- Defers opening the map until after combat.
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(_, evt)
            if evt == "PLAYER_REGEN_ENABLED" then
                -- Re-opens the map to trigger the setting mechanism.
                ShowUIPanel(WorldMapFrame)
                f:UnregisterEvent("PLAYER_REGEN_ENABLED")
            end
        end)
        return true, "deferred due to combat"
    else
        -- Opens the WorldMapFrame.
        ShowUIPanel(WorldMapFrame)
        return true, "map opened"
    end

    return true, "map setting deferred to WorldMapFrame OnShow"
end

function Viewer:OnInitialize()
    self:CreateWindow()
    L:RegisterMessage("LootCollector_DiscoveriesUpdated", function(event, action, guid, discoveryData)
        
        -- Handles incremental cache updates based on the action.
        if action == "add" and guid and discoveryData then
            -- Adds a new discovery to the cache.
            if Cache.discoveriesBuilt and not Cache.discoveriesBuilding then
                self:AddDiscoveryToCache(guid, discoveryData)
                -- Refreshes the UI immediately if the window is shown.
                if self.window and self.window:IsShown() then
                    self:RefreshData()
                end
            end
        elseif action == "update" and guid and discoveryData then
            -- Updates an existing discovery in the cache.
            if Cache.discoveriesBuilt and not Cache.discoveriesBuilding then
                self:AddDiscoveryToCache(guid, discoveryData) -- This handles updates too.
                -- Refreshes the UI immediately if the window is shown.
                if self.window and self.window:IsShown() then
                    self:RefreshData()
                end
            end
        elseif action == "remove" and guid then
            -- Removes a discovery from the cache.
            if Cache.discoveriesBuilt and not Cache.discoveriesBuilding then
                self:RemoveDiscoveryFromCache(guid)
                -- Refreshes the UI immediately if the window is shown.
                if self.window and self.window:IsShown() then
                    self:RefreshData()
                end
            end
        elseif action == "clear" then
            -- Clears all caches and rebuilds.
            Cache.discoveriesBuilt = false
            Cache.discoveriesBuilding = false
            Cache.discoveries = {}
            Cache.filteredResults = {}
            Cache.lastFilterState = nil
            Cache.uniqueValuesValid = false
            Cache.uniqueValuesContext = {}
            Cache.duplicateItems = {}
            -- Refreshes the UI immediately if the window is shown.
            if self.window and self.window:IsShown() then
                self:RefreshData()
            end
        else
            -- Fallback: invalidates filtered results for unknown actions.
            if Cache.discoveriesBuilt and not Cache.discoveriesBuilding then
                Cache.filteredResults = {}
                Cache.lastFilterState = nil
                Cache.uniqueValuesValid = false
                Cache.uniqueValuesContext = {}
                -- Refreshes the UI immediately if the window is shown.
                if self.window and self.window:IsShown() then
                    self:RefreshData()
                end
            end
        end
    end)

    -- Hooks WorldMapFrame OnShow to set the map if a pending areaID exists.
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", function()
            -- Only sets the map if there is a pending areaID and the viewer window is currently shown.
            if Viewer.pendingMapAreaID and Viewer.window and Viewer.window:IsShown() then
                Viewer:SetWorldMapToPendingArea()
            end
        end)
    end

    -- Hooks WorldMapFrame OnHide to restore Viewer to UISpecialFrames after map closes.
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnHide", function()
            Viewer.pendingMapAreaID = nil
            -- Hides the overlay pin when the map is closed.
            if WorldMapFrame.viewerOverlayPin then
                WorldMapFrame.viewerOverlayPin:Hide()
            end
            Viewer.currentOverlayTarget = nil
            
            -- Restore window to UISpecialFrames after map closes
            if Viewer.restoreToSpecialFrames and Viewer.windowNameToRestore then
                -- Small delay to ensure map is fully closed before restoration
                C_Timer.After(0.1, function()
                    -- Restore to UISpecialFrames for ESC functionality
                    if Viewer.window and Viewer.window:IsShown() then
                        addToSpecialFrames(Viewer.windowNameToRestore)
                    end
                    -- Clear restoration state
                    Viewer.restoreToSpecialFrames = false
                    Viewer.windowNameToRestore = nil
                    Viewer.inMapOperation = false -- Clear persistent flag
                end)
            end
        end)
    end

    -- Create a cleanup frame to handle map changes and pin updates
    if not Viewer.mapCleanupFrame then
        Viewer.mapCleanupFrame = CreateFrame("Frame")
        Viewer.mapCleanupFrame:RegisterEvent("WORLD_MAP_UPDATE")
        Viewer.mapCleanupFrame:SetScript("OnEvent", function(self, event)
            if event == "WORLD_MAP_UPDATE" then
                -- Hide overlay when map changes zones
                if WorldMapFrame.viewerOverlayPin then
                    WorldMapFrame.viewerOverlayPin:Hide()
                end
                Viewer.currentOverlayTarget = nil
            end
        end)
    end

    -- Initializes the Clear All button state.
    self:UpdateClearAllButton()
    -- Initializes filter button states.
    self:UpdateFilterButtonStates()
end

function Viewer:Show()
    if not self.window then
        self:CreateWindow()
    end
    self.window:Show()
    self.currentPage = self.currentPage or 1
    self.currentFilter = self.currentFilter or "equipment"
    self:UpdateFilterButtons()
    self:UpdateSortHeaders()
    self:UpdateFilterButtonStates()
    self:RefreshData()



    -- Clears any pending map state when the viewer is shown to prevent unwanted map opening.
    self.pendingMapAreaID = nil
end

function Viewer:Hide()
    if self.window then
        self.window:Hide()
    end
    -- Clears pending map state when the viewer is hidden.
    self.pendingMapAreaID = nil
end

function Viewer:Toggle()
    if self.window and self.window:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Static popup for delete confirmation.
StaticPopupDialogs["LOOTCOLLECTOR_VIEWER_DELETE"] = {
    text = "%s",
    button1 = "Yes, Delete",
    button2 = "No, Cancel",
    OnAccept = function(self, data)
        if data and data.viewer and data.guid then
            data.viewer:DeleteDiscovery(data.guid)
            -- No need to clear all caches, DeleteDiscovery handles cache removal.
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    showAlert = true,
}

-- Static popup for bulk delete confirmation.
StaticPopupDialogs["LOOTCOLLECTOR_VIEWER_DELETE_ALL_FROM_PLAYER"] = {
    text = "%s",
    button1 = "Yes, Delete All",
    button2 = "No, Cancel",
    OnAccept = function(self, data)
        if data and data.viewer and data.playerName then
            data.viewer:DeleteAllFromPlayer(data.playerName)
            -- Cache management is handled by DeleteAllFromPlayer.
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    showAlert = true,
}

function Viewer:SetWorldMapToPendingArea()
    if not self.pendingMapAreaID or not WorldMapFrame or not WorldMapFrame:IsShown() then
        return
    end

    local areaID = self.pendingMapAreaID
    self.pendingMapAreaID = nil -- Clears it immediately.

    local success = false
    -- Attempts to use direct APIs first.
    if SetMapByID then
        pcall(SetMapByID, areaID)
        success = (GetCurrentMapAreaID() == areaID)
    end

    -- Fallback to ZoneResolver table if direct API failed or is not available.
    if not success then
        local Z = L and L:GetModule("ZoneResolver", true)
        if Z and Z.AreaID_Lookup and Z.AreaID_Lookup[areaID] then
            local lu = Z.AreaID_Lookup[areaID]
            if lu.continent and lu.zoneIndex then
                pcall(SetMapZoom, lu.continent, lu.zoneIndex)
                success = (GetCurrentMapAreaID() == areaID)
            end
        end
    end

    -- Last resort: one-time scan through all map continents and zones.
    if not success then
        for c = 1, #({ GetMapContinents() }) do
            local zones = { GetMapZones(c) }
            for z = 1, #zones do
                pcall(SetMapZoom, c, z)
                if GetCurrentMapAreaID() == areaID then
                    success = true
                    break
                end
            end
            if success then break end
        end
    end

    return success
end

-- Provides slash commands for viewer management.
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
