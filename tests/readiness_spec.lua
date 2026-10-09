local Wow = require("wow")

local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Readiness.lua"))("DuelElo", ns)
local R = ns.Readiness
local B = R.BITS

local READY = { inCombat = false, health = 1, mana = 1, cooldowns = 0, trinkets = 0, banned = 0 }

local function with(over)
    local t = {}
    for k, v in pairs(READY) do t[k] = v end
    for k, v in pairs(over) do t[k] = v end
    return t
end

test("all checks passing gives mask 0", function()
    local mask, counts, unknown = R.Evaluate(READY)
    eq(mask, 0)
    eq(counts, { cooldowns = 0, trinkets = 0, banned = 0 })
    eq(unknown, {})
end)

test("bit values match protocol v2", function()
    eq(B, { HEALTH = 1, POWER = 2, COOLDOWNS = 4, TRINKETS = 8, BANNED = 16, COMBAT = 32 })
    eq(R.BASELINE_BITS, 1 + 2 + 16 + 32)
    eq(R.INFO_BITS, 4 + 8)
end)

-- One failing value per check; every subset of them must give exactly the sum.
local FAILING = {
    { B.HEALTH, { health = 0.5 } },
    { B.POWER, { mana = 0.2 } },
    { B.COOLDOWNS, { cooldowns = 2 } },
    { B.TRINKETS, { trinkets = 1 } },
    { B.BANNED, { banned = 1 } },
    { B.COMBAT, { inCombat = true } },
}

test("mask is correct for every combination of failed checks", function()
    for combo = 0, 63 do
        local over, expected = {}, 0
        for i, f in ipairs(FAILING) do
            if math.floor(combo / 2 ^ (i - 1)) % 2 == 1 then
                expected = expected + f[1]
                for k, v in pairs(f[2]) do over[k] = v end
            end
        end
        eq(R.Evaluate(with(over)), expected, "combo " .. combo)
    end
end)

test("thresholds: exactly 95% passes, just below fails", function()
    eq(R.Evaluate(with({ health = 0.95, mana = 0.95 })), 0)
    eq(R.Evaluate(with({ health = 0.949 })), B.HEALTH)
    eq(R.Evaluate(with({ mana = 0.949 })), B.POWER)
end)

test("no mana pool means the power check passes", function()
    eq(R.Evaluate(with({ mana = false })), 0)
end)

test("unreadable inputs are marked unknown; all but health and mana fail", function()
    local mask, _, unknown = R.Evaluate({})
    eq(mask, R.ALL_BITS - B.HEALTH - B.POWER)
    for _, b in pairs(B) do ok(unknown[b], "bit " .. b) end
    local m2, _, u2 = R.Evaluate(with({ health = "?" }))
    eq(m2, 0, "hidden health doesn't block (secret on Forever)")
    eq(u2, { [B.HEALTH] = true })
    eq(R.Unchecked(m2, u2), { "health" })
    local noMana = with({})
    noMana.mana = nil
    local m3, _, u3 = R.Evaluate(noMana)
    eq(m3, 0)
    eq(R.Unchecked(m3, u3), { "mana" })
end)

test("baseline vs informational split", function()
    local mask = B.HEALTH + B.COOLDOWNS + B.TRINKETS + B.COMBAT
    eq(R.Baseline(mask), B.HEALTH + B.COMBAT)
    eq(R.Info(mask), B.COOLDOWNS + B.TRINKETS)
    eq(R.Baseline(B.COOLDOWNS + B.TRINKETS), 0)
    eq(R.Info(B.POWER + B.BANNED), 0)
end)

test("Decode accepts 0..63 integers only", function()
    eq(R.Decode("0"), 0)
    eq(R.Decode("63"), 63)
    eq(R.Decode("64"), nil)
    eq(R.Decode("-1"), nil)
    eq(R.Decode("1.5"), nil)
    eq(R.Decode("x"), nil)
    eq(R.Decode(nil), nil)
end)

test("Describe: ready, own side with counts, opponent side from a bare mask", function()
    eq(R.Describe(0), "Ready")
    local mask, counts, unknown = R.Evaluate(with({ health = 0.5, cooldowns = 2 }))
    eq(R.Describe(mask, counts, unknown), "Not ready: health, 2 cooldowns")
    eq(R.Describe(B.TRINKETS + B.POWER), "Not ready: mana, trinkets")
    eq(R.Describe(B.BANNED, { banned = 1 }), "Not ready: 1 banned buff")
    eq(R.Describe(B.BANNED), "Not ready: banned buffs")
    local m2, c2, u2 = R.Evaluate(with({ cooldowns = "?" }))
    eq(R.Describe(m2, c2, u2), "Not ready: cooldowns ?")
end)

test("Problems separates baseline from informational problems", function()
    local baseline, info = R.Problems(B.COMBAT + B.COOLDOWNS + B.TRINKETS, { cooldowns = 1, trinkets = 2 })
    eq(baseline, { "in combat" })
    eq(info, { "1 cooldown", "2 trinkets" })
end)

