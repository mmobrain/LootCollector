-- Map.lua
-- Item-icon pins on the world map, sticky tooltip with right-side hover icon,
-- LC filter menu via EasyMenu, and optional minimap edge indicators for discoveries.
-- REFACTORED: Now uses an efficient, internal positioning engine inspired by Astrolabe.
-- OPTIMIZED: Minimap pin updates are now handled by a single, centralized timer instead of per-pin OnUpdate scripts.
-- UNK.B64.UTF-8


local L = LootCollector
local Map = L:NewModule("Map", "AceEvent-3.0")

local PIN_FALLBACK_TEXTURE = "Interface\\AddOns\\LootCollector\\media\\pin"

Map.pins = Map.pins or {}
Map._pinnedPin = nil

Map._hoverBtn = Map._hoverBtn or nil
Map._hoverBtnItemLink = nil

local itemInfoTooltip = nil

local DropFrame = CreateFrame("Frame", "LootCollectorPinDropDown", UIParent, "UIDropDownMenuTemplate")
local menuList = {}

Map._pinsByMid = Map._pinsByMid or {}

Map._searchFrame = nil
Map._searchBox = nil
Map._searchResultsFrame = nil 
Map._searchTimer = nil

Map._showToDialog = nil

Map._cachedFriends = {}
Map._cachedGuild = {}
Map._cachedRecent = {}
Map.MAX_RECENT_NAMES = 15 

local mapOverlay

Map._bmItemLines = Map._bmItemLines or {}
local BM_LINE_HEIGHT = 20
local BM_ICON_SIZE_IN_LINE = 18

Map.clusterPins = Map.clusterPins or {}
local CLUSTER_PIN_SIZE = 32
local CLUSTER_PIN_BACKGROUND_TEXTURE = "Interface\\AddOns\\LootCollector\\media\\pin"

local IST_TO_EQUIPLOC = {
    
    [1] = "INVTYPE_CLOTH",
    [2] = "INVTYPE_LEATHER",
    [3] = "INVTYPE_MAIL",
    [4] = "INVTYPE_PLATE",
    [5] = "INVTYPE_SHIELD",
    [6] = "INVTYPE_LIBRAM",
    [7] = "INVTYPE_IDOL",
    [8] = "INVTYPE_TOTEM",
    [9] = "INVTYPE_SIGIL",
    
    [30] = "INVTYPE_WEAPON", 
    [34] = "INVTYPE_WEAPON", 
    [37] = "INVTYPE_WEAPON", 
    [40] = "INVTYPE_WEAPON", 
    [41] = "INVTYPE_DAGGER",
    
    [31] = "INVTYPE_2HWEAPON", 
    [35] = "INVTYPE_2HWEAPON", 
    [38] = "INVTYPE_2HWEAPON", 
    [36] = "INVTYPE_2HWEAPON", 
    [39] = "INVTYPE_2HWEAPON", 
    
    [32] = "INVTYPE_RANGED", 
    [33] = "INVTYPE_RANGEDRIGHT", 
    [43] = "INVTYPE_RANGEDRIGHT", 
    [44] = "INVTYPE_RANGED", 
    [42] = "INVTYPE_THROWN",
    
    [45] = "INVTYPE_FISHINGPOLE",
}

local SOURCE_TEXT_MAP = {
    world_loot = "Drop / Object Interaction",
    npc_gossip = "NPC Interaction",
    emote_event = "Event / emote",
    direct = "Object Interaction / other",
}

local QUALITY_COLORS_PIN = {
  [0] = { r = 0.6, g = 0.6, b = 0.6 },   
  [1] = { r = 1.0, g = 1.0, b = 1.0 },   
  [2] = { r = 0.1, g = 0.8, b = 0.1 },   
  [3] = { r = 0.1, g = 0.5, b = 1.0 },   
  [4] = { r = 0.7, g = 0.3, b = 1.0 },   
  [5] = { r = 1.0, g = 0.5, b = 0.0 },   
  [6] = { r = 0.8, g = 0.5, b = 0.2 },   
  [7] = { r = 0.9, g = 0.8, b = 0.5 },   
}

local MinimapSize = {
	indoor = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80,  [5] = 50 },
	outdoor = { [0] = 466 + 2/3, [1] = 400, [2] = 333 + 1/3, [3] = 266 + 2/3, [4] = 200, [5] = 133 + 1/3 },
}

Map.WorldMapSize = {
    [1] = {
        zoneData = { [2]="Ashenvale", [3]="Azshara", [4]="Azuremyst Isle", [6]="Bloodmyst Isle", [9]="Darkshore", [10]="Darnassus", [11]="Desolace", [12]="Durotar", [13]="Dustwallow Marsh", [16]="Felwood", [17]="Feralas", [18]="Maraudon", [19]="Moonglade", [21]="Mulgore", [22]="Orgrimmar", [27]="Silithus", [31]="Stonetalon Mountains", [32]="Tanaris", [33]="Teldrassil", [34]="The Barrens", [35]="The Exodar", [40]="Thousand Needles", [41]="Thunder Bluff", [44]="Un'Goro Crater", [46]="Wailing Caverns", [47]="Winterspring" },
        [2] = { height = 3843.72, width = 5766.72, xOffset = 15366.76, yOffset = 8126.92 },
        [3] = { height = 3381.22, width = 5070.88, xOffset = 20343.90, yOffset = 7458.18 },
        [4] = { height = 2714.56, width = 4070.87, xOffset = 9966.70, yOffset = 5460.27 },
        [6] = { height = 2174.98, width = 3262.53, xOffset = 9541.70, yOffset = 3424.87 },
        [9] = { height = 4366.63, width = 6550.07, xOffset = 14125.08, yOffset = 4466.53 },
        [11] = { height = 2997.89, width = 4495.88, xOffset = 12833.40, yOffset = 12347.72 },
        [12] = { height = 3524.97, width = 5287.55, xOffset = 19029.30, yOffset = 10991.48 },
        [13] = { height = 3499.97, width = 5250.05, xOffset = 18041.79, yOffset = 14833.12 },
        [16] = { height = 3833.30, width = 5750.06, xOffset = 15425.10, yOffset = 5666.52 },
        [17] = { height = 4633.30, width = 6950.07, xOffset = 11625.05, yOffset = 15166.45 },
        [19] = { height = 1539.57, width = 2308.35, xOffset = 18448.04, yOffset = 4308.20 },
        [21] = { height = 3424.97, width = 5137.55, xOffset = 15018.84, yOffset = 13072.72 },
        [27] = { height = 2322.90, width = 3483.37, xOffset = 14529.25, yOffset = 18758.10 },
        [31] = { height = 3256.22, width = 4883.38, xOffset = 13820.91, yOffset = 9883.16 },
        [32] = { height = 4599.96, width = 6900.07, xOffset = 17285.53, yOffset = 18674.76 },
        [33] = { height = 3393.72, width = 5091.72, xOffset = 13252.16, yOffset = 968.64 },
        [34] = { height = 6756.20, width = 10133.44, xOffset = 14443.84, yOffset = 11187.32 },
        [40] = { height = 2933.31, width = 4400.04, xOffset = 17500.12, yOffset = 16766.44 },
        [44] = { height = 2466.64, width = 3700.03, xOffset = 16533.44, yOffset = 18766.43 },
        [47] = { height = 4733.29, width = 7100.07, xOffset = 17383.45, yOffset = 4266.53 },
    },
    [2] = {
        zoneData = { [1]="Alterac Mountains", [3]="Arathi Highlands", [4]="Badlands", [6]="Blasted Lands", [7]="Burning Steppes", [10]="Deadwind Pass", [12]="Dun Morogh", [13]="Duskwood", [14]="Eastern Plaguelands", [16]="Elwynn Forest", [17]="Eversong Woods", [19]="Ghostlands", [22]="Hillsbrad Foothills", [23]="Ironforge", [24]="Isle of Quel'Danas", [27]="Loch Modan", [30]="Redridge Mountains", [32]="Searing Gorge", [35]="Silvermoon City", [36]="Silverpine Forest", [37]="Stormwind City", [38]="Stranglethorn Vale", [40]="Swamp of Sorrows", [43]="The Hinterlands", [44]="Tirisfal Glades", [46]="Undercity", [47]="Western Plaguelands", [48]="Westfall", [49]="Wetlands" },
        [1] = { height = 1866.67, width = 2799.99, xOffset = 17388.63, yOffset = 9676.38 },
        [3] = { height = 2400.00, width = 3599.99, xOffset = 19038.63, yOffset = 11309.72 },
        [4] = { height = 1658.34, width = 2487.50, xOffset = 20251.13, yOffset = 17065.99 },
        [6] = { height = 2233.34, width = 3349.99, xOffset = 19413.63, yOffset = 21743.09 },
        [7] = { height = 1952.09, width = 2929.16, xOffset = 18438.63, yOffset = 18207.66 },
        [10] = { height = 1666.67, width = 2499.99, xOffset = 19005.30, yOffset = 21043.09 },
        [12] = { height = 3283.34, width = 4925.00, xOffset = 16369.88, yOffset = 15053.48 },
        [13] = { height = 1800.00, width = 2699.99, xOffset = 17338.63, yOffset = 20893.09 },
        [14] = { height = 2687.51, width = 4031.24, xOffset = 20459.46, yOffset = 7472.20 },
        [16] = { height = 2314.59, width = 3470.83, xOffset = 16636.55, yOffset = 19116.00 },
        [17] = { height = 3283.34, width = 4925.00, xOffset = 20259.46, yOffset = 2534.68 },
        [19] = { height = 2200.00, width = 3300.00, xOffset = 21055.29, yOffset = 5309.69 },
        [22] = { height = 2133.34, width = 3199.99, xOffset = 17105.30, yOffset = 10776.38 },
        [27] = { height = 1839.58, width = 2758.33, xOffset = 20165.71, yOffset = 15663.90 },
        [30] = { height = 1447.92, width = 2170.83, xOffset = 19742.80, yOffset = 19751.42 },
        [32] = { height = 1487.50, width = 2231.24, xOffset = 18494.88, yOffset = 17276.41 },
        [36] = { height = 2800.01, width = 4199.99, xOffset = 14721.96, yOffset = 9509.71 },
        [38] = { height = 4254.18, width = 6381.24, xOffset = 15951.13, yOffset = 22345.18 },
        [40] = { height = 1529.17, width = 2293.75, xOffset = 20394.88, yOffset = 20797.25 },
        [43] = { height = 2566.67, width = 3849.99, xOffset = 19746.96, yOffset = 9709.71 },
        [44] = { height = 3012.51, width = 4518.74, xOffset = 15138.63, yOffset = 7338.87 },
        [47] = { height = 2866.67, width = 4299.99, xOffset = 17755.30, yOffset = 7809.70 },
        [48] = { height = 2333.34, width = 3499.99, xOffset = 15155.30, yOffset = 20576.42 },
        [49] = { height = 2756.26, width = 4135.41, xOffset = 18561.55, yOffset = 13324.31 },
    },
    [3] = {
        zoneData = { [1]="Blade's Edge Mountains", [2]="Hellfire Peninsula", [3]="Nagrand", [4]="Netherstorm", [5]="Shadowmoon Valley", [6]="Shattrath City", [7]="Terokkar Forest", [8]="Zangarmarsh" },
        [1] = { height = 3616.55, width = 5424.97, xOffset = 4150.18, yOffset = 1412.98 },
        [2] = { height = 3443.64, width = 5164.55, xOffset = 7456.41, yOffset = 4339.97 },
        [3] = { height = 3683.21, width = 5524.97, xOffset = 2700.19, yOffset = 5779.51 },
        [4] = { height = 3716.55, width = 5574.97, xOffset = 7512.66, yOffset = 365.09 },
        [5] = { height = 3666.55, width = 5499.97, xOffset = 8770.99, yOffset = 7769.03 },
        [7] = { height = 3599.88, width = 5399.97, xOffset = 5912.67, yOffset = 6821.14 },
        [8] = { height = 3351.97, width = 5027.05, xOffset = 3521.02, yOffset = 3885.82 },
    },
    [4] = {
        zoneData = { [1]="Borean Tundra", [2]="Crystalsong Forest", [3]="Dalaran", [4]="Dragonblight", [5]="Grizzly Hills", [6]="Howling Fjord", [8]="Icecrown", [9]="Sholazar Basin", [10]="The Storm Peaks", [11]="Wintergrasp", [12]="Zul'Drak" },
        [1] = { height = 3843.76, width = 5764.58, xOffset = 646.31, yOffset = 5695.48 },
        [2] = { height = 1814.59, width = 2722.91, xOffset = 7773.40, yOffset = 4091.30 },
        [4] = { height = 3739.59, width = 5608.33, xOffset = 5590.06, yOffset = 5018.39 },
        [5] = { height = 3500.01, width = 5249.99, xOffset = 10327.56, yOffset = 5076.72 },
        [6] = { height = 4031.26, width = 6045.83, xOffset = 10615.06, yOffset = 7476.73 },
        [8] = { height = 4181.26, width = 6270.83, xOffset = 3773.40, yOffset = 1166.29 },
        [9] = { height = 2904.17, width = 4356.24, xOffset = 2287.98, yOffset = 3305.88 },
        [10] = { height = 4741.68, width = 7112.49, xOffset = 7375.48, yOffset = 395.46 },
        [11] = { height = 1983.34, width = 2974.99, xOffset = 4887.98, yOffset = 4876.72 },
        [12] = { height = 3329.17, width = 4993.74, xOffset = 9817.15, yOffset = 2924.63 },
    },
};

