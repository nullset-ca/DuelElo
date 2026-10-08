-- Rules.lua: may these two characters play a ranked duel? (no WoW API)
-- Ranked is offered only if every rule holds; otherwise the prompt explains
-- why and only Casual is possible. Each failure has a one-letter code that is
-- also sent as the reason in the R message (protocol v2, SPEC §2.3/§3.3).
local _, ns = ...
local L = ns.L

local Rules = {}
ns.Rules = Rules

Rules.PAIR_WINDOW = 7 * 86400
-- Rating weight of the next ranked game vs the same opponent, by how many
-- ranked games the pair already played in the trailing window.
Rules.PAIR_WEIGHTS = { 1, 0.5, 0.25 }

-- Prompt texts per reason code. L/A/B/U are new in protocol v2; F/N/D predate it.
Rules.REASONS = {
    L = L["Different levels"],
    A = L["Your own character"],
    B = L["Banned from the ranked ladder"],
    F = L["Ranked limit vs this opponent reached this week"],
    U = L["Not ready"],
    N = L["Ranked duels turned off"],
    D = L["Declined"],
}

function Rules.ReasonText(code)
    return Rules.REASONS[code] or L["Not available"]
end

-- Weight of the next ranked game vs one opponent: 1, 0.5, 0.25, then 0.
-- times: timestamps of earlier ranked games vs that opponent.
function Rules.PairWeight(times, now)
    local recent = 0
    for _, t in ipairs(times or {}) do
        if t <= now and now - t < Rules.PAIR_WINDOW then recent = recent + 1 end
    end
    return Rules.PAIR_WEIGHTS[recent + 1] or 0
end

-- Is `name` flagged ladder-banned in the official ladder data addon?
-- ladderData = DuelEloLadderData (may be nil); see Ladder.lua.
function Rules.LadderBanned(ladderData, region, name)
    local e = ns.Ladder.Entry(ladderData, region, name)
    return e ~= nil and e.banned
end

-- ctx:
--   myLevel, oppLevel   character levels (nil = unknown, which fails the level rule)
--   opp                 "Name-Realm" of the opponent
--   characters          account registry DuelEloDB.characters
--   oppBanned, meBanned ladder-banned flags
--   pairTimes, now      earlier ranked games vs opp, for the pair weight
-- Returns ok, reasonCode.
function Rules.Check(ctx)
    if not ctx.myLevel or ctx.myLevel ~= ctx.oppLevel then return false, "L" end
    if ctx.characters and ctx.characters[ctx.opp] then return false, "A" end
    if ctx.oppBanned or ctx.meBanned then return false, "B" end
    if Rules.PairWeight(ctx.pairTimes, ctx.now) <= 0 then return false, "F" end
    return true
end
