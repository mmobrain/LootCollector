-- DevCommands.lua
-- 3.3.5a-safe developer/testing commands for LootCollector
-- Provides:
--   /lctestcomm -> force a network broadcast to test comms
--   /lcadd      -> add a local discovery (no broadcast)
--   /lccomm     -> AceComm send/recv utilities, verbose logs, clear caches
--   /lcfind     -> inspect a discovery’s reinforce counters and status
--   /lcclear    -> clear comm caches or delete a specific record
--   /lcclearcache -> Clears the session-only deduplication cache.
--   /lcrf       -> force reinforcement due or set originator for a record
--   /lcchan     -> join/status/leave the public channel (BBLCC25)
--   /lcsl       -> send LC1 chat line (DISC/CONF/GONE) over BBLCC25
--   /lcseed     -> seed fake local discoveries for testing
--   /lcpurge    -> clear all discoveries from the database
--   /lcchatdebug-> toggle visibility of addon communication in chat
--   /lcpause    -> toggle queuing of incoming/outgoing messages
--   /lcchatencode-> toggle payload encoding for chat messages
--   /lcdebugconsole -> Shows a dedicated debug message console. Alias: /lcdc

local L = LootCollector
local Dev = L:NewModule("DevCommands", "AceConsole-3.0")

Dev.console = nil -- To hold the debug console frame

-- Utility functions
local function round2(v) return math.floor((tonumber(v) or 0) * 100 + 0.5) / 100 end
local function hereCoords() local x, y = GetPlayerMapPosition("player"); local z = GetCurrentMapZone() or 1; return z, round2(x or 0), round2(y or 0) end
local function makeLink(itemID) return string.format("|cff0070dd|Hitem:%d:0:0:0:0:0:0:0:0|h[Test Item %d]|h|r", itemID or 0, itemID or 0) end
local function guidKey(z, i, x, y) return ("%s-%s-%.2f-%.2f"):format(z or 0, i or 0, round2(x or 0), round2(y or 0)) end
local function M_Comm() return L and L:GetModule("Comm", true) end
local function M_Core() return L and L:GetModule("Core", true) end

--[[--------------------------------------------------------------------
    Debug Console
----------------------------------------------------------------------]]

function Dev:CreateDebugConsole()
    if self.console then return end

    local f = CreateFrame("Frame", "LootCollectorDebugConsole", UIParent)
    f:SetSize(600, 300)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
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

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -16)
    f.title:SetText("LootCollector Debug Console")

    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 16, -38)
    f.scroll:SetPoint("BOTTOMRIGHT", -34, 48)

    f.editBox = CreateFrame("EditBox", nil, f.scroll)
    f.editBox:SetMultiLine(true)
    f.editBox:SetMaxLetters(0) -- Unlimited
    f.editBox:SetFontObject(ChatFontNormal)
    f.editBox:SetWidth(540)
    f.editBox:SetAutoFocus(false)
    f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)

    f.scroll:SetScrollChild(f.editBox)

    f.btnClose = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.btnClose:SetSize(100, 22)
    f.btnClose:SetPoint("BOTTOMRIGHT", -12, 12)
    f.btnClose:SetText("Close")
    f.btnClose:SetScript("OnClick", function() f:Hide() end)
    
    f.btnClear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.btnClear:SetSize(100, 22)
    f.btnClear:SetPoint("RIGHT", f.btnClose, "LEFT", -4, 0)
    f.btnClear:SetText("Clear")
    f.btnClear:SetScript("OnClick", function() f.editBox:SetText("") end)

    self.console = f
end

function Dev:LogMessage(prefix, message)
    if not self.console then self:CreateDebugConsole() end
    
    local logLine = string.format("|cffffff00%s|r |cff8888ff%s:|r %s\n", date("%H:%M:%S"), prefix, tostring(message))
    self.console.editBox:Insert(logLine)

    -- Auto-scroll to bottom
    self.console.scroll:UpdateScrollChildRect()
    local min, max = self.console.scroll:GetVerticalScrollRange()
    
    if max and type(max) == "number" and max > 0 then
        self.console.scroll:SetVerticalScroll(max)
    end
end

function Dev:CmdDebugConsole()
    if not self.console then self:CreateDebugConsole() end
    self.console:SetShown(not self.console:IsShown())
end

--[[--------------------------------------------------------------------
    Slash Command Handlers
----------------------------------------------------------------------]]

