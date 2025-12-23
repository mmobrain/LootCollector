

local L = LootCollector
local Core = L:GetModule("Core", true)
local Map = L:NewModule("Map", "AceEvent-3.0")

local PIN_FALLBACK_TEXTURE = "Interface\\AddOns\\LootCollector\\media\\pin"
local MAP_UPDATE_THROTTLE = 0.4

local mapOverlay 

Map._lastPlayerState = { c = nil, mapID = nil, px = nil, py = nil, facing = nil }
Map.cachedVisibleDiscoveries = {}
Map.cacheIsDirty = true
Map.cachingEnabled = true
Map._lastLocationFetchTime = 0
Map._cachedLocation = { c = nil, mapID = nil, px = nil, py = nil }
Map._minimapPinsDirty = false 

Map.pins = Map.pins or {}

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

Map._bmItemLines = Map._bmItemLines or {}
local BM_LINE_HEIGHT = 20
local BM_ICON_SIZE_IN_LINE = 18

Map.clusterPins = Map.clusterPins or {}
local CLUSTER_PIN_SIZE = 32
local CLUSTER_PIN_BACKGROUND_TEXTURE = "Interface\\AddOns\\LootCollector\\media\\pin"

Map.worldMapUpdatePending = false
Map.worldMapUpdateTimer = 0
Map.throttleFrame = nil

local function CreateOrShowPersistentOverlayPin(px, py, discovery)
    local parent = WorldMapDetailFrame or WorldMapFrame
    if not parent then return end

    local pin = WorldMapFrame.viewerOverlayPin
    if not pin then
        pin = CreateFrame("Frame", "LootCollectorViewerOverlayPin", parent)
        pin:SetSize(32, 32)
        -- Xurkon: Changed from TOOLTIP to HIGH strata to fix tooltips displaying behind pins
        pin:SetFrameStrata("HIGH")

        pin.glowTexture = pin:CreateTexture(nil, "OVERLAY")
        pin.glowTexture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        pin.glowTexture:SetBlendMode("ADD")
        pin.glowTexture:SetVertexColor(1, 0.8, 0.3, 1)
        pin.glowTexture:SetSize(46, 46)
        pin.glowTexture:SetPoint("CENTER")

        pin.itemIcon = pin:CreateTexture(nil, "ARTWORK")
        pin.itemIcon:SetSize(28, 28)
        pin.itemIcon:SetPoint("CENTER")

        pin.glowTime = 0
        
        
        pin:SetScript("OnUpdate", function(self, delta)
            self.glowTime = self.glowTime + delta
            if self.glowTime > 1.0 then
                self.glowTime = 0
            end

            local progress = self.glowTime / 1.0
            local alpha = 0.5 + 0.5 * math.sin(progress * math.pi)
            local scale = 0.9 + 0.3 * math.sin(progress * math.pi)

            self.glowTexture:SetAlpha(alpha)
            self:SetScale(scale)
        end)
        
        pin:EnableMouse(false)
        WorldMapFrame.viewerOverlayPin = pin
    end

    pin:SetParent(parent)
    pin:SetFrameLevel(parent:GetFrameLevel() + 50)
    
    local iconTexture = Map:GetDiscoveryIcon(discovery)
    pin.itemIcon:SetTexture(iconTexture or PIN_FALLBACK_TEXTURE)
    
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", parent, "TOPLEFT", px, -py)
    pin:Show()
    pin.discovery = discovery
end

local function EnsureMapOverlay()
	local parent = WorldMapDetailFrame or WorldMapFrame
	if mapOverlay and mapOverlay:GetParent() == parent then
		return mapOverlay
	end
	
	mapOverlay = CreateFrame("Frame", "LootCollectorMapOverlay", parent)
	mapOverlay.baseSize = 34
	mapOverlay:SetSize(mapOverlay.baseSize, mapOverlay.baseSize)
	-- Xurkon: Changed from TOOLTIP to HIGH strata to fix tooltips displaying behind overlay
	mapOverlay:SetFrameStrata("HIGH")
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

    
    if ShowUIPanel and WorldMapFrame then ShowUIPanel(WorldMapFrame)
    elseif WorldMapFrame and WorldMapFrame.Show then WorldMapFrame:Show() end

    if d.z and d.z > 0 and SetMapByID then
        SetMapByID(d.z - 1)
    elseif SetMapToCurrentZone then
        SetMapToCurrentZone()
    end

    
    if WorldMapFrame.viewerOverlayPin then
        WorldMapFrame.viewerOverlayPin:Hide()
    end

    
    
    
    
    local attempts = 0
    local function TryFocus()
        if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
        
        local targetPin = nil
        
        for _, pin in ipairs(Map.pins) do
            if pin:IsShown() and pin.discovery and pin.discovery.g == d.g then
                targetPin = pin
                break
            end
        end

        if targetPin then
            
            
            local parent = WorldMapDetailFrame or WorldMapFrame
            local overlayPin = WorldMapFrame.viewerOverlayPin

            if not overlayPin then
                overlayPin = CreateFrame("Frame", "LootCollectorViewerOverlayPin", targetPin) 
                overlayPin:SetSize(32, 32)
                -- Xurkon: Changed from TOOLTIP to HIGH strata to fix tooltips displaying behind overlay pins
                overlayPin:SetFrameStrata("HIGH")
                
                overlayPin.glowTexture = overlayPin:CreateTexture(nil, "OVERLAY")
                overlayPin.glowTexture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                overlayPin.glowTexture:SetBlendMode("ADD")
                overlayPin.glowTexture:SetVertexColor(1, 0.8, 0.3, 1)
                overlayPin.glowTexture:SetSize(46, 46)
                overlayPin.glowTexture:SetPoint("CENTER")

                overlayPin.itemIcon = overlayPin:CreateTexture(nil, "ARTWORK")
                overlayPin.itemIcon:SetSize(28, 28)
                overlayPin.itemIcon:SetPoint("CENTER")
                
                overlayPin.glowTime = 0
                overlayPin:SetScript("OnUpdate", function(self, delta)
                    self.glowTime = self.glowTime + delta
                    if self.glowTime > 1.0 then self.glowTime = 0 end
                    local progress = self.glowTime / 1.0
                    local alpha = 0.5 + 0.5 * math.sin(progress * math.pi)
                    local scale = 0.9 + 0.3 * math.sin(progress * math.pi)
                    self.glowTexture:SetAlpha(alpha)
                    self:SetScale(scale)
                end)
                
                overlayPin:EnableMouse(false)
                WorldMapFrame.viewerOverlayPin = overlayPin
            end
            
            
            overlayPin:SetParent(targetPin)
            overlayPin:SetFrameLevel(targetPin:GetFrameLevel() + 10)
            overlayPin:ClearAllPoints()
            overlayPin:SetPoint("CENTER", targetPin, "CENTER", 0, 0)
            
            
            local iconTexture = Map:GetDiscoveryIcon(d)
            overlayPin.itemIcon:SetTexture(iconTexture or PIN_FALLBACK_TEXTURE)
            overlayPin:Show()
            
            
            local px, py = targetPin:GetCenter()
            local parentX, parentY = (WorldMapDetailFrame or WorldMapFrame):GetLeft(), (WorldMapDetailFrame or WorldMapFrame):GetTop()
            if px and py and parentX and parentY then
                PulseOverlayAt(px - parentX, -(py - parentY))
            end
        else
            
            attempts = attempts + 1
            if attempts < 5 then
                C_Timer.After(0.2, TryFocus) 
            else
                L._debug("Map-Focus", "Could not find target map pin for GUID: " .. tostring(d.g) .. " after retries.")
            end
        end
    end

    
    C_Timer.After(0.2, TryFocus)
end

  

function Map:HighlightPin(pin)
    if not pin then return end

    
    local overlayPin = WorldMapFrame.viewerOverlayPin
    if not overlayPin then
        local parent = WorldMapDetailFrame or WorldMapFrame
        overlayPin = CreateFrame("Frame", "LootCollectorViewerOverlayPin", parent)
        overlayPin:SetSize(32, 32)
        -- Xurkon: Changed from TOOLTIP to HIGH strata to fix tooltips displaying behind overlay pins
        overlayPin:SetFrameStrata("HIGH")
        
        overlayPin.glowTexture = overlayPin:CreateTexture(nil, "OVERLAY")
        overlayPin.glowTexture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        overlayPin.glowTexture:SetBlendMode("ADD")
        overlayPin.glowTexture:SetVertexColor(1, 0.8, 0.3, 1)
        overlayPin.glowTexture:SetSize(46, 46)
        overlayPin.glowTexture:SetPoint("CENTER")

        overlayPin.itemIcon = overlayPin:CreateTexture(nil, "ARTWORK")
        overlayPin.itemIcon:SetSize(28, 28)
        overlayPin.itemIcon:SetPoint("CENTER")
        
        overlayPin.glowTime = 0
        overlayPin:SetScript("OnUpdate", function(self, delta)
            self.glowTime = self.glowTime + delta
            if self.glowTime > 1.0 then self.glowTime = 0 end
            local progress = self.glowTime / 1.0
            local alpha = 0.5 + 0.5 * math.sin(progress * math.pi)
            local scale = 0.9 + 0.3 * math.sin(progress * math.pi)
            self.glowTexture:SetAlpha(alpha)
            self:SetScale(scale)
        end)
        
        overlayPin:EnableMouse(false)
        WorldMapFrame.viewerOverlayPin = overlayPin
    end
    
    
    overlayPin:SetParent(pin)
    overlayPin:SetFrameLevel(pin:GetFrameLevel() + 10)
    overlayPin:ClearAllPoints()
    overlayPin:SetPoint("CENTER", pin, "CENTER", 0, 0)
    
    
    local iconTexture = self:GetDiscoveryIcon(pin.discovery)
    overlayPin.itemIcon:SetTexture(iconTexture or "Interface\\AddOns\\LootCollector\\media\\pin")
    
    overlayPin:Show()
end

function Map:ClearPinHighlight()
    if WorldMapFrame.viewerOverlayPin then
        WorldMapFrame.viewerOverlayPin:Hide()
    end
end

function Map:EnsureThrottleFrame()
    if self.throttleFrame then return end
    self.throttleFrame = CreateFrame("Frame")
    self.throttleFrame:SetScript("OnUpdate", function(frame, elapsed)
        if Map.worldMapUpdatePending then
            Map.worldMapUpdateTimer = Map.worldMapUpdateTimer + elapsed
            if Map.worldMapUpdateTimer >= MAP_UPDATE_THROTTLE then
                Map:DrawWorldMapPins()
                Map.worldMapUpdatePending = false
                Map.worldMapUpdateTimer = 0
            end
        end
    end)
end

function Map:OnInitialize()
    if L.LEGACY_MODE_ACTIVE then return end
    if not (L.db and L.db.profile and L.db.global and L.db.char) then return end
    
    self:EnsureThrottleFrame()
    
    
    self.cacheIsDirty = true
    self.mapSystemReady = false

    
    local function CheckMapReadiness()
        local px, py = GetPlayerMapPosition("player")
        local mapID = GetCurrentMapAreaID()
        
        if (px and py and (px > 0 or py > 0)) and (mapID and mapID > 0) then
            if not Map.mapSystemReady then
                L._debug("Map-Init", "Map system is now READY. Valid coords detected.")
                Map.mapSystemReady = true
                Map.cacheIsDirty = true
                L.DataHasChanged = true 
                if Map.UpdateMinimap then Map:UpdateMinimap() end
            end
            return true
        end
        return false
    end

    self:RegisterEvent("WORLD_MAP_UPDATE", function()
        if Map.isOpeningMenu then
            Map.isOpeningMenu = false
            return
        end
        
        if not self.mapSystemReady then
            CheckMapReadiness()
        end

        if WorldMapFrame and WorldMapFrame:IsShown() then
            Map.cacheIsDirty = true 
            L.DataHasChanged = true 
        end
        if WorldMapFrame and WorldMapFrame.viewerOverlayPin then
            WorldMapFrame.viewerOverlayPin:Hide()
        end
    end)

    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        self.mapSystemReady = false
        
        local attempts = 0
        local ticker
        ticker = C_Timer.NewTicker(0.5, function()
            attempts = attempts + 1
            if CheckMapReadiness() then
                ticker:Cancel()
            elseif attempts > 20 then
                ticker:Cancel()
                L._debug("Map-Init", "Map readiness check timed out. Forcing ready.")
                Map.mapSystemReady = true
                if Map.UpdateMinimap then Map:UpdateMinimap() end
            end
        end)
    end)
    
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
        self.mapSystemReady = false
        CheckMapReadiness()
    end)
        
    self:EnsureFilterUI()
    self:EnsureMinimapTicker()

    self:RegisterEvent("FRIENDLIST_UPDATE", "UpdateFriendCache")
    self:RegisterEvent("GUILD_ROSTER_UPDATE", "UpdateGuildCache")
    
    C_Timer.After(3, function()
        if ShowFriends then ShowFriends() end
        if GuildRoster then GuildRoster() end
        CheckMapReadiness()
    end)

    GameTooltip:HookScript("OnHide", function()
    end)
    
    
    
    local MAP_DEBOUNCE_INTERVAL = 0.5
    local timeSinceLastUpdate = 0
    
    local updateTicker = CreateFrame("Frame")
    updateTicker:SetScript("OnUpdate", function(self, elapsed)
        timeSinceLastUpdate = timeSinceLastUpdate + elapsed
        
        if L.DataHasChanged then
            
            if timeSinceLastUpdate > MAP_DEBOUNCE_INTERVAL then
                Map:DrawWorldMapPins()
                L.DataHasChanged = false
                timeSinceLastUpdate = 0
            end
        end
    end)
    
    if WorldMapDetailFrame then
        WorldMapDetailFrame:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
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
                if not isOverMenu then CloseDropDownMenus() end
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
                Map._searchResultsFrame:SetParent(UIParent)
                Map._searchResultsFrame:ClearAllPoints()
                Map._searchResultsFrame:SetPoint("CENTER")
            end
            Map.cacheIsDirty = true
            L.DataHasChanged = true 
        end)
        
        hooksecurefunc(WorldMapFrame, "Hide", function()
          Map:HideDiscoveryTooltip()
          if Map._searchFrame then Map._searchFrame:Hide() end
          if Map._searchBox then Map._searchBox:SetText("") end
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
          local ProximityList = L:GetModule("ProximityList", true)
          if ProximityList and ProximityList:IsShown() then
              ProximityList:Hide("Call from Map:OnInitialize")
          end
          if WorldMapFrame.viewerOverlayPin then
              WorldMapFrame.viewerOverlayPin:Hide()
          end
        end)
    end
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
        [5]   = { name="Durotar", width = 5288, height = 3524, xOffset = -7250, yOffset = -1808 }, 
        [10]  = { name="Mulgore", width = 5136, height = 3425, xOffset = -3089, yOffset = 272 }, 
        [12]  = { name="The Barrens", width = 10132, height = 6755, xOffset = -7510, yOffset = -1612 }, 
        [42]  = { name="Teldrassil", width = 5091, height = 3394, xOffset = -1277, yOffset = -11831 }, 
        [43]  = { name="Darkshore", width = 6549, height = 4367, xOffset = -3608, yOffset = -8333 }, 
        [44]  = { name="Ashenvale", width = 5766, height = 3843, xOffset = -4066, yOffset = -4672 }, 
        [62]  = { name="Thousand Needles", width = 4400, height = 2934, xOffset = -4833, yOffset = 3966 }, 
        [82]  = { name="Stonetalon Mountains", width = 4882, height = 3255, xOffset = -1637, yOffset = -2916 }, 
        [102] = { name="Desolace", width = 4234, height = 2997, xOffset = -262, yOffset = -452 }, 
        [122] = { name="Feralas", width = 6949, height = 4634, xOffset = -1508, yOffset = 2366 }, 
        [142] = { name="Dustwallow Marsh", width = 5251, height = 3500, xOffset = -6225, yOffset = 2033 }, 
        [162] = { name="Tanaris", width = 6900, height = 4600, xOffset = -7118, yOffset = 5875 }, 
        [182] = { name="Azshara", width = 5070, height = 3381, xOffset = -8347, yOffset = -5341 }, 
        [183] = { name="Felwood", width = 5749, height = 3833, xOffset = -4108, yOffset = -7133 }, 
        [202] = { name="Un'Goro Crater", width = 3700, height = 2467, xOffset = -3166, yOffset = 5966 }, 
        [242] = { name="Moonglade", width = 2308, height = 1539, xOffset = -3689, yOffset = -8491 }, 
        [262] = { name="Silithus", width = 3482, height = 2323, xOffset = -945, yOffset = 5958 }, 
        [282] = { name="Winterspring", width = 7100, height = 4733, xOffset = -7416, yOffset = -8533 }, 
        [465] = { name="Azuremyst Isle", width = 4070, height = 2715, xOffset = -14570, yOffset = 2793 }, 
        [477] = { name="Bloodmyst Isle", width = 3262, height = 2175, xOffset = -13337, yOffset = 758 }, 
        
        [1244] = { name="Valley of Trials", width=1173.94, height=782.65, xOffset=-4991.67, yOffset=3641.67 }, 
        [1243] = { name="Shadowglen", width=1260.91, height=840.57, xOffset=41.666, yOffset=-11033.3 }, 
        [1245] = { name="Camp Narache", width=1565.16, height=1043.57, xOffset=-1533.34, yOffset=2566.74 }, 
        [1242] = { name="Ammen Vale", width=650, height=500, xOffset=-14633.3, yOffset=3604.17 }, 
    },
    [2] = { 
        [16]  = { name="Alterac Mountains", width = 2799, height = 1866, xOffset = -2016, yOffset = -1500 }, 
        [17]  = { name="Arathi Highlands", width = 3600, height = 2400, xOffset = -4466, yOffset = 133 }, 
        [18]  = { name="Badlands", width = 2487, height = 1658, xOffset = -4566, yOffset = 5889 }, 
        [20]  = { name="Blasted Lands", width = 3350, height = 2234, xOffset = -4591, yOffset = 10566 }, 
        [21]  = { name="Tirisfal Glades", width = 4518, height = 3013, xOffset = -1485, yOffset = -3837 }, 
        [22]  = { name="Silverpine Forest", width = 4200, height = 2800, xOffset = -750, yOffset = -1666 }, 
        [23]  = { name="Western Plaguelands", width = 4300, height = 2866, xOffset = -3883, yOffset = -3366 }, 
        [24]  = { name="Eastern Plaguelands", width = 4031, height = 2688, xOffset = -6318, yOffset = -3704 }, 
        [25]  = { name="Hillsbrad Foothills", width = 3200, height = 2133, xOffset = -2133, yOffset = -400 }, 
        [27]  = { name="The Hinterlands", width = 3850, height = 2566, xOffset = -5425, yOffset = -1466 }, 
        [28]  = { name="Dun Morogh", width = 4924, height = 3283, xOffset = -3122, yOffset = 3877 }, 
        [29]  = { name="Searing Gorge", width = 2232, height = 1487, xOffset = -2554, yOffset = 6100 }, 
        [30]  = { name="Burning Steppes", width = 2929, height = 1952, xOffset = -3195, yOffset = 7031 }, 
        [31]  = { name="Elwynn Forest", width = 3470, height = 2315, xOffset = -1935, yOffset = 7939 }, 
        [33]  = { name="Deadwind Pass", width = 2500, height = 1667, xOffset = -3333, yOffset = 9866 }, 
        [35]  = { name="Duskwood", width = 2700, height = 1800, xOffset = -1866, yOffset = 9716 }, 
        [36]  = { name="Loch Modan", width = 2759, height = 1840, xOffset = -4752, yOffset = 4487 }, 
        [37]  = { name="Redridge Mountains", width = 2171, height = 1447, xOffset = -3741, yOffset = 8575 }, 
        [38]  = { name="Stranglethorn Vale", width = 6380, height = 4254, xOffset = -4160, yOffset = 11168 }, 
        [39]  = { name="Swamp of Sorrows", width = 2294, height = 1530, xOffset = -4516, yOffset = 9620 }, 
        [40]  = { name="Westfall", width = 3500, height = 2333, xOffset = -483, yOffset = 9400 }, 
        [41]  = { name="Wetlands", width = 4136, height = 2757, xOffset = -4525, yOffset = 2147 }, 
        [463] = { name="Eversong Woods", width = 4925, height = 3283, xOffset = -9412, yOffset = -11041 }, 
        [464] = { name="Ghostlands", width = 3300, height = 2200, xOffset = -8583, yOffset = -8266 }, 
        
        [1238] = { name="Northshire Valley", width=507.28, height=507.49, xOffset=-781.25, yOffset=8570.83 }, 
        [1239] = { name="Coldridge Valley", width=663.35, height=661.63, xOffset=-66.8, yOffset=5724.66 }, 
        [1241] = { name="Sunstrider Isle", width=510, height=500, xOffset=-6983.33, yOffset=9766.67 }, 
        [1240] = { name="Deathknell", width=570.56, height=571.33, xOffset=1058.33, yOffset=-2270.83 }, 
    },
    [3] = { 
        [466] = { name="Hellfire Peninsula", width=5164, height=3443, xOffset=375, yOffset=-1481 }, 
        [468] = { name="Zangarmarsh", width=5028, height=3351, xOffset=4447, yOffset=-1935 }, 
        [474] = { name="Shadowmoon Valley", width=5500, height=3667, xOffset=-1275, yOffset=1947 }, 
        [476] = { name="Blade's Edge Mountains", width=5425, height=3617, xOffset=3420, yOffset=-4408 }, 
        [478] = { name="Nagrand", width=5525, height=3682, xOffset=4770, yOffset=-41 }, 
        [479] = { name="Terokkar Forest", width=5400, height=3601, xOffset=1683, yOffset=999 }, 
        [480] = { name="Netherstorm", width=5574, height=3717, xOffset=-91, yOffset=-5456 }, 
    },
    [4] = { 
        [487] = { name="Borean Tundra", width=5764, height=3843, xOffset=2806, yOffset=-4897 }, 
        [489] = { name="Dragonblight", width=5608, height=3740, xOffset=-1981, yOffset=-5575 }, 
        [491] = { name="Grizzly Hills", width=5250, height=3500, xOffset=-6360, yOffset=-5516 }, 
        [492] = { name="Howling Fjord", width=6046, height=4030, xOffset=-7443, yOffset=914 }, 
        [493] = { name="Icecrown", width=6270, height=4182, xOffset=-827, yOffset=-9427 }, 
        [494] = { name="Sholazar Basin", width=4357, height=2904, xOffset=2572, yOffset=-7287 }, 
        [496] = { name="The Storm Peaks", width=7111, height=4741, xOffset=-5270, yOffset=-10197 }, 
        [497] = { name="Zul'Drak", width=4993, height=3329, xOffset=-5593, yOffset=-7668 }, 
        [502] = { name="Wintergrasp", width=2975, height=1983, xOffset=1354, yOffset=-5716 }, 
        [511] = { name="Crystalsong Forest", width=2722, height=1815, xOffset=-1279, yOffset=-6502 }, 
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

local function SaveMapState()
    
    if WorldMapFrame and WorldMapFrame:IsVisible() then
        return GetCurrentMapContinent(), GetCurrentMapZone(), GetCurrentMapDungeonLevel()
    end    
    return nil, nil, nil
end

local function RestoreMapState(c, z, dl)
    if c and z then SetMapZoom(c, z) end
    if dl then SetDungeonMapLevel(dl) end
end

function Map:GetPlayerLocation()
    local c, mapID, px, py

    if WorldMapFrame and WorldMapFrame:IsVisible() then
        c = GetCurrentMapContinent()
        mapID = GetCurrentMapAreaID()
        px, py = GetPlayerMapPosition("player")
    else
        local continent, zone, level = SaveMapState()
        SetMapToCurrentZone()
        c = GetCurrentMapContinent()
        mapID = GetCurrentMapAreaID()
        px, py = GetPlayerMapPosition("player")
        if continent then
            RestoreMapState(continent, zone, level)
        end
    end
    
    local cache = Map._cachedLocation
    cache.c, cache.mapID, cache.px, cache.py = c, mapID, px, py
    
    return c, mapID, px, py
end

local function ComputeDistance(c1, z1, x1, y1, c2, z2, x2, y2)
    c1, z1, c2, z2 = tonumber(c1), tonumber(z1), tonumber(c2), tonumber(z2) 
    if c1 ~= c2 then return end 
    local xDelta, yDelta
    if z1 == z2 then
        local zoneData = Map.WorldMapSize[c1] and Map.WorldMapSize[c1][z1]
        if not zoneData then
            L._mdebug("Map-ComputeDist", "FAIL: No WorldMapSize data for c="..tostring(c1)..", z="..tostring(z1))
            return
        end
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
        local dist = math.sqrt(xDelta*xDelta + yDelta*yDelta)
        L._mdebug("Map-ComputeDist", string.format("SUCCESS: c=%d, z=%d. Calculated distance: %.2f yards.", c1, z1, dist))
        return dist, xDelta, yDelta
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
    ["ROUND"]                 = { true,  true,  true,  true  },
    ["SQUARE"]                = { false, false, false, false },

    
    ["CORNER-TOPLEFT"]        = { false, true,  true,  true  },
    ["CORNER-BOTTOMLEFT"]     = { true,  false, true,  true  },
    ["CORNER-TOPRIGHT"]       = { true,  true,  false, true  },
    ["CORNER-BOTTOMRIGHT"]    = { true,  true,  true,  false },

    
    ["SIDE-LEFT"]             = { false, true,  true,  true  },
    ["SIDE-RIGHT"]            = { true,  true,  false, true  },
    ["SIDE-TOP"]              = { true,  true,  true,  false },
    ["SIDE-BOTTOM"]           = { true,  false, true,  true  },

    
    ["TRICORNER-TOPLEFT"]     = { true,  false, false, false },
    ["TRICORNER-BOTTOMLEFT"]  = { false, true,  false, false },
    ["TRICORNER-TOPRIGHT"]    = { false, false, true,  false },
    ["TRICORNER-BOTTOMRIGHT"] = { false, false, false, true  },
}

Map._mmPins = Map._mmPins or {}
Map._mmTicker = Map._mmTicker or nil
Map._mmElapsed = 0
Map._mmInterval = 0.11
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

function Map:RebuildFilteredCache()
    if not self.cachingEnabled then
        wipe(self.cachedVisibleDiscoveries)
        self.cacheIsDirty = false
        return
    end

    if not self.cacheIsDirty then return end

    
    wipe(self.cachedVisibleDiscoveries)

    
    local discoveries = L:GetDiscoveriesDB()
    local vendors = L:GetVendorsDB()
    
    
    if discoveries then
        for guid, d in pairs(discoveries) do
            if passesFilters(d) then
                table.insert(self.cachedVisibleDiscoveries, d)
            end
        end
    end

    if vendors then
        for guid, d in pairs(vendors) do
            if passesFilters(d) then
                table.insert(self.cachedVisibleDiscoveries, d)
            end
        end
    end
    
    L._mdebug("Map-Cache", "Cache rebuilt. Total passing filters: " .. #self.cachedVisibleDiscoveries)
    self.cacheIsDirty = false
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
    if self._hoverBtn then 
        
        if WorldMapTooltip and WorldMapTooltip:IsShown() then
            self._hoverBtn:SetParent(WorldMapTooltip)
            self._hoverBtn:SetFrameLevel(WorldMapTooltip:GetFrameLevel() + 10)
        else
            self._hoverBtn:SetParent(GameTooltip)
            self._hoverBtn:SetFrameLevel(GameTooltip:GetFrameLevel() + 10)
        end
        return 
    end
    
    
    local btn = CreateFrame("Button", "LootCollectorItemHoverBtn", GameTooltip)
    btn:SetSize(16, 16)
    -- Xurkon: Changed from TOOLTIP to HIGH strata to fix tooltips displaying behind hover button
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(GameTooltip:GetFrameLevel() + 10)
    btn:EnableMouse(true)
    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetAllPoints(btn)
    btn:Hide()
    
    btn:SetScript("OnEnter", function(self)
        if not Map._hoverBtnItemLink then return end
        ItemRefTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        ItemRefTooltip:ClearAllPoints()
        
        local activeTooltip = self:GetParent()
        ItemRefTooltip:SetPoint("TOPLEFT", activeTooltip, "TOPRIGHT", 8, 0)
        ItemRefTooltip:SetHyperlink(Map._hoverBtnItemLink)
        ItemRefTooltip:Show()
    end)
    
    btn:SetScript("OnLeave", function(self)
        ItemRefTooltip:Hide()
    end)
    self._hoverBtn = btn
end

function Map:ShowBlackmarketTooltip(d, anchorFrame)
    
    if not self._vendorTooltip then
        self._vendorTooltip = CreateFrame("GameTooltip", "LootCollectorVendorTooltip", UIParent, "GameTooltipTemplate")
        self._vendorTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    local tooltip = self._vendorTooltip
    
    
    if WorldMapFrame and WorldMapFrame:IsShown() then
         tooltip:SetParent(WorldMapFrame)
         tooltip:SetFrameStrata("TOOLTIP")
         tooltip:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 200)
    else
         tooltip:SetParent(UIParent)
         tooltip:SetFrameStrata("TOOLTIP")
    end
    
    tooltip:SetOwner(anchorFrame, "ANCHOR_RIGHT")
    tooltip:ClearLines()
    
    local vendorTypeDisplay
    if d.vendorType == "MS" or (d.g and d.g:find("MS-", 1, true)) then
        vendorTypeDisplay = "|cffa335ee<Mystic Scroll Vendor>|r"
        tooltip:AddLine(d.vendorName or "Unknown Vendor", 1, 0.82, 0)
    else
        vendorTypeDisplay = "|cff9400D3<Blackmarket Artisan Supplies>|r"
        tooltip:AddLine(d.vendorName or "Unknown Vendor", 0.85, 0.44, 0.85)
    end
    
    tooltip:AddLine(vendorTypeDisplay, 1, 1, 1)

    local status = L:GetDiscoveryStatus(d)
    tooltip:AddDoubleLine("Status", status, 0.8, 0.8, 0.8, 1, 1, 1)

    local ls = tonumber(d.ls) or tonumber(d.t0) or time()
    tooltip:AddDoubleLine("Last seen", date("%Y-%m-%d %H:%M", ls), 0.8, 0.8, 0.8, 1, 1, 1)

    do
        local c, z, iz = tonumber(d.c) or 0, tonumber(d.z) or 0, tonumber(d.iz) or 0
        local zoneName = L.ResolveZoneDisplay(c, z, iz)
        tooltip:AddDoubleLine("Zone", zoneName, 0.8, 0.8, 0.8, 1, 1, 1)
    end

    if d.xy then
        tooltip:AddDoubleLine("Location", string.format("%.1f, %.1f", (d.xy.x or 0) * 100, (d.xy.y or 0) * 100), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    
    tooltip:AddLine(" ", nil, nil, nil, true) 
    tooltip:AddLine("|cff00ff00Left-click to view inventory.|r")

    tooltip:Show()
end

function Map:ShowDiscoveryTooltip(discoveryOrPin, anchorFrame)
    local d = discoveryOrPin.discovery or discoveryOrPin
    if not d then return end
    
    local Constants = L:GetModule("Constants", true)
    if Constants and d.dt == Constants.DISCOVERY_TYPE.BLACKMARKET then
        self:ShowBlackmarketTooltip(d, anchorFrame or discoveryOrPin)
        return
    end

    if WorldMapPOIFrame and WorldMapPOIFrame.allowBlobTooltip ~= nil then
        self._oldAllowBlobTooltip = WorldMapPOIFrame.allowBlobTooltip
        WorldMapPOIFrame.allowBlobTooltip = false
    end

    
    local tooltip = GameTooltip
    local isFullScreen = false
    
    if WorldMapFrame and WorldMapFrame:IsShown() then
         local mapSize = WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.size
         if mapSize == WORLDMAP_QUESTLIST_SIZE or mapSize == WORLDMAP_FULLMAP_SIZE then
             isFullScreen = true
         end
    end

    if isFullScreen then
        tooltip:SetParent(WorldMapFrame)
        tooltip:SetFrameStrata("TOOLTIP")
        tooltip:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 100)
    else
        
        tooltip:SetParent(UIParent)
        tooltip:SetFrameStrata("TOOLTIP")
    end

    tooltip:SetOwner(anchorFrame or discoveryOrPin, "ANCHOR_RIGHT")
    
    local itemName, itemLink = GetItemInfo(d.i or d.il)
    local isCached = itemName and itemLink and true or false

    if isCached then
        tooltip:SetHyperlink(itemLink)
    else
        tooltip:ClearLines()
        local header = d.il or ("Item ID: " .. tostring(d.i))
        tooltip:AddLine(header, 1, 1, 1, true)
        tooltip:AddLine("Retrieving item information...", 0.6, 0.6, 0.6)
        
        local Core = L:GetModule("Core", true)
        if Core and Core.QueueItemForCaching then
            Core:QueueItemForCaching(d.i)
        end
    end

    tooltip:AddLine(" ", nil, nil, nil, true) 

    if not (L.db and L.db.profile and L.db.profile.hidePlayerNames) then
        tooltip:AddLine(string.format("Found by %s", d.fp or "Unknown"), 0.6, 0.8, 1, true)
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
        local c, z, iz = tonumber(d.c) or 0, tonumber(d.z) or 0, tonumber(d.iz) or 0
        local zoneName = L.ResolveZoneDisplay(c, z, iz)
        tooltip:AddDoubleLine("Zone", zoneName, 0.8, 0.8, 0.8, 1, 1, 1)
    end

    if d.xy then
        tooltip:AddDoubleLine("Location", string.format("%.1f, %.1f", (d.xy.x or 0) * 100, (d.xy.y or 0) * 100), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    
     local Constants = L:GetModule("Constants", true)
    if d.dt == (Constants and Constants.DISCOVERY_TYPE.MYSTIC_SCROLL) and d.src ~= nil then
        local srcText = "Unknown"
        if type(d.src) == "number" then
            
            
            if d.src == 0 then srcText = SOURCE_TEXT_MAP["world_loot"]
            elseif d.src == 1 then srcText = SOURCE_TEXT_MAP["npc_gossip"]
            elseif d.src == 2 then srcText = SOURCE_TEXT_MAP["emote_event"]
            elseif d.src == 3 then srcText = SOURCE_TEXT_MAP["direct"]
            else srcText = "Type " .. d.src end
        else
            srcText = SOURCE_TEXT_MAP[d.src] or d.src
        end
        tooltip:AddDoubleLine("Source", srcText, 0.8, 0.8, 0.8, 1, 1, 1)
    end

    tooltip:Show()
end

function Map:HideDiscoveryTooltip()
  if GameTooltip and GameTooltip:IsShown() then 
      local owner = GameTooltip:GetOwner()
      
      
      local isOurPin = false
      
      if owner then
          
          for _, pin in ipairs(self.pins) do
              if owner == pin then isOurPin = true; break end
          end
          
          if not isOurPin then
              for _, pin in ipairs(self.clusterPins) do
                  if owner == pin then isOurPin = true; break end
              end
          end
          
          if not isOurPin and L:GetModule("ProximityList", true) then
             local PL = L:GetModule("ProximityList", true)
             if PL and PL._buttons then
                 for _, btn in ipairs(PL._buttons) do
                     if owner == btn then isOurPin = true; break end
                 end
             end
          end
          
           if not isOurPin and L:GetModule("Viewer", true) then
             local Viewer = L:GetModule("Viewer", true)
             if Viewer and Viewer.rows then
                 for _, row in ipairs(Viewer.rows) do
                     if row.nameFrame and owner == row.nameFrame then isOurPin = true; break end
                     if row.itemBtn and owner == row.itemBtn then isOurPin = true; break end
                     if row.zoneBtn and owner == row.zoneBtn then isOurPin = true; break end
                 end
             end
             if not isOurPin and Viewer and Viewer.vendorInventoryLines then
                  for _, line in ipairs(Viewer.vendorInventoryLines) do
                      if owner == line then isOurPin = true; break end
                  end
             end
          end
          
          if not isOurPin and WorldMapFrame.viewerOverlayPin and owner == WorldMapFrame.viewerOverlayPin then
              isOurPin = true
          end
      end

      if isOurPin then
          GameTooltip:Hide() 
          
          GameTooltip:SetParent(UIParent)
          GameTooltip:SetFrameStrata("TOOLTIP") -- Xurkon: Force above other addon frames
      end
  end
  
  
  if ItemRefTooltip then ItemRefTooltip:Hide() end
  if self._hoverBtn then self._hoverBtn:Hide(); self._hoverBtnItemLink = nil end

  if self._vendorTooltip and self._vendorTooltip:IsShown() then
    self._vendorTooltip:Hide()
  end

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
        Map.cacheIsDirty = true 
        Map:Update()
      end })
      table.insert(menuList, { text = "Set as unlooted", notCheckable = true, func = function()
        if not (L.db and L.db.char and L.db.char.looted) then return end
        L.db.char.looted[d.g] = nil
        Map.cacheIsDirty = true 
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
  
  
  Map.isOpeningMenu = true

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
       func = function() 
          f[key] = not f[key]
          Map.cacheIsDirty = true
          Map:Update()
          Map:UpdateMinimap()
      end 
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
      text = "Auto-track Nearest Unlooted",
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
  table.insert(showSub, { text = "Mystic Scrolls", checked = f.showMysticScrolls, keepShownOnClick = true, func = function() f.showMysticScrolls = not f.showMysticScrolls; Map.cacheIsDirty = true; Map:Update(); Map:UpdateMinimap() end })
  table.insert(showSub, { text = "Worldforged Items", checked = f.showWorldforged, keepShownOnClick = true, func = function() f.showWorldforged = not f.showWorldforged; Map.cacheIsDirty = true; Map:Update(); Map:UpdateMinimap() end })
  
table.insert(showSub, {
  text = "Enhanced WF Toltip",
  checked = (L.db and L.db.profile and L.db.profile.enhancedWFTooltip) and true or false,
  keepShownOnClick = true,
  func = function()
    if not (L and L.db and L.db.profile) then return end
    L.db.profile.enhancedWFTooltip = not (L.db.profile.enhancedWFTooltip and true or false)

    local Tooltip = L:GetModule("Tooltip", true)
    if Tooltip and Tooltip.ApplySetting then
      Tooltip:ApplySetting()
    else
      _G.ItemUpgradeTooltipDB = _G.ItemUpgradeTooltipDB or {}
      _G.ItemUpgradeTooltipDB.enabled = L.db.profile.enhancedWFTooltip and true or false
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
        Map.cacheIsDirty = true 
        Map:Update()
        Map:UpdateMinimap()
        if EasyMenu and FilterButton then
          EasyMenu(BuildFilterEasyMenu(), FilterMenuHost, FilterButton, 0, 0, "MENU", 2)
        end
      end
    })
  end
  table.insert(menu, { text = "Minimum Quality", hasArrow = true, notCheckable = true, menuList = raritySub })

  local slotsSub = { { text = "Slots", isTitle = true, notCheckable = true }, { text = "Clear All", notCheckable = true, func = function() for k in pairs(f.allowedEquipLoc) do f.allowedEquipLoc[k] = nil end; Map.cacheIsDirty = true; Map:Update(); Map:UpdateMinimap() end } }
  for _, opt in ipairs(SLOT_OPTIONS) do
    table.insert(slotsSub, {
      text = opt.text,
      checked = f.allowedEquipLoc[opt.loc] and true or false,
      keepShownOnClick = true,
      func = function()
        if f.allowedEquipLoc[opt.loc] then f.allowedEquipLoc[opt.loc] = nil else f.allowedEquipLoc[opt.loc] = true end
        Map.cacheIsDirty = true 
        Map:Update(); Map:UpdateMinimap()
      end
    })
  end
  table.insert(menu, { text = "Slots", hasArrow = true, notCheckable = true, menuList = slotsSub })

  local usableBySub = { { text = "Usable by", isTitle = true, notCheckable = true }, { text = "Clear All", notCheckable = true, func = function() for k in pairs(f.usableByClasses) do f.usableByClasses[k] = nil end; Map.cacheIsDirty = true; Map:Update(); Map:UpdateMinimap() end } }
  for _, classTok in ipairs(CLASS_OPTIONS) do
    local locName = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classTok]) or classTok
    table.insert(usableBySub, {
      text = locName,
      checked = f.usableByClasses[classTok] and true or false,
      keepShownOnClick = true,
      func = function()
        if f.usableByClasses[classTok] then f.usableByClasses[classTok] = nil else f.usableByClasses[classTok] = true end
        Map.cacheIsDirty = true 
        Map:Update(); Map:UpdateMinimap()
      end
    })
  end
  table.insert(menu, { text = "Usable by", hasArrow = true, notCheckable = true, menuList = usableBySub })

  return menu
