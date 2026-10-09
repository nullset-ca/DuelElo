local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Elo.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Glicko.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Rules.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/WidgetModel.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Data.lua"))("DuelElo", ns)
local Data = ns.Data

local function entry(result, opp, class)
    return { t = 1000, opp = opp or "Thrall-Area52", class = class, result = result, how = "KO" }
end

test("InitChar creates a fresh db", function()
    local db = Data.InitChar(nil)
    eq(db.schema, Data.SCHEMA)
    eq(db.totals, { w = 0, l = 0 })
    eq(#db.duels, 0)
end)

test("InitChar keeps existing data", function()
    local db = Data.InitChar({ schema = 1, totals = { w = 3, l = 1 }, duels = { entry("W") }, streak = 2, bestStreak = 2 })
    eq(db.totals, { w = 3, l = 1 })
    eq(#db.duels, 1)
    eq(db.streak, 2)
end)

test("InitChar repairs corrupted fields", function()
    local db = Data.InitChar({ totals = "oops", duels = { entry("W") }, streak = "x" })
    eq(db.totals, { w = 0, l = 0 })
    eq(#db.duels, 1)
    eq(db.streak, 0)
    eq(type(db.byOpp), "table")
end)

test("InitChar repairs partial nested tables", function()
    eq(Data.InitChar({ totals = { w = 5 } }).totals, { w = 5, l = 0 })
end)

test("InitAccount defaults and repair", function()
    eq(Data.InitAccount(nil).settings.chatSummary, true)
    eq(Data.InitAccount({ settings = { chatSummary = false } }).settings.chatSummary, false)
    eq(Data.InitAccount({ settings = 7 }).settings.chatSummary, true)
end)

test("Record updates totals, class and opponent buckets", function()
    local db = Data.InitChar(nil)
    Data.Record(db, entry("W", "Thrall-Area52", "SHAMAN"))
    Data.Record(db, entry("L", "Thrall-Area52", nil))
    Data.Record(db, entry("W", "Jaina-Sargeras", "MAGE"))
    eq(db.totals, { w = 2, l = 1 })
    eq(db.byClass.SHAMAN, { w = 1, l = 0 })
    eq(db.byClass.MAGE, { w = 1, l = 0 })
    eq(db.byOpp["Thrall-Area52"].w, 1)
    eq(db.byOpp["Thrall-Area52"].l, 1)
    eq(db.byOpp["Thrall-Area52"].class, "SHAMAN", "unknown class must not erase a known one")
    eq(#db.duels, 3)
end)

test("Record tracks win and loss streaks", function()
    local db = Data.InitChar(nil)
    for _, r in ipairs({ "W", "W", "W", "L", "L", "W" }) do Data.Record(db, entry(r)) end
    eq(db.streak, 1)
    eq(db.bestStreak, 3)
    Data.Record(db, entry("L"))
    Data.Record(db, entry("L"))
    eq(db.streak, -2)
end)

test("Record caps history but keeps totals", function()
    local saved = Data.MAX_HISTORY
    Data.MAX_HISTORY = 3
    local db = Data.InitChar(nil)
    for i = 1, 5 do
        local e = entry("W")
        e.t = i
        Data.Record(db, e)
    end
    Data.MAX_HISTORY = saved
    eq(#db.duels, 3)
    eq(db.duels[1].t, 3, "oldest entries dropped first")
    eq(db.totals.w, 5)
end)

test("WinRate", function()
    eq(Data.WinRate(0, 0), 0)
    eq(Data.WinRate(3, 1), 0.75)
end)

test("PrunePlayers drops stale and corrupt entries only", function()
    local now = 10000000
    local players = {
        ["Fresh-R"] = { rating = 1, seen = now - 10 },
        ["Stale-R"] = { rating = 1, seen = now - 100 },
        ["NoSeen-R"] = { rating = 1 },
        ["Junk-R"] = "oops",
    }
    eq(Data.PrunePlayers(players, now, 50), 2)
    ok(players["Fresh-R"])
    ok(players["NoSeen-R"], "entries without a timestamp are kept")
    eq(players["Stale-R"], nil)
    eq(players["Junk-R"], nil)
end)

test("schema 2 migration archives Elo and starts Glicko fresh, keeping history", function()
    local db = Data.InitChar(dofile("tests/fixtures/v1_char.lua"))
    eq(db.schema, Data.SCHEMA)
    eq(db.legacy, { rating = 1452, games = 25, w = 16, l = 9, peak = 1510 })
    eq(db.rating, 1200)
    eq(db.glicko, { r = 1200, rd = 350, sigma = 0.06 })
    eq(db.rankedGames, 0)
    eq({ db.rankedW, db.rankedL, db.peak, db.lastRanked }, { 0, 0, 0, 0 })
    eq(#db.duels, 2, "history kept")
    eq(db.duels[1].delta, 22, "old entries keep their Elo deltas")
    eq(db.duels[1].legacy, true, "old ranked entries marked legacy")
    eq(db.duels[2].legacy, nil, "casual entries untouched")
    eq(db.totals, { w = 30, l = 12 })
    eq(db.bestStreak, 9)
    eq(db.byOpp["Thrall-Area52"].w, 10)
end)

test("schema 2 migration: no legacy block without ranked games", function()
    local db = Data.InitChar({ schema = 1, rating = 1200, rankedGames = 0, totals = { w = 1, l = 0 }, duels = {} })
    eq(db.legacy, nil)
    eq(db.totals.w, 1)
end)

test("schema 2 saves are not migrated again", function()
    local saved = Data.InitChar(dofile("tests/fixtures/v1_char.lua"))
    saved.rating, saved.rankedGames = 1333, 4
    local db = Data.InitChar(saved)
    eq(db.rating, 1333)
    eq(db.rankedGames, 4)
    eq(db.legacy.rating, 1452)
end)

test("account SavedVariables move to the current schema untouched", function()
    local db = Data.InitAccount({ schema = 1, players = { ["A-R"] = { rating = 1500, games = 3 } },
        settings = { rankedPref = "always" } })
    eq(db.schema, Data.SCHEMA)
    eq(db.players["A-R"].rating, 1500)
    eq(db.settings.rankedPref, "always")
end)

test("schema 3 hides a widget saved as shown, once", function()
    local db = Data.InitAccount({ schema = 2, settings = { widget = { shown = true, preset = "full" } } })
    eq(db.schema, 3)
    eq(db.settings.widget.shown, false)
    eq(db.settings.widget.preset, "full", "other widget settings kept")
    db.settings.widget.shown = true
    eq(Data.InitAccount(db).settings.widget.shown, true, "turning it back on sticks")
end)

test("a fresh account starts with the widget hidden", function()
    eq(Data.InitAccount(nil).settings.widget.shown, false)
end)

---------------------------------------------------------------------------
-- Reports (SPEC §3.6)
---------------------------------------------------------------------------

local NOW = 1791500000
local function report(over)
    local r = { target = "Thrall-Area52", reason = "THROWN", matchId = "12:34", note = "gave up at 90%" }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
end

test("a valid report is stored with matchId, target, reason, note and time", function()
    local db = Data.InitChar(nil)
    eq(Data.AddReport(db, report(), NOW), true)
    eq(db.reports, { { t = NOW, target = "Thrall-Area52", matchId = "12:34", reason = "THROWN", note = "gave up at 90%" } })
    ok(Data.Reported(db, "12:34"))
    ok(not Data.Reported(db, "56:78"))
end)

test("reports survive a reload (SavedVariables round trip)", function()
    local db = Data.InitChar(nil)
    Data.AddReport(db, report(), NOW)
    local again = Data.InitChar(db)
    eq(#again.reports, 1)
    eq(again.reports[1].reason, "THROWN")
end)

test("report validation", function()
    local db = Data.InitChar(nil)
    eq({ Data.AddReport(db, report({ reason = "RUDE" }), NOW) }, { false, "reason" })
    eq({ Data.AddReport(db, report({ target = "NoRealm" }), NOW) }, { false, "target" })
    eq({ Data.AddReport(db, report({ target = "Evil|cffff0000-Realm" }), NOW) }, { false, "target" })
    eq({ Data.AddReport(db, report({ matchId = "bad id" }), NOW) }, { false, "match" })
    eq({ Data.AddReport(db, report({ note = ("x"):rep(141) }), NOW) }, { false, "note" })
    eq(#db.reports, 0)
end)

test("notes: 140 characters (not bytes), escapes and controls stripped, empty dropped", function()
    local db = Data.InitChar(nil)
    eq(Data.AddReport(db, report({ matchId = "1:1", note = ("é"):rep(140) }), NOW), true)
    eq(Data.AddReport(db, report({ matchId = "1:2", note = "  |cffff0000red|r\nline  " }), NOW), true)
    eq(db.reports[2].note, "cffff0000redrline")
    eq(Data.AddReport(db, report({ matchId = "1:3", note = "   " }), NOW), true)
    eq(db.reports[3].note, nil)
    eq(Data.AddReport(db, report({ matchId = nil }), NOW), true, "a report without a match")
end)

test("one report per duel", function()
    local db = Data.InitChar(nil)
    Data.AddReport(db, report(), NOW)
    eq({ Data.AddReport(db, report({ reason = "HELP" }), NOW + 5) }, { false, "duplicate" })
end)

test("at most 20 reports a day", function()
    local db = Data.InitChar(nil)
    for i = 1, 20 do eq(Data.AddReport(db, report({ matchId = "m:" .. i }), NOW + i), true) end
    eq({ Data.AddReport(db, report({ matchId = "m:21" }), NOW + 21) }, { false, "limit" })
    eq(Data.AddReport(db, report({ matchId = "m:22" }), NOW + 86400 + 2), true, "a day later")
end)

test("only the newest 200 reports are kept", function()
    local db = Data.InitChar(nil)
    for i = 1, 205 do db.reports[i] = { t = 1, target = "A-B", reason = "OTHER" } end
    eq(Data.AddReport(db, report(), NOW), true)
    eq(#db.reports, Data.REPORT_KEEP)
    eq(db.reports[#db.reports].matchId, "12:34")
end)
