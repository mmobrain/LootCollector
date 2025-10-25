-- Reinforce.lua
-- 3.3.5a-safe reinforcement scheduler and distributed takeover for LootCollector
-- UNK.B64.UTF-8


local L = LootCollector
local Reinforce = L:NewModule("Reinforce", "AceEvent-3.0")

local OFFSETS = {900, 1800, 3600, 10800, 18000, 28800, 43200, 86400, 172800, 432000, 604800}
local MAX_STEPS = #OFFSETS
local CONFIRMATION_THRESHOLD = 7 

local GRACE_SEC, MIN_SPACING, JITTER_MIN, JITTER_MAX = 1200, 3.40, 5, 30
local now = time

Reinforce.queue, Reinforce.lastSendAt, Reinforce.scanAccum, Reinforce.scanPeriod = {}, 0, 0, 60

local function buildGuid3(c,z,i,x,y) return tostring(c or 0).."-"..tostring(z or 0).."-"..tostring(i or 0).."-"..string.format("%.2f",L:Round2(x or 0)).."-"..string.format("%.2f",L:Round2(y or 0)) end
local function selfName() return UnitName("player") or "?" end
local function randint(a,b) return math.random(a,b) end

local function recomputeNextDue(d)
    if not d then return end
    
    local lastAnnounced = tonumber(d.at) or tonumber(d.t0) or tonumber(d.ls) or now()
    local count = tonumber(d.ac) or 1
    if count >= MAX_STEPS then
        d.nd = nil 
        return
    end
    local nextIdx = math.min(count + 1, MAX_STEPS)
    d.nd = lastAnnounced + OFFSETS[nextIdx]
end

local function ensurePerDiscoveryFields(d)
    if not d then return end
    if d.i==nil and d.il then local id=d.il:match("item:(%d+)"); d.i=id and tonumber(id)or d.i end
    d.o=d.o or d.fp or"Unknown"
    d.ac=tonumber(d.ac)or 0
    if d.ac<=0 then 
        d.ac=1
        d.at = d.at or d.t0 or d.ls or now()
    end
    if not d.nd then
        
        recomputeNextDue(d) 
    end
end

function Reinforce:HandleConfirmation(norm)
    if not norm or not norm.xy then return end
    local db = L.db.global.discoveries or {}
    local guid = buildGuid3(norm.c, norm.z, norm.i, norm.xy.x, norm.xy.y)
    local d = db[guid]

    if not d then return end

    local t = tonumber(norm.t0) or now()

    
    
    
    d.at = now() 
    recomputeNextDue(d) 
    
    
    for i = #Reinforce.queue, 1, -1 do
        if Reinforce.queue[i].guid == guid then
            table.remove(Reinforce.queue, i)
            d.pendingAnnounce = nil 
        end
    end

    
    d.mc = (d.mc or 1) + 1

    
    if d.s == "UNCONFIRMED" then
        if d.mc >= CONFIRMATION_THRESHOLD then
            d.s = "CONFIRMED"
            d.st = t 
        end
    
    elseif d.s == "FADING" or d.s == "STALE" then
        d.s = "CONFIRMED" 
        d.st = t
        d.mc = 1 
    end
end

local function isMine(d)
    local me = UnitName and UnitName("player")
    if not me or not d then return false end
    local names = { d.o, d.fp }
    for _, n in ipairs(names) do
      if type(n) == "string" and n ~= "" then
        if n == me or n:find("^"..me.."%-") then
          return true
        end
      end
    end
    return d.bySelf == true or d.isLocal == true
end

local function shouldEnqueue(d)
    ensurePerDiscoveryFields(d)
    
    if (tonumber(d.ac) or 0) >= MAX_STEPS then return false end
    if not d.nd or d.nd <= 0 then return false end

    local tnow = now()

    
    if d.pendingAnnounce and (tnow - (tonumber(d.pendingAnnounce) or 0)) < 120 then
        return false
    end

    
    local origin = d.o or "Unknown"
    local canSend = (origin == selfName() or origin == "Unknown" or origin == "An Unnamed Collector")

    
    if d.onHold then
        if not isMine(d) then
            return false
        end
    end

    
    if canSend then
        return tnow >= d.nd
    else
        return tnow >= (d.nd + GRACE_SEC)
    end
end

local function discoveryPayloadFrom(d)
    local fpName = d.fp or "An Unnamed Collector"
    local s_flag = (fpName == "An Unnamed Collector") and 1 or 0
    if s_flag == 1 then fpName = "" end 
    
    return {
      g   = d.g,
      il  = d.il,
      i   = d.i,
      c   = d.c,
      z   = d.z,
      iz  = d.iz or 0,
      xy  = d.xy,
      t0  = d.t0 or now(),
      dt  = d.dt,
      q   = d.q or 1,
      fp  = fpName,
      s   = s_flag,
    }
end

local function enqueue(d)
    local jitter = randint(JITTER_MIN, JITTER_MAX)
    local fireAt = math.max(now(), (tonumber(d.nd) or now())) + jitter
    table.insert(Reinforce.queue, {fireAt = fireAt, guid = d.g})
    d.pendingAnnounce = fireAt
end

local function drainQueueOnce()
    local Comm = L:GetModule("Comm", true)
    if not Comm or not Comm.BroadcastReinforcement then return end
    local tnow = now()
    if (tnow - Reinforce.lastSendAt) < MIN_SPACING then return end
    
    local bestIdx, bestFireAt = nil, nil
    for i, q in ipairs(Reinforce.queue) do
        if not bestFireAt or q.fireAt < bestFireAt then
            bestFireAt = q.fireAt
            bestIdx = i
        end
    end
    
    if not bestIdx or bestFireAt > tnow then return end
    
    local q = table.remove(Reinforce.queue, bestIdx)
    local db = L.db.global.discoveries or {}
    local d = db[q.guid]
    if not d or (tonumber(d.ac) or 0) >= MAX_STEPS then return end
    
    local payload = discoveryPayloadFrom(d)
    Comm:BroadcastReinforcement(payload)
    
    d.at = now() 
    d.ac = math.min(MAX_STEPS, (tonumber(d.ac) or 1) + 1)
    recomputeNextDue(d)
    
    d.pendingAnnounce = nil
    Reinforce.lastSendAt = tnow
end

local function scanAndEnqueue()
    local db = L.db.global.discoveries or {}
    local added = 0
    for guid, d in pairs(db) do
        if type(d) == "table" then
            if added >= 10 then break end
            d.g = guid
            if shouldEnqueue(d) then
                enqueue(d)
                added = added + 1
            end
        end
    end
end

local tickerFrame = nil
local function ensureTicker()
    if tickerFrame then return end
    tickerFrame = CreateFrame("Frame", "LootCollectorReinforceTicker")
    tickerFrame:SetScript("OnUpdate", function(_, e)
        Reinforce.scanAccum = Reinforce.scanAccum + e
        if Reinforce.scanAccum >= Reinforce.scanPeriod then
            Reinforce.scanAccum = 0
            scanAndEnqueue()
        end
        drainQueueOnce()
    end)
end

function Reinforce:OnInitialize()
    
    self:RegisterMessage("LOOTCOLLECTOR_CONFIRMATION_RECEIVED", "HandleConfirmation")
    ensureTicker()
end

function Reinforce:OnEnable()
    if C_Timer and C_Timer.After then
        C_Timer.After(5, scanAndEnqueue)
    end
end

return Reinforce
-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl