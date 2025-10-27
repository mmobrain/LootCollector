-- Decay.lua
-- UNK.B64.UTF-8


local L = LootCollector
local Decay = L:NewModule("Decay")

local FADE_DAYS, STALE_DAYS = 30, 90
local SCAN_ON_LOGIN_DELAY, SCAN_PERIODIC_SECONDS = 5, 6 * 3600
local STATUS_UNCONFIRMED, STATUS_CONFIRMED, STATUS_FADING, STATUS_STALE = "UNCONFIRMED", "CONFIRMED", "FADING", "STALE"
local now = time

local hasCTimer = type(C_Timer) == "table" and type(C_Timer.After) == "function"

    function Decay:ScanOnce()
        if not (L.db and L.db.global and L.db.global.discoveries) then return 0 end
        
        local Constants = L:GetModule("Constants", true)
        if not Constants then return 0 end
        local STATUS = Constants.STATUS
        
        local fadeSecs, staleSecs = FADE_DAYS * 86400, STALE_DAYS * 86400
        if staleSecs < fadeSecs then staleSecs = fadeSecs + 86400 end
        local tnow, changed = now(), 0
    
        for _, d in pairs(L.db.global.discoveries) do
            if type(d) == "table" and d.ls then
                local age = tnow - (tonumber(d.ls) or 0)
                local prev = d.s or STATUS.UNCONFIRMED
    
                
                if not d.onHold then
                    if age >= staleSecs then
                        if prev ~= STATUS.STALE then
                            d.s = STATUS.STALE
                            d.st = tnow
                            changed = changed + 1
                        end
                    elseif age >= fadeSecs then
                        if prev ~= STATUS.FADING and prev ~= STATUS.STALE then
                            d.s = STATUS.FADING
                            d.st = tnow
                            changed = changed + 1
                        end
                    end
                end
            end
        end
    
        if changed > 0 then
            local Map = L:GetModule("Map", true)
            if Map and Map.Update then Map:Update() end
        end
        return changed
    end
    

SLASH_LootCollectorDECAY1 = "/lcdecay"; SlashCmdList["LootCollectorDECAY"] = function(msg)
    local sub = (msg or ""):match("^%s*(%S*)") or ""; sub = sub:lower()
    if sub == "scan" or sub == "" then print(string.format("|cff00ff00LootCollector:|r Decay scan complete, changed %d entries.", Decay:ScanOnce()))
    elseif sub == "show" then print(string.format("|cff00ff00LootCollector:|r fade=%d days, stale=%d days", FADE_DAYS, STALE_DAYS))
    else print("|cffff7f00Usage:|r /lcdecay [scan|show]") end
end

function Decay:OnInitialize()
    if L.LEGACY_MODE_ACTIVE then return end
    if hasCTimer then
        C_Timer.After(SCAN_ON_LOGIN_DELAY, function() self:ScanOnce() end)
        C_Timer.NewTicker(SCAN_PERIODIC_SECONDS, function() self:ScanOnce() end)
    else 
        local f = CreateFrame("Frame"); local elapsed = 0
        f:SetScript("OnUpdate", function(_, e) elapsed=elapsed+e; if elapsed>=SCAN_ON_LOGIN_DELAY then f:SetScript("OnUpdate",nil); self:ScanOnce() end end)
        local ticker = CreateFrame("Frame"); local accum = 0
        ticker:SetScript("OnUpdate", function(_, el) accum=accum+el; if accum>=SCAN_PERIODIC_SECONDS then accum=0; self:ScanOnce() end end)
    end
end

return Decay
-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl