-- Own build snapshot (SPEC §3.13): Loadout.lua strings against the shared
-- vectors, storage and pruning, and the snapshot taken around a real duel.
local json = require("json")
local Wow = require("wow")
local V = json.read("spec/vectors/loadout.json")

local ns = {}
for _, f in ipairs({ "Crypto", "Statement", "Loadout" }) do assert(loadfile("DuelElo/" .. f .. ".lua"))("DuelElo", ns) end
local Loadout = ns.Loadout

test("item links parse to item:enchant:gems:suffix (vectors)", function()
    for _, c in ipairs(V.items) do
        eq(Loadout.ParseItemLink(c.link), c.parsed, c.link)
    end
end)

test("gear: ascending slots, shirt and tabard left out, empty slots omitted (vector)", function()
    local links = {}
    for slot, link in pairs(V.gear.links) do links[tonumber(slot)] = link end
    eq(Loadout.Gear(links), V.gear.gear)
    eq(Loadout.Gear({}), "")
end)

test("classic talents: tier/column order, trailing zeros and dashes trimmed (vectors)", function()
    for _, c in ipairs(V.talents) do
        eq(Loadout.ClassicTalents(c.trees), c.string, c.name)
        eq(Loadout.TreePoints(c.string), c.points, c.name)
    end
end)

test("build hashes (vectors)", function()
    for _, c in ipairs(V.hashes) do eq(Loadout.Hash(c.fmt, c.gear, c.talents), c.hash) end
end)

test("snapshot signature string and HMAC (vectors)", function()
    for _, c in ipairs(V.signatures) do
        local e = { loadout = c.loadout, buffs = c.buffs ~= "" and c.buffs or nil, cds = c.cds ~= "" and c.cds or nil,
            used = c.used ~= "" and c.used or nil, late = c.late or nil }
        eq(Loadout.SignString(c.key, e), c.string)
        eq(ns.Statement.Sign(V.secret, c.string), c.sig)
    end
end)

test("lists are capped", function()
    local many = {}
    for i = 1, 60 do many[i] = i end
    local s = Loadout.List(many)
    eq(select(2, s:gsub(",", "")) + 1, Loadout.MAX_LIST)
end)

local SNAP = { fmt = "classic", gear = "1=16921:2588", talents = "305-05", spec = nil, ilvl = 60,
    buffs = "1459", cds = "", used = "1953@2" }

test("attach stores each distinct build once and signs the duel's part", function()
    local char = { duels = {}, loadouts = {} }
    local a = { t = 100, opp = "Thrall-Area52", match = "1:2" }
    local b = { t = 200, opp = "Jaina-Area52" }
    ok(Loadout.Attach(char, a, SNAP, V.secret, 100))
    ok(Loadout.Attach(char, b, SNAP, V.secret, 200))
    local n = 0
    for hash, build in pairs(char.loadouts) do
        n = n + 1
        eq(hash, Loadout.Hash("classic", "1=16921:2588", "305-05"))
        eq(build.t, 100)  -- first seen
    end
    eq(n, 1)
    eq(a.loadout, b.loadout)
    eq(a.buffs, "1459")
    eq(a.cds, nil)  -- empty lists aren't stored
    eq(a.used, "1953@2")
    eq(a.loadoutSig, ns.Statement.Sign(V.secret, "DS1|1:2|" .. a.loadout .. "|1459||1953@2|0"))
    eq(b.loadoutSig, ns.Statement.Sign(V.secret, "DS1|C:200:Jaina-Area52|" .. b.loadout .. "|1459||1953@2|0"))
end)

test("attach refuses a missing or unknown snapshot", function()
    local char = { duels = {}, loadouts = {} }
    eq(Loadout.Attach(char, {}, nil, V.secret, 1), false)
    eq(Loadout.Attach(char, {}, { fmt = "weird" }, V.secret, 1), false)
    eq(next(char.loadouts), nil)
end)

test("prune drops old snapshots whole and forgets unreferenced builds", function()
    local char = { duels = {}, loadouts = {} }
    local other = { fmt = "classic", gear = "1=1", talents = "5", buffs = "", cds = "", used = "" }
    for i = 1, Loadout.DETAIL_KEEP + 2 do
        local e = { t = i, opp = "X-Y" }
        Loadout.Attach(char, e, i <= 2 and other or SNAP, V.secret, i)
        char.duels[i] = e
    end
    Loadout.Prune(char)
    eq(char.duels[1].loadout, nil)
    eq(char.duels[1].loadoutSig, nil)
    eq(char.duels[2].buffs, nil)
    ok(char.duels[3].loadout and char.duels[3].loadoutSig)
    eq(char.loadouts[Loadout.Hash("classic", "1=1", "5")], nil)
    ok(char.loadouts[char.duels[3].loadout])
end)

---------------------------------------------------------------------------
-- In the client: snapshot at the countdown, casts during the duel
---------------------------------------------------------------------------

-- A Forever-like client: three talent trees, some gear, two buffs and Blink.
local function forever(env)
    local trees = { { { 1, 1, 3 }, { 1, 2, 2 } }, { { 1, 1, 0 }, { 2, 1, 5 } }, { { 1, 1, 0 } } }
    function GetNumTalentTabs() return #trees end
    function GetNumTalents(tab) return #trees[tab] end
    function GetTalentInfo(tab, i)
        local t = trees[tab][i]
        return "Talent", 136000, t[1], t[2], t[3], 5
    end
    local links = { [1] = V.items[3].link, [16] = V.items[1].link, [13] = "item:18854" }
    function GetInventoryItemLink(_, slot) return links[slot] end
    function GetInventoryItemID(_, slot) return links[slot] and tonumber(links[slot]:match("item:(%d+)")) end
    function GetItemSpell(item) if item == 18854 then return "Insignia", 23276 end end
    C_UnitAuras.GetAuraDataByIndex = function(_, i)
        local ids = { 10938, 1459 }
        return ids[i] and { spellId = ids[i] }
    end
    env.spells = { { 1953, 15000, 0, 0 }, { 12051, 480000, env.clock - 100, 480 }, { 133, 0, 0, 0 } }
end

local function cast(env, id) env.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id) end

test("a duel records the build at the countdown and the cooldowns used", function()
    local env = Wow.new()
    forever(env)
    env.login()
    env.fire("CHAT_MSG_SYSTEM", "Duel starting: 3")
    cast(env, 1953)                     -- Blink during the countdown
    env.fire("CHAT_MSG_SYSTEM", "Duel starting: 2")
    env.clock = env.clock + 10
    cast(env, 133)                      -- Fireball: no cooldown, not logged
    cast(env, 23276)                    -- trinket
    cast(env, 1953)
    env.fire("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-2", 1953)  -- someone else
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall in a duel")
    local e = DuelEloCharDB.duels[#DuelEloCharDB.duels]
    local build = DuelEloCharDB.loadouts[e.loadout]
    eq(build.fmt, "classic")
    eq(build.talents, "32-05")
    eq(build.gear, "1=16921:2588,13=18854,16=19019:1900")
    eq(build.ilvl, 612)
    eq(e.buffs, "10938,1459")
    eq(e.cds, "12051:380")              -- Evocation still had 380 s left
    eq(e.used, "1953@-3,23276@7,1953@7")
    eq(e.late, nil)
    eq(e.loadoutSig, ns.Statement.Sign(DuelEloCharDB.key.secret, Loadout.SignString(Loadout.KeyOf(e), e)))
end)

test("casts stop being logged when the duel ends", function()
    local env = Wow.new()
    forever(env)
    env.login()
    env.fire("CHAT_MSG_SYSTEM", "Duel starting: 1")
    env.fire("DUEL_FINISHED")
    cast(env, 1953)
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall in a duel")
    eq(DuelEloCharDB.duels[#DuelEloCharDB.duels].used, nil)
end)

test("no countdown: the build is read at the result and marked late", function()
    local env = Wow.new()
    forever(env)
    env.login()
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall in a duel")
    local e = DuelEloCharDB.duels[#DuelEloCharDB.duels]
    eq(e.late, true)
    eq(e.buffs, nil)
    eq(DuelEloCharDB.loadouts[e.loadout].talents, "32-05")
end)

test("a cancelled duel's snapshot doesn't leak into the next one", function()
    local env = Wow.new({ units = { target = { name = "Jaina", realm = "Sargeras", class = "MAGE" } } })
    forever(env)
    env.login()
    env.fire("CHAT_MSG_SYSTEM", "Duel starting: 3")
    cast(env, 1953)
    env.fire("DUEL_FINISHED")           -- cancelled
    StartDuel("target")                 -- a new request
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Jaina in a duel")
    local e = DuelEloCharDB.duels[#DuelEloCharDB.duels]
    eq(e.late, true)
    eq(e.used, nil)
end)

test("missing or secret APIs give the 'none' format, never an error", function()
    local env = Wow.new()
    env.login()                          -- the plain harness has no talent or gear API
    env.fire("CHAT_MSG_SYSTEM", "Duel starting: 3")
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall in a duel")
    local e = DuelEloCharDB.duels[#DuelEloCharDB.duels]
    eq(DuelEloCharDB.loadouts[e.loadout].fmt, "none")

    local env2 = Wow.new()
    forever(env2)
    env2.secrets[3] = true               -- a secret talent rank
    function GetTalentInfo() return "Talent", 1, 1, 1, 3, 5 end
    env2.login()
    env2.fire("CHAT_MSG_SYSTEM", "Duel starting: 3")
    env2.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall in a duel")
    local e2 = DuelEloCharDB.duels[#DuelEloCharDB.duels]
    eq(DuelEloCharDB.loadouts[e2.loadout].fmt, "none")
end)

test("uploads carry each referenced build once", function()
    local env = Wow.new()
    forever(env)
    env.login()
    for _ = 1, 2 do
        env.fire("CHAT_MSG_SYSTEM", "Duel starting: 3")
        env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall in a duel")
    end
    DuelEloCharDB.duels[#DuelEloCharDB.duels + 1] = { t = 1, opp = "Old-Realm", result = "W", how = "KO" }
    local p = env.ns.Export.Build(DuelEloCharDB, { name = "Ashvale", realm = "Sargeras", class = "MAGE", level = 30,
        region = 1, flavor = "forever", version = "0.6.0", now = os.time(), full = true })
    eq(#p.loadouts, 1)
    eq(p.loadouts[1].hash, p.casual[1].loadout)
    eq(p.loadouts[1].talents, "32-05")
    ok(p.casual[1].loadoutSig and p.casual[2].loadoutSig)
    eq(p.casual[3].loadout, nil)
end)
