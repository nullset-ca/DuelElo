-- Smoke tests for UI/Options.lua against a stubbed Settings API.
local Wow = require("wow")
local Stub = require("ui_stub")

local function optionsEnv()
    DuelEloOptionsPanel = nil
    local env = Wow.new()
    Stub.install(env)
    Settings, SettingsPanel = Stub.deep(), Stub.deep()
    local registered = {}
    Settings.RegisterCanvasLayoutCategory = function(frame, name)
        registered.frame, registered.name = frame, name
        return Stub.deep()
    end
    Settings.RegisterVerticalLayoutCategory = function() registered.vertical = true return Stub.deep() end
    Settings.RegisterAddOnCategory = function() registered.added = true end
    env.load()
    env.ns.DEFAULT_SOUNDS, env.ns.SOUND_CANDIDATES = { victory = 1, defeat = 2, promote = 3, demote = 4 },
        { { 1, "One" }, { 2, "Two" }, { 3, "Three" } }
    env.ns.PlaySoundKit = function(id) env.played = id end
    Stub.load(env, "UI/Options.lua")
    env.fire("ADDON_LOADED", "DuelElo")
    env.fire("PLAYER_LOGIN")
    Settings, SettingsPanel = nil, nil
    return env, registered
end

local function click(b, button) b.scripts.OnClick(b, button or "LeftButton") end

test("options page is a canvas page of our own (Settings search never runs it)", function()
    local _, registered = optionsEnv()
    ok(registered.added, "category registered")
    eq(registered.name, "DuelElo")
    eq(registered.frame, DuelEloOptionsPanel)
    eq(registered.vertical, nil, "no vertical layout: its controls are what the search taints")
end)

test("options controls change the settings", function()
    local env = optionsEnv()
    local c = DuelEloOptionsPanel.controls
    click(c.strict)
    eq(DuelEloDB.settings.strict, true)
    click(c.rankedPref)
    eq(DuelEloDB.settings.rankedPref, "always")
    click(c.rankedPref, "RightButton")
    eq(DuelEloDB.settings.rankedPref, "ask")
    click(c.rankedPref, "RightButton")
    eq(DuelEloDB.settings.rankedPref, "never", "wraps around")
    click(c.shareChannel)
    eq(DuelEloDB.settings.shareChannel, false)
    click(c.resultsScale.plus)
    eq(DuelEloDB.settings.resultsScale, 0.85)
    for _ = 1, 30 do click(c.resultsScale.minus) end
    eq(DuelEloDB.settings.resultsScale, 0.5, "clamped")

    local changed = 0
    env.ns.Listen(function(e) if e == "WIDGET_CHANGED" then changed = changed + 1 end end)
    click(c.shown)
    eq(DuelEloDB.settings.widget.shown, true)
    click(c.preset)
    eq(DuelEloDB.settings.widget.preset, "minimal")
    click(c.recent)
    eq(DuelEloDB.settings.widget.recent, 10)
    eq(changed, 3)

    click(c.sound_victory)
    eq(DuelEloDB.settings.sounds.victory, 2)
    eq(env.played, 2, "plays the new sound")
end)
