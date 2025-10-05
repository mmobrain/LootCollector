-- Reinforce.lua
-- 3.3.5a-safe reinforcement scheduler and distributed takeover for LootCollector
-- - Tracks per-discovery reinforce progress: announceCount, lastAnnouncedTs, nextDueTs, originator
-- - Schedules confirmations based on the OFFSETS table.
-- - Originator grace window; post-grace community takeover with jitter
-- - Drip-sends via existing Comm:BroadcastReinforcement to respect throttles
-- - Updates counters on inbound DISC/CONF via AceComm, and via LC1 through Comm glue

local L = LootCollector
local Reinforce = L:NewModule("Reinforce", "AceEvent-3.0", "AceComm-3.0")
local AceSerializer = LibStub and LibStub("AceSerializer-3.0", true) or nil

-- Updated reinforcement schedule
local OFFSETS = {
    0,      -- Step 1: Immediate (t0)
    1800,   -- Step 2: +30 minutes
    3600,   -- Step 3: +1 hour
    10800,  -- Step 4: +3 hours
    18000,  -- Step 5: +5 hours
    28800,  -- Step 6: +8 hours
    43200,  -- Step 7: +12 hours
    86400,  -- Step 8: +24 hours
    172800, -- Step 9: +48 hours
    432000, -- Step 10: +5 days
    604800, -- Step 11: +7 days
}
local MAX_STEPS = #OFFSETS -- This is now 11

-- Takeover guard and pacing
local GRACE_SEC = 1200
local MIN_SPACING = 0.75
local JITTER_MIN, JITTER_MAX = 5, 30

-- Local clock alias
local now = time

-- Queue state
Reinforce.queue = Reinforce.queue or {}
Reinforce.lastSendAt = 0
Reinforce.scanAccum = 0
Reinforce.scanPeriod = 30
Reinforce.enabled = true

-- Helpers
local function round2(v)
  v = tonumber(v) or 0
  return math.floor(v * 100 + 0.5) / 100
end

local function buildGuid2(zoneID, itemID, x, y)
  return tostring(zoneID or 0) .. "-" .. tostring(itemID or 0) .. "-"
    .. string.format("%.2f", round2(x or 0)) .. "-"
    .. string.format("%.2f", round2(y or 0))
end

local function selfName()
  return UnitName("player") or "?"
end

local function randint(a, b)
  return math.random(a, b)
end

local function ensurePerDiscoveryFields(d)
  if not d then return end; if d.itemID == nil and type(d.itemLink) == "string" then local id = d.itemLink:match("item:(%d+)"); d.itemID = id and tonumber(id) or d.itemID end; local t0 = tonumber(d.timestamp) or tonumber(d.lastSeen) or now(); d.originator = d.originator or d.foundBy_player or d.foundByplayer or d.foundBy or "Unknown"; d.announceCount = tonumber(d.announceCount) or 0; d.lastAnnouncedTs = tonumber(d.lastAnnouncedTs) or nil; d.nextDueTs = tonumber(d.nextDueTs) or nil; if d.announceCount <= 0 then d.announceCount = 1; d.lastAnnouncedTs = t0; d.nextDueTs = t0 + OFFSETS[2] else if not d.nextDueTs then local nextIdx = math.min(d.announceCount + 1, MAX_STEPS); d.nextDueTs = t0 + OFFSETS[nextIdx] end end
end

local function recomputeNextDue(d)
  if not d then return end; local t0 = tonumber(d.timestamp) or tonumber(d.lastSeen) or now(); local count = tonumber(d.announceCount) or 1; if count >= MAX_STEPS then d.nextDueTs = nil; return end; local nextIdx = math.min(count + 1, MAX_STEPS); d.nextDueTs = t0 + OFFSETS[nextIdx]
end