local function getContPosition(c, z, x, y)
    local continentData = Map.WorldMapSize[c]
    if not continentData then return end
    local zoneData = continentData[z]
    if not zoneData then return end
    x = x * zoneData.width + zoneData.xOffset
    y = y * zoneData.height + zoneData.yOffset
    return x, y
end

local function ComputeDistance(c1, z1, x1, y1, c2, z2, x2, y2)
    if c1 ~= c2 then return end 
    local xDelta, yDelta
    if z1 == z2 then
        local zoneData = Map.WorldMapSize[c1] and Map.WorldMapSize[c1][z1]
        if not zoneData then return end
        xDelta = (x2 - x1) * zoneData.width
        yDelta = (y2 - y1) * zoneData.height
    else
        x1, y1 = getContPosition(c1, z1, x1, y1)
        x2, y2 = getContPosition(c2, z2, x2, y2)
        if not x1 or not x2 then return end
        xDelta = x2 - x1
        yDelta = y2 - y1
    end
    if xDelta and yDelta then
        return math.sqrt(xDelta*xDelta + yDelta*yDelta), xDelta, yDelta
    end
end

local function isMine(rec)
    local me = UnitName and UnitName("player")
    if not me or not rec then return false end
    if rec.fp and rec.fp == me then return true end
    if rec.o and rec.o == me then return true end
end

