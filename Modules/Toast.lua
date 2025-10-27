-- Toast.lua
-- Displays toast notifications with a buffered queue, "anonymous" batching, and a ticker overflow for heavy load (3.3.5a-safe).
-- Session-based special ticker with smoothing/fades, font controls, and correct routing (normal first, special only after threshold).
-- UNK.B64.UTF-8


local L = LootCollector
local Toast = L:NewModule("Toast")

local TOASTWIDTH, TOASTHEIGHT = 390, 52
local TICKERHEIGHT = 30
local VERTICALSPACING = 8

local TOASTDISPLAYTIME = 5.0
local TOASTFADEIN = 0.4
local TOASTFADEOUT = 1.0

local DELAYMIN, DELAYMAX = 1.0, 5.0

local MAXQUEUEBEFORETICKER = 7

local ANONGATHERTIME = 2.5
local ANONMIN, ANONMAX = 2, 3

local MAXCONCURRENTTOASTSNORMAL = 2
local MAXCONCURRENTTOASTSWITHTICKER = 1

local TICKERSPEED = 32 
local TICKERSTARTPADDING = 30 

local TICKERMINMERGED = 3
local TICKERSEPARATOR = " • "
local TICKERGAP = 4

local TICKERSINGLEPASSFROMHALF = true
local TICKERFIRSTBUILDDELAY = 0.30

local TICKEREASEIN = 0.25
local TICKERDTEMAALPHA = 0.25
local TICKERDTCLAMP = 0.05

local TICKERFADEMASKS = true
local TICKERFADESIZE = 18
local TICKERFADEALPHA = 0.85

local TICKERFONTDELTA = 3 
local TICKERFONTFLAGS = "OUTLINE" 

local SPAMCHECKQUEUEMIN = 15 
local DISCSPAMCOUNTTHRESHOLD = 3 
local DISCSPAMTIMEWINDOW = 60 
local CONFSPAMCOUNTTHRESHOLD = 6 
local CONFSPAMDURATION = 900 

local spamState = {
	blocked = {}, 
	counts = {}, 
	confSuppressed = {}, 
	lastViolationEpoch = {}, 
	scanEpoch = 0, 
	queueTrimEvents = 0, 
}

Toast.displayTime = TOASTDISPLAYTIME
Toast.tickerEnabled = true
Toast.tickerSpeed = TICKERSPEED
Toast.tickerFontDelta = TICKERFONTDELTA
Toast.tickerOutline = false

local toastContainer
local toasts = {}
local queue = {}
local anonBuffer = {}
local anonWindowEnds = nil
local lastScheduledAt = 0
local overflowActive = false
local dispatcher
local bottomMostToast

local ticker = {
	frame = nil,
	scrollContainer = nil,
	child = nil,
	text = nil,
	messages = {},
	active = false,
	textX = 0.0,
	ready = false,
	
	sessionBuilt = false,
	coalesceUntil = 0.0,
	sessionLines = {},
	
	dtEMA = nil,
	easeT = 0.0,
	
	fadeL = nil,
	fadeR = nil,
	
	baseFontSize = nil,
}

local function defaultAnchor()
	local chat = _G.ChatFrame1 or UIParent
	return "BOTTOMLEFT", chat, "TOPLEFT", 0, 80
end

local function getDiscoveryTimestamp(d, fallback)
	
	return (d and (d.t or d.t0 or d.time or d.ts)) or fallback or GetTime()
end

local function ensureProfile()
	if not L.db and L.db.profile then return end
	L.db.profile.toasts = L.db.profile.toasts or {}
	local T = L.db.profile.toasts
	if T.enabled == nil then T.enabled = true end
	if T.hidePlayerNames == nil then T.hidePlayerNames = false end
	if T.displayTime == nil then T.displayTime = TOASTDISPLAYTIME end
	if T.tickerEnabled == nil then T.tickerEnabled = true end
	if T.tickerSpeed == nil then T.tickerSpeed = TICKERSPEED end
	if T.tickerFontDelta == nil then T.tickerFontDelta = TICKERFONTDELTA end
	if T.tickerOutline == nil then T.tickerOutline = false end
	if T.whiteFrame == nil then T.whiteFrame = true end
end

local function saveContainerPosition(f)
	ensureProfile()
	if not L.db and L.db.profile and L.db.profile.toasts then return end
	local point, rel, relPoint, x, y = f:GetPoint()
	L.db.profile.toasts.position = {
		point = point or "BOTTOMLEFT",
		rel = (rel and rel:GetName()) or "UIParent",
		relPoint = relPoint or "BOTTOMLEFT",
		x = x or 0,
		y = y or 0,
	}
end

