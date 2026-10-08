local json = require("json")
local Wow = require("wow")
local Stub = require("ui_stub")

local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
for _, f in ipairs({ "Crypto", "Codec", "Export" }) do assert(loadfile("DuelElo/" .. f .. ".lua"))("DuelElo", ns) end
local Export, Codec, Crypto = ns.Export, ns.Codec, ns.Crypto

local SECRET = ("a1"):rep(32)
local T = 1791500000

-- One of each kind of history entry.
local function fixture()
    return {
        key = { secret = SECRET, created = T - 1e6 },
        duels = {
            { t = T - 500, opp = "Old-Realm", result = "W", how = "KO", ranked = true, delta = 20, legacy = true },
            { t = T - 400, opp = "Thrall-Area52", class = "SHAMAN", result = "L", how = "KO", ranked = true,
              match = "1:2", statement = "DE2|1:2|1|Thrall-Area52|Ashvale-Sargeras|30|C|KO|1500|1200|0|0|1|2",
              sigC = ("cd"):rep(32), sigD = ("ef"):rep(32), fpC = ("0f"):rep(16), fpD = ("1e"):rep(16),
              zone = 84, secs = 41, spec = 253, ilvl = 612, oppSpec = 262, oppIlvl = 605, delta = -12 },
            { t = T - 300, opp = "Jaina-Area52", class = "MAGE", result = "W", how = "FLED", match = "3:4", zone = 85 },
            { t = T - 200, opp = "Stranger-Illidan", result = "W", how = "KO", secs = 20 },
        },
        reports = { { t = T - 350, target = "Thrall-Area52", matchId = "1:2", reason = "THROWN", note = "afk" } },
    }
end

local CTX = { name = "Ashvale", realm = "Sargeras", class = "HUNTER", level = 30, region = 1, flavor = "forever",
    version = "0.6.0", now = T }