---------------------------------------------------------------------------
-- Adapter: reading the (fake) client
---------------------------------------------------------------------------

local function client()
    local env = Wow.new()
    env.login()
    return env, env.ns
end

test("adapter: fresh character out of combat is ready", function()
    local _, a = client()
    eq(a.EvaluateReadiness(), 0)
end)

test("adapter: low health and mana", function()
    local env, a = client()
    env.vitals.health, env.vitals.mana = 80, 50
    eq(a.EvaluateReadiness(), B.HEALTH + B.POWER)
end)

test("adapter: no mana pool is fine", function()
    local env, a = client()
    env.vitals.manaMax, env.vitals.mana = 0, 0
    eq(a.EvaluateReadiness(), 0)
end)

test("adapter: in combat reports only the combat bit", function()
    local env, a = client()
    env.vitals.combat, env.vitals.health = true, 10
    eq(a.EvaluateReadiness(), B.COMBAT)
end)

test("adapter: long cooldowns counted, short ones and GCD ignored", function()
    local env, a = client()
    env.spells = {
        { 1, 120000, 900, 120 },  -- long, cooling
        { 2, 180000, 0, 0 },      -- long, ready
        { 3, 30000, 990, 30 },    -- short, cooling: not counted
        { 4, 60000, 999, 1.5 },   -- long, only the GCD running
        { 5, 60000, 950, 60 },    -- long, cooling
    }
    env.fire("SPELLS_CHANGED")
    local mask, counts = a.EvaluateReadiness()
    eq(mask, B.COOLDOWNS)
    eq(counts.cooldowns, 2)
end)

test("adapter: spellbook is rescanned after SPELLS_CHANGED", function()
    local env, a = client()
    eq(a.EvaluateReadiness(), 0)
    env.spells = { { 7, 120000, 900, 120 } }
    eq(a.EvaluateReadiness(), 0, "cached scan")
    env.fire("SPELLS_CHANGED")
    eq(a.EvaluateReadiness(), B.COOLDOWNS)
end)

test("adapter: trinket on cooldown", function()
    local env, a = client()
    env.vitals.trinkets[14] = { 900, 120, 1 }
    local mask, counts = a.EvaluateReadiness()
    eq(mask, B.TRINKETS)
    eq(counts.trinkets, 1)
end)

test("adapter: banned aura", function()
    local env, a = client()
    env.vitals.auras[22888] = { spellId = 22888 }
    eq(a.EvaluateReadiness(), B.BANNED)
end)

test("adapter: secret values never throw and mark the check unknown", function()
    local env, a = client()
    env.vitals.health = "secret-health"
    env.secrets["secret-health"] = true
    local mask, _, unknown = a.EvaluateReadiness()
    eq(mask, 0, "hidden health is unchecked, not a failure")
    ok(unknown[B.HEALTH])
end)

test("adapter: UnitHealthPercent stands in for a hidden UnitHealth", function()
    local env, a = client()
    env.vitals.health = "secret-health"
    env.secrets["secret-health"] = true
    UnitHealthPercent = function() return 50 end  -- 0..100
    local mask, _, unknown = a.EvaluateReadiness()
    UnitHealthPercent = nil
    eq(mask, B.HEALTH, "50% is too low")
    eq(unknown[B.HEALTH], nil)
end)

test("adapter: secret cooldown info marks cooldowns unknown", function()
    local env, a = client()
    env.spells = { { 1, 120000, "secret-start", 120 } }
    env.secrets["secret-start"] = true
    env.fire("SPELLS_CHANGED")
    local mask, _, unknown = a.EvaluateReadiness()
    eq(mask, B.COOLDOWNS)
    ok(unknown[B.COOLDOWNS])
end)

test("adapter: secret combat state blocks as unknown", function()
    local env, a = client()
    env.vitals.combat = "secret-combat"
    env.secrets["secret-combat"] = true
    local mask, _, unknown = a.EvaluateReadiness()
    eq(mask, B.COMBAT)
    ok(unknown[B.COMBAT])
end)

test("adapter: missing or erroring APIs never throw", function()
    local _, a = client()
    C_SpellBook, C_UnitAuras, UnitBuff = nil, nil, nil
    UnitHealth = function() error("boom") end
    local mask, _, unknown = a.EvaluateReadiness()
    eq(mask, B.COOLDOWNS + B.BANNED)
    ok(unknown[B.HEALTH] and unknown[B.COOLDOWNS] and unknown[B.BANNED])
end)

test("adapter: falls back to UnitBuff when C_UnitAuras is missing", function()
    local _, a = client()
    C_UnitAuras = nil
    UnitBuff = function(_, i)
        if i == 1 then return "Songflower Serenade", nil, nil, nil, nil, nil, nil, nil, nil, 15366 end
    end
    eq(a.EvaluateReadiness(), B.BANNED)
end)

test("banned aura list entries are all named", function()
    local _, a = client()
    local n = 0
    for id, name in pairs(a.BANNED_AURAS) do
        n = n + 1
        ok(type(id) == "number" and type(name) == "string" and name ~= "", tostring(id))
    end
    ok(n >= 10)
end)
