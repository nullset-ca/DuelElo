local Wow = require("wow")

local function loggedIn(opts)
    local env = Wow.new(opts)
    env.login()
    return env
end

local function last(env) return DuelEloCharDB.duels[#DuelEloCharDB.duels] end

test("fresh install creates SavedVariables on load", function()
    loggedIn()
    eq(DuelEloCharDB.totals, { w = 0, l = 0 })
    eq(DuelEloDB.settings.chatSummary, true)
end)

test("existing SavedVariables are kept", function()
    loggedIn({ charDB = { schema = 1, totals = { w = 7, l = 2 }, duels = {}, streak = 0, bestStreak = 4 } })
    eq(DuelEloCharDB.totals, { w = 7, l = 2 })
    eq(DuelEloCharDB.bestStreak, 4)
end)

test("knockout win vs same-realm player", function()
    local env = loggedIn()
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall in a duel")
    eq(last(env).result, "W")
    eq(last(env).opp, "Thrall-Sargeras")
    eq(last(env).how, "KO")
end)

test("we fled: loss", function()
    local env = loggedIn()
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has fled from Thrall-Area52 in a duel")
    eq(last(env).result, "L")
    eq(last(env).opp, "Thrall-Area52")
    eq(last(env).how, "FLED")
end)

test("they fled: win", function()
    local env = loggedIn()
    env.fire("CHAT_MSG_SYSTEM", "Thrall-Area52 has fled from Ashvale in a duel")
    eq(last(env).result, "W")
    eq(last(env).opp, "Thrall-Area52")
end)

test("our name with realm suffix still counts", function()
    local env = loggedIn()
    env.fire("CHAT_MSG_SYSTEM", "Thrall-Area52 has defeated Ashvale-Sargeras in a duel")
    eq(last(env).result, "L")
end)

test("other people's duels are ignored", function()
    local env = loggedIn()
    env.fire("CHAT_MSG_SYSTEM", "Jaina has defeated Thrall in a duel")
    eq(#DuelEloCharDB.duels, 0)
end)

test("same name on another realm is not us", function()
    local env = loggedIn()
    env.fire("CHAT_MSG_SYSTEM", "Ashvale-Area52 has defeated Thrall in a duel")
    eq(#DuelEloCharDB.duels, 0)
end)

test("unrelated and secret system messages are ignored", function()
    local env = loggedIn()
    env.fire("CHAT_MSG_SYSTEM", "Welcome to World of Warcraft!")
    local msg = "Ashvale has defeated Thrall in a duel"
    env.secrets[msg] = true
    env.fire("CHAT_MSG_SYSTEM", msg)
    eq(#DuelEloCharDB.duels, 0)
end)

test("messages before PLAYER_LOGIN are ignored without erroring", function()
    local env = Wow.new()
    env.load()
    env.fire("ADDON_LOADED", "DuelElo")
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall in a duel")
    eq(#DuelEloCharDB.duels, 0)
end)

test("ADDON_LOADED for other addons does not init our db", function()
    local env = Wow.new()
    env.load()
    env.fire("ADDON_LOADED", "SomeOtherAddon")
    eq(DuelEloCharDB, nil)
end)

test("class comes from the target at result time", function()
    local env = loggedIn()
    env.units.target = { name = "Thrall", class = "SHAMAN" }
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall in a duel")
    eq(last(env).class, "SHAMAN")
    eq(DuelEloCharDB.byClass.SHAMAN, { w = 1, l = 0 })
end)

test("class comes from a nameplate", function()
    local env = loggedIn()
    env.units.nameplate7 = { name = "Thrall", realm = "Area52", class = "SHAMAN" }
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall-Area52 in a duel")
    eq(last(env).class, "SHAMAN")
end)

test("class is remembered from the duel request", function()
    local env = loggedIn()
    env.units.target = { name = "Thrall", class = "SHAMAN" }
    env.fire("DUEL_REQUESTED", "Thrall")
    env.units.target = nil
    env.fire("CHAT_MSG_SYSTEM", "Thrall has defeated Ashvale in a duel")
    eq(last(env).class, "SHAMAN")
end)

test("class is remembered when we start the duel", function()
    local env = loggedIn()
    env.units.target = { name = "Jaina", realm = "Area52", class = "MAGE" }
    StartDuel("target")
    env.units.target = nil
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Jaina-Area52 in a duel")
    eq(last(env).class, "MAGE")
end)

test("a stale hint for a different opponent is not used", function()
    local env = loggedIn()
    env.units.target = { name = "Jaina", class = "MAGE" }
    StartDuel("target")
    env.units.target = nil
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall in a duel")
    eq(last(env).class, nil)
end)

test("unknown class is recorded as nil", function()
    local env = loggedIn()
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall in a duel")
    eq(last(env).class, nil)
end)

test("chat summary is printed and can be toggled off", function()
    local env = loggedIn()
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall in a duel")
    ok(env.lastPrint():find("Victory"), "victory message")
    ok(env.lastPrint():find("vs Thrall%."), "same-realm name shown without realm")
    ok(env.lastPrint():find("1%-0"), "record shown")
    env.slash("chat")
    local n = #env.printed
    env.fire("CHAT_MSG_SYSTEM", "Thrall has defeated Ashvale in a duel")
    eq(#env.printed, n, "nothing printed when off")
    eq(DuelEloDB.settings.chatSummary, false)
end)

test("listeners receive DUEL_RECORDED and errors in one don't block others", function()
    local env = Wow.new()
    local ns = env.load()
    local got
    geterrorhandler = function() return function() end end
    ns.Listen(function() error("boom") end)
    ns.Listen(function(event, entry) if event == "DUEL_RECORDED" then got = entry end end)
    env.fire("ADDON_LOADED", "DuelElo")
    env.fire("PLAYER_LOGIN")
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall in a duel")
    eq(got and got.opp, "Thrall-Sargeras")
end)

test("demo mode shows sample data without touching saved data", function()
    local env = loggedIn()
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall in a duel")
    env.slash("dev on")
    env.slash("demo")
    ok(env.ns.ViewData() ~= DuelEloCharDB, "view switched to demo")
    eq(#env.ns.ViewData().duels, 40)
    eq(DuelEloCharDB.totals, { w = 1, l = 0 }, "saved data untouched")
    env.fire("CHAT_MSG_SYSTEM", "Thrall has defeated Ashvale in a duel")
    eq(DuelEloCharDB.totals, { w = 1, l = 1 }, "real duels still saved during demo")
    eq(#env.ns.ViewData().duels, 40)
    env.slash("demo")
    ok(env.ns.ViewData() == DuelEloCharDB, "view back to real data")
end)

test("size command clamps and saves the results scale", function()
    local env = loggedIn()
    env.slash("size 120")
    eq(DuelEloDB.settings.resultsScale, 1.2)
    env.slash("size 5")
    eq(DuelEloDB.settings.resultsScale, 0.5)
    env.slash("size 999")
    eq(DuelEloDB.settings.resultsScale, 1.5)
    env.slash("size abc")
    eq(DuelEloDB.settings.resultsScale, 1.5, "garbage leaves it unchanged")
end)

test("sound command previews and assigns sounds", function()
    local env = loggedIn()
    local played = {}
    env.ns.SOUND_CANDIDATES = { { 111, "One" }, { 222, "Two" } }
    env.ns.PlaySoundKit = function(id) played[#played + 1] = id end
    env.slash("sound 2")
    eq(played, { 222 })
    env.slash("sound promote 1")
    eq(DuelEloDB.settings.sounds.promote, 111)
    env.slash("sound promote 9")
    eq(DuelEloDB.settings.sounds.promote, 111, "out of range ignored")
    env.slash("sound bogus 1")
    eq(DuelEloDB.settings.sounds.bogus, nil)
end)

test("old account settings gain new defaults", function()
    loggedIn({ db = { schema = 1, settings = { chatSummary = false } } })
    eq(DuelEloDB.settings.chatSummary, false)
    eq(DuelEloDB.settings.resultsScale, 0.8)
    eq(type(DuelEloDB.settings.sounds), "table")
end)

test("leaderboard: real data uses saved players, demo uses fake ones", function()
    local env = loggedIn()
    DuelEloDB.players["Rival-Area52"] = { rating = 1500, games = 20 }
    eq(env.ns.ViewPlayers()["Rival-Area52"].rating, 1500)
    local me = env.ns.MyLeaderboardEntry()
    eq(me.name, "Ashvale-Sargeras")
    eq(me.class, "PALADIN")
    eq(me.rating, 1200)
    env.slash("dev on")
    env.slash("demo")
    local list, myPos = env.ns.Leaderboard.Build(env.ns.ViewPlayers(), env.ns.MyLeaderboardEntry())
    eq(#list, 151, "150 demo players + me")
    local forever = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true,
        MAGE = true, WARLOCK = true, DRUID = true }
    for name, p in pairs(env.ns.ViewPlayers()) do
        ok(forever[p.class], ("demo player %s has a WoW Forever class (%s)"):format(name, tostring(p.class)))
    end
    ok(myPos and myPos > 1, "demo me is on the board")
    eq(env.ns.ViewPlayers()["Rival-Area52"], nil, "real players hidden in demo")
    env.slash("demo")
    eq(env.ns.ViewPlayers()["Rival-Area52"].rating, 1500)
end)

---------------------------------------------------------------------------
-- Ranked duels end to end (we play the opponent's client by hand)
---------------------------------------------------------------------------

local OPP = "Thrall-Area52"
-- The opponent's protocol 2 hello: level 30, ready, optional spec/item level.
local function oppHello(role, spec, ilvl)
    return ("H~2~t1~%s~1500~40~K~SHAMAN~25~15~%s~%s~~30~0"):format(role, spec or "", ilvl or "")
end

local function field(msg, i)
    local f = {}
    for x in (msg .. "~"):gmatch("(.-)~") do f[#f + 1] = x end
    return f[i]
end

-- Opponent challenges us; both agree; we accept; result `msg` arrives.
local function rankedAsChallenged(env, resultMsg)
    env.fire("DUEL_REQUESTED", OPP)
    local hello = env.lastSent("H~")
    env.addonMsg(OPP, oppHello("C"))
    env.ns.engine:Consent(true)
    env.addonMsg(OPP, ("R~%s~1~"):format(field(hello.msg, 3)))
    AcceptDuel()
    env.fire("CHAT_MSG_SYSTEM", resultMsg)
    return hello
end

test("ranked: challenged side, full flow, win", function()
    local env = loggedIn()
    local hello = rankedAsChallenged(env, "Ashvale has defeated Thrall-Area52 in a duel")
    eq(hello.target, OPP)
    eq(field(hello.msg, 4), "D")
    eq(env.lastSent("R~").msg, "R~t1~1~")
    eq(env.lastSent("L~").msg, "L~t1~R~0~0")
    local e = last(env)
    eq(e.ranked, true)
    eq(e.oppRating, 1500)
    eq(DuelEloCharDB.rating, 1200 + e.delta)
    ok(e.delta > 20, "upset win during placements pays more than 20")
    eq(DuelEloCharDB.rankedGames, 1)
    eq(DuelEloCharDB.rankedW, 1)
    local p = env.lastSent("P~")
    eq(p.target, OPP, "new stats shared with the opponent")
    eq(field(p.msg, 2), tostring(DuelEloCharDB.rating))
end)

test("ranked: challenger side, lock from opponent, loss", function()
    local env = loggedIn()
    env.units.target = { name = "Thrall", realm = "Area52", class = "SHAMAN" }
    StartDuel("target")
    local hello = env.lastSent("H~")
    eq(field(hello.msg, 4), "C")
    env.addonMsg(OPP, oppHello("D"))
    env.ns.engine:Consent(true)
    local nonce = field(hello.msg, 3)
    env.addonMsg(OPP, ("R~%s~1~"):format(nonce))
    env.addonMsg(OPP, ("L~%s~R"):format(nonce))
    env.fire("CHAT_MSG_SYSTEM", "Thrall-Area52 has defeated Ashvale in a duel")
    eq(last(env).ranked, true)
    ok(DuelEloCharDB.rating < 1200)
    eq(DuelEloCharDB.rankedL, 1)
end)

test("ranked: opponent without the addon stays casual", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    AcceptDuel()
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall-Area52 in a duel")
    eq(last(env).ranked, nil)
    eq(DuelEloCharDB.rating, 1200)
    eq(env.lastSent("P~"), nil)
end)

test("ranked: declining keeps it casual", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    local hello = env.lastSent("H~")
    env.addonMsg(OPP, oppHello("C"))
    env.ns.engine:Consent(false)
    env.addonMsg(OPP, ("R~%s~1~"):format(field(hello.msg, 3)))
    AcceptDuel()
    eq(env.lastSent("L~").msg, "L~t1~C~0~0")
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall-Area52 in a duel")
    eq(last(env).ranked, nil)
end)

test("ranked: countdown message locks when the AcceptDuel hook never fires", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    local hello = env.lastSent("H~")
    env.addonMsg(OPP, oppHello("C"))
    env.ns.engine:Consent(true)
    env.addonMsg(OPP, ("R~%s~1~"):format(field(hello.msg, 3)))
    env.fire("CHAT_MSG_SYSTEM", "Duel starting: 3")
    eq(env.lastSent("L~").msg, "L~t1~R~0~0")
    env.fire("CHAT_MSG_SYSTEM", "Duel starting: 2")
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall-Area52 in a duel")
    eq(last(env).ranked, true)
    eq(#DuelEloCharDB.duels, 1, "countdown lines are not duels")
end)

-- Replays of the real 2026-10-07 duel logs (same-realm names, both event orders).
test("real log replay: challenged side, winner message before DUEL_FINISHED", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", "Duskmire")
    for i = 3, 1, -1 do env.fire("CHAT_MSG_SYSTEM", "Duel starting: " .. i) end
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Duskmire in a duel")
    env.fire("DUEL_FINISHED")
    eq(last(env).opp, "Duskmire-Sargeras")
    eq(last(env).result, "W")
end)

test("real log replay: challenger side, DUEL_FINISHED before the winner message", function()
    local env = loggedIn({ units = { player = { name = "Duskmire", realm = "Sargeras", class = "PRIEST" } } })
    env.units.target = { name = "Ashvale", class = "HUNTER" }
    StartDuel("target")
    for i = 3, 1, -1 do env.fire("CHAT_MSG_SYSTEM", "Duel starting: " .. i) end
    env.fire("DUEL_FINISHED")
    env.clock = env.clock + 1
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Duskmire in a duel")
    eq(last(env).opp, "Ashvale-Sargeras")
    eq(last(env).result, "L")
    eq(last(env).class, "HUNTER")
end)

test("ranked preference: always answers automatically, bad values ignored", function()
    local env = loggedIn()
    env.slash("ranked always")
    eq(DuelEloDB.settings.rankedPref, "always")
    env.slash("ranked sometimes")
    eq(DuelEloDB.settings.rankedPref, "always")
    env.fire("DUEL_REQUESTED", OPP)
    env.addonMsg(OPP, oppHello("C"))
    eq(env.lastSent("R~").msg, "R~t1~1~")
end)

test("anti-farm: 4th ranked duel vs the same player in a day is declined", function()
    local env = loggedIn()
    for _ = 1, 3 do
        rankedAsChallenged(env, "Ashvale has defeated Thrall-Area52 in a duel")
        eq(last(env).ranked, true)
    end
    env.fire("DUEL_REQUESTED", OPP)
    env.addonMsg(OPP, oppHello("C"))
    eq(env.lastSent("R~").msg, "R~t1~0~F")
    eq(env.ns.engine:Consent(true), false)
end)

test("players met through handshakes land on the leaderboard", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    env.addonMsg(OPP, oppHello("C"))
    local p = DuelEloDB.players[OPP]
    eq(p.rating, 1500)
    eq(p.class, "SHAMAN")
    eq(p.w, 25)
end)

test("guild: stats shared after login, guildmates' stats stored, own echo ignored", function()
    local env = Wow.new()
    env.login()
    env.inGuild = true
    env.runTimers()
    local p = env.lastSent("P~")
    eq(p.channel, "GUILD")
    env.addonMsg("Jaina-Sargeras", "P~1650~30~MAGE~20~10", "GUILD")
    eq(DuelEloDB.players["Jaina-Sargeras"].rating, 1650)
    env.addonMsg("Ashvale-Sargeras", "P~2500~30~PALADIN~20~10", "GUILD")
    eq(DuelEloDB.players["Ashvale-Sargeras"], nil, "our own broadcast is not a player entry")
end)

test("not in a guild: nothing sent to GUILD", function()
    local env = loggedIn()
    env.runTimers()
    for _, s in ipairs(env.sent) do ok(s.channel ~= "GUILD") end
end)

test("addon messages with other prefixes or secret values are ignored", function()
    local env = loggedIn()
    env.fire("CHAT_MSG_ADDON", "OtherAddon", "P~1650~30~MAGE~20~10", "GUILD", "Jaina-Sargeras")
    env.secrets["Jaina-Sargeras"] = true
    env.addonMsg("Jaina-Sargeras", "P~1650~30~MAGE~20~10", "GUILD")
    eq(DuelEloDB.players["Jaina-Sargeras"], nil)
end)

test("prefix registered on load", function()
    local env = loggedIn()
    eq(env.prefix, "DuelElo")
end)

---------------------------------------------------------------------------
-- Realm-wide channel and richer records (layer 1)
---------------------------------------------------------------------------

-- Run timers until the queue is empty (timers can schedule more timers).
local function settle(env, rounds)
    for _ = 1, rounds or 3 do env.runTimers() end
end

test("channel: joined after login, hidden from chat, stats announced", function()
    local env = loggedIn()
    eq(env.channels.DuelEloLadder, nil, "not joined immediately")
    env.runTimers()  -- guild share + channel join
    eq(env.channels.DuelEloLadder, 5)
    eq(env.removedFrom, { "1:DuelEloLadder", "2:DuelEloLadder" })
    env.runTimers()  -- first announcement
    local p = env.lastSent("P~")
    eq(p.channel, "CHANNEL")
    eq(p.target, 5)
end)

test("channel: never takes /1 when the game rejoined it before General", function()
    -- The game rejoins custom channels at login, sometimes before General and Trade.
    local env = loggedIn({ channels = { DuelEloLadder = 1 } })
    env.gameJoins("General")
    env.gameJoins("Trade")
    settle(env)
    eq(env.channels, { General = 1, Trade = 2, DuelEloLadder = 3 })
    env.gameJoins("LocalDefense")
    settle(env)
    eq(env.channels.LocalDefense, 3)
    eq(env.channels.DuelEloLadder, 4)
    env.ns.Comm.ShareStats(nil)
    eq(env.lastSent("P~").target, 4, "announces on the channel's current number")
end)

test("channel: joining with gaps in the numbers still goes last", function()
    local env = loggedIn({ channels = { General = 1, LookingForGroup = 4 } })
    settle(env)
    eq(env.channels.General, 1)
    eq(env.channels.DuelEloLadder, 4, "behind every other channel")
end)

test("channel: left at logout so the game can't rejoin it early", function()
    local env = loggedIn()
    settle(env)
    eq(env.channels.DuelEloLadder, 5)
    env.fire("PLAYER_LOGOUT")
    eq(env.channels.DuelEloLadder, nil)
end)

test("channel: opted-out players leave a channel the game rejoined", function()
    local env = loggedIn({ db = { schema = 2, settings = { shareChannel = false } },
        channels = { DuelEloLadder = 1, General = 2 } })
    settle(env)
    eq(env.channels.DuelEloLadder, nil)
end)

test("channel: join/leave notices for our channel are filtered", function()
    local env = loggedIn()
    local filter = env.filters.CHAT_MSG_CHANNEL_NOTICE
    eq(filter(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", "", "", "5. DuelEloLadder"), true)
    eq(filter(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", "", "", "1. General"), false)
end)

test("channel: strangers' stats are stored as self-reported", function()
    local env = loggedIn()
    env.addonMsg("Jaina-Area52", "P~1650~30~MAGE~20~10", "CHANNEL")
    local p = DuelEloDB.players["Jaina-Area52"]
    eq(p.rating, 1650)
    eq(p.source, "channel")
    local list = env.ns.Leaderboard.Build(DuelEloDB.players, nil, time())
    eq(list[1].verified, false)
end)

test("channel: a duel upgrades a player to verified and it sticks", function()
    local env = loggedIn()
    env.addonMsg(OPP, "P~1500~40~SHAMAN~25~15", "CHANNEL")
    eq(DuelEloDB.players[OPP].source, "channel")
    env.fire("DUEL_REQUESTED", OPP)
    env.addonMsg(OPP, oppHello("C"))
    eq(DuelEloDB.players[OPP].source, "met")
    env.clock = env.clock + 60
    env.addonMsg(OPP, "P~1510~41~SHAMAN~26~15", "CHANNEL")
    eq(DuelEloDB.players[OPP].source, "met")
    eq(DuelEloDB.players[OPP].rating, 1510, "newer numbers still taken")
end)

test("channel: per-player rate limit drops floods", function()
    local env = loggedIn()
    env.addonMsg("Jaina-Area52", "P~1650~30~MAGE~20~10", "CHANNEL")
    env.addonMsg("Jaina-Area52", "P~4999~30~MAGE~20~10", "CHANNEL")
    eq(DuelEloDB.players["Jaina-Area52"].rating, 1650)
    env.clock = env.clock + 11
    env.addonMsg("Jaina-Area52", "P~1660~31~MAGE~21~10", "CHANNEL")
    eq(DuelEloDB.players["Jaina-Area52"].rating, 1660)
end)

test("channel: opting out leaves and stops announcing", function()
    local env = loggedIn()
    settle(env)
    eq(env.channels.DuelEloLadder, 5)
    env.slash("channel off")
    eq(DuelEloDB.settings.shareChannel, false)
    eq(env.channels.DuelEloLadder, nil)
    env.sent = {}
    settle(env)
    for _, s in ipairs(env.sent) do ok(s.channel ~= "CHANNEL") end
end)

test("channel: opted-out players never join", function()
    local env = loggedIn({ db = { schema = 1, settings = { shareChannel = false } } })
    settle(env)
    eq(env.channels.DuelEloLadder, nil)
end)

test("leaderboard: players unseen for 30+ days drop off", function()
    local env = loggedIn()
    local now = time()
    DuelEloDB.players["Old-Realm"] = { rating = 1900, games = 50, seen = now - 31 * 86400, source = "channel" }
    DuelEloDB.players["New-Realm"] = { rating = 1800, games = 50, seen = now - 86400, source = "channel" }
    local list = env.ns.Leaderboard.Build(DuelEloDB.players, nil, now)
    eq(#list, 1)
    eq(list[1].name, "New-Realm")
end)

test("duel records carry match id, zone, duration, specs and item levels", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    local hello = env.lastSent("H~")
    eq(field(hello.msg, 11), "253", "our spec in the hello")
    eq(field(hello.msg, 12), "612", "our equipped item level in the hello")
    env.addonMsg(OPP, oppHello("C", 262, 605))
    env.fire("CHAT_MSG_SYSTEM", "Duel starting: 3")
    env.clock = env.clock + 3 + 42
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall-Area52 in a duel")
    local e = last(env)
    eq(e.match, "t1:" .. field(hello.msg, 3), "challenger nonce first")
    eq(e.zone, 84)
    eq(e.secs, 42)
    eq(e.spec, 253)
    eq(e.ilvl, 612)
    eq(e.oppSpec, 262)
    eq(e.oppIlvl, 605)
    eq(e.class, "SHAMAN", "class learned from the handshake")
    eq(DuelEloDB.region, 1)
end)

test("casual duel vs a player without the addon still records zone and duration", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    env.fire("CHAT_MSG_SYSTEM", "Duel starting: 3")
    env.clock = env.clock + 20
    env.fire("CHAT_MSG_SYSTEM", "Thrall-Area52 has defeated Ashvale in a duel")
    local e = last(env)
    eq(e.match, nil)
    eq(e.zone, 84)
    eq(e.secs, 17)
end)

test("welcome message only on the first ever login", function()
    local env = loggedIn()
    local hello = 0
    for _, line in ipairs(env.printed) do if line:find("Thanks for installing") then hello = hello + 1 end end
    eq(hello, 1)
    eq(DuelEloDB.welcomed, true)
    local env2 = loggedIn({ db = DuelEloDB })
    for _, line in ipairs(env2.printed) do ok(not line:find("Thanks for installing")) end
end)

test("welcome message links the Discord", function()
    local env = loggedIn()
    local found = false
    for _, line in ipairs(env.printed) do
        if line:find("|Haddon:DuelElo:discord|h", 1, true) then found = true end
    end
    ok(found)
end)

test("/duelelo discord shows the invite in a copy box", function()
    local env = loggedIn()
    local shown
    env.ns.ShowCopyBox = function(_, _, value) shown = value end
    env.slash("discord")
    eq(shown, env.ns.DISCORD_URL)
    ok(shown:find("^https://discord%.gg/"))
end)

test("clicking the chat link opens the invite", function()
    local env = loggedIn()
    local shown
    env.ns.ShowCopyBox = function(_, _, value) shown = value end
    SetItemRef("addon:DuelElo:discord", "[Discord]", "LeftButton")
    eq(shown, env.ns.DISCORD_URL)
    shown = nil
    SetItemRef("player:Thrall", "[Thrall]", "LeftButton")
    eq(shown, nil)
end)

test("Discord nudge appears once, after the 10th duel", function()
    local env = loggedIn()
    local function nudges()
        local n = 0
        for _, line in ipairs(env.printed) do if line:find("Enjoying DuelElo") then n = n + 1 end end
        return n
    end
    for i = 1, 9 do env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall" .. i .. " in a duel") end
    eq(nudges(), 0)
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall10 in a duel")
    eq(nudges(), 1)
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall11 in a duel")
    eq(nudges(), 1)
    eq(DuelEloDB.discordNudged, true)
end)

test("unknown commands get a hint instead of opening the window", function()
    local env = loggedIn()
    local opened = 0
    env.ns.ToggleMain = function() opened = opened + 1 end
    env.slash("frobnicate")
    eq(opened, 0)
    ok(env.lastPrint():find("Unknown command"))
end)

test("SetChannelSharing joins and leaves", function()
    local env = loggedIn()
    env.ns.SetChannelSharing(true)
    eq(env.channels.DuelEloLadder, 5)
    env.ns.SetChannelSharing(false)
    eq(env.channels.DuelEloLadder, nil)
    eq(DuelEloDB.settings.shareChannel, false)
end)

test("stale players are pruned at login", function()
    local env = loggedIn({ db = { schema = 1, players = {
        ["Gone-R"] = { rating = 1500, games = 20, seen = time() - 100 * 86400 },
        ["Here-R"] = { rating = 1500, games = 20, seen = time() - 86400 },
    } } })
    eq(DuelEloDB.players["Gone-R"], nil)
    ok(DuelEloDB.players["Here-R"])
end)

test("nonces are unique per duel, non-zero and protocol-safe (regression: WoW gave 0:0)", function()
    local env = loggedIn()
    local orig = math.random
    math.random = function() return 0 end   -- simulate the broken in-game random
    local seen = {}
    for _ = 1, 5 do
        env.fire("DUEL_REQUESTED", OPP)
        local n = field(env.lastSent("H~").msg, 3)
        ok(n ~= "0" and n ~= "", "non-trivial nonce")
        ok(#n <= 16 and not n:find("~", 1, true), "fits the protocol")
        ok(not seen[n], "unique: " .. n)
        seen[n] = true
    end
    math.random = orig
end)

test("item level of 0 is not recorded", function()
    local env = loggedIn()
    GetAverageItemLevel = function() return 0, 0 end
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall-Area52 in a duel")
    eq(last(env).ilvl, nil)
end)

test("slash command opens the window when UI is loaded", function()
    local env = loggedIn()
    local opened = 0
    env.ns.ToggleMain = function() opened = opened + 1 end
    env.slash("")
    DuelElo_OnAddonCompartmentClick()
    eq(opened, 2)
end)

---------------------------------------------------------------------------
-- Protocol v2 on the client: readiness polling, eligibility, strict
---------------------------------------------------------------------------

test("our hello carries level and readiness", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    local hello = env.lastSent("H~")
    eq(field(hello.msg, 2), "2")
    eq(field(hello.msg, 13), env.ns.Crypto.Fingerprint(DuelEloCharDB.key.secret), "our key fingerprint")
    eq(field(hello.msg, 14), "30")
    eq(field(hello.msg, 15), "0")
end)

test("readiness is polled only while the decision is open, changes sent with Y", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    eq(env.liveTickers(), 0, "no poll before the opponent's hello")
    env.addonMsg(OPP, oppHello("C"))
    eq(env.liveTickers(), 1)
    env.vitals.health = 50
    env.tick()
    eq(env.lastSent("Y~").msg, "Y~t1~1")
    eq(env.lastSent("Y~").target, OPP)
    AcceptDuel()
    eq(env.liveTickers(), 0, "polling stops at the lock")
end)

test("not ready at accept: lock is casual even though both agreed", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    local hello = env.lastSent("H~")
    env.addonMsg(OPP, oppHello("C"))
    env.ns.engine:Consent(true)
    env.addonMsg(OPP, ("R~%s~1~"):format(field(hello.msg, 3)))
    env.vitals.combat = true
    AcceptDuel()
    eq(env.lastSent("L~").msg, "L~t1~C~0~32")
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall-Area52 in a duel")
    eq(last(env).ranked, nil)
end)

test("opponent not ready (Y): lock is casual", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    local hello = env.lastSent("H~")
    local nonce = field(hello.msg, 3)
    env.addonMsg(OPP, oppHello("C"))
    env.ns.engine:Consent(true)
    env.addonMsg(OPP, ("R~%s~1~"):format(nonce))
    env.addonMsg(OPP, ("Y~%s~16"):format(nonce))  -- banned buff
    AcceptDuel()
    eq(env.lastSent("L~").msg, "L~t1~C~16~0")
end)

test("strict on/off command and setting", function()
    local env = loggedIn()
    eq(DuelEloDB.settings.strict, false)
    env.slash("strict on")
    eq(DuelEloDB.settings.strict, true)
    ok(env.lastPrint():find("on", 1, true))
    env.slash("strict maybe")
    eq(DuelEloDB.settings.strict, true)
    env.slash("strict off")
    eq(DuelEloDB.settings.strict, false)
end)

test("/duelelo cooldowns is the new name for strict", function()
    local env = loggedIn()
    env.slash("cooldowns on")
    eq(DuelEloDB.settings.strict, true)
    ok(env.lastPrint():find("Wait for cooldowns", 1, true))
    env.slash("cooldowns off")
    eq(DuelEloDB.settings.strict, false)
end)

test("strict: our cooldown down refuses consent", function()
    local env = loggedIn()
    env.slash("strict on")
    env.vitals.trinkets[13] = { 900, 120, 1 }
    env.fire("DUEL_REQUESTED", OPP)
    env.addonMsg(OPP, oppHello("C"))
    eq(env.ns.engine:Consent(true), false)
end)

test("different level: declined automatically with reason L", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    env.addonMsg(OPP, (oppHello("C"):gsub("~30~0$", "~31~0")))
    eq(env.lastSent("R~").msg, "R~t1~0~L")
    eq(env.ns.engine:Consent(true), false)
end)

test("one of our own characters: declined with reason A", function()
    local env = loggedIn({ db = { schema = 1, characters = { [OPP] = { class = "SHAMAN", level = 30 } } } })
    env.fire("DUEL_REQUESTED", OPP)
    env.addonMsg(OPP, oppHello("C"))
    eq(env.lastSent("R~").msg, "R~t1~0~A")
end)

test("ladder-banned opponent: declined with reason B", function()
    local env = loggedIn()
    DuelEloLadderData = { [1] = { players = { [OPP] = "1500|10|DUELIST||1" } } }
    env.fire("DUEL_REQUESTED", OPP)
    env.addonMsg(OPP, oppHello("C"))
    DuelEloLadderData = nil
    eq(env.lastSent("R~").msg, "R~t1~0~B")
end)

test("outdated opponent (protocol 1): casual, no reply, stats kept", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    env.addonMsg(OPP, "H~1~t1~C~1500~40~K~SHAMAN~25~15")
    eq(env.ns.engine.session.status, "outdated")
    eq(env.lastSent("R~"), nil)
    eq(DuelEloDB.players[OPP].rating, 1500)
    AcceptDuel()
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall-Area52 in a duel")
    eq(last(env).ranked, nil)
end)

---------------------------------------------------------------------------
-- Dev mode
---------------------------------------------------------------------------

test("dev commands are refused while dev mode is off", function()
    local env = loggedIn()
    eq(DuelEloDB.dev, false)
    for _, cmd in ipairs({ "demo", "test promo", "art noart", "debug" }) do
        env.printed = {}
        env.slash(cmd)
        ok(env.lastPrint():find("Dev mode is off", 1, true), cmd)
        eq(#env.printed, 1, cmd .. " did nothing else")
    end
    eq(env.ns.demo, nil)
    eq(env.ns.debugOn, false)
end)

test("dev on enables dev commands and is saved", function()
    local env = loggedIn()
    env.slash("dev on")
    eq(DuelEloDB.dev, true)
    env.slash("debug")
    eq(env.ns.debugOn, true)
    env.slash("demo")
    ok(env.ns.demo, "demo on")
end)

test("dev off turns debug and demo off again", function()
    local env = loggedIn()
    env.slash("dev on")
    env.slash("debug")
    env.slash("demo")
    env.slash("dev off")
    eq(DuelEloDB.dev, false)
    eq(env.ns.debugOn, false)
    eq(env.ns.demo, nil)
    ok(env.ns.ViewData() == DuelEloCharDB)
end)

test("help hides dev commands unless dev mode is on", function()
    local env = loggedIn()
    local function helpText()
        env.printed = {}
        env.slash("help")
        return table.concat(env.printed, "\n")
    end
    ok(not helpText():find("demo", 1, true))
    env.slash("dev on")
    ok(helpText():find("demo", 1, true))
end)

test("results screen size and position commands work without dev mode", function()
    local env = loggedIn()
    env.slash("size 120")
    eq(DuelEloDB.settings.resultsScale, 1.2)
    env.slash("resetpos")
    ok(env.lastPrint():find("reset", 1, true))
end)

---------------------------------------------------------------------------
-- Rank widget settings
---------------------------------------------------------------------------

test("widget settings: defaults on a fresh install", function()
    loggedIn()
    local w = DuelEloDB.settings.widget
    eq({ w.shown, w.preset, w.trend, w.period, w.recent, w.scale, w.locked }, { false, "compact", "number", "session", 5, 1, false })
end)

test("widget commands change and persist settings", function()
    local env = loggedIn()
    local changed = 0
    env.ns.Listen(function(event) if event == "WIDGET_CHANGED" then changed = changed + 1 end end)
    env.slash("widget hide")
    eq(DuelEloDB.settings.widget.shown, false)
    env.slash("widget show")
    env.slash("widget lock")
    eq(DuelEloDB.settings.widget.locked, true)
    env.slash("widget unlock")
    eq(DuelEloDB.settings.widget.locked, false)
    env.slash("widget preset full")
    eq(DuelEloDB.settings.widget.preset, "full")
    env.slash("widget preset giant")
    eq(DuelEloDB.settings.widget.preset, "full", "unknown preset ignored")
    DuelEloDB.settings.widget.pos = { "CENTER", 10, 20 }
    env.slash("widget reset")
    eq(DuelEloDB.settings.widget.pos, nil)
    eq(changed, 6)
end)

test("widget scale and opacity are clamped", function()
    local env = loggedIn()
    env.slash("widget scale 500")
    eq(DuelEloDB.settings.widget.scale, 2)
    env.slash("widget scale 120")
    eq(DuelEloDB.settings.widget.scale, 1.2)
    env.slash("widget opacity 5")
    eq(DuelEloDB.settings.widget.opacity, 0.3)
end)

test("widget settings are validated when loaded", function()
    loggedIn({ db = { schema = 2, settings = { widget = { scale = 9, opacity = -1, preset = "nope" } } } })
    local w = DuelEloDB.settings.widget
    eq({ w.scale, w.opacity, w.preset, w.trend }, { 2, 0.3, "compact", "number" })
end)

test("widget usage is printed for an unknown subcommand", function()
    local env = loggedIn()
    env.slash("widget")
    ok(env.lastPrint():find("preset full", 1, true))
end)

test("session start rating is captured at login", function()
    local env = loggedIn()
    eq(env.ns.sessionStart.rating, 1200)
    ok(env.ns.sessionStart.t)
end)

---------------------------------------------------------------------------
-- Signed statements on the client (B4)
---------------------------------------------------------------------------

local OPP_FP = ("0f"):rep(16)
local OPP_SIG = ("cd"):rep(32)

local function signedHello(role)
    return ("H~2~t1~%s~1500~40~K~SHAMAN~25~15~~~%s~30~0"):format(role, OPP_FP)
end

test("challenged side: signs the challenger's statement and stores both signatures", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    local nonce = field(env.lastSent("H~").msg, 3)
    env.addonMsg(OPP, signedHello("C"))
    env.ns.engine:Consent(true)
    env.addonMsg(OPP, ("R~%s~1~"):format(nonce))
    AcceptDuel()
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall-Area52 in a duel")
    local e = last(env)
    eq(e.statement, nil, "waits for the challenger's times")
    eq(e.fpC, OPP_FP)
    eq(e.fpD, env.ns.myFp)
    local tEnd = GetServerTime()
    env.addonMsg(OPP, ("S~t1:%s~0~%d~%s"):format(nonce, tEnd, OPP_SIG))
    eq(e.sigC, OPP_SIG)
    local S = env.ns.Statement
    ok(S.Verify(DuelEloCharDB.key.secret, e.statement, e.sigD), "our signature")
    eq(env.lastSent("S~").msg, ("S~t1:%s~0~%d~%s"):format(nonce, tEnd, e.sigD))
    local f = S.Parse(e.statement)
    eq({ f.challenger, f.challenged, f.winner, f.cPre, f.dPre, f.level, f.region },
        { OPP, "Ashvale-Sargeras", "D", 1500, 1200, 30, 1 })
end)

test("challenger side: signs first, then stores the opponent's signature", function()
    local env = loggedIn()
    env.units.target = { name = "Thrall", realm = "Area52", class = "SHAMAN" }
    StartDuel("target")
    local nonce = field(env.lastSent("H~").msg, 3)
    env.addonMsg(OPP, signedHello("D"))
    env.ns.engine:Consent(true)
    env.addonMsg(OPP, ("R~%s~1~"):format(nonce))
    env.addonMsg(OPP, ("L~%s~R~0~0"):format(nonce))
    env.fire("CHAT_MSG_SYSTEM", "Duel starting: 3")
    env.fire("CHAT_MSG_SYSTEM", "Thrall-Area52 has defeated Ashvale in a duel")
    local e = last(env)
    ok(e.statement and e.sigC, "signed at once")
    eq(e.fpC, env.ns.myFp)
    local sent = env.lastSent("S~")
    eq(sent.target, OPP)
    local f = env.ns.Statement.Parse(e.statement)
    eq(f.winner, "D")
    env.addonMsg(OPP, ("S~%s:t1~%d~%d~%s"):format(nonce, f.tStart, f.tEnd, OPP_SIG))
    eq(e.sigD, OPP_SIG)
end)

test("challenged side: no challenger signature -> signs its own times when the timer fires", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    local nonce = field(env.lastSent("H~").msg, 3)
    env.addonMsg(OPP, signedHello("C"))
    env.ns.engine:Consent(true)
    env.addonMsg(OPP, ("R~%s~1~"):format(nonce))
    AcceptDuel()
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall-Area52 in a duel")
    eq(env.lastSent("S~"), nil)
    env.runTimers()
    ok(env.lastSent("S~"), "signed after the wait")
    ok(last(env).sigD)
end)

test("casual duels vs addon users carry no statement", function()
    local env = loggedIn()
    env.fire("DUEL_REQUESTED", OPP)
    env.addonMsg(OPP, signedHello("C"))
    AcceptDuel()
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall-Area52 in a duel")
    eq(last(env).statement, nil)
    eq(env.lastSent("S~"), nil)
end)

---------------------------------------------------------------------------
-- Forever-first (SPEC §3.12)
---------------------------------------------------------------------------

test("client flavor from the interface number", function()
    local ns = loggedIn().ns
    eq(ns.FlavorOf(16001), "forever")
    eq(ns.FlavorOf(16999), "forever")
    eq(ns.FlavorOf(120100), "retail")
    eq(ns.FlavorOf(110000), "retail")
    eq(ns.FlavorOf(11507), "unknown")
    eq(ns.FlavorOf(50500), "unknown")
    eq(ns.FlavorOf(nil), "unknown")
    eq(ns.FlavorOf("x"), "unknown")
end)

test("ns.FLAVOR follows the running client", function()
    eq(loggedIn().ns.FLAVOR, "forever")
    eq(loggedIn({ toc = 120100 }).ns.FLAVOR, "retail")
end)

test("the welcome message and help say WoW Forever", function()
    local env = loggedIn()
    local all = table.concat(env.printed, "\n")
    ok(all:find("WoW Forever", 1, true), "welcome")
    env.printed = {}
    env.slash("help")
    ok(env.printed[1]:find("Ranked dueling for WoW Forever", 1, true), "help header")
end)

test("the TOC lists Forever first", function()
    local toc = assert(io.open("DuelElo/DuelElo.toc")):read("*a")
    ok(toc:find("## Interface: 16001, 120100", 1, true))
    local probe = assert(io.open("probe/DuelEloProbe/DuelEloProbe.toc")):read("*a")
    ok(probe:match("## Interface:[^\n]*16001"), "probe loads on Forever")
end)

---------------------------------------------------------------------------
-- Witnesses (SPEC §3.5)
---------------------------------------------------------------------------

test("a nearby duel between two visible players is witnessed and signed", function()
    local env = loggedIn()
    env.units.nameplate3 = { name = "Thrall", realm = "Area52", class = "SHAMAN" }
    env.fire("CHAT_MSG_SYSTEM", "Thrall-Area52 has defeated Jaina-Area52 in a duel")
    local w = DuelEloCharDB.witnesses
    eq(#w, 1)
    local f = env.ns.Statement.Parse(w[1].statement)
    eq({ f.kind, f.witness, f.winner, f.loser, f.how, f.zone, f.region },
        { "witness", "Ashvale-Sargeras", "Thrall-Area52", "Jaina-Area52", "KO", 84, 1 })
    eq(f.t % 10, 0, "time floored to 10 s")
    ok(env.ns.Statement.Verify(DuelEloCharDB.key.secret, w[1].statement, w[1].sig))
    eq(w[1].fp, env.ns.myFp)
    eq(#DuelEloCharDB.duels, 0, "not recorded as our duel")
end)

test("our own duels are never witnessed", function()
    local env = loggedIn()
    env.units.target = { name = "Thrall", realm = "Area52", class = "SHAMAN" }
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall-Area52 in a duel")
    eq(#DuelEloCharDB.witnesses, 0)
    eq(#DuelEloCharDB.duels, 1)
end)

test("no witness when neither duelist is visible (e.g. a message from afar)", function()
    local env = loggedIn()
    env.fire("CHAT_MSG_SYSTEM", "Thrall-Area52 has fled from Jaina-Area52 in a duel")
    eq(#DuelEloCharDB.witnesses, 0)
end)

test("fled duels, duplicates and the 200 cap", function()
    local env = loggedIn()
    env.units.mouseover = { name = "Jaina", realm = "Area52", class = "MAGE" }
    env.fire("CHAT_MSG_SYSTEM", "Thrall-Area52 has fled from Jaina-Area52 in a duel")
    env.fire("CHAT_MSG_SYSTEM", "Thrall-Area52 has fled from Jaina-Area52 in a duel")
    eq(#DuelEloCharDB.witnesses, 1, "same statement only once")
    eq(env.ns.Statement.Parse(DuelEloCharDB.witnesses[1].statement).how, "FLED")
    for i = 1, 205 do
        env.ns.Data.AddWitness(DuelEloCharDB, { statement = "DW2|x" .. i, sig = "s", fp = "f", t = i })
    end
    eq(#DuelEloCharDB.witnesses, 200)
    eq(DuelEloCharDB.witnesses[200].statement, "DW2|x205")
end)

test("witnesses go into the next upload code", function()
    local env = loggedIn()
    env.units.target = { name = "Thrall", realm = "Area52", class = "SHAMAN" }
    env.fire("CHAT_MSG_SYSTEM", "Thrall-Area52 has defeated Jaina-Area52 in a duel")
    local me = env.ns.me
    local p = env.ns.Export.Build(DuelEloCharDB, { name = me.name, realm = me.realm, region = 1, flavor = "forever",
        version = "x", now = time() + 1 })
    eq(#p.witnesses, 1)
    eq(p.witnesses[1].fp, env.ns.myFp)
end)

test("/duel: no name means the target, a name is a player name (with or without realm)", function()
    local env = loggedIn({ units = { target = { name = "Thrall", realm = "Area52", class = "SHAMAN" } } })
    local Duel = env.ns.Duel
    eq(Duel.OpponentFromDuelArg(""), "Thrall-Area52", "plain /duel uses the target")
    eq(Duel.OpponentFromDuelArg(nil), "Thrall-Area52")
    eq(Duel.OpponentFromDuelArg("target"), "Thrall-Area52", "a unit token still works (right-click menu)")
    eq(Duel.OpponentFromDuelArg("Jaina"), "Jaina-Sargeras", "/duel Name: same realm")
    eq(Duel.OpponentFromDuelArg("Jaina-Area52"), "Jaina-Area52")
end)

test("MySpec falls back to C_SpecializationInfo and survives no specs at all", function()
    local env = loggedIn()
    GetSpecialization, GetSpecializationInfo = nil, nil
    C_SpecializationInfo = { GetSpecialization = function() return 2 end,
        GetSpecializationInfo = function(i) return i == 2 and 254 or nil end }
    eq(env.ns.Comm.MySpec(), 254)
    C_SpecializationInfo = nil
    eq(env.ns.Comm.MySpec(), nil)
end)

---------------------------------------------------------------------------
-- WoW Forever names: "First Last", realm only from GetNormalizedRealmName
---------------------------------------------------------------------------

local function foreverEnv(extra)
    local units = { player = { name = "Duelio", surname = "Vodee", class = "PALADIN" } }
    for k, v in pairs(extra or {}) do units[k] = v end
    return loggedIn({ forever = { realm = "ClassicBetaPvP" }, units = units })
end

test("Forever: we are 'First Last' on the real realm, not First-Surname", function()
    local env = foreverEnv()
    eq(env.ns.me.name, "Duelio Vodee")
    eq(env.ns.me.realm, "ClassicBetaPvP")
    eq(env.ns.me.full, "Duelio Vodee-ClassicBetaPvP")
    eq(env.ns.DisplayName(env.ns.me.full), "Duelio Vodee")
end)

test("Forever: a duel with surnames in the chat message is recorded", function()
    local env = foreverEnv({ target = { name = "Bran", surname = "Drav", class = "ROGUE" } })
    env.fire("DUEL_REQUESTED", "Bran Drav")
    env.fire("CHAT_MSG_SYSTEM", "Duelio Vodee has defeated Bran Drav in a duel")
    eq(#DuelEloCharDB.duels, 1)
    local e = last(env)
    eq(e.opp, "Bran Drav-ClassicBetaPvP")
    eq(e.result, "W")
    eq(e.class, "ROGUE", "class found through the target")
end)

test("Forever: our own channel broadcast isn't stored as a stranger", function()
    local env = foreverEnv()
    env.addonMsg("Duelio Vodee", "P~1500~10~PALADIN~6~4", "CHANNEL")
    eq(DuelEloDB.players["Duelio Vodee-ClassicBetaPvP"], nil)
    eq(DuelEloDB.players["Duelio Vodee-Vodee"], nil)
    env.addonMsg("Bran Drav", "P~1650~30~ROGUE~20~10", "CHANNEL")
    eq(DuelEloDB.players["Bran Drav-ClassicBetaPvP"].rating, 1650, "other players still are")
end)

test("Forever: /duel with the target uses the whole name", function()
    local env = foreverEnv({ target = { name = "Bran", surname = "Drav", class = "ROGUE" } })
    eq(env.ns.Duel.OpponentFromDuelArg(""), "Bran Drav-ClassicBetaPvP")
    eq(env.ns.Duel.OpponentFromDuelArg("Bran Drav"), "Bran Drav-ClassicBetaPvP")
end)
