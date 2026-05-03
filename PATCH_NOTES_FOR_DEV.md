# Community Patch: "Hide Collected Mystic Enchants" + "Disable Fade Effect"

> **For the LootCollector developer — this document describes every change made to your addon,  
> written so you can review, adopt, or reject each piece independently.**  
> All changes are self-contained, backward-compatible, and follow your existing code patterns.

---

## Summary of Features Added

| Feature | Where it shows | Setting key |
|---|---|---|
| Hide Collected Mystic Enchants | Map right-click menu, /lc Settings panel, Viewer filter bar | `db.profile.mapFilters.hideCollectedME` |
| Disable Fade Effect | Map right-click menu, /lc Settings panel | `db.profile.mapFilters.disableFadeEffect` |

---

## Feature 1: Hide Collected Mystic Enchants

### How it works

When the filter is active, any `MYSTIC_SCROLL` discovery whose item has been collected by the 
current account is hidden. Collection status is detected via tooltip scanning:

1. A hidden `GameTooltip` (named `LootCollectorMEScannerTooltip`) scans the item by `SetHyperlink`.
2. Each tooltip line's text is stripped of WoW color codes (`|cXXXXXXXX`/`|r`).
3. If any stripped line equals exactly `"Collected"`, the item is considered collected.
4. Results are cached for **5 minutes** per `itemID` to avoid repeated tooltip scanning.

> **Note:** `C_MysticEnchant.IsCollected()` was tested but does not exist on Ascension.  
> The tooltip method works — the "Collected" text from the game client IS accessible via hidden  
> scanner tooltips (it appears as `|cff1EFF00Collected` — green color code prepended).

---

### File 1 of 4: `LootCollector.lua`

**Change 1 — Default value in `dbDefaults`**

In the `mapFilters` block inside `dbDefaults`, one new key was added:

```lua
-- ADDED: after hideLearnedTransmog = false,
hideCollectedME = false,
```

**Change 2 — Default guard in `GetFilters()`**

One new line was added at the end of `GetFilters()`, before `return f`:

```lua
-- ADDED: after existing if-nil guards
if f.disableFadeEffect == nil then f.disableFadeEffect = false end
```

Wait — see Feature 2 below. `disableFadeEffect` guard is also here.

For `hideCollectedME` specifically, this line was added:

```lua
if f.hideCollectedME == nil then f.hideCollectedME = false end
```

**Change 3 — New detection function `IsMysticEnchantCollected()`**

Added a new function after `IsAppearanceCollected()`:

```lua
local meCollectedCache = {}
local meCollectedCacheTime = {}
local ME_COLLECTED_CACHE_DURATION = 300

function LootCollector:IsMysticEnchantCollected(itemID)
    if not itemID or itemID == 0 then return false end

    local now = GetTime()
    if meCollectedCacheTime[itemID] and (now - meCollectedCacheTime[itemID]) < ME_COLLECTED_CACHE_DURATION then
        return meCollectedCache[itemID]
    end

    local isCollected = false

    -- Try direct API first (Ascension-specific)
    if C_MysticEnchant and C_MysticEnchant.IsCollected then
        local ok, result = pcall(C_MysticEnchant.IsCollected, itemID)
        if ok and result then
            isCollected = true
        end
    end

    -- Fallback: scan the item tooltip for "Collected" text
    if not isCollected then
        local scannerName = "LootCollectorMEScannerTooltip"
        local scanner = _G[scannerName]
        if not scanner then
            scanner = CreateFrame("GameTooltip", scannerName, UIParent, "GameTooltipTemplate")
            scanner:SetOwner(UIParent, "ANCHOR_NONE")
        end
        scanner:ClearLines()
        scanner:SetOwner(UIParent, "ANCHOR_NONE")
        scanner:SetHyperlink("item:" .. itemID)

        for i = 1, scanner:NumLines() do
            local leftText = _G[scannerName .. "TextLeft" .. i]
            if leftText then
                local text = leftText:GetText()
                local stripped = text and text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or ""
                if stripped == "Collected" then
                    isCollected = true
                    break
                end
            end
        end
        scanner:Hide()
    end

    meCollectedCache[itemID] = isCollected
    meCollectedCacheTime[itemID] = now

    return isCollected
end
```

**Change 4 — Filter check in `DiscoveryPassesFilters()`**

One new `if` block was added after the `hideLearnedTransmog` check:

```lua
-- ADDED: after the hideLearnedTransmog block
if f.hideCollectedME and Constants and d.dt == Constants.DISCOVERY_TYPE.MYSTIC_SCROLL and d.i and d.i > 0 and self:IsMysticEnchantCollected(d.i) then
    return false
end
```

---

### File 2 of 4: `Modules/Map.lua`

**Change 1 — Right-click dropdown menu**

In the `BuildHideSubmenu()` (or equivalent) function that builds the "Hide" submenu, one line was
added after the "Hide Collected Appearances" toggle:

```lua
-- ADDED: after addToggle("Hide Collected Appearances", "hideLearnedTransmog", hideSub)
addToggle("Hide Collected Mystic Enchants", "hideCollectedME", hideSub)
```

**Change 2 — `AlphaForStatus()` function** *(Feature 2 — see below)*

---

### File 3 of 4: `Modules/Settings.lua`

**Change — New AceConfig toggle in the Visibility section**

After the `hideCollectedME` entry (order 4.2), a new entry was inserted:

```lua
hideCollectedME = {
    type = "toggle",
    name = "Hide Collected Mystic Enchants",
    order = 4.2,
    desc = "Hide Mystic Scroll discoveries for enchants you have already collected.",
    get = function() return L.db.profile.mapFilters.hideCollectedME end,
    set = function(_, v)
        L.db.profile.mapFilters.hideCollectedME = v
        refreshUI()
    end,
},
```

---

### File 4 of 4: `Modules/Viewer.lua`

The Viewer received several additions to integrate a tri-state "Collected" filter button into the 
filter bar (matching the existing "Looted" tri-state pattern):

**State field** (top of file, near `lootedFilterState`):
```lua
Viewer.collectedMEFilterState = nil   -- nil = All, true = Only Collected, false = Only Not Collected
```

**Filter predicate** — added to both filter paths (the `GetFilteredDatasetForUniqueValues` path
and the main display path), checking:
```lua
if Viewer.collectedMEFilterState ~= nil then
    local Constants = L:GetModule("Constants", true)
    if data.isMystic and Constants then
        local itemID = data.discovery and data.discovery.i
        local isCollected = itemID and itemID > 0 and L:IsMysticEnchantCollected(itemID)
        if Viewer.collectedMEFilterState ~= (isCollected == true) then return false end
    else
        if Viewer.collectedMEFilterState == true then return false end
    end
end
```

**`HasActiveFilters()`** — added one new condition:
```lua
or Viewer.collectedMEFilterState ~= nil
```

**`UpdateFilterButtonStates()`** — added handler for the new button:
```lua
if Viewer.collectedMEBtn then
    if Viewer.collectedMEFilterState == nil then
        Viewer.collectedMEBtn:SetText("Collected: All")
        Viewer.collectedMEBtn:SetNormalFontObject("GameFontNormal")
    elseif Viewer.collectedMEFilterState == false then
        Viewer.collectedMEBtn:SetText("Collected: No")
        Viewer.collectedMEBtn:SetNormalFontObject("GameFontHighlight")
    else
        Viewer.collectedMEBtn:SetText("Collected: Yes")
        Viewer.collectedMEBtn:SetNormalFontObject("GameFontHighlight")
    end
end
```

**Clear All** — reset added alongside `lootedFilterState`:
```lua
Viewer.collectedMEFilterState = nil
```

**Filter state hash** — added to the string that determines if a re-filter is needed:
```lua
.. tostring(Viewer.collectedMEFilterState)
```

**Button creation** — a new button was created following the exact same pattern as the Looted button:
```lua
local collectedMEBtn = CreateFrame("Button", nil, additionalFiltersFrame, "UIPanelButtonTemplate")
collectedMEBtn:SetSize(87, 22)  -- adjusted to fit within the original 556px frame
collectedMEBtn:SetPoint("LEFT", lootedBtn, "RIGHT", 3, 0)
collectedMEBtn:SetText("Collected: All")
collectedMEBtn:SetScript("OnClick", function()
    if Viewer.collectedMEFilterState == nil then
        Viewer.collectedMEFilterState = false
    elseif Viewer.collectedMEFilterState == false then
        Viewer.collectedMEFilterState = true
    else
        Viewer.collectedMEFilterState = nil
    end
    Viewer:RequestRefresh()
    Viewer:UpdateFilterButtonStates()
end)
collectedMEBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Collected ME Filter", 1, 1, 1)
    GameTooltip:AddLine("All: show all Mystic Scroll discoveries", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("No: show only uncollected Mystic Scrolls", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Yes: show only already-collected Mystic Scrolls", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
collectedMEBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
Viewer.collectedMEBtn = collectedMEBtn
```

**Layout adjustment** — To fit the new button, other buttons in the 556px filter bar were 
slightly reduced and gaps changed from 5px to 3px between buttons:
```
Source: 65px, Quality: 65px, Slots: 55px, Usable By: 75px, Looted: 82px, Collected: 87px, Duplicates: 78px
```

---

## Feature 2: Disable Fade Effect

### How it works

When enabled, the `AlphaForStatus()` function in Map.lua immediately returns `1.0` (full opacity)
for all pin statuses, bypassing the FADING (65%) and STALE (45%) alpha reductions.

---

### `LootCollector.lua` changes

**`dbDefaults`** — new key:
```lua
-- ADDED: after hidePlayerNames
disableFadeEffect = false,
```

**`GetFilters()`** — new guard:
```lua
-- ADDED: before return f
if f.disableFadeEffect == nil then f.disableFadeEffect = false end
```

---

### `Modules/Map.lua` changes

**`AlphaForStatus()`** — the function was modified:

```lua
-- BEFORE:
local function AlphaForStatus(status)
  if status == "FADING" then return 0.65 elseif status == "STALE" then return 0.45 end
  return 1.0
end

-- AFTER:
local function AlphaForStatus(status)
  local f = L:GetFilters()
  if f.disableFadeEffect then return 1.0 end
  if status == "FADING" then return 0.65 elseif status == "STALE" then return 0.45 end
  return 1.0
end
```

**Right-click dropdown menu** — one separator and toggle added after the `hideCollectedME` toggle:
```lua
-- ADDED: after addToggle("Hide Collected Mystic Enchants", ...)
table.insert(hideSub, { text = "", notCheckable = true, disabled = true })
addToggle("Disable Fade Effect", "disableFadeEffect", hideSub)
```

---

### `Modules/Settings.lua` changes

**New AceConfig toggle** — inserted after `hideCollectedME` (order 4.2), at order 4.3:
```lua
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
```

---

## Diagnostic Command (can be removed)

A `/lcme <itemID>` slash command was added to `LootCollector.lua` for debugging purposes.  
It dumps `C_MysticEnchant` API methods and tests collection detection for a given item ID.  
**This can be safely removed** — it was only used to discover the correct detection approach  
and is not part of the permanent feature.

---

## Compatibility Notes

- **SavedVariables**: New keys (`hideCollectedME`, `disableFadeEffect`) default to `false` and  
  are guarded in `GetFilters()`, so existing saves are unaffected.
- **No new global functions** are exposed — all new functions are addon-scoped (`LootCollector:`).
- **No taint risk** — tooltip scanner uses `UIParent` as owner, not any Blizzard secure frame.
- **No breaking changes** — all existing behavior is preserved when the new toggles are off  
  (which is the default).
