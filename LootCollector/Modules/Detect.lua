local L = LootCollector
local Detect = L:NewModule("Detect", "AceEvent-3.0")

local LEGACY_DETECT_MODE = false 

Detect.recentlyScannedNPCs = Detect.recentlyScannedNPCs or {} 
Detect._cache, Detect._recent = { isWF = {}, isMS = {} }, {}
Detect._dirtyBags = {}
Detect._bagUpdateTimer = nil

Detect._lastDiscoveryGUID = nil
Detect._lastDiscoveryTime = 0
Detect._recoverySuppressionUntil = 0
local RECOVERY_SUPPRESSION_WINDOW = 9.0

local NPCScanTip = CreateFrame("GameTooltip", "LootCollector_NPCScanTip", UIParent, "GameTooltipTemplate")
NPCScanTip:SetOwner(UIParent, "ANCHOR_NONE")

local lastLootContext = {
    openedAt = 0,
    mapID = 0,
    c = 0, z = 0, iz = 0,
    x = 0, y = 0,
}
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
local LOOT_VALIDITY_WINDOW = 20
local ITEM_EXPECTATION_WINDOW = 9.0 

Detect._expectingItemUntil = 0
Detect._expectedItemLink = nil

function Detect:Debug(msg, ...) return end

local function ParseItemID(link)
  if not link then return nil end
  return tonumber(link:match("item:(%d+)"))
end

local SCAN_TIP_NAME = "LootCollectorDetectScanTip"
local scanTip = nil

