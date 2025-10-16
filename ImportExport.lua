-- ImportExport.lua (3.3.5-safe)
-- - Export/import canonical discoveries with optional per-character overlays.
-- - Interface Options -> LootCollector -> Discoveries panel with four tabs:
--   1) "Import/Export"  2) "Looted"  3) "All World"  4) "Instances"
-- - Highlights current looted state per row (green for current, red for alternative)
--   and colorizes discovery status (UNCONFIRMED/CONFIRMED/FADING/STALE).

local L = LootCollector
local ImportExport = L:NewModule("ImportExport")

-- Optional libs (safe if missing on Ascension/WotLK)
local LibSerialize = (LibStub and LibStub("LibSerialize", true)) or nil
local AceSerializer = (LibStub and LibStub("AceSerializer-3.0", true)) or nil
local LibDeflate  = (LibStub and LibStub("LibDeflate", true)) or nil
local LibBase64   = _G.LibBase64 or nil
local Smallfolk   = (LibStub and LibStub("LibSmallfolk-1.0", true)) or _G.smallfolk or nil

-- Wire header for export
local HEADER = "!LC1!"

-- codec tags
local LS, AS = "LS", "AS"
local LD, NZ = "LD", "NZ"
local PF, LB, SF = "PF", "LB", "SF"

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function now() return time() end

local STATUS_UNCONFIRMED = "UNCONFIRMED"
local STATUS_CONFIRMED   = "CONFIRMED"
local STATUS_FADING      = "FADING"
local STATUS_STALE       = "STALE"

-- The cleanRecord function now includes founder info
local function cleanRecord(d)
  if type(d) ~= "table" then return nil end
  return {
    guid = d.guid,
    itemID = d.itemID,
    zoneID = d.zoneID,
    coords = d.coords and {x = tonumber(d.coords.x) or 0, y = tonumber(d.coords.y) or 0} or {x = 0, y = 0},
    status = d.status or STATUS_UNCONFIRMED,
    statusTs = tonumber(d.statusTs) or tonumber(d.lastSeen) or tonumber(d.timestamp) or now(),
    lastSeen = tonumber(d.lastSeen) or tonumber(d.timestamp) or now(),
    timestamp = tonumber(d.timestamp) or now(),
    itemLink = d.itemLink,
    zone = d.zone,
    subZone = d.subZone,
    -- Added fields
    foundBy_player = d.foundBy_player,
    originator = d.originator,
    source = d.source,
    mergeCount = d.mergeCount,
  }
end


local function countTableKeys(t)
  local n = 0; if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end; return n
end

----------------------------------------------------------------------
-- Build export payload
----------------------------------------------------------------------
local function buildExport(includeOverlays)
  local discoveries = {}; local count = 0; if L.db and L.db.global and L.db.global.discoveries then for guid, d in pairs(L.db.global.discoveries) do local rec = cleanRecord(d); if rec and rec.guid then discoveries[rec.guid] = rec; count = count + 1 end end end; local overlays = nil; if includeOverlays and L.db and L.db.char then overlays = { looted = {}, hidden = {} }; for guid, ts in pairs(L.db.char.looted or {}) do overlays.looted[guid] = tonumber(ts) or 1 end; for guid, on in pairs(L.db.char.hidden or {}) do if on then overlays.hidden[guid] = true end end end; local payload = { meta = { v = 1, addon = "LootCollector", ts = now(), counts = { discoveries = count, looted = overlays and countTableKeys(overlays.looted) or 0, hidden = overlays and countTableKeys(overlays.hidden) or 0, }, }, discoveries = discoveries, overlays = overlays, }; return payload
end

----------------------------------------------------------------------
-- Serialization pipeline (WeakAuras-like)
----------------------------------------------------------------------
local function serializeTable(tbl)
  if LibSerialize then local ok, bytes = pcall(LibSerialize.Serialize, LibSerialize, tbl); if ok and bytes then return LS, bytes end end; if AceSerializer then local ok, bytes = pcall(AceSerializer.Serialize, AceSerializer, tbl); if ok and bytes then return AS, bytes end end; return nil, "SerializerMissing"
end
local function compressBytes(bytes)
  if LibDeflate and type(bytes) == "string" then local ok, out = pcall(LibDeflate.CompressDeflate, LibDeflate, bytes, { level = 8 }); if ok and out then return LD, out end end; return NZ, bytes
end
local function encodePrintable(bytes)
  if LibDeflate and LibDeflate.EncodeForPrint then local ok, out = pcall(LibDeflate.EncodeForPrint, LibDeflate, bytes); if ok and out then return PF, out end end; if LibBase64 and LibBase64.Encode then local ok, out = pcall(LibBase64.Encode, bytes); if ok and out then return LB, out end end; if Smallfolk and Smallfolk.dumps then local ok, out = pcall(Smallfolk.dumps, bytes); if ok and out then return SF, out end end; return nil, "EncoderMissing"
end
local function decodePrintable(codecEnc, text)
  if codecEnc == PF and LibDeflate and LibDeflate.DecodeForPrint then return LibDeflate:DecodeForPrint(text) elseif codecEnc == LB and LibBase64 and LibBase64.Decode then return LibBase64.Decode(text) elseif codecEnc == SF and Smallfolk and Smallfolk.loads then return Smallfolk.loads(text) end; return nil
end
local function decompressBytes(codecZip, bytes)
  if codecZip == LD and LibDeflate and LibDeflate.DecompressDeflate then return LibDeflate:DecompressDeflate(bytes) end; return bytes
end
local function deserializeTable(codecSer, bytes)
  if codecSer == LS and LibSerialize and LibSerialize.Deserialize then local ok, success, out = pcall(LibSerialize.Deserialize, LibSerialize, bytes); if ok and success and type(out) == "table" then return out end elseif codecSer == AS and AceSerializer and AceSerializer.Deserialize then local ok, success, out = pcall(AceSerializer.Deserialize, AceSerializer, bytes); if ok and success and type(out) == "table" then return out end end; return nil
end

function ImportExport:ExportString(includeOverlays)
  local payload = buildExport(includeOverlays); local codecSer, ser = serializeTable(payload); if not codecSer then return nil, "No serializer available" end; local codecZip, zipped = compressBytes(ser); local codecEnc, text = encodePrintable(zipped); if not codecEnc then return nil, "No encoder available" end; local codec = table.concat({ codecSer, codecZip or NZ, codecEnc }, ","); return HEADER .. codec .. ":" .. text
end

----------------------------------------------------------------------
-- Importing
----------------------------------------------------------------------
local function parseHeader(s)
  if type(s) ~= "string" then return nil end; if s:find("^!LC1!") then return "!LC1!", s:sub(6) end; if s:find("^!LH1!") then return "!LH1!", s:sub(6) end; return nil
end

function ImportExport:ParseImportString(s)
  local hdr, rest = parseHeader(s); if not hdr then return nil, "Bad header or missing !LC1! prefix" end; local codec, body, codec_delimiter; codec, body = rest:match("^([^:]+):(.+)$"); codec_delimiter = ","; if not codec or not body then codec, body = rest:match("^([^;]+);(.+)$"); codec_delimiter = "%+" end; if not codec or not body or body == "" then return nil, "Malformed payload (invalid format or empty body)" end; local parts = {}; for p in string.gmatch(codec, "([^" .. codec_delimiter .. "]+)") do table.insert(parts, p) end; local codecSer, codecZip, codecEnc = parts[1], parts[2] or "NZ", parts[3]; local bytes = decodePrintable(codecEnc, body); if not bytes then return nil, "Decode failed (check libraries and string)" end; local unz = decompressBytes(codecZip, bytes); if not unz then return nil, "Decompress failed" end; local tbl = deserializeTable(codecSer, unz); if type(tbl) ~= "table" or type(tbl.discoveries) ~= "table" then return nil, "Deserialize failed (final data is not a valid table)" end; local meta = tbl.meta or {}; local disc = tbl.discoveries or {}; local overlays = tbl.overlays or {}; local stats = { imported = 0, overlays = 0 }; for _ in pairs(disc) do stats.imported = stats.imported + 1 end; for _ in pairs(overlays.looted or {}) do stats.overlays = stats.overlays + 1 end; return { meta = meta, discoveries = disc, overlays = overlays }, stats
end

local function mergeOne(ex, inc)
  ex.statusTs = math.max(tonumber(ex.statusTs) or 0, tonumber(inc.statusTs) or 0); ex.lastSeen = math.max(tonumber(ex.lastSeen) or 0, tonumber(inc.lastSeen) or 0); if inc.status and (tonumber(inc.statusTs) or 0) >= (tonumber(ex.statusTs) or 0) then ex.status = inc.status end; if not ex.itemLink and inc.itemLink then ex.itemLink = inc.itemLink end; if not ex.zone and inc.zone then ex.zone = inc.zone end; if not ex.subZone and inc.subZone then ex.subZone = inc.subZone end
end

function ImportExport:ApplyImport(parsed, mode, withOverlays)
  if not (L.db and L.db.global) then return nil, "DB not ready" end; local disc = parsed.discoveries or {}; local overlays = parsed.overlays or {}; local g = L.db.global; g.discoveries = g.discoveries or {}; local applied = { added = 0, updated = 0, total = 0, overlays = 0 }; if mode == "OVERRIDE" then g.discoveries = {} end; for guid, d in pairs(disc) do applied.total = applied.total + 1; local ex = g.discoveries[guid]; if not ex then g.discoveries[guid] = d; applied.added = applied.added + 1 else mergeOne(ex, d); applied.updated = applied.updated + 1 end end; if withOverlays and L.db and L.db.char then L.db.char.looted = L.db.char.looted or {}; for guid, ts in pairs(overlays.looted or {}) do L.db.char.looted[guid] = tonumber(ts) or now(); applied.overlays = applied.overlays + 1 end; L.db.char.hidden = L.db.char.hidden or {}; for guid, on in pairs(overlays.hidden or {}) do L.db.char.hidden[guid] = on and true or nil end end; local Map = L:GetModule("Map", true); if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end; return applied
  end

function ImportExport:ApplyImportString(importString, mode, withOverlays)
    local parsed, errOrStats = self:ParseImportString(importString); if not parsed then print("|cffff7f00LootCollector:|r Import failed: " .. tostring(errOrStats)); return end; local res, err = self:ApplyImport(parsed, mode, withOverlays); if not res then print("|cffff7f00LootCollector:|r Failed to apply import: " .. tostring(err)); return end; print(string.format("|cff00ff00LootCollector:|r Import successful! Merged %d discoveries.", res.total)); local Core = L:GetModule("Core", true); if Core and Core.ScanDatabaseForUncachedItems then Core:ScanDatabaseForUncachedItems() end
end


----------------------------------------------------------------------
-- 3.3.5-safe dialogs: export/import
----------------------------------------------------------------------
local function CreateEditDialog(name, title, isReadOnly)
  local f = CreateFrame("Frame", name, UIParent); f:SetSize(560, 380); f:SetPoint("CENTER"); f:Hide(); f:SetFrameStrata("DIALOG"); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing); f:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=32, insets={left=8,right=8,top=8,bottom=8} }); f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.title:SetPoint("TOPLEFT", 16, -12); f.title:SetText(title or ""); f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate"); f.scroll:SetPoint("TOPLEFT", 16, -36); f.scroll:SetPoint("BOTTOMRIGHT", -34, 48); f.edit = CreateFrame("EditBox", nil, f.scroll); f.edit:SetMultiLine(true); f.edit:SetFontObject(ChatFontNormal); f.edit:SetWidth(500); f.edit:SetAutoFocus(false); f.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end); f.scroll:SetScrollChild(f.edit); f.btnClose = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); f.btnClose:SetSize(100, 22); f.btnClose:SetPoint("BOTTOMRIGHT", -12, 12); f.btnClose:SetText("Close"); f.btnClose:SetScript("OnClick", function() f:Hide() end); if isReadOnly then f.edit:EnableMouse(true); f.edit:SetScript("OnTextChanged", function() end); f.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end) end; return f
end
local function OpenExportDialog(includeOverlays)
  ImportExport.exportDialog = ImportExport.exportDialog or CreateEditDialog("LootCollectorExportDialog", "LootCollector Export", true); local s, err = ImportExport:ExportString(includeOverlays); ImportExport.exportDialog.edit:SetText(s or ("export failed: " .. tostring(err or "?"))); ImportExport.exportDialog:Show()