StaticPopupDialogs["LOOTCOLLECTOR_REMOVE_DISCOVERY"] = {
  text = "Do you want to report this discovery as gone? This will notify other players and permanently remove it from your database.",
  button1 = "Report and Remove",
  button2 = "Cancel",
  OnAccept = function(self, data_guid)
    if data_guid then
      local Core = L:GetModule("Core", true)
      if Core and Core.ReportDiscoveryAsGone then
        Core:ReportDiscoveryAsGone(data_guid)
      end
    end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

local FilterButton = nil
local FilterMenuHost = CreateFrame("Frame", "LootCollectorFilterMenuHost", UIParent, "UIDropDownMenuTemplate")

local ValidMinimapShapes = {
  ["SQUARE"]                = { false, false, false, false },
  ["CORNER-TOPLEFT"]        = { true,  false, false, false },
  ["CORNER-TOPRIGHT"]       = { false, false, true,  false },
  ["CORNER-BOTTOMLEFT"]     = { false, true,  false, false },
  ["CORNER-BOTTOMRIGHT"]    = { false, false, false, true },
  ["SIDE-LEFT"]             = { true,  true,  false, false },
  ["SIDE-RIGHT"]            = { false, false, true,  true },
  ["SIDE-TOP"]              = { true,  false, true,  false },
  ["SIDE-BOTTOM"]           = { false, true,  false, true },
  ["TRICORNER-TOPLEFT"]     = { true,  true,  true,  false },
  ["TRICORNER-TOPRIGHT"]    = { true,  false, true,  true },
  ["TRICORNER-BOTTOMLEFT"]  = { true,  true,  false, true },
  ["TRICORNER-BOTTOMRIGHT"] = { false, true,  true,  true },
}

Map._mmPins = Map._mmPins or {}
Map._mmTicker = Map._mmTicker or nil
Map._mmElapsed = 0
Map._mmInterval = 0.1 
Map._mmSize = 10

local SLOT_OPTIONS = {
  { loc = "INVTYPE_HEAD", text = "Head" }, { loc = "INVTYPE_NECK", text = "Neck" }, { loc = "INVTYPE_SHOULDER", text = "Shoulder" }, { loc = "INVTYPE_CHEST", text = "Chest" }, { loc = "INVTYPE_ROBE", text = "Robe" }, { loc = "INVTYPE_WAIST", text = "Waist" }, { loc = "INVTYPE_LEGS", text = "Legs" }, { loc = "INVTYPE_FEET", text = "Feet" }, { loc = "INVTYPE_WRIST", text = "Wrist" }, { loc = "INVTYPE_HAND", text = "Hands" }, { loc = "INVTYPE_FINGER", text = "Finger" }, { loc = "INVTYPE_TRINKET", text = "Trinket" }, { loc = "INVTYPE_CLOAK", text = "Back" }, { loc = "INVTYPE_WEAPON", text = "One-Hand" }, { loc = "INVTYPE_2HWEAPON", text = "Two-Hand" }, { loc = "INVTYPE_WEAPONMAINHAND", text = "Main Hand" }, { loc = "INVTYPE_WEAPONOFFHAND", text = "Off Hand" }, { loc = "INVTYPE_SHIELD", text = "Shield" }, { loc = "INVTYPE_HOLDABLE", text = "Held Off-hand" }, { loc = "INVTYPE_RANGED", text = "Ranged" }, { loc = "INVTYPE_RANGEDRIGHT", text = "Ranged (Right)" }, { loc = "INVTYPE_THROWN", text = "Thrown" }, { loc = "INVTYPE_RELIC", text = "Relic" },
}

local CLASS_OPTIONS = {
  "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","DEATHKNIGHT","SHAMAN","MAGE","WARLOCK","DRUID",
}

local CLASS_ABBREVIATIONS_REVERSE = {
  ["wa"] = "WARRIOR", ["pa"] = "PALADIN", ["hu"] = "HUNTER", ["ro"] = "ROGUE",
  ["pr"] = "PRIEST", ["dk"] = "DEATHKNIGHT", ["sh"] = "SHAMAN", ["ma"] = "MAGE",
  ["lo"] = "WARLOCK", ["dr"] = "DRUID",
}

local function GetQualityColor(quality)
  quality = tonumber(quality)
  if not quality then return 1,1,1 end
  if QUALITY_COLORS_PIN and QUALITY_COLORS_PIN[quality] then
    local c = QUALITY_COLORS_PIN[quality]
    return c.r or 1, c.g or 1, c.b or 1
  end
  if GetItemQualityColor then
    local r,g,b = GetItemQualityColor(quality)
    if r and g and b then return r,g,b end
  end
 
  return 1,1,1
end

local function AlphaForStatus(status)
  if status == "FADING" then return 0.65 elseif status == "STALE" then return 0.45 end
  return 1.0
end

local function SearchDiscoveryForTerm(d, term)
    if not d or not term or term == "" then return false end

    
    local itemName = (d.il and d.il:match("%[(.+)%]")) or ""
    if string.find(string.lower(itemName), term, 1, true) then
        return true
    end

    
    local zoneName = (L.ResolveZoneDisplay and L:ResolveZoneDisplay(d.c, d.z, d.iz)) or ""
    if string.find(string.lower(zoneName), term, 1, true) then
        return true
    end

    
    local Constants = L:GetModule("Constants", true)
    if d.dt == (Constants and Constants.DISCOVERY_TYPE.BLACKMARKET) then
        if d.vendorName and string.find(string.lower(d.vendorName), term, 1, true) then
            return true
        end
        if d.vendorItems then
            for _, itemData in ipairs(d.vendorItems) do
                if itemData.name and string.find(string.lower(itemData.name), term, 1, true) then
                    return true
                end
            end
        end
    end
    
    return false
end

local function passesFilters(d)
    if not L:DiscoveryPassesFilters(d) then
        return false
    end

    if Map._searchBox and Map._searchBox:GetText() ~= "" then
        local term = string.lower(Map._searchBox:GetText())
        if not SearchDiscoveryForTerm(d, term) then
            return false
        end
    end

    return true
end

local function NavigateHere(discovery)
  if not discovery then return end
  local Arrow = L:GetModule("Arrow", true)
  if not Arrow then return end
  if Arrow.PointToRecordV5 then
      Arrow:PointToRecordV5(discovery)
  elseif Arrow.NavigateTo then
      Arrow:NavigateTo(discovery)
  end
end

local function EnsureMapOverlay()
	local parent = WorldMapDetailFrame or WorldMapFrame
	if mapOverlay and mapOverlay:GetParent() == parent then
		return mapOverlay
	end
	
	mapOverlay = CreateFrame("Frame", "LootCollectorMapOverlay", parent)
	mapOverlay.baseSize = 34
	mapOverlay:SetSize(mapOverlay.baseSize, mapOverlay.baseSize)
	mapOverlay:SetFrameStrata("TOOLTIP")
	mapOverlay:SetFrameLevel(parent:GetFrameLevel() + 1000)
	
	mapOverlay.dot = mapOverlay:CreateTexture(nil, "OVERLAY")
	mapOverlay.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
	mapOverlay.dot:SetSize(8, 8)
	mapOverlay.dot:SetVertexColor(1, 1, 1)
	mapOverlay.dot:Hide()
	
	local beamColorR, beamColorG, beamColorB = 0.00, 0.88, 1.00
	local beamThickness = 4
	local beamLen = 28
	
	local top = mapOverlay:CreateTexture(nil, "OVERLAY")
	top:SetTexture("Interface\\Buttons\\WHITE8X8")
	top:SetSize(beamThickness, beamLen)
	top:SetVertexColor(beamColorR, beamColorG, beamColorB)
	mapOverlay.beamTop = top
	
	local left = mapOverlay:CreateTexture(nil, "OVERLAY")
	left:SetTexture("Interface\\Buttons\\WHITE8X8")
	left:SetSize(beamLen, beamThickness)
	left:SetVertexColor(beamColorR, beamColorG, beamColorB)
	mapOverlay.beamLeft = left
	
	local right = mapOverlay:CreateTexture(nil, "OVERLAY")
	right:SetTexture("Interface\\Buttons\\WHITE8X8")
	right:SetSize(beamLen, beamThickness)
	right:SetVertexColor(beamColorR, beamColorG, beamColorB)
	mapOverlay.beamRight = right
	
	mapOverlay.glow = mapOverlay:CreateTexture(nil, "OVERLAY")
	mapOverlay.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
	mapOverlay.glow:SetVertexColor(1, 1, 1)
	mapOverlay.glow:Hide()
	
	mapOverlay:Hide()
	return mapOverlay
end

local function PulseOverlayAt(px, py)
	local parent = WorldMapDetailFrame or WorldMapFrame
	if not parent then return end
	local w, h = parent:GetWidth(), parent:GetHeight()
	if not w or not h or w == 0 or h == 0 then return end
	
	local overlay = EnsureMapOverlay()
	overlay:SetParent(parent)
	overlay:ClearAllPoints()
	overlay:SetPoint("CENTER", parent, "TOPLEFT", px, -py)
	overlay:Show()
	
	overlay.dot:ClearAllPoints()
	overlay.dot:SetPoint("CENTER", overlay, "CENTER", 0, 0)
	overlay.dot:Show()
	
	overlay.glow:ClearAllPoints()
	overlay.glow:SetPoint("CENTER", overlay, "CENTER", 0, 0)
	overlay.glow:SetSize(16, 16)
	overlay.glow:SetAlpha(0)
	overlay.glow:Show()
	
	overlay.elapsed = 0
	overlay.period = 0.9
	overlay.cycles = 3
	overlay.duration = overlay.period * overlay.cycles
	
	overlay:SetScript("OnUpdate", function(self, dt)
		self.elapsed = self.elapsed + (dt or 0)
		local t = self.elapsed
		if t >= self.duration then
			self:SetScript("OnUpdate", nil)
			self:Hide()
			return
		end
		
		local phase = (t % self.period) / self.period
		local ease = phase * phase * (3 - 2 * phase)
		
		local topY = -py + (0 - (-py)) * (1 - ease)
		self.beamTop:ClearAllPoints()
		self.beamTop:SetPoint("CENTER", parent, "TOPLEFT", px, topY)
		
		local leftX = px * ease
		self.beamLeft:ClearAllPoints()
		self.beamLeft:SetPoint("CENTER", parent, "TOPLEFT", leftX, -py)
		
		local rightX = w - (w - px) * ease
		self.beamRight:ClearAllPoints()
		self.beamRight:SetPoint("CENTER", parent, "TOPLEFT", rightX, -py)
		
		local glowAlpha = 0.2 + 0.6 * ease
		local glowSize = 16 + 10 * ease
		self.glow:SetAlpha(glowAlpha)
		self.glow:SetSize(glowSize, glowSize)
		
		self:SetAlpha(0.95)
	end)
end

function Map:FocusOnDiscovery(d)
    if not d then return end
    
    local x, y
    if d.xy and type(d.xy) == "table" then
        
        x = tonumber(d.xy.x) or 0
        y = tonumber(d.xy.y) or 0
    else
        
        x = tonumber(d.x) or 0
        y = tonumber(d.y) or 0
    end
    
    if not x or not y then return end
    
    if ShowUIPanel and WorldMapFrame then ShowUIPanel(WorldMapFrame)
    elseif WorldMapFrame and WorldMapFrame.Show then WorldMapFrame:Show() end
    
    if d.c and d.z and d.z > 0 and SetMapZoom then
        SetMapZoom(d.c, d.z)
    elseif SetMapToCurrentZone then
        SetMapToCurrentZone()
    end
    
    local parent = WorldMapDetailFrame or WorldMapFrame
    if not parent or not parent.GetWidth or not parent.GetHeight then return end
    local pw, ph = parent:GetWidth(), parent:GetHeight()
    
    local px = (x > 0 and x < 1 and x * pw) or 0
    local py = (y > 0 and y < 1 and y * ph) or 0
    PulseOverlayAt(px, py)
end

function Map:GetDiscoveryIcon(d)
  local Constants = L:GetModule("Constants", true)
  if d and d.dt == (Constants and Constants.DISCOVERY_TYPE.BLACKMARKET) then
      if d.vendorType == "MS" or (d.g and d.g:find("MS-", 1, true)) then
          return "Interface\\Icons\\INV_Scroll_03" 
      else
          return "Interface\\Icons\\INV_Misc_Coin_01" 
      end
  end
  local texture = nil
  if d and d.i then texture = select(10, GetItemInfo(d.i)) end
  if (not texture) and d and d.il then texture = select(10, GetItemInfo(d.il)) end
  return texture or PIN_FALLBACK_TEXTURE
end

function Map:EnsureHoverButton()
  if self._hoverBtn then return end
  local btn = CreateFrame("Button", "LootCollectorItemHoverBtn", GameTooltip)
  btn:SetSize(16, 16)
  btn:SetFrameStrata("TOOLTIP")
  btn:SetFrameLevel(GameTooltip:GetFrameLevel() + 10)
  btn:EnableMouse(true)
  btn.tex = btn:CreateTexture(nil, "ARTWORK")
  btn.tex:SetAllPoints(btn)
  btn:Hide()
  btn:SetScript("OnEnter", function(self)
    if not Map._hoverBtnItemLink then return end
    ItemRefTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    ItemRefTooltip:ClearAllPoints()
    ItemRefTooltip:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", 8, 0)
    ItemRefTooltip:SetHyperlink(Map._hoverBtnItemLink)
    ItemRefTooltip:Show()
  end)
  btn:SetScript("OnLeave", function(self)
    ItemRefTooltip:Hide()
  end)
  self._hoverBtn = btn
end

function Map:GetBMItemLine(parentTooltip)
    for _, lineFrame in ipairs(self._bmItemLines) do
        if not lineFrame:IsShown() then
            if lineFrame:GetParent() ~= parentTooltip then
                lineFrame:SetParent(parentTooltip)
                
                lineFrame:SetSize(parentTooltip:GetWidth() - 20, BM_LINE_HEIGHT)
            end
            return lineFrame
        end
    end

    local lineFrame = CreateFrame("Button", nil, parentTooltip)
    lineFrame:SetSize(parentTooltip:GetWidth() - 20, BM_LINE_HEIGHT)
    lineFrame:SetFrameLevel(parentTooltip:GetFrameLevel() + 1)
    
    lineFrame.texture = lineFrame:CreateTexture(nil, "ARTWORK")
    lineFrame.texture:SetSize(BM_ICON_SIZE_IN_LINE, BM_ICON_SIZE_IN_LINE)
    lineFrame.texture:SetPoint("LEFT", 0, 0)
    lineFrame.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    lineFrame.fontString = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lineFrame.fontString:SetPoint("LEFT", lineFrame.texture, "RIGHT", 4, 0)
    lineFrame.fontString:SetPoint("RIGHT", -4, 0)
    lineFrame.fontString:SetJustifyH("LEFT")

    lineFrame:SetScript("OnEnter", function(self)
        if self.itemLink then
            
            ItemRefTooltip:SetOwner(self, "ANCHOR_RIGHT")
            ItemRefTooltip:SetHyperlink(self.itemLink)
            ItemRefTooltip:Show()
        end
    end)
    lineFrame:SetScript("OnLeave", function() ItemRefTooltip:Hide() end)
    lineFrame:SetScript("OnClick", function(self, button)
        if self.itemLink then HandleModifiedItemClick(self.itemLink) end
    end)
    
    table.insert(self._bmItemLines, lineFrame)
    return lineFrame
end

function Map:ShowBlackmarketTooltip(d, anchorFrame)
    local mapSize = WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.size
    local useWorldMapTooltip = (mapSize and (mapSize == WORLDMAP_QUESTLIST_SIZE or mapSize == WORLDMAP_FULLMAP_SIZE))
    local tooltip = useWorldMapTooltip and WorldMapTooltip or GameTooltip
    
    tooltip:SetOwner(anchorFrame, "ANCHOR_RIGHT")
    tooltip:ClearLines()
    
    local vendorTypeDisplay
    if d.vendorType == "MS" or (d.g and d.g:find("MS-", 1, true)) then
        vendorTypeDisplay = "|cffa335ee<Mystic Scroll Vendor>|r"
    else
        vendorTypeDisplay = "|cffa335ee<Blackmarket Artisan Supplies>|r"
    end
    tooltip:AddLine(d.vendorName or "Unknown Vendor", 1, 0.82, 0)
    tooltip:AddLine(vendorTypeDisplay, 1, 1, 1)

    local status = L:GetDiscoveryStatus(d)
    tooltip:AddDoubleLine("Status", status, 0.8, 0.8, 0.8, 1, 1, 1)

    local ls = tonumber(d.ls) or tonumber(d.t0) or time()
    tooltip:AddDoubleLine("Last seen", date("%Y-%m-%d %H:%M", ls), 0.8, 0.8, 0.8, 1, 1, 1)

    do
        local c, z, iz = tonumber(d.c) or 0, tonumber(d.z) or 0, tonumber(d.iz) or 0
        local zoneName
        if z == 0 then
            local ZL = L:GetModule("ZoneList", true)
            zoneName = (ZL and ZL.ResolveIz and ZL:ResolveIz(iz)) or (GetRealZoneText and GetRealZoneText()) or "Unknown Instance"
        else
            local ZL = L:GetModule("ZoneList", true)
            zoneName = (ZL and ZL.GetZoneName and ZL:GetZoneName(c, z)) or "Unknown Zone"
        end
        tooltip:AddDoubleLine("Zone", zoneName, 0.8, 0.8, 0.8, 1, 1, 1)
    end

    if d.xy then
        tooltip:AddDoubleLine("Location", string.format("%.1f, %.1f", (d.xy.x or 0) * 100, (d.xy.y or 0) * 100), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    
    tooltip:AddLine(" ", nil, nil, nil, true) 

    local items = d.vendorItems
    if not items or #items == 0 then
        tooltip:AddLine("No items found on this vendor.", 1, 0.5, 0.5)
        tooltip:Show()
        return
    end

    tooltip:Show() 

    local listHeight = #items * BM_LINE_HEIGHT
    tooltip:SetHeight(tooltip:GetHeight() + listHeight)
    
    local anchorLine = _G[tooltip:GetName().."TextLeft8"] 
    if not anchorLine then tooltip:Show(); return end
    
    local lastLine = nil
    for i, itemData in ipairs(items) do
        local line = self:GetBMItemLine(tooltip)
        
        local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemData.link)
        
        line.itemLink = itemData.link
        line.texture:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        line.fontString:SetText(itemData.link)

        line:ClearAllPoints()
        if not lastLine then
            line:SetPoint("TOPLEFT", anchorLine, "BOTTOMLEFT", 4, -4)
        else
            line:SetPoint("TOPLEFT", lastLine, "BOTTOMLEFT", 0, 0)
        end
        lastLine = line
        line:Show()
    end
end

function Map:ShowDiscoveryTooltip(discoveryOrPin, anchorFrame)
    local d = discoveryOrPin.discovery or discoveryOrPin
    if not d then return end
    
    local Constants = L:GetModule("Constants", true)
    if d.dt == (Constants and Constants.DISCOVERY_TYPE.BLACKMARKET) then
        self:ShowBlackmarketTooltip(d, anchorFrame or discoveryOrPin)
        return
    end

    if WorldMapPOIFrame and WorldMapPOIFrame.allowBlobTooltip ~= nil then
        self._oldAllowBlobTooltip = WorldMapPOIFrame.allowBlobTooltip
        WorldMapPOIFrame.allowBlobTooltip = false
    end

    local mapSize = WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.size
    local useWorldMapTooltip = (mapSize and (mapSize == WORLDMAP_QUESTLIST_SIZE or mapSize == WORLDMAP_FULLMAP_SIZE))
    local tooltip = useWorldMapTooltip and WorldMapTooltip or GameTooltip

    tooltip:SetOwner(anchorFrame or discoveryOrPin, "ANCHOR_RIGHT")
    tooltip:ClearLines()

    if self._pinnedPin == discoveryOrPin and d.il then
        if not itemInfoTooltip then
            itemInfoTooltip = CreateFrame("GameTooltip", "LootCollectorItemInfoTooltip", UIParent, "GameTooltipTemplate")
        end
        itemInfoTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        itemInfoTooltip:SetHyperlink(d.il)
        for i = 1, itemInfoTooltip:NumLines() do
            local line = _G["LootCollectorItemInfoTooltipTextLeft" .. i]
            if line and line:GetText() then
                local r, g, b = line:GetTextColor()
                tooltip:AddLine(line:GetText(), r, g, b, true)
            end
        end
        itemInfoTooltip:Hide()
    else
        local name, _, quality = GetItemInfo(d.il or d.i or 0)
        local header = d.il or name or "Discovery"
        tooltip:AddLine(header, 1, 1, 1, true)
        if quality then
            local r, g, b = GetQualityColor(quality)
            local firstLine = _G[tooltip:GetName().."TextLeft1"]
            if firstLine then
                firstLine:SetTextColor(r or 1, g or 1, b or 1)
            end
        end
    end

    tooltip:AddLine(string.format("Found by %s", d.fp or "Unknown"), 0.6, 0.8, 1, true)
    
   

    if self._pinnedPin ~= discoveryOrPin and (d.it or d.ist) then
        local Constants = L:GetModule("Constants", true)
        if Constants and (d.it or d.ist) then
            local itemTypeStr = d.it and Constants.ID_TO_ITEM_TYPE and Constants.ID_TO_ITEM_TYPE[d.it]
            local itemSubTypeStr = d.ist and Constants.ID_TO_ITEM_SUBTYPE and Constants.ID_TO_ITEM_SUBTYPE[d.ist]
            local typeDisplay = ""
            if itemSubTypeStr then
                typeDisplay = itemSubTypeStr
                if itemTypeStr then
                    typeDisplay = typeDisplay .. " (" .. itemTypeStr .. ")"
                end
            elseif itemTypeStr then
                typeDisplay = itemTypeStr
            end
            if typeDisplay ~= "" then
                tooltip:AddLine(typeDisplay, 0.95, 0.95, 0.95, true)
            end
        end
    end

    local ts = tonumber(d.t0) or time()
    tooltip:AddDoubleLine("Date", date("%Y-%m-%d %H:%M", ts), 0.8, 0.8, 0.8, 1, 1, 1)

    local status = L:GetDiscoveryStatus(d)
    if d.adc and d.adc > 0 then
        status = string.format("%s (%d votes)", status, d.adc)
    end
    tooltip:AddDoubleLine("Status", status, 0.8, 0.8, 0.8, 1, 1, 1)

    local ls = tonumber(d.ls) or ts
    tooltip:AddDoubleLine("Last seen", date("%Y-%m-%d %H:%M", ls), 0.8, 0.8, 0.8, 1, 1, 1)

    do
        local c  = tonumber(d.c) or 0
        local z  = tonumber(d.z) or 0
        local iz = tonumber(d.iz) or 0
        local zoneName

        if z == 0 then
            local ZL = L:GetModule("ZoneList", true)
            zoneName = (ZL and ZL.ResolveIz and ZL:ResolveIz(iz)) or (GetRealZoneText and GetRealZoneText()) or "Unknown Instance"
        else
            local ZL = L:GetModule("ZoneList", true)
            zoneName = (ZL and ZL.GetZoneName and ZL:GetZoneName(c, z)) or "Unknown Zone"
        end

        tooltip:AddDoubleLine("Zone", zoneName, 0.8, 0.8, 0.8, 1, 1, 1)
    end

    if d.src then
        local srcKey, srcDetail = d.src:match("^(%S+)%s*%((.+)%)?$")
		local bkey = "357fjt+y36zfnd+N36wg35/fit+s35vfjN+y36zfoN+M37Ig36Dfjt+sIN+h34rfk9+M36zfn9+K36wg357fn9+P35zfjd+rIN+V34rfrN+h34zfst+s36Pfjd+yIN+g347frCDfmN+Q36s="
        if not srcKey then srcKey = d.src end
        
        local srcDisplay = SOURCE_TEXT_MAP[srcKey] or "Unknown"
        if srcDetail then
            srcDisplay = string.format("%s (%s)", srcDisplay, srcDetail)
        end
        tooltip:AddDoubleLine("Source", srcDisplay, 0.8, 0.8, 0.8, 1, 1, 1)
    end

    if d.xy then
        tooltip:AddDoubleLine("Location", string.format("%.1f, %.1f", (d.xy.x or 0) * 100, (d.xy.y or 0) * 100), 0.8, 0.8, 0.8, 1, 1, 1)
    end

    if self._pinnedPin == discoveryOrPin and (d.il or d.i) then
        self:EnsureHoverButton()
        self._hoverBtnItemLink = d.il or d.i
        local icon = self:GetDiscoveryIcon(d)
        self._hoverBtn.tex:SetTexture(icon or PIN_FALLBACK_TEXTURE)
        tooltip:Show()
        self._hoverBtn:ClearAllPoints()
        
        local firstLine = _G[tooltip:GetName().."TextLeft1"]
        if firstLine then
            self._hoverBtn:SetPoint("LEFT", firstLine, "RIGHT", 4, 0)
        else
            self._hoverBtn:SetPoint("TOPRIGHT", tooltip, "TOPRIGHT", -6, -6)
        end
        self._hoverBtn:Show()
    else
        if self._hoverBtn then
            self._hoverBtn:Hide()
        end
        self._hoverBtnItemLink = nil
        tooltip:Show()
    end
end

function Map:HideDiscoveryTooltip()
  if GameTooltip and GameTooltip:IsShown() then GameTooltip:Hide() end
  
  if WorldMapTooltip and WorldMapTooltip:IsShown() then WorldMapTooltip:Hide() end
  if ItemRefTooltip then ItemRefTooltip:Hide() end
  if self._hoverBtn then self._hoverBtn:Hide(); self._hoverBtnItemLink = nil end

  if WorldMapPOIFrame and self._oldAllowBlobTooltip ~= nil then
      WorldMapPOIFrame.allowBlobTooltip = self._oldAllowBlobTooltip
      self._oldAllowBlobTooltip = nil
  end
end

StaticPopupDialogs["LOOTCOLLECTOR_REMOVE_BM_VENDOR"] = {
  text = "Do you want to remove this Blackmarket vendor pin from your local database? This action will not be broadcast to other players.",
  button1 = "Remove Pin",
  button2 = "Cancel",
  OnAccept = function(self, data_guid)
    if data_guid then
      local Core = L:GetModule("Core", true)
      if Core and Core.RemoveBlackmarketVendorByGuid then
        Core:RemoveBlackmarketVendorByGuid(data_guid)
      end
    end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

function Map:OpenPinMenu(anchorFrame)
  if not anchorFrame or not anchorFrame.discovery then return end
  local d = anchorFrame.discovery
  local name = d.il or (select(1, GetItemInfo(d.i)) or "Discovery")
  wipe(menuList)
  table.insert(menuList, { text = tostring(name), isTitle = true, notCheckable = true })
  table.insert(menuList, { text = "Navigate here", notCheckable = true, func = function() NavigateHere(d) end })
  table.insert(menuList, { text = "Show to...", notCheckable = true, func = function() Map:OpenShowToDialog(d) end })
  
  local Constants = L:GetModule("Constants", true)
  local isBlackmarket = d.dt and Constants and d.dt == Constants.DISCOVERY_TYPE.BLACKMARKET
  
  if not isBlackmarket then
      table.insert(menuList, { text = "Set as looted", notCheckable = true, func = function()
        if not (L.db and L.db.char) then return end
        L.db.char.looted = L.db.char.looted or {}
        L.db.char.looted[d.g] = time()
        Map:Update()
      end })
      table.insert(menuList, { text = "Set as unlooted", notCheckable = true, func = function()
        if not (L.db and L.db.char and L.db.char.looted) then return end
        L.db.char.looted[d.g] = nil
        Map:Update()
      end })
  end
  
  table.insert(menuList, { text = "", notCheckable = true, disabled = true })

  if isBlackmarket then
    table.insert(menuList, { text = "|cffff7f00Remove Vendor Pin|r", notCheckable = true, func = function()
      StaticPopup_Show("LOOTCOLLECTOR_REMOVE_BM_VENDOR", nil, nil, d.g)
    end })
  else
    table.insert(menuList, { text = "|cffff7f00Report as Gone|r", notCheckable = true, func = function()
      StaticPopup_Show("LOOTCOLLECTOR_REMOVE_DISCOVERY", nil, nil, d.g)
    end })
  end

  table.insert(menuList, { text = "Close", notCheckable = true })
  
  if EasyMenu then
    EasyMenu(menuList, DropFrame, "cursor", 0, 0, "MENU", 2)
  else
    ToggleDropDownMenu(1, nil, DropFrame, anchorFrame, 0, 0)
    UIDropDownMenu_Initialize(DropFrame, function(self, level)
      for _, item in ipairs(menuList) do UIDropDownMenu_AddButton(item, level) end
    end, "MENU")
  end
end

local function BuildFilterEasyMenu()
  local Constants = L:GetModule("Constants", true)
  local f = L:GetFilters()
  local menu = {}
  table.insert(menu, { text = "LootCollector Filters", isTitle = true, notCheckable = true })
  table.insert(menu, {
    text = L:IsPaused() and "|cffff7f00Resume Processing|r" or "|cff00ff00Pause Processing|r",
    checked = L:IsPaused(),
    keepShownOnClick = true,
    func = function()
      L:TogglePause()
      Map:Update()
      if EasyMenu and FilterButton then
        EasyMenu(BuildFilterEasyMenu(), FilterMenuHost, FilterButton, 0, 0, "MENU", 2)
      end
    end
  })
  table.insert(menu, { text = "", notCheckable = true, disabled = true })

  local function addToggle(label, key, targetTable)
    table.insert(targetTable, {
      text = label,
      checked = f[key] and true or false,
      keepShownOnClick = true,
      func = function() f[key] = not f[key]; Map:Update(); Map:UpdateMinimap() end 
    })
  end

  addToggle("Show on Minimap", "showMinimap", menu)
  
  table.insert(menu, {
    text = "Show Map Filter",
    checked = not f.hideSearchBar,
    keepShownOnClick = true,
    func = function()
        f.hideSearchBar = not f.hideSearchBar
        Map:ToggleSearchUI(not f.hideSearchBar)
    end
  })
  
  
  table.insert(menu, {
      text = "Show Zone Summary",
      desc = "Show total discovery counts for zones on the continent map.",
      checked = f.showZoneSummaries,
      keepShownOnClick = true,
      func = function() 
          f.showZoneSummaries = not f.showZoneSummaries
          Map:Update() 
      end
  })
  
  
  local arrowSub = { { text = "Arrow", isTitle = true, notCheckable = true } }
  table.insert(arrowSub, {
      text = "Auto-track Unlooted",
      checked = f.autoTrackNearest,
      keepShownOnClick = true,
      func = function()
          f.autoTrackNearest = not f.autoTrackNearest
          local Arrow = L:GetModule("Arrow", true)
          if Arrow then
              if f.autoTrackNearest then
                  Arrow:Show()
              else
                  Arrow:Hide()
              end
          end
      end
  })
  table.insert(arrowSub, { text = "Skip nearest (session)", notCheckable = true, func = function() 
      local Arrow = L:GetModule("Arrow", true)
      if Arrow and Arrow.SkipNearest then Arrow:SkipNearest() end
  end})
  table.insert(arrowSub, { text = "Clear skipped (session)", notCheckable = true, func = function() 
      local Arrow = L:GetModule("Arrow", true)
      if Arrow and Arrow.ClearSessionSkipList then Arrow:ClearSessionSkipList() end
  end})
  table.insert(menu, { text = "Arrow", hasArrow = true, notCheckable = true, menuList = arrowSub })

  local hideSub = { { text = "Hide Options", isTitle = true, notCheckable = true } }
  addToggle("Hide All Discoveries", "hideAll", hideSub)
  addToggle("Hide Looted", "hideLooted", hideSub)
  addToggle("Hide Unconfirmed", "hideUnconfirmed", hideSub)
  addToggle("Hide Uncached", "hideUncached", hideSub)
  addToggle("Hide Faded", "hideFaded", hideSub)
  addToggle("Hide Stale", "hideStale", hideSub)
  table.insert(menu, { text = "Hide", hasArrow = true, notCheckable = true, menuList = hideSub })
  
  local showSub = { { text = "Show Item Types", isTitle = true, notCheckable = true } }
  table.insert(showSub, { text = "Mystic Scrolls", checked = f.showMysticScrolls, keepShownOnClick = true, func = function() f.showMysticScrolls = not f.showMysticScrolls; Map:Update(); Map:UpdateMinimap() end })
  table.insert(showSub, { text = "Worldforged Items", checked = f.showWorldforged, keepShownOnClick = true, func = function() f.showWorldforged = not f.showWorldforged; Map:Update(); Map:UpdateMinimap() end })
  
table.insert(showSub, {
  text = "Enhanced WF Toltip",
  checked = (LootCollector.db and LootCollector.db.profile and LootCollector.db.profile.enhancedWFTooltip) and true or false,
  keepShownOnClick = true,
  func = function()
    if not (LootCollector and LootCollector.db and LootCollector.db.profile) then return end
    LootCollector.db.profile.enhancedWFTooltip = not (LootCollector.db.profile.enhancedWFTooltip and true or false)

    local Tooltip = LootCollector:GetModule("Tooltip", true)
    if Tooltip and Tooltip.ApplySetting then
      Tooltip:ApplySetting()
    else
      _G.ItemUpgradeTooltipDB = _G.ItemUpgradeTooltipDB or {}
      _G.ItemUpgradeTooltipDB.enabled = LootCollector.db.profile.enhancedWFTooltip and true or false
    end

    if Map then
      if Map.Update then Map:Update() end
      if Map.UpdateMinimap then Map:UpdateMinimap() end
    end
  end
})

  table.insert(menu, { text = "Show", hasArrow = true, notCheckable = true, menuList = showSub })

  local qualities = { "Poor","Common","Uncommon","Rare","Epic","Legendary","Artifact","Heirloom" }
  local raritySub = { { text = "Minimum Quality", isTitle = true, notCheckable = true } }
  for q = 0, 7 do
    local r, g, b = GetQualityColor(q)
    table.insert(raritySub, {
      text = qualities[q+1] or ("Quality "..q),
      colorCode = string.format("|cff%02x%02x%02x", (r*255), (g*255), (b*255)),
      checked = (f.minRarity == q),
      keepShownOnClick = true,
      func = function()
        f.minRarity = q
        Map:Update()
        Map:UpdateMinimap()
        if EasyMenu and FilterButton then
          EasyMenu(BuildFilterEasyMenu(), FilterMenuHost, FilterButton, 0, 0, "MENU", 2)
        end
      end
    })
  end
  table.insert(menu, { text = "Minimum Quality", hasArrow = true, notCheckable = true, menuList = raritySub })

  local slotsSub = { { text = "Slots", isTitle = true, notCheckable = true }, { text = "Clear All", notCheckable = true, func = function() for k in pairs(f.allowedEquipLoc) do f.allowedEquipLoc[k] = nil end; Map:Update(); Map:UpdateMinimap() end } }
  for _, opt in ipairs(SLOT_OPTIONS) do
    table.insert(slotsSub, {
      text = opt.text,
      checked = f.allowedEquipLoc[opt.loc] and true or false,
      keepShownOnClick = true,
      func = function()
        if f.allowedEquipLoc[opt.loc] then f.allowedEquipLoc[opt.loc] = nil else f.allowedEquipLoc[opt.loc] = true end
        Map:Update(); Map:UpdateMinimap()
      end
    })
  end
  table.insert(menu, { text = "Slots", hasArrow = true, notCheckable = true, menuList = slotsSub })

  local usableBySub = { { text = "Usable by", isTitle = true, notCheckable = true }, { text = "Clear All", notCheckable = true, func = function() for k in pairs(f.usableByClasses) do f.usableByClasses[k] = nil end; Map:Update(); Map:UpdateMinimap() end } }
  for _, classTok in ipairs(CLASS_OPTIONS) do
    local locName = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classTok]) or classTok
    table.insert(usableBySub, {
      text = locName,
      checked = f.usableByClasses[classTok] and true or false,
      keepShownOnClick = true,
      func = function()
        if f.usableByClasses[classTok] then f.usableByClasses[classTok] = nil else f.usableByClasses[classTok] = true end
        Map:Update(); Map:UpdateMinimap()
      end
    })
  end
  table.insert(menu, { text = "Usable by", hasArrow = true, notCheckable = true, menuList = usableBySub })

  return menu
