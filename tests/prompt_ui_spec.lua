-- Smoke tests for UI/Prompt.lua with stubbed frames (the look is checked in game).
local Wow = require("wow")
local Stub = require("ui_stub")

local function promptEnv()
    DuelEloPrompt = nil
    local env = Wow.new()
    Stub.install(env)
    env.login()
    env.ns.SetEmblem = function() end
    Stub.load(env, "UI/Prompt.lua")
    return env
end

local PEER = { rating = 1452, games = 40, class = "SHAMAN", w = 25, l = 15, pref = "ask", level = 30 }
local RB = { HEALTH = 1, POWER = 2, COOLDOWNS = 4, TRINKETS = 8, BANNED = 16, COMBAT = 32 }

test("prompt renders every session state without errors", function()
    local env = promptEnv()
    local base = { opp = "Thrall-Area52", role = "D", peer = PEER, status = "pending" }
    local states = {
        {},
        { myReady = 0, theirReady = 0 },
        { myReady = RB.HEALTH + RB.COOLDOWNS, myCounts = { cooldowns = 2 }, theirReady = RB.TRINKETS },
        { myReady = RB.COOLDOWNS, myUnknown = { [RB.COOLDOWNS] = true }, theirReady = 63 },
        { theirConsent = true },
        { theirConsent = false, theirReason = "U" },
        { theirConsent = false, theirReason = "L" },
        { myConsent = false, myReason = "A", ineligible = "A" },
        { myConsent = false, myReason = "D" },
        { myConsent = true, theirConsent = true },
        { countdown = true },
        { locked = true, status = "ranked" },
        { locked = true, status = "casual" },
        { status = "outdated" },
        { status = "incompatible", peer = { proto = 99 } },
    }
    for _, st in ipairs(states) do
        local s = {}
        for k, v in pairs(base) do s[k] = v end
        for k, v in pairs(st) do s[k] = v end
        env.ns.Fire("SESSION_CHANGED", s)
    end
    env.ns.Fire("SESSION_CHANGED", nil)
    ok(DuelEloPrompt, "prompt was built")
end)

test("prompt follows a live handshake", function()
    local env = promptEnv()
    env.fire("DUEL_REQUESTED", "Thrall-Area52")
    env.addonMsg("Thrall-Area52", "H~2~t1~C~1500~40~K~SHAMAN~25~15~~~~30~4")
    ok(DuelEloPrompt:IsShown())
    env.vitals.health = 10
    env.tick()
    AcceptDuel()
    ok(true)
end)