local function refreshUI()
    local Map = L:GetModule("Map", true)
    if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then
        Map:Update()
    end
    local Arrow = L:GetModule("Arrow", true)
    if Arrow and Arrow.frame and L.db and L.db.profile and L.db.profile.mapFilters and L.db.profile.mapFilters.hideAll then
        Arrow.frame:Hide()
    end
end

local function seedDiscoveries(count, radius, itemID)
    if not (L.db and L.db.global) then return end
    count, radius, itemID = tonumber(count) or 12, tonumber(radius) or 0.04, tonumber(itemID) or 450501
    local px, py = GetPlayerMapPosition("player")
    if not px or not py or (px == 0 and py == 0) then self:Print("|cffff7f00LootCollector:|r Cannot seed here (no player map position)."); return end
    local zoneID, Core = GetCurrentMapZone(), L:GetModule("Core", true)
    if not (Core and Core.AddDiscovery) then return end
    local now, itemLink, seeded = time(), select(2, GetItemInfo(itemID)), 0
    for i = 1, count do
        local ang, r = math.random() * 2 * math.pi, math.random() * radius
        local x, y = round2(math.min(0.99, math.max(0.01, px + r * math.cos(ang)))), round2(math.min(0.99, math.max(0.01, py + r * math.sin(ang))))
        local ts = now - math.random(0, 3 * 24 * 3600)
        local discovery = { itemLink=itemLink, itemID=itemID, zone=GetRealZoneText(), subZone=GetSubZoneText(), zoneID=zoneID, coords={x=x,y=y}, foundBy_player=UnitName("player"), timestamp=ts, lastSeen=ts, status="UNCONFIRMED", statusTs=ts }
        Core:AddDiscovery(discovery, true); seeded = seeded + 1
    end
    refreshUI(); self:Print(string.format("|cff00ff00LootCollector:|r Seeded %d discoveries.", seeded))
end

local function purgeDB()
    local Core = M_Core()
    if Core and Core.ClearDiscoveries then Core:ClearDiscoveries(); refreshUI()
    else self:Print("|cffff7f00LootCollector:|r Core module not available for clearing.") end
end

function Dev:CmdTestComm(msg)
    local Comm = M_Comm()
    if not Comm then self:Print("Comm module missing"); return end
    local z, x, y = hereCoords()
    if z == 1 and x == 0 and y == 0 then self:Print("|cffff7f00Cannot send test from an unmapped area (indoors?).|r"); return end
    local fakeDiscovery = { itemLink=makeLink(450501), itemID=450501, zoneID=z, coords={x=x, y=y}, timestamp=time(), foundBy_player=UnitName("player") }
    Comm:BroadcastDiscovery(fakeDiscovery)
    self:Print("Sent test broadcast. Check debug console for outgoing payload.")
end

function Dev:CmdChan(msg)
  local Comm = M_Comm()
  if not Comm then self:Print("Comm missing"); return end
  local sub = msg:match("^(%S+)") or "status"
  sub = string.lower(sub)
  if sub == "status" then
    local name = Comm.channelName or "BBLCC25"
    self:Print(string.format("--- Channel Status for '%s' ---", name))
    local live_id, live_name = GetChannelName(name)
    local is_healthy = live_id and live_id > 6 and live_name and string.lower(live_name) == string.lower(name)
    local status_text = is_healthy and "|cff00ff00OK|r" or "|cffff7f00ERROR|r"
    self:Print(string.format("Overall Status: %s", status_text))
    self:Print(string.format("Addon Cached ID: %s", tostring(Comm.channelId)))
    self:Print(string.format("Live API Check: GetChannelName('%s') -> id=%s, name=%s", name, tostring(live_id), tostring(live_name)))
  elseif sub == "rejoin" then
    local name = Comm.channelName or "BBLCC25"
    LeaveChannelByName(name)
    Comm.channelId = 0
    self:Print("Leave requested for "..name..", will attempt to rejoin shortly.")
    C_Timer.After(1.5, function() Comm:EnsureChannelJoined(); self:Print("Rejoin requested for "..name) end)
  else
    self:Print("Usage: /lcchan status|rejoin")
  end
end

function Dev:CmdAdd(msg)
  local a,b,c,d,e = msg:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
  local z,i,x,y
  if a == "here" and b ~= "" then i = tonumber(b); z,x,y = hereCoords()
  elseif a == "at" and e ~= "" then z = tonumber(b); i = tonumber(c); x = round2(tonumber(d)); y = round2(tonumber(e))
  else self:Print("Usage: /lcadd here <itemID> OR /lcadd at <zoneID> <itemID> <x> <y>"); return end
  local Core = M_Core()
  if not Core then self:Print("Core module missing"); return end
  local d = { itemLink=makeLink(i), itemID=i, zone=GetRealZoneText(), subZone=GetSubZoneText(), zoneID=z, coords={x=x, y=y}, timestamp=time(), status="UNCONFIRMED", statusTs=time() }
  Core:AddDiscovery(d, false)
  self:Print(string.format("Added local discovery z=%d i=%d x=%.2f y=%.2f", z, i, x, y))
end

function Dev:CmdComm(msg)
  local sub, rest = msg:match("^(%S+)%s*(.*)$")
  if not sub then self:Print("Usage: verbose|clear|..."); return end
  local Comm = M_Comm()
  if not Comm then self:Print("Comm module missing"); return end
  if sub == "verbose" then
    local v = rest:match("^(%S+)$")
    Comm.verbose = (v == "on")
    self:Print("Verbose " .. (Comm.verbose and "ON" or "OFF"))
  end
end

function Dev:CmdFind(msg)
  local a,b,c,d,e = msg:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
  local z,i,x,y
  if a == "here" and b ~= "" then i = tonumber(b); z,x,y = hereCoords()
  elseif a == "at" and e ~= "" then z = tonumber(b); i = tonumber(c); x = round2(tonumber(d)); y = round2(tonumber(e))
  else self:Print("Usage: /lcfind here <itemID>  OR  /lcfind at <zoneID> <itemID> <x> <y>"); return end
  if not (L and L.db and L.db.global and L.db.global.discoveries) then self:Print("No database loaded"); return end
  local drec = L.db.global.discoveries[guidKey(z,i,x,y)]
  if not drec then self:Print("No discovery at guid " .. guidKey(z,i,x,y)); return end
  self:Print(string.format("GUID %s | status=%s lastSeen=%s", guidKey(z,i,x,y), tostring(drec.status), tostring(drec.lastSeen)))
end

function Dev:CmdClear(msg)
  local sub, rest = msg:match("^(%S+)%s*(.*)$")
  if sub == "comm" then
    local Comm = M_Comm()
    if Comm then
      if Comm.cooldown and Comm.cooldown.CONF then wipe(Comm.cooldown.CONF) end
      if Comm.seen then wipe(Comm.seen) end
    end
    self:Print("Cleared Comm cooldowns and seen cache")
  elseif sub == "record" then
    local a,b,c,d,e = rest:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
    local z,i,x,y
    if a == "here" and b ~= "" then i = tonumber(b); z,x,y = hereCoords()
    elseif a == "at" and e ~= "" then z = tonumber(b); i = tonumber(c); x = round2(tonumber(d)); y = round2(tonumber(e))
    else self:Print("Usage: /lcclear record here <itemID>  OR  /lcclear record at <z> <i> <x> <y>"); return end
    if L and L.db and L.db.global then L.db.global.discoveries[guidKey(z,i,x,y)] = nil; self:Print("Deleted record " .. guidKey(z,i,x,y)) end
  else
    self:Print("Usage: /lcclear comm | /lcclear record here <itemID> | /lcclear record at <z> <i> <x> <y>")
  end
end

function Dev:CmdReinforce(msg)
  local sub, rest = msg:match("^(%S+)%s*(.*)$")
  if not sub then self:Print("Usage: /lcrf due|origin ..."); return end
  local a,b,c,d,e,f = rest:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
  local z,i,x,y
  if a == "here" and b ~= "" then i = tonumber(b); z,x,y = hereCoords()
  elseif a == "at" and e ~= "" then z = tonumber(b); i = tonumber(c); x = round2(tonumber(d)); y = round2(tonumber(e))
  else self:Print("here <itemID>  OR  at <z> <itemID> <x> <y>"); return end
  local drec = (L and L.db and L.db.global) and L.db.global.discoveries[guidKey(z,i,x,y)]
  if not drec then self:Print("No record " .. guidKey(z,i,x,y)); return end
  if sub == "due" then
    local secPast = tonumber(f or rest:match("(%d+)%s*$") or "") or 10
    drec.nextDueTs = time() - secPast
    drec.pendingAnnounce = nil
    self:Print(string.format("Set nextDueTs past by %ds for %s", secPast, guidKey(z,i,x,y)))
  elseif sub == "origin" then
    local who = rest:match("%s+(mine)$") or rest:match("%s+([%a%d%-_]+)%s*$")
    if who == "mine" then who = UnitName("player") end
    if not who or who == "" then self:Print("Usage: /lcrf origin ... mine|<name>"); return end
    drec.originator = who
    self:Print(string.format("Originator set to %s for %s", who, guidKey(z,i,x,y)))
  end
