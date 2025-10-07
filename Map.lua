-- Map.lua
-- Item-icon pins on the world map, sticky tooltip with right-side hover icon,
-- LC filter menu via EasyMenu, and optional minimap edge indicators for discoveries.

local L = LootCollector
local Map = L:NewModule("Map")

local BZ = LibStub("LibBabble-Zone-3.0")
local BZL = BZ:GetUnstrictLookupTable()
local BZR = BZ:GetReverseLookupTable()

local ItemInfoCache = {}
local function GetCachedItemInfo(linkOrId)
    if not linkOrId or linkOrId == "" then return nil end
    if ItemInfoCache[linkOrId] then return unpack(ItemInfoCache[linkOrId]) end

    local name, itemLink, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, texture, sellPrice = GetItemInfo(linkOrId)
    if name then
        ItemInfoCache[linkOrId] = { name, itemLink, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, texture, sellPrice }
    end
    return name, itemLink, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, texture, sellPrice
end

local MapZoneCache = {}
local function GetMapZoneNumbers(zonename)
    local cached = MapZoneCache[zonename]
    if cached then return unpack(cached) end

    -- Try to translate the zone name to English using LibBabble-Zone-3.0 if it's not already English
    local canonicalZonename = BZR[zonename] or zonename
    for cont in pairs{GetMapContinents()} do
        for zone,name in pairs{GetMapZones(cont)} do
            local cleanedName = string.lower(string.trim(name or ""))
            local cleanedCanonicalZonename = string.lower(string.trim(canonicalZonename or ""))
            if cleanedName == cleanedCanonicalZonename then
                MapZoneCache[zonename]={cont,zone}
                return cont,zone
            end
        end
    end
    return 0,0
end

-- Pin size (per request)
local PIN_FALLBACK_TEXTURE = "Interface\\AddOns\\LootCollector\\media\\pin"

Map.pins = Map.pins or {}
Map._pinnedPin = nil

-- Tooltip item hover button
Map._hoverBtn = Map._hoverBtn or nil
Map._hoverBtnItemLink = nil

local itemInfoTooltip = nil

-- Pin context dropdown
local DropFrame = CreateFrame("Frame", "LootCollectorPinDropDown", UIParent, "UIDropDownMenuTemplate")
local menuList = {}

