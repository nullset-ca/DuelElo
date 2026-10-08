-- Keys.lua: each character's signing key (SPEC §2.1). Created once, on the
-- first login with v1, and never replaced automatically: the server ties a
-- character's matches to it. Only the fingerprint ever leaves the client in
-- game; the secret goes into upload codes only.
local _, ns = ...
local Crypto = ns.Crypto

local Keys = {}
ns.Keys = Keys

-- tostring() of a call, or "" if it errors or returns a secret value.
local function piece(fn, ...)
    if type(fn) ~= "function" then return "" end
    local ok, v = pcall(fn, ...)
    if not ok or ns.IsSecret(v) then return "" end
    return tostring(v)
end

-- Everything hard to guess the client can tell us, joined (SPEC §2.1).
function Keys.Entropy()
    local parts = { piece(debugprofilestop), piece(GetTime), piece(GetServerTime), piece(time),
        piece(UnitGUID, "player") }
    for _ = 1, 16 do parts[#parts + 1] = piece(math.random, 0, 255) end
    parts[#parts + 1] = piece(collectgarbage, "count")
    return table.concat(parts, "|")
end

-- Make sure the character has a key; returns its fingerprint. A missing or
-- malformed key (hand-edited SavedVariables) is replaced, nothing else is.
function Keys.Ensure(char)
    local key = char.key
    if type(key) ~= "table" or not Crypto.ValidSecret(key.secret) then
        if key ~= nil then ns.DPrint("Signing key was unreadable; made a new one") end
        key = { secret = Crypto.SHA256(Keys.Entropy()), created = time() }
        char.key = key
    end
    return Crypto.Fingerprint(key.secret)
end
