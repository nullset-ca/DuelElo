-- Smoke tests for UI/Widget.lua with stubbed frames (the look is checked in game).
local Wow = require("wow")
local Stub = require("ui_stub")

-- The widget is opt-in; most tests turn it on so the drawing code runs.
local function widgetEnv(opts, hidden)
    DuelEloWidget = nil
    local env = Wow.new(opts)
    Stub.install(env)
    env.login()
    if not hidden then DuelEloDB.settings.widget.shown = true end
    env.ns.SetEmblem = function() end
    Stub.load(env, "UI/Widget.lua")
    env.ns.Fire("READY")
    return env
end

test("widget source has no OnUpdate (event-driven only)", function()
    local src = assert(io.open("DuelElo/UI/Widget.lua")):read("*a")
    ok(not src:find("OnUpdate", 1, true))
end)

test("widget renders every preset and trend display without errors", function()
    local env = widgetEnv()
    for _, preset in ipairs({ "full", "compact", "minimal" }) do
        for _, trend in ipairs({ "number", "sparkline", "both", "none" }) do
            DuelEloDB.settings.widget.preset = preset
            DuelEloDB.settings.widget.trend = trend
            env.ns.RefreshWidget()
        end
    end
    ok(true)
end)

test("widget renders placements, ranked, official and demo data", function()
    local env = widgetEnv()
    DuelEloCharDB.rankedGames, DuelEloCharDB.rating = 25, 1452
    for i = 1, 12 do
        DuelEloCharDB.duels[i] = { t = time() - 100 + i, opp = "X-Y", result = i % 3 == 0 and "L" or "W",
            how = i % 5 == 0 and "FLED" or "KO", ranked = i % 4 ~= 0 or nil, delta = i % 4 ~= 0 and 8 or nil }
    end
    DuelEloDB.settings.widget.preset = "full"
    DuelEloDB.settings.widget.trend = "both"
    DuelEloDB.settings.widget.casual = true
    DuelEloDB.settings.widget.recent = 10
    DuelEloDB.settings.widget.nameTag = true
    env.ns.RefreshWidget()
    DuelEloLadderData = { [1] = { players = { ["Ashvale-Sargeras"] = "1612|40|DUELIST||0" } } }
    env.ns.RefreshWidget()
    DuelEloLadderData = nil
    env.slash("dev on")
    env.slash("demo")
    env.slash("demo")
    ok(true)
end)

test("hide and show follow the setting", function()
    local env = widgetEnv(nil, true)
    ok(not (DuelEloWidget and DuelEloWidget:IsShown()), "hidden by default")
    env.slash("widget show")
    local f = DuelEloWidget
    eq(f:IsShown(), true)
    env.slash("widget hide")
    eq(f:IsShown(), false)
    env.slash("widget show")
    eq(f:IsShown(), true)
end)

test("a duel result and a new rating redraw the widget", function()
    local env = widgetEnv()
    env.fire("DUEL_REQUESTED", "Thrall-Area52")
    env.fire("CHAT_MSG_SYSTEM", "Ashvale has defeated Thrall-Area52 in a duel")
    ok(true)
end)
