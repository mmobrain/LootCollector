## Developer's Guide for Contributors

Thank you for your interest in contributing to LootCollector! To ensure the addon remains stable and functional for the entire community, please adhere to the following guidelines.

*A Note on Project Ascension*
LootCollector is designed specifically for the Project Ascension (3.3.5a) custom World of Warcraft server. At its core, the addon is built around custom game mechanics unique to this platform, which are not present in the standard WotLK client. All contributions must maintain compatibility with this unique environment, as future features will continue to rely on and expand this custom integration. 

### Project Structure Overview

The addon is organized into several key modules:

-   **`LootCollector.lua`**: The main addon file that loads dependencies and manages core state.
-   **`Modules/Core.lua`**: Handles the central database logic, including adding, removing, and migrating discoveries.
-   **`Modules/Detect.lua`**: Responsible for detecting new discoveries from in-game events (looting, NPC interaction).
-   **`Modules/Comm.lua`**: Manages all network communication, including serialization, compression, and rate-limiting.
-   **`Modules/Reinforce.lua`**: Schedules and broadcasts reinforcement messages (`CONF`) to keep discoveries active on the network.
-   **`Modules/Map.lua`**: Renders all visual elements on the world map and minimap.
and more...

### The Database Schema: A Critical Note

LootCollector uses a shared, global database (`LootCollectorDB_Asc`) that is synchronized across all of a user's characters and other players. The structure of this database is fundamental to the addon's stability.

**⚠️ Do NOT make any schema changes on your own when contributing to this project.**

The database schema is the "contract" that ensures data saved by one version of the addon can be read by another. Unauthorized changes can lead to widespread data corruption, Lua errors, and a poor user experience.

-   **Why is this so important?** An unplanned change (e.g., renaming `d.fp` to `d.foundBy`) will cause any code expecting the old field to fail with a `nil` error.
-   **When are schema changes acceptable?** Schema changes are only made in major version updates and are always accompanied by a carefully written migration script (see `Modules/Migration_v5.lua`). This process must be planned and approved by the core project maintainers.
-   **What to do if you think a change is needed:** If you believe a database change is necessary to implement a new feature or fix a bug, please open an issue or pull request and clearly explain your reasoning. This allows for a proper discussion and, if approved, the creation of a safe migration path.

### Forking and Custom Versions

If you plan to release a forked version of LootCollector that significantly changes the logic or requires a different database structure, you **must** use a different communication channel to avoid conflicts with the main version.

This prevents your version from sending or receiving incompatible data to users of the official addon, which could cause errors for both groups.

To change the communication channel:

1.  **Modify `Modules/Constants.lua`**:
    Change the default prefix and channel name to something unique for your version.

    ```lua
    -- In Modules/Constants.lua
    Constants.ADDON_PREFIX_DEFAULT = "MyFork_CAM25" -- Change this
    Constants.CHANNEL_NAME_DEFAULT = "MyFork_LCC25" -- And this
    ```

2.  **Rename your SavedVariables file**:
    In `LootCollector.toc`, change the `## SavedVariables` line to prevent your version from overwriting the official addon's database.

    ```
    ## SavedVariables: MyFork_LootCollectorDB
    ```

### Submitting Pull Requests

1.  **Fork the repository.**
2.  **Create a new branch** for your feature or bugfix (`git checkout -b feature/my-new-feature`).
3.  **Make your changes.** Please ensure your code is commented and follows the existing style.
4.  **Test your changes thoroughly.** Use the built-in developer commands (`/lcsimdb`, `/lcinject`, etc.) to test different scenarios.
5.  **Submit a pull request** with a clear description of the problem you are solving and the changes you have made.

Thank you for helping to make LootCollector better!