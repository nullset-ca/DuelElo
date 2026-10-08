-- A DuelEloCharDB as saved by v0.4.x (schema 1, Elo ratings).
return {
    schema = 1,
    duels = {
        { t = 1791000000, opp = "Thrall-Area52", class = "SHAMAN", result = "W", how = "KO",
          ranked = true, oppRating = 1400, before = 1430, after = 1452, delta = 22, match = "1:2" },
        { t = 1791000600, opp = "Jaina-Area52", class = "MAGE", result = "L", how = "FLED" },
    },
    totals = { w = 30, l = 12 },
    byClass = { SHAMAN = { w = 10, l = 2 } },
    byOpp = { ["Thrall-Area52"] = { w = 10, l = 2, last = 1791000000, class = "SHAMAN" } },
    streak = 3, bestStreak = 9,
    rating = 1452, rankedGames = 25, rankedW = 16, rankedL = 9, peak = 1510,
    rankedLog = { ["Thrall-Area52"] = { 1791000000 } },
}
