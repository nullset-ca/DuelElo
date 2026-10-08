-- Two Session engines wired through a fake network: A challenges B.
local ns = {}
assert(loadfile("DuelElo/Locale.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Crypto.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Statement.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Readiness.lua"))("DuelElo", ns)
assert(loadfile("DuelElo/Session.lua"))("DuelElo", ns)
local Session = ns.Session

local A, B = "Alice-Area52", "Bob-Sargeras"
local SECRETS = { [A] = ("a1"):rep(32), [B] = ("b2"):rep(32) }

-- opts: prefA/prefB, farmA/farmB (false = limit reached), statsA/statsB, protoB
-- Mutable per side: w.ready[name] (readiness mask), w.level[name], w.strict[name].
local function world(opts)
    opts = opts or {}
    local w = { clock = 1000, queue = {}, drop = {}, peers = {}, changes = 0, later = {},
        stime = { [A] = 1791500000, [B] = 1791500000 }, signed = { [A] = {}, [B] = {} },
        ready = { [A] = 0, [B] = 0 }, level = { [A] = 30, [B] = 30 }, strict = {} }
    local seq = 0
    local function engine(me, prefKey, farmKey, stats)
        return Session.New({
            me = function() return stats or { rating = 1200, games = 20, class = "MAGE", w = 12, l = 8 } end,
            pref = function() return opts[prefKey] or "ask" end,
            farmAllowed = function() return opts[farmKey] ~= false end,
            eligible = function(_, peer)
                if peer.level ~= w.level[me] then return false, "L" end
                return true
            end,
            readiness = function() return w.ready[me], {}, {} end,
            level = function() return w.level[me] end,
            fp = function()
                if opts.signing then return ns.Crypto.Fingerprint(SECRETS[me]) end
                return me == A and ("ab"):rep(16) or nil
            end,
            strict = function() return w.strict[me] end,
            sign = opts.signing and function(st) return ns.Statement.Sign(SECRETS[me], st) end or nil,
            myName = function() return me end,
            region = function() return 1 end,
            serverTime = function() return w.stime[me] end,
            after = function(sec, fn) w.later[#w.later + 1] = { at = w.clock + sec, fn = fn } end,
            onSigned = function(id, fields)
                local t = w.signed[me][id] or {}
                w.signed[me][id] = t
                for k, v in pairs(fields) do t[k] = v end
            end,
            send = function(target, msg)
                if w.drop[msg:sub(1, 1)] then return end
                w.queue[#w.queue + 1] = { from = me, to = target, msg = msg }
            end,
            now = function() return w.clock end,
            nonce = function() seq = seq + 1 return me:sub(1, 1) .. seq end,
            onChange = function() w.changes = w.changes + 1 end,
            onPeer = function(name, stats) w.peers[me .. ">" .. name] = stats end,
        })
    end
    w[A] = engine(A, "prefA", "farmA", opts.statsA)
    w[B] = engine(B, "prefB", "farmB", opts.statsB or { rating = 1500, games = 40, class = "ROGUE", w = 25, l = 15 })
    -- deliver everything in flight (and anything sent in response)
    function w.flush()
        while #w.queue > 0 do
            local m = table.remove(w.queue, 1)
            w[m.to]:OnMessage(m.from, m.msg)
        end
    end
    -- standard opening: both clients see the request, hellos are exchanged
    function w.open()
        w[A]:Start(B, "C")
        w[B]:Start(A, "D")
        w.flush()
    end
    return w
end

test("both agree before accept: ranked on both sides", function()
    local w = world()
    w.open()
    ok(w[A]:Consent(true))
    ok(w[B]:Consent(true))
    w.flush()
    w[B]:Accepted()
    w.flush()
    eq(w[A].session.status, "ranked")
    eq(w[B].session.status, "ranked")
    local ra, rb = w[A]:Result(B), w[B]:Result(A)
    eq(ra.ranked, true)
    eq(ra.oppRating, 1500)
    eq(rb.ranked, true)
    eq(rb.oppRating, 1200)
    ok(ra.matchId, "match id present")
    eq(ra.matchId, rb.matchId, "both sides derive the same match id")
end)

test("hello carries spec and item level; old-format hellos still work", function()
    local w = world({ statsB = { rating = 1500, games = 40, class = "ROGUE", w = 25, l = 15, spec = 260, ilvl = 612 } })
    w.open()
    eq(w[A].session.peer.spec, 260)
    eq(w[A].session.peer.ilvl, 612)
    w[B]:Start(A, "D")
    w.queue = {}
    w[B]:OnMessage(A, "H~1~old1~C~1300~12~K~MAGE~7~5")
    ok(w[B].session.peer, "10-field hello from an older client accepted")
    eq(w[B].session.peer.spec, nil)
end)

test("hellos share stats with the leaderboard", function()
    local w = world()
    w.open()
    eq(w.peers[A .. ">" .. B].rating, 1500)
    eq(w.peers[A .. ">" .. B].class, "ROGUE")
    eq(w.peers[A .. ">" .. B].pref, "ask")
    eq(w.peers[B .. ">" .. A].w, 12)
end)

test("one side declines: casual", function()
    local w = world()
    w.open()
    w[A]:Consent(true)
    w[B]:Consent(false)
    w.flush()
    w[B]:Accepted()
    w.flush()
    eq(w[A].session.status, "casual")
    eq(w[B].session.status, "casual")
    eq(w[A]:Result(B).ranked, false)
    eq(w[B]:Result(A).ranked, false)
end)

test("nobody answers the prompt: casual", function()
    local w = world()
    w.open()
    w[B]:Accepted()
    w.flush()
    eq(w[A]:Result(B).ranked, false)
    eq(w[B]:Result(A).ranked, false)
end)

test("consent that arrives after the accept is too late, for both sides", function()
    local w = world()
    w.open()
    w[B]:Consent(true)
    w.flush()
    w[A]:Consent(true)          -- in flight...
    w[B]:Accepted()             -- ...while B accepts
    w.flush()
    eq(w[B].session.status, "casual")
    eq(w[A].session.status, "casual", "challenger adopts the lock, not its own view")
end)

test("no consent after lock", function()
    local w = world()
    w.open()
    w[B]:Accepted()
    w.flush()
    eq(w[A]:Consent(true), false)
    eq(w[B]:Consent(true), false)
end)

test("always + always: ranked with no clicks", function()
    local w = world({ prefA = "always", prefB = "always" })
    w.open()
    w[B]:Accepted()
    w.flush()
    eq(w[A]:Result(B).ranked, true)
    eq(w[B]:Result(A).ranked, true)
end)

test("always + never: casual, and the reason is shared", function()
    local w = world({ prefA = "always", prefB = "never" })
    w.open()
    eq(w[A].session.theirConsent, false)
    eq(w[A].session.theirReason, "N")
    w[B]:Accepted()
    w.flush()
    eq(w[A]:Result(B).ranked, false)
end)

test("always + ask: ranked once the asker clicks", function()
    local w = world({ prefA = "always" })
    w.open()
    eq(w[B].session.theirConsent, true, "A agreed automatically")
    w[B]:Consent(true)
    w.flush()
    w[B]:Accepted()
    w.flush()
    eq(w[A]:Result(B).ranked, true)
end)

test("farm limit declines automatically and blocks manual consent", function()
    local w = world({ farmA = false })
    w.open()
    eq(w[A].session.myConsent, false)
    eq(w[B].session.theirReason, "F")
    eq(w[A]:Consent(true), false)
end)

test("opponent without the addon: no handshake, casual", function()
    local w = world()
    w[A]:Start(B, "C")
    w.queue = {}                -- B has no addon: nothing answers
    eq(w[A].session.status, "noaddon")
    eq(w[A]:Consent(true), false)
    eq(w[A]:Result(B), { ranked = false, oppRating = nil })
end)

test("incompatible protocol: casual", function()
    local w = world()
    w[A]:Start(B, "C")
    w.queue = {}
    w[A]:OnMessage(B, "H~99~x1~D~1500~40~K~ROGUE~1~1")
    eq(w[A].session.status, "incompatible")
    eq(w[A]:Consent(true), false)
end)

test("hello that arrives before our duel event is used", function()
    local w = world()
    w[A]:Start(B, "C")
    w.flush()                   -- B gets A's hello before its DUEL_REQUESTED
    eq(w[B].session, nil)
    w[B]:Start(A, "D")
    w.flush()
    ok(w[B].session.peer, "stashed hello consumed")
    ok(w[A].session.peer)
end)

test("unsolicited hello never opens a session or a prompt", function()
    local w = world()
    w[B]:OnMessage("Spammer-Area52", "H~1~s1~C~2000~99~A~WARRIOR~99~0")
    eq(w[B].session, nil)
    w.clock = w.clock + Session.HELLO_TTL + 1
    w[B]:Start("Spammer-Area52", "D")
    eq(w[B].session.peer, nil, "stale hello expired")
end)

test("messages from a third player are ignored", function()
    local w = world()
    w.open()
    local nonce = w[A].session.myNonce
    w[A]:OnMessage("Eve-Area52", ("R~%s~1~"):format(nonce))
    w[A]:OnMessage("Eve-Area52", ("L~%s~R"):format(nonce))
    eq(w[A].session.theirConsent, nil)
    eq(w[A].session.locked, nil)
end)

test("replies carrying an old duel's nonce are ignored", function()
    local w = world()
    w.open()
    w[A]:OnMessage(B, "R~A999~1~")
    w[A]:OnMessage(B, "L~A999~R")
    eq(w[A].session.theirConsent, nil)
    eq(w[A].session.locked, nil)
end)

test("a new duel with the same opponent starts fresh", function()
    local w = world()
    w.open()
    w[A]:Consent(true)
    w[B]:Consent(true)
    w.flush()
    w[B]:Accepted()
    w.flush()
    w[A]:Result(B)
    w[B]:Result(A)
    w.open()
    eq(w[A].session.myConsent, nil)
    eq(w[A].session.locked, nil)
    w[B]:Accepted()
    w.flush()
    eq(w[A]:Result(B).ranked, false)
end)

test("lost lock message: challenger stays casual", function()
    local w = world()
    w.open()
    w[A]:Consent(true)
    w[B]:Consent(true)
    w.flush()
    w.drop.L = true
    w[B]:Accepted()
    w.flush()
    eq(w[B]:Result(A).ranked, true)
    eq(w[A]:Result(B).ranked, false, "known limitation: one side counts it, documented in PLAN")
end)

test("FightStarted locks if the accept was missed", function()
    local w = world()
    w.open()
    w[A]:Consent(true)
    w[B]:Consent(true)
    w.flush()
    w[B]:FightStarted()
    w.flush()
    eq(w[A].session.status, "ranked")
    eq(w[B].session.status, "ranked")
end)

test("cancelled duel: session dropped after the grace period", function()
    local w = world()
    w.open()
    w[A]:Finished()
    w.clock = w.clock + Session.FINISH_GRACE + 1
    eq(w[A]:Result(B).ranked, false)
    eq(w[A].session, nil)
end)

test("winner message shortly after DUEL_FINISHED still counts", function()
    local w = world({ prefA = "always", prefB = "always" })
    w.open()
    w[B]:Accepted()
    w.flush()
    w[A]:Finished()
    w.clock = w.clock + 2
    eq(w[A]:Result(B).ranked, true)
end)

test("Result for a different opponent doesn't touch the session", function()
    local w = world()
    w.open()
    eq(w[A]:Result("Someone-Else").ranked, false)
    ok(w[A].session, "session kept")
end)

test("garbage messages never error", function()
    local w = world()
    w.open()
    local junk = { "", "~", "H", "H~1", "H~1~~C~a~b~c~d~e~f", "R", "R~~~", "L~~", "P~-5~1~X~1~1",
        "P~1~1~bad class~1~1", ("x"):rep(400), "H~1~n~C~1~1~K~MAGE~1~1~extra~fields", "\0\1\2" }
    for _, m in ipairs(junk) do
        w[A]:OnMessage(B, m)
        w[A]:OnMessage("Other-Realm", m)
    end
    w[A]:OnMessage(nil, "H")
    w[A]:OnMessage(B, nil)
    ok(true)
end)

test("stats message round-trips and rejects junk", function()
    local text = Session.EncodeStats({ rating = 1600, games = 33, class = "DRUID", w = 20, l = 13 })
    eq(Session.DecodeStats(text), { rating = 1600, games = 33, class = "DRUID", w = 20, l = 13 })
    eq(Session.DecodeStats("P~99999~1~X~1~1"), nil)
    eq(Session.DecodeStats("P~1500~1~~1~1").class, nil)
    eq(Session.DecodeStats("H~1500"), nil)
end)

test("stats messages update the leaderboard", function()
    local w = world()
    w[A]:OnMessage("Carol-Area52", "P~1700~50~PRIEST~30~20")
    eq(w.peers[A .. ">Carol-Area52"].rating, 1700)
end)

test("countdown on the challenger side freezes its choice and waits for the lock", function()
    local w = world()
    w.open()
    w[A]:FightStarted()
    eq(w[A].session.countdown, true)
    eq(w[A]:Consent(true), false, "too late to change after the countdown")
    w[B]:Consent(true)
    w[B]:FightStarted()
    w.flush()
    eq(w[A].session.status, "casual")
end)

---------------------------------------------------------------------------
-- Protocol v2: level, readiness, strict, eligibility, outdated peers
---------------------------------------------------------------------------

local RB = ns.Readiness.BITS

-- Both consent, then B (challenged) accepts. Returns both results.
local function agreeAndAccept(w)
    w[A]:Consent(true)
    w[B]:Consent(true)
    w.flush()
    w[B]:Accepted()
    w.flush()
    return w[A]:Result(B), w[B]:Result(A)
end

test("v2 hello carries fingerprint, level and readiness", function()
    local w = world()
    w.ready[A] = RB.COOLDOWNS
    w.open()
    local peer = w[B].session.peer
    eq(peer.proto, 2)
    eq(peer.level, 30)
    eq(peer.fp, ("ab"):rep(16))
    eq(w[A].session.peer.fp, nil, "no key yet: empty field")
    eq(w[B].session.theirReady, RB.COOLDOWNS)
    eq(w[A].session.theirReady, 0)
end)

test("both ready: ranked, and both readiness masks are recorded", function()
    local w = world()
    w.open()
    local ra, rb = agreeAndAccept(w)
    eq(ra.ranked, true)
    eq(rb.ranked, true)
    eq({ ra.myReady, ra.theirReady }, { 0, 0 })
end)

test("baseline not ready at lock time: casual even though both agreed", function()
    local w = world()
    w.ready[A] = RB.HEALTH
    w.open()
    local ra, rb = agreeAndAccept(w)
    eq(ra.ranked, false)
    eq(rb.ranked, false)
end)

test("challenged side not ready: casual", function()
    local w = world()
    w.ready[B] = RB.COMBAT
    w.open()
    local ra, rb = agreeAndAccept(w)
    eq(rb.ranked, false)
    eq(ra.ranked, false)
end)

test("cooldowns only are informational: still ranked, masks recorded", function()
    local w = world()
    w.ready[A] = RB.COOLDOWNS + RB.TRINKETS
    w.open()
    local ra, rb = agreeAndAccept(w)
    eq(ra.ranked, true)
    eq(rb.ranked, true)
    eq(rb.theirReady, RB.COOLDOWNS + RB.TRINKETS)
    eq(ra.myReady, RB.COOLDOWNS + RB.TRINKETS)
end)

test("readiness changes while pending are sent with Y", function()
    local w = world()
    w.ready[A] = RB.HEALTH
    w.open()
    eq(w[B].session.theirReady, RB.HEALTH)
    w.ready[A] = 0
    w[A]:UpdateReadiness()
    eq(w.queue[#w.queue].msg, ("Y~%s~0"):format(w[B].session.myNonce))
    w.flush()
    eq(w[B].session.theirReady, 0)
    local ra = agreeAndAccept(w)
    eq(ra.ranked, true, "healed up before the accept")
end)

test("unchanged readiness sends nothing", function()
    local w = world()
    w.open()
    w[A]:UpdateReadiness()
    eq(#w.queue, 0)
end)

test("becoming not ready after agreeing makes the lock casual", function()
    local w = world()
    w.open()
    w[A]:Consent(true)
    w[B]:Consent(true)
    w.flush()
    w.ready[A] = RB.POWER
    w[A]:UpdateReadiness()
    w.flush()
    w[B]:Accepted()
    w.flush()
    eq(w[B]:Result(A).ranked, false)
    eq(w[A]:Result(B).ranked, false)
end)

test("the challenged side re-reads its own readiness at accept", function()
    local w = world()
    w.open()
    w[A]:Consent(true)
    w[B]:Consent(true)
    w.flush()
    w.ready[B] = RB.HEALTH      -- took damage; no poll has run yet
    w[B]:Accepted()
    w.flush()
    eq(w[B]:Result(A).ranked, false)
    eq(w[A]:Result(B).ranked, false)
end)

test("Y with the wrong nonce or a bad mask is ignored", function()
    local w = world()
    w.open()
    w[B]:OnMessage(A, "Y~A999~1")
    w[B]:OnMessage(A, ("Y~%s~64"):format(w[B].session.myNonce))
    w[B]:OnMessage(A, ("Y~%s~x"):format(w[B].session.myNonce))
    w[B]:OnMessage("Eve-Area52", ("Y~%s~1"):format(w[B].session.myNonce))
    eq(w[B].session.theirReady, 0)
end)

test("a hello without a readable readiness counts as not ready", function()
    local w = world()
    w[B]:Start(A, "D")
    w.queue = {}
    w[B]:OnMessage(A, "H~2~a1~C~1300~12~K~MAGE~7~5~~~~30~")
    eq(w[B].session.status, "pending")
    eq(w[B].session.theirReady, ns.Readiness.ALL_BITS)
end)

test("strict: no consent while the opponent's cooldowns are down", function()
    local w = world({ prefA = "always" })
    w.strict[A] = true
    w.ready[B] = RB.COOLDOWNS
    w.open()
    eq(w[A].session.myConsent, nil, "always does not auto-agree while blocked")
    eq(w[A]:Consent(true), false)
    w.ready[B] = 0
    w[B]:UpdateReadiness()
    w.flush()
    eq(w[A].session.myConsent, true, "agrees automatically once ready")
    w[B]:Consent(true)
    w.flush()
    w[B]:Accepted()
    w.flush()
    eq(w[A]:Result(B).ranked, true)
end)

test("strict: our own cooldowns block too", function()
    local w = world()
    w.strict[B] = true
    w.ready[B] = RB.TRINKETS
    w.open()
    eq(w[B]:Consent(true), false)
end)

test("strict: consent is withdrawn when a cooldown goes down", function()
    local w = world()
    w.strict[A] = true
    w.open()
    ok(w[A]:Consent(true))
    w[B]:Consent(true)
    w.flush()
    w.ready[B] = RB.COOLDOWNS
    w[B]:UpdateReadiness()
    w.flush()
    eq(w[A].session.myConsent, nil)
    eq(w[B].session.theirConsent, false)
    eq(w[B].session.theirReason, "U")
    w[B]:Accepted()
    w.flush()
    eq(w[B]:Result(A).ranked, false)
end)

test("strict off: cooldowns never block", function()
    local w = world()
    w.ready[A], w.ready[B] = RB.COOLDOWNS, RB.TRINKETS
    w.open()
    local ra = agreeAndAccept(w)
    eq(ra.ranked, true)
end)

test("different levels: ineligible, both sides decline with reason L", function()
    local w = world({ prefA = "always", prefB = "always" })
    w.level[B] = 31
    w.open()
    eq(w[A].session.ineligible, "L")
    eq(w[B].session.ineligible, "L")
    eq(w[A].session.theirReason, "L")
    eq(w[A]:Consent(true), false)
    eq(w[A]:Polling(), false, "no readiness polling for an ineligible duel")
    w[B]:Accepted()
    w.flush()
    eq(w[A]:Result(B).ranked, false)
end)

test("outdated v1 peer: casual only, stats still kept", function()
    local w = world()
    w[B]:Start(A, "D")
    w.queue = {}
    w[B]:OnMessage(A, "H~1~old1~C~1300~12~K~MAGE~7~5~64~600")
    eq(w[B].session.status, "outdated")
    eq(w.peers[B .. ">" .. A].rating, 1300)
    eq(w[B]:Consent(true), false)
    eq(w[B]:Polling(), false)
    w[B]:Accepted()
    eq(#w.queue, 0, "no lock is sent to an outdated client")
    eq(w[B]:Result(A).ranked, false)
end)

test("polling only while a decision is open", function()
    local w = world()
    w[A]:Start(B, "C")
    eq(w[A]:Polling(), false, "no addon on the other side yet")
    w[B]:Start(A, "D")
    w.flush()
    eq(w[A]:Polling(), true)
    w[B]:Accepted()
    w.flush()
    eq(w[A]:Polling(), false)
    eq(w[B]:Polling(), false)
end)

test("strict: the challenged side's own cooldown at accept makes it casual", function()
    local w = world()
    w.strict[B] = true
    w.open()
    w[A]:Consent(true)
    ok(w[B]:Consent(true))
    w.flush()
    w.ready[B] = RB.TRINKETS    -- trinket used; no poll has run yet
    w[B]:Accepted()
    w.flush()
    eq(w[B]:Result(A).ranked, false)
    eq(w[A]:Result(B).ranked, false)
end)

---------------------------------------------------------------------------
-- Signed match statements (S messages)
---------------------------------------------------------------------------

local S = ns.Statement

-- Run due `after` callbacks.
local function runLater(w)
    local due = {}
    for i = #w.later, 1, -1 do
        if w.later[i].at <= w.clock then due[#due + 1] = table.remove(w.later, i) end
    end
    for _, l in ipairs(due) do l.fn() end
end

-- A ranked duel A (challenger) vs B; A wins by KO. Returns everything each side
-- stored for the match: Result().sign merged with later onSigned fields.
local function rankedDuel(w, opts)
    opts = opts or {}
    w.open()
    w[A]:Consent(true)
    w[B]:Consent(true)
    w.flush()
    w[B]:Accepted()
    w.flush()
    w[A]:FightStarted()         -- the countdown: both note the start time
    w.stime[B] = w.stime[B] + (opts.skewStartB or 0)
    w[B]:FightStarted()
    w.stime[B] = w.stime[B] - (opts.skewStartB or 0)
    w.stime[A], w.stime[B] = w.stime[A] + 41, w.stime[B] + 41 + (opts.skewB or 0)
    local first, second = A, B
    if opts.bFirst then first, second = B, A end
    local res = {}
    res[first] = w[first]:Result(first == A and B or A, first == A and "W" or "L", "KO")
    if not opts.holdFirst then w.flush() end
    res[second] = w[second]:Result(second == A and B or A, second == A and "W" or "L", "KO")
    if opts.holdFirst then w.flush() end
    w.flush()
    local stored = {}
    for _, side in ipairs({ A, B }) do
        local t = {}
        for k, v in pairs(res[side].sign or {}) do t[k] = v end
        for k, v in pairs(w.signed[side][res[side].matchId] or {}) do t[k] = v end
        stored[side] = t
    end
    return stored, res
end

test("signing: both sides store the same statement, both signatures and fingerprints", function()
    local w = world({ signing = true })
    local stored, res = rankedDuel(w)
    local a, b = stored[A], stored[B]
    ok(a.statement and a.sigC and a.sigD, "challenger complete")
    eq(a, b, "identical on both sides")
    eq(a.fpC, ns.Crypto.Fingerprint(SECRETS[A]))
    eq(a.fpD, ns.Crypto.Fingerprint(SECRETS[B]))
    ok(S.Verify(SECRETS[A], a.statement, a.sigC))
    ok(S.Verify(SECRETS[B], a.statement, a.sigD))
    local f = S.Parse(a.statement)
    eq({ f.matchId, f.challenger, f.challenged, f.winner, f.how, f.level, f.cPre, f.dPre },
        { res[A].matchId, A, B, "C", "KO", 30, 1200, 1500 })
    eq({ f.tStart, f.tEnd }, { 1791500000, 1791500041 })
end)

test("signing: the challenged side's winner message first (challenger's S arrives later)", function()
    local w = world({ signing = true })
    local stored = rankedDuel(w, { bFirst = true })
    eq(stored[A], stored[B])
    ok(stored[B].sigC and stored[B].sigD)
end)

test("signing: the challenger's S arrives before the challenged side's result", function()
    local w = world({ signing = true })
    local stored = rankedDuel(w)  -- A's Result + flush happen before B's Result
    ok(stored[B].sigC, "stashed S used")
    eq(stored[A], stored[B])
end)

test("signing: challenger clock 10 s off is accepted (challenger's times win)", function()
    local w = world({ signing = true })
    local stored = rankedDuel(w, { skewB = 10 })
    eq(stored[A], stored[B])
    eq(S.Parse(stored[B].statement).tEnd, 1791500041)
end)

test("signing: times more than 15 s apart -> each signs its own, mismatch flagged", function()
    local w = world({ signing = true })
    local stored = rankedDuel(w, { skewB = 30 })
    ok(stored[A].sigMismatch and stored[B].sigMismatch)
    ok(stored[A].statement ~= stored[B].statement)
    eq(stored[A].sigD, nil, "no signature over a different statement")
    eq(stored[B].sigC, nil)
    ok(S.Verify(SECRETS[B], stored[B].statement, stored[B].sigD), "B signed its own times")
end)

test("signing: no S from the challenger -> challenged signs its own times after 10 s", function()
    local w = world({ signing = true })
    w.drop.S = true
    local stored, res = rankedDuel(w, { skewB = 3 })
    eq(stored[B].sigD, nil, "waits first")
    w.drop.S = nil
    w.clock = w.clock + Session.SIGN_WAIT
    runLater(w)
    w.flush()
    local b = w.signed[B][res[B].matchId]
    ok(b.sigD and S.Verify(SECRETS[B], b.statement, b.sigD))
    eq(S.Parse(b.statement).tEnd, 1791500044, "own times")
    ok(w.signed[A][res[A].matchId].sigMismatch, "challenger sees different times")
end)

test("signing: a signature after the 60 s window is ignored", function()
    local w = world({ signing = true })
    w.drop.S = true
    local _, res = rankedDuel(w)
    w.drop.S = nil
    w.clock = w.clock + Session.SIGN_WINDOW + 1
    w[A]:OnMessage(B, ("S~%s~1791500000~1791500041~%s"):format(res[A].matchId, ("cd"):rep(32)))
    eq(w.signed[A][res[A].matchId], nil)
end)

test("signing: S from a third player or with bad fields is ignored", function()
    local w = world({ signing = true })
    w.drop.S = true
    local stored, res = rankedDuel(w)
    local id = res[A].matchId
    w[A]:OnMessage("Eve-Area52", ("S~%s~1791500000~1791500041~%s"):format(id, ("cd"):rep(32)))
    for _, m in ipairs({ "S~" .. id .. "~x~1~" .. ("cd"):rep(32), "S~" .. id .. "~1~1~short",
        "S~" .. id .. "~1~1~" .. ("ZZ"):rep(32), "S~nope~1~1~" .. ("cd"):rep(32), "S" }) do
        w[A]:OnMessage(B, m)
    end
    eq(w.signed[A][id], nil)
    eq(stored[A].sigD, nil)
end)

test("signing: casual duels are never signed", function()
    local w = world({ signing = true })
    w.open()
    w[B]:Accepted()
    w.flush()
    local r = w[A]:Result(B, "W", "KO")
    eq(r.sign, nil)
    for _, m in ipairs(w.queue) do ok(m.msg:sub(1, 2) ~= "S~") end
end)

test("signing: the lock carries both masks, so statements agree even if a Y was in flight", function()
    local w = world({ signing = true })
    w.open()
    w[A]:Consent(true)
    w[B]:Consent(true)
    w.flush()
    w.ready[A] = RB.COOLDOWNS
    w.drop.Y = true
    w[A]:UpdateReadiness()       -- A's Y is lost: B locks with A's old mask
    w.drop.Y = nil
    w[B]:Accepted()
    w.flush()
    eq(w[A].session.lockMasks, { c = 0, d = 0 }, "challenger adopts the lock's masks")
    local ra = w[A]:Result(B, "W", "KO")
    w.flush()
    local rb = w[B]:Result(A, "L", "KO")
    w.flush()
    eq(ra.sign.statement, rb.sign.statement)
end)

test("signing: without sign deps nothing is signed", function()
    local w = world()
    w.open()
    local _, rb = agreeAndAccept(w)
    eq(rb.sign, nil)
end)

test("signing: start times more than 15 s apart are a mismatch too", function()
    local w = world({ signing = true })
    local stored = rankedDuel(w, { skewStartB = 20 })
    ok(stored[A].sigMismatch and stored[B].sigMismatch)
end)

test("signing: no countdown seen on one side -> the other side's start time is used", function()
    local w = world({ signing = true })
    w.open()
    w[A]:Consent(true)
    w[B]:Consent(true)
    w.flush()
    w[B]:Accepted()
    w.flush()
    w[A]:FightStarted()          -- B reloaded and missed the countdown
    w.stime[A], w.stime[B] = w.stime[A] + 41, w.stime[B] + 41
    local ra = w[A]:Result(B, "W", "KO")
    w.flush()
    local rb = w[B]:Result(A, "L", "KO")
    w.flush()
    eq(ra.sign.statement, rb.sign.statement)
    eq(S.Parse(rb.sign.statement).tStart, 1791500000)
end)
