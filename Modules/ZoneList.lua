-- ZoneList.lua
-- Centralized zone and instance mapping for LootCollector (3.3.5a-safe).
-- Provides:
-- - ZoneData: continent -> zoneID -> zoneName
-- - ZONE_ABBREVIATIONS: map of full zone names to short forms
-- - InstanceZones: iz (instance id) -> instance name
-- - Resolve helpers for iz and zone abbreviations
-- UNK.B64.UTF-8


local L = LootCollector
local ZoneList = L:NewModule("ZoneList")

ZoneList.mapIdToZoneInfo = ZoneList.mapIdToZoneInfo or {} 
ZoneList.zoneInfoToMapId = ZoneList.zoneInfoToMapId or {} 

ZoneList.ZoneData = ZoneList.ZoneData or {
    [1] = { 
        [1] = "Ammen Vale", [2] = "Ashenvale", [3] = "Azshara", [4] = "Azuremyst Isle", [5] = "Ban'ethil Barrow Den", [6] = "Bloodmyst Isle", [7] = "Burning Blade Coven", [8] = "Caverns of Time", [9] = "Darkshore", [10] = "Darnassus", [11] = "Desolace", [12] = "Durotar", [13] = "Dustwallow Marsh", [14] = "Dustwind Cave", [15] = "Fel Rock", [16] = "Felwood", [17] = "Feralas", [18] = "Maraudon", [19] = "Moonglade", [20] = "Moonlit Ossuary", [21] = "Mulgore", [22] = "Orgrimmar", [23] = "Palemane Rock", [24] = "Red Cloud Mesa", [25] = "Shadowglen", [26] = "Shadowthread Cave", [27] = "Silithus", [28] = "Sinister Lair", [29] = "Skull Rock", [30] = "Stillpine Hold", [31] = "Stonetalon Mountains", [32] = "Tanaris", [33] = "Teldrassil", [34] = "The Barrens", [35] = "The Exodar", [36] = "The Gaping Chasm", [37] = "The Noxious Lair", [38] = "The Slithering Scar", [39] = "The Venture Co. Mine", [40] = "Thousand Needles", [41] = "Thunder Bluff", [42] = "Tides' Hollow", [43] = "Twilight's Run", [44] = "Un'Goro Crater", [45] = "Valley of Trials", [46] = "Wailing Caverns", [47] = "Winterspring",
    },
    [2] = { 
        [1] = "Alterac Mountains", [2] = "Amani Catacombs", [3] = "Arathi Highlands", [4] = "Badlands", [5] = "Blackrock Mountain", [6] = "Blasted Lands", [7] = "Burning Steppes", [8] = "Coldridge Pass", [9] = "Coldridge Valley", [10] = "Deadwind Pass", [11] = "Deathknell", [12] = "Dun Morogh", [13] = "Duskwood", [14] = "Eastern Plaguelands", [15] = "Echo Ridge Mine", [16] = "Elwynn Forest", [17] = "Eversong Woods", [18] = "Fargodeep Mine", [19] = "Ghostlands", [20] = "Gol'Bolar Quarry", [21] = "Gold Coast Quarry", [22] = "Hillsbrad Foothills", [23] = "Ironforge", [24] = "Isle of Quel'Danas", [25] = "Jangolode Mine", [26] = "Jasperlode Mine", [27] = "Loch Modan", [28] = "Night Web's Hollow", [29] = "Northshire Valley", [30] = "Redridge Mountains", [31] = "Scarlet Monastery", [32] = "Searing Gorge", [33] = "Secret Inquisitorial Dungeon", [34] = "Shadewell Spring", [35] = "Silvermoon City", [36] = "Silverpine Forest", [37] = "Stormwind City", [38] = "Stranglethorn Vale", [39] = "Sunstrider Isle", [40] = "Swamp of Sorrows", [41] = "The Deadmines", [42] = "The Grizzled Den", [43] = "The Hinterlands", [44] = "Tirisfal Glades", [45] = "Uldaman", [46] = "Undercity", [47] = "Western Plaguelands", [48] = "Westfall", [49] = "Wetlands",
    },
    [3] = { 
        [1] = "Blade's Edge Mountains", [2] = "Hellfire Peninsula", [3] = "Nagrand", [4] = "Netherstorm", [5] = "Shadowmoon Valley", [6] = "Shattrath City", [7] = "Terokkar Forest", [8] = "Zangarmarsh",
    },
    [4] = { 
        [1] = "Borean Tundra", [2] = "Crystalsong Forest", [3] = "Dalaran", [4] = "Dragonblight", [5] = "Grizzly Hills", [6] = "Howling Fjord", [7] = "Hrothgar's Landing", [8] = "Icecrown", [9] = "Sholazar Basin", [10] = "The Storm Peaks", [11] = "Wintergrasp", [12] = "Zul'Drak",
    }
}

