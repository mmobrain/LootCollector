local L = LootCollector
local MapData = L:NewModule("MapData")

-- Zone data: [continentID][zoneID] = {name, width, height}
local zones = {
	[1] = {
		[1] = { "Ammen Vale", 1600.00, 1600.00 },
		[2] = { "Ashenvale", 5766.47, 3844.31 },
		[3] = { "Azshara", 5070.67, 3380.45 },
		[4] = { "Azuremyst Isle", 4070.69, 2713.79 },
		[5] = { "Ban'ethil Barrow Den", 1600.00, 1600.00 },
		[6] = { "Bloodmyst Isle", 3262.39, 2174.92 },
		[7] = { "Burning Blade Coven", 1600.00, 1600.00 },
		[8] = { "Caverns of Time", 1600.00, 1600.00 },
		[9] = { "Darkshore", 6549.78, 4366.52 },
		[10] = { "Darnassus", 1058.30, 705.53 },
		[11] = { "Desolace", 4495.73, 2997.15 },
		[12] = { "Durotar", 5287.29, 3524.86 },
		[13] = { "Dustwallow Marsh", 5250.00, 3500.00 },
		[14] = { "Dustwind Cave", 1600.00, 1600.00 },
		[15] = { "Fel Rock", 1600.00, 1600.00 },
		[16] = { "Felwood", 5749.80, 3833.20 },
		[17] = { "Feralas", 6949.76, 4633.17 },
		[18] = { "Maraudon", 1600.00, 1600.00 },
		[19] = { "Moonglade", 2308.25, 1538.84 },
		[20] = { "Moonlit Ossuary", 1600.00, 1600.00 },
		[21] = { "Mulgore", 5137.32, 3424.88 },
		[22] = { "Orgrimmar", 1402.56, 935.04 },
		[23] = { "Palemane Rock", 1600.00, 1600.00 },
		[24] = { "Red Cloud Mesa", 1600.00, 1600.00 },
		[25] = { "Shadowglen", 1600.00, 1600.00 },
		[26] = { "Shadowthread Cave", 1600.00, 1600.00 },
		[27] = { "Silithus", 3483.22, 2322.15 },
		[28] = { "Sinister Lair", 1600.00, 1600.00 },
		[29] = { "Skull Rock", 1600.00, 1600.00 },
		[30] = { "Stillpine Hold", 1600.00, 1600.00 },
		[31] = { "Stonetalon Mountains", 4883.17, 3255.45 },
		[32] = { "Tanaris", 6899.77, 4599.84 },
		[33] = { "Teldrassil", 5091.47, 3394.31 },
		[34] = { "The Barrens", 10133.33, 6756.25 },
		[35] = { "The Exodar", 1056.73, 704.49 },
		[36] = { "The Gaping Chasm", 1600.00, 1600.00 },
		[37] = { "The Noxious Lair", 1600.00, 1600.00 },
		[38] = { "The Slithering Scar", 1600.00, 1600.00 },
		[39] = { "The Venture Co. Mine", 1600.00, 1600.00 },
		[40] = { "Thousand Needles", 4399.86, 2933.24 },
		[41] = { "Thunder Bluff", 1043.76, 695.84 },
		[42] = { "Tides' Hollow", 1600.00, 1600.00 },
		[43] = { "Twilight's Run", 1600.00, 1600.00 },
		[44] = { "Un'Goro Crater", 3699.87, 2466.58 },
		[45] = { "Valley of Trials", 1600.00, 1600.00 },
		[46] = { "Wailing Caverns", 1600.00, 1600.00 },
		[47] = { "Winterspring", 7099.76, 4733.17 },
	},
	[2] = {
		[1] = { "Alterac Mountains", 2799.82, 1866.55 },
		[2] = { "Amani Catacombs", 1600.00, 1600.00 },
		[3] = { "Arathi Highlands", 3599.79, 2399.86 },
		[4] = { "Badlands", 2487.34, 1658.23 },
		[5] = { "Blackrock Mountain", 1600.00, 1600.00 },
		[6] = { "Blasted Lands", 3349.81, 2233.21 },
		[7] = { "Burning Steppes", 2929.17, 1952.08 },
		[8] = { "Coldridge Pass", 1600.00, 1600.00 },
		[9] = { "Coldridge Valley", 1600.00, 1600.00 },
		[10] = { "Deadwind Pass", 2499.85, 1666.57 },
		[11] = { "Deathknell", 1600.00, 1600.00 },
		[12] = { "Dun Morogh", 4924.66, 3283.11 },
		[13] = { "Duskwood", 2699.84, 1799.89 },
		[14] = { "Eastern Plaguelands", 4031.25, 2687.50 },
		[15] = { "Echo Ridge Mine", 1600.00, 1600.00 },
		[16] = { "Elwynn Forest", 3470.63, 2313.75 },
		[17] = { "Eversong Woods", 4925.00, 3283.33 },
		[18] = { "Fargodeep Mine", 1600.00, 1600.00 },
		[19] = { "Ghostlands", 3299.76, 2199.84 },
		[20] = { "Gol'Bolar Quarry", 1600.00, 1600.00 },
		[21] = { "Gold Coast Quarry", 1600.00, 1600.00 },
		[22] = { "Hillsbrad Foothills", 3199.80, 2133.20 },
		[23] = { "Ironforge", 790.57, 527.05 },
		[24] = { "Isle of Quel'Danas", 1600.00, 1600.00 },
		[25] = { "Jangolode Mine", 1600.00, 1600.00 },
		[26] = { "Jasperlode Mine", 1600.00, 1600.00 },
		[27] = { "Loch Modan", 2758.16, 1838.77 },
		[28] = { "Night Web's Hollow", 1600.00, 1600.00 },
		[29] = { "Northshire Valley", 1600.00, 1600.00 },
		[30] = { "Redridge Mountains", 2170.70, 1447.14 },
		[31] = { "Scarlet Monastery", 1600.00, 1600.00 },
		[32] = { "Searing Gorge", 2231.12, 1487.41 },
		[33] = { "Secret Inquisitorial Dungeon", 1600.00, 1600.00 },
		[34] = { "Shadewell Spring", 1600.00, 1600.00 },
		[35] = { "Silvermoon City", 1211.38, 807.59 },
		[36] = { "Silverpine Forest", 4199.74, 2799.83 },
		[37] = { "Stormwind City", 1737.50, 1158.33 },
		[38] = { "Stranglethorn Vale", 6381.25, 4254.17 },
		[39] = { "Sunstrider Isle", 1600.00, 1600.00 },
		[40] = { "Swamp of Sorrows", 2293.61, 1529.07 },
		[41] = { "The Deadmines", 1600.00, 1600.00 },
		[42] = { "The Grizzled Den", 1600.00, 1600.00 },
		[43] = { "The Hinterlands", 3850.00, 2566.67 },
		[44] = { "Tirisfal Glades", 4518.47, 3012.31 },
		[45] = { "Uldaman", 1600.00, 1600.00 },
		[46] = { "Undercity", 959.31, 639.54 },
		[47] = { "Western Plaguelands", 4299.74, 2866.49 },
		[48] = { "Westfall", 3499.79, 2333.19 },
		[49] = { "Wetlands", 4135.17, 2756.78 },
	},
	[3] = {
		[1] = { "Blade's Edge Mountains", 5424.85, 3616.57 },
		[2] = { "Hellfire Peninsula", 5164.42, 3442.95 },
		[3] = { "Nagrand", 5525.00, 3683.33 },
		[4] = { "Netherstorm", 5574.83, 3716.55 },
		[5] = { "Shadowmoon Valley", 5500.00, 3666.67 },
		[6] = { "Shattrath City", 1306.21, 870.81 },
		[7] = { "Terokkar Forest", 5399.83, 3599.89 },
		[8] = { "Zangarmarsh", 5027.08, 3352.08 },
	},
	[4] = {
		[1] = { "Borean Tundra", 5764.58, 3843.75 },
		[2] = { "Crystalsong Forest", 2722.92, 1814.58 },
		[3] = { "Dalaran", 667.00, 768.00 },
		[4] = { "Dragonblight", 5608.33, 3739.58 },
		[5] = { "Grizzly Hills", 5250.00, 3500.00 },
		[6] = { "Howling Fjord", 6045.83, 4031.25 },
		[7] = { "Hrothgar's Landing", 3677.08, 2452.08 },
		[8] = { "Icecrown", 1600.00, 1600.00 },
		[9] = { "Sholazar Basin", 4356.25, 2904.17 },
		[10] = { "The Storm Peaks", 7112.50, 4741.67 },
		[11] = { "Wintergrasp", 1600.00, 1600.00 },
		[12] = { "Zul'Drak", 4993.75, 3329.17 },
	},
	[5] = {
		[1] = { "Azzar Archipelago", 1600.00, 1600.00 },
		[2] = { "Glorious Azzar Faire", 1600.00, 1600.00 },
	},
}

-- Name lookup cache for O(1) access
local nameCache = {}

-- Build name cache on initialization
function MapData:OnInitialize()
	for continentID, continentZones in pairs(zones) do
		for zoneID, zoneData in pairs(continentZones) do
			nameCache[zoneData[1]] = { continentID, zoneID }
		end
	end
end

-- Get zone dimensions by name
function MapData:GetZoneDimensionsByName(zoneName)
	local cached = nameCache[zoneName]
	if cached then
		local continentID, zoneID = cached[1], cached[2]
		local zoneData = zones[continentID][zoneID]
		return zoneData[2], zoneData[3], continentID, zoneID
	end
	return 0, 0, 0, 0
end

-- Get zone dimensions by continent/zone IDs
function MapData:GetZoneDimensionsByIDs(continentID, zoneID)
	local zoneData = zones[continentID] and zones[continentID][zoneID]
	if zoneData then
		return zoneData[2], zoneData[3], zoneData[1]
	end
	return 0, 0, "Unknown Zone"
end

-- Get all zones for a continent
function MapData:GetZonesForContinent(continentID)
	return zones[continentID] or {}
end

return MapData
