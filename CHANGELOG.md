## LootCollector 0.8.5 - Fix.
- **Lua error fix**

## LootCollector 0.8.4 - Security, Fixes, tiny Performance fix.

- **Fixes:** Fixed few bugs.
- **Network Protocol "bump":** Bumped minimum compatible version to 0.8.4.

## LootCollector 0.8.3 - Fix.
- **Lua error fix**

## LootCollector 0.8.2 - Pin Menu / Chat Linking, Fixes.

- **Added RMB Chat Link Action:** Added a context-menu option on map pins to insert the item and its location into chat.
- **Improved Existing Shortcut Discoverability:** Surfaced the old Ctrl+Alt+RMB behavior through the normal RMB menu so it is no longer hidden behind a modifier-only flow.
- **Fixes:** .toc, code.

Credit:
- Chat action suggestion and .toc fixes by StepOnLegos - The Chaotic Helper.

## LootCollector 0.8.1 - Fix.
- **Lua error fix**

## LootCollector 0.8.0 - The V8 Engine Overhaul (Performance, Proximity logic, Security, QOL, CoA)
*The features and code in this release were built with efficiency in mind rather than aiming for the best possible overall solution.*

**1. V8 Database Migration & Unified Identifiers**
- **High-Precision GUIDs:** Completely replaced the old 2-decimal grid coordinate system with a 4-decimal exact-match format (`c-z-iz-i-x-y`). (Previously, in some cases, for optimization reasons, 2-decimal coordinates were used)
- **Auto-Migration:** Added a seamless sequence that recalculates the entire database and remaps all character `looted` history to V8 standards on login (requires 1-time reload).
- **Looted State Inheritance:** Redesigned how "looted" markers behave. When pins are merged by the deduplicator or synced via imports, the surviving/new map pin automatically *inherits* the looted state of the consumed pin.
- **Load-on-Demand Initializers:** The 200KB+ Starter Database and the Custom Import string buffers have been decentralized into independent, Load-on-Demand (LoD) addon modules. This further reduces RAM allocation and delays during the `PLAYER_LOGIN` event.
- **Per-Character Filter Isolation:** Moved all data-driven map filters (e.g., Min Quality, Usable By Class, Hide Looted) from the global Account profile to strictly Per-Character settings. Added a silent migration to automatically copy your existing global filters to first character player logs in upon first login.
- **Code Pruning:** Removed some obsolete network variables and redundant legacy structures.


**2. True Yardage Logic & O(N) Deduplication**
- **Euclidean Spatial Clustering:** Replaced flat percentage-based map math with true yardage calculations utilizing `Map.WorldMapSize` and native engine coordinates.
- **O(N) Deduplicator Rewrite:** The cleanup engine now uses a fast, greedy clustering algorithm grouped by Item ID. This should process the database in milliseconds without locking up the game.
- **The Highlander Rule ;D:** Enforced strict rules for Worldforged items. The deduplicator sorts duplicates by Trust, absorbs consensus votes, and purges outliers to ensure **only one** true pin exists per WF Discovery per zone.

**3. Anti-Drift Consensus & Echo-Locking Fixes**
- **Exponential Moving Average (EMA):** Pin coordinates now gracefully drift toward the true center of a cluster using an 80/20 EMA split.
- **Trust Weight Capping:** Incoming network packets have their validation weight capped to prevent spoofed or artificially amplified network echoes from permanently locking pins in incorrect locations.
- **Toast Notifications Rework:** Fixed a bug where echoing another player's drop accidentally stripped their name due to local anonymity settings. Additionally, reinforcement toasts will now hide player names to keep notifications cleaner and less intrusive.

**4. Networking, Security & Spam Shields**
- **Infinite Payload Chunking:** `Comm.lua` can now natively slice massive payloads (like vendor inventories) into 250-byte chunks (`M1`, `M2`, `M3`) and reassemble them. 
- **Memory & Injection Shields:** Implemented strict memory ceilings for message assembly and added another layer of upstream database injection limits per sender to prevent malicious database bloating.
- **Regex Garbage Eradication:** Rewrote the `DBSync.lua` network parser to use a high-performance plain-text crawler instead of Lua Regex, eliminating massive RAM garbage spikes during bulk syncs.
- **PvP Instance Hard Block:** Added a hardcoded rule that completely ignores local loot events while inside Battlegrounds or Arenas.
- **Sharing:** Further network duplication optimization.