local function EnsureScanTip()
    if scanTip then return end
    scanTip = CreateFrame("GameTooltip", SCAN_TIP_NAME, nil, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
end

local function TooltipHas(link, needle)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not link or not needle then 
        if pTime then L:ProfileStop("Scanner:TooltipHas", pTime) end
        return false 
    end
    EnsureScanTip()
    scanTip:ClearLines()
    scanTip:SetHyperlink(link)
    
    
    for i = 2, 5 do
        local fs = _G[SCAN_TIP_NAME .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        if text and string.find(string.lower(text), string.lower(needle), 1, true) then
            if pTime then L:ProfileStop("Scanner:TooltipHas", pTime) end
            return true
        end
    end
    
    
    local line1Left = _G[SCAN_TIP_NAME .. "TextLeft1"]
    if line1Left and line1Left:GetText() == "Retrieving item information..." then
        if pTime then L:ProfileStop("Scanner:TooltipHas", pTime) end
        return nil 
    end
    
    if pTime then L:ProfileStop("Scanner:TooltipHas", pTime) end
    return false
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

  if text then
      
      local cleanText = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      if cleanText:match("^Level %d") or tonumber(cleanText:match("(%d+)")) then
          return nil
      end
  end
  return text
end

function Detect:IsWorldforged(link)
    local c = self._cache.isWF[link]
    if c ~= nil then return c end

    
    local ok = TooltipHas(link, "worldforged")
    
    if ok == nil then
        L._ddebug("Detect", string.format("IsWorldforged scan for %s: Retrieving item data (nil from TooltipHas)", tostring(link)))
        return nil 
    end

    L._ddebug("Detect", string.format("IsWorldforged scan for %s: %s", tostring(link), tostring(ok)))
    self._cache.isWF[link] = ok
    return ok
end

function Detect:IsMysticScroll(link, source)
  local Constants = L:GetModule("Constants", true)
  if Constants and not Constants:HasMysticScrolls() then return false end

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
  local isWF = self:IsWorldforged(link)
  local isMS = self:IsMysticScroll(link, source)
  
  
  if isWF == nil then
      L._ddebug("Detect", string.format("Qualifies check for %s | WF: Data Not Ready, MS: %s", tostring(link), tostring(isMS)))
      return nil
  end
  
  L._ddebug("Detect", string.format("Qualifies check for %s | WF: %s, MS: %s", tostring(link), tostring(isWF), tostring(isMS)))
  return isWF or isMS
end

function Detect:OnRetroactiveSuppressionEvent(event, arg1, arg2)
    local shouldSuppress = false
    local reason = "Unknown"

    if event == "UI_INFO_MESSAGE" and arg1 == "|cFF2EF50EItem recovery completed|r" then
        shouldSuppress = true
        reason = "item recovery"
    elseif event == "RECOVERY_RESULT" and arg2 and type(arg2) == "string" and string.find(arg2, "_OK$") then
        shouldSuppress = true
        reason = "item recovery"
    elseif event == "PURCHASE_CUSTOM_STORE_ITEM_RESULT" and arg1 == "PURCHASE_CUSTOM_STORE_ITEM_OK" then
        
        shouldSuppress = true
        reason = "store purchase or upgrade"
    end

    if shouldSuppress then
        L._ddebug("Detect", "Retroactive suppression event detected: " .. event)
        local now = GetTime()
        
        
        if self._lastDiscoveryGUID and (now - self._lastDiscoveryTime < 2.5) then
            local Core = L:GetModule("Core", true)
            if Core and Core.RemoveDiscoveryByGuid then
                L._ddebug("Detect", "Retroactively removing false discovery due to " .. reason .. ": " .. self._lastDiscoveryGUID)
                Core:RemoveDiscoveryByGuid(self._lastDiscoveryGUID, "Discovery suppressed due to " .. reason .. ".")
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

function Detect:OnNPCInteraction()
if L:IsPaused() then return end
    local unitToCheck = "npc"
    if not UnitExists(unitToCheck) then return end

    local npcGUID = UnitGUID(unitToCheck)
    if not npcGUID then return end

    
    if self.recentlyScannedNPCs[npcGUID] and (time() - self.recentlyScannedNPCs[npcGUID] < 10) then
        return
    end

    local isBMVendor = IsBlackmarketArtisan(unitToCheck)
    local isMSVendor = false

    local merchantItems = {}
    if GetMerchantNumItems() > 0 then
        merchantItems = ScanMerchant()
    end

    local Constants = L:GetModule("Constants", true)
    if not isBMVendor and Constants and Constants:HasMysticScrolls() then
        for _, itemData in ipairs(merchantItems) do
            if itemData.name and string.find(itemData.name, "Mystic Scroll", 1, true) then
                isMSVendor = true
                break
            end
        end
    end

    if not isMSVendor and not isBMVendor then return end
    
    
    self.recentlyScannedNPCs[npcGUID] = time()

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

    local discovery = {
        c = c, z = z, iz = iz, mapID = mapID,
        xy = { x = px, y = py }, 
        t0 = now,
        src = "merchant",
        vendorType = vendorType, 
        vendorName = UnitName(unitToCheck),
        vendorItems = merchantItems, 
        fp = UnitName("player"),
        dt = Constants and Constants.DISCOVERY_TYPE.BLACKMARKET,
    }

    local Core = L:GetModule("Core", true)
    if Core and Core.HandleLocalLoot then
        L._ddebug("Detect", string.format("Passing Vendor %s (%s) to Core.", discovery.vendorName, vendorType))
        Core:HandleLocalLoot(discovery)
    end
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

  
  self:RegisterEvent("GOSSIP_SHOW", function() self._ctx.lastGossipAt = time(); self:OnNPCInteraction() end)
  self:RegisterEvent("GOSSIP_CLOSED", function() self._ctx.lastGossipAt = time(); self._expectingItemUntil = GetTime() + ITEM_EXPECTATION_WINDOW end)
  self:RegisterEvent("MERCHANT_SHOW", function() self._ctx.lastMerchantAt = time(); self:OnNPCInteraction() end)
  self:RegisterEvent("MERCHANT_UPDATE", function() self._ctx.lastMerchantAt = time(); self:OnNPCInteraction() end)
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

  self:RegisterEvent("UI_INFO_MESSAGE", "OnRetroactiveSuppressionEvent")
  self:RegisterEvent("RECOVERY_RESULT", "OnRetroactiveSuppressionEvent")
  self:RegisterEvent("PURCHASE_CUSTOM_STORE_ITEM_RESULT", "OnRetroactiveSuppressionEvent")

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
    local pTime = L.ProfileStart and L:ProfileStart() 

    if L:IsPaused() then 
        if pTime then L:ProfileStop("Detect:OnChatMsgLoot", pTime) end 
        return 
    end

    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.ALLOW_PVP_INSTANCES == false then
        local isInstance, instanceType = IsInInstance()
        if isInstance and (instanceType == "pvp" or instanceType == "arena") then
            L._ddebug("Detect", "Dropped: Loot event occurred inside a PvP instance.")
            if pTime then L:ProfileStop("Detect:OnChatMsgLoot", pTime) end 
            return
        end
    end
    L._ddebug("Detect", "OnChatMsgLoot fired: " .. tostring(msg))
    
    local link = msg and msg:match("|Hitem:%d+:[^|]+|h%[[^%]]+%]|h")
    if not link then 
        L._ddebug("Detect", "Dropped: No item link found in chat message.")
        if pTime then L:ProfileStop("Detect:OnChatMsgLoot", pTime) end 
        return 
    end

    local _, _, playerName = string.find(msg, "([^%s]+)%s+receives loot:")
    local looter = playerName or UnitName("player")
    
    if looter ~= UnitName("player") then 
        L._ddebug("Detect", string.format("Ignored third-party loot event from '%s'. Awaiting their network broadcast to prevent coordinate desync.", tostring(looter)))
        if pTime then L:ProfileStop("Detect:OnChatMsgLoot", pTime) end 
        return 
    end
    
    local nowTime = time()
    local src = classifySource(self._ctx, nowTime)
    L._ddebug("Detect", "Source originally classified as: " .. tostring(src))

    local isWF = self:IsWorldforged(link)
    if isWF and src == "quest_reward" then
        if lastLootContext.openedAt and (nowTime - lastLootContext.openedAt) <= LOOT_VALIDITY_WINDOW then
            src = "world_loot"
            L._ddebug("Detect", "Override: Changed quest_reward to world_loot (WF items do not come from quests)")      
        end
    end

    local deniedSources = { mail = true, quest_reward = true, trade = true, crafting = true, mystic_altar = true, vendor = true, bank = true, guild_bank = true, achievement = true }
    if deniedSources[src] then 
        L._ddebug("Detect", "Dropped: Source is in denied list (" .. tostring(src) .. ")")
        if pTime then L:ProfileStop("Detect:OnChatMsgLoot", pTime) end 
        return 
    end

    if src == "world_loot" and (nowTime - lastLootContext.openedAt) > LOOT_VALIDITY_WINDOW then 
        L._ddebug("Detect", "Dropped: world_loot timeframe expired (Window closed).")
        if pTime then L:ProfileStop("Detect:OnChatMsgLoot", pTime) end 
        return 
    end

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
    
    if Constants and Constants.IsForbiddenZone and Constants:IsForbiddenZone(c, z, looter) then
        L._ddebug("Detect", "Dropped: Looted inside a forbidden zone.")
        if pTime then L:ProfileStop("Detect:OnChatMsgLoot", pTime) end 
        return
    end

    local qualifies = self:Qualifies(link, src)
    
    if qualifies == nil then
        L._ddebug("Detect", "Data not ready. Queueing cache request and delaying CHAT_MSG_LOOT evaluation by 1 second.")
        local itemID = tonumber(link:match("item:(%d+)"))
        if itemID then
            local Core = L:GetModule("Core", true)
            if Core and Core.QueueItemForCaching then
                Core:QueueItemForCaching(itemID)
                Core:EnsureCachePump()
            end
        end
        L:ScheduleAfter(1.0, function()
            self:OnChatMsgLoot(nil, msg)
        end)
        if pTime then L:ProfileStop("Detect:OnChatMsgLoot", pTime) end 
        return
    elseif qualifies == false then
        L._ddebug("Detect", "Dropped: Item does not qualify (Not WF or MS).")
        if pTime then L:ProfileStop("Detect:OnChatMsgLoot", pTime) end 
        return 
    end
    
    local last = self._recent[link] or 0
    if nowTime - last < 1.0 then 
        L._ddebug("Detect", "Dropped: Throttled (Looted multiple in <1s).")
        if pTime then L:ProfileStop("Detect:OnChatMsgLoot", pTime) end 
        return 
    end
    self._recent[link] = nowTime

    L._ddebug("Detect", "SUCCESS: Passing " .. tostring(link) .. " to Core:HandleLocalLoot.")
    local discovery = { il = link, c = c, z = z, iz = iz, xy = { x = x_val, y = y_val }, t0 = nowTime, src = src, fp = looter }
    local Core = L:GetModule("Core", true)
    if Core and Core.HandleLocalLoot then
        local itemID = tonumber(link:match("item:(%d+)"))
        local guid = L:GenerateGUID(c, z, iz, itemID, x_val, y_val)
        self._lastDiscoveryGUID = guid
        self._lastDiscoveryTime = nowTime
        Core:HandleLocalLoot(discovery)
    end
    
    local itemID = tonumber(link:match("item:(%d+)"))
    if itemID then
        L:SendMessage("LOOTCOLLECTOR_PLAYER_LOOTED_ITEM", itemID, c, z, x_val, y_val)
    end
    
    if pTime then L:ProfileStop("Detect:OnChatMsgLoot", pTime) end 
end

function Detect:ProcessPotentialDiscovery(link, sourceHint, looterName)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if L:IsPaused() then 
        if pTime then L:ProfileStop("Detect:ProcessPotentialDiscovery", pTime) end 
        return 
    end

    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.ALLOW_PVP_INSTANCES == false then
        local isInstance, instanceType = IsInInstance()
        if isInstance and (instanceType == "pvp" or instanceType == "arena") then
            L._ddebug("Detect", "Dropped: Loot event occurred inside a PvP instance.")
            if pTime then L:ProfileStop("Detect:ProcessPotentialDiscovery", pTime) end 
            return
        end
    end
    
    local nowTime = time()
    looterName = looterName or UnitName("player")
    local src = classifySource(self._ctx, nowTime)
        
    local isWF = self:IsWorldforged(link)
    if isWF and src == "quest_reward" then
        if lastLootContext.openedAt and (nowTime - lastLootContext.openedAt) <= LOOT_VALIDITY_WINDOW then
            src = "world_loot"  
		end			
    end

    local deniedSources = { mail = true, quest_reward = true, trade = true, crafting = true, mystic_altar = true, vendor = true, vendor_buyback = true, bank = true, guild_bank = true, achievement = true }
    if deniedSources[src] then 
        if pTime then L:ProfileStop("Detect:ProcessPotentialDiscovery", pTime) end 
        return 
    end

    local isMS = self:IsMysticScroll(link, src)
    if not isWF and not isMS then 
        if pTime then L:ProfileStop("Detect:ProcessPotentialDiscovery", pTime) end 
        return 
    end
    if isWF and src ~= "world_loot" then 
        if pTime then L:ProfileStop("Detect:ProcessPotentialDiscovery", pTime) end 
        return 
    end
    
    local c, z, iz, px, py
    if src == "world_loot" and (nowTime - lastLootContext.openedAt) <= LOOT_VALIDITY_WINDOW then
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

    if Constants and Constants.IsForbiddenZone and Constants:IsForbiddenZone(c, z, looterName) then
        if pTime then L:ProfileStop("Detect:ProcessPotentialDiscovery", pTime) end 
        return
    end

    local discovery = { il = link, c = c, z = z, iz = iz, xy = { x = px, y = py }, t0 = nowTime, src = src, fp = looterName }
    local Core = L:GetModule("Core", true)
    if Core and Core.HandleLocalLoot then
        local itemID = tonumber(link:match("item:(%d+)"))
        local guid = L:GenerateGUID(c, z, iz, itemID, px, py)
        self._lastDiscoveryGUID = guid
        self._lastDiscoveryTime = nowTime
        Core:HandleLocalLoot(discovery)
    end
    
    local itemID = tonumber(link:match("item:(%d+)"))
    if itemID then
        L:SendMessage("LOOTCOLLECTOR_PLAYER_LOOTED_ITEM", itemID, c, z, px, py)
    end
    
    if pTime then L:ProfileStop("Detect:ProcessPotentialDiscovery", pTime) end 
end

local function ProcessDirtyBags()
    local pTime = L.ProfileStart and L:ProfileStart() 

    Detect._bagUpdateTimer = nil
    if L:IsPaused() then 
        if pTime then L:ProfileStop("Detect:ProcessDirtyBags", pTime) end 
        return 
    end
    
    local now = time()
    if now > Detect._expectingItemUntil then
        wipe(Detect._dirtyBags)
        if pTime then L:ProfileStop("Detect:ProcessDirtyBags", pTime) end 
        return
    end
    
    for link, timestamp in pairs(Detect._recent) do
        if now - timestamp > 3.0 then
            Detect._recent[link] = nil
        end
    end
    
    for bagID in pairs(Detect._dirtyBags) do
        for slotID = 1, GetContainerNumSlots(bagID) do
            local link = GetContainerItemLink(bagID, slotID)
            if link and not Detect._recent[link] then
                local qualifies = Detect:Qualifies(link, "direct")
                
                if qualifies == nil then
                    local itemID = tonumber(link:match("item:(%d+)"))
                    if itemID then
                        local Core = L:GetModule("Core", true)
                        if Core and Core.QueueItemForCaching then
                            Core:QueueItemForCaching(itemID)
                            Core:EnsureCachePump()
                        end
                    end
                else
                    Detect._recent[link] = now
                    if qualifies then 
                        Detect:ProcessPotentialDiscovery(link, "bag_update", UnitName("player"))
                    end
                end
            end
        end
    end
    wipe(Detect._dirtyBags)
    
    if pTime then L:ProfileStop("Detect:ProcessDirtyBags", pTime) end 
end

function Detect:OnBagUpdate(event, bagID)
    if not bagID then return end
    self._dirtyBags[bagID] = true
    if not self._bagUpdateTimer then
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            self._bagUpdateTimer = C_Timer.After(0.2, ProcessDirtyBags)
        else
            
            ProcessDirtyBags()
        end
    end
end

return Detect