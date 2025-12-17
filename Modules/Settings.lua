

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
    
    
    p.mapFilters = p.mapFilters or {}
    if p.mapFilters.showMapFilter == nil then p.mapFilters.showMapFilter = true end
    if p.mapFilters.showMinimap == nil then p.mapFilters.showMinimap = true end
    if p.mapFilters.autoTrackNearest == nil then p.mapFilters.autoTrackNearest = false end
    if p.mapFilters.maxMinimapDistance == nil then p.mapFilters.maxMinimapDistance = 0 end 
end

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
					hideAll = {
						type = "toggle",
						name = "Hide All",
						order = 1,
						get = function() return L.db.profile.mapFilters.hideAll end,
						set = function(_, v)
							L.db.profile.mapFilters.hideAll = v
							refreshUI()
						end,
					},
					hideFaded = {
						type = "toggle",
						name = "Hide Faded",
						order = 2,
						get = function() return L.db.profile.mapFilters.hideFaded end,
						set = function(_, v)
							L.db.profile.mapFilters.hideFaded = v
							refreshUI()
						end,
					},
					hideStale = {
						type = "toggle",
						name = "Hide Stale",
						order = 3,
						get = function() return L.db.profile.mapFilters.hideStale end,
						set = function(_, v)
							L.db.profile.mapFilters.hideStale = v
							refreshUI()
						end,
					},
					hideLooted = {
						type = "toggle",
						name = "Hide Looted",
						order = 4,
						desc = "Hide discoveries already looted by this character.",
						get = function() return L.db.profile.mapFilters.hideLooted end,
						set = function(_, v)
							L.db.profile.mapFilters.hideLooted = v
							refreshUI()
						end,
					},
					hidePlayerNames = {
						type = "toggle",
						name = "Hide Player Names",
						order = 4.5, 
						desc = "Replaces finder names in toasts and map tooltips with a generic message.",
						get = function()
							return L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.hidePlayerNames
						end,
						set = function(_, v)
							if not L.db or not L.db.profile then return end
							L.db.profile.toasts = L.db.profile.toasts or {}
							L.db.profile.toasts.hidePlayerNames = v
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
                        get = function() return L.db.profile.mapFilters.autoTrackNearest end,
                        set = function(_, v)
                            L.db.profile.mapFilters.autoTrackNearest = v
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
						desc = "Broadcast discoveries to party/raid/guild and the public channel.",
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
                                name = "Purge Blocked Players Data",
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

            
            about = {
                type = "group",
                name = "About",
                order = 99,
                args = {
                    intro_text = {
                        type = "description",
                        name = "Hi there! \n\nI'm Skulltrail, and I'm thrilled to present LootCollector - my first-ever WoW addon! \n\nA huge shoutout to all the amazing contributors for their incredible help and hard work. This addon wouldn't be what it is today without you! \nBig thanks to: |cffFFD700Deidre, Rhenyra, Morty, Markosz, Bandit Tech|r, and all the awesome community helpers out there.\n\nIf you'd like to support me, I'd love to hear what you enjoy about LootCollector or any ideas for improvement. Feel free to drop me a message on Discord @Skulltrail!",
                        fontSize = "large",
                        order = 10,
                    },
                    donations_desc = {
                        type = "description",
                        name = "\nFor those who'd like to support development, donations are welcome at:",
                        fontSize = "medium",
                        order = 41,
                    },
                    ingame_mail_desc = {
                        type = "description",
                        name = "• In-game mailbox ;)",
                        fontSize = "medium",
                        order = 42,
                    },
                    usdt_button = {
                        type = "execute",
                        name = "• USDT/USDC: 0xe24cAd648ce24cAd648ce24cAd648casd",
                        order = 43,
                        func = function()
                            OpenCopyPopup("USDT/USDC Address", "0xe24cAd648ce24cAd648ce24cAd648casd\nThanks for making it here - that already means a lot. If this helped you and you're the kind of person who keeps good tools alive, even a small tip today keeps it running tomorrow.")
                        end,
                    },
                    btc_button = {
                        type = "execute",
                        name = "• BTC: bc1qte860ljxkqte860ljxkqte860ljxkasw",
                        order = 44,
                        func = function()
                            OpenCopyPopup("BTC Address", "bc1qte860ljxkqte860ljxkqte860ljxkasw\nThanks for making it here - that already means a lot. If this helped you and you're the kind of person who keeps good tools alive, even a small tip today keeps it running tomorrow.")
                        end,
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
