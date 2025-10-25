-- Detect.lua (3.3.5-safe)
-- UNK.B64-UTF-8


local L = LootCollector
local Detect = L:NewModule("Detect", "AceEvent-3.0")

local SCAN_TIP_NAME = "LootCollectorScanTip"
local scanTip
local LEGACY_DETECT_MODE = false 

local FORBIDDEN_CITY_ZONES = {
    [1] = { 
        [10] = true, 
        [22] = true, 
        [35] = true, 
        [41] = true, 
    },
    [2] = { 
        [23] = true, 
        [37] = true, 
        [46] = true, 
    },
    [3] = { 
        [6] = true, 
    },
    [4] = { 
        [3] = true, 
    }
}

local NPCScanTip = CreateFrame("GameTooltip", "LootCollector_NPCScanTip", UIParent, "GameTooltipTemplate")
NPCScanTip:SetOwner(UIParent, "ANCHOR_NONE")

local lastLootContext = {
    openedAt = 0,
    c = 0, z = 0, iz = 0,
    x = 0, y = 0,
}

local LOOT_VALIDITY_WINDOW = 20
local ITEM_EXPECTATION_WINDOW = 9.0 -- Seconds after an event to expect an item in bags

Detect._expectingItemUntil = 0
Detect._expectedItemLink = nil

function Detect:Debug(msg, ...) return end

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
  lastTradeAcceptedAt = nil,
  tradeOpen = false,
  craftingOpen = false,
  
  bankOpen = false,
  guildBankOpen = false,
  lastAchievementAt = nil,
  lastBuybackAt = nil,
}

local function GetNPCSubname(unit)
  if not unit or not UnitExists(unit) then return nil end
  NPCScanTip:ClearLines()
  NPCScanTip:SetUnit(unit)
  local line2 = _G["LootCollector_NPCScanTipTextLeft2"]
  local text = line2 and line2:IsShown() and line2:GetText() or nil

  
  if text and tonumber(text:match("(%d+)")) then
    return nil
  end
  return text
end

local function IsBlackmarketArtisan(unit)
  local sub = GetNPCSubname(unit)
  
  return sub and sub:find("Blackmarket Artisan Supplies", 1, true) ~= nil
end

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

function Detect:OnNPCInteraction()
    local unitToCheck = "npc"
    if not UnitExists(unitToCheck) then return end

    local merchantItems = ScanMerchant()
    
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

    if not isMSVendor and not isBMVendor then
        return
    end

    local vendorType, placeholderLink
    if isMSVendor then
        vendorType = "MS"
        placeholderLink = string.format("|cffa335ee|Hitem:-4:0:0:0:0:0:0:0:0|h[Mystic Scroll Vendor]|h|r")
    elseif isBMVendor then
        vendorType = "BM"
        placeholderLink = string.format("|cff663300|Hitem:-3:0:0:0:0:0:0:0:0|h[Blackmarket Supplies]|h|r")
    end

    local now = time()
    local px, py = GetPlayerMapPosition("player")
    px = px or 0; py = py or 0
    if (px == 0 and py == 0) and SetMapToCurrentZone then
        SetMapToCurrentZone()
        local nx, ny = GetPlayerMapPosition("player")
        if nx and ny then px, py = nx, ny end
    end
    
    local c = GetCurrentMapContinent and GetCurrentMapContinent() or 0
    local z = GetCurrentMapZone and GetCurrentMapZone() or 0
    local iz = 0
    if z == 0 then
        local ZL = L:GetModule("ZoneList", true)
        if ZL and ZL.ResolveInstanceIz then
            local live = GetRealZoneText() or GetZoneText()
            iz = ZL:ResolveInstanceIz(live)
        end
    end
    
    local mapID = GetCurrentMapAreaID()

    local Constants = L:GetModule("Constants", true)
    local discovery = {
        il = placeholderLink,
        i = (vendorType == "MS" and -4 or -3),
        c = c,
        z = z,
        iz = iz,
        mapID = mapID, 
        xy = { x = px, y = py },
        t0 = now,
        src = "merchant",
        fp = UnitName("player"),
        dt = Constants and Constants.DISCOVERY_TYPE.BLACKMARKET,
        vendorType = vendorType,
        vendorItems = merchantItems,
        vendorName = UnitName(unitToCheck),
    }

    local Core = L:GetModule("Core", true)
    if Core and Core.HandleLocalLoot then
        Core:HandleLocalLoot(discovery)
    end
