-- Smoke test for UI/Options.lua against a stubbed Settings API.
local Wow = require("wow")
local Stub = require("ui_stub")

test("options panel builds without errors", function()
    local env = Wow.new()
    Stub.install(env)
    Settings, SettingsPanel = Stub.deep(), Stub.deep()
    MinimalSliderWithSteppersMixin = Stub.deep()
    local built = false
    Settings.RegisterAddOnCategory = function() built = true end
    env.load()
    env.ns.DEFAULT_SOUNDS, env.ns.SOUND_CANDIDATES = { victory = 1, defeat = 2, promote = 3, demote = 4 }, { { 1, "One" } }
    Stub.load(env, "UI/Options.lua")
    env.fire("ADDON_LOADED", "DuelElo")
    env.fire("PLAYER_LOGIN")
    Settings, SettingsPanel, MinimalSliderWithSteppersMixin = nil, nil, nil
    ok(built, "category registered")
end)