end
local function OpenImportDialog()
    ImportExport.importDialog = ImportExport.importDialog or CreateEditDialog("LootCollectorImportDialog", "LootCollector Import", false); local f = ImportExport.importDialog; f:SetScript("OnMouseDown", function(self, button) if not MouseIsOver(self.btnMerge) and not MouseIsOver(self.btnOverride) and not MouseIsOver(self.chkOverlays) and not MouseIsOver(self.btnClose) then self.edit:SetFocus() end end); if not f.btnMerge then f.btnMerge = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); f.btnMerge:SetSize(120, 22); f.btnMerge:SetPoint("BOTTOMLEFT", 12, 12); f.btnMerge:SetText("Merge"); f.btnOverride = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); f.btnOverride:SetSize(120, 22); f.btnOverride:SetPoint("LEFT", f.btnMerge, "RIGHT", 8, 0); f.btnOverride:SetText("Override"); f.chkOverlays = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate"); f.chkOverlays:SetPoint("LEFT", f.btnOverride, "RIGHT", 12, 0); f.chkOverlays.text = f.chkOverlays:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.chkOverlays.text:SetPoint("LEFT", f.chkOverlays, "RIGHT", 4, 0); f.chkOverlays.text:SetText("Import overlays"); local function apply(mode) local s = f.edit:GetText() or ""; local parsed, errOrStats = ImportExport:ParseImportString(s); if not parsed then print("|cffff7f00LootCollector:|r Import parse failed: " .. tostring(errOrStats)); return end; local res, err = ImportExport:ApplyImport(parsed, mode, f.chkOverlays:GetChecked() and true or false); if not res then print("|cffff7f00LootCollector:|r Import apply failed: " .. tostring(err)); return end; print(string.format("|cff00ff00LootCollector:|r %s applied: +%d, ~%d, total %d, overlays %d", mode, res.added, res.updated, res.total, res.overlays)) end; f.btnMerge:SetScript("OnClick", function() apply("MERGE") end); f.btnOverride:SetScript("OnClick",function() apply("OVERRIDE") end) end; f:Show()
end
----------------------------------------------------------------------
-- Discoveries panel: tabs and pages (+ row styling)
----------------------------------------------------------------------
local panel, tabs, tabPages, activeTab = nil, {}, {}, 1; local ROWS, ROWH = 14, 20; local COLOR_GREEN, COLOR_RED = {0.4,1,0}, {0.85,0.25,0.25}; local STATUS_HEX = {[STATUS_CONFIRMED]="ff20ff20",[STATUS_UNCONFIRMED]="fff0c000",[STATUS_FADING]="ffff7f00",[STATUS_STALE]="ff9d9d9d"}; local function colorizeStatus(s) return "|c"..(STATUS_HEX[s] or "ffffffff")..(s or "").."|r" end; local function tintButton(btn, r, g, b) if not btn then return end; local nt=btn:GetNormalTexture(); local pt=btn:GetPushedTexture(); local dt=btn:GetDisabledTexture(); local ht=btn:GetHighlightTexture(); if nt then nt:SetVertexColor(r, g, b) end; if pt then pt:SetVertexColor(r*0.9, g*0.9, b*0.9) end; if dt then dt:SetVertexColor(r, g, b) end; if ht then ht:SetVertexColor(1,1,1) end end; local function styleRowButtons(row, isLooted) if not row or not row.btnLoot or not row.btnUnl then return end; if isLooted then tintButton(row.btnLoot, unpack(COLOR_GREEN)); tintButton(row.btnUnl, unpack(COLOR_RED)) else tintButton(row.btnLoot, unpack(COLOR_RED)); tintButton(row.btnUnl, unpack(COLOR_GREEN)) end end; local function CreateTab(parent, id, text) local parentName=(parent.GetName and parent:GetName()) or "LootCollectorDiscoveriesPanel"; local tabName=parentName.."Tab"..tostring(id); local btn=CreateFrame("Button",tabName,parent,"OptionsFrameTabButtonTemplate"); btn:SetID(id); btn:SetText(text or ("Tab "..id)); if PanelTemplates_TabResize then PanelTemplates_TabResize(btn, 0) elseif PanelTemplates_TabResize2 then PanelTemplates_TabResize2(btn, 0) end; btn:SetScript("OnClick", function(self) PanelTemplates_SetTab(parent, self:GetID()); activeTab = self:GetID(); for i, page in ipairs(tabPages) do page:SetShown(i == activeTab); if page:IsShown() and page.refresh then page.refresh() end end end); return btn end

local function BuildImportExportPage(parent)
    local page=CreateFrame("Frame",nil,parent);page:SetAllPoints(parent);local title=page:CreateFontString(nil,"OVERLAY","GameFontHighlight");title:SetPoint("TOPLEFT",page,"TOPLEFT",0,0);title:SetText("Import / Export");local btnExportAll=CreateFrame("Button",nil,page,"UIPanelButtonTemplate");btnExportAll:SetSize(160,22);btnExportAll:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-8);btnExportAll:SetText("Export (with overlays)");btnExportAll:SetScript("OnClick",function()OpenExportDialog(true)end);local btnExportCanon=CreateFrame("Button",nil,page,"UIPanelButtonTemplate");btnExportCanon:SetSize(160,22);btnExportCanon:SetPoint("LEFT",btnExportAll,"RIGHT",8,0);btnExportCanon:SetText("Export (canonical only)");btnExportCanon:SetScript("OnClick",function()OpenExportDialog(false)end);local btnImport=CreateFrame("Button",nil,page,"UIPanelButtonTemplate");btnImport:SetSize(120,22);btnImport:SetPoint("LEFT",btnExportCanon,"RIGHT",8,0);btnImport:SetText("Import from String");btnImport:SetScript("OnClick",OpenImportDialog);local btnImportStarter=CreateFrame("Button",nil,page,"UIPanelButtonTemplate");btnImportStarter:SetSize(180,22);btnImportStarter:SetPoint("TOPLEFT",btnExportAll,"BOTTOMLEFT",0,-8);btnImportStarter:SetText("Merge Starter Database");btnImportStarter:SetScript("OnClick",function()if _G.LootCollector_OptionalDB then ImportExport:ApplyImportString(_G.LootCollector_OptionalDB,"MERGE",false)end end);btnImportStarter:SetShown(_G.LootCollector_OptionalDB and true or false);local help=page:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");help:SetPoint("TOPLEFT",btnImportStarter,"BOTTOMLEFT",0,-12);help:SetWidth(540);help:SetJustifyH("LEFT");help:SetText("Export copies a shareable string. Import pastes one from others. Overlays include per-character looted/hidden flags.");function page.refresh()end;return page
