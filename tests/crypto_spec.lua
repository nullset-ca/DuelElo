local json = require("json")

local function load(bitlib)
    local saved = bit
    bit = bitlib
    local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
    assert(loadfile("DuelElo/Crypto.lua"))("DuelElo", ns)
    bit = saved
    return ns.Crypto
end

-- Some clients' bit libraries return unsigned results where LuaJIT's are
-- signed; run every vector against both flavours.
local unsigned = {}
for k, fn in pairs(bit) do
    unsigned[k] = function(...) local r = fn(...) return type(r) == "number" and r % 4294967296 or r end
end

local FLAVOURS = { { "LuaJIT bit", load(bit) }, { "unsigned bit", load(unsigned) } }
local SKIP_SLOW = os.getenv("DUELELO_FAST") == "1"

local sha = json.read("spec/vectors/sha256.json")
local hmac = json.read("spec/vectors/hmac.json")

for _, fl in ipairs(FLAVOURS) do
    local name, C = fl[1], fl[2]
    for _, c in ipairs(sha.cases) do
        if not (c.slow and (SKIP_SLOW or name ~= "LuaJIT bit")) then
            test(("sha256 [%s]: %s"):format(name, c.name), function()
                local input = c.inputHex and C.HexToBytes(c.inputHex) or c.input
                eq(C.SHA256(input:rep(c["repeat"] or 1)), c.expected)
            end)
        end
    end
    for _, c in ipairs(hmac.cases) do
        test(("hmac [%s]: %s"):format(name, c.name), function()
            local mac = C.HMAC(C.HexToBytes(c.keyHex), C.HexToBytes(c.dataHex))
            eq(c.truncateHex and mac:sub(1, c.truncateHex) or mac, c.expected)
        end)
    end
end

local C = FLAVOURS[1][2]

test("hex <-> bytes round trip, lowercase out, invalid hex rejected", function()
    local bytes = C.HexToBytes("00ff10AB")
    eq(#bytes, 4)
    eq(C.BytesToHex(bytes), "00ff10ab")
    eq(C.HexToBytes("abc"), nil, "odd length")
    eq(C.HexToBytes("zz"), nil)
    eq(C.HexToBytes(nil), nil)
    eq(C.HexToBytes(""), "")
end)

test("SHA256Raw is the 32 bytes behind the hex digest", function()
    local raw = C.SHA256Raw("abc")
    eq(#raw, 32)
    eq(C.BytesToHex(raw), C.SHA256("abc"))
end)

test("vector files have the required cases", function()
    ok(#sha.cases >= 4)
    eq(#hmac.cases >= 7, true)
end)
