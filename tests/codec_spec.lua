local json = require("json")

local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Codec.lua"))("DuelElo", ns)
local C = ns.Codec
local V = json.read("spec/vectors/upload.json")

local function hexToBytes(h)
    return (h:gsub("%x%x", function(p) return string.char(tonumber(p, 16)) end))
end

for _, c in ipairs(V.json) do
    test("json vector: " .. c.name, function() eq(C.JSON(c.value), c.json) end)
end

for _, c in ipairs(V.base64) do
    test("base64 vector: " .. c.name, function()
        eq(C.Base64Encode(hexToBytes(c.hex)), c.base64)
        eq(C.Base64Decode(c.base64), hexToBytes(c.hex))
    end)
end

for _, c in ipairs(V.upload) do
    test("upload vector: " .. c.name, function()
        eq(C.JSON(c.payload), c.json)
        eq(C.UploadCode(c.payload, nil), c.code)
        local flags, bytes = C.ParseUploadCode(c.code)
        eq(flags, "N")
        eq(bytes, c.json)
    end)
end

test("upload code with a compressor is flagged Z", function()
    local payload = V.upload[1].payload
    local fake = function(s) return s:reverse() end
    local code = C.UploadCode(payload, fake)
    eq(code:sub(1, 11), "DUELELO1:Z:")
    local flags, bytes = C.ParseUploadCode(code)
    eq(flags, "Z")
    eq(bytes:reverse(), C.JSON(payload))
end)

test("a compressor that fails falls back to N", function()
    eq(C.UploadCode({ v = 1 }, function() return nil end), "DUELELO1:N:" .. C.Base64Encode('{"v":1}'))
end)

test("JSON is deterministic regardless of insertion order", function()
    local a, b = {}, {}
    for _, k in ipairs({ "x", "b", "a", "y" }) do a[k] = k end
    for _, k in ipairs({ "y", "a", "b", "x" }) do b[k] = k end
    eq(C.JSON(a), C.JSON(b))
    eq(C.JSON(a), '{"a":"a","b":"b","x":"x","y":"y"}')
end)

test("JSON: DEL is not escaped, controls are", function()
    eq(C.JSON("a\127b\31"), '"a\127b\\u001f"')
end)

test("JSON refuses values it can't represent", function()
    for _, bad in ipairs({ 0 / 0, math.huge, -math.huge, print, { [1] = 1, [3] = 3 }, { [true] = 1 } }) do
        ok(not pcall(C.JSON, bad), tostring(bad))
    end
    local deep = {}
    local cur = deep
    for _ = 1, 30 do cur.x = {} cur = cur.x end
    ok(not pcall(C.JSON, deep), "too deep")
end)

test("base64 decoder rejects malformed input", function()
    for _, bad in ipairs({ "abc", "ab=c", "a===", "Zm9v!", "Zg==Zg==", nil }) do
        eq(C.Base64Decode(bad), nil, tostring(bad))
    end
end)

test("ParseUploadCode rejects other formats", function()
    eq(C.ParseUploadCode("DUELELO2:N:Zg=="), nil)
    eq(C.ParseUploadCode("DUELELO1:X:Zg=="), nil)
    eq(C.ParseUploadCode("DUELELO1:N:@@@@"), nil)
    eq(C.ParseUploadCode(nil), nil)
end)
