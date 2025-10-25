# LootCollector for Project Ascension (Bronzebeard)

> [!IMPORTANT]  
> **Compatibility Notice:** This addon has been developed and tested specifically for the **Bronzebeard** realm of Project Ascension. Its data-sharing model is designed for static world object spawns (e.g., clickable chests/nodes). On realms where items like Mystic Scrolls drop from random mobs, sharing coordinates is not useful, and this addon may not function as intended.

**LootCollector** is a community-driven discovery and navigation tool for the Bronzebeard realm of Project Ascension. It creates a live, shared, and now self-healing database of hand-placed world objects-such as Worldforged gear-by allowing all users to automatically share their findings and report when items are gone.

Thanks to a completely re-engineered database and network protocol, LootCollector is faster, more accurate, and more reliable than ever. All it takes is one user to find a new item, and its location is instantly shared with the entire addon community.


Screenhots from live Brozebeard few fours after launch (0.4.2-alpha):
![image](https://i.imgur.com/cfYL2fM.jpeg)

Screenhots from 0.5.1S-alpha:
![image](https://i.imgur.com/W7oPo9L.jpeg)

## Installation

1.  Download the latest version from the [Releases](https://github.com/mmobrain/LootCollector/releases) page.
2.  Extract the ZIP file.
3.  Copy the `LootCollector` folder into your `Interface\AddOns` directory in your World of Warcraft installation.
4.  Restart World of Warcraft.

## Key Features

### 1. Live Community Database
*   **Automatic Sharing:** When you loot a qualifying item, its location is automatically shared with other LootCollector users after a brief delay to ensure data accuracy.
*   **Real-Time Updates:** Receive notifications and map updates as other players discover items.
*   **Community Moderation:** Is a discovery no longer there? Right-click its pin and "Report as Gone." With enough reports from the community, an item's status will change to `FADING` and eventually `STALE`, keeping the map clean and up-to-date.
*   **Spam & Tamper Resistance:** The new network protocol automatically validates incoming data and tracks sender reputation, protecting the database from invalid or malicious information.
*   **Nameless & Delayed Sharing:** Enable "Nameless Sharing" to contribute anonymously or "Delayed Sharing" to wait a configurable time before broadcasting your find.

### 2. Advanced Map & Navigation Tools
*   **Clustered Map View:** The continent map is now decluttered! Discoveries are grouped into a single pin per zone with a counter. Clicking a cluster zooms you into that zone's map.
*   **Map Search & Focus:** A new search bar on the world map allows you to filter pins by item or zone name. Find an item from anywhere and use the "Focus" feature to have the map automatically pan and play a pulsing animation at its location.
*   **Interactive Map Overlay:** All known discoveries are plotted on your map with item icons.
    *   **Quality Borders:** Pin borders are now color-coded by item quality for at-a-glance identification.
    *   **Status Indicators:** `FADING` and `STALE` items are transparent, while items you've already looted are desaturated.
*   **Smarter TomTom Integration:**
    *   **Auto-Track Nearest:** Enable this new option to have the navigation arrow automatically point to the closest unlooted discovery matching your filters. (Requires TomTom and may not work in starter zone untill Astrolable - a library that TomTom uses is updated)
    *   **Skip Target:** Don't want to go to the nearest item? Use the map menu to skip it for your current session.
*   **Smarter Minimap:** The minimap has been overhauled for better performance and accuracy. A new distance filter lets you control how far away discoveries can be before they appear. You can also mouse over an minimap icons to see details!

### 3. Powerful Filtering & Data Management
*   **Advanced Filtering:** The filter menu gives you full control over what you see.
    *   Hide items by status (`Faded`, `Stale`, `Unconfirmed`) or those you've already looted.
    *   **New:** Filter by **Usable by Class** or specific **Equipment Slot** (e.g., only Trinkets), which works even for items you haven't seen before.
*   **"Show to..." Player Sharing:** Right-click a map pin and select "Show to..." to send a discovery's location directly to another player via whisper. They'll get a prompt to view it on their map.
*   **Import/Export:** A new "Import from File" method allows you to safely import massive community databases without freezing your client.

## Slash Commands

*   `/lc` or `/lootcollector` - Opens the main options panel.
*   `/lchistory` - Opens the new Discovery History window (test).
*   `/lcarrow` - Toggles the TomTom navigation arrow.
*   `/lcarrow clearskip` - Clears the list of temporarily skipped arrow targets.
*   `/lctop` - Displays the top 10 contributors from the database.
*   `/lcpause` - Toggles the pausing of all incoming and outgoing messages.
*   `/lcshare <party|raid|guild|whisper> [player]` - Manually shares your entire database with others.
*   `/lcexport` / `/lcimport` - Opens the export/import dialog windows.

## Other QOL
*   `Shift+click` - focus on discovery on the map
*   `Ctrl+Alt+click` - link discovery with coords on chat

## FAQ

**Q: I don't see an arrow. How do I turn it on?**
**A:** The navigation arrow requires the **TomTom** addon. Once installed, you can enable "Auto-track Nearest Unlooted" in the map filter menu, right-click a discovery and select "Navigate here," or type `/lcarrow`.

**Q: What do the `FADING` and `STALE` statuses mean?**
**A:** These statuses are part of the new community moderation system. When enough players report an item as "gone," its status changes to `FADING`. If it remains unconfirmed after a long time, it becomes `STALE`. This helps keep the map accurate by highlighting discoveries that may no longer be there.

**Q: I found an item but it wasn't shared.**
**A:** The addon automatically shares items that have the "Worldforged" subtitle in their tooltip or "Mystic Scroll" in their name. Other items are not shared. Also, ensure that sharing is enabled in the options (`/lc`).

**Q: The arrow is pointing in the wrong direction.**
**A:** TomTom relies on a library named Astrolabe for map data. Project Ascension has custom zones that may not be in Astrolabe's database. While LootCollector includes its own data for minimap accuracy, TomTom's world map navigation may still fail in some custom areas.

## Contributing

This project is open to contributions from the community. If you are interested in fixing a bug or adding a new feature, please refer to the **[CONTRIBUTING.md](CONTRIBUTING.md)** guide for developer guidelines and best practices.

## License
This project is released under the [MIT License](LICENSE.md).