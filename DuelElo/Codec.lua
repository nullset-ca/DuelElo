-- Codec.lua: deterministic JSON, base64 and the upload code (SPEC §2.6; no WoW
-- API — the compressor is passed in). The site decodes the same format;
-- both are checked against spec/vectors/upload.json.
local _, ns = ...

local Codec = {}
ns.Codec = Codec

Codec.PREFIX = "DUELELO1"

---------------------------------------------------------------------------
-- JSON (encode only; the addon never reads JSON)
---------------------------------------------------------------------------

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n",
    ["\r"] = "\\r", ["\t"] = "\\t" }

local function escapeChar(c)
    return ESCAPES[c] or ("\\u%04x"):format(c:byte())
end

local function encodeString(s)
    -- control characters 0-31 only (not DEL), like every mainstream encoder
    return '"' .. s:gsub('[%z\1-\31"\\]', escapeChar) .. '"'
end

local function encodeNumber(n)
    if n ~= n or n == math.huge or n == -math.huge then error("JSON: number is not finite") end
    if n == math.floor(n) and math.abs(n) < 2 ^ 53 then return ("%d"):format(n) end
    return ("%.17g"):format(n)
end

-- A table is an array when its keys are exactly 1..n. Empty tables encode
-- as [] (every collection in the upload payload is an array).
local function arrayLength(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do
        if t[i] == nil then return nil end
    end
    return n
end

local encode

local function encodeTable(t, depth)
    if depth > 20 then error("JSON: nested too deeply") end
    local n = arrayLength(t)
    local out = {}
    if n then
        for i = 1, n do out[i] = encode(t[i], depth + 1) end
        return "[" .. table.concat(out, ",") .. "]"
    end
    local keys = {}
    for k in pairs(t) do
        if type(k) ~= "string" then error("JSON: object keys must be strings") end
        keys[#keys + 1] = k
    end
    table.sort(keys)  -- byte order: the same string on every client and on the server
    for i, k in ipairs(keys) do out[i] = encodeString(k) .. ":" .. encode(t[k], depth + 1) end
    return "{" .. table.concat(out, ",") .. "}"
end

function encode(v, depth)
    local kind = type(v)
    if kind == "string" then return encodeString(v) end
    if kind == "number" then return encodeNumber(v) end
    if kind == "boolean" then return v and "true" or "false" end
    if kind == "nil" then return "null" end
    if kind == "table" then return encodeTable(v, depth) end
    error("JSON: can't encode a " .. kind)
end

-- Compact JSON with sorted keys. Errors on values JSON can't hold.
function Codec.JSON(v)
    return encode(v, 0)
end

---------------------------------------------------------------------------
-- Base64 (standard alphabet, with padding)
---------------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC, DEC = {}, {}
for i = 1, 64 do
    local c = ALPHABET:sub(i, i)
    ENC[i - 1], DEC[c] = c, i - 1
end

function Codec.Base64Encode(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = ENC[math.floor(n / 262144)] .. ENC[math.floor(n / 4096) % 64]
            .. (b and ENC[math.floor(n / 64) % 64] or "=") .. (c and ENC[n % 64] or "=")
    end
    return table.concat(out)
end

-- Bytes for a base64 string, or nil if it isn't valid padded base64.
function Codec.Base64Decode(s)
    if type(s) ~= "string" or #s % 4 ~= 0 or s:find("[^%w%+/=]") or s:find("=[^=]") or s:find("===") then
        return nil
    end
    local out = {}
    for i = 1, #s, 4 do
        local q = s:sub(i, i + 3)
        local pad = select(2, q:gsub("=", ""))
        if pad > 0 and i + 3 < #s then return nil end  -- padding only at the very end
        local n = 0
        for j = 1, 4 do n = n * 64 + (DEC[q:sub(j, j)] or 0) end
        local bytes = string.char(math.floor(n / 65536), math.floor(n / 256) % 256, n % 256)
        out[#out + 1] = bytes:sub(1, 3 - pad)
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Upload code: DUELELO1:<Z|N>:<base64>
---------------------------------------------------------------------------

-- payload: the §2.6 table. compress(str) -> compressed bytes, or nil when the
-- client has no compressor (C_EncodingUtil missing): the code is then "N".
function Codec.UploadCode(payload, compress)
    local json = Codec.JSON(payload)
    local packed = compress and compress(json)
    if packed then
        return ("%s:Z:%s"):format(Codec.PREFIX, Codec.Base64Encode(packed))
    end
    return ("%s:N:%s"):format(Codec.PREFIX, Codec.Base64Encode(json))
end

-- flags, bytes of an upload code (bytes still compressed for "Z"); nil if malformed.
function Codec.ParseUploadCode(code)
    if type(code) ~= "string" then return nil end
    local flags, body = code:match("^" .. Codec.PREFIX .. ":([ZN]):(.*)$")
    local bytes = flags and Codec.Base64Decode(body)
    if not bytes then return nil end
    return flags, bytes
end
