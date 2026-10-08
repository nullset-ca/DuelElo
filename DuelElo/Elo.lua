-- Elo.lua: rank tiers and placements (no WoW API). The name is historical:
-- rating math moved to Glicko.lua in v0.5; tiers are thresholds on the rating.
local _, ns = ...
local L = ns.L

local Elo = {}
ns.Elo = Elo

Elo.START = 1200
Elo.PLACEMENTS = 10      -- first N ranked games hide the rank ("Placements")

---------------------------------------------------------------------------
-- Ranks
---------------------------------------------------------------------------

-- Tiers from lowest to highest, named after (and drawn with) WoW's own rated-PvP
-- tier icons. Tiers with divisions split into IV..I, 50 points each.
Elo.TIERS = {
    { key = "COMBATANT",  name = L["Combatant"],  min = 0,    divisions = true,  color = { 0.78, 0.80, 0.84 } },
    { key = "CHALLENGER", name = L["Challenger"], min = 1200, divisions = true,  color = { 1.00, 0.80, 0.25 } },
    { key = "RIVAL",      name = L["Rival"],      min = 1400, divisions = true,  color = { 0.70, 0.82, 1.00 } },
    { key = "DUELIST",    name = L["Duelist"],    min = 1600, divisions = true,  color = { 0.25, 0.70, 1.00 } },
    { key = "ELITE",      name = L["Elite"],      min = 1800, divisions = false, color = { 0.72, 0.40, 1.00 } },
}
local DIV_SIZE = 50
local ROMAN = { "I", "II", "III", "IV" }
local FIRST_BASE = 1000  -- first tier's divisions start here; everything lower is its division IV

-- Returns { tier, key, name, division (4..1 or nil), label, color, progress (0..1), floor, ceil }.
-- progress is how far through the current division (or tier) the rating is.
function Elo.Rank(rating)
    local idx = 1
    for i = #Elo.TIERS, 1, -1 do
        if rating >= Elo.TIERS[i].min then idx = i break end
    end
    local t = Elo.TIERS[idx]
    local nextMin = Elo.TIERS[idx + 1] and Elo.TIERS[idx + 1].min

    local r = { tier = idx, key = t.key, name = t.name, color = t.color }
    if t.divisions then
        local base = idx == 1 and FIRST_BASE or t.min
        local step = math.floor((rating - base) / DIV_SIZE)
        if step < 0 then step = 0 end
        if step > 3 then step = 3 end
        r.division = 4 - step
        r.floor = base + step * DIV_SIZE
        r.ceil = base + (step + 1) * DIV_SIZE
        r.label = t.name .. " " .. ROMAN[r.division]
    else
        r.floor = t.min
        r.ceil = nextMin   -- nil for the top tier
        r.label = t.name
    end

    if r.ceil then
        local p = (rating - r.floor) / (r.ceil - r.floor)
        r.progress = math.max(0, math.min(1, p))
    else
        r.progress = 1
    end
    return r
end

-- Compare two ranks: 1 if b is higher than a, -1 if lower, 0 if the same.
function Elo.CompareRank(a, b)
    if a.tier ~= b.tier then return b.tier > a.tier and 1 or -1 end
    if (a.division or 0) ~= (b.division or 0) then return b.division < a.division and 1 or -1 end
    return 0
end
