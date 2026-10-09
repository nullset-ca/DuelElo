local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Elo.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Ladder.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/WidgetModel.lua"))("DuelElo", ns)
local M, Elo = ns.WidgetModel, ns.Elo

local NOW = 1800000000
local HOUR = 3600

local function settings(over)
    local w = {}
    for k, v in pairs(M.DEFAULTS) do w[k] = v end
    for k, v in pairs(over or {}) do w[k] = v end
    return w
end

-- duels: list of { t, result, delta } (ranked) or { t, result, casual = true }
local function char(rating, games, duels)
    local list = {}
    for _, d in ipairs(duels or {}) do
        list[#list + 1] = { t = d.t, result = d.result, how = d.how or "KO", ranked = not d.casual or nil,
            delta = not d.casual and d.delta or nil, legacy = d.legacy }
    end
    return { rating = rating, rankedGames = games, rankedW = 3, rankedL = 2, peak = 1500,
        glicko = { r = rating, rd = 80, sigma = 0.06 }, duels = list }
end

local CTX = { sessionStart = NOW - 2 * HOUR, dayStart = NOW - 10 * HOUR, name = "Ashvale-Sargeras" }

test("placements: grey emblem and progress through the 10 games", function()
    local m = M.Build(char(1260, 4), settings(), CTX)
    eq(m.tierKey, "UNRANKED")
    eq(m.placements, { done = 4, total = Elo.PLACEMENTS })
    eq(m.progress, nil)
    eq(m.estimated, true)
end)

test("ranked: tier, label and progress to the next division", function()
    local m = M.Build(char(1452, 30), settings(), CTX)
    eq(m.tierKey, "RIVAL")
    eq(m.label, "Rival III")
    eq(m.rating, 1452)
    eq(m.progress.toNext, 48)
    eq(m.progress.nextLabel, "Rival II")
    ok(math.abs(m.progress.fraction - 0.04) < 1e-9)
    eq(m.rd, 80)
    eq(m.record, { w = 3, l = 2 })
end)

test("division and tier boundaries", function()
    local cases = {
        { 1199, "Combatant I", 1, "Challenger IV" },
        { 1200, "Challenger IV", 50, "Challenger III" },
        { 1399, "Challenger I", 1, "Rival IV" },
        { 1799, "Duelist I", 1, "Elite" },
    }
    for _, c in ipairs(cases) do
        local m = M.Build(char(c[1], 20), settings(), CTX)
        eq(m.label, c[2], "label at " .. c[1])
        eq(m.progress.toNext, c[3], "toNext at " .. c[1])
        eq(m.progress.nextLabel, c[4], "next at " .. c[1])
    end
    local top = M.Build(char(1900, 20), settings(), CTX)
    eq(top.label, "Elite")
    eq(top.progress.toNext, nil, "nothing above Elite")
    eq(top.progress.fraction, 1)
end)

test("official rating from the ladder data overrides the estimate", function()
    local m = M.Build(char(1452, 30), settings(), { official = 1610, sessionStart = 0, dayStart = 0 })
    eq(m.rating, 1610)
    eq(m.official, true)
    eq(m.estimated, false)
    eq(m.label, "Duelist IV")
end)

test("an official rating shows a rank even during local placements", function()
    local m = M.Build(char(1260, 3), settings(), { official = 1500, sessionStart = 0, dayStart = 0 })
    eq(m.placements, nil)
    eq(m.tierKey, "RIVAL")
end)

test("OfficialRating parses the ladder entry", function()
    local data = { [1] = { players = { ["Ashvale-Sargeras"] = "1834|31|DUELIST|S1E,FD|0" } } }
    eq(M.OfficialRating(data, 1, "Ashvale-Sargeras"), 1834)
    eq(M.OfficialRating(data, 1, "Other-Realm"), nil)
    eq(M.OfficialRating(data, 3, "Ashvale-Sargeras"), nil)
    eq(M.OfficialRating(nil, 1, "Ashvale-Sargeras"), nil)
    eq(M.OfficialRating({ [1] = { players = { X = "junk" } } }, 1, "X"), nil)
end)

-- 14 ranked games: three before today, five today before this session, six this session.
local function history()
    local d = {}
    for i = 1, 3 do d[#d + 1] = { t = NOW - 30 * HOUR + i, result = "W", delta = 10 } end
    for i = 1, 5 do d[#d + 1] = { t = NOW - 8 * HOUR + i, result = "L", delta = -4 } end
    for i = 1, 6 do d[#d + 1] = { t = NOW - HOUR + i, result = "W", delta = 7 } end
    d[#d + 1] = { t = NOW - 30, result = "L", casual = true }
    return d
end

test("trend: this session", function()
    local m = M.Build(char(1500, 40, history()), settings({ period = "session" }), CTX)
    eq(m.trend.value, 42)
    eq(m.trend.games, 6)
    eq(#m.trend.points, 7, "start + one point per game")
end)

test("trend: today", function()
    local m = M.Build(char(1500, 40, history()), settings({ period = "today" }), CTX)
    eq(m.trend.value, 42 - 20)
    eq(m.trend.games, 11)
end)

test("trend: last 10 ranked games", function()
    local m = M.Build(char(1500, 40, history()), settings({ period = "last10" }), CTX)
    eq(m.trend.games, 10)
    eq(m.trend.value, 42 - 16)
end)

test("trend: nothing in the period", function()
    local m = M.Build(char(1500, 40, history()), settings(), { sessionStart = NOW, dayStart = NOW })
    eq(m.trend.value, 0)
    eq(m.trend.points, {})
end)

test("trend ignores casual and test-era (legacy) results", function()
    local d = { { t = NOW - 10, result = "W", delta = 500, legacy = true }, { t = NOW - 5, result = "L", casual = true },
        { t = NOW - 1, result = "W", delta = 9 } }
    local m = M.Build(char(1500, 40, d), settings(), { sessionStart = 0, dayStart = 0 })
    eq(m.trend.value, 9)
    eq(m.trend.games, 1)
end)

test("sparkline points: rating path normalised to 0..1", function()
    local d = { { t = NOW - 3, result = "W", delta = 10 }, { t = NOW - 2, result = "L", delta = -20 },
        { t = NOW - 1, result = "W", delta = 30 } }
    -- ratings: 1480, 1490, 1470, 1500
    local m = M.Build(char(1500, 40, d), settings({ period = "last10" }), CTX)
    eq(m.trend.points, { 1 / 3, 2 / 3, 0, 1 })
end)

test("Normalise: flat line, single point, many points", function()
    eq(M.Normalise({ 1500, 1500, 1500 }), { 0.5, 0.5, 0.5 })
    eq(M.Normalise({ 1500 }), { 0.5 })
    eq(M.Normalise({}), {})
    eq(M.Normalise({ 0, 5, 10, 2.5 }), { 0, 0.5, 1, 0.25 })
end)

test("recent results: newest last, ranked only by default", function()
    local m = M.Build(char(1500, 40, history()), settings({ recent = 3 }), CTX)
    eq(#m.recent, 3)
    for _, r in ipairs(m.recent) do eq(r.ranked, true) end
    eq(m.recent[3], { result = "W", fled = false, ranked = true, delta = 7 })
end)

test("recent results: include casual option", function()
    local d = history()
    d[#d + 1] = { t = NOW - 1, result = "W", casual = true, how = "FLED" }
    local m = M.Build(char(1500, 40, d), settings({ recent = 5, casual = true }), CTX)
    eq(#m.recent, 5)
    eq(m.recent[5], { result = "W", fled = true, ranked = false, delta = nil })
    eq(m.recent[4].ranked, false)
end)

test("recent results: fewer games than boxes", function()
    local m = M.Build(char(1200, 1, { { t = NOW, result = "L", delta = -30 } }), settings({ recent = 10 }), CTX)
    eq(#m.recent, 1)
end)

test("Validate clamps scale and opacity and fixes unknown values", function()
    local w = M.Validate({ scale = 5, opacity = 0.01, preset = "huge", trend = "bars", period = "year",
        recent = 7, shown = "yes" })
    eq(w.scale, M.SCALE_MAX)
    eq(w.opacity, M.OPACITY_MIN)
    eq(w.preset, "compact")
    eq(w.trend, "number")
    eq(w.period, "session")
    eq(w.recent, 5)
    eq(w.shown, false, "junk falls back to the default (hidden)")
    eq(M.Validate({ scale = 0.1 }).scale, M.SCALE_MIN)
    eq(M.Validate({ scale = "x" }).scale, 1)
    local good = M.Validate({ scale = 1.5, opacity = 0.6, preset = "full", trend = "both", period = "today",
        recent = 10, shown = true })
    eq({ good.scale, good.opacity, good.preset, good.trend, good.period, good.recent, good.shown },
        { 1.5, 0.6, "full", "both", "today", 10, true })
end)

test("TrendText", function()
    eq(M.TrendText(38), "+38")
    eq(M.TrendText(-12), "-12")
    eq(M.TrendText(0), "0")
end)
