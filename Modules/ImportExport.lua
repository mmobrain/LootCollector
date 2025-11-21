

local L = LootCollector
local ImportExport = L:NewModule("ImportExport", "AceEvent-3.0")
local AceSerializer = LibStub("AceSerializer-3.0", true)
local LibDeflate = LibStub("LibDeflate", true)

local HEADER = "!LC1!"
local now = time

local Constants = L:GetModule("Constants", true)
local STATUS = Constants and Constants.STATUS or { UNCONFIRMED = "UNCONFIRMED", CONFIRMED = "CONFIRMED", FADING = "FADING", STALE = "STALE" }

local STATEABBREVIATIONS = {
	[STATUS.UNCONFIRMED] = "U",
	[STATUS.CONFIRMED] = "C",
	[STATUS.FADING] = "F",
	[STATUS.STALE] = "S",
}

local ZoneList = L:GetModule("ZoneList", true)

local DropDownMenu = CreateFrame("Frame", "LootCollectorListDropDown", UIParent, "UIDropDownMenuTemplate")
local menuList = {}
local panel, tabs, tabPages, activeTab = nil, {}, {}, 1

function ImportExport:RefreshAllTabs()
    if tabPages then
        for _, page in ipairs(tabPages) do
            if page and page.refresh then
                page.refresh()
            end
        end
    end
end

StaticPopupDialogs["LOOTCOLLECTOR_MERGE_STARTER_CONFIRM"] = {
  text = "Are you sure you want to merge the starter database?\n\nYour existing discoveries will be kept and updated if necessary.",
  button1 = "Merge",
  button2 = "Cancel",
  OnAccept = function()
    
    if type(_G.LootCollector_OptionalDB_Data) == "table" and _G.LootCollector_OptionalDB_Data.data ~= "" then
      print("|cff00ff00LootCollector:|r Merging starter data with existing database...")
      ImportExport:ApplyImportString(_G.LootCollector_OptionalDB_Data.data, "MERGE", false, true, true)
    else
      print("|cffff7f00LootCollector:|r Import from starter DB failed: The data seems to be missing.")
    end
  end,
  timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = true,
}

StaticPopupDialogs["LOOTCOLLECTOR_OVERRIDE_STARTER_CONFIRM"] = {
  text = "|cffff0000WARNING:|r Are you sure you want to OVERWRITE your database with the starter data?\n\nAll of your current discoveries will be PERMANENTLY DELETED. This cannot be undone.",
  button1 = "Yes, Overwrite",
  button2 = "Cancel",
  OnAccept = function()
    
    if type(_G.LootCollector_OptionalDB_Data) == "table" and _G.LootCollector_OptionalDB_Data.data ~= "" then
      print("|cffff7f00LootCollector:|r Overwriting existing database with starter data...")
      ImportExport:ApplyImportString(_G.LootCollector_OptionalDB_Data.data, "OVERRIDE", false, true, true)
    else
      print("|cffff7f00LootCollector:|r Import from starter DB failed: The data in customimport.lua seems to be missing.")
    end
  end,
  timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = true,
}

StaticPopupDialogs["LOOTCOLLECTOR_FILE_IMPORT_CONFIRM"] = {
  text = "Data found in customimport.lua. Choose an import method.\n\nThis will use data from the file, not the paste box.",
  button1 = "Import",
  button2 = "Cancel",
  hasCheckBox = true,
  OnShow = function(self)
    if self.CheckBox then
        self.CheckBox:SetText("Override existing data (otherwise, will merge)")
        self.CheckBox:Show()
    end
  end,
  OnAccept = function(self, data)
    local override = self.CheckBox and self.CheckBox:GetChecked()
    local mode = override and "OVERRIDE" or "MERGE"
    local withOverlays = data and data.withOverlays
    local skipBlacklist = data and data.skipBlacklist
    local skipWhitelist = data and data.skipWhitelist
    
    if type(_G.LootCollector_CustiomImport) == "string" and _G.LootCollector_CustiomImport ~= "" then
      ImportExport:ApplyImportString(_G.LootCollector_CustiomImport, mode, withOverlays, skipBlacklist, skipWhitelist)
    else
      print("|cffff7f00LootCollector:|r Import from file failed: The data in customimport.lua seems to have disappeared.")
    end
  end,
  OnHide = function(self)
    if self.CheckBox then
      self.CheckBox:SetChecked(false)
    end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
  showAlert = true,
}

StaticPopupDialogs["LOOTCOLLECTOR_PURGE_CONFIRM"] = {
	text = "Are you sure you want to permanently delete ALL discoveries AND Blackmarket vendor data from the database?\n\n|cffff7f00This will NOT affect your settings, looted history, or other character data.|r\n\n|cffff0000This action cannot be undone!|r",
	button1 = "Yes, Purge Data",
	button2 = "Cancel",
	OnAccept = function()
		local Core = L:GetModule("Core", true)
		if Core and Core.ClearDiscoveries then
			Core:ClearDiscoveries()
			local Map = L:GetModule("Map", true)
			if Map and Map.Update then Map:Update() end
			
            local IE = L:GetModule("ImportExport", true)
            if IE and IE.RefreshAllTabs then
                IE:RefreshAllTabs()
            end
			
			print("|cff00ff00LootCollector|r All discovery and Blackmarket vendor data has been purged.")
		else
			print("|cffff7f00LootCollector|r Core module not available for clearing.")
		end
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

StaticPopupDialogs["LOOTCOLLECTOR_NUKE_CONFIRM"] = {
	text = "Are you sure you want to permanently delete ALL LootCollector data?\n\n|cffff0000This will reset the addon to its default state, deleting ALL discoveries, ALL looted history for ALL characters, and ALL settings. THIS CANNOT BE UNDONE!|r",
	button1 = "|cffff0000Yes, Factory Reset|r",
	button2 = "Cancel",
	OnAccept = function()
		if L and L.db and L.db.ResetDB then
            print("|cffff0000LootCollector:|r Performing factory reset... The addon will reload.")
            L.db:ResetDB()
            ReloadUI()
        else
            print("|cffff7f00LootCollector:|r Database object not available for a full reset.")
        end
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

local function longKeyRecordFromShort(d)
	if type(d) ~= "table" then return nil end
	return {
		guid = d.g,
		continent = d.c,
		zoneID = d.z,
		instanceID = d.iz,
		itemID = d.i,
		coords = (d.xy and {x = tonumber(d.xy.x) or 0, y = tonumber(d.xy.y) or 0}) or {x=0,y=0},
		itemLink = d.il,
		itemQuality = d.q,
		timestamp = d.t0,
		lastSeen = d.ls,
		statusTs = d.st,
		status = d.s,
		mergeCount = d.mc,
		foundBy_player = d.fp,
		originator = d.o,
		source = d.src,
		class = d.cl,
		itemType = d.it,
		itemSubType = d.ist,
		discoveryType = d.dt,
		deletedBy = d.dby,
		messageID = d.mid,
		announceCount = d.ac,
		nextDueTs = d.nd,
		lastAnnouncedTs = d.at,
		ackDelCount = d.adc,
		onHold = d.onHold,
        fp_votes = d.fp_votes,
        
        vendorType = d.vendorType,
        vendorName = d.vendorName,
        vendorItems = d.vendorItems,
	}
end

local function countTableKeys(t)
	local n = 0
	if type(t) == "table" then
		for _ in pairs(t) do n = n + 1 end
	end
	return n
end

local function buildExport(includeOverlays)
    
    local discoveries, count = {}, 0
    
    
    local dbDiscs = L:GetDiscoveriesDB()
    if dbDiscs then
        for guid, d in pairs(dbDiscs) do
            local rec = longKeyRecordFromShort(d)
            if rec and rec.guid then
                discoveries[rec.guid] = rec
                count = count + 1
            end
        end
    end

    
    local blackmarketVendors, bmcount = {}, 0
    
    local dbVends = L:GetVendorsDB()
    if dbVends then
        for guid, d in pairs(dbVends) do
            local rec = longKeyRecordFromShort(d)
            if rec and rec.guid then
                blackmarketVendors[rec.guid] = rec
                bmcount = bmcount + 1
            end
        end
    end

    
    local overlays = nil
    if includeOverlays then
        if L.db and L.db.char then
            overlays = { looted = {}, hidden = {} }
            for guid, ts in pairs(L.db.char.looted or {}) do
                overlays.looted[guid] = tonumber(ts) or 1
            end
            for guid, on in pairs(L.db.char.hidden or {}) do
                if on then
                    overlays.hidden[guid] = true
                end
            end
        end
    end

    
    local profilesharing = nil
    if L.db and L.db.profile and L.db.profile.sharing then
        profilesharing = { blockList = {}, whiteList = {} }
        for k, v in pairs(L.db.profile.sharing.blockList or {}) do
            profilesharing.blockList[k] = v
        end
        for k, v in pairs(L.db.profile.sharing.whiteList or {}) do
            profilesharing.whiteList[k] = v
        end
    end

    local tnow = time()
    local realmKey = L.GetActiveRealmKey and L:GetActiveRealmKey() or "Unknown Realm"

    return {
        meta = {
            v = 1,
            addon = "LootCollector",
            ts = tnow,
            realm = realmKey,
            counts = {
                discoveries = count,
                blackmarketVendors = bmcount,
                looted = overlays and countTableKeys(overlays.looted) or 0,
                hidden = overlays and countTableKeys(overlays.hidden) or 0,
            },
        },
        discoveries = discoveries,
        blackmarketVendors = blackmarketVendors,
        overlays = overlays,
        profilesharing = profilesharing,
    }
end

local function serialize(tbl)
	if not AceSerializer then return nil end
	local ok, b = pcall(AceSerializer.Serialize, AceSerializer, tbl)
	if ok and b then
		local _, c = pcall(LibDeflate.CompressDeflate, LibDeflate, b, {level=8})
		if c then return LibDeflate:EncodeForPrint(c) end
	end
	return nil
end

local function deserialize(s)
	if not AceSerializer or not LibDeflate then return nil, "Libs missing" end
	if type(s) ~= "string" then return nil, "Invalid input type" end
	
	local body = s:match("^!LC1!(.+)$")
	if not body then return nil, "Bad header" end
	
	local bytes = LibDeflate:DecodeForPrint(body)
	if not bytes then return nil, "Decode failed" end
	
	local unz = LibDeflate:DecompressDeflate(bytes)
	if not unz then return nil, "Decompress failed" end
	
	local ok, _, tbl = pcall(AceSerializer.Deserialize, AceSerializer, unz)
	if ok and type(tbl) == "table" then return tbl end
	
	return nil, "Deserialize final step failed"
end

function ImportExport:ExportString(includeOverlays)
	local payload = buildExport(includeOverlays)
	local text = serialize(payload)
	if not text then return nil, "Serialization failed" end
	return HEADER .. text
end

function ImportExport:ApplyImport(parsed, mode, withOverlays, skipBlacklist, skipWhitelist, isStarterDB)
	if not L.db then return nil, "DB not ready" end

    local cityZoneIDsToPurge = {
        [1] = { [382] = true, [322] = true, [363] = true },
        [2] = { [342] = true, [302] = true, [383] = true },
        [3] = { [482] = true },
        [4] = { [505] = true }
    }
	
	local disc = parsed.discoveries or {}
	local applied = {total = 0, bm_total = 0, overlays = 0, profilelists = 0, skippedCity = 0}
	
    
	local db = L:GetDiscoveriesDB()
    local bm_db = L:GetVendorsDB()
    
    
    if not db or not bm_db then return nil, "Realm DBs missing" end

	if mode == "OVERRIDE" then
        
		wipe(db)
        wipe(bm_db)
	end
	
    local currentTime = time()

	for guid, d in pairs(disc) do
        if d.continent and d.zoneID and cityZoneIDsToPurge[d.continent] and cityZoneIDsToPurge[d.continent][d.zoneID] then
            applied.skippedCity = applied.skippedCity + 1
        else
            local shortRecord = {
                g = d.guid,
                c = d.continent,
                z = d.zoneID,
                iz = d.instanceID or 0,
                i = d.itemID,
                xy = d.coords,
                il = d.itemLink,
                q = d.itemQuality or 0,
                t0 = d.timestamp,
                ls = d.lastSeen,
                st = d.statusTs,
                s = d.status,
                mc = d.mergeCount,
                fp = d.foundBy_player,
                o = d.originator,
                src = d.source,
                cl = d.class,
                it = d.itemType or 0,
                ist = d.itemSubType or 0,
                dt = d.discoveryType or 0,
                dby = d.deletedBy,
                mid = d.messageID,
                
                fp_votes = d.fp_votes,
                ack_votes = d.ack_votes, 
                
                vendorType = d.vendorType,
                vendorName = d.vendorName,
                vendorItems = d.vendorItems,
            }

            shortRecord.ac = math.random(2, 4)
            shortRecord.at = currentTime
            shortRecord.nd = nil

            if not shortRecord.fp_votes and shortRecord.fp and shortRecord.t0 then
                shortRecord.fp_votes = { [shortRecord.fp] = { score = 1, t0 = shortRecord.t0 } }
            end
            
            db[guid] = shortRecord
            applied.total = applied.total + 1
        end
	end
	
    local bm_vendors = parsed.blackmarketVendors or {}
    for guid, d in pairs(bm_vendors) do
        if d.continent and d.zoneID and cityZoneIDsToPurge[d.continent] and cityZoneIDsToPurge[d.continent][d.zoneID] then
            applied.skippedCity = applied.skippedCity + 1
        else
            local shortRecord = {
                g = d.guid,
                c = d.continent,
                z = d.zoneID,
                iz = d.instanceID or 0,
                i = d.itemID,
                xy = d.coords,
                il = d.itemLink,
                t0 = d.timestamp,
                ls = d.lastSeen,
                st = d.statusTs,
                s = d.status,
                fp = d.foundBy_player,
                o = d.originator,
                dt = d.discoveryType or 0,
                vendorType = d.vendorType,
                vendorName = d.vendorName,
                vendorItems = d.vendorItems,
            }
            bm_db[guid] = shortRecord
            applied.bm_total = applied.bm_total + 1
        end
    end

    
	if withOverlays then
		if L.db and L.db.char and parsed.overlays then
			if mode == "OVERRIDE" then
				L.db.char.looted = {}
				L.db.char.hidden = {}
			end
			L.db.char.looted = L.db.char.looted or {}
			for guid, ts in pairs(parsed.overlays.looted or {}) do
				L.db.char.looted[guid] = tonumber(ts) or time()
				applied.overlays = applied.overlays + 1
			end
			L.db.char.hidden = L.db.char.hidden or {}
			for guid, on in pairs(parsed.overlays.hidden or {}) do
				if on then L.db.char.hidden[guid] = true end
			end
		end
    end
    
	if L.db and L.db.profile and L.db.profile.sharing and parsed.profilesharing then
        L.db.profile.sharing.blockList = L.db.profile.sharing.blockList or {}
        L.db.profile.sharing.whiteList = L.db.profile.sharing.whiteList or {}
        
        if not skipBlacklist then
            for name, _ in pairs(parsed.profilesharing.blockList or {}) do
                if not L.db.profile.sharing.blockList[name] then
                    L.db.profile.sharing.blockList[name] = true
                    applied.profilelists = applied.profilelists + 1
                end
            end
        end

        if not skipWhitelist then
            for name, _ in pairs(parsed.profilesharing.whiteList or {}) do
                if not L.db.profile.sharing.whiteList[name] then
                    L.db.profile.sharing.whiteList[name] = true
                    applied.profilelists = applied.profilelists + 1
                end
            end
        end
    end

    if _G.LootCollectorDB_Asc then
        _G.LootCollectorDB_Asc._schemaVersion = 7 
    end
	
	local Map = L:GetModule("Map", true)
	if Map then
        
        Map.cacheIsDirty = true
        
        if Map.Update then Map:Update() end
        if Map.UpdateMinimap then Map:UpdateMinimap() end
    end
	
	return applied
end

function ImportExport:ApplyImportString(importString, mode, withOverlays, skipBlacklist, skipWhitelist)
    local parsed, err = deserialize(importString)
    if not parsed then
        print("|cffff7f00LootCollector|r Import failed: " .. tostring(err))
        return
    end

    
    local isStarterDB = (_G.LootCollector_OptionalDB_Data and importString == _G.LootCollector_OptionalDB_Data.data)

    
    if not isStarterDB then
        local activeRealm = L.GetActiveRealmKey and L:GetActiveRealmKey() or nil
        local srcRealm = parsed.meta and parsed.meta.realm or nil

        
        
        local function isAllowedCrossRealm(a, b)
            if not a or not b then return false end
            if (a == "Bronzebeard - Warcraft Reborn" and b == "Malfurion - Warcraft Reborn") then return true end
            if (a == "Malfurion - Warcraft Reborn" and b == "Bronzebeard - Warcraft Reborn") then return true end
            return false
        end

        if not srcRealm or srcRealm == "" then
            print("|cffff7f00LootCollector|r Import rejected: the data has no realm metadata. Please re-export with a newer version.") 
            return
        end

        if activeRealm and srcRealm ~= activeRealm and not isAllowedCrossRealm(srcRealm, activeRealm) then
            print(string.format("|cffff7f00LootCollector|r Import rejected: source realm '%s' does not match current realm '%s'.", tostring(srcRealm), tostring(activeRealm)))
            return
        end
    end

    local res, err2 = self:ApplyImport(parsed, mode, withOverlays, skipBlacklist, skipWhitelist, isStarterDB)
    if not res then
        print("|cffff7f00LootCollector|r Failed to apply import: " .. tostring(err2))
        return
    end

    local msg = string.format("|cff00ff00LootCollector|r Import successful! Processed %d discoveries.", res.total)
    if res.bm_total > 0 then
        msg = msg .. string.format(" Processed %d vendors.", res.bm_total)
    end
    if isStarterDB then
        msg = msg .. " Reinforcement schedule has been pre-staggered."
    elseif res.total > 0 then
        msg = msg .. " Reinforcement schedule has been staggered to prevent network spam."
    end
    if res.overlays > 0 then
        msg = msg .. string.format(" Applied %d overlay entries.", res.overlays)
    end
    if res.profilelists > 0 then
        msg = msg .. string.format(" Merged %d player list entries.", res.profilelists)
    end
    print(msg)

    
    local Core = L:GetModule("Core", true)
    if Core and Core.RemapLootedHistoryV6 then
        Core:RemapLootedHistoryV6()
    end

    if Core then Core:ScanDatabaseForUncachedItems() end
end

local function CreateEditDialog(name, title, isReadOnly)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetSize(560, 380)
	f:SetPoint("CENTER")
	f:Hide()
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
	f.title:SetText(title or "")
	
	f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	f.scroll:SetPoint("TOPLEFT", 16, -36)
	f.scroll:SetPoint("BOTTOMRIGHT", -34, 48)
	
	f.edit = CreateFrame("EditBox", nil, f.scroll)
	f.edit:SetMultiLine(true)
	f.edit:SetFontObject(ChatFontNormal)
	f.edit:SetWidth(500)
	f.edit:SetAutoFocus(false)
	f.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.scroll:SetScrollChild(f.edit)
	
	f.btnClose = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.btnClose:SetSize(100, 22)
	f.btnClose:SetPoint("BOTTOMRIGHT", -12, 12)
	f.btnClose:SetText("Close")
	f.btnClose:SetScript("OnClick", function() f:Hide() end)
	
	if isReadOnly then
		f.edit:EnableMouse(true)
		f.edit:SetScript("OnTextChanged", function() end)
		f.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	end
	
	return f
end

local function OpenExportDialog(includeOverlays)
	ImportExport.exportDialog = ImportExport.exportDialog or CreateEditDialog("LootCollectorExportDialog", "LootCollector Export", true)
	local s, err = ImportExport:ExportString(includeOverlays)
	ImportExport.exportDialog.edit:SetText(s or ("export failed: " .. tostring(err or "?")))
	ImportExport.exportDialog:Show()
end

local function OpenImportDialog()
	if not ImportExport.importDialog then
		ImportExport.importDialog = CreateEditDialog("LootCollectorImportDialog", "LootCollector Import", false)
	end
	local f = ImportExport.importDialog
	
	if not f.isRedesigned then
		f:SetSize(560, 520)

		if f.btnMerge then f.btnMerge:Hide() end
		if f.btnOverride then f.btnOverride:Hide() end
		if f.chkOverlays then f.chkOverlays:Hide() end

		local headerFile = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		headerFile:SetPoint("TOPLEFT", 16, -40)
		headerFile:SetText("Method 1: Import from File (Recommended)")

		local descFile = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		descFile:SetWidth(500)
		descFile:SetPoint("TOPLEFT", headerFile, "BOTTOMLEFT", 0, -8)
		descFile:SetText("For large imports to avoid freezing the game, place your import string inside the AddOns\\LootCollector\\DBopt\\customimport.lua file.")
		descFile:SetJustifyH("LEFT")

		f.btnImportFile = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		f.btnImportFile:SetSize(220, 24)
		f.btnImportFile:SetPoint("TOP", descFile, "BOTTOM", 0, -12)
		f.btnImportFile:SetText("Import from customimport.lua")
		
		local separator = f:CreateTexture(nil, "ARTWORK")
		separator:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
		separator:SetSize(500, 2)
		separator:SetPoint("TOP", f.btnImportFile, "BOTTOM", 0, -20)
		
		local headerPaste = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		headerPaste:SetPoint("TOP", separator, "BOTTOM", 0, -12)
		headerPaste:SetText("Method 2: Paste String (For small imports)")

		local warningPaste = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		warningPaste:SetTextColor(1, 0.8, 0.2)
		warningPaste:SetPoint("TOP", headerPaste, "BOTTOM", 0, -6)
		warningPaste:SetText("WARNING: Pasting very large strings may cause the game to freeze temporarily.")

		f.scroll:ClearAllPoints()
		f.scroll:SetPoint("TOPLEFT", warningPaste, "BOTTOMLEFT", -1, -8)
		f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 130)

		f.btnClose:ClearAllPoints()
		f.btnClose:SetPoint("BOTTOMRIGHT", -12, 12)
		
		f.btnOverridePaste = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		f.btnOverridePaste:SetSize(120, 22)
		f.btnOverridePaste:SetPoint("RIGHT", f.btnClose, "LEFT", -8, 0)
		f.btnOverridePaste:SetText("Override from Paste")

		f.btnMergePaste = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		f.btnMergePaste:SetSize(120, 22)
		f.btnMergePaste:SetPoint("RIGHT", f.btnOverridePaste, "LEFT", -8, 0)
		f.btnMergePaste:SetText("Merge from Paste")
		
		f.chkSkipBlacklist = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
		f.chkSkipBlacklist:SetPoint("BOTTOMLEFT", 16, 48)
		f.chkSkipBlacklist.text = f.chkSkipBlacklist:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		f.chkSkipBlacklist.text:SetPoint("LEFT", f.chkSkipBlacklist, "RIGHT", 4, 0)
		f.chkSkipBlacklist.text:SetText("Skip importing blacklist")
		f.chkSkipBlacklist:SetChecked(false)

        f.chkSkipWhitelist = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
		f.chkSkipWhitelist:SetPoint("BOTTOMLEFT", f.chkSkipBlacklist, "TOPLEFT", 0, 4)
		f.chkSkipWhitelist.text = f.chkSkipWhitelist:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		f.chkSkipWhitelist.text:SetPoint("LEFT", f.chkSkipWhitelist, "RIGHT", 4, 0)
		f.chkSkipWhitelist.text:SetText("Skip importing whitelist")
		f.chkSkipWhitelist:SetChecked(true)
        
		f.chkOverlaysGlobal = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
		f.chkOverlaysGlobal:SetPoint("BOTTOMLEFT", f.chkSkipWhitelist, "TOPLEFT", 0, 4)
		f.chkOverlaysGlobal.text = f.chkOverlaysGlobal:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		f.chkOverlaysGlobal.text:SetPoint("LEFT", f.chkOverlaysGlobal, "RIGHT", 4, 0)
		f.chkOverlaysGlobal.text:SetText("Import personal data (looted/hidden status)")
		f.chkOverlaysGlobal:SetChecked(true)

		f.btnImportFile:SetScript("OnClick", function()
			if type(_G.LootCollector_CustiomImport) == "string" and _G.LootCollector_CustiomImport ~= "" then
				local popupData = { 
                    withOverlays = f.chkOverlaysGlobal:GetChecked(),
                    skipBlacklist = f.chkSkipBlacklist:GetChecked(),
                    skipWhitelist = f.chkSkipWhitelist:GetChecked()
                }
				StaticPopup_Show("LOOTCOLLECTOR_FILE_IMPORT_CONFIRM", nil, nil, popupData)
			else
				print("|cffff7f00LootCollector:|r The 'customimport.lua' file is empty or could not be loaded. Please add an import string to it.")
			end
		end)

		local function applyPaste(mode)
			local s = f.edit:GetText() or ""
			if s == "" then
				print("|cffff7f00LootCollector:|r Paste box is empty.")
				return
			end
			local withOverlays = f.chkOverlaysGlobal:GetChecked()
            local skipBlacklist = f.chkSkipBlacklist:GetChecked()
            local skipWhitelist = f.chkSkipWhitelist:GetChecked()
			ImportExport:ApplyImportString(s, mode, withOverlays, skipBlacklist, skipWhitelist)
		end

		f.btnMergePaste:SetScript("OnClick", function() applyPaste("MERGE") end)
		f.btnOverridePaste:SetScript("OnClick", function() applyPaste("OVERRIDE") end)

		f:SetScript("OnMouseDown", function(self, button)
			if not MouseIsOver(self.btnImportFile) 
			   and not MouseIsOver(self.btnMergePaste) 
			   and not MouseIsOver(self.btnOverridePaste) 
			   and not MouseIsOver(self.chkOverlaysGlobal)
               and not MouseIsOver(self.chkSkipBlacklist)
               and not MouseIsOver(self.chkSkipWhitelist)
			   and not MouseIsOver(self.btnClose) 
			   and not MouseIsOver(self.scroll.ScrollBar) then
				self.edit:SetFocus()
			end
		end)

		f.isRedesigned = true
	end

	f.edit:SetText("")
	f:Show()
end

local ROWS, ROWH = 14, 24

local STATUSHEX = {
	[STATUS.CONFIRMED] = "ff20ff20",
	[STATUS.UNCONFIRMED] = "fff0c000",
	[STATUS.FADING] = "ffff7f00",
	[STATUS.STALE] = "ff9d9d9d",
}

local function colorizeStatusAbbrev(status)
	local hex = STATUSHEX[status] or "ffffffff"
	local letter = STATEABBREVIATIONS[status] or "?"
	return "|c"..hex..letter.."|r"
end

local function abbreviateZoneIfNeeded(itemName, zoneName, d)
	local iname = tostring(itemName) or ""
	local zname = tostring(zoneName) or ""

	if string.len(iname) + string.len(zname) > 38 then
        L._debug("AbbrevCheck", string.format("Line too long (%d > 38). Checking for abbreviation.", string.len(iname) + string.len(zname)))
        L._debug("AbbrevCheck", string.format(" -> Item: '%s', Zone: '%s'", iname, zname))
        L._debug("AbbrevCheck", string.format(" -> Discovery data: c=%s, z=%s, iz=%s", tostring(d.c), tostring(d.z), tostring(d.iz)))
		if ZoneList then
            
            if (d.iz or 0) > 0 and ZoneList.IZ_TO_ABBREVIATIONS then
                local lookupID = (d.z == 0 and d.iz) or d.z
                L._debug("AbbrevCheck", " -> Is instance (iz > 0). Checking IZ_TO_ABBREVIATIONS with key: " .. tostring(lookupID))
                if ZoneList.IZ_TO_ABBREVIATIONS[lookupID] then
                    local abbrev = ZoneList.IZ_TO_ABBREVIATIONS[lookupID]
                    L._debug("AbbrevCheck", " -> SUCCESS: Found instance abbreviation: '" .. abbrev .. "'")
                    return abbrev
                else
                    L._debug("AbbrevCheck", " -> FAILED: No instance abbreviation found for ID " .. tostring(lookupID))
                end
            end
            
			if ZoneList.ZONEABBREVIATIONS then
                L._debug("AbbrevCheck", " -> Checking ZONEABBREVIATIONS with key (zname): '" .. zname .. "'")
				if ZoneList.ZONEABBREVIATIONS[zname] then
                    local abbrev = ZoneList.ZONEABBREVIATIONS[zname]
					L._debug("AbbrevCheck", " -> SUCCESS: Found world zone abbreviation: '" .. abbrev .. "'")
                    return abbrev
				else
                    L._debug("AbbrevCheck", " -> FAILED: No world zone abbreviation found for that name.")
                end
			end
		end
	end

	return zname
end

local function fmtCoords(d)
	local x = 0
	local y = 0
	if d and d.xy then
		x = tonumber(d.xy.x) or 0
		y = tonumber(d.xy.y) or 0
	end
	return string.format("|cffffd100%.2f, %.2f|r", x * 100, y * 100)
end

local function FocusOnDiscovery(d)
	if not d then return end
	local Map = L:GetModule("Map", true)
	if Map and Map.FocusOnDiscovery then
		Map:FocusOnDiscovery(d)
	end
end

local function setLooted(guid, on)
	if not L.db and L.db.char then return end
	L.db.char.looted = L.db.char.looted or {}
	if on then
		L.db.char.looted[guid] = now()
	else
		L.db.char.looted[guid] = nil
	end
	local Map = L:GetModule("Map", true)
	if Map and Map.Update then Map:Update() end
end

local function CreateTab(parent, id, text)
	local btn = CreateFrame("Button", parent:GetName().."Tab"..id, parent, "OptionsFrameTabButtonTemplate")
	btn:SetID(id)
	btn:SetText(text)
	if PanelTemplates_TabResize then
		PanelTemplates_TabResize(btn, 0)
	end
	btn:SetScript("OnClick", function(self)
		PanelTemplates_SetTab(parent, self:GetID())
		activeTab = self:GetID()
		for i, page in ipairs(tabPages) do
			page:SetShown(i == activeTab)
			if page:IsShown() and page.refresh then
				page.refresh()
			end
		end
	end)
	return btn
end

local function BuildImportExportPage(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetAllPoints(parent)
	
	local t = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	t:SetPoint("TOPLEFT", 0, 0)
	t:SetText("Import / Export")
	
	local b1 = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	b1:SetSize(160, 22)
	b1:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
	b1:SetText("Export with overlays")
	b1:SetScript("OnClick", function() OpenExportDialog(true) end)
	
	local b2 = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	b2:SetSize(160, 22)
	b2:SetPoint("LEFT", b1, "RIGHT", 8, 0)
	b2:SetText("Export canonical only")
	b2:SetScript("OnClick", function() OpenExportDialog(false) end)
	
	local b3 = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	b3:SetSize(120, 22)
	b3:SetPoint("LEFT", b2, "RIGHT", 8, 0)
	b3:SetText("Import from String")
	b3:SetScript("OnClick", OpenImportDialog)
	
	local btnMergeStarter = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	btnMergeStarter:SetSize(180, 22)
	btnMergeStarter:SetPoint("TOPLEFT", b1, "BOTTOMLEFT", 0, -8)
	btnMergeStarter:SetText("Merge Starter Database")
	btnMergeStarter:SetScript("OnClick", function()
        
		if _G.LootCollector_OptionalDB_Data and _G.LootCollector_OptionalDB_Data.data then
			StaticPopup_Show("LOOTCOLLECTOR_MERGE_STARTER_CONFIRM")
		else
			print("|cffff7f00LootCollector:|r Starter database (db.lua) not found or is empty.")
		end
	end)

	local btnOverrideStarter = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	btnOverrideStarter:SetSize(220, 22)
	btnOverrideStarter:SetPoint("LEFT", btnMergeStarter, "RIGHT", 8, 0)
	btnOverrideStarter:SetText("|cffff7f00Override With Starter Database|r")
	btnOverrideStarter:SetScript("OnClick", function()
		
		if _G.LootCollector_OptionalDB_Data and _G.LootCollector_OptionalDB_Data.data then
			StaticPopup_Show("LOOTCOLLECTOR_OVERRIDE_STARTER_CONFIRM")
		else
			print("|cffff7f00LootCollector:|r Starter database (db.lua) not found or is empty.")
		end
	end)
	
	local help = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", btnMergeStarter, "BOTTOMLEFT", 0, -12)
	help:SetWidth(540)
	help:SetJustifyH("LEFT")
	help:SetText("Export copies a shareable string. Import pastes one from others. Overlays include per-character looted/hidden flags.")
	
	function p.refresh()
		
		local starterExists = _G.LootCollector_OptionalDB_Data and _G.LootCollector_OptionalDB_Data.data and _G.LootCollector_OptionalDB_Data.data ~= ""
		btnMergeStarter:SetShown(starterExists)
		btnOverrideStarter:SetShown(starterExists)
	end
	
    p:SetScript("OnShow", p.refresh)
    p.refresh()

	return p
end

local function BuildListPage(parent, titleText, dataFilterFunc)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints(parent)
	
	local title = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOPLEFT", 0, 0)
	title:SetText(titleText)
	
	local countDisplay = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countDisplay:SetPoint("TOPRIGHT", -4, 0)
	
	local edit = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
	edit:SetAutoFocus(false)
	edit:SetSize(220, 22)
	edit:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 40, -6)

	local lbl = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	lbl:SetPoint("RIGHT", edit, "LEFT", -4, 0)
	lbl:SetText("Filter:")

	local scroll = CreateFrame("ScrollFrame", nil, page, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -8, -8)
	scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 40)

	
	local rows = {}
	for i=1, ROWS do
		local r = CreateFrame("Frame", nil, page)
		r:SetHeight(ROWH)
		r:SetPoint("TOPLEFT", scroll, -36, -(i-1)*ROWH)
		r:SetPoint("RIGHT", scroll, -4, 0)
		
		r.txt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.txt:SetPoint("LEFT", r, "LEFT", 6, 0)
		r.txt:SetJustifyH("LEFT")
		r.txt:SetPoint("RIGHT", r.btnLoot, "LEFT", -6, 0)
		do
			local f, fs, fl = r.txt:GetFont()
			fs = fs or 12
			r.txt:SetFont(f, math.floor(fs * 1.2 + 0.5), fl)
		end
		
		r.measure = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		do
			local f, fs, fl = r.txt:GetFont()
			r.measure:SetFont(f, fs, fl)
		end
		r.measure:Hide()
		
		r.itemBtn = CreateFrame("Button", nil, r)
		r.itemBtn:SetHeight(ROWH)
		r.itemBtn:RegisterForClicks("AnyUp")
		
		r.zoneBtn = CreateFrame("Button", nil, r)
		r.zoneBtn:SetHeight(ROWH)
		
		local buttonSize = 22
		local buttonSpacing = 4
		
		r.btnDel = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
		r.btnDel:SetSize(buttonSize, buttonSize)
		r.btnDel:SetPoint("RIGHT", -4, 0)
		r.btnDel:SetText("D")
		r.btnDel:SetScript("OnEnter", function()
			GameTooltip:SetOwner(r.btnDel, "ANCHOR_TOP")
			GameTooltip:SetText("Delete")
			GameTooltip:Show()
		end)
		r.btnDel:SetScript("OnLeave", function() GameTooltip:Hide() end)
		
		r.btnNav = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
		r.btnNav:SetSize(buttonSize, buttonSize)
		r.btnNav:SetPoint("RIGHT", r.btnDel, "LEFT", -buttonSpacing, 0)
		r.btnNav:SetText("N")
		r.btnNav:SetScript("OnEnter", function()
			GameTooltip:SetOwner(r.btnNav, "ANCHOR_TOP")
			GameTooltip:SetText("Navigate")
			GameTooltip:Show()
		end)
		r.btnNav:SetScript("OnLeave", function() GameTooltip:Hide() end)
		
		r.btnUnl = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
		r.btnUnl:SetSize(buttonSize, buttonSize)
		r.btnUnl:SetPoint("RIGHT", r.btnNav, "LEFT", -buttonSpacing, 0)
		r.btnUnl:SetText("U")
		r.btnNav:SetScript("OnEnter", function()
			GameTooltip:SetOwner(r.btnNav, "ANCHOR_TOP")
			GameTooltip:SetText("Navigate")
			GameTooltip:Show()
		end)
		r.btnUnl:SetScript("OnLeave", function() GameTooltip:Hide() end)
		
		r.btnLoot = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
		r.btnLoot:SetSize(buttonSize, buttonSize)
		r.btnLoot:SetPoint("RIGHT", r.btnUnl, "LEFT", -buttonSpacing, 0)
		r.btnLoot:SetText("L")
		r.btnLoot:SetScript("OnEnter", function()
			GameTooltip:SetOwner(r.btnLoot, "ANCHOR_TOP")
			GameTooltip:SetText("Mark as Looted")
			GameTooltip:Show()
		end)
		r.btnLoot:SetScript("OnLeave", function() GameTooltip:Hide() end)
		
		r.txt:SetPoint("RIGHT", r.btnLoot, "LEFT", -8, 0)
		rows[i] = r
	end
	
	page.filterTimer = nil
	function page.refresh()
		if not L.db then return end
        
        
		local term = string.lower(edit:GetText() or "")
		local list, totalCount = {}, 0
		local discoveries = L:GetDiscoveriesDB() or {}
        
		for _, d in pairs(discoveries) do
			if type(d) == "table" and dataFilterFunc(d) then
				totalCount = totalCount + 1
				
                local name = d.il or (d.i and select(1, GetItemInfo(d.i))) or ""
                local zoneName
                do
                    local c = tonumber(d.c) or 0
                    local z = tonumber(d.z) or 0
                    local iz = tonumber(d.iz) or 0
                    
                    if z == 0 and iz > 0 then
                        zoneName = (ZoneList and ZoneList.ResolveIz and ZoneList:ResolveIz(iz)) or "Unknown Instance"
                    else
                        zoneName = (ZoneList and ZoneList.GetZoneName and ZoneList:GetZoneName(c, z)) or "Unknown Zone"
                    end
                end
                zoneName = zoneName or ""
                
                if term == "" or string.find(string.lower(name), term, 1, true) or string.find(string.lower(zoneName), term, 1, true) then
                    table.insert(list, d)
                end
			end
		end
		
		countDisplay:SetText(string.format("Showing %d of %d", #list, totalCount))
		
		table.sort(list, function(a, b)
			local la = tonumber(a.ls) or 0
			local lb = tonumber(b.ls) or 0
			if la ~= lb then return la > lb end
			return (a.i or 0) < (b.i or 0)
		end)
		
		local offset = FauxScrollFrame_GetOffset(scroll)
		FauxScrollFrame_Update(scroll, #list, ROWS, ROWH)
		
		for i=1, ROWS do
			local idx = i + offset
			local r = rows[i]
			local d = list[idx]
			
			if d then
				r:Show()
				r.discoveryData = d
				
				local lootedByMe = L.db.char.looted and L.db.char.looted[d.g]
				
				local zNameFull
				do
					local c = tonumber(d.c) or 0
					local z = tonumber(d.z) or 0
					local iz = tonumber(d.iz) or 0
                    
                    if z == 0 and iz > 0 then
                        zNameFull = (ZoneList and ZoneList.ResolveIz and ZoneList:ResolveIz(iz)) or "Unknown Instance"
                    else
                        zNameFull = (ZoneList and ZoneList.GetZoneName and ZoneList:GetZoneName(c, z)) or "Unknown Zone"
                    end
				end
				zNameFull = zNameFull or ""
				
				local itemNameClean = (d.i and select(1, GetItemInfo(d.i or 0))) or (d.il and d.il:match("|h%[(.-)%]|h")) or ""
				local zDisplay = abbreviateZoneIfNeeded(itemNameClean, zNameFull, d)
				local statusDisplay = colorizeStatusAbbrev(d.s)
				
				local itemLink = d.il or select(2, GetItemInfo(d.i or 0))
				local itemDisplay = itemLink or itemNameClean or ("item "..tostring(d.i or "?"))
				local coordsDisplay = fmtCoords(d)
				
				local statusText = ""
				if d.s == "STALE" or d.s == "FADING" then
					statusText = string.format(" |cffff9933[%s: %d]|r", d.s, d.adc or 0)
				end
				
				local label = string.format("%s%s | %s | %s | %s", 
					itemDisplay, statusText, zDisplay, coordsDisplay, statusDisplay)
				r.txt:SetText(label)
				
				if not r.bg then
					r.bg = r:CreateTexture(nil, "BACKGROUND")
					r.bg:SetAllPoints(r)
					r.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
				end
				
				if d.s == "STALE" then
					r.bg:SetVertexColor(1, 0.6, 0, 0.15)
					r.bg:Show()
				else
					r.bg:Hide()
				end
				
				local isLooted = lootedByMe and true or false
				r.btnLoot:SetEnabled(not isLooted)
				r.btnUnl:SetEnabled(isLooted)
				
				r.btnLoot:SetScript("OnClick", function()
					setLooted(d.g, true)
					page.refresh()
				end)
				
				r.btnUnl:SetScript("OnClick", function()
					setLooted(d.g, false)
					page.refresh()
				end)
				
				r.btnNav:SetScript("OnClick", function()
				    local Arrow = L:GetModule("Arrow", true)				    
				    if Arrow and Arrow.NavigateTo then
					  Arrow:NavigateTo(d)
				    end
				end)
				
				r.btnDel:SetScript("OnClick", function()
					StaticPopup_Show("LOOTCOLLECTOR_REMOVE_DISCOVERY", nil, nil, d.g)
				end)
				
				r.measure:SetText(itemDisplay .. " ")
				local itemSegWidth = r.measure:GetStringWidth() or 0
				
				r.measure:SetText(itemDisplay .. statusText .. " ")
				local itemWithBadgeWidth = r.measure:GetStringWidth() or 0
				
				r.measure:SetText(zDisplay)
				local zoneSegWidth = r.measure:GetStringWidth() or 0
				
				r.itemBtn:ClearAllPoints()
				r.itemBtn:SetPoint("LEFT", r.txt, "LEFT", 0, 0)
				r.itemBtn:SetWidth(itemSegWidth)
				
				r.itemBtn:SetScript("OnEnter", function(s)
					if itemLink then
						GameTooltip:SetOwner(s, "ANCHOR_CURSOR")
						GameTooltip:SetHyperlink(itemLink)
						GameTooltip:Show()
					end
				end)
				
				r.itemBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
				
				r.itemBtn:SetScript("OnClick", function(s, button)
					if not r.discoveryData then return end
					local data = r.discoveryData

					if IsControlKeyDown() and IsAltKeyDown() and button == "RightButton" then
						local zoneName = zNameFull
						local coords = string.format("%.1f, %.1f", (data.xy.x or 0) * 100, (data.xy.y or 0) * 100)
						local msg = string.format("%s @ %s (%s)", data.il, zoneName, coords)
						if ChatFrame1EditBox:IsVisible() then
							ChatFrame1EditBox:Insert(msg)
						else
							ChatFrame_OpenChat(msg)
						end
						return
					elseif IsShiftKeyDown() and IsAltKeyDown() and button == "LeftButton" then
						local Map = L:GetModule("Map", true)
						if Map and Map.OpenShowToDialog then
							Map:OpenShowToDialog(data)
						end
						return
					end

					if IsShiftKeyDown() then
						FocusOnDiscovery(data)
					elseif itemLink then
						GameTooltip:SetOwner(s, "ANCHOR_CURSOR")
						GameTooltip:SetHyperlink(itemLink)
						GameTooltip:Show()
					end
				end)
				
				local isAbbrev = ZoneList and ZoneList.ZONEABBREVIATIONS and ZoneList.ZONEABBREVIATIONS[zNameFull] ~= nil and ZoneList.ZONEABBREVIATIONS[zNameFull] == zDisplay
				
				r.zoneBtn:ClearAllPoints()
				r.zoneBtn:SetPoint("LEFT", r.txt, "LEFT", itemWithBadgeWidth, 0)
				r.zoneBtn:SetWidth(zoneSegWidth)
				
				if isAbbrev then
					r.zoneBtn:SetScript("OnEnter", function(s)
						GameTooltip:SetOwner(s, "ANCHOR_CURSOR")
						GameTooltip:AddLine(zNameFull, 1, 1, 1, true)
						GameTooltip:Show()
					end)
					r.zoneBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
				else
					r.zoneBtn:SetScript("OnEnter", nil)
					r.zoneBtn:SetScript("OnLeave", nil)
				end
				
			else
				r:Hide()
			end
		end
	end
	
	scroll:SetScript("OnVerticalScroll", function(s, dlt)
		FauxScrollFrame_OnVerticalScroll(s, dlt, ROWH, page.refresh)
	end)
	
	edit:SetScript("OnTextChanged", function()
        if page.filterTimer then
            C_Timer.CancelTimer(page.filterTimer)
        end
        page.filterTimer = C_Timer.After(0.7, page.refresh)
    end)
	page:SetScript("OnShow", page.refresh)
	
	if titleText == "All World Discoveries" then
		local purgeBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
		purgeBtn:SetSize(140, 24)
		purgeBtn:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 8)
		purgeBtn:SetText("|cffff7f00Purge Data|r")
		purgeBtn:SetScript("OnClick", function()
			StaticPopup_Show("LOOTCOLLECTOR_PURGE_CONFIRM")
		end)
		
        local nukeBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        nukeBtn:SetSize(140, 24)
        nukeBtn:SetPoint("RIGHT", purgeBtn, "LEFT", -8, 0)
        nukeBtn:SetText("|cffff0000Factory Reset|r")
        nukeBtn:SetScript("OnClick", function()
			StaticPopup_Show("LOOTCOLLECTOR_NUKE_CONFIRM")
		end)
	end
	
	return page
end

local function BuildBlackmarketPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    page.selectedVendorGuid = nil

    
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("Special Vendors")

    
	local edit = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
	edit:SetAutoFocus(false)
	edit:SetSize(220, 22)
	edit:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 40, -6)

	local lbl = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	lbl:SetPoint("RIGHT", edit, "LEFT", -4, 0)
	lbl:SetText("Filter:")

    
    local vendorScroll = CreateFrame("ScrollFrame", nil, page, "FauxScrollFrameTemplate")
    vendorScroll:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -18, -8)
    vendorScroll:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 40)
    vendorScroll:SetWidth(360)

    local vendorRows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, page)
        r:SetHeight(ROWH)
        r:SetPoint("TOPLEFT", vendorScroll, -36, -(i-1) * ROWH)
        r:SetPoint("RIGHT", vendorScroll, -4, 0)
        
        r:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
        
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints(r)
        r.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        
        r.txt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.txt:SetAllPoints(r)
        r.txt:SetJustifyH("LEFT")
        
        r:SetScript("OnClick", function(self)
            if self.discoveryData then
                if IsShiftKeyDown() then
                    FocusOnDiscovery(self.discoveryData)
                else
                    page.selectedVendorGuid = self.discoveryData.g
                    page.refresh()
                end
            end
        end)
        vendorRows[i] = r
    end

    
    local inventoryFrame = CreateFrame("Frame", nil, page)
    inventoryFrame:SetPoint("TOPLEFT", vendorScroll, "TOPRIGHT", 12, 0)
    inventoryFrame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 40)
    
    local inventoryTitle = inventoryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    inventoryTitle:SetPoint("TOPLEFT", 10, 0)
    inventoryTitle:SetText("Vendor Inventory")

    
    local invScroll = CreateFrame("ScrollFrame", nil, inventoryFrame, "FauxScrollFrameTemplate")
    invScroll:SetPoint("TOPLEFT", inventoryTitle, "BOTTOMLEFT", 0, -8)
    invScroll:SetPoint("BOTTOMRIGHT", inventoryFrame, "BOTTOMRIGHT", 0, 0)

    inventoryFrame.itemLines = {}
     for i = 1, ROWS do 
        local line = CreateFrame("Button", nil, inventoryFrame)
        line:SetHeight(ROWH)
        
        
        line:SetPoint("RIGHT", invScroll, "RIGHT", 0, 0)
        line:SetPoint("LEFT", invScroll, "LEFT", 8, 0)
        
        if i == 1 then
            line:SetPoint("TOPLEFT", invScroll, "TOPLEFT", 8, 0)
        else
            line:SetPoint("TOPLEFT", inventoryFrame.itemLines[i-1], "BOTTOMLEFT", 0, 0)
        end
        
        line.icon = line:CreateTexture(nil, "ARTWORK")
        line.icon:SetSize(18, 18)
        line.icon:SetPoint("LEFT", 0, 0)

        line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.text:SetPoint("LEFT", line.icon, "RIGHT", 4, 0)
        line.text:SetPoint("RIGHT", 0, 0)
        line.text:SetJustifyH("LEFT")
        
        line:SetScript("OnEnter", function(self)
            if self.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.itemLink)
                GameTooltip:Show()
            end
        end)
        line:SetScript("OnLeave", GameTooltip_Hide)
        
        line:SetScript("OnClick", function(self)
            if IsShiftKeyDown() then
                if self.parentVendorData then
                    FocusOnDiscovery(self.parentVendorData)
                end
            elseif self.itemLink then 
                HandleModifiedItemClick(self.itemLink) 
            end
        end)
        
        line:Hide()
        inventoryFrame.itemLines[i] = line
    end

    
    local function refreshInventory()
        if page.selectedVendorGuid then
            local dbVendors = L:GetVendorsDB()
            local d = dbVendors and dbVendors[page.selectedVendorGuid]
            
            if d and d.vendorItems then
                inventoryTitle:SetText(d.vendorName .. "'s Inventory")
                
                local numItems = #d.vendorItems
                FauxScrollFrame_Update(invScroll, numItems, ROWS, ROWH)
                local offset = FauxScrollFrame_GetOffset(invScroll)
                
                for i = 1, ROWS do
                    local line = inventoryFrame.itemLines[i]
                    local idx = offset + i
                    if idx <= numItems then
                        local itemData = d.vendorItems[idx]
                        if itemData then
                            local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemData.link)
                            line.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                            line.text:SetText(itemData.link)
                            line.itemLink = itemData.link
                            line.parentVendorData = d
                            line:Show()
                        else
                            line:Hide()
                        end
                    else
                        line:Hide()
                    end
                end
            else
                inventoryTitle:SetText("Vendor Inventory")
                FauxScrollFrame_Update(invScroll, 0, ROWS, ROWH)
                for _, line in ipairs(inventoryFrame.itemLines) do line:Hide() end
            end
        else
            inventoryTitle:SetText("Select a vendor to view inventory")
            FauxScrollFrame_Update(invScroll, 0, ROWS, ROWH)
            for _, line in ipairs(inventoryFrame.itemLines) do line:Hide() end
        end
    end

    
    invScroll:SetScript("OnVerticalScroll", function(s, dlt)
        FauxScrollFrame_OnVerticalScroll(s, dlt, ROWH, refreshInventory)
    end)

    function page.refresh()
        local term = string.lower(edit:GetText() or "")
        local list = {}
        
        
        local vendors = L:GetVendorsDB() or {}
        
        for _, d in pairs(vendors) do
            if term == "" then
                table.insert(list, d)
            else
                local zoneName = L.ResolveZoneDisplay(d.c, d.z, d.iz) or ""
                if string.find(string.lower(d.vendorName or ""), term, 1, true) or
                   string.find(string.lower(zoneName), term, 1, true) then
                    table.insert(list, d)
                else
                    local itemMatch = false
                    for _, itemData in ipairs(d.vendorItems or {}) do
                        if string.find(string.lower(itemData.name or ""), term, 1, true) then
                            itemMatch = true
                            break
                        end
                    end
                    if itemMatch then
                        table.insert(list, d)
                    end
                end
            end
        end

        table.sort(list, function(a, b) return (a.ls or 0) > (b.ls or 0) end)
        
        local offset = FauxScrollFrame_GetOffset(vendorScroll)
        FauxScrollFrame_Update(vendorScroll, #list, ROWS, ROWH)
        
        for i = 1, ROWS do
            local idx = i + offset
            local r = vendorRows[i]
            local d = list[idx]
            if d then
                r:Show()
                r.discoveryData = d
                local zoneName = L.ResolveZoneDisplay(d.c, d.z, d.iz) or "Unknown Zone"
                local coords = fmtCoords(d)
                
                local vendorTypeTag
                if d.vendorType == "MS" or (d.g and d.g:find("MS-", 1, true)) then
                    vendorTypeTag = "|cffa335ee[MS]|r "
                else
                    vendorTypeTag = "|cff9400D3[BM]|r " 
                end
                r.txt:SetText(string.format("  %s%s | %s | %s", vendorTypeTag, d.vendorName or "Unknown", zoneName, coords))
                
                if d.g == page.selectedVendorGuid then
                    r.bg:SetVertexColor(0.2, 0.2, 0.8, 0.3)
                    r.bg:Show()
                else
                    r.bg:Hide()
                end
            else
                r:Hide()
            end
        end
        
        
        refreshInventory()
    end
    
    vendorScroll:SetScript("OnVerticalScroll", function(s, dlt)
        FauxScrollFrame_OnVerticalScroll(s, dlt, ROWH, page.refresh)
    end)
    
	edit:SetScript("OnTextChanged", function()
        if page.filterTimer then
            C_Timer.CancelTimer(page.filterTimer)
        end
        page.filterTimer = C_Timer.After(0.7, page.refresh)
    end)
    
    page:SetScript("OnShow", page.refresh)
    
    return page
end

function ImportExport:OnInitialize()
if L.LEGACY_MODE_ACTIVE then return end
	panel = CreateFrame("Frame", "LootCollectorDiscoveriesPanel", InterfaceOptionsFramePanelContainer)
	panel.name = "Discoveries"
	panel.parent = "LootCollector"
	
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("LootCollector Discoveries")
	
	tabs[1] = CreateTab(panel, 1, "All World")
	tabs[2] = CreateTab(panel, 2, "Instances")
	tabs[3] = CreateTab(panel, 3, "Looted")
	tabs[4] = CreateTab(panel, 4, "Special Vendors") 
	tabs[5] = CreateTab(panel, 5, "Import/Export")
	
	tabs[1]:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	for i=2,5 do 
		tabs[i]:SetPoint("LEFT", tabs[i-1], "RIGHT", 8, 0)
	end
	
	local content = CreateFrame("Frame", nil, panel)
	content:SetPoint("TOPLEFT", 16, -88)
	content:SetPoint("BOTTOMRIGHT", -16, 16)
	
    
	tabPages[1] = BuildListPage(content, "All World Discoveries", function(d) return (d.iz or 0) == 0 end)
	tabPages[2] = BuildListPage(content, "Instance Discoveries", function(d) return (d.iz or 0) > 0 end)
	tabPages[3] = BuildListPage(content, "Looted by this character", function(d) return L.db.char.looted and L.db.char.looted[d.g] end)
	tabPages[4] = BuildBlackmarketPage(content) 
	tabPages[5] = BuildImportExportPage(content)
	
	for i, page in ipairs(tabPages) do
		page:SetAllPoints(content)
		page:SetShown(i == 1)
	end
	
	PanelTemplates_SetNumTabs(panel, 5) 
	PanelTemplates_SetTab(panel, 1)
	activeTab = 1
	
	InterfaceOptions_AddCategory(panel)

    self:RegisterMessage("LOOTCOLLECTOR_DISCOVERY_LIST_UPDATED", function()
        if activeTab and tabPages[activeTab] and tabPages[activeTab].refresh then
            tabPages[activeTab]:refresh()
        end
    end)
end

ImportExport.ZONEABBREVIATIONS = (ZoneList and ZoneList.ZONEABBREVIATIONS) or ImportExport.ZONEABBREVIATIONS or _G.ZONEABBREVIATIONS or {}

function ImportExport:GetZoneAbbrevByIds(continent, zoneID, instanceNameHint)
	if ZoneList and ZoneList.GetZoneAbbrev then
		return ZoneList:GetZoneAbbrev(continent, zoneID, instanceNameHint)
	end
	return instanceNameHint or "Unknown Zone"
end

function ImportExport:GetInstanceNameByIz(iz)
	if ZoneList and ZoneList.ResolveIz then
		return ZoneList:ResolveIz(iz)
	end
	return nil
end

function ImportExport:BuildExportEntryV5(rec)
	if type(rec) ~= "table" then return nil end
	
	local entry = {
		v = 5,
		op = "DISC",
		c = tonumber(rec.continent) or 0,
		z = tonumber(rec.zoneID) or 0,
		iz = tonumber(rec.iz) or 0,
		i = tonumber(rec.itemID) or 0,
		x = L:Round4(rec.xy and rec.xy.x or 0),
		y = L:Round4(rec.xy and rec.xy.y or 0),
		t = tonumber(rec.timestamp) or time(),
		q = tonumber(rec.itemQuality) or 1,
		s = tonumber(rec.s) or 0,
		av = tostring(rec.av or L.Version or "0.0.0"),
		mid = tostring(rec.mid or ""),
		l = rec.itemLink,
		n = rec.itemName,
	}
	return entry
end

function ImportExport:SerializeExportV5(entry)
	local AceSerializer = LibStub and LibStub("AceSerializer-3.0", true)
	local LibDeflate = LibStub and LibStub("LibDeflate", true)
	if not AceSerializer and LibDeflate then return nil end
	if type(entry) ~= "table" then return nil end
	
	local okS, serialized = pcall(AceSerializer.Serialize, AceSerializer, entry)
	if not okS or not serialized then return nil end
	
	local okC, compressed = pcall(LibDeflate.CompressDeflate, LibDeflate, serialized, {level = 9})
	if not okC or not compressed then return nil end
	
	local okE, encoded = pcall(LibDeflate.EncodeForPrint, LibDeflate, compressed)
	if not okE or not encoded then return nil end
	
	return encoded
end

function ImportExport:DeserializeExportV5(encoded)
	local AceSerializer = LibStub and LibStub("AceSerializer-3.0", true)
	local LibDeflate = LibStub and LibStub("LibDeflate", true)
	if not AceSerializer and LibDeflate then return nil end
	if type(encoded) ~= "string" or encoded == "" then return nil end
	
	local okD, decoded = pcall(LibDeflate.DecodeForPrint, LibDeflate, encoded)
	if not okD or not decoded then return nil end
	
	local okU, uncompressed = pcall(LibDeflate.DecompressDeflate, LibDeflate, decoded)
	if not okU or not uncompressed then return nil end
	
	local okT, tbl = AceSerializer:Deserialize(uncompressed)
	if not okT or type(tbl) ~= "table" then return nil end
	if tonumber(tbl.v) ~= 5 then return nil end
	
	return tbl
end

function ImportExport:ToNormalizedDiscoveryV5(tbl)
	if type(tbl) ~= "table" or tonumber(tbl.v) ~= 5 then return nil end
	
	return {
		v = 5,
		op = tbl.op or "DISC",
		itemLink = tbl.l,
		itemName = tbl.n,
		itemID = tonumber(tbl.i),
		itemQuality = tonumber(tbl.q),
		continent = tonumber(tbl.c) or 0,
		zoneID = tonumber(tbl.z) or 0,
		iz = tonumber(tbl.iz) or 0,
		coords = {x = L:Round4(tbl.x), y = L:Round4(tbl.y)},
		foundByanonymous = tonumber(tbl.s) == 1,
		timestamp = tonumber(tbl.t) or time(),
		lastSeen = tonumber(tbl.t) or time(),
		av = tostring(tbl.av or L.Version or "0.0.0"),
		mid = tostring(tbl.mid or ""),
		seq = tonumber(tbl.seq) or 0,
	}
end

if not ImportExport.ExportDiscoveryV5 then
	function ImportExport:ExportDiscoveryV5(rec)
		local entry = self:BuildExportEntryV5(rec)
		if not entry then return nil end
		return self:SerializeExportV5(entry)
	end
end

SLASH_LCEXPORT1 = "/lcexport"
SlashCmdList["LCEXPORT"] = function(msg)
	OpenExportDialog(not (msg and msg:lower():find("nooverlay")))
end

SLASH_LCIMPORT1 = "/lcimport"
SlashCmdList["LCIMPORT"] = OpenImportDialog

SLASH_LCLIST1 = "/lclist"
SlashCmdList["LCLIST"] = function()
	InterfaceOptionsFrame_OpenToCategory("LootCollector")
	InterfaceOptionsFrame_OpenToCategory("Discoveries")
end

return ImportExport
