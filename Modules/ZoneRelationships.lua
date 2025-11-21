

local L = _G.LootCollector
if not L then return end

local ZoneList = L:GetModule("ZoneList")
if not ZoneList then return end

ZoneList.ZoneRelationships = {
    
    [1244] = { parentMapID = 5, c = 1, z = 1244, name = "Valley of Trials", label = "", parent = { c = 1, z = 5, name = "Durotar" }, entrance = { x = 0.4387, y = 0.6390 } },
    [1238] = { parentMapID = 31, c = 2, z = 1238, name = "Northshire Valley", label = "", parent = { c = 2, z = 31, name = "Elwynn Forest" }, entrance = { x = 0.5144, y = 0.4536 } },
    [1243] = { parentMapID = 42, c = 1, z = 1243, name = "Shadowglen", label = "", parent = { c = 1, z = 42, name = "Teldrassil" }, entrance = { x = 0.5966, y = 0.3788 } },
    [1239] = { parentMapID = 28, c = 2, z = 1239, name = "Coldridge Valley", label = "", parent = { c = 2, z = 28, name = "Dun Morogh" }, entrance = { x = 0.2547, y = 0.7248 } },
    [1245] = { parentMapID = 10, c = 1, z = 1245, name = "Camp Narache", label = "", parent = { c = 1, z = 10, name = "Mulgore" }, entrance = { x = 0.4600, y = 0.8269 } },	
    [1242] = { parentMapID = 465, c = 1, z = 1242, name = "Ammen Vale", label = "", parent = { c = 1, z = 465, name = "Azuremyst Isle" }, entrance = { x = 0.7640, y = 0.4618 } },
    [1241] = { parentMapID = 463, c = 2, z = 1241, name = "Sunstrider Isle", label = "", parent = { c = 2, z = 463, name = "Eversong Woods" }, entrance = { x = 0.3350, y = 0.2197 } },
    [1240] = { parentMapID = 21, c = 2, z = 1240, name = "Deathknell", label = "", parent = { c = 2, z = 21, name = "Tirisfal Glades" }, entrance = { x = 0.3676, y = 0.6059 } },

    
    
    
    
    
    
    
    
    
    
    
    
    
    

    
    
    
    
    
    
    
    
    
    
    
    
    
}

ZoneList.ZoneRelationshipsC = {
    [10] = { parentMapID = 14, c = 1, z = 10, name = "Mulgore", label = "[LC]", parent = { c = 1, z = 14, name = "Kalimdor" }, entrance = { x = 0.4697, y = 0.6000 } },
}