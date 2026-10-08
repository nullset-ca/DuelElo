-- Readiness.lua: is a player fit to start a ranked duel? (no WoW API)
-- The adapter (ReadinessAdapter.lua) reads the client into a plain inputs
-- table; this module turns it into the bit mask both players exchange.
-- Decision D2: baseline checks are enforced, cooldowns are informational.
local _, ns = ...
local L = ns.L

local Readiness = {}
ns.Readiness = Readiness

-- Bits of *failed* checks; 0 means ready. Values are part of protocol v2 (§2.3).
local B = { HEALTH = 1, POWER = 2, COOLDOWNS = 4, TRINKETS = 8, BANNED = 16, COMBAT = 32 }
Readiness.BITS = B
Readiness.BASELINE_BITS = B.HEALTH + B.POWER + B.BANNED + B.COMBAT  -- block ranked
Readiness.INFO_BITS = B.COOLDOWNS + B.TRINKETS                       -- shown, never block
Readiness.ALL_BITS = Readiness.BASELINE_BITS + Readiness.INFO_BITS

Readiness.HEALTH_MIN = 0.95
Readiness.MANA_MIN = 0.95

-- Plain arithmetic instead of the `bit` library: the probe still has to
-- confirm `bit` exists on Forever, and masks are only 6 bits wide.
function Readiness.Has(mask, b)
    return math.floor(mask / b) % 2 == 1
end

local function only(mask, set)
    local out = 0
    for _, b in pairs(B) do
        if Readiness.Has(mask, b) and Readiness.Has(set, b) then out = out + b end
    end
    return out
end

function Readiness.Baseline(mask) return only(mask, Readiness.BASELINE_BITS) end
function Readiness.Info(mask) return only(mask, Readiness.INFO_BITS) end

-- inputs: every field may be nil, meaning "couldn't read it" (API missing or a
-- secret value). An unreadable check counts as failed, and is remembered in
-- `unknown` so the prompt can say "health ?" rather than claim a number.
--   inCombat  boolean
--   health    fraction 0..1
--   mana      fraction 0..1, or false when the character has no mana pool
--   cooldowns count of long (>= 60 s base) spell cooldowns still running
--   trinkets  count of equipped trinkets on cooldown
--   banned    count of banned auras on the player
-- Returns mask, counts ({cooldowns, trinkets, banned}), unknown (bit -> true).
function Readiness.Evaluate(inputs)
    local mask, unknown = 0, {}
    local function fail(b, isUnknown)
        mask = mask + b
        if isUnknown then unknown[b] = true end
    end

    if inputs.inCombat == nil then fail(B.COMBAT, true) elseif inputs.inCombat then fail(B.COMBAT) end

    if type(inputs.health) ~= "number" then fail(B.HEALTH, true)
    elseif inputs.health < Readiness.HEALTH_MIN then fail(B.HEALTH) end

    if inputs.mana == nil then fail(B.POWER, true)
    elseif inputs.mana ~= false and inputs.mana < Readiness.MANA_MIN then fail(B.POWER) end

    local counts = { cooldowns = inputs.cooldowns, trinkets = inputs.trinkets, banned = inputs.banned }
    for _, c in ipairs({ { B.COOLDOWNS, "cooldowns" }, { B.TRINKETS, "trinkets" }, { B.BANNED, "banned" } }) do
        local n = inputs[c[2]]
        if type(n) ~= "number" then fail(c[1], true) elseif n > 0 then fail(c[1]) end
    end
    return mask, counts, unknown
end

-- A mask from the wire: an integer 0..63, anything else is rejected (nil).
function Readiness.Decode(s)
    local n = tonumber(s)
    if not n or n ~= math.floor(n) or n < 0 or n > Readiness.ALL_BITS then return nil end
    return n
end

local LABELS = {
    { B.COMBAT, L["in combat"] }, { B.HEALTH, L["health"] }, { B.POWER, L["mana"] },
    { B.BANNED, L["banned buff"], L["banned buffs"], "banned" },
    { B.COOLDOWNS, L["cooldown"], L["cooldowns"], "cooldowns" },
    { B.TRINKETS, L["trinket"], L["trinkets"], "trinkets" },
}

-- Human-readable problems for a mask, split into baseline and informational
-- lists. counts/unknown are only known for our own side; the opponent's
-- side comes from the wire as a bare mask.
function Readiness.Problems(mask, counts, unknown)
    local baseline, info = {}, {}
    for _, l in ipairs(LABELS) do
        local b, one, many, key = l[1], l[2], l[3], l[4]
        if Readiness.Has(mask, b) then
            local text = one
            local n = key and counts and counts[key]
            if unknown and unknown[b] then
                text = L["%s ?"]:format(many or one)
            elseif type(n) == "number" and n > 0 then
                text = L["%d %s"]:format(n, n == 1 and one or many)
            elseif many then
                text = many
            end
            local list = Readiness.Has(Readiness.BASELINE_BITS, b) and baseline or info
            list[#list + 1] = text
        end
    end
    return baseline, info
end

-- "Ready" or "Not ready: health, 2 cooldowns" (baseline problems first).
function Readiness.Describe(mask, counts, unknown)
    if mask == 0 then return L["Ready"] end
    local baseline, info = Readiness.Problems(mask, counts, unknown)
    for _, t in ipairs(info) do baseline[#baseline + 1] = t end
    return L["Not ready: %s"]:format(table.concat(baseline, ", "))
end
