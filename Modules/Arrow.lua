-- Arrow.lua
-- Refactored to integrate with TomTom as an optional dependency.
-- UNK.B64.UTF-8


local L = LootCollector
local Arrow = L:NewModule("Arrow", "AceEvent-3.0")

local UPDATE_INTERVAL = 2.0
local ARRIVAL_DISTANCE_YARDS = 15 
local LOOT_DISTANCE_THRESHOLD_SQ = (0.01 * 0.01) 

local Arrow_updateFrame = nil
Arrow.elapsed = 0

Arrow.currentTarget = nil 
Arrow.manualTarget = nil  
Arrow.tomtomUID = nil
Arrow.enabled = false 

Arrow.sessionSkipList = {}

local function isMine(rec)
    local me = UnitName and UnitName("player")
    if not me or not rec then return false end
    
    local names = { rec.o, rec.fp }
    for _, n in ipairs(names) do
        if type(n) == "string" and n ~= "" then
            if n == me or n:find("^"..me.."%-") then
                return true
            end
        end
    end
    
    if rec.bySelf == true or rec.isLocal == true then
        return true
    end
    return false
end

local function IsTomTomAvailable() return _G.TomTomAddZWaypoint or (_G.TomTom and _G.TomTom.AddZWaypoint) end
local function TT_AddZWaypoint(c, z, x, y, desc)
    if not IsTomTomAvailable() then return end
    x, y = (x or 0) * 100, (y or 0) * 100
    if _G.TomTom and _G.TomTom.AddZWaypoint then return TomTom:AddZWaypoint(c, z, x, y, desc, false, false, true, nil, true, false)
    elseif _G.TomTomAddZWaypoint then return TomTomAddZWaypoint(c, z, x, y, desc, false, false, true, nil, true, false) end
end
local function TT_RemoveWaypoint(uid)
    if not uid or not IsTomTomAvailable() then return end
    if _G.TomTom and _G.TomTom.RemoveWaypoint then TomTom:RemoveWaypoint(uid)
    elseif _G.TomTomRemoveWaypoint then TomTomRemoveWaypoint(uid) end
end
local function TT_SetCrazyArrow(uid, title)
    if not IsTomTomAvailable() then return end
    if _G.TomTom and _G.TomTom.SetCrazyArrow then TomTom:SetCrazyArrow(uid, ARRIVAL_DISTANCE_YARDS, title)
    elseif _G.TomTomSetCrazyArrow then TomTomSetCrazyArrow(uid, ARRIVAL_DISTANCE_YARDS, title) end
end
local function TT_ClearCrazyArrow()
    if not IsTomTomAvailable() then return end
    if _G.TomTom and _G.TomTom.SetCrazyArrow then TomTom:SetCrazyArrow(nil)
    elseif _G.TomTomSetCrazyArrow then TomTomSetCrazyArrow(nil) end
end
local function TT_GetDistanceToWaypoint(uid)
    if not uid or not IsTomTomAvailable() then return nil end
    if _G.TomTom and _G.TomTom.GetDistanceToWaypoint then return TomTom:GetDistanceToWaypoint(uid)
    elseif _G.TomTomGetDistanceToWaypoint then return TomTomGetDistanceToWaypoint(uid) end
end

local function SaveMapState() return GetCurrentMapContinent and GetCurrentMapContinent()or 0, GetCurrentMapZone and GetCurrentMapZone()or 0, GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel()or 0 end
local function RestoreMapState(c,z,dl) if SetMapZoom and c and z then SetMapZoom(c,z)end; if SetDungeonMapLevel and dl then SetDungeonMapLevel(dl)end end

function Arrow:GetPlayerPos()
    local mapOpen = WorldMapFrame and WorldMapFrame:IsShown()
    local sc, sz, sdl; if not mapOpen then sc,sz,sdl=SaveMapState(); if SetMapToCurrentZone then SetMapToCurrentZone()end end
    local px,py = GetPlayerMapPosition("player"); if not mapOpen then RestoreMapState(sc,sz,sdl) end
    return px, py
end

function Arrow:GetPlayerLocation()
    local mapOpen = WorldMapFrame and WorldMapFrame:IsShown()
    local sc, sz, sdl; if not mapOpen then sc,sz,sdl=SaveMapState(); if SetMapToCurrentZone then SetMapToCurrentZone()end end
    local c = GetCurrentMapContinent and GetCurrentMapContinent()or 0; local z = GetCurrentMapZone and GetCurrentMapZone()or 0
    if not mapOpen then RestoreMapState(sc,sz,sdl) end
    return c, z
end

function Arrow:ClearSessionSkipList()
    wipe(self.sessionSkipList)
    print("|cff00ff00LootCollector:|r Session skip list has been cleared.")
    self:UpdateArrow(true) 
end

function Arrow:SkipNearest()
    if self.enabled and self.currentTarget and not self.manualTarget then
        local guid = self.currentTarget.g
        if guid then
            self.sessionSkipList[guid] = true            
            print(string.format("|cff00ff00LootCollector:|r Skipped tracking of: %s", self.currentTarget.il or "discovery"))
            self:UpdateArrow(true) 
        end
    else
        print("|cffff7f00LootCollector:|r No active target to skip.")
    end
end

function Arrow:OnPlayerLootedItem(event, itemID, c, z, x, y)
    if not self.enabled or not self.currentTarget then return end
    if not (L.db and L.db.profile and L.db.profile.mapFilters and L.db.profile.mapFilters.autoTrackNearest) then return end

    local target = self.currentTarget
    
    
    if target.i == itemID and target.c == c and target.z == z then
        local dx = (target.xy.x or 0) - x
        local dy = (target.xy.y or 0) - y
        if (dx*dx + dy*dy) < LOOT_DISTANCE_THRESHOLD_SQ then            
            self.manualTarget = nil 
            self:UpdateArrow(true) 
        end
    end
end

function Arrow:OnPlayerLogin()
    if L.db and L.db.profile and L.db.profile.mapFilters and L.db.profile.mapFilters.autoTrackNearest then        
        self:Show()
    end
end

function Arrow:OnInitialize()
if L.LEGACY_MODE_ACTIVE then return end
    self:RegisterMessage("LOOTCOLLECTOR_PLAYER_LOOTED_ITEM", "OnPlayerLootedItem")
    self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")
    
end

function Arrow:StartUpdates() if not Arrow_updateFrame then Arrow_updateFrame=CreateFrame("Frame"); Arrow_updateFrame:SetScript("OnUpdate",function(_,e) Arrow.elapsed=Arrow.elapsed+e; if Arrow.elapsed>=UPDATE_INTERVAL then Arrow.elapsed=0; Arrow:UpdateArrow()end end)end end
function Arrow:StopUpdates() if Arrow_updateFrame then Arrow_updateFrame:SetScript("OnUpdate",nil)end; Arrow.elapsed=0 end

function Arrow:NavigateTo(discovery)
    if not IsTomTomAvailable()then print("|cffff7f00LootCollector:|r TomTom not available."); self.enabled=false; return end
    self.enabled=true; self.manualTarget=discovery; self:UpdateArrow(true); self:StartUpdates()
end
function Arrow:Show() if not IsTomTomAvailable()then print("|cffff7f00LootCollector:|r TomTom not available."); self.enabled=false; return end; self.enabled=true; self.manualTarget=nil; self:UpdateArrow(true); self:StartUpdates() end
function Arrow:Hide() self.enabled=false; self.manualTarget=nil; self.currentTarget=nil; self:StopUpdates(); self:ClearTomTomWaypoint() end
function Arrow:Toggle() if self.enabled then self:Hide() else self:Show() end end

function Arrow:SlashCommandHandler(msg)
    msg = msg or ""
    if msg == "clearskip" then
        self:ClearSessionSkipList()
    else
        self:Toggle()
    end
end

function Arrow:ClearTomTomWaypoint() if self.tomtomUID then TT_RemoveWaypoint(self.tomtomUID); self.tomtomUID=nil; TT_ClearCrazyArrow() end end

function Arrow:FindBestTarget()
    local db = L.db and L.db.global and L.db.global.discoveries; if not db then self.currentTarget=nil; return end
    
    local filters = L:GetFilters()
    if filters.hideAll then self.currentTarget=nil; return end
    
    local px,py=self:GetPlayerPos(); if not px or not py then self.currentTarget=nil; return end
    local currentContinent, currentZoneID = self:GetPlayerLocation()
    local bestTarget, minDist = nil, -1
    
    
    local autoTrackUnlooted = L.db.profile.mapFilters.autoTrackNearest

    for guid, d in pairs(db) do
        
        if not self.sessionSkipList[guid] then
            if type(d) == "table" and d.c == currentContinent and d.z == currentZoneID and d.xy and L:DiscoveryPassesFilters(d) then
                if not (autoTrackUnlooted and L:IsLootedByChar(guid)) then
                    if d.onHold and not isMine(d) then
                        
                        
                    else
                        local tx,ty = d.xy.x or 0, d.xy.y or 0
                        local dx,dy = tx-px, ty-py
                        local dist = dx*dx + dy*dy
                        if minDist == -1 or dist < minDist then
                            minDist = dist; bestTarget = d
                        end
                    end
                end
            end
        end
    end
    self.currentTarget = bestTarget
end

function Arrow:UpdateArrow(forceUpdate)
    if not self.enabled or not IsTomTomAvailable() then return end

    
    if self.manualTarget and self.tomtomUID then
        local dist = TT_GetDistanceToWaypoint(self.tomtomUID)
        if dist and dist < ARRIVAL_DISTANCE_YARDS then
            print("|cff00ff00LootCollector:|r Arrived at manual destination. Switching to auto-navigation.")
            self.manualTarget = nil
            self:ClearTomTomWaypoint()
            forceUpdate = true 
        end
    end

    local oldTargetGUID = self.currentTarget and self.currentTarget.g
    local targetThisUpdate
    
    if self.manualTarget then
        targetThisUpdate = self.manualTarget
    else
        self:FindBestTarget()
        targetThisUpdate = self.currentTarget
    end

    
    local autoTrackMode = L.db.profile.mapFilters.autoTrackNearest
    if autoTrackMode and not self.manualTarget and targetThisUpdate then
        local px, py = self:GetPlayerPos()
        if px and py then
            local dx = (targetThisUpdate.xy.x or 0) - px
            local dy = (targetThisUpdate.xy.y or 0) - py
            
            if (dx*dx + dy*dy) < (0.005 * 0.005) then
                
                
                
                self:ClearTomTomWaypoint()
                return
            end
        end
    end
    
    local newTargetGUID = targetThisUpdate and targetThisUpdate.g
    if not forceUpdate and newTargetGUID == oldTargetGUID then return end

    self.currentTarget = targetThisUpdate
    self:ClearTomTomWaypoint()

    if self.currentTarget then
        local d = self.currentTarget
        local mapC = d.c
        local mapZ = d.z
        local x = d.xy and d.xy.x or 0
        local y = d.xy and d.xy.y or 0
        local itemName = (d.il and d.il:match("%[(.+)%]")) or "Discovery"

        self.tomtomUID = TT_AddZWaypoint(mapC, mapZ, x, y, itemName)
        if self.tomtomUID then TT_SetCrazyArrow(self.tomtomUID, itemName) end
    end
end

function Arrow:ClearTarget()
    self:ClearTomTomWaypoint()
    self.currentTarget = nil
    self.manualTarget = nil        
end
    

function Arrow:CanNavigateRecord(rec)
    if not rec then
        return false
    end
    
    if rec.onHold and not isMine(rec) then
        return false
    end

    
    if not (rec.xy and rec.xy.x and rec.xy.y) then
        return false
    end
    return true
end

local function resolveZoneName(rec)
    local c  = tonumber(rec.c) or 0
    local z  = tonumber(rec.z) or 0
    local iz = tonumber(rec.iz) or 0
    if L.ResolveZoneDisplay then
        return L:ResolveZoneDisplay(c, z, iz)
    end
    
    local ZoneList = L:GetModule("ZoneList", true)
    if ZoneList then
        if z == 0 and iz > 0 and ZoneList.ResolveIz then
            return ZoneList:ResolveIz(iz) or (GetRealZoneText() or "Unknown Instance")
        end
        if ZoneList.GetZoneName then
            return ZoneList:GetZoneName(c, z, nil, iz) 
        end
    end
    if z == 0 and iz > 0 then
        return GetRealZoneText() or "Unknown Instance"
    end
    return "Unknown Zone"
end

function Arrow:PointToRecordV5(rec)
    if not self or not self.CanNavigateRecord then return false end
    if not self:CanNavigateRecord(rec) then
        if rec and rec.mid and self.currentTarget and self.currentTarget.mid == rec.mid then
            if self.ClearTarget then
                self:ClearTarget()
            else
                self.enabled = false
            end
        end
        return false
    end

    
    self.manualTarget = {
        mid   = rec.mid,
        i     = rec.i,
        il    = rec.il,
        xy    = rec.xy,
        c     = rec.c,
        z     = rec.z,
        iz    = tonumber(rec.iz) or 0,
        label = resolveZoneName(rec),
    }

    self.enabled = true

    if self.UpdateArrow then
        self:UpdateArrow(true)
        return true
    end

    return false
end

function Arrow:ClearIfOnHold(rec)
    if not rec or not rec.mid then return end
    if not self or not self.currentTarget or self.currentTarget.mid ~= rec.mid then
        return
    end
    if rec.onHold and not isMine(rec) then
        if self.ClearTarget then
            self:ClearTarget()
        else
            self.enabled = false
            self.currentTarget = nil
        end
    end
end

return Arrow
-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl