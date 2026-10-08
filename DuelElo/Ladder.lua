-- Ladder.lua: reads the official ladder data addon (SPEC §2.7/§3.8; no WoW
-- API). DuelElo_Ladder is generated from duelelo.com and sets
--   DuelEloLadderData[region] = { season, generated, players = {
--     ["Name-Realm"] = "rating|rank|tierKey|badges(comma)|flags" } }
-- flags bit 1 = ladder-banned. `confirmed` (F2) lists the match IDs the site
-- confirmed in the last 30 days, space-separated.
local _, ns = ...
local L = ns.L

local Ladder = {}
ns.Ladder = Ladder

Ladder.ADDON = "DuelElo_Ladder"
Ladder.BANNED_FLAG = 1

-- Badge codes (shared with the site, F1). Season badges are "S<n><tier letter>".
Ladder.BADGES = {
    C1 = L["Champion"], T10 = L["Top 10"], T100 = L["Top 100"],
    FD = L["Founding Duelist"], RR = L["Realm Reporter"], W = L["Witness"],
}
local SEASON_TIERS = { C = L["Combatant"], H = L["Challenger"], R = L["Rival"], D = L["Duelist"], E = L["Elite"] }

-- "S1E" -> "Season 1 Elite"; known codes -> their names; anything else as is.
function Ladder.BadgeName(code)
    local season, tier = code:match("^S(%d+)(%u)$")
    if season and SEASON_TIERS[tier] then return L["Season %s %s"]:format(season, SEASON_TIERS[tier]) end
    return Ladder.BADGES[code] or code
end

function Ladder.Region(data, region)
    local r = type(data) == "table" and data[region]
    return type(r) == "table" and type(r.players) == "table" and r or nil
end

-- Parse one entry; nil if missing or malformed.
local function parse(raw)
    if type(raw) ~= "string" then return nil end
    local rating, rank, tier, badges, flags = raw:match("^(%d+)|(%d*)|(%u*)|([^|]*)|(%d*)$")
    if not rating then return nil end
    local list = {}
    for code in badges:gmatch("[^,]+") do list[#list + 1] = code end
    local f = tonumber(flags) or 0
    return {
        rating = tonumber(rating), rank = tonumber(rank), tierKey = tier ~= "" and tier or nil,
        badges = list, banned = math.floor(f / Ladder.BANNED_FLAG) % 2 == 1,
    }
end

-- The official entry for "Name-Realm" in a region, or nil.
function Ladder.Entry(data, region, name)
    local r = Ladder.Region(data, region)
    return r and parse(r.players[name]) or nil
end

-- Confirmed-match sets, parsed once per data table (weak keys: a reloaded
-- data addon gets a fresh set).
local confirmedSets = setmetatable({}, { __mode = "k" })

-- Whether the site confirmed this match (both players' signatures checked).
function Ladder.Confirmed(data, region, matchId)
    local r = Ladder.Region(data, region)
    if not r or type(r.confirmed) ~= "string" or type(matchId) ~= "string" then return false end
    local set = confirmedSets[r]
    if not set or set.source ~= r.confirmed then
        set = { source = r.confirmed, ids = {} }
        for id in r.confirmed:gmatch("[%w:]+") do set.ids[id] = true end
        confirmedSets[r] = set
    end
    return set.ids[matchId] == true
end

-- A History entry the community verified: a ranked duel whose match the site confirmed.
function Ladder.Verified(data, region, entry)
    return type(entry) == "table" and entry.ranked == true and Ladder.Confirmed(data, region, entry.match)
end

-- Ranked players of a region for the Official leaderboard view, best first:
-- { name, rating, rank, tierKey, badges, banned, marker }. Unranked entries
-- (banned or not yet eligible) come last, by rating.
function Ladder.Build(data, region)
    local r = Ladder.Region(data, region)
    local list = {}
    if not r then return list end
    for name, raw in pairs(r.players) do
        local e = parse(raw)
        if e then
            e.name = name
            list[#list + 1] = e
        end
    end
    table.sort(list, function(a, b)
        if (a.rank ~= nil) ~= (b.rank ~= nil) then return a.rank ~= nil end
        if a.rank and b.rank and a.rank ~= b.rank then return a.rank < b.rank end
        if a.rating ~= b.rating then return a.rating > b.rating end
        return a.name < b.name
    end)
    for _, e in ipairs(list) do e.marker = ns.Leaderboard and ns.Leaderboard.Marker(e.rank) end
    return list
end
