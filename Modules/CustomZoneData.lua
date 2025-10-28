-- Modules/CustomZoneData.lua
-- This file contains custom measurements for zones not included in the default Astrolabe data.
-- UNK.B64.UTF-8


local L = _G.LootCollector
if not L then return end

local Map = L:GetModule("Map")
if not Map then return end

local customData = {
    [1] = {
        --[45] = { name = "Valley of Trials",      width = 2000, height = 500 },
		[45] = { name = "Valley of Trials",width = 1173.94, height = 782.65, xOffset = 18007.16, yOffset = 11130.17 }, -- valleyoftrialsstart
        --[25] = { name = "Shadowglen",            width = 500, height = 500 },
        --[24] = { name = "Camp Narache",          width = 900, height = 500 },
		[25] = { name = "Shadowglen", width = 1260.91, height = 840.57, xOffset = 13543.26, yOffset = 1535.47 }, -- shadowglenstart
		[24] = { name = "Camp Narache", width = 1565.16, height = 1043.57, xOffset = 14608.62, yOffset = 13362.24 }, -- campnarachestart
        [1]  = { name = "Ammen Vale",            width = 650, height = 500 },
		
    },
    
    [2] = {
        --[29] = { name = "Northshire Valley",     width = 600, height = 550 },
		[29] = { name = "Northshire Valley", width = 507.28, height = 507.49, xOffset = 9416.98, yOffset = 15516.80 }, -- northshire
        --[9]  = { name = "Coldridge Valley",      width = 600, height = 580 },
		  [9] = { name = "Coldridge Valley", width = 663.35, height = 661.63, xOffset = 8886.79, yOffset = 13280.32 }, -- coldridgevalley
        [39] = { name = "Sunstrider Isle",       width = 510, height = 500 },
	  --[11] = { name = "Deathknell",       width = 720, height = 520 },
	  [11] = { name = "Deathknell", width = 570.56, height = 571.33, xOffset = 8390.42, yOffset = 6997.57 }, -- deathknellstart
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