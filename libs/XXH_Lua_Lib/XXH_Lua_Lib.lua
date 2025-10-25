--[[

XXH_Lua_Lib.lua

A high-performance, pure Lua 5.1 implementation of XXHash32 and XXHash64 optimized for World of Warcraft (3.35) addon environment, relying on the native `bit` library for maximum speed and compatibility. 
It provides both 32-bit and 64-bit hashing functions (64-bit arithmetic via two 32-bit halves)


  ------------------------------------------------------------------------------
  Version: 1.0.0
  Date: October 12, 2025
  Author: Skulltrail
  Algorithm Credit: Based on the original XXHash algorithm by Yann Collet.
  ------------------------------------------------------------------------------


API:
- XXH32(inputString, [seed]) -> 32-bit unsigned integer (Lua number, masked to 0xFFFFFFFF) | 1234567890 (32-bit number)
- XXH64(inputString, [seed]) -> 16-char uppercase hex string
- RunSelfTests([opts]) -> Prints test results to chat and returns boolean status.
  opts:
    - hexDumpAlways    = true|false  -- if true, shows hex dump for every test
    - which            = "all"|"lua"|"ascii"|"hex" -- select subset of tests

]]

local bit    = bit
local band   = bit.band
local bor    = bit.bor
local bxor   = bit.bxor
local lshift = bit.lshift
local rshift = bit.rshift

local string = string
local sbyte  = string.byte
local table  = table
local _G     = _G

-- =========================================================================
-- CONSTANTS
-- =========================================================================

local P32_1 = 0x9E3779B1
local P32_2 = 0x85EBCA77
local P32_3 = 0xC2B2AE3D
local P32_4 = 0x27D4EB2F
local P32_5 = 0x165667B1

-- 64-bit primes split into hi/lo 32-bit words
local P64_1_H, P64_1_L = 0x9E3779B1, 0x85EBCA87
local P64_2_H, P64_2_L = 0xC2B2AE3D, 0x27D4EB4F
local P64_3_H, P64_3_L = 0x165667B1, 0x9E3779F9
local P64_4_H, P64_4_L = 0x85EBCA77, 0xC2B2AE63
local P64_5_H, P64_5_L = 0x27D4EB2F, 0x165667C5

local U32_MASK = 0xFFFFFFFF
local TWO32    = 4294967296

-- =========================================================================
-- 32-bit helpers
-- =========================================================================

local function rol32_fallback(x, s)
    s = band(s or 0, 31)
    if s == 0 then
        return band(x, U32_MASK)
    end
    local left  = lshift(band(x, U32_MASK), s)
    local right = rshift(band(x, U32_MASK), 32 - s)
    return band(bor(left, right), U32_MASK)
end

local rol32 = (bit and bit.rol) or rol32_fallback

local function imul32(a, b)
    a = band(a or 0, U32_MASK)
    b = band(b or 0, U32_MASK)
    local a_hi, a_lo = rshift(a, 16), band(a, 0xFFFF)
    local b_hi, b_lo = rshift(b, 16), band(b, 0xFFFF)
    local p1 = a_lo * b_lo
    local p2 = a_lo * b_hi
    local p3 = a_hi * b_lo
    local mid  = rshift(p1, 16) + band(p2, 0xFFFF) + band(p3, 0xFFFF)
    local lo32 = band(p1, 0xFFFF) + lshift(band(mid, 0xFFFF), 16)
    return band(lo32, U32_MASK)
end

local function read_u32_le(str, offset)
    local b1, b2, b3, b4 = sbyte(str, offset, offset + 3)
    b1, b2, b3, b4 = b1 or 0, b2 or 0, b3 or 0, b4 or 0
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- =========================================================================
-- XXH32
-- =========================================================================

local function XXH32(str, seed)
    local len = #str
    seed = band(seed or 0, U32_MASK)

    local h32
    local index = 1

    if len >= 16 then
        local acc1 = band(seed + P32_1 + P32_2, U32_MASK)
        local acc2 = band(seed + P32_2, U32_MASK)
        local acc3 = band(seed, U32_MASK)
        local acc4 = band(seed - P32_1, U32_MASK)

        local limit = len - 15
        while index <= limit do
            acc1 = imul32(rol32(band(acc1 + imul32(read_u32_le(str, index),      P32_2), U32_MASK), 13), P32_1)
            acc2 = imul32(rol32(band(acc2 + imul32(read_u32_le(str, index + 4),  P32_2), U32_MASK), 13), P32_1)
            acc3 = imul32(rol32(band(acc3 + imul32(read_u32_le(str, index + 8),  P32_2), U32_MASK), 13), P32_1)
            acc4 = imul32(rol32(band(acc4 + imul32(read_u32_le(str, index + 12), P32_2), U32_MASK), 13), P32_1)
            index = index + 16
        end

        h32 = band(rol32(acc1, 1) + rol32(acc2, 7) + rol32(acc3, 12) + rol32(acc4, 18), U32_MASK)
    else
        h32 = band(seed + P32_5, U32_MASK)
    end

    h32 = band(h32 + len, U32_MASK)

    while index <= len - 3 do
        h32 = band(h32 + imul32(read_u32_le(str, index), P32_3), U32_MASK)
        h32 = imul32(rol32(h32, 17), P32_4)
        index = index + 4
    end

    -- At most three tail bytes;
    local rem = len - index + 1
    if rem >= 1 then
        h32 = band(h32 + imul32(sbyte(str, index), P32_5), U32_MASK)
        h32 = imul32(rol32(h32, 11), P32_1)
        index = index + 1
    end
    if rem >= 2 then
        h32 = band(h32 + imul32(sbyte(str, index), P32_5), U32_MASK)
        h32 = imul32(rol32(h32, 11), P32_1)
        index = index + 1
    end
    if rem >= 3 then
        h32 = band(h32 + imul32(sbyte(str, index), P32_5), U32_MASK)
        h32 = imul32(rol32(h32, 11), P32_1)
    end

    h32 = bxor(h32, rshift(h32, 15))
    h32 = imul32(h32, P32_2)
    h32 = bxor(h32, rshift(h32, 13))
    h32 = imul32(h32, P32_3)
    h32 = bxor(h32, rshift(h32, 16))

    return h32
end

-- =========================================================================
-- 64-bit helpers (hi, lo)
-- =========================================================================

local function mul32_to64(a, b)
    a = band(a or 0, U32_MASK)
    b = band(b or 0, U32_MASK)
    local a_hi, a_lo = rshift(a, 16), band(a, 0xFFFF)
    local b_hi, b_lo = rshift(b, 16), band(b, 0xFFFF)
    local p1 = a_lo * b_lo
    local p2 = a_lo * b_hi
    local p3 = a_hi * b_lo
    local p4 = a_hi * b_hi
    local mid     = rshift(p1, 16) + band(p2, 0xFFFF) + band(p3, 0xFFFF)
    local lo_word = band(p1, 0xFFFF) + lshift(band(mid, 0xFFFF), 16)
    local hi_word = p4 + rshift(p2, 16) + rshift(p3, 16) + rshift(mid, 16)
    return band(hi_word, U32_MASK), band(lo_word, U32_MASK)
end

local function mul64(a_hi, a_lo, b_hi, b_lo)
    local p1_hi, p1_lo = mul32_to64(a_lo, b_lo)
    local p2_lo        = imul32(a_lo, b_hi)
    local p3_lo        = imul32(a_hi, b_lo)
    local hi           = band(p1_hi + p2_lo + p3_lo, U32_MASK)
    local lo           = p1_lo
    return hi, lo
end

-- Specialized: 32-bit value x times 64-bit constant (C_H, C_L)
local function mul_u32_const64(x, C_H, C_L)
    local hi_part, lo_part = mul32_to64(x, C_L)
    hi_part = band(hi_part + imul32(x, C_H), U32_MASK)
    return hi_part, lo_part
end

local function add64(a_hi, a_lo, b_hi, b_lo)
    a_hi, a_lo = band(a_hi or 0, U32_MASK), band(a_lo or 0, U32_MASK)
    b_hi, b_lo = band(b_hi or 0, U32_MASK), band(b_lo or 0, U32_MASK)

    local sum_lo = a_lo + b_lo
    local carry  = (sum_lo >= TWO32) and 1 or 0
    if carry ~= 0 then
        sum_lo = sum_lo - TWO32
    end
    local sum_hi = a_hi + b_hi + carry
    return band(sum_hi, U32_MASK), band(sum_lo, U32_MASK)
end

local function sub64(a_hi, a_lo, b_hi, b_lo)
    a_hi, a_lo = band(a_hi or 0, U32_MASK), band(a_lo or 0, U32_MASK)
    b_hi, b_lo = band(b_hi or 0, U32_MASK), band(b_lo or 0, U32_MASK)
    local diff_lo = a_lo - b_lo
    local borrow  = 0
    if diff_lo < 0 then
        diff_lo = diff_lo + TWO32
        borrow  = 1
    end
    local diff_hi = a_hi - b_hi - borrow
    return band(diff_hi, U32_MASK), band(diff_lo, U32_MASK)
end

local function rol64(hi, lo, bits)
    bits = band(bits or 0, 63)
    if bits == 0 then return band(hi, U32_MASK), band(lo, U32_MASK) end
    if bits >= 32 then
        bits = bits - 32
        hi, lo = lo, hi
        if bits == 0 then
            return band(hi, U32_MASK), band(lo, U32_MASK)
        end
    end
    local new_hi = band(bor(lshift(hi, bits), rshift(lo, 32 - bits)), U32_MASK)
    local new_lo = band(bor(lshift(lo, bits), rshift(hi, 32 - bits)), U32_MASK)
    return new_hi, new_lo
end

local function rshift64(hi, lo, bits)
    bits = band(bits or 0, 63)
    hi   = band(hi, U32_MASK)
    lo   = band(lo, U32_MASK)
    if bits == 0 then
        return hi, lo
    elseif bits < 32 then
        local new_lo = bor(rshift(lo, bits), lshift(hi, 32 - bits))
        local new_hi = rshift(hi, bits)
        return band(new_hi, U32_MASK), band(new_lo, U32_MASK)
    elseif bits == 32 then
        return 0, hi
    else
        return 0, rshift(hi, bits - 32)
    end
end

-- Specialized right shifts used in avalanche (fewer branches)
local function rshift64_33(hi, lo)
    -- Shift right 64 by 33: new_hi = 0, new_lo = hi >> 1
    return 0, rshift(band(hi, U32_MASK), 1)
end

local function rshift64_29(hi, lo)
    -- Shift right 64 by 29: new_hi = hi >> 29, new_lo = (lo >> 29) | (hi << 3)
    hi = band(hi, U32_MASK); lo = band(lo, U32_MASK)
    local new_hi = rshift(hi, 29)
    local new_lo = bor(rshift(lo, 29), lshift(hi, 3))
    return band(new_hi, U32_MASK), band(new_lo, U32_MASK)
end

local function rshift64_32(hi, lo)
    -- Shift right 64 by 32: new_hi = 0, new_lo = hi
    return 0, band(hi, U32_MASK)
end

-- =========================================================================
-- XXH64
-- =========================================================================

local function merge_accumulators(h_h, h_l, a_h, a_l)
    local t_h, t_l = mul64(a_h, a_l, P64_2_H, P64_2_L)
    t_h, t_l = rol64(t_h, t_l, 31)
    t_h, t_l = mul64(t_h, t_l, P64_1_H, P64_1_L)
    h_h = bxor(h_h, t_h); h_l = bxor(h_l, t_l)
    h_h, h_l = mul64(h_h, h_l, P64_1_H, P64_1_L)
    return add64(h_h, h_l, P64_4_H, P64_4_L)
end

local function XXH64_small(str, seed)
    -- Specialized fast path for len <= 16 (avoids extra branching/loops)
    local len = #str
    local h_hi, h_lo = 0, band(seed or 0, U32_MASK)
    -- h = seed + P5
    h_hi, h_lo = add64(h_hi, h_lo, P64_5_H, P64_5_L)
    -- h += len
    h_hi, h_lo = add64(h_hi, h_lo, 0, len)

    local index = 1
    if len >= 8 then
        local ll = read_u32_le(str, index)
        local lh = read_u32_le(str, index + 4)
        -- h ^= (lane * P2).rotl(31) * P1
        local t_h, t_l = mul64(lh, ll, P64_2_H, P64_2_L)
        t_h, t_l = rol64(t_h, t_l, 31)
        t_h, t_l = mul64(t_h, t_l, P64_1_H, P64_1_L)
        h_hi = bxor(h_hi, t_h); h_lo = bxor(h_lo, t_l)
        h_hi, h_lo = rol64(h_hi, h_lo, 27)
        h_hi, h_lo = mul64(h_hi, h_lo, P64_1_H, P64_1_L)
        h_hi, h_lo = add64(h_hi, h_lo, P64_4_H, P64_4_L)
        index = index + 8
        len = len - 8
    end

    if len >= 4 then
        local v32 = read_u32_le(str, index)
        local m_h, m_l = mul_u32_const64(v32, P64_1_H, P64_1_L)
        h_hi = bxor(h_hi, m_h); h_lo = bxor(h_lo, m_l)
        h_hi, h_lo = rol64(h_hi, h_lo, 23)
        h_hi, h_lo = mul64(h_hi, h_lo, P64_2_H, P64_2_L)
        h_hi, h_lo = add64(h_hi, h_lo, P64_3_H, P64_3_L)
        index = index + 4
        len = len - 4
    end

    while len > 0 do
        local b = sbyte(str, index)
        local m_h, m_l = mul_u32_const64(b, P64_5_H, P64_5_L)
        h_hi = bxor(h_hi, m_h); h_lo = bxor(h_lo, m_l)
        h_hi, h_lo = rol64(h_hi, h_lo, 11)
        h_hi, h_lo = mul64(h_hi, h_lo, P64_1_H, P64_1_L)
        index = index + 1
        len = len - 1
    end

    -- Avalanche with specialized shifts
    local s1_h, s1_l = rshift64_33(h_hi, h_lo)
    h_hi = bxor(h_hi, s1_h); h_lo = bxor(h_lo, s1_l)
    h_hi, h_lo = mul64(h_hi, h_lo, P64_2_H, P64_2_L)

    local s2_h, s2_l = rshift64_29(h_hi, h_lo)
    h_hi = bxor(h_hi, s2_h); h_lo = bxor(h_lo, s2_l)
    h_hi, h_lo = mul64(h_hi, h_lo, P64_3_H, P64_3_L)

    local s3_h, s3_l = rshift64_32(h_hi, h_lo)
    h_hi = bxor(h_hi, s3_h); h_lo = bxor(h_lo, s3_l)

    return string.format("%08X%08X", h_hi, h_lo)
end

local function XXH64(str, seed)
    local len = #str
    if len <= 16 then
        return XXH64_small(str, seed)
    end

    local seed_hi, seed_lo = 0, band(seed or 0, U32_MASK)
    local h_hi, h_lo
    local index = 1

    if len >= 32 then
        local acc1_h, acc1_l = add64(seed_hi, seed_lo, P64_1_H, P64_1_L)
        acc1_h, acc1_l = add64(acc1_h, acc1_l, P64_2_H, P64_2_L)
        local acc2_h, acc2_l = add64(seed_hi, seed_lo, P64_2_H, P64_2_L)
        local acc3_h, acc3_l = seed_hi, seed_lo
        local acc4_h, acc4_l = sub64(seed_hi, seed_lo, P64_1_H, P64_1_L)

        local limit = len - 31
        while index <= limit do
            -- Inline read_u64_le
            local l1l = read_u32_le(str, index)
            local l1h = read_u32_le(str, index + 4)
            local l2l = read_u32_le(str, index + 8)
            local l2h = read_u32_le(str, index + 12)
            local l3l = read_u32_le(str, index + 16)
            local l3h = read_u32_le(str, index + 20)
            local l4l = read_u32_le(str, index + 24)
            local l4h = read_u32_le(str, index + 28)

            do
                local t_h, t_l = mul64(l1h, l1l, P64_2_H, P64_2_L)
                acc1_h, acc1_l = add64(acc1_h, acc1_l, t_h, t_l)
                acc1_h, acc1_l = rol64(acc1_h, acc1_l, 31)
                acc1_h, acc1_l = mul64(acc1_h, acc1_l, P64_1_H, P64_1_L)
            end
            do
                local t_h, t_l = mul64(l2h, l2l, P64_2_H, P64_2_L)
                acc2_h, acc2_l = add64(acc2_h, acc2_l, t_h, t_l)
                acc2_h, acc2_l = rol64(acc2_h, acc2_l, 31)
                acc2_h, acc2_l = mul64(acc2_h, acc2_l, P64_1_H, P64_1_L)
            end
            do
                local t_h, t_l = mul64(l3h, l3l, P64_2_H, P64_2_L)
                acc3_h, acc3_l = add64(acc3_h, acc3_l, t_h, t_l)
                acc3_h, acc3_l = rol64(acc3_h, acc3_l, 31)
                acc3_h, acc3_l = mul64(acc3_h, acc3_l, P64_1_H, P64_1_L)
            end
            do
                local t_h, t_l = mul64(l4h, l4l, P64_2_H, P64_2_L)
                acc4_h, acc4_l = add64(acc4_h, acc4_l, t_h, t_l)
                acc4_h, acc4_l = rol64(acc4_h, acc4_l, 31)
                acc4_h, acc4_l = mul64(acc4_h, acc4_l, P64_1_H, P64_1_L)
            end

            index = index + 32
        end

        local r1h, r1l = rol64(acc1_h, acc1_l, 1)
        local r2h, r2l = rol64(acc2_h, acc2_l, 7)
        local r3h, r3l = rol64(acc3_h, acc3_l, 12)
        local r4h, r4l = rol64(acc4_h, acc4_l, 18)

        h_hi, h_lo = add64(r1h, r1l, r2h, r2l)
        h_hi, h_lo = add64(h_hi, h_lo, r3h, r3l)
        h_hi, h_lo = add64(h_hi, h_lo, r4h, r4l)

        h_hi, h_lo = merge_accumulators(h_hi, h_lo, acc1_h, acc1_l)
        h_hi, h_lo = merge_accumulators(h_hi, h_lo, acc2_h, acc2_l)
        h_hi, h_lo = merge_accumulators(h_hi, h_lo, acc3_h, acc3_l)
        h_hi, h_lo = merge_accumulators(h_hi, h_lo, acc4_h, acc4_l)
    else
        h_hi, h_lo = add64(seed_hi, seed_lo, P64_5_H, P64_5_L)
    end

    -- h += len
    h_hi, h_lo = add64(h_hi, h_lo, 0, len)

    -- 8-byte lanes
    local limit8 = len - (index - 1) - 7
    while limit8 >= 0 do
        local ll = read_u32_le(str, index)
        local lh = read_u32_le(str, index + 4)
        local t_h, t_l = mul64(lh, ll, P64_2_H, P64_2_L)
        t_h, t_l = rol64(t_h, t_l, 31)
        t_h, t_l = mul64(t_h, t_l, P64_1_H, P64_1_L)
        h_hi = bxor(h_hi, t_h); h_lo = bxor(h_lo, t_l)
        h_hi, h_lo = rol64(h_hi, h_lo, 27)
        h_hi, h_lo = mul64(h_hi, h_lo, P64_1_H, P64_1_L)
        h_hi, h_lo = add64(h_hi, h_lo, P64_4_H, P64_4_L)
        index = index + 8
        limit8 = limit8 - 8
    end

    -- 4-byte tail: h ^= (read32 * P1); h = rotl(h, 23) * P2 + P3
    if index <= #str - 3 then
        local v32 = read_u32_le(str, index)
        local m_h, m_l = mul_u32_const64(v32, P64_1_H, P64_1_L)
        h_hi = bxor(h_hi, m_h); h_lo = bxor(h_lo, m_l)
        h_hi, h_lo = rol64(h_hi, h_lo, 23)
        h_hi, h_lo = mul64(h_hi, h_lo, P64_2_H, P64_2_L)
        h_hi, h_lo = add64(h_hi, h_lo, P64_3_H, P64_3_L)
        index = index + 4
    end

    -- 1-byte tails: for each b, h ^= (b * P5); h = rotl(h, 11) * P1
    while index <= #str do
        local b = sbyte(str, index)
        local m_h, m_l = mul_u32_const64(b, P64_5_H, P64_5_L)
        h_hi = bxor(h_hi, m_h); h_lo = bxor(h_lo, m_l)
        h_hi, h_lo = rol64(h_hi, h_lo, 11)
        h_hi, h_lo = mul64(h_hi, h_lo, P64_1_H, P64_1_L)
        index = index + 1
    end

    -- Final mix (avalanche) with specialized shifts
    local s1_h, s1_l = rshift64_33(h_hi, h_lo)
    h_hi = bxor(h_hi, s1_h); h_lo = bxor(h_lo, s1_l)
    h_hi, h_lo = mul64(h_hi, h_lo, P64_2_H, P64_2_L)

    local s2_h, s2_l = rshift64_29(h_hi, h_lo)
    h_hi = bxor(h_hi, s2_h); h_lo = bxor(h_lo, s2_l)
    h_hi, h_lo = mul64(h_hi, h_lo, P64_3_H, P64_3_L)

    local s3_h, s3_l = rshift64_32(h_hi, h_lo)
    h_hi = bxor(h_hi, s3_h); h_lo = bxor(h_lo, s3_l)

    return string.format("%08X%08X", h_hi, h_lo)
end

-- =========================================================================
-- DEBUG/TEST UTILITIES
-- =========================================================================

local function to_hex_bytes(str)
    local t = {}
    for i = 1, #str do
        t[#t + 1] = string.format("%02X", sbyte(str, i))
    end
    return table.concat(t, " ")
end

local function parse_hex_bytes(hex)
    local out = {}
    for byte in string.gmatch(hex, "%x%x") do
        out[#out + 1] = string.char(tonumber(byte, 16))
    end
    return table.concat(out)
end

local function printable_echo(str)
    return (str
        :gsub("\\", "\\\\")
        :gsub("\0", "\\0")
        :gsub("([\001-\009\011\012\014-\031\127])", function(c)
            return string.format("\\x%02X", sbyte(c))
        end))
end

-- =========================================================================
-- SELF-TESTING FUNCTION
-- =========================================================================

local function RunSelfTests(opts)
    opts = opts or {}
    local hexAlways = not not opts.hexDumpAlways
    local which     = opts.which or "all"

    -- Expectations aligned with Python xxhash and exact bytes:
    -- ""            -> XXH32 02CC5D05, XXH64 EF46DB3751D8E999
    -- 00            -> XXH32 CF65B03E, XXH64 E934A84ADB052768
    -- 5C 30 ("\\0") -> XXH32 6257410B, XXH64 5263B0A7F5A1FD64
    -- 61 62 63      -> XXH32 32D153FF, XXH64 44BC2CF5AD770999
    -- empty seed 0x9E3779B1 -> XXH32 36B78AE7, XXH64 AC75FDA2929B17EF
    -- 5C30 61 5C30 62 5C30 63 5C30 -> XXH32 737C5242, XXH64 43AB68FB8CD6407D
    -- "Skulltrail" seed 2025 -> XXH32 4A31242C, XXH64 A56F88A6999B63F5

    local tests = {
        lua = {
            { str = "",               seed = 0,          exp32 = 0x02CC5D05, exp64 = "EF46DB3751D8E999", label = "empty" },
            { str = "\0",             seed = 0,          exp32 = 0xCF65B03E, exp64 = "E934A84ADB052768", label = "single NUL 00" },
            { str = "\0a\0",          seed = 0,          exp32 = false,      exp64 = false,            label = "00 61 00 (info)" },
            { str = "\0a\0b\0c\0",    seed = 0,          exp32 = false,      exp64 = false,            label = "00 61 00 62 00 63 00 (info)" },
            { str = "\0t\0e\0s\0t\0", seed = 0,          exp32 = false,      exp64 = false,            label = "00 74 00 65 00 73 00 74 00 (info)" },
            { str = "",               seed = 0x9E3779B1, exp32 = 0x36B78AE7, exp64 = "AC75FDA2929B17EF", label = "empty, seed" },
            { str = "Skulltrail",     seed = 2025,       exp32 = 0x4A31242C, exp64 = "A56F88A6999B63F5", label = "string+seed" },
        },
        ascii = {
            { str = "\\0",            seed = 0,          exp32 = 0x6257410B, exp64 = "5263B0A7F5A1FD64", label = "ASCII \\0 (5C 30)" },
            { str = "\\0a\\0b\\0c\\0",seed = 0,          exp32 = 0x737C5242, exp64 = "43AB68FB8CD6407D", label = "ASCII \\0a\\0b\\0c\\0" },
        },
        hex = {
            { hex = "61 62 63",                         seed = 0, exp32 = 0x32D153FF, exp64 = "44BC2CF5AD770999", label = "HEX abc" },
            { hex = "00",                               seed = 0, exp32 = 0xCF65B03E, exp64 = "E934A84ADB052768", label = "HEX 00" },
            { hex = "5C 30",                            seed = 0, exp32 = 0x6257410B, exp64 = "5263B0A7F5A1FD64", label = "HEX 5C 30 (\"\\0\")" },
            { hex = "5C 30 61 5C 30 62 5C 30 63 5C 30", seed = 0, exp32 = 0x737C5242, exp64 = "43AB68FB8CD6407D", label = "HEX \\0a\\0b\\0c\\0" },
        },
    }

    local selection = {}
    if which == "all" or which == "lua"  then for _, t in ipairs(tests.lua)  do table.insert(selection, { kind = "lua",  data = t }) end end
    if which == "all" or which == "ascii" then for _, t in ipairs(tests.ascii) do table.insert(selection, { kind = "ascii", data = t }) end end
    if which == "all" or which == "hex"  then for _, t in ipairs(tests.hex)  do table.insert(selection, { kind = "hex",  data = t }) end end

    local success = true
    print("--- Running XXH_Lua_Lib Self-Tests ---")

    for _, item in ipairs(selection) do
        local kind = item.kind
        local t    = item.data

        local src, shown
        if kind == "lua" then
            src   = t.str
            shown = printable_echo(t.str)
        elseif kind == "ascii" then
            src   = t.str
            shown = t.str
        elseif kind == "hex" then
            src   = parse_hex_bytes(t.hex)
            shown = t.hex
        end

        local got32 = XXH32(src, t.seed)
        local got64 = XXH64(src, t.seed)

        if t.exp32 ~= false then
            local ok32  = (got32 == t.exp32)
            local status32 = ok32 and "|cff00ff00PASS|r" or "|cffff0000FAIL|r"
            print(string.format("XXH Test: %s - XXH32 - Input: '%s', Seed: 0x%x", status32, shown, t.seed))
            if not ok32 then
                print(string.format("  - Expected: 0x%08X", t.exp32))
                print(string.format("  - Got:      0x%08X", got32))
                success = false
            end
            if hexAlways or not ok32 then
                print(string.format("  - Hex Dump: %s\t\t%s", to_hex_bytes(src), printable_echo(src)))
            end
        else
            print(string.format("XXH Test: INFO - XXH32 - Input: '%s', Seed: 0x%x -> 0x%08X", shown, t.seed, got32))
            if hexAlways then print(string.format("  - Hex Dump: %s\t\t%s", to_hex_bytes(src), printable_echo(src))) end
        end

        if t.exp64 ~= false then
            local ok64  = (string.upper(got64) == string.upper(t.exp64))
            local status64 = ok64 and "|cff00ff00PASS|r" or "|cffff0000FAIL|r"
            print(string.format("XXH Test: %s - XXH64 - Input: '%s', Seed: 0x%x", status64, shown, t.seed))
            if not ok64 then
                print(string.format("  - Expected: %s", t.exp64))
                print(string.format("  - Got:      %s", got64))
                success = false
            end
            if hexAlways or not ok64 then
                print(string.format("  - Hex Dump: %s\t\t%s", to_hex_bytes(src), printable_echo(src)))
            end
        else
            print(string.format("XXH Test: INFO - XXH64 - Input: '%s', Seed: 0x%x -> %s", shown, t.seed, got64))
            if hexAlways then print(string.format("  - Hex Dump: %s\t\t%s", to_hex_bytes(src), printable_echo(src))) end
        end
    end

    if success then
        print("|cff00ff00All tests passed successfully!|r")
    else
        print("|cffff0000One or more tests failed!|r")
    end

    print("--------------------------------------")
    return success
end

-- =========================================================================
-- MODULE EXPORT
-- =========================================================================

local XXH_Lua_Lib = {
    XXH32        = XXH32,
    XXH64        = XXH64,
    RunSelfTests = RunSelfTests,
}

_G.XXH_Lua_Lib = XXH_Lua_Lib
return XXH_Lua_Lib
