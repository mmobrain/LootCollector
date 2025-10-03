local AceAddon     = LibStub("AceAddon-3.0")
local AceEvent     = LibStub("AceEvent-3.0")
local AceComm      = LibStub("AceComm-3.0")
local AceDB        = LibStub("AceDB-3.0")

local LootCollector = AceAddon:NewAddon("LootCollector", "AceEvent-3.0", "AceComm-3.0")
_G.LootCollector = LootCollector

-- Shared constants used by Comm and others
LootCollector.addonPrefix = "BBLCAM25"  -- AceComm prefix for group/guild/whisper comms
LootCollector.chatChannel = "BBLCC25"   -- Hidden public chat channel name for world-scale sharing

-- SavedVariables: LootCollectorDB_Asc (AceDB scopes: profile, char, global)
local dbDefaults = {
    profile = {
        enabled = true,
        paused = false,
        
        -- Detection filters
        minQuality = 2,
        checkOnlySingleItemLoot = true,

        -- Visibility filters (Map/Arrow)
        mapFilters = {
            hideAll   = false,
            hideFaded = false,
            hideStale = false,
            hideLooted = false,
            pinSize   = 16, -- Icon size setting
        },
        
        -- Toast notifications
        toasts = {
            enabled = true,
        },
        
        -- Sharing master toggle (Comm + DBSync)
        sharing = {
            enabled = true,
            anonymous = false,
            delayed = false,
            delaySeconds = 30,
            pauseInHighRisk = false,
        },

        -- Toggle for addon channel message visibility
        chatDebug = false,
        chatEncode = true, -- NEW: Toggle for payload encoding

        -- NEW: Ignored Zones
        ignoreZones = {},

        -- Time-based decay thresholds (days)
        decay = {
            fadeAfterDays  = 30,
            staleAfterDays = 90,
        },

        -- Legacy (migrated on first run)
        discoveries = nil,
        _schemaVersion = 0,
    },

    -- Per-character overlays (completion/visibility)
    char = {
        looted = {},  -- [guid] = timestamp
        hidden = {},  -- [guid] = true
    },

    -- Account-wide canonical discoveries shared by all characters
    global = {
        discoveries = {}, -- [guid] = discovery record (no per-character flags)
        _schemaVersion = 0,
    },
}

function LootCollector:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("LootCollectorDB_Asc", dbDefaults, true)
    self.name = "LootCollector"

    -- NEW: Session-only queue for paused state
    self.pauseQueue = {
        incoming = {},
        outgoing = {}
    }

    self.db.global.discoveries = self.db.global.discoveries or {}
    self.db.char.looted = self.db.char.looted or {}
    self.db.char.hidden = self.db.char.hidden or {}

    SLASH_LootCollectorARROW1 = "/lcarrow"
    SlashCmdList["LootCollectorARROW"] = function()
        local Arrow = self:GetModule("Arrow", true)
        if Arrow and Arrow.ToggleCommand then
            Arrow:ToggleCommand()
        else
            print("|cffff7f00LootCollector:|r Arrow module not available.")
        end
    end
end

-- NEW: Helper to check pause state
function LootCollector:IsPaused()
    return self.db and self.db.profile.paused
end

-- NEW: Function to process queued messages
function LootCollector:ProcessPauseQueues()
    if self:IsPaused() then return end

    local Core = self:GetModule("Core", true)
    local Comm = self:GetModule("Comm", true)
    if not Core or not Comm then return end

    local incomingCount = #self.pauseQueue.incoming
    for _, discoveryData in ipairs(self.pauseQueue.incoming) do
        Core:AddDiscovery(discoveryData, true)
    end
    self.pauseQueue.incoming = {}

    local outgoingCount = #self.pauseQueue.outgoing
    for _, discoveryData in ipairs(self.pauseQueue.outgoing) do
        Comm:_BroadcastNow(discoveryData)
    end
    self.pauseQueue.outgoing = {}

    if (incomingCount + outgoingCount) > 0 then
        print(string.format("|cff00ff00LootCollector:|r Processed %d incoming and %d outgoing queued messages.", incomingCount, outgoingCount))
        local Map = self:GetModule("Map", true)
        if Map and Map.Update then Map:Update() end
    end
end

-- NEW: Central function to toggle pause state
function LootCollector:TogglePause()
    if not (self.db and self.db.profile) then return end
    self.db.profile.paused = not self.db.profile.paused
    
    if self.db.profile.paused then
        print("|cffff7f00LootCollector:|r Processing is now |cffff0000PAUSED|r. Messages will be queued.")
    else
        print("|cff00ff00LootCollector:|r Processing is now |cff00ff00RESUMED|r.")
        self:ProcessPauseQueues()
    end
end


-- Central function to check if the current zone is ignored
function LootCollector:IsZoneIgnored()
    if not (self.db and self.db.profile and self.db.profile.ignoreZones) then return false end
    local zoneName = GetRealZoneText()
    return zoneName and self.db.profile.ignoreZones[zoneName]
end

function LootCollector:DelayedChannelInit()
    -- Gate the entire function on the sharing setting AND ignored zone
    if not (self.db and self.db.profile.sharing.enabled) or self:IsZoneIgnored() then return end

    local Comm = self:GetModule("Comm", true)
    if not Comm then return end
    
    local DELAY_SECONDS = 5.0 

    if Comm.verbose then print(string.format("[%s-Debug] PLAYER_ENTERING_WORLD fired. Waiting %s seconds to initialize channel.", self.name, DELAY_SECONDS)) end

    -- Use a temporary frame to manage the timed delay safely.
    local timerFrame = CreateFrame("Frame", "LootCollectorChannelTimer")
    local elapsed = 0
    timerFrame:SetScript("OnUpdate", function(_, e)
        elapsed = elapsed + e
        if elapsed >= DELAY_SECONDS then
            timerFrame:SetScript("OnUpdate", nil)
            -- Call the specialized join function
            Comm:JoinPublicChannel(false) 
        end
    end)
    
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

function LootCollector:OnEnable()
    -- Register all persistent events here.
    local Core = self:GetModule("Core", true)
    if Core then self:RegisterEvent("LOOT_OPENED", function() Core:OnLootOpened() end) end

    local Map = self:GetModule("Map", true)
    if Map then self:RegisterEvent("WORLD_MAP_UPDATE", function() if WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end end) end

    -- This event now fires every time the player enters the world (e.g., after any loading screen).
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "DelayedChannelInit")
end

function LootCollector:OnDisable()
    -- Unregister all events to be clean.
    self:UnregisterAllEvents()
end