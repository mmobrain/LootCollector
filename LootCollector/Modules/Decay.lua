local L = LootCollector
local Decay = L:NewModule("Decay")

local FADE_DAYS, STALE_DAYS, REMOVE_DAYS = 30, 90, 120
local SCAN_ON_LOGIN_DELAY, SCAN_PERIODIC_SECONDS = 5, 6 * 3600
local STATUS_UNCONFIRMED, STATUS_CONFIRMED, STATUS_FADING, STATUS_STALE = "UNCONFIRMED", "CONFIRMED", "FADING", "STALE"
local now = time

local DECAY_BUDGET_MS = 4 
local DECAY_HARDCAP = 150

Decay._scanInProgress = false
Decay._scanKey = nil
Decay._scanChangedCount = 0
Decay._scanRemovedCount = 0

Decay._tombstoneScanKey = nil
Decay._tombstonePurgedCount = 0
Decay._guidsToRemove = {}

local function ScheduleAfter(seconds, func)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        return C_Timer.After(seconds, func)
    end
    local f = CreateFrame("Frame")
    local cancelled = false
    local target = GetTime() + (tonumber(seconds) or 0)
    f:SetScript("OnUpdate", function(self)
        if cancelled then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            return
        end
        if GetTime() >= target then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            func()
        end
    end)
    f:Show()
    return {
        Cancel = function() cancelled = true end,
        IsCancelled = function() return cancelled end,
    }
end

function Decay:StartChunkedScan()
    if self._scanInProgress then return end
    
    self._scanInProgress = true
    self._scanKey = nil
    self._tombstoneScanKey = nil
    self._scanChangedCount = 0
    self._scanRemovedCount = 0
    self._tombstonePurgedCount = 0
    
    L._debug("Decay", "Starting background database decay scan...")
    self:ProcessNextChunk()
end

function Decay:ProcessNextChunk()
    if not self._scanInProgress then return end

    if L:IsPaused() or InCombatLockdown() then 
        ScheduleAfter(2.0, function() self:ProcessNextChunk() end)
        return 
    end

    local startMs = debugprofilestop and debugprofilestop() or (GetTime() * 1000)

    local db = L:GetDiscoveriesDB()
    local tnow = time()
    local fadeSecs = FADE_DAYS * 86400
    local staleSecs = STALE_DAYS * 86400
    local removeSecs = REMOVE_DAYS * 86400

    local k = self._scanKey
    
    
    local guidsToRemove = self._guidsToRemove
    wipe(guidsToRemove)
    
    local loopCounter = 0

    if db then
        if k ~= nil and db[k] == nil then k = nil end
        
        while true do
            k, d = next(db, k)
            if not k then break end 
            
            if type(d) == "table" and d.ls then
                local age = tnow - (tonumber(d.ls) or 0)
                local prev = d.s or STATUS_UNCONFIRMED

                if not d.onHold then
                    if age >= removeSecs then
                        table.insert(guidsToRemove, k)
                    elseif age >= staleSecs then
                        if prev ~= STATUS_STALE then
                            d.s = STATUS_STALE
                            d.st = tnow
                            self._scanChangedCount = self._scanChangedCount + 1
                        end
                    elseif age >= fadeSecs then
                        if prev ~= STATUS_FADING and prev ~= STATUS_STALE then
                            d.s = STATUS_FADING
                            d.st = tnow
                            self._scanChangedCount = self._scanChangedCount + 1
                        end
                    end
                end
            end
            
            loopCounter = loopCounter + 1
            if loopCounter >= 250 then break end 
            
            local nowMs = debugprofilestop and debugprofilestop() or (GetTime() * 1000)
            if (nowMs - startMs) >= DECAY_BUDGET_MS then
                break
            end
        end
        self._scanKey = k
    end

    for _, guid in ipairs(guidsToRemove) do
        db[guid] = nil
        self._scanRemovedCount = self._scanRemovedCount + 1
    end

    if self._scanKey == nil then
        local deletedCache = L.db and L.db.global and L.db.global.deletedCache
        local tk = self._tombstoneScanKey
        loopCounter = 0
        
        if deletedCache then
            if tk ~= nil and deletedCache[tk] == nil then tk = nil end
            
            while true do
                tk, data = next(deletedCache, tk)
                if not tk then break end 
                
                local shouldRemove = false
                if data.expiresAt then
                    if tnow > data.expiresAt then shouldRemove = true end
                elseif data.deletedAt then
                    if (tnow - data.deletedAt) > staleSecs then shouldRemove = true end
                else
                    shouldRemove = true
                end
                
                if shouldRemove then
                    deletedCache[tk] = nil
                    self._tombstonePurgedCount = self._tombstonePurgedCount + 1
                end
                
                loopCounter = loopCounter + 1
                if loopCounter >= 250 then break end 

                local nowMs = debugprofilestop and debugprofilestop() or (GetTime() * 1000)
                if (nowMs - startMs) >= DECAY_BUDGET_MS then
                    break
                end
            end
            self._tombstoneScanKey = tk
        end
    end

    if self._scanKey == nil and self._tombstoneScanKey == nil then
        self._scanInProgress = false
        if self._scanChangedCount > 0 or self._scanRemovedCount > 0 or self._tombstonePurgedCount > 0 then
            local Map = L:GetModule("Map", true)
            if Map then
                Map.cacheIsDirty = true
                if Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end
                if Map.UpdateMinimap then Map:UpdateMinimap() end
            end
            L:SendMessage("LOOTCOLLECTOR_DISCOVERY_LIST_UPDATED")
        end
        return
    end

    ScheduleAfter(0.05, function() self:ProcessNextChunk() end)
end

SLASH_LootCollectorDECAY1 = "/lcdecay"
SlashCmdList["LootCollectorDECAY"] = function(msg)
    local sub = (msg or ""):match("^%s*(%S*)") or ""; sub = sub:lower()
    if sub == "scan" or sub == "" then 
        if Decay._scanInProgress then
            print("|cffff7f00LootCollector:|r A background decay scan is already in progress.")
        else
            Decay:StartChunkedScan()
            print("|cff00ff00LootCollector:|r Background decay scan started.")
        end
    elseif sub == "show" then 
        print(string.format("|cff00ff00LootCollector:|r fade=%d days, stale=%d days, remove=%d days", FADE_DAYS, STALE_DAYS, REMOVE_DAYS))
    else 
        print("|cffff7f00Usage:|r /lcdecay [scan|show]") 
    end
end

function Decay:OnInitialize()
    if L.LEGACY_MODE_ACTIVE then return end
    
    
    ScheduleAfter(SCAN_ON_LOGIN_DELAY, function() 
        self:StartChunkedScan()
    end)
    
    
    if type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
        C_Timer.NewTicker(SCAN_PERIODIC_SECONDS, function()
            self:StartChunkedScan()
        end)
    else
        local ticker = CreateFrame("Frame")
        local accum = 0
        ticker:SetScript("OnUpdate", function(_, el) 
            accum = accum + el
            if accum >= SCAN_PERIODIC_SECONDS then 
                accum = 0
                self:StartChunkedScan()
            end 
        end)
    end
end

return Decay