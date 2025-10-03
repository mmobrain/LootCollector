local L = LootCollector
local DBSync = L:NewModule("DBSync", "AceComm-3.0", "AceSerializer-3.0")

local PREFIX = "LCDB1"
local MAX_MSG = 240

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

local function scaleCoord(v)
    if not v or v ~= v then return 0 end
    local x = v * 1000
    if x >= 0 then
        return math.floor(x + 0.5)
    else
        return -math.floor(-x + 0.5)
    end
end

local function getItemID(d)
    if d.itemID and type(d.itemID) == "number" then return d.itemID end
    if d.itemLink and type(d.itemLink) == "string" then
        local id = d.itemLink:match("item:(%d+)")
        if id then
            id = tonumber(id)
            d.itemID = id
            return id
        end
    end
    return nil
end

local function guidParts(d)
    local z = d.zoneID or d.zone or 0
    local id = getItemID(d) or 0
    local x = scaleCoord(d.coords and d.coords.x or 0)
    local y = scaleCoord(d.coords and d.coords.y or 0)
    return z, id, x, y
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

local function packRecord(d)
    local z, i, x3, y3 = guidParts(d)
    local s  = STATUS[(d.status or "UNCONFIRMED"):upper()] or STATUS.UNCONFIRMED
    local st = getStatusTs(d)
    local ls = getLastSeen(d)
    return { z or 0, i or 0, x3 or 0, y3 or 0, s or 0, st or 0, ls or 0 }
end

local function unpackRecord(rec)
    local z  = tonumber(rec[1]) or 0
    local i  = tonumber(rec[2]) or 0
    local x3 = tonumber(rec[3]) or 0
    local y3 = tonumber(rec[4]) or 0
    local s  = tonumber(rec[5]) or 0
    local st = tonumber(rec[6]) or 0
    local ls = tonumber(rec[7]) or 0
    return z, i, x3, y3, s, st, ls
end

function DBSync:ApplyRecord(z, i, x3, y3, s, st, ls)
    if not (L.db and L.db.global and L.db.global.discoveries) then return end
    local guid = buildGuid(z, i, x3, y3)
    local existing = L.db.global.discoveries[guid]

    if not existing then
        L.db.global.discoveries[guid] = {
            guid = guid,
            zoneID = z,
            itemID = i,
            coords = { x = x3 / 1000, y = y3 / 1000 },
            status = STATUS_REV[s] or "UNCONFIRMED",
            statusTs = st,
            lastSeen = ls,
            timestamp = ls,
        }
        return
    end

    local localSt = getStatusTs(existing)
    if st > localSt then
        existing.status = STATUS_REV[s] or "UNCONFIRMED"
        existing.statusTs = st
    end

    local localLs = getLastSeen(existing)
    if ls > localLs then
        existing.lastSeen = ls
    end

    if not existing.itemID or existing.itemID == 0 then
        existing.itemID = i
    end
end

function DBSync:SendPacket(distribution, target, seq, records)
    local payload = { t = "D", q = seq, r = records }
    local ok, msg = self:Serialize(payload)
    if not ok or not msg then return 0 end
    if #msg > MAX_MSG then return -1 end
    self:SendCommMessage(PREFIX, msg, distribution, target, "NORMAL")
    return #msg
end

local function recordsIterator()
    local tbl = (L.db and L.db.global and L.db.global.discoveries) or {}
    return next, tbl, nil
end

function DBSync:Share(scope, target)
    scope = scope and scope:upper() or "PARTY"
    if scope == "WHISPER" and (not target or target == "") then
        print("|cffff7f00LootCollector:|r /lcshare whisper <PlayerName> required for whisper.")
        return
    end

    local distribution = (scope == "PARTY" or scope == "RAID" or scope == "GUILD" or scope == "WHISPER") and scope or "PARTY"

    local seq = 1
    local batch = {}
    local sent = 0

    for _, d in recordsIterator() do
        local z, i, x3, y3 = guidParts(d)
        if i and i ~= 0 and (x3 ~= 0 or y3 ~= 0) then
            local rec = packRecord(d)
            table.insert(batch, rec)

            local testPayload = { t = "D", q = seq, r = batch }
            local ok, testMsg = self:Serialize(testPayload)
            if ok and #testMsg > MAX_MSG then
                table.remove(batch)
                if #batch > 0 then
                    local bytes = self:SendPacket(distribution, target, seq, batch)
                    if bytes == -1 then
                        for _, single in ipairs(batch) do
                            local b2 = self:SendPacket(distribution, target, seq, { single })
                            if b2 ~= -1 then
                                sent = sent + 1
                                seq = seq + 1
                            end
                        end
                    else
                        sent = sent + #batch
                        seq = seq + 1
                    end
                end
                batch = { rec }
            end
        end
    end

    if #batch > 0 then
        local bytes = self:SendPacket(distribution, target, seq, batch)
        if bytes == -1 then
            for _, single in ipairs(batch) do
                local b2 = self:SendPacket(distribution, target, seq, { single })
                if b2 ~= -1 then
                    sent = sent + 1
                    seq = seq + 1
                end
            end
        else
            sent = sent + #batch
            seq = seq + 1
        end
    end

    print(string.format("|cff00ff00LootCollector:|r Shared %d records via %s%s.", sent, distribution, distribution == "WHISPER" and (" to " .. target) or ""))
end

function DBSync:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= PREFIX then return end
    if sender == UnitName("player") then return end

    local ok, payload = self:Deserialize(message)
    if not ok or type(payload) ~= "table" then return end
    if payload.t ~= "D" or type(payload.r) ~= "table" then return end

    for _, rec in ipairs(payload.r) do
        if type(rec) == "table" then
            local z, i, x3, y3, s, st, ls = unpackRecord(rec)
            if i ~= 0 and (x3 ~= 0 or y3 ~= 0) then
                self:ApplyRecord(z, i, x3, y3, s, st, ls)
            end
        end
    end

    local Map = L:GetModule("Map", true)
    if Map and Map.Update then
        Map:Update()
    end
end

SLASH_LootCollectorSHARE1 = "/lcshare"
SlashCmdList["LootCollectorSHARE"] = function(msg)
    msg = msg or ""
    local scope, target = msg:match("^%s*(%S+)%s*(.*)$")
    scope = scope or "PARTY"
    target = target or ""
    DBSync:Share(scope, target)
end

function DBSync:OnInitialize()
    self:RegisterComm(PREFIX, "OnCommReceived")
end

return DBSync
