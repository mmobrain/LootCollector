local L = LootCollector
local Moderation = L:NewModule("Moderation")

local PROTO_V              = 5
local OP_ACK               = "ACK"
local ACT_DET              = "DET"
local ACK_SPAM_MIN_THRESH  = 4 
local ACK_SPAM_MONTH_THRESH = 21

Moderation._ackSeen = Moderation._ackSeen or {} 
Moderation._ackSpamMinute = Moderation._ackSpamMinute or {}

local function now()
    return time()
end

function Moderation:HandleAck(norm, sender, via)
    L._debug("Moderation", "HandleAck entry point. Sender: " .. tostring(sender))
    if not norm or norm.op ~= OP_ACK then
        L._debug("Moderation", "Dropped: Packet is not an ACK.")
        return
    end
    if tonumber(norm.v or PROTO_V) ~= PROTO_V then
        return
    end
    local mid = norm.ack or norm.mid
    if not mid or mid == "" then
        L._debug("Moderation", "Dropped: ACK packet is missing mid/ack identifier.")
        return
    end

    L._debug("Moderation", "Processing ACK for mid: " .. tostring(mid))

    local tnow = now()

    Moderation._ackSeen[mid] = Moderation._ackSeen[mid] or {}
    
    if Moderation._ackSeen[mid][sender] then
        L._debug("Moderation", "Duplicate ACK detected from this sender. Checking spam thresholds.")
        
        local mTrack = Moderation._ackSpamMinute[sender] or { start = tnow, count = 0 }
        if tnow - mTrack.start > 60 then
            mTrack.start = tnow
            mTrack.count = 0
        end
        mTrack.count = mTrack.count + 1
        Moderation._ackSpamMinute[sender] = mTrack
        
        local monthCount = 0
        if L.db and L.db.profile then
            local currentMonth = date("%Y-%m")
            L.db.profile.ackModeration = L.db.profile.ackModeration or { month = currentMonth, counts = {} }
            if L.db.profile.ackModeration.month ~= currentMonth then
                L.db.profile.ackModeration.month = currentMonth
                L.db.profile.ackModeration.counts = {}
            end
            L.db.profile.ackModeration.counts[sender] = (L.db.profile.ackModeration.counts[sender] or 0) + 1
            monthCount = L.db.profile.ackModeration.counts[sender]
        end
        
        if mTrack.count > ACK_SPAM_MIN_THRESH or monthCount > ACK_SPAM_MONTH_THRESH then
            L._debug("Moderation", "SPAM THRESHOLD EXCEEDED. Blocking sender.")
            if L.db and L.db.profile then
                if not (L.db.profile.sharing and L.db.profile.sharing.blockList and L.db.profile.sharing.blockList[sender]) then
                    L.db.profile.invalidSenders = L.db.profile.invalidSenders or {}
                    L.db.profile.invalidSenders[sender] = {
                        count = 999,
                        lastInvalid = tnow,
                        sessionIgnored = true,
                        permanent = true,
                        lastReason = "ack_spam_duplicate",
                    }
                    
                    L.db.profile.sharing = L.db.profile.sharing or {}
                    L.db.profile.sharing.blockList = L.db.profile.sharing.blockList or {}
                    L.db.profile.sharing.blockList[sender] = true
                    
                    print(string.format("|cffff0000[LootCollector SECURITY]|r %s sent excessive duplicate ACKs. PERMANENTLY BANNED.", sender))
                end
            end
        end
        L._debug("Moderation", "Spam check passed, but this is a duplicate. Logic ends here.")
        return 
    end

    Moderation._ackSeen[mid][sender] = true
    
    if (norm.act or ACT_DET) ~= ACT_DET then
        L._debug("Moderation", "ACK Action is not DET (Detection). Skipping vote.")
        return
    end

    local Core = L:GetModule("Core", true)
    if Core and Core.ProcessAckVote then
        L._debug("Moderation", "Forwarding to Core:ProcessAckVote.")
        Core:ProcessAckVote(mid, sender)
    else
        L._debug("Moderation", "ERROR: Core:ProcessAckVote is missing!")
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