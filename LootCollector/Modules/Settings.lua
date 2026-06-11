

local L = LootCollector
local Settings = L:NewModule("Settings", "AceConsole-3.0")
local AceConfig = (LibStub and LibStub("AceConfig-3.0", true)) or nil
local AceConfigDialog = (LibStub and LibStub("AceConfigDialog-3.0", true)) or nil

local function OpenCopyPopup(title, textToCopy)
    local f = _G["LootCollectorCopyPopup"]
    if not f then
        f = CreateFrame("Frame", "LootCollectorCopyPopup", UIParent)
        f:SetSize(560, 380)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\DialogBox\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = {left = 8, right = 8, top = 8, bottom = 8},
        })
        f:SetBackdropColor(0, 0, 0, 1)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOPLEFT", 16, -12)

        f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        f.scroll:SetPoint("TOPLEFT", 16, -36)
        f.scroll:SetPoint("BOTTOMRIGHT", -34, 48)

        f.edit = CreateFrame("EditBox", nil, f.scroll)
        f.edit:SetMultiLine(true)
        f.edit:SetFontObject(ChatFontNormal)
        f.edit:SetWidth(500)
        f.edit:SetAutoFocus(false)
        f.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        f.edit:EnableMouse(true)
		f.edit:SetScript("OnTextChanged", function() end)
		f.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        f.scroll:SetScrollChild(f.edit)

        f.btnClose = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.btnClose:SetSize(100, 22)
        f.btnClose:SetPoint("BOTTOMRIGHT", -12, 12)
        f.btnClose:SetText("Close")
        f.btnClose:SetScript("OnClick", function() f:Hide() end)
        
        _G["LootCollectorCopyPopup"] = f
    end

    f.title:SetText(title)
    f.edit:SetText(textToCopy)
    f:Show()
    f.edit:SetFocus()
end

local function refreshUI()
	local Map = L:GetModule("Map", true)
	if Map then
        
        Map.cacheIsDirty = true
        
        if Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
            Map:Update()
        end
        
        if Map.UpdateMinimap then
            Map:UpdateMinimap() 
        end
    end
    
	local Arrow = L:GetModule("Arrow", true)
	if Arrow and Arrow.frame and L.db and L.db.profile and L.db.profile.mapFilters and L.db.profile.mapFilters.hideAll then
		Arrow.frame:Hide()
	end
end

local function ShowTopContributors()
    
	local discoveries = L:GetDiscoveriesDB()
	if not discoveries then
		print("|cffff7f00LootCollector|r Database not found.")
		return
	end
	local counts = {}
	for _, d in pairs(discoveries) do
		if d and d.fp and d.fp ~= "" and d.fp ~= "Unknown" then
			counts[d.fp] = (counts[d.fp] or 0) + 1
		end
	end
	local sorted = {}
	for n, c in pairs(counts) do
		table.insert(sorted, {n = n, c = c})
	end
	table.sort(sorted, function(a, b) return a.c > b.c end)
	print("|cffffff00--- LootCollector Top Contributors ---|r")
	for i = 1, math.min(10, #sorted) do
		print(string.format("%d. |cffffff00%s|r: %d discoveries", i, sorted[i].n, sorted[i].c))
	end
end

local function listToString(t)
	if type(t) ~= "table" then return "" end
	local names = {}
	for name, on in pairs(t) do
		if on and type(name) == "string" then
			local s = name:gsub("^%s+", ""):gsub("%s+$", "")
			if s ~= "" then table.insert(names, s) end
		end
	end
	table.sort(names)
	return table.concat(names, "\n")
end

local function stringToList(v, t)
	if type(t) ~= "table" then return end
	for k in pairs(t) do t[k] = nil end
	if type(v) ~= "string" then return end
	for line in v:gmatch("[^\r\n]+") do
		local s = line:gsub("^%s+", ""):gsub("%s+$", "")
		if s ~= "" then t[s] = true end
	end
end

local function ensureDefaults()
	if not L.db and L.db.profile then return end
	local p = L.db.profile
	
	if p.hidePlayerNames == nil then p.hidePlayerNames = false end
	if p.hideNonEssential == nil then p.hideNonEssential = true end 
	if p.disableMysticScrolls == nil then p.disableMysticScrolls = false end
    
    p.featureOverrides = p.featureOverrides or {
        realmType = "AUTO",
    }
    
    p.viewer = p.viewer or {}
    if p.viewer.rowFont == nil then p.viewer.rowFont = "Fonts\\ARIALN.TTF" end
    if p.viewer.rowFontSize == nil then p.viewer.rowFontSize = 14 end
    if p.viewer.rowHeight == nil then p.viewer.rowHeight = 28 end
    if p.viewer.uiFont == nil then p.viewer.uiFont = "Fonts\\ARIALN.TTF" end
    if p.viewer.uiFontSize == nil then p.viewer.uiFontSize = 13 end
    if p.viewer.useWCAGColoring == nil then p.viewer.useWCAGColoring = true end
    if p.viewer.inlineVendorView == nil then p.viewer.inlineVendorView = false end
    if p.viewer.splitRatio == nil then p.viewer.splitRatio = 0.64 end
    if p.viewer.asyncLoading == nil then p.viewer.asyncLoading = true end
    
	p.sharing = p.sharing or {}
	if p.sharing.enabled == nil then p.sharing.enabled = true end
	if p.sharing.anonymous == nil then p.sharing.anonymous = false end
	if p.sharing.delayed == nil then p.sharing.delayed = false end
	if p.sharing.delaySeconds == nil then p.sharing.delaySeconds = 30 end
	if p.sharing.pauseInHighRisk == nil then p.sharing.pauseInHighRisk = false end
    if p.sharing.allowShowRequests == nil then p.sharing.allowShowRequests = true end 
	if p.sharing.rejectPartySync == nil then p.sharing.rejectPartySync = false end
	if p.sharing.rejectGuildSync == nil then p.sharing.rejectGuildSync = false end
	if p.sharing.rejectWhisperSync == nil then p.sharing.rejectWhisperSync = false end
	if p.sharing.blockList == nil then p.sharing.blockList = {} end
	if p.sharing.whiteList == nil then p.sharing.whiteList = {} end
	if p.autoCache == nil then p.autoCache = true end

	p.toasts = p.toasts or {}
	if p.toasts.enabled == nil then p.toasts.enabled = true end	
	if p.toasts.displayTime == nil then p.toasts.displayTime = 5.0 end
	if p.toasts.tickerEnabled == nil then p.toasts.tickerEnabled = true end
	if p.toasts.tickerSpeed == nil then p.toasts.tickerSpeed = 90 end
	if p.toasts.tickerFontDelta == nil then p.toasts.tickerFontDelta = 3 end
	if p.toasts.tickerOutline == nil then p.toasts.tickerOutline = false end
	if p.toasts.whiteFrame == nil then p.toasts.whiteFrame = true end
	if p.toasts.toastOnlyNew == nil then p.toasts.toastOnlyNew = true end
	if p.toasts.toastMinQuality == nil then p.toasts.toastMinQuality = 2 end
    
    
    p.mapFilters = p.mapFilters or {}
    if p.mapFilters.showMapFilter == nil then p.mapFilters.showMapFilter = true end
    if p.mapFilters.showMinimap == nil then p.mapFilters.showMinimap = true end
    if p.mapFilters.maxMinimapDistance == nil then p.mapFilters.maxMinimapDistance = 0 end 
	if p.mapFilters.disableProximityList == nil then p.mapFilters.disableProximityList = false end 
	if p.minimapButtonHidden == nil then p.minimapButtonHidden = false end
	if p.mapFilters.pinSize == nil then p.mapFilters.pinSize = 16 end
	if p.mapFilters.minimapPinSize == nil then p.mapFilters.minimapPinSize = 10 end
	if p.mapFilters.showZoneSummaries == nil then p.mapFilters.showZoneSummaries = false end
	if p.mapFilters.disableFadeEffect == nil then p.mapFilters.disableFadeEffect = false end
	if p.mapFilters.enableChatLinkIntegration == nil then p.mapFilters.enableChatLinkIntegration = true end
	
    
    if not L.db.char then L.db.char = {} end
    local c = L.db.char
    
    
    if not c.migratedFiltersV8 then
        c.mapFilters = {
            hideAll = p.mapFilters.hideAll or false,
            hideFaded = p.mapFilters.hideFaded or false,
            hideStale = p.mapFilters.hideStale or false,
            hideLooted = p.mapFilters.hideLooted or false,
            hideUnconfirmed = p.mapFilters.hideUnconfirmed or false,
            hideUncached = p.mapFilters.hideUncached or false,
            hideLearnedTransmog = p.mapFilters.hideLearnedTransmog or false,
            hideCollectedME = p.mapFilters.hideCollectedME or false,
            hideBags = p.mapFilters.hideBags or false,
            showMysticScrolls = p.mapFilters.showMysticScrolls ~= false,
            showWorldforged = p.mapFilters.showWorldforged ~= false,
            showVendors = p.mapFilters.showVendors ~= false,
            autoTrackNearest = p.mapFilters.autoTrackNearest or false,
            minRarity = p.mapFilters.minRarity or 0,
            usableByClasses = {},
            allowedEquipLoc = {},
        }
        
        if p.mapFilters.usableByClasses then
            for k, v in pairs(p.mapFilters.usableByClasses) do c.mapFilters.usableByClasses[k] = v end
        end
        if p.mapFilters.allowedEquipLoc then
            for k, v in pairs(p.mapFilters.allowedEquipLoc) do c.mapFilters.allowedEquipLoc[k] = v end
        end
        
        c.paused = p.paused or false
        c.autoPauseInBG = p.autoPauseInBG or true 
        c.autoPauseInRaidInstance = p.autoPauseInRaidInstance or true 
        c.autoPauseInRaidGroup = p.autoPauseInRaidGroup or false
        
        c.migratedFiltersV8 = true
    end
    
    c.mapFilters = c.mapFilters or {}
    if c.mapFilters.hideAll == nil then c.mapFilters.hideAll = false end
    if c.mapFilters.hideFaded == nil then c.mapFilters.hideFaded = false end
    if c.mapFilters.hideStale == nil then c.mapFilters.hideStale = false end
    if c.mapFilters.hideLooted == nil then c.mapFilters.hideLooted = false end
    if c.mapFilters.hideUnconfirmed == nil then c.mapFilters.hideUnconfirmed = false end
    if c.mapFilters.hideUncached == nil then c.mapFilters.hideUncached = false end
    if c.mapFilters.hideLearnedTransmog == nil then c.mapFilters.hideLearnedTransmog = false end
    if c.mapFilters.hideCollectedME == nil then c.mapFilters.hideCollectedME = false end
	if c.mapFilters.hideBags == nil then c.mapFilters.hideBags = false end
    if c.mapFilters.showMysticScrolls == nil then c.mapFilters.showMysticScrolls = true end
    if c.mapFilters.showWorldforged == nil then c.mapFilters.showWorldforged = true end
    if c.mapFilters.showVendors == nil then c.mapFilters.showVendors = true end
    if c.mapFilters.autoTrackNearest == nil then c.mapFilters.autoTrackNearest = false end
    if c.mapFilters.minRarity == nil then c.mapFilters.minRarity = 0 end
    if c.mapFilters.usableByClasses == nil then c.mapFilters.usableByClasses = {} end
    if c.mapFilters.allowedEquipLoc == nil then c.mapFilters.allowedEquipLoc = {} end
    
	if c.paused == nil then c.paused = false end
	if c.autoPauseInBG == nil then c.autoPauseInBG = true end 
	if c.autoPauseInRaidInstance == nil then c.autoPauseInRaidInstance = true end 
	if c.autoPauseInRaidGroup == nil then c.autoPauseInRaidGroup = false end
end

StaticPopupDialogs["LOOTCOLLECTOR_REALM_OVERRIDE_RELOAD"] = {
    text = "You have changed the Active Realm Mode.\n\nA UI reload is required to fully apply these changes to the interface.\n\nWould you like to reload now?",
    button1 = "Reload UI",
    button2 = "Later",
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

StaticPopupDialogs["LOOTCOLLECTOR_COA_OVERRIDE_WARNING"] = {
	text = "|cffff0000WARNING:|r You are manually setting the realm type to 'CoA'.\n\nThis will permanently DELETE all Mystic Scrolls, Mystic Scroll Vendors, Librams, and Idols from your database.\n\nAre you sure?",
	button1 = "Yes, Proceed",
	button2 = "Cancel",
	OnAccept = function()
		L.db.profile.featureOverrides.realmType = "COA"
		local Constants = L:GetModule("Constants", true)
		if Constants and Constants.DetermineRealmCapabilities then
			Constants:DetermineRealmCapabilities()
			Constants:UpdateAllowedTypes()
		end
		
		local Core = L:GetModule("Core", true)
		if Core and Core.RunUnifiedDatabasePass then
            
			local stats = Core:RunUnifiedDatabasePass()
            local count = (stats and stats.coa) or 0
			print(string.format("|cff00ff00LootCollector:|r Realm mode manually set to COA. Purged %d incompatible entries.", count))
		end
        
		
		StaticPopup_Show("LOOTCOLLECTOR_REALM_OVERRIDE_RELOAD")
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	showAlert = true,
}

local function buildOptions()
	ensureDefaults()
	local opts = {
		type = "group",
		name = "LootCollector",
		args = {
			visibility = {
				type = "group",
				name = "Visibility",
				inline = false,
				order = 10,
				args = {
					pauseAddon = {
						type = "toggle",
						name = "|cffff0000Manual Hibernation (Pause)|r",
						order = 0.1,
						desc = "|cffff0000WARNING:|r Pausing the addon completely stops all background tracking. \n\nYour map icons will vanish, you will not receive network updates, and |cffff7f00any items you loot while paused will NOT be saved to your database.|r",
						get = function() return L.db.char.paused end,
						set = function(_, v) L:TogglePause() end,
					},
					autoPauseInBG = {
						type = "toggle",
						name = "Auto-Hibernate in PvP Instances",
						order = 0.2,
						desc = "Automatically puts the addon into Hibernation Mode while inside Battlegrounds or Arenas to save CPU and network bandwidth.",
						get = function() return L.db.char.autoPauseInBG end,
						set = function(_, v) 
						    L.db.char.autoPauseInBG = v 
						    L:EvaluateAutoPause()
						end,
					},
					autoPauseInRaidInstance = {
						type = "toggle",
						name = "Auto-Hibernate in Raid Instances",
						order = 0.3,
						desc = "Automatically puts the addon into Hibernation Mode while inside Raid instances (e.g. Naxxramas).",
						get = function() return L.db.char.autoPauseInRaidInstance end,
						set = function(_, v) 
						    L.db.char.autoPauseInRaidInstance = v 
						    L:EvaluateAutoPause()
						end,
					},
					autoPauseInRaidGroup = {
						type = "toggle",
						name = "Auto-Hibernate in Raid Groups",
						order = 0.4,
						desc = "Automatically puts the addon into Hibernation Mode whenever you are in a Raid Group, regardless of your location. (Warning: You will miss all open-world discoveries while grouped).",
						get = function() return L.db.char.autoPauseInRaidGroup end,
						set = function(_, v) 
						    L.db.char.autoPauseInRaidGroup = v 
						    L:EvaluateAutoPause()
						end,
					},
					hideAll = {
						type = "toggle",
						name = "Hide All",
						order = 1,
						get = function() return L.db.char.mapFilters.hideAll end,
						set = function(_, v)
							L.db.char.mapFilters.hideAll = v
							refreshUI()
						end,
					},
					hideFaded = {
						type = "toggle",
						name = "Hide Faded",
						order = 2,
						get = function() return L.db.char.mapFilters.hideFaded end,
						set = function(_, v)
							L.db.char.mapFilters.hideFaded = v
							refreshUI()
						end,
					},
					hideStale = {
						type = "toggle",
						name = "Hide Stale",
						order = 3,
						get = function() return L.db.char.mapFilters.hideStale end,
						set = function(_, v)
							L.db.char.mapFilters.hideStale = v
							refreshUI()
						end,
					},
					hideLooted = {
						type = "toggle",
						name = "Hide Looted",
						order = 4,
						desc = "Hide discoveries already looted by this character.",
						get = function() return L.db.char.mapFilters.hideLooted end,
						set = function(_, v)
							L.db.char.mapFilters.hideLooted = v
							refreshUI()
						end,
					},
					hideLearnedTransmog = {
						type = "toggle",
						name = "Hide Collected Appearances",
						order = 4.1,
						desc = "Hide discoveries for items with appearances you have already collected.",
						get = function() return L.db.char.mapFilters.hideLearnedTransmog end,
						set = function(_, v)
							L.db.char.mapFilters.hideLearnedTransmog = v
							refreshUI()
						end,
					},
					hideCollectedME = {
						type = "toggle",
						name = "Hide Collected Mystic Enchants",
						order = 4.2,
						desc = "Hide Mystic Scroll discoveries for enchants you have already collected.",
						get = function() return L.db.char.mapFilters.hideCollectedME end,
						set = function(_, v)
							L.db.char.mapFilters.hideCollectedME = v
							refreshUI()
						end,
					},
					hideBags = {
						type = "toggle",
						name = "Hide Bags",
						order = 4.25,
						desc = "Hide discoveries for bag items (containers). Useful if you already have large bags.",
						get = function() return L.db.char.mapFilters.hideBags end,
						set = function(_, v)
							L.db.char.mapFilters.hideBags = v
							refreshUI()
						end,
					},
					enableChatLinkIntegration = {
                        type = "toggle",
                        name = "Chat Link Map Integration",
                        order = 4.38,
                        desc = "Allows you to Alt + Right-Click any item link in the chat box to instantly search your database and show its location on the World Map if found.",
                        get = function() return L.db.profile.mapFilters.enableChatLinkIntegration ~= false end,
                        set = function(_, v)
                            L.db.profile.mapFilters.enableChatLinkIntegration = v
                        end,
                    },
					disableFadeEffect = {
						type = "toggle",
						name = "Disable Fade Effect",
						order = 4.3,
						desc = "Show all map pins at full opacity, even if their discovery is fading or stale.",
						get = function() return L.db.profile.mapFilters.disableFadeEffect end,
						set = function(_, v)
							L.db.profile.mapFilters.disableFadeEffect = v
							refreshUI()
						end,
					},
					hidePlayerNames = {
						type = "toggle",
						name = "Hide Player Names",
						order = 4.5, 
						desc = "Replaces finder names in toasts and map tooltips with a generic message.",
						get = function()
							return L.db.profile.hidePlayerNames
						end,
						set = function(_, v)
							L.db.profile.hidePlayerNames = v
							refreshUI()
						end,
					},
					hideNonEssential = {
						type = "toggle",
						name = "Hide Non-Essential Messages",
						order = 4.6, 
						desc = "Hides routine maintenance and background caching chat messages.",
						get = function()
							return L.db.profile.hideNonEssential
						end,
						set = function(_, v)
							L.db.profile.hideNonEssential = v
						end,
					},
                    showMinimap = {
                        type = "toggle",
                        name = "Show on Minimap",
                        order = 5,
                        get = function() return L.db.profile.mapFilters.showMinimap end,
                        set = function(_,v) L.db.profile.mapFilters.showMinimap = v; refreshUI() end,
                    },
                    minimapPinSize = {
                        type = "range",
                        name = "Minimap Icon Size",
                        order = 5.01, 
                        min = 6, max = 24, step = 1,
                        disabled = function() return not L.db.profile.mapFilters.showMinimap end,
                        get = function() return L.db.profile.mapFilters.minimapPinSize or 10 end,
                        set = function(_, v)
                            L.db.profile.mapFilters.minimapPinSize = v
                            
                            local Map = L:GetModule("Map", true)
                            if Map and Map.UpdateMinimapPinSizes then
                                Map:UpdateMinimapPinSizes()
                            end
                        end,
                    },
                    maxMinimapDistance = {
                        type = "range",
                        name = "Max Minimap Distance (yards)",
                        order = 5.1,
                        desc = "Only show icons on the minimap if they are within this many yards of you.",
                        min = 100, max = 5000, step = 10,
                        disabled = function() return not L.db.profile.mapFilters.showMinimap end,
                        get = function() return L.db.profile.mapFilters.maxMinimapDistance end,
                        set = function(_, v) L.db.profile.mapFilters.maxMinimapDistance = v; refreshUI() end,
                    },
                    autoTrackNearest = {
                        type = "toggle",
                        name = "Auto-track Nearest Unlooted",
                        order = 5.5,
                        desc = "Automatically enables the arrow to point to the nearest unlooted discovery that matches your filters.",
                        get = function() return L.db.char.mapFilters.autoTrackNearest end,
                        set = function(_, v)
                            L.db.char.mapFilters.autoTrackNearest = v
                            local Arrow = L:GetModule("Arrow", true)
                            if Arrow then
                                if v then
                                    Arrow:Show()
                                else
                                    Arrow:Hide()
                                end
                            end
                        end,
                    },
					pinSizeSlider = {
						type = "range",
						name = "Map Icon Size",
						order = 6,
						min = 8,
						max = 32,
						step = 1,
						get = function() return L.db.profile.mapFilters.pinSize end,
						set = function(_, v)
							L.db.profile.mapFilters.pinSize = v
							refreshUI()
						end,
					},
                    showMapFilter = {
                        type = "toggle",
                        name = "Show Map Filter",
                        order = 7,
                        get = function() return L.db.profile.mapFilters.showMapFilter end,
                        set = function(_, v)
                            L.db.profile.mapFilters.showMapFilter = v
                            local Map = L:GetModule("Map", true)
                            if Map and Map.ToggleSearchUI then
                                Map:ToggleSearchUI(v) 
                            end
                        end,
                    },
			  showMinimapButton = {
						type = "toggle",
						name = "Show Minimap Button",
						order = 7.1,
						desc = "Toggle the visibility of the LootCollector minimap button.",
						get = function() return not L.db.profile.minimapButtonHidden end,
						set = function(_, v)
							L.db.profile.minimapButtonHidden = not v
							local MMBtn = L:GetModule("MinimapButton", true)
							if MMBtn then
								if v then 
									MMBtn:Show() 
								else 
									MMBtn:Hide() 
								end
							end
						end,
					},
					disableProximityList = {
						type = "toggle",
						name = "Disable 'Nearby Discoveries'",
						order = 8,
						desc = "Completely disables the 'Nearby Discoveries' list from popping up when hovering over clustered map pins. (You can also hold CTRL to temporarily suppress it).",
						get = function() return L.db.profile.mapFilters.disableProximityList end,
						set = function(_, v)
							L.db.profile.mapFilters.disableProximityList = v
							if v then
								local PL = L:GetModule("ProximityList", true)
								if PL and PL.Hide then PL:Hide() end
							end
						end,
					},										
					toastHeader = {
						type = "header",
						name = "Toast Notifications",
						order = 10,
					},
					toastsEnabled = {
						type = "toggle",
						name = "Enable Toasts",
						order = 11,
						desc = "Show toast notifications for discoveries.",
						get = function()
							return L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.enabled
						end,
						set = function(_, v)
							if not L.db or not L.db.profile then return end
							L.db.profile.toasts = L.db.profile.toasts or {}
							L.db.profile.toasts.enabled = v
							local Toast = L:GetModule("Toast", true)
							if Toast and Toast.ApplySettings then
								Toast:ApplySettings()
							end
						end,
					},	
					toastOnlyNew = {
						type = "toggle",
						name = "Only Toast NEW Discoveries",
						order = 11.1,
						desc = "If enabled, only brand new pins will trigger a popup. Updates/Reinforcements to existing pins will be silent.",
						disabled = function()
							return not (L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.enabled)
						end,
						get = function()
							if L.db.profile.toasts.toastOnlyNew == nil then return true end 
							return L.db.profile.toasts.toastOnlyNew
						end,
						set = function(_, v)
							L.db.profile.toasts.toastOnlyNew = v
						end,
					},
					toastMinQuality = {
						type = "select",
						name = "Minimum Toast Quality",
						order = 11.2,
						desc = "Only show toasts for items of this quality or higher.",
						values = {
							[0] = "|cff9d9d9dPoor|r",
							[1] = "|cffffffffCommon|r",
							[2] = "|cff1eff00Uncommon|r",
							[3] = "|cff0070ddRare|r",
							[4] = "|cffa335eeEpic|r",
							[5] = "|cffff8000Legendary|r"
						},
						disabled = function()
							return not (L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.enabled)
						end,
						get = function()
							return L.db.profile.toasts.toastMinQuality or 2 
						end,
						set = function(_, v)
							L.db.profile.toasts.toastMinQuality = v
						end,
					},
					toastDisplayTime = {
						type = "range",
						name = "Toast Display Time",
						order = 12,
						min = 2.0,
						max = 10.0,
						step = 0.5,
						disabled = function()
							return not (L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.enabled)
						end,
						get = function()
							return L.db.profile.toasts.displayTime
						end,
						set = function(_, v)
							L.db.profile.toasts.displayTime = v
							local Toast = L:GetModule("Toast", true)
							if Toast and Toast.ApplySettings then
								Toast:ApplySettings()
							end
						end,
					},
					tickerEnabled = {
						type = "toggle",
						name = "Enable Special Ticker",
						order = 13,
						desc = "Use a scrolling ticker for high-volume discoveries.",
						disabled = function()
							return not (L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.enabled)
						end,
						get = function()
							return L.db.profile.toasts.tickerEnabled
						end,
						set = function(_, v)
							L.db.profile.toasts.tickerEnabled = v
							local Toast = L:GetModule("Toast", true)
							if Toast and Toast.ApplySettings then
								Toast:ApplySettings()
							end
						end,
					},
					tickerSpeed = {
						type = "range",
						name = "Ticker Scroll Speed",
						order = 14,
						min = 30,
						max = 150,
						step = 5,
						disabled = function()
							return not (L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.enabled and L.db.profile.toasts.tickerEnabled)
						end,
						get = function()
							return L.db.profile.toasts.tickerSpeed
						end,
						set = function(_, v)
							L.db.profile.toasts.tickerSpeed = v
							local Toast = L:GetModule("Toast", true)
							if Toast and Toast.ApplySettings then
								Toast:ApplySettings()
							end
						end,
					},
					tickerFontDelta = {
						type = "range",
						name = "Ticker Font Size Adjustment",
						order = 15,
						min = -2,
						max = 8,
						step = 1,
						disabled = function()
							return not (L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.enabled and L.db.profile.toasts.tickerEnabled)
						end,
						get = function()
							return L.db.profile.toasts.tickerFontDelta
						end,
						set = function(_, v)
							L.db.profile.toasts.tickerFontDelta = v
							local Toast = L:GetModule("Toast", true)
							if Toast and Toast.ApplySettings then
								Toast:ApplySettings()
							end
						end,
					},
					tickerOutline = {
						type = "toggle",
						name = "Ticker Font Outline",
						order = 16,
						disabled = function()
							return not (L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.enabled and L.db.profile.toasts.tickerEnabled)
						end,
						get = function()
							return L.db.profile.toasts.tickerOutline
						end,
						set = function(_, v)
							L.db.profile.toasts.tickerOutline = v
							local Toast = L:GetModule("Toast", true)
							if Toast and Toast.ApplySettings then
								Toast:ApplySettings()
							end
						end,
					},
					whiteFrame = {
						type = "toggle",
						name = "Bright Frame Border",
						order = 17,
						desc = "Use a bright white border for toast frames instead of dim gray.",
						disabled = function()
							return not (L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.enabled)
						end,
						get = function()
							return L.db.profile.toasts.whiteFrame
						end,
						set = function(_, v)
							L.db.profile.toasts.whiteFrame = v
							local Toast = L:GetModule("Toast", true)
							if Toast and Toast.ApplyFrameStyle then
								Toast:ApplyFrameStyle()
							end
						end,
					},
					resetToastPosition = {
						type = "execute",
						name = "Reset Toast Position",
						order = 18,
						desc = "Reset toast notifications to default position.",
						disabled = function()
							return not (L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.enabled)
						end,
						func = function()
							local Toast = L:GetModule("Toast", true)
							if Toast and Toast.ResetPosition then
								Toast:ResetPosition()
							end
						end,
					},
				},
			},

			viewerOptions = {
				type = "group",
				name = "Viewer Setup",
				inline = false,
				order = 15,
				args = {
					viewerDesc = {
						type = "description",
						name = "Customize the fonts and spacing for the Discovery Viewer.",
						order = 1,
					},
					rowFont = {
						type = "select",
						name = "List Font (Rows)",
						order = 2,
						values = {
							["Fonts\\ARIALN.TTF"] = "Arial Narrow",
							["Fonts\\FRIZQT__.TTF"] = "Friz Quadrata",
							["Fonts\\2002.TTF"] = "2022",
							["Fonts\\MORPHEUS.ttf"] = "Morpheus",
							["Fonts\\NIM_____.ttf"] = "Nimrod MT"
						},
						get = function() return L.db.profile.viewer.rowFont end,
						set = function(_, v) 
                            L.db.profile.viewer.rowFont = v
                            local Viewer = L:GetModule("Viewer", true)
                            if Viewer and Viewer.ApplySettings then Viewer:ApplySettings() end
                        end,
					},
					rowFontSize = {
						type = "range",
						name = "List Font Size",
						order = 3,
						min = 10, max = 22, step = 1,
						get = function() return L.db.profile.viewer.rowFontSize end,
						set = function(_, v) 
                            L.db.profile.viewer.rowFontSize = v
                            local Viewer = L:GetModule("Viewer", true)
                            if Viewer and Viewer.ApplySettings then Viewer:ApplySettings() end
                        end,
					},
					rowHeight = {
						type = "range",
						name = "Row Height",
						order = 4,
						min = 18, max = 48, step = 1,
						get = function() return L.db.profile.viewer.rowHeight end,
						set = function(_, v) 
                            L.db.profile.viewer.rowHeight = v
                            local Viewer = L:GetModule("Viewer", true)
                            if Viewer and Viewer.ApplySettings then Viewer:ApplySettings() end
                        end,
					},
					uiFont = {
						type = "select",
						name = "UI Font (Headers & Buttons)",
						order = 5,
						values = {
							["Fonts\\ARIALN.TTF"] = "Arial Narrow",
							["Fonts\\FRIZQT__.TTF"] = "Friz Quadrata",
							["Fonts\\2002.TTF"] = "2022",
							["Fonts\\MORPHEUS.ttf"] = "Morpheus",
							["Fonts\\NIM_____.ttf"] = "Nimrod MT"
						},
						get = function() return L.db.profile.viewer.uiFont end,
						set = function(_, v) 
                            L.db.profile.viewer.uiFont = v
                            local Viewer = L:GetModule("Viewer", true)
                            if Viewer and Viewer.ApplySettings then Viewer:ApplySettings() end
                        end,
					},
					uiFontSize = {
						type = "range",
						name = "UI Font Size",
						order = 6,
						min = 10, max = 22, step = 1,
						get = function() return L.db.profile.viewer.uiFontSize end,
						set = function(_, v) 
                            L.db.profile.viewer.uiFontSize = v
                            local Viewer = L:GetModule("Viewer", true)
                            if Viewer and Viewer.ApplySettings then Viewer:ApplySettings() end
                        end,
					},
					useWCAGColoring = {
						type = "toggle",
						name = "Use WCAG Discovery coloring",
						desc = "Adjusts Poor, Rare, and Epic item colors slightly to meet WCAG AA contrast compliance (4.5:1 ratio) on dark backgrounds.",
						order = 7,
						get = function() return L.db.profile.viewer.useWCAGColoring end,
						set = function(_, v) 
                            L.db.profile.viewer.useWCAGColoring = v
                            local Viewer = L:GetModule("Viewer", true)
                            if Viewer and Viewer.ApplySettings then Viewer:ApplySettings() end
                        end,
					},
					useInlineVendorView = {
						type = "toggle",
						name = "Use Inline Vendors Style",
						desc = "Reverts the Vendors tab to the old drop-down expansion style instead of the split view.",
						order = 8,
						get = function() return L.db.profile.viewer.inlineVendorView end,
						set = function(_, v) 
                            L.db.profile.viewer.inlineVendorView = v
                            local Viewer = L:GetModule("Viewer", true)
                            if Viewer then 
                                Viewer.expandedVendors = {} 
                                if Viewer.InvalidateFilterCache then Viewer:InvalidateFilterCache() end
                                if Viewer.ApplySettings then Viewer:ApplySettings() end
                                if Viewer.window and Viewer.window:IsShown() then Viewer:RefreshData() end
                            end
                        end,
					},
					
					asyncLoading = {
                        type = "toggle",
                        name = "Delay Viewer Data Loading",
                        desc = function()
                            local baseDesc = "Loads the Discoveries Viewer smoothly in the background over a few seconds to completely eliminate screen freezing, rather than locking the game for a split second."
                            
                            if not L.db.profile.viewer.asyncLoading and L._profilerStats then
                                local stats = L._profilerStats["Viewer:UpdateAllDiscoveries"]
                                if stats and stats.max and stats.max >= 100.0 then
                                    local timeSaved = math.floor(stats.max)
                                    return baseDesc .. string.format("\n\n|cffff7f00If you enable this feature it will eliminate a %dms screen freeze on your machine.|r", timeSaved)
                                end
                            end
                            return baseDesc
                        end,
                        order = 9,
                        get = function() return L.db.profile.viewer.asyncLoading end,
                        set = function(_, v) L.db.profile.viewer.asyncLoading = v end,
                    },
				},							
			},
			
			
			sharing = {
				type = "group",
				name = "Behavior & Sharing",
				inline = false,
				order = 20,
				args = {
					autoCache = {
						type = "toggle",
						name = "Automatically Cache Discoveries",
						order = 1,
						desc = "Fetch item info in background for unknown items.",
						get = function()
							return L.db.profile.autoCache
						end,
						set = function(_, v)
							L.db.profile.autoCache = v
							
							
							local queueSize = (L.db and L.db.global and L.db.global.cacheQueue and #L.db.global.cacheQueue) or 0
							
							
							if v then
								if queueSize > 0 then
									print(string.format("|cff00ff00LootCollector|r Automatic item caching is now |cff00ff00ENABLED|r. %d items in queue.", queueSize))
								else
									print("|cff00ff00LootCollector|r Automatic item caching is now |cff00ff00ENABLED|r. Queue is empty.")
								end
							else
								if queueSize > 0 then
									print(string.format("|cffff7f00LootCollector|r Automatic item caching is now |cffff0000DISABLED|r. %d items remain in queue.", queueSize))
								else
									print("|cffff7f00LootCollector|r Automatic item caching is now |cffff0000DISABLED|r.")
								end
							end
							
							
							local Core = L:GetModule("Core", true)
							if Core then
								if v then
									
									if Core.ScanDatabaseForUncachedItems then
										Core:ScanDatabaseForUncachedItems()
									end
									if Core.EnsureCachePump then
										Core:EnsureCachePump()
									end
								else
									
									
									if queueSize > 0 then
										print("|cffffff00LootCollector|r Item cache processing will stop after current item.")
									end
								end
							end
						end,
					},
					sharingHeader = {
						type = "header",
						name = "Sharing Controls",
						order = 9,
					},
					sharingEnabled = {
						type = "toggle",
						name = "Enable Sharing",
						order = 10,
						desc = "Broadcast discoveries to party/raid/guild and the public channel.|n|cFFFFA500Warning: this feature can cause stuttering on some machines even with high FPS.|r",
						get = function()
							return L.db and L.db.profile and L.db.profile.sharing and L.db.profile.sharing.enabled
						end,
						set = function(_, v)
							if not L.db or not L.db.profile then return end
							L.db.profile.sharing = L.db.profile.sharing or {}
							L.db.profile.sharing.enabled = v

							local Comm = L:GetModule("Comm", true)

							if v then
								
								print("|cff00ff00LootCollector:|r Sharing enabled.")
								if Comm then
									if L.channelReady then
										if Comm.EnsureChannelJoined then Comm:EnsureChannelJoined() end
									else
										print("|cffff7f00LootCollector:|r Sharing will be fully enabled after the initial login delay.")
									end
								end
							else
								
								if Comm and Comm.LeavePublicChannel then
									Comm:LeavePublicChannel()
								end

								local clearedBroadcasts = 0
								local Core = L:GetModule("Core", true)
								if Core and Core.pendingBroadcasts then
									for _ in pairs(Core.pendingBroadcasts) do clearedBroadcasts = clearedBroadcasts + 1 end
									wipe(Core.pendingBroadcasts)
								end

								if Comm and Comm._rateLimitQueue then
									clearedBroadcasts = clearedBroadcasts + #Comm._rateLimitQueue
									wipe(Comm._rateLimitQueue)
								end

								local clearedToasts = 0
								local Toast = L:GetModule("Toast", true)
								if Toast and Toast.ClearQueue then
									clearedToasts = Toast:ClearQueue()
								end

								print(string.format("|cffff7f00LootCollector:|r Sharing disabled. Cleared %d pending broadcasts and %d pending notifications.", clearedBroadcasts, clearedToasts))
							end
						end,
					},					
					namelessSharing = {
						type = "toggle",
						name = "Nameless Sharing",
						order = 11,
						desc = "Share discoveries anonymously.",
						disabled = function()
							return not L.db.profile.sharing.enabled
						end,
						get = function()
							return L.db and L.db.profile and L.db.profile.sharing and L.db.profile.sharing.anonymous
						end,
						set = function(_, v)
							if not L.db or not L.db.profile then return end
							L.db.profile.sharing = L.db.profile.sharing or {}
							L.db.profile.sharing.anonymous = (not not v)
						end,
					},
					delayedSharing = {
						type = "toggle",
						name = "Delayed Sharing",
						order = 12,
						desc = "Delay outgoing shares by a set number of seconds.",
						disabled = function()
							return not L.db.profile.sharing.enabled
						end,
						get = function()
							return L.db.profile.sharing.delayed
						end,
						set = function(_, v)
							L.db.profile.sharing.delayed = v
						end,
					},
					delaySlider = {
						type = "range",
						name = "Sharing Delay",
						order = 13,
						min = 15,
						max = 60,
						step = 1,
						disabled = function()
							return not L.db.profile.sharing.enabled or not L.db.profile.sharing.delayed
						end,
						get = function()
							return L.db.profile.sharing.delaySeconds
						end,
						set = function(_, v)
							L.db.profile.sharing.delaySeconds = v
						end,
					},
                    allowShowRequests = {
                        type = "toggle",
                        name = "Allow 'Show' Requests",
                        order = 14,
                        desc = "Allow other players to send you discovery locations to view on your map.",
                        disabled = function() return not L.db.profile.sharing.enabled end,
                        get = function() return L.db.profile.sharing.allowShowRequests end,
                        set = function(_, v) L.db.profile.sharing.allowShowRequests = v end,
                    },
			   
					  dataTypesHeader = {
								type = "header",
								name = "Data Types",
								order = 14.1,
							},
					disableMysticScrolls = {
								type = "toggle",
								name = "Disable Mystic Scrolls",
								desc = "If checked, Mystic Scroll discoveries will not be recorded, shared, or received from others.",
								order = 14.2,
								hidden = function() 
								    local Constants = L:GetModule("Constants", true)
								    return Constants and not Constants:HasMysticScrolls()
								end,
						get = function() return L.db.profile.disableMysticScrolls end,
						set = function(_, v) 
						    L.db.profile.disableMysticScrolls = v 
						    
						    local Constants = L:GetModule("Constants", true)
						    if Constants and Constants.UpdateAllowedTypes then
							  Constants:UpdateAllowedTypes()
						    end
						end,
					  },
					syncHeader = {
						type = "header",
						name = "Sync Restrictions",
						order = 19,
					},
					rejectPartySync = {
						type = "toggle",
						name = "Block Party/Raid Sync",
						order = 20,
						get = function()
							return L.db.profile.sharing.rejectPartySync
						end,
						set = function(_, v)
							L.db.profile.sharing.rejectPartySync = v
						end,
					},
					rejectGuildSync = {
						type = "toggle",
						name = "Block Guild Sync",
						order = 21,
						get = function()
							return L.db.profile.sharing.rejectGuildSync
						end,
						set = function(_, v)
							L.db.profile.sharing.rejectGuildSync = v
						end,
					},
					rejectWhisperSync = {
						type = "toggle",
						name = "Block Whisper Sync",
						order = 22,
						get = function()
							return L.db.profile.sharing.rejectWhisperSync
						end,
						set = function(_, v)
							L.db.profile.sharing.rejectWhisperSync = v
						end,
					},
					playerListsHeader = {
						type = "header",
						name = "Player Lists",
						order = 29,
					},
					blockList = {
						type = "input",
						multiline = 5,
						width = "full",
						order = 30,
						name = "Blocked Players",
						desc = "One player per line. Blocks messages sent from these players or discoveries originally found by them.",
						get = function()
							return listToString(L.db.profile.sharing.blockList)
						end,
						set = function(_, v)
							stringToList(v, L.db.profile.sharing.blockList)
                            
                            if L.SyncInvalidSendersWithBlockList then
                                L:SyncInvalidSendersWithBlockList()
                            end
						end,
					},
                    purgeGroup = {
                        type = "group",
                        name = "",
                        order = 30.1,
                        inline = true,
                        args = {
                            spacer = {
                                type = "description",
                                name = "",
                                width = "full",
                                order = 1,
                            },
                            purgeBlockedData = {
                                type = "execute",
                                name = "Purge Blocked Players Discoveries",
                                desc = "Removes all discoveries from your database where the original finder ('fp') is on your block list.",
                                order = 2,
                                func = function()
                                    local Core = L:GetModule("Core", true)
                                    if Core and Core.PurgeDiscoveriesFromBlockedPlayers then
                                        Core:PurgeDiscoveriesFromBlockedPlayers()
                                    else
                                        print("|cffff7f00LootCollector:|r Core module not available to perform purge.")
                                    end
                                end,
                            },
                        },
                    },
					whiteList = {
						type = "input",
						multiline = 5,
						width = "full",
						order = 31,
						name = "Whitelisted Players",
						desc = "If non-empty, only these players are accepted.",
						get = function()
							return listToString(L.db.profile.sharing.whiteList)
						end,
						set = function(_, v)
							stringToList(v, L.db.profile.sharing.whiteList)
						end,
					},
				},
			},
			
			realmOverridesHeader = {
						type = "header",
						name = "Realm Capability Overrides",
						order = 40,
					},
                    overrideDesc = {
                        type = "description",
                        name = "LootCollector automatically detects the Ascension Realm type to optimize UI and features. If detection fails, you can force the mode here.\n|cffff0000Requires a /reload to apply changes.|r",
                        order = 41,
                    },
			realmTypeOverride = {
						type = "select",
						name = "Active Realm Mode",
						order = 42,
						width = 1.6,
						values = {
                            ["AUTO"] = "Auto-Detect (Recommended)",
                            ["WR"] = "Warcraft Reborn (Bronzebeard) + Mystic Scrolls",
                            ["WILDCARD"] = "Wildcard (Elune)",
                            ["COA"] = "CoA (Vol'jin) - No Scrolls",
                            ["CLASSLESS"] = "Classless (A:25) - No Scrolls",
                        },
						get = function() return L.db.profile.featureOverrides.realmType end,
						set = function(_, v) 
						    if v == "COA" then
						        StaticPopup_Show("LOOTCOLLECTOR_COA_OVERRIDE_WARNING")
						    else
                                L.db.profile.featureOverrides.realmType = v
                                local Constants = L:GetModule("Constants", true)
                                if Constants and Constants.DetermineRealmCapabilities then
                                    Constants:DetermineRealmCapabilities()
                                    Constants:UpdateAllowedTypes()
                                end
                                print("|cff00ff00LootCollector:|r Realm mode manually set to " .. v .. ".")
                                
                                StaticPopup_Show("LOOTCOLLECTOR_REALM_OVERRIDE_RELOAD")
						    end
						end,
					},      
            about = {
                type = "group",
                name = "About",
                order = 99,
                args = {
                    intro_text = {
                        type = "description",
                        name = "Hi there!\n\nI'm Skulltrail, and I'm happy to present LootCollector—my first-ever WoW addon!\n\nA huge thank you to all the contributors for their hard work and support. This addon wouldn't be possible without your help!\nSpecial thanks to: |cffFFD700Deidre, Rhenyra, Morty, Markosz, Bandit Tech, xan, Stilnight, Xurkon, Netherborne, Liakate|r, and all the community helpers out there.\n\nI would also like to extend a special thank you to |cffFFD700@ERitzman|r for being our first-ever LootCollector sponsor!\n\nContact: Discord @Skulltrail!",
                        fontSize = "large",
                        order = 10,
                    },
                    donations_desc = {
                        type = "description",
                        name = "\nFor those who'd like to support development, sponsorships are welcome at:",
                        fontSize = "medium",
                        order = 41,
                    },
                    github_button = {
                        type = "execute",
                        name = "• GitHub Sponsors",
                        order = 43,
                        func = function()
                            OpenCopyPopup("GitHub Sponsors", "https://github.com/sponsors/mmobrain")
                        end,
                    },
                    ingame_mail_desc = {
                        type = "description",
                        name = "• In-game mailbox ;)",
                        fontSize = "medium",
                        order = 44,
                    },
                }
            },
		},
	}
	return opts
end

function Settings:OnInitialize()
	
	
	local function showLegacyMessage()
		print("|cffff0000LootCollector is in Legacy Mode!|r")
		print("|cffffff00Your database is from an older version and needs to be updated.|r")
		print("  - Type |cff00ff00/lcpreserve|r to migrate your data now.")
		print("  - Type |cffff7f00/reload|r to see the migration pop-up again.")
	end

	if L.LEGACY_MODE_ACTIVE then
		
		self:RegisterChatCommand("lc", showLegacyMessage)
		self:RegisterChatCommand("lootcollector", showLegacyMessage)
		SLASH_LCLIST1 = "/lclist"
		SlashCmdList["LCLIST"] = showLegacyMessage
		return 
	end

	
	if not L.db and L.db.profile then return end
	ensureDefaults()

	if AceConfig and AceConfigDialog then
		AceConfig:RegisterOptionsTable("LootCollector", buildOptions)
		AceConfigDialog:AddToBlizOptions("LootCollector", "LootCollector")

		local function openOptions(tab)
			InterfaceOptionsFrame_OpenToCategory("LootCollector")
			if tab == "discoveries" then
				InterfaceOptionsFrame_OpenToCategory("Discoveries")
			end
		end

		self:RegisterChatCommand("lc", function(input)
			local tab = input:match("%S+")
			openOptions(tab)
		end)
		self:RegisterChatCommand("lootcollector", function(input)
			local tab = input:match("%S+")
			openOptions(tab)
		end)
	else
		
		SLASH_LootCollectorCFG1 = "/lc"
		SlashCmdList["LootCollectorCFG"] = function(msg)
			msg = msg or ""
			local cmd, val = msg:match("(%S+)%s*(%S*)")
			cmd = (cmd or ""):lower()
			local on = not (val == "0" or val == "off" or val == "false")
			if cmd == "sharing" then
				L.db.profile.sharing.enabled = on
				print(string.format("|cff00ff00LootCollector|r sharing.enabled=%s", tostring(on)))
				local Comm = L:GetModule("Comm", true)
				if Comm then
					if on then
						Comm:JoinPublicChannel(true)
					else
						Comm:LeavePublicChannel()
					end
				end
			elseif cmd == "toasts" or cmd == "hideall" or cmd == "hidefaded" or cmd == "hidestale" or cmd == "hidelooted" then
				local setting = (cmd == "toasts" and "toasts" or "mapFilters")
				local key = (cmd == "toasts" and "enabled" or cmd)
				L.db.profile[setting][key] = on
				print(string.format("|cff00ff00LootCollector|r %s.%s=%s", setting, key, tostring(on)))
				refreshUI()
			else
				print("|cff00ff00LootCollector|r /lc sharing on|off, toasts on/off, hideall on/off, etc.")
			end
		end
	end

	SLASH_LootCollectorTOP1 = "/lctop"
	SlashCmdList["LootCollectorTOP"] = ShowTopContributors
end

return Settings