StaticPopupDialogs["LOOTCOLLECTOR_REMOVE_DISCOVERY"] = {
  text = "Are you sure you want to permanently remove this discovery?",
  button1 = "Yes",
  button2 = "No",
  OnAccept = function(self, data)
    if data then
      local Core = L:GetModule("Core", true)
      if Core and Core.RemoveDiscovery then
        Core:RemoveDiscovery(data)
      end
    end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

-- World map LC button and EasyMenu host
local FilterButton = nil
local FilterMenuHost = CreateFrame("Frame", "LootCollectorFilterMenuHost", UIParent, "UIDropDownMenuTemplate")
Map._filters = Map._filters or {}

-- Minimap shape definitions (which corners are rounded)
-- { upper-left, lower-left, upper-right, lower-right }
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

-- Distance scale values for different minimap zoom levels
local MINIMAP_ZOOM_SCALES = {
  [0] = 0.10,  -- Largest view (largest area)
  [1] = 0.09, 
  [2] = 0.08,  
  [3] = 0.07,  
  [4] = 0.06, 
  [5] = 0.05, 
  [6] = 0.04,  
  [7] = 0.03,  -- Closest view (smallest area)
}

-- Minimap indicators
Map._mmPins = Map._mmPins or {}
Map._mmTicker = Map._mmTicker or nil
Map._mmElapsed = 0
Map._mmInterval = 0.1
Map._mmSize = 10

local function GetMinimapScale(zoom)
    return MINIMAP_ZOOM_SCALES[zoom] or MINIMAP_ZOOM_SCALES[0]
end

-- Slot options (INVTYPE for multi-select)
local SLOT_OPTIONS = {
  { loc = "INVTYPE_HEAD", text = "Head" }, { loc = "INVTYPE_NECK", text = "Neck" }, { loc = "INVTYPE_SHOULDER", text = "Shoulder" }, { loc = "INVTYPE_CHEST", text = "Chest" }, { loc = "INVTYPE_ROBE", text = "Robe" }, { loc = "INVTYPE_WAIST", text = "Waist" }, { loc = "INVTYPE_LEGS", text = "Legs" }, { loc = "INVTYPE_FEET", text = "Feet" }, { loc = "INVTYPE_WRIST", text = "Wrist" }, { loc = "INVTYPE_HAND", text = "Hands" }, { loc = "INVTYPE_FINGER", text = "Finger" }, { loc = "INVTYPE_TRINKET", text = "Trinket" }, { loc = "INVTYPE_CLOAK", text = "Back" }, { loc = "INVTYPE_WEAPON", text = "One-Hand" }, { loc = "INVTYPE_2HWEAPON", text = "Two-Hand" }, { loc = "INVTYPE_WEAPONMAINHAND", text = "Main Hand" }, { loc = "INVTYPE_WEAPONOFFHAND", text = "Off Hand" }, { loc = "INVTYPE_SHIELD", text = "Shield" }, { loc = "INVTYPE_HOLDABLE", text = "Held Off-hand" }, { loc = "INVTYPE_RANGED", text = "Ranged" }, { loc = "INVTYPE_RANGEDRIGHT", text = "Ranged (Right)" }, { loc = "INVTYPE_THROWN", text = "Thrown" }, { loc = "INVTYPE_RELIC", text = "Relic" },
}

-- Class options
local CLASS_OPTIONS = {
  "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST", "DEATHKNIGHT","SHAMAN","MAGE","WARLOCK","DRUID",
}

local function GetQualityColor(quality)
  quality = tonumber(quality); if not quality then return 1,1,1 end; if GetItemQualityColor then local r,g,b = GetItemQualityColor(quality); if r and g and b then return r,g,b end end; if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then local c = ITEM_QUALITY_COLORS[quality]; return c.r or 1, c.g or 1, c.b or 1 end; return 1,1,1
end

local STATUS_UNCONFIRMED = "UNCONFIRMED"; local STATUS_CONFIRMED = "CONFIRMED"; local STATUS_FADING = "FADING"; local STATUS_STALE = "STALE";

local function GetStatus(d)
  local s = (d and d.status) or STATUS_UNCONFIRMED; if s == STATUS_FADING or s == STATUS_STALE or s == STATUS_CONFIRMED or s == STATUS_UNCONFIRMED then return s end; return STATUS_UNCONFIRMED
end

local function AlphaForStatus(status)
  if status == STATUS_FADING then return 0.65 elseif status == STATUS_STALE then return 0.45 end; return 1.0
end

local function getFilters()
  return Map._filters
end

local function isLootedByChar(guid)
  if not (L.db and L.db.char and L.db.char.looted) then return false end; return L.db.char.looted[guid] and true or false
end

local function isClassAgnosticItem(itemType, equipLoc)
  if not itemType then return true end; if itemType ~= "Armor" and itemType ~= "Weapon" then return true end; return not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_CLOAK"
end

local function passesFilters(d)
  local f = getFilters()
  if f.hideAll then return false end
  
  local s = GetStatus(d)
  if s == STATUS_UNCONFIRMED and f.hideUnconfirmed then return false end
  if s == STATUS_FADING and f.hideFaded then return false end
  if s == STATUS_STALE  and f.hideStale  then return false end
  if f.hideLooted and d and d.guid and isLootedByChar(d.guid) then return false end
  
  local linkOrId = d.itemLink or d.itemID
  if linkOrId then
    local name, _, quality, _, _, itemType, _, _, equipLoc = GetCachedItemInfo(linkOrId)

    if f.hideUncached then
        if not name then
            return false
        end
    end
    
    if quality and quality < (f.minRarity or 0) then return false end
    if equipLoc and next(f.allowedEquipLoc) and not f.allowedEquipLoc[equipLoc] then return false end
    if next(f.allowedClasses) then 
      if itemType == "Armor" or itemType == "Weapon" then 
        if isClassAgnosticItem(itemType, equipLoc) then 
        else 
          local playerClass = select(2, UnitClass("player"))
          if playerClass and not f.allowedClasses[playerClass] then return false end 
        end 
      end 
    end

    if name then
        if string.find(name, "Mystic Scroll", 1, true) then
            if not f.showMysticScrolls then return false end
        else
            if not f.showWorldforged then return false end
        end
    end
  end
  return true
end

local function NavigateHere(discovery)
  if not discovery then return end; local Arrow = L:GetModule("Arrow", true); if Arrow and Arrow.NavigateTo then Arrow:NavigateTo(discovery) end
end

function Map:GetDiscoveryIcon(d)
  local texture = nil; if d and d.itemID then texture = select(10, GetCachedItemInfo(d.itemID)) end; if (not texture) and d and d.itemLink then texture = select(10, GetCachedItemInfo(d.itemLink)) end; return texture or PIN_FALLBACK_TEXTURE
end

function Map:EnsureHoverButton()
  if self._hoverBtn then return end; local btn = CreateFrame("Button", "LootCollectorItemHoverBtn", GameTooltip); btn:SetSize(16, 16); btn:SetFrameStrata("TOOLTIP"); btn:SetFrameLevel(GameTooltip:GetFrameLevel() + 10); btn:EnableMouse(true); btn.tex = btn:CreateTexture(nil, "ARTWORK"); btn.tex:SetAllPoints(btn); btn:Hide(); btn:SetScript("OnEnter", function(self) if not Map._hoverBtnItemLink then return end; ItemRefTooltip:SetOwner(UIParent, "ANCHOR_NONE"); ItemRefTooltip:ClearAllPoints(); ItemRefTooltip:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", 8, 0); ItemRefTooltip:SetHyperlink(Map._hoverBtnItemLink); ItemRefTooltip:Show() end); btn:SetScript("OnLeave", function(self) ItemRefTooltip:Hide() end); self._hoverBtn = btn
end

local SOURCE_TEXT_MAP = {
    world_loot = "World Loot",
    npc_gossip = "NPC Interaction",
    emote_event = "World Event",
    direct = "Direct (World Drop)",
}

function Map:ShowDiscoveryTooltip(pin)
    if not pin or not pin.discovery then return end; local d = pin.discovery; GameTooltip:SetOwner(pin, "ANCHOR_RIGHT"); GameTooltip:ClearLines(); if self._pinnedPin == pin and d.itemLink then if not itemInfoTooltip then itemInfoTooltip = CreateFrame("GameTooltip", "LootCollectorItemInfoTooltip", UIParent, "GameTooltipTemplate") end; itemInfoTooltip:SetOwner(UIParent, "ANCHOR_NONE"); itemInfoTooltip:SetHyperlink(d.itemLink); for i = 1, itemInfoTooltip:NumLines() do local line = _G["LootCollectorItemInfoTooltipTextLeft" .. i]; local r, g, b; if line and line:GetText() then r, g, b = line:GetTextColor(); GameTooltip:AddLine(line:GetText(), r, g, b) end end; itemInfoTooltip:Hide(); GameTooltip:AddLine(" ") else local name, _, quality = GetCachedItemInfo(d.itemLink or d.itemID or ""); local header = d.itemLink or name or "Discovery"; GameTooltip:AddLine(header, 1, 1, 1, true); if quality then local r, g, b = GetQualityColor(quality); GameTooltipTextLeft1:SetTextColor(r, g, b) end end; GameTooltip:AddLine(string.format("Found by: %s", d.foundBy_player or "Unknown"), 0.6, 0.8, 1, true); local ts = tonumber(d.timestamp) or time(); GameTooltip:AddDoubleLine("Date", date("%Y-%m-%d %H:%M", ts), 0.8, 0.8, 0.8, 1, 1, 1); local status = GetStatus(d); local ls = tonumber(d.lastSeen) or ts; GameTooltip:AddDoubleLine("Status", status, 0.8, 0.8, 0.8, 1, 1, 1); GameTooltip:AddDoubleLine("Last seen", date("%Y-%m-%d %H:%M", ls), 0.8, 0.8, 0.8, 1, 1, 1); 

    GameTooltip:AddDoubleLine("Zone", d.zone or "Unknown Zone", 0.8, 0.8, 0.8, 1, 1, 1); 
    if d.source then local sourceText = SOURCE_TEXT_MAP[d.source] or d.source; GameTooltip:AddDoubleLine("Source", sourceText, 0.8, 0.8, 0.8, 1, 1, 1) end; if d.coords then GameTooltip:AddDoubleLine("Location", string.format("%.1f, %.1f", (d.coords.x or 0) * 100, (d.coords.y or 0) * 100), 0.8, 0.8, 0.8, 1, 1, 1) end; if self._pinnedPin == pin and (d.itemLink or d.itemID) then self:EnsureHoverButton(); self._hoverBtnItemLink = d.itemLink or d.itemID; local icon = self:GetDiscoveryIcon(d); self._hoverBtn.tex:SetTexture(icon or PIN_FALLBACK_TEXTURE); GameTooltip:Show(); self._hoverBtn:ClearAllPoints(); if GameTooltipTextLeft1 then self._hoverBtn:SetPoint("LEFT", GameTooltipTextLeft1, "RIGHT", 4, 0) else self._hoverBtn:SetPoint("TOPRIGHT", GameTooltip, "TOPRIGHT", -6, -6) end; self._hoverBtn:Show() else if self._hoverBtn then self._hoverBtn:Hide() end; self._hoverBtnItemLink = nil; GameTooltip:Show() end
end

function Map:HideDiscoveryTooltip()
  if GameTooltip and GameTooltip:IsShown() then GameTooltip:Hide() end; if ItemRefTooltip then ItemRefTooltip:Hide() end; if self._hoverBtn then self._hoverBtn:Hide(); self._hoverBtnItemLink = nil end
end

function Map:OpenPinMenu(anchorFrame)
    if not anchorFrame or not anchorFrame.discovery then return end; local d = anchorFrame.discovery; local name, _, quality = GetCachedItemInfo(d.itemLink or d.itemID or ""); name = name or "Discovery"; wipe(menuList); table.insert(menuList, { text = tostring(name), isTitle = true, notCheckable = true }); table.insert(menuList, { text = "Navigate here", notCheckable = true, func = function() NavigateHere(d) end }); table.insert(menuList, { text = "Set as looted", notCheckable = true, func = function() if not (L.db and L.db.char) then return end; L.db.char.looted = L.db.char.looted or {}; L.db.char.looted[d.guid] = time(); Map:Update() end }); table.insert(menuList, { text = "Set as unlooted", notCheckable = true, func = function() if not (L.db and L.db.char and L.db.char.looted) then return end; L.db.char.looted[d.guid] = nil; Map:Update() end }); table.insert(menuList, { text = "", notCheckable = true, disabled = true }); table.insert(menuList, { text = "|cffff7f00Remove Discovery|r", notCheckable = true, func = function() StaticPopup_Show("LOOTCOLLECTOR_REMOVE_DISCOVERY", nil, nil, d.guid) end, }); table.insert(menuList, { text = "Close", notCheckable = true }); if EasyMenu then EasyMenu(menuList, DropFrame, "cursor", 0, 0, "MENU", 2) else ToggleDropDownMenu(1, nil, DropFrame, anchorFrame, 0, 0); UIDropDownMenu_Initialize(DropFrame, function(self, level) for _, item in ipairs(menuList) do UIDropDownMenu_AddButton(item, level) end end, "MENU") end
end

local function BuildFilterEasyMenu()
  local f=getFilters();local menu={};table.insert(menu,{text="LootCollector Filters",isTitle=true,notCheckable=true});table.insert(menu,{text=L:IsPaused()and"|cffff7f00Resume Processing|r"or"|cff00ff00Pause Processing|r",checked=L:IsPaused(),keepShownOnClick=true,func=function()L:TogglePause();Map:Update();if EasyMenu and FilterButton then EasyMenu(BuildFilterEasyMenu(),FilterMenuHost,FilterButton,0,0,"MENU",2)end end});table.insert(menu,{text="",notCheckable=true,disabled=true});local function addToggle(label,key)table.insert(menu,{text=label,checked=f[key]and true or false,keepShownOnClick=true,func=function()f[key]=not f[key];Map:UpdateFilterSettings();Map:Update()end})end;addToggle("Hide All Discoveries","hideAll");addToggle("Hide Looted","hideLooted");addToggle("Hide Unconfirmed","hideUnconfirmed");addToggle("Hide Uncached","hideUncached");addToggle("Hide Faded","hideFaded");addToggle("Hide Stale","hideStale");addToggle("Show on Minimap","showMinimap");
  local showSub={{text="Show Item Types",isTitle=true,notCheckable=true}}; table.insert(showSub,{text="Mystic Scrolls",checked=f.showMysticScrolls,keepShownOnClick=true,func=function()f.showMysticScrolls=not f.showMysticScrolls;Map:UpdateFilterSettings();Map:Update()end}); table.insert(showSub,{text="Worldforged Items",checked=f.showWorldforged,keepShownOnClick=true,func=function()f.showWorldforged=not f.showWorldforged;Map:UpdateFilterSettings();Map:Update()end}); table.insert(menu,{text="Show",hasArrow=true,notCheckable=true,menuList=showSub});
  local qualities={"Poor","Common","Uncommon","Rare","Epic","Legendary","Artifact","Heirloom"};local raritySub={{text="Minimum Quality",isTitle=true,notCheckable=true}};for q=0,7 do local r,g,b=GetQualityColor(q);table.insert(raritySub,{text=qualities[q+1]or("Quality "..q),colorCode=string.format("|cff%02x%02x%02x",r*255,g*255,b*255),checked=(f.minRarity==q),keepShownOnClick=true,func=function()f.minRarity=q;Map:UpdateFilterSettings();Map:Update();if EasyMenu and FilterButton then EasyMenu(BuildFilterEasyMenu(),FilterMenuHost,FilterButton,0,0,"MENU",2)end end})end;table.insert(menu,{text="Minimum Quality",hasArrow=true,notCheckable=true,menuList=raritySub});local slotsSub={{text="Slots",isTitle=true,notCheckable=true},{text="Clear All",notCheckable=true,func=function()for k in pairs(f.allowedEquipLoc)do f.allowedEquipLoc[k]=nil end;Map:UpdateFilterSettings();Map:Update()end}};for _,opt in ipairs(SLOT_OPTIONS)do table.insert(slotsSub,{text=opt.text,checked=f.allowedEquipLoc[opt.loc]and true or false,keepShownOnClick=true,func=function()if f.allowedEquipLoc[opt.loc]then f.allowedEquipLoc[opt.loc]=nil else f.allowedEquipLoc[opt.loc]=true end;Map:UpdateFilterSettings();Map:Update()end})end;table.insert(menu,{text="Slots",hasArrow=true,notCheckable=true,menuList=slotsSub});local classesSub={{text="Classes",isTitle=true,notCheckable=true},{text="Clear All",notCheckable=true,func=function()for k in pairs(f.allowedClasses)do f.allowedClasses[k]=nil end;Map:UpdateFilterSettings();Map:Update()end}};for _,classTok in ipairs(CLASS_OPTIONS)do local locName=(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classTok])or classTok;table.insert(classesSub,{text=locName,checked=f.allowedClasses[classTok]and true or false,keepShownOnClick=true,func=function()if f.allowedClasses[classTok]then f.allowedClasses[classTok]=nil else f.allowedClasses[classTok]=true end;Map:UpdateFilterSettings();Map:Update()end})end;table.insert(menu,{text="Classes",hasArrow=true,notCheckable=true,menuList=classesSub});return menu
end

local function PlaceFilterButton(btn)
    btn:ClearAllPoints(); local potentialAnchors = { "_NPCScanOverlayWorldMapToggle", "WorldMapQuestShowObjectives", "WorldMapTrackQuest", "WorldMapFrameCloseButton" }; for _, anchorName in ipairs(potentialAnchors) do local anchorFrame = _G[anchorName]; if anchorFrame and anchorFrame:IsShown() then btn:SetPoint("RIGHT", anchorFrame, "LEFT", -8, 0); return end end; btn:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -80, -30)