ZoneList.ZONEABBREVIATIONS = ZoneList.ZONEABBREVIATIONS or {
    ["Ragefire Chasm"]="rfc", ["Wailing Caverns"]="wc", ["The Deadmines"]="dm", ["Shadowfang Keep"]="sfk", ["The Stockade"]="stocks", ["Blackfathom Deeps"]="bfd", ["Gnomeregan"]="gnomer", ["Razorfen Kraul"]="rfk", ["Scarlet Monastery"]="sm", ["Razorfen Downs"]="rfd", ["Uldaman"]="uld", ["Zul'Farrak"]="zf", ["Maraudon"]="mara", ["Temple of Atal'Hakkar"]="st", ["Blackrock Depths"]="brd", ["Dire Maul"]="dme", ["Lower Blackrock Spire"]="lbrs", ["Upper Blackrock Spire"]="ubrs", ["Scholomance"]="scholo", ["Stratholme"]="strat", ["Molten Core"]="mc", ["Onyxia's Lair"]="ony", ["Blackwing Lair"]="bwl", ["Zul'Gurub"]="zg", ["Ruins of Ahn'Qiraj"]="aq20", ["Temple of Ahn'Qiraj"]="aq40", ["Hellfire Ramparts"]="hfr", ["The Blood Furnace"]="bf", ["The Shattered Halls"]="shh", ["The Slave Pens"]="sp", ["The Underbog"]="ub", ["The Steamvault"]="sv", ["Mana-Tombs"]="mt", ["Auchenai Crypts"]="ac", ["Sethekk Halls"]="sh", ["Shadow Labyrinth"]="sl", ["Escape from Durnholde Keep"]="ohf", ["Opening the Dark Portal"]="bm", ["The Mechanar"]="mech", ["The Botanica"]="bot", ["The Arcatraz"]="arc", ["Magisters' Terrace"]="mgt", ["Karazhan"]="kara", ["Gruul's Lair"]="gruul", ["Magtheridon's Lair"]="mag", ["Utgarde Keep"]="uk", ["The Nexus"]="nex", ["Ahn'kahet: The Old Kingdom"]="an", ["Azjol-Nerub"]="an", ["Drak'Tharon Keep"]="dtk", ["The Violet Hold"]="vh", ["Gundrak"]="gd", ["Halls of Stone"]="hos", ["Halls of Lightning"]="hol", ["Utgarde Pinnacle"]="up", ["The Culling of Stratholme"]="cos", ["The Oculus"]="ocu", ["Forge of Souls"]="fos", ["Pit of Saron"]="pos", ["Halls of Reflection"]="hor", ["Trial of the Champion"]="toc", ["Naxxramas"]="naxx", ["Vault of Archavon"]="voa", ["The Obsidian Sanctum"]="os", ["The Eye of Eternity"]="eoe", ["Ulduar"]="ulduar", ["Trial of the Crusader"]="toc", ["Icecrown Citadel"]="icc", ["The Ruby Sanctum"]="rs", ["Eonar's Cradle"]="ec", ["Forgotten Mine"]="fm", ["Frozen Reach"]="fr", ["Gronn's Spine"]="gs", ["Iskirr Village"]="iv", ["Ocean Battle"]="ob", ["Ocean's Sword"]="osw", ["Pools of the Eidola"]="poe", ["Temple of Eternity"]="toe", ["The Grim Marsh"]="gm", ["The Karazhan Crypts"]="kc", ["Unused Monastery"]="um", ["The Black Morass"]="bm", ["AzzarEvent"]="aze", ["Battle Royal"]="br", ["Black Temple"]="bt", ["Alterac Valley"]="av", ["Arathi Basin"]="ab", ["Eye of the Storm"]="eos", ["Isle of Conquest"]="ioc", ["Southshore vs. Tarren Mill"]="svst", ["Strand of the Ancients"]="sota", ["Temple of Kotmogu"]="tok", ["Twin Peaks"]="tp", ["Warsong Gulch"]="wsg",
}
  
