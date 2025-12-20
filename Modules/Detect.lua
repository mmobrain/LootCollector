
local L = LootCollector
local Detect = L:NewModule("Detect", "AceEvent-3.0")

local SCAN_TIP_NAME = "LootCollectorScanTip"
local scanTip
local LEGACY_DETECT_MODE = false 

Detect.recentlyScannedNPCs = Detect.recentlyScannedNPCs or {} 

Detect._lastDiscoveryGUID = nil
Detect._lastDiscoveryTime = 0
Detect._recoverySuppressionUntil = 0
local RECOVERY_SUPPRESSION_WINDOW = 9.0

local FORBIDDEN_CITY_ZONES = {
    [1] = { 
        [382] = true, 
        [322] = true, 
        [472] = true, 
        [363] = true, 
    },
    [2] = { 
        [342] = true, 
        [302] = true, 
        [383] = true, 
        [481] = true, 
    },
    [3] = { 
        [482] = true, 
    },
    [4] = { 
        [505] = true, 
    }
}

local NPCScanTip = CreateFrame("GameTooltip", "LootCollector_NPCScanTip", UIParent, "GameTooltipTemplate")
NPCScanTip:SetOwner(UIParent, "ANCHOR_NONE")

local lastLootContext = {
    openedAt = 0,
    mapID = 0,
    c = 0, z = 0, iz = 0,
    x = 0, y = 0,
}

local LOOT_VALIDITY_WINDOW = 20
local ITEM_EXPECTATION_WINDOW = 9.0 

Detect._expectingItemUntil = 0
Detect._expectedItemLink = nil

function Detect:Debug(msg, ...) return end

local function ParseItemID(link)
  if not link then return nil end
  return tonumber(link:match("item:(%d+)"))
end

local function ScanMerchant()
  local items = {}
  local n = GetMerchantNumItems()
  if n == 0 then return items end
  
  for i = 1, n do
    local link = GetMerchantItemLink(i)
    local name, texture, price, quantity, numAvailable, isUsable, extendedCost = GetMerchantItemInfo(i)
    local itemID = ParseItemID(link)

    local costs = {}
    if extendedCost then
      local costKinds = GetMerchantItemCostInfo(i)
      for j = 1, (costKinds or 0) do
        local costTexture, costAmount, costLink, currencyName = GetMerchantItemCostItem(i, j)
        local costItemID = ParseItemID(costLink)
        costs[#costs+1] = {
          amount = costAmount,
          link = costLink,
          itemID = costItemID,
          currencyName = currencyName,
          texture = costTexture,
        }
      end
    end

    if itemID then
        items[#items+1] = {
          index = i,
          itemID = itemID,
          link = link,
          name = name,
          price = price,
          stack = quantity,
          numAvailable = numAvailable,
          isUsable = isUsable,
          extendedCost = extendedCost,
          costs = costs,
        }
    end
  end
  return items
end

local function GetNPCSubname(unit)
  if not unit or not UnitExists(unit) then return nil end
  NPCScanTip:ClearLines()
  NPCScanTip:SetUnit(unit)
  local line2 = _G["LootCollector_NPCScanTipTextLeft2"]
  local text = line2 and line2:IsShown() and line2:GetText() or nil

  
  if text and (text:match("^Level %d") or tonumber(text:match("(%d+)"))) then
    return nil
  end
  return text
end

local function EnsureScanTip()
  if scanTip then return end
  scanTip = CreateFrame("GameTooltip", SCAN_TIP_NAME, nil, "GameTooltipTemplate")
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
end

local function TooltipHas(link, needle)
  if not link or not needle then return false end
  EnsureScanTip()
  scanTip:ClearLines()
  scanTip:SetHyperlink(link)
  for i = 2, 5 do
    local fs = _G[SCAN_TIP_NAME .. "TextLeft" .. i]
    local text = fs and fs:GetText()
    if text and string.find(string.lower(text), string.lower(needle), 1, true) then
      return true
    end
  end
  return false
end

Detect._cache, Detect._recent = { isWF = {}, isMS = {} }, {}

function Detect:IsWorldforged(link)
  local c = self._cache.isWF[link]
  if c ~= nil then return c end
  local ok = TooltipHas(link, "Worldforged")
  self._cache.isWF[link] = ok
  return ok
end

function Detect:IsMysticScroll(link, source)
  local name = (link and select(1, GetItemInfo(link))) or (link and link:match("%[(.-)%]")) or ""
  if name == "" then return false end
  if L.ignoreList and L.ignoreList[name] then return false end
  if L.sourceSpecificIgnoreList and L.sourceSpecificIgnoreList[name] and source ~= "world_loot" and source ~= "direct" then
    return false
  end
  return string.find(name, "Mystic Scroll:", 1, true) ~= nil
end

function Detect:Qualifies(link, source)
  if not link then return false end
  return self:IsWorldforged(link) or self:IsMysticScroll(link, source)
end

Detect._ctx = {
  lastLootOpenedAt = nil,
  lastGossipAt = nil,
  lastMerchantAt = nil,
  lastEmoteAt = nil,
  lastMailTakeAt = nil,
  mailOpen = false,
  lastQuestCompleteAt = nil,
  lastQuestFinishedAt = nil, 
  lastQuestTurnedInAt = nil, 
  lastQuestMsgAt = nil,      
  lastTradeAcceptedAt = nil,
  tradeOpen = false,
  craftingOpen = false,
  
  bankOpen = false,
  guildBankOpen = false,
  lastAchievementAt = nil,
  lastBuybackAt = nil,
}

function Detect:OnRecoveryEvent(event, arg1, arg2)
    local isRecoverySuccess = false

    if event == "UI_INFO_MESSAGE" and arg1 == "|cFF2EF50EItem recovery completed|r" then
        isRecoverySuccess = true
    elseif event == "RECOVERY_RESULT" and arg2 and string.find(arg2, "_OK$") then
        isRecoverySuccess = true
    end

    if isRecoverySuccess then
        L._debug("Detect", "Item recovery event detected.")
        local now = GetTime()
        
        
        if self._lastDiscoveryGUID and (now - self._lastDiscoveryTime < 1.0) then
            local Core = L:GetModule("Core", true)
            if Core and Core.RemoveDiscoveryByGuid then
                L._debug("Detect", "Retroactively removing last discovery due to recovery: " .. self._lastDiscoveryGUID)
                Core:RemoveDiscoveryByGuid(self._lastDiscoveryGUID, "Discovery suppressed due to item recovery.")
            end
        end

        
        self._lastDiscoveryGUID = nil
        self._lastDiscoveryTime = 0
    end
end

function Detect:ScanAndRecordVendor()
    local unit = "npc"
    if not UnitExists(unit) then return end

    
    
    local npcName = UnitName(unit)
    if not npcName or npcName == "" or npcName == "Unknown" then
        
        C_Timer.After(0.5, function() Detect:ScanAndRecordVendor() end)
        return
    end

    local npcGUID = UnitGUID(unit)
    if not npcGUID then return end

    if self.recentlyScannedNPCs[npcGUID] and (time() - self.recentlyScannedNPCs[npcGUID] < 60) then
        return
    end
    self.recentlyScannedNPCs[npcGUID] = time()

    local merchantItems = ScanMerchant()
    if #merchantItems == 0 then
        return
    end

    local isBlackmarket = false
    local sellsMysticScroll = false
    local npcSubname = GetNPCSubname(unit)

    if npcSubname and npcSubname:find("Blackmarket Artisan Supplies", 1, true) then
        isBlackmarket = true
    end

    for _, itemData in ipairs(merchantItems) do
        if itemData.name and itemData.name:find("Mystic Scroll", 1, true) then
            sellsMysticScroll = true
            break
        end
    end

    if isBlackmarket or sellsMysticScroll then
        local now = time()
        local px, py = GetPlayerMapPosition("player")
        px = px or 0; py = py or 0
        
        
        SetMapToCurrentZone()
        local mapID = GetCurrentMapAreaID()
        
        
        if not mapID or mapID == 0 then return end

        local ZoneList = L:GetModule("ZoneList", true)
        local zoneInfo = ZoneList and ZoneList.MapDataByID[mapID]
        
        local c, z, iz
        if zoneInfo then
            
            c = zoneInfo.continentID
            z = mapID
            iz = 0
        else 
            
            c = GetCurrentMapContinent() or 0
            z = mapID
            iz = mapID 
        end

        local Constants = L:GetModule("Constants", true)
        
        local discovery = {
            i = -3,
            c = c,
            z = z,
            iz = iz,
            mapID = mapID,
            xy = { x = px, y = py },
            t0 = now,
            src = "merchant",
            fp = UnitName("player"),
            dt = Constants and Constants.DISCOVERY_TYPE.BLACKMARKET, 
            vendorType = sellsMysticScroll and "MS" or "BM",
            vendorItems = merchantItems,
            vendorName = npcName, 
        }

        local Core = L:GetModule("Core", true)
        if Core and Core.HandleLocalLoot then
            Core:HandleLocalLoot(discovery)
        end
    end
