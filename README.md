# LootCollector

> [!IMPORTANT: Project Status Notice]
> ** Active development and support for LootCollector has ended. The repository is now archived and will no longer receive updates. Thank you to everyone who helped build and test this Proof of Concept (POC) project.**

---

## How LootCollector Speeds Up Your Character Progression

### 1. Target the Exact Upgrades for Your Build
* **Filter by Class and Archetype:** Stop wasting time running to discoveries you cannot use. On Conquest of Azeroth (CoA) realms, the map automatically filters out original classes and highlights gear usable by your custom archetype (e.g., *Templar*, *Venomancer*).
* **Deep Search:** Looking for a specific stat or a particular equip effect to complete your build? Toggle the "Deep Search" option in the Viewer to search through the tooltips of discovered items. Matches are highlighted with a distinct `[DS]` tag.
* **Filter by Slot:** Narrow your map down to specific equipment slots, allowing you to focus strictly on replacing your lowest-item-level gear (like searching only for trinkets or weapons).
![LootCollector_features](https://raw.githubusercontent.com/mmobrain/stuffforstuff/refs/heads/main/lc/2.jpg)

### 2. Streamline Your Farming Routes
* **Auto-Track the Closest Upgrades:** Load **TomTom** addon to activate a navigation arrow that automatically points to the nearest unlooted discovery matching your active filters or set it manually to your desired target.
* **Skip and Filter Targets:** If a specific node is too dangerous or out of the way, you can temporarily "skip" it from the map menu, and the navigation arrow will automatically recalculate the route to your next option.
* **Clean Map Clutter:** Toggle options to hide already looted items, low-quality gear, or bags, leaving only high-value upgrades visible on your world map and minimap.
![LootCollector_features](https://raw.githubusercontent.com/mmobrain/stuffforstuff/refs/heads/main/lc/1.jpg)

### 3. Coordinate with Community and Allies
* **Automatic Sharing:** When you loot a qualifying item, its location is automatically shared with other LootCollector users.
* **Real-Time Updates:** Receive notifications and map updates as other players discover items.
* **Direct Point-of-Interest Pings ("Show to"):** Right-click any pin on your map and select "Show to..." to send the exact location directly to a friend. If they accept, the item is highlighted on their map with a pulsing animation so they can collect their upgrade immediately.

### 4. Spend Less Time on Empty Spawns
* **Community-Driven Mapping:** Spawns are kept accurate through a community vote system. If an item is no longer at a location, players can right-click the pin to **"Report as Gone."** If enough players agree, the node fades and is removed, saving you from running to empty camp spots.
* **Realm Isolation:** Your data is kept organized by realm (Realm Buckets). Seasonal, Wildcard, and Main realm data never mix.

---

## Essential Shortcuts for Quick Navigation

* **Shift + Left Click (on any Discovery):** Instantly pans the world map to that item's location and plays a pulsing highlight.
* **Ctrl + Alt + Left Click:** Automatically links the item and its map coordinates directly into your active chat window (party, guild, or whisper).
* **Alt + Mouseover:** Displays additional information about the discovery in the tooltip.
* **Ctrl + Mouseover:** Disables the nearby proximity list when hovering over tightly packed clusters of pins, making it easier to select a single target.
* **Shift + Left Click (on Minimap Button):** Allows you to drag and reposition the button.

---

## Simple Slash Commands

* `/lc` – Opens the configuration panel to toggle filters, visibility, and settings.
* `/lcv` – Opens the Discovery Viewer to search the database of items, stats, and locations.
* `/lcarrow` – Toggles the navigation arrow.
* `/lcarrow clearskip` – Clears your list of temporarily skipped targets, resetting your navigation path.
* `/lctoggle` – Instantly toggles the visibility of all pins on your world map and minimap.
* `/lcshare <party|raid|guild|whisper> [player]` – Broadcasts your discovery database to other players.
* `/lcexport` / `/lcimport` – Opens the manual text import/export windows to share databases outside of the game (e.g., via Discord).
* `/lcpause` - Hibernates addon functionality.

---

## Installation

1.  Download the latest version from the [Releases](https://github.com/mmobrain/LootCollector/releases) page.
2.  Extract the ZIP file.
3.  Copy the `LootCollector` folder into your `Interface\AddOns` directory in your World of Warcraft installation.
4.  Restart World of Warcraft.

---

## FAQ

#### I just installed or updated the addon and my map is empty. What should I do?
Because the addon separates databases by realm, your map might appear empty if you have not discovered any items on that character yet. You can quickly populate your map by importing a community-shared database string via `/lcimport` or by syncing with guild members who are running the addon.

#### How do I send a specific weapon or armor location to a friend?
Right-click the pin on your world map, select "Show to...", and enter your friend's character name. They will receive a prompt to view the location directly on their map.

#### Why did a pin fade or disappear from my map?
Other players have reported that the Discovery is no longer at that location. This system removed outdated or missing entry automatically.

#### How do I share data with friends?
You can use the `/lcshare party` command to broadcast your database to party members, or use `/lcexport` to generate a text string that can be pasted into Discord or forums. Friends can use `/lcimport` to load it.

#### Why do some discoveries appear on the Continent map instead of a specific zone?
Certain sub-zones in the 3.3.5a client do not have their own specific map data/texture. When inside these areas, the game defaults to the Continent view. To maintain coordinate accuracy, LootCollector records these exactly as reported by the game. Building a solution around this would ultimately create more problems than it solves.

**Known affected areas include:**
*   **Dire Maul** (appears on Kalimdor map, located in Feralas)
*   **Caverns of Time** Entrance (appears on Kalimdor map, located in Tanaris)
*   **Blackrock Mountain** (appears on Eastern Kingdoms map, located between Searing Gorge/Burning Steppes)
*   **The Deadmines** Entrance (appears on Eastern Kingdoms map, located in Westfall)
*   **Wailing Caverns** Entrance (appears on Kalimdor map, located in The Barrens)
*   **Scarlet Monastery** Entrance (appears on Eastern Kingdoms map, located in Tirisfal Glades)

#### Why are some item names or icons missing?**
The addon caches item information as it encounters it. If you see "Unknown Item" or a question mark icon, the server hasn't sent the item data to your client yet. The addon will automatically retry fetching this information in the background.

#### I don't see any tooltip changes with "Enhanced WF Toltip" enabled.**
You need AtlasLoot installed and AtlasLoot_Cache enabled for the enhanced tooltips to appear.

#### I can't click the map pins or open the right-click menu.**
The default "M" map key opens the map in a mode that sometimes blocks LC interaction. To fully interact with pins, use the command `/script WorldMapFrame:Show()` (you can create macro and keyind it) or install a map addon like **Magnify (WotLK Edition)** or **ElvUI**, which handle this automatically.

## Contributing

This project is open to contributions from the community. If you are interested in fixing a bug or adding a new feature, please refer to the **[CONTRIBUTING.md](CONTRIBUTING.md)** guide for developer guidelines and best practices.

#### Credits
*   **Author:** Skulltrail
*   **Contributors:** Deidre, Rhenyra, Morty, Markosz, Bandit Tech, xan, Stilnight and Xurkon
*   **Early alpha Top Collectors:** Morty, Laya, Brokenheart, Mie, Rhen, Aaltrix, Insanestar, Harrydn, Blutact

#### License
This project is released under the [MIT License](LICENSE.md).