end

function Dev:CmdSendLC1(msg)
  local Comm = M_Comm()
  if not Comm then self:Print("Comm missing"); return end
  local op, mode, a,b,c,d = msg:match("^(%S+)%s+(%S+)%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
  if not op then self:Print("Usage: /lcsl OP here <itemID> | at <z> <i> <x> <y>"); return end
  op = string.upper(op)
  if op ~= "DISC" and op ~= "CONF" and op ~= "GONE" then self:Print("OP must be DISC|CONF|GONE"); return end
  local z,i,x,y
  if mode == "here" and a ~= "" then i = tonumber(a); z,x,y = hereCoords()
  elseif mode == "at" and d ~= "" then z = tonumber(a); i = tonumber(b); x = round2(tonumber(c)); y = round2(tonumber(d))
  else self:Print("Usage: /lcsl OP here <itemID> | at <z> <i> <x> <y>"); return end
  Comm:SendLC1Discovery({ zoneID = z, itemID = i, coords = { x=x, y=y }, timestamp=time() })
  self:Print(string.format("LC1 %s sent z=%d i=%d x=%.2f y=%.2f (Format: %s)", op, z, i, x, y, L.db.profile.chatEncode and "Encoded" or "Legacy"))
end

function Dev:CmdPause()
    if L and L.TogglePause then L:TogglePause() end
end

function Dev:CmdSeed(msg)
    local a, b, c = msg:match("^%s*(%S*)%s*(%S*)%s*(%S*)")
    seedDiscoveries(a, b, c)
end

function Dev:CmdPurge()
    purgeDB()
end

function Dev:CmdChatDebug()
    if not (L.db and L.db.profile) then return end
    L.db.profile.chatDebug = not L.db.profile.chatDebug
    self:Print(string.format("Channel message visibility/logging: %s", L.db.profile.chatDebug and "|cff00ff00ON|r" or "|cffff7f00OFF|r"))
end

function Dev:CmdChatEncode()
    if not (L.db and L.db.profile) then return end
    L.db.profile.chatEncode = not L.db.profile.chatEncode
    self:Print(string.format("Chat message encoding: %s", L.db.profile.chatEncode and "|cff00ff00ON|r" or "|cffff7f00OFF|r"))
end

-- NEW: Handler for the cache clearing command
function Dev:CmdClearCache()
    local Comm = M_Comm()
    if Comm and Comm.ClearCaches then
        Comm:ClearCaches()
    else
        self:Print("Comm module not available to clear caches.")
    end
end

-- Register slash commands
function Dev:OnInitialize()
  self:RegisterChatCommand("lcadd", "CmdAdd")
  self:RegisterChatCommand("lccomm", "CmdComm")
  self:RegisterChatCommand("lcfind", "CmdFind")
  self:RegisterChatCommand("lcclear", "CmdClear")
  self:RegisterChatCommand("lcrf", "CmdReinforce")
  self:RegisterChatCommand("lcchan", "CmdChan")
  self:RegisterChatCommand("lcsl", "CmdSendLC1")
  self:RegisterChatCommand("lctestcomm", "CmdTestComm")
  self:RegisterChatCommand("lcseed", "CmdSeed")
  self:RegisterChatCommand("lcpurge", "CmdPurge")
  self:RegisterChatCommand("lcchatdebug", "CmdChatDebug")
  self:RegisterChatCommand("lcpause", "CmdPause")
  self:RegisterChatCommand("lcchatencode", "CmdChatEncode")
  self:RegisterChatCommand("lcdebugconsole", "CmdDebugConsole")
  self:RegisterChatCommand("lcdc", "CmdDebugConsole") -- Alias
  self:RegisterChatCommand("lcclearcache", "CmdClearCache") -- NEW
end

return Dev