end

function Detect:OnLootOpened()
    self._ctx.lastLootOpenedAt = time() 
    
    lastLootContext.openedAt = time()
    
    local px, py = GetPlayerMapPosition("player")
    lastLootContext.x = px or 0
    lastLootContext.y = py or 0
    
    if (lastLootContext.x == 0 and lastLootContext.y == 0) and SetMapToCurrentZone then
        SetMapToCurrentZone()
        local nx, ny = GetPlayerMapPosition("player")
        if nx and ny then
            lastLootContext.x = nx
            lastLootContext.y = ny
        end
    end
    
    lastLootContext.c = GetCurrentMapContinent and GetCurrentMapContinent() or 0
    lastLootContext.z = GetCurrentMapZone and GetCurrentMapZone() or 0
    
    local iz = 0
    if lastLootContext.z == 0 then
        local ZL = L:GetModule("ZoneList", true)
        if ZL and ZL.ResolveInstanceIz then
            local live = GetRealZoneText() or GetZoneText()
            iz = ZL:ResolveInstanceIz(live)
        end
    end
    lastLootContext.iz = iz
    
end

function Detect:OnLootClosed()
    self._expectingItemUntil = GetTime() + ITEM_EXPECTATION_WINDOW
end

function Detect:OnInitialize()
  
  self:RegisterEvent("LOOT_OPENED", "OnLootOpened")
  self:RegisterEvent("LOOT_CLOSED", "OnLootClosed")
  
  self:RegisterEvent("BAG_UPDATE", "OnBagUpdate")

  self:RegisterEvent("GOSSIP_SHOW", function() self._ctx.lastGossipAt = time(); self:OnNPCInteraction() end)
  self:RegisterEvent("GOSSIP_CLOSED", function() self._ctx.lastGossipAt = time(); self._expectingItemUntil = GetTime() + ITEM_EXPECTATION_WINDOW end)
  self:RegisterEvent("MERCHANT_SHOW", function() self._ctx.lastMerchantAt = time(); self:OnNPCInteraction() end)
  self:RegisterEvent("MERCHANT_UPDATE", function() self._ctx.lastMerchantAt = time(); self:OnNPCInteraction() end)
  self:RegisterEvent("MAIL_SHOW", function() self._ctx.mailOpen = true end)
  self:RegisterEvent("MAIL_CLOSED", function() self._ctx.mailOpen = false end)
  self:RegisterEvent("CHAT_MSG_LOOT", "OnChatMsgLoot")
  self:RegisterEvent("QUEST_COMPLETE", function() self._ctx.lastQuestCompleteAt = time() end)
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

  if hooksecurefunc then
    hooksecurefunc("TakeInboxItem", function() Detect._ctx.lastMailTakeAt = time() end)
    hooksecurefunc("DoEmote", function() Detect._ctx.lastEmoteAt = time() end)
    hooksecurefunc("BuybackItem", function() Detect._ctx.lastBuybackAt = time() end)
  end
end

