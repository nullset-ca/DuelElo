local json = require("json")

local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Glicko.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Ladder.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Rules.lua"))("DuelElo", ns)
local G, Rules = ns.Glicko, ns.Rules

local TOL = 1e-6

local function near(actual, expected, msg)
    if type(actual) ~= "number" or math.abs(actual - expected) > TOL then
        error(("%s: expected %.10g, got %s"):format(msg, expected, tostring(actual)), 2)
    end
end

local function nearP(actual, expected, msg)
    near(actual.r, expected.r, msg .. " r")
    near(actual.rd, expected.rd, msg .. " rd")
    near(actual.sigma, expected.sigma, msg .. " sigma")
end

local vectors = json.read("spec/vectors/glicko.json")

test("vectors: at least 20 cases", function()
    ok(#vectors.cases >= 20, "#cases " .. #vectors.cases)
end)

test("vectors: constants match the implementation", function()
    local c = vectors.constants
    eq({ c.r0, c.rd0, c.sigma0, c.tau, c.scale, c.clamp, c.rdMax },
        { G.R0, G.RD0, G.SIGMA0, G.TAU, G.SCALE, G.CLAMP, G.RD_MAX })
    near(c.c, G.C, "c")
    eq(c.pairWeights, { Rules.PAIR_WEIGHTS[1], Rules.PAIR_WEIGHTS[2], Rules.PAIR_WEIGHTS[3], 0 })
    eq(c.pairWindowDays * 86400, Rules.PAIR_WINDOW)
end)

local RUN = {
    rate = function(c) nearP(G.Rate(c.player, c.games), c.expected, c.name) end,
    update = function(c) nearP(G.Update(c.player, c.opp, c.score, c.weight), c.expected, c.name) end,
    inflate = function(c) near(G.Inflate(c.rd, c.days), c.expected, c.name) end,
    softReset = function(c) nearP(G.SoftReset(c.player), c.expected, c.name) end,
    rdFromGames = function(c) near(G.RDFromGames(c.games), c.expected, c.name) end,
    pairWeight = function(c) eq(Rules.PairWeight(c.times, c.now), c.expected, c.name) end,
}

for _, c in ipairs(vectors.cases) do
    test("vector: " .. c.name, function()
        assert(RUN[c.fn], "unknown fn " .. tostring(c.fn))(c)
    end)
end

test("Glickman's published example (independent of our vectors)", function()
    local res = G.Rate({ r = 1500 - 300, rd = 200, sigma = 0.06 }, {
        { r = 1400 - 300, rd = 30, score = 1 }, { r = 1550 - 300, rd = 100, score = 0 },
        { r = 1700 - 300, rd = 300, score = 0 } })
    ok(math.abs(res.r + 300 - 1464.06) < 0.01, "r " .. res.r)
    ok(math.abs(res.rd - 151.52) < 0.01, "rd " .. res.rd)
    ok(math.abs(res.sigma - 0.05999) < 0.00001, "sigma " .. res.sigma)
end)

local NEW = G.New()

test("equal players: win and loss mirror each other", function()
    local w = G.Update(NEW, { r = 1200, rd = 350 }, 1)
    local l = G.Update(NEW, { r = 1200, rd = 350 }, 0)
    ok(w.r > 1200 and l.r < 1200)
    ok(math.abs((w.r - 1200) + (l.r - 1200)) < 1e-9)
    ok(w.rd < 350, "playing lowers RD")
end)

test("upset pays more than an expected win", function()
    local upset = G.Update({ r = 1400, rd = 80, sigma = 0.06 }, { r = 1700, rd = 80 }, 1).r - 1400
    local expected = G.Update({ r = 1700, rd = 80, sigma = 0.06 }, { r = 1400, rd = 80 }, 1).r - 1700
    ok(upset > expected * 3)
end)

test("clamp: a far stronger opponent counts as +400", function()
    local p = { r = 1200, rd = 100, sigma = 0.06 }
    nearP(G.Update(p, { r = 2100, rd = 100 }, 1), G.Update(p, { r = 1600, rd = 100 }, 1), "clamped")
    nearP(G.Update(p, { r = 300, rd = 100 }, 0), G.Update(p, { r = 800, rd = 100 }, 0), "clamped low")
end)

test("pair weight scales the change; weight 0 changes nothing", function()
    local p, o = { r = 1500, rd = 90, sigma = 0.06 }, { r = 1550, rd = 90 }
    local full = G.Update(p, o, 1, 1).r - 1500
    near(G.Update(p, o, 1, 0.5).r - 1500, full * 0.5, "half")
    near(G.Update(p, o, 1, 0.25).r - 1500, full * 0.25, "quarter")
    eq(G.Update(p, o, 1, 0), p)
end)

test("inactivity grows RD back to 350 in 180 days", function()
    near(G.Inflate(50, 180), 350, "180 days")
    ok(G.Inflate(50, 90) < 350)
    eq(G.Inflate(300, 1000), 350)
    eq(G.Inflate(80, 0), 80)
end)

test("soft reset halves the distance to 1200 and keeps RD >= 150", function()
    eq(G.SoftReset({ r = 1800, rd = 60, sigma = 0.06 }), { r = 1500, rd = 150, sigma = 0.06 })
    eq(G.SoftReset({ r = 1000, rd = 200, sigma = 0.05 }), { r = 1100, rd = 200, sigma = 0.05 })
end)

test("RD estimate from games shrinks with play", function()
    eq(G.RDFromGames(0), 350)
    eq(G.RDFromGames(nil), 350)
    ok(G.RDFromGames(10) < G.RDFromGames(2))
    eq(G.RDFromGames(100000), 60)
end)

test("Round to the nearest point", function()
    eq(G.Round(1234.5), 1235)
    eq(G.Round(1234.49), 1234)
end)
