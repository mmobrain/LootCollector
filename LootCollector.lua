local AceAddon     = LibStub("AceAddon-3.0")
local AceEvent     = LibStub("AceEvent-3.0")
local AceComm      = LibStub("AceComm-3.0")
local AceDB        = LibStub("AceDB-3.0")

local LootCollector = AceAddon:NewAddon("LootCollector", "AceEvent-3.0", "AceComm-3.0")
_G.LootCollector = LootCollector

LootCollector.addonPrefix = "BBLCAM25"
LootCollector.chatChannel = "BBLCC25"

-- Centralized item ignore lists
LootCollector.ignoreList = {
    ["Embossed Mystic Scroll"] = true,
    ["Unimbued Mystic Scroll"] = true,
    ["Untapped Mystic Scroll"] = true,
    ["Felforged Mystic Scroll: Unlock Uncommon"] = true,
    ["Felforged Mystic Scroll: Unlock Rare"] = true,
    ["Felforged Mystic Scroll: Unlock Legendary"] = true,
    ["Felforged Mystic Scroll: Unlock Epic"] = true,
    ["Enigmatic Mystic Scroll"] = true,
}

LootCollector.sourceSpecificIgnoreList = {
    ["Mystic Scroll: White Walker"] = true,
    ["Mystic Scroll: Powder Mage"] = true,
    ["Mystic Scroll: Midnight Flames"] = true,
    ["Mystic Scroll: Lucifur"] = true,
    ["Mystic Scroll: Knight of the Eclipse"] = true,
    ["Mystic Scroll: Hoplite"] = true,
    ["Mystic Scroll: Fire Watch"] = true,
    ["Mystic Scroll: Eskimo"] = true,
    ["Mystic Scroll: Dark Surgeon"] = true,
    ["Mystic Scroll: Cauterizing Fire"] = true,
    ["Mystic Scroll: Blood Venom"] = true,
    ["Mystic Scroll: Ancestral Ninja"] = true,
}

-- Version key for the optional database. Change this if you update db.lua. 
local OPTIONAL_DB_VERSION = "v1"

-- Static Popup definition 
StaticPopupDialogs["LOOTCOLLECTOR_OPTIONAL_DB_IMPORT"] = {
  text = "LootCollector has detected a starter database of discoveries. Would you like to merge it with your existing data?\n\nThis can be done later from the 'Discoveries' panel in the addon's options.",
  button1 = "Yes, Merge",
  button2 = "No, Thanks",
  OnAccept = function()
    local ImportExport = LootCollector:GetModule("ImportExport", true)
    if ImportExport and ImportExport.ApplyImportString then
        ImportExport:ApplyImportString(_G.LootCollector_OptionalDB, "MERGE", false)
    end
    -- Set the flag so we don't ask again for this version
    if LootCollector.db then
        LootCollector.db.profile.offeredOptionalDB = OPTIONAL_DB_VERSION
    end
  end,
  OnCancel = function()
    -- Set the flag even on cancel to make it a one-time offer
    if LootCollector.db then
        LootCollector.db.profile.offeredOptionalDB = OPTIONAL_DB_VERSION
    end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
  showAlert = true,
}

local dbDefaults = {
    profile = {
        enabled = true,
        paused = false,
        offeredOptionalDB = nil, -- Flag for one-time offer
        minQuality = 2,
        checkOnlySingleItemLoot = true,
        mapFilters = { hideAll = false, hideFaded = false, hideStale = false, hideLooted = false, pinSize = 16, },
        toasts = { enabled = true, },
        sharing = { enabled = true, anonymous = false, delayed = false, delaySeconds = 30, pauseInHighRisk = false, },
        chatDebug = false,
        chatEncode = true,
        ignoreZones = {},
        decay = { fadeAfterDays  = 30, staleAfterDays = 90, },
        discoveries = nil,
        _schemaVersion = 0,
    },
    char = { looted = {}, hidden = {}, },
    global = { discoveries = {}, _schemaVersion = 0, },
}

function LootCollector:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("LootCollectorDB_Asc", dbDefaults, true)
    self.name = "LootCollector"
    self.Version = "0.4.9-alpha-nr"

    self.pauseQueue = { incoming = {}, outgoing = {} }
    self.notifiedNewVersion = nil

    self.db.global.discoveries = self.db.global.discoveries or {}
    self.db.char.looted = self.db.char.looted or {}
    self.db.char.hidden = self.db.char.hidden or {}

    -- Check if we should offer the optional DB import
    if _G.LootCollector_OptionalDB and self.db.profile.offeredOptionalDB ~= OPTIONAL_DB_VERSION then
        -- Use a timer to ensure the popup doesn't appear too early during a chaotic login
        C_Timer.After(5, function()
            StaticPopup_Show("LOOTCOLLECTOR_OPTIONAL_DB_IMPORT")
        end)
    end

    SLASH_LootCollectorARROW1 = "/lcarrow"
    SlashCmdList["LootCollectorARROW"] = function()
        local Arrow = self:GetModule("Arrow", true)
        if Arrow and Arrow.ToggleCommand then Arrow:ToggleCommand() else print("|cffff7f00LootCollector:|r Arrow module not available.") end
    end

    SLASH_LootCollectorMAINTENANCE1 = "/lcfix"
    SlashCmdList["LootCollectorMAINTENANCE"] = function()
        local ZoneResolver = self:GetModule("ZoneResolver", true)
        if ZoneResolver and ZoneResolver.UpdateAllContinentAndZoneIDs then 
            ZoneResolver:UpdateAllContinentAndZoneIDs() 
        else 
            print("|cffff7f00LootCollector:|r ZoneResolver module not available.") 
        end
    end
end

function LootCollector:IsPaused()
    return self.db and self.db.profile.paused
end

function LootCollector:ProcessPauseQueues()
    if self:IsPaused() then return end
    local Core = self:GetModule("Core", true); local Comm = self:GetModule("Comm", true); if not Core or not Comm then return end
    local incomingCount = #self.pauseQueue.incoming; for _, discoveryData in ipairs(self.pauseQueue.incoming) do Core:AddDiscovery(discoveryData, true) end; self.pauseQueue.incoming = {}
    local outgoingCount = #self.pauseQueue.outgoing; for _, discoveryData in ipairs(self.pauseQueue.outgoing) do Comm:_BroadcastNow(discoveryData) end; self.pauseQueue.outgoing = {}
    if (incomingCount + outgoingCount) > 0 then print(string.format("|cff00ff00LootCollector:|r Processed %d incoming and %d outgoing queued messages.", incomingCount, outgoingCount)); local Map = self:GetModule("Map", true); if Map and Map.Update then Map:Update() end end
end

function LootCollector:TogglePause()
    if not (self.db and self.db.profile) then return end
    self.db.profile.paused = not self.db.profile.paused
    if self.db.profile.paused then print("|cffff7f00LootCollector:|r Processing is now |cffff0000PAUSED|r. Messages will be queued.") else print("|cff00ff00LootCollector:|r Processing is now |cff00ff00RESUMED|r."); self:ProcessPauseQueues() end
end

function LootCollector:IsZoneIgnored()
    if not (self.db and self.db.profile and self.db.profile.ignoreZones) then return false end
    local zoneName = GetRealZoneText()
    return zoneName and self.db.profile.ignoreZones[zoneName]
end

function LootCollector:DelayedChannelInit()
    if not (self.db and self.db.profile.sharing.enabled) or self:IsZoneIgnored() then return end
    local Comm = self:GetModule("Comm", true); if not Comm then return end
    local DELAY_SECONDS = 5.0; if Comm.verbose then print(string.format("[%s-Debug] PLAYER_ENTERING_WORLD fired. Waiting %s seconds to initialize channel.", self.name, DELAY_SECONDS)) end
    local timerFrame = CreateFrame("Frame", "LootCollectorChannelTimer"); local elapsed = 0; timerFrame:SetScript("OnUpdate", function(_, e) elapsed = elapsed + e; if elapsed >= DELAY_SECONDS then timerFrame:SetScript("OnUpdate", nil); Comm:JoinPublicChannel(false) end end)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

function LootCollector:OnEnable()
    local Core = self:GetModule("Core", true); if Core then self:RegisterEvent("LOOT_OPENED", function() Core:OnLootOpened() end) end
    local Map = self:GetModule("Map", true); if Map then self:RegisterEvent("WORLD_MAP_UPDATE", function() if WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end end) end
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "DelayedChannelInit")
end

function LootCollector:OnDisable()
    self:UnregisterAllEvents()
end
