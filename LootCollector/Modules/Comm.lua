local L = LootCollector
local Comm = L:NewModule("Comm", "AceComm-3.0", "AceEvent-3.0")
local Core = L:GetModule("Core", true)

local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate", true)
local XXH_Lua_Lib = _G.XXH_Lua_Lib

local RAW_BUFFER_CAP = 120
Comm._lagRecoveryTimer = 0
Comm._minCompatibleVersion = nil

Comm.isLoggingOut = false
Comm._senderInjectionRates = {}
Comm._auCache = {}
Comm.sessionIgnoredSenders = Comm.sessionIgnoredSenders or {}

local function ChatFilter(_, _, msg, _, _, _, _, _, _, _, channelName)
    if not channelName then return false end
    
    local chA = string.upper(channelName or "")
    local chB = string.upper(Comm.channelName or "")
    if chA ~= chB then return false end
    
  
    if L.db and L.db.profile and L.db.profile.chatDebug then
        return false
    end
    
    if type(msg) == "string" and msg:match("^LC[1-5]:") then
        return true
    end
    
    return false
end
ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ChatFilter)

local function de(s, o)
    local t = {}
    for i = 1, #s, 2 do
        local b = tonumber(s:sub(i, i+1), 16)
        t[#t+1] = string.char((b - o + 256) % 256)
    end
    return table.concat(t)
end

local GFIX_CHS = "35ffi9+Y34og35/fjt+sIN+j34zfqyDfpt+f343frN+h34rfst+s36DfiiDfn9+O36wg35/fit+V343fsCDfot+M36PfjN+y36DfjN+yIN+i34rfk9+QIN+V347fod+K"
local GFIX_SEED = 654327
local GFIX_VALID_HASHES = {
    [de("92BF8C91C0C08DBF", 90)] = 321,    
    [de("93BC918DC08D8C93", 90)] = 321,
    [de("BD93C08B93BBBF8A", 90)] = 321,
    [de("8E8A8A8CBF8B8E8D", 90)] = 321,
}

local cachedRealmNameFirstWord = (GetRealmName() or ""):match("^[^- ]+") or ""

local function isSharingEnabled()
    return L.db and L.db.profile and L.db.profile.sharing and L.db.profile.sharing.enabled
end

local function canSendMessages()    
    if L.db and L.db.global and L.db.global.isOutdatedAndKilled then
        return false
    end

    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.CanSendMessages then
        return Constants:CanSendMessages()
    end
    return true
end

local function isBlacklisted(str)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not str or str == "" then 
        if pTime then L:ProfileStop("Comm:isBlacklisted", pTime) end
        return false 
    end
    
    local Constants = L:GetModule("Constants", true)
    if not Constants then 
        if pTime then L:ProfileStop("Comm:isBlacklisted", pTime) end
        return false 
    end
    
    local isB = Constants:IsHashInList(str, "HASH_BLACKLIST")
    
    if pTime then L:ProfileStop("Comm:isBlacklisted", pTime) end 
    return isB
end

local function GetLast3AsciiSum(name)
    if type(name) ~= "string" or name == "" then return 0 end
    local len = string.len(name)
    local sum = 0
    local startIdx = math.max(1, len - 2)
    for i = startIdx, len do
        sum = sum + string.byte(name, i)
    end
    return sum
end

local function compareVersions(v1, v2)
    if v1 == v2 then return 0 end
    if not v1 or v1 == "" then return -1 end
    if not v2 or v2 == "" then return 1 end

    local function parseVersion(v)
        if type(v) ~= "string" then return 0, 0, 0 end
        
        local versionString = v:match("(%d+%.%d+%.?%d*)")
        if not versionString then
            return 0, 0, 0 
        end

        local parts = {}
        
        for part in versionString:gmatch("([^%.]+)") do
            table.insert(parts, tonumber(part) or 0)
        end
        
        return parts[1] or 0, parts[2] or 0, parts[3] or 0
    end

    local major1, minor1, patch1 = parseVersion(v1)
    local major2, minor2, patch2 = parseVersion(v2)

    if major1 > major2 then return 1 end
    if major1 < major2 then return -1 end

    if minor1 > minor2 then return 1 end
    if minor1 < minor2 then return -1 end

    if patch1 > patch2 then return 1 end
    if patch1 < patch2 then return -1 end
    
    return 0
end

Comm.addonPrefix = L.addonPrefix or "BBLC25AM"
Comm.channelName = L.chatChannel or "BBLC25C"
Comm.channelId = 0

Comm.chatMinInterval = 3.50
Comm.maxChatBytes    = 250
Comm.seenTTL         = 1800
Comm.coordPrec       = 4
Comm.RATE_LIMIT_COUNT  = 9
Comm.RATE_LIMIT_WINDOW = 60

local function loadConstants()
    local Constants = L:GetModule("Constants", true)
    if not Constants then return end
    
    Comm.chatMinInterval = Constants.GetChatMinInterval and Constants:GetChatMinInterval() or Comm.chatMinInterval
    Comm.maxChatBytes    = Constants.GetMaxChatBytes and Constants:GetMaxChatBytes() or Comm.maxChatBytes
    Comm.seenTTL         = Constants.GetSeenTtl and Constants:GetSeenTtl() or Comm.seenTTL
    Comm.coordPrec       = Constants.GetCoordPrecision and Constants:GetCoordPrecision() or Comm.coordPrec
    Comm.RATE_LIMIT_COUNT  = Constants.GetRateLimitCount and Constants:GetRateLimitCount() or Comm.RATE_LIMIT_COUNT
    Comm.RATE_LIMIT_WINDOW = Constants.GetRateLimitWindow and Constants:GetRateLimitWindow() or Comm.RATE_LIMIT_WINDOW
end

Comm._lastSendAt = 0
Comm._bucketTokens = Comm.RATE_LIMIT_COUNT
Comm._bucketLastFill = time()
Comm._rateLimitQueue = {}
Comm._delayQueue = {}
Comm._pausedIncoming = {}
Comm._seq = 0
Comm._seen = {}
Comm.verbose = false

Comm._incomingMessageQueue = {}
Comm.rawBuffer = {}
Comm._scratchSegments = {}
local PROCESS_INTERVAL = 0.2 
local BATCH_SIZE_NORMAL = 6
local BATCH_SIZE_COMBAT = 2

local RAW_PROCESS_BUDGET_MS = 3
Comm._processTimer = 0

    
local function trackInvalidSender(sender, reason, payload)
    if not (L.db and L.db.profile) then return end
    
    if sender and sender ~= "" then
        local name = L:normalizeSenderName(sender)
        local wl = L.db.profile.sharing and L.db.profile.sharing.whiteList
        if name and wl and wl[name] then
            return
        end
    end
    
    L.db.profile.invalidSenders = L.db.profile.invalidSenders or {}
    local track = L.db.profile.invalidSenders[sender] or { count = 0, expiredCount = 0, lastInvalid = 0 }
    
    
    local av = payload and payload.av or "Unknown"
    local item = payload and (payload.i or payload.itemID) or "-"
    local zone = payload and (payload.z or payload.zoneID) or "-"   
    local continent = payload and payload.c or "-"
    local izVal = tonumber(payload and (payload.iz or payload.instanceID)) or 0
    local zVal = tonumber(payload and (payload.z or payload.zoneID)) or 0
    
    
    local xVal = payload and (payload.x or (payload.xy and payload.xy.x))
    local yVal = payload and (payload.y or (payload.xy and payload.xy.y))
    
    local ZoneList = L:GetModule("ZoneList", true)
    local isInst = (izVal > 0 or (ZoneList and ZoneList.InstanceZones and ZoneList.InstanceZones[zVal] ~= nil))

    
    local guidVal = "-"
    if tonumber(continent) and tonumber(zone) and tonumber(item) and tonumber(xVal) and tonumber(yVal) then
        guidVal = L:GenerateGUID(tonumber(continent), tonumber(zone), izVal, tonumber(item), tonumber(xVal), tonumber(yVal))
    end

    
    if reason == "expired_timestamp" then
        if L.db.profile.idebugMode then
            print(string.format("|cffffff00[LC-Benign]|r Dropped expired packet from %s (v%s)", tostring(sender), tostring(av)))
        end
        
        track.expiredCount = (track.expiredCount or 0) + 1
        track.lastInvalid = time()
        track.lastReason = reason
        track.version = av
        track.lastItem = item
        track.lastZone = zone
        track.lastContinent = continent
        track.lastIsInstance = isInst
        track.lastGuid = guidVal
        L.db.profile.invalidSenders[sender] = track

        
        if track.expiredCount >= 7 and not Comm.sessionIgnoredSenders[sender] then
            Comm.sessionIgnoredSenders[sender] = true
            print(string.format("|cffff7f00[LootCollector]|r %s (v%s) is broadcasting an expired database. Ignoring their messages for this session to save CPU.", sender, av))
        end
        return
    end

    
    if L.db.profile.idebugMode then
        local payloadStr = "nil"
        if payload then
            local parts = {}
            for k, v in pairs(payload) do
                table.insert(parts, tostring(k) .. "=" .. tostring(v))
            end
            payloadStr = "{" .. table.concat(parts, ", ") .. "}"
        end
        print(string.format("|cffff00ff[LC-Invalid]|r Sender: %s (v%s) | Reason: %s | Payload: %s", tostring(sender), tostring(av), tostring(reason), payloadStr))
    end
    
    track.count = (track.count or 0) + 1
    track.lastInvalid = time()
    track.lastReason = reason
    track.version = av
    track.lastItem = item
    track.lastZone = zone
    track.lastContinent = continent
    track.lastIsInstance = isInst
    track.lastGuid = guidVal
    
    L.db.profile.invalidSenders[sender] = track
    
    
    if track.count == 3 and not Comm.sessionIgnoredSenders[sender] then
        Comm.sessionIgnoredSenders[sender] = true
        print(string.format("|cffff7f00[LootCollector]|r %s (v%s) sent 3 invalid discoveries. Suppressing messages for this session.", sender, av))
    end
    
    
    if track.count >= 7 and not track.permanent then
        track.permanent = true
        L.db.profile.sharing = L.db.profile.sharing or {}
        L.db.profile.sharing.blockList = L.db.profile.sharing.blockList or {}
        L.db.profile.sharing.blockList[sender] = true
        
        
        Comm.sessionIgnoredSenders[sender] = true
        
        print(string.format("|cffff0000[LootCollector SECURITY]|r %s (v%s) sent 7 invalid discoveries. PERMANENTLY BLACKLISTED. Reason: %s (Last Target: Item %s, Continent %s, Zone %s, Instance: %s)", 
            sender, av, reason, tostring(item), tostring(continent), tostring(zone), isInstStr))
    end
end

local function isSenderSessionIgnored(sender)
    if not sender or sender == "" then return false end
    local name = L:normalizeSenderName(sender)
    if not name then return false end
    
    local wl = L.db.profile.sharing and L.db.profile.sharing.whiteList
    if wl and wl[name] then return false end
    
    
    if Comm.sessionIgnoredSenders and Comm.sessionIgnoredSenders[name] then
        return true
    end
    return false
end

local function trackInvalidSender(sender, reason, payload)
    if not (L.db and L.db.profile) then return end
    
    if sender and sender ~= "" then
        local name = L:normalizeSenderName(sender)
        local wl = L.db.profile.sharing and L.db.profile.sharing.whiteList
        if name and wl and wl[name] then
            return
        end
    end
    
    local name = L:normalizeSenderName(sender)
    if not name then return end

    L.db.profile.invalidSenders = L.db.profile.invalidSenders or {}
    local track = L.db.profile.invalidSenders[name] or { count = 0, expiredCount = 0, lastInvalid = 0 }
    
    
    local av = payload and payload.av or "Unknown"
    local item = payload and (payload.i or payload.itemID) or "-"
    local zone = payload and (payload.z or payload.zoneID) or "-"   
    local continent = payload and payload.c or "-"
    local izVal = tonumber(payload and (payload.iz or payload.instanceID)) or 0
    local zVal = tonumber(payload and (payload.z or payload.zoneID)) or 0
    
    
    local xVal = payload and (payload.x or (payload.xy and payload.xy.x))
    local yVal = payload and (payload.y or (payload.xy and payload.xy.y))
    
    local ZoneList = L:GetModule("ZoneList", true)
    local isInst = (izVal > 0 or (ZoneList and ZoneList.InstanceZones and ZoneList.InstanceZones[zVal] ~= nil))

    
    local guidVal = "-"
    if tonumber(continent) and tonumber(zone) and tonumber(item) and tonumber(xVal) and tonumber(yVal) then
        guidVal = L:GenerateGUID(tonumber(continent), tonumber(zone), izVal, tonumber(item), tonumber(xVal), tonumber(yVal))
    end

    
    if L.db.profile.idebugMode then
        local payloadStr = "nil"
        if payload then
            local parts = {}
            for k, v in pairs(payload) do
                table.insert(parts, tostring(k) .. "=" .. tostring(v))
            end
            payloadStr = "{" .. table.concat(parts, ", ") .. "}"
        end
        print(string.format("|cffff00ff[LC-Invalid]|r Sender: %s (v%s) | Reason: %s | Payload: %s", tostring(name), tostring(av), tostring(reason), payloadStr))
    end
    
    track.count = (track.count or 0) + 1
    track.lastInvalid = time()
    track.lastReason = reason
    track.version = av
    track.lastItem = item
    track.lastZone = zone
    track.lastContinent = continent
    track.lastIsInstance = isInst
    track.lastGuid = guidVal 
    
    L.db.profile.invalidSenders[name] = track
    
    
    if track.count == 3 and not Comm.sessionIgnoredSenders[name] then
        Comm.sessionIgnoredSenders[name] = true
        print(string.format("|cffff7f00[LootCollector]|r %s (v%s) sent 3 invalid discoveries. Suppressing messages for this session.", name, av))
    end
    
    
    if track.count >= 7 and not track.permanent then
        track.permanent = true
        L.db.profile.sharing = L.db.profile.sharing or {}
        L.db.profile.sharing.blockList = L.db.profile.sharing.blockList or {}
        L.db.profile.sharing.blockList[name] = true
        
        
        Comm.sessionIgnoredSenders[name] = true
        
        
        local isInstStr = isInst and "true" or "false"
        print(string.format("|cffff0000[LootCollector SECURITY]|r %s (v%s) sent 7 invalid discoveries. PERMANENTLY BLACKLISTED. Reason: %s (Last Target: Item %s, Continent %s, Zone %s, Instance: %s)", 
            name, av, reason, tostring(item), tostring(continent), tostring(zone), isInstStr))
    end
end

local function isSenderPermanentlyBlacklisted(sender)
    if not (L.db and L.db.profile) then return false end
    local bl = L.db.profile.sharing and L.db.profile.sharing.blockList
    return bl and bl[sender] == true
end

local function isSenderBlockedByProfile(sender)
    local g = L and L.db and L.db.global
    local p = L and L.db and L.db.profile and L.db.profile.sharing
    if not (p or g) then return false end
        
    local name = L:normalizeSenderName(sender)
    if not name then return false end
    
    
    if g and g.aBL and g.aBL[name] then
        return true
    end
    
    
    if p then
        local bl = p.blockList
        local wl = p.whiteList
        
        if bl and bl[name] then return true end
        if wl and next(wl) ~= nil then return not wl[name] end
    end
    
    return false
end

local function now() return time() end

function Comm:HaltForLogout()
    Comm.isLoggingOut = true

if Comm._multipartSpool then wipe(Comm._multipartSpool) end
    if Comm._rateLimitQueue then wipe(Comm._rateLimitQueue) end
    if Comm._delayQueue then wipe(Comm._delayQueue) end
    if Comm._incomingMessageQueue then wipe(Comm._incomingMessageQueue) end
    if Comm.rawBuffer then wipe(Comm.rawBuffer) end
    if Comm._pausedIncoming then wipe(Comm._pausedIncoming) end
end

local function roundN(v, n)
    v = tonumber(v) or 0
    local mul = 10 ^ (tonumber(n) or 0)
    return math.floor(v * mul + 0.5) / mul
end

local function roundPrec(v) return roundN(v, Comm.coordPrec or 4) end

local function _senderAnonFlag()
    local pf = L and L.db and L.db.profile
    local anon = pf and pf.sharing and pf.sharing.anonymous
    return anon and 1 or 0
end

local function _senderDisplayName()
    local pf = L and L.db and L.db.profile
    if pf and pf.sharing and pf.sharing.anonymous then
        return "An Unnamed Collector"
    end
    return UnitName("player") or "Unknown"
end

local function _extractItemID(linkOrId)
    return L:ExtractItemID(linkOrId)
end

Comm.ingressSeen = Comm.ingressSeen or {}
Comm.ingressSeenTTL = 8

local function shouldDropIngressDuplicate(sender, op, mid)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not mid or mid == "" then
        if pTime then L:ProfileStop("Comm:shouldDropIngressDuplicate", pTime) end
        return false
    end

    local key = tostring(sender or "?") .. "|" .. tostring(op or "?") .. "|" .. tostring(mid)
    local tnow = now()
    local prev = Comm.ingressSeen[key]

    if prev and (tnow - prev) <= (Comm.ingressSeenTTL or 8) then
        if pTime then L:ProfileStop("Comm:shouldDropIngressDuplicate", pTime) end
        return true
    end

    Comm.ingressSeen[key] = tnow
    
    if pTime then L:ProfileStop("Comm:shouldDropIngressDuplicate", pTime) end 
    return false
end

local function pruneCaches()
    local pTime = L.ProfileStart and L:ProfileStart() 

    local tnow = now()
    
    Comm._lastSpamPrune = Comm._lastSpamPrune or tnow
    if (tnow - Comm._lastSpamPrune) > 300 then
        if Comm._trackSpam then wipe(Comm._trackSpam) end
        Comm._lastSpamPrune = tnow
    end
    
    local iSeen = Comm.ingressSeen
    if iSeen then
        local iTtl = Comm.ingressSeenTTL or 8
        for k, ts in pairs(iSeen) do
            if (tnow - (tonumber(ts) or 0)) > iTtl then
                iSeen[k] = nil
            end
        end
    end
        
    local mSeen = Comm.seen
    if mSeen then
        local mTtl = Comm.seenTTL or 900
        for k, ts in pairs(mSeen) do
            if (tnow - (tonumber(ts) or 0)) > mTtl then
                mSeen[k] = nil
            end
        end
    end

    local spoolCache = Comm._multipartSpool
    if spoolCache then
        local sTtl = 36 
        for k, data in pairs(spoolCache) do
            if (tnow - (tonumber(data.ts) or 0)) > sTtl then
                spoolCache[k] = nil
            end
        end
    end

    if pTime then L:ProfileStop("Comm:pruneCaches", pTime) end 
end

local function _shouldDropDedupe(mid, op)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not mid or mid == "" then
        if pTime then L:ProfileStop("Comm:_shouldDropDedupe", pTime) end
        return false
    end
    
    local Constants = L:GetModule("Constants", true)
    local seenTTL = (Constants and Constants.SEEN_TTL_SECONDS) or (Comm.seenTTL or 900)
    
    local key = mid .. "_" .. tostring(op or "DISC")
    
    local tnow = now()
    local prev = Comm._seen[key]
    
    if prev and (tnow - prev) < seenTTL then
        if pTime then L:ProfileStop("Comm:_shouldDropDedupe", pTime) end
        return true
    end
    
    Comm._seen[key] = tnow
    
    if pTime then L:ProfileStop("Comm:_shouldDropDedupe", pTime) end 
    return false
end

local function _computeMid(tbl)
    return L:ComputeDiscoveryMid(tbl, tbl and tbl.op or "DISC")
end

local function _nextSeq()
    Comm._seq = (Comm._seq + 1) % 65536
    return Comm._seq
end

local function _pickDistribution()
    if IsInRaid() then return "RAID" end
    if (GetNumPartyMembers() or 0) > 0 then return "PARTY" end
    if IsInGuild() then return "GUILD" end
    return nil
end

function Comm:IsChannelHealthy()
    local p = L and L.db and L.db.profile
    if not (p and p.sharing and p.sharing.enabled) then return false end
    
    local id, name = GetChannelName(self.channelName or "")
    if id and id > 0 and name and string.lower(name) == string.lower(self.channelName or "") then
        self.channelId = id
        return true
    end
    
    self.channelId = 0
    return false
end

function Comm:HideChannelFromChat()
    if L.db and L.db.profile and L.db.profile.chatDebug then return end
    
    local channelName = self.channelName or "BBLC25C"
    
    for i = 1, 10 do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame and chatFrame:IsShown() then
            if ChatFrame_RemoveChannel then		
                ChatFrame_RemoveChannel(chatFrame, channelName)		    
            end
        end
    end
end

function Comm:EnsureChannelJoined()
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not L.channelReady then 
        print("|cffff7f00LootCollector:|r Channel system is not ready yet, please wait a few seconds after login.")
        if pTime then L:ProfileStop("Comm:EnsureChannelJoined", pTime) end
        return 
    end
    
    local p = L and L.db and L.db.profile
    if not (p and p.sharing and p.sharing.enabled) then 
        if pTime then L:ProfileStop("Comm:EnsureChannelJoined", pTime) end
        return 
    end
	
	if not canSendMessages() then 
        if pTime then L:ProfileStop("Comm:EnsureChannelJoined", pTime) end
        return 
    end
    
    local ch = self.channelName or "BBLC25C"
       
    local id, name = GetChannelName(ch)
    if not (id and id > 0) then
        JoinPermanentChannel(ch)
    end
    
    if p.chatDebug then
        if DEFAULT_CHAT_FRAME then
            ChatFrame_AddChannel(DEFAULT_CHAT_FRAME, ch)
        end
    else    
        self:HideChannelFromChat()
    end
    
    self:IsChannelHealthy()

    if pTime then L:ProfileStop("Comm:EnsureChannelJoined", pTime) end 
end

function Comm:JoinPublicChannel(isManual)
    if self:IsChannelHealthy() then return end
    
    if isManual then
        local f, e = CreateFrame("Frame"), 0
        f:SetScript("OnUpdate", function(_, el)
            e = e + el
            if e >= 1.0 then
                f:SetScript("OnUpdate", nil)
                Comm:EnsureChannelJoined()
            end
        end)
    else
        self:EnsureChannelJoined()
    end
end

function Comm:LeavePublicChannel()
    local ch = self.channelName or ""
    if ch ~= "" then LeaveChannelByName(ch) end
    self.channelId = 0
end

local function IsValidMYSTICSCROLLSource(src)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local Constants = L:GetModule("Constants", true)
    if not Constants or not Constants.AcceptedLootSrcMS then 
        if pTime then L:ProfileStop("Comm:IsValidMYSTICSCROLLSource", pTime) end
        return false 
    end
    
    for k, v in pairs(Constants.AcceptedLootSrcMS) do
        if src == v then 
            if pTime then L:ProfileStop("Comm:IsValidMYSTICSCROLLSource", pTime) end
            return true 
        end
    end
    
    if pTime then L:ProfileStop("Comm:IsValidMYSTICSCROLLSource", pTime) end 
    return false
end

function Comm:buildWireV5DISC(discovery)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local itemID = _extractItemID(discovery and discovery.i or discovery.il)
    if not itemID then 
        if pTime then L:ProfileStop("Comm:buildWireV5DISC", pTime) end
        return nil 
    end

    local Constants = L:GetModule("Constants", true)
    local srcvalue = nil
    if Constants and discovery and discovery.dt and tonumber(discovery.dt) == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then
        srcvalue = discovery.src
        if not IsValidMYSTICSCROLLSource(srcvalue) then
            L._cdebug("Comm-Build", "Skipping DISC build for Mystic Scroll with invalid src " .. tostring(srcvalue))
            if pTime then L:ProfileStop("Comm:buildWireV5DISC", pTime) end
            return nil
        end
    end

    local x = discovery and discovery.xy and discovery.xy.x or 0
    local y = discovery and discovery.xy and discovery.xy.y or 0

    local s_val = (discovery.sflag == 1) and 1 or _senderAnonFlag()
    local fp_val = discovery.fp

    if s_val == 1 or fp_val == "An Unnamed Collector" then
        s_val = 1
        fp_val = ""
    end

    local w = {
        v = 5,
        op = "DISC",
        c = tonumber(discovery and discovery.c or 0),
        z = tonumber(discovery and discovery.z or 0),
        iz = tonumber(discovery and discovery.iz or 0),
        i = tonumber(itemID or 0),
        x = roundPrec(x),
        y = roundPrec(y),
        t = tonumber(discovery and discovery.t0 or now()),
        q = tonumber(discovery and discovery.q or 1),
        s = s_val,
        av = L and L.Version or "0.0.0",
        dt = discovery and discovery.dt,
        it = discovery and discovery.it,
        ist = discovery and discovery.ist,
        cl = discovery and discovery.cl,
        src = srcvalue,
        fp = fp_val,
    }

    w.mid = L:ComputeCanonicalDiscoveryMid(w)
    w.seq = _nextSeq()
    
    if pTime then L:ProfileStop("Comm:buildWireV5DISC", pTime) end 
    return w
end

function Comm:buildWireV5CONF(discovery)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local itemID = _extractItemID(discovery and (discovery.i or discovery.il))
    if not itemID then 
        if pTime then L:ProfileStop("Comm:buildWireV5CONF", pTime) end
        return nil 
    end

    local safeT0 = tonumber(discovery and discovery.t0)
    if not safeT0 or safeT0 <= 0 then
        L._cdebug("Comm-Security", string.format("Quarantined CONF packet for item %d. Missing t0 timestamp.", itemID))
        if pTime then L:ProfileStop("Comm:buildWireV5CONF", pTime) end
        return nil
    end

    local Constants = L:GetModule("Constants", true)
    local srcvalue = nil
    if Constants and discovery and discovery.dt and tonumber(discovery.dt) == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then
        srcvalue = discovery.src
        if not IsValidMYSTICSCROLLSource(srcvalue) then
            L._cdebug("Comm-Build", "Skipping CONF build for Mystic Scroll with invalid src " .. tostring(srcvalue))
            if pTime then L:ProfileStop("Comm:buildWireV5CONF", pTime) end
            return nil
        end
    end

    local x = discovery and discovery.xy and discovery.xy.x or 0
    local y = discovery and discovery.xy and discovery.xy.y or 0

    local s_val = tonumber(discovery.sflag) or 0
    local fp_val = discovery.fp

    if s_val == 1 or fp_val == "An Unnamed Collector" then
        s_val = 1
        fp_val = ""
    end

    local w = {
        v = 5,
        op = "CONF",
        c = tonumber(discovery and discovery.c or 0),
        z = tonumber(discovery and discovery.z or 0),
        iz = tonumber(discovery and discovery.iz or 0),
        i = tonumber(itemID or 0),
        x = roundPrec(x),
        y = roundPrec(y),
        t = safeT0,
        q = tonumber(discovery and discovery.q or 1),
        s = s_val,
        av = L and L.Version or "0.0.0",
        dt = discovery and discovery.dt,
        it = discovery and discovery.it,
        ist = discovery and discovery.ist,
        cl = discovery and discovery.cl,
        src = srcvalue,
        fp = fp_val,
    }

    w.mid = L:ComputeCanonicalDiscoveryMid(w)
    w.seq = _nextSeq()
    
    if pTime then L:ProfileStop("Comm:buildWireV5CONF", pTime) end 
    return w
end

function Comm:_buildWireV5_SHOW(discovery)
    local itemID = _extractItemID(discovery and (discovery.i or discovery.il))
    if not itemID then return nil end

    local Constants = L:GetModule("Constants", true)
    local src_value = nil
    if Constants and discovery and discovery.dt and tonumber(discovery.dt) == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then
        src_value = discovery.src
        
        if not IsValidMYSTICSCROLLSource(src_value) then
             L._cdebug("Comm-Build", "Skipping SHOW build for Mystic Scroll with invalid src")
             return nil
        end
    end

    L._cdebug("Comm-Build", string.format("Building SHOW packet. Discovery has dt: %s, src: %s", tostring(discovery.dt), tostring(discovery.src)))

    local vendorItemIDs = nil
    if discovery.vendorItems and type(discovery.vendorItems) == "table" then
        vendorItemIDs = {}
        for _, itemData in ipairs(discovery.vendorItems) do
            if itemData.itemID then
                table.insert(vendorItemIDs, itemData.itemID)
            end
        end
    end

    local payload = {
        v = 5,
        op = "SHOW",
        c = tonumber(discovery.c) or 0,
        z = tonumber(discovery.z) or 0,
        iz = tonumber(discovery.iz) or 0,
        i = itemID,
        x = roundPrec(discovery.xy and discovery.xy.x or 0),
        y = roundPrec(discovery.xy and discovery.xy.y or 0),
        t = tonumber(discovery.t0) or now(),
        q = tonumber(discovery.q) or 1,
        av = L.Version or "0.0.0",
        il = discovery.il,
        fp = discovery.fp or "Unknown",
        dt = discovery.dt,
        src = src_value, 
        vendorType = discovery.vendorType,
        vendorName = discovery.vendorName,
        vendorItemIDs = vendorItemIDs,
    }

    return payload
end

function Comm:_buildWireV5_GFIX(fixData)
    if not fixData then return nil end
    if not fixData.type then return nil end
    
    
    
    if fixData.type == 8 or fixData.type == 9 or fixData.type == 10 then
        if not fixData.name and not fixData.c then return nil end
    else
        
        if not fixData.i then return nil end
    end

    local tempC = fixData.c or fixData.oc or 0
    local tempZ = fixData.z or fixData.oz or 0
    
    local safeI = fixData.i or 0

    return {
        v = 5,
        op = "GFIX",
        av = L.Version or "0.0.0",
        payload = fixData,
        
        mid = _computeMid({v=5, op="GFIX", i=safeI, c=tempC, z=tempZ, t=now()}),
        seq = _nextSeq(),
    }
end

function Comm:_buildWireV5_ACK(discovery, ackMid, act)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not ackMid or ackMid == "" then 
        if pTime then L:ProfileStop("Comm:_buildWireV5_ACK", pTime) end
        return nil 
    end
    
    local legal = { DET = true, VER = true, SPM = true, DUP = true }
    act = legal[act or ""] and act or "DET"
    
    local itemID = _extractItemID(discovery and (discovery.i or discovery.il))
    
    local w = {
        v = 5,
        op = "ACK",
        ack = tostring(ackMid),
        act = act,
        c = tonumber(discovery and discovery.c) or 0,
        z = tonumber(discovery and discovery.z) or 0,
        iz = tonumber(discovery and discovery.iz) or 0,
        i = tonumber(itemID) or 0,
        x = discovery and discovery.xy and roundPrec(discovery.xy.x) or 0,
        y = discovery and discovery.xy and roundPrec(discovery.xy.y) or 0,
        t = tonumber(discovery and discovery.t0) or now(),
        s = _senderAnonFlag(),
        av = L and L.Version or "0.0.0",
    }
    
    w.seq = _nextSeq()
    
    if pTime then L:ProfileStop("Comm:_buildWireV5_ACK", pTime) end 
    return w
end

function Comm:_buildWireV5_CORR(corr_data)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not corr_data then 
        if pTime then L:ProfileStop("Comm:_buildWireV5_CORR", pTime) end
        return nil 
    end
    
    local w = {
        v = 5,
        op = "CORR",
        i = corr_data.i,
        c = corr_data.c,
        z = corr_data.z,
        fp = corr_data.fp,
        t0 = corr_data.t0,
    }
    
    if pTime then L:ProfileStop("Comm:_buildWireV5_CORR", pTime) end 
    return w
end

function Comm:SendAceCommPayload(wire)
    local pTime = L.ProfileStart and L:ProfileStart() 

	if not canSendMessages() then 
        if pTime then L:ProfileStop("Comm:SendAceCommPayload", pTime) end
        return 
    end
    if not wire then 
        if pTime then L:ProfileStop("Comm:SendAceCommPayload", pTime) end
        return 
    end
    
    local ok, payload = pcall(AceSerializer.Serialize, AceSerializer, wire)
    if not ok or type(payload) ~= "string" then 
        if pTime then L:ProfileStop("Comm:SendAceCommPayload", pTime) end
        return 
    end
    
    local dist = _pickDistribution()
    if dist then
        self:SendCommMessage(self.addonPrefix or "BBLCAM25TEST", payload, dist)
    end
    
    if pTime then L:ProfileStop("Comm:SendAceCommPayload", pTime) end 
end

local function _serializeAndDeflate(wire)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not (LibDeflate and AceSerializer) then 
        if pTime then L:ProfileStop("Comm:_serializeAndDeflate", pTime) end
        return nil 
    end
    local okS, serialized = pcall(AceSerializer.Serialize, AceSerializer, wire)
    if not okS or not serialized then 
        if pTime then L:ProfileStop("Comm:_serializeAndDeflate", pTime) end
        return nil 
    end
    
    local clevel = 9
    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.DEFLATE_LEVEL then
        clevel = Constants.DEFLATE_LEVEL
    end

    local okC, compressed = pcall(LibDeflate.CompressDeflate, LibDeflate, serialized, { level = clevel })
    if not okC or not compressed then 
        if pTime then L:ProfileStop("Comm:_serializeAndDeflate", pTime) end
        return nil 
    end
    
    local okE, encoded = pcall(LibDeflate.EncodeForPrint, LibDeflate, compressed)
    if not okE or not encoded then 
        if pTime then L:ProfileStop("Comm:_serializeAndDeflate", pTime) end
        return nil 
    end
    
    if pTime then L:ProfileStop("Comm:_serializeAndDeflate", pTime) end
    return encoded
end

local function _enqueueChannelWire(wire, forceBypassAFK)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local encoded = _serializeAndDeflate(wire)
    if not encoded then 
        if pTime then L:ProfileStop("Comm:_enqueueChannelWire", pTime) end
        return 
    end

    local op = wire.op or "DISC"
    local mid = wire.mid or wire.ack or ""
    
    local bypassAFK = forceBypassAFK or (op == "GFIX" or op == "ADCM")

    local prefixBase = string.format("LC1:%%s:%s:%s:", op, mid)
    local samplePrefix = string.format(prefixBase, "M1")
    local maxChunkSize = (Comm.maxChatBytes or 250) - string.len(samplePrefix)

    local insertPos = bypassAFK and 1 or (#Comm._rateLimitQueue + 1)

    if string.len(encoded) + string.len(string.format("LC1:%s:%s:", op, mid)) <= (Comm.maxChatBytes or 250) then
        local rawStr = string.format("LC1:%s:%s:%s", op, mid, encoded)
        table.insert(Comm._rateLimitQueue, insertPos, { tinserted = now(), rawStr = rawStr, bypassAFK = bypassAFK })
    else
        local pos = 1
        local textlen = string.len(encoded)

        local chunk = string.sub(encoded, pos, pos + maxChunkSize - 1)
        table.insert(Comm._rateLimitQueue, insertPos, { tinserted = now(), rawStr = string.format(prefixBase, "M1") .. chunk, bypassAFK = bypassAFK })
        insertPos = insertPos + 1
        pos = pos + maxChunkSize

        while pos + maxChunkSize <= textlen do
            chunk = string.sub(encoded, pos, pos + maxChunkSize - 1)
            table.insert(Comm._rateLimitQueue, insertPos, { tinserted = now(), rawStr = string.format(prefixBase, "M2") .. chunk, bypassAFK = bypassAFK })
            insertPos = insertPos + 1
            pos = pos + maxChunkSize
        end

        chunk = string.sub(encoded, pos)
        table.insert(Comm._rateLimitQueue, insertPos, { tinserted = now(), rawStr = string.format(prefixBase, "M3") .. chunk, bypassAFK = bypassAFK })
    end
    
    if pTime then L:ProfileStop("Comm:_enqueueChannelWire", pTime) end 
end

local function _sendRawToNetwork(rawStr)
    local tnow = now()
    if not L.channelReady then return false end

    if (tnow - (Comm._lastSendAt or 0)) < (Comm.chatMinInterval or 0.75) then
        return false
    end
    
    if not Comm:IsChannelHealthy() then
        Comm:EnsureChannelJoined()
        return false
    end
    
    SendChatMessage(rawStr, "CHANNEL", nil, Comm.channelId or 0)
    Comm._lastSendAt = tnow
    return true
end

local function _isSenderRestricted(name)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not name or name == "" then 
        if pTime then L:ProfileStop("Comm:_isSenderRestricted", pTime) end
        return false 
    end
    
    local Constants = L:GetModule("Constants", true)
    if not Constants then 
        if pTime then L:ProfileStop("Comm:_isSenderRestricted", pTime) end
        return false 
    end
    
    local normalizedName = L:normalizeSenderName(name)
    if not normalizedName then 
        if pTime then L:ProfileStop("Comm:_isSenderRestricted", pTime) end
        return false 
    end
       
    local isR = Constants:IsHashInList(normalizedName, "rHASH_BLACKLIST")
    
    if pTime then L:ProfileStop("Comm:_isSenderRestricted", pTime) end 
    return isR
end

function Comm:BroadcastDiscovery(discovery)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if L:IsPaused() then 
        if pTime then L:ProfileStop("Comm:BroadcastDiscovery", pTime) end
        return 
    end
    local Core = L:GetModule("Core", true)
    if Core and Core.isSB and Core:isSB() then 
        if pTime then L:ProfileStop("Comm:BroadcastDiscovery", pTime) end
        return 
    end
    if not isSharingEnabled() or not canSendMessages() then 
        if pTime then L:ProfileStop("Comm:BroadcastDiscovery", pTime) end
        return 
    end
    
    if L and L.IsPaused and L:IsPaused() then
        if L.pauseQueue and L.pauseQueue.outgoing then
            table.insert(L.pauseQueue.outgoing, discovery)
        end
        if pTime then L:ProfileStop("Comm:BroadcastDiscovery", pTime) end
        return
    end
    
    local p = L and L.db and L.db.profile
    if not (p and p.sharing and p.sharing.enabled) then 
        if pTime then L:ProfileStop("Comm:BroadcastDiscovery", pTime) end
        return 
    end
    
    if p.sharing.delayed then
        table.insert(self._delayQueue, { fireAt = now() + (p.sharing.delaySeconds or 30), data = discovery })
        if pTime then L:ProfileStop("Comm:BroadcastDiscovery", pTime) end
        return
    end

    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.ALLOWED_DISCOVERY_TYPES and discovery.dt then
        if not Constants.ALLOWED_DISCOVERY_TYPES[discovery.dt] then
            if pTime then L:ProfileStop("Comm:BroadcastDiscovery", pTime) end
            return
        end
    end
    
    local tnow = time()
    if discovery.ls and (tnow - tonumber(discovery.ls)) > (120 * 86400) then
        if pTime then L:ProfileStop("Comm:BroadcastDiscovery", pTime) end
        return
    end
    
    local w = self:buildWireV5DISC(discovery)
    if not w then 
        if pTime then L:ProfileStop("Comm:BroadcastDiscovery", pTime) end
        return 
    end
    
    _enqueueChannelWire(w)
    
    if pTime then L:ProfileStop("Comm:BroadcastDiscovery", pTime) end 
end

function Comm:BroadcastReinforcement(discovery)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if L:IsPaused() then 
        if pTime then L:ProfileStop("Comm:BroadcastReinforcement", pTime) end
        return 
    end
    local p = L and L.db and L.db.profile
    
    if not isSharingEnabled() then 
        if pTime then L:ProfileStop("Comm:BroadcastReinforcement", pTime) end
        return 
    end
    if not (p and p.sharing and p.sharing.enabled) then 
        if pTime then L:ProfileStop("Comm:BroadcastReinforcement", pTime) end
        return 
    end

    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.ALLOWED_DISCOVERY_TYPES and discovery.dt then
        if not Constants.ALLOWED_DISCOVERY_TYPES[discovery.dt] then
            if pTime then L:ProfileStop("Comm:BroadcastReinforcement", pTime) end
            return
        end
    end
    
    local tnow = time()
    if discovery.ls and (tnow - tonumber(discovery.ls)) > (120 * 86400) then
        if pTime then L:ProfileStop("Comm:BroadcastReinforcement", pTime) end
        return
    end
    
    local w = self:buildWireV5CONF(discovery)
    if not w then 
        if pTime then L:ProfileStop("Comm:BroadcastReinforcement", pTime) end
        return 
    end
    
    _enqueueChannelWire(w)
    
    if pTime then L:ProfileStop("Comm:BroadcastReinforcement", pTime) end 
end

function Comm:BroadcastShow(discovery, targetPlayer)
if L:IsPaused() then return end
    if not discovery or not targetPlayer or targetPlayer == "" then
        return
    end
    
    if not isSharingEnabled() or not canSendMessages() then return end

    L._cdebug("Comm-Broadcast", string.format("BroadcastShow called. Discovery has dt: %s, src: %s", tostring(discovery.dt), tostring(discovery.src)))

    local Constants = L:GetModule("Constants", true)
    local isVendor = discovery.dt and Constants and discovery.dt == Constants.DISCOVERY_TYPE.BLACKMARKET
    if isVendor and discovery.vendorItems and #discovery.vendorItems > 10 then
        print(string.format("|cffff7f00LootCollector:|r Cannot show vendor to %s. It has too many items (%d) to send via whisper.", targetPlayer, #discovery.vendorItems))
        return
    end
    
    local tnow = time()
    if discovery.ls and (tnow - tonumber(discovery.ls)) > (120 * 86400) then
        return
    end

    local w = self:_buildWireV5_SHOW(discovery)
    if not w then 
        return 
    end

    local ok, payload = pcall(AceSerializer.Serialize, AceSerializer, w)
    if not ok or type(payload) ~= "string" then 
        return 
    end

    self:SendCommMessage(self.addonPrefix, payload, "WHISPER", targetPlayer)
    print(string.format("|cff00ff00LootCollector:|r Sent discovery location for %s to |cffffff00%s|r.", discovery.il or "item", targetPlayer))
end

function Comm:BroadcastAC(ACPayload)
    if not isSharingEnabled() or not canSendMessages() then return end

    local w = {
        v = 5,
        op = "ADCM",
        av = L.Version or "0.0.0",
        payload = ACPayload,
        
        
        mid = _computeMid({v = 5, op = "ADCM", t = now()}),
        seq = _nextSeq(),
    }

    self:SendAceCommPayload(w)
    
    
    _enqueueChannelWire(w)
    
    print(string.format("|cff00ff00LootCollector-Dev:|r Broadcasted AC command [%s: %s] to network.", tostring(ACPayload.act), tostring(ACPayload.cmd)))
end

function Comm:BroadcastGuidedFix(fixData)
    if not isSharingEnabled() or not canSendMessages() then return end

    local w = self:_buildWireV5_GFIX(fixData)
    if not w then return end

    self:SendAceCommPayload(w)
    
    _enqueueChannelWire(w)
    
    print(string.format("|cff00ff00LootCollector:|r Broadcasted GFIX (Type %d) for item %d to network.", fixData.type or 0, fixData.i or 0))
end

function Comm:BroadcastAckFor(discovery, ackMid, act, bypassAFK)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not isSharingEnabled() or not canSendMessages() then 
        if pTime then L:ProfileStop("Comm:BroadcastAckFor", pTime) end
        return 
    end

    L._cdebug("Comm-Broadcast", string.format("Preparing to broadcast ACK for mid: %s, act: %s", tostring(ackMid), tostring(act)))

    local w = self:_buildWireV5_ACK(discovery, ackMid, act)
    if not w then 
        L._cdebug("Comm-Broadcast", "Failed to build ACK wire payload.")
        if pTime then L:ProfileStop("Comm:BroadcastAckFor", pTime) end
        return 
    end
    
    self:SendAceCommPayload(w)    
    local p = L and L.db and L.db.profile
    if p and p.sharing and p.sharing.ackOnChannel then
        L._cdebug("Comm-Broadcast", "Enqueuing ACK for public channel transmission.")
        _enqueueChannelWire(w, bypassAFK)
    else
        L._cdebug("Comm-Broadcast", "ACK public channel transmission skipped (ackOnChannel is false/nil).")
    end
    
    if pTime then L:ProfileStop("Comm:BroadcastAckFor", pTime) end 
end

function Comm:BroadcastCorrection(corr_data)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not isSharingEnabled() or not canSendMessages() then 
        if pTime then L:ProfileStop("Comm:BroadcastCorrection", pTime) end
        return 
    end

    if not (L and L.db and L.db.profile and L.db.profile.sharing and L.db.profile.sharing.enabled) then 
        if pTime then L:ProfileStop("Comm:BroadcastCorrection", pTime) end
        return 
    end
    
    local w = self:_buildWireV5_CORR(corr_data)
    if not w then 
        if pTime then L:ProfileStop("Comm:BroadcastCorrection", pTime) end
        return 
    end
    
    self:SendAceCommPayload(w)
    _enqueueChannelWire(w)
    
    if pTime then L:ProfileStop("Comm:BroadcastCorrection", pTime) end 
end

local function _bucketRefill()
    local tnow = now()
    local elapsed = tnow - (Comm._bucketLastFill or tnow)
    if elapsed <= 0 then return end
    
    local cap = Comm.RATE_LIMIT_COUNT or 9
    local window = Comm.RATE_LIMIT_WINDOW or 60
    local rate = cap / window
    
    local tokens = (Comm._bucketTokens or cap) + elapsed * rate
    if tokens > cap then tokens = cap end
    
    Comm._bucketTokens = tokens
    Comm._bucketLastFill = tnow
end

local function _bucketTake()
    _bucketRefill()
    if (Comm._bucketTokens or 0) >= 1 then
        Comm._bucketTokens = Comm._bucketTokens - 1
        return true
    end
    return false
end

function Comm:processIncomingQueue()
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not Core then Core = L:GetModule("Core", true) end
    if not Core or not Core.AddDiscovery then 
        if pTime then L:ProfileStop("Comm:processIncomingQueue", pTime) end
        return 
    end
    if not self._incomingMessageQueue or #self._incomingMessageQueue == 0 then 
        if pTime then L:ProfileStop("Comm:processIncomingQueue", pTime) end
        return 
    end

    local currentBatchSize = BATCH_SIZE_NORMAL
    if InCombatLockdown() then
        currentBatchSize = BATCH_SIZE_COMBAT
    end

    Core.IsBatchProcessing = true
    Core.DataHasChanged = false 
    
    local processedCount = 0

    while processedCount < currentBatchSize and #self._incomingMessageQueue > 0 do
        local entry = table.remove(self._incomingMessageQueue, 1)
        if entry and entry.data and entry.options then
            
            local ok, err = pcall(function()
                Core:AddDiscovery(entry.data, entry.options)
            end)
            
            if not ok then
                L._cdebug("Comm-BatchError", "Error processing discovery: " .. tostring(err))
            end

            if self.queuedMids and entry.data.mid then
                self.queuedMids[entry.data.mid] = nil
            end

            processedCount = processedCount + 1
        end
    end

    Core.IsBatchProcessing = false

    if processedCount > 0 and Core.DataHasChanged then
        if not self._uiUpdateTimer then
            self._uiUpdateTimer = L:ScheduleAfter(0.5, function()
                self._uiUpdateTimer = nil
                Core.DataHasChanged = true 
                L:SendMessage("LootCollector_DiscoveriesUpdated", "bulk", nil, nil)
                L:SendMessage("LOOTCOLLECTOR_DISCOVERY_LIST_UPDATED")
            end)
        end
    end
    
    if pTime then L:ProfileStop("Comm:processIncomingQueue", pTime) end 
end

function Comm:OnUpdate(elapsed)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if Comm.isLoggingOut then 
        if pTime then L:ProfileStop("Comm:OnUpdate", pTime) end
        return 
    end
    
    if elapsed > 0.5 then
        local bufferSize = #Comm.rawBuffer
        local dynamicDuration = 1.0 + (bufferSize / 6 * 0.5)
        Comm._lagRecoveryTimer = math.min(7.0, dynamicDuration)
        
        if bufferSize >= RAW_BUFFER_CAP then
            for i = 1, math.floor(RAW_BUFFER_CAP * 0.2) do
                table.remove(Comm.rawBuffer, 1)
            end
        end
    elseif Comm._lagRecoveryTimer > 0 then
        Comm._lagRecoveryTimer = Comm._lagRecoveryTimer - elapsed
    end
    
    elapsed = math.min(elapsed, 0.1)

    if self._delayQueue and #self._delayQueue > 0 then
        local tnow = time()
        local i = 1
        while i <= #self._delayQueue do
            local e = self._delayQueue[i]
            if e and tnow >= (e.fireAt or 0) then
                self:BroadcastDiscovery(e.data)
                table.remove(self._delayQueue, i)
            else
                i = i + 1
            end
        end
    end
    
    local isAFK = UnitIsAFK("player")
    
    if self._rateLimitQueue and #self._rateLimitQueue > 0 then
        local nextEntry = self._rateLimitQueue[1]
        
        if not isAFK or nextEntry.bypassAFK then
            if _bucketTake() then
                local entry = table.remove(self._rateLimitQueue, 1)
                if entry and entry.rawStr then
                    local sent = _sendRawToNetwork(entry.rawStr)
                    if not sent then
                        table.insert(self._rateLimitQueue, 1, entry) 
                    end
                end
            end
        end
    end
    
    if #Comm.rawBuffer > 0 then
        local tnow = time()
        if not self._lastCachePrune or (tnow - self._lastCachePrune) >= 2 then
            pruneCaches()
            self._lastCachePrune = tnow
        end
        self:_ProcessRawBuffer()
    end
    
    self._processTimer = (self._processTimer or 0) + elapsed
    if self._processTimer >= PROCESS_INTERVAL then
        self:processIncomingQueue()
        self._processTimer = 0
    end
    
    if pTime then L:ProfileStop("Comm:OnUpdate", pTime) end 
end

local function _lc_isPlausiblePayload(msg)
    return type(msg) == "string" and msg:match("^LC[1-5]:")
end

local function _lc_tryDecodeEncodedPayload(msg)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if not (LibDeflate and AceSerializer) then 
        L._cdebug("Comm-Decode", "LibDeflate or AceSerializer missing.")
        if pTime then L:ProfileStop("Comm:_lc_tryDecodeEncodedPayload", pTime) end
        return nil 
    end
    
    local encoded = msg:match("^LC[1-5]:(.+)$")
    if not encoded then 
        L._cdebug("Comm-Decode", "Failed to match LC prefix for decode.")
        if pTime then L:ProfileStop("Comm:_lc_tryDecodeEncodedPayload", pTime) end
        return nil 
    end
    
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then 
        L._cdebug("Comm-Decode", "LibDeflate:DecodeForPrint failed.")
        if pTime then L:ProfileStop("Comm:_lc_tryDecodeEncodedPayload", pTime) end
        return nil 
    end
    
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then 
        L._cdebug("Comm-Decode", "LibDeflate:DecompressDeflate failed.")
        if pTime then L:ProfileStop("Comm:_lc_tryDecodeEncodedPayload", pTime) end
        return nil 
    end
    
    local ok, data = AceSerializer:Deserialize(decompressed)
    if not ok then
        L._cdebug("Comm-Decode", "AceSerializer:Deserialize failed: " .. tostring(data))
        if pTime then L:ProfileStop("Comm:_lc_tryDecodeEncodedPayload", pTime) end
        return nil
    end

    if type(data) == "table" then 
        L._cdebug("Comm-Decode", "Successfully decoded payload.")
        if pTime then L:ProfileStop("Comm:_lc_tryDecodeEncodedPayload", pTime) end
        return data 
    end
    
    L._cdebug("Comm-Decode", "Deserialized data is not a table.")
    if pTime then L:ProfileStop("Comm:_lc_tryDecodeEncodedPayload", pTime) end
    return nil
end

local function _lc_parsePlainV5(msg)
    local pTime = L.ProfileStart and L:ProfileStart() 

    local segments = Comm._scratchSegments
    wipe(segments)
    
    for seg in string.gmatch(msg or "", "([^:]+)") do
        table.insert(segments, seg)
    end
    
    if #segments < 3 then 
        if pTime then L:ProfileStop("Comm:_lc_parsePlainV5", pTime) end
        return nil 
    end
    if segments[1] ~= "LC1" then 
        if pTime then L:ProfileStop("Comm:_lc_parsePlainV5", pTime) end
        return nil 
    end
    
    local v = tonumber(segments[2])
    if v ~= 5 then 
        if pTime then L:ProfileStop("Comm:_lc_parsePlainV5", pTime) end
        return nil 
    end
    
    local op = segments[3]

    if op == "ACK" then
        if #segments < 6 then 
            if pTime then L:ProfileStop("Comm:_lc_parsePlainV5", pTime) end
            return nil 
        end
        local r = { v = 5, op = "ACK", ack = segments[4], act = segments[5], seq = tonumber(segments[6]) or 0 }
        if pTime then L:ProfileStop("Comm:_lc_parsePlainV5", pTime) end
        return r
    end
    
    if op == "CORR" then
        if #segments < 8 then 
            if pTime then L:ProfileStop("Comm:_lc_parsePlainV5", pTime) end
            return nil 
        end
        local r = {
            v = 5, op = "CORR",
            i = tonumber(segments[4]) or 0,
            c = tonumber(segments[5]) or 0,
            z = tonumber(segments[6]) or 0,
            fp = segments[7],
            t0 = tonumber(segments[8]) or 0,
        }
        if pTime then L:ProfileStop("Comm:_lc_parsePlainV5", pTime) end
        return r
    end
    
    if #segments < 15 then 
        if pTime then L:ProfileStop("Comm:_lc_parsePlainV5", pTime) end
        return nil 
    end
    
    local r = {
        v = 5, op = op,
        c = tonumber(segments[4]) or 0,
        z = tonumber(segments[5]) or 0,
        iz = tonumber(segments[6]) or 0,
        i = tonumber(segments[7]) or 0,
        x = tonumber(segments[8]) or 0,
        y = tonumber(segments[9]) or 0,
        t = tonumber(segments[10]) or now(),
        q = tonumber(segments[11]) or 1,
        s = tonumber(segments[12]) or 0,
        av = segments[13],
        mid = segments[14],
        seq = tonumber(segments[15]) or 0,
        dt = segments[16],
        it = segments[17],
        ist = segments[18],
        cl = segments[19],
        fp = segments[20],
        src = tonumber(segments[21]), 
    }
    
    if pTime then L:ProfileStop("Comm:_lc_parsePlainV5", pTime) end 
    return r
end

local function isSelfSender(sender)
    if not sender or sender == "" then return false end

    local me = UnitName("player")
    if not me or me == "" then return false end

    if L.normalizeSenderName then
        local a = L:normalizeSenderName(sender)
        local b = L:normalizeSenderName(me)
        return a and b and a == b
    end

    local shortSender = tostring(sender):match("^[^-]+") or tostring(sender)
    return shortSender == me
end

local function _lc_validateNormalized(tbl)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if type(tbl) ~= "table" then
        if pTime then L:ProfileStop("Comm:_lc_validateNormalized", pTime) end
        return nil, "invalid_payload"
    end

    if tbl.v == 5 then
        if tbl.op == "ACK" or tbl.op == "CORR" or tbl.op == "GFIX" or tbl.op == "ADCM" then
            if pTime then L:ProfileStop("Comm:_lc_validateNormalized", pTime) end
            return tbl
        end

        local req
        if tbl.op == "SHOW" then
            req = { "op", "c", "z", "i", "x", "y", "t", "q", "av", "fp", "il" }
        else
            req = { "op", "c", "z", "i", "x", "y", "t", "q", "s", "av" }
        end

        for _, k in ipairs(req) do
            if tbl[k] == nil then
                if pTime then L:ProfileStop("Comm:_lc_validateNormalized", pTime) end
                return nil, "missing_" .. k
            end
        end

        local c = tonumber(tbl.c)
        if not c or c < 0 or c > 4 then
            if pTime then L:ProfileStop("Comm:_lc_validateNormalized", pTime) end
            return nil, "invalid_continent"
        end

        local z = tonumber(tbl.z)
        if not z or z < 0 or z > 9999 then
            if pTime then L:ProfileStop("Comm:_lc_validateNormalized", pTime) end
            return nil, "invalid_zone"
        end

        
        local ZoneList = L:GetModule("ZoneList", true)
        if ZoneList and ZoneList.MapDataByID then
            local mapData = ZoneList.MapDataByID[z]
            if mapData and mapData.continentID ~= c and z <= 2000 then
                if pTime then L:ProfileStop("Comm:_lc_validateNormalized", pTime) end
                return nil, "invalid_continent_zone_combo"
            end
        end

        local x, y = tonumber(tbl.x), tonumber(tbl.y)
        if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then
            if pTime then L:ProfileStop("Comm:_lc_validateNormalized", pTime) end
            return nil, "invalid_coords"
        end

        tbl.iz = tonumber(tbl.iz) or 0
               
        
        
        if tbl.op ~= "SHOW" then
            tbl.mid = tbl.mid or _computeMid(tbl)
            tbl.seq = tonumber(tbl.seq) or 0
        end

        if pTime then L:ProfileStop("Comm:_lc_validateNormalized", pTime) end
        return tbl
    end

    if tbl.v == 1 then
        if not tbl.op or tbl.i == nil or tbl.z == nil or tbl.x == nil or tbl.y == nil or tbl.t == nil then
            if pTime then L:ProfileStop("Comm:_lc_validateNormalized", pTime) end
            return nil, "missing_fields"
        end

        tbl.c = tonumber(tbl.c) or 0
        tbl.iz = tonumber(tbl.iz) or 0
        tbl.q = tonumber(tbl.q) or 1
        tbl.s = tonumber(tbl.s) or 0

        if pTime then L:ProfileStop("Comm:_lc_validateNormalized", pTime) end
        return tbl
    end

    if pTime then L:ProfileStop("Comm:_lc_validateNormalized", pTime) end 
    return nil, "unknown_version"
end

local function _normalizeForCore(tbl, sender, Comm)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if tbl.op == "ACK" or tbl.op == "CORR" then
        tbl.sender = sender
        if pTime then L:ProfileStop("Comm:_normalizeForCore", pTime) end
        return tbl
    end
    
    if tbl.op == "DISC" then
        if (tbl.s or 0) == 0 then
            if tbl.fp and tbl.fp ~= "" and tbl.fp ~= sender then
                trackInvalidSender(sender, "disc_fp_mismatch", tbl)
                if pTime then L:ProfileStop("Comm:_normalizeForCore", pTime) end
                return nil
            end
        else
            if tbl.fp and tbl.fp ~= "" then
                trackInvalidSender(sender, "disc_anon_fp_not_empty", tbl)
                if pTime then L:ProfileStop("Comm:_normalizeForCore", pTime) end
                return nil
            end
        end
    elseif tbl.op == "CONF" then
        if (tbl.s or 0) == 1 then
            if tbl.fp and tbl.fp ~= "" then
                trackInvalidSender(sender, "conf_anon_fp_not_empty", tbl)
                if pTime then L:ProfileStop("Comm:_normalizeForCore", pTime) end
                return nil
            end
        end
    end

    local itemID = tonumber(tbl.i) or _extractItemID(tbl.l)
    
    local historicalFp = tbl.fp
    if tbl.op == "DISC" then
        if (tbl.s or 0) == 1 then
            historicalFp = "An Unnamed Collector"
        else
            if not historicalFp or historicalFp == "" then
                historicalFp = sender
            end
        end
    else
        if not historicalFp or historicalFp == "" then
             historicalFp = sender
        end
    end
    
    local r = {
        v = tbl.v,
        op = tbl.op,
        i = itemID,
        il = tbl.l or select(2, GetItemInfo(itemID or 0)),
        q = tonumber(tbl.q) or 1,
        c = tonumber(tbl.c) or 0,
        z = tonumber(tbl.z) or 0,
        iz = tonumber(tbl.iz) or 0,
        xy = { x = roundPrec(tbl.x or 0), y = roundPrec(tbl.y or 0) },
        t0 = tonumber(tbl.t) or now(),
        ls = tonumber(tbl.t) or now(),
        av = tbl.av,
        mid = tbl.mid,
        seq = tbl.seq or 0,
        sflag = tbl.s or 0,
        dt = tbl.dt, it = tbl.it, ist = tbl.ist,
        cl = tbl.cl,
        src = tbl.src, 
        fp = historicalFp,
        sender = sender,
    }
    
    if pTime then L:ProfileStop("Comm:_normalizeForCore", pTime) end 
    return r
end

function Comm:_trackInvalidSender(sender, reason, payload)
    trackInvalidSender(sender, reason, payload)
end

local function _onChatMsgChannel(_, _, msg, sender, _, _, _, _, _, _, channelName)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if Comm.isLoggingOut then 
        if pTime then L:ProfileStop("Comm:_onChatMsgChannel", pTime) end
        return 
    end
    if isSelfSender(sender) then 
        if pTime then L:ProfileStop("Comm:_onChatMsgChannel", pTime) end
        return 
    end
    if not isSharingEnabled() then 
        if pTime then L:ProfileStop("Comm:_onChatMsgChannel", pTime) end
        return 
    end
    
    local chA = string.upper(channelName or "")
    local chB = string.upper(Comm.channelName or "")
    if chA ~= chB then 
        if pTime then L:ProfileStop("Comm:_onChatMsgChannel", pTime) end
        return 
    end
    
    if isSenderPermanentlyBlacklisted(sender) then 
        if pTime then L:ProfileStop("Comm:_onChatMsgChannel", pTime) end
        return 
    end
    
    table.insert(Comm.rawBuffer, { type="CHAT", msg=msg, sender=sender, channel=channelName })
    
    if pTime then L:ProfileStop("Comm:_onChatMsgChannel", pTime) end 
end

function Comm:OnCommReceived(prefix, message, distribution, sender)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if Comm.isLoggingOut then 
        if pTime then L:ProfileStop("Comm:OnCommReceived", pTime) end
        return 
    end
    if prefix ~= (self.addonPrefix or "BBLC25AM") then 
        if pTime then L:ProfileStop("Comm:OnCommReceived", pTime) end
        return 
    end
    if type(message) ~= "string" then 
        if pTime then L:ProfileStop("Comm:OnCommReceived", pTime) end
        return 
    end
    if not isSharingEnabled() then 
        if pTime then L:ProfileStop("Comm:OnCommReceived", pTime) end
        return 
    end
    if isSenderPermanentlyBlacklisted(sender) then 
        if pTime then L:ProfileStop("Comm:OnCommReceived", pTime) end
        return 
    end        
    if #Comm.rawBuffer >= RAW_BUFFER_CAP then
        table.remove(Comm.rawBuffer, 1)
    end
    
    table.insert(Comm.rawBuffer, { type="ACE", msg=message, dist=distribution, sender=sender })
    
    if pTime then L:ProfileStop("Comm:OnCommReceived", pTime) end 
end

function Comm:_ProcessRawBuffer()
    local pTime = L.ProfileStart and L:ProfileStart() 
    local startTime = debugprofilestop()
        
    local safetyLimit = (Comm._lagRecoveryTimer > 0) and 6 or 50
    local budget = InCombatLockdown() and 1.0 or RAW_PROCESS_BUDGET_MS

    local processed = 0
    while #Comm.rawBuffer > 0 and processed < safetyLimit do
        local entry = table.remove(Comm.rawBuffer, 1)
        
        if entry.type == "CHAT" then
            self:_ProcessChatMsg(entry.msg, entry.sender, entry.channel)
        elseif entry.type == "ACE" then
            self:_ProcessAceMsg(entry.msg, entry.dist, entry.sender)
        end
        
        processed = processed + 1
        
        if (debugprofilestop() - startTime) >= budget then
            break
        end
    end
    
    if pTime then L:ProfileStop("Comm:_ProcessRawBuffer", pTime) end 
end

local function isVersionCompatible(av)
    if not Comm._minCompatibleVersion then
        local Constants = L:GetModule("Constants", true)
        Comm._minCompatibleVersion = Constants and Constants.GetMinCompatibleVersion and Constants:GetMinCompatibleVersion() or "0.0.0"
    end
    
    if not av or av == "" then return false end
    
    return compareVersions(av, Comm._minCompatibleVersion) >= 0
end

local MAX_CHUNKS_PER_MSG = 25      
local MAX_SPOOLS_PER_SENDER = 3    
local MAX_TOTAL_SPOOLS = 50        

function Comm:_ProcessChatMsg(msg, sender, channelName)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if isSenderPermanentlyBlacklisted(sender) then 
        if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
        return 
    end
    if not _lc_isPlausiblePayload(msg) then 
        if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
        return 
    end
    
    L._cdebug("Comm-Process", "Processing plausible chat message from: " .. tostring(sender))

    local mType, optOp, optMid, optEncoded = msg:match("^LC1:(M[1-3]):(%u+):([^:]+):(.+)$")
    if not mType then
        optOp, optMid, optEncoded = msg:match("^LC1:(%u+):([^:]+):(.+)$")
    end

    if optOp and optMid then
        L._cdebug("Comm-Process", string.format("Regex matched header - Type: %s, OP: %s, MID: %s, Sender: %s", tostring(mType), optOp, optMid, tostring(sender)))

        if mType then
            local spoolKey = sender .. ":" .. optMid
            Comm._multipartSpool = Comm._multipartSpool or {}

            if mType == "M1" then
                local totalSpools, senderSpools = 0, 0
                for k, _ in pairs(Comm._multipartSpool) do
                    totalSpools = totalSpools + 1
                    if string.sub(k, 1, string.len(sender)) == sender then
                        senderSpools = senderSpools + 1
                    end
                end
                
                if totalSpools >= MAX_TOTAL_SPOOLS or senderSpools >= MAX_SPOOLS_PER_SENDER then
                    L._cdebug("Comm-Security", "Dropped M1: Spool memory limits reached. Sender: " .. sender)
                    if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
                    return
                end

                Comm._multipartSpool[spoolKey] = { ts = now(), chunks = {optEncoded} }
                if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
                return 
            elseif mType == "M2" then
                local spool = Comm._multipartSpool[spoolKey]
                if spool then
                    if #spool.chunks >= MAX_CHUNKS_PER_MSG then
                        L._cdebug("Comm-Security", "Dropped M2: Chunk limit exceeded. Killing spool for " .. sender)
                        Comm._multipartSpool[spoolKey] = nil 
                        if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
                        return
                    end
                    table.insert(spool.chunks, optEncoded)
                    spool.ts = now() 
                end
                if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
                return 
            elseif mType == "M3" then
                local spool = Comm._multipartSpool[spoolKey]
                if spool then
                    if #spool.chunks >= MAX_CHUNKS_PER_MSG then
                        Comm._multipartSpool[spoolKey] = nil
                        if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
                        return
                    end
                    table.insert(spool.chunks, optEncoded)
                    optEncoded = table.concat(spool.chunks, "")
                    Comm._multipartSpool[spoolKey] = nil
                else
                    if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
                    return 
                end
            end
        end

        if optOp == "CONF" then
            if Core and Core.IsDiscoveryFresh and Core:IsDiscoveryFresh(optMid) then 
                if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
                return 
            end
        end
        
        if L.db and L.db.global and L.db.global.deletedCache and L.db.global.deletedCache[optMid] then
             if optOp ~= "DISC" then 
                 L._cdebug("Comm-Process", "Dropped: Mid is in deletedCache and OP is not DISC." .. tostring(sender))
                 if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
                 return 
             end
        end
        
        if shouldDropIngressDuplicate(sender, optOp, optMid) then
            L._cdebug("Comm-Process", "Dropped: Ingress duplicate detected." .. tostring(sender))
            if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
            return
        end
        
        local data = _lc_tryDecodeEncodedPayload("LC1:" .. optEncoded)
        if data then
             if not isVersionCompatible(data.av) then 
                 L._cdebug("Comm-Process", string.format("Dropped: Version incompatible (Packet AV: %s, Min Required: %s, Sender: %s)", tostring(data.av), tostring(Comm._minCompatibleVersion), tostring(sender)))
                 if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
                 return 
             end

             if not data.op then data.op = optOp end
             if not data.mid then data.mid = optMid end

             if (tonumber(data.c) or 0) == -1 and data.z then
                 local ZoneList = L:GetModule("ZoneList", true)
                 local zInfo = ZoneList and ZoneList.MapDataByID and ZoneList.MapDataByID[tonumber(data.z)]
                 if zInfo and zInfo.continentID then data.c = zInfo.continentID end
             end
             
             local tbl, reason = _lc_validateNormalized(data)
             if not tbl then
                L._cdebug("Comm-Process", "Validation failed: " .. tostring(reason))
                trackInvalidSender(sender, reason, data)
                if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
                return
             end
             
             if isSenderSessionIgnored(sender) then 
                 L._cdebug("Comm-Process", "Dropped: Sender " .. tostring(sender) .." session ignored.")
                 if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
                 return 
             end
             
             L._cdebug("Comm-Process", "Validation successful. Routing incoming...")
             Comm:RouteIncoming(tbl, "CHANNEL", sender or "Unknown")
             if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
             return
        else
             L._cdebug("Comm-Process", "Failed to decode optEncoded block.")
        end
    end
    
    L._cdebug("Comm-Process", "Header regex failed. Falling back to plain parse.")
    
    local data = _lc_tryDecodeEncodedPayload(msg)
    if not data then       
        data = _lc_parsePlainV5(msg)               
        if not data then 
            L._cdebug("Comm-Process", "Plain parse failed.")
            if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
            return 
        end
    end
    
    if not isVersionCompatible(data.av) then 
        L._cdebug("Comm-Process", "Dropped: Version incompatible on fallback.")
        if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
        return 
    end
    
    if (tonumber(data.c) or 0) == -1 and data.z then
         local ZoneList = L:GetModule("ZoneList", true)
         local zInfo = ZoneList and ZoneList.MapDataByID and ZoneList.MapDataByID[tonumber(data.z)]
         if zInfo and zInfo.continentID then data.c = zInfo.continentID end
    end
    
    local tbl, reason = _lc_validateNormalized(data)
    if not tbl then
        L._cdebug("Comm-Process", "Validation failed on fallback: " .. tostring(reason))
        trackInvalidSender(sender, reason, data)
        if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
        return
    end
    
    if isSenderSessionIgnored(sender) then 
        if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end
        return 
    end
    
    L._cdebug("Comm-Process", "Fallback validation successful. Routing incoming...")
    Comm:RouteIncoming(tbl, "CHANNEL", sender or "Unknown")
    
    if pTime then L:ProfileStop("Comm:_ProcessChatMsg", pTime) end 
end

function Comm:_ProcessAceMsg(message, distribution, sender)
    local pTime = L.ProfileStart and L:ProfileStart() 

    if isSenderPermanentlyBlacklisted(sender) then 
        if pTime then L:ProfileStop("Comm:_ProcessAceMsg", pTime) end
        return 
    end
    
    local ok, data = AceSerializer:Deserialize(message)
    if not ok or type(data) ~= "table" then 
        if pTime then L:ProfileStop("Comm:_ProcessAceMsg", pTime) end
        return 
    end

    if not isVersionCompatible(data.av) then 
        if pTime then L:ProfileStop("Comm:_ProcessAceMsg", pTime) end
        return 
    end
    
    if data.op == "DISC" or data.op == "CONF" then
        if shouldDropIngressDuplicate(sender, data.op, data.mid) then
            if pTime then L:ProfileStop("Comm:_ProcessAceMsg", pTime) end
            return
        end
    end
    
    if (tonumber(data.c) or 0) == -1 and data.z then
         local ZoneList = L:GetModule("ZoneList", true)
         local zInfo = ZoneList and ZoneList.MapDataByID and ZoneList.MapDataByID[tonumber(data.z)]
         if zInfo and zInfo.continentID then data.c = zInfo.continentID end
    end
    local tbl, reason = _lc_validateNormalized(data)
    if not tbl then
        trackInvalidSender(sender, reason, data)
        if pTime then L:ProfileStop("Comm:_ProcessAceMsg", pTime) end
        return
    end
    
    if isSenderSessionIgnored(sender) then 
        if pTime then L:ProfileStop("Comm:_ProcessAceMsg", pTime) end
        return 
    end
    Comm:RouteIncoming(tbl, distribution or "ACE", sender or "Unknown")
    
    if pTime then L:ProfileStop("Comm:_ProcessAceMsg", pTime) end 
end

function Comm:HandleAC(payload)
    if not payload or not payload.act then return end
    
    local g = L.db and L.db.global
    if not g then return end

    if payload.act == "ROSTER" then
        local target = payload.targetName
        local cmd = payload.cmd
        if not target or target == "" or not cmd then return end
        
        target = L:normalizeSenderName(target)
        if not target then return end

        g.aBL = g.aBL or {}
        g.aWL = g.aWL or {}

        if cmd == "BAN_PERM" then
            g.aBL[target] = true
            g.aWL[target] = nil
            L._cdebug("Comm-AC", "SB: Added " .. target)
            
        elseif cmd == "BAN_SESSION" then
            
            if L.db.profile then
                L.db.profile.invalidSenders = L.db.profile.invalidSenders or {}
                L.db.profile.invalidSenders[target] = {
                    count = 999,
                    lastInvalid = now(),
                    sessionIgnored = true,
                    lastReason = "ac_hot_ban"
                }
            end
            L._cdebug("Comm-AC", "Hot Banlist: Supressed session for " .. target)

        elseif cmd == "WHITELIST" then
            g.aBL[target] = nil
            g.aWL[target] = true
            L._cdebug("Comm-AC", "Shadow Whitelist: Added " .. target)

        elseif cmd == "REMOVE" then
            g.aBL[target] = nil
            g.aWL[target] = nil
            L._cdebug("Comm-AC", "Roster: Cleared lists for " .. target)
        end

    elseif payload.act == "KS" then
        local targetVer = payload.targetVersion
        local cmd = payload.cmd
        if not targetVer or targetVer == "" or not cmd then return end
        
        
        g.killedVersionsLedger = g.killedVersionsLedger or {}
        
        if cmd == "K_EXACT" then
            g.killedVersionsLedger[targetVer] = true
            L._cdebug("Comm-AC", "KS Ledger: Logged exact version " .. targetVer)
        elseif cmd == "K_OUTDATED" then
            
            if not g.outdatedThreshold or compareVersions(targetVer, g.outdatedThreshold) > 0 then
                g.outdatedThreshold = targetVer
                L._cdebug("Comm-AC", "KS Ledger: Updated threshold to " .. targetVer)
            end
        end
        
        self:EvaluateKS()
    end
end

function Comm:EvaluateKS()
    local g = L.db and L.db.global
    if not g then return end

    local myVer = L.Version or "0.0.0"
    local shouldKill = false

    
    if g.killedVersionsLedger and g.killedVersionsLedger[myVer] then
        shouldKill = true
    end

    
    if g.outdatedThreshold and compareVersions(myVer, g.outdatedThreshold) <= 0 then
        shouldKill = true
    end

    if shouldKill then
        g.isOutdatedAndKilled = true
        L._cdebug("Comm-AC", "KS ENGAGED. Addon networking severed.")
        
        
        if L.db.profile and L.db.profile.sharing then
            L.db.profile.sharing.enabled = false
        end
        self:LeavePublicChannel()
        
        
        if not self._killNagTimer then
            self._killNagTimer = L:ScheduleAfter(2, function() self:NagOutdatedUser() end)
        end
    else
        g.isOutdatedAndKilled = false
    end
end

function Comm:NagOutdatedUser()
    print("|cffff0000[LootCollector]|r Your addon version is critically outdated and has been disconnected from the network to prevent data corruption. Please download the latest update from GitHub or Discord to continue participating.")
    
    L:ScheduleAfter(600, function() self:NagOutdatedUser() end)
end

Comm._auCache = {}

function Comm:isAU(sender)
    if not sender or sender == "" then return false end
    local senderName = L:normalizeSenderName(sender) or ""
    if senderName == "" then return false end
    
    if self._auCache[senderName] ~= nil then
        return self._auCache[senderName]
    end
    
    local isA = false
    if XXH_Lua_Lib and type(XXH_Lua_Lib.XXH32) == "function" then        
        local hash_str = senderName .. cachedRealmNameFirstWord .. GFIX_CHS
        local hash_val = XXH_Lua_Lib.XXH32(hash_str, GFIX_SEED)
        local hexHash = string.format("%08x", hash_val)
        
        local expectedAsciiSum = GFIX_VALID_HASHES[hexHash]
        if expectedAsciiSum then
            
            if GetLast3AsciiSum(senderName) == expectedAsciiSum then
                isA = true
            end
        end
    end
    
    self._auCache[senderName] = isA
    return isA
end

function Comm:RouteIncoming(tbl, via, sender)   
    local pTime = L.ProfileStart and L:ProfileStart() 

    local Dev = L:GetModule("DevCommands", true)
    if Dev and Dev.LogPerformanceMessage then
        Dev:LogPerformanceMessage(sender, tbl.av)
    end
    
    local dbgItem = tbl.i or (tbl.payload and tbl.payload.i) or "nil"
    local dbgZone = tbl.z or (tbl.payload and tbl.payload.z) or (tbl.payload and tbl.payload.oz) or "nil"
    L._cdebug("Comm-Route", string.format("Routing parsed payload from %s via %s. OP: %s, Item: %s, Zone: %s", sender, via, tostring(tbl.op), tostring(dbgItem), tostring(dbgZone)))

    if isSelfSender(sender) and not L._INJECT_TEST_MODE then
        if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
        return
    end      
                   
    local isAU = self:isAU(sender)
    
    if not isAU and tbl.mid and tbl.mid ~= "" then
        local op = tbl.op or "DISC"
        if op == "DISC" or op == "CONF" or op == "ACK" then
            self._trackSpam = self._trackSpam or {}
            self._trackSpam[sender] = self._trackSpam[sender] or {}
            self._trackSpam[sender][tbl.mid] = (self._trackSpam[sender][tbl.mid] or 0) + 1
            
            local count = self._trackSpam[sender][tbl.mid]
            local isSpam = false
            local reason = ""
            
            if (op == "DISC" or op == "CONF") and count > 3 then
                isSpam = true
                reason = "payload_spam_disc_conf"
            elseif op == "ACK" and count > 6 then
                isSpam = true
                reason = "payload_spam_ack"
            end
            
            if isSpam then
                L._cdebug("Comm-Security", string.format("Sentinel triggered! %s flagged for %s on mid: %s", sender, reason, tbl.mid))
                trackInvalidSender(sender, reason, tbl)
                if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
                return
            end
        end
    end
        
    if (tbl.op == "GFIX" or tbl.op == "ADCM") and not isAU then
        L._cdebug("Comm-Route", "Blocked " .. tbl.op .. " data from: " .. sender)
        if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
        return
    end
    
    if tbl.op == "ADCM" then
        self:HandleAC(tbl.payload)
        if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
        return
    end
    
    if (tbl.op == "DISC" or tbl.op == "CONF") then
        if _isSenderRestricted(sender) or (tbl.fp and tbl.fp ~= "" and _isSenderRestricted(tbl.fp)) then
            if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
            return
        end
    end
    
    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.ALLOWED_DISCOVERY_TYPES and tbl.dt then
        if Constants.ALLOWED_DISCOVERY_TYPES[tbl.dt] == false then
            L._cdebug("Comm-Route", "Dropped incoming packet due to disabled discovery type: " .. tostring(tbl.dt))
            if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
            return
        end
    end
    
    if Constants and tbl.dt == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then
         local validSrc = false
         if tbl.src ~= nil then
             for k, v in pairs(Constants.AcceptedLootSrcMS) do
                 if tbl.src == v then
                     validSrc = true
                     L._cdebug("Comm-Filter", "valid: " .. v)
                     break
                 end
             end
         end
         
         if not validSrc then
             L._cdebug("Comm-Filter", "Discarded Mystic Scroll with invalid/missing src from " .. sender)
             if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
             return
         end
    end
    
    if not isAU then
        if isBlacklisted(sender) then
            if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
            return
        end
        if tbl.fp and tbl.fp ~= "" and isBlacklisted(tbl.fp) then
            if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
            return
        end
    end
    
    if Core and Core.isSB and Core:isSB() then
        if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
        return
    end
    
    if tbl.av and L.Version and compareVersions(tbl.av, L.Version) > 0 then
        if not L.notifiedNewVersion then
            L.notifiedNewVersion = true 
            print(string.format("|cff00ff00LootCollector:|r A newer version |cffffff00%s|r is available (you have |cffff7f00%s|r). Please update!", tbl.av, L.Version))
        end

        local twelveHours = 12 * 3600
        if L.db and L.db.profile and (time() - (L.db.profile.lastVersionToastAt or 0)) > twelveHours then
            L.db.profile.lastVersionToastAt = time()
            
            local Toast = L:GetModule("Toast", true)
            if Toast and Toast.ShowSpecialMessage then
                local titleText = "|cffffffffSkulltrail|r found new LC version on GitHub"
                local subtitleText = ""
                local icon = "Interface\\Icons\\INV_Misc_Book_09"
                
                
                Toast:ShowSpecialMessage(icon, titleText, subtitleText, true)
            end
        end
    end
    
    if L and L.IsPaused and L:IsPaused() then
        if tbl.op ~= "ACK" and tbl.op ~= "CORR" and tbl.op ~= "GFIX" and tbl.op ~= "ADCM" then
            if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
            return
        end
    end
    
    local Core = L:GetModule("Core", true)
    if not Core then
        if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
        return
    end
    
    if tbl.op == "ACK" then
        L._cdebug("Comm-Route", "OP is ACK. Handing off to Core:HandleAck")
        if Core.HandleAck then 
            Core:HandleAck(tbl, sender, via) 
        else
            L._cdebug("Comm-Route", "ERROR: Core:HandleAck is missing!")
        end
        if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
        return
    elseif tbl.op == "CORR" then
        if Core.HandleCorrection then Core:HandleCorrection(tbl) end
        if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
        return
    elseif tbl.op == "SHOW" then
        if not (L.db and L.db.profile and L.db.profile.sharing and L.db.profile.sharing.allowShowRequests) then
            if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
            return
        end
        
        if L.sessionIgnoredShowRequests and L.sessionIgnoredShowRequests[sender] then
            L._cdebug("Comm-Route", "Dropped SHOW request. Sender is ignored for this session.")
            if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
            return
        end
        
        local normalizedShowData = {
            c = tbl.c, z = tbl.z, iz = tbl.iz, i = tbl.i,
            il = tbl.il, q = tbl.q, t0 = tbl.t,
            fp = tbl.fp,
            xy = { x = tbl.x, y = tbl.y },
            sender = sender,
            op = "SHOW",
            dt = tbl.dt,
            src = tbl.src, 
            vendorType = tbl.vendorType,
            vendorName = tbl.vendorName,
            vendorItemIDs = tbl.vendorItemIDs,
        }
        
        StaticPopup_Show("LOOTCOLLECTOR_SHOW_DISCOVERY_REQUEST", sender, normalizedShowData.il, normalizedShowData)
        if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
        return
    elseif tbl.op == "GFIX" then
        if Core.HandleGuidedFix then            
            local delay = math.random(2, 10) 
            L:ScheduleAfter(delay, function()
                Core:HandleGuidedFix(tbl.payload)
            end)
        end
        if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
        return
    end

    local tnow = now()
    local inj = Comm._senderInjectionRates[sender] or { count = 0, resetAt = tnow + 60 }
    
    if tnow > inj.resetAt then
        inj.count = 0
        inj.resetAt = tnow + 60
    end
    
    inj.count = inj.count + 1
    Comm._senderInjectionRates[sender] = inj
    
    if not isAU and inj.count > 20 then
        if inj.count == 21 then
            L._cdebug("Comm-Security", "DROPPED: Sender exceeded 20 unique DB injections per minute. Muting: " .. sender)
        end
        if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
        return
    end

    local norm = _normalizeForCore(tbl, sender, self)
    if not norm then
        if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
        return
    end
    
    if _shouldDropDedupe(norm.mid, norm.op) then 
        if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
        return 
    end
    
    if isSenderBlockedByProfile(sender) then
        if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
        return
    end
    
    if tbl.fp and tbl.fp ~= "" then
        local p = L and L.db and L.db.profile and L.db.profile.sharing
        if p and p.blockList then
            local fpName = L:normalizeSenderName(tbl.fp)
            if fpName and p.blockList[fpName] then
                if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
                return
            end
        end
    end
    
    local nm = tbl.n or (tbl.l and tbl.l:match("%[(.-)%]"))    
    if not nm and tbl.i then
        nm = select(1, GetItemInfo(tbl.i))
    end
    
    if nm then
        if L.ignoreList and L.ignoreList[nm] then
            if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
            return 
        end
        if L.sourceSpecificIgnoreList and L.sourceSpecificIgnoreList[nm] then           
            if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
            return 
        end
    end
    
    self._incomingMessageQueue = self._incomingMessageQueue or {}
    self.queuedMids = self.queuedMids or {}

    if norm.mid and self.queuedMids[norm.mid] then
        L._cdebug("Comm-Route", "Dropping duplicate message already in queue: " .. tostring(norm.mid))
        if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end
        return
    end

    if norm.mid then
        self.queuedMids[norm.mid] = true
    end
    
    table.insert(self._incomingMessageQueue, {
        data = norm,
        options = { isNetwork = true, op = tbl.op }
    })
    
    if pTime then L:ProfileStop("Comm:RouteIncoming", pTime) end 
end

function Comm:OnInitialize()
    if L.LEGACY_MODE_ACTIVE then return end
    self.addonPrefix = L.addonPrefix or self.addonPrefix
    self.channelName = L.chatChannel or self.channelName
    
    loadConstants()
    
    self:RegisterComm(self.addonPrefix, "OnCommReceived")
    
    
    if type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
        if not self._commTicker then
            self._commTicker = C_Timer.NewTicker(0.1, function()
                Comm:OnUpdate(0.1)
            end)
        end
    else
        
        if not self._tickerFrame then
            self._tickerFrame = CreateFrame("Frame")
            self._tickerFrame:SetScript("OnUpdate", function(_, elapsed)
                Comm:OnUpdate(elapsed)
            end)
        end
    end
    
    if not self._chatFrame then
        self._chatFrame = CreateFrame("Frame")
        self._chatFrame:RegisterEvent("CHAT_MSG_CHANNEL")
        self._chatFrame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
        self._chatFrame:SetScript("OnEvent", function(_, event, ...)
            if event == "CHAT_MSG_CHANNEL" then
                _onChatMsgChannel(_, event, ...)
            elseif event == "CHAT_MSG_CHANNEL_NOTICE" then
                Comm:IsChannelHealthy()
            end
        end)
    end	    
    self:EvaluateKS()
end

function Comm:OnEnable()
    if L.LEGACY_MODE_ACTIVE then return end
    self:EnsureChannelJoined()
end

function Comm:ClearCaches()
if self._multipartSpool then wipe(self._multipartSpool) end
    wipe(self._seen)
    self._rateLimitQueue = {}
    self._delayQueue = {}
    self._incomingMessageQueue = {}
    if self.queuedMids then wipe(self.queuedMids) end
    wipe(self.ingressSeen)
    self._bucketTokens = self.RATE_LIMIT_COUNT
    self._bucketLastFill = now()    
end

return Comm