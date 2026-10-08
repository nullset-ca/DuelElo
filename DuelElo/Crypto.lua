-- Crypto.lua: SHA-256, HMAC-SHA256 and hex <-> bytes (no WoW API besides `bit`).
-- Used to sign match statements with each character's key (SPEC §2.1/§2.2).
-- Checked against NIST and RFC 4231 vectors (spec/vectors/sha256.json, hmac.json).
--
-- `bit` differs between clients: LuaJIT returns signed 32-bit results, other
-- bitlibs unsigned ones. Every result is normalised with u32() before it is
-- added or printed, and rotations are built from shifts (no bit.ror needed).
--
-- Speed for a 1 KB message (Apple M-series): 0.03 ms in LuaJIT 2.1, 0.4 ms
-- with the JIT off (closest to WoW's interpreter). A statement is ~100 bytes.
local _, ns = ...
local bit = bit

local Crypto = {}
ns.Crypto = Crypto

local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local rshift, lshift = bit.rshift, bit.lshift
local char, byte, format = string.char, string.byte, string.format
local MOD = 4294967296

local function u32(x) return x % MOD end

local function ror(x, n)
    return u32(bor(rshift(x, n), lshift(x, 32 - n)))
end

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local H0 = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }

-- Message padded to a multiple of 64 bytes, with the bit length at the end.
local function pad(msg)
    local len = #msg
    local zeros = (55 - len) % 64
    local bits = len * 8
    local tail = {}
    for i = 7, 0, -1 do
        tail[#tail + 1] = char(math.floor(bits / 2 ^ (8 * i)) % 256)
    end
    return msg .. "\128" .. ("\0"):rep(zeros) .. table.concat(tail)
end

local w = {}  -- message schedule, reused between blocks

local function block(h, msg, offset)
    for i = 1, 16 do
        local a, b, c, d = byte(msg, offset + (i - 1) * 4 + 1, offset + i * 4)
        w[i] = ((a * 256 + b) * 256 + c) * 256 + d
    end
    for i = 17, 64 do
        local x, y = w[i - 15], w[i - 2]
        local s0 = bxor(ror(x, 7), ror(x, 18), rshift(x, 3))
        local s1 = bxor(ror(y, 17), ror(y, 19), rshift(y, 10))
        w[i] = u32(w[i - 16] + u32(s0) + w[i - 7] + u32(s1))
    end
    local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
    for i = 1, 64 do
        local S1 = u32(bxor(ror(e, 6), ror(e, 11), ror(e, 25)))
        local ch = u32(bxor(band(e, f), band(bnot(e), g)))
        local t1 = hh + S1 + ch + K[i] + w[i]
        local S0 = u32(bxor(ror(a, 2), ror(a, 13), ror(a, 22)))
        local maj = u32(bxor(band(a, b), band(a, c), band(b, c)))
        hh, g, f, e = g, f, e, u32(d + t1)
        d, c, b, a = c, b, a, u32(t1 + S0 + maj)
    end
    h[1], h[2], h[3], h[4] = u32(h[1] + a), u32(h[2] + b), u32(h[3] + c), u32(h[4] + d)
    h[5], h[6], h[7], h[8] = u32(h[5] + e), u32(h[6] + f), u32(h[7] + g), u32(h[8] + hh)
end

-- SHA-256 of a byte string, as 32 raw bytes.
function Crypto.SHA256Raw(msg)
    local h = { H0[1], H0[2], H0[3], H0[4], H0[5], H0[6], H0[7], H0[8] }
    local padded = pad(msg)
    for offset = 0, #padded - 1, 64 do block(h, padded, offset) end
    local out = {}
    for i = 1, 8 do
        local v = h[i]
        out[i] = char(math.floor(v / 16777216) % 256, math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256)
    end
    return table.concat(out)
end

function Crypto.BytesToHex(bytes)
    return (bytes:gsub(".", function(c) return format("%02x", byte(c)) end))
end

-- Raw bytes for a hex string; nil if it isn't valid hex.
function Crypto.HexToBytes(hex)
    if type(hex) ~= "string" or #hex % 2 ~= 0 or hex:find("[^%x]") then return nil end
    return (hex:gsub("%x%x", function(pair) return char(tonumber(pair, 16)) end))
end

-- SHA-256 of a byte string, as 64 lowercase hex characters.
function Crypto.SHA256(msg)
    return Crypto.BytesToHex(Crypto.SHA256Raw(msg))
end

local IPAD, OPAD = {}, {}
for i = 0, 255 do
    IPAD[char(i)] = char(bxor(i, 0x36) % 256)
    OPAD[char(i)] = char(bxor(i, 0x5c) % 256)
end

-- HMAC-SHA256 (RFC 2104) with a raw byte key; lowercase hex.
function Crypto.HMAC(key, msg)
    if #key > 64 then key = Crypto.SHA256Raw(key) end
    key = key .. ("\0"):rep(64 - #key)
    local inner = Crypto.SHA256Raw(key:gsub(".", IPAD) .. msg)
    return Crypto.SHA256(key:gsub(".", OPAD) .. inner)
end

-- Key fingerprint (SPEC §2.1): first 32 hex chars of SHA256(bytes(secret)).
function Crypto.Fingerprint(secretHex)
    local bytes = Crypto.HexToBytes(secretHex)
    if not bytes or #bytes ~= 32 then return nil end
    return Crypto.SHA256(bytes):sub(1, 32)
end

-- A usable secret: 64 lowercase hex characters.
function Crypto.ValidSecret(secret)
    return type(secret) == "string" and #secret == 64 and not secret:find("[^0-9a-f]")
end
