-- Arrow.lua
-- Refactored to integrate with TomTom as an optional dependency.
-- This module now acts as a controller, creating and managing TomTom
-- waypoints instead of rendering its own arrow. Now supports a manual
-- target override from the map UI.

local L = LootCollector
local Arrow = L:NewModule("Arrow")

-- Constants and State
local UPDATE_INTERVAL = 2.0
local ARRIVAL_DISTANCE_YARDS = 15 -- Distance to consider "arrived"
local Arrow_updateFrame = nil
Arrow.elapsed = 0

Arrow.currentTarget = nil -- The target currently being pointed to
Arrow.manualTarget = nil  -- A sticky target set by the user (e.g., from the map)
Arrow.tomtomUID = nil
Arrow.enabled = false -- Tracks if the user wants the arrow active

-- Status Constants (for filters)
local STATUS_UNCONFIRMED, STATUS_CONFIRMED, STATUS_FADING, STATUS_STALE =
  "UNCONFIRMED", "CONFIRMED", "FADING", "STALE"

-----------------------------------------------------------------------
-- TomTom API Wrappers (Safe Calls)
-----------------------------------------------------------------------

local function IsTomTomAvailable()
    return _G.TomTomAddZWaypoint or (_G.TomTom and _G.TomTom.AddZWaypoint)
end

local function TT_AddZWaypoint(c, z, x, y, desc)
    if not IsTomTomAvailable() then return end
    x, y = (x or 0) * 100, (y or 0) * 100
    if _G.TomTom and _G.TomTom.AddZWaypoint then
        return TomTom:AddZWaypoint(c, z, x, y, desc, false, true, true, nil, true, false)
    elseif _G.TomTomAddZWaypoint then
        return TomTomAddZWaypoint(c, z, x, y, desc, false, true, true, nil, true, false)
    end
end

local function TT_RemoveWaypoint(uid)
    if not uid or not IsTomTomAvailable() then return end
    if _G.TomTom and _G.TomTom.RemoveWaypoint then
        TomTom:RemoveWaypoint(uid)
    elseif _G.TomTomRemoveWaypoint then
        TomTomRemoveWaypoint(uid)
    end
end

local function TT_SetCrazyArrow(uid, title)
    if not IsTomTomAvailable() then return end
    if _G.TomTom and _G.TomTom.SetCrazyArrow then
        TomTom:SetCrazyArrow(uid, ARRIVAL_DISTANCE_YARDS, title)
    elseif _G.TomTomSetCrazyArrow then
        TomTomSetCrazyArrow(uid, ARRIVAL_DISTANCE_YARDS, title)
    end
end

local function TT_ClearCrazyArrow()
    if not IsTomTomAvailable() then return end
    if _G.TomTom and _G.TomTom.SetCrazyArrow then
        TomTom:SetCrazyArrow(nil)
    elseif _G.TomTomSetCrazyArrow then
        TomTomSetCrazyArrow(nil)
    end
end

local function TT_GetDistanceToWaypoint(uid)
    if not uid or not IsTomTomAvailable() then return nil end
    if _G.TomTom and _G.TomTom.GetDistanceToWaypoint then
        return TomTom:GetDistanceToWaypoint(uid)
    elseif _G.TomTomGetDistanceToWaypoint then
        return TomTomGetDistanceToWaypoint(uid)
    end
end

-----------------------------------------------------------------------
-- Filter and Map Helpers
-----------------------------------------------------------------------

local function getFilters()
  local p = L.db and L.db.profile
  local f = (p and p.mapFilters) or {}
  if f.hideAll == nil then f.hideAll = false end
  if f.hideFaded == nil then f.hideFaded = false end
  if f.hideStale == nil then f.hideStale = false end
  return f
end

local function statusOf(d)
  local s = d and d.status or STATUS_UNCONFIRMED
  if s == STATUS_UNCONFIRMED or s == STATUS_CONFIRMED or s == STATUS_FADING or s == STATUS_STALE then return s end
  return STATUS_UNCONFIRMED
end

local function passesFilters(d)
  local f = getFilters()
  if f.hideAll then return false end
  local s = statusOf(d)
  if s == STATUS_FADING and f.hideFaded then return false end
  if s == STATUS_STALE and f.hideStale then return false end
  return true
end

local function SaveMapState()
  return GetCurrentMapContinent and GetCurrentMapContinent() or 0,
         GetCurrentMapZone and GetCurrentMapZone() or 0,
         GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or 0
end

local function RestoreMapState(c, z, dl)
  if SetMapZoom and c and z then SetMapZoom(c, z) end
  if SetDungeonMapLevel and dl then SetDungeonMapLevel(dl) end
end

function Arrow:GetPlayerPos()
    local mapOpen = WorldMapFrame and WorldMapFrame:IsShown()
    local sc, sz, sdl
    if not mapOpen then sc, sz, sdl = SaveMapState(); if SetMapToCurrentZone then SetMapToCurrentZone() end end
    local px, py = GetPlayerMapPosition("player")
    if not mapOpen then RestoreMapState(sc, sz, sdl) end
    return px, py
end

function Arrow:GetPlayerZoneIdNormalized()
    local mapOpen = WorldMapFrame and WorldMapFrame:IsShown()
    local sc, sz, sdl
    if not mapOpen then sc, sz, sdl = SaveMapState(); if SetMapToCurrentZone then SetMapToCurrentZone() end end
    local z = GetCurrentMapZone and GetCurrentMapZone() or 0
    if not mapOpen then RestoreMapState(sc, sz, sdl) end
    return z
end

function Arrow:EnsureDiscoveryLayer(d)
    if d.mapC and d.mapZ then return end
    d.mapC, d.mapZ = GetCurrentMapContinent(), GetCurrentMapZone()
end

-----------------------------------------------------------------------
-- Core Logic
-----------------------------------------------------------------------

function Arrow:OnInitialize() end

function Arrow:StartUpdates()
    if not Arrow_updateFrame then
        Arrow_updateFrame = CreateFrame("Frame")
        Arrow_updateFrame:SetScript("OnUpdate", function(_, elapsed)
            Arrow.elapsed = Arrow.elapsed + elapsed
            if Arrow.elapsed >= UPDATE_INTERVAL then
                Arrow.elapsed = 0
                Arrow:UpdateArrow()
            end
        end)
    end
end

function Arrow:StopUpdates()
    if Arrow_updateFrame then Arrow_updateFrame:SetScript("OnUpdate", nil) end
    Arrow.elapsed = 0
end

function Arrow:NavigateTo(discovery)
    if not IsTomTomAvailable() then
        print("|cffff7f00LootCollector:|r TomTom addon is not installed or enabled. Arrow navigation is unavailable.")
        self.enabled = false
        return
    end
    self.enabled = true
    self.manualTarget = discovery
    self:UpdateArrow(true)
    self:StartUpdates()
end

function Arrow:Show() -- Auto mode
    if not IsTomTomAvailable() then
        print("|cffff7f00LootCollector:|r TomTom addon is not installed or enabled. Arrow navigation is unavailable.")
        self.enabled = false
        return
    end
    self.enabled = true
    self.manualTarget = nil
    self:UpdateArrow(true)
    self:StartUpdates()
end

function Arrow:Hide()
    self.enabled = false
    self.manualTarget = nil
    self.currentTarget = nil
    self:StopUpdates()
    self:ClearTomTomWaypoint()
end

function Arrow:Toggle()
    if self.enabled then self:Hide() else self:Show() end
end

function Arrow:ToggleCommand()
    self:Toggle()
end

function Arrow:ClearTomTomWaypoint()
    if self.tomtomUID then
        TT_RemoveWaypoint(self.tomtomUID)
        self.tomtomUID = nil
        TT_ClearCrazyArrow()
    end
end

function Arrow:FindBestTarget()
  local db = L.db and L.db.global and L.db.global.discoveries
  if not db then self.currentTarget = nil; return end

  local f = getFilters()
  if f.hideAll then self.currentTarget = nil; return end

  local px, py = self:GetPlayerPos()
  if not px or not py or (px == 0 and py == 0) then self.currentTarget = nil; return end
  local currentZoneID = self:GetPlayerZoneIdNormalized()

  local bestTarget, minDist = nil, -1

  for _, d in pairs(db) do
    repeat
      if not d or not d.coords then break end
      if d.zoneID ~= currentZoneID then break end
      if d.lootedByMe or not passesFilters(d) then break end
      
      local tx, ty = d.coords.x or 0, d.coords.y or 0
      local dx, dy = tx - px, ty - py
      local dist = dx*dx + dy*dy
      if minDist == -1 or dist < minDist then
        minDist = dist
        bestTarget = d
      end
    until true
  end

  self.currentTarget = bestTarget
end

function Arrow:UpdateArrow(forceUpdate)
    if not self.enabled or not IsTomTomAvailable() then return end

    if self.manualTarget and self.tomtomUID then
        local dist = TT_GetDistanceToWaypoint(self.tomtomUID)
        if dist and dist < ARRIVAL_DISTANCE_YARDS then
            print("|cff00ff00LootCollector:|r Arrived at destination. Switching to auto-navigation.")
            self.manualTarget = nil
        end
    end

    local oldTargetGUID = self.currentTarget and self.currentTarget.guid
    local targetThisUpdate

    if self.manualTarget then
        targetThisUpdate = self.manualTarget
    else
        self:FindBestTarget()
        targetThisUpdate = self.currentTarget
    end

    local newTargetGUID = targetThisUpdate and targetThisUpdate.guid
    if not forceUpdate and newTargetGUID == oldTargetGUID then return end

    self.currentTarget = targetThisUpdate
    self:ClearTomTomWaypoint()

    if self.currentTarget then
        local d = self.currentTarget
        self:EnsureDiscoveryLayer(d)

        local mapC = d.mapC
        local mapZ = d.mapZ
        local x = d.coords and d.coords.x or 0
        local y = d.coords and d.coords.y or 0
        local itemName = (d.itemLink and d.itemLink:match("%[(.+)%]")) or "Discovery"

        self.tomtomUID = TT_AddZWaypoint(mapC, mapZ, x, y, itemName)
        if self.tomtomUID then TT_SetCrazyArrow(self.tomtomUID, itemName) end
    end
end

return Arrow