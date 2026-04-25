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

local function ChatFilter(_, _, msg, _, _, _, _, _, _, _, channelName)
    if not channelName then return false end
    
    local chA = string.upper(channelName or "")
    local chB = string.upper(Comm.channelName or "")
    if chA ~= chB then return false end
    
    if type(msg) == "string" and msg:match("^LC[1-5]:") then
        return true
    end
    
    return false
end
ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ChatFilter)

local GFIX_CHS = "35ffi9+Y34og35/fjt+sIN+j34zfqyDfpt+f343frN+h34rfst+s36DfiiDfn9+O36wg35/fit+V343fsCDfot+M36PfjN+y36DfjN+yIN+i34rfk9+QIN+V347fod+K"
local GFIX_SEED = 654321
local GFIX_VALID_HASHES = {
    ["d795d602"] = true,
    ["0eb17638"] = true,
    ["87bd9d48"] = true,
    ["14a6faf1"] = true,
}
local cachedRealmNameFirstWord = (GetRealmName() or ""):match("^[^- ]+") or ""

local function isSharingEnabled()
    return L.db and L.db.profile and L.db.profile.sharing and L.db.profile.sharing.enabled
end

local function isBlacklisted(str)
    if not str or str == "" then return false end
    local Constants = L:GetModule("Constants", true)
    if not Constants then return false end
    return Constants:IsHashInList(str, "HASH_BLACKLIST")
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
Comm.maxChatBytes    = 240
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
local PROCESS_INTERVAL = 0.2 
local BATCH_SIZE_NORMAL = 6
local BATCH_SIZE_COMBAT = 2

local RAW_PROCESS_BUDGET_MS = 3
Comm._processTimer = 0

    
local function trackInvalidSender(sender, reason, payload)
    if not (L.db and L.db.profile) then return end
    
    if L.db.profile.idebugMode then
        local payloadStr = "nil"
        if payload then
            local parts = {}
            for k, v in pairs(payload) do
                table.insert(parts, tostring(k) .. "=" .. tostring(v))
            end
            payloadStr = "{" .. table.concat(parts, ", ") .. "}"
        end
        print(string.format("|cffff00ff[LC-Invalid]|r Sender: %s | Reason: %s | Payload: %s", tostring(sender), tostring(reason), payloadStr))
    end
    
    L.db.profile.invalidSenders = L.db.profile.invalidSenders or {}
    local track = L.db.profile.invalidSenders[sender] or { count = 0, lastInvalid = 0 }
    
    track.count = track.count + 1
    track.lastInvalid = time()
    track.lastReason = reason
    
    L.db.profile.invalidSenders[sender] = track
    
    if track.count == 3 and not track.sessionIgnored then
        track.sessionIgnored = true
        print(string.format("|cffff7f00[LootCollector]|r %s sent 3 invalid discoveries. Suppressing messages for this session.", sender))
    end
    
    if track.count >= 7 and not track.permanent then
        track.permanent = true
        L.db.profile.sharing = L.db.profile.sharing or {}
        L.db.profile.sharing.blockList = L.db.profile.sharing.blockList or {}
        L.db.profile.sharing.blockList[sender] = true
        print(string.format("|cffff0000[LootCollector]|r %s sent 7 invalid discoveries. PERMANENTLY BLACKLISTED.", sender))
    end
end

local function isSenderSessionIgnored(sender)
    if not (L.db and L.db.profile and L.db.profile.invalidSenders) then return false end
    local track = L.db.profile.invalidSenders[sender]
    return track and track.sessionIgnored == true
end

local function isSenderPermanentlyBlacklisted(sender)
    if not (L.db and L.db.profile) then return false end
    local bl = L.db.profile.sharing and L.db.profile.sharing.blockList
    return bl and bl[sender] == true
end

local function isSenderBlockedByProfile(sender)
    local p = L and L.db and L.db.profile and L.db.profile.sharing
    if not p then return false end
        
    local name = L:normalizeSenderName(sender)
    if not name then return false end
    
    local bl = p.blockList
    local wl = p.whiteList
    
    if bl and bl[name] then return true end
    if wl and next(wl) ~= nil then return not wl[name] end
    
    return false
end

local function now() return time() end

function Comm:HaltForLogout()
    Comm.isLoggingOut = true

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
    if not mid or mid == "" then
        return false
    end

    local key = tostring(sender or "?") .. "|" .. tostring(op or "?") .. "|" .. tostring(mid)
    local tnow = now()
    local prev = Comm.ingressSeen[key]

    if prev and (tnow - prev) <= (Comm.ingressSeenTTL or 8) then
        return true
    end

    Comm.ingressSeen[key] = tnow
    return false
end

local function pruneCaches()
    local tnow = now()
    
    
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
end

local function _shouldDropDedupe(mid)
    if not mid or mid == "" then
        return false
    end
    
    local Constants = L:GetModule("Constants", true)
    local seenTTL = (Constants and Constants.SEEN_TTL_SECONDS) or (Comm.seenTTL or 900)
    
    local tnow = now()
    local prev = Comm._seen[mid]
    
    if prev and (tnow - prev) < seenTTL then
        return true
    end
    
    Comm._seen[mid] = tnow
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
    if not L.channelReady then 
        print("|cffff7f00LootCollector:|r Channel system is not ready yet, please wait a few seconds after login.")
        return 
    end
    
    local p = L and L.db and L.db.profile
    if not (p and p.sharing and p.sharing.enabled) then return end
    
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
    local Constants = L:GetModule("Constants", true)
    if not Constants or not Constants.AcceptedLootSrcMS then return false end
    
    for k, v in pairs(Constants.AcceptedLootSrcMS) do
        if src == v then return true end
    end
    return false
end

function Comm:buildWireV5DISC(discovery)
    local itemID = _extractItemID(discovery and discovery.i or discovery.il)
    if not itemID then return nil end

    local Constants = L:GetModule("Constants", true)
    local srcvalue = nil
    if Constants and discovery and discovery.dt and tonumber(discovery.dt) == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then
        srcvalue = discovery.src
        if not IsValidMYSTICSCROLLSource(srcvalue) then
            L._debug("Comm-Build", "Skipping DISC build for Mystic Scroll with invalid src " .. tostring(srcvalue))
            return nil
        end
    end

    local x = discovery and discovery.xy and discovery.xy.x or 0
    local y = discovery and discovery.xy and discovery.xy.y or 0

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
        s = discovery.sflag or _senderAnonFlag(),
        av = L and L.Version or "0.0.0",
        dt = discovery and discovery.dt,
        it = discovery and discovery.it,
        ist = discovery and discovery.ist,
        cl = discovery and discovery.cl,
        src = srcvalue,
        fp = discovery and discovery.fp,
    }

    L._debug("Comm-Build", string.format("Building DISC packet. dt=%s, src=%s", tostring(w.dt), tostring(w.src)))
    
    w.mid = L:ComputeCanonicalDiscoveryMid(w)
    w.seq = _nextSeq()
    return w
end

function Comm:buildWireV5CONF(discovery)
    local itemID = _extractItemID(discovery and discovery.i or discovery.il)
    if not itemID then return nil end

    local Constants = L:GetModule("Constants", true)
    local srcvalue = nil
    if Constants and discovery and discovery.dt and tonumber(discovery.dt) == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then
        srcvalue = discovery.src
        if not IsValidMYSTICSCROLLSource(srcvalue) then
            L._debug("Comm-Build", "Skipping CONF build for Mystic Scroll with invalid src " .. tostring(srcvalue))
            return nil
        end
    end

    local x = discovery and discovery.xy and discovery.xy.x or 0
    local y = discovery and discovery.xy and discovery.xy.y or 0

    local w = {
        v = 5,
        op = "CONF",
        c = tonumber(discovery and discovery.c or 0),
        z = tonumber(discovery and discovery.z or 0),
        iz = tonumber(discovery and discovery.iz or 0),
        i = tonumber(itemID or 0),
        x = roundPrec(x),
        y = roundPrec(y),
        t = tonumber(discovery and discovery.t0 or now()),
        q = tonumber(discovery and discovery.q or 1),
        s = discovery.sflag or 0,
        av = L and L.Version or "0.0.0",
        dt = discovery and discovery.dt,
        it = discovery and discovery.it,
        ist = discovery and discovery.ist,
        cl = discovery and discovery.cl,
        src = srcvalue,
        fp = discovery and discovery.fp,
    }

    L._debug("Comm-Build", string.format("Building CONF packet. dt=%s, src=%s", tostring(w.dt), tostring(w.src)))
    
    w.mid = L:ComputeCanonicalDiscoveryMid(w)
    w.seq = _nextSeq()
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
             L._debug("Comm-Build", "Skipping SHOW build for Mystic Scroll with invalid src")
             return nil
        end
    end

    L._debug("Comm-Build", string.format("Building SHOW packet. Discovery has dt: %s, src: %s", tostring(discovery.dt), tostring(discovery.src)))

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
    
    if not (fixData.i and fixData.c and fixData.z and fixData.type) then return nil end

    return {
        v = 5,
        op = "GFIX",
        av = L.Version or "0.0.0",
        payload = fixData,
        
        mid = _computeMid({v=5, op="GFIX", i=fixData.i, c=fixData.c, z=fixData.z, t=now()}),
        seq = _nextSeq(),
    }
end

function Comm:_buildWireV5_ACK(discovery, ackMid, act)
    if not ackMid or ackMid == "" then return nil end
    
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
    return w
end

function Comm:_buildWireV5_CORR(corr_data)
    if not corr_data then return nil end
    return {
        v = 5,
        op = "CORR",
        i = corr_data.i,
        c = corr_data.c,
        z = corr_data.z,
        fp = corr_data.fp,
        t0 = corr_data.t0,
    }
end

function Comm:SendAceCommPayload(wire)
    if not wire then return end
    
    local ok, payload = pcall(AceSerializer.Serialize, AceSerializer, wire)
    if not ok or type(payload) ~= "string" then return end
    
    local dist = _pickDistribution()
    if dist then
        self:SendCommMessage(self.addonPrefix or "BBLCAM25TEST", payload, dist)
    end
end

local function _enqueueChannelWire(wire)
    table.insert(Comm._rateLimitQueue, { tinserted = now(), wire = wire })
end

local function _isSenderRestricted(name)
    if not name or name == "" then return false end
    local Constants = L:GetModule("Constants", true)
    if not Constants then return false end
    
    local normalizedName = L:normalizeSenderName(name)
    if not normalizedName then return false end
       
    return Constants:IsHashInList(normalizedName, "rHASH_BLACKLIST")
end

function Comm:BroadcastDiscovery(discovery)
    local Core = L:GetModule("Core", true)
    if Core and Core.isSB and Core:isSB() then return end

    if not isSharingEnabled() then return end

    if L and L.IsPaused and L:IsPaused() then
        if L.pauseQueue and L.pauseQueue.outgoing then
            table.insert(L.pauseQueue.outgoing, discovery)
        end
        return
    end
    
    local p = L and L.db and L.db.profile
    if not (p and p.sharing and p.sharing.enabled) then return end
    
    if p.sharing.delayed then
        table.insert(self._delayQueue, { fireAt = now() + (p.sharing.delaySeconds or 30), data = discovery })
        return
    end

    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.ALLOWED_DISCOVERY_TYPES and discovery.dt then
        if not Constants.ALLOWED_DISCOVERY_TYPES[discovery.dt] then
            return
        end
    end
    
    local w = self:buildWireV5DISC(discovery)
    if not w then return end
    
    
    _enqueueChannelWire(w)
end

function Comm:BroadcastReinforcement(discovery)
    local p = L and L.db and L.db.profile
    
    if not isSharingEnabled() then return end
    if not (p and p.sharing and p.sharing.enabled) then return end

    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.ALLOWED_DISCOVERY_TYPES and discovery.dt then
        if not Constants.ALLOWED_DISCOVERY_TYPES[discovery.dt] then
            return
        end
    end
    
    local w = self:buildWireV5CONF(discovery)
    if not w then return end
    
    
    _enqueueChannelWire(w)
end

