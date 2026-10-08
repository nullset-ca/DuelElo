local json = require("json")
local Wow = require("wow")

local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Crypto.lua"))("DuelElo", ns)
local Crypto = ns.Crypto
local vectors = json.read("spec/vectors/keys.json")

for _, c in ipairs(vectors.fingerprints) do
    test("fingerprint vector: " .. c.name, function()
        eq(Crypto.Fingerprint(c.secret), c.fp)
    end)
end

test("secret derivation vector: SHA256 of the entropy string", function()
    eq(Crypto.SHA256(vectors.entropy.input), vectors.entropy.secret)
end)

test("Fingerprint and ValidSecret reject malformed secrets", function()
    eq(Crypto.Fingerprint("abc"), nil)
    eq(Crypto.Fingerprint(("zz"):rep(32)), nil)
    eq(Crypto.Fingerprint(("ab"):rep(31)), nil)
    eq(Crypto.ValidSecret(("ab"):rep(32)), true)
    eq(Crypto.ValidSecret(("AB"):rep(32)), false, "lowercase only")
    eq(Crypto.ValidSecret(nil), false)
end)

test("first login creates a key; its fingerprint goes into the registry", function()
    local env = Wow.new()
    env.login()
    local key = DuelEloCharDB.key
    ok(Crypto.ValidSecret(key.secret))
    ok(type(key.created) == "number")
    eq(env.ns.myFp, Crypto.Fingerprint(key.secret))
    eq(DuelEloDB.characters["Ashvale-Sargeras"].fp, env.ns.myFp)
end)

test("the key is stable across reloads (saved key fixture)", function()
    local saved = { schema = 2, key = { secret = ("5f3a"):rep(16), created = 1791000000 } }
    local env = Wow.new({ charDB = saved })
    env.login()
    eq(DuelEloCharDB.key, { secret = ("5f3a"):rep(16), created = 1791000000 })
    local sample
    for _, c in ipairs(vectors.fingerprints) do if c.name == "sample secret" then sample = c end end
    eq(sample.secret, ("5f3a"):rep(16))
    eq(env.ns.myFp, sample.fp, "fp matches the vector")
    local again = Wow.new({ charDB = DuelEloCharDB, db = DuelEloDB })
    again.login()
    eq(DuelEloCharDB.key.secret, ("5f3a"):rep(16), "not regenerated")
end)

test("two characters get different keys", function()
    local a = Wow.new()
    a.login()
    local first = DuelEloCharDB.key.secret
    local b = Wow.new({ units = { player = { name = "Other", realm = "Sargeras", class = "MAGE" } } })
    b.login()
    ok(DuelEloCharDB.key.secret ~= first)
end)

test("a malformed saved key is replaced; a valid one never is", function()
    local env = Wow.new({ charDB = { schema = 2, key = { secret = "not hex" } } })
    env.login()
    ok(Crypto.ValidSecret(DuelEloCharDB.key.secret))
end)

test("entropy never errors when APIs are missing", function()
    local env = Wow.new()
    env.login()
    debugprofilestop, GetServerTime, UnitGUID = nil, nil, nil
    ok(#env.ns.Keys.Entropy() > 0)
end)