end

local function PlaceFilterButton(btn)
  
  if btn.isDragging then return end

  
  if L.db and L.db.profile and L.db.profile.mapFilters and L.db.profile.mapFilters.filterButtonPos then
      local pos = L.db.profile.mapFilters.filterButtonPos
      btn:ClearAllPoints()
      btn:SetPoint(pos.point, WorldMapFrame, pos.relPoint, pos.x, pos.y)
      return
  end

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
    
    
    FilterButton:SetMovable(true)
    FilterButton:RegisterForDrag("LeftButton")
    FilterButton:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self.isDragging = true
            self:StartMoving()
        end
    end)
    FilterButton:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.isDragging = false
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        if L.db and L.db.profile then
            L.db.profile.mapFilters = L.db.profile.mapFilters or {}
            L.db.profile.mapFilters.filterButtonPos = {
                point = point,
                relPoint = relativePoint,
                x = xOfs,
                y = yOfs
            }
        end
    end)
    
    
    FilterButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("LootCollector Filters")
        GameTooltip:AddLine("Left-Click to open menu", 1, 1, 1)
        GameTooltip:AddLine("Shift+Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
        GameTooltip:SetFrameStrata("TOOLTIP") -- Xurkon: Force above other addon frames
    end)
    FilterButton:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

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
    if not self.discovery then return end
    
    local d = self.discovery
    local Constants = L:GetModule("Constants", true)
    local isVendor = d.dt and Constants and d.dt == Constants.DISCOVERY_TYPE.BLACKMARKET
    
    if IsAltKeyDown() or isVendor then
        L._debug("Map", "OnEnter - Pin (ALT pressed or Vendor, showing detailed tooltip)")
        Map:ShowDiscoveryTooltip(self)
    else
        L._debug("Map", "OnEnter - Pin (no modifier, showing simple tooltip)")
        
        local itemLink = d.il or d.i
        if itemLink then
            
            local tooltip = GameTooltip
            local isFullScreen = false
            if WorldMapFrame and WorldMapFrame:IsShown() then
                 local mapSize = WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.size
                 if mapSize == WORLDMAP_QUESTLIST_SIZE or mapSize == WORLDMAP_FULLMAP_SIZE then
                     isFullScreen = true
                 end
            end

            if isFullScreen then
                tooltip:SetParent(WorldMapFrame)
                tooltip:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 100)
            else
                tooltip:SetParent(UIParent)
            end
            tooltip:SetFrameStrata("TOOLTIP")

            tooltip:SetOwner(self, "ANCHOR_RIGHT")
            tooltip:SetHyperlink(itemLink)
            
            local itemName = GetItemInfo(itemLink)
            if not itemName then
                tooltip:AddLine("Retrieving item information...", 0.6, 0.6, 0.6)
            end
            tooltip:Show()
        end
    end
    
    local ProximityList = L:GetModule("ProximityList", true)
    if ProximityList and not IsControlKeyDown() then
        if ProximityList.UpdateForPin then
            local clusterFound = ProximityList:UpdateForPin(self)
            if clusterFound then
                Map:HideDiscoveryTooltip() 
                return
            end
        end
    end
  end)

  frame:SetScript("OnLeave", function(self)
    L._debug("Map", "OnLeave - Pin")
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
     if button == "LeftButton" then
        NavigateHere(d)
        
        local Constants = L:GetModule("Constants", true)
        local isVendor = d.dt and Constants and d.dt == Constants.DISCOVERY_TYPE.BLACKMARKET
        
        if isVendor then
            local ProximityList = L:GetModule("ProximityList", true)
            if ProximityList and ProximityList.ShowVendorInventory then
                ProximityList:ShowVendorInventory(d)
            end
        elseif IsControlKeyDown() and d.il then
            ChatFrame1EditBox:Insert(d.il)
        end
    end
  end)

  table.insert(self.pins, frame)
  return frame
end
  

local function GetCurrentMinimapShape()
    local shape = "ROUND"
    if _G.GetMinimapShape then
        local s = _G.GetMinimapShape()
        if s and ValidMinimapShapes[s] then
            shape = s
        end
    end
    return ValidMinimapShapes[shape]
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
  
  
  local f = CreateFrame("Frame", "LootCollectorMinimapPin"..i, Minimap)
  f:SetSize(pinSize, pinSize)
  
  f:EnableMouse(true)
  
  
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
      GameTooltip:SetFrameStrata("TOOLTIP") -- Xurkon: Force above other addon frames
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
  
  
  if self.cachingEnabled then
      if self.cacheIsDirty or #self.cachedVisibleDiscoveries == 0 then
           self.cacheIsDirty = true
           self:RebuildFilteredCache()
      end
  end

  local currentContinent, currentMapID = self:GetPlayerLocation()

  if not currentContinent or not currentMapID then
    self:HideAllMmPins()
    return
  end
  
  currentContinent = tonumber(currentContinent)
  currentMapID = tonumber(currentMapID)
  
  local visibleDiscoveries = {}
  local sourceList = self.cachingEnabled and self.cachedVisibleDiscoveries or {}
  
  if not self.cachingEnabled then
      local discoveries = L:GetDiscoveriesDB()
      if discoveries then
          for guid, d in pairs(discoveries) do table.insert(sourceList, d) end
      end
      local vendors = L:GetVendorsDB()
      if vendors then
          for guid, d in pairs(vendors) do table.insert(sourceList, d) end
      end
  end

  for _, d in ipairs(sourceList) do
    
    local shouldShow = false
    
    if self.cachingEnabled then
        
        if tonumber(d.c) == currentContinent and tonumber(d.z) == currentMapID then
            shouldShow = true
        end
    else
        
        if passesFilters(d) and tonumber(d.c) == currentContinent and tonumber(d.z) == currentMapID then
            shouldShow = true
        end
    end

    if shouldShow then
        table.insert(visibleDiscoveries, d)
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
  
  self._minimapPinsDirty = true
  if self._mmTicker then
      self._mmInterval = 0 
      if not self._mmTicker:GetScript("OnUpdate") then
           self:EnsureMinimapTicker()
      end
  else
      self:EnsureMinimapTicker()
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

    self._mmTicker = CreateFrame("Frame")
    self._mmTicker:SetScript("OnUpdate", function(_, elapsed)
        Map._mmElapsed = (Map._mmElapsed or 0) + elapsed
        if Map._mmElapsed >= Map._mmInterval then
            Map._mmElapsed = 0

            
            local c, mapID, px, py = Map:GetPlayerLocation()
            if not px or not py or not c or not mapID then return end

            c = tonumber(c)
            mapID = tonumber(mapID)

            local rotateEnabled = (GetCVar("rotateMinimap") == "1")
            local facing = GetPlayerFacing()

            
            local state = Map._lastPlayerState
            local playerMoved = not (
                c == state.c and
                mapID == state.mapID and
                math.abs(px - (state.px or -1)) < 0.0001 and
                math.abs(py - (state.py or -1)) < 0.0001 and
                math.abs(facing - (state.facing or -1)) < 0.001
            )

            
            if not playerMoved and not Map._minimapPinsDirty then
                
                 L._mdebug("Map-Ticker", "Player state unchanged. Skipping position recalculation.")
                Map._mmInterval = 0.5
                Map._playerStateChanged = false
                return
            end

            
            Map._playerStateChanged = true
            Map._minimapPinsDirty = false 
            Map._mmInterval = 0.1

            state.c, state.mapID, state.px, state.py, state.facing = c, mapID, px, py, facing

            if playerMoved then
                 L._mdebug(
                    "Map-Ticker",
                    string.format("Ticker Position Update: c=%s, mapID=%s. Player at %.4f, %.4f", tostring(c), tostring(mapID), px, py)
                )
            else
                
                 L._mdebug("Map-Ticker", "Forced ticker update (pins dirty).")
            end

            local minimapRadius = Minimap:GetViewRadius()
            local mapWidth = Minimap:GetWidth()
            local mapHeight = Minimap:GetHeight()

            local xScale = (minimapRadius * 2) / mapWidth
            local yScale = (minimapRadius * 2) / mapHeight

            local edgeRadius = minimapRadius - 8

            local maxDistYards = L.db.profile.mapFilters.maxMinimapDistance
            local maxDistSq = (maxDistYards and maxDistYards > 0) and (maxDistYards * maxDistYards) or nil

            local cos_f, sin_f
            if rotateEnabled then
                cos_f = math.cos(facing)
                sin_f = math.sin(facing)
            end

            
            local minimapShape = GetCurrentMinimapShape()

            for _, pin in ipairs(Map._mmPins) do
                if pin.discovery then 
                    local d = pin.discovery

                    
                    
                    
                    
                    
                    if d.c == c and d.z == mapID then
                        local distYards, xDist, yDist = ComputeDistance(
                            c, mapID, px, py,
                            d.c, d.z, d.xy.x, d.xy.y
                        )

                        if distYards and xDist and yDist then
                            
                            if maxDistSq and (distYards * distYards) > maxDistSq then
                                pin:Hide()
                            else
                                
                                if rotateEnabled then
                                    local dx, dy = xDist, yDist
                                    xDist = dx * cos_f - dy * sin_f
                                    yDist = dx * sin_f + dy * cos_f
                                end

                                
                                local quad = (xDist < 0) and 1 or 3
                                if yDist >= 0 then
                                    quad = quad + 1
                                end

                                local useCircular = minimapShape and minimapShape[quad]
                                local dist
                                if useCircular then
                                    dist = math.sqrt(xDist * xDist + yDist * yDist)
                                else
                                    dist = math.max(math.abs(xDist), math.abs(yDist))
                                end

                                local iconRadius = ((pin:GetWidth() / 2) + 3) * xScale

                                if dist + iconRadius > edgeRadius then
                                    local maxEdgeDist = edgeRadius - iconRadius
                                    if dist > 0 and maxEdgeDist > 0 then
                                        local scale = maxEdgeDist / dist
                                        xDist = xDist * scale
                                        yDist = yDist * scale
                                    end
                                end

                                pin:ClearAllPoints()
                                pin:SetPoint("CENTER", Minimap, "CENTER", xDist / xScale, -yDist / yScale)

                                if not pin:IsShown() then
                                    pin:Show()
                                end
                            end
                        else
                            pin:Hide()
                        end
                    else
                        
                        pin:Hide()
                    end
                else
                    
                    pin:Hide()
                end
            end
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
            Map.cacheIsDirty = true 
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
        if Map._searchTimer then 
            C_Timer.CancelTimer(Map._searchTimer) 
            Map._searchTimer = nil 
        end
        Map.cacheIsDirty = true 
        Map:Update()
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
    
    local discoveries = L:GetDiscoveriesDB() or {}
    for _, d in pairs(discoveries) do
        if SearchDiscoveryForTerm(d, term) then
            table.insert(results, d)
        end
    end
    
    local vendors = L:GetVendorsDB() or {}
    for _, d in pairs(vendors) do
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
      f:SetFrameStrata("FULLSCREEN_DIALOG") 
      f:SetFrameLevel(200) 
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
  
  
  if WorldMapFrame and WorldMapFrame:IsShown() then
       local mapSize = WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.size
       if mapSize == WORLDMAP_QUESTLIST_SIZE or mapSize == WORLDMAP_FULLMAP_SIZE then
           f:SetParent(WorldMapFrame)
           f:SetFrameStrata("FULLSCREEN_DIALOG")
           f:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 200)
       else
           f:SetParent(UIParent)
       end
  else
       f:SetParent(UIParent)
  end
  
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
      
      zoneName = L.ResolveZoneDisplay(c, z, iz)
      
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
              
              local tooltip = GameTooltip
              if f:GetParent() == WorldMapFrame then
                  tooltip:SetParent(WorldMapFrame)
                  tooltip:SetFrameLevel(f:GetFrameLevel() + 10)
              else
                  tooltip:SetParent(UIParent)
              end
              
              tooltip:SetOwner(self, "ANCHOR_RIGHT")
              tooltip:SetHyperlink(d.il)
              tooltip:Show()
          end
      end)
      btn:SetScript("OnLeave", function()
          GameTooltip:Hide()
          if f:GetParent() == WorldMapFrame then
               GameTooltip:SetParent(UIParent) 
          end
      end)
      
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
  
  
  L._debug("Map-ShowTo", string.format("Opening 'Show To' dialog. Discovery dt: %s, src: %s", tostring(discovery.dt), tostring(discovery.src)))
  
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

function Map:RefreshPinIconsForItem(itemID)
    if not itemID or not self.pins then return end
    L._debug("Map-Cache", "Force refreshing pin icons for itemID: " .. itemID)

    local filters = L:GetFilters()

    for _, pin in ipairs(self.pins) do
        if pin and pin.discovery and pin.discovery.i == itemID then
            L._debug("Map-Cache", "Found matching pin to refresh.")
            local d = pin.discovery
            
            local icon = self:GetDiscoveryIcon(d)
            pin.texture:SetTexture(icon or PIN_FALLBACK_TEXTURE)
            
            local isLooted = L:IsLootedByChar(d.g)
            local isFallback = (icon == PIN_FALLBACK_TEXTURE)

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
        end
    end
end

    

function Map:DrawWorldMapPins()
    local isB = Core and Core.isSB and Core:isSB()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end  
    
    self:EnsureSearchUI()

    local ProximityList = L:GetModule("ProximityList", true)

    if L.IsZoneIgnored and L:IsZoneIgnored() then
        for _, pin in ipairs(self.pins) do pin:Hide() end
        for _, pin in ipairs(self.clusterPins) do pin:Hide() end
        self:HideDiscoveryTooltip()
        if ProximityList and ProximityList._frame then ProximityList._frame:Hide("Call from Map:Update@ IsZoneIgnored") end
        return
    end
  
    
    local Core = L:GetModule("Core", true)
    if not Core or not Core.ZoneIndexBuilt then return end 
    
    self:EnsureFilterUI()
    local filters = L:GetFilters()
    if filters.hideAll then
        for _, pin in ipairs(self.pins) do pin:Hide() end
        for _, pin in ipairs(self.clusterPins) do pin:Hide() end
        self:HideDiscoveryTooltip()
        if ProximityList and ProximityList._frame then ProximityList._frame:Hide() end
        return
    end

    if self.cachingEnabled then
        self:RebuildFilteredCache()
    end

    local currentContinent, currentMapID = GetCurrentMapContinent(), GetCurrentMapAreaID()
  
    if not WorldMapDetailFrame or not WorldMapButton then return end
    local mapWidth, mapHeight = WorldMapDetailFrame:GetWidth(), WorldMapDetailFrame:GetHeight()
    if not mapWidth or mapWidth == 0 then return end
  
    local mapLeft, mapTop = WorldMapDetailFrame:GetLeft(), WorldMapDetailFrame:GetTop()
    local parentLeft, parentTop = WorldMapButton:GetLeft(), WorldMapButton:GetTop()
  
    if not mapLeft or not mapTop or not parentLeft or not parentTop then
        L._mdebug("Map", "Aborting Update: Map frame geometry data is nil.")
        return
    end
  
    local offsetX, offsetY = mapLeft - parentLeft, mapTop - parentTop
    local pinIndex = 1
  
    if ProximityList and ProximityList._lastHoveredPin then
        ProximityList._lastHoveredPin:SetScale(1.0)
        ProximityList._lastHoveredPin = nil
    end
  
    
    
    
    
    
    local discoveries = L:GetDiscoveriesDB()
    local vendors = L:GetVendorsDB()
    local zoneGUIDs = Core.ZoneIndex[currentMapID]
    
    if zoneGUIDs then
        for _, guid in ipairs(zoneGUIDs) do
            
            local d = discoveries[guid] or vendors[guid]
            
            if d then
                
                if tonumber(d.c) == tonumber(currentContinent) then
                    
                    
                    if passesFilters(d) then
                        if type(d) == "table" and d.xy then
                            if isB then
                            else            
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
                            end
                        end
                    end
                end
            end
        end
    end
  
    for i = pinIndex, #self.pins do self.pins[i]:Hide() self.pins[i].discovery = nil end
  
    local ZoneList = L:GetModule("ZoneList", true)
    local clusterPinIndex = 1
  
    
    
    
    if ZoneList and ZoneList.ParentToSubzones and ZoneList.ParentToSubzones[currentMapID] then
        for _, childMapID in ipairs(ZoneList.ParentToSubzones[currentMapID]) do
            local subzoneData = ZoneList.ZoneRelationships and ZoneList.ZoneRelationships[childMapID]
            if subzoneData then
                local count = 0
                local childGUIDs = Core.ZoneIndex[childMapID]
                
                if childGUIDs then
                    for _, guid in ipairs(childGUIDs) do
                        local d = discoveries[guid] or vendors[guid]
                        if d and d.c == subzoneData.c then 
                            if passesFilters(d) then
                                count = count + 1
                            end
                        end
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
                        GameTooltip:AddLine("\n|cff00ff00Click to view this zone.|r", .8,.8,.8, true); GameTooltip:Show(); GameTooltip:SetFrameStrata("TOOLTIP") -- Xurkon: Force above other addon frames
                    end)
                    pin:SetScript("OnClick", function() if SetMapByID then SetMapByID(subzoneData.z - 1) end end)
                    pin:Show()
                end
            end
        end
    end
  
    
    local isContinentView = (currentMapID == 14 or currentMapID == 15 or currentMapID == 467 or currentMapID == 486)
    if filters.showZoneSummaries and isContinentView and ZoneList and ZoneList.ZoneRelationshipsC then
        for _, zoneData in pairs(ZoneList.ZoneRelationshipsC) do
            if zoneData and zoneData.parent and zoneData.parent.c == currentContinent then
                local count = 0
                
                
                local targetZoneID = zoneData.z
                local targetGUIDs = Core.ZoneIndex[targetZoneID]
                
                if targetGUIDs then
                    for _, guid in ipairs(targetGUIDs) do
                        local d = discoveries[guid] or vendors[guid]
                        if d and passesFilters(d) then
                            count = count + 1
                        end
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
                        GameTooltip:AddLine("\n|cff00ff00Click to view this zone.|r", .8,.8,.8, true); GameTooltip:Show(); GameTooltip:SetFrameStrata("TOOLTIP") -- Xurkon: Force above other addon frames
                    end)
                    pin:SetScript("OnClick", function() if SetMapByID then SetMapByID(zoneData.z - 1) end end)
                    pin:Show()
                end
            end
        end
    end

    for i = clusterPinIndex, #self.clusterPins do self.clusterPins[i]:Hide() end

    if ProximityList and ProximityList._frame and ProximityList._frame:IsShown() then
        if not ProximityList._lastHoveredPin or not ProximityList._lastHoveredPin:IsShown() then
            
        end
    end
end

function Map:Update()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    
    
    self:EnsureThrottleFrame()
    
    
    self.worldMapUpdatePending = true
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

function Map:EnsureThrottleFrame()
    if self.throttleFrame then return end
    self.throttleFrame = CreateFrame("Frame")
    self.throttleFrame:SetScript("OnUpdate", function(frame, elapsed)
        if Map.worldMapUpdatePending then
            Map.worldMapUpdateTimer = Map.worldMapUpdateTimer + elapsed
            if Map.worldMapUpdateTimer >= MAP_UPDATE_THROTTLE then
                Map:DrawWorldMapPins()
                Map.worldMapUpdatePending = false
                Map.worldMapUpdateTimer = 0
            end
        end
    end)
end

return Map