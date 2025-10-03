-- Settings.lua
-- Exposes configurable options via AceConfig-3.0, with safe slash-command fallbacks.

local L = LootCollector
local Settings = L:NewModule("Settings")

-- Libs are optional; fall back to slash if missing
local AceConfig       = LibStub and LibStub("AceConfig-3.0", true)
local AceConfigDialog = LibStub and LibStub("AceConfigDialog-3.0", true)

local function ensureDefaults()
    if not (L.db and L.db.profile) then return end
    local p = L.db.profile
    
    p.sharing = p.sharing or {}
    if p.sharing.enabled == nil then p.sharing.enabled = true end
    if p.sharing.anonymous == nil then p.sharing.anonymous = false end
    if p.sharing.delayed == nil then p.sharing.delayed = false end
    if p.sharing.delaySeconds == nil then p.sharing.delaySeconds = 30 end
    if p.sharing.pauseInHighRisk == nil then p.sharing.pauseInHighRisk = false end
end

local function refreshUI()
    local Map = L:GetModule("Map", true)
    if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
        Map:Update()
    end
    local Arrow = L:GetModule("Arrow", true)
    if Arrow and Arrow.frame and L.db and L.db.profile and L.db.profile.mapFilters and L.db.profile.mapFilters.hideAll then
        Arrow.frame:Hide()
    end
end