end

local function PlaceFilterButton(btn)
  btn:ClearAllPoints()
  local potentialAnchors = { "_NPCScanOverlayWorldMapToggle", "WorldMapQuestShowObjectives", "WorldMapTrackQuest", "WorldMapFrameCloseButton" }
  for _, anchorName in ipairs(potentialAnchors) do
    local anchorFrame = _G[anchorName]
    if anchorFrame and anchorFrame:IsShown() then
      btn:SetPoint("RIGHT", anchorFrame, "LEFT", -8, 0)
      return
    end
  end
  btn:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -80, -30)
end

function Map:EnsureFilterUI()
  if not WorldMapFrame then return end
  if not FilterButton then
    FilterButton = CreateFrame("Button", "LootCollectorFilterButton", WorldMapFrame, "UIPanelButtonTemplate")
    FilterButton:SetSize(24, 20)
    FilterButton:SetText("LC")
    FilterButton:SetFrameStrata("HIGH")
    FilterButton:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 10)
    FilterButton:SetToplevel(true)
    FilterButton:EnableMouse(true)
    FilterButton:RegisterForClicks("LeftButtonUp")
    PlaceFilterButton(FilterButton)
    FilterButton:SetScript("OnClick", function(self)
      if EasyMenu then EasyMenu(BuildFilterEasyMenu(), FilterMenuHost, self, 0, 0, "MENU", 2)
      else ToggleDropDownMenu(1, nil, FilterMenuHost, self, 0, 0) end
    end)
    FilterButton:SetScript("OnShow", function(self) PlaceFilterButton(self) end)
  else
    PlaceFilterButton(FilterButton)
  end
end

function Map:BuildPin()
  local pinSize = (L.db and L.db.profile and L.db.profile.mapFilters and L.db.profile.mapFilters.pinSize) or 16
  local frame = CreateFrame("Button", nil, WorldMapButton)
  frame:SetSize(pinSize, pinSize)
  frame:SetFrameStrata(WorldMapButton:GetFrameStrata())
  frame:SetFrameLevel(WorldMapButton:GetFrameLevel() + 10)
  frame:SetNormalTexture(nil)
  frame:SetHighlightTexture(nil)
  frame:SetPushedTexture(nil)
  frame:SetDisabledTexture(nil)

  frame.border = frame:CreateTexture(nil, "BACKGROUND")
  frame.border:SetHeight(pinSize)
  frame.border:SetWidth(pinSize)
  frame.border:SetPoint("CENTER", 0, 0)
  frame.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  frame.border:SetTexCoord(0.2, 0.8, 0.2, 0.8)
  frame.border:SetVertexColor(0, 0, 0, 0.25)

  frame.unlootedOutline = frame:CreateTexture(nil, "BORDER")
  frame.unlootedOutline:SetTexture("Interface\\Buttons\\WHITE8X8")
  frame.unlootedOutline:SetHeight(pinSize)
  frame.unlootedOutline:SetWidth(pinSize)
  frame.unlootedOutline:SetPoint("CENTER", 0, 0)
  frame.unlootedOutline:Hide()

  local iconSize = pinSize - 2
  frame.texture = frame:CreateTexture(nil, "ARTWORK")
  frame.texture:SetHeight(iconSize)
  frame.texture:SetWidth(iconSize)
  frame.texture:SetPoint("CENTER", 0, 0)
  frame.texture:SetTexture(PIN_FALLBACK_TEXTURE)

  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  frame:SetScript("OnEnter", function(self)
    if Map._pinnedPin and Map._pinnedPin ~= self then return end
    if not self.discovery then return end
    Map:ShowDiscoveryTooltip(self)
  end)
  frame:SetScript("OnLeave", function(self)
    if Map._pinnedPin == self then return end
    Map:HideDiscoveryTooltip()
  end)
  frame:SetScript("OnClick", function(self, button)
    local d = self.discovery
    if not d then return end

    
    if IsControlKeyDown() and IsAltKeyDown() and button == "RightButton" then
        if d.il then
            local zoneName = L.ResolveZoneDisplay(d.c, d.z, d.iz)
            local coords = string.format("%.1f, %.1f", (d.xy.x or 0) * 100, (d.xy.y or 0) * 100)
            local msg = string.format("%s @ %s (%s)", d.il, zoneName, coords)
            if ChatFrame1EditBox:IsVisible() then
                ChatFrame1EditBox:Insert(msg)
            else
                ChatFrame_OpenChat(msg)
            end
        end
        return 
    elseif IsShiftKeyDown() and IsAltKeyDown() and button == "LeftButton" then
        Map:OpenShowToDialog(d)
        return 
    end

    
    if button == "RightButton" then
      Map:OpenPinMenu(self)
      return
    end
    if Map._pinnedPin == self then
      Map._pinnedPin = nil
      Map:HideDiscoveryTooltip()
    else
      Map._pinnedPin = self
      Map:ShowDiscoveryTooltip(self)
    end
  end)

  table.insert(self.pins, frame)
  return frame
end

local function GetCurrentMinimapShape()
  if _G.GetMinimapShape then
    local shape = _G.GetMinimapShape()
    return ValidMinimapShapes[shape] or ValidMinimapShapes["SQUARE"]
  end
  return ValidMinimapShapes["SQUARE"]
end

local function GetRotateMinimapFacing()
  local rotate = GetCVar and GetCVar("rotateMinimap")
  if rotate == "1" and MiniMapCompassRing and MiniMapCompassRing.GetFacing then
    return MiniMapCompassRing:GetFacing() or 0
  end
  return 0
end

function Map:UpdateMinimapPinSizes()
    local pinSize = (L.db and L.db.profile.mapFilters.minimapPinSize) or 10
    for _, pin in ipairs(self._mmPins) do
        pin:SetSize(pinSize, pinSize)
        if pin.tex then
            pin.tex:SetSize(pinSize - 2, pinSize - 2)
        end
    end
end

