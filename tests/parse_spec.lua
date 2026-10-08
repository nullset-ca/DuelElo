local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Parse.lua"))("DuelElo", ns)
local Parse = ns.Parse

local KO = "%1$s has defeated %2$s in a duel"
local FLED = "%2$s has fled from %1$s in a duel"

test("Compile handles positional args in text order", function()
    local c = Parse.Compile(FLED)
    eq(c.pattern, "^(.+) has fled from (.+) in a duel$")
    eq(c.order, { 2, 1 })
end)

test("Compile handles plain %s args", function()
    eq(Parse.Compile("%s has defeated %s in a duel").order, { 1, 2 })
end)

test("Compile escapes pattern magic characters", function()
    local c = Parse.Compile("%2$s wurde von %1$s im Duell besiegt.")
    ok(("Jaina wurde von Thrall im Duell besiegt."):match(c.pattern))
    ok(not ("Jaina wurde von Thrall im Duell besiegtX"):match(c.pattern), ". must be literal")
end)

test("Compile rejects nil and templates without exactly two names", function()
    eq(Parse.Compile(nil), nil)
    eq(Parse.Compile("%s won"), nil)
    eq(Parse.Compile("%s %s %s"), nil)
end)

local match = Parse.Matcher({ { kind = "KO", fmt = KO }, { kind = "FLED", fmt = FLED } })

test("Matcher: knockout gives winner then loser", function()
    eq({ match("Ashvale has defeated Thrall-Area52 in a duel") }, { "KO", "Ashvale", "Thrall-Area52" })
end)

test("Matcher: retreat maps loser-first text to winner, loser", function()
    eq({ match("Thrall-Area52 has fled from Ashvale in a duel") }, { "FLED", "Ashvale", "Thrall-Area52" })
end)

test("Matcher: ignores unrelated and non-string messages", function()
    eq(match("You have been awarded 5 honor."), nil)
    eq(match(nil), nil)
    eq(match(42), nil)
end)

test("Matcher skips missing templates", function()
    local m, n = Parse.Matcher({ { kind = "KO", fmt = nil }, { kind = "FLED", fmt = FLED } })
    eq(n, 1)
    eq(m("A has fled from B in a duel"), "FLED")
end)

test("SplitName", function()
    eq({ Parse.SplitName("Thrall-Area52") }, { "Thrall", "Area52" })
    eq({ Parse.SplitName("Thrall") }, { "Thrall" })
    eq({ Parse.SplitName("Thrall-Twisting-Nether") }, { "Thrall", "Twisting-Nether" })
    eq(Parse.SplitName(nil), nil)
end)

test("Normalize appends default realm only when missing", function()
    eq(Parse.Normalize("Thrall", "Sargeras"), "Thrall-Sargeras")
    eq(Parse.Normalize("Thrall-Area52", "Sargeras"), "Thrall-Area52")
    eq(Parse.Normalize("Thrall", nil), "Thrall")
    eq(Parse.Normalize(nil, "Sargeras"), nil)
end)

test("CountdownPattern matches the duel countdown line only", function()
    local p = Parse.CountdownPattern("Duel starting: %d")
    ok(("Duel starting: 3"):match(p))
    ok(("Duel starting: 10"):match(p))
    ok(not ("Duel starting: x"):match(p))
    ok(not ("Ashvale has defeated Duskmire in a duel"):match(p))
    eq(Parse.CountdownPattern(nil), nil)
    eq(Parse.CountdownPattern("no number"), nil)
end)