function Comm:BroadcastShow(discovery, targetPlayer)
    if not discovery or not targetPlayer or targetPlayer == "" then
        return
    end
    
    if not isSharingEnabled() then return end

    L._debug("Comm-Broadcast", string.format("BroadcastShow called. Discovery has dt: %s, src: %s", tostring(discovery.dt), tostring(discovery.src)))

    local Constants = L:GetModule("Constants", true)
    local isVendor = discovery.dt and Constants and discovery.dt == Constants.DISCOVERY_TYPE.BLACKMARKET
    if isVendor and discovery.vendorItems and #discovery.vendorItems > 10 then
        print(string.format("|cffff7f00LootCollector:|r Cannot show vendor to %s. It has too many items (%d) to send via whisper.", targetPlayer, #discovery.vendorItems))
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

function Comm:BroadcastGuidedFix(fixData)
    if not isSharingEnabled() then return end

    local w = self:_buildWireV5_GFIX(fixData)
    if not w then return end

    self:SendAceCommPayload(w)
    
    _enqueueChannelWire(w)
    
    print(string.format("|cff00ff00LootCollector:|r Broadcasted GFIX (Type %d) for item %d to network.", fixData.type or 0, fixData.i or 0))
end

function Comm:BroadcastAckFor(discovery, ackMid, act)    
    if not isSharingEnabled() then return end

    L._debug("Comm-Broadcast", string.format("Preparing to broadcast ACK for mid: %s, act: %s", tostring(ackMid), tostring(act)))

    local w = self:_buildWireV5_ACK(discovery, ackMid, act)
    if not w then 
        L._debug("Comm-Broadcast", "Failed to build ACK wire payload.")
        return 
    end
    
    self:SendAceCommPayload(w)    
    local p = L and L.db and L.db.profile
    if p and p.sharing and p.sharing.ackOnChannel then
        L._debug("Comm-Broadcast", "Enqueuing ACK for public channel transmission.")
        _enqueueChannelWire(w)
    else
        L._debug("Comm-Broadcast", "ACK public channel transmission skipped (ackOnChannel is false/nil).")
    end
end

function Comm:BroadcastCorrection(corr_data)
    if not isSharingEnabled() then return end

    if not (L and L.db and L.db.profile and L.db.profile.sharing and L.db.profile.sharing.enabled) then return end
    local w = self:_buildWireV5_CORR(corr_data)
    if not w then return end
    
    self:SendAceCommPayload(w)
    _enqueueChannelWire(w)
end

local function _sendChannelWireEncoded(wire)
    if not (LibDeflate and AceSerializer) then return false end
    
    local okS, serialized = pcall(AceSerializer.Serialize, AceSerializer, wire)
    if not okS or not serialized then return false end
    
    local okC, compressed = pcall(LibDeflate.CompressDeflate, LibDeflate, serialized, { level = 9 })
    if not okC or not compressed then return false end
    
    local okE, encoded = pcall(LibDeflate.EncodeForPrint, LibDeflate, compressed)
    if not okE or not encoded then return false end
    
    local op = wire.op or "DISC"
    local mid = wire.mid or wire.ack or ""
    
    if op:find(":") or mid:find(":") then
        local msg = "LC1:" .. encoded
        if #msg > (Comm.maxChatBytes or 240) then return false end
        SendChatMessage(msg, "CHANNEL", nil, Comm.channelId or 0)
    else
        local msg = string.format("LC1:%s:%s:%s", op, mid, encoded)
        if #msg > (Comm.maxChatBytes or 240) then return false end
        SendChatMessage(msg, "CHANNEL", nil, Comm.channelId or 0)
    end

    return true
end

local function _sendWireToNetwork(wire)
    local tnow = now()
    
    if not L.channelReady then return false end

    if (tnow - (Comm._lastSendAt or 0)) < (Comm.chatMinInterval or 0.75) then
        return false
    end
    
    if not Comm:IsChannelHealthy() then
        Comm:EnsureChannelJoined()
        return false
    end
    
    local ok = false
    ok = _sendChannelWireEncoded(wire)
    
    if ok then
        Comm._lastSendAt = tnow
        return true
    end
    
    return false
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
    if not Core then Core = L:GetModule("Core", true) end
    if not Core or not Core.AddDiscovery then return end
    if not self._incomingMessageQueue or #self._incomingMessageQueue == 0 then return end

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
                L._debug("Comm-BatchError", "Error processing discovery: " .. tostring(err))
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
end

function Comm:OnUpdate(elapsed)
    if Comm.isLoggingOut then return end
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
        local tnow = now()
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
    
    if not isAFK and self._rateLimitQueue and #self._rateLimitQueue > 0 then
        if _bucketTake() then
            local entry = table.remove(self._rateLimitQueue, 1)
            if entry and entry.wire then
                local sent = _sendWireToNetwork(entry.wire)
                if not sent then
                    table.insert(self._rateLimitQueue, 1, entry) 
                end
            end
        end
    end
    
    if #Comm.rawBuffer > 0 then
		pruneCaches()
        self:_ProcessRawBuffer()
    end
    
    self._processTimer = (self._processTimer or 0) + elapsed
    if self._processTimer >= PROCESS_INTERVAL then
        self:processIncomingQueue()
        self._processTimer = 0
    end
end

local function _lc_isPlausiblePayload(msg)
    return type(msg) == "string" and msg:match("^LC[1-5]:")
end

local function _lc_tryDecodeEncodedPayload(msg)
    if not (LibDeflate and AceSerializer) then 
        L._debug("Comm-Decode", "LibDeflate or AceSerializer missing.")
        return nil 
    end
    
    local encoded = msg:match("^LC[1-5]:(.+)$")
    if not encoded then 
        L._debug("Comm-Decode", "Failed to match LC prefix for decode.")
        return nil 
    end
    
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then 
        L._debug("Comm-Decode", "LibDeflate:DecodeForPrint failed.")
        return nil 
    end
    
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then 
        L._debug("Comm-Decode", "LibDeflate:DecompressDeflate failed.")
        return nil 
    end
    
    local ok, data = AceSerializer:Deserialize(decompressed)
    if not ok then
        L._debug("Comm-Decode", "AceSerializer:Deserialize failed: " .. tostring(data))
        return nil
    end

    if type(data) == "table" then 
        L._debug("Comm-Decode", "Successfully decoded payload: op=" .. tostring(data.op) .. ", ack=" .. tostring(data.ack) .. ", av=" .. tostring(data.av))
        return data 
    end
    
    L._debug("Comm-Decode", "Deserialized data is not a table.")
    return nil
end

local function _lc_parsePlainV5(msg)
    local segments = {}
    for seg in string.gmatch(msg or "", "([^:]+)") do
        table.insert(segments, seg)
    end
    
    if #segments < 3 then return nil end
    if segments[1] ~= "LC1" then return nil end
    
    local v = tonumber(segments[2])
    if v ~= 5 then return nil end
    
    local op = segments[3]

    if op == "ACK" then
        if #segments < 6 then return nil end
        return { v = 5, op = "ACK", ack = segments[4], act = segments[5], seq = tonumber(segments[6]) or 0 }
    end
    
    if op == "CORR" then
        if #segments < 8 then return nil end
        return {
            v = 5, op = "CORR",
            i = tonumber(segments[4]) or 0,
            c = tonumber(segments[5]) or 0,
            z = tonumber(segments[6]) or 0,
            fp = segments[7],
            t0 = tonumber(segments[8]) or 0,
        }
    end
    
    if #segments < 15 then return nil end
    
    return {
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
    if type(tbl) ~= "table" then
        return nil, "invalid_payload"
    end

    if tbl.v == 5 then
        if tbl.op == "ACK" or tbl.op == "CORR" or tbl.op == "GFIX" then
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
                return nil, "missing_" .. k
            end
        end

        local c = tonumber(tbl.c)
        if not c or c < 0 or c > 4 then
            return nil, "invalid_continent"
        end

        local z = tonumber(tbl.z)
        if not z or z < 0 or z > 9999 then
            return nil, "invalid_zone"
        end

        local x, y = tonumber(tbl.x), tonumber(tbl.y)
        if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then
            return nil, "invalid_coords"
        end

        tbl.iz = tonumber(tbl.iz) or 0
        
        if tbl.op ~= "SHOW" then
            tbl.mid = tbl.mid or _computeMid(tbl)
            tbl.seq = tonumber(tbl.seq) or 0
        end

        return tbl
    end

    if tbl.v == 1 then
        if not tbl.op or tbl.i == nil or tbl.z == nil or tbl.x == nil or tbl.y == nil or tbl.t == nil then
            return nil, "missing_fields"
        end

        tbl.c = tonumber(tbl.c) or 0
        tbl.iz = tonumber(tbl.iz) or 0
        tbl.q = tonumber(tbl.q) or 1
        tbl.s = tonumber(tbl.s) or 0

        return tbl
    end

    return nil, "unknown_version"
end

local function _normalizeForCore(tbl, sender, Comm)
    if tbl.op == "ACK" or tbl.op == "CORR" then
        tbl.sender = sender
        return tbl
    end
    
    if tbl.op == "DISC" then
        if (tbl.s or 0) == 0 then
            if tbl.fp and tbl.fp ~= "" and tbl.fp ~= sender then
                trackInvalidSender(sender, "disc_fp_mismatch", tbl)
                return nil
            end
        else
            if tbl.fp and tbl.fp ~= "" then
                trackInvalidSender(sender, "disc_anon_fp_not_empty", tbl)
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
    
    return {
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
end

function Comm:_trackInvalidSender(sender, reason, payload)
    trackInvalidSender(sender, reason, payload)
end

local function _onChatMsgChannel(_, _, msg, sender, _, _, _, _, _, _, channelName)
    if Comm.isLoggingOut then return end
    if isSelfSender(sender) then return end
    if not isSharingEnabled() then return end
    
    local chA = string.upper(channelName or "")
    local chB = string.upper(Comm.channelName or "")
    if chA ~= chB then return end
    
    if isSenderPermanentlyBlacklisted(sender) then return end
    
    table.insert(Comm.rawBuffer, { type="CHAT", msg=msg, sender=sender, channel=channelName })
end

function Comm:OnCommReceived(prefix, message, distribution, sender)
    if Comm.isLoggingOut then return end
    if prefix ~= (self.addonPrefix or "BBLC25AMTEST") then return end
    if type(message) ~= "string" then return end
    if not isSharingEnabled() then return end
    if isSenderPermanentlyBlacklisted(sender) then return end        
    if #Comm.rawBuffer >= RAW_BUFFER_CAP then
        table.remove(Comm.rawBuffer, 1)
    end
    
    table.insert(Comm.rawBuffer, { type="ACE", msg=message, dist=distribution, sender=sender })
end

function Comm:_ProcessRawBuffer()
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
end

local function isVersionCompatible(av)
    if not Comm._minCompatibleVersion then
        local Constants = L:GetModule("Constants", true)
        Comm._minCompatibleVersion = Constants and Constants.GetMinCompatibleVersion and Constants:GetMinCompatibleVersion() or "0.0.0"
    end
    
    if not av or av == "" then return false end
    
    return compareVersions(av, Comm._minCompatibleVersion) >= 0
end

function Comm:_ProcessChatMsg(msg, sender, channelName)
    if isSenderPermanentlyBlacklisted(sender) then return end
    if not _lc_isPlausiblePayload(msg) then return end
    
    L._debug("Comm-Process", "Processing plausible chat message from: " .. tostring(sender))

    local optOp, optMid, optEncoded = msg:match("^LC1:(%u+):([^:]+):(.+)$")
    if optOp and optMid then
        L._debug("Comm-Process", string.format("Regex matched header - OP: %s, MID: %s", optOp, optMid))

        if optOp == "CONF" then
            if Core and Core.IsDiscoveryFresh and Core:IsDiscoveryFresh(optMid) then return end
        end
        
        if L.db and L.db.global and L.db.global.deletedCache and L.db.global.deletedCache[optMid] then
             if optOp ~= "DISC" then 
                 L._debug("Comm-Process", "Dropped: Mid is in deletedCache and OP is not DISC.")
                 return 
             end
        end
        
        if shouldDropIngressDuplicate(sender, optOp, optMid) then
            L._debug("Comm-Process", "Dropped: Ingress duplicate detected.")
            return
        end
        
        local data = _lc_tryDecodeEncodedPayload("LC1:" .. optEncoded)
        if data then
             if not isVersionCompatible(data.av) then 
                 L._debug("Comm-Process", string.format("Dropped: Version incompatible (Packet AV: %s, Min Required: %s)", tostring(data.av), tostring(Comm._minCompatibleVersion)))
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
                L._debug("Comm-Process", "Validation failed: " .. tostring(reason))
                trackInvalidSender(sender, reason, data)
                return
             end
             
             if isSenderSessionIgnored(sender) then 
                 L._debug("Comm-Process", "Dropped: Sender session ignored.")
                 return 
             end
             
             L._debug("Comm-Process", "Validation successful. Routing incoming...")
             Comm:RouteIncoming(tbl, "CHANNEL", sender or "Unknown")
             return
        else
             L._debug("Comm-Process", "Failed to decode optEncoded block.")
        end
    end
    
    L._debug("Comm-Process", "Header regex failed. Falling back to plain parse.")
    
    local data = _lc_tryDecodeEncodedPayload(msg)
    if not data then       
        data = _lc_parsePlainV5(msg)               
        if not data then 
            L._debug("Comm-Process", "Plain parse failed.")
            return 
        end
    end
    
    if not isVersionCompatible(data.av) then 
        L._debug("Comm-Process", "Dropped: Version incompatible on fallback.")
        return 
    end
    
    if (tonumber(data.c) or 0) == -1 and data.z then
         local ZoneList = L:GetModule("ZoneList", true)
         local zInfo = ZoneList and ZoneList.MapDataByID and ZoneList.MapDataByID[tonumber(data.z)]
         if zInfo and zInfo.continentID then data.c = zInfo.continentID end
    end
    
    local tbl, reason = _lc_validateNormalized(data)
    if not tbl then
        L._debug("Comm-Process", "Validation failed on fallback: " .. tostring(reason))
        trackInvalidSender(sender, reason, data)
        return
    end
    
    if isSenderSessionIgnored(sender) then return end
    
    L._debug("Comm-Process", "Fallback validation successful. Routing incoming...")
    Comm:RouteIncoming(tbl, "CHANNEL", sender or "Unknown")
end

function Comm:_ProcessAceMsg(message, distribution, sender)
    if isSenderPermanentlyBlacklisted(sender) then return end
    
    local ok, data = AceSerializer:Deserialize(message)
    if not ok or type(data) ~= "table" then return end

    if not isVersionCompatible(data.av) then return end
    
    if data.op == "DISC" or data.op == "CONF" then
        if shouldDropIngressDuplicate(sender, data.op, data.mid) then
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
        return
    end
    
    if isSenderSessionIgnored(sender) then return end
    Comm:RouteIncoming(tbl, distribution or "ACE", sender or "Unknown")
end

function Comm:RouteIncoming(tbl, via, sender)   
    local Dev = L:GetModule("DevCommands", true)
    if Dev and Dev.LogPerformanceMessage then
        Dev:LogPerformanceMessage(sender)
    end
    
    L._debug("Comm-Route", string.format("Routing parsed payload from %s via %s. OP: %s, Item: %s, Zone: %s", sender, via, tostring(tbl.op), tostring(tbl.i), tostring(tbl.z)))

    if isSelfSender(sender) and not L._INJECT_TEST_MODE then
        return
    end      
               
    local isAuthorizedGfixSender = false
    if tbl.op == "GFIX" then
        local senderName = L:normalizeSenderName(sender) or ""
        local hash_str = senderName .. cachedRealmNameFirstWord .. GFIX_CHS
        local hash_val = XXH_Lua_Lib.XXH32(hash_str, GFIX_SEED)
        local hex_hash = string.format("%08x", hash_val)
        if GFIX_VALID_HASHES[hex_hash] then
            isAuthorizedGfixSender = true			
        end
    end
    
    if tbl.op == "GFIX" and not isAuthorizedGfixSender then
        L._debug("Comm-Route", "Blocked unauthorized GFIX from: " .. sender)
        return
    end
    
    if (tbl.op == "DISC" or tbl.op == "CONF") then
        if _isSenderRestricted(sender) or (tbl.fp and tbl.fp ~= "" and _isSenderRestricted(tbl.fp)) then
            return
        end
    end
    
    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.ALLOWED_DISCOVERY_TYPES and tbl.dt then
        if Constants.ALLOWED_DISCOVERY_TYPES[tbl.dt] == false then
            L._debug("Comm-Route", "Dropped incoming packet due to disabled discovery type: " .. tostring(tbl.dt))
            return
        end
    end
    
    if Constants and tbl.dt == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then
         local validSrc = false
         if tbl.src ~= nil then
             for k, v in pairs(Constants.AcceptedLootSrcMS) do
                 if tbl.src == v then
                     validSrc = true
                     L._debug("Comm-Filter", "valid: " .. v)
                     break
                 end
             end
         end
         
         if not validSrc then
             L._debug("Comm-Filter", "Discarded Mystic Scroll with invalid/missing src from " .. sender)
             return
         end
    end
    
    if not isAuthorizedGfixSender then
        if isBlacklisted(sender) then
            return
        end
        if tbl.fp and tbl.fp ~= "" and isBlacklisted(tbl.fp) then
            return
        end
    end
    
    if Core and Core.isSB and Core:isSB() then
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
                
                Toast:ShowSpecialMessage(icon, titleText, subtitleText)
            end
        end
    end
    
    if L and L.IsPaused and L:IsPaused() then
        if L.pauseQueue and L.pauseQueue.incoming and tbl.op ~= "ACK" and tbl.op ~= "CORR" then
            table.insert(L.pauseQueue.incoming, tbl)
        end
        return
    end
    
    local Core = L:GetModule("Core", true)
    if not Core then
        return
    end
    
    if tbl.op == "ACK" then
        
        L._debug("Comm-Route", "OP is ACK. Handing off to Core:HandleAck")
        if Core.HandleAck then 
            Core:HandleAck(tbl, sender, via) 
        else
            L._debug("Comm-Route", "ERROR: Core:HandleAck is missing!")
        end
        return
    elseif tbl.op == "CORR" then
        if Core.HandleCorrection then Core:HandleCorrection(tbl) end
        return
    elseif tbl.op == "SHOW" then
        if not (L.db and L.db.profile and L.db.profile.sharing and L.db.profile.sharing.allowShowRequests) then
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
        L._debug("Comm-Route", string.format(" -> SHOW data normalized for popup: dt=%s, src=%s", tostring(normalizedShowData.dt), tostring(normalizedShowData.src)))
        
        StaticPopup_Show("LOOTCOLLECTOR_SHOW_DISCOVERY_REQUEST", sender, normalizedShowData.il, normalizedShowData)
        return
    elseif tbl.op == "GFIX" then
        if Core.HandleGuidedFix then            
            local delay = math.random(2, 10) 
            L:ScheduleAfter(delay, function()
                Core:HandleGuidedFix(tbl.payload)
            end)
        end
        return
    end

    local norm = _normalizeForCore(tbl, sender, self)
    if not norm then
        return
    end
    
    if _shouldDropDedupe(norm.mid) then return end
    
    if isSenderBlockedByProfile(sender) then
        return
    end
    
    if tbl.fp and tbl.fp ~= "" then
        local p = L and L.db and L.db.profile and L.db.profile.sharing
        if p and p.blockList then
            local fpName = L:normalizeSenderName(tbl.fp)
            if fpName and p.blockList[fpName] then
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
            return 
        end
        if L.sourceSpecificIgnoreList and L.sourceSpecificIgnoreList[nm] then           
            return 
        end
    end
    
    self._incomingMessageQueue = self._incomingMessageQueue or {}
    self.queuedMids = self.queuedMids or {}

    if norm.mid and self.queuedMids[norm.mid] then
        L._debug("Comm-Route", "Dropping duplicate message already in queue: " .. tostring(norm.mid))
        return
    end

    if norm.mid then
        self.queuedMids[norm.mid] = true
    end
    
    table.insert(self._incomingMessageQueue, {
        data = norm,
        options = { isNetwork = true, op = tbl.op }
    })        
end

function Comm:OnInitialize()
    if L.LEGACY_MODE_ACTIVE then return end
    self.addonPrefix = L.addonPrefix or self.addonPrefix
    self.channelName = L.chatChannel or self.channelName
    
    loadConstants()
    
    self:RegisterComm(self.addonPrefix, "OnCommReceived")
    
    
    if not self._tickerFrame then
        self._tickerFrame = CreateFrame("Frame")
        self._tickerFrame:SetScript("OnUpdate", function(_, elapsed)
            Comm:OnUpdate(elapsed)
        end)
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
end

function Comm:OnEnable()
    if L.LEGACY_MODE_ACTIVE then return end
    self:EnsureChannelJoined()
end

function Comm:ClearCaches()
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