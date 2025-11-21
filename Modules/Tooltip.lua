

local L = LootCollector
local Tooltip = L:NewModule("Tooltip", "AceEvent-3.0")

local addonName = "ItemUpgradeTooltip"
local printPrefix = "|cff33ff99ItemUpgradeTooltip:|r "

local inHandler = false

local QUALITY_COLORS = {
    [0] = "|cFF9D9D9D", [1] = "|cFFFFFFFF", [2] = "|cFF1EFF00",
    [3] = "|cFF0070DD", [4] = "|cFFA335EE", [5] = "|cFFFF8000",
    [6] = "|cFFE6CC80", [7] = "|cFFE6CC80",
}

local DIFFICULTY_TIERS = {
    { index = 4, name = "Dungeon Upgrade", short = "Dung" },
    { index = 5, name = "ZG Upgrade", short = "ZG" },
    { index = 6, name = "Tier 1 Upgrade", short = "T1" },
    { index = 7, name = "Tier 2 Upgrade", short = "T2" },
    { index = 8, name = "AQ Upgrade", short = "AQ" },
    { index = 9, name = "Tier 3 Upgrade", short = "T3" },
}

local STAT_LABELS = {
    ITEM_MOD_STRENGTH_SHORT = "Strength",
    ITEM_MOD_AGILITY_SHORT = "Agility",
    ITEM_MOD_INTELLECT_SHORT = "Intellect",
    ITEM_MOD_SPIRIT_SHORT = "Spirit",
    ITEM_MOD_STAMINA_SHORT = "Stamina",
}

local STAT_ORDER = {
    "Strength", "Agility", "Intellect", "Spirit", "Stamina",
}

local upgradeCache = {}
local worldforgedCache = {}
local pendingItemLoads = {} 

local function ensureProfileDefaults()
    if not (L and L.db and L.db.profile) then return end
    if L.db.profile.enhancedWFTooltip == nil then
        L.db.profile.enhancedWFTooltip = false
    end
    if L.db.profile.enhancedWFTooltipDebug == nil then
        L.db.profile.enhancedWFTooltipDebug = false
    end
end

local function DebugPrint(...)
    if not (L and L.db and L.db.profile and L.db.profile.enhancedWFTooltipDebug) then return end
    local t = {}
    for i = 1, select("#", ...) do
        t[#t + 1] = tostring(select(i, ...))
    end
    print(printPrefix .. "[DEBUG] " .. table.concat(t, " "))
end

local function DebugPrintTable(tbl, name)
    if not (L and L.db and L.db.profile and L.db.profile.enhancedWFTooltipDebug) then return end
    if not tbl then
        DebugPrint(name .. " is nil")
        return
    end
    DebugPrint("--- Table:", name, "---")
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            DebugPrint("  ", tostring(k), "-> [Nested Table]")
        else
            DebugPrint("  ", tostring(k), "->", tostring(v))
        end
    end
    DebugPrint("--- End Table:", name, "---")
end

local function GetItemIDFromLink(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

local function GetQualityColor(quality)
    return QUALITY_COLORS[quality] or "|cFFFFFFFF"
end

local function GetScanner()
    if not ItemUpgradeTooltip_ScannerTooltip then
        ItemUpgradeTooltip_ScannerTooltip = CreateFrame("GameTooltip", addonName .. "ScannerTooltip", UIParent, "GameTooltipTemplate")
    end
    return ItemUpgradeTooltip_ScannerTooltip
end

local function PrimeItemCache(itemID)
    if not itemID then return end
    local scanner = GetScanner()
    scanner:ClearLines()
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    scanner:SetHyperlink("item:" .. itemID)
    scanner:Hide()
end

local function GetItemStatsTable(link)
    if not link then return {} end

    local apiStats = GetItemStats(link) or {}
    local readableStats = {}
    for statKey, label in pairs(STAT_LABELS) do
        if apiStats[statKey] then
            readableStats[label] = apiStats[statKey]
        end
    end

    
    local scanner = GetScanner()
    scanner:ClearLines()
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    scanner:SetHyperlink(link)

    for i = 2, scanner:NumLines() do
        local leftFS = _G[scanner:GetName() .. "TextLeft" .. i]
        local lineText = leftFS and leftFS:GetText()
        if lineText and lineText ~= "" then
            
            local negVal, negStatName = lineText:match("^%-([%d]+) ([%a%s]+)$")
            if negVal and negStatName then
                negStatName = string.trim and string.trim(negStatName) or negStatName:gsub("^%s+", ""):gsub("%s+$", "")
                for _, statName in ipairs(STAT_ORDER) do
                    if statName == negStatName then
                        readableStats[statName] = -tonumber(negVal)
                        break
                    end
                end
            elseif ITEM_MOD_MANA_REGENERATION then
                
                local mp5Pattern = ITEM_MOD_MANA_REGENERATION:gsub("%%d", "([%%d]+)"):gsub("%.", "%%.")
                local mp5val = lineText:match(mp5Pattern)
                if mp5val then
                    readableStats["MP5"] = tonumber(mp5val)
                end
            else
                
                local pvpPowerVal = lineText:match("Increases PvP Power by (%d+)")
                if pvpPowerVal then
                    readableStats["PvP Power"] = tonumber(pvpPowerVal)
                else
                    local critVal = lineText:match("Improves critical strike rating by (%d+)")
                    if critVal and not readableStats["Crit Rating"] then
                        readableStats["Crit Rating"] = tonumber(critVal)
                    else
                        local hasteVal = lineText:match("Improves haste rating by (%d+)")
                        if hasteVal and not readableStats["Haste Rating"] then
                            readableStats["Haste Rating"] = tonumber(hasteVal)
                        end
                    end
                end
            end
        end
    end

    scanner:Hide()
    return readableStats
end

local function IsWorldforged(tooltip, itemID, itemName)
    DebugPrint(">>> IsWorldforged check for itemID:", itemID, "Name:", itemName)
    if worldforgedCache[itemID] ~= nil then
        DebugPrint(">>> IsWorldforged: cache:", tostring(worldforgedCache[itemID]))
        return worldforgedCache[itemID]
    end

    if itemName and itemName:find("Worldforged") then
        DebugPrint(">>> IsWorldforged: name match")
        worldforgedCache[itemID] = true
        return true
    end

    local numLines = tooltip:NumLines()
    DebugPrint(">>> IsWorldforged: scanning", numLines, "lines")

    for i = 1, numLines do
        local lineText = ""
        local leftText = _G[tooltip:GetName() .. "TextLeft" .. i]
        if leftText and leftText:GetText() then
            lineText = lineText .. leftText:GetText()
        end

        local rightText = _G[tooltip:GetName() .. "TextRight" .. i]
        if rightText and rightText:GetText() then
            lineText = lineText .. rightText:GetText()
        end

        if lineText:find("Worldforged") then
            DebugPrint(">>> IsWorldforged: found on line", i)
            worldforgedCache[itemID] = true
            return true
        end
    end

    DebugPrint(">>> IsWorldforged: not found")
    worldforgedCache[itemID] = false
    return false
end

local function CountPlaceholders(upgradeChain)
    local count = 0
    for _, upgrade in ipairs(upgradeChain) do
        if upgrade.placeholder then
            count = count + 1
        end
    end
    return count
end

local function GetItemInfoAndEffects(link)
    if not link then return {}, {} end
    DebugPrint(">>> GetItemInfoAndEffects for link:", link)

    local standardStats = {}
    local effectLines = {}

    local apiStats = GetItemStats(link) or {}
    for statKey, label in pairs(STAT_LABELS) do
        if apiStats[statKey] then
            standardStats[label] = apiStats[statKey]
        end
    end
    DebugPrintTable(standardStats, "API Stats")

    local scanner = GetScanner()
    scanner:ClearLines()
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    scanner:SetHyperlink(link)

    DebugPrint(">>> Scanning tooltip for generic effects...")
    for i = 2, scanner:NumLines() do
        local leftFS = _G[scanner:GetName() .. "TextLeft" .. i]
        local lineText = leftFS and leftFS:GetText()
        DebugPrint(">>> Line", i, "(raw):", lineText)

        if lineText and lineText ~= "" and lineText:find(":") then
            local cleanLine = lineText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")

            local isStandardStat = false

            local negVal, negStatName = cleanLine:match("^%-([%d]+) ([%a%s]+)$")
            if negVal and negStatName then
                negStatName = string.trim and string.trim(negStatName) or negStatName:gsub("^%s+", ""):gsub("%s+$", "")
                for _, statName in ipairs(STAT_ORDER) do
                    if statName == negStatName then
                        standardStats[statName] = -tonumber(negVal)
                        isStandardStat = true
                        DebugPrint(">>> - negative stat:", negStatName)
                        break
                    end
                end
            end

            if not isStandardStat then
                local posVal, posStatName = cleanLine:match("^%+([%d]+) ([%a%s]+)$")
                if posVal and posStatName then
                    for _, label in pairs(STAT_LABELS) do
                        if label == (string.trim and string.trim(posStatName) or posStatName:gsub("^%s+", ""):gsub("%s+$", "")) then
                            isStandardStat = true
                            DebugPrint(">>> - known positive stat (skip, API)")
                            break
                        end
                    end
                end
            end

            if not isStandardStat then
                DebugPrint(">>> - effect:", cleanLine)
                table.insert(effectLines, cleanLine)
            end
        end
    end

    scanner:Hide()
    DebugPrintTable(effectLines, "Parsed Effect Lines")
    return standardStats, effectLines
end

local function BuildTierHeader(upgradeChain)
    local tiers = {}
    for _, upgrade in ipairs(upgradeChain) do
        table.insert(tiers, upgrade.tierShort)
    end
    return "Upgrades: " .. table.concat(tiers, ", ")
end

local function BuildStatLine(statName, upgradeChain)
    local values = {}
    local hasAnyValue = false

    for _, upgrade in ipairs(upgradeChain) do
        if upgrade.placeholder then
            table.insert(values, "|cff888888?|r")
        else
            local value = upgrade.stats[statName]
            if value then
                local color = GetQualityColor(upgrade.quality)
                table.insert(values, color .. (value > 0 and "+" or "") .. value .. "|r")
                hasAnyValue = true
            else
                table.insert(values, "|cff666666-|r")
            end
        end
    end

    if not hasAnyValue then
        return nil
    end

    return statName .. ": " .. table.concat(values, ", ")
end

local function GetAllStats(upgradeChain)
    local allStats = {}
    for _, upgrade in ipairs(upgradeChain) do
        if not upgrade.placeholder then
            for statName, _ in pairs(upgrade.stats or {}) do
                allStats[statName] = true
            end
        end
    end
    return allStats
end

local function AddUpgradeInfo(tooltip, upgradeChain)
    if not upgradeChain or #upgradeChain == 0 then
        DebugPrint(">>> AddUpgradeInfo: empty")
        return false
    end

    local placeholderCount = CountPlaceholders(upgradeChain)

    tooltip:AddLine(" ", 1, 1, 1)
    tooltip:AddLine(BuildTierHeader(upgradeChain), 1, 0.82, 0)

    local allStandardStats = {}
    for _, upgrade in ipairs(upgradeChain) do
        if not upgrade.placeholder and upgrade.stats then
            for statName, _ in pairs(upgrade.stats) do
                allStandardStats[statName] = true
            end
        end
    end
    DebugPrintTable(allStandardStats, "Unique Standard Stats")

    local statLineCount = 0
    for _, statName in ipairs(STAT_ORDER) do
        if allStandardStats[statName] then
            local statLine = BuildStatLine(statName, upgradeChain)
            if statLine then
                tooltip:AddLine(statLine, 1, 1, 1, true)
                statLineCount = statLineCount + 1
            end
        end
    end

    
    local processedTemplates = {}
    local effectLineCount = 0

    for i, baseUpgrade in ipairs(upgradeChain) do
        if not baseUpgrade.placeholder and baseUpgrade.effects then
            for _, effect in ipairs(baseUpgrade.effects) do
                local template = effect:gsub("%d+", "%%d")
                if not processedTemplates[template] then
                    processedTemplates[template] = true
                    effectLineCount = effectLineCount + 1

                    local numPlaceholders = 0
                    for _ in template:gmatch("%%d") do numPlaceholders = numPlaceholders + 1 end

                    local combinedValues = {}
                    for k = 1, numPlaceholders do combinedValues[k] = {} end

                    for _, targetUpgrade in ipairs(upgradeChain) do
                        local foundMatch = false
                        if not targetUpgrade.placeholder and targetUpgrade.effects then
                            for _, targetEffect in ipairs(targetUpgrade.effects) do
                                if targetEffect:gsub("%d+", "%%d") == template then
                                    local numIndex = 1
                                    for num in targetEffect:gmatch("%d+") do
                                        if combinedValues[numIndex] then
                                            local color = GetQualityColor(targetUpgrade.quality)
                                            table.insert(combinedValues[numIndex], { val = num, color = color })
                                            numIndex = numIndex + 1
                                        end
                                    end
                                    foundMatch = true
                                    break
                                end
                            end
                        end
                        if not foundMatch then
                            for k = 1, numPlaceholders do
                                table.insert(combinedValues[k], { val = "-", color = "|cff666666" })
                            end
                        end
                    end

                    local mergedNumbers = {}
                    for k = 1, numPlaceholders do
                        local firstVal = nil
                        local allSame = true
                        if #combinedValues[k] > 0 and combinedValues[k][1].val ~= "-" then
                            firstVal = combinedValues[k][1].val
                            for _, entry in ipairs(combinedValues[k]) do
                                if entry.val ~= firstVal then
                                    allSame = false
                                    break
                                end
                            end
                        else
                            allSame = false
                        end

                        if allSame then
                            table.insert(mergedNumbers, combinedValues[k][1].val)
                        else
                            local coloredVals = {}
                            for _, entry in ipairs(combinedValues[k]) do
                                table.insert(coloredVals, entry.color .. entry.val .. "|r")
                            end
                            table.insert(mergedNumbers, table.concat(coloredVals, "|cFFFFFFFF/|r"))
                        end
                    end

                    local finalLine = ""
                    local lastPos = 1
                    local numIndex = 1
                    for pos, numStr in effect:gmatch("()(%d+)") do
                        finalLine = finalLine .. "|cff1eff00" .. effect:sub(lastPos, pos - 1)
                        finalLine = finalLine .. (mergedNumbers[numIndex] or "?")
                        lastPos = pos + #numStr
                        numIndex = numIndex + 1
                    end
                    finalLine = finalLine .. "|cff1eff00" .. effect:sub(lastPos) .. "|r"

                    tooltip:AddLine(finalLine, 1, 1, 1, true)
                end
            end
        end
    end

    if statLineCount == 0 and effectLineCount == 0 and placeholderCount > 0 then
        tooltip:AddLine("Loading upgrade data...", 0.7, 0.7, 0.7)
        tooltip:AddLine("(Hover again in 1-2 seconds)", 0.6, 0.6, 0.6)
    elseif statLineCount == 0 and effectLineCount == 0 and placeholderCount == 0 then
        tooltip:AddLine("(No stat changes or generic effects found)", 0.7, 0.7, 0.7)
    elseif placeholderCount > 0 then
        tooltip:AddLine(" ", 1, 1, 1)
        tooltip:AddLine("? = loading... (hover again)", 0.6, 0.6, 0.6)
    end

    return true
end

local function BuildUpgradeChain(baseItemID)
    
    if upgradeCache[baseItemID] then
        local chain = upgradeCache[baseItemID]
        for _, upgrade in ipairs(chain) do
            if upgrade.placeholder then
                local itemName, itemLink, itemQuality = GetItemInfo(upgrade.itemID)
                if itemName and itemLink then
                    local standardStats, effectLines = GetItemInfoAndEffects(itemLink)
                    upgrade.itemName = itemName
                    upgrade.itemLink = itemLink
                    upgrade.quality = itemQuality or 2
                    upgrade.stats = standardStats
                    upgrade.effects = effectLines
                    upgrade.placeholder = false
                else
                    PrimeItemCache(upgrade.itemID)
                end
            end
        end
        return chain
    end

    if not GetItemDifficultyID then
        DebugPrint(">>> ERROR: GetItemDifficultyID not found")
        return nil
    end

    local newChain = {}

    for _, tier in ipairs(DIFFICULTY_TIERS) do
        local upgradedID = GetItemDifficultyID(baseItemID, tier.index)
        DebugPrint(">>> Tier", tier.index, "(", tier.short, ") ->", tostring(upgradedID))

        if upgradedID and upgradedID ~= 0 and upgradedID ~= baseItemID then
            local itemName, itemLink, itemQuality = GetItemInfo(upgradedID)
            local entry = {
                itemID = upgradedID,
                tierIndex = tier.index,
                tierName = tier.name,
                tierShort = tier.short,
            }

            if not itemName or not itemLink then
                PrimeItemCache(upgradedID)
                entry.itemName = nil
                entry.itemLink = "item:" .. upgradedID
                entry.quality = 2
                entry.stats = {}
                entry.effects = {}
                entry.placeholder = true
            else
                local standardStats, effectLines = GetItemInfoAndEffects(itemLink)
                entry.itemName = itemName
                entry.itemLink = itemLink
                entry.quality = itemQuality or 2
                entry.stats = standardStats
                entry.effects = effectLines
                entry.placeholder = false
            end
            table.insert(newChain, entry)
        end
    end

    if #newChain > 0 then
        upgradeCache[baseItemID] = newChain
        return newChain
    end

    return nil
end

local function OnTooltipSetItem(tooltip)
    local Core = L:GetModule("Core", true)
    if Core and Core.isSB and Core:isSB() then
        return
    end
    if inHandler then return end

    if not (L and L.db and L.db.profile and L.db.profile.enhancedWFTooltip) then
        return
    end

    if not GetItemDifficultyID then
        return
    end

    local name, link = tooltip:GetItem()
    if not link then return end

    local itemID = GetItemIDFromLink(link)
    if not itemID then return end

    DebugPrint("==========================================")
    DebugPrint(">>> Processing itemID:", itemID, "name:", name)

    if not IsWorldforged(tooltip, itemID, name) then
        DebugPrint(">>> Not Worldforged")
        return
    end

    DebugPrint(">>> Confirmed Worldforged")

    inHandler = true

    local upgradeChain = BuildUpgradeChain(itemID)

    if upgradeChain and #upgradeChain > 0 then
        AddUpgradeInfo(tooltip, upgradeChain)
        tooltip:Show()
        DebugPrint(">>> Tooltip updated")
    end

    DebugPrint("==========================================")

    inHandler = false
end

local function HookTooltips()
    print(printPrefix .. "Hooking tooltips...")

    
    local tooltips = { GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2, WorldMapTooltip }

    for _, tip in pairs(tooltips) do
        if tip and tip.HookScript then
            pcall(function()
                tip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
            end)
            if tip.GetName then
                print(printPrefix .. "Hooked: " .. (tip:GetName() or "unknown"))
            end
        end
    end

    print(printPrefix .. "Ready!")
end

local function ClearCache()
    upgradeCache = {}
    worldforgedCache = {}
    pendingItemLoads = {}
    print(printPrefix .. "Cache cleared")
end

function Tooltip:OnInitialize()
    ensureProfileDefaults()
end

function Tooltip:OnEnable()
    ensureProfileDefaults()
    self:RegisterEvent("PLAYER_LOGIN", function()
        
        HookTooltips()
    end)
end

function Tooltip:ApplySetting()
    
end

SLASH_LCWF1 = "/lcwf"
SlashCmdList["LCWF"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)") or ""
    if cmd == "debug" then
        L.db.profile.enhancedWFTooltipDebug = not L.db.profile.enhancedWFTooltipDebug
        print(printPrefix .. "Debug: " .. (L.db.profile.enhancedWFTooltipDebug and "ON" or "OFF"))
    elseif cmd == "clear" then
        ClearCache()
    else
        L.db.profile.enhancedWFTooltip = not L.db.profile.enhancedWFTooltip
        print(printPrefix .. (L.db.profile.enhancedWFTooltip and "Enabled" or "Disabled"))
    end
end

return Tooltip
