-- Detect.lua (3.3.5-safe)
-- Source-aware filtering for LootCollector:
-- - Only process “Worldforged” and “Mystic Scroll” items.
-- - Classify direct-to-bag scrolls: world_loot, mail, npc_gossip, emote_event, direct.
-- - Skip mail, quest, trade, and crafting sources to avoid false coordinates.

local L = LootCollector
local Detect = L:NewModule("Detect", "AceEvent-3.0")

-- Off-screen tooltip scanner for “Worldforged” subtitle
local SCAN_TIP_NAME = "LootCollectorScanTip"
local scanTip

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

Detect._cache = { isWF = {}, isMS = {}, }
Detect._recent = {}

function Detect:IsWorldforged(link)
  local c = self._cache.isWF[link]; if c ~= nil then return c end; local ok = TooltipHas(link, "Worldforged"); self._cache.isWF[link] = ok and true or false; return self._cache.isWF[link]
end

function Detect:IsMysticScroll(link, source)
  local name = (link and select(1, GetItemInfo(link))) or (link and link:match("%[(.-)%]")) or ""
  if not name or name == "" then
    return false
  end

  -- Check ignore lists first
  if L.ignoreList and L.ignoreList[name] then
    return false
  end
  if L.sourceSpecificIgnoreList and L.sourceSpecificIgnoreList[name] then
    -- This item is on the conditional list. Only allow from 'world_loot' or 'direct' (unidentified world drop) source.
    if source ~= "world_loot" and source ~= "direct" then
      return false
    end
  end

  local isMystic = string.find(name, "Mystic Scroll", 1, true)
  return isMystic and true or false
end

function Detect:Qualifies(link, source)
  if not link then return false end
  return self:IsWorldforged(link) or self:IsMysticScroll(link, source)
end

-- UPDATED: Context state tracking table
Detect._ctx = { 
    lastLootOpenedAt = nil, 
    lastGossipAt = nil, 
    lastEmoteAt = nil, 
    lastMailTakeAt = nil, 
    mailOpen = false,
    --  Additional states for source detection
    lastQuestCompleteAt = nil,
    lastTradeAcceptedAt = nil,
    tradeOpen = false,
    craftingOpen = false,
}


function Detect:OnInitialize()
  self:RegisterEvent("LOOT_OPENED", function() self._ctx.lastLootOpenedAt = time() end)
  self:RegisterEvent("GOSSIP_SHOW", function() self._ctx.lastGossipAt = time() end)
  self:RegisterEvent("GOSSIP_CLOSED", function() self._ctx.lastGossipAt = time() end)
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
  
  if hooksecurefunc then 
    hooksecurefunc("TakeInboxItem", function() Detect._ctx.lastMailTakeAt = time() end)
    hooksecurefunc("DoEmote", function() Detect._ctx.lastEmoteAt = time() end) 
  end
end


local function classifySource(ctx, now)
  -- High-priority checks for invalid sources
  if ctx.mailOpen or (ctx.lastMailTakeAt and (now - ctx.lastMailTakeAt <= 3)) then return "mail" end
  if ctx.tradeOpen or (ctx.lastTradeAcceptedAt and (now - ctx.lastTradeAcceptedAt <= 3)) then return "trade" end
  if ctx.lastQuestCompleteAt and (now - ctx.lastQuestCompleteAt <= 3) then return "quest_reward" end
  if ctx.craftingOpen then return "crafting" end

  -- Standard checks for valid or ambiguous sources
  if ctx.lastLootOpenedAt and (now - ctx.lastLootOpenedAt <= 3) then return "world_loot" end
  if ctx.lastGossipAt and (now - ctx.lastGossipAt <= 5) then return "npc_gossip" end
  if ctx.lastEmoteAt and (now - ctx.lastEmoteAt <= 5) then return "emote_event" end
  
  return "direct" -- Fallback for items appearing in bags without other context
end

-- OnChatMsgLoot to filter out all invalid sources
function Detect:OnChatMsgLoot(event, msg)
  local link = msg and msg:match("|Hitem:%d+:[^|]+|h%[[^%]]+%]|h"); if not link then return end
  local now = time()
  local src = classifySource(self._ctx, now)

  -- First, check if the item is something we would ever care about, regardless of source.
  if not self:Qualifies(link, src) then return end

  -- Debounce duplicate messages for the same item
  local last = self._recent[link] or 0; if now - last < 1.0 then return end
  self._recent[link] = now

  -- Central block for all ignored sources.
  -- We do not process items from these sources because they lack valid coordinates.
  -- "world_loot" is handled by Core:OnLootOpened, not here.
  if src == "mail" or src == "quest_reward" or src == "trade" or src == "crafting" or src == "world_loot" then
    return -- Silently ignore items from these sources in this handler.
  end

  local px, py = GetPlayerMapPosition("player")
  px, py = px or 0, py or 0
  
  local discovery = {
    itemLink = link,
    zone     = GetRealZoneText(),
    subZone  = GetSubZoneText(),
    zoneID   = GetCurrentMapZone() or 0,
    continentID = GetCurrentMapContinent() or 0,
    coords   = { x = px, y = py },
    foundByplayer = UnitName("player"),
    foundByclass  = select(2, UnitClass("player")),
    timestamp = now,
    source    = src,
  }

  local Core = L:GetModule("Core", true)
  if Core and Core.HandleLocalLoot then
    Core:HandleLocalLoot(discovery)
  end
end

return Detect