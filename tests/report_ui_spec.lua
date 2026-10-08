-- Smoke tests for UI/Report.lua with stubbed frames (the look is checked in game).
local Wow = require("wow")
local Stub = require("ui_stub")

local function reportEnv()
    DuelEloReportFrame = nil
    local env = Wow.new()
    Stub.install(env)
    env.login()
    Stub.load(env, "UI/Report.lua")
    return env
end

local OPP = "Thrall-Area52"
local HELLO = "H~2~t1~C~1500~40~K~SHAMAN~25~15~~~~30~0"

-- A duel vs another DuelElo player (it gets a match id).
local function addonDuel(env)
    env.fire("DUEL_REQUESTED", OPP)
    env.addonMsg(OPP, HELLO)
    AcceptDuel()
    env.fire("CHAT_MSG_SYSTEM", "Thrall-Area52 has defeated Ashvale in a duel")
    return DuelEloCharDB.duels[#DuelEloCharDB.duels]
end

test("only duels vs DuelElo players can be reported", function()
    local env = reportEnv()
    local e = addonDuel(env)
    ok(e.match, "addon duel has a match id")
    ok(env.ns.CanReport(e))
    env.fire("DUEL_REQUESTED", "Stranger-Area52")
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Stranger-Area52 in a duel")
    eq(env.ns.CanReport(DuelEloCharDB.duels[#DuelEloCharDB.duels]), false)
end)

test("picking a reason and sending stores the report", function()
    local env = reportEnv()
    local e = addonDuel(env)
    env.ns.ShowReport(e)
    local f = DuelEloReportFrame
    ok(f:IsShown())
    f.reasons[2].scripts.OnClick()  -- Outside help
    f.send.scripts.OnClick()
    eq(#DuelEloCharDB.reports, 1)
    eq(DuelEloCharDB.reports[1].reason, "HELP")
    eq(DuelEloCharDB.reports[1].target, OPP)
    eq(DuelEloCharDB.reports[1].matchId, e.match)
    eq(f:IsShown(), false)
    eq(env.ns.CanReport(e), false, "can't report the same duel twice")
    env.ns.ShowReport(e)
    ok(env.lastPrint():find("already reported", 1, true))
end)

test("sending without a reason explains why", function()
    local env = reportEnv()
    env.ns.ShowReport(addonDuel(env))
    DuelEloReportFrame.send.scripts.OnClick()
    ok(env.lastPrint():find("Pick a reason", 1, true))
    eq(#DuelEloCharDB.reports, 0)
end)