local function classifySource(ctx, now)
  if ctx.mailOpen or (ctx.lastMailTakeAt and (now - ctx.lastMailTakeAt <= 3)) then return "mail" end
  if ctx.tradeOpen or (ctx.lastTradeAcceptedAt and (now - ctx.lastTradeAcceptedAt <= 3)) then return "trade" end
  if ctx.bankOpen then return "bank" end
  if ctx.guildBankOpen then return "guild_bank" end
  if ctx.lastQuestCompleteAt and (now - ctx.lastQuestCompleteAt <= 3) then return "quest_reward" end
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
  if src == "mail" or src == "quest_reward" or src == "trade" or src == "crafting" or src == "mystic_altar" or src == "vendor" or src == "bank" or src == "guild_bank" or src == "achievement" or src == "npc_gossip" then
      return
  end
  
  if (now - lastLootContext.openedAt) > LOOT_VALIDITY_WINDOW then
      return
  end

  if FORBIDDEN_CITY_ZONES[lastLootContext.c] and FORBIDDEN_CITY_ZONES[lastLootContext.c][lastLootContext.z] then
      if self:IsMysticScroll(link, src) then 
          return
      end
  end

  if not self:Qualifies(link, "world_loot") then return end

  local last = self._recent[link] or 0
  if now - last < 1.0 then return end
  self._recent[link] = now

  local discovery = {
    il        = link,
    c         = lastLootContext.c,
    z         = lastLootContext.z,
    iz        = lastLootContext.iz,
    xy        = { x = lastLootContext.x, y = lastLootContext.y },
    t0        = now,
    src       = "world_loot",
    fp        = looter,
  }

  local Core = L:GetModule("Core", true)
  if Core and Core.HandleLocalLoot then
      Core:HandleLocalLoot(discovery)
  end

  local itemID = tonumber(link:match("item:(%d+)"))
  if itemID then
      L:SendMessage("LOOTCOLLECTOR_PLAYER_LOOTED_ITEM", itemID, discovery.c, discovery.z, discovery.xy.x, discovery.xy.y)
  end
end

function Detect:ProcessPotentialDiscovery(link, sourceHint, looterName)
    local now = time()
    looterName = looterName or UnitName("player")

    local src = classifySource(self._ctx, now)

    local deniedSources = {
        mail = true, quest_reward = true, trade = true, crafting = true,
        mystic_altar = true, vendor = true, vendor_buyback = true,
        bank = true, guild_bank = true, achievement = true,
    }

    if deniedSources[src] then
        return
    end

    local isWF, isMS = self:Qualifies(link, src)

    if not isWF and not isMS then
        return
    end

    if isWF and src ~= "world_loot" then
        return
    end
    
    local c, z, iz, px, py
    if src == "world_loot" and (now - lastLootContext.openedAt) <= LOOT_VALIDITY_WINDOW then
        c, z, iz, px, py = lastLootContext.c, lastLootContext.z, lastLootContext.iz, lastLootContext.x, lastLootContext.y
    else
        px, py = GetPlayerMapPosition("player")
        px = px or 0; py = py or 0
        if (px == 0 and py == 0) and SetMapToCurrentZone then
            SetMapToCurrentZone()
            local nx, ny = GetPlayerMapPosition("player")
            if nx and ny then px, py = nx, ny end
        end
        c = GetCurrentMapContinent and GetCurrentMapContinent() or 0
        z = GetCurrentMapZone and GetCurrentMapZone() or 0
        iz = 0
        if z == 0 then
            local ZL = L:GetModule("ZoneList", true)
            if ZL and ZL.ResolveInstanceIz then
                local live = GetRealZoneText() or GetZoneText()
                iz = ZL:ResolveInstanceIz(live)
            end
        end
    end

    if isMS and src == "world_loot" then
        if FORBIDDEN_CITY_ZONES[c] and FORBIDDEN_CITY_ZONES[c][z] then
            return
        end
    end

    local discovery = {
        il = link, c = c, z = z, iz = iz,
        xy = { x = px, y = py }, t0 = now,
        src = src, fp = looterName,
    }
    
    local Core = L:GetModule("Core", true)
    if Core and Core.HandleLocalLoot then
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
-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl