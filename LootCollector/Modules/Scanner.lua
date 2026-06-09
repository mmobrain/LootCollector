local L = LootCollector
local Scanner = L:NewModule("Scanner")

local SCANNER_FRAME_NAME = "LootCollector_UnifiedScanner"

local RETRIEVING_TEXT = "Retrieving item information..."

local CLASS_LOCAL_BY_TOKEN, TOKEN_BY_LOCAL = nil, nil
local function BuildClassLocalizationMaps()
    if CLASS_LOCAL_BY_TOKEN then return end
    CLASS_LOCAL_BY_TOKEN, TOKEN_BY_LOCAL = {}, {}
    local Constants = L:GetModule("Constants", true)
    local m = _G.LOCALIZED_CLASS_NAMES_MALE or {}
    local f = _G.LOCALIZED_CLASS_NAMES_FEMALE or {}
    local activeClasses = Constants and Constants:GetActiveClasses() or { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
    
    for _, tok in ipairs(activeClasses) do
        local loc = m[tok] or f[tok] or tok
        CLASS_LOCAL_BY_TOKEN[tok] = loc
        TOKEN_BY_LOCAL[string.lower(loc)] = tok
    end
end

local function escape_lua_pattern(s)
    return (s:gsub("(%W)", "%%%1"))
end

function Scanner:OnInitialize()
    if not self.tooltip then
        self.tooltip = CreateFrame("GameTooltip", SCANNER_FRAME_NAME, nil, "GameTooltipTemplate")
        self.tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    BuildClassLocalizationMaps()
    
    
    if L.db and L.db.global then
        L.db.global.scannerData = L.db.global.scannerData or {}
        self.dbCache = L.db.global.scannerData
    else
        self.dbCache = {}
    end
    
    
    self.ramCache = {} 
    
    
    C_Timer.After(15, function() self:StartBackgroundHydration() end)
end

function Scanner:ClearCache()
    wipe(self.dbCache)
    wipe(self.ramCache)
end

local function ExtractClassToken(lineText)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not lineText or lineText == "" then 
        if pTime then L:ProfileStop("Scanner:ExtractClassToken", pTime) end
        return nil 
    end
    local lower = string.lower(lineText)

    local list = lower:match("^classes:%s*(.+)$")
    if list then
        for localName, tok in pairs(TOKEN_BY_LOCAL) do
            if string.find(list, localName, 1, true) then 
                if pTime then L:ProfileStop("Scanner:ExtractClassToken", pTime) end
                return tok 
            end
        end
    end

    for localName, tok in pairs(TOKEN_BY_LOCAL) do
        local pat = "%f[%w]" .. escape_lua_pattern(localName) .. "%f[%W]"
        if lower:find(pat) or lower:find(localName, 1, true) then
            if pTime then L:ProfileStop("Scanner:ExtractClassToken", pTime) end
            return tok
        end
    end
    
    if pTime then L:ProfileStop("Scanner:ExtractClassToken", pTime) end
    return nil
end

function Scanner:GetItemData(itemID, itemLink)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not itemID and not itemLink then 
        if pTime then L:ProfileStop("Scanner:GetItemData", pTime) end
        return nil 
    end

    local cacheKey = itemLink or itemID
    local coreData = self.dbCache[cacheKey]
    local ramData = self.ramCache[cacheKey]

    local linkToScan = itemLink or select(2, GetItemInfo(itemID))
    local isMS = linkToScan and string.find(linkToScan, "Mystic Scroll", 1, true)

    
    if coreData and ramData then
        
        if isMS and not coreData.classToken then
            coreData = nil 
        else
            local res = {
                isWF = coreData.isWF,
                classToken = coreData.classToken,
                isCollected = coreData.isCollected,
                reqLevel = coreData.reqLevel,
                fullText = ramData.fullText
            }
            if pTime then L:ProfileStop("Scanner:GetItemData", pTime) end
            return res
        end
    end

    
    local itemData = { isWF = false, classToken = nil, isCollected = false, reqLevel = nil }

    if coreData then
        itemData.isWF = coreData.isWF
        itemData.classToken = coreData.classToken
        itemData.isCollected = coreData.isCollected
        itemData.reqLevel = coreData.reqLevel
    else
        
        if itemID and C_MysticEnchant and C_MysticEnchant.GetEnchantInfoByItem then
            local ok, enchantInfos = pcall(C_MysticEnchant.GetEnchantInfoByItem, itemID)
            if ok and enchantInfos and type(enchantInfos) == "table" and enchantInfos[1] then
                local info = enchantInfos[1]
                itemData.isWF = info.IsWorldforged == true
                itemData.isCollected = info.Known == true
                if info.ClassRequirements and type(info.ClassRequirements) == "table" and info.ClassRequirements[1] then
                    local cType = info.ClassRequirements[1].ClassType
                    if cType then itemData.classToken = cType:gsub("^Reborn", ""):upper() end
                end
            end
        end

        if not itemData.isCollected and itemID and C_MysticEnchant and C_MysticEnchant.IsCollected then
            local ok, result = pcall(C_MysticEnchant.IsCollected, itemID)
            if ok and result then itemData.isCollected = true end
        end
    end

    if not linkToScan then 
        if pTime then L:ProfileStop("Scanner:GetItemData", pTime) end
        return nil 
    end

    self.tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    self.tooltip:ClearLines()
    self.tooltip:SetHyperlink(linkToScan)

    local numLines = self.tooltip:NumLines()
    if numLines > 0 then
        local line1Left = _G[SCANNER_FRAME_NAME .. "TextLeft1"]
        if not (line1Left and line1Left:GetText() == RETRIEVING_TEXT) then
            local textParts = {}
            local reqLevelPattern = _G.ITEM_MIN_LEVEL and _G.ITEM_MIN_LEVEL:gsub("%%d", "(%%d+)") or "Requires Level%s+(%%d+)"
            
            for i = 1, numLines do
                local leftLine = _G[SCANNER_FRAME_NAME .. "TextLeft" .. i]
                local rightLine = _G[SCANNER_FRAME_NAME .. "TextRight" .. i]
                
                local lText = leftLine and leftLine:GetText() or ""
                local rText = rightLine and rightLine:GetText() or ""
                
                if lText ~= "" then table.insert(textParts, lText) end
                if rText ~= "" then table.insert(textParts, rText) end
                
                if not coreData then
                    if not itemData.isWF and (string.find(lText, "Worldforged", 1, true) or string.find(rText, "Worldforged", 1, true)) then
                        itemData.isWF = true
                    end
                    
                    if not itemData.classToken then
                        if string.find(string.lower(lText), "classes:", 1, true) then
                            itemData.classToken = ExtractClassToken(lText)
                        elseif isMS and i <= 4 then
                            
                            
                            local stripped = lText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
                            local tok = TOKEN_BY_LOCAL[string.lower(stripped)]
                            if tok then itemData.classToken = tok end
                        end
                    end
                    
                    if not itemData.reqLevel then
                        local reqLvlText = lText:match(reqLevelPattern) or rText:match(reqLevelPattern)
                        if reqLvlText then itemData.reqLevel = tonumber(reqLvlText) end
                    end
                    if not itemData.isCollected then
                        local stripped = lText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                        if stripped == "Collected" then itemData.isCollected = true end
                    end
                end
            end
            self.ramCache[cacheKey] = { fullText = string.lower(table.concat(textParts, " ")) }
        end
    end

    if not coreData then
        self.dbCache[cacheKey] = {
            isWF = itemData.isWF,
            classToken = itemData.classToken,
            isCollected = itemData.isCollected,
            reqLevel = itemData.reqLevel
        }
    end

    local finalData = {
        isWF = itemData.isWF,
        classToken = itemData.classToken,
        isCollected = itemData.isCollected,
        reqLevel = itemData.reqLevel,
        fullText = self.ramCache[cacheKey] and self.ramCache[cacheKey].fullText or ""
    }

    if pTime then L:ProfileStop("Scanner:GetItemData", pTime) end 
    return finalData
end

function Scanner:PreWarmCache(itemID, itemLink)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not itemID or not itemLink then 
        if pTime then L:ProfileStop("Scanner:PreWarmCache", pTime) end
        return 
    end
    local key = itemLink or itemID
    if self.dbCache[key] and self.ramCache[key] then 
        if pTime then L:ProfileStop("Scanner:PreWarmCache", pTime) end
        return 
    end   
    self:GetItemData(itemID, itemLink)
    
    if pTime then L:ProfileStop("Scanner:PreWarmCache", pTime) end
end

function Scanner:StartBackgroundHydration()
    local pTime = L.ProfileStart and L:ProfileStart() 

    if self._hydrationInProgress then 
        if pTime then L:ProfileStop("Scanner:StartBackgroundHydration", pTime) end
        return 
    end
    self._hydrationInProgress = true
    self._hydrationQueue = {}
    
    local db = L:GetDiscoveriesDB() or {}
    local seen = {}
    for _, d in pairs(db) do
        local key = d.il or d.i
        if key and not seen[key] and not self.ramCache[key] then
            table.insert(self._hydrationQueue, key)
            seen[key] = true
        end
    end
    
    self:ProcessHydrationChunk()
    
    if pTime then L:ProfileStop("Scanner:StartBackgroundHydration", pTime) end
end

function Scanner:ProcessHydrationChunk()
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not self._hydrationInProgress then 
        if pTime then L:ProfileStop("Scanner:ProcessHydrationChunk", pTime) end
        return 
    end
    if L:IsPaused() or InCombatLockdown() then
        C_Timer.After(2.0, function() self:ProcessHydrationChunk() end)
        if pTime then L:ProfileStop("Scanner:ProcessHydrationChunk", pTime) end
        return
    end
    
    if #self._hydrationQueue == 0 then
        self._hydrationInProgress = false
        L._debug("Scanner", "Background Hydration complete. Deep Search RAM cache is fully loaded.")
        if pTime then L:ProfileStop("Scanner:ProcessHydrationChunk", pTime) end
        return
    end
    
    local BUDGET_MS = 1.0 
    local startMs = debugprofilestop()
    local processed = 0
    
    while #self._hydrationQueue > 0 do
        local key = table.remove(self._hydrationQueue, 1)
        local itemID = type(key) == "number" and key or tonumber(key:match("item:(%d+)"))
        
        if itemID and GetItemInfo(itemID) then
            self:GetItemData(itemID, type(key) == "string" and key or nil)
        end
        
        processed = processed + 1
        if debugprofilestop() - startMs >= BUDGET_MS then break end
    end
    
    C_Timer.After(0.1, function() self:ProcessHydrationChunk() end)
    
    if pTime then L:ProfileStop("Scanner:ProcessHydrationChunk", pTime) end
end

return Scanner