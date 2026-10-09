-- WidgetModel.lua: what the rank widget shows, as plain data (no WoW API).
-- UI/Widget.lua only draws this model, so everything that decides *what* to
-- show (placements, progress, recent results, trend) is unit-tested here.
local _, ns = ...
local L = ns.L

local Model = {}
ns.WidgetModel = Model

Model.PRESETS = { full = true, compact = true, minimal = true }
Model.TRENDS = { number = true, sparkline = true, both = true, none = true }
Model.PERIODS = { session = true, today = true, last10 = true }
Model.RECENT_COUNTS = { [3] = true, [5] = true, [10] = true }
Model.SCALE_MIN, Model.SCALE_MAX = 0.5, 2
Model.OPACITY_MIN, Model.OPACITY_MAX = 0.3, 1
Model.LAST_N = 10  -- games in the "last 10 ranked games" period

Model.DEFAULTS = {
    shown = false,         -- opt-in: /duelelo widget show or the Options panel
    preset = "compact",
    trend = "number",      -- number | sparkline | both | none
    period = "session",    -- session | today | last10
    recent = 5,            -- result boxes: 3, 5 or 10
    casual = false,        -- include casual results in the boxes
    nameTag = false,
    fade = false,          -- fade to 40% while a duel is pending/active
    pulse = true,          -- pulse the delta when the rating changes
    scale = 1,
    opacity = 0.85,
    locked = false,        -- locks itself after the first drag
    placed = false,        -- has the player dragged it yet?
}

local function clamp(v, lo, hi, default)
    v = tonumber(v)
    if not v then return default end
    return math.max(lo, math.min(hi, v))
end

-- Fix out-of-range or unknown settings in place (SavedVariables are user-editable).
function Model.Validate(w)
    local d = Model.DEFAULTS
    w.scale = clamp(w.scale, Model.SCALE_MIN, Model.SCALE_MAX, d.scale)
    w.opacity = clamp(w.opacity, Model.OPACITY_MIN, Model.OPACITY_MAX, d.opacity)
    if not Model.PRESETS[w.preset] then w.preset = d.preset end
    if not Model.TRENDS[w.trend] then w.trend = d.trend end
    if not Model.PERIODS[w.period] then w.period = d.period end
    if not Model.RECENT_COUNTS[w.recent] then w.recent = d.recent end
    for _, k in ipairs({ "shown", "casual", "nameTag", "fade", "pulse", "locked", "placed" }) do
        if type(w[k]) ~= "boolean" then w[k] = d[k] end
    end
    return w
end

-- Official rating from the ladder data addon (SPEC §2.7), or nil.
function Model.OfficialRating(ladderData, region, name)
    local e = ns.Ladder.Entry(ladderData, region, name)
    return e and e.rating
end

-- Ranked results that count for the rating: test-era Elo entries (archived by
-- the schema 2 migration) are left out.
local function isRanked(e)
    return e.ranked == true and not e.legacy and type(e.delta) == "number"
end

-- Scale values to 0..1. A flat series sits in the middle.
function Model.Normalise(values)
    local lo, hi = math.huge, -math.huge
    for _, v in ipairs(values) do
        lo, hi = math.min(lo, v), math.max(hi, v)
    end
    local out = {}
    for i, v in ipairs(values) do
        out[i] = hi > lo and (v - lo) / (hi - lo) or 0.5
    end
    return out
end

-- Rating change and sparkline over the chosen period. Ratings are rebuilt
-- backwards from the current rating with each game's delta, so demo data
-- (deltas only) works the same as real data.
function Model.Trend(duels, rating, period, ctx)
    local games = {}
    for i = #duels, 1, -1 do
        local e = duels[i]
        if isRanked(e) then
            if period == "last10" then
                if #games >= Model.LAST_N then break end
            elseif period == "today" then
                if e.t < (ctx.dayStart or 0) then break end
            elseif e.t < (ctx.sessionStart or 0) then
                break
            end
            table.insert(games, 1, e)
        end
    end
    local value, ratings = 0, { rating }
    for i = #games, 1, -1 do
        value = value + games[i].delta
        table.insert(ratings, 1, ratings[1] - games[i].delta)
    end
    return { value = value, games = #games, points = #games > 0 and Model.Normalise(ratings) or {} }
end

-- The newest `n` results (oldest first, newest last).
function Model.Recent(duels, n, includeCasual)
    local out = {}
    for i = #duels, 1, -1 do
        if #out >= n then break end
        local e = duels[i]
        if isRanked(e) or (includeCasual and not e.ranked) then
            table.insert(out, 1, { result = e.result, fled = e.how == "FLED", ranked = isRanked(e), delta = e.delta })
        end
    end
    return out
end

-- char: a character DB (or demo data); w: validated widget settings;
-- ctx: { sessionStart, dayStart, official, name }.
function Model.Build(char, w, ctx)
    local Elo = ns.Elo
    local rating = ctx.official or char.rating
    local m = {
        rating = rating,
        official = ctx.official ~= nil,
        estimated = ctx.official == nil,
        name = ctx.name,
        rd = char.glicko and char.glicko.rd,
        record = { w = char.rankedW or 0, l = char.rankedL or 0 },
        peak = char.peak,
        recent = Model.Recent(char.duels, w.recent, w.casual),
        trend = Model.Trend(char.duels, char.rating, w.period, ctx),
    }
    if (char.rankedGames or 0) < Elo.PLACEMENTS and not m.official then
        m.tierKey, m.label = "UNRANKED", L["Placements"]
        m.placements = { done = char.rankedGames or 0, total = Elo.PLACEMENTS }
        return m
    end
    local r = Elo.Rank(rating)
    m.tierKey, m.label, m.color = r.key, r.label, r.color
    local progress = { fraction = r.progress }
    if r.ceil then
        progress.toNext = r.ceil - rating
        progress.nextLabel = Elo.Rank(r.ceil).label
    end
    m.progress = progress
    return m
end

-- "+38" / "-12" / "0". ASCII on purpose: WoW's default fonts have no ▲/▼/−
-- glyphs, so the UI adds arrow textures and colour around this text.
function Model.TrendText(value)
    if value > 0 then return ("+%d"):format(value) end
    if value < 0 then return ("-%d"):format(-value) end
    return "0"
end