-- NEW: Function to handle the /lctop command logic
local function ShowTopContributors()
    if not (L.db and L.db.global and L.db.global.discoveries) then
        print("|cffff7f00LootCollector:|r Database not found.")
        return
    end

    local counts = {}
    -- 1. Count contributions for each player
    for guid, discovery in pairs(L.db.global.discoveries) do
        if discovery and discovery.foundBy_player and type(discovery.foundBy_player) == "string" and discovery.foundBy_player ~= "" then
            local name = discovery.foundBy_player
            -- We don't want to count anonymous contributions as a single user
            if name ~= "An Unnamed Collector" then
                counts[name] = (counts[name] or 0) + 1
            end
        end
    end

    -- 2. Convert the counts map to a sortable list
    local sortedList = {}
    for name, count in pairs(counts) do
        table.insert(sortedList, { name = name, count = count })
    end

    if #sortedList == 0 then
        print("|cffffff00--- LootCollector: Top Contributors ---|r")
        print("No contributions found in the database.")
        return
    end

    -- 3. Sort the list by count, descending
    table.sort(sortedList, function(a, b)
        return a.count > b.count
    end)

    -- 4. Print the top 10 results
    print("|cffffff00--- LootCollector: Top Contributors ---|r")
    for i = 1, math.min(10, #sortedList) do
        local entry = sortedList[i]
        print(string.format("#%d. |cffffff00%s|r - %d discoveries", i, entry.name, entry.count))
    end
end

local function buildOptions()
    local opts = {
        type = "group",
        name = "LootCollector",
        args = {
            header = { type = "header", name = "LootCollector Settings", order = 0 },
            desc   = { type = "description", name = "Configure visibility filters, discovery toasts, and network sharing.", order = 1 },
            visibility = {
                type = "group", name = "Visibility", inline = true, order = 10,
                args = {
                    hideAll = { type = "toggle", name = "Hide All", order = 1, get = function() return L.db.profile.mapFilters.hideAll end, set = function(_, val) L.db.profile.mapFilters.hideAll = val; refreshUI() end, },
                    hideFaded = { type = "toggle", name = "Hide Faded", order = 2, get = function() return L.db.profile.mapFilters.hideFaded end, set = function(_, val) L.db.profile.mapFilters.hideFaded = val; refreshUI() end, },
                    hideStale = { type = "toggle", name = "Hide Stale", order = 3, get = function() return L.db.profile.mapFilters.hideStale end, set = function(_, val) L.db.profile.mapFilters.hideStale = val; refreshUI() end, },
                    hideLooted = { type = "toggle", name = "Hide Looted", desc = "Hide discoveries already looted by this character.", order = 4, get = function() return L.db.profile.mapFilters.hideLooted end, set = function(_, val) L.db.profile.mapFilters.hideLooted = val; refreshUI() end, },
                    pinSizeSlider = {
                        type = "range", name = "Map Icon Size",
                        desc = "Adjust the size of the discovery icons on the world map.",
                        order = 5,
                        min = 8, max = 32, step = 1,
                        get = function() return L.db.profile.mapFilters.pinSize end,
                        set = function(_, val) L.db.profile.mapFilters.pinSize = val; refreshUI() end,
                    },
                },
            },
            behavior = {
                type = "group", name = "Behavior & Sharing", inline = true, order = 20,
                args = {
                    showToasts = { type = "toggle", name = "Show Toasts", desc = "Show toast notifications for discoveries received from other players.", order = 1, get = function() return L.db.profile.toasts.enabled end, set = function(_, val) L.db.profile.toasts.enabled = val end, },
                    sharing = {
                        type = "toggle", name = "Enable Sharing",
                        desc = "Allow network sharing with other players. Disabling this will leave the global channel.",
                        order = 10,
                        get = function() return L.db.profile.sharing.enabled end,
                        set = function(_, val)
                            L.db.profile.sharing.enabled = val
                            local Comm = L:GetModule("Comm", true)
                            if Comm then
                                if val then Comm:JoinPublicChannel(true) else Comm:LeavePublicChannel() end
                            end
                        end,
                    },
                    nameless = {
                        type = "toggle", name = "Nameless Sharing",
                        desc = "When sharing a discovery, your name will be replaced with 'An Unnamed Collector'.",
                        order = 11,
                        disabled = function() return not L.db.profile.sharing.enabled end,
                        get = function() return L.db.profile.sharing.anonymous end,
                        set = function(_, val) L.db.profile.sharing.anonymous = val end,
                    },
                    delayed = {
                        type = "toggle", name = "Delayed Sharing",
                        desc = "Wait a configured amount of time before broadcasting a new discovery.",
                        order = 12,
                        disabled = function() return not L.db.profile.sharing.enabled end,
                        get = function() return L.db.profile.sharing.delayed end,
                        set = function(_, val) L.db.profile.sharing.delayed = val end,
                    },
                    delaySlider = {
                        type = "range", name = "Sharing Delay",
                        desc = "Number of seconds to wait before broadcasting.",
                        order = 13,
                        min = 15, max = 60, step = 1,
                        disabled = function() return not L.db.profile.sharing.enabled or not L.db.profile.sharing.delayed end,
                        get = function() return L.db.profile.sharing.delaySeconds end,
                        set = function(_, val) L.db.profile.sharing.delaySeconds = val end,
                    },
                    pauseHighRisk = {
                        type = "toggle", name = "Pause in High-Risk (Soon™)",
                        desc = "Automatically pause sharing when in High-Risk zones or arenas. (This feature is not yet implemented.)",
                        order = 20,
                        disabled = true, -- Always disabled
                        get = function() return false end,
                        set = function() end, -- Do nothing
                    },
                },
            },
        },
    }
    return opts
end

function Settings:OnInitialize()
    if not (L.db and L.db.profile) then return end
    ensureDefaults()

    if AceConfig and AceConfigDialog then
        local options = buildOptions()
        AceConfig:RegisterOptionsTable("LootCollector", options)
        self.optionsFrame = AceConfigDialog:AddToBlizOptions("LootCollector", "LootCollector")
    else
        SLASH_LootCollectorCFG1 = "/lc"
        SlashCmdList["LootCollectorCFG"] = function(msg)
            msg = msg or ""
            local cmd, val = msg:match("^(%S+)%s*(%S*)")
            cmd = cmd and cmd:lower() or ""
            local on = not (val == "0" or val == "off" or val == "false")

            if cmd == "sharing" then
                L.db.profile.sharing.enabled = on
                local Comm = L:GetModule("Comm", true)
                if Comm then
                    if on then Comm:JoinPublicChannel() else Comm:LeavePublicChannel() end
                end
                print(string.format("|cff00ff00LootCollector:|r sharing.enabled=%s", tostring(on)))
            elseif cmd == "toasts" or cmd == "hideall" or cmd == "hidefaded" or cmd == "hidestale" or cmd == "hidelooted" then
                local setting = (cmd == "toasts" and "toasts") or "mapFilters"
                local key = (cmd == "toasts" and "enabled") or cmd
                L.db.profile[setting][key] = on
                print(string.format("|cff00ff00LootCollector:|r %s.%s=%s", setting, key, tostring(on)))
                refreshUI()
            else
                print("|cff00ff00LootCollector:|r /lc sharing on|off, toasts on|off, hideall on|off, etc.")
            end
        end
    end

    -- Register the new /lctop command
    SLASH_LootCollectorTOP1 = "/lctop"
    SlashCmdList["LootCollectorTOP"] = ShowTopContributors
end

return Settings