end

function Map:EnsureFilterUI()
  if not WorldMapFrame then return end; if not FilterButton then FilterButton = CreateFrame("Button", "LootCollectorFilterButton", WorldMapFrame, "UIPanelButtonTemplate"); FilterButton:SetSize(24, 20); FilterButton:SetText("LC"); FilterButton:SetFrameStrata("HIGH"); FilterButton:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 10); FilterButton:SetToplevel(true); FilterButton:EnableMouse(true); FilterButton:RegisterForClicks("LeftButtonUp"); PlaceFilterButton(FilterButton); FilterButton:SetScript("OnClick", function(self) if EasyMenu then EasyMenu(BuildFilterEasyMenu(), FilterMenuHost, self, 0, 0, "MENU", 2) else ToggleDropDownMenu(1, nil, FilterMenuHost, self, 0, 0) end end); FilterButton:SetScript("OnShow", function(self) PlaceFilterButton(self) end) else PlaceFilterButton(FilterButton) end
end

function Map:BuildPin()
  local pinSize=(L.db and L.db.profile.mapFilters.pinSize)or 16;local frame=CreateFrame("Button",nil,WorldMapButton);frame:SetSize(pinSize,pinSize);frame:SetFrameStrata(WorldMapButton:GetFrameStrata());frame:SetFrameLevel(WorldMapButton:GetFrameLevel()+10);frame:SetNormalTexture(nil);frame:SetHighlightTexture(nil);frame:SetPushedTexture(nil);frame:SetDisabledTexture(nil);frame.border=frame:CreateTexture(nil,"BACKGROUND");frame.border:SetHeight(pinSize);frame.border:SetWidth(pinSize);frame.border:SetPoint("CENTER",0,0);frame.border:SetTexture("Interface\\Buttons\\UI-Quickslot2");frame.border:SetTexCoord(0.2,0.8,0.2,0.8);frame.border:SetVertexColor(0,0,0,0.25);frame.unlootedOutline=frame:CreateTexture(nil,"BORDER");frame.unlootedOutline:SetTexture("Interface\\Buttons\\WHITE8X8");frame.unlootedOutline:SetHeight(pinSize);frame.unlootedOutline:SetWidth(pinSize);frame.unlootedOutline:SetPoint("CENTER",0,0);frame.unlootedOutline:Hide();local iconSize=pinSize-2;frame.texture=frame:CreateTexture(nil,"ARTWORK");frame.texture:SetHeight(iconSize);frame.texture:SetWidth(iconSize);frame.texture:SetPoint("CENTER",0,0);frame.texture:SetTexture(PIN_FALLBACK_TEXTURE);frame:RegisterForClicks("LeftButtonUp","RightButtonUp");frame:SetScript("OnEnter",function(self)if Map._pinnedPin and Map._pinnedPin~=self then return end;if not self.discovery then return end;Map:ShowDiscoveryTooltip(self)end);frame:SetScript("OnLeave",function(self)if Map._pinnedPin==self then return end;Map:HideDiscoveryTooltip()end);frame:SetScript("OnClick",function(self,button)if button=="RightButton"then Map:OpenPinMenu(self);return end;if Map._pinnedPin==self then Map._pinnedPin=nil;Map:HideDiscoveryTooltip()else Map._pinnedPin=self;Map:ShowDiscoveryTooltip(self)end end);table.insert(self.pins,frame);return frame
