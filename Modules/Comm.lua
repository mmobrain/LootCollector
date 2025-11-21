

local L = LootCollector
local Comm = L:NewModule("Comm", "AceComm-3.0")
local Core = L:GetModule("Core", true)

local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate", true)
local XXH_Lua_Lib = _G.XXH_Lua_Lib

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

local function _getconst(fn, default)
    local f = rawget(_G, fn)
    if type(f) == "function" then
        local ok, v = pcall(f)
        if ok and v ~= nil then return v end
    end
    return default
end

Comm.chatMinInterval = _getconst("ConstantsGetChatMinInterval", 3.50)
Comm.maxChatBytes = _getconst("ConstantsGetMaxChatBytes", 240)
Comm.seenTTL = _getconst("ConstantsGetSeenTtl", 900)
Comm.coordPrec = _getconst("ConstantsGetCoordPrecision", 4)
Comm.RATE_LIMIT_COUNT = _getconst("ConstantsGetRateLimitCount", 9)
Comm.RATE_LIMIT_WINDOW = _getconst("ConstantsGetRateLimitWindow", 60)

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
local PROCESS_INTERVAL = 0.2 
local BATCH_SIZE = 5       
Comm._processTimer = 0

local function _debug(mod, msg) return end
    

local function trackInvalidSender(sender, reason)
    if not (L.db and L.db.profile) then return end
    
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
    if type(linkOrId) == "number" then return linkOrId end
    if type(linkOrId) == "string" then
        local id = linkOrId:match("item:(%d+)")
        if id then return tonumber(id) end
    end
    return nil
end

local function _shouldDropDedupe(mid)
    
    if not mid or mid == "" then
        
        return false
    end
    
    
    local Constants = L:GetModule("Constants", true)
    local seenTTL = (Constants and Constants.SEEN_TTL_SECONDS) or (Comm.seenTTL or 1800)
    
    local tnow = now()
    local prev = Comm._seen[mid]
    
    if prev and (tnow - prev) < seenTTL then
        
        return true
    end
    
    Comm._seen[mid] = tnow
    
    return false
end

local function _fnv1a32(s)
    local hash = 2166136261
    for i = 1, #s do
        hash = bit.bxor(hash, string.byte(s, i))
        hash = (hash * 16777619) % 4294967296
    end
    return hash
end

local function _hex32(u)
    local n = tonumber(u) or 0
    local hi = math.floor(n / 65536)
    local lo = n % 65536
    return string.format("%04x%04x", hi, lo)
end

local function _identityString(tbl)
    return table.concat({
        tostring(tbl.v or 5),
        tostring(tbl.op or "DISC"),
        tostring(tbl.c or 0),
        tostring(tbl.z or 0),
        tostring(tbl.iz or 0),
        tostring(tbl.i or 0),
        string.format("%.6f", tonumber(tbl.x) or 0),
        string.format("%.6f", tonumber(tbl.y) or 0),
        tostring(tbl.t or 0),
    }, "|")
end

local function _computeMid(tbl)
    local s = _identityString(tbl)
    return _hex32(_fnv1a32(s))
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

function Comm:EnsureChannelJoined()
    if not L.channelReady then 
        print("|cffff7f00LootCollector:|r Channel system is not ready yet, please wait a few seconds after login.")
        return 
    end
    local p = L and L.db and L.db.profile
    if not (p and p.sharing and p.sharing.enabled) then return end
    if self:IsChannelHealthy() then return end
    
    local ch = self.channelName or "BBLCC25TEST"
    JoinPermanentChannel(ch)
    if DEFAULT_CHAT_FRAME then
        ChatFrame_AddChannel(DEFAULT_CHAT_FRAME, ch)
    end
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

function Comm:_buildWireV5_DISC(discovery)
    local itemID = _extractItemID(discovery and (discovery.i or discovery.il))
    if not itemID then return nil end
    
    local x = discovery and discovery.xy and discovery.xy.x or 0
    local y = discovery and discovery.xy and discovery.xy.y or 0
    
    local Constants = L:GetModule("Constants", true)
    local src_value = nil
    if Constants and discovery and discovery.dt and tonumber(discovery.dt) == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then
        src_value = discovery.src
    end
    
    local w = {
        v = 5,
        op = "DISC",
        c = tonumber(discovery and discovery.c) or 0,
        z = tonumber(discovery and discovery.z) or 0,
        iz = tonumber(discovery and discovery.iz) or 0,
        i = tonumber(itemID) or 0,
        x = roundPrec(x),
        y = roundPrec(y),
        t = tonumber(discovery and discovery.t0) or now(),
        q = tonumber(discovery and discovery.q) or 1,
        s = discovery.s or _senderAnonFlag(),
        av = L and L.Version or "0.0.0",
        dt = discovery and discovery.dt,
        it = discovery and discovery.it,
        ist = discovery and discovery.ist,
        cl = discovery and discovery.cl,
        src = src_value, 
        fp = discovery.fp,
    }

    L._debug("Comm-Build", string.format("Building DISC packet. dt=%s, src=%s", tostring(w.dt), tostring(w.src)))
    
    w.mid = _computeMid(w)
    w.seq = _nextSeq()
    return w
end

function Comm:_buildWireV5_CONF(discovery)
    local itemID = _extractItemID(discovery and (discovery.i or discovery.il))
    if not itemID then return nil end
    
    local x = discovery and discovery.xy and discovery.xy.x or 0
    local y = discovery and discovery.xy and discovery.xy.y or 0
    
    local Constants = L:GetModule("Constants", true)
    local src_value = nil
    if Constants and discovery and discovery.dt and tonumber(discovery.dt) == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then
        src_value = discovery.src
    end
    
    local w = {
        v = 5,
        op = "CONF",
        c = tonumber(discovery and discovery.c) or 0,
        z = tonumber(discovery and discovery.z) or 0,
        iz = tonumber(discovery and discovery.iz) or 0,
        i = tonumber(itemID) or 0,
        x = roundPrec(x),
        y = roundPrec(y),
        t = tonumber(discovery and discovery.t0) or now(),
        q = tonumber(discovery and discovery.q) or 1,
        s = discovery.s or 0,
        av = L and L.Version or "0.0.0",
        dt = discovery and discovery.dt,
        it = discovery and discovery.it,
        ist = discovery and discovery.ist,
        cl = discovery and discovery.cl,
        src = src_value, 
        fp = discovery.fp,
    }

    L._debug("Comm-Build", string.format("Building CONF packet. dt=%s, src=%s", tostring(w.dt), tostring(w.src)))
    
    w.mid = _computeMid(w)
    w.seq = _nextSeq()
    return w
end

function Comm:_buildWireV5_SHOW(discovery)
    local itemID = _extractItemID(discovery and (discovery.i or discovery.il))
    if not itemID then return nil end

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
    
    local Constants = L:GetModule("Constants", true)
    local src_value = nil
    if Constants and discovery and discovery.dt and tonumber(discovery.dt) == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then
        src_value = discovery.src
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

    L._debug("Comm-Build", string.format(" -> SHOW payload prepared with dt=%s, src=%s", tostring(payload.dt), tostring(payload.src)))

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
    
    local w = self:_buildWireV5_DISC(discovery)
    if not w then return end
    
    self:SendAceCommPayload(w)
    _enqueueChannelWire(w)
end

function Comm:BroadcastReinforcement(discovery)

   
    
    local p = L and L.db and L.db.profile
    if not (p and p.sharing and p.sharing.enabled) then return end

    
    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.ALLOWED_DISCOVERY_TYPES and discovery.dt then
        if not Constants.ALLOWED_DISCOVERY_TYPES[discovery.dt] then
            
            return
        end
    end
    
    local w = self:_buildWireV5_CONF(discovery)
    if not w then return end
    
    self:SendAceCommPayload(w)
    _enqueueChannelWire(w)
end

function Comm:BroadcastShow(discovery, targetPlayer)
    if not discovery or not targetPlayer or targetPlayer == "" then
        return
    end

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
    local w = self:_buildWireV5_GFIX(fixData)
    if not w then return end

    
    self:SendAceCommPayload(w)
    
    
    
    _enqueueChannelWire(w)
    
    print(string.format("|cff00ff00LootCollector:|r Broadcasted GFIX (Type %d) for item %d to network.", fixData.type or 0, fixData.i or 0))
end

function Comm:BroadcastAckFor(discovery, ackMid, act)

    local w = self:_buildWireV5_ACK(discovery, ackMid, act)
    if not w then return end
    
    self:SendAceCommPayload(w)
    
    local p = L and L.db and L.db.profile
    if p and p.sharing and p.sharing.ackOnChannel then
        _enqueueChannelWire(w)
    end
end

function Comm:BroadcastCorrection(corr_data)

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
    local mid = wire.mid or ""
    
    
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

local function _fmtOrNil(v)
    return (v ~= nil and v ~= "") and tostring(v) or ""
end

local function _sendChannelWirePlain(wire)
    local parts
    
    if wire.op == "ACK" then
        parts = {
            "LC1", tostring(wire.v or 5), "ACK",
            _fmtOrNil(wire.ack), _fmtOrNil(wire.act), _fmtOrNil(wire.seq),
        }
    elseif wire.op == "CORR" then
        parts = {
            "LC1", tostring(wire.v or 5), "CORR",
            tostring(wire.i or 0),
            tostring(wire.c or 0),
            tostring(wire.z or 0),
            _fmtOrNil(wire.fp or ""),
            tostring(wire.t0 or 0),
        }
    else 
        parts = {
            "LC1",
            tostring(wire.v or 5),
            tostring(wire.op or "DISC"),
            tostring(wire.c or 0),
            tostring(wire.z or 0),
            tostring(wire.iz or 0),
            tostring(wire.i or 0),
            string.format("%.6f", tonumber(wire.x) or 0),
            string.format("%.6f", tonumber(wire.y) or 0),
            tostring(wire.t or 0),
            tostring(wire.q or 1),
            tostring(wire.s or 0),
            _fmtOrNil(wire.av or ""),
            _fmtOrNil(wire.mid or ""),
            _fmtOrNil(wire.seq or ""),
            _fmtOrNil(wire.dt),
            _fmtOrNil(wire.it),
            _fmtOrNil(wire.ist),
            _fmtOrNil(wire.cl),
            _fmtOrNil(wire.fp),
        }
    end
    
    local msg = table.concat(parts, ":")
    if #msg > (Comm.maxChatBytes or 240) then return false end
    
    SendChatMessage(msg, "CHANNEL", nil, Comm.channelId or 0)
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

function Comm:_processIncomingQueue()
    
    if not Core then Core = L:GetModule("Core", true) end
    if not Core or not Core.AddDiscovery then return end
    if not self._incomingMessageQueue or #self._incomingMessageQueue == 0 then return end

    local processedCount = 0
    
    while processedCount < BATCH_SIZE and #self._incomingMessageQueue > 0 do
        local entry = table.remove(self._incomingMessageQueue, 1)
        if entry and entry.data and entry.options then
            
            Core:AddDiscovery(entry.data, entry.options)
            processedCount = processedCount + 1
        end
    end
end

function Comm:OnUpdate(elapsed)
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
    
    if not self._rateLimitQueue or #self._rateLimitQueue == 0 then
        
    else
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
    
    
    self._processTimer = (self._processTimer or 0) + elapsed
    if self._processTimer >= PROCESS_INTERVAL then
        self:_processIncomingQueue()
        self._processTimer = 0
    end
end

local function _lc_isPlausiblePayload(msg)
    return type(msg) == "string" and msg:match("^LC[1-5]:")
end

local function _lc_tryDecodeEncodedPayload(msg)
    if not (LibDeflate and AceSerializer) then return nil end
    
    local encoded = msg:match("^LC[1-5]:(.+)$")
    if not encoded then return nil end
    
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then return nil end
    
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return nil end
    
    local ok, data = AceSerializer:Deserialize(decompressed)
    if ok and type(data) == "table" then return data end
    
    return nil
