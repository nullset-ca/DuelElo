-- Minimal JSON decoder for test fixtures (spec/vectors). Not used by the addon.
local M = {}

local function skip(s, i)
    return s:find("[^ \t\r\n]", i) or #s + 1
end

local decode

local ESC = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function str(s, i)
    local out, j = {}, i + 1
    while true do
        local c = s:sub(j, j)
        if c == "" then error("unterminated string at " .. i) end
        if c == '"' then return table.concat(out), j + 1 end
        if c == "\\" then
            local e = s:sub(j + 1, j + 1)
            if e == "u" then
                local code = assert(tonumber(s:sub(j + 2, j + 5), 16), "bad \\u escape")
                assert(code < 0xD800 or code > 0xDFFF, "surrogate pairs not supported")
                if code < 0x80 then
                    out[#out + 1] = string.char(code)
                elseif code < 0x800 then
                    out[#out + 1] = string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
                else
                    out[#out + 1] = string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64,
                        0x80 + code % 64)
                end
                j = j + 6
            else
                out[#out + 1] = assert(ESC[e], "bad escape")
                j = j + 2
            end
        else
            out[#out + 1] = c
            j = j + 1
        end
    end
end

function decode(s, i)
    i = skip(s, i)
    local c = s:sub(i, i)
    if c == "{" then
        local obj = {}
        i = skip(s, i + 1)
        if s:sub(i, i) == "}" then return obj, i + 1 end
        while true do
            local k
            k, i = str(s, skip(s, i))
            i = skip(s, i)
            assert(s:sub(i, i) == ":", "expected ':' at " .. i)
            obj[k], i = decode(s, i + 1)
            i = skip(s, i)
            local d = s:sub(i, i)
            if d == "}" then return obj, i + 1 end
            assert(d == ",", "expected ',' at " .. i)
            i = i + 1
        end
    elseif c == "[" then
        local arr = {}
        i = skip(s, i + 1)
        if s:sub(i, i) == "]" then return arr, i + 1 end
        while true do
            arr[#arr + 1], i = decode(s, i)
            i = skip(s, i)
            local d = s:sub(i, i)
            if d == "]" then return arr, i + 1 end
            assert(d == ",", "expected ',' at " .. i)
            i = i + 1
        end
    elseif c == '"' then
        return str(s, i)
    elseif s:sub(i, i + 3) == "true" then return true, i + 4
    elseif s:sub(i, i + 4) == "false" then return false, i + 5
    elseif s:sub(i, i + 3) == "null" then return nil, i + 4
    end
    local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    assert(num and #num > 0, "unexpected character at " .. i)
    return tonumber(num), i + #num
end

function M.decode(s)
    local v, i = decode(s, 1)
    assert(skip(s, i) > #s, "trailing data")
    return v
end

function M.read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return M.decode(s)
end

return M