test("signed ranked duels become matches; everything else is casual", function()
    local p = Export.Build(fixture(), CTX)
    eq(#p.matches, 1)
    eq(p.matches[1], {
        statement = fixture().duels[2].statement, sigC = ("cd"):rep(32), sigD = ("ef"):rep(32), fpC = ("0f"):rep(16),
        fpD = ("1e"):rep(16), zone = 84, secs = 41, self = "Ashvale-Sargeras", spec = 253, ilvl = 612, oppSpec = 262,
        oppIlvl = 605,
    })
    eq(#p.casual, 3, "test-era ranked, casual addon duel, duel vs a non-addon player")
    eq(p.casual[2], { t = T - 300, opp = "Jaina-Area52", result = "W", how = "FLED", class = "HUNTER",
        oppClass = "MAGE", zone = 85, level = 30 })
    eq(p.reports, { { matchId = "1:2", target = "Thrall-Area52", reason = "THROWN", note = "afk", t = T - 350 } })
end)

test("the payload names the client, character and key", function()
    local p = Export.Build(fixture(), CTX)
    eq({ p.v, p.addon, p.flavor, p.region, p.exportedAt, p.since }, { 1, "0.6.0", "forever", 1, T, nil })
    eq(p.characters, { { name = "Ashvale", realm = "Sargeras", class = "HUNTER", level = 30,
        fp = Crypto.Fingerprint(SECRET), secret = SECRET } })
    eq(p.witnesses, {})
end)

test("only records newer than the last export, unless it's a full export", function()
    local char = fixture()
    char.lastExport = T - 350
    local p = Export.Build(char, CTX)
    eq(p.since, T - 350)
    eq(#p.matches, 0)
    eq(#p.casual, 2)
    eq(#p.reports, 0)
    local all = Export.Build(char, { name = "Ashvale", realm = "Sargeras", now = T, full = true, version = "x",
        region = 1, flavor = "forever" })
    eq(all.since, nil)
    eq(#all.matches + #all.casual + #all.reports, 5)
end)

test("Pending counts what a new code would contain", function()
    local char = fixture()
    eq(Export.Pending(char, nil), { matches = 1, casual = 3, reports = 1, witnesses = 0 })
    eq(Export.Pending(char, T - 350), { matches = 0, casual = 2, reports = 0, witnesses = 0 })
end)

test("the code is a valid DUELELO1 code with the payload as sorted JSON", function()
    local p = Export.Build(fixture(), CTX)
    local code = Codec.UploadCode(p, nil)
    local flags, bytes = Codec.ParseUploadCode(code)
    eq(flags, "N")
    local back = json.decode(bytes)
    eq(back.flavor, "forever")
    eq(#back.matches, 1)
    eq(back.characters[1].fp, Crypto.Fingerprint(SECRET))
end)

test("nudges: 5 unverified ranked duels, once per session, only when enabled", function()
    local char = { duels = {} }
    for i = 1, 5 do
        char.duels[i] = { t = T + i, statement = "DE2|…", sigC = "x", match = "m" .. i }
    end
    eq(Export.Unverified(char), 5)
    eq(Export.Unverified(char, { m1 = true, m2 = true }), 3, "confirmed by the community")
    char.lastExport = T + 2
    eq(Export.Unverified(char), 3)
    eq(Export.ShouldNudge(5, false, true), true)
    eq(Export.ShouldNudge(4, false, true), false)
    eq(Export.ShouldNudge(9, true, true), false)
    eq(Export.ShouldNudge(9, false, false), false)
end)

---------------------------------------------------------------------------
-- In the (fake) client
---------------------------------------------------------------------------

local function client(opts)
    local env = Wow.new(opts)
    Stub.install(env)
    env.login()
    Stub.load(env, "UI/Upload.lua")
    return env
end

test("MakeUploadCode: N without C_EncodingUtil, Z with it; remembers the export time", function()
    local env = client()
    local code, payload = env.ns.MakeUploadCode(false)
    eq(code:sub(1, 11), "DUELELO1:N:")
    eq(payload.flavor, "forever")
    eq(payload.characters[1].name, "Ashvale")
    eq(payload.characters[1].secret, DuelEloCharDB.key.secret)
    ok(DuelEloCharDB.lastExport)
    C_EncodingUtil = { CompressString = function(s) return "Z" .. s end }
    Enum = { CompressionMethod = { Deflate = 0 } }
    local z = env.ns.MakeUploadCode(true)
    C_EncodingUtil, Enum = nil, nil
    eq(z:sub(1, 11), "DUELELO1:Z:")
    local _, bytes = Codec.ParseUploadCode(z)
    eq(bytes:sub(1, 2), "Z{")
end)

test("a failing compressor falls back to N", function()
    local env = client()
    C_EncodingUtil = { CompressString = function() error("boom") end }
    Enum = { CompressionMethod = { Deflate = 0 } }
    local code = env.ns.MakeUploadCode(false)
    C_EncodingUtil, Enum = nil, nil
    eq(code:sub(1, 11), "DUELELO1:N:")
end)

test("chat nudge after the 5th unverified ranked duel, once per session", function()
    local env = client()
    local function signedDuel(i)
        local e = { t = time() + i, opp = "X-Y", result = "W", how = "KO", statement = "DE2|…", sigC = "s",
            match = "n" .. i }
        DuelEloCharDB.duels[#DuelEloCharDB.duels + 1] = e
        env.ns.Fire("DUEL_RECORDED", e)
    end
    for i = 1, 4 do signedDuel(i) end
    local nudges = 0
    for _, line in ipairs(env.printed) do if line:find("waiting to be verified", 1, true) then nudges = nudges + 1 end end
    eq(nudges, 0)
    signedDuel(5)
    signedDuel(6)
    nudges = 0
    for _, line in ipairs(env.printed) do if line:find("waiting to be verified", 1, true) then nudges = nudges + 1 end end
    eq(nudges, 1)
end)

test("no nudge when reminders are off", function()
    local env = client()
    DuelEloDB.settings.uploadNudges = false
    for i = 1, 6 do
        local e = { t = time() + i, statement = "DE2|…", sigC = "s", match = "q" .. i }
        DuelEloCharDB.duels[#DuelEloCharDB.duels + 1] = e
        env.ns.Fire("DUEL_RECORDED", e)
    end
    for _, line in ipairs(env.printed) do ok(not line:find("waiting to be verified", 1, true)) end
end)

test("/duelelo upload opens the Upload tab", function()
    local env = client()
    local opened = false
    env.ns.ShowUploadTab = function() opened = true end
    env.slash("upload")
    ok(opened)
end)

test("the Upload page builds and refreshes", function()
    local env = client()
    local page = Stub.stub()
    env.ns.BuildUploadPage(page)
    page.Refresh()
    ok(true)
end)
