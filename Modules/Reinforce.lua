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

-- MODIFIED: Reinforce.queue is now used as a dictionary { [guid] = { fireAt, guid } }
Reinforce.queue, Reinforce.lastSendAt, Reinforce.scanAccum, Reinforce.scanPeriod = {}, 0, 0, 60
Reinforce.scanNextKey = nil
Reinforce.scanInProgress = false
local SCAN_CHUNK_SIZE = 300       -- Records to process per tick during a scan
local MAX_ENQUEUE_PER_SCAN = 10 -- Max items to add to the reinforcement queue during a single full scan cycle

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

-- MODIFIED: Replaced linear array search with O(1) dictionary lookup.
function Reinforce:HandleConfirmation(norm)
    if not norm or not norm.xy then return end
    local db = L.db.global.discoveries or {}
    local guid = buildGuid3(norm.c, norm.z, norm.i, norm.xy.x, norm.xy.y)
    local d = db[guid]

    if not d then return end

    local t = tonumber(norm.t0) or now()

    d.at = now() 
    recomputeNextDue(d) 
    
    -- O(1) removal from queue
    if Reinforce.queue[guid] then
        d.pendingAnnounce = nil 
        Reinforce.queue[guid] = nil
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

-- MODIFIED: Use GUID as the key for the dictionary.
local function enqueue(d)
    local jitter = randint(JITTER_MIN, JITTER_MAX)
    local fireAt = math.max(now(), (tonumber(d.nd) or now())) + jitter
    Reinforce.queue[d.g] = {fireAt = fireAt, guid = d.g}
    d.pendingAnnounce = fireAt
end

-- MODIFIED: Iterate with pairs() over the dictionary and remove by key.
local function drainQueueOnce()
    local Comm = L:GetModule("Comm", true)
    if not Comm or not Comm.BroadcastReinforcement then return end
    local tnow = now()
    if (tnow - Reinforce.lastSendAt) < MIN_SPACING then return end
    
    -- Check if the queue is empty
    if not next(Reinforce.queue) then return end
    
    local bestGuid, bestFireAt = nil, nil
    for guid, q_entry in pairs(Reinforce.queue) do
        if not bestFireAt or q_entry.fireAt < bestFireAt then
            bestFireAt = q_entry.fireAt
            bestGuid = guid
        end
    end
    
    if not bestGuid or bestFireAt > tnow then return end
    
    -- Retrieve and remove the *best* entry
    local q = Reinforce.queue[bestGuid]
    Reinforce.queue[bestGuid] = nil
    
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

local function startScan()
    if Reinforce.scanInProgress then return end
    Reinforce.scanInProgress = true
    Reinforce.scanNextKey = nil 
    Reinforce.enqueuedThisCycle = 0
end

local function processScanChunk()
    if not Reinforce.scanInProgress then return end
    
    local db = L.db.global.discoveries or {}
    if not next(db) then
        Reinforce.scanInProgress = false
        return
    end

    local processedInChunk = 0
    local currentKey = Reinforce.scanNextKey

    while processedInChunk < SCAN_CHUNK_SIZE do
        local key, value = next(db, currentKey)

        if not key then
            
            Reinforce.scanInProgress = false
            Reinforce.scanNextKey = nil
            return
        end

        if type(value) == "table" then
            value.g = key 
            if (Reinforce.enqueuedThisCycle or 0) < MAX_ENQUEUE_PER_SCAN and shouldEnqueue(value) then
                enqueue(value)
                Reinforce.enqueuedThisCycle = (Reinforce.enqueuedThisCycle or 0) + 1
            end
        end

        processedInChunk = processedInChunk + 1
        currentKey = key 
    end
    
    
    Reinforce.scanNextKey = currentKey
end

local tickerFrame = nil

local function ensureTicker()
 if tickerFrame then return end
    tickerFrame = CreateFrame("Frame", "LootCollectorReinforceTicker")
    
end

function Reinforce:OnInitialize()
	if L.LEGACY_MODE_ACTIVE then return end
    self:RegisterMessage("LOOTCOLLECTOR_CONFIRMATION_RECEIVED", "HandleConfirmation")
    ensureTicker()
end

function Reinforce:OnEnable()
    if L.LEGACY_MODE_ACTIVE then return end
    
    if tickerFrame then
        tickerFrame:SetScript("OnUpdate", function(_, e)
            Reinforce.scanAccum = Reinforce.scanAccum + e
            if Reinforce.scanAccum >= Reinforce.scanPeriod then
                Reinforce.scanAccum = 0
                startScan()
            end
            
            if Reinforce.scanInProgress then
                processScanChunk()
            end
            
            drainQueueOnce()
        end)
    end
    
    if C_Timer and C_Timer.After then
        C_Timer.After(5, startScan)
    end
end

function Reinforce:OnDisable()
    
    if tickerFrame then
        tickerFrame:SetScript("OnUpdate", nil)
    end
end

return Reinforce
-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl