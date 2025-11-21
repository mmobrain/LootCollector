
local L = LootCollector
local ZoneList = L:NewModule("ZoneList")

ZoneList.MapDataByID = {
    [5] = { name = "Durotar", continentID = 1, zoneID = 5 },
    [10] = { name = "Mulgore", continentID = 1, zoneID = 10 },
    [12] = { name = "The Barrens", continentID = 1, zoneID = 12 }, 
    [14] = { name = "Kalimdor", continentID = 1, zoneID = 14 }, 
    [15] = { name = "Azeroth", continentID = 0, zoneID = 15 }, 
    [16] = { name = "Alterac Mountains", continentID = 2, zoneID = 16 },
    [17] = { name = "Arathi Highlands", continentID = 2, zoneID = 17 },
    [18] = { name = "Badlands", continentID = 2, zoneID = 18 },
    [20] = { name = "Blasted Lands", continentID = 2, zoneID = 20 },
    [21] = { name = "Tirisfal Glades", continentID = 2, zoneID = 21 },
    [22] = { name = "Silverpine Forest", continentID = 2, zoneID = 22 },
    [23] = { name = "Western Plaguelands", continentID = 2, zoneID = 23 },
    [24] = { name = "Eastern Plaguelands", continentID = 2, zoneID = 24 },
    [25] = { name = "Hillsbrad Foothills", continentID = 2, zoneID = 25 },
    [27] = { name = "The Hinterlands", continentID = 2, zoneID = 27 },
    [28] = { name = "Dun Morogh", continentID = 2, zoneID = 28 },
    [29] = { name = "Searing Gorge", continentID = 2, zoneID = 29 },
    [30] = { name = "Burning Steppes", continentID = 2, zoneID = 30 },
    [31] = { name = "Elwynn Forest", continentID = 2, zoneID = 31 },
    [33] = { name = "Deadwind Pass", continentID = 2, zoneID = 33 },
    [35] = { name = "Duskwood", continentID = 2, zoneID = 35 },
    [36] = { name = "Loch Modan", continentID = 2, zoneID = 36 },
    [37] = { name = "Redridge Mountains", continentID = 2, zoneID = 37 },
    [38] = { name = "Stranglethorn Vale", continentID = 2, zoneID = 38 },
    [39] = { name = "Swamp of Sorrows", continentID = 2, zoneID = 39 },
    [40] = { name = "Westfall", continentID = 2, zoneID = 40 },
    [41] = { name = "Wetlands", continentID = 2, zoneID = 41 },
    [42] = { name = "Teldrassil", continentID = 1, zoneID = 42 },
    [43] = { name = "Darkshore", continentID = 1, zoneID = 43 },
    [44] = { name = "Ashenvale", continentID = 1, zoneID = 44 },
    [62] = { name = "Thousand Needles", continentID = 1, zoneID = 62 },
    [82] = { name = "Stonetalon Mountains", continentID = 1, zoneID = 82 },
    [102] = { name = "Desolace", continentID = 1, zoneID = 102 },
    [122] = { name = "Feralas", continentID = 1, zoneID = 122 },
    [142] = { name = "Dustwallow Marsh", continentID = 1, zoneID = 142 },
    [162] = { name = "Tanaris", continentID = 1, zoneID = 162 },
    [182] = { name = "Azshara", continentID = 1, zoneID = 182 },
    [183] = { name = "Felwood", continentID = 1, zoneID = 183 },
    [202] = { name = "Un'Goro Crater", continentID = 1, zoneID = 202 },
    [242] = { name = "Moonglade", continentID = 1, zoneID = 242 },
    [262] = { name = "Silithus", continentID = 1, zoneID = 262 },
    [282] = { name = "Winterspring", continentID = 1, zoneID = 282 },
    [302] = { name = "Stormwind City", continentID = 2, zoneID = 302 },
    [322] = { name = "Orgrimmar", continentID = 1, zoneID = 322 },
    [342] = { name = "Ironforge", continentID = 2, zoneID = 342 },
    [363] = { name = "Thunder Bluff", continentID = 1, zoneID = 363 },
    [382] = { name = "Darnassus", continentID = 1, zoneID = 382 },
    [383] = { name = "Undercity", continentID = 2, zoneID = 383 },
    [402] = { name = "Alterac Valley", continentID = 2, zoneID = 402 },
    [444] = { name = "Warsong Gulch", continentID = 1, zoneID = 444 },
    [462] = { name = "Arathi Basin", continentID = 2, zoneID = 462 },
    [463] = { name = "Eversong Woods", continentID = 2, zoneID = 463 },
    [464] = { name = "Ghostlands", continentID = 2, zoneID = 464 },
    [465] = { name = "Azuremyst Isle", continentID = 1, zoneID = 465 },
    [466] = { name = "Hellfire Peninsula", continentID = 3, zoneID = 466 },
    [467] = { name = "Expansion01", continentID = 3, zoneID = 467 }, 
    [468] = { name = "Zangarmarsh", continentID = 3, zoneID = 468 },
    [472] = { name = "The Exodar", continentID = 1, zoneID = 472 },
    [474] = { name = "Shadowmoon Valley", continentID = 3, zoneID = 474 },
    [476] = { name = "Blade's Edge Mountains", continentID = 3, zoneID = 476 },
    [477] = { name = "Bloodmyst Isle", continentID = 1, zoneID = 477 },
    [478] = { name = "Nagrand", continentID = 3, zoneID = 478 },
    [479] = { name = "Terokkar Forest", continentID = 3, zoneID = 479 },
    [480] = { name = "Netherstorm", continentID = 3, zoneID = 480 },
    [481] = { name = "Silvermoon City", continentID = 2, zoneID = 481 },
    [482] = { name = "Shattrath City", continentID = 3, zoneID = 482 },
    [483] = { name = "Netherstorm Arena", continentID = 3, zoneID = 483 },
    [486] = { name = "Northrend", continentID = 4, zoneID = 486 },
    [487] = { name = "Borean Tundra", continentID = 4, zoneID = 487 },
    [489] = { name = "Dragonblight", continentID = 4, zoneID = 489 },
    [491] = { name = "Grizzly Hills", continentID = 4, zoneID = 491 },
    [492] = { name = "Howling Fjord", continentID = 4, zoneID = 492 },
    [493] = { name = "Icecrown", continentID = 4, zoneID = 493 },
    [494] = { name = "Sholazar Basin", continentID = 4, zoneID = 494 },
    [496] = { name = "The Storm Peaks", continentID = 4, zoneID = 496 },
    [497] = { name = "Zul'Drak", continentID = 4, zoneID = 497 },
    [500] = { name = "Sunwell Plateau", continentID = 2, zoneID = 500 },
    [502] = { name = "Wintergrasp", continentID = 4, zoneID = 502 },
    [503] = { name = "Plaguelands: The Scarlet Enclave", continentID = 2, zoneID = 503 },
    [505] = { name = "Dalaran", continentID = 4, zoneID = 505 },
    [511] = { name = "Crystalsong Forest", continentID = 4, zoneID = 511 },
    [513] = { name = "Strand of the Ancients", continentID = 4, zoneID = 513 },
    [521] = { name = "The Nexus", continentID = 4, zoneID = 521 },
    [522] = { name = "The Culling of Stratholme", continentID = 2, zoneID = 522 },
    [523] = { name = "Ahn'kahet: The Old Kingdom", continentID = 4, zoneID = 523 },
    [524] = { name = "Utgarde Keep", continentID = 4, zoneID = 524 },
    [525] = { name = "Utgarde Pinnacle", continentID = 4, zoneID = 525 },
    [526] = { name = "Halls of Lightning", continentID = 4, zoneID = 526 },
    [527] = { name = "Halls of Stone", continentID = 4, zoneID = 527 },
    [528] = { name = "The Eye of Eternity", continentID = 4, zoneID = 528 },
    [529] = { name = "The Oculus", continentID = 4, zoneID = 529 },
    [530] = { name = "Ulduar", continentID = 4, zoneID = 530 },
    [531] = { name = "Gundrak", continentID = 4, zoneID = 531 },
    [532] = { name = "The Obsidian Sanctum", continentID = 4, zoneID = 532 },
    [533] = { name = "Vault of Archavon", continentID = 4, zoneID = 533 },
    [534] = { name = "Azjol-Nerub", continentID = 4, zoneID = 534 },
    [535] = { name = "Drak'Tharon Keep", continentID = 4, zoneID = 535 },
    [536] = { name = "Naxxramas", continentID = 4, zoneID = 536 },
    [537] = { name = "The Violet Hold", continentID = 4, zoneID = 537 },
    [538] = { name = "Naxxramas", continentID = 2, zoneID = 538 }, 
    [541] = { name = "Isle of Conquest", continentID = 4, zoneID = 541 },
    [542] = { name = "Hrothgar's Landing", continentID = 4, zoneID = 542 },
    [543] = { name = "Trial of the Champion", continentID = 4, zoneID = 543 },
    [544] = { name = "Trial of the Crusader", continentID = 4, zoneID = 544 },
    [602] = { name = "The Forge of Souls", continentID = 4, zoneID = 602 },
    [603] = { name = "Pit of Saron", continentID = 4, zoneID = 603 },
    [604] = { name = "Halls of Reflection", continentID = 4, zoneID = 604 },
    [605] = { name = "Icecrown Citadel", continentID = 4, zoneID = 605 },
    [610] = { name = "The Ruby Sanctum", continentID = 4, zoneID = 610 },
    [626] = { name = "Twisting Nether", continentID = 0, zoneID = 626 },
    [627] = { name = "Twin Peaks", continentID = 1, zoneID = 627 },
    [667] = { name = "Shadowfang Keep", continentID = 2, zoneID = 667 },
    [681] = { name = "Ragefire Chasm", continentID = 1, zoneID = 681 },
    [687] = { name = "Zul'Farrak", continentID = 1, zoneID = 687 },
    [689] = { name = "Blackfathom Deeps", continentID = 1, zoneID = 689 },
    [691] = { name = "The Stockade", continentID = 2, zoneID = 691 },
    [692] = { name = "Gnomeregan", continentID = 2, zoneID = 692 },
    [693] = { name = "Uldaman", continentID = 2, zoneID = 693 },
    [697] = { name = "Molten Core", continentID = 2, zoneID = 697 },
    [698] = { name = "Zul'Gurub", continentID = 2, zoneID = 698 },
    [700] = { name = "Dire Maul", continentID = 1, zoneID = 700 },
    [705] = { name = "Blackrock Depths", continentID = 2, zoneID = 705 },
    [711] = { name = "The Shattered Halls", continentID = 3, zoneID = 711 },
    [718] = { name = "Ruins of Ahn'Qiraj", continentID = 1, zoneID = 718 },
    [719] = { name = "Onyxia's Lair", continentID = 1, zoneID = 719 },
    [721] = { name = "Uldum", continentID = 1, zoneID = 721 },
    [722] = { name = "Blackrock Spire", continentID = 2, zoneID = 722 },
    [723] = { name = "Auchenai Crypts", continentID = 3, zoneID = 723 },
    [724] = { name = "Sethekk Halls", continentID = 3, zoneID = 724 },
    [725] = { name = "Shadow Labyrinth", continentID = 3, zoneID = 725 },
    [726] = { name = "The Blood Furnace", continentID = 3, zoneID = 726 },
    [727] = { name = "The Underbog", continentID = 3, zoneID = 727 },
    [728] = { name = "The Steamvault", continentID = 3, zoneID = 728 },
    [729] = { name = "The Slave Pens", continentID = 3, zoneID = 729 },
    [730] = { name = "The Botanica", continentID = 3, zoneID = 730 },
    [731] = { name = "The Mechanar", continentID = 3, zoneID = 731 },
    [732] = { name = "The Arcatraz", continentID = 3, zoneID = 732 },
    [733] = { name = "Mana-Tombs", continentID = 3, zoneID = 733 },
    [734] = { name = "The Black Morass", continentID = 1, zoneID = 734 },
    [735] = { name = "Old Hillsbrad Foothills", continentID = 2, zoneID = 735 },
    [750] = { name = "Wailing Caverns", continentID = 1, zoneID = 750 },
    [751] = { name = "Maraudon", continentID = 1, zoneID = 751 },
    [754] = { name = "Blackrock Caverns", continentID = 2, zoneID = 754 },
    [756] = { name = "Blackwing Lair", continentID = 2, zoneID = 756 },
    [757] = { name = "The Deadmines", continentID = 2, zoneID = 757 },
    [761] = { name = "Razorfen Downs", continentID = 1, zoneID = 761 },
    [762] = { name = "Razorfen Kraul", continentID = 1, zoneID = 762 },
    [763] = { name = "Scarlet Monastery", continentID = 2, zoneID = 763 },
    [764] = { name = "Scholomance", continentID = 2, zoneID = 764 },
    [765] = { name = "Shadowfang Keep", continentID = 2, zoneID = 765 },
    [766] = { name = "Stratholme", continentID = 2, zoneID = 766 },
    [767] = { name = "Temple of Ahn'Qiraj", continentID = 1, zoneID = 767 },
    [776] = { name = "Hyjal Summit", continentID = 1, zoneID = 776 },
    [777] = { name = "Gruul's Lair", continentID = 3, zoneID = 777 },
    [780] = { name = "Magtheridon's Lair", continentID = 3, zoneID = 780 },
    [781] = { name = "Serpentshrine Cavern", continentID = 3, zoneID = 781 },
    [782] = { name = "Zul'Aman", continentID = 2, zoneID = 782 },
    [783] = { name = "Tempest Keep", continentID = 3, zoneID = 783 },
    [790] = { name = "Sunwell Plateau", continentID = 2, zoneID = 790 },
    [794] = { name = "Zul'Gurub", continentID = 2, zoneID = 794 },
    [797] = { name = "Black Temple", continentID = 3, zoneID = 797 },
    [798] = { name = "Hellfire Ramparts", continentID = 3, zoneID = 798 },
    [799] = { name = "Magisters' Terrace", continentID = 2, zoneID = 799 },
    [800] = { name = "Karazhan", continentID = 2, zoneID = 800 },
    [1001] = { name = "RedridgeMountainsManastorm", continentID = 2, zoneID = 1001 },
    [1002] = { name = "AlteracMountainsManastorm", continentID = 2, zoneID = 1002 },
    [1003] = { name = "BlastedLandsManastorm", continentID = 2, zoneID = 1003 },
    [1004] = { name = "EasternPlaguelandsManastorm", continentID = 2, zoneID = 1004 },
    [1005] = { name = "FeralasManastorm", continentID = 1, zoneID = 1005 },
    [1006] = { name = "HillsbradFoothillsManastorm", continentID = 2, zoneID = 1006 },
    [1007] = { name = "SilverpineForestManastorm", continentID = 2, zoneID = 1007 },
    [1008] = { name = "TanarisManastorm", continentID = 1, zoneID = 1008 },
    [1009] = { name = "WesternPlaguelandsManastorm", continentID = 2, zoneID = 1009 },
    [1010] = { name = "WestfallManastorm", continentID = 2, zoneID = 1010 },
    [1011] = { name = "WinterSpringManastorm", continentID = 1, zoneID = 1011 },
    [1140] = { name = "Arathi Basin Winter", continentID = 2, zoneID = 1140 },
    [1141] = { name = "Warsong Gulch Winter", continentID = 1, zoneID = 1141 },
    [1142] = { name = "Twisting Nether Map", continentID = 0, zoneID = 1142 },
    [1143] = { name = "Twisting Nether Map", continentID = 0, zoneID = 1143 },
    [1144] = { name = "Twisting Nether Map", continentID = 0, zoneID = 1144 },
    [1145] = { name = "Forgotten Mine", continentID = 2, zoneID = 1145 },
    [1201] = { name = "Wailing Caverns (Entrance)", continentID = 1, zoneID = 1201 },
    [1202] = { name = "Scarlet Monastery (Entrance)", continentID = 2, zoneID = 1202 },
    [1203] = { name = "Caverns of Time (Interior)", continentID = 1, zoneID = 1203 },
    [1204] = { name = "Caverns of Time", continentID = 1, zoneID = 1204 },
    [1205] = { name = "Blackrock Mountain", continentID = 2, zoneID = 1205 },
    [1206] = { name = "Upper Blackrock Mountain", continentID = 2, zoneID = 1206 },
    [1207] = { name = "Lower Blackrock Mountain", continentID = 2, zoneID = 1207 },
    [1208] = { name = "Maraudon (Orange)", continentID = 1, zoneID = 1208 },
    [1209] = { name = "Maraudon (Purple)", continentID = 1, zoneID = 1209 },
    [1210] = { name = "Uldaman (Entrance)", continentID = 2, zoneID = 1210 },
    
    [1244] = { name = "Valley of Trials", continentID = 1, zoneID = 1244 },
    [1240] = { name = "Deathknell", continentID = 2, zoneID = 1240 },
    
     [1211] = { name = "Stillpine Hold", continentID = 1, zoneID = 1211 },
    [1212] = { name = "Tides' Hollow", continentID = 1, zoneID = 1212 },
    [1213] = { name = "Night Web's Hollow", continentID = 2, zoneID = 1213 },
    [1214] = { name = "Gol'Bolar Quarry", continentID = 2, zoneID = 1214 },
    [1215] = { name = "Coldridge Pass", continentID = 2, zoneID = 1215 },
    [1216] = { name = "The Grizzled Den", continentID = 2, zoneID = 1216 },
    [1217] = { name = "Burning Blade Coven", continentID = 1, zoneID = 1217 },
    [1218] = { name = "Dustwind Cave", continentID = 1, zoneID = 1218 },
    [1219] = { name = "Skull Rock", continentID = 1, zoneID = 1219 },
    [1220] = { name = "Fargodeep Mine (Upper)", continentID = 2, zoneID = 1220 },
    [1221] = { name = "Fargodeep Mine (Lower)", continentID = 2, zoneID = 1221 },
    [1222] = { name = "Jasperlode Mine", continentID = 2, zoneID = 1222 },
    [1223] = { name = "Amani Catacombs", continentID = 2, zoneID = 1223 },
    [1224] = { name = "Palemane Rock", continentID = 1, zoneID = 1224 },
    [1225] = { name = "The Venture Co. Mine", continentID = 1, zoneID = 1225 },
    [1226] = { name = "Echo Ridge Mine", continentID = 2, zoneID = 1226 },
    [1227] = { name = "Twilight's Run", continentID = 1, zoneID = 1227 },
    [1228] = { name = "The Noxious Lair", continentID = 1, zoneID = 1228 },
    [1229] = { name = "The Gaping Chasm", continentID = 1, zoneID = 1229 },
    [1230] = { name = "Ban'ethil Barrow Den (Upper)", continentID = 1, zoneID = 1230 },
    [1231] = { name = "Ban'ethil Barrow Den (Lower)", continentID = 1, zoneID = 1231 },
    [1232] = { name = "Fel Rock", continentID = 1, zoneID = 1232 },
    [1233] = { name = "Shadowthread Cave", continentID = 1, zoneID = 1233 },
    [1234] = { name = "The Slithering Scar", continentID = 1, zoneID = 1234 },
    [1235] = { name = "The Deadmines (Entrance)", continentID = 2, zoneID = 1235 },
    [1236] = { name = "Gold Coast Quarry", continentID = 2, zoneID = 1236 },
    [1237] = { name = "Jangolode Mine", continentID = 2, zoneID = 1237 },
    [1238] = { name = "Northshire Valley", continentID = 2, zoneID = 1238 },
    [1239] = { name = "Coldridge Valley", continentID = 2, zoneID = 1239 },
    [1240] = { name = "Deathknell", continentID = 2, zoneID = 1240 },
    [1241] = { name = "Sunstrider Isle", continentID = 2, zoneID = 1241 },
    [1242] = { name = "Ammen Vale", continentID = 1, zoneID = 1242 },
    [1243] = { name = "Shadowglen", continentID = 1, zoneID = 1243 },
    [1244] = { name = "Valley of Trials", continentID = 1, zoneID = 1244 },
    [1245] = { name = "Camp Narache", continentID = 1, zoneID = 1245 },
    [2001] = { name = "SpellDevMap", continentID = 0, zoneID = 2001 },
    [2002] = { name = "AlvaEncounter", continentID = 0, zoneID = 2002 },
    [2003] = { name = "Warsong Gulch (Updated)", continentID = 1, zoneID = 2003 },
    [2004] = { name = "Arathi Basin (Updated)", continentID = 2, zoneID = 2004 },
    [2005] = { name = "Stormwind Sewers", continentID = 2, zoneID = 2005 },
    [2006] = { name = "osrs4", continentID = 0, zoneID = 2006 },
    [2007] = { name = "AzzarFaire", continentID = 1, zoneID = 2007 },
    [2008] = { name = "Tiris Fortress", continentID = 2, zoneID = 2008 },
    [2009] = { name = "zamasucombat", continentID = 0, zoneID = 2009 },
    [2010] = { name = "AzzarFaire", continentID = 1, zoneID = 2010 },
    [2011] = { name = "AzzarFaire2", continentID = 1, zoneID = 2011 },
    [2012] = { name = "Tol Barad", continentID = 2, zoneID = 2012 },
    [2013] = { name = "Karazhan Crypts", continentID = 2, zoneID = 2013 },
    [2014] = { name = "TwistingNetherMap", continentID = 0, zoneID = 2014 },
    [2015] = { name = "BloodmystIsleManastorm", continentID = 1, zoneID = 2015 },
    [2016] = { name = "GhostlandsManastorm", continentID = 2, zoneID = 2016 },
    [2017] = { name = "HellfirePeninsulaManastorm", continentID = 3, zoneID = 2017 },
    [2018] = { name = "NagrandManastorm", continentID = 3, zoneID = 2018 },
    [2019] = { name = "ShadowmoonValleyManastorm", continentID = 3, zoneID = 2019 },
    [2020] = { name = "ZangarmarshManastorm", continentID = 3, zoneID = 2020 },
    [2021] = { name = "Orgrimmar Depths", continentID = 1, zoneID = 2021 },
    [2022] = { name = "The Temple of Atal'hakkar", continentID = 2, zoneID = 2022 },
    [2023] = { name = "Northrend2", continentID = 4, zoneID = 2023 },
    [2024] = { name = "Deeprun Tram", continentID = 2, zoneID = 2024 },
    [2025] = { name = "Tor Watha", continentID = 2, zoneID = 2025 },
    [2026] = { name = "Orgrimmar Depths (Underroof)", continentID = 1, zoneID = 2026 },
    [2027] = { name = "Stormwind Sewers (Shade)", continentID = 2, zoneID = 2027 },
    [2028] = { name = "Shadewell Spring", continentID = 2, zoneID = 2028 },
    [2029] = { name = "Secret Inquisitorial Dungeon", continentID = 2, zoneID = 2029 },
    [2030] = { name = "Sinister Lair", continentID = 1, zoneID = 2030 },
    [2031] = { name = "Moonlit Ossuary", continentID = 1, zoneID = 2031 },
};