local function restoreContainerPosition(f)
	ensureProfile()
	local pos = L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.position
	local relFrame = (pos and pos.rel and _G[pos.rel]) or nil
	if pos and pos.point and relFrame and pos.relPoint then
		f:ClearAllPoints()
		f:SetPoint(pos.point, relFrame, pos.relPoint, pos.x or 0, pos.y or 0)
	else
		local p, r, rp, x, y = defaultAnchor()
		f:ClearAllPoints()
		f:SetPoint(p, r, rp, x, y)
	end
end

local function anyShown()
	for _, t in ipairs(toasts) do
		if t:IsShown() then return true end
	end
	return false
end

local function visibleCount()
	local n = 0
	for _, t in ipairs(toasts) do
		if t:IsShown() then n = n + 1 end
	end
	return n
end

function Toast:ApplyFrameStyle()
	local on = L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.whiteFrame
	local r, g, b, a = 1, 1, 1, (on and 1 or 0.15)
	
	if toasts then
		for _, t in ipairs(toasts) do
			if t and t.SetBackdropBorderColor then
				t:SetBackdropBorderColor(r, g, b, a)
			end
		end
	end
	
	if ticker and ticker.frame and ticker.frame.SetBackdropBorderColor then
		ticker.frame:SetBackdropBorderColor(r, g, b, a)
	end
end

local function normalBacklogSize()
	
	return visibleCount() + #queue + #anonBuffer
end

local function getQualityColor(q)
	q = tonumber(q) or 1
	if GetItemQualityColor then
		local r, g, b = GetItemQualityColor(q)
		if r and g and b then return r, g, b end
	end
	if _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q] then
		local c = _G.ITEM_QUALITY_COLORS[q]
		return c.r or 1, c.g or 1, c.b or 1
	end
	return 1, 1, 1
end

function Toast:ShowSpecialMessage(iconTexture, titleText, subtitleText)
    if not (L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.enabled) then
		return
	end
	if not toastContainer then return end

    -- This function is for trusted, local-only messages.
    -- It does not use the queue and displays immediately.

    local f = self:acquireToast()

    f.text.discoveryData = nil -- No discovery data associated with this
	f.icon:SetTexture(iconTexture or "Interface\\Icons\\INV_Misc_Book_09")
    f.text.fontString:SetText(titleText or "LootCollector Notification")
	f.subtext:SetText(subtitleText or "")

	if not toastContainer:IsShown() then
		toastContainer:Show()
	end
	f:SetAlpha(0.0)
	f.startTime = GetTime()
	f:Show()
	self:_layoutStacks()
	f:SetScript("OnUpdate", function(self)
		local dt = GetTime() - (self.startTime or 0)
		if dt < TOASTFADEIN then
			self:SetAlpha(dt / TOASTFADEIN)
		elseif dt < TOASTFADEIN + Toast.displayTime then
			self:SetAlpha(1.0)
		elseif dt < TOASTFADEIN + Toast.displayTime + TOASTFADEOUT then
			local fade = (dt - (TOASTFADEIN + Toast.displayTime)) / TOASTFADEOUT
			self:SetAlpha(1.0 - fade)
			if fade >= 1.0 then
				self:SetScript("OnUpdate", nil)
				self:Hide()
				Toast:_layoutStacks()
				if not anyShown() and not ticker.active then
					toastContainer:Hide()
				end
			end
		else
			self:SetScript("OnUpdate", nil)
			self:Hide()
			Toast:_layoutStacks()
			if not anyShown() and not ticker.active then
				toastContainer:Hide()
			end
		end
	end)
end

local function makeItemDisplay(d)
	local name, quality, texture
    local itemID = d.i
    local itemLink = d.il

	if itemLink then
		local n, _, q, _, _, _, _, _, _, tex = GetItemInfo(itemLink)
        name = n
        quality = q
        texture = tex
        if not itemID then itemID = tonumber((itemLink:match("item:(%d+)"))) end
	elseif itemID then
		local n, lnk, q, _, _, _, _, _, _, tex = GetItemInfo(itemID)
        name = n
        itemLink = lnk
        quality = q
        texture = tex
	end

	name = name or d.itemName or "an item"
	quality = quality or d.itemQuality or d.q or 1
	texture = texture or d.texture or "Interface\\Icons\\INV_Misc_QuestionMark"

	local display
	if itemLink and itemLink:find("|Hitem:") then
		display = itemLink
	elseif itemID then
		local r, g, b = getQualityColor(quality)
		local hex = string.format("ff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
		display = string.format("|c%s|Hitem:%d:0:0:0:0:0:0:0:0|h[%s]|h|r", hex, itemID, name)
	else
		
		local r, g, b = getQualityColor(quality)
		local hex = string.format("ff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
		display = string.format("|cff%s[%s]|r", hex, name)
	end
    
    
    
    d.il = display

	return display, texture
end

local function makeTickerLineFromDiscovery(d, options)
	options = options or {}
	local itemDisplay, _ = makeItemDisplay(d)
	local finder = d.fp or "Unknown"
	local zoneName = d.zoneNameOverride
	if not zoneName then
		
		zoneName = L.ResolveZoneDisplay(d.c, d.z, d.iz) or "an unknown zone"
	end
	if options.isLateDiscovery then
		zoneName = zoneName .. " (away)" 
	end

    if L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.hidePlayerNames then
        return string.format("%s in %s!", itemDisplay, tostring(zoneName))
    else
	    return string.format("%s in %s found by %s!", itemDisplay, tostring(zoneName), tostring(finder))
    end
end

local function checkQueueForSpam()
	if L.ANTISPAMDISABLED then return end
	if #queue < SPAMCHECKQUEUEMIN then return end
	spamState.scanEpoch = (spamState.scanEpoch or 0) + 1
	local tnow = GetTime()
	
	local byName = {}
	for _, entry in ipairs(queue) do
		local d = entry.data
		local op = entry.options and entry.options.op or "DISC"
		local name = d and d.fp
		if name and name ~= "An Unnamed Collector" then
			byName[name] = byName[name] or { disctimes = {}, confcount = 0 }
			if op == "DISC" then
				local ts = getDiscoveryTimestamp(d)
				table.insert(byName[name].disctimes, ts)
			elseif op == "CONF" then
				byName[name].confcount = byName[name].confcount + 1
			end
		end
	end
	
	for name, data in pairs(byName) do
		
		if not spamState.blocked[name] and #data.disctimes >= DISCSPAMCOUNTTHRESHOLD then
			table.sort(data.disctimes)
			local span = data.disctimes[#data.disctimes] - data.disctimes[1]
			if span <= DISCSPAMTIMEWINDOW then
				
				local lastEpoch = spamState.lastViolationEpoch[name]
				if lastEpoch ~= spamState.scanEpoch then
					spamState.counts[name] = (spamState.counts[name] or 0) + 1
					spamState.lastViolationEpoch[name] = spamState.scanEpoch
					if spamState.counts[name] >= 2 then
						
						spamState.blocked[name] = true
						LootCollector:Print(string.format("|cffff0000[SPAM ALERT]|r Permanently suppressing toasts from %s (Excessive DISC spam).", name))
					end
				end
			end
		end
		
		if data.confcount >= CONFSPAMCOUNTTHRESHOLD and tnow >= (spamState.confSuppressed[name] or 0) then
			
			spamState.confSuppressed[name] = tnow + CONFSPAMDURATION
			LootCollector:Print(string.format("|cffffff00[SPAM ALERT]|r Temporarily suppressing CONF toasts from %s for %d minutes (Excessive reinforcements).", name, CONFSPAMDURATION/60))
			
			local specialMessage = string.format("|cff00ff00%s|r found many more. Check your map!", name)
			Toast:AddSpecialLine(specialMessage)
		end
	end
	
	local newQueue = {}
	for _, entry in ipairs(queue) do
		local d = entry.data
		local op = entry.options and entry.options.op or "DISC"
		local name = d and d.fp
		local isAnonymous = (name == "An Unnamed Collector")
		if isAnonymous or not name then
			
			table.insert(newQueue, entry)
		elseif spamState.blocked[name] then
			
			if op == "DISC" then
				
			else
				
				table.insert(newQueue, entry)
			end
		elseif op == "CONF" and tnow < (spamState.confSuppressed[name] or 0) then
			
			
		else
			
			table.insert(newQueue, entry)
		end
	end
	queue = newQueue
end

local function removeFirstNFromQueue(n)
	n = math.min(n or 0, #queue)
	if n <= 0 then return end
	for i = 1, n do
		table.remove(queue, 1)
	end
end

local function maybeTrimQueue()
	if L.ANTISPAMDISABLED then return end
	local threshold = (spamState.queueTrimEvents >= 3 and 20 or 30)
	if #queue >= threshold then
		removeFirstNFromQueue(10)
		spamState.queueTrimEvents = (spamState.queueTrimEvents or 0) + 1
	end
end

function Toast:ApplySettings()
	ensureProfile()
	local T = L.db.profile.toasts
	self.displayTime = tonumber(T.displayTime) or TOASTDISPLAYTIME
	self.tickerEnabled = (T.tickerEnabled ~= false)
	self.tickerSpeed = tonumber(T.tickerSpeed) or TICKERSPEED
	self.tickerFontDelta = tonumber(T.tickerFontDelta) or TICKERFONTDELTA
	self.tickerOutline = (T.tickerOutline == true)
	
	if ticker and ticker.text then
		local fnt, curSize = ticker.text:GetFont()
		if not ticker.baseFontSize then
			local _, bs = ticker.text:GetFont()
			ticker.baseFontSize = bs or 10
		end
		local flags = (self.tickerOutline and TICKERFONTFLAGS or "")
		ticker.text:SetFont(fnt, ticker.baseFontSize + self.tickerFontDelta, flags)
		if ticker.child then
			local sh = ticker.child:GetHeight() or (TICKERHEIGHT - 8)
			ticker.text:SetHeight(sh)
			ticker.text:SetJustifyV("MIDDLE")
		end
	end
	if self.ApplyFrameStyle then
		self:ApplyFrameStyle()
	end
end

function Toast:acquireToast()
	for _, t in ipairs(toasts) do
		if not t:IsShown() then return t end
	end
	local f = CreateFrame("Frame", nil, toastContainer)
	f:SetSize(TOASTWIDTH, TOASTHEIGHT)
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetBackdropColor(0, 0, 0, 0.90)
	do
		local on = L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.whiteFrame
		if f.SetBackdropBorderColor then
			f:SetBackdropBorderColor(1, 1, 1, on and 1 or 0.15)
		end
	end
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(38, 38)
	f.icon:SetPoint("LEFT", 8, 0)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", 0, 0)
	f.close:SetScale(0.8)
	f.close:SetScript("OnClick", function(btn)
		local parent = btn:GetParent()
		parent:Hide()
		parent:SetScript("OnUpdate", nil)
        Toast:_layoutStacks()
		if not anyShown() and not ticker.active then
			toastContainer:Hide()
		end
	end)
	
	f.text = CreateFrame("Button", nil, f)
	f.text:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -6)
	f.text:SetPoint("RIGHT", f.close, "LEFT", -8, 0)
    f.text:SetHeight(20) 

    f.text.fontString = f.text:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text.fontString:SetAllPoints(f.text)
    f.text.fontString:SetJustifyH("LEFT")

	f.subtext = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.subtext:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -2)
	f.subtext:SetPoint("RIGHT", f.text, "RIGHT")
	f.subtext:SetJustifyH("LEFT")
	f.subtext:SetTextColor(0.85, 0.85, 0.85)
	
    
    f.text:SetScript("OnEnter", function(self)
        if self.discoveryData and self.discoveryData.il and self.discoveryData.il:find("|Hitem:") then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.discoveryData.il)
            GameTooltip:Show()
        end
    end)
    f.text:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    f.text:SetScript("OnClick", function(self, button)
        if IsShiftKeyDown() then
            if self.discoveryData then
                
                local Map = L:GetModule("Map", true)
                if Map and Map.FocusOnDiscovery then
                    Map:FocusOnDiscovery(self.discoveryData)
                end
            end
        else
            if self.discoveryData and self.discoveryData.il and self.discoveryData.il:find("|Hitem:") then
                SetItemRef(self.discoveryData.il, self.discoveryData.il, button)
            end
        end
    end)

	
	do
		local fnt, size, flags = f.text.fontString:GetFont() 
		f.text.fontString:SetFont(fnt, (size or 12) + 2, flags or "")
		f.text.fontString:SetShadowOffset(1, -1)
		f.text.fontString:SetShadowColor(0, 0, 0, 0.8)
	end

	do
		local fnt, size, flags = f.subtext:GetFont()
		f.subtext:SetFont(fnt, (size or 10) + 1, flags or "")
	end
	f:Hide()
	table.insert(toasts, f)
	return f
end

function Toast:_layoutStacks()
	local visibles = {}
	for _, f in ipairs(toasts) do
		if f:IsShown() then table.insert(visibles, f) end
	end
	if #visibles == 0 then
		bottomMostToast = nil
	else
		table.sort(visibles, function(a, b) return (a.startTime or 0) < (b.startTime or 0) end)
		local last = visibles[1]
		last:ClearAllPoints()
		last:SetPoint("TOP", toastContainer, "TOP", 0, 0)
		for i = 2, #visibles do
			local cur = visibles[i]
			cur:ClearAllPoints()
			cur:SetPoint("TOP", last, "BOTTOM", 0, -VERTICALSPACING)
			last = cur
		end
		bottomMostToast = last
	end
	local n = #visibles
	local neededHeight = (n > 0 and n * TOASTHEIGHT + (n - 1) * VERTICALSPACING or TOASTHEIGHT)
	toastContainer:SetHeight(neededHeight)
end

local function renderToast(d, options)
	options = options or {}
	ensureProfile()
	if not (L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.enabled) then
		return
	end
	if not toastContainer then return end
	local itemDisplay, icon = makeItemDisplay(d)
	local f = Toast:acquireToast()

    f.text.discoveryData = d 
	f.icon:SetTexture(icon)

    if d.isSpecialMessage then
        f.text.fontString:SetText(itemDisplay)
        f.subtext:SetText(d.zoneNameOverride or "")
    else
        local zoneName = d.zoneNameOverride
        if not zoneName then
            zoneName = L.ResolveZoneDisplay(d.c, d.z, d.iz) or "an unknown zone"
        end
        if options.isLateDiscovery then
            zoneName = zoneName .. " (while you were away)"
        end
        
        if L.db.profile.toasts.hidePlayerNames then
            f.text.fontString:SetFormattedText("%s was spotted!", itemDisplay)
        else
            f.text.fontString:SetFormattedText("%s found %s!", d.fp or "Unknown", itemDisplay)
        end

        f.subtext:SetText("in " .. tostring(zoneName))
    end
	
	if not toastContainer:IsShown() then
		toastContainer:Show()
	end
	f:SetAlpha(0.0)
	f.startTime = GetTime()
	f:Show()
	Toast:_layoutStacks()
	f:SetScript("OnUpdate", function(self)
		local dt = GetTime() - (self.startTime or 0)
		if dt < TOASTFADEIN then
			self:SetAlpha(dt / TOASTFADEIN)
		elseif dt < TOASTFADEIN + Toast.displayTime then
			self:SetAlpha(1.0)
		elseif dt < TOASTFADEIN + Toast.displayTime + TOASTFADEOUT then
			local fade = (dt - (TOASTFADEIN + Toast.displayTime)) / TOASTFADEOUT
			self:SetAlpha(1.0 - fade)
			if fade >= 1.0 then
				self:SetScript("OnUpdate", nil)
				self:Hide()
				Toast:_layoutStacks()
				if not anyShown() and not ticker.active then
					toastContainer:Hide()
				end
			end
		else
			self:SetScript("OnUpdate", nil)
			self:Hide()
			Toast:_layoutStacks()
			if not anyShown() and not ticker.active then
				toastContainer:Hide()
			end
		end
	end)
end

local function tickerEnsureChildSize()
	if not ticker.scrollContainer or not ticker.child then return end
	local sw = ticker.scrollContainer:GetWidth() or 0
	local sh = ticker.scrollContainer:GetHeight() or (TICKERHEIGHT - 8)
	if sw <= 0 or sh <= 0 then
		ticker.ready = false
		return
	end
	ticker.child:SetWidth(sw)
	ticker.child:SetHeight(sh)
	ticker.ready = true
	if ticker.text then
		ticker.text:SetHeight(sh)
		ticker.text:SetJustifyV("MIDDLE")
	end
end

local function tickerReposition()
	if not ticker.text or not ticker.child then return end
	ticker.text:ClearAllPoints()
	ticker.text:SetPoint("LEFT", ticker.child, "LEFT", ticker.textX or 0, 0)
end

local function takeFromQueueForSession(parts, wantMore)
	
	while wantMore > 0 and #queue > 0 do
		local e = table.remove(queue)
		if e and e.data then
			table.insert(parts, makeTickerLineFromDiscovery(e.data, e.options))
			wantMore = wantMore - 1
		end
	end
	return wantMore
end

local function tickerBuildSessionLine()
	tickerEnsureChildSize()
	if not ticker.ready then
		ticker.text:SetText("")
		ticker.textX = 0.0
		return
	end
	local pendingTicker = #ticker.messages
	local pendingQueue = #queue
	local totalPending = pendingTicker + pendingQueue
	local sessionCount
	if TICKERSINGLEPASSFROMHALF then
		sessionCount = math.max(TICKERMINMERGED, math.floor(totalPending / 2))
	else
		sessionCount = math.max(TICKERMINMERGED, pendingTicker)
	end
	local parts = {}
	for i = 1, math.min(pendingTicker, sessionCount) do
		parts[#parts + 1] = ticker.messages[i]
	end
	if TICKERSINGLEPASSFROMHALF and #parts < sessionCount then
		takeFromQueueForSession(parts, sessionCount - #parts)
	end
	if #parts == 0 and pendingTicker > 0 then
		parts[#parts + 1] = ticker.messages[1]
	end
	ticker.sessionLines = parts
	ticker.messages = {}
	ticker.sessionBuilt = true
	local merged = table.concat(parts, TICKERSEPARATOR)
	ticker.text:SetText(merged)
	local sw = ticker.scrollContainer:GetWidth() or 0
	ticker.textX = sw + TICKERSTARTPADDING
	ticker.dtEMA = nil
	ticker.easeT = 0.0
	tickerReposition()
end

local function tickerAdvanceSession()
	ticker.sessionLines = {}
	ticker.sessionBuilt = false
	ticker.active = false
	if ticker.fadeL then ticker.fadeL:Hide() end
	if ticker.fadeR then ticker.fadeR:Hide() end
	ticker.frame:Hide()
	if not anyShown() then
		toastContainer:Hide()
	end
end

local function addToTicker(d, options)
	local pname = d and (d.fp or d.playerName or d.finder)
	if pname and spamState.blocked[pname] then return end
	local line = makeTickerLineFromDiscovery(d, options)
	table.insert(ticker.messages, line)
	if not ticker.active then
		ticker.active = true
		ticker.frame:Show()
		ticker.coalesceUntil = GetTime() + TICKERFIRSTBUILDDELAY
		ticker.sessionBuilt = false
		if ticker.fadeL then ticker.fadeL:Show() end
		if ticker.fadeR then ticker.fadeR:Show() end
	end
end

local function enqueueToast(d, options)
	local now = GetTime()
	local base = math.max(lastScheduledAt, now)
	local jitter = math.random() * (DELAYMAX - DELAYMIN) + DELAYMIN
	local when = base + jitter
	table.insert(queue, { data = d, fireAt = when, options = options })
	maybeTrimQueue()
	checkQueueForSpam()
end

local function shuffleRange(list, startIdx, endIdx)
	for i = endIdx, startIdx + 1, -1 do
		local j = math.random(startIdx, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function processAnonWindow()
	if not anonWindowEnds then return end
	if GetTime() < anonWindowEnds then return end
	anonWindowEnds = nil
	if #anonBuffer == 0 then return end
	local take = math.min(#anonBuffer, math.random(ANONMIN, ANONMAX))
	shuffleRange(anonBuffer, 1, take)
	for i = 1, take do
		local entry = anonBuffer[i]
		if entry then
			enqueueToast(entry.data, entry.options)
		end
	end
	if take < #anonBuffer then
		for i = 1, #anonBuffer - take do
			anonBuffer[i] = anonBuffer[i + take]
		end
		for i = #anonBuffer - take + 1, #anonBuffer do
			anonBuffer[i] = nil
		end
		anonWindowEnds = GetTime() + 1.2
	else
		for i = #anonBuffer, 1, -1 do
			anonBuffer[i] = nil
		end
	end
end

function Toast:Show(discoveryData, force, options)
	
	local Dev = L:GetModule("DevCommands", true)
	if Dev and Dev.LogMessage then
		options = options or {}
		
		local opstr = options.op or (options.isLateDiscovery and "CONF" or "DISC")
		local datastr = nil
		if discoveryData then
			
			datastr = string.format("{i=%s, c=%s, z=%s, iz=%s, q=%s, fp=%s, il=%s}",
				tostring(discoveryData.i),
				tostring(discoveryData.c),
				tostring(discoveryData.z),
				tostring(discoveryData.iz),
				tostring(discoveryData.q),
				tostring(discoveryData.fp),
				tostring(discoveryData.il))
			if discoveryData.zn then 
				datastr = datastr .. ", zn=" .. tostring(discoveryData.zn) .. "}"
			else
				datastr = datastr .. "}"
			end
		end
		Dev:LogMessage("Toast:Show", string.format("Received data for op=%s: %s", opstr, datastr))
	end
	
	
	options = options or {}
	local op = options.op or "DISC"
	
	ensureProfile()
	if not (L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.enabled) then
	
		return
	end
	local pname = discoveryData and (discoveryData.fp or discoveryData.playerName or discoveryData.finder)
	local tnow = GetTime()
	
	if pname and pname ~= "An Unnamed Collector" then
		if spamState.blocked[pname] then
			
			return
		end
		if op == "CONF" and tnow < (spamState.confSuppressed[pname] or 0) then
			
			return
		end
	end
	if force then
		
		renderToast(discoveryData, options)
		return
	end
	
	local nBacklog = normalBacklogSize()
	if nBacklog >= MAXQUEUEBEFORETICKER then
		if Toast.tickerEnabled then
			overflowActive = true
			
			addToTicker(discoveryData, options)
			return
		else
			
			enqueueToast(discoveryData, options)
			return
		end
	end
	
	if discoveryData.fp == "An Unnamed Collector" then
		
		table.insert(anonBuffer, { data = discoveryData, options = options })
		if not anonWindowEnds then
			anonWindowEnds = GetTime() + ANONGATHERTIME
		end
	else
		
		enqueueToast(discoveryData, options)
	end
end

function Toast:ResetPosition()
	if not toastContainer then return end
	local p, r, rp, x, y = defaultAnchor()
	toastContainer:ClearAllPoints()
	toastContainer:SetPoint(p, r, rp, x, y)
	saveContainerPosition(toastContainer)
	layoutStacks()
end

function Toast:AddSpecialLine(text)
	if not text or text == "" then return end
	table.insert(ticker.messages, tostring(text))
	if not ticker.active then
		if not Toast.tickerEnabled then return end
		ticker.active = true
		ticker.frame:Show()
		ticker.coalesceUntil = GetTime() + TICKERFIRSTBUILDDELAY
		ticker.sessionBuilt = false
		if ticker.fadeL then ticker.fadeL:Show() end
		if ticker.fadeR then ticker.fadeR:Show() end
	end
end

function Toast:OnInitialize()
if L.LEGACY_MODE_ACTIVE then return end
	ensureProfile()
	self:ApplySettings()
	
	toastContainer = CreateFrame("Frame", "LootCollectorToastContainer", UIParent)
	toastContainer:SetSize(TOASTWIDTH, TOASTHEIGHT + (MAXCONCURRENTTOASTSNORMAL * (VERTICALSPACING + MAXCONCURRENTTOASTSNORMAL - 1)))
	toastContainer:SetFrameStrata("MEDIUM")
	toastContainer:SetMovable(true)
	toastContainer:EnableMouse(true)
	toastContainer:SetClampedToScreen(true)
	toastContainer:RegisterForDrag("LeftButton")
	toastContainer:SetScript("OnDragStart", function(self, button)
		if button == "LeftButton" and IsShiftKeyDown() then
			self:StartMoving()
		end
	end)
	toastContainer:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		saveContainerPosition(self)
		layoutStacks()
	end)
	restoreContainerPosition(toastContainer)
	toastContainer:Hide()
	
	ticker.frame = CreateFrame("Frame", "LootCollectorTickerToast", UIParent)
	ticker.frame:SetFrameStrata("MEDIUM")
	ticker.frame:SetSize(TOASTWIDTH, TICKERHEIGHT)
	ticker.frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	ticker.frame:SetBackdropColor(0, 0, 0, 0.75)
	do
		local on = L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.whiteFrame
		if ticker.frame.SetBackdropBorderColor then
			ticker.frame:SetBackdropBorderColor(1, 1, 1, on and 1 or 0.15)
		end
	end
	ticker.close = CreateFrame("Button", nil, ticker.frame, "UIPanelCloseButton")
	ticker.close:SetPoint("TOPRIGHT", 2, 2)
	ticker.close:SetScale(0.7)
	ticker.close:SetScript("OnClick", function()
		for i = #ticker.messages, 1, -1 do
			table.remove(ticker.messages, i)
		end
		ticker.sessionLines = {}
		ticker.sessionBuilt = false
		ticker.active = false
		if ticker.fadeL then ticker.fadeL:Hide() end
		if ticker.fadeR then ticker.fadeR:Hide() end
		ticker.frame:Hide()
		if not anyShown() then
			toastContainer:Hide()
		end
	end)
	ticker.scrollContainer = CreateFrame("ScrollFrame", nil, ticker.frame)
	ticker.scrollContainer:SetPoint("TOPLEFT", 8, -4)
	ticker.scrollContainer:SetPoint("BOTTOMRIGHT", ticker.close, "BOTTOMLEFT", -4, 4)
	ticker.child = CreateFrame("Frame", nil, ticker.scrollContainer)
	ticker.child:SetWidth(1)
	ticker.child:SetHeight(TICKERHEIGHT - 8)
	ticker.scrollContainer:SetScrollChild(ticker.child)
	ticker.text = ticker.child:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	do
		local fnt, size = ticker.text:GetFont()
		ticker.baseFontSize = size or 10
		local flags = (Toast.tickerOutline and TICKERFONTFLAGS or "")
		ticker.text:SetFont(fnt, ticker.baseFontSize + Toast.tickerFontDelta, flags)
	end
	ticker.text:SetJustifyH("LEFT")
	ticker.text:SetJustifyV("MIDDLE")
	ticker.text:SetWordWrap(false)
	ticker.text:SetNonSpaceWrap(false)
	ticker.text:SetTextColor(0.92, 0.92, 0.92)
	ticker.text:SetShadowOffset(1, -1)
	ticker.text:SetShadowColor(0, 0, 0, 0.8)
	if TICKERFADEMASKS then
		ticker.fadeL = ticker.scrollContainer:CreateTexture(nil, "OVERLAY")
		ticker.fadeL:SetTexture("Interface\\Buttons\\WHITE8X8")
		ticker.fadeL:SetPoint("TOPLEFT", ticker.scrollContainer, "TOPLEFT", 0, 0)
		ticker.fadeL:SetPoint("BOTTOMLEFT", ticker.scrollContainer, "BOTTOMLEFT", 0, 0)
		ticker.fadeL:SetWidth(TICKERFADESIZE)
		ticker.fadeL:SetGradientAlpha("HORIZONTAL", 0, 0, 0, TICKERFADEALPHA, 0, 0, 0, 0)
		ticker.fadeL:Hide()
		ticker.fadeR = ticker.scrollContainer:CreateTexture(nil, "OVERLAY")
		ticker.fadeR:SetTexture("Interface\\Buttons\\WHITE8X8")
		ticker.fadeR:SetPoint("TOPRIGHT", ticker.scrollContainer, "TOPRIGHT", 0, 0)
		ticker.fadeR:SetPoint("BOTTOMRIGHT", ticker.scrollContainer, "BOTTOMRIGHT", 0, 0)
		ticker.fadeR:SetWidth(TICKERFADESIZE)
		ticker.fadeR:SetGradientAlpha("HORIZONTAL", 0, 0, 0, 0, 0, 0, 0, TICKERFADEALPHA)
		ticker.fadeR:Hide()
	end
	
	ticker.frame:ClearAllPoints()
	ticker.frame:SetPoint("TOP", toastContainer, "BOTTOM", 0, -TICKERGAP)
	ticker.frame:SetScript("OnShow", function()
		tickerEnsureChildSize()
		if ticker.fadeL then ticker.fadeL:Show() end
		if ticker.fadeR then ticker.fadeR:Show() end
	end)
	ticker.frame:Hide()
	
	dispatcher = CreateFrame("Frame")
	dispatcher:SetScript("OnUpdate", function(_, elapsed)
		
		if anonWindowEnds and GetTime() >= anonWindowEnds then
			processAnonWindow()
		end
		
		if ticker.active and not ticker.sessionBuilt and GetTime() >= ticker.coalesceUntil then
			tickerBuildSessionLine()
		end
		
		if ticker.active and ticker.sessionBuilt then
			if not ticker.dtEMA then ticker.dtEMA = elapsed end
			ticker.dtEMA = ticker.dtEMA * (1 - TICKERDTEMAALPHA) + elapsed * TICKERDTEMAALPHA
			local dt = math.max(ticker.dtEMA, TICKERDTCLAMP)
			ticker.easeT = math.min(ticker.easeT + dt, TICKEREASEIN)
			local easeFactor = math.min(ticker.easeT / TICKEREASEIN, 1.0)
			local baseSpeed = Toast.tickerSpeed or TICKERSPEED
			local speed = baseSpeed * easeFactor
			ticker.textX = ticker.textX - (speed * dt)
			tickerReposition()
			local tw = ticker.text:GetStringWidth() or 0
			if ticker.textX + tw < 0 then
				tickerAdvanceSession()
			end
		end
		
		checkQueueForSpam()
		
		local maxConcurrent = (overflowActive and MAXCONCURRENTTOASTSWITHTICKER or MAXCONCURRENTTOASTSNORMAL)
		if visibleCount() < maxConcurrent and #queue > 0 then
			table.sort(queue, function(a, b) return a.fireAt < b.fireAt end)
			if queue[1] and queue[1].fireAt <= GetTime() then
				local e = table.remove(queue, 1)
				if e and e.data then
					renderToast(e.data, e.options)
				end
			end
		end
		
		local nBacklog = normalBacklogSize()
		if nBacklog >= MAXQUEUEBEFORETICKER then
			overflowActive = true
		elseif nBacklog <= (MAXQUEUEBEFORETICKER - 2) and not ticker.active and not ticker.sessionBuilt then
			overflowActive = false
		end
	end)
end

local function resolveZoneName(rec)
	local c = tonumber(rec.c) or 0
	local z = tonumber(rec.z) or 0
	local iz = tonumber(rec.iz) or 0
	if L.ResolveZoneDisplay then
		return L.ResolveZoneDisplay(c, z, iz)
	end
    
	local ZoneList = L:GetModule("ZoneList", true)
	if ZoneList then
		if z == 0 and iz > 0 and ZoneList.ResolveIz then
			return ZoneList:ResolveIz(iz) or GetRealZoneText() or "Unknown Instance"
		end
		if ZoneList.GetZoneName then
			return ZoneList:GetZoneName(c, z, nil, iz) 
		end
	end
	if z == 0 and iz > 0 then
		return GetRealZoneText() or "Unknown Instance"
	end
	return "Unknown Zone"
end

local function finderDisplay(rec)
	local s = tonumber(rec.s) or 0
	if s == 1 then return "An Unnamed Collector" end
	return rec.fp or "A collector"
end

local function buildToastDataFromV5(rec)
	if not rec then return end
	local link = rec.il
	local texture
	if not link and rec.i then
		local _, lnk, _, _, _, _, _, _, _, tex = GetItemInfo(rec.i)
		link = lnk
		texture = tex
	end
	return {
		il = link,
		i = rec.i,
		itemName = rec.itemName,
		itemQuality = rec.q,
		texture = texture,
		c = rec.c,
		z = rec.z,
		iz = rec.iz,
		xy = rec.xy, 
		zoneNameOverride = resolveZoneName(rec),
		fp = finderDisplay(rec),
	}
end

function Toast:ShowDiscoveryV5(rec, isSpecial)
	local data = buildToastDataFromV5(rec)
	if not data then return end
	if self.Show then
		self:Show(data, isSpecial and true or false)
	end
end

function Toast:NotifyOnHold(rec)
	if not rec or not rec.onHold then return end
	local data = buildToastDataFromV5(rec) or {}
	local zone = resolveZoneName(rec)
	data.zoneNameOverride = string.format("%s (%s)", zone, "ON HOLD")
	if self.Show then
		self:Show(data, true)
	end
end

function Toast:NotifyOnHoldBatch(records)
	if type(records) ~= "table" then return end
	for _, r in ipairs(records) do
		if r and r.onHold then
			self:NotifyOnHold(r)
		end
	end
end

return Toast
-- QSBBIEEgQSBBIEEgQSBBIEEgQQrwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5KlIPCfkqUg8J+SpSDwn5Kl