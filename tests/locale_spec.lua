-- Every user-visible string goes through L (DuelElo/Locale.lua).
local SOURCES = {}
for _, dir in ipairs({ "DuelElo", "DuelElo/UI" }) do
    local p = io.popen('ls "' .. dir .. '"/*.lua')
    for path in p:lines() do SOURCES[#SOURCES + 1] = path end
    p:close()
end

local function read(path)
    local f = assert(io.open(path))
    local s = f:read("*a")
    f:close()
    return s
end

local ENGLISH = {}
for key in read("DuelElo/Locale.lua"):gmatch('\n    "(.-)",') do ENGLISH[key] = true end

-- Files with protocol, crypto or data formats only (no user-visible text).
local TECHNICAL = { ["DuelElo/Locale.lua"] = true, ["DuelElo/BannedAuras.lua"] = true, ["DuelElo/Crypto.lua"] = true,
    ["DuelElo/Codec.lua"] = true, ["DuelElo/Statement.lua"] = true, ["DuelElo/Session.lua"] = true,
    ["DuelElo/Glicko.lua"] = true, ["DuelElo/Parse.lua"] = true, ["DuelElo/Loadout.lua"] = true }

-- Sentence-like literals that are deliberately not localized (see Locale.lua's header).
local ALLOWED = {
    "https://discord.gg/", "addon:", "Duel starting: %d", "DuelElo  |cff808080v", "DuelElo options panel: ",
    "duelelo.com/upload", "widget ", "DuelElo|r  ", "|cffffd100DuelElo|r ", "|TInterface",
}

local function allowed(s)
    for _, a in ipairs(ALLOWED) do if s:find(a, 1, true) then return true end end
    return false
end

test("every L key used in the addon exists in Locale.lua", function()
    local missing = {}
    for _, path in ipairs(SOURCES) do
        for key in (path == "DuelElo/Locale.lua" and "" or read(path)):gmatch('L%["(.-)"%]') do
            if not ENGLISH[key] then missing[#missing + 1] = path .. ": " .. key end
        end
    end
    eq(missing, {})
end)

test("Locale.lua has no unused keys", function()
    local used = {}
    for _, path in ipairs(SOURCES) do
        for key in read(path):gmatch('L%["(.-)"%]') do used[key] = true end
    end
    local unused = {}
    for key in pairs(ENGLISH) do if not used[key] then unused[#unused + 1] = key end end
    eq(unused, {})
end)

test("no sentence-like string literals outside L[] (except the documented ones)", function()
    local found = {}
    for _, path in ipairs(SOURCES) do
        if not TECHNICAL[path] then
            local n = 0
            for line in (read(path) .. "\n"):gmatch("(.-)\n") do
                n = n + 1
                -- drop comments (whole-line and trailing; no "--" appears inside strings here)
                local code = line:match("^%s*%-%-") and "" or line:gsub("%s%-%-%s.*$", "")
                if not code:find("DPrint", 1, true) then
                    -- strip localized strings, then look at what's left
                    local rest = code:gsub('L%[".-"%]', "")
                    for s in rest:gmatch('"(.-)"') do
                        if s:find("%a%a+[ ,.!?:]") and not s:find("~", 1, true) and not allowed(s) then
                            found[#found + 1] = ("%s:%d: %s"):format(path, n, s)
                        end
                    end
                end
            end
        end
    end
    eq(found, {})
end)

test("L falls back to the English text", function()
    local ns = {}
    assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
    eq(ns.L["Ranked"], "Ranked")
    eq(ns.L["Something new"], "Something new")
    ok(ns.LOCALE_KEYS["Ranked"])
end)
