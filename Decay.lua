local L = LootCollector
local Decay = L:NewModule("Decay")

-- Hardcoded global policy
local FADE_DAYS  = 30
local STALE_DAYS = 90

local SCAN_ON_LOGIN_DELAY   = 5
local SCAN_PERIODIC_SECONDS = 6 * 3600

local STATUS_UNCONFIRMED = "UNCONFIRMED"
local STATUS_CONFIRMED   = "CONFIRMED"
local STATUS_FADING      = "FADING"
local STATUS_STALE       = "STALE"

local now = time

local hasCTimer = type(C_Timer) == "table" and type(C_Timer.After) == "function" and type(C_Timer.NewTicker) == "function"

function Decay:ScanOnce()
    if not (L.db and L.db.global and L.db.global.discoveries) then return 0 end

    local fadeSecs  = FADE_DAYS  * 86400
    local staleSecs = STALE_DAYS * 86400
    if staleSecs < fadeSecs then
        staleSecs = fadeSecs + 86400
    end

    local tnow = now()
    local changed = 0

    for _, d in pairs(L.db.global.discoveries) do
        repeat
            if not d or not d.lastSeen then break end
            local ls = tonumber(d.lastSeen) or 0
            if ls <= 0 then break end
            local age = tnow - ls
            local prev = d.status or STATUS_UNCONFIRMED

            if age >= staleSecs then
                if prev ~= STATUS_STALE then
                    d.status = STATUS_STALE
                    d.statusTs = tnow
                    changed = changed + 1
                end
            elseif age >= fadeSecs then
                if prev ~= STATUS_FADING and prev ~= STATUS_STALE then
                    d.status = STATUS_FADING
                    d.statusTs = tnow
                    changed = changed + 1
                end
            end
        until true
    end

    if changed > 0 then
        local Map = L:GetModule("Map", true)
        if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
            Map:Update()
        end
    end

    return changed
end

SLASH_LootCollectorDECAY1 = "/lcdecay"
SlashCmdList["LootCollectorDECAY"] = function(msg)
    msg = msg or ""
    local sub = msg:match("^%s*(%S*)") or ""
    sub = sub:lower()

    if sub == "scan" or sub == "" then
        local n = Decay:ScanOnce()
        print(string.format("|cff00ff00LootCollector:|r Decay scan complete, changed %d entries.", n))
        return
    end

    if sub == "show" then
        print(string.format("|cff00ff00LootCollector:|r fade=%d days, stale=%d days (hardcoded policy)", FADE_DAYS, STALE_DAYS))
        return
    end

    print("|cffff7f00Usage:|r /lcdecay [scan|show]")
end

local tickerFrame = nil
local accum = 0

local function ensureFallbackTicker()
    if tickerFrame then return end
    tickerFrame = CreateFrame("Frame")
    tickerFrame:SetScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if accum >= SCAN_PERIODIC_SECONDS then
            accum = 0
            Decay:ScanOnce()
        end
    end)
end

function Decay:OnInitialize()
    if hasCTimer then
        C_Timer.After(SCAN_ON_LOGIN_DELAY, function() Decay:ScanOnce() end)
        C_Timer.NewTicker(SCAN_PERIODIC_SECONDS, function() Decay:ScanOnce() end)
    else
        ensureFallbackTicker()
        local f = CreateFrame("Frame")
        local elapsed = 0
        f:SetScript("OnUpdate", function(_, e)
            elapsed = elapsed + e
            if elapsed >= SCAN_ON_LOGIN_DELAY then
                f:SetScript("OnUpdate", nil)
                Decay:ScanOnce()
            end
        end)
    end
end

return Decay