end

function Detect:OnRecoveryEvent(event, arg1, arg2)
    local isRecoverySuccess = false

    if event == "UI_INFO_MESSAGE" and arg1 == "|cFF2EF50EItem recovery completed|r" then
        isRecoverySuccess = true
    elseif event == "RECOVERY_RESULT" and arg2 and string.find(arg2, "_OK$") then
        isRecoverySuccess = true
    end

    if isRecoverySuccess then
        L._debug("Detect", "Item recovery event detected.")
        local now = GetTime()
        
        
        if self._lastDiscoveryGUID and (now - self._lastDiscoveryTime < 2.5) then
            local Core = L:GetModule("Core", true)
            if Core and Core.RemoveDiscoveryByGuid then
                L._debug("Detect", "Retroactively removing last discovery due to recovery: " .. self._lastDiscoveryGUID)
                Core:RemoveDiscoveryByGuid(self._lastDiscoveryGUID, "Discovery suppressed due to item recovery.")
            end
        end

        
        self._lastDiscoveryGUID = nil
        self._lastDiscoveryTime = 0
    end
end

local function IsBlackmarketArtisan(unit)
  local sub = GetNPCSubname(unit)
  
  return sub and sub:find("Blackmarket Artisan Supplies", 1, true) ~= nil
end

local function FindNearbyVendor(newVendor)
    
    local vendors = L:GetVendorsDB()
    if not vendors then return nil end
    
    if not (newVendor.vendorName and newVendor.z) then return nil end
    local COORD_THRESHOLD = 0.03
    local newX = newVendor.xy and L:Round4(newVendor.xy.x) or 0
    local newY = newVendor.xy and L:Round4(newVendor.xy.y) or 0
    
    for guid, existingVendor in pairs(vendors) do
        if existingVendor.vendorName and
           existingVendor.vendorName == newVendor.vendorName and
           (existingVendor.vendorType == newVendor.vendorType) and
           (tonumber(existingVendor.z) == tonumber(newVendor.z)) and
           (tonumber(existingVendor.c) == tonumber(newVendor.c)) then
            local existingX = existingVendor.xy and L:Round4(existingVendor.xy.x) or 0
            local existingY = existingVendor.xy and L:Round4(existingVendor.xy.y) or 0
            if math.abs(newX - existingX) < COORD_THRESHOLD and math.abs(newY - existingY) < COORD_THRESHOLD then
                return existingVendor
            end
        end
    end
    return nil
end

local function MergeVendorData(existing, new)
    existing.ls = math.max(tonumber(existing.ls) or 0, tonumber(new.t0) or 0)
    existing.st = math.max(tonumber(existing.st) or 0, tonumber(new.t0) or 0)
    if new.fp and new.fp ~= "Unknown" then existing.fp = new.fp end
    if new.vendorItems and #new.vendorItems > 0 then
        existing.vendorItems = existing.vendorItems or {}
        local itemLookup = {}
        for _, item in ipairs(existing.vendorItems) do
            if item.itemID then itemLookup[item.itemID] = true end
        end
        for _, item in ipairs(new.vendorItems) do
            if item.itemID and not itemLookup[item.itemID] then
                table.insert(existing.vendorItems, item)
                itemLookup[item.itemID] = true
            end
        end
    end
    existing.mc = (tonumber(existing.mc) or 1) + 1
    if (tonumber(new.t0) or 0) > (tonumber(existing.ls) or 0) then
        existing.xy = new.xy
    end
    L:SendMessage("LOOTCOLLECTOR_DISCOVERY_UPDATED", "update", existing.g, existing)
    return true 
end

function Detect:OnNPCInteraction()
    local unitToCheck = "npc"
    if not UnitExists(unitToCheck) then return end
    local npcGUID = UnitGUID(unitToCheck)
    if not npcGUID then return end
    if self.recentlyScannedNPCs[npcGUID] and (time() - self.recentlyScannedNPCs[npcGUID]) < 10 then
        return
    end
    self.recentlyScannedNPCs[npcGUID] = time()
    local merchantItems = ScanMerchant()
    if not merchantItems or #merchantItems == 0 then return end
    local isMSVendor = false
    local isBMVendor = IsBlackmarketArtisan(unitToCheck)
    if not isBMVendor then
        for _, itemData in ipairs(merchantItems) do
            if itemData.name and string.find(itemData.name, "Mystic Scroll", 1, true) then
                isMSVendor = true
                break
            end
        end
    end
    if not isMSVendor and not isBMVendor then return end
    local vendorType = isMSVendor and "MS" or "BM"
    local now = time()
    local px, py = GetPlayerMapPosition("player")
    px = px or 0; py = py or 0

    
    SetMapToCurrentZone()
    local mapID = GetCurrentMapAreaID()
    local ZoneList = L:GetModule("ZoneList", true)
    local zoneInfo = ZoneList and ZoneList.MapDataByID[mapID]

    local c, z, iz
    if zoneInfo then
        
        c = zoneInfo.continentID
        z = mapID
        iz = 0
    else 
        
        c = GetCurrentMapContinent() or 0
        z = mapID
        iz = mapID
    end

    local Constants = L:GetModule("Constants", true)
    local potentialDiscovery = {
        c = c, z = z, iz = iz, xy = { x = px, y = py }, t0 = now,
        vendorType = vendorType, vendorName = UnitName(unitToCheck),
        vendorItems = merchantItems, fp = UnitName("player"),
        dt = Constants and Constants.DISCOVERY_TYPE.BLACKMARKET,
    }
    local existingVendor = FindNearbyVendor(potentialDiscovery)
    if existingVendor then
        MergeVendorData(existingVendor, potentialDiscovery)
        local Comm = L:GetModule("Comm", true)
        if Comm and Comm.QueueBroadcast then
            Comm:QueueBroadcast(existingVendor)
        end
    else
        potentialDiscovery.i = (vendorType == "MS" and -400000 or -300000) - mapID
        potentialDiscovery.il = string.format("|cffa335ee|Hitem:%d:0:0:0:0:0:0:0:0|h[%s Vendor]|h|r", potentialDiscovery.i, vendorType)
        local Core = L:GetModule("Core", true)
        if Core and Core.HandleLocalLoot then
            Core:HandleLocalLoot(potentialDiscovery)
        end
    end
    local Map = L:GetModule("Map", true)
    if Map and Map.Update then Map:Update() end
end

function Detect:OnLootOpened()
    self._ctx.lastLootOpenedAt = time()
    lastLootContext.openedAt = time()

    local px, py = GetPlayerMapPosition("player")
    lastLootContext.x = px or 0
    lastLootContext.y = py or 0
    
    
    
    SetMapToCurrentZone() 
    local mapID = GetCurrentMapAreaID()
    lastLootContext.mapID = mapID
    
    local ZoneList = L:GetModule("ZoneList", true)
    local zoneInfo = ZoneList and ZoneList.MapDataByID[mapID]

    if zoneInfo then
        
        lastLootContext.c = zoneInfo.continentID
        lastLootContext.z = mapID 
        lastLootContext.iz = 0   
    else 
        
        lastLootContext.c = GetCurrentMapContinent() or 0
        lastLootContext.z = mapID  
        lastLootContext.iz = mapID 
    end
end

function Detect:OnLootClosed()
    self._expectingItemUntil = GetTime() + ITEM_EXPECTATION_WINDOW
end

function Detect:OnSystemMessage(_, msg)
    if msg and string.find(msg, " completed.") then
        self._ctx.lastQuestMsgAt = time()
    end
end

function Detect:OnInitialize()
  if L.LEGACY_MODE_ACTIVE then return end
  
  self:RegisterEvent("LOOT_OPENED", "OnLootOpened")
  self:RegisterEvent("LOOT_CLOSED", "OnLootClosed")
  
  self:RegisterEvent("BAG_UPDATE", "OnBagUpdate")

  self:RegisterEvent("GOSSIP_SHOW", function() self._ctx.lastGossipAt = time() end)
  self:RegisterEvent("GOSSIP_CLOSED", function() self._ctx.lastGossipAt = time(); self._expectingItemUntil = GetTime() + ITEM_EXPECTATION_WINDOW end)
  self:RegisterEvent("MERCHANT_SHOW", "ScanAndRecordVendor")
  self:RegisterEvent("MERCHANT_UPDATE", "ScanAndRecordVendor")
  self:RegisterEvent("MERCHANT_CLOSED", function() self._ctx.lastMerchantAt = nil end)
  self:RegisterEvent("MAIL_SHOW", function() self._ctx.mailOpen = true end)
  self:RegisterEvent("MAIL_CLOSED", function() self._ctx.mailOpen = false end)
  self:RegisterEvent("CHAT_MSG_LOOT", "OnChatMsgLoot")
  
  
  self:RegisterEvent("QUEST_COMPLETE", function() self._ctx.lastQuestCompleteAt = time() end)
  self:RegisterEvent("QUEST_FINISHED", function() self._ctx.lastQuestFinishedAt = time() end)
  self:RegisterEvent("QUEST_TURNED_IN", function() self._ctx.lastQuestTurnedInAt = time() end)
  self:RegisterEvent("CHAT_MSG_SYSTEM", "OnSystemMessage")

  self:RegisterEvent("TRADE_SHOW", function() self._ctx.tradeOpen = true end)
  self:RegisterEvent("TRADE_CLOSED", function() self._ctx.tradeOpen = false; self._ctx.lastTradeAcceptedAt = nil end)
  self:RegisterEvent("TRADE_ACCEPTED", function() self._ctx.lastTradeAcceptedAt = time() end)
  self:RegisterEvent("TRADE_SKILL_SHOW", function() self._ctx.craftingOpen = true end)
  self:RegisterEvent("TRADE_SKILL_CLOSE", function() self._ctx.craftingOpen = false end)
  self:RegisterEvent("CRAFT_SHOW", function() self._ctx.craftingOpen = true end)
  self:RegisterEvent("CRAFT_CLOSE", function() self._ctx.craftingOpen = false end)
  
  
  self:RegisterEvent("BANK_FRAME_OPENED", function() self._ctx.bankOpen = true end)
  self:RegisterEvent("BANK_FRAME_CLOSED", function() self._ctx.bankOpen = false end)
  self:RegisterEvent("GUILDBANKFRAME_OPENED", function() self._ctx.guildBankOpen = true end)
  self:RegisterEvent("GUILDBANKFRAME_CLOSED", function() self._ctx.guildBankOpen = false end)
  self:RegisterEvent("ACHIEVEMENT_EARNED", function() self._ctx.lastAchievementAt = time() end)

  
  self:RegisterEvent("UI_INFO_MESSAGE", "OnRecoveryEvent")
  self:RegisterEvent("RECOVERY_RESULT", "OnRecoveryEvent")

  if hooksecurefunc then
    hooksecurefunc("TakeInboxItem", function() Detect._ctx.lastMailTakeAt = time() end)
    hooksecurefunc("DoEmote", function() Detect._ctx.lastEmoteAt = time() end)
    hooksecurefunc("BuybackItem", function() Detect._ctx.lastBuybackAt = time() end)
  end
end

local function classifySource(ctx, now)
  local QUEST_WINDOW = 30.0

  if ctx.mailOpen or (ctx.lastMailTakeAt and (now - ctx.lastMailTakeAt <= 3)) then return "mail" end
  if ctx.tradeOpen or (ctx.lastTradeAcceptedAt and (now - ctx.lastTradeAcceptedAt <= 3)) then return "trade" end
  if ctx.bankOpen then return "bank" end
  if ctx.guildBankOpen then return "guild_bank" end
  
  
  if (ctx.lastQuestCompleteAt and (now - ctx.lastQuestCompleteAt <= 5)) or
     (ctx.lastQuestFinishedAt and (now - ctx.lastQuestFinishedAt <= QUEST_WINDOW)) or
     (ctx.lastQuestTurnedInAt and (now - ctx.lastQuestTurnedInAt <= QUEST_WINDOW)) or
     (ctx.lastQuestMsgAt and (now - ctx.lastQuestMsgAt <= QUEST_WINDOW)) then 
     return "quest_reward" 
  end

  if ctx.lastAchievementAt and (now - ctx.lastAchievementAt <= 3) then return "achievement" end
  if ctx.craftingOpen then return "crafting" end
  if _G.C_MysticEnchant and _G.C_MysticEnchant.HasNearbyMysticAltar and _G.C_MysticEnchant.HasNearbyMysticAltar() then return "mystic_altar" end
  if ctx.lastBuybackAt and (now - ctx.lastBuybackAt <= 3) then return "vendor_buyback" end
  if ctx.lastMerchantAt and (now - ctx.lastMerchantAt <= 5) then return "vendor" end
  if ctx.lastLootOpenedAt and (now - ctx.lastLootOpenedAt <= 5) then return "world_loot" end
  if ctx.lastGossipAt and (now - ctx.lastGossipAt <= 5) then return "npc_gossip" end
  if ctx.lastEmoteAt and (now - ctx.lastEmoteAt <= 5) then return "emote_event" end
  return "direct"
end

function Detect:OnChatMsgLoot(_, msg)
    
    
    local link = msg and msg:match("|Hitem:%d+:[^|]+|h%[[^%]]+%]|h")
    if not link then return end

    local _, _, playerName = string.find(msg, "([^%s]+)%s+receives loot:")
    local looter = playerName or UnitName("player")
    if looter ~= UnitName("player") then return end
    
    local now = time()
    local src = classifySource(self._ctx, now)
    local deniedSources = { mail = true, quest_reward = true, trade = true, crafting = true, mystic_altar = true, vendor = true, bank = true, guild_bank = true, achievement = true }
    if deniedSources[src] then return end
    if src == "world_loot" and (now - lastLootContext.openedAt) > LOOT_VALIDITY_WINDOW then return end

    local c, z, iz, x_val, y_val
    if src == "world_loot" then
        c, z, iz = lastLootContext.c, lastLootContext.z, lastLootContext.iz
        x_val, y_val = lastLootContext.x, lastLootContext.y
    else
        c = GetCurrentMapContinent() or 0
        SetMapToCurrentZone()
        local mapID = GetCurrentMapAreaID()
        local ZoneList = L:GetModule("ZoneList", true)
        local zoneInfo = ZoneList and ZoneList.MapDataByID[mapID]

        if zoneInfo then
            c = zoneInfo.continentID 
            z = mapID
            iz = 0
        else
            z = mapID
            iz = mapID
        end
        
        local px, py = GetPlayerMapPosition("player")
        x_val, y_val = px or 0, py or 0
    end
    
    if FORBIDDEN_CITY_ZONES[c] and FORBIDDEN_CITY_ZONES[c][z] then
        return
    end

    if not self:Qualifies(link, src) then return end
    local last = self._recent[link] or 0
    if now - last < 1.0 then return end
    self._recent[link] = now

    local discovery = { il = link, c = c, z = z, iz = iz, xy = { x = x_val, y = y_val }, t0 = now, src = src, fp = looter }
    local Core = L:GetModule("Core", true)
    if Core and Core.HandleLocalLoot then
        
        local guid = L:GenerateGUID(c, z, tonumber(link:match("item:(%d+)")), x_val, y_val)
        self._lastDiscoveryGUID = guid
        self._lastDiscoveryTime = now
        Core:HandleLocalLoot(discovery)
    end
    local itemID = tonumber(link:match("item:(%d+)"))
    if itemID then
        L:SendMessage("LOOTCOLLECTOR_PLAYER_LOOTED_ITEM", itemID, c, z, x_val, y_val)
    end
end

function Detect:ProcessPotentialDiscovery(link, sourceHint, looterName)
    

    local now = time()
    looterName = looterName or UnitName("player")
    local src = classifySource(self._ctx, now)
    local deniedSources = { mail = true, quest_reward = true, trade = true, crafting = true, mystic_altar = true, vendor = true, vendor_buyback = true, bank = true, guild_bank = true, achievement = true }
    if deniedSources[src] then return end

    local isWF, isMS = self:Qualifies(link, src)
    if not isWF and not isMS then return end
    if isWF and src ~= "world_loot" then return end
    
    local c, z, iz, px, py
    if src == "world_loot" and (now - lastLootContext.openedAt) <= LOOT_VALIDITY_WINDOW then
        c, z, iz, px, py = lastLootContext.c, lastLootContext.z, lastLootContext.iz, lastLootContext.x, lastLootContext.y
    else
        c = GetCurrentMapContinent() or 0
        SetMapToCurrentZone()
        local mapID = GetCurrentMapAreaID()
        local ZoneList = L:GetModule("ZoneList", true)
        local zoneInfo = ZoneList and ZoneList.MapDataByID[mapID]

        if zoneInfo then
            c = zoneInfo.continentID 
            z = mapID
            iz = 0
        else
            z = mapID
            iz = mapID
        end
        
        px, py = GetPlayerMapPosition("player")
        px = px or 0; py = py or 0
    end

    if FORBIDDEN_CITY_ZONES[c] and FORBIDDEN_CITY_ZONES[c][z] then
        return
    end

    local discovery = { il = link, c = c, z = z, iz = iz, xy = { x = px, y = py }, t0 = now, src = src, fp = looterName }
    local Core = L:GetModule("Core", true)
    if Core and Core.HandleLocalLoot then
        
        local itemID = tonumber(link:match("item:(%d+)"))
        local guid = L:GenerateGUID(c, z, itemID, px, py)
        self._lastDiscoveryGUID = guid
        self._lastDiscoveryTime = now
        Core:HandleLocalLoot(discovery)
    end
    local itemID = tonumber(link:match("item:(%d+)"))
    if itemID then
        L:SendMessage("LOOTCOLLECTOR_PLAYER_LOOTED_ITEM", itemID, c, z, px, py)
    end
end

function Detect:OnBagUpdate(event, bagID)
    if not bagID then return end
    
    local now = time()
    if now > self._expectingItemUntil then
        return
    end
    
    for link, timestamp in pairs(self._recent) do
        if now - timestamp > 3.0 then
            self._recent[link] = nil
        end
    end
    
    for slotID = 1, GetContainerNumSlots(bagID) do
        local link = GetContainerItemLink(bagID, slotID)
        if link and not self._recent[link] then
            self._recent[link] = now

            local isWF, isMS = self:Qualifies(link, "direct")
            if isMS and not isWF then 
                self:ProcessPotentialDiscovery(link, "bag_update", UnitName("player"))
            end
        end
    end
end

return Detect