**5. Engine Performance & Stutter Fixes**
- **Accelerated C-Side Caching:** If Ascension's native C_AssetQueryService is active, the background cache queue processing delay is dropped from 3-6 seconds down to a highly responsive, randomized 0.5 to 0.7 seconds per item (pcall for now).
- **Unified C-API Scanner:** Eliminated hidden UI tooltip scraping for Mystic Scrolls. The new module `Scanner.lua` instantly queries Ascension's native `C_MysticEnchant` APIs in O(1) time (this requires more testing but hopefully will work as is :>).
- **Time-Budgeted Decay:** The background `Decay.lua` scanner now processes items within a strict 4-millisecond frame window (~0 FPS loss on any hardware).
- **Minimap & Arrow Optimization:** The Auto-Tracking arrow now searches only within `Core.ZoneIndex[currentZoneID]` instead of the global DB. Minimap rendering uses cached math functions and a fast-fail bounding box (`distYards * distYards > maxDistSq`) to skip heavy trigonometry. It also has a (crude sorry ;p) failsafe mechanism for the Astrolabe `nil` glitch.
- **Bag Scanner Debounce:** Added a 0.2-second debounce timer to `BAG_UPDATE` to stop the game from freezing when looting multiple items or using auto-sorters.
- **Toast Ticker:** The scrolling UI toast ticker now cycles just two objects. This produces smoother scrolling and eliminates possible memory bloat caused by string concatenation.
- **Reduced Load Freeze:** Completely rewrote the Viewer array compiler into a time-budgeted, asynchronous background loader. It now processes exactly 8ms of data per frame, allowing massive 10000-item databases to load seamlessly in the background without dropping frames or freezing the game. (Toggleable via Settings).
- **Annihilated some Garbage Collection (GC) Stutters:** Reduced memory bloat across the entire addon. The Viewer now utilizes **Object Pooling (Table Recycling)**. Instead of creating and abandoning 10000 tables during searches/filters (forcing GC stutters), it securely overwrites existing memory blocks, significantly dropping active RAM allocation.
- **Pre-Computed Sort Keys:** Eliminated screen stutter when clicking table column headers (like "Zone" or "Name"). Complex string/API resolutions are now pre-computed during the background load, rendering UI sorting an instantaneous `O(1)` math operation.
- **Persistent Core Scanner & RAM 'Hydration':** Added a permanent `SavedVariables` cache for lightweight core stats (Worldforged, Level, Class). Heavy tooltip text required for "Deep Searching" is now quietly 'hydrated' into a transient RAM cache over time via a silent background 1.0ms ticker.
- **Contextual Minimap Caching & Math Bypass:** Minimap tracking now uses "fast", local Lua arithmetic instead of bridging to Ascension C-APIs hundreds of times a second.
-**Unified Database Pass Optimization:** Consolidated independent O(N) database sweeps into a single, cohesive pass, significantly reducing login maintenance overhead.

**6. Dynamic AOE Deadzones**
- **AOE Tombstones (Deadzones):** The addon can now set invisible 50-yard exclusion bubbles to instantly annihilate corrupted item data (for example, false WF drops spawned by Guardian of Time upgrades).
- **MS Vendor Deadzones:** Implemented a permanent, localized 70-yard deadzone surrounding all recorded Mystic Scroll Vendors. This prevents random, duplicated MS map pins from clustering on top of vendors. 

**7. Diagnostics**
- **Bug Report Generator:** Added a dedicated Report a Bug Button (Bug icon) to the Viewer. Users can input a Title and Description to generate a fully compressed, deflated `!LCDBG1!` payload string containing their environment data, active addon list, database metrics, and profiler health.

**8. Quality of Life & Event Suppression**
- **Bags Filter:** Added by @Raxxlian. Hides Bags from Discoveries. Map->LC->Hide->"Hide Bags".
- **Clear Looted History Button:** Added by @Raxxlian. Interface->LootCollector(+)->Discoveries->Looted->"Clears All Looted".
- **New Viewer feature - "Deep Search (Stats & Effects)"!:** Added by @Raxxlian. Toggle this in Veiwer to include Stats & Effects search!
	* Additional updates to Raxxlian's "Deep Search":
	*   The toggle state of **"Deep Search"** is now properly saved and loaded across reloads and game sessions.
    *   **Visual Highlights:** Discoveries matched exclusively via tooltip descriptions are highlighted in the list with a distinct golden **`[DS]`** tag.
    *   **Keystroke Debouncing:** Added a **0.2-second typing delay** to the Viewer's search box to completely eliminate interface lag while typing. Highlights are instantly cleared when search queries are emptied.
- **CoA Archetypes & Localized Menus:** 
    *   Standard vanilla retail classes are now completely filtered out of the Map and Viewer "Usable by" lists on CoA realms.
    *   Dropdown menus now strictly display the clean localized display names.
- **Hide Non-Essential Messages:** Added a new Visibility toggle to suppress verbose chat output (such as routine background database scan/cache notifications, login maintenance stages, and automatic cleanup reports).
- **Hibernation Mode:** The "Pause" feature has been entirely rewritten into a true "Hibernation Mode". Turning this on instantly purges all network queues, halts background caching, **stops local detection**, and clears map + minimap pins, reducing CPU overhead.
- **Auto-Hibernation:** Added Settings toggles to automatically trigger Hibernation Mode when entering *PvP Instances, Raid Instances, or Raid Groups* to eliminate distractions and chat-throttling during intense group content.
- **Hide Non-Essential Messages:** Added a new Visibility toggle to suppress verbose chat output (such as routine background database scan notifications and login maintenance stages).
- **Strict CoA Purges:** When CoA Realm mode is detected (or manually overridden), the addon will automatically purge all incompatible data (*Idols, Librams, Mystic Scrolls, and MS Vendors*) and hide their respective tabs in the Viewer to prevent database bloat.
- **Quest & Store Failsafes:** Fixed Worldforged items being ignored if looted after turning in a quest. Upgrading WF items should not appear as fresh WF Discovery anymore.
- **Tooltip RAM Management and QOL:** Reworked pedictor to use a 400-item FIFO queue. This should be better solution to prevent RAM bloat during long sessions. Added Quality filters. Toast Ticker will now only display a notification when a reported discovery passes all filters and is added to the database (this can be toggled via Settings to revert to the old behavior)).
- **Settings Toggles:** Added options to **"Show Minimap Button"**, **"Disable 'Nearby Discoveries'"**, and a **"Realm Mode Override"** dropdown.
- **Cross-Character Filter Copying:** Added a new "Copy Filters From..." submenu to the Map button, allowing players to instantly clone their specialized map filter setups from their Mains to their Alts with two clicks.
- **LC Map button Menu Boundary Detection:** The map Filter Menu now dynamically calculates screen boundaries, opening above the button instead of below it if there isn't enough vertical space, preventing it from clipping off-screen.
- **LC Map button Menu State Refresh:** Fixed a closure bug where "Show" and "Hide" submenus of the 'LC' button would only toggle once due to static option snapshots (this still needs a small fix for a specific scenario).

## LootCollector 0.7.54 - Fixes & Optimizations
- **Fix:** (pssibly) fixed an issue that sometimes caused Worldforged items not to be marked as looted after being collected.
- **Fix:** fixed an issue where the header was not displayed in the key bindings section.
- **Other:** slightly lowered the amount of WoW API calls.

## LootCollector 0.7.53 - Fixes
- **Fix:** (Possibly) fixed bug that caused crash and some Worldforged items were not marked as looted after being collected.
- **Fix:** More Area 52 dedicated fixes.

## LootCollector 0.7.52 - Feature, Fixes
- **Added:** "Show Minimap Button" option under "Visibility" settings.
- **Fix:** Minimap discovery icons blinking.
- **Fix:** (Possibly) fixed bug where some Worldforged items were not marked as looted after being collected.
- **Network Protocol "bump":** Bumped minimum compatible version to 0.7.49.

## LootCollector 0.7.51 - Initial interface compatibility update for non "Warcraft Reborn" Ascension realms. (Special thanks to **Netherborne** for the CoA invite that made this update possible.)
- **Dynamic Realm Capabilities:** The addon now automatically detects your active realm type (Warcraft Reborn, Classless, CoA, or Wildcard) to toggle unsupported features like Mystic Scrolls. Added a manual override dropdown in Settings.
- **CoA Class Support:** Added native support and proficiency mappings for custom archetype classes (Barbarian, Witchdoctor, Reaper, etc.), fixing Lua crashes caused by Ascension's background UI tooltip scanning.
- **Network:** Automatically pauses outgoing database sharing for characters under level 10 on Area 52 realm to prevent "You don't have permission..." chat errors.
- **QOL:** You can now toggle "Disable Nearby Discoveries" in Settings window and the quick Map Filter dropdown (->Hide).

## LootCollector 0.7.49 - New Filters, QOL (Raxxlian/Rhenyra)
- **Added Filter to hide:** Collected Mystic Enchants and WF items you've collected their appearance.
- **QOL:** Added option to disable the fading effect of the stale items.

## LootCollector 0.7.48 - Bugfix
- **Fixed a typo:** ec.mk = self:MakeKeyV5(rec) -> rec.mk = self:MakeKeyV5(rec)

## LootCollector 0.7.47 - Network Consensus, Background Maintenance, Optimizations & Fixes
#### **1. Consensus & Data Integrity**
*   **Repaired Deletion Consensus:** Fully implemented the "Report as Gone" (ACK) threshold logic. Nodes now transition to **Fading** at 5 votes, **Stale** at 6 votes, and are **Permanently Deleted** at 7 votes.
*   **Background Identifier Indexer:** Added a throttled background maintenance system (`ProcessIndexerBatch`) that generates missing Message IDs (`mid`) and Location Keys (`mk`) for legacy database records.
*   **Atomic Local Discoveries:** Updated `Core:HandleLocalLoot` to generate unique identifiers (`mid`/`mk`) the instant a player finds an item, ensuring new nodes are network-ready immediately.

#### **2. Performance & Architecture Improvements**
*   **O(1) Hash Map Indexing:** Redesigned database lookups to utilize `_midIndex` and `_keyV5Index` hash maps, replacing inefficient O(N) loops with instant constant-time lookups.
*   **Decoupled Map Rendering:** Separated the World Map pin logic from the Minimap logic. The Minimap now operates on its own independent cycle, preventing data changes on the World Map from causing performance hitches or "blinking" on the Minimap.
*   **Dynamic Minimap Ticker:** Implemented an anonymous background ticker for the Minimap that intelligently toggles between an "Active" state (0.1s updates while moving) and an "Idle" state (0.5s updates while stationary), significantly reducing CPU overhead.
*   **Comm Cache Pruning:** Added logic to the `Comm:OnUpdate` cycle to automatically prune the deduplication and ingress caches, preventing memory bloat during long play sessions.

#### **3. Network & Synchronization**
*   **Scheduled Deletion Reinforcement:** Implemented a persistent broadcast schedule (1h, 8h, 16h, 30h) for deletions to ensure consensus reaches players who were offline during the initial event.
*   **Reactive Anti-Entropy (Tombstone Defense):** Clients now automatically fire a counter-ACK if they detect someone sharing a discovery that exists in their local `deletedCache` (Tombstone).
*   **Protocol Security Gate:** Restricted reactive responses to clients running version `0.7.47` or higher and bumped `MIN_COMPATIBLE_VERSION` to ensure network-wide stability.

#### **4. Bug Fixes & Maintenance**
*   **Zone Transition Persistence:** Corrected the `ZONE_CHANGED_NEW_AREA` handler to force-refresh the Minimap, ensuring pins generate immediately when crossing zone boundaries.
*   **Mystic Scroll Data Health:** Integrated a routine maintenance cycle to safely clean up and migrate legacy Mystic Scroll source metadata (`world_loot`, `npc_gossip`, etc.).
*   **Identifier-Aware Data Sync:** Updated manual Import/Export strings to include and preserve `mid` and `mk` identifiers, maintaining network consensus even after a manual database migration.

## LootCollector 0.7.46 - Small Fix
- **Minimap Visibility Fix:** Resolved a bug where discoveries would persist on the minimap after being looted, even with the "Hide Looted" filter active (internal cache handler will trigger UI refreshes as soon as local loot events occur).
- **Synced Map Tickers:** Synchronized the refresh logic between the World Map and Minimap to ensure consistent data display across both UI elements.

## LootCollector 0.7.45 - Critical Fix

- **Version Validation Fix:** Fixed a critical bug where optimized encoded messages were bypassing version validation.
- **Network Protocol "Reset":** Bumped minimum compatible version to 0.7.45. This ensures all participants on the sync network are utilizing the 0.7.44 lag-recovery, AFK-protection logic and new 0.7.45 Version Validation Fix.

## LootCollector 0.7.44 - Stability & Lag Recovery

- **Anti-Freeze Protection:** Implemented delta-time clamping (`math.min(elapsed, 0.1)`) across all animation and tracking modules (Arrow, Map, Minimap, Toast Ticker). This prevents UI "teleportation" and logic spikes after loading screens, lag, or Alt-Tabs.
- **Lag Recovery Mode:** The communication layer now detects Alt-Tab/Freeze events and enters a dynamic "Safe Mode" (throttled processing at 6 msgs/frame) for up to 7 seconds to ensure the game engine remains smooth while clearing backlogs.
- **Message Buffer Optimization:** Added a hard cap to the incoming message buffer. If the buffer is full upon resuming, the oldest 20% of messages are automatically purged to prioritize fresh data and minimize the duration of "resume stutters."
- **AFK Spam Fix:** Added AFK detection to pause outgoing network sync. This fixes the infinite "Away / No longer Away" chat loop caused by addon traffic clearing the AFK status on 3.3.5a clients.
- **Minimap Power Save:** The minimap update ticker now completely stops all coordinate processing and pin math when the minimap is hidden or "Hide All" is toggled, saving CPU cycles.


## LootCollector 0.7.42 - Tooltip Strata Fix (Xurkon)

- **Fixed Tooltip Z-Order:** Tooltips now properly display above ArkInventory, TSM, and Postal UIs
  - Added `SetFrameStrata("TOOLTIP")` after all `GameTooltip:Show()` calls
  - Fixed 23 instances across Viewer.lua, Toast.lua, MinimapButton.lua, Map.lua, and ImportExport.lua

## LootCollector 0.7.41 - Frame Strata Fix (Xurkon)

- **Fixed Tooltip Visibility:** Tooltips now display above map pins and overlays instead of behind them
  - Changed map pins, overlays, and hover buttons from `TOOLTIP` strata to `HIGH` strata
  - Changed context menus and autocomplete dropdowns from `TOOLTIP` strata to `DIALOG` strata
  - This prevents addon frames from overlapping game tooltips

## LootCollector 0.7.40 - Fixes + Small Optimizations**

- Fixed few bugs.
- Testing some alternative solutions and optimizations.
- Added feature to disable Mystic Scrolls processing.
- Removed HistoryTab feature.

## LootCollector 0.6.90 - Fixes**

- Fixed a bug where HideDiscoveryTooltip was hiding other map tooltips.  
- Improved minimap icon visibility.  
- Fixed a bug where Mystic Scrolls were not filtered correctly.  
- The default addon channel is now hidden from users.
- You can now reposition the LC map button by holding Shift and dragging it.

## LootCollector 0.6.40 - Fixes + Small Optimizations**

- Fixed few reported issues in Map, Settings and Viewer.
- Map Optimization.

## LootCollector 0.6.10 - Fixes + Small Optimizations**

- Fixed issue where out-of-distance minimap icons appeared on the edges of minimap and "floated".
- Minimum compatible version to accept discoveries is now 0.6.10

## LootCollector 0.6.00 - Fixes**

- Added support when `GetCurrentMapContinent()` returning -1 in some cases.
- Improved detection of Mystic Scroll acquisition from quests.
- Various minor fixes and stability improvements.

## **LootCollector 0.5.97 - Fixes**

Bunch of fixes

## **LootCollector 0.5.94 - Fixes**

Bunch of fixes

## **LootCollector 0.5.90 - Realm Buckets & Stability Overhaul**

### **Highlights**
*   **Realm Buckets (Database Isolation):**
    *   Completely restructured the database to store discoveries and vendors separately per Realm (e.g., *Bronzebeard* / *Malfurion* vs *Elune*). This prevents data corruption and "bleeding" when switching between Seasonal and Main realms.
    *   Includes an automatic **Migration System** that moves your existing data to the correct realm bucket upon login.
*   **Zone ID Standardization:**
    *   The addon now enforces stricter Zone ID validation using modern MapIDs instead of legacy indexes.
    *   Added an automatic repair tool (`/lcczfix`) to detect and correct records with invalid Continent-Zone mismatches.
    *   Introduced **Tombstones with Expiration**: When a bad record is fixed, a "tombstone" is created to prevent older data from syncing back to you for a set duration.
*   **Mystic Scroll discoveries are once again shared! Automatic vendor sharing is still on the to-do list, but you can share them manually with the "Show to" feature.

### **Fixes**
*Too many but still not enough :p*

### **Technical & Optimizations**
*   **Database Accessors:** Refactored every module (`Core`, `Map`, `Viewer`, `DBSync`, etc.) to use secure accessors (`GetDiscoveriesDB`) instead of accessing global tables directly. This improves stability and supports the new Realm Bucket architecture.
*   **Network Security:** Strengthened validation for incoming data packets to reject malformed zone IDs immediately.

### **Feature Refinements**
*   **World Map:** Clarified interaction logic. For best results, use `/script WorldMapFrame:Show()` or a map addon (like Magnify/ElvUI) to enable full interactivity (Context Menus, Proximity Lists) which are restricted in the default protected map mode.
*   **Vendor Tracking:** Improved logic for associating specific inventories with Black Market vendors in the database.

*Database Update: Updated starter database to include verified coordinates for the latest content.*

## **LootCollector 0.5.8/0.5.81 - Fixes **

Some emergency fixes.
Expanded block list functionality.
Added option to delete data from blocked players.

## **LootCollector 0.5.7 - Performance optimizations + Fix **
Several performance optimizations that may improve the addon's performance. 
Fix for disappearing tooltip.

Database Update: Updated starter database to 2k+ discoveries.

## **LootCollector 0.5.6 - Fixes **
Bunch of fixes

Database Update: Updated starter database to 1840+ discoveries.

## **LootCollector 0.5.5 - New command + Fixes **

Highlights
- **`/lctoggle`  New command**  
Toggles visibility of Map and Minimap discoveries (you can keybind it too!)

Fixes
Database cleanup and optimization to ensure stability and performance.
Improved the WF tooltip with richer details.
Fixed tracking and auto-tracking functionality to now work correctly in all starter zones*.

Database Update: Updated starter database to 1760+ discoveries.

## **LootCollector 0.5.4 - Fixes **
Mainly related to the new player experience with the addon.
Changed item and vendor detection.
A bunch of other fixes.

Database Update: Updated starter database to 1640+ discoveries.

## **LootCollector 0.5.3 - Enhanced WF Tooltip + Fixes**
Highlights
Enhanced WF Tooltip - new feature for WF items that displays statistics after certain upgrade levels, providing detailed progression information directly in tooltips.

Fixes
Database Error Fix: Resolved issue where new discovery reports for older records caused errors when attempting to access the non-existent fp_votes table.

Toast Notification Fix: Reduced redundant toast spam that incorrectly displayed notifications for already existing discoveries.

Database Update: Updated starter database to 1590 discoveries.



## **LootCollector 0.5.2 - Viewer + Fixes**
Highlights
Integrated Markosz’s Viewer module and its minimap icon into the addon.

Fixes
Resolved locked movement during display of certain popup dialogs.
Added a short delay to addon minimap operations after changing zones to avoid UI lag.
Corrected fallback channel name resolution in Comm.lua.
Fixed pause state handling.
Possibly fixed another /1 hijack issue and fixed channel joining.
Fixed an issue where looted discoveries were not automatically marked as looted
Corrected square map detection and minimap rotation handling. //Markosz
Fixed the Show() function to target the correct discovery item. //Markosz

## **LootCollector Changelog: Version 0.5.1S (from 0.4.9)**

Changes focusing on database optimization, network protocol enhancements, community moderation, and  UI/UX and QOL improvements.

### **Major New Features & Architectural Changes**

*   **Database Schema v6 Overhaul & Migration:**   
    *   A new automated, one-time **Database Migration** system prompts users with older databases. It safely preserves all character-specific "looted" history while upgrading the main discovery database to the new format and automatically importing the latest starter database.

*   **Map Clustering & Zone Awareness:**
    *   When viewing a continent or parent zone (e.g., Kalimdor), discoveries are now grouped into a single "cluster" pin at the zone's entrance, showing the total count. (implemented just not applied except Mulgore)
    *   Clicking a cluster pin zooms into that zone, decluttering the world view and improving performance.

*   **Advanced Toast Notification System:**
    *   **Anti-Spam Ticker:** When many discoveries are received at once, the addon switches from individual pop-ups to a single, scrolling "ticker" frame to prevent UI spam. (can be disabled)
    *   **Smart Queue & Spam Detection:** The system now detects and suppresses toast spam from individual players to maintain a clean user experience.
    *   **Interactivity:** Toasts are now interactive. Move mouse pointer over an item to see details or Shift+click to opens map and focus on its location.

*   **Community Moderation & Data Integrity:**
    *   **"Report as Gone":** Right-clicking a map pin and reporting it as gone now sends a "deletion vote" to the network.
    *   **Status by Consensus:** If enough players report a discovery as gone, its status is automatically downgraded to `FADING` and then `STALE`, keeping the database clean. `STALE` items are visually distinct on the map.
    *   **Coordinate Consensus:** The system refines a discovery's coordinates over time by averaging reports from multiple players, improving pin accuracy.

*   **"Show to..." a Player Feature:**
    *   You can now right-click a map pin to select "Show to...". This allows you to send a specific discovery location directly to another player and focus his map on it.
    *   The recipient gets a confirmation popup to "Allow," "Deny," or "Block Sender," preventing unsolicited map pings.

### **Communication & Network**

*   **New v5 Network Protocol:** The communication system has been rewritten for efficiency, supporting new features like deletion votes (`ACK`), data corrections, and "Show" requests.
*   **Advanced Rate Limiting:** A "leaky bucket" algorithm has been implemented for channel messages. This smooths out network traffic to prevent disconnects and ensures no messages are dropped during busy periods.
*   **Enhanced Security & Validation:**
    *   Incoming messages are now strictly validated for correct data types and ranges. Invalid messages are tracked, and repeat offenders are automatically session-ignored or permanently blacklisted.
*   **Version Enforcement:** The addon now enforces a minimum compatible version, ignoring messages from outdated clients to prevent data corruption.
*   **Important Change to Sharing:** To ensure data quality, automatic sharing is temporarily limited to **Worldforged** items. Mystic Scrolls can still be shared manually via `/lcshare` and the "Show to..." feature. Default automatic sharing for MS will be restored in future versions.


### **UI & Quality of Life Improvements**

*   **Map Enhancements:**
    *   **Search & Filter Bar:** An optional search bar can now be displayed on the World Map to filter pins by item or zone name in real-time.
    *   **Map Focus Animation:** A new "Focus" feature (accessible via Shift+click) opens the map and plays a pulsing animation at a discovery's location.
    *   **Improved Pin Appearance:** Pin borders are now color-coded by item quality. `STALE` items are clearly marked with a distinct orange color.

*   **Arrow (TomTom) Improvements:**
    *   A new "Auto-track Nearest Unlooted" option automatically activates the arrow.
    *   You can now temporarily "skip" the nearest target for the current session via the map filter menu.
    *   The arrow now automatically finds the next target after you loot the one it was pointing to.

*   **Minimap Overhaul:**
	*   Dynamic minimap shape detection to display markers along the edges correctly has been implemented based on **Markosz** code.
	*   A new option allows limiting minimap pins to a specific yardage from your character.
    *   The minimap pin logic has been completely rewritten for accuracy and performance.    

*   **Advanced Filtering:**
    *   Filters for discoveries now include "Usable by Class" and "Equipment Slot," which work instantly even for uncached items.

*   **Import/Export:**
    *   Added a new **"Import from File"** method for safely importing massive community databases without freezing the client.
    *   Player block/whitelists can now be included in exports.
    *   Added a **"Factory Reset"** button to the Discoveries panel to completely wipe all addon data.

### **Core Logic & Bug Fixes**

*   **Centralized Zone Data:** A new `ZoneList.lua` module provides accurate Zone, Instance, and Sub-zone name resolution, which is critical for map clustering and display accuracy.
*   **Item Metadata Storage:** The addon now stores more metadata for each discovery (item type, subtype, class restrictions) directly in the database.
*   **Delayed Broadcasting:** Newly found discoveries are now briefly buffered. This allows the client to cache item information, ensuring more complete and accurate data is broadcast to other players.
*   **Coordinate Precision:** All coordinates now use 4-decimal precision for improved accuracy.
*   **Fixed `/1` Hijacking:** Resolved an issue where the addon could sometimes interfere with the official chat channels.