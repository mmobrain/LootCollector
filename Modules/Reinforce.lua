

local L = LootCollector
local Reinforce = L:NewModule("Reinforce", "AceEvent-3.0")

local OFFSETS = {900, 1800, 3600, 10800, 18000, 28800, 43200, 86400, 172800, 432000, 604800}
local MAX_STEPS = #OFFSETS
local CONFIRMATION_THRESHOLD = 7 

local GRACE_SEC, MIN_SPACING, JITTER_MIN, JITTER_MAX = 1200, 3.40, 5, 30
local now = time

Reinforce.queue, Reinforce.lastSendAt, Reinforce.scanAccum, Reinforce.scanPeriod = {}, 0, 0, 60
Reinforce.scanNextKey = nil
Reinforce.scanInProgress = false
local SCAN_CHUNK_SIZE = 300       
local MAX_ENQUEUE_PER_SCAN = 10 

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
    
    local db = L:GetDiscoveriesDB() or {}
    local guid = buildGuid3(norm.c, norm.z, norm.i, norm.xy.x, norm.xy.y)
    local d = db[guid]

    if not d then return end

    local t = tonumber(norm.t0) or now()

    d.at = now() 
    recomputeNextDue(d) 
    
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
    
    
    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.ALLOWED_DISCOVERY_TYPES and d.dt then
        if Constants.ALLOWED_DISCOVERY_TYPES[d.dt] == false then
            
            return false
        end
    end
    
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

    
    local gracePeriod = (Constants and Constants.REINFORCE_TAKEOVER_GRACE_SECONDS) or GRACE_SEC

    if canSend then
        return tnow >= d.nd
    else
        return tnow >= (d.nd + gracePeriod)
    end
end

local function discoveryPayloadFrom(d)
    local fpName = d.fp or "An Unnamed Collector"
    local s_flag = (fpName == "An Unnamed Collector") and 1 or 0
    if s_flag == 1 then fpName = "" end 
    
    L._debug("Reinforce-Payload", string.format("Building payload for broadcast. Discovery has src: %s, dt: %s", tostring(d.src), tostring(d.dt)))

    local payload = {
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

    
    local Constants = L:GetModule("Constants", true)
    if Constants and payload.dt and tonumber(payload.dt) == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then
        payload.src = d.src
        L._debug("Reinforce-Payload", " -> It's a Mystic Scroll. Added 'src' field: " .. tostring(payload.src))
    end

    return payload
end

local function enqueue(d)
    local jitter = randint(JITTER_MIN, JITTER_MAX)
    local fireAt = math.max(now(), (tonumber(d.nd) or now())) + jitter
    Reinforce.queue[d.g] = {fireAt = fireAt, guid = d.g}
    d.pendingAnnounce = fireAt
end

local function drainQueueOnce()
    local p = L and L.db and L.db.profile
    if not (p and p.sharing and p.sharing.enabled) then
        if next(Reinforce.queue) then wipe(Reinforce.queue) end
        return 
    end

    local Comm = L:GetModule("Comm", true)
    if not Comm or not Comm.BroadcastReinforcement then return end
    local tnow = now()
    if (tnow - Reinforce.lastSendAt) < MIN_SPACING then return end
    
    if not next(Reinforce.queue) then return end
    
    local bestGuid, bestFireAt = nil, nil
    for guid, q_entry in pairs(Reinforce.queue) do
        if not bestFireAt or q_entry.fireAt < bestFireAt then
            bestFireAt = q_entry.fireAt
            bestGuid = guid
        end
    end
    
    if not bestGuid or bestFireAt > tnow then return end
    
    local q = Reinforce.queue[bestGuid]
    Reinforce.queue[bestGuid] = nil
    
    
    local db = L:GetDiscoveriesDB() or {}
    local d = db[q.guid]
    if not d or (tonumber(d.ac) or 0) >= MAX_STEPS then return end
    
    L._debug("Reinforce", "Broadcasting reinforcement for GUID: " .. tostring(d.g)) 
    
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
Reinforce.startScan = startScan

local function processScanChunk()
    if not Reinforce.scanInProgress then return end
    
    
    if InCombatLockdown() then return end
    
    
    local db = L:GetDiscoveriesDB() or {}
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
            
            local p = L and L.db and L.db.profile
            if not (p and p.sharing and p.sharing.enabled) then
                
                if next(Reinforce.queue) then wipe(Reinforce.queue) end
                Reinforce.scanInProgress = false
                return
            end

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
