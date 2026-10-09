-- Smoke tests for UI/Setup.lua with stubbed frames (the look is checked in game).
local Wow = require("wow")
local Stub = require("ui_stub")

-- Logs in with Setup.lua loaded, so it hears READY like in game.
local function setupEnv(opts)
    DuelEloSetupFrame = nil
    local env = Wow.new(opts)
    Stub.install(env)
    env.load()
    Stub.load(env, "UI/Setup.lua")
    env.fire("ADDON_LOADED", "DuelElo")
    env.fire("PLAYER_LOGIN")
    return env
end

local function click(b) b.scripts.OnClick(b) end
local function controls(n) return DuelEloSetupFrame.pages[n].controls end
local function printed(env, text)
    for _, line in ipairs(env.printed) do if line:find(text, 1, true) then return true end end
    return false
end

test("the setup guide opens shortly after the first login", function()
    local env = setupEnv()
    ok(not DuelEloSetupFrame, "not straight away")
    env.runTimers()
    ok(DuelEloSetupFrame:IsShown())
    eq(DuelEloSetupFrame.pages[1]:IsShown(), true)
    eq(DuelEloSetupFrame.pages[2]:IsShown(), false)
    ok(env.ns.SetupPending(), "still pending while open")
end)

test("walking through the guide saves every choice", function()
    local env = setupEnv()
    env.runTimers()
    local f = DuelEloSetupFrame
    local widgetChanges = 0
    env.ns.Listen(function(event) if event == "WIDGET_CHANGED" then widgetChanges = widgetChanges + 1 end end)

    click(f.next)
    eq(f.pages[2]:IsShown(), true, "how ranked works")
    click(f.next)
    click(controls(3).always)
    click(controls(3).strict)
    click(controls(3).share)
    eq(DuelEloDB.settings.rankedPref, "always")
    eq(DuelEloDB.settings.strict, true)
    eq(DuelEloDB.settings.shareChannel, false)

    click(f.next)
    click(controls(4).shown)
    click(controls(4).full)
    eq(DuelEloDB.settings.widget.shown, true)
    eq(DuelEloDB.settings.widget.preset, "full")
    eq(widgetChanges, 2)

    click(f.back)
    eq(f.pages[3]:IsShown(), true, "back goes one step back")
    click(f.next)
    click(f.next)
    eq(f.pages[5]:IsShown(), true)
    click(f.next)  -- Finish
    eq(f:IsShown(), false)
    eq(env.ns.SetupPending(), false)
    ok(printed(env, "You're all set"))
end)

test("skipping on the first step marks the guide as seen", function()
    local env = setupEnv()
    env.runTimers()
    click(DuelEloSetupFrame.back)  -- "Skip setup" on step 1
    eq(DuelEloSetupFrame:IsShown(), false)
    eq(env.ns.SetupPending(), false)
    ok(printed(env, "/duelelo setup"))
    eq(DuelEloDB.settings.rankedPref, "ask", "nothing changed")
end)

test("closing the guide with X or Escape counts as skipping", function()
    local env = setupEnv()
    env.runTimers()
    DuelEloSetupFrame:Hide()
    DuelEloSetupFrame.scripts.OnHide(DuelEloSetupFrame)
    eq(env.ns.SetupPending(), false)
    ok(printed(env, "Setup skipped"))
end)

test("the guide doesn't open again once seen, but /duelelo setup reopens it", function()
    local env = setupEnv()
    env.runTimers()
    click(DuelEloSetupFrame.back)
    local env2 = setupEnv({ db = DuelEloDB })
    env2.runTimers()
    ok(not DuelEloSetupFrame, "not shown on the next login")
    env2.slash("setup")
    ok(DuelEloSetupFrame:IsShown())
    eq(DuelEloSetupFrame.pages[1]:IsShown(), true, "starts at the first step")
end)

test("the guide waits until combat is over", function()
    local env = setupEnv()
    InCombatLockdown = function() return true end
    env.runTimers()
    InCombatLockdown = function() return false end
    ok(not DuelEloSetupFrame, "not during combat")
    env.runTimers()
    InCombatLockdown = nil
    ok(DuelEloSetupFrame:IsShown())
end)

test("SetupStep stays within the steps", function()
    local env = setupEnv()
    env.ns.ShowSetup()
    env.ns.SetupStep(99)
    eq(DuelEloSetupFrame.pages[5]:IsShown(), true)
    env.ns.SetupStep(0)
    eq(DuelEloSetupFrame.pages[1]:IsShown(), true)
end)
