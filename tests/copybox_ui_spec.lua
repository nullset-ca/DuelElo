-- Smoke tests for UI/Community.lua's copy box with stubbed frames.
local Wow = require("wow")
local Stub = require("ui_stub")

local function copyEnv()
    DuelEloCopyFrame = nil
    local env = Wow.new()
    Stub.install(env)
    env.login()
    Stub.load(env, "UI/Community.lua")
    return env
end

test("upload codes are hidden on screen but still in the box to copy", function()
    local env = copyEnv()
    env.ns.ShowCopyBox("Title", "Text", "DUELELO1:secret", true)
    local f = DuelEloCopyFrame
    ok(f:IsShown())
    eq(f.mask:IsShown(), true, "mask over the code")
    eq(f.reveal:IsShown(), true, "Show code button")
    eq(f.value, "DUELELO1:secret")
    f.reveal.scripts.OnClick(f.reveal)
    eq(f.mask:IsShown(), false, "revealed")
    f.reveal.scripts.OnClick(f.reveal)
    eq(f.mask:IsShown(), true, "hidden again")
end)

test("each new secret starts hidden, and plain links are never masked", function()
    local env = copyEnv()
    env.ns.ShowCopyBox("Title", "Text", "DUELELO1:a", true)
    local f = DuelEloCopyFrame
    f.reveal.scripts.OnClick(f.reveal)
    env.ns.ShowCopyBox("Title", "Text", "DUELELO1:b", true)
    eq(f.mask:IsShown(), true)
    env.ns.ShowCopyBox("Discord", "Text", "https://discord.gg/x")
    eq(f.mask:IsShown(), false)
    eq(f.reveal:IsShown(), false)
end)

test("Ctrl+C on a hidden code says it was copied", function()
    local env = copyEnv()
    env.ns.ShowCopyBox("Title", "Text", "DUELELO1:a", true)
    local f = DuelEloCopyFrame
    IsControlKeyDown = function() return true end
    f.edit.scripts.OnKeyDown(f.edit, "C")
    IsControlKeyDown = nil
    eq(f.copied, true)
end)
