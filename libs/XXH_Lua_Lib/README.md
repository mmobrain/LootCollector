# XXH_Lua_Lib


A high-performance, pure Lua implementation of the XXHash algorithm, optimized for the World of Warcraft (3.3.5/Lua 5.1) addon environment. 
This library is reasonably fast and robust implementation of non-cryptographic hashing with zero external dependencies.

## Features
*   **Pure Lua 5.1:** Fully compatible with the World of Warcraft addon environment.
*   **High Performance:** Leverages the native `bit` library for maximum speed.
*   **Standard Compliant:** Produces correct XXH32 and XXH64 hash values.
*   **Self-Contained:** A single, drop-in file with no external dependencies.
*   **Provides both XXH32 and XXH64:** Choose between the fastest 32-bit hash or less collisions prone 64-bit version.


## Installation
1.  Copy the `XXH_Lua_Lib.lua` file into your addon's directory.
2.  Add the file to your addon's `.toc` file to ensure it is loaded by the game client. Make sure it loads before any files that use it.


## My Addon TOC
XXH_Lua_Lib.lua
MyAddonCore.lua

The library will be available globally as the `XXH_Lua_Lib` table.


## API Reference

### `XXH_Lua_Lib.XXH32(inputString, [seed])`

Calculates a 32-bit XXHash. This is the recommended function for most use cases due to its excellent speed and quality.

*   **`inputString`** (`string`): The data to hash.
*   **`seed`** (`number`, optional): A 32-bit number to seed the hash. Defaults to `0`.
*   **Returns:** (`string`) An 8-character hexadecimal string representing the 32-bit hash.


### `XXH_Lua_Lib.XXH64(inputString, [seed])`
Calculates a 64-bit XXHash using emulated 64-bit arithmetic. This function provides extremely high collision resistance at the cost of performance.

*   **`inputString`** (`string`): The data to hash.
*   **`seed`** (`number`, optional): A 32-bit number to seed the lower bits of the hash. Defaults to `0`.
*   **Returns:** (`string`) A 16-character hexadecimal string representing the 64-bit hash.


## Example Usage

-- Assuming XXH_Lua_Lib.lua is loaded via your .toc file
local XXH = XXH_Lua_Lib

-- --- XXH32 Example ---
local myString = "Skulltrail-Bronzebeard"
local mySeed = 2025

local hash32 = XXH.XXH32(myString, mySeed)
print(string.format("XXH32 hash of '%s' is: 0x%s", myString, hash32))
-- Expected output: XXH32 hash of 'Skulltrail-Bronzebeard' is: 0X36A8DB00


-- --- XXH64 Example ---
local anotherString = "item:19019:0:0:0:0:0:0:0"
local anotherSeed = 24

local hash64 = XXH.XXH64(anotherString, anotherSeed)
print(string.format("XXH64 hash of '%s' is: %s", anotherString, hash64))

-- Expected output: XXH64 hash of 'item:19019:0:0:0:0:0:0:0' is: 74A23844118D1EE3


## Performance Considerations

*   **`XXH32` is quite fast.** It is highly optimized and should be your default choice for hashing strings in performance-critical code, such as table lookups, data caching, and quick comparisons.

*   **`XXH64` is slower.** The 64-bit integer emulation required in Lua 5.1 makes this function significantly slower than `XXH32`. Only use it when you need the highest possible guarantee against hash collisions (e.g., generating unique IDs for a very large dataset shared between many users). emulated 64-bit version is slower than 32-bit up to 3.5 times)

## Credits
*   **Author:** Skulltrail
*   **Algorithm:** Based on the original XXHash algorithm by Yann Collet.
