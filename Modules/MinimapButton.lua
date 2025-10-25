-- MinimapButton.lua
-- Provides a draggable minimap button to toggle the viewer window

local L = LootCollector
local MinimapButton = L:NewModule("MinimapButton")

-- Button reference
local button = nil
local dragFrame = nil

-- Default settings
local DEFAULT_POSITION = 200 -- degrees around minimap

-- Helper function to calculate position on minimap edge
local function UpdateButtonPosition(angle)
    if not button then return end
    
    local x, y
    local q = math.rad(angle or DEFAULT_POSITION)
    local radius = 80 -- Distance from minimap center
    
    x = math.cos(q) * radius
    y = math.sin(q) * radius
    
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Create the minimap button
local function CreateMinimapButton()
    if button then return button end
    
    -- Create button frame
    button = CreateFrame("Button", "LootCollectorMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetWidth(31)
    button:SetHeight(31)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    -- Set icon texture (using a default icon for now)
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("CENTER", button, "CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    button.icon = icon
    
    -- Create border overlay
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.overlay = overlay
    
    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cffe5cc80LootCollector|r", 1, 1, 1)
        GameTooltip:AddLine("Left-click to open Discoveries", 0.7, 0.7, 1)
        GameTooltip:AddLine("Right-click to open Options", 0.7, 0.7, 1)
        GameTooltip:AddLine("Drag to move", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Click handlers
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" then
            -- Toggle viewer window
            local Viewer = L:GetModule("Viewer", true)
            if Viewer then
                Viewer:Toggle()
            end
        elseif btn == "RightButton" then
            -- Open settings
            InterfaceOptionsFrame_OpenToCategory("LootCollector")
            InterfaceOptionsFrame_OpenToCategory("LootCollector")
        end
    end)
    
    -- Make draggable
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            
            local angle = math.deg(math.atan2(py - my, px - mx))
            if angle < 0 then
                angle = angle + 360
            end
            
            UpdateButtonPosition(angle)
            
            -- Save position
            if L.db and L.db.profile then
                L.db.profile.minimapButtonAngle = angle
            end
        end)
    end)
    
    button:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)
    
    -- Position button
    local savedAngle = L.db and L.db.profile and L.db.profile.minimapButtonAngle or DEFAULT_POSITION
    UpdateButtonPosition(savedAngle)
    
    button:Show()
    
    return button
end

-- Public API
function MinimapButton:Show()
    if not button then
        CreateMinimapButton()
    else
        button:Show()
    end
    
    if L.db and L.db.profile then
        L.db.profile.minimapButtonHidden = false
    end
end

function MinimapButton:Hide()
    if button then
        button:Hide()
    end
    
    if L.db and L.db.profile then
        L.db.profile.minimapButtonHidden = true
    end
end

function MinimapButton:Toggle()
    if button and button:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function MinimapButton:IsShown()
    return button and button:IsShown()
end

-- Module initialization
function MinimapButton:OnInitialize()
    -- Ensure database has a setting for the minimap button
    if L.db and L.db.profile then
        if L.db.profile.minimapButtonHidden == nil then
            L.db.profile.minimapButtonHidden = false
        end
        if L.db.profile.minimapButtonAngle == nil then
            L.db.profile.minimapButtonAngle = DEFAULT_POSITION
        end
    end
    
    -- Create button after a short delay to ensure UI is ready
    C_Timer.After(1, function()
        if L.db and L.db.profile and not L.db.profile.minimapButtonHidden then
            self:Show()
        end
    end)
end

return MinimapButton

