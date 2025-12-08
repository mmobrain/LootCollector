# LootCollector for Project Ascension (Bronzebeard)

> [!IMPORTANT]  
> **Compatibility Notice:** This addon has been developed and tested specifically for the **Bronzebeard** realm of Project Ascension. Its data-sharing model is designed for static world object spawns (e.g., clickable chests/nodes). On realms where items like Mystic Scrolls drop from random mobs, sharing coordinates is not useful, and this addon may not function as intended.

**LootCollector** is a community-driven discovery and navigation tool for the Bronzebeard realm of Project Ascension. It creates a live, shared, and now self-healing database of hand-placed world objects-such as Worldforged gear-by allowing all users to automatically share their findings and report when items are gone.

Screenhots from live Brozebeard few fours after launch (0.4.2-alpha):
![image](https://i.imgur.com/cfYL2fM.jpeg)

Screenhots from 0.5.1S-alpha:
![image](https://i.imgur.com/W7oPo9L.jpeg)

Screenhots from 0.5.90-alpha:
![image](https://i.imgur.com/HGY0ITz.jpeg)


## Installation

1.  Download the latest version from the [Releases](https://github.com/mmobrain/LootCollector/releases) page.
2.  Extract the ZIP file.
3.  Copy the `LootCollector` folder into your `Interface\AddOns` directory in your World of Warcraft installation.
4.  Restart World of Warcraft.

## Key Features

### 1. Live Community Database
*   **Automatic Sharing:** When you loot a qualifying item, its location is automatically shared with other LootCollector users after a brief delay to ensure data accuracy.
*   **Real-Time Updates:** Receive notifications and map updates as other players discover items.
*   **Community Moderation:** Is a discovery no longer there? Right-click its pin and "Report as Gone." With enough reports from the community, an item's status will change to `FADING` and eventually `STALE`.
*   **Spam & Tamper Resistance:** The network protocol automatically validates incoming data, tracks sender reputation, and strictly enforces valid zone IDs to protect the database from invalid or malicious information.

### 2. Advanced Map & Navigation Tools
*   **Map Search & Focus:** A search bar on the world map allows you to filter pins by item or zone name. Find an item from anywhere and use the "Focus" feature (`Shift+Click`) to have the map automatically pan and play a pulsing animation at its location.
*   **Interactive Map Overlay:**
    *   **Quality Borders:** Pin borders are now color-coded by item quality for at-a-glance identification.
    *   **Status Indicators:** `FADING` and `STALE` items are transparent, while items you've already looted are desaturated.
*   **TomTom Integration:**
    *   **Auto-Track Nearest:** Enable this option to have the navigation arrow automatically point to the closest unlooted discovery matching your filters.
    *   **Skip Target:** Don't want to go to the nearest item? Use the map menu to skip it for your current session.
*   **Smarter Minimap:** The minimap has been overhauled for better performance and accuracy. Distance filter lets you control how far away discoveries can be before they appear. You can also mouse over an minimap icons to see details!

### 3. Powerful Filtering & Data Management
*   **Advanced Filtering:** The filter menu gives you full control over what you see.
    *   Hide items by status (`Faded`, `Stale`, `Unconfirmed`) or those you've already looted.
    *   Filter by **Usable by Class** or specific **Equipment Slot** (e.g., only Trinkets).
*   **"Show to..." Player Sharing:** Right-click a map pin and select "Show to..." to send a discovery's location directly to another player via whisper. They'll get a prompt to view it on their map.
*   **Import/Export:** A new "Import from File" method allows you to safely import massive community databases without freezing your client.

## Slash Commands

*   `/lc` or `/lootcollector` - Opens the main options panel.
*   `/lcv` or `/lcviewer` - Opens the Discovery Viewer (Database List).
*   `/lcarrow` - Toggles the TomTom navigation arrow.
*   `/lcarrow clearskip` - Clears the list of temporarily skipped arrow targets.
*   `/lctop` - Displays the top 10 contributors from the database.
*   `/lcpause` - Toggles the pausing of all incoming and outgoing messages.
*   `/lcshare <party|raid|guild|whisper> [player]` - Manually shares your entire database with others.
*   `/lcexport` / `/lcimport` - Opens the export/import dialog windows.
*   `/lcczfix` - Runs a database repair tool to fix entries with mismatched Continent/Zone IDs.

## Other QOL
*   `Shift+click` - Focus on discovery on the map.
*   `Ctrl+Alt+click` - Link discovery with coords to chat.
*   `Ctrl+mouseover` - Disables Proximity List feature when hovering over multiple icons are clustered closely on Map.
*   `Alt+mouseover` - Shows additional info about Map discovery.
*   `Shift+LMB (on LC button)` - Repositions the LC map button.

## FAQ & Known Issues

**Q: I just updated and my map is empty! Where did my data go?**
**A:** Version 0.5.90 introduced **Realm Buckets**. Your old data was likely "Global". When you log in, the addon attempts to migrate your data to the correct Realm Bucket (e.g., "Bronzebeard - Warcraft Reborn"). If you switched realms recently or the migration failed, your data might be in a different bucket. Try importing a fresh starter database to repopulate the correct realm.
Additionally, old databases from before version 0.5.1 will likely not work.

**Q: I found an item but it wasn't shared.**
**A:** The addon automatically shares items that have the "Worldforged" subtitle in their tooltip or "Mystic Scroll" in their name. Other items are not shared automatically. Ensure sharing is enabled in the options (`/lc`).

**Q: The arrow is pointing in the wrong direction.**
**A:** TomTom relies on a library named Astrolabe for map data. Project Ascension has custom zones and currently manages Astrolable internally. You can set the exact same waypoint manually using tomtom /way (example: /way azshara 50.0 50.0) and check if it works. 

**Q:  How do I share data with friends?**
**A:** You can use the `/lcshare party` command to broadcast your database to party members, or use `/lcexport` to generate a text string that can be pasted into Discord or forums. Friends can use `/lcimport` to load it.

**Q: Why do some discoveries appear on the Continent map instead of a specific zone?**
**A:** Certain sub-zones in the 3.3.5a client do not have their own specific map data/texture. When inside these areas, the game defaults to the Continent view. To maintain coordinate accuracy, LootCollector records these exactly as reported by the game. Building a solution around this would ultimately create more problems than it solves.

**Known affected areas include:**
*   **Dire Maul** (appears on Kalimdor map, located in Feralas)
*   **Caverns of Time** Entrance (appears on Kalimdor map, located in Tanaris)
*   **Blackrock Mountain** (appears on Eastern Kingdoms map, located between Searing Gorge/Burning Steppes)
*   **The Deadmines** Entrance (appears on Eastern Kingdoms map, located in Westfall)
*   **Wailing Caverns** Entrance (appears on Kalimdor map, located in The Barrens)
*   **Scarlet Monastery** Entrance (appears on Eastern Kingdoms map, located in Tirisfal Glades)

**Q: Why are some item names or icons missing?**
**A:** The addon caches item information as it encounters it. If you see "Unknown Item" or a question mark icon, the server hasn't sent the item data to your client yet. The addon will automatically retry fetching this information in the background.

**Q: I can't click the map pins or open the right-click menu.**
**A:** The default "M" map key opens the map in a mode that sometimes blocks LC interaction. To fully interact with pins, use the command `/script WorldMapFrame:Show()` (you can create macro and keyind it) or install a map addon like **Magnify (WotLK Edition)** or **ElvUI**, which handle this automatically.

**Q: I don't see any tooltip changes with "Enhanced WF Toltip" enabled.**
**A:** You need AtlasLoot installed and AtlasLoot_Cache enabled for the enhanced tooltips to appear.

## Contributing

This project is open to contributions from the community. If you are interested in fixing a bug or adding a new feature, please refer to the **[CONTRIBUTING.md](CONTRIBUTING.md)** guide for developer guidelines and best practices.

## Credits
*   **Author:** Skulltrail
*   **Contributors:** Deidre, Rhenyra, Morty, Markosz, Bandit Tech, xan, Stilnight
*   **Early alpha Top Collectors:** Morty, Laya, Brokenheart, Mie, Rhen, Aaltrix, Insanestar, Harrydn, Blutact

## License
This project is released under the [MIT License](LICENSE.md).