end

local function _lc_parsePlainV1(msg)
    local header, payload = string.match(msg, "^(LC1:%d+:[^:]+:[^:]+:[^:]+:[^:]+:[^:]+:[^:]+:%d+):(.*)$")
    if not header then return nil end
    
    local v, op, z, i, x, y, t, q = string.match(header, "^LC1:(%d+):([^:]+):(%d+):(%d+):([%-%d%.]+):([%-%d%.]+):(%d+):(%d+)$")
    if not v then return nil end
    
    local parts = {}
    for part in string.gmatch(payload or "", "[^\t]+") do
        table.insert(parts, part)
    end
    
    local sSender = parts[1]
    local itemName = parts[2]
    local zoneName = parts[3]
    local av = parts[4]
    
    local tbl = {
        v = tonumber(v) or 1,
        op = op or "DISC",
        c = 0,
        z = tonumber(z) or 0,
        iz = 0,
        i = tonumber(i) or 0,
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
        t = tonumber(t) or now(),
        q = tonumber(q) or 1,
        s = 0,
        av = av,
        l = itemName,
        sn = sSender,
        zn = zoneName,
    }
    
    return tbl
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
    }
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
            if tbl.fp ~= sender then
                
                trackInvalidSender(sender, "disc_fp_mismatch")
                return nil
            end
        else
            if tbl.fp ~= "" then
                
                trackInvalidSender(sender, "disc_anon_fp_not_empty")
                return nil
            end
        end
    end

    local itemID = tonumber(tbl.i) or _extractItemID(tbl.l)
    
    local historicalFp = tbl.fp
    if tbl.op == "DISC" then
        historicalFp = (tbl.s == 1 and "An Unnamed Collector" or sender)
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

function Comm:_trackInvalidSender(sender, reason)
    trackInvalidSender(sender, reason)
end

local function _onChatMsgChannel(_, _, msg, sender, _, _, _, _, _, _, channelName)
    if sender == UnitName("player") then
        return
    end
    
    local chA = string.upper(channelName or "")
    local chB = string.upper(Comm.channelName or "")
    if chA ~= chB then return end
	
    L._debug("Comm-Chat", string.format("Event CHAT_MSG_CHANNEL from %s on channel %s.", sender, channelName))
    

    if isSenderPermanentlyBlacklisted(sender) then
        return
    end
    
    if not _lc_isPlausiblePayload(msg) then
        return
    end
    
    
    
    local optOp, optMid, optEncoded = msg:match("^LC1:(%u+):([^:]+):(.+)$")
    
    if optOp and optMid then
        
        
        
        if optOp == "CONF" then
            if Core and Core.IsDiscoveryFresh and Core:IsDiscoveryFresh(optMid) then
                L._debug("Comm-Opt", "Skipping redundant CONF for fresh MID: " .. tostring(optMid))
                return 
            end
        end
        
        
        
        if L.db and L.db.global and L.db.global.deletedCache and L.db.global.deletedCache[optMid] then
             
             if optOp ~= "DISC" then
                 L._debug("Comm-Opt", "Skipping message for deleted MID: " .. tostring(optMid))
                 return
             end
        end
        
        
        
        
        local data = _lc_tryDecodeEncodedPayload("LC1:" .. optEncoded)
        if data then
            
             local tbl, reason = _lc_validateNormalized(data)
            if not tbl then
                trackInvalidSender(sender, reason)
                return
            end
             if isSenderSessionIgnored(sender) then return end
             Comm:RouteIncoming(tbl, "CHANNEL", sender or "Unknown")
             return
        end
    end
    
    
    L._debug("Comm-Parse", "Attempting to parse legacy/standard payload...")
    
    local data = _lc_tryDecodeEncodedPayload(msg)
    if data then
        L._debug("Comm-Parse", "SUCCESS: Decoded as standard encoded payload.")
    else
        L._debug("Comm-Parse", "INFO: Encoded parse failed, trying plain text formats.")
        data = _lc_parsePlainV5(msg)
        if data then
            L._debug("Comm-Parse", "SUCCESS: Parsed as plain V5 payload.")
        else
            data = _lc_parsePlainV1(msg)
            if data then
                L._debug("Comm-Parse", "SUCCESS: Parsed as legacy plain V1 payload.")
            else
                L._debug("Comm-Parse", "FAIL: No valid format detected. Dropping message.")
                return
            end
        end
    end

    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.GetMinCompatibleVersion then
        local minVersion = Constants:GetMinCompatibleVersion()
        if not data.av or compareVersions(data.av, minVersion) < 0 then
            
            return 
        end
    end
    
    local tbl, reason = _lc_validateNormalized(data)
    if not tbl then
        trackInvalidSender(sender, reason)
        return
    end
    
    if isSenderSessionIgnored(sender) then
        return
    end
    
    Comm:RouteIncoming(tbl, "CHANNEL", sender or "Unknown")
end

function Comm:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= (self.addonPrefix or "BBLC25AMTEST") then return end
    if type(message) ~= "string" then return end
    
    L._debug("Comm-Ace", string.format("OnCommReceived from: %s via %s | Msg Length: %d", tostring(sender), tostring(distribution), #message))
    
    if isSenderPermanentlyBlacklisted(sender) then
        L._debug("Comm-Filter", "REJECT: Permanently blacklisted sender: " .. sender)
        return
    end
    
    L._debug("Comm-Parse", "Attempting to deserialize AceComm payload...")
    local ok, data = AceSerializer:Deserialize(message)
    if not ok or type(data) ~= "table" then
        L._debug("Comm-Parse", "FAIL: AceSerializer failed to deserialize payload. Dropping.")
        return
    end
    L._debug("Comm-Parse", "SUCCESS: Deserialized AceComm payload.")

    local Constants = L:GetModule("Constants", true)
    if Constants and Constants.GetMinCompatibleVersion then
        local minVersion = Constants:GetMinCompatibleVersion()
        if not data.av or compareVersions(data.av, minVersion) < 0 then
            L._debug("Comm-Filter", "REJECT: Incompatible version from " .. sender .. ". Received " .. tostring(data.av) .. ", requires " .. minVersion)
            return 
        end
    end
    
    local tbl, reason = _lc_validateNormalized(data)
    if not tbl then
        L._debug("Comm-Filter", "FAIL: Deserialized data failed validation. Reason: " .. reason)
        trackInvalidSender(sender, reason)
        return
    end
    
    if isSenderSessionIgnored(sender) then
        L._debug("Comm-Filter", "SUPPRESS: Suppressing valid message from session-ignored sender: " .. sender)
        return
    end
    
    Comm:RouteIncoming(tbl, distribution or "ACE", sender or "Unknown")
end

function Comm:RouteIncoming(tbl, via, sender)   
	local Dev = L:GetModule("DevCommands", true)
    if Dev and Dev.LogPerformanceMessage then
        Dev:LogPerformanceMessage(sender)
    end
	
	L._debug("Comm-Route", string.format("Routing parsed payload from %s via %s. OP: %s, Item: %s, Zone: %s", sender, via, tostring(tbl.op), tostring(tbl.i), tostring(tbl.z)))

    if sender == UnitName("player") and not L._INJECT_TEST_MODE then
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
        if Core.HandleAck then Core:HandleAck(tbl, sender, via) end
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
    
    
    if self._incomingMessageQueue and #self._incomingMessageQueue > 0 then
        for _, queued in ipairs(self._incomingMessageQueue) do
            
            if queued.data then
                if norm.mid and queued.data.mid and norm.mid == queued.data.mid then
                    L._debug("Comm-Route", "Dropping duplicate message already in queue: " .. tostring(norm.mid))
                    return
                end
            end
        end
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
    self._bucketTokens = self.RATE_LIMIT_COUNT
    self._bucketLastFill = now()
end

return Comm