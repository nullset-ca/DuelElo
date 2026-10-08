-- Rank tiers (Elo.lua) and ranked results applied to a character (Data.ApplyRanked).
-- The rating math itself is covered by glicko_spec.lua.
local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Elo.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Glicko.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Rules.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/WidgetModel.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Data.lua"))("DuelElo", ns)
local Elo, Data, Glicko = ns.Elo, ns.Data, ns.Glicko

test("Rank: tier boundaries and divisions", function()
    local cases = {
        { 0, "Combatant IV" }, { 1049, "Combatant IV" }, { 1050, "Combatant III" }, { 1199, "Combatant I" },
        { 1200, "Challenger IV" }, { 1250, "Challenger III" }, { 1399, "Challenger I" },
        { 1400, "Rival IV" }, { 1599, "Rival I" }, { 1600, "Duelist IV" }, { 1799, "Duelist I" },
        { 1800, "Elite" }, { 3000, "Elite" },
    }
    for _, c in ipairs(cases) do eq(Elo.Rank(c[1]).label, c[2], "rating " .. c[1]) end
end)

test("Rank: progress within division", function()
    eq(Elo.Rank(1200).progress, 0)
    eq(Elo.Rank(1225).progress, 0.5)
    eq(Elo.Rank(500).progress, 0, "deep combatant clamps to 0")
    eq(Elo.Rank(2500).progress, 1, "elite is always full")
end)

test("Rank: everyone starts in Challenger IV", function()
    eq(Elo.Rank(Elo.START).label, "Challenger IV")
end)

test("CompareRank detects promotion and demotion", function()
    eq(Elo.CompareRank(Elo.Rank(1390), Elo.Rank(1410)), 1)
    eq(Elo.CompareRank(Elo.Rank(1260), Elo.Rank(1251)), 0)
    eq(Elo.CompareRank(Elo.Rank(1251), Elo.Rank(1249)), -1, "division drop")
    eq(Elo.CompareRank(Elo.Rank(1790), Elo.Rank(1810)), 1, "duelist I -> elite")
end)

local function rankedEntry(result, opp, t)
    return { t = t or 100000, opp = opp or "Thrall-Area52", result = result, how = "KO" }
end

test("ApplyRanked updates rating, games and entry fields", function()
    local db = Data.InitChar(nil)
    local e = rankedEntry("W")
    ok(Data.ApplyRanked(db, e, 1200, 0))
    local g = Glicko.Update(Glicko.New(), { r = 1200, rd = 350 }, 1, 1)
    eq(e.ranked, true)
    eq(e.oppRating, 1200)
    eq(e.before, 1200)
    eq(e.after, Glicko.Round(g.r))
    eq(e.delta, e.after - 1200)
    ok(e.delta > 100, "a new player's first win moves a lot")
    eq(e.placement, 1)
    eq(e.weight, nil, "full weight is not stored")
    eq(db.rating, e.after)
    eq(db.glicko, g)
    eq(db.lastRanked, e.t)
    eq(db.rankedGames, 1)
    eq(db.rankedW, 1)
    eq(db.peak, 0, "no peak during placements")
end)

test("a loss lowers the rating; opponent games set their RD estimate", function()
    local db = Data.InitChar(nil)
    local e = rankedEntry("L")
    Data.ApplyRanked(db, e, 1500, 40)
    local g = Glicko.Update(Glicko.New(), { r = 1500, rd = Glicko.RDFromGames(40) }, 0, 1)
    eq(db.glicko, g)
    ok(e.delta < 0)
    eq(db.rankedL, 1)
end)

test("peak is set once placements finish", function()
    local db = Data.InitChar(nil)
    for i = 1, Elo.PLACEMENTS do
        Data.ApplyRanked(db, rankedEntry("W", "Opp" .. i), 1200, 20)
    end
    eq(db.rankedGames, 10)
    eq(db.peak, db.rating)
    local e = rankedEntry("W", "Someone")
    Data.ApplyRanked(db, e, 1200, 20)
    eq(e.placement, nil)
end)

test("pair weights: repeat games vs one opponent move less, the 4th not at all", function()
    local db = Data.InitChar(nil)
    local t = 100000
    local deltas = {}
    for i = 1, 4 do
        -- reset to the same state so only the weight differs
        db.glicko, db.rating, db.lastRanked = Glicko.New(), 1200, 0
        local e = rankedEntry("W", "Thrall", t + i)
        ok(Data.ApplyRanked(db, e, 1200, 20))
        deltas[i] = e.delta
        eq(e.weight, ({ nil, 0.5, 0.25, 0 })[i])
    end
    ok(deltas[1] > deltas[2] and deltas[2] > deltas[3], "1 > 0.5 > 0.25")
    eq(deltas[4], 0, "weight 0: recorded, no change")
    eq(Data.RankedAllowed(db, "Thrall", t + 10), false)
    ok(Data.RankedAllowed(db, "Jaina", t + 10), "other opponents unaffected")
    ok(Data.RankedAllowed(db, "Thrall", t + 7 * 86400 + 2), "allowed again after 7 days")
end)

test("old games drop out of the ranked log", function()
    local db = Data.InitChar(nil)
    Data.ApplyRanked(db, rankedEntry("W", "Thrall", 100000), 1200, 20)
    Data.ApplyRanked(db, rankedEntry("W", "Thrall", 100000 + 8 * 86400), 1200, 20)
    eq(#db.rankedLog.Thrall, 1)
end)

test("RD grows while idle between ranked games", function()
    local db = Data.InitChar(nil)
    Data.ApplyRanked(db, rankedEntry("W", "A", 100000), 1200, 20)
    local rdAfter = db.glicko.rd
    local active = Data.InitChar(nil)
    active.glicko = { r = db.glicko.r, rd = rdAfter, sigma = db.glicko.sigma }
    active.rating, active.lastRanked = db.rating, 100000
    local e1, e2 = rankedEntry("W", "B", 100000 + 60), rankedEntry("W", "B", 100000 + 60 * 86400)
    Data.ApplyRanked(active, e1, 1200, 20)
    Data.ApplyRanked(db, e2, 1200, 20)
    ok(e2.delta > e1.delta, "after 60 idle days the same win moves more")
end)
