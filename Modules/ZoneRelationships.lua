-- Modules/ZoneRelationships.lua
-- This file links subzone maps to their parent maps and provides all necessary lookup data.
-- UNK.B64.UTF-8


local L = _G.LootCollector
if not L then return end

local ZoneList = L:GetModule("ZoneList")
if not ZoneList then return end

ZoneList.ZoneRelationships = {
    
    [1244] = { parentMapID = 5, c = 1, z = 45, name = "Valley of Trials", label = "", parent = { c = 1, z = 12, name = "Durotar" }, entrance = { x = 0.4387, y = 0.6390 } },
    [1238] = { parentMapID = 31, c = 2, z = 29, name = "northshire", parent = { c = 2, z = 16, name = "Elwynn" }, entrance = { x = 0.5144, y = 0.4536 } },
	[1243] = { parentMapID = 42, c = 1, z = 25, name = "shadowglenstart", parent = { c = 1, z = 33, name = "Teldrassil" }, entrance = { x = 0.5966, y = 0.3788 } },
	[1239] = { parentMapID = 28, c = 2, z = 9, name = "coldridgevalley", parent = { c = 2, z = 12, name = "DunMorogh" }, entrance = { x = 0.2547, y = 0.7248 } },
	[1245] = { parentMapID = 10, c = 1, z = 24, name = "campnarachestart", parent = { c = 1, z = 21, name = "Mulgore" }, entrance = { x = 0.4600, y = 0.8269 } },
	[1242] = { parentMapID = 465, c = 1, z = 1, name = "ammenvalestart", parent = { c = 1, z = 4, name = "AzuremystIsle" }, entrance = { x = 0.7640, y = 0.4618 } },
	[1241] = { parentMapID = 463, c = 2, z = 39, name = "sunstriderislestart", parent = { c = 2, z = 17, name = "EversongWoods" }, entrance = { x = 0.3350, y = 0.2197 } },
	[1240] = { parentMapID = 21, c = 2, z = 11, name = "deathknellstart", parent = { c = 2, z = 44, name = "Tirisfal" }, entrance = { x = 0.3676, y = 0.6059 } },

	
}

ZoneList.ZoneRelationshipsC = {
    [10] = { parentMapID = 14, c = 1, z = 21, name = "Mulgore", label = "[LC]", parent = { c = 1, z = 0, name = "Kalimdor" }, entrance = { x = 0.4697, y = 0.6000 } },
}
-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl