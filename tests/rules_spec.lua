local Wow = require("wow")

local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Ladder.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Rules.lua"))("DuelElo", ns)
local Rules = ns.Rules

local NOW = 2000000000
local DAY = 86400

local function ctx(over)
    local c = { myLevel = 30, oppLevel = 30, opp = "Thrall-Area52", characters = {},
        pairTimes = {}, now = NOW }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

test("same level at any level is eligible", function()
    eq(Rules.Check(ctx()), true)
    eq(Rules.Check(ctx({ myLevel = 1, oppLevel = 1 })), true)
    eq(Rules.Check(ctx({ myLevel = 80, oppLevel = 80 })), true)
end)

test("different or unknown levels -> L", function()
    eq({ Rules.Check(ctx({ oppLevel = 31 })) }, { false, "L" })
    local c = ctx()
    c.myLevel = nil
    eq({ Rules.Check(c) }, { false, "L" })
    c = ctx()
    c.oppLevel = nil
    eq({ Rules.Check(c) }, { false, "L" })
    c.myLevel = nil
    eq({ Rules.Check(c) }, { false, "L" }, "both unknown")
end)

test("opponent is one of our own characters -> A", function()
    local chars = { ["Thrall-Area52"] = { class = "SHAMAN", level = 30 } }
    eq({ Rules.Check(ctx({ characters = chars })) }, { false, "A" })
end)

test("ladder-banned on either side -> B", function()
    eq({ Rules.Check(ctx({ oppBanned = true })) }, { false, "B" })
    eq({ Rules.Check(ctx({ meBanned = true })) }, { false, "B" })
end)

test("pair weight 0 -> F", function()
    local times = { NOW - DAY, NOW - 2 * DAY, NOW - 3 * DAY }
    eq({ Rules.Check(ctx({ pairTimes = times })) }, { false, "F" })
end)

test("level is checked before the other rules", function()
    eq({ Rules.Check(ctx({ oppLevel = 20, oppBanned = true,
        characters = { ["Thrall-Area52"] = {} } })) }, { false, "L" })
end)

test("pair weights over the trailing 7 days: 1, 0.5, 0.25, 0", function()
    eq(Rules.PairWeight({}, NOW), 1)
    eq(Rules.PairWeight(nil, NOW), 1)
    eq(Rules.PairWeight({ NOW - DAY }, NOW), 0.5)
    eq(Rules.PairWeight({ NOW - DAY, NOW - 6 * DAY }, NOW), 0.25)
    eq(Rules.PairWeight({ NOW - 1, NOW - 2, NOW - 3 }, NOW), 0)
    eq(Rules.PairWeight({ NOW - 1, NOW - 2, NOW - 3, NOW - 4 }, NOW), 0)
end)

test("games older than 7 days don't count toward the pair weight", function()
    eq(Rules.PairWeight({ NOW - 7 * DAY, NOW - 8 * DAY, NOW - 30 * DAY }, NOW), 1)
    eq(Rules.PairWeight({ NOW - 7 * DAY + 1 }, NOW), 0.5)
end)

test("every reason code has prompt text", function()
    for _, code in ipairs({ "L", "A", "B", "F", "U", "N", "D" }) do
        ok(Rules.REASONS[code], code)
        eq(Rules.ReasonText(code), Rules.REASONS[code])
    end
    eq(Rules.ReasonText("?"), "Not available")
end)

test("LadderBanned reads the flags field", function()
    local data = { [1] = { players = {
        ["Bad-Realm"] = "1834|31|DUELIST|S1E,FD|1",
        ["Good-Realm"] = "1834|31|DUELIST|S1E,FD|0",
        ["Both-Realm"] = "1200|900|COMBATANT||3",
        ["Odd-Realm"] = "1200|900|COMBATANT||",
    } } }
    eq(Rules.LadderBanned(data, 1, "Bad-Realm"), true)
    eq(Rules.LadderBanned(data, 1, "Good-Realm"), false)
    eq(Rules.LadderBanned(data, 1, "Both-Realm"), true)
    eq(Rules.LadderBanned(data, 1, "Odd-Realm"), false)
    eq(Rules.LadderBanned(data, 1, "Unknown-Realm"), false)
    eq(Rules.LadderBanned(data, 3, "Bad-Realm"), false)
    eq(Rules.LadderBanned(nil, 1, "Bad-Realm"), false)
end)

---------------------------------------------------------------------------
-- Account character registry
---------------------------------------------------------------------------

test("login registers the character with class and level", function()
    local env = Wow.new()
    env.login()
    eq(DuelEloDB.characters["Ashvale-Sargeras"], { class = "PALADIN", level = 30, fp = env.ns.myFp })
end)

test("registry keeps other characters and updates on level up", function()
    local env = Wow.new({ db = { schema = 1, characters = { ["Alt-Sargeras"] = { class = "MAGE", level = 12, fp = "ab" } } } })
    env.login()
    env.fire("PLAYER_LEVEL_UP", 31)
    eq(DuelEloDB.characters["Alt-Sargeras"], { class = "MAGE", level = 12, fp = "ab" })
    eq(DuelEloDB.characters["Ashvale-Sargeras"].level, 31)
end)

test("a secret level is not stored", function()
    local env = Wow.new({ units = { player = { name = "Ashvale", realm = "Sargeras", class = "PALADIN", level = "lvl" } } })
    env.secrets["lvl"] = true
    env.login()
    eq(DuelEloDB.characters["Ashvale-Sargeras"], { class = "PALADIN", fp = env.ns.myFp })
end)

test("ranked log keeps 7 days of games for the pair weight", function()
    local db = { schema = 1 }
    local env = Wow.new({ charDB = db })
    local a = env.login()
    local c = DuelEloCharDB
    local t0 = 1000000
    for i, t in ipairs({ t0, t0 + 3 * DAY, t0 + 5 * DAY }) do
        a.Data.ApplyRanked(c, { t = t, opp = "Thrall-Area52", result = "W" }, 1200)
        eq(#c.rankedLog["Thrall-Area52"], i)
    end
    eq(Rules.PairWeight(c.rankedLog["Thrall-Area52"], t0 + 6 * DAY), 0)
end)
