-- Glicko.lua: Glicko-2 rating math for the local estimate (no WoW API).
-- Mirrors packages/core/glicko (the server is authoritative); both are checked
-- against spec/vectors/glicko.json. Each ranked duel is its own rating period.
local _, ns = ...

local Glicko = {}
ns.Glicko = Glicko

Glicko.R0 = 1200
Glicko.RD0 = 350
Glicko.SIGMA0 = 0.06
Glicko.TAU = 0.5
Glicko.SCALE = 173.7178
Glicko.CLAMP = 400        -- opponent rating counted at most this far from ours
Glicko.RD_MAX = 350
Glicko.EPSILON = 0.000001
-- RD growth per idle day: an RD of 50 grows back to 350 in 180 days.
Glicko.C = math.sqrt((350 ^ 2 - 50 ^ 2) / 180)

function Glicko.New()
    return { r = Glicko.R0, rd = Glicko.RD0, sigma = Glicko.SIGMA0 }
end

-- RD after `days` without ranked games.
function Glicko.Inflate(rd, days)
    if not days or days <= 0 then return rd end
    return math.min(Glicko.RD_MAX, math.sqrt(rd ^ 2 + Glicko.C ^ 2 * days))
end

-- Hellos don't carry RD, so an opponent's RD is estimated from their games:
-- 350 for a new player, shrinking roughly as Glicko does with play.
function Glicko.RDFromGames(games)
    return math.max(60, Glicko.RD0 / math.sqrt(1 + (games or 0) / 2))
end

-- Season soft reset: halfway back to the start, and at least some uncertainty.
function Glicko.SoftReset(p)
    return { r = Glicko.R0 + 0.5 * (p.r - Glicko.R0), rd = math.max(p.rd, 150), sigma = p.sigma }
end

local PI2 = math.pi ^ 2

local function g(phi)
    return 1 / math.sqrt(1 + 3 * phi ^ 2 / PI2)
end

-- New volatility (Glickman's step 5, Illinois algorithm).
local function volatility(sigma, phi, v, delta)
    local tau = Glicko.TAU
    local a = math.log(sigma ^ 2)
    local function f(x)
        local ex = math.exp(x)
        return ex * (delta ^ 2 - phi ^ 2 - v - ex) / (2 * (phi ^ 2 + v + ex) ^ 2) - (x - a) / tau ^ 2
    end
    local A, B = a, nil
    if delta ^ 2 > phi ^ 2 + v then
        B = math.log(delta ^ 2 - phi ^ 2 - v)
    else
        local k = 1
        while f(a - k * tau) < 0 do k = k + 1 end
        B = a - k * tau
    end
    local fA, fB = f(A), f(B)
    while math.abs(B - A) > Glicko.EPSILON do
        local C = A + (A - B) * fA / (fB - fA)
        local fC = f(C)
        if fC * fB <= 0 then
            A, fA = B, fB
        else
            fA = fA / 2
        end
        B, fB = C, fC
    end
    return math.exp(A / 2)
end

-- One rating period. p = { r, rd, sigma }; games = list of { r, rd, score }
-- (score 1 win, 0 loss). Opponent ratings are clamped to p.r ± CLAMP.
-- Returns a new { r, rd, sigma }; p is not modified.
function Glicko.Rate(p, games)
    local mu, phi = (p.r - Glicko.R0) / Glicko.SCALE, p.rd / Glicko.SCALE
    if #games == 0 then
        local phiStar = math.sqrt(phi ^ 2 + p.sigma ^ 2)
        return { r = p.r, rd = math.min(Glicko.RD_MAX, phiStar * Glicko.SCALE), sigma = p.sigma }
    end
    local vInv, sum = 0, 0
    for _, o in ipairs(games) do
        local oppR = math.max(p.r - Glicko.CLAMP, math.min(p.r + Glicko.CLAMP, o.r))
        local muJ, phiJ = (oppR - Glicko.R0) / Glicko.SCALE, o.rd / Glicko.SCALE
        local gJ = g(phiJ)
        local E = 1 / (1 + math.exp(-gJ * (mu - muJ)))
        vInv = vInv + gJ ^ 2 * E * (1 - E)
        sum = sum + gJ * (o.score - E)
    end
    local v = 1 / vInv
    local delta = v * sum
    local sigma = volatility(p.sigma, phi, v, delta)
    local phiStar = math.sqrt(phi ^ 2 + sigma ^ 2)
    local phiNew = 1 / math.sqrt(1 / phiStar ^ 2 + 1 / v)
    local muNew = mu + phiNew ^ 2 * sum
    return {
        r = Glicko.SCALE * muNew + Glicko.R0,
        rd = math.min(Glicko.RD_MAX, Glicko.SCALE * phiNew),
        sigma = sigma,
    }
end

-- One ranked duel with a pair weight (1, 0.5, 0.25 or 0 — Rules.PairWeight):
-- rating, RD and volatility each move by `weight` times their full change.
function Glicko.Update(p, opp, score, weight)
    weight = weight or 1
    if weight <= 0 then return { r = p.r, rd = p.rd, sigma = p.sigma } end
    local full = Glicko.Rate(p, { { r = opp.r, rd = opp.rd, score = score } })
    return {
        r = p.r + weight * (full.r - p.r),
        rd = p.rd + weight * (full.rd - p.rd),
        sigma = p.sigma + weight * (full.sigma - p.sigma),
    }
end

-- Displayed rating: nearest whole point.
function Glicko.Round(r)
    return math.floor(r + 0.5)
end
