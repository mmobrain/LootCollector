local L = LootCollector

local MapDimensions = L:NewModule("MapDimensions")

-- Zone_data (width, height, zoneID)
local zone_data = {
	["Arathi Highlands"] = {3599.78645678886,2399.85763785924,1,},
	["Orgrimmar"] = {1402.563051365538,935.042034243692,2,},
	["Eastern Kingdoms"] = {37649.15159852673,25099.43439901782,3,},
	["Undercity"] = {959.3140238076666,639.5426825384444,4,},
	["The Barrens"] = { 10133.3330078125, 6756.24987792969, 5},
	["Darnassus"] = {1058.300884213672,705.5339228091146,6,},
	["Azuremyst Isle"] = {4070.691916244019, 2713.794610829346,7,},
	["Un'Goro Crater"] = {3699.872808671186,2466.581872447457,8,},
	["Burning Steppes"] = { 2929.16659545898, 1952.08349609375, 9},
	["Wetlands"] = {4135.166184805389,2756.777456536926,10,},
	["Winterspring"] = {7099.756078049357,4733.170718699571,11,},
	["Dustwallow Marsh"] = { 5250.00006103516, 3499.99975585938, 12},
	["Darkshore"] = {6549.780280774227,4366.520187182819,13,},
	["Loch Modan"] = {2758.158752877019,1838.772501918013,14,},
	["Blade's Edge Mountains"] = {5424.84803598309,3616.56535732206,15,},
	["Durotar"] = {5287.285801274457,3524.857200849638,16,},
	["Silithus"] = {3483.224287356748,2322.149524904499,17,},
	["Shattrath City"] = {1306.210386847456,870.8069245649707,18,},
	["Ashenvale"] = {5766.471113365881,3844.314075577254,19,},
	["Azeroth"] = { 40741.181640625, 27149.6875, 20},
	["Nagrand"] = { 5525.0, 3683.33316802979, 21},
	["Terokkar Forest"] = {5399.832305361811,3599.888203574541,22,},
	["Eversong Woods"] = { 4925.0, 3283.3330078125, 23},
	["Silvermoon City"] = {1211.384457945605,807.5896386304033,24,},
	["Tanaris"] = {6899.765399158026,4599.843599438685,25,},
	["Stormwind City"] = { 1737.499958992, 1158.3330078125, 26},
	["Swamp of Sorrows"] = {2293.606089974149,1529.070726649433,27,},
	["Eastern Plaguelands"] = { 4031.25, 2687.49987792969, 28},
	["Blasted Lands"] = {3349.808966078055,2233.20597738537,29,},
	["Elwynn Forest"] = {3470.62593362794,2313.750622418627,30,},
	["Deadwind Pass"] = {2499.848163715574,1666.565442477049,31,},
	["Dun Morogh"] = {4924.664537147015,3283.109691431343,32,},
	["The Exodar"] = {1056.732317707213,704.4882118048087,33,},
	["Felwood"] = {5749.8046476606,3833.2030984404,34,},
	["Silverpine Forest"] = {4199.739879721531,2799.826586481021,35,},
	["Thunder Bluff"] = {1043.762849319158,695.8418995461053,36,},
	["The Hinterlands"] = { 3850.0, 2566.66662597656, 37},
	["Stonetalon Mountains"] = {4883.173287670144,3255.448858446763,38,},
	["Mulgore"] = {5137.32138887616,3424.88092591744,39,},
	["Hellfire Peninsula"] = {5164.421615455519,3442.947743637013,40,},
	["Ironforge"] = {790.5745810546713,527.0497207031142,41,},
	["Thousand Needles"] = {4399.86408093722,2933.242720624814,42,},
	["Stranglethorn Vale"] = { 6381.24975585938, 4254.166015625, 43},
	["Badlands"] = {2487.343589680943,1658.229059787295,44,},
	["Teldrassil"] = {5091.467863261982,3394.311908841321,45,},
	["Moonglade"] = {2308.253559286662,1538.835706191108,46,},
	["Shadowmoon Valley"] = { 5500.0, 3666.66638183594, 47},
	["Tirisfal Glades"] = {4518.469744413802,3012.313162942535,48,},
	["Azshara"] = {5070.669448432522,3380.446298955014,49,},
	["Redridge Mountains"] = {2170.704876735185,1447.136584490123,50,},
	["Bloodmyst Isle"] = {3262.385067990556,2174.92337866037,51,},
	["Western Plaguelands"] = {4299.7374000546,2866.4916000364,52,},
	["Alterac Mountains"] = {2799.820894040741,1866.547262693827,53,},
	["Westfall"] = {3499.786489780177,2333.190993186784,54,},
	["Duskwood"] = {2699.837284973949,1799.891523315966,55,},
	["Netherstorm"] = {5574.82788866266,3716.551925775107,56,},
	["Ghostlands"] = {3299.755735439147,2199.837156959431,57,},
	["Zangarmarsh"] = { 5027.08349609375, 3352.08325195312, 58},
	["Desolace"] = {4495.726850591814,2997.151233727876,59,},
	["Kalimdor"] = { 36799.810546875, 24533.2001953125, 60},
	["Searing Gorge"] = {2231.119799153945,1487.413199435963,61,},
	["Outland"] = { 17464.078125, 11642.71875, 62},
	["Feralas"] = {6949.760203962193,4633.173469308129,63,},
	["Hillsbrad Foothills"] = {3199.802496078764,2133.201664052509,64,},
	["Sunwell Plateau"] = {3327.0830078125,2218.7490234375,65,},
	["Northrend"] = {17751.3984375,11834.2650146484,66,},
	["Borean Tundra"] = {5764.5830088,3843.749878,67,},
	["Dragonblight"] = {5608.33312988281,3739.58337402344,68,},
	["Grizzly Hills"] = {5249.999878,3499.999878,69,},
	["Howling Fjord"] = {6045.83288574219,4031.24981689453,70,},
	["Icecrown Glacier"] = {6270.83331298828, 4181.25,71,},
	["Sholazar Basin"] = {4356.25,2904.166504,72,},
	["The Storm Peaks"] = {7112.49963378906,4741.666015625,73,},
	["Zul'Drak"] = {4993.75,3329.166504,74,},
	["Scarlet Enclave"] = {3162.5,2108.333374,76,},
	["Crystalsong Forest"] = {2722.91662597656,1814.5830078125,77,},
	["Lake Wintergrasp"] = {2974.99987792969,1983.33325195312,78,},
	["Strand of the Ancients"] = {1743.74993896484,1162.49993896484,79,},
	["Dalaran"] = {667,768,80,},
	["Naxxramas"] = { 1856.24975585938, 1237.5, 81},
	["Azjol-Nerub"] = { 1072.91664505005, 714.583297729492, 90},
	["Drak'Tharon Keep"] = { 627.083312988281, 418.75, 96},
	["The Obsidian Sanctum"] = { 1162.49991798401, 775.0, 99},
	["Halls of Lightning"] = { 3399.99993896484, 2266.66666412354, 100},
	["The Violet Hold"] = { 383.333312988281, 256.25, 103},
	["Caverns of Time: Stratholme"] = { 1824.99993896484, 1216.66650390625, 106},
	["The Eye of Eternity"] = { 3399.99981689453, 2266.66666412354, 108},
	["The Nexus"] = { 2600.0, 1733.33322143555, 110},
	["Vault of Archavon"] = { 2599.99987792969, 1733.33325195312, 115},
	["Ulduar"] = { 3287.49987792969, 2191.66662597656, 117},
	["Gundrak"] = { 1143.74996948242, 762.499877929688, 124},
	["Ahn'kahet: The Old Kingdom"] = { 972.91667175293, 647.916610717773, 128},
	["Utgarde Pinnacle"] = { 6549.99951171875, 4366.66650390625, 131},
	["Utgarde Keep"] = { 0.0, 0.0, 134},
	["Isle of Conquest"] = { 2650.0, 1766.66658401489, 138},
	["Trial of the Crusader"] = { 2599.99996948242, 1733.33334350586, 139},
	["Hrothgar's Landing"] = { 3677.08312988281, 2452.083984375, 143},
}

MapDimensions.data = {
  -- Static data, keyed by zone name
}

MapDimensions.idData = {
  -- Static data, keyed by zone ID
}

-- Minimap_size settings for zoom (radius values in yards)
local minimap_size_data = {
	indoor = {
		[0] = 300, -- scale
		[1] = 240, -- 1.25
		[2] = 180, -- 5/3
		[3] = 120, -- 2.5
		[4] = 80,  -- 3.75
		[5] = 50,  -- 6
        [6] = 33.3,
		[7] = 22.2,
        
	},
	outdoor = {
		[0] = 466 + 2/3, -- scale
		[1] = 400,       -- 7/6
		[2] = 333 + 1/3, -- 1.4
		[3] = 266 + 2/6, -- 1.75
		[4] = 200,       -- 7/3
		[5] = 133 + 1/3, -- 3.5
        [6] = 88.9,
		[7] = 59.3,
	},
}

function MapDimensions:GetMinimapRadius(zoom, isIndoor)
    local type = isIndoor and "indoor" or "outdoor"
    return minimap_size_data[type][zoom] or 0
end

-- Populate MapDimensions.data with zone_data on initialization
function MapDimensions:OnInitialize()
    for zoneName, data in pairs(zone_data) do
        local width, height, id = data[1], data[2], data[3]
        MapDimensions.data[zoneName] = { width = width, height = height, id = id, name = zoneName }
        MapDimensions.idData[id] = { width = width, height = height, id = id, name = zoneName }
    end
    -- Clear the local zone_data table to save memory
    zone_data = nil
end

function MapDimensions:GetZoneDimensions(zoneName)
    local data = MapDimensions.data[zoneName]
    if data then
        return data.width, data.height, data.id
    end
    -- Fallback to dynamic retrieval if not found
    SetMapToCurrentZone();
    local name, height, width = GetMapInfo();
    local zoneID = GetCurrentMapZone();
    if name == zoneName and height and width and height ~= 0 and width ~= 0 then
        MapDimensions.data[name] = {width = width, height = height, id = zoneID, name = name}; -- Cache dynamic result
        return width, height, zoneID;
    end
    return 1600, 1600, 0 -- Default fallback values
end

function MapDimensions:GetMapDimensions(mapID) -- TODO: What is mapID? zoneID is not unique
    local data = MapDimensions.idData[mapID]
    if data then
        return data.width, data.height, data.name
    end
    -- Fallback to dynamic retrieval if not found
    SetMapByID(mapID);
    local name, height, width = GetMapInfo();
    local zoneID = GetCurrentMapZone();
    if height and width and height ~= 0 and width ~= 0 then
        MapDimensions.data[name] = {width = width, height = height, id = zoneID, name = name};
        MapDimensions.idData[zoneID] = MapDimensions.data[name];
        return width, height, name;
    end
    return 1600, 1600, "Unknown Zone" -- Default fallback values
end

return MapDimensions
