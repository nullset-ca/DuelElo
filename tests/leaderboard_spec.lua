local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Elo.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Leaderboard.lua"))("DuelElo", ns)
local LB = ns.Leaderboard

test("Marker cutoffs", function()
    eq(LB.Marker(1), "FIRST")
    eq(LB.Marker(2), "GOLD")
    eq(LB.Marker(10), "GOLD")
    eq(LB.Marker(11), "SILVER")
    eq(LB.Marker(100), "SILVER")
    eq(LB.Marker(101), nil)
    eq(LB.Marker(nil), nil)
end)

local function player(rating, games) return { rating = rating, games = games or 20 } end

test("Build sorts by rating, then games, then name", function()
    local list = LB.Build({
        ["B-R"] = player(1500, 20),
        ["A-R"] = player(1500, 20),
        ["C-R"] = player(1500, 30),
        ["D-R"] = player(1700),
    })
    local names = {}
    for i, e in ipairs(list) do names[i] = e.name end
    eq(names, { "D-R", "C-R", "A-R", "B-R" })
    eq(list[1].pos, 1)
    eq(list[1].marker, "FIRST")
    eq(list[2].marker, "GOLD")
end)

test("Build excludes players still in placements and junk entries", function()
    local list = LB.Build({
        ["New-R"] = player(1900, 9),
        ["Done-R"] = player(1300, 10),
        ["Bad-R"] = "corrupt",
        ["NoRating-R"] = { games = 50 },
    })
    eq(#list, 1)
    eq(list[1].name, "Done-R")
end)

test("Build uses fresh self data over a stale gossip copy and reports my position", function()
    local list, myPos = LB.Build({
        ["Me-R"] = player(1000),
        ["Other-R"] = player(1400),
    }, { name = "Me-R", rating = 1600, games = 40 })
    eq(#list, 2, "self not duplicated")
    eq(myPos, 1)
    eq(list[1].isMe, true)
    eq(list[1].rating, 1600)
end)

test("Build: unplaced self has no position", function()
    local _, myPos = LB.Build({ ["Other-R"] = player(1400) }, { name = "Me-R", rating = 1600, games = 3 })
    eq(myPos, nil)
end)

test("Build assigns silver to 11..100 and nothing after", function()
    local players = {}
    for i = 1, 120 do players[("P%03d-R"):format(i)] = player(2000 - i) end
    local list = LB.Build(players)
    eq(list[11].marker, "SILVER")
    eq(list[100].marker, "SILVER")
    eq(list[101].marker, nil)
end)
