-- Duel.lua: duel detection (who we're fighting, countdown) and recording results.
local _, ns = ...
local L = ns.L
local Parse, Data = ns.Parse, ns.Data
local me = ns.me

local Duel = {}
ns.Duel = Duel

local opponentHint = nil  -- { full, class, t } captured when a duel is requested
local fightStartAt = nil  -- GetTime() when the current duel's countdown ends

local matchResult = Parse.Matcher({
    { kind = "KO",   fmt = DUEL_WINNER_KNOCKOUT },
    { kind = "FLED", fmt = DUEL_WINNER_RETREAT },
})
-- "Duel starting: 3": WoW announces the countdown as a system message.
local countdownPattern = Parse.CountdownPattern(DUEL_COUNTDOWN or "Duel starting: %d")

local SEARCH_UNITS = { "target", "focus", "mouseover" }
for i = 1, 40 do SEARCH_UNITS[#SEARCH_UNITS + 1] = "nameplate" .. i end

local function visible(full)
    for _, unit in ipairs(SEARCH_UNITS) do
        if ns.UnitFullName(unit) == full then return true end
    end
    return false
end

-- Look for the opponent among units we can see, to learn their class.
local function findClass(full)
    for _, unit in ipairs(SEARCH_UNITS) do
        if ns.UnitFullName(unit) == full then
            local classFile = ns.UnitClassFile(unit)
            if classFile then return classFile end
        end
    end
    return nil
end

function Duel.RememberOpponent(full, role)
    if not full then return end
    opponentHint = { full = full, class = findClass(full), t = time() }
    fightStartAt = nil
    ns.Snapshot.Reset()
    ns.DPrint("Duel with " .. full .. " (class " .. tostring(opponentHint.class) .. ")")
    if ns.engine then ns.engine:Start(full, role) end
end

function ns.HandleSystemMessage(msg)
    if not me.full or type(msg) ~= "string" or ns.IsSecret(msg) then return end
    local secondsLeft = countdownPattern and msg:match(countdownPattern)
    if secondsLeft then
        if not fightStartAt then
            fightStartAt = GetTime() + (tonumber(secondsLeft) or 0)
            ns.Snapshot.Start(secondsLeft)  -- our build as the duel starts (SPEC §3.13)
        end
        if ns.engine then ns.engine:FightStarted() end
        return
    end
    local kind, winner, loser = matchResult(msg)
    if not kind then return end

    winner, loser = Parse.Normalize(winner, me.realm), Parse.Normalize(loser, me.realm)
    local result, opp
    if winner == me.full then
        result, opp = "W", loser
    elseif loser == me.full then
        result, opp = "L", winner
    else
        return Duel.Witness(kind, winner, loser)  -- someone else's duel nearby
    end

    local class = findClass(opp)
    if not class and opponentHint and opponentHint.full == opp then class = opponentHint.class end
    opponentHint = nil

    local entry = { t = time(), opp = opp, class = class, result = result, how = kind }
    -- Extra detail for stats (and a future website): where, how long, gear, specs.
    local zone = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    entry.zone = (type(zone) == "number" and not ns.IsSecret(zone)) and zone or nil
    if fightStartAt then entry.secs = math.max(0, math.floor(GetTime() - fightStartAt + 0.5)) end
    fightStartAt = nil
    entry.spec, entry.ilvl = ns.Comm.MySpec(), ns.Comm.MyItemLevel()

    local ranked = ns.engine and ns.engine:Result(opp, result, kind)
    if ranked then
        entry.match = ranked.matchId
        -- signed statement (ranked only): statement, sigC/sigD, fpC/fpD so far
        for k, v in pairs(ranked.sign or {}) do entry[k] = v end
        if ranked.peer then
            entry.oppSpec, entry.oppIlvl = ranked.peer.spec, ranked.peer.ilvl
            entry.class = entry.class or ranked.peer.class
        end
        if ranked.ranked and ranked.oppRating then
            Data.ApplyRanked(ns.char, entry, ranked.oppRating, ranked.peer and ranked.peer.games)
        end
    end
    ns.Loadout.Attach(ns.char, entry, ns.Snapshot.Finish(), ns.char.key and ns.char.key.secret, entry.t)
    Data.Record(ns.char, entry)
    ns.Loadout.Prune(ns.char)
    ns.DPrint(("Recorded %s vs %s (%s%s)"):format(result, opp, kind, entry.ranked and ", ranked" or ""))
    if entry.ranked then ns.Comm.ShareStats(opp) end
    ns.Fire("DUEL_RECORDED", entry)
end

-- A duel between two other players finished near us (SPEC §3.5). Winner
-- messages only reach nearby clients; we also require seeing one of them (a
-- target, focus, mouseover or nameplate), so the zone we sign is theirs too.
-- Passive: nothing is shown, the signed statement goes into the next upload.
function Duel.Witness(kind, winner, loser)
    local key = ns.char.key
    if not (key and ns.myFp) or not (visible(winner) or visible(loser)) then return end
    local zone = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if ns.IsSecret(zone) then return end
    local st = ns.Statement.Witness({
        region = ns.account.region, witness = me.full, winner = winner, loser = loser, how = kind,
        t = GetServerTime and GetServerTime() or time(), zone = zone,
    })
    if not st then return end
    if Data.AddWitness(ns.char, { statement = st, sig = ns.Statement.Sign(key.secret, st), fp = ns.myFp, t = time() }) then
        ns.DPrint(("Witnessed %s vs %s"):format(winner, loser))
    end
end

-- The opponent's signature (or a mismatch) arrived after the duel was recorded.
-- Only the last few entries can still be signing (60 s window).
function Duel.OnSigned(matchId, fields)
    local duels = ns.char.duels
    for i = #duels, math.max(1, #duels - 20), -1 do
        local e = duels[i]
        if e.match == matchId then
            for k, v in pairs(fields) do e[k] = v end
            return
        end
    end
end

-- Catch duels we start (right-click menu and /duel both call StartDuel). The
-- menu passes a unit; "/duel" passes "" (meaning the target) and "/duel Name"
-- a player name. Hooked only if the client has StartDuel.
function Duel.OpponentFromDuelArg(arg)
    if type(arg) ~= "string" or ns.IsSecret(arg) or arg == "" then return ns.UnitFullName("target") end
    return ns.UnitFullName(arg) or ns.Parse.Normalize(arg, ns.me.realm)
end

if StartDuel then
    hooksecurefunc("StartDuel", function(arg)
        Duel.RememberOpponent(Duel.OpponentFromDuelArg(arg), "C")
    end)
end

-- Accepting a duel request locks the ranked decision.
if AcceptDuel then
    hooksecurefunc("AcceptDuel", function()
        if ns.engine then ns.engine:Accepted() end
    end)
end

-- Chat feedback after each duel (optional; the results screen is the main view).
ns.Listen(function(event, entry)
    if event ~= "DUEL_RECORDED" or not ns.account.settings.chatSummary then return end
    local t = ns.char.totals
    local verdict = entry.result == "W" and "|cff20ff20Victory|r" or "|cffff2020Defeat|r"
    local how = entry.how == "FLED" and (entry.result == "W" and L[" (they fled)"] or L[" (fled)"]) or ""
    ns.Print(L["%s vs %s%s. Record: %d-%d"]:format(verdict, ns.DisplayName(entry.opp), how, t.w, t.l))
end)
