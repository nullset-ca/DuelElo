-- Data.lua: SavedVariables schema, migrations and record keeping (no WoW API).
local _, ns = ...

local Data = {}
ns.Data = Data

Data.SCHEMA = 2
Data.MAX_HISTORY = 1000   -- detailed entries kept; totals are kept forever

local function newChar()
    return {
        schema = Data.SCHEMA,
        duels = {},           -- oldest first: { t, opp, class, result = "W"|"L", how = "KO"|"FLED" }
        totals = { w = 0, l = 0 },
        byClass = {},         -- [classFile] = { w, l }
        byOpp = {},           -- ["Name-Realm"] = { w, l, last, class }
        streak = 0,           -- >0 win streak, <0 loss streak
        bestStreak = 0,
        rating = ns.Elo.START,   -- displayed estimate: glicko.r rounded
        glicko = ns.Glicko.New(), -- { r, rd, sigma }: the local Glicko-2 estimate
        lastRanked = 0,           -- time of the last ranked game (RD grows while idle)
        rankedGames = 0,
        rankedW = 0,
        rankedL = 0,
        peak = 0,             -- highest rating after placements
        rankedLog = {},       -- ["Name-Realm"] = { timestamps of recent ranked games }
        witnesses = {},       -- oldest first: { t, statement, sig, fp } duels we saw nearby (SPEC §3.5)
        -- lastExport = time of the last upload code (records after it are "new")
        reports = {},         -- oldest first: { t, target, matchId, reason, note } (uploaded with the next code)
        loadouts = {},        -- [hash] = { fmt, gear, talents, spec, ilvl, t }: builds duels refer to (SPEC §3.13)
        -- legacy = { rating, games, w, l, peak }: test-era Elo, archived by schema 2
    }
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function newAccount()
    return {
        schema = Data.SCHEMA,
        settings = {
            chatSummary = true,
            resultsScreen = true,
            resultsScale = 0.8,
            rankedPref = "ask",   -- "always" | "ask" | "never"
            shareChannel = true,  -- share/receive stats on the hidden realm-wide channel
            strict = false,       -- refuse ranked while either side has cooldowns down
            uploadNudges = true,  -- remind to upload unverified ranked duels (SPEC §3.7)
            sounds = {},          -- [moment] = sound kit id, overrides the defaults
            widget = copy(ns.WidgetModel.DEFAULTS),  -- rank widget (SPEC §3.11)
        },
        players = {},             -- ["Name-Realm"] = { rating, games, class, spec, w, l, seen, source }
        dev = false,              -- developer commands (demo, test, art, debug)
        characters = {},          -- our own characters: ["Name-Realm"] = { class, level, fp }
    }
end

-- Fill any missing or corrupted fields with defaults, without touching valid data.
local function repair(db, defaults)
    for k, v in pairs(defaults) do
        if type(db[k]) ~= type(v) then
            db[k] = v
        elseif type(v) == "table" then
            repair(db[k], v)
        end
    end
    return db
end

-- Migrations: MIGRATIONS[n] upgrades a db from schema n-1 to n. Character and
-- account SavedVariables share the schema number but not the steps.
local CHAR_MIGRATIONS, ACCOUNT_MIGRATIONS = {}, {}

-- Schema 2 (v0.5): Elo -> Glicko-2. Test-era ratings are archived, not
-- converted (preseason reset, decision D3); duel history is kept as is.
CHAR_MIGRATIONS[2] = function(db)
    if type(db.rating) == "number" and (tonumber(db.rankedGames) or 0) > 0 then
        db.legacy = { rating = db.rating, games = db.rankedGames, w = db.rankedW, l = db.rankedL, peak = db.peak }
    end
    db.rating, db.rankedGames, db.rankedW, db.rankedL, db.peak = nil, nil, nil, nil, nil
    -- old ranked entries keep their Elo deltas for History, but no longer feed trends
    for _, e in ipairs(type(db.duels) == "table" and db.duels or {}) do
        if type(e) == "table" and e.ranked then e.legacy = true end
    end
    db.glicko, db.lastRanked = nil, nil
end

local function migrate(db, steps)
    local from = tonumber(db.schema) or 0
    for v = from + 1, Data.SCHEMA do
        if steps[v] then steps[v](db) end
    end
    db.schema = Data.SCHEMA
end

function Data.InitChar(db)
    if type(db) ~= "table" then return newChar() end
    migrate(db, CHAR_MIGRATIONS)
    return repair(db, newChar())
end

function Data.InitAccount(db)
    if type(db) ~= "table" then return newAccount() end
    migrate(db, ACCOUNT_MIGRATIONS)
    repair(db, newAccount())
    ns.WidgetModel.Validate(db.settings.widget)
    return db
end

local function bump(bucket, won)
    if won then bucket.w = bucket.w + 1 else bucket.l = bucket.l + 1 end
end

-- entry = { t = time(), opp = "Name-Realm", class = "WARRIOR"|nil, result = "W"|"L", how = "KO"|"FLED" }
function Data.Record(db, entry)
    local won = entry.result == "W"

    local duels = db.duels
    duels[#duels + 1] = entry
    while #duels > Data.MAX_HISTORY do table.remove(duels, 1) end

    bump(db.totals, won)

    if entry.class then
        db.byClass[entry.class] = db.byClass[entry.class] or { w = 0, l = 0 }
        bump(db.byClass[entry.class], won)
    end

    local o = db.byOpp[entry.opp] or { w = 0, l = 0 }
    db.byOpp[entry.opp] = o
    bump(o, won)
    o.last = entry.t
    o.class = entry.class or o.class

    if won then
        db.streak = db.streak > 0 and db.streak + 1 or 1
        if db.streak > db.bestStreak then db.bestStreak = db.streak end
    else
        db.streak = db.streak < 0 and db.streak - 1 or -1
    end
end

-- Pair weight of the next ranked game vs `opp` (Rules.PairWeight over our log).
function Data.PairWeight(db, opp, now)
    return ns.Rules.PairWeight(db.rankedLog[opp], now)
end

-- Anti-farming: ranked is only offered while the pair weight is above 0.
function Data.RankedAllowed(db, opp, now)
    return Data.PairWeight(db, opp, now) > 0
end

-- Apply a ranked result before recording it. Fills entry.ranked/before/after/
-- delta (and weight when below 1). oppGames estimates the opponent's RD.
-- At pair weight 0 the game is still recorded as ranked, with no change.
function Data.ApplyRanked(db, entry, oppRating, oppGames)
    local Elo, Glicko = ns.Elo, ns.Glicko
    local weight = Data.PairWeight(db, entry.opp, entry.t)
    local idleDays = db.lastRanked > 0 and (entry.t - db.lastRanked) / 86400 or 0
    local g = db.glicko
    local start = { r = g.r, rd = Glicko.Inflate(g.rd, idleDays), sigma = g.sigma }
    local opp = { r = oppRating, rd = Glicko.RDFromGames(oppGames) }
    db.glicko = Glicko.Update(start, opp, entry.result == "W" and 1 or 0, weight)

    entry.ranked = true
    entry.oppRating = oppRating
    entry.before = db.rating
    entry.after = Glicko.Round(db.glicko.r)
    entry.delta = entry.after - entry.before
    entry.weight = weight < 1 and weight or nil
    entry.placement = db.rankedGames < Elo.PLACEMENTS and (db.rankedGames + 1) or nil

    db.rating = entry.after
    db.lastRanked = entry.t
    db.rankedGames = db.rankedGames + 1
    if entry.result == "W" then db.rankedW = db.rankedW + 1 else db.rankedL = db.rankedL + 1 end
    if db.rankedGames >= Elo.PLACEMENTS and db.rating > db.peak then db.peak = db.rating end

    -- keep only timestamps the pair weight still reads
    local kept = {}
    for _, t in ipairs(db.rankedLog[entry.opp] or {}) do
        if entry.t - t < ns.Rules.PAIR_WINDOW then kept[#kept + 1] = t end
    end
    kept[#kept + 1] = entry.t
    db.rankedLog[entry.opp] = kept
    return true
end

Data.WITNESS_KEEP = 200

-- Keep a signed witness statement (newest 200, no duplicates). True if added.
function Data.AddWitness(db, w)
    for _, old in ipairs(db.witnesses) do
        if old.statement == w.statement then return false end
    end
    db.witnesses[#db.witnesses + 1] = w
    while #db.witnesses > Data.WITNESS_KEEP do table.remove(db.witnesses, 1) end
    return true
end

---------------------------------------------------------------------------
-- Reports (SPEC §3.6): kept locally and sent with the next upload
---------------------------------------------------------------------------

Data.REPORT_REASONS = { "THROWN", "HELP", "BANNED", "EXPLOIT", "OTHER" }
Data.REPORT_DAILY_MAX = 20
Data.REPORT_NOTE_MAX = 140     -- characters, not bytes
Data.REPORT_KEEP = 200

local VALID_REASON = {}
for _, r in ipairs(Data.REPORT_REASONS) do VALID_REASON[r] = true end

local function utf8Len(s)
    return select(2, s:gsub("[^\128-\191]", ""))
end

-- r = { target = "Name-Realm", reason = code, matchId = id or nil, note = text or nil }.
-- Returns true, or false and why: "reason", "target", "match", "note",
-- "duplicate" (that duel is already reported) or "limit" (20 a day).
function Data.AddReport(db, r, now)
    if not VALID_REASON[r.reason] then return false, "reason" end
    if type(r.target) ~= "string" or not r.target:match("^[^%-|%c]+%-[^|%c]+$") then return false, "target" end
    if r.matchId ~= nil and (type(r.matchId) ~= "string" or not r.matchId:match("^[%w:]+$") or #r.matchId > 40) then
        return false, "match"
    end
    -- no UI escape sequences or control characters in what we store
    local note = type(r.note) == "string" and r.note:gsub("[|%c]", ""):match("^%s*(.-)%s*$") or ""
    if utf8Len(note) > Data.REPORT_NOTE_MAX then return false, "note" end
    local today = 0
    for _, old in ipairs(db.reports) do
        if r.matchId and old.matchId == r.matchId then return false, "duplicate" end
        if now - old.t < 86400 then today = today + 1 end
    end
    if today >= Data.REPORT_DAILY_MAX then return false, "limit" end
    db.reports[#db.reports + 1] = { t = now, target = r.target, matchId = r.matchId, reason = r.reason,
        note = note ~= "" and note or nil }
    while #db.reports > Data.REPORT_KEEP do table.remove(db.reports, 1) end
    return true
end

function Data.Reported(db, matchId)
    for _, r in ipairs(db.reports) do
        if r.matchId == matchId then return true end
    end
    return false
end

-- Record one of our own characters in the account registry (ranked rules
-- refuse duels between characters of the same account). Keeps a known fp.
function Data.RegisterCharacter(account, full, class, level)
    if not full then return end
    local c = account.characters[full] or {}
    account.characters[full] = c
    c.class = class or c.class
    c.level = level or c.level
    return c
end

-- Forget players we haven't heard from in maxAge seconds (keeps SavedVariables small).
function Data.PrunePlayers(players, now, maxAge)
    local removed = 0
    for name, p in pairs(players) do
        if type(p) ~= "table" or (p.seen and now - p.seen > maxAge) then
            players[name] = nil
            removed = removed + 1
        end
    end
    return removed
end

function Data.WinRate(w, l)
    local n = w + l
    if n == 0 then return 0 end
    return w / n
end