ZoneList.InstanceZones = ZoneList.InstanceZones or {
    [1]="Ragefire Chasm", [2]="Wailing Caverns", [3]="The Deadmines", [4]="Shadowfang Keep", [5]="The Stockade", [6]="Blackfathom Deeps", [7]="Gnomeregan", [8]="Razorfen Kraul", [9]="Scarlet Monastery", [10]="Razorfen Downs", [11]="Uldaman", [12]="Zul'Farrak", [13]="Maraudon", [14]="Temple of Atal'Hakkar", [15]="Blackrock Depths", [16]="Dire Maul", [17]="Lower Blackrock Spire", [18]="Upper Blackrock Spire", [19]="Scholomance", [20]="Stratholme", [21]="Molten Core", [22]="Onyxia's Lair", [23]="Blackwing Lair", [24]="Zul'Gurub", [25]="Ruins of Ahn'Qiraj", [26]="Temple of Ahn'Qiraj", [27]="Hellfire Ramparts", [28]="The Blood Furnace", [29]="The Shattered Halls", [30]="The Slave Pens", [31]="The Underbog", [32]="The Steamvault", [33]="Mana-Tombs", [34]="Auchenai Crypts", [35]="Sethekk Halls", [36]="Shadow Labyrinth", [37]="Escape from Durnholde Keep", [38]="Opening the Dark Portal", [39]="The Mechanar", [40]="The Botanica", [41]="The Arcatraz", [42]="Magisters' Terrace", [43]="Karazhan", [44]="Gruul's Lair", [45]="Magtheridon's Lair", [46]="Utgarde Keep", [47]="The Nexus", [48]="Ahn'kahet: The Old Kingdom", [49]="Azjol-Nerub", [50]="Drak'Tharon Keep", [51]="The Violet Hold", [52]="Gundrak", [53]="Halls of Stone", [54]="Halls of Lightning", [55]="Utgarde Pinnacle", [56]="The Culling of Stratholme", [57]="The Oculus", [58]="Forge of Souls", [59]="Pit of Saron", [60]="Halls of Reflection", [61]="Trial of the Champion", [62]="Naxxramas", [63]="Vault of Archavon", [64]="The Obsidian Sanctum", [65]="The Eye of Eternity", [66]="Ulduar", [67]="Onyxia's Lair", [68]="Trial of the Crusader", [69]="Icecrown Citadel", [70]="The Ruby Sanctum", [71]="Eonar's Cradle", [72]="Forgotten Mine", [73]="Frozen Reach", [74]="Gronn's Spine", [75]="Iskirr Village", [76]="Ocean Battle", [77]="Ocean's Sword", [78]="Pools of the Eidola", [79]="Temple of Eternity", [80]="The Grim Marsh", [81]="The Karazhan Crypts", [82]="Unused Monastery", [83]="The Black Morass", [84]="AzzarEvent", [85]="Battle Royal", [86]="Black Temple", [87]="Alterac Valley", [88]="Arathi Basin", [89]="Eye of the Storm", [90]="Isle of Conquest", [91]="Southshore vs. Tarren Mill", [92]="Strand of the Ancients", [93]="Temple of Kotmogu", [94]="Twin Peaks", [95]="Warsong Gulch",
}

ZoneList._zonesCache = ZoneList._zonesCache or {}           

ZoneList._instanceNameToId = ZoneList._instanceNameToId or {}
ZoneList.instanceNameToId = ZoneList._instanceNameToId

local function GetMaxContinents()
    if type(GetMapContinents) == "function" then
        local continents = { GetMapContinents() }
        if #continents > 0 then
            return #continents
        end
    end
    local maxK = 0
    for k in pairs(ZoneList.ZoneData) do
        if type(k) == "number" and k > maxK then maxK = k end
    end
    return (maxK > 0) and maxK or 4
end

local function GetMapZonesArray(c)
    c = tonumber(c) or 0
    if c <= 0 then return nil end
    if ZoneList._zonesCache[c] then
        return ZoneList._zonesCache[c]
    end
    if type(GetMapZones) == "function" then
        local t = { GetMapZones(c) }
        if #t > 0 then
            ZoneList._zonesCache[c] = t
            return t
        end
    end
    return nil
end

function ZoneList:RebuildInstanceNameIndexPreferLowest()
    self._instanceNameToId = self._instanceNameToId or {}
    self.instanceNameToId = self._instanceNameToId
    wipe(self._instanceNameToId)
    if type(self.InstanceZones) ~= "table" then
        return
    end
    local minByName = {}
    for iz, name in pairs(self.InstanceZones) do
        local lname = type(name) == "string" and string.lower(name) or nil
        local niz = tonumber(iz) or 0
        if lname and niz > 0 then
            local prev = minByName[lname]
            if not prev or niz < prev then
                minByName[lname] = niz
            end
        end
    end
    for lname, niz in pairs(minByName) do
        self._instanceNameToId[lname] = niz
    end
end

