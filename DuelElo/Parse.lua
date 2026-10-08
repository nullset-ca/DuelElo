-- Parse.lua: pure string helpers (no WoW API), unit tested in tests/.
local _, ns = ...

local Parse = {}
ns.Parse = Parse

-- Compile a client format string such as "%2$s has fled from %1$s in a duel"
-- into a Lua pattern plus the argument index of each capture, so captures can
-- be mapped back to %1$s / %2$s no matter the order they appear in the text.
function Parse.Compile(fmt)
    if type(fmt) ~= "string" then return nil end
    local order, n = {}, 0
    local p = fmt:gsub("%%(%d?)%$?s", function(idx)
        n = n + 1
        order[n] = tonumber(idx) or n
        return "\001"
    end)
    if n ~= 2 then return nil end
    p = p:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("\001", "(.+)")
    return { pattern = "^" .. p .. "$", order = order }
end

-- Build a matcher from { {kind = "KO", fmt = DUEL_WINNER_KNOCKOUT}, ... }.
-- The matcher returns kind, winner, loser for a winner message, or nil.
function Parse.Matcher(templates)
    local compiled = {}
    for _, t in ipairs(templates) do
        local c = Parse.Compile(t.fmt)
        if c then
            c.kind = t.kind
            compiled[#compiled + 1] = c
        end
    end
    return function(msg)
        if type(msg) ~= "string" then return nil end
        for _, c in ipairs(compiled) do
            local a, b = msg:match(c.pattern)
            if a then
                local args = {}
                args[c.order[1]], args[c.order[2]] = a, b
                return c.kind, args[1], args[2]
            end
        end
        return nil
    end, #compiled
end

-- Pattern for the duel countdown line, e.g. DUEL_COUNTDOWN = "Duel starting: %d".
-- Captures the seconds remaining.
function Parse.CountdownPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p, n = fmt:gsub("%%d", "\001")
    if n ~= 1 then return nil end
    p = p:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    return "^" .. p:gsub("\001", "(%%d+)") .. "$"
end

-- "Name-Realm" -> "Name", "Realm". "Name" -> "Name", nil.
function Parse.SplitName(full)
    if type(full) ~= "string" then return nil end
    local name, realm = full:match("^([^%-]+)%-(.+)$")
    if name then return name, realm end
    return full, nil
end

-- Always "Name-Realm"; names without a realm belong to defaultRealm.
function Parse.Normalize(full, defaultRealm)
    local name, realm = Parse.SplitName(full)
    if not name then return nil end
    realm = realm or defaultRealm
    if not realm or realm == "" then return name end
    return name .. "-" .. realm
end