end
local function setLooted(guid, on) if not (L.db and L.db.char) then return end; L.db.char.looted=L.db.char.looted or{}; if on then L.db.char.looted[guid]=now() else L.db.char.looted[guid]=nil end; local Map=L:GetModule("Map", true); if Map and Map.Update and WorldMapFrame and WorldMapFrame:IsShown() then Map:Update() end end;
local function BuildLootedListPage(parent, titleText)
  local page=CreateFrame("Frame",nil,parent);page:SetAllPoints(parent);local title=page:CreateFontString(nil,"OVERLAY","GameFontHighlight");title:SetPoint("TOPLEFT",page,"TOPLEFT",0,0);title:SetText(titleText or"Looted by this character");
  
  local countDisplay = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
  countDisplay:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, 0);
  countDisplay:SetText("");

  local lblFilter=page:CreateFontString(nil,"OVERLAY","GameFontHighlight");lblFilter:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-6);lblFilter:SetText("Filter:");local edit=CreateFrame("EditBox",nil,page,"InputBoxTemplate");edit:SetAutoFocus(false);edit:SetSize(220,22);edit:SetPoint("LEFT",lblFilter,"RIGHT",4,0);local scroll=CreateFrame("ScrollFrame",nil,page,"FauxScrollFrameTemplate");scroll:SetPoint("TOPLEFT",lblFilter,"BOTTOMLEFT",0,-8);scroll:SetPoint("BOTTOMRIGHT",page,"BOTTOMRIGHT",-24,0);local rows={};for i=1,ROWS do local row=CreateFrame("Frame",nil,page);row:SetHeight(ROWH);row:SetPoint("TOPLEFT",scroll,"TOPLEFT",0,-(i-1)*ROWH);row:SetPoint("RIGHT",scroll,"RIGHT",0,0);row.txt=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");row.txt:SetPoint("LEFT",4,0);row.txt:SetJustifyH("LEFT");row.btnUnl=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");row.btnUnl:SetSize(84,ROWH-2);row.btnUnl:SetPoint("RIGHT",-4,0);row.btnUnl:SetText("Unlooted");row.btnLoot=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");row.btnLoot:SetSize(64,ROWH-2);row.btnLoot:SetPoint("RIGHT",row.btnUnl,"LEFT",-6,0);row.btnLoot:SetText("Looted");row.txt:SetPoint("RIGHT",row.btnLoot,"LEFT",-8,0);rows[i]=row end;
  
  function page.refresh()
      if not(L.db and L.db.global)then return end;local term=string.lower(edit:GetText()or"");local list={};local totalLooted=0;for _,d in pairs(L.db.global.discoveries or{})do local lootedByMe=L.db and L.db.char and L.db.char.looted and L.db.char.looted[d.guid]and true or false;if lootedByMe then totalLooted=totalLooted+1;local name=d.itemLink or(d.itemID and select(1,GetItemInfo(d.itemID))or"")or"";local zone=d.zone or"";local match=(term==""or(string.find(string.lower(name),term,1,true)~=nil)or(string.find(string.lower(zone),term,1,true)~=nil));if match then table.insert(list,d)end end end;
      countDisplay:SetText(string.format("(Showing %d of %d)", #list, totalLooted));
      table.sort(list,function(a,b)local la=tonumber(a.lastSeen)or 0;local lb=tonumber(b.lastSeen)or 0;if la~=lb then return la>lb end;return(a.itemID or 0)<(b.itemID or 0)end);local offset=FauxScrollFrame_GetOffset(scroll);local total=#list;FauxScrollFrame_Update(scroll,total,ROWS,ROWH);for i=1,ROWS do local idx=i+offset;local row=rows[i];local d=list[idx];if d then row:Show();local label=string.format("%s | %s | %s",d.itemLink or(d.itemID and("item:"..d.itemID)or"item"),d.zone or"Zone",colorizeStatus(d.status or STATUS_UNCONFIRMED));row.txt:SetText(label);local isLooted=true;styleRowButtons(row,isLooted);row.btnLoot.disc,row.btnUnl.disc=d,d;row.btnLoot:SetScript("OnClick",function(self)local dd=self.disc;if dd and dd.guid then setLooted(dd.guid,true);page.refresh()end end);row.btnUnl:SetScript("OnClick",function(self)local dd=self.disc;if dd and dd.guid then setLooted(dd.guid,false);page.refresh()end end)else row:Hide();row.btnLoot.disc,row.btnUnl.disc=nil,nil end end
  end;
  scroll:SetScript("OnVerticalScroll",function(self,delta)FauxScrollFrame_OnVerticalScroll(self,delta,ROWH,page.refresh)end);edit:SetScript("OnTextChanged",page.refresh);page:SetScript("OnShow",page.refresh);return page
end
local function BuildAllListPage(parent, titleText)
  local page=CreateFrame("Frame",nil,parent);page:SetAllPoints(parent);local title=page:CreateFontString(nil,"OVERLAY","GameFontHighlight");title:SetPoint("TOPLEFT",page,"TOPLEFT",0,0);title:SetText(titleText or"All World Discoveries");
  
  local countDisplay = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
  countDisplay:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, 0);
  countDisplay:SetText("");
  
  local lblFilter=page:CreateFontString(nil,"OVERLAY","GameFontHighlight");lblFilter:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-6);lblFilter:SetText("Filter:");local edit=CreateFrame("EditBox",nil,page,"InputBoxTemplate");edit:SetAutoFocus(false);edit:SetSize(220,22);edit:SetPoint("LEFT",lblFilter,"RIGHT",4,0);local scroll=CreateFrame("ScrollFrame",nil,page,"FauxScrollFrameTemplate");scroll:SetPoint("TOPLEFT",lblFilter,"BOTTOMLEFT",0,-8);scroll:SetPoint("BOTTOMRIGHT",page,"BOTTOMRIGHT",-24,0);local rows={};for i=1,ROWS do local row=CreateFrame("Frame",nil,page);row:SetHeight(ROWH);row:SetPoint("TOPLEFT",scroll,"TOPLEFT",0,-(i-1)*ROWH);row:SetPoint("RIGHT",scroll,"RIGHT",0,0);row.txt=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");row.txt:SetPoint("LEFT",4,0);row.txt:SetJustifyH("LEFT");row.btnUnl=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");row.btnUnl:SetSize(84,ROWH-2);row.btnUnl:SetPoint("RIGHT",-4,0);row.btnUnl:SetText("Unlooted");row.btnLoot=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");row.btnLoot:SetSize(64,ROWH-2);row.btnLoot:SetPoint("RIGHT",row.btnUnl,"LEFT",-6,0);row.btnLoot:SetText("Looted");row.txt:SetPoint("RIGHT",row.btnLoot,"LEFT",-8,0);rows[i]=row end;
  
  function page.refresh()
      if not(L.db and L.db.global)then return end;local term=string.lower(edit:GetText()or"");local list={};local totalWorld=0;for _,d in pairs(L.db.global.discoveries or{})do if d and d.guid and(d.zoneID and d.zoneID~=0)then totalWorld=totalWorld+1;local name=d.itemLink or(d.itemID and select(1,GetItemInfo(d.itemID))or"")or"";local zone=d.zone or"";local match=(term==""or(string.find(string.lower(name),term,1,true)~=nil)or(string.find(string.lower(zone),term,1,true)~=nil));if match then table.insert(list,d)end end end;
      countDisplay:SetText(string.format("(Showing %d of %d)", #list, totalWorld));
      table.sort(list,function(a,b)local la=tonumber(a.lastSeen)or 0;local lb=tonumber(b.lastSeen)or 0;if la~=lb then return la>lb end;return(a.itemID or 0)<(b.itemID or 0)end);local offset=FauxScrollFrame_GetOffset(scroll);local total=#list;FauxScrollFrame_Update(scroll,total,ROWS,ROWH);for i=1,ROWS do local idx=i+offset;local row=rows[i];local d=list[idx];if d then row:Show();local lootedByMe=L.db and L.db.char and L.db.char.looted and L.db.char.looted[d.guid]and true or false;local label=string.format("%s | %s | %s",d.itemLink or(d.itemID and("item:"..d.itemID)or"item"),d.zone or"Zone",colorizeStatus(d.status or STATUS_UNCONFIRMED));row.txt:SetText(label);styleRowButtons(row,lootedByMe);row.btnLoot.disc,row.btnUnl.disc=d,d;row.btnLoot:SetScript("OnClick",function(self)local dd=self.disc;if dd and dd.guid then setLooted(dd.guid,true);page.refresh()end end);row.btnUnl:SetScript("OnClick",function(self)local dd=self.disc;if dd and dd.guid then setLooted(dd.guid,false);page.refresh()end end)else row:Hide();row.btnLoot.disc,row.btnUnl.disc=nil,nil end end
  end;
  scroll:SetScript("OnVerticalScroll",function(self,delta)FauxScrollFrame_OnVerticalScroll(self,delta,ROWH,page.refresh)end);edit:SetScript("OnTextChanged",page.refresh);page:SetScript("OnShow",page.refresh);return page
end
local function BuildInstanceListPage(parent, titleText)
  local page=CreateFrame("Frame",nil,parent);page:SetAllPoints(parent);local title=page:CreateFontString(nil,"OVERLAY","GameFontHighlight");title:SetPoint("TOPLEFT",page,"TOPLEFT",0,0);title:SetText(titleText or"Instance Discoveries (No Map Pins)");
  
  local countDisplay = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
  countDisplay:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, 0);
  countDisplay:SetText("");
  
  local lblFilter=page:CreateFontString(nil,"OVERLAY","GameFontHighlight");lblFilter:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-6);lblFilter:SetText("Filter:");local edit=CreateFrame("EditBox",nil,page,"InputBoxTemplate");edit:SetAutoFocus(false);edit:SetSize(220,22);edit:SetPoint("LEFT",lblFilter,"RIGHT",4,0);local scroll=CreateFrame("ScrollFrame",nil,page,"FauxScrollFrameTemplate");scroll:SetPoint("TOPLEFT",lblFilter,"BOTTOMLEFT",0,-8);scroll:SetPoint("BOTTOMRIGHT",page,"BOTTOMRIGHT",-24,0);local rows={};for i=1,ROWS do local row=CreateFrame("Frame",nil,page);row:SetHeight(ROWH);row:SetPoint("TOPLEFT",scroll,"TOPLEFT",0,-(i-1)*ROWH);row:SetPoint("RIGHT",scroll,"RIGHT",0,0);row.txt=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");row.txt:SetPoint("LEFT",4,0);row.txt:SetJustifyH("LEFT");row.btnUnl=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");row.btnUnl:SetSize(84,ROWH-2);row.btnUnl:SetPoint("RIGHT",-4,0);row.btnUnl:SetText("Unlooted");row.btnLoot=CreateFrame("Button",nil,row,"UIPanelButtonTemplate");row.btnLoot:SetSize(64,ROWH-2);row.btnLoot:SetPoint("RIGHT",row.btnUnl,"LEFT",-6,0);row.btnLoot:SetText("Looted");row.txt:SetPoint("RIGHT",row.btnLoot,"LEFT",-8,0);rows[i]=row end;
  
  function page.refresh()
      if not(L.db and L.db.global)then return end;local term=string.lower(edit:GetText()or"");local list={};local totalInstance=0;for _,d in pairs(L.db.global.discoveries or{})do if d and d.guid and(d.zoneID==0)then totalInstance=totalInstance+1;local name=d.itemLink or(d.itemID and select(1,GetItemInfo(d.itemID))or"")or"";local zone=d.zone or"";local match=(term==""or(string.find(string.lower(name),term,1,true)~=nil)or(string.find(string.lower(zone),term,1,true)~=nil));if match then table.insert(list,d)end end end;
      countDisplay:SetText(string.format("(Showing %d of %d)", #list, totalInstance));
      table.sort(list,function(a,b)local zoneA=a.zone or"";local zoneB=b.zone or"";if zoneA~=zoneB then return zoneA<zoneB end;local la=tonumber(a.lastSeen)or 0;local lb=tonumber(b.lastSeen)or 0;if la~=lb then return la>lb end;return(a.itemID or 0)<(b.itemID or 0)end);local offset=FauxScrollFrame_GetOffset(scroll);local total=#list;FauxScrollFrame_Update(scroll,total,ROWS,ROWH);for i=1,ROWS do local idx=i+offset;local row=rows[i];local d=list[idx];if d then row:Show();local lootedByMe=L.db and L.db.char and L.db.char.looted and L.db.char.looted[d.guid]and true or false;local label=string.format("%s | %s | %s",d.itemLink or(d.itemID and("item:"..d.itemID)or"item"),d.zone or"Instance",colorizeStatus(d.status or STATUS_UNCONFIRMED));row.txt:SetText(label);styleRowButtons(row,lootedByMe);row.btnLoot.disc,row.btnUnl.disc=d,d;row.btnLoot:SetScript("OnClick",function(self)local dd=self.disc;if dd and dd.guid then setLooted(dd.guid,true);page.refresh()end end);row.btnUnl:SetScript("OnClick",function(self)local dd=self.disc;if dd and dd.guid then setLooted(dd.guid,false);page.refresh()end end)else row:Hide();row.btnLoot.disc,row.btnUnl.disc=nil,nil end end
  end;
  scroll:SetScript("OnVerticalScroll",function(self,delta)FauxScrollFrame_OnVerticalScroll(self,delta,ROWH,page.refresh)end);edit:SetScript("OnTextChanged",page.refresh);page:SetScript("OnShow",page.refresh);return page
end

local function EnsureDiscoveriesPanel()
  if panel then return end; panel=CreateFrame("Frame","LootCollectorDiscoveriesPanel",InterfaceOptionsFramePanelContainer); panel.name="Discoveries"; panel.parent="LootCollector"; local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); title:SetPoint("TOPLEFT",16,-16); title:SetText("LootCollector Discoveries"); tabs[1]=CreateTab(panel,1,"Import/Export"); tabs[2]=CreateTab(panel,2,"Looted"); tabs[3]=CreateTab(panel,3,"All World"); tabs[4]=CreateTab(panel,4,"Instances"); tabs[1]:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-8); tabs[2]:SetPoint("LEFT",tabs[1],"RIGHT",8,0); tabs[3]:SetPoint("LEFT",tabs[2],"RIGHT",8,0); tabs[4]:SetPoint("LEFT",tabs[3],"RIGHT",8,0); if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(panel,4)else panel.numTabs=4 end; if PanelTemplates_SetTab then PanelTemplates_SetTab(panel,1)end; activeTab=1; local content=CreateFrame("Frame",nil,panel); content:SetPoint("TOPLEFT",panel,"TOPLEFT",16,-88); content:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-16,16); tabPages[1]=BuildImportExportPage(content); tabPages[2]=BuildLootedListPage(content,"Looted by this character"); tabPages[3]=BuildAllListPage(content,"All World Discoveries"); tabPages[4]=BuildInstanceListPage(content,"Instance Discoveries"); for i,page in ipairs(tabPages)do page:ClearAllPoints(); page:SetPoint("TOPLEFT",content,"TOPLEFT",0,0); page:SetPoint("BOTTOMRIGHT",content,"BOTTOMRIGHT",0,0); page:SetShown(i==1)end; panel:SetScript("OnShow",function()local sel=(PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(panel))or activeTab or 1; activeTab=sel; local page=tabPages[sel]; if page and page.refresh then page.refresh()end end); InterfaceOptions_AddCategory(panel)
end
SLASH_LCEXPORT1="/lcexport"; SlashCmdList["LCEXPORT"]=function(msg)OpenExportDialog(not(msg and msg:lower():find("nooverlay")))end;
SLASH_LCIMPORT1="/lcimport"; SlashCmdList["LCIMPORT"]=function()OpenImportDialog()end;
SLASH_LCLIST1="/lclist"; SlashCmdList["LCLIST"]=function()EnsureDiscoveriesPanel(); InterfaceOptionsFrame_OpenToCategory("LootCollector"); InterfaceOptionsFrame_OpenToCategory("Discoveries"); local sel=activeTab or 1; local page=tabPages[sel]; if page and page.refresh then page.refresh()end end;
function ImportExport:OnInitialize() EnsureDiscoveriesPanel() end
return ImportExport