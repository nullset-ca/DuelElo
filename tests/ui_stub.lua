-- Permissive stand-ins for WoW UI objects, for smoke tests of UI files: any
-- method exists and does nothing, Create* methods return more stubs, and the
-- few getters UI code reads return plausible values. Catches nil indexing,
-- wrong arguments to our own helpers and Lua errors; not how things look.
local M = {}

local GETTERS = {
    GetWidth = 70, GetHeight = 16, GetScale = 1, GetAlpha = 1,
}

local function stub(target)
    target = target or {}
    target.shown = target.shown or false
    return setmetatable(target, { __index = function(_, k)
        if GETTERS[k] then return function() return GETTERS[k] end end
        if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 12, -34 end end
        if k == "IsShown" then return function(self) return self.shown end end
        if k == "Show" then return function(self) self.shown = true end end
        if k == "Hide" then return function(self) self.shown = false end end
        if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
        if k:match("^Create") then return function() return stub() end end
        return function() end
    end })
end
M.stub = stub

-- A stub that is also every field and every call result of itself, for
-- deep API namespaces like Settings (Settings.VarType.Boolean, chained calls).
function M.deep()
    return setmetatable({}, {
        __index = function() return M.deep() end,
        __call = function() return M.deep() end,
    })
end

-- Wrap the fake client's CreateFrame so frames keep event support and gain
-- every other method; add the UI globals the addon's UI files touch.
function M.install(env)
    local orig = CreateFrame
    CreateFrame = function(kind, name, ...)
        local f = stub(orig(kind, name, ...))
        if name then _G[name] = f end  -- named frames become globals, as in game
        return f
    end
    UIParent, GameTooltip = stub(), stub()
    UISpecialFrames = {}
    tinsert = table.insert
    MenuUtil = nil
    C_Timer.NewTimer = function() return stub() end
end

-- Load a UI file into the addon namespace (after env.login()).
function M.load(env, file)
    assert(loadfile("DuelElo/" .. file))("DuelElo", env.ns)
end

return M
