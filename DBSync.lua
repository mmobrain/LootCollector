local L = LootCollector
local DBSync = L:NewModule("DBSync", "AceComm-3.0", "AceSerializer-3.0")

local LibDeflate = LibStub("LibDeflate", true)
local AceSerializer = LibStub("AceSerializer-3.0")

local PREFIX = "LCDB1"
local MAX_MSG = 240
local SHARE_COOLDOWN = 60

local STATUS = {
    UNCONFIRMED = 0,
    CONFIRMED   = 1,
    FADING      = 2,
    STALE       = 3,
}

local STATUS_REV = {
    [0] = "UNCONFIRMED",
    [1] = "CONFIRMED",
    [2] = "FADING",
    [3] = "STALE",
}

local OFFSETS = { 0, 3600, 18000, 86400, 172800, 432000, 604800 }
local MAX_STEPS = 7

local importCounters = {}
local importTimers = {}
local summaryTicker = nil

local lastShareTime = 0
local announcedSenders = {}

local function debugPrint(message)
    local Comm = L:GetModule("Comm", true)
    if Comm and Comm.verbose then
        print(string.format("|cffffff00[DBSync DEBUG]|r %s", tostring(message)))
    end
end

local function tableToString(tbl, indent)
    indent = indent or 0; local str = string.rep("  ", indent) .. "{\n"; for k, v in pairs(tbl) do str = str .. string.rep("  ", indent + 1) .. "[" .. tostring(k) .. "] = "; if type(v) == "table" then str = str .. tableToString(v, indent + 1) else str = str .. tostring(v) end; str = str .. ",\n" end; str = str .. string.rep("  ", indent) .. "}"; return str
end

local function SerializePayload(payload)
    if not LibDeflate then debugPrint("|cffff7f00SerializePayload Error: LibDeflate is not available!|r"); return nil end; local ok, serialized = pcall(AceSerializer.Serialize, AceSerializer, payload); if not ok or not serialized then debugPrint("|cffff7f00SerializePayload Error: AceSerializer failed.|r"); return nil end; local compressed = LibDeflate:CompressDeflate(serialized, {level = 9}); local encoded = LibDeflate:EncodeForPrint(compressed); return encoded
end

local function DeserializePayload(message)
    if not LibDeflate then debugPrint("|cffff7f00DeserializePayload Error: LibDeflate is not available!|r"); return nil end; local ok, payload = pcall(function() local decoded = LibDeflate:DecodeForPrint(message); local decompressed = LibDeflate:DecompressDeflate(decoded); local success, data = AceSerializer:Deserialize(decompressed); if success then return data end end); if ok and type(payload) == "table" then return true, payload end; return false, nil
end

local function scaleCoord(v)
    if not v or v ~= v then return 0 end; local x = v * 1000; if x >= 0 then return math.floor(x + 0.5) else return -math.floor(-x + 0.5) end
end

local function getItemID(d)
    if d.itemID and type(d.itemID) == "number" then return d.itemID end; if d.itemLink and type(d.itemLink) == "string" then local id = d.itemLink:match("item:(%d+)"); if id then id = tonumber(id); d.itemID = id; return id end end; return nil
end

local function guidParts(d)
    local z = d.zoneID or d.zone or 0; local id = getItemID(d) or 0; local x = scaleCoord(d.coords and d.coords.x or 0); local y = scaleCoord(d.coords and d.coords.y or 0); return z, id, x, y
end

local function buildGuid(z, id, x3, y3)
    return tostring(z) .. "-" .. tostring(id) .. "-" .. tostring(x3) .. "-" .. tostring(y3)
end

local function getStatusTs(d)
    return tonumber(d.statusTs) or tonumber(d.lastConfirmed) or tonumber(d.lastSeen) or tonumber(d.timestamp) or time()
end

local function getLastSeen(d)
    return tonumber(d.lastSeen) or tonumber(d.timestamp) or time()
end

local function packRecord(d, nameCache)
    local z, i, x3, y3 = guidParts(d); local s  = STATUS[(d.status or "UNCONFIRMED"):upper()] or STATUS.UNCONFIRMED; local st = getStatusTs(d); local ls = getLastSeen(d); local ac = d.announceCount or 0; local originator = d.originator or "Unknown"; local foundBy = d.foundBy_player or originator; nameCache.map[originator] = (nameCache.map[originator] or #nameCache.list + 1); if nameCache.map[originator] > #nameCache.list then table.insert(nameCache.list, originator) end; nameCache.map[foundBy] = (nameCache.map[foundBy] or #nameCache.list + 1); if nameCache.map[foundBy] > #nameCache.list then table.insert(nameCache.list, foundBy) end; local oIdx = nameCache.map[originator]; local fIdx = nameCache.map[foundBy]; return { z or 0, i or 0, x3 or 0, y3 or 0, s or 0, st or 0, ls or 0, ac or 0, oIdx, fIdx }
end

local function unpackRecord(rec)
    local z  = tonumber(rec[1]) or 0; local i  = tonumber(rec[2]) or 0; local x3 = tonumber(rec[3]) or 0; local y3 = tonumber(rec[4]) or 0; local s  = tonumber(rec[5]) or 0; local st = tonumber(rec[6]) or 0; local ls = tonumber(rec[7]) or 0; local ac = tonumber(rec[8]) or 0; local oIdx = tonumber(rec[9]) or 1; local fIdx = tonumber(rec[10]) or oIdx; return z, i, x3, y3, s, st, ls, ac, oIdx, fIdx
end

function DBSync:ApplyRecord(z, i, x3, y3, s, st, ls, ac, originator, foundBy)
    if not (L.db and L.db.global and L.db.global.discoveries) then return end; local guid = buildGuid(z, i, x3, y3); local existing = L.db.global.discoveries[guid]; local now = time(); local _, itemLink = GetItemInfo(i); if not existing then local newRecord = { guid = guid, zoneID = z, itemID = i, itemLink = itemLink, coords = { x = x3 / 1000, y = y3 / 1000 }, status = STATUS_REV[s] or "UNCONFIRMED", statusTs = st, lastSeen = ls, timestamp = ls, announceCount = ac, originator = originator, foundBy_player = foundBy, }; local nextIdx = math.min((ac or 0) + 1, MAX_STEPS); if nextIdx <= MAX_STEPS then newRecord.nextDueTs = now + (OFFSETS[nextIdx] or 3600) end; L.db.global.discoveries[guid] = newRecord; return end; if not existing.itemLink and itemLink then existing.itemLink = itemLink end; local localSt = getStatusTs(existing); if st > localSt then existing.status = STATUS_REV[s] or "UNCONFIRMED"; existing.statusTs = st; existing.announceCount = ac; existing.originator = originator; existing.foundBy_player = foundBy; local nextIdx = math.min((ac or 0) + 1, MAX_STEPS); if nextIdx <= MAX_STEPS then existing.nextDueTs = now + (OFFSETS[nextIdx] or 3600) end end; if ls > (existing.lastSeen or 0) then existing.lastSeen = ls end; if not existing.itemID or existing.itemID == 0 then existing.itemID = i end
end

function DBSync:SendPacket(distribution, target, seq, records, nameCache)
    if not records or #records == 0 then return 0 end; local payload = { t = "D", q = seq, r = records, n = nameCache }; local msg = SerializePayload(payload); if not msg then debugPrint("|cffff7f00Serialization failed for a batch. Not sending.|r See debug console for payload."); local Dev = L:GetModule("DevCommands", true); if Dev and Dev.LogMessage then Dev:LogMessage("SERIALIZE_FAIL", "The following payload failed to serialize:\n" .. tableToString(payload)) end; return 0 end; debugPrint(string.format("SENDING packet. Seq: %d, Records: %d, Names: %d, Size: %d bytes, Dist: %s", seq, #records, #nameCache, #msg, distribution)); if #msg > MAX_MSG then debugPrint(string.format("|cffff7f00PACKET TOO LARGE! Size: %d bytes. Aborting send.|r", #msg)); return -1 end; self:SendCommMessage(PREFIX, msg, distribution, target, "NORMAL"); return #records
end

local function recordsIterator()
    return next, (L.db and L.db.global and L.db.global.discoveries) or {}, nil
end

function DBSync:Share(scope, target)
 
    local now = GetTime()
    if now - lastShareTime < SHARE_COOLDOWN then
        print(string.format("|cffff7f00LootCollector:|r /lcshare is on cooldown. Please wait %d more seconds.", math.ceil(SHARE_COOLDOWN - (now - lastShareTime))))
        return
    end

    scope = scope and scope:upper() or "PARTY"; if scope == "WHISPER" and (not target or target == "") then print("|cffff7f00LootCollector:|r /lcshare whisper <PlayerName> required for whisper."); return end; local distribution = (scope == "PARTY" or scope == "RAID" or scope == "GUILD" or scope == "WHISPER") and scope or "PARTY"; local seq = 1; local batch = {}; local totalSent = 0; local nameCache = { list = {"Unknown"}, map = {["Unknown"]=1} }; for guid, d in recordsIterator() do if type(d) == "table" then local z, i, x3, y3 = guidParts(d); if i and i ~= 0 and (x3 ~= 0 or y3 ~= 0) then local tempBatch = {}; for i=1, #batch do tempBatch[i] = batch[i] end; local tempNameCache = { list = {}, map = {} }; for k,v in pairs(nameCache.list) do tempNameCache.list[k] = v end; for k,v in pairs(nameCache.map) do tempNameCache.map[k] = v end; local newRec = packRecord(d, tempNameCache); table.insert(tempBatch, newRec); local testPayload = { t = "D", q = seq, r = tempBatch, n = tempNameCache.list }; local testMsg = SerializePayload(testPayload); if testMsg and #testMsg <= MAX_MSG then batch = tempBatch; nameCache = tempNameCache else local sent = self:SendPacket(distribution, target, seq, batch, nameCache.list); if sent > 0 then totalSent = totalSent + sent; seq = seq + 1 end; nameCache = { list = {"Unknown"}, map = {["Unknown"]=1} }; local finalNewRec = packRecord(d, nameCache); batch = { finalNewRec } end end else debugPrint(string.format("|cffff7f00Corrupt record in database, skipping. GUID: %s|r", tostring(guid))) end end; if #batch > 0 then local sent = self:SendPacket(distribution, target, seq, batch, nameCache.list); if sent > 0 then totalSent = totalSent + sent end end;
    
    -- If we actually sent something, start the cooldown
    if totalSent > 0 then
        lastShareTime = now
        print(string.format("|cff00ff00LootCollector:|r Shared %d records via %s%s.", totalSent, distribution, distribution == "WHISPER" and (" to " .. target) or ""))
    else
        print("|cffffff00LootCollector:|r No records to share.")
    end
end

local function OnSummaryUpdate()
    local now = GetTime(); local hasActiveTimers = false; for sender, expiration in pairs(importTimers) do if expiration then hasActiveTimers = true; if now > expiration then local total = importCounters[sender]; if total and total > 0 then print(string.format("|cff00ff00LootCollector:|r Finished importing %d records from %s.", total, sender)) end; importCounters[sender] = nil; importTimers[sender] = nil end end end; if not hasActiveTimers then summaryTicker:Hide() end
end

function DBSync:OnCommReceived(prefix, message, distribution, sender)
    debugPrint("OnCommReceived fired. Prefix: " .. tostring(prefix) .. ", Sender: " .. tostring(sender)); if prefix ~= PREFIX then return end; if sender == UnitName("player") then return end; local ok, payload = DeserializePayload(message); debugPrint("Deserialize result: ok=" .. tostring(ok) .. ", payload type=" .. type(payload)); if not ok or type(payload) ~= "table" then debugPrint("|cffff7f00Deserialize failed or payload is not a table. Aborting."); return end; if payload.t ~= "D" then return end; local p = L.db.profile.sharing; if (distribution == "PARTY" and p.rejectPartySync) or (distribution == "RAID" and p.rejectPartySync) or (distribution == "GUILD" and p.rejectGuildSync) or (distribution == "WHISPER" and p.rejectWhisperSync) then debugPrint("Rejecting incoming DBSync from " .. distribution .. " channel as per user settings."); return end; debugPrint("Payload type check: t=" .. tostring(payload.t) .. ", r is a table: " .. tostring(type(payload.r) == "table") .. ", n is a table: " .. tostring(type(payload.n) == "table")); if payload.r == nil or type(payload.r) ~= "table" or payload.n == nil or type(payload.n) ~= "table" then debugPrint("|cffff7f00Payload structure is invalid. Aborting."); return end;
    
    -- Show "Receiving..." message on first packet
    if not announcedSenders[sender] then
        print(string.format("|cff00ff00LootCollector:|r Receiving database from %s...", sender))
        announcedSenders[sender] = true
    end

    local nameCache = payload.n; local recordCount = #payload.r; debugPrint("Payload is valid. Processing " .. tostring(recordCount) .. " records with " .. #nameCache .. " names."); local processedCount = 0; for _, rec in ipairs(payload.r) do if type(rec) == "table" then local z, i, x3, y3, s, st, ls, ac, oIdx, fIdx = unpackRecord(rec); if i ~= 0 and (x3 ~= 0 or y3 ~= 0) then local originatorName = nameCache[oIdx] or "Unknown"; local foundByName = nameCache[fIdx] or originatorName; self:ApplyRecord(z, i, x3, y3, s, st, ls, ac, originatorName, foundByName); processedCount = processedCount + 1 end end end; debugPrint("|cff00ff00Successfully processed " .. processedCount .. " of " .. recordCount .. " records.");
    
    if processedCount > 0 then if not importCounters[sender] then importCounters[sender] = 0 end; importCounters[sender] = importCounters[sender] + processedCount; importTimers[sender] = GetTime() + 5; if summaryTicker and not summaryTicker:IsShown() then summaryTicker:Show() end end

    local Map = L:GetModule("Map", true); if Map and Map.Update then Map:Update() end
end

SLASH_LootCollectorSHARE1 = "/lcshare"; SlashCmdList["LootCollectorSHARE"] = function(msg) wipe(announcedSenders); msg = msg or ""; local scope, target = msg:match("^%s*(%S+)%s*(.*)$"); scope = scope or "PARTY"; target = target or ""; DBSync:Share(scope, target) end
function DBSync:OnInitialize()
    debugPrint("Registering comms for prefix: " .. tostring(PREFIX)); self:RegisterComm(PREFIX, "OnCommReceived"); if not summaryTicker then summaryTicker = CreateFrame("Frame"); summaryTicker:SetScript("OnUpdate", OnSummaryUpdate); summaryTicker:Hide() end
end

return DBSync