function ZoneList:BuildMapIDLookups()
    if not self.ZoneData then return end
    
    wipe(self.mapIdToZoneInfo)
    wipe(self.zoneInfoToMapId)
    
    local maxC = 0
    for k in pairs(self.ZoneData) do
        if k > maxC then maxC = k end
    end

    local count = 0
    for c = 1, maxC do
        if self.ZoneData[c] then
            for z, name in pairs(self.ZoneData[c]) do
                
                SetMapZoom(c, z)
                local mapID = GetCurrentMapAreaID()
                
                if mapID and mapID > 0 then
                    local key = c .. ":" .. z
                    self.mapIdToZoneInfo[mapID] = { c = c, z = z, name = name }
                    self.zoneInfoToMapId[key] = mapID
                    count = count + 1
                end
            end
        end
    end
    
    
    
    if SetMapToCurrentZone then SetMapToCurrentZone() end
end

function ZoneList:GetZoneName(continent, zoneID, third, fourth)
    local c = tonumber(continent) or 0
    local z = tonumber(zoneID) or 0

    local iz = 0
    local instanceNameHint = nil
    if type(third) == "number" and fourth == nil then
        iz = tonumber(third) or 0
    else
        instanceNameHint = third
        iz = tonumber(fourth) or 0
    end

    
    if z == 0 then
        if iz and iz > 0 then
            local iname = self:ResolveIz(iz)
            if iname and iname ~= "" then
                return iname
            end
        end
        if type(instanceNameHint) == "string" and instanceNameHint ~= "" then
            return instanceNameHint
        end
        
        local live = (type(GetRealZoneText) == "function" and GetRealZoneText())
                  or (type(GetZoneText) == "function" and GetZoneText())
                  or nil
        return live or "Unknown Zone"
    end

    
    local cdata = self.ZoneData[c]
    if cdata and cdata[z] then
        return cdata[z]
    end

    
    local zones = GetMapZonesArray(c)
    if zones and zones[z] then
        return zones[z]
    end

    
    if c <= 0 and z > 0 then
        local maxC = GetMaxContinents()
        for ci = 1, maxC do
            local cd = self.ZoneData[ci]
            if cd and cd[z] then
                return cd[z]
            end
            local zz = GetMapZonesArray(ci)
            if zz and zz[z] then
                return zz[z]
            end
        end
    end

    return "Unknown Zone"
end

function ZoneList:GetZoneAbbrev(continent, zoneID, third, fourth)
    local full = self:GetZoneName(continent, zoneID, third, fourth)
    return self.ZONEABBREVIATIONS[full] or full
end

function ZoneList:ResolveInstanceIz(zoneName)
    if type(zoneName) ~= "string" or zoneName == "" then
        return 0
    end
    local iz = self.instanceNameToId[string.lower(zoneName)]
    return tonumber(iz) or 0
end

ZoneList.ResolveInstanceIZ = ZoneList.ResolveInstanceIz

function ZoneList:ResolveIz(iz)
    return self.InstanceZones[tonumber(iz) or 0]
end

function ZoneList:GetCurrentZoneDisplay()
    local c = (type(GetCurrentMapContinent) == "function" and GetCurrentMapContinent()) or 0
    local z = (type(GetCurrentMapZone) == "function" and GetCurrentMapZone()) or 0

    if z and z > 0 then
        local name = self:GetZoneName(c, z, nil)
        return 0, name, c, z
    end

    
    local live = (type(GetRealZoneText) == "function" and GetRealZoneText())
              or (type(GetZoneText) == "function" and GetZoneText())
              or nil
    local iz = self:ResolveInstanceIz(live or "")
    local name = self:ResolveIz(iz) or live or "Unknown Instance"
    return iz or 0, name, c, z or 0
end

function ZoneList:OnInitialize()    
    if self.ZoneRelationships then
        
        self.ParentToSubzones = self.ParentToSubzones or {}
        wipe(self.ParentToSubzones)
        
        local count = 0
        for childID, data in pairs(self.ZoneRelationships) do
            if data and data.parentMapID then
                local parentID = data.parentMapID
                if not self.ParentToSubzones[parentID] then
                    self.ParentToSubzones[parentID] = {}
                end
                table.insert(self.ParentToSubzones[parentID], childID)
                count = count + 1
            end
        end

    end

    
    if self.RebuildInstanceNameIndexPreferLowest then
        self:RebuildInstanceNameIndexPreferLowest()
    end

    
    self.IZ_TO_ABBREVIATIONS = {}
    local count = 0
    if self.InstanceZones and self.ZONEABBREVIATIONS then
        for iz, instanceName in pairs(self.InstanceZones) do
            if self.ZONEABBREVIATIONS[instanceName] then
                self.IZ_TO_ABBREVIATIONS[iz] = self.ZONEABBREVIATIONS[instanceName]
                count = count + 1
            end
        end
    end
end

return ZoneList
-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl