-- Minimal dependency-free test runner.
-- Usage (from repo root):  luajit tests/run.lua
package.path = "./tests/?.lua;" .. package.path

local write = io.write
local passed, failed, failures = 0, 0, {}
local currentFile

local function show(v)
    if type(v) == "string" then return ("%q"):format(v) end
    return tostring(v)
end

local function deepEq(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        passed = passed + 1
        write(".")
    else
        failed = failed + 1
        failures[#failures + 1] = ("%s :: %s\n%s"):format(currentFile, name, err)
        write("F")
    end
end

function eq(actual, expected, msg)
    if not deepEq(actual, expected) then
        error(("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", show(expected), show(actual)), 2)
    end
end

function ok(v, msg)
    if not v then error(msg or "expected truthy value", 2) end
end

local specs = { "parse_spec", "elo_spec", "data_spec", "leaderboard_spec", "session_spec", "core_spec",
    "readiness_spec", "rules_spec",
    "glicko_spec", "widget_model_spec", "widget_ui_spec",
    "prompt_ui_spec", "options_ui_spec", "report_ui_spec", "setup_ui_spec", "copybox_ui_spec", "export_spec", "ladder_spec", "locale_spec", "crypto_spec",
    "keys_spec", "statement_spec", "codec_spec", "loadout_spec" }
for _, name in ipairs(specs) do
    currentFile = name
    dofile("tests/" .. name .. ".lua")
end

write(("\n\n%d passed, %d failed\n"):format(passed, failed))
for _, f in ipairs(failures) do write("\n" .. f .. "\n") end
os.exit(failed == 0 and 0 or 1)
