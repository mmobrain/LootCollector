-- Detect.lua (3.3.5-safe)
-- Source-aware filtering for LootCollector:
-- - Only process “Worldforged” and “Mystic Scroll” items.
-- - Classify direct-to-bag scrolls: world_loot, mail, npc_gossip, emote_event, direct.
-- - Skip mail sources for map discoveries to avoid false coordinates.

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
  -- Lines 2..5: the “under name” area and early descriptors on 3.3.5
  for i = 2, 5 do
    local fs = _G[SCAN_TIP_NAME .. "TextLeft" .. i]
    local text = fs and fs:GetText()
    if text and string.find(string.lower(text), string.lower(needle), 1, true) then
      return true
    end
  end
  return false
end

-- Simple caches to avoid repeated scans
Detect._cache = {
  isWF = {},  -- link -> bool
  isMS = {},  -- link -> bool
}
Detect._recent = {} -- link -> last processed time for CHAT_MSG_LOOT de-dupe

function Detect:IsWorldforged(link)
  local c = self._cache.isWF[link]
  if c ~= nil then return c end
  local ok = TooltipHas(link, "Worldforged")
  self._cache.isWF[link] = ok and true or false
  return self._cache.isWF[link]
end

function Detect:IsMysticScroll(link)
  local c = self._cache.isMS[link]
  if c ~= nil then return c end
  local name = (link and select(1, GetItemInfo(link))) or (link and link:match("%[(.-)%]")) or ""
  local ok = (name and string.find(name, "Mystic Scroll", 1, true) ~= nil) and true or false
  self._cache.isMS[link] = ok
  return ok
end

function Detect:Qualifies(link)
  if not link then return false end
  return self:IsWorldforged(link) or self:IsMysticScroll(link)
end

-- Context timeline for source classification
Detect._ctx = {
  lastLootOpenedAt = nil,
  lastGossipAt = nil,
  lastEmoteAt = nil,
  lastMailTakeAt = nil,
  mailOpen = false,
}

function Detect:OnInitialize()
  -- Event taps for context
  self:RegisterEvent("LOOT_OPENED", function() self._ctx.lastLootOpenedAt = time() end)
  self:RegisterEvent("LOOT_CLOSED", function() end)
  self:RegisterEvent("GOSSIP_SHOW", function() self._ctx.lastGossipAt = time() end)
  self:RegisterEvent("GOSSIP_CLOSED", function() self._ctx.lastGossipAt = time() end)
  self:RegisterEvent("MAIL_SHOW", function() self._ctx.mailOpen = true end)
  self:RegisterEvent("MAIL_CLOSED", function() self._ctx.mailOpen = false end)
  self:RegisterEvent("CHAT_MSG_LOOT", "OnChatMsgLoot")

  -- Hooks: mailbox take and player emotes
  if hooksecurefunc then
    hooksecurefunc("TakeInboxItem", function()
      Detect._ctx.lastMailTakeAt = time()
    end)
    hooksecurefunc("DoEmote", function()
      Detect._ctx.lastEmoteAt = time()
    end)
  end
end

local function classifySource(ctx, now)
  if ctx.mailOpen or (ctx.lastMailTakeAt and (now - ctx.lastMailTakeAt <= 3)) then
    return "mail"
  end
  if ctx.lastLootOpenedAt and (now - ctx.lastLootOpenedAt <= 3) then
    return "world_loot"
  end
  if ctx.lastGossipAt and (now - ctx.lastGossipAt <= 5) then
    return "npc_gossip"
  end
  if ctx.lastEmoteAt and (now - ctx.lastEmoteAt <= 5) then
    return "emote_event"
  end
  return "direct"
end

function Detect:OnChatMsgLoot(event, msg)
  -- Extract the first item link from the loot chat line (3.3.5 pattern)
  local link = msg and msg:match("|Hitem:%d+:[^|]+|h%[[^%]]+%]|h")
  if not link then return end
  if not self:Qualifies(link) then return end

  -- De-dupe against rapid consecutive chat echoes
  local now = time()
  local last = self._recent[link] or 0
  if now - last < 1.0 then return end
  self._recent[link] = now

  local src = classifySource(self._ctx, now)

  -- If the loot window is/was open, Core will handle it; avoid duplicate processing here
  if src == "world_loot" then
    return
  end

  -- Skip mail-scrolled items for map discoveries to avoid false coordinates
  if src == "mail" then
    -- Optionally: log or track for UI analytics; intentionally no discovery
    return
  end

  -- Build discovery at the player's current location for NPC/gossip/emote/direct cases
  local px, py = GetPlayerMapPosition("player")
  px, py = px or 0, py or 0

  local discovery = {
    itemLink = link,
    zone     = GetRealZoneText(),
    subZone  = GetSubZoneText(),
    zoneID   = GetCurrentMapZone() or 0,
    coords   = { x = px, y = py },
    foundByplayer = UnitName("player"),
    foundByclass  = select(2, UnitClass("player")),
    timestamp = now,
    source    = src,  -- Optional field; ignored by network serializers, but useful locally
  }

  local Core = L:GetModule("Core", true)
  if Core and Core.HandleLocalLoot then
    Core:HandleLocalLoot(discovery)
  end
end

return Detect
