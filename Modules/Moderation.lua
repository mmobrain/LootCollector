-- Moderation.lua
-- Discovery moderation, ACK aggregation, and ON HOLD threshold logic for v5 protocol.
-- Includes session-based anti-spam for ACK packets.
-- UNK.B64.UTF-8


local L = LootCollector
local Moderation = L:NewModule("Moderation")

local PROTO_V              = 5
local OP_ACK               = "ACK"
local ACT_DET              = "DET"
local ACK_SPAM_THRESHOLD   = 6 

Moderation._ackSeen = Moderation._ackSeen or {} 
Moderation._ackSpamCount = Moderation._ackSpamCount or {} 

local function now()
    return time()
end

function Moderation:HandleAck(norm, sender, via)
    if not norm or norm.op ~= OP_ACK then
        return
    end
    if tonumber(norm.v or PROTO_V) ~= PROTO_V then
        return
    end
    local mid = norm.ack or norm.mid
    if not mid or mid == "" then
        return
    end

    local tnow = now()

    
    Moderation._ackSeen[mid] = Moderation._ackSeen[mid] or {}
    
    if Moderation._ackSeen[mid][sender] then
        
        Moderation._ackSpamCount[mid] = Moderation._ackSpamCount[mid] or {}
        Moderation._ackSpamCount[mid][sender] = (Moderation._ackSpamCount[mid][sender] or 1) + 1
        
        local spamCount = Moderation._ackSpamCount[mid][sender]
        
        if spamCount > ACK_SPAM_THRESHOLD then
            if L.db and L.db.profile then
                if not (L.db.profile.sharing and L.db.profile.sharing.blockList and L.db.profile.sharing.blockList[sender]) then
                    L.db.profile.invalidSenders = L.db.profile.invalidSenders or {}
                    L.db.profile.invalidSenders[sender] = {
                        count = 999,
                        lastInvalid = tnow,
                        sessionIgnored = true,
                        permanent = true,
                        lastReason = "ack_spam",
                    }
                    
                    L.db.profile.sharing = L.db.profile.sharing or {}
                    L.db.profile.sharing.blockList = L.db.profile.sharing.blockList or {}
                    L.db.profile.sharing.blockList[sender] = true
                    
                    print(string.format("|cffff0000[LootCollector SECURITY]|r %s sent excessive ACK spam. PERMANENTLY BANNED.", sender))
                end
            end
        end
        return 
    end

    
    Moderation._ackSeen[mid][sender] = true
    
    
    if (norm.act or ACT_DET) ~= ACT_DET then
        return
    end

    
    local Core = L:GetModule("Core", true)
    if Core and Core.ProcessAckVote then
        Core:ProcessAckVote(mid, sender)
    end
end

local function hookCore()
    local Core = L:GetModule("Core", true)
    if Core and not Core.HandleAck then
        function Core:HandleAck(norm, sender, via)
            return Moderation:HandleAck(norm, sender, via)
        end
    end
end

function Moderation:OnInitialize()
    hookCore()
end

return Moderation
-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl