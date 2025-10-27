-- Modules/DBSync.lua
-- UNK.B64.UTF-8


local L = LootCollector
local DBSync = L:NewModule("DBSync", "AceComm-3.0")

local PREFIX         = "LCDB1"
local MAXMSG         = 240            
local SHARECOOLDOWN  = 60

DBSync.PREFIX        = PREFIX
DBSync.MAXMSG        = MAXMSG
DBSync.SHARECOOLDOWN = SHARECOOLDOWN

local STATUS     = { UNCONFIRMED = 0, CONFIRMED = 1, FADING = 2, STALE = 3 }
local STATUS_REV = { [0] = "UNCONFIRMED", [1] = "CONFIRMED", [2] = "FADING", [3] = "STALE" }

DBSync.incomingBySid = DBSync.incomingBySid or {}
local MAXBUFFEREDRECORDS   = 50000
local PROCESS_BATCH_SIZE   = 10

local importCounters = {}
local importTimers   = {}
local summaryTicker  = nil

local lastShareTime  = 0

local function pushToConsole(msg)
    if L and type(L.DC) == "function" then pcall(L.DC, L, msg) end
    local Console = (L and L.GetModule) and (L:GetModule("DevConsole", true) or L:GetModule("Console", true) or L:GetModule("Dev", true)) or nil
    if Console then
        if type(Console.AddLine) == "function" then pcall(Console.AddLine, Console, msg) end
        if type(Console.Print)   == "function" then pcall(Console.Print,   Console, msg) end
        if type(Console.Log)     == "function" then pcall(Console.Log,     Console, msg) end
    end
end


local function dprint(msg) return end
    

local function normalizeSenderName(sender)
    if type(sender) ~= "string" then return nil end
    local name = sender:match("^[^-]+") or sender
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return (name ~= "" and name) or nil
end

local function isSenderBlockedByProfile(sender, distribution)
    local p = L and L.db and L.db.profile and L.db.profile.sharing
    if not p then return false end
    if (distribution == "PARTY" and p.rejectPartySync) or
       (distribution == "RAID"  and p.rejectPartySync) or
       (distribution == "GUILD" and p.rejectGuildSync) or
       (distribution == "WHISPER" and p.rejectWhisperSync) then
        return true
    end
    local name = normalizeSenderName(sender)
    if not name then return false end
    local bl = p.blockList
    local wl = p.whiteList
    if bl and bl[name] then return true end
    if wl and next(wl) ~= nil then return not wl[name] end
    return false
end

local function round4k(v)
    v = tonumber(v) or 0
    return math.floor(v * 10000 + 0.5)
end

local function guidParts(d)
    local c = tonumber(d and d.c) or 0
    local z = tonumber(d and d.z) or 0
    local i = tonumber(d and d.i) or 0
    local x = d and d.xy and d.xy.x or 0
    local y = d and d.xy and d.xy.y or 0
    return c, z, i, round4k(x), round4k(y)
end

local function extractItemNameFromLink(link)
    if type(link) ~= "string" then return nil end
    return link:match("%[(.-)%]")
end

local function esc(s)
    s = s or ""
    s = tostring(s)
    s = s:gsub("[:%c]", "?")
    return s
end

local function newNameCache()
    return { list = { "Unknown" }, map = { ["Unknown"] = 1 } }
end

local function nameIndex(cache, s)
    if not s or s == "" then return 1 end
    s = esc(normalizeSenderName(s) or s)
    local idx = cache.map[s]
    if not idx then
        idx = #cache.list + 1
        cache.list[idx] = s
        cache.map[s] = idx
    end
    return idx
end

local function findWinnerFromVotes(votes, default_fp, default_t0)
    if not votes or not next(votes) then
        return default_fp, default_t0
    end

    local winner_fp = default_fp
    local max_score = -1
    local min_t0 = 9999999999

    for name, data in pairs(votes) do
        if data.score > max_score then
            max_score = data.score
            min_t0 = data.t0
            winner_fp = name
        elseif data.score == max_score then
            if data.t0 < min_t0 then
                min_t0 = data.t0
                winner_fp = name
            end
        end
    end
    return winner_fp, min_t0
end

local function packRecord(d, cache)
    local c, z, i, x4, y4 = guidParts(d)
    
    local winning_fp, winning_t0 = findWinnerFromVotes(d.fp_votes, d.fp, d.t0)
    
    local sfield = d and d.s
    local sNum = type(sfield) == "number" and sfield or STATUS[tostring(sfield or "")] or 0
    
    local fp_t0 = winning_t0 or 0
    local fIdx = nameIndex(cache, winning_fp)
    
    local q    = tonumber(d and d.q) or 0
    local dt   = tonumber(d and d.dt) or 0
    local it   = tonumber(d and d.it) or 0
    local ist  = tonumber(d and d.ist) or 0
    local cl   = (d and d.cl) or nil
    local clIdx = nameIndex(cache, cl)
    local itemName = (d and d.il and extractItemNameFromLink(d.il)) or (d and d.itemName) or nil
    local itemNameIdx = nameIndex(cache, itemName)
    
    local packed = { c, z, i, x4, y4, sNum, fp_t0, fIdx, q, dt, it, ist, clIdx, itemNameIdx }

    
    if d.vendorItems and type(d.vendorItems) == "table" and #d.vendorItems > 0 then
        for _, itemData in ipairs(d.vendorItems) do
            if itemData.itemID then
                table.insert(packed, itemData.itemID)
            end
        end
    end
    
    return packed
end

local function encodeDataWire(sid, q, recs, nlist)
    local parts = {}
    parts[#parts+1] = "D"
    parts[#parts+1] = sid
    parts[#parts+1] = tostring(q)
    local nc = #nlist
    parts[#parts+1] = tostring(nc)
    for i = 1, nc do parts[#parts+1] = nlist[i] end
    local rc = #recs
    parts[#parts+1] = tostring(rc)
    for r = 1, rc do
        local t = recs[r]
        parts[#parts+1] = #t 
        for k = 1, #t do
            parts[#parts+1] = tostring(t[k] or 0)
        end
    end
    return table.concat(parts, ":")
end

local function parseWire(line)
    if type(line) ~= "string" then return nil end
    local typ = line:match("^([SDE]):")
    if typ == "S" then
        local sid, tot = line:match("^S:([^:]+):(%d+)$")
        if sid and tot then return { t = "S", sid = sid, total = tonumber(tot) or 0 } end
        return nil
    elseif typ == "E" then
        local sid, pk = line:match("^E:([^:]+):(%d+)$")
        if sid and pk then return { t = "E", sid = sid, packets = tonumber(pk) or 0 } end
        return nil
    elseif typ == "D" then
        local _, sid, q, rest = line:match("^(D):([^:]+):(%d+):(.+)$")
        if not (sid and q and rest) then return nil end
        local pos = 1
        local function nextField(s)
            local a, b, v = s:find("([^:]+)", pos)
            if not v then return nil end
            pos = (b or pos) + 2
            return v
        end
        local nc = tonumber(rest:match("^(%d+):"))
        if not nc then return nil end
        pos = #tostring(nc) + 2
        local nlist = {}
        for i = 1, nc do
            local v = nextField(rest); if not v then return nil end
            nlist[i] = v
        end
        local rcStr = nextField(rest); if not rcStr then return nil end
        local rc = tonumber(rcStr) or 0
        local recs = {}
        for r = 1, rc do
            local numFieldsStr = nextField(rest); if not numFieldsStr then return nil end 
            local numFields = tonumber(numFieldsStr) or 0
            if numFields < 14 then return nil end 
            local t = {}
            for k = 1, numFields do
                local v = nextField(rest); if not v then return nil end
                t[k] = tonumber(v)
            end
            recs[#recs+1] = t
        end
        return { t = "D", sid = sid, q = tonumber(q) or 0, r = recs, n = nlist }
    end
    return nil
end

function DBSync:SendWire(distribution, target, wire)
    if not wire or #wire > (DBSync.MAXMSG or MAXMSG) then
        
        return 0
    end
    
    if distribution == "WHISPER" then
        self:SendCommMessage(PREFIX, wire, "WHISPER", target)
    else
        self:SendCommMessage(PREFIX, wire, distribution)
    end
    return 1
end

function DBSync:ApplyRecord(c, z, i, x4, y4, s, fp_t0, foundBy, q, dt, it, ist, cl, itemName, sender, extraFields)
    if not (L and L.db and L.db.global and L.db.global.discoveries) then return end
    local Core = L:GetModule("Core", true)
    local Constants = L:GetModule("Constants", true)
    if not Core or not Constants then return end

    local x = L:Round4((tonumber(x4) or 0) / 10000)
    local y = L:Round4((tonumber(y4) or 0) / 10000)

    
    local target_db, guid
    if dt == Constants.DISCOVERY_TYPE.BLACKMARKET then
        target_db = L.db.global.blackmarketVendors
        if i >= -399999 and i <= -300000 then 
            guid = "BM-" .. c .. "-" .. z .. "-" .. string.format("%.2f", L:Round2(x)) .. "-" .. string.format("%.2f", L:Round2(y))
        elseif i >= -499999 and i <= -400000 then 
            guid = "MS-" .. c .. "-" .. z .. "-" .. string.format("%.2f", L:Round2(x)) .. "-" .. string.format("%.2f", L:Round2(y))
        else 
            guid = "BM-" .. c .. "-" .. z .. "-" .. string.format("%.2f", L:Round2(x)) .. "-" .. string.format("%.2f", L:Round2(y))
        end
    else
        target_db = L.db.global.discoveries
        guid = L:GenerateGUID(c, z, i, x, y)
    end

    local now = time()
    local existing = target_db[guid]
    local sName = type(s) == "number" and (STATUS_REV[s] or "UNCONFIRMED") or (s or "UNCONFIRMED")

    local il = nil
    local isCached = Core.IsItemCached and Core:IsItemCached(i)
    if isCached then
        local _, _link = GetItemInfo(i)
        il = _link
    elseif itemName and q and i then
        local r, g, b = GetItemQualityColor(q)
        local hex = string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
        il = string.format("|c%s|Hitem:%d:0:0:0:0:0:0:0:0|h[%s]|h|r", hex, i, itemName)
    end

    
    local vendorItems = nil
    if dt == Constants.DISCOVERY_TYPE.BLACKMARKET and extraFields and #extraFields > 0 then
        vendorItems = {}
        for _, itemID in ipairs(extraFields) do
            local name, link = GetItemInfo(itemID)
            if name and link then
                table.insert(vendorItems, { itemID = itemID, name = name, link = link })
            end
        end
    end

    if not existing then
        local vendorType
        if dt == Constants.DISCOVERY_TYPE.BLACKMARKET then
            if i >= -399999 and i <= -300000 then
                vendorType = "BM"
            elseif i >= -499999 and i <= -400000 then
                vendorType = "MS"
            end
        end

        local newRecord = {
            g  = guid, c = c, z = z, i = i, il = il,
            xy = { x = x, y = y }, s = sName,
            st = now, ls = now, t0 = fp_t0,
            ac = 1,
            o  = sender, fp = foundBy,
            q  = q or 0, dt = dt or 0, it = it or 0, ist = ist or 0, cl = cl,
            vendorType = vendorType,
            vendorItems = vendorItems, 
            fp_votes = { [foundBy] = { score = 1, t0 = fp_t0 } },
            mc = 1, adc = 0, onHold = false,
            at = now,
            nd = now + math.random(7200, 18000),
        }
        
        local Comm = L:GetModule("Comm", true)
        if Comm and Comm._computeMid then newRecord.mid = Comm._computeMid(newRecord) end
        
        target_db[guid] = newRecord
        if dt ~= Constants.DISCOVERY_TYPE.BLACKMARKET then
            if Core.QueueItemForCaching and (not isCached or not newRecord.il) then
                Core:QueueItemForCaching(i)
                if Core.EnsureCachePump then Core:EnsureCachePump() end
            end
        end
        local Map = L:GetModule("Map", true)
        if Map and Map.Update then Map:Update() end
    else
        
        if (not existing.il) and il then existing.il = il end
        if (existing.q or 0) == 0 and q and q > 0 then existing.q = q end
        if (existing.dt or 0) == 0 and dt and dt > 0 then existing.dt = dt end
        if (existing.it or 0) == 0 and it and it > 0 then existing.it = it end
        if (existing.ist or 0) == 0 and ist and ist > 0 then existing.ist = ist end
        if (not existing.cl) and cl then existing.cl = cl end
        
        if dt == Constants.DISCOVERY_TYPE.BLACKMARKET then
            if not existing.vendorType then
                if i >= -399999 and i <= -300000 then existing.vendorType = "BM"
                elseif i >= -499999 and i <= -400000 then existing.vendorType = "MS"
                end
            end
            if vendorItems and #vendorItems > 0 then
                existing.vendorItems = vendorItems 
            end
        end
        
        if dt ~= Constants.DISCOVERY_TYPE.BLACKMARKET then
            if Core.QueueItemForCaching and (not isCached or not existing.il) then
                Core:QueueItemForCaching(i)
                if Core.EnsureCachePump then Core:EnsureCachePump() end
            end
        end
    end
end

function DBSync:Share(scope, target)
    return DBSync.Shares(scope, target)
end

function DBSync.Shares(scope, target)
    local now = GetTime()
    local cd = DBSync.SHARECOOLDOWN or SHARECOOLDOWN or 60
    if (now - lastShareTime) < cd then
        print(string.format("|cffff7f00LootCollector|r: lcshare is on cooldown for %d more seconds.", math.ceil(cd - (now - lastShareTime))))
        return
    end

    scope = (scope and scope.upper and scope:upper()) or "PARTY"
    if scope == "WHISPER" and (not target or target == "") then
        print("|cffff7f00LootCollector|r: lcshare whisper <PlayerName> required.")
        return
    end
    local distribution = (scope == "PARTY" or scope == "RAID" or scope == "GUILD" or scope == "WHISPER") and scope or "PARTY"

    if not (L and L.db and L.db.global) then
        print("|cffff7f00LootCollector|r: Database not ready.")
        return
    end

    local totalRecords = 0
    
    for _, d in pairs(L.db.global.discoveries or {}) do
        if type(d) == "table" and d.i and not d.onHold then
            totalRecords = totalRecords + 1
        end
    end
    for _, d in pairs(L.db.global.blackmarketVendors or {}) do
        if type(d) == "table" and d.i then
            totalRecords = totalRecords + 1
        end
    end
    
    if totalRecords == 0 then
        print("|cffffff00LootCollector|r: No records to share.")
        return
    end

    local sid = string.format("%s-%d-%04d", UnitName("player") or "player", time(), math.random(0, 9999))

    
    local startWire = string.format("S:%s:%d", sid, totalRecords)
    
    DBSync:SendWire(distribution, target, startWire)

    
    local seq = 1
    local batch = {}
    local cache = newNameCache()
    local totalSent = 0
    local limit = DBSync.MAXMSG or MAXMSG

    local function reset()
        cache = newNameCache()
        batch = {}
    end

    local function sendBatch()
        if #batch == 0 then return end
        local wire = encodeDataWire(sid, seq, batch, cache.list)
        
        if #wire > limit then
        
        else
            DBSync:SendWire(distribution, target, wire)
            totalSent = totalSent + #batch
            seq = seq + 1
        end
        reset()
    end

    local function tableCopyList(t) local r = {}; for i=1,#t do r[i]=t[i] end; return r end
    local function tableCopyMap(m) local r = {}; for k,v in pairs(m) do r[k]=v end; return r end

    local function tryAppendRecord(d, guid)
        local tmpCache = { list = tableCopyList(cache.list), map = tableCopyMap(cache.map) }
        local tmpRec   = packRecord(d, tmpCache)
        local tmpBatch = {}
        for i=1, #batch do tmpBatch[i] = batch[i] end
        tmpBatch[#tmpBatch+1] = tmpRec
        local wire = encodeDataWire(sid, seq, tmpBatch, tmpCache.list)
        
        if #wire <= limit then
            cache = tmpCache
            batch = tmpBatch
            return true
        end
        return false
    end

    
    for guid, d in pairs(L.db.global.discoveries or {}) do
        if type(d) == "table" and not d.onHold then
            local _, _, i, x4, y4 = guidParts(d)
            if i and i ~= 0 and not (x4 == 0 or y4 == 0) then
                if not tryAppendRecord(d, guid) then
                    sendBatch()
                    if not tryAppendRecord(d, guid) then
                        
                        reset()
                    end
                end
            end
        end
    end
    
    
    for guid, d in pairs(L.db.global.blackmarketVendors or {}) do
        if type(d) == "table" then
            local _, _, i, x4, y4 = guidParts(d)
            if i and i ~= 0 and not (x4 == 0 or y4 == 0) then
                if not tryAppendRecord(d, guid) then
                    sendBatch()
                    if not tryAppendRecord(d, guid) then
                        
                        reset()
                    end
                end
            end
        end
    end

    
    sendBatch()
    local packets = (seq - 1)
    local endWire = string.format("E:%s:%d", sid, packets)
    
    DBSync:SendWire(distribution, target, endWire)

    if totalSent > 0 then
        lastShareTime = now
        print(string.format("|cff00ff00LootCollector|r: Sent share request for %d records in %d packets via %s%s.",
            totalSent, packets, distribution, (distribution == "WHISPER" and (" to " .. target) or "")))
    end
end

function DBSync:ProcessBatchForSid(sid)
    local buffer = self.incomingBySid[sid]
    if not buffer or #buffer.pendingProcessing == 0 then return end

    local seqsToProcess = buffer.pendingProcessing
    buffer.pendingProcessing = {}

    

    local processedInBatch = 0
    for _, seq in ipairs(seqsToProcess) do
        local payload = buffer.packets[seq]
        if payload then
            local nameCache = payload.n or {}
            for _, rec in ipairs(payload.r or {}) do
                if type(rec) == "table" and #rec >= 14 then
                    local c   = rec[1] or 0
                    local z   = rec[2] or 0
                    local i   = rec[3] or 0
                    local x4  = rec[4] or 0
                    local y4  = rec[5] or 0
                    local s   = rec[6] or 0
                    local fp_t0 = rec[7] or 0
                    local fix = rec[8] or 1
                    local q   = rec[9] or 0
                    local dt  = rec[10] or 0
                    local it  = rec[11] or 0
                    local ist = rec[12] or 0
                    local clx = rec[13] or 1
                    local nix = rec[14] or 1
                    
                    local extraFields = {}
                    if #rec > 14 then
                        for j = 15, #rec do
                            table.insert(extraFields, rec[j])
                        end
                    end

                    if i ~= 0 and not (x4 == 0 or y4 == 0) then
                        local fName = nameCache[fix] or "Unknown"
                        local cl    = nameCache[clx]
                        local iname = nameCache[nix]
                        self:ApplyRecord(c, z, i, x4, y4, s, fp_t0, fName, q, dt, it, ist, cl, iname, buffer.sender, extraFields)
                        processedInBatch = processedInBatch + 1
                    end
                end
            end
            buffer.packets[seq] = nil
        end
    end

    if processedInBatch > 0 then
        importCounters[buffer.sender] = (importCounters[buffer.sender] or 0) + processedInBatch
        importTimers[buffer.sender]   = GetTime() + 5
        local Map = L:GetModule("Map", true)
        if Map and Map.Update then Map:Update() end
    end
end

function DBSync:ClearSidBuffer(sid, userIgnored)
    local buffer = self.incomingBySid[sid]
    if buffer then
        if userIgnored then
            print(string.format("|cffff7f00LootCollector|r: Ignored database share from %s.", buffer.sender or "unknown"))
        end
        self.incomingBySid[sid] = nil
        
    end
end

StaticPopupDialogs["LOOTCOLLECTOR_DBSYNC_CONFIRM"] = {
    text = "%s would like to share %d discoveries with you.",
    button1 = ACCEPT,
    button2 = IGNORE,
    OnAccept = function(selfFrame, data)
        local sid = data and data.sid
        if sid and DBSync.incomingBySid[sid] then
            local buffer = DBSync.incomingBySid[sid]
            buffer.state = "accepted"
            print(string.format("|cff00ff00LootCollector|r: Share from %s accepted. Import will begin as data is received.", buffer.sender or "unknown"))
            if #buffer.pendingProcessing >= PROCESS_BATCH_SIZE then
                DBSync:ProcessBatchForSid(sid)
            elseif buffer.isComplete then
                DBSync:ProcessBatchForSid(sid)
                DBSync:ClearSidBuffer(sid)
            end
        end
    end,
    OnCancel = function(selfFrame, data)
        local sid = data and data.sid
        if sid then DBSync:ClearSidBuffer(sid, true) end
    end,
    OnHide = function(selfFrame, data)
        local sid = data and data.sid
        local buf = sid and DBSync.incomingBySid[sid]
        if buf and buf.state == "pending" then
            DBSync:ClearSidBuffer(sid, true)
        end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = true,
}

function DBSync:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= PREFIX then return end
    

    

    local payload = parseWire(message)
    

    if payload.t == "S" then
        local total = tonumber(payload.total) or 0
        local sid   = tostring(payload.sid or "")
    

    
        
        local dynamicTimeout = math.max(120, math.min(600, total * 0.16))
    

        self.incomingBySid[sid] = {
            sender = sender,
            state = "pending",
            packets = {},
            pendingProcessing = {},
            totalRecords = 0,
            expectedRecords = total,
            expiresAt = GetTime() + dynamicTimeout,
            isComplete = false,
            limitReached = false,
        }
        StaticPopup_Show("LOOTCOLLECTOR_DBSYNC_CONFIRM", sender, tostring(total), { sender = sender, sid = sid, total = total })
        return
    end

    if payload.t == "D" then
        local sid = tostring(payload.sid or "")
        local buffer = self.incomingBySid[sid]
        

        if buffer.totalRecords >= MAXBUFFEREDRECORDS then
            if not buffer.limitReached then
                print(string.format("|cffff0000LootCollector|r: Share from %s exceeded the record limit of %d. Further data will be ignored.", buffer.sender or "unknown", MAXBUFFEREDRECORDS))
                buffer.limitReached = true
            end
            return
        end

        local seq = tonumber(payload.q) or 0
        if seq > 0 and not buffer.packets[seq] then
            buffer.packets[seq] = payload
            table.insert(buffer.pendingProcessing, seq)
            buffer.totalRecords = buffer.totalRecords + (#(payload.r or {}))
            
            if buffer.state == "accepted" and #buffer.pendingProcessing >= PROCESS_BATCH_SIZE then
                self:ProcessBatchForSid(sid)
            end
        
        end
        return
    end

    if payload.t == "E" then
        local sid = tostring(payload.sid or "")
        local buffer = self.incomingBySid[sid]
        buffer.isComplete = true
        if buffer.state == "accepted" then
            if #buffer.pendingProcessing > 0 then
                self:ProcessBatchForSid(sid)
            end
            self:ClearSidBuffer(sid)
        end
        return
    end
end

local function OnSummaryUpdate(self, elapsed)
    local now = GetTime()

    local hasActiveTimer = false
    for sender, exp in pairs(importTimers) do
        if exp then
            hasActiveTimer = true
            if now >= exp then
                local anyActiveForSender = false
                for sid, buffer in pairs(DBSync.incomingBySid) do
                    if buffer and buffer.sender == sender then
                        anyActiveForSender = true
                        break
                    end
                end
                if not anyActiveForSender then
                    local total = importCounters[sender]
                    if total and total > 0 then
                        print(string.format("|cff00ff00LootCollector|r: Finished importing %d records from %s.", total, sender))
                    end
                    importCounters[sender] = nil
                    importTimers[sender]   = nil
                end
            end
        end
    end

    for sid, buffer in pairs(DBSync.incomingBySid) do
        if now >= (buffer.expiresAt or now) and not buffer.isComplete then
            if buffer.state == "accepted" then
                print(string.format("|cffff7f00LootCollector|r: Share from %s timed out. Processing %d received records...", buffer.sender or "unknown", buffer.totalRecords))
                if #buffer.pendingProcessing > 0 then DBSync:ProcessBatchForSid(sid) end
            else
                print(string.format("|cffff7f00LootCollector|r: Database share from %s timed out and was ignored.", buffer.sender or "unknown"))
            end
            DBSync:ClearSidBuffer(sid)
        end
    end
end

SLASH_LootCollectorSHARE1 = "/lcshare"
SlashCmdList["LootCollectorSHARE"] = function(msg)
    wipe(importCounters)
    msg = msg or ""
    local s, t = msg:match("^%s*(%S+)%s*(.*)$")
    DBSync:Share(s or "PARTY", t or "")
end

function DBSync:OnInitialize()
    if L.LEGACY_MODE_ACTIVE then return end
    self:RegisterComm(PREFIX, "OnCommReceived")
    if not summaryTicker then
        summaryTicker = CreateFrame("Frame", "LootCollectorDBSyncSummaryTicker")
        summaryTicker:SetScript("OnUpdate", OnSummaryUpdate)
    end
end
-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl