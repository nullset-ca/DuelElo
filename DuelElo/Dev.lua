-- Dev.lua: demo data and fake results for previewing the UI solo. Nothing
-- here is ever saved; the UI reads through ns.ViewData/ns.ViewPlayers so it
-- shows demo data while demo mode is on.
local _, ns = ...
local L = ns.L
local Parse, Data = ns.Parse, ns.Data
local me = ns.me

local Dev = {}
ns.Dev = Dev

local DEMO_OPPONENTS = {
    { "Thrall", "SHAMAN" }, { "Jaina-Area52", "MAGE" }, { "Garrosh", "WARRIOR" },
    { "Sylvanas-Illidan", "HUNTER" }, { "Valeera", "ROGUE" }, { "Anduin-Area52", "PRIEST" },
    { "Malfurion", "DRUID" }, { "Gul'dan-Stormrage", "WARLOCK" },
}

local function buildDemo()
    local db = Data.InitChar(nil)
    local now = time()
    for i = 1, 40 do
        local o = DEMO_OPPONENTS[(i * 7) % #DEMO_OPPONENTS + 1]
        Data.Record(db, {
            t = now - (41 - i) * 3600 * 5,
            opp = Parse.Normalize(o[1], me.realm),
            class = o[2],
            result = (i % 3 == 0) and "L" or "W",
            how = (i % 7 == 0) and "FLED" or "KO",
            ranked = true,
            delta = (i % 3 == 0) and -(10 + i % 9) or (12 + i % 11),
            secs = 18 + (i * 7) % 60,
            zone = (i % 3 == 0) and 85 or 84,  -- Orgrimmar / Stormwind
        })
    end
    db.rating, db.rankedGames, db.peak = 1748, 40, 1781  -- lands inside the demo top 100
    db.rankedW, db.rankedL = 26, 14
    return db
end

local DEMO_SYLLABLES = { "Kor", "Zul", "Ash", "Vel", "Mor", "Thal", "Gri", "Bra", "Syl", "Dra",
    "Nyx", "Tor", "Eli", "Vor", "Ka", "Lun" }
local DEMO_ENDINGS = { "gash", "ria", "dor", "nix", "thar", "wyn", "zak", "lia", "mok", "ren" }
local DEMO_REALMS = { "Sargeras", "Area52", "Illidan", "Stormrage", "Tichondrius" }
-- WoW Forever's classes only (no Death Knight, Monk, Demon Hunter or Evoker)
local DEMO_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function buildDemoPlayers()
    local players = {}
    for i = 1, 150 do
        -- 16 x 10 syllable/ending combinations, so all 150 names are unique
        local name = DEMO_SYLLABLES[(i - 1) % #DEMO_SYLLABLES + 1]
            .. DEMO_ENDINGS[math.floor((i - 1) / #DEMO_SYLLABLES) % #DEMO_ENDINGS + 1]
        local full = name .. "-" .. DEMO_REALMS[i % #DEMO_REALMS + 1]
        local games = 10 + (i * 13) % 70
        local w = math.floor(games * (0.35 + ((i * 17) % 40) / 100))
        players[full] = {
            rating = 2060 - i * 6 - (i * 29) % 11,
            games = games, w = w, l = games - w,
            class = DEMO_CLASSES[i % #DEMO_CLASSES + 1],
            source = (i % 3 == 0) and "met" or "channel",
            seen = time(),
        }
    end
    return players
end

function Dev.ToggleDemo()
    ns.demo = not ns.demo and buildDemo() or nil
    ns.demoPlayers = ns.demo and buildDemoPlayers() or nil
    ns.Print(ns.demo and L["Demo data on (not saved)"] or L["Demo data off"])
    ns.Fire("VIEW_CHANGED")
    if ns.demo and ns.ShowMain then ns.ShowMain() end
end

-- What the UI should show: demo data while demo mode is on, otherwise ours.
function ns.ViewData()
    return ns.demo or ns.char
end

function ns.ViewPlayers()
    return ns.demoPlayers or ns.account.players
end

-- The local character as a leaderboard entry, from whatever data is on view.
function ns.MyLeaderboardEntry()
    local c = ns.ViewData()
    return { name = me.full, rating = c.rating, games = c.rankedGames, class = me.class, w = c.rankedW, l = c.rankedL }
end

-- Fake results for previewing the results screen. Nothing is saved.
local TEST_RESULTS = {
    win     = { result = "W", before = 1310, after = 1330 },
    loss    = { result = "L", before = 1330, after = 1312 },
    promo   = { result = "W", before = 1388, after = 1410 },
    demote  = { result = "L", before = 1205, after = 1190 },
    place   = { result = "W", before = 1200, after = 1240, placement = 4 },
    reveal  = { result = "W", before = 1390, after = 1418, placement = 10 },
    elite   = { result = "W", before = 1790, after = 1806 },
    unranked = { result = "W" },
}

-- Walks the ranked prompt through its stages with a fake opponent.
local function showPromptTest()
    local peer = { rating = 1452, games = 40, class = "SHAMAN", w = 25, l = 15, pref = "ask" }
    local base = { opp = Parse.Normalize("Thrall-Area52", me.realm), role = "D", peer = peer, status = "pending",
        myReady = 0, theirReady = ns.Readiness.BITS.COOLDOWNS }
    local stages = {
        {},
        { theirConsent = true },
        { theirConsent = true, myConsent = true },
        { theirConsent = true, myConsent = true, locked = true, status = "ranked" },
    }
    for i, stage in ipairs(stages) do
        C_Timer.After((i - 1) * 2.5, function()
            local s = {}
            for k, v in pairs(base) do s[k] = v end
            for k, v in pairs(stage) do s[k] = v end
            ns.Fire("SESSION_CHANGED", s)
        end)
    end
end

function Dev.ShowTest(kind)
    if kind == "prompt" then return showPromptTest() end
    local spec = TEST_RESULTS[kind]
    if not spec then
        local names = {}
        for k in pairs(TEST_RESULTS) do names[#names + 1] = k end
        table.sort(names)
        ns.Print(L["Test results: %s, prompt"]:format(table.concat(names, ", ")))
        return
    end
    local e = { t = time(), opp = Parse.Normalize("Thrall-Area52", me.realm), class = "SHAMAN", how = "KO" }
    for k, v in pairs(spec) do e[k] = v end
    if e.before then
        e.ranked = true
        e.delta = e.after - e.before
    end
    if ns.ShowResult then ns.ShowResult(e) end
end

function Dev.Art(mode)
    if ns.SetArtMode and ns.SetArtMode(mode) then
        ns.Print(L["Art mode: %s (reopen the window / rerun a test to see it)"]:format(mode))
    else
        ns.Print(L["/duelelo art <normal|noapi|noart>"])
    end
end

function Dev.ToggleDebug()
    ns.debugOn = not ns.debugOn
    ns.Print(L["Debug %s"]:format(ns.debugOn and L["on"] or L["off"]))
end
