-- Session.lua: the ranked-duel handshake between two DuelElo clients.
-- Pure logic (no WoW API): everything it needs comes in through `deps`, so
-- tests can wire two engines together and play both sides of a duel.
--
-- Flow
--   1. Both sides see the duel request (challenger via StartDuel, the challenged
--      via DUEL_REQUESTED) and send HELLO: protocol, nonce, rating, preference,
--      level and readiness.
--   2. Each side checks ranked eligibility (Rules) and consents to ranked or not
--      (automatically from the preference, or via the prompt) and sends RANK.
--      While pending, readiness changes are sent with READY.
--   3. The challenged side LOCKS the decision when it accepts the duel: ranked
--      only if both consented by then and neither side has a baseline
--      readiness problem. It tells the challenger, who adopts it.
--   4. After the duel, Result() says whether it counted and the opponent's rating.
--   5. After a ranked result both sides sign the canonical match statement
--      (Statement.lua). The challenger is the time authority: it signs first and
--      sends S with its times; the challenged signs the same statement if the
--      times are within 15 s of its own (else, or after 10 s without the
--      challenger's S, it signs its own times: the server will see a mismatch).
--      Signatures arriving later than 60 s after the result are ignored.
--
-- Messages ("~"-separated; nonces tie replies to this duel, not an older one)
--   H~2~nonce~role~rating~games~pref~class~w~l~spec~ilvl~fp~level~ready   hello (role C/D)
--     A protocol 1 hello (H~1~…, 10–12 fields) is from an outdated client: its
--     stats are kept but the duel can only be casual.
--   Y~theirNonce~ready                               readiness changed while pending
--   R~theirNonce~1|0~reason                          ranked consent (reasons: see Rules.REASONS)
--   L~theirNonce~R|C~cReady~dReady                   lock: ranked or casual (challenged -> challenger),
--                                                    with the readiness masks both sides then sign
--   S~matchId~tStart~tEnd~sig                        my HMAC of the match statement (after a ranked result)
--   P~rating~games~class~w~l                         player stats (after matches, gossip)
local _, ns = ...
local Readiness, Statement = ns.Readiness, ns.Statement

local Session = {}
ns.Session = Session

Session.PROTO = 2
Session.OLD_PROTO = 1          -- still understood, casual only
Session.HELLO_TTL = 30        -- keep an early HELLO this long, waiting for our duel event
Session.FINISH_GRACE = 5      -- after DUEL_FINISHED, wait this long for the winner message
Session.STALE = 180           -- drop a never-locked session after this long
Session.MAX_LEN = 255
Session.SIGN_WAIT = 10         -- challenged side waits this long for the challenger's times
Session.SIGN_WINDOW = 60       -- accept the opponent's signature this long after the result
Session.TIME_TOLERANCE = 15    -- challenger times accepted if this close to ours (seconds)

local SEP = "~"
local PREF_CODE = { always = "A", ask = "K", never = "N" }
local PREF_NAME = { A = "always", K = "ask", N = "never" }

local function split(msg)
    local t = {}
    for field in (msg .. SEP):gmatch("(.-)" .. SEP) do t[#t + 1] = field end
    return t
end

local function int(s, lo, hi)
    local n = tonumber(s)
    if not n or n ~= math.floor(n) or n < lo or n > hi then return nil end
    return n
end

local function classToken(s)
    if type(s) == "string" and s:match("^%u+$") and #s <= 16 then return s end
    return nil
end

-- Parse rating, games, class, w, l starting at fields[i]. nil if invalid.
local function parseStats(f, i)
    local rating, games = int(f[i], 0, 5000), int(f[i + 1], 0, 1000000)
    local w, l = int(f[i + 3], 0, 1000000), int(f[i + 4], 0, 1000000)
    if not (rating and games and w and l) then return nil end
    return { rating = rating, games = games, class = classToken(f[i + 2]), w = w, l = l }
end

function Session.EncodeStats(me)
    return ("P~%d~%d~%s~%d~%d"):format(me.rating, me.games, me.class or "", me.w or 0, me.l or 0)
end

function Session.DecodeStats(text)
    if type(text) ~= "string" or #text > Session.MAX_LEN then return nil end
    local f = split(text)
    if f[1] ~= "P" then return nil end
    return parseStats(f, 2)
end

---------------------------------------------------------------------------
-- Engine
---------------------------------------------------------------------------

local Engine = {}
Engine.__index = Engine

-- deps:
--   me()               -> { rating, games, class, w, l, spec, ilvl }   (ranked stats)
--   pref()             -> "always" | "ask" | "never"
--   farmAllowed(opp)   -> bool (anti-farm limit not reached vs opp)
--   eligible(opp, peer) -> ok, reasonCode (Rules.Check; optional, default ok)
--   readiness()        -> mask, counts, unknown (our readiness now; optional, default ready)
--   level()            -> our level or nil
--   fp()               -> our key fingerprint (32 hex) or nil
--   strict()           -> bool: refuse ranked while either side has cooldowns down
--   send(target, msg)  whisper an addon message
--   now()              -> seconds
--   nonce()            -> short random string
--   onChange(session)  the prompt UI should redraw (session may be nil)
--   onPeer(name, stats) a player's stats were learned (leaderboard)
-- Signing (optional; without `sign` nothing is signed):
--   sign(statement)    -> our HMAC hex of a statement
--   myName()           -> our "Name-Realm";  region() -> region id
--   serverTime()       -> GetServerTime()
--   after(sec, fn)     run fn later (the challenged side's 10 s fallback)
--   onSigned(matchId, fields) signature fields arrived after Result() returned
function Session.New(deps)
    return setmetatable({ deps = deps, stash = {}, signing = {}, sigStash = {} }, Engine)
end

function Engine:_changed()
    if self.deps.onChange then self.deps.onChange(self.session) end
end

function Engine:_expire()
    local s, now = self.session, self.deps.now()
    if s and ((s.finishedAt and now - s.finishedAt > Session.FINISH_GRACE)
        or (not s.locked and now - s.startedAt > Session.STALE)) then
        self.session = nil
        self:_changed()
    end
    for name, st in pairs(self.stash) do
        if now - st.t > Session.HELLO_TTL then self.stash[name] = nil end
    end
    for id, rec in pairs(self.signing) do
        if now > rec.deadline then self.signing[id] = nil end
    end
    for name, st in pairs(self.sigStash) do
        if now - st.t > Session.SIGN_WINDOW then self.sigStash[name] = nil end
    end
end

function Engine:_send(msg)
    self.deps.send(self.session.opp, msg)
end

function Engine:_sendConsent(yes, reason)
    local s = self.session
    s.myConsent, s.myReason = yes, reason
    self:_send(("R~%s~%s~%s"):format(s.theirNonce, yes and "1" or "0", reason or ""))
end

-- Strict preference: no ranked while either side has an informational
-- readiness problem (cooldowns or trinkets down).
function Engine:_strictBlocked()
    local s = self.session
    if not (self.deps.strict and self.deps.strict()) then return false end
    return Readiness.Info(s.myReady or 0) ~= 0 or Readiness.Info(s.theirReady or 0) ~= 0
end

-- Answer automatically if the rules, the preference or the farm limit decide
-- it. Re-run whenever either side's readiness changes, for the Strict rule.
function Engine:_autoConsent()
    local s = self.session
    if s.locked or s.status ~= "pending" then return end
    if s.myConsent == true and self:_strictBlocked() then
        -- withdraw; we may agree again once everything is ready
        self:_sendConsent(false, "U")
        s.myConsent = nil
        return
    end
    if s.myConsent ~= nil then return end
    if s.ineligible then
        self:_sendConsent(false, s.ineligible)
    elseif not self.deps.farmAllowed(s.opp) then
        self:_sendConsent(false, "F")
    elseif self.deps.pref() == "never" then
        self:_sendConsent(false, "N")
    elseif self.deps.pref() == "always" and not self:_strictBlocked() then
        self:_sendConsent(true)
    end
end

-- Our readiness right now (mask, counts, unknown); counts/unknown are for our UI.
function Engine:_readMine()
    if not self.deps.readiness then return 0 end
    local mask, counts, unknown = self.deps.readiness()
    local s = self.session
    s.myReady, s.myCounts, s.myUnknown = mask or Readiness.ALL_BITS, counts, unknown
    return s.myReady
end

-- Parse a hello's stats. Protocol 1 hellos stop after ilvl.
local function parseHello(f)
    local stats = {
        rating = int(f[5], 0, 5000), games = int(f[6], 0, 1000000), pref = PREF_NAME[f[7]],
        class = classToken(f[8]), w = int(f[9], 0, 1000000), l = int(f[10], 0, 1000000),
        spec = int(f[11], 1, 100000), ilvl = int(f[12], 1, 10000),
    }
    if not (stats.rating and stats.games and stats.w and stats.l) then return nil end
    return stats
end

local function validNonce(nonce)
    return nonce and nonce ~= "" and #nonce <= 16 and not nonce:find(SEP, 1, true)
end

function Engine:_hello(f)
    local s = self.session
    local proto = int(f[2], 0, 1000)
    if proto ~= Session.PROTO and proto ~= Session.OLD_PROTO then
        s.peer = { proto = proto }
        s.status = "incompatible"
        return
    end
    local stats, nonce = parseHello(f), f[3]
    if not stats or not validNonce(nonce) then return end
    if self.deps.onPeer then self.deps.onPeer(s.opp, stats) end
    stats.proto = proto
    if proto == Session.OLD_PROTO then
        s.peer, s.status = stats, "outdated"  -- they need to update for ranked
        return
    end
    -- v2: fp (32 hex, empty until signing keys exist), level, readiness mask
    stats.fp = (f[13] or ""):match("^%x+$") and #f[13] == 32 and f[13]:lower() or nil
    stats.level = int(f[14], 1, 100)
    s.theirReady = Readiness.Decode(f[15]) or Readiness.ALL_BITS  -- unreadable: not ready
    s.peer, s.theirNonce = stats, nonce
    s.status = "pending"
    if self.deps.eligible then
        local okay, code = self.deps.eligible(s.opp, stats)
        if not okay then s.ineligible = code or "L" end
    end
    self:_autoConsent()
end

-- masks: { c, d } readiness at lock time, as signed in the match statement.
function Engine:_lock(ranked, masks)
    local s = self.session
    s.locked = true
    s.status = ranked and "ranked" or "casual"
    local mine, theirs = s.myReady or 0, s.theirReady or 0
    s.lockMasks = masks or (s.role == "C" and { c = mine, d = theirs } or { c = theirs, d = mine })
end

---------------------------------------------------------------------------
-- Inputs from the game
---------------------------------------------------------------------------

-- A duel request involving `opp` was seen. role: "C" (we challenged) or "D".
function Engine:Start(opp, role)
    self:_expire()
    local me = self.deps.me()
    local s = { opp = opp, role = role, myNonce = self.deps.nonce(), startedAt = self.deps.now(), status = "noaddon" }
    self.session = s
    self:_readMine()
    -- what we announce is what we later sign (cPre/dPre, level)
    s.myRating, s.myLevel, s.myFp = me.rating, self.deps.level and self.deps.level(), self.deps.fp and self.deps.fp()
    self:_send(("H~%d~%s~%s~%d~%d~%s~%s~%d~%d~%s~%s~%s~%s~%d"):format(Session.PROTO, s.myNonce, role,
        me.rating, me.games, PREF_CODE[self.deps.pref()] or "K", me.class or "", me.w or 0, me.l or 0,
        me.spec or "", me.ilvl or "", s.myFp or "", s.myLevel or "", s.myReady or 0))
    local early = self.stash[opp]
    if early then
        self.stash[opp] = nil
        self:_hello(early.fields)
    end
    self:_changed()
end

-- Poll result: our readiness may have changed. Tells the opponent while the
-- decision is still open.
function Engine:UpdateReadiness()
    local s = self.session
    if not s or s.locked then return end
    local before = s.myReady
    self:_readMine()
    if s.myReady == before then return end
    if s.status == "pending" and s.theirNonce then
        self:_send(("Y~%s~%d"):format(s.theirNonce, s.myReady))
        self:_autoConsent()
    end
    self:_changed()
end

-- Should readiness be polled now? Only while a ranked decision is open.
function Engine:Polling()
    local s = self.session
    return s ~= nil and s.status == "pending" and not s.locked and not s.ineligible
end

-- Could we agree to ranked right now? (drives the prompt's Ranked button)
function Engine:CanConsent()
    local s = self.session
    return s ~= nil and s.status == "pending" and s.theirNonce ~= nil and not s.locked and not s.countdown
        and s.myConsent == nil and not s.ineligible and self.deps.farmAllowed(s.opp) and not self:_strictBlocked()
end

-- The player answered the prompt.
function Engine:Consent(yes)
    self:_expire()
    local s = self.session
    if not s or s.status ~= "pending" or not s.theirNonce or s.locked or s.countdown or s.myConsent ~= nil then
        return false
    end
    if yes and (s.ineligible or not self.deps.farmAllowed(s.opp) or self:_strictBlocked()) then return false end
    self:_sendConsent(yes, (not yes) and "D" or nil)
    self:_changed()
    return true
end

-- We (the challenged side) accepted the duel: the decision is final now.
function Engine:Accepted()
    self:_expire()
    local s = self.session
    if not s or s.role ~= "D" or s.locked then return end
    self:_readMine()  -- fresh: the 1 s poll may be behind the click
    local ranked = s.status == "pending" and s.myConsent == true and s.theirConsent == true
        and not self:_strictBlocked()
        and Readiness.Baseline(s.myReady or 0) == 0 and Readiness.Baseline(s.theirReady or 0) == 0
    self:_lock(ranked)
    if s.theirNonce then
        self:_send(("L~%s~%s~%d~%d"):format(s.theirNonce, ranked and "R" or "C", s.lockMasks.c, s.lockMasks.d))
    end
    self:_changed()
end

-- The duel countdown started. The challenged side locks now if Accepted() was
-- missed; the challenger can no longer change its mind and waits for the lock.
function Engine:FightStarted()
    local s = self.session
    if s and not s.tStart and self.deps.serverTime then s.tStart = self.deps.serverTime() end
    if not s or s.locked then return end
    if s.role == "D" then
        self:Accepted()
    elseif not s.countdown then
        s.countdown = true
        self:_changed()
    end
end

-- DUEL_FINISHED: the winner message may still be on its way.
function Engine:Finished()
    local s = self.session
    if s and not s.finishedAt then s.finishedAt = self.deps.now() end
end

-- The duel vs `opp` ended. Returns { ranked, oppRating, matchId, peer, myReady,
-- theirReady, sign } where matchId ("challengerNonce:challengedNonce") is
-- identical on both clients, so a server can pair the two players' reports.
-- result ("W"/"L") and how ("KO"/"FLED") are needed to sign a ranked match;
-- `sign` then holds the signature fields known so far (statement, sigC/sigD,
-- fpC/fpD); later ones arrive through deps.onSigned.
function Engine:Result(opp, result, how)
    self:_expire()
    local s = self.session
    if not s or s.opp ~= opp then return { ranked = false } end
    self.session = nil
    self:_changed()
    local matchId
    if s.theirNonce then
        matchId = s.role == "C" and (s.myNonce .. ":" .. s.theirNonce) or (s.theirNonce .. ":" .. s.myNonce)
    end
    local ranked = s.locked == true and s.status == "ranked"
    return {
        ranked = ranked,
        oppRating = s.peer and s.peer.rating,
        matchId = matchId,
        peer = s.peer,
        myReady = s.theirNonce and s.myReady,       -- readiness masks, recorded with the match
        theirReady = s.theirNonce and s.theirReady,
        sign = ranked and result and how and self:_beginSigning(s, matchId, result, how) or nil,
    }
end

---------------------------------------------------------------------------
-- Signing the match statement
---------------------------------------------------------------------------

-- Signature fields go to the caller of Result() while it runs, and through
-- deps.onSigned afterwards (the duel entry exists by then).
function Engine:_notify(rec, fields)
    if self.collecting then
        for k, v in pairs(fields) do self.collecting[k] = v end
    elseif self.deps.onSigned then
        self.deps.onSigned(rec.matchId, fields)
    end
end

-- Sign the statement with the given times and send it.
function Engine:_signAndSend(rec, tStart, tEnd)
    rec.fields.tStart, rec.fields.tEnd = tStart, tEnd
    local statement = Statement.Match(rec.fields)
    if not statement then return false end
    local sig = self.deps.sign(statement)
    if not sig then return false end
    rec.statement, rec.mine = statement, sig
    self.deps.send(rec.opp, ("S~%s~%d~%d~%s"):format(rec.matchId, tStart, tEnd, sig))
    self:_notify(rec, { statement = statement, [rec.role == "C" and "sigC" or "sigD"] = sig })
    return true
end

local function near(a, b)
    return math.abs(a - b) <= Session.TIME_TOLERANCE
end

-- The opponent's S for a match we're signing.
function Engine:_theirSignature(rec, tStart, tEnd, sig)
    if rec.theirs ~= nil then return end  -- (records expire after SIGN_WINDOW in _expire)
    local theirKey = rec.role == "C" and "sigD" or "sigC"
    if rec.role == "D" and not rec.mine then
        -- the challenger's times: adopt them if they agree with what we saw
        local o = rec.observed
        local startOk = tStart == 0 or o.tStart == 0 or near(tStart, o.tStart)
        if startOk and near(tEnd, o.tEnd) then
            if self:_signAndSend(rec, tStart, tEnd) then
                rec.theirs = sig
                self:_notify(rec, { [theirKey] = sig })
            end
            return
        end
        self:_signAndSend(rec, o.tStart, o.tEnd)
    end
    if rec.fields.tStart == tStart and rec.fields.tEnd == tEnd then
        rec.theirs = sig
        self:_notify(rec, { [theirKey] = sig })
    else
        rec.theirs = false
        self:_notify(rec, { sigMismatch = true })  -- different statements: the server disputes it
    end
end

function Engine:_beginSigning(s, matchId, result, how)
    local d = self.deps
    if not (d.sign and matchId and s.peer) then return nil end
    local c = s.role == "C"
    local masks = s.lockMasks or {}
    local rec = {
        matchId = matchId, opp = s.opp, role = s.role,
        deadline = d.now() + Session.SIGN_WINDOW,
        observed = { tStart = s.tStart or 0, tEnd = d.serverTime() },
        fields = {
            matchId = matchId, region = d.region(),
            challenger = c and d.myName() or s.opp, challenged = c and s.opp or d.myName(),
            level = c and s.myLevel or s.peer.level,
            winner = ((result == "W") == c) and "C" or "D", how = how,
            cPre = c and s.myRating or s.peer.rating, dPre = c and s.peer.rating or s.myRating,
            cReady = masks.c, dReady = masks.d,
        },
    }
    self.signing[matchId] = rec
    self.collecting = { fpC = c and s.myFp or s.peer.fp, fpD = c and s.peer.fp or s.myFp }
    if c then
        self:_signAndSend(rec, rec.observed.tStart, rec.observed.tEnd)
    else
        local early = self.sigStash[s.opp]
        self.sigStash[s.opp] = nil
        if early and early.matchId == matchId then
            self:_theirSignature(rec, early.tStart, early.tEnd, early.sig)
        elseif d.after then
            d.after(Session.SIGN_WAIT, function()
                if not rec.mine and self.signing[matchId] == rec then self:_signAndSend(rec, rec.observed.tStart, rec.observed.tEnd) end
            end)
        end
    end
    local fields = self.collecting
    self.collecting = nil
    return fields
end

-- S~matchId~tStart~tEnd~sig
function Engine:_onSignature(sender, f)
    local matchId, tStart, tEnd, sig = f[2], int(f[3], 0, 2 ^ 40), int(f[4], 0, 2 ^ 40), f[5]
    if not (matchId and tStart and tEnd and type(sig) == "string" and #sig == 64 and not sig:find("[^0-9a-f]")) then
        return
    end
    local rec = self.signing[matchId]
    if rec then
        if rec.opp == sender then self:_theirSignature(rec, tStart, tEnd, sig) end
        return
    end
    -- may arrive before our own winner message: keep it for _beginSigning
    local s = self.session
    if s and s.opp == sender and s.role == "D" then
        self.sigStash[sender] = { matchId = matchId, tStart = tStart, tEnd = tEnd, sig = sig, t = self.deps.now() }
    end
end

function Engine:OnMessage(sender, text)
    self:_expire()
    if type(sender) ~= "string" or type(text) ~= "string" or #text > Session.MAX_LEN then return end
    local f = split(text)
    local kind = f[1]

    if kind == "P" then
        local stats = parseStats(f, 2)
        if stats and self.deps.onPeer then self.deps.onPeer(sender, stats) end
        return
    end

    if kind == "S" then return self:_onSignature(sender, f) end

    local s = self.session
    if kind == "H" then
        if s and s.opp == sender then
            if not s.peer then
                self:_hello(f)
                self:_changed()
            end
        else
            -- Arrived before our own duel event; only acted on if that event follows.
            self.stash[sender] = { fields = f, t = self.deps.now() }
        end
        return
    end

    if not s or s.opp ~= sender or s.locked then return end
    if kind == "R" and f[2] == s.myNonce and (f[3] == "1" or f[3] == "0") then
        s.theirConsent = f[3] == "1"
        s.theirReason = f[4] ~= "" and f[4] or nil
        self:_changed()
    elseif kind == "Y" and f[2] == s.myNonce and s.status == "pending" then
        local mask = Readiness.Decode(f[3])
        if not mask then return end
        s.theirReady = mask
        self:_autoConsent()
        self:_changed()
    elseif kind == "L" and s.role == "C" and f[2] == s.myNonce and (f[3] == "R" or f[3] == "C") then
        local c, d = Readiness.Decode(f[4]), Readiness.Decode(f[5])
        self:_lock(f[3] == "R" and s.myConsent == true, c and d and { c = c, d = d } or nil)
        self:_changed()
    end
end