ZoneList.OldToNewZoneMap = {
    
    ["1:2"] = { c=1, z=44 },   
    ["1:3"] = { c=1, z=182 },  
    ["1:4"] = { c=1, z=465 },  
    ["1:6"] = { c=1, z=477 },  
    ["1:9"] = { c=1, z=43 },   
    ["1:11"] = { c=1, z=102 }, 
    ["1:12"] = { c=1, z=5 },   
    ["1:13"] = { c=1, z=142 }, 
    ["1:16"] = { c=1, z=183 }, 
    ["1:17"] = { c=1, z=122 }, 
    ["1:19"] = { c=1, z=242 }, 
    ["1:21"] = { c=1, z=10 },  
    ["1:27"] = { c=1, z=262 }, 
    ["1:31"] = { c=1, z=82 },  
    ["1:32"] = { c=1, z=162 }, 
    ["1:33"] = { c=1, z=42 },  
    ["1:34"] = { c=1, z=12 },  
    ["1:40"] = { c=1, z=62 },  
    ["1:44"] = { c=1, z=202 }, 
    ["1:47"] = { c=1, z=282 }, 
    
    ["1:1"] = { c=1, z=1242 }, 
    ["1:10"] = { c=1, z=382 }, 
    ["1:22"] = { c=1, z=322 }, 
    ["1:24"] = { c=1, z=1245 },
    ["1:25"] = { c=1, z=1243 },
    ["1:35"] = { c=1, z=472 }, 
    ["1:41"] = { c=1, z=363 }, 
    ["1:45"] = { c=1, z=1244 },
    
    ["1:8"] = { c=1, z=1204 }, 
    ["1:18"] = { c=1, z=751 }, 
    ["1:46"] = { c=1, z=750 }, 

    
    ["2:1"] = { c=2, z=16 },   
    ["2:3"] = { c=2, z=17 },   
    ["2:4"] = { c=2, z=18 },   
    ["2:6"] = { c=2, z=20 },   
    ["2:7"] = { c=2, z=30 },   
    ["2:10"] = { c=2, z=33 },  
    ["2:12"] = { c=2, z=28 },  
    ["2:13"] = { c=2, z=35 },  
    ["2:14"] = { c=2, z=24 },  
    ["2:16"] = { c=2, z=31 },  
    ["2:17"] = { c=2, z=463 }, 
    ["2:19"] = { c=2, z=464 }, 
    ["2:22"] = { c=2, z=25 },  
    ["2:27"] = { c=2, z=36 },  
    ["2:30"] = { c=2, z=37 },  
    ["2:32"] = { c=2, z=29 },  
    ["2:36"] = { c=2, z=22 },  
    ["2:38"] = { c=2, z=38 },  
    ["2:40"] = { c=2, z=39 },  
    ["2:43"] = { c=2, z=27 },  
    ["2:44"] = { c=2, z=21 },  
    ["2:47"] = { c=2, z=23 },  
    ["2:48"] = { c=2, z=40 },  
    ["2:49"] = { c=2, z=41 },  
    
    ["2:9"] = { c=2, z=1239 }, 
    ["2:11"] = { c=2, z=1240 },
    ["2:23"] = { c=2, z=342 }, 
    ["2:29"] = { c=2, z=1238 },
    ["2:35"] = { c=2, z=481 }, 
    ["2:37"] = { c=2, z=302 }, 
    ["2:39"] = { c=2, z=1241 },
    ["2:46"] = { c=2, z=383 }, 
    
    ["2:5"] = { c=2, z=1205 }, 
    ["2:24"] = { c=2, z=799 }, 
    ["2:31"] = { c=2, z=763 }, 
    ["2:41"] = { c=2, z=757 }, 
    ["2:45"] = { c=2, z=693 }, 

    
    ["3:1"] = { c=3, z=476 },  
    ["3:2"] = { c=3, z=466 },  
    ["3:3"] = { c=3, z=478 },  
    ["3:4"] = { c=3, z=480 },  
    ["3:5"] = { c=3, z=474 },  
    ["3:6"] = { c=3, z=482 },  
    ["3:7"] = { c=3, z=479 },  
    ["3:8"] = { c=3, z=468 },  

    
    ["4:1"] = { c=4, z=487 },  
    ["4:2"] = { c=4, z=511 },  
    ["4:3"] = { c=4, z=505 },  
    ["4:4"] = { c=4, z=489 },  
    ["4:5"] = { c=4, z=491 },  
    ["4:6"] = { c=4, z=492 },  
    ["4:7"] = { c=4, z=542 },  
    ["4:8"] = { c=4, z=493 },  
    ["4:9"] = { c=4, z=494 },  
    ["4:10"] = { c=4, z=496 }, 
    ["4:11"] = { c=4, z=502 }, 
    ["4:12"] = { c=4, z=497 }, 
};

ZoneList.mapIdToZoneInfo = ZoneList.mapIdToZoneInfo or {}
ZoneList.zoneInfoToMapId = ZoneList.zoneInfoToMapId or {}

ZoneList.ZoneData = ZoneList.ZoneData or {
    [1] = { 
        [1] = "Ammen Vale", [2] = "Ashenvale", [3] = "Azshara", [4] = "Azuremyst Isle", [5] = "Ban'ethil Barrow Den", [6] = "Bloodmyst Isle", [7] = "Burning Blade Coven", [8] = "Caverns of Time", [9] = "Darkshore", [10] = "Darnassus", [11] = "Desolace", [12] = "Durotar", [13] = "Dustwallow Marsh", [14] = "Dustwind Cave", [15] = "Fel Rock", [16] = "Felwood", [17] = "Feralas", [18] = "Maraudon", [19] = "Moonglade", [20] = "Moonlit Ossuary", [21] = "Mulgore", [22] = "Orgrimmar", [23] = "Palemane Rock", [24] = "Camp Narache", [25] = "Shadowglen", [26] = "Shadowthread Cave", [27] = "Silithus", [28] = "Sinister Lair", [29] = "Skull Rock", [30] = "Stillpine Hold", [31] = "Stonetalon Mountains", [32] = "Tanaris", [33] = "Teldrassil", [34] = "The Barrens", [35] = "The Exodar", [36] = "The Gaping Chasm", [37] = "The Noxious Lair", [38] = "The Slithering Scar", [39] = "The Venture Co. Mine", [40] = "Thousand Needles", [41] = "Thunder Bluff", [42] = "Tides' Hollow", [43] = "Twilight's Run", [44] = "Un'Goro Crater", [45] = "Valley of Trials", [46] = "Wailing Caverns", [47] = "Winterspring",
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
    
    ["Ragefire Chasm"]="rfc", ["Wailing Caverns"]="wc", ["The Deadmines"]="dm", ["Shadowfang Keep"]="sfk", ["The Stockade"]="stocks", ["Blackfathom Deeps"]="bfd", ["Gnomeregan"]="gnomer", ["Razorfen Kraul"]="rfk", ["Scarlet Monastery"]="sm", ["Razorfen Downs"]="rfd", ["Uldaman"]="uld", ["Zul'Farrak"]="zf", ["Maraudon"]="mara", ["The Temple of Atal'hakkar"]="st", ["Blackrock Depths"]="brd", ["Dire Maul"]="dme", ["Lower Blackrock Spire"]="lbrs", ["Upper Blackrock Spire"]="ubrs", ["Scholomance"]="scholo", ["Stratholme"]="strat", ["Molten Core"]="mc", ["Onyxia's Lair"]="ony", ["Blackwing Lair"]="bwl", ["Zul'Gurub"]="zg", ["Ruins of Ahn'Qiraj"]="aq20", ["Temple of Ahn'Qiraj"]="aq40", ["Hellfire Ramparts"]="hfr", ["The Blood Furnace"]="bf", ["The Shattered Halls"]="shh", ["The Slave Pens"]="sp", ["The Underbog"]="ub", ["The Steamvault"]="sv", ["Mana-Tombs"]="mt", ["Auchenai Crypts"]="ac", ["Sethekk Halls"]="sh", ["Shadow Labyrinth"]="sl", ["Escape from Durnholde Keep"]="ohf", ["Opening the Dark Portal"]="bm", ["The Mechanar"]="mech", ["The Botanica"]="bot", ["The Arcatraz"]="arc", ["Magisters' Terrace"]="mgt", ["Karazhan"]="kara", ["Gruul's Lair"]="gruul", ["Magtheridon's Lair"]="mag", ["Utgarde Keep"]="uk", ["The Nexus"]="nex", ["Ahn'kahet: The Old Kingdom"]="an", ["Azjol-Nerub"]="an", ["Drak'Tharon Keep"]="dtk", ["The Violet Hold"]="vh", ["Gundrak"]="gd", ["Halls of Stone"]="hos", ["Halls of Lightning"]="hol", ["Utgarde Pinnacle"]="up", ["The Culling of Stratholme"]="cos", ["The Oculus"]="ocu", ["Forge of Souls"]="fos", ["Pit of Saron"]="pos", ["Halls of Reflection"]="hor", ["Trial of the Champion"]="toc", ["Naxxramas"]="naxx", ["Vault of Archavon"]="voa", ["The Obsidian Sanctum"]="os", ["The Eye of Eternity"]="eoe", ["Ulduar"]="ulduar", ["Trial of the Crusader"]="toc", ["Icecrown Citadel"]="icc", ["The Ruby Sanctum"]="rs", ["Eonar's Cradle"]="ec", ["Forgotten Mine"]="fm", ["Frozen Reach"]="fr", ["Gronn's Spine"]="gs", ["Iskirr Village"]="iv", ["Ocean Battle"]="ob", ["Ocean's Sword"]="osw", ["Pools of the Eidola"]="poe", ["Temple of Eternity"]="toe", ["The Grim Marsh"]="gm", ["The Karazhan Crypts"]="kc", ["Unused Monastery"]="um", ["The Black Morass"]="bm", ["AzzarEvent"]="aze", ["Battle Royal"]="br", ["Black Temple"]="bt", ["Alterac Valley"]="av", ["Arathi Basin"]="ab", ["Eye of the Storm"]="eos", ["Isle of Conquest"]="ioc", ["Southshore vs. Tarren Mill"]="svst", ["Strand of the Ancients"]="sota", ["Temple of Kotmogu"]="tok", ["Twin Peaks"]="tp", ["Warsong Gulch"]="wsg", 
    
    
    ["Arathi Highlands"]="AH",
    ["Ashenvale"]="Ash",
    ["Azshara"]="Azs",
    ["Azuremyst Isle"]="Azure",
    ["Badlands"]="BL",
    ["Blasted Lands"]="Blasted",
    ["Bloodmyst Isle"]="Bloodmyst",
    ["Burning Steppes"]="Burning",
    ["Darkshore"]="Darkshore",
    ["Deadwind Pass"]="Deadwind",
    ["Desolace"]="Desolace",
    ["Dun Morogh"]="Dun Morogh",
    ["Durotar"]="Durotar",
    ["Duskwood"]="Duskwood",
    ["Dustwallow Marsh"]="Dustwallow",
    ["Eastern Plaguelands"]="EPL",
    ["Elwynn Forest"]="Elwynn",
    ["Eversong Woods"]="Eversong",
    ["Felwood"]="Felwood",
    ["Feralas"]="Feralas",
    ["Ghostlands"]="Ghostlands",
    ["Hillsbrad Foothills"]="Hillsbrad",
    ["Loch Modan"]="Loch Modan",
    ["Moonglade"]="Moonglade",
    ["Mulgore"]="Mulgore",
    ["Redridge Mountains"]="Redridge",
    ["Searing Gorge"]="Searing",
    ["Silverpine Forest"]="Silverpine",
    ["Silithus"]="Silithus",
    ["Stonetalon Mountains"]="Stonetalon",
    ["Stranglethorn Vale"]="STV",
    ["Swamp of Sorrows"]="Swamp",
    ["Tanaris"]="Tanaris",
    ["Teldrassil"]="Teldrassil",
    ["The Barrens"]="Barrens",
    ["The Hinterlands"]="Hinterlands",
    ["Thousand Needles"]="1k Needles",
    ["Tirisfal Glades"]="Tirisfal",
    ["Un'Goro Crater"]="Un'Goro",
    ["Western Plaguelands"]="WPL",
    ["Westfall"]="Westfall",
    ["Wetlands"]="Wetlands",
    ["Winterspring"]="Winterspring",
	["Northshire Valley"] = "Nths Valley",
}

ZoneList.InstanceZones = ZoneList.InstanceZones or {
    [1]="Ragefire Chasm", [2]="Wailing Caverns", [3]="The Deadmines", [4]="Shadowfang Keep", [5]="The Stockade", [6]="Blackfathom Deeps", [7]="Gnomeregan", [8]="Razorfen Kraul", [9]="Scarlet Monastery", [10]="Razorfen Downs", [11]="Uldaman", [12]="Zul'Farrak", [13]="Maraudon", [14]="The Temple of Atal'hakkar", [15]="Blackrock Depths", [16]="Dire Maul", [17]="Lower Blackrock Spire", [18]="Upper Blackrock Spire", [19]="Scholomance", [20]="Stratholme", [21]="Molten Core", [22]="Onyxia's Lair", [23]="Blackwing Lair", [24]="Zul'Gurub", [25]="Ruins of Ahn'Qiraj", [26]="Temple of Ahn'Qiraj", [27]="Hellfire Ramparts", [28]="The Blood Furnace", [29]="The Shattered Halls", [30]="The Slave Pens", [31]="The Underbog", [32]="The Steamvault", [33]="Mana-Tombs", [34]="Auchenai Crypts", [35]="Sethekk Halls", [36]="Shadow Labyrinth", [37]="Escape from Durnholde Keep", [38]="Opening the Dark Portal", [39]="The Mechanar", [40]="The Botanica", [41]="The Arcatraz", [42]="Magisters' Terrace", [43]="Karazhan", [44]="Gruul's Lair", [45]="Magtheridon's Lair", [46]="Utgarde Keep", [47]="The Nexus", [48]="Ahn'kahet: The Old Kingdom", [49]="Azjol-Nerub", [50]="Drak'Tharon Keep", [51]="The Violet Hold", [52]="Gundrak", [53]="Halls of Stone", [54]="Halls of Lightning", [55]="Utgarde Pinnacle", [56]="The Culling of Stratholme", [57]="The Oculus", [58]="Forge of Souls", [59]="Pit of Saron", [60]="Halls of Reflection", [61]="Trial of the Champion", [62]="Naxxramas", [63]="Vault of Archavon", [64]="The Obsidian Sanctum", [65]="The Eye of Eternity", [66]="Ulduar", [67]="Onyxia's Lair", [68]="Trial of the Crusader", [69]="Icecrown Citadel", [70]="The Ruby Sanctum", [71]="Eonar's Cradle", [72]="Forgotten Mine", [73]="Frozen Reach", [74]="Gronn's Spine", [75]="Iskirr Village", [76]="Ocean Battle", [77]="Ocean's Sword", [78]="Pools of the Eidola", [79]="Temple of Eternity", [80]="The Grim Marsh", [81]="The Karazhan Crypts", [82]="Unused Monastery", [83]="The Black Morass", [84]="AzzarEvent", [85]="Battle Royal", [86]="Black Temple", [87]="Alterac Valley", [88]="Arathi Basin", [89]="Eye of the Storm", [90]="Isle of Conquest", [91]="Southshore vs. Tarren Mill", [92]="Strand of the Ancients", [93]="Temple of Kotmogu", [94]="Twin Peaks", [95]="Warsong Gulch",
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
    if not self.MapDataByID then return end

    wipe(self.mapIdToZoneInfo)
    wipe(self.zoneInfoToMapId)

    local count = 0
    for mapID, data in pairs(self.MapDataByID) do
        if data.continentID and data.zoneID then
            local key = data.continentID .. ":" .. data.zoneID
            self.mapIdToZoneInfo[mapID] = data
            self.zoneInfoToMapId[key] = mapID
            count = count + 1
        end
    end

    if SetMapToCurrentZone then SetMapToCurrentZone() end
end

function ZoneList:GetZoneName(continent, zoneID, third, fourth)
    local c = tonumber(continent) or 0
    local z = tonumber(zoneID) or 0 
    local iz = (type(third) == "number" and fourth == nil and tonumber(third)) or (tonumber(fourth) or 0)

    
    
    local mapData = self.MapDataByID[z]
    if mapData then
        return mapData.name
    end
    
    
    
    if z > 0 and z == GetCurrentMapAreaID() then
        local realZone = GetRealZoneText()
        if realZone and realZone ~= "" then
            return realZone
        end
    end
    
    
    
    local cdata = self.ZoneData[c]
    if cdata and cdata[z] then
        return cdata[z]
    end

    local zones = GetMapZonesArray(c)
    if zones and zones[z] then
        return zones[z]
    end
    
    
    return (GetRealZoneText and GetRealZoneText()) or "Unknown Zone"
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
    
    
    local legacyInstanceName = self.InstanceZones[tonumber(iz) or 0]
    if not legacyInstanceName then return nil end

    
    for mapID, data in pairs(self.MapDataByID) do
        if data.name == legacyInstanceName or data.altName == legacyInstanceName or data.altName2 == legacyInstanceName then
            return data.name 
        end
    end
    
    return legacyInstanceName 
end

function ZoneList:GetCurrentZoneDisplay()
    local mapID = GetCurrentMapAreaID()
    local mapData = self.MapDataByID[mapID]

    if mapData then
        return 0, mapData.name, mapData.continentID, mapData.zoneID
    end

    
    local c = (type(GetCurrentMapContinent) == "function" and GetCurrentMapContinent()) or 0
    local z = (type(GetCurrentMapZone) == "function" and GetCurrentMapZone()) or 0
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
        L._debug("ZoneList-Abbrev", "Building instance abbreviation map...")
        
        for iz, legacyInstanceName in pairs(self.InstanceZones) do
            local canonicalName = legacyInstanceName
            for mapID, data in pairs(self.MapDataByID) do
                if data.name == legacyInstanceName or data.altName == legacyInstanceName or data.altName2 == legacyInstanceName then
                    canonicalName = data.name
                    break
                end
            end
            
            
            if self.ZONEABBREVIATIONS[canonicalName] then
                local abbreviation = self.ZONEABBREVIATIONS[canonicalName]
                
                
                local modernMapID
                for mapID, data in pairs(self.MapDataByID) do
                    if data.name == canonicalName then
                        modernMapID = mapID
                        break
                    end
                end

                
                if modernMapID and not self.IZ_TO_ABBREVIATIONS[modernMapID] then
                    self.IZ_TO_ABBREVIATIONS[modernMapID] = abbreviation
                    count = count + 1
                    L._debug("ZoneList-Abbrev", string.format(" -> SUCCESS: Mapped mapID %d ('%s') to abbreviation '%s'", modernMapID, canonicalName, abbreviation))
                end
            end
        end
        L._debug("ZoneList-Abbrev", "Finished building map. Total abbreviations mapped: " .. count)
    end

    C_Timer.After(1, function()
        if self.BuildMapIDLookups then
            self:BuildMapIDLookups()
        end
    end)
end

return ZoneList