end

local function GetCurrentMinimapShape()
  if _G.GetMinimapShape then
    local shape = _G.GetMinimapShape()
    return ValidMinimapShapes[shape] or ValidMinimapShapes["SQUARE"]
  end
  return ValidMinimapShapes["SQUARE"]
end

local function EnsureMmPin(i)
  if Map._mmPins[i] then return Map._mmPins[i] end; local f = CreateFrame("Frame", nil, Minimap); f:SetSize(Map._mmSize, Map._mmSize); f.tex = f:CreateTexture(nil, "ARTWORK"); f.tex:SetAllPoints(f); f:Hide(); Map._mmPins[i] = f; return f
end
function Map:HideAllMmPins()
  for _, pin in ipairs(self._mmPins) do pin:Hide(); pin.discovery = nil end
end

function Map:UpdateMinimap()
  local f = getFilters(); if not f.showMinimap or not Minimap or (L.IsZoneIgnored and L:IsZoneIgnored()) then self:HideAllMmPins(); return end;  local mapID = GetCurrentMapZone();  local px, py = GetPlayerMapPosition("player"); if not px or not py or (px == 0 and py == 0) then self:HideAllMmPins(); return end;  local count = 0; local centerX, centerY = Minimap:GetWidth() * 0.5, Minimap:GetHeight() * 0.5;  local radius = math.min(centerX, centerY) - 6;  local minimapShape = GetCurrentMinimapShape();  local zoom = Minimap:GetZoom()  local minimapScale = GetMinimapScale(zoom)  local maxDist = f.maxMinimapDistance or 0;  for _, d in pairs(L.db.global.discoveries or {}) do  repeat  if not d or not d.coords or not d.zoneID or d.zoneID ~= mapID or not passesFilters(d) then break end;  local x, y = (d.coords.x or 0), (d.coords.y or 0);  local dx, dy = (x - px), (y - py);  if maxDist > 0 then  local mapDist = math.sqrt(dx * dx + dy * dy); if mapDist > maxDist then break end  end;  local mmX = (x - px) / minimapScale * centerX;  local mmY = (py - y) / minimapScale * centerY;  local isRound = true; if minimapShape and not (mmX == 0 or mmY == 0) then  local cornerIndex = (mmX < 0) and 1 or 3; if mmY >= 0 then cornerIndex = cornerIndex + 1 end; isRound =  minimapShape[cornerIndex]  end; local dist; if isRound then  dist = math.sqrt(mmX * mmX + mmY * mmY)  else  dist = math.max(math.abs(mmX),  math.abs(mmY))  end; if dist > radius then  local scale = radius / dist; mmX = mmX * scale; mmY = mmY * scale  end; count = count + 1;  local pin = EnsureMmPin(count); pin.discovery = d; pin:ClearAllPoints(); pin:SetPoint(  "CENTER", Minimap, "CENTER", mmX, mmY);  local icon = self:GetDiscoveryIcon(d); pin.tex:SetTexture(icon or  PIN_FALLBACK_TEXTURE); pin:Show()  pin:SetSize(Map._mmSize, Map._mmSize)  until true  end; for i = count + 1, #self._mmPins do  self._mmPins[i]:Hide(); self._mmPins[i].discovery = nil  end
end

function Map:EnsureMinimapTicker()
  if self._mmTicker then return end; self._mmTicker = CreateFrame("Frame"); self._mmTicker:SetScript("OnUpdate", function(_, elapsed) Map._mmElapsed = Map._mmElapsed + elapsed; if Map._mmElapsed >= Map._mmInterval then Map._mmElapsed = 0; Map:UpdateMinimap() end end)
end

function Map:OnInitialize()
  if not (L.db and L.db.profile and L.db.global and L.db.char) then return end; 
  self:UpdateFilterSettings();
  self:EnsureFilterUI(); self:EnsureMinimapTicker(); if WorldMapDetailFrame then WorldMapDetailFrame:EnableMouse(true); WorldMapDetailFrame:SetScript("OnMouseDown", function() if Map._pinnedPin then Map._pinnedPin = nil; Map:HideDiscoveryTooltip() end end) end; if WorldMapFrame and hooksecurefunc then hooksecurefunc(WorldMapFrame, "Hide", function() if Map._pinnedPin then Map._pinnedPin = nil; Map:HideDiscoveryTooltip() end end) end
  if Minimap and hooksecurefunc then hooksecurefunc(Minimap, "SetZoom", function() Map:UpdateMinimap() end) end
end

function Map:UpdateFilterSettings()
  local p = L.db and L.db.profile; 
  local f = (p and p.mapFilters) or {}; 
  if f.hideAll == nil then f.hideAll = false end;
  if f.hideFaded == nil then f.hideFaded = false end;
  if f.hideStale == nil then f.hideStale = false end;
  if f.hideLooted == nil then f.hideLooted = false end;
  if f.hideUnconfirmed == nil then f.hideUnconfirmed = false end;
  if f.hideUncached == nil then f.hideUncached = false end;
  if f.minRarity == nil then f.minRarity = 0 end;
  if f.allowedEquipLoc == nil then f.allowedEquipLoc = {} end;
  if f.allowedClasses == nil then f.allowedClasses = {} end;
  if f.showMinimap == nil then f.showMinimap = true end;
  if f.showMysticScrolls == nil then f.showMysticScrolls = true end;
  if f.showWorldforged == nil then f.showWorldforged = true end;
  if f.maxMinimapDistance == nil then f.maxMinimapDistance = 0 end;
  Map._filters = f;
end

function Map:Update()
  if not WorldMapFrame or not WorldMapFrame:IsShown() then return end;
  local filters = getFilters();
  if filters.hideAll then
    for i = 1, #self.pins do self.pins[i]:Hide(); self.pins[i].discovery = nil end;
    self._pinnedPin = nil;
    self:HideDiscoveryTooltip();
    return
  end;

  if L:IsZoneIgnored() or not (L.db and L.db.global and L.db.global.discoveries) then
    for i = 1, #self.pins do self.pins[i]:Hide(); self.pins[i].discovery = nil end;
    self._pinnedPin = nil;
    self:HideDiscoveryTooltip();
    return
  end;

  self:EnsureFilterUI();
  local mapID = GetCurrentMapZone();
  local currentContinentID = GetCurrentMapContinent();
  if not WorldMapDetailFrame or not WorldMapButton then return end; local mapWidth, mapHeight = WorldMapDetailFrame:GetWidth(), WorldMapDetailFrame:GetHeight(); local mapLeft, mapTop = WorldMapDetailFrame:GetLeft(), WorldMapDetailFrame:GetTop(); local parentLeft, parentTop = WorldMapButton:GetLeft(), WorldMapButton:GetTop(); if not mapWidth or not mapHeight or not mapLeft or not mapTop or not parentLeft or not parentTop then return end; if mapWidth == 0 or mapHeight == 0 then return end; local offsetX = mapLeft - parentLeft; local offsetY = mapTop - parentTop; 
  local pinIndex = 1; local stillPinned = false; 
  for _, discovery in pairs(L.db.global.discoveries) do 
    repeat 
      local discoveryContinentID = discovery.continentID or 0
      local discoveryZoneID = discovery.zoneID or 0

      -- Attempt to get correct map info for old data (continentID 0) using local GetMapZoneNumbers
      if discoveryContinentID == 0 and GetMapZoneNumbers and discovery.zone then
          local tempContID, tempZoneID = GetMapZoneNumbers(discovery.zone)
          if tempContID and tempZoneID then
              discoveryContinentID = tempContID
              discoveryZoneID = tempZoneID
          end
      end

      if not discovery or not discovery.coords or discoveryZoneID == 0 or 
          (discoveryContinentID ~= 0 and discoveryContinentID ~= currentContinentID) or 
          (discoveryZoneID ~= mapID and not (discoveryContinentID == 0 and discoveryZoneID == 0)) or 
          (discoveryZoneID == 0 or discoveryZoneID == 41) then break end;
      if not passesFilters(discovery) then break end; 
      local pin = self.pins[pinIndex] or self:BuildPin(); pinIndex = pinIndex + 1; pin.discovery = discovery; local pinSize=(L.db.profile.mapFilters.pinSize)or 16;pin:SetSize(pinSize,pinSize);local isLooted=isLootedByChar(discovery.guid);local icon=self:GetDiscoveryIcon(discovery);local isFallbackTexture=(icon==PIN_FALLBACK_TEXTURE or not icon);pin.texture:SetTexture(icon);if isFallbackTexture then if pin.border then pin.border:Hide()end;if pin.unlootedOutline then pin.unlootedOutline:Hide()end;pin.texture:SetVertexColor(1,1,1)else if pin.border then pin.border:Show()end;if isLooted then if pin.unlootedOutline then pin.unlootedOutline:Hide()end;pin.texture:SetVertexColor(0.7,0.7,0.7)else if pin.unlootedOutline then pin.unlootedOutline:Show()end;pin.texture:SetVertexColor(1,1,1);local _,_,quality=GetCachedItemInfo(discovery.itemLink or discovery.itemID);local r,g,b=GetQualityColor(quality);pin.unlootedOutline:SetVertexColor(r,g,b)end end;pin:SetAlpha(AlphaForStatus(GetStatus(discovery)));local pinX_relative=(discovery.coords.x or 0)*mapWidth;local pinY_relative=(discovery.coords.y or 0)*mapHeight;local finalX=offsetX+pinX_relative;local finalY=offsetY-pinY_relative;pin:ClearAllPoints();pin:SetPoint("CENTER",WorldMapButton,"TOPLEFT",finalX,finalY);pin:Show();if self._pinnedPin==pin then stillPinned=true;self:ShowDiscoveryTooltip(pin)end 
    until true 
  end; 
  for i = pinIndex, #self.pins do self.pins[i]:Hide(); self.pins[i].discovery = nil end; if self._pinnedPin and not stillPinned then self._pinnedPin = nil; self:HideDiscoveryTooltip() end
end

return Map