-- Toast.lua
-- Displays toast notifications, now with support for anonymous senders.

local L = LootCollector
local Toast = L:NewModule("Toast")

local TOAST_WIDTH, TOAST_HEIGHT = 380, 52
local TOAST_DISPLAY_TIME, TOAST_FADE_TIME = 5.0, 1.5
local VERTICAL_SPACING = 8

local toastContainer, toasts = nil, {}

local function defaultAnchor()
    local chat = _G.ChatFrame1 or _G.DEFAULT_CHAT_FRAME or UIParent
    return "BOTTOMLEFT", chat, "TOPLEFT", 0, 80
end

local function saveContainerPosition(f)
    if not (L.db and L.db.profile and L.db.profile.toasts) then return end
    local point, rel, relPoint, x, y = f:GetPoint()
    L.db.profile.toasts.position = {
        point = point,
        rel = (rel and rel:GetName()) or "UIParent",
        relPoint = relPoint,
        x = x or 0,
        y = y or 0,
    }
end

local function restoreContainerPosition(f)
    local pos = (L.db and L.db.profile and L.db.profile.toasts and L.db.profile.toasts.position) or {}
    local relFrame = (pos.rel and _G[pos.rel]) or nil
    if pos.point and relFrame and pos.relPoint then
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

function Toast:OnInitialize()
    if L.db and L.db.profile then
        L.db.profile.toasts = L.db.profile.toasts or {}
    end

    local f = CreateFrame("Frame", "LootCollectorToastContainer", UIParent)
    f:SetSize(TOAST_WIDTH, TOAST_HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")

    f:SetScript("OnDragStart", function(self, button)
        if button == "LeftButton" and IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveContainerPosition(self)
    end)
    
    restoreContainerPosition(f)
    f:Hide()
    toastContainer = f
end

local function acquireToast()
    for _, t in ipairs(toasts) do
        if not t:IsShown() then
            return t
        end
    end

    local t = CreateFrame("Frame", nil, toastContainer)
    t:SetSize(TOAST_WIDTH, TOAST_HEIGHT)
    t:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16 })
    t:SetBackdropColor(0, 0, 0, 0.5)

    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(38, 38)
    t.icon:SetPoint("LEFT", 8, 0)

    t.close = CreateFrame("Button", nil, t, "UIPanelCloseButton")
    t.close:SetPoint("TOPRIGHT", 0, 0)
    t.close:SetScale(0.7)
    t.close:SetScript("OnClick", function(btn)
        local parent = btn:GetParent()
        parent:Hide()
        parent:SetScript("OnUpdate", nil)
        if not anyShown() and toastContainer then toastContainer:Hide() end
    end)

    t.text = CreateFrame("Button", nil, t)
    t.text:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 10, -6)
    t.text:SetPoint("RIGHT", t.close, "LEFT", -8, 0)
    t.text:SetHeight(16)
    t.text:EnableMouse(true)
    
    t.text.fontString = t.text:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.text.fontString:SetAllPoints(t.text)
    t.text.fontString:SetJustifyH("LEFT")
    
    -- Add tooltip for item links
    t.text:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    
    t.text:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    t.text:SetScript("OnClick", function(self, button)
        if self.itemLink then
            if button == "LeftButton" then
                if IsShiftKeyDown() then
                    -- Shift + click: insert into chat
                    local editBox = ChatEdit_ChooseBoxForSend()
                    if editBox then
                        ChatEdit_ActivateChat(editBox)
                        editBox:Insert(self.itemLink)
                    end
                else
                    -- Click: Show Item Tooltip
                    SetItemRef(self.itemLink, self.itemLink, "LeftButton")
                end
            end
        end
    end)

    t.subtext = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.subtext:SetPoint("TOPLEFT", t.text, "BOTTOMLEFT", 0, -2)
    t.subtext:SetPoint("RIGHT", t.text, "RIGHT")
    t.subtext:SetJustifyH("LEFT")
    t.subtext:SetTextColor(0.85, 0.85, 0.85)
    
    t:Hide()
    table.insert(toasts, t)
    return t
end

function Toast:Show(discoveryData)
    if not (L.db and L.db.profile.toasts and L.db.profile.toasts.enabled) then return end
    if not toastContainer then return end

    local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(discoveryData.itemLink or discoveryData.itemID or "")
    
    -- UPDATED: Use name and quality from network packet as fallback
    name = name or discoveryData.itemName
    quality = quality or discoveryData.itemQuality
    
    if not name then
        name, quality, texture = "an item", 1, "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    local finder = discoveryData.foundBy_player or "Unknown"

    local t = acquireToast()
    t.icon:SetTexture(texture)
    t.text.itemLink = discoveryData.itemLink or discoveryData.itemID

    -- UPDATED: Manually colorize name if itemLink is not available
    local itemDisplayString
    if discoveryData.itemLink then
        itemDisplayString = discoveryData.itemLink
    else
        local r, g, b = GetItemQualityColor(quality or 1)
        local hex = string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
        itemDisplayString = string.format("|c%s[%s]|r", hex, name)
    end
    
    t.text.fontString:SetFormattedText("%s found %s!", finder, itemDisplayString)
    t.subtext:SetText("in " .. (discoveryData.zone or "Unknown"))

    if not toastContainer:IsShown() then toastContainer:Show() end

    for _, other in ipairs(toasts) do
        if other:IsShown() and other ~= t then
            other:ClearAllPoints()
            other:SetPoint("TOP", other.anchor or toastContainer, "BOTTOM", 0, -VERTICAL_SPACING)
            other.anchor = other.anchor or toastContainer
        end
    end

    t:ClearAllPoints()
    t:SetPoint("TOP", toastContainer, "TOP")
    t.anchor = toastContainer
    t:SetAlpha(0)
    t:Show()

    t.startTime = GetTime()
    t:SetScript("OnUpdate", function(selfFrame)
        local dt = GetTime() - selfFrame.startTime
        if dt <= 0.5 then
            selfFrame:SetAlpha(dt / 0.5)
        elseif dt > TOAST_DISPLAY_TIME then
            local fade = (dt - TOAST_DISPLAY_TIME) / TOAST_FADE_TIME
            selfFrame:SetAlpha(1 - fade)
            if fade >= 1 then
                selfFrame:Hide()
                selfFrame:SetScript("OnUpdate", nil)
                if not anyShown() and toastContainer then toastContainer:Hide() end
            end
        else
            selfFrame:SetAlpha(1)
        end
    end)
end

function Toast:ResetPosition()
    if not toastContainer then return end
    local p, r, rp, x, y = defaultAnchor()
    toastContainer:ClearAllPoints()
    toastContainer:SetPoint(p, r, rp, x, y)
    saveContainerPosition(toastContainer)
end