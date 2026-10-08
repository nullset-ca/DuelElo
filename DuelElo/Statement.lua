-- Statement.lua: the canonical strings players sign (no WoW API).
-- Both duelists build the same match statement from the same facts and sign
-- it with their key; the server rebuilds and verifies it (SPEC §2.4/§2.5,
-- spec/vectors/statement.json). Any change here is a protocol change.
local _, ns = ...
local Crypto = ns.Crypto

local Statement = {}
ns.Statement = Statement

Statement.MATCH_TAG, Statement.WITNESS_TAG = "DE2", "DW2"

local MATCH_FIELDS = { "matchId", "region", "challenger", "challenged", "level", "winner", "how",
    "cPre", "dPre", "cReady", "dReady", "tStart", "tEnd" }
local WITNESS_FIELDS = { "region", "witness", "winner", "loser", "how", "t", "zone" }

local INTS = { region = true, level = true, cPre = true, dPre = true, cReady = true, dReady = true,
    tStart = true, tEnd = true, t = true, zone = true }

local function isInt(v)
    return type(v) == "number" and v == math.floor(v) and v >= 0 and v < 2 ^ 53
end

-- A name or id: non-empty, no separator, no control characters.
local function isText(v)
    return type(v) == "string" and v ~= "" and not v:find("[|%c]")
end

-- Extra checks per field; anything else is an integer (INTS) or text.
local MATCH_CHECKS = {
    matchId = function(v) return type(v) == "string" and v:match("^[%w:]+$") ~= nil and #v <= 40 end,
    winner = function(v) return v == "C" or v == "D" end,
    how = function(v) return v == "KO" or v == "FLED" end,
    cReady = function(v) return isInt(v) and v <= 63 end,
    dReady = function(v) return isInt(v) and v <= 63 end,
    level = function(v) return isInt(v) and v >= 1 and v <= 100 end,
}
local WITNESS_CHECKS = { how = MATCH_CHECKS.how }

local function build(tag, fields, checks, f)
    local parts = { tag }
    for _, k in ipairs(fields) do
        local v = f[k]
        local check = checks[k] or (INTS[k] and isInt) or isText
        if not check(v) then return nil, "bad " .. k end
        parts[#parts + 1] = INTS[k] and ("%d"):format(v) or v
    end
    return table.concat(parts, "|")
end

-- f: { matchId, region, challenger, challenged, level, winner ("C"/"D"),
-- how ("KO"/"FLED"), cPre, dPre, cReady, dReady, tStart, tEnd }.
-- Returns the statement, or nil and the first invalid field.
function Statement.Match(f)
    return build(Statement.MATCH_TAG, MATCH_FIELDS, MATCH_CHECKS, f)
end

-- Witness time resolution: GetServerTime() floored to 10 s.
function Statement.WitnessTime(t)
    return t - t % 10
end

-- f: { region, witness, winner, loser, how, t (raw server time), zone }.
function Statement.Witness(f)
    local copy = {}
    for k, v in pairs(f) do copy[k] = v end
    if isInt(copy.t) then copy.t = Statement.WitnessTime(copy.t) end
    if copy.witness ~= nil and (copy.witness == copy.winner or copy.witness == copy.loser) then
        return nil, "own duel"  -- a client never witnesses its own duels
    end
    return build(Statement.WITNESS_TAG, WITNESS_FIELDS, WITNESS_CHECKS, copy)
end

-- Parse a statement back into fields (nil if malformed). Numbers come back as numbers.
function Statement.Parse(s)
    if type(s) ~= "string" then return nil end
    local parts = {}
    for p in (s .. "|"):gmatch("(.-)|") do parts[#parts + 1] = p end
    local fields = parts[1] == Statement.MATCH_TAG and MATCH_FIELDS
        or parts[1] == Statement.WITNESS_TAG and WITNESS_FIELDS
    if not fields or #parts ~= #fields + 1 then return nil end
    local f = { kind = parts[1] == Statement.MATCH_TAG and "match" or "witness" }
    for i, k in ipairs(fields) do
        local v = parts[i + 1]
        if INTS[k] then
            if not v:match("^%d+$") then return nil end
            v = tonumber(v)
        end
        f[k] = v
    end
    local rebuilt = f.kind == "match" and Statement.Match(f) or build(Statement.WITNESS_TAG, WITNESS_FIELDS, WITNESS_CHECKS, f)
    if rebuilt ~= s then return nil end  -- only canonical strings parse
    return f
end

-- HMAC-SHA256 of a statement with a character secret (64 hex); nil if the secret is bad.
function Statement.Sign(secretHex, statement)
    local key = Crypto.HexToBytes(secretHex)
    if not key or #key ~= 32 then return nil end
    return Crypto.HMAC(key, statement)
end

function Statement.Verify(secretHex, statement, sig)
    return type(sig) == "string" and Statement.Sign(secretHex, statement) == sig
end
