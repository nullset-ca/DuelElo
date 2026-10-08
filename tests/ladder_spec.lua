local Wow = require("wow")
local Stub = require("ui_stub")

local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Ladder.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Leaderboard.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Rules.lua"))("DuelElo", ns)
local Ladder, Rules = ns.Ladder, ns.Rules

local function fixture()
    DuelEloLadderData = nil
    dofile("tests/fixtures/ladder_us.lua")
    local data = DuelEloLadderData
    DuelEloLadderData = nil
    return data
end

test("entries parse into rating, rank, tier, badges and the ban flag", function()
    local d = fixture()
    eq(Ladder.Entry(d, 1, "Ashvale-Sargeras"),
        { rating = 1834, rank = 2, tierKey = "ELITE", badges = { "S1E", "FD", "T10" }, banned = false })
    eq(Ladder.Entry(d, 1, "Cheater-Illidan"), { rating = 1700, tierKey = "DUELIST", badges = {}, banned = true })
    eq(Ladder.Entry(d, 1, "Broken-Realm"), nil, "malformed entries are ignored")
    eq(Ladder.Entry(d, 1, "Nobody-Here"), nil)
    eq(Ladder.Entry(d, 3, "Ashvale-Sargeras"), nil, "other region")
    eq(Ladder.Entry(nil, 1, "Ashvale-Sargeras"), nil)
end)

test("confirmed matches: listed ids only, per region; History marks ranked ones verified", function()
    local d = fixture()
    eq(Ladder.Confirmed(d, 1, "123:456"), true)
    eq(Ladder.Confirmed(d, 1, "100000:200000"), true)
    eq(Ladder.Confirmed(d, 1, "789:12"), true)
    eq(Ladder.Confirmed(d, 1, "999:999"), false)
    eq(Ladder.Confirmed(d, 1, "123"), false, "whole ids only")
    eq(Ladder.Confirmed(d, 1, "bad#id"), false, "malformed tokens never match")
    eq(Ladder.Confirmed(d, 3, "123:456"), false, "other region")
    eq(Ladder.Confirmed(nil, 1, "123:456"), false)
    eq(Ladder.Confirmed(d, 1, nil), false)
    eq(Ladder.Verified(d, 1, { ranked = true, match = "123:456" }), true)
    eq(Ladder.Verified(d, 1, { ranked = false, match = "123:456" }), false, "casual duels are never verified")
    eq(Ladder.Verified(d, 1, { ranked = true }), false)
    eq(Ladder.Verified(d, 1, nil), false)
    -- a newer data file replaces the list
    d[1].confirmed = "999:999"
    eq(Ladder.Confirmed(d, 1, "999:999"), true)
    eq(Ladder.Confirmed(d, 1, "123:456"), false)
    d[1].confirmed = nil
    eq(Ladder.Confirmed(d, 1, "999:999"), false, "older data files have no list")
end)

test("the Official view lists ranked players first, by rank, with markers", function()
    local list = Ladder.Build(fixture(), 1)
    local names = {}
    for i, e in ipairs(list) do names[i] = e.name end
    eq(names, { "Thrall-Area52", "Ashvale-Sargeras", "Jaina-Area52", "Cheater-Illidan", "Newbie-Sargeras" })
    eq(list[1].marker, "FIRST")
    eq(list[2].marker, "GOLD")
    eq(list[4].marker, nil)
    eq(Ladder.Build(nil, 1), {})
end)

test("badge names", function()
    eq(Ladder.BadgeName("S1E"), "Season 1 Elite")
    eq(Ladder.BadgeName("S12D"), "Season 12 Duelist")
    eq(Ladder.BadgeName("FD"), "Founding Duelist")
    eq(Ladder.BadgeName("C1"), "Champion")
    eq(Ladder.BadgeName("XYZ"), "XYZ")
end)

test("ladder bans feed the ranked rules", function()
    local d = fixture()
    eq(Rules.LadderBanned(d, 1, "Cheater-Illidan"), true)
    eq(Rules.LadderBanned(d, 1, "Thrall-Area52"), false)
end)

---------------------------------------------------------------------------
-- In the (fake) client
---------------------------------------------------------------------------

local function client(withLadder)
    local env = Wow.new()
    local loaded = {}
    C_AddOns = { LoadAddOn = function(name)
        loaded[#loaded + 1] = name
        if withLadder and name == "DuelElo_Ladder" then dofile("tests/fixtures/ladder_us.lua") end
        return withLadder
    end }
    DuelEloLadderData = nil
    local events = {}
    env.load()
    env.ns.Listen(function(event) events[#events + 1] = event end)
    env.fire("ADDON_LOADED", "DuelElo")
    env.fire("PLAYER_LOGIN")
    return env, loaded, events
end

test("the ladder addon is loaded at login when installed", function()
    local env, loaded, events = client(true)
    eq(loaded, { "DuelElo_Ladder" })
    local fired = false
    for _, e in ipairs(events) do if e == "LADDER_LOADED" then fired = true end end
    ok(fired)
    eq(env.ns.OfficialEntry().rating, 1834)
    eq(env.ns.OfficialEntry("Thrall-Area52").rank, 1)
    C_AddOns, DuelEloLadderData = nil, nil
end)

test("without the ladder addon nothing changes", function()
    local env, _, events = client(false)
    for _, e in ipairs(events) do ok(e ~= "LADDER_LOADED") end
    eq(env.ns.OfficialEntry(), nil)
    C_AddOns = nil
end)

test("a ladder-banned opponent can't play ranked", function()
    local env = client(true)
    env.fire("DUEL_REQUESTED", "Cheater-Illidan")
    env.addonMsg("Cheater-Illidan", "H~2~t1~C~1700~40~K~ROGUE~25~15~~~~30~0")
    eq(env.lastSent("R~").msg, "R~t1~0~B")
    C_AddOns, DuelEloLadderData = nil, nil
end)

test("unit tooltips show official rank, badges and bans", function()
    local env = client(true)
    Stub.install(env)
    Stub.load(env, "UI/Tooltip.lua")
    local lines = env.ns.TooltipLines("Ashvale-Sargeras")
    eq(lines[1][1], "DuelElo: Elite  ·  1834  ·  #2")
    eq(lines[2][1], "Season 1 Elite")
    eq(#lines, 4)
    local banned = env.ns.TooltipLines("Cheater-Illidan")
    eq(banned[#banned][1], "Banned from the DuelElo ladder")
    eq(env.ns.TooltipLines("Nobody-Here"), {})
    C_AddOns, DuelEloLadderData = nil, nil
end)