local function EnsureMmPin(i)
  if Map._mmPins[i] then return Map._mmPins[i] end
  
  local pinSize = (L.db and L.db.profile.mapFilters.minimapPinSize) or 10
  
  local f = CreateFrame("Button", "LootCollectorMinimapPin"..i, Minimap)
  f:SetSize(pinSize, pinSize)
  
  
  f.bg_border = f:CreateTexture(nil, "BACKGROUND")
  f.bg_border:SetAllPoints(f)
  f.bg_border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  f.bg_border:SetTexCoord(0.2, 0.8, 0.2, 0.8)
  f.bg_border:SetVertexColor(0, 0, 0, 0.25)
  
  
  f.color_frame = f:CreateTexture(nil, "BORDER")
  f.color_frame:SetTexture("Interface\\Buttons\\WHITE8X8") 
  f.color_frame:SetAllPoints(f)
  f.color_frame:Hide()
  
  
  local iconSize = pinSize - 2
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetSize(iconSize, iconSize)
  f.tex:SetPoint("CENTER")
  
  f:SetScript("OnEnter", function(self)
    if self.discovery and self.discovery.il then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(self.discovery.il)
      GameTooltip:Show()
    end
  end)
  f:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)
  f:Hide()
  Map._mmPins[i] = f
  return f
end

function Map:HideAllMmPins()
  for _, pin in ipairs(self._mmPins) do
    pin:Hide()
    pin.discovery = nil
    pin:SetScript("OnUpdate", nil)
  end
end

function Map:UpdateMinimap()
  local f = L:GetFilters()
  if not f or not f.showMinimap or not Minimap or (L.IsZoneIgnored and L:IsZoneIgnored()) then
    self:HideAllMmPins()
    return
  end

  local currentContinent, currentZoneID, px, py = GetCurrentMapContinent(), GetCurrentMapZone(), GetPlayerMapPosition("player")
  if not px or not py or not currentContinent or not currentZoneID then
    self:HideAllMmPins()
    return
  end

  
  if not (Map.WorldMapSize[currentContinent] and Map.WorldMapSize[currentContinent][currentZoneID]) then
    self:HideAllMmPins()
    return
  end

  local maxDist = 0
  if L.db and L.db.profile and L.db.profile.mapFilters then
    maxDist = L.db.profile.mapFilters.maxMinimapDistance or 0
  end

  local visibleDiscoveries = {}
  for guid, d in pairs(L.db.global.discoveries or {}) do
    if type(d) == "table"
       and d.c == currentContinent
       and d.z == currentZoneID
       and d.z > 0
       and d.s ~= "STALE" 
       and passesFilters(d)
    then
      if maxDist == 0 then
        table.insert(visibleDiscoveries, d)
      else
        local dx = d.xy and d.xy.x
        local dy = d.xy and d.xy.y
        if dx and dy then
          
          local dist = ComputeDistance(currentContinent, currentZoneID, px, py, d.c, d.z, dx, dy)
          if dist and dist <= maxDist then
            table.insert(visibleDiscoveries, d)
          end
        end
      end
    end
  end

  for i = 1, math.max(#self._mmPins, #visibleDiscoveries) do
    local pin = EnsureMmPin(i)
    local discovery = visibleDiscoveries[i]
    if discovery then
      pin.discovery = discovery
      local icon = self:GetDiscoveryIcon(discovery)
      pin.tex:SetTexture(icon or PIN_FALLBACK_TEXTURE)
      
      local r, g, b = GetQualityColor(discovery.q or select(3,GetItemInfo(discovery.il or discovery.i)))
      local isLooted = L:IsLootedByChar(discovery.g)

      pin.bg_border:Show()

      if isLooted then
          
          local gray = 0.5
          pin.color_frame:Hide()
          pin.tex:SetVertexColor(gray, gray, gray)
      else
          
          if icon == PIN_FALLBACK_TEXTURE then
              
              pin.tex:SetVertexColor(r, g, b)
              pin.color_frame:Hide()
          else
              
              pin.tex:SetVertexColor(1, 1, 1)
              pin.color_frame:SetVertexColor(r, g, b)
              pin.color_frame:Show()
          end
      end
      
      pin:Show()
      
    else
      pin:Hide()
      pin.discovery = nil
    end
  end
end

function Map:BuildClusterPin(index)
    local pin = CreateFrame("Button", nil, WorldMapButton)
    pin:SetSize(48, 48) 
    pin:SetFrameStrata(WorldMapButton:GetFrameStrata())
    pin:SetFrameLevel(WorldMapButton:GetFrameLevel() + 20)
    
    if not pin.count then
        pin.count = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		
		pin.count:SetFont("Fonts\\FRIZQT__.ttf", 16, "OUTLINE")		
        pin.count:SetPoint("TOP", pin, "TOP")
        pin.count:SetTextColor(1, 1, 1, 1)
        pin.count:SetShadowOffset(2, -2)
        pin.count:SetShadowColor(0, 0, 0, 1)
    end
    
    if not pin.label then
        pin.label = pin:CreateFontString(nil, "OVERLAY", "GameFontNormal")       	
	    pin.label:SetFont("Fonts\\FRIZQT__.ttf", 12, "OUTLINE")		
        pin.label:SetJustifyH("CENTER")
        pin.label:SetPoint("TOP", pin.count, "BOTTOM", 0, -2)
        pin.label:SetTextColor(1, 1, 1, 1)
        pin.label:SetShadowOffset(1, -1)
        pin.label:SetShadowColor(0, 0, 0, 1)
    end

    pin:SetScript("OnLeave", GameTooltip_Hide)
    pin:SetScript("OnUpdate", nil)

    self.clusterPins[index] = pin
    return pin
end

function Map:EnsureMinimapTicker()
  if self._mmTicker then return end
  
  -- Custom starter zones that have WorldMapSize but need fallback calculation
  local customZones = {
    --[1] = { [45] = true, [25] = true, [24] = true, [1] = true },  -- Kalimdor starters
    --[2] = { [29] = true, [9] = true, [39] = true, [11] = true }   -- Eastern Kingdoms starters
  }
  
  self._mmTicker = CreateFrame("Frame")
  self._mmTicker:SetScript("OnUpdate", function(_, elapsed)
    Map._mmElapsed = (Map._mmElapsed or 0) + elapsed
    if Map._mmElapsed >= Map._mmInterval then
      Map._mmElapsed = 0
      
      Map:UpdateMinimap()
      
      local px, py = GetPlayerMapPosition("player")
      if not px then return end

      local c, z = GetCurrentMapContinent(), GetCurrentMapZone()
      local isAstrolabeZone = Map.WorldMapSize[c] and Map.WorldMapSize[c][z]
      local isCustomZone = customZones[c] and customZones[c][z]

      -- Use GetViewRadius() for accurate minimap diameter in yards
      local minimapRadius = Minimap:GetViewRadius()
      local mapWidth = Minimap:GetWidth()
      local mapHeight = Minimap:GetHeight()
      -- yards per pixel
      local xScale = (minimapRadius * 2) / mapWidth
      local yScale = (minimapRadius * 2) / mapHeight
      local edgeRadius = minimapRadius - 8

      -- Rotation setup
      local facing = GetPlayerFacing()
      local rotateEnabled = (GetCVar("rotateMinimap") == "1")
      local cos_f, sin_f
      if rotateEnabled then
        cos_f = math.cos(facing)
        sin_f = math.sin(facing)
      end

      -- Edge detection
      local shapeData = GetCurrentMinimapShape()
      local isRoundShape = shapeData and shapeData["SQUARE"] == false

      for _, pin in ipairs(Map._mmPins) do
        if pin:IsShown() and pin.discovery then
            local d = pin.discovery
            local xDist, yDist

            -- Use fallback for custom zones OR non-Astrolabe zones
            if isAstrolabeZone and not isCustomZone then
                local _, xD, yD = ComputeDistance(c, z, px, py, d.c, d.z, d.xy.x, d.xy.y)
                if xD then
                    xDist, yDist = xD, yD
                else
                    pin:Hide()
                end
            else
                -- Fallback calculation for custom zones and non-Astrolabe zones
                local zoneData = Map.WorldMapSize[c] and Map.WorldMapSize[c][z]
                local ZONE_YARDS = zoneData and zoneData.width or 1000
                local dx = (d.xy.x or 0) - px
                local dy = (d.xy.y or 0) - py
                xDist = dx * ZONE_YARDS
                yDist = dy * ZONE_YARDS
            end

            if xDist and yDist then
                -- Rotation (in yards, before pixel conversion)
                if rotateEnabled then
                    local dx, dy = xDist, yDist
                    xDist = dx * cos_f - dy * sin_f
                    yDist = dx * sin_f + dy * cos_f
                end

                -- Calculate distance based on minimap shape
                local dist
                if isRoundShape then
                    dist = math.sqrt(xDist * xDist + yDist * yDist)
                else
                    dist = math.max(math.abs(xDist), math.abs(yDist))
                end
                
                -- Clamp to edge (in yards)
                local iconRadius = (pin:GetWidth() / 2) * xScale
                if dist + iconRadius > edgeRadius then
                    local maxDist = edgeRadius - iconRadius
                    if dist > 0 and maxDist > 0 then
                        local scale = maxDist / dist
                        xDist = xDist * scale
                        yDist = yDist * scale
                    end
                end
                
                -- Position pin
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", Minimap, "CENTER", xDist / xScale, -yDist / yScale)
            end
        end
      end
    end
  end)
  
  self._mmTicker:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  self._mmTicker:SetScript("OnEvent", function(self, event)
    if event == "ZONE_CHANGED_NEW_AREA" then
        -- MODIFIED: Instead of forcing an immediate scan, schedule it.
        -- This prevents a lag spike during the zone transition.
        C_Timer.After(1.5, function()
            if Map._mmTicker and Map._mmTicker:IsShown() then
                Map:UpdateMinimap()
            end
        end)
    end
  end)
end




function Map:ToggleSearchUI(show)
    self:EnsureSearchUI()
    if self._searchFrame then
        if show then
            self._searchFrame:Show()
        else
            self._searchFrame:Hide()
            if self._searchBox then
                self._searchBox:SetText("")
            end
            if self._searchResultsFrame and self._searchResultsFrame:IsShown() then
                self._searchResultsFrame:Hide()
            end
        end
    end
end

function Map:EnsureSearchUI()
if L.LEGACY_MODE_ACTIVE then return end
    if self._searchFrame then return end
    if not WorldMapDetailFrame then return end
    if L.db.profile.mapFilters.hideSearchBar then return end

    local f = CreateFrame("Frame", "LootCollectorMapSearchFrame", WorldMapDetailFrame)
    f:SetSize(400, 30)
    f:SetPoint("BOTTOM", WorldMapDetailFrame, "BOTTOM", 0, 5)
    f:SetFrameStrata("HIGH")

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 5, 0)
    label:SetText("Filter:")

    local editBox = CreateFrame("EditBox", "LootCollectorMapSearchBox", f, "InputBoxTemplate")
    editBox:SetSize(180, 20)
    editBox:SetPoint("LEFT", label, "RIGHT", 5, 0)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnTextChanged", function()
        if Map._searchTimer then
            C_Timer.CancelTimer(Map._searchTimer)
            Map._searchTimer = nil
        end
        Map._searchTimer = C_Timer.After(0.7, function()
            Map:Update()
            Map._searchTimer = nil
        end)
    end)

    local findBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    findBtn:SetSize(60, 22)
    findBtn:SetText("Find")
    findBtn:SetPoint("LEFT", editBox, "RIGHT", 5, 0)
    findBtn:SetScript("OnClick", function() Map:ExecuteSearch() end)
    
    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(60, 22)
    clearBtn:SetText("Clear")
    clearBtn:SetPoint("LEFT", findBtn, "RIGHT", 5, 0)
    clearBtn:SetScript("OnClick", function()
        editBox:SetText("")
        if Map._searchResultsFrame then Map._searchResultsFrame:Hide() end
    end)

    self._searchFrame = f
    self._searchBox = editBox
end

function Map:ExecuteSearch()
    if self._searchResultsFrame then self._searchResultsFrame:Hide() end
    
    local term = self._searchBox and string.lower(self._searchBox:GetText() or "")
    if not term or term == "" then return end

    local results = {}
    for _, d in pairs(L.db.global.discoveries or {}) do
        if SearchDiscoveryForTerm(d, term) then
            table.insert(results, d)
        end
    end

    if #results == 0 then
        print("|cffff7f00LootCollector:|r No discovery found matching '"..term.."'")
    elseif #results == 1 then
        self:FocusOnDiscovery(results[1])
    else
        self:ShowSearchResults(results)
    end
end

function Map:ShowSearchResults(results)
  if not self._searchResultsFrame then
      
      local f = CreateFrame("Frame", "LootCollectorSearchResultsFrame", UIParent)
      f:SetSize(450, 250)
      f:SetPoint("CENTER")
      f:SetFrameStrata("HIGH")
      f:SetFrameLevel(101) 
      f:SetBackdrop({ bgFile = "Interface/DialogFrame/UI-DialogBox-Background", edgeFile = "Interface/DialogFrame/UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
      f:SetMovable(true)
      f:EnableMouse(true)
      f:RegisterForDrag("LeftButton")
      f:SetScript("OnDragStart", f.StartMoving)
      f:SetScript("OnDragStop", f.StopMovingOrSizing)
      
      local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      title:SetPoint("TOP", 0, -16)
      title:SetText("Multiple Discoveries Found")

      local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
      closeBtn:SetPoint("TOPRIGHT", -4, -4)
      closeBtn:SetScript("OnClick", function() f:Hide() end)

      f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
      f.scroll:SetPoint("TOPLEFT", 16, -38)
      f.scroll:SetPoint("BOTTOMRIGHT", -34, 12)

      f.content = CreateFrame("Frame", nil, f.scroll)
      f.scroll:SetScrollChild(f.content)
      f.content:SetWidth(400)
      f.content:SetHeight(1)
      f.buttons = {}
      
      self._searchResultsFrame = f
  end

  local f = self._searchResultsFrame
  for _, btn in ipairs(f.buttons) do
      btn:Hide()
  end
  
  table.sort(results, function(a,b) return (a.ls or 0) > (b.ls or 0) end)
  
  local Constants = L:GetModule("Constants", true)

  for i, d in ipairs(results) do
      local btn = f.buttons[i]
      if not btn then
          btn = CreateFrame("Button", nil, f.content)
          btn:SetSize(400, 20)
          f.buttons[i] = btn
      end
      
      if i == 1 then
          btn:SetPoint("TOPLEFT", 0, 0)
      else
          btn:SetPoint("TOPLEFT", f.buttons[i-1], "BOTTOMLEFT", 0, -2)
      end
      
      local text = btn.text or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      btn.text = text
      text:SetAllPoints(true)
      text:SetJustifyH("LEFT")

      local zoneName
      local c, z, iz = tonumber(d.c) or 0, tonumber(d.z) or 0, tonumber(d.iz) or 0
      
      do
          local ZL = L:GetModule("ZoneList", true)
          if z == 0 then
              zoneName = (ZL and ZL.ResolveIz and ZL:ResolveIz(iz)) or (GetRealZoneText and GetRealZoneText()) or "Unknown Instance"
          else
              zoneName = (ZL and ZL.GetZoneName and ZL:GetZoneName(c, z)) or "Unknown Zone"
          end
      end
      
      local coords = string.format("%.1f, %.1f", (d.xy.x or 0) * 100, (d.xy.y or 0) * 100)

      local metaParts = {}
      if d.dt and Constants and Constants.DISCOVERY_TYPE then
          if d.dt == Constants.DISCOVERY_TYPE.WORLDFORGED then table.insert(metaParts, "WF")
          elseif d.dt == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL then table.insert(metaParts, "MS")
          end
      end
      if d.it and d.ist and Constants and Constants.ID_TO_ITEM_TYPE and Constants.ID_TO_ITEM_SUBTYPE then
          local typeStr = Constants.ID_TO_ITEM_TYPE[d.it]
          local subTypeStr = Constants.ID_TO_ITEM_SUBTYPE[d.ist]
          if subTypeStr then
              table.insert(metaParts, subTypeStr)
          elseif typeStr then
              table.insert(metaParts, typeStr)
          end
      end
      local meta = table.concat(metaParts, ", ")
      
      text:SetText(string.format("%s (%s) | %s | %s", d.il or "Unknown Item", zoneName, coords, meta))

      btn:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
      
      btn:SetScript("OnClick", function()
          Map:FocusOnDiscovery(d)
      end)
      
      btn:SetScript("OnEnter", function(self)
          if d.il and d.il:find("|Hitem:") then
              GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
              GameTooltip:SetHyperlink(d.il)
              GameTooltip:Show()
          end
      end)
      btn:SetScript("OnLeave", GameTooltip_Hide)
      
      btn:Show()
  end

  f.content:SetHeight(#results * 22)
  f:Show()
end

function Map:PopulateShowToDropdown(dropdownFrame, level)
  local f = self._showToDialog
  if not f then return end

  local myName = UnitName("player")

  
  local groupAdded = false
  local function addGroupMember(name)
      if name and name ~= myName then
          local info = {} 
          info.text = name
          info.func = function() f.editBox:SetText(name) end
          UIDropDownMenu_AddButton(info, level)
          groupAdded = true
      end
  end
  
  if IsInRaid() then
      local info = { text = "Raid", isTitle = true, notCheckable = true }
      UIDropDownMenu_AddButton(info, level)
      for i = 1, GetNumRaidMembers() do
          addGroupMember(GetRaidRosterInfo(i))
      end
  elseif GetNumPartyMembers() > 0 then
      local info = { text = "Party", isTitle = true, notCheckable = true }
      UIDropDownMenu_AddButton(info, level)
      for i = 1, GetNumPartyMembers() do
          addGroupMember(UnitName("party"..i))
      end
  end
  if groupAdded then 
      local info = { text = "", notCheckable = true, disabled = true }
      UIDropDownMenu_AddButton(info, level)
  end

  
  if #self._cachedRecent > 0 then
      local info = { text = "Recent", isTitle = true, notCheckable = true }
      UIDropDownMenu_AddButton(info, level)
      for _, name in ipairs(self._cachedRecent) do
          local recentInfo = {} 
          recentInfo.text = name
          recentInfo.func = function() f.editBox:SetText(name) end
          UIDropDownMenu_AddButton(recentInfo, level)
      end
      local sepInfo = { text = "", notCheckable = true, disabled = true }
      UIDropDownMenu_AddButton(sepInfo, level)
  end

  
  if #self._cachedFriends > 0 then
      local info = { text = "Friends (Online)", isTitle = true, notCheckable = true }
      UIDropDownMenu_AddButton(info, level)
      for _, friend in ipairs(self._cachedFriends) do
          local friendInfo = {} 
          friendInfo.text = friend.name
          friendInfo.func = function() f.editBox:SetText(friend.name) end
          UIDropDownMenu_AddButton(friendInfo, level)
      end
      local sepInfo = { text = "", notCheckable = true, disabled = true }
      UIDropDownMenu_AddButton(sepInfo, level)
  end

  
  
  
  
  
  
  
  
  
  
  
end

function Map:EnsureShowToDialog()
  if self._showToDialog then return end

  
  local f = CreateFrame("Frame", "LootCollectorShowToDialog", UIParent)
  f:SetSize(360, 180)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetFrameLevel(100) 
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 8, right = 8, top = 8, bottom = 8 }
  })
  f:Hide()
  
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -16)
  title:SetText("Show Discovery To") 

  local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", 16, -50)
  label:SetText("Player Name:")

  local editBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  editBox:SetSize(220, 20)
  editBox:SetPoint("LEFT", label, "RIGHT", 8, 0)
  editBox:SetAutoFocus(true)
  
  
  local dropdown = CreateFrame("Frame", "LootCollectorShowToDropdown", f, "UIDropDownMenuTemplate")
  dropdown:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", -16, -8)
  dropdown:SetFrameLevel(f:GetFrameLevel() + 1)
  UIDropDownMenu_Initialize(dropdown, function(self, level) 
      Map:PopulateShowToDropdown(self, level) 
  end)
  UIDropDownMenu_SetWidth(dropdown, 220)
  UIDropDownMenu_SetText(dropdown, "Select from Lists...")
  dropdown:Show()

  local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  cancelBtn:SetSize(100, 22)
  cancelBtn:SetPoint("BOTTOMRIGHT", -12, 12)
  cancelBtn:SetText("Cancel")
  
  local sendBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sendBtn:SetSize(100, 22)
  sendBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -4, 0)
  sendBtn:SetText("Send")
  
  cancelBtn:SetScript("OnClick", function() f:Hide() end)
  
  sendBtn:SetScript("OnClick", function()
      local playerName = editBox:GetText()
      if playerName and playerName ~= "" and f.discovery then
          local Comm = L:GetModule("Comm", true)
          if Comm and Comm.BroadcastShow then
              Comm:BroadcastShow(f.discovery, playerName)
              
              
              local found = false
              for _, name in ipairs(Map._cachedRecent) do
                  if name == playerName then found = true; break end
              end
              if not found then
                  table.insert(Map._cachedRecent, 1, playerName)
                  if #Map._cachedRecent > Map.MAX_RECENT_NAMES then
                      table.remove(Map._cachedRecent)
                  end
              end

              f:Hide()
          end
      else
          print("|cffff7f00LootCollector:|r Please enter a player name.")
      end
  end)
  
  f.titleText = title
  f.editBox = editBox
  f.playerDropdown = dropdown
  self._showToDialog = f
end

function Map:OpenShowToDialog(discovery)
  if not discovery then return end
  self:EnsureShowToDialog()
  
  self._showToDialog.discovery = discovery
  self._showToDialog.editBox:SetText("")
  
  
  local itemName = (discovery.il and discovery.il:match("%[(.+)%]")) or "Discovery"
  local truncatedName = itemName
  if #itemName > 25 then
      truncatedName = string.sub(itemName, 1, 22) .. "..."
  end
  self._showToDialog.titleText:SetText("Show " .. truncatedName .. " To")
  
  UIDropDownMenu_SetText(self._showToDialog.playerDropdown, "Select from Lists...")
  self._showToDialog:Show()
  self._showToDialog.editBox:SetFocus()
end

function Map:UpdateFriendCache()
    wipe(self._cachedFriends)
    for i = 1, GetNumFriends() do
        local name, _, _, _, connected = GetFriendInfo(i)
        if name and connected then
            table.insert(self._cachedFriends, { name = name })
        end
    end
    table.sort(self._cachedFriends, function(a, b) return a.name < b.name end)
end

function Map:UpdateGuildCache()
    wipe(self._cachedGuild)
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and online then
            table.insert(self._cachedGuild, { name = name })
        end
    end
    table.sort(self._cachedGuild, function(a, b) return a.name < b.name end)
end

