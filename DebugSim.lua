-- DebugSim.lua
-- Single-client network simulation and debug for LootCollector:
-- - Injects DISC/CONF/GONE (AceComm and channel) and compact DBSYNC frames with a fake sender.
-- - Prints library presence and detailed serialization outputs for inspection.

local L = LootCollector
local Sim = L:NewModule("DebugSim")  -- debug-only module. [attached_file:1]


local LibBase64 = LibStub and LibStub("LibBase64-1.0", true) -- not required now, but kept if needed elsewhere
local AceSerializer = LibStub("AceSerializer-3.0")  -- required. [attached_file:3]

local function round2(v)
    v = tonumber(v) or 0
    return math.floor(v * 100 + 0.5) / 100
end  -- unify coords. [attached_file:1]

local function truncate(s, n)
    if not s then return "nil" end
    n = n or 96
    if #s <= n then return s end
    return s:sub(1, n) .. "...(" .. tostring(#s) .. " bytes)"
end  -- pretty head. [attached_file:1]

local function sfdumps(tbl)
    if not Smallfolk or not Smallfolk.dumps then return nil, "LibSmallfolk missing" end
    local ok, s = pcall(Smallfolk.dumps, tbl)
    if ok and type(s) == "string" then return s end
    return nil, "Smallfolk.dumps failed"
end  -- Smallfolk serializer. [attached_file:1]

local function aser_serialize(tbl)
    local ser = AceSerializer:Serialize(tbl)
    if type(ser) == "string" then return ser end
    return nil, "AceSerializer Serialize failed"
end
 -- AceSerializer serializer. [attached_file:3]

local function b64enc(s)
    if not LibBase64 or not LibBase64.Encode then return nil, "LibBase64 missing" end
    local ok, out = pcall(LibBase64.Encode, s)
    if ok and type(out) == "string" then return out end
    return nil, "Base64 encode failed"
end  -- base64. [attached_file:1]

-- Build v1 wire (2-decimal coords), default op="DISC"
local function buildWireV1(op, itemID, zoneID, x, y)
    return {
        v = 1,
        op = op or "DISC",
        i = tonumber(itemID) or 0,
        z = tonumber(zoneID) or 0,
        x = round2(x),
        y = round2(y),
        t = time(),
    }
end  -- wire builder. [attached_file:1]

-- Channel encoders
local function encodeLCb1(wire)
    local blob, e1 = sfdumps(wire)
    if not blob then return nil, e1 end
    local b64, e2 = b64enc(blob)
    if not b64 then return nil, e2 end
    return "LCb1:" .. b64, nil, blob, b64
end  -- LCb1 encoder. [attached_file:1]

local function encodeLC1(wire)
    return string.format("LC1:i%d,z%d,x%.2f,y%.2f,t%d", wire.i or 0, wire.z or 0, wire.x or 0, wire.y or 0, wire.t or time())
end  -- LC1 legacy. [attached_file:1]

-- AceComm injection with debug; uses Smallfolk if present, else AceSerializer
local function injectAceComm(op, itemID, zoneID, x, y, sender)
    local Comm = L:GetModule("Comm", true)
    if not (Comm and Comm.OnCommMessageReceived) then
        print("|cffff7f00LootCollector:|r Comm module not ready.")
        return
    end
    local wire = buildWireV1(op, itemID, zoneID, x, y)
    local payload, which = sfdumps(wire), "SF"
    if not payload then
        payload, which = aser_serialize(wire), "ASer"
    end
    if not payload then
        print("|cffff7f00LootCollector:|r No serializer available for AceComm (Smallfolk and AceSerializer both failed).")
        return
    end
    sender = sender and tostring(sender) or "Tester"
    print(string.format("|cff00ff00AceComm Debug:|r op=%s z=%d i=%d x=%.2f y=%.2f | payload=%d bytes | head=%s | ser=%s",
        wire.op, wire.z, wire.i, wire.x, wire.y, #payload, truncate(payload), which))
    Comm:OnCommMessageReceived(L.addonPrefix, payload, sender, "WHISPER")
    print(string.format("|cff00ff00LootCollector:|r Injected AceComm %s from '%s'", wire.op, sender))
end  -- comm inject. [attached_file:1]

-- Channel injection with debug (LCb1 preferred only when Smallfolk exists; else LC1 fallback)
local function injectChannel(op, itemID, zoneID, x, y, sender, legacy)
    local Comm = L:GetModule("Comm", true)
    if not (Comm and Comm.OnChatMsgChannel) then
        print("|cffff7f00LootCollector:|r Comm module not ready.")
        return
    end
    local wire = buildWireV1(op, itemID, zoneID, x, y)
    sender = sender and tostring(sender) or "Tester"
    local line, err, raw, b64
    if not legacy and Smallfolk then
        line, err, raw, b64 = encodeLCb1(wire)
        if line then
            print(string.format("|cff00ff00Channel Debug LCb1:|r op=%s z=%d i=%d x=%.2f y=%.2f | raw=%dB b64=%dB | head=%s",
                wire.op, wire.z, wire.i, wire.x, wire.y, #raw, #b64, truncate("LCb1:" .. b64)))
        end
    end
    if not line then
        if not legacy and not Smallfolk then
            print("|cffffff00LootCollector:|r Smallfolk missing; using LC1 legacy for channel injection.")
        elseif not legacy and err then
            print(string.format("|cffffff00LootCollector:|r LCb1 encode failed (%s); using LC1 legacy.", tostring(err)))
        end
        line = encodeLC1(wire)
        print(string.format("|cff00ff00Channel Debug LC1:|r line=%s", line))
    end
    local channelBaseName = L.chatChannel or "BBLCC25"
    Comm:OnChatMsgChannel(line, sender, nil, nil, nil, nil, nil, nil, nil, channelBaseName)
    print(string.format("|cff00ff00LootCollector:|r Injected %s %s from '%s'", (Smallfolk and not legacy) and "LCb1" or "LC1", wire.op, sender))
end  -- channel inject. [attached_file:1]

-- DBSYNC injection with debug (always AceSerializer)
local function injectDBSync(itemID, zoneID, x, y, status, statusTs, lastSeen, sender)
    local DBS = L:GetModule("DBSync", true)
    if not (DBS and DBS.OnCommReceived and DBS.Serialize) then
        print("|cffff7f00LootCollector:|r DBSync module or AceSerializer not ready.")
        return
    end
    local z = tonumber(zoneID) or 0
    local i = tonumber(itemID) or 0
    local x2 = math.floor(round2(x) * 100 + 0.5)
    local y2 = math.floor(round2(y) * 100 + 0.5)
    local s  = tonumber(status) or 0
    local st = tonumber(statusTs) or time()
    local ls = tonumber(lastSeen) or st
    local payload = { t = "D", q = 1, r = { { z, i, x2, y2, s, st, ls } } }
    local serialized = DBS:Serialize(payload)
    if type(serialized) ~= "string" then
        print("|cffff7f00LootCollector:|r AceSerializer Serialize failed for DBSYNC payload.")
        return
    end
    print(string.format("|cff00ff00DBSYNC Debug:|r z=%d i=%d x2=%d y2=%d s=%d st=%d ls=%d | payload=%d bytes | head=%s",
        z, i, x2, y2, s, st, ls, #serialized, truncate(serialized)))
    sender = sender and tostring(sender) or "Tester"
    DBS:OnCommReceived("LCDB1", serialized, "WHISPER", sender)
    print(string.format("|cff00ff00LootCollector:|r Injected DBSYNC record from '%s'", sender))
end  -- dbsync inject. [attached_file:1]

-- Slash: /lcinject comm|chan|legacy <op> <itemID> <zoneID> <x> <y> [sender]
SLASH_LootCollectorINJECT1 = "/lcinject"
SlashCmdList["LootCollectorINJECT"] = function(msg)
    msg = msg or ""
    local via, op, i, z, x, y, sender = msg:match("^%s*(%S+)%s+(%S+)%s+(%d+)%s+(%d+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*(%S*)")
    if not via or not op or not i or not z or not x or not y then
        print("|cffff7f00Usage:|r /lcinject comm|chan|legacy <op> <itemID> <zoneID> <x> <y> [sender]")
        return
    end
    if via == "comm" then
        injectAceComm(op, i, z, x, y, sender ~= "" and sender or nil)
    elseif via == "chan" then
        injectChannel(op, i, z, x, y, sender ~= "" and sender or nil, false)
    elseif via == "legacy" then
        injectChannel(op, i, z, x, y, sender ~= "" and sender or nil, true)
    else
        print("|cffff7f00LootCollector:|r via must be one of: comm, chan, legacy")
    end
end  -- main injector. [attached_file:1]

-- Slash: /lcsimdb <itemID> <zoneID> <x> <y> [status 0..3] [statusTs] [lastSeen] [sender]
SLASH_LootCollectorSIMDB1 = "/lcsimdb"
SlashCmdList["LootCollectorSIMDB"] = function(msg)
    msg = msg or ""
    local i, z, x, y, s, st, ls, sender = msg:match("^%s*(%d+)%s+(%d+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*(%d*)%s*(%d*)%s*(%d*)%s*(%S*)")
    if not i or not z or not x or not y then
        print("|cffff7f00Usage:|r /lcsimdb <itemID> <zoneID> <x> <y> [status 0..3] [statusTs] [lastSeen] [sender]")
        return
    end
    injectDBSync(i, z, x, y, s ~= "" and s or 0, st ~= "" and st or nil, ls ~= "" and ls or nil, sender ~= "" and sender or nil)
end  -- dbsync injector. [attached_file:1]

-- Slash: /lclibs to print library presence (LibStub and global fallback)
SLASH_LootCollectorLIBS1 = "/lclibs"
SlashCmdList["LootCollectorLIBS"] = function()
    local sfOk = ((LibStub and LibStub("LibSmallfolk-1.0", true)) or _G.smallfolk) and true or false
    local asOk = (LibStub and LibStub("AceSerializer-3.0", true)) and true or false
    local b64Ok = (LibBase64 ~= nil)
    print(string.format("|cff00ff00LootCollector:|r LibSmallfolk=%s, LibBase64=%s, AceSerializer=%s", tostring(sfOk), tostring(b64Ok), tostring(asOk)))
    local Comm = L:GetModule("Comm", true)
    local DBS  = L:GetModule("DBSync", true)
    print(string.format("|cff00ff00LootCollector:|r Comm ready=%s, DBSync ready=%s", tostring(Comm ~= nil), tostring(DBS ~= nil)))
end  -- lib status. [attached_file:1]

function Sim:OnInitialize()
    -- nothing. [attached_file:1]
end

return Sim  -- end module. [attached_file:1]