local function bumpOnAnnouncement(d, tstamp)
  ensurePerDiscoveryFields(d); local t = tonumber(tstamp) or now(); local last = tonumber(d.lastAnnouncedTs) or 0; if t <= last + 60 then return end; d.lastAnnouncedTs = t; d.announceCount = math.min(MAX_STEPS, (tonumber(d.announceCount) or 1) + 1); recomputeNextDue(d)
end

local function canOriginatorSend(d, tnow)
  return tnow >= (tonumber(d.nextDueTs) or 0)
end

local function canCommunitySend(d, tnow)
  return tnow >= ((tonumber(d.nextDueTs) or 0) + GRACE_SEC)
end

local function shouldEnqueue(d)
    ensurePerDiscoveryFields(d); if (tonumber(d.announceCount) or 0) >= MAX_STEPS then return false end; local due = tonumber(d.nextDueTs) or 0; if due <= 0 then return false end; local tnow = now(); if d.pendingAnnounce and (tnow - (tonumber(d.pendingAnnounce) or 0)) < 120 then return false end; local origin = d.originator or "Unknown"; if origin == selfName() then return canOriginatorSend(d, tnow) elseif origin == "Unknown" or origin == "An Unnamed Collector" then return canOriginatorSend(d, tnow) else return canCommunitySend(d, tnow) end
end

local function discoveryPayloadFrom(d)
  return { guid = d.guid, itemLink = d.itemLink, itemID = d.itemID, zone = d.zone, subZone = d.subZone, zoneID = d.zoneID, coords = d.coords and { x = d.coords.x, y = d.coords.y } or { x = 0, y = 0 }, foundByplayer = d.foundByplayer or d.foundBy or d.originator or "Unknown", timestamp = now(), }
end

local function enqueue(d, whenTs)
  local jitter = randint(JITTER_MIN, JITTER_MAX); local fireAt = math.max(now(), (tonumber(whenTs) or now())) + jitter; table.insert(Reinforce.queue, { fireAt = fireAt, guid = d.guid }); d.pendingAnnounce = fireAt
end

local function drainQueueOnce()
  local Comm = L and L:GetModule("Comm", true); if not Comm or not Comm.BroadcastReinforcement then return end; local tnow = now(); if (tnow - (Reinforce.lastSendAt or 0)) < MIN_SPACING then return end; local idx, bestAt = nil, nil; for i, q in ipairs(Reinforce.queue) do if not bestAt or q.fireAt < bestAt then bestAt = q.fireAt; idx = i end end; if not idx then return end; if bestAt > tnow then return end; local q = table.remove(Reinforce.queue, idx); local db = L.db and L.db.global and L.db.global.discoveries or nil; if not db then return end; local d = db[q.guid]; if not d then return end; if (tonumber(d.announceCount) or 0) >= MAX_STEPS then return end; local payload = discoveryPayloadFrom(d); Comm:BroadcastReinforcement(payload); bumpOnAnnouncement(d, payload.timestamp); d.pendingAnnounce = nil; Reinforce.lastSendAt = tnow
end

local function scanAndEnqueue()
  local db = L.db and L.db.global and L.db.global.discoveries or nil; if not db then return 0 end; local addedToQueue = 0; local ENQUEUE_LIMIT = 10; for guid, d in pairs(db) do repeat if addedToQueue >= ENQUEUE_LIMIT then break end; if not d or not d.zoneID or not d.coords then break end; d.guid = d.guid or guid; ensurePerDiscoveryFields(d); if (tonumber(d.announceCount) or 0) >= MAX_STEPS then break end; if shouldEnqueue(d) then enqueue(d, tonumber(d.nextDueTs) or now()); addedToQueue = addedToQueue + 1 end until true end; return addedToQueue
end

function Reinforce:BumpFromWire(z, i, x, y, tstamp, op)
  if not (L and L.db and L.db.global and L.db.global.discoveries) then return end; local guid = buildGuid2(tonumber(z) or 0, tonumber(i) or 0, tonumber(x) or 0, tonumber(y) or 0); local d = L.db.global.discoveries[guid]; if not d then return end; ensurePerDiscoveryFields(d); if op == "DISC" then local t0 = tonumber(tstamp) or tonumber(d.timestamp) or now(); if (tonumber(d.announceCount) or 0) < 1 then d.announceCount = 1 end; if not d.lastAnnouncedTs or t0 > (tonumber(d.lastAnnouncedTs) or 0) then d.lastAnnouncedTs = t0 end; recomputeNextDue(d) elseif op == "CONF" then bumpOnAnnouncement(d, tstamp) end
end

local function hookCoreOnce()
  local Core = L and L:GetModule("Core", true); if not Core or Reinforce.coreHooked then return end; Reinforce.coreHooked = true; hooksecurefunc(Core, "HandleLocalLoot", function(_, discovery) if not L.db or not L.db.global then return end; if not discovery then return end; local itemID; if type(discovery.itemLink) == "string" then local id = discovery.itemLink:match("item:(%d+)"); itemID = id and tonumber(id) or discovery.itemID else itemID = discovery.itemID end; local z = discovery.zoneID or 0; local x = discovery.coords and discovery.coords.x or 0; local y = discovery.coords and discovery.coords.y or 0; local guid = buildGuid2(z, itemID, x, y); local d = L.db.global.discoveries and L.db.global.discoveries[guid]; if not d then return end; ensurePerDiscoveryFields(d); d.originator = d.originator or (UnitName("player") or "Unknown"); if (tonumber(d.announceCount) or 0) <= 0 then d.announceCount = 1; d.lastAnnouncedTs = tonumber(d.timestamp) or now(); recomputeNextDue(d) end; local t = now(); if not d.lastAnnouncedTs or (t > (tonumber(d.lastAnnouncedTs) or 0) + 60) then d.lastAnnouncedTs = t; d.announceCount = math.min(MAX_STEPS, (tonumber(d.announceCount) or 1) + 1); recomputeNextDue(d) end end)
end

function Reinforce:OnCommReceived(prefix, message, distribution, sender)
  if prefix ~= (L.addonPrefix or "BBLCAM25") then return end; if not AceSerializer or type(message) ~= "string" then return end; local ok, data = AceSerializer:Deserialize(message); if not ok or type(data) ~= "table" then return end; if data.v ~= 1 or not data.i or not data.z or not data.x or not data.y then return end; local db = L.db and L.db.global and L.db.global.discoveries or nil; if not db then return end; local guid = buildGuid2(tonumber(data.z) or 0, tonumber(data.i) or 0, tonumber(data.x) or 0, tonumber(data.y) or 0); local d = db[guid]; if not d then return end; ensurePerDiscoveryFields(d); d.originator = d.originator or sender or "Unknown"; local op = data.op or "DISC"; local tstamp = tonumber(data.t) or now(); if op == "DISC" then if (tonumber(d.announceCount) or 0) < 1 then d.announceCount = 1 end; if not d.lastAnnouncedTs or tstamp > (tonumber(d.lastAnnouncedTs) or 0) then d.lastAnnouncedTs = tstamp end; recomputeNextDue(d) elseif op == "CONF" then bumpOnAnnouncement(d, tstamp) end
end

local tickerFrame = nil
local function ensureTicker()
  if tickerFrame then return end; tickerFrame = CreateFrame("Frame", "LootCollectorReinforceTicker"); tickerFrame:SetScript("OnUpdate", function(_, elapsed) Reinforce.scanAccum = (Reinforce.scanAccum or 0) + (elapsed or 0); if Reinforce.scanAccum >= Reinforce.scanPeriod then Reinforce.scanAccum = 0; scanAndEnqueue() end; drainQueueOnce() end)
end

function Reinforce:OnInitialize()
  self:RegisterComm(L.addonPrefix or "BBLCAM25", "OnCommReceived"); hookCoreOnce(); ensureTicker()
end

function Reinforce:OnEnable()
  if Timer and type(Timer.After) == "function" then Timer.After(5, function() scanAndEnqueue() end) end
end

return Reinforce