function Map:OnInitialize()
if L.LEGACY_MODE_ACTIVE then return end
  if not (L.db and L.db.profile and L.db.global and L.db.char) then return end
  self:EnsureFilterUI()
  self:EnsureMinimapTicker()

  
  self:RegisterEvent("FRIENDLIST_UPDATE", "UpdateFriendCache")
  self:RegisterEvent("GUILD_ROSTER_UPDATE", "UpdateGuildCache")
  
  
  C_Timer.After(3, function()
      if ShowFriends then ShowFriends() end
      if GuildRoster then GuildRoster() end
  end)

  
  GameTooltip:HookScript("OnHide", function()
      if Map._bmItemLines then
          for _, lineFrame in ipairs(Map._bmItemLines) do
              lineFrame:Hide()
          end
      end
      if ItemRefTooltip then
          ItemRefTooltip:Hide()
      end
  end)

  if WorldMapDetailFrame then
    WorldMapDetailFrame:SetScript("OnMouseDown", function()
        if Map._pinnedPin then
            Map._pinnedPin = nil
            Map:HideDiscoveryTooltip()
        end
        
        local menuHost = _G["LootCollectorFilterMenuHost"]
        if menuHost and UIDropDownMenu_IsVisible(menuHost) then
            local isOverMenu = MouseIsOver(menuHost)
            for i = 1, UIDROPDOWNMENU_MAXLEVELS do
                local dropdown = _G["DropDownList"..i]
                if dropdown and dropdown:IsShown() and MouseIsOver(dropdown) then
                    isOverMenu = true
                    break
                end
            end
            if not isOverMenu then
                CloseDropDownMenus()
            end
        end
    end)
  end

  if WorldMapFrame and hooksecurefunc then
    hooksecurefunc(WorldMapFrame, "Show", function()
        Map:EnsureSearchUI()
        if Map._searchFrame and not L.db.profile.mapFilters.hideSearchBar then Map._searchFrame:Show() end
        
        
        Map:EnsureShowToDialog()
        if Map._showToDialog then
            Map._showToDialog:SetParent(WorldMapFrame)
            Map._showToDialog:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 50)
        end

        
        if Map._searchResultsFrame then
            Map._searchResultsFrame:SetParent(WorldMapFrame)
            Map._searchResultsFrame:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 51)
        end
    end)
    hooksecurefunc(WorldMapFrame, "Hide", function()
      if Map._pinnedPin then
        Map._pinnedPin = nil
        Map:HideDiscoveryTooltip()
      end
      if Map._searchFrame then Map._searchFrame:Hide() end
      if Map._searchBox then Map._searchBox:SetText("") end
      if Map._searchResultsFrame and Map._searchResultsFrame:IsShown() then
        
      end
      
      
      if Map._showToDialog then
          Map._showToDialog:SetParent(UIParent)
          Map._showToDialog:ClearAllPoints()
          Map._showToDialog:SetPoint("CENTER")
      end

      
      if Map._searchResultsFrame then
          Map._searchResultsFrame:SetParent(UIParent)
          Map._searchResultsFrame:ClearAllPoints()
          Map._searchResultsFrame:SetPoint("CENTER")
      end
    end)
  end
end

function Map:Update()
  if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
  
  
  self:EnsureSearchUI()

  if L.IsZoneIgnored and L:IsZoneIgnored() then
    for _, pin in ipairs(self.pins) do pin:Hide() end
    for _, pin in ipairs(self.clusterPins) do pin:Hide() end
    self._pinnedPin = nil; self:HideDiscoveryTooltip()
    return
  end
  if not (L.db and L.db.global and (L.db.global.discoveries or L.db.global.blackmarketVendors)) then
    for _, pin in ipairs(self.pins) do pin:Hide() end
    for _, pin in ipairs(self.clusterPins) do pin:Hide() end
    self._pinnedPin = nil; self:HideDiscoveryTooltip()
    return
  end

  self:EnsureFilterUI()
  local filters = L:GetFilters()
  if filters.hideAll then
    for _, pin in ipairs(self.pins) do pin:Hide() end
    for _, pin in ipairs(self.clusterPins) do pin:Hide() end
    self._pinnedPin = nil; self:HideDiscoveryTooltip()
    return
  end

  local currentContinent, currentZoneID, currentMapID = GetCurrentMapContinent(), GetCurrentMapZone(), GetCurrentMapAreaID()
  

  if not WorldMapDetailFrame or not WorldMapButton then return end
  local mapWidth, mapHeight = WorldMapDetailFrame:GetWidth(), WorldMapDetailFrame:GetHeight()
  if not mapWidth or mapWidth == 0 then return end
  local mapLeft, mapTop = WorldMapDetailFrame:GetLeft(), WorldMapDetailFrame:GetTop()
  local parentLeft, parentTop = WorldMapButton:GetLeft(), WorldMapButton:GetTop()
  local offsetX, offsetY = mapLeft - parentLeft, mapTop - parentTop

  local pinIndex, stillPinned = 1, false

  
  
  local allDiscoveries = {}
  if L.db.global.discoveries then
      for guid, d in pairs(L.db.global.discoveries) do
          table.insert(allDiscoveries, d)
      end
  end
  if L.db.global.blackmarketVendors then
      for guid, d in pairs(L.db.global.blackmarketVendors) do
          table.insert(allDiscoveries, d)
      end
  end
  
  for _, d in ipairs(allDiscoveries) do
    if type(d) == "table" and d.xy then
        local recordContinent = d.c
        local recordZone = d.z
        
        if recordContinent == currentContinent and recordZone == currentZoneID and recordZone > 0 and passesFilters(d) then
            local pin = self.pins[pinIndex] or self:BuildPin()
            pinIndex = pinIndex + 1
            pin.discovery = d
            pin:SetSize((filters.pinSize or 16), (filters.pinSize or 16))
            
            local icon = self:GetDiscoveryIcon(d)
            pin.texture:SetTexture(icon or PIN_FALLBACK_TEXTURE)
            
            local isLooted = L:IsLootedByChar(d.g)
            local isFallback = (icon == PIN_FALLBACK_TEXTURE)

            if pin.border then pin.border:Show() end

            if d.s == "STALE" then
                pin.texture:SetVertexColor(0.9, 0.5, 0.0)
                if pin.unlootedOutline then
                    pin.unlootedOutline:Show()
                    pin.unlootedOutline:SetVertexColor(1, 1, 1)
                end
            elseif isLooted then
                pin.texture:SetVertexColor(0.5, 0.5, 0.5)
                if pin.unlootedOutline then pin.unlootedOutline:Hide() end
            else
                if isFallback then
                    if pin.unlootedOutline then pin.unlootedOutline:Hide() end
                    local r, g, b = GetQualityColor(d.q or select(3,GetItemInfo(d.il or d.i)))
                    pin.texture:SetVertexColor(r, g, b)
                else
                    pin.texture:SetVertexColor(1, 1, 1)
                    if pin.unlootedOutline then
                        pin.unlootedOutline:Show()
                        local r, g, b = GetQualityColor(d.q or select(3, GetItemInfo(d.il or d.i)))
                        pin.unlootedOutline:SetVertexColor(r, g, b)
                    end
                end
            end

            pin:SetAlpha(AlphaForStatus(L:GetDiscoveryStatus(d)))
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", WorldMapButton, "TOPLEFT", offsetX + d.xy.x * mapWidth, offsetY - d.xy.y * mapHeight)
            pin:Show()
            if d.mid then self._pinsByMid[d.mid] = pin end
            if self._pinnedPin == pin then stillPinned = true; self:ShowDiscoveryTooltip(pin) end
        end
    end
  end
  
  for i = pinIndex, #self.pins do self.pins[i]:Hide() self.pins[i].discovery = nil end
  if self._pinnedPin and not stillPinned then self._pinnedPin = nil; self:HideDiscoveryTooltip() end
  

  local ZoneList = L:GetModule("ZoneList", true)
  local clusterPinIndex = 1

  
  if ZoneList and ZoneList.ParentToSubzones and ZoneList.ParentToSubzones[currentMapID] then
    for _, childMapID in ipairs(ZoneList.ParentToSubzones[currentMapID]) do
        local subzoneData = ZoneList.ZoneRelationships and ZoneList.ZoneRelationships[childMapID]
        if subzoneData then
            local count = 0
            for guid, d in pairs(L.db.global.discoveries) do
                if d.c == subzoneData.c and d.z == subzoneData.z and passesFilters(d) then
                    count = count + 1
                end
            end
            if count > 0 then
                local pin = self.clusterPins[clusterPinIndex] or self:BuildClusterPin(clusterPinIndex)
                clusterPinIndex = clusterPinIndex + 1
                pin.count:SetText(count)
                
                if subzoneData.label and subzoneData.label ~= "" then
                    pin.label:SetText(subzoneData.label)
                else
                    pin.label:SetText("disc\ninside!")
                end
                
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", WorldMapButton, "TOPLEFT", offsetX + subzoneData.entrance.x * mapWidth, offsetY + subzoneData.entrance.y * -mapHeight)
                pin:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(subzoneData.name, 1,1,0); GameTooltip:AddLine(count .. " discoveries inside.", 1,1,1)
                    GameTooltip:AddLine("\n|cff00ff00Click to view this zone.|r", .8,.8,.8, true); GameTooltip:Show()
                end)
                pin:SetScript("OnClick", function() if SetMapZoom then SetMapZoom(subzoneData.c, subzoneData.z) end end)
                pin:Show()
            end
        end
    end
  end
  
  
  
  if filters.showZoneSummaries and currentZoneID == 0 and ZoneList and ZoneList.ZoneRelationshipsC then
    for _, zoneData in pairs(ZoneList.ZoneRelationshipsC) do
        if zoneData and zoneData.parent and zoneData.parent.z == 0 and zoneData.parent.c == currentContinent then
            local count = 0
            for guid, d in pairs(L.db.global.discoveries) do
                if d.c == zoneData.c and d.z == zoneData.z and passesFilters(d) then
                    count = count + 1
                end
            end
            
            if count > 0 then
                local pin = self.clusterPins[clusterPinIndex] or self:BuildClusterPin(clusterPinIndex)
                clusterPinIndex = clusterPinIndex + 1
                pin.count:SetText(count)
                pin.label:SetText(zoneData.label or "L00Ts")
                
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", WorldMapButton, "TOPLEFT", offsetX + zoneData.entrance.x * mapWidth, offsetY + zoneData.entrance.y * -mapHeight)
                pin:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(zoneData.name, 1,1,0); GameTooltip:AddLine(count .. " discoveries in this zone.", 1,1,1)
                    GameTooltip:AddLine("\n|cff00ff00Click to view this zone.|r", .8,.8,.8, true); GameTooltip:Show()
                end)
                pin:SetScript("OnClick", function() if SetMapZoom then SetMapZoom(zoneData.c, zoneData.z) end end)
                pin:Show()
            end
        end
    end
  end

  for i = clusterPinIndex, #self.clusterPins do self.clusterPins[i]:Hide() end
end

function Map:AddOrUpdatePinV5(rec)
  if not rec or not rec.xy then return false end
  local c = tonumber(rec.c) or 0
  local z = tonumber(rec.z) or 0
  if z == 0 then return false end
  local currentContinent = GetCurrentMapContinent()
  local currentZoneID = GetCurrentMapZone()
  if c == currentContinent and z == currentZoneID then
    self:Update()
    return true
  end
  return false
end

function Map:RemovePinByMid(mid)
  if not mid then return end
  local pin = self._pinsByMid[mid]
  if not pin then return end
  pin:Hide()
  pin.discovery = nil
  self._pinsByMid[mid] = nil
end

function Map:RefreshV5()
  self:Update()
end

function Map:OnRecordStatusChanged(rec)
  if not rec or not rec.mid then return end
  if rec.s == "STALE" then 
    
    self:Update()
  else
    self:AddOrUpdatePinV5(rec)
  end
end

return Map
-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl