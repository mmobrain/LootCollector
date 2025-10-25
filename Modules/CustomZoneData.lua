-- Modules/CustomZoneData.lua
-- This file contains custom measurements for zones not included in the default Astrolabe data.
-- UNK.B64.UTF-8


local L = _G.LootCollector
if not L then return end

local Map = L:GetModule("Map")
if not Map then return end

local customData = {
    -- all this needs some real calcs+offsets instead of guessing
    [1] = {
        [45] = { name = "Valley of Trials",      width = 2000, height = 500 },
        [25] = { name = "Shadowglen",            width = 500, height = 500 },
        [24] = { name = "Camp Narache",          width = 900, height = 500 },
        [1]  = { name = "Ammen Vale",            width = 650, height = 500 },
    },
    
    [2] = {
        [29] = { name = "Northshire Valley",     width = 600, height = 550 },
        [9]  = { name = "Coldridge Valley",      width = 600, height = 580 },
        [39] = { name = "Sunstrider Isle",       width = 510, height = 500 },
	  [11] = { name = "Deathknell",       width = 720, height = 520 },
    }
}

for continentID, zones in pairs(customData) do
    if not Map.WorldMapSize[continentID] then
        Map.WorldMapSize[continentID] = {}
    end
    for zoneID, data in pairs(zones) do
        
        
        Map.WorldMapSize[continentID][zoneID] = {
            width = data.width or data.scale, 
            height = data.height or data.scale, 
            xOffset = 0, 
            yOffset = 0, 
        }
    end
end
-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl