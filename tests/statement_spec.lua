local json = require("json")

local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Crypto.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Statement.lua"))("DuelElo", ns)
local S = ns.Statement
local V = json.read("spec/vectors/statement.json")

for _, c in ipairs(V.cases) do
    test("statement vector: " .. c.name, function()
        if c.kind == "match" then
            eq(S.Match(c.input), c.statement)
            eq(S.Sign(V.secrets.challenger, c.statement), c.sigC)
            eq(S.Sign(V.secrets.challenged, c.statement), c.sigD)
            ok(S.Verify(V.secrets.challenger, c.statement, c.sigC))
            ok(not S.Verify(V.secrets.challenged, c.statement, c.sigC), "wrong key")
        else
            eq(S.Witness(c.input), c.statement)
            eq(S.Sign(V.secrets.witness, c.statement), c.sig)
        end
        local parsed = S.Parse(c.statement)
        ok(parsed, "parses")
        eq(parsed.kind, c.kind)
    end)
end

local BASE = V.cases[1].input

local function with(over)
    local t = {}
    for k, v in pairs(BASE) do t[k] = v end
    for k, v in pairs(over) do t[k] = v end
    return t
end

test("parse round trip gives the same fields", function()
    local p = S.Parse(V.cases[1].statement)
    p.kind = nil
    eq(p, BASE)
end)

test("invalid fields are rejected with the field name", function()
    local bad = {
        { { winner = "X" }, "bad winner" }, { { how = "DRAW" }, "bad how" },
        { { challenger = "Evil|Name" }, "bad challenger" }, { { challenged = "" }, "bad challenged" },
        { { level = 0 }, "bad level" }, { { level = 101 }, "bad level" }, { { cPre = 1.5 }, "bad cPre" },
        { { cReady = 64 }, "bad cReady" }, { { tEnd = -1 }, "bad tEnd" }, { { matchId = "a b" }, "bad matchId" },
        { { region = "1" }, "bad region" }, { { challenger = "Line\nBreak" }, "bad challenger" },
    }
    for _, b in ipairs(bad) do
        local st, err = S.Match(with(b[1]))
        eq(st, nil, b[2])
        eq(err, b[2])
    end
    local missing = with({})
    missing.tStart = nil
    eq(select(2, S.Match(missing)), "bad tStart")
end)

test("a client never witnesses its own duel", function()
    local w = V.cases[#V.cases].input
    local own = {}
    for k, v in pairs(w) do own[k] = v end
    own.witness = own.winner
    eq({ S.Witness(own) }, { nil, "own duel" })
    own.witness = own.loser
    eq(S.Witness(own), nil)
end)

test("witness time is floored to 10 s", function()
    eq(S.WitnessTime(1791600309), 1791600300)
    eq(S.WitnessTime(1791600300), 1791600300)
end)

test("Parse rejects non-canonical or malformed strings", function()
    local st = V.cases[1].statement
    eq(S.Parse(st .. "|"), nil, "trailing separator")
    eq(S.Parse(st:gsub("|30|", "|030|")), nil, "leading zero")
    eq(S.Parse(st:gsub("^DE2", "DE1")), nil, "unknown tag")
    eq(S.Parse(st:gsub("|C|", "|X|")), nil, "bad winner")
    eq(S.Parse("DE2|x"), nil)
    eq(S.Parse(nil), nil)
end)

test("Sign refuses malformed secrets", function()
    eq(S.Sign("abc", "DE2|..."), nil)
    eq(S.Sign(("ab"):rep(31), "x"), nil)
    eq(S.Verify("abc", "x", "sig"), false)
end)
