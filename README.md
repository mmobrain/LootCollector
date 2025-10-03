# LootCollector for Project Ascension (Bronzebeard)

> [!IMPORTANT]  
> **Compatibility Notice:** This addon has been developed and tested specifically for the **Bronzebeard** realm of Project Ascension. Its data-sharing model is designed for static world object spawns (e.g., clickable chests/nodes). On realms where items like Mystic Scrolls drop from random mobs, sharing coordinates is not useful, and this addon may not function as intended.

**LootCollector** is a community-driven discovery and navigation tool for the Bronzebeard realm of Project Ascension. It creates a live, shared database of hand-placed, static world objects—such as Worldforged gear and Mystic Scrolls—by allowing all users to automatically share their findings with each other in real-time.

Unlike addons that require manual updates after every server patch, LootCollector's database is evergreen. All it takes is one user to find a new item, and its location is instantly shared with the entire addon community.

## Installation

1.  Download the latest version from the [Releases](https://github.com/your-username/LootCollector/releases) page.
2.  Extract the ZIP file.
3.  Copy the `LootCollector` folder into your `Interface\AddOns` directory in your World of Warcraft installation.
4.  Restart World of Warcraft.

## Key Features

### 1. Live Community Database
*   **Automatic Sharing:** When you loot a qualifying item (like a Worldforged piece or Mystic Scroll), its location is automatically shared with other LootCollector users.
*   **Real-Time Updates:** Receive notifications and map updates as other players discover items around the world.
*   **Status System:** Discoveries are tracked with a status (`UNCONFIRMED`, `FADING`, `STALE`), giving you an idea of how recently an item was seen.
*   **Anonymous Mode:** Enable "Nameless Sharing" to contribute as "An Unnamed Collector".
*   **Delayed Sharing:** Need a head start? Enable "Delayed Sharing" to wait a configurable amount of time before broadcasting your find.
*   **Pause Functionality:** Temporarily pause all incoming and outgoing messages with `/lcpause` or through the map menu. Perfect for high-stakes situations.

### 2. Map & Navigation Tools
*   **Interactive Map Overlay:** All known discoveries are plotted directly on your world map with item icons.
    *   **Dynamic Icons:** Icons are color-coded by quality and change transparency based on their status (faded, stale).
    *   **Looted Indicators:** Items you've already looted on your current character are clearly marked.
    *   **Configurable Size:** Adjust the size of map icons to your preference via the settings panel.
*   **TomTom Integration:** If you have the TomTom addon installed, LootCollector will use its navigation arrow to guide you to a discovery.
    *   Right-click any discovery on the map and select "Navigate here" to set it as your target.

### 3. Advanced Filtering
A filtering system, accessible via the "LC" button on the world map, gives you full control over what you see.
*   **Hide by Status:** Hide discoveries that are `Faded`, `Stale`, or `Unconfirmed`.
*   **Hide Looted:** Hide all items you've already found on your current character.
*   **Filter by Quality:** Set a minimum item rarity to display on the map.
*   **Filter by Equip Slot:** Only show specific armor or weapon types (e.g., only Trinkets and Two-Handed Weapons).
*   **Filter by Class:** Show only items usable by your class.

### 4. Data Management
*   **Import/Export:** Share your entire discovery database with friends or import a backup. The addon uses a compressed format for easy sharing.
*   **Top Contributors:** See a list of the top 10 players who have contributed the most discoveries with the `/lctop` command.

## How to Configure

All major options can be configured through the in-game panel or the "LC" button on the world map.

*   **Open the options:** Type `/lc` in chat.
*   **Navigate to:** `Interface -> AddOns -> LootCollector`

## Slash Commands

*   `/lc` - Opens the main options panel.
*   `/lcarrow` - Toggles the TomTom navigation arrow.
*   `/lctop` - Displays the top 10 contributors from the database.
*   `/lcpause` - Toggles the pausing of all incoming and outgoing messages.
*   `/lcshare <party|raid|guild|whisper> [player]` - Manually shares your entire database with others.
*   `/lcexport` / `/lcimport` - Opens the export/import dialog windows.

## FAQ

**Q: I don't see an arrow. How do I turn it on?**
**A:** The navigation arrow requires the **TomTom** addon to be installed and enabled. Once TomTom is running, you can right-click a discovery on the map to navigate to it or type `/lcarrow` to toggle the arrow.

**Q: The arrow is pointing in the wrong direction.**
**A:** TomTom relies on a library named Astrolabe for zone and map data. Project Ascension has many custom zones that may not be in Astrolabe's database. Until this library is updated with the custom map data, TomTom may fail to navigate correctly in some places.

**Q: Why does a map icon say "Found by: Unknown"?**
**A:** This can happen if the discovery was imported from an older version of the addon, or if the person who found it had "Nameless Sharing" enabled. New discoveries you find should always be credited to your name.

**Q: I found an item but it wasn't shared.**
**A:** The addon currently filters for items that contain the keywords "Worldforged" or "Mystic Scroll" in their tooltips. Other items are not automatically shared. Also, ensure that sharing is enabled in the options (`/lc`).

## License
This project is released under the [MIT License](LICENSE.md).