-- Comm.lua: addon-message transport. Our stats as others see them, the
-- Session engine wired to the real client, and stats heard from other players.
local _, ns = ...
local Data, Rules = ns.Data, ns.Rules
local me = ns.me

local COMM_PREFIX = "DuelElo"     -- addon message prefix (max 16 chars)
local PEER_MIN_INTERVAL = 10      -- ignore a player's stats if they sent some this recently
local READY_POLL = 1              -- seconds between readiness checks while a decision is open

-- Where a leaderboard entry came from; higher wins when we hear about someone twice.
local SOURCE_RANK = { channel = 1, guild = 2, met = 3 }

local Comm = { PREFIX = COMM_PREFIX }
ns.Comm = Comm

-- Specialization id, from the old globals or C_SpecializationInfo (the
-- Forever client has only the latter, if anything), or nil.
function Comm.MySpec()
    local si = C_SpecializationInfo
    local getSpec = GetSpecialization or (si and si.GetSpecialization)
    local getInfo = GetSpecializationInfo or (si and si.GetSpecializationInfo)
    if not (getSpec and getInfo) then return nil end
    local ok, index = pcall(getSpec)
    if not ok or type(index) ~= "number" or ns.IsSecret(index) then return nil end
    local ok2, id = pcall(getInfo, index)
    return ok2 and type(id) == "number" and not ns.IsSecret(id) and id or nil
end

function Comm.MyItemLevel()
    if not GetAverageItemLevel then return nil end
    local _, equipped = GetAverageItemLevel()
    return type(equipped) == "number" and equipped >= 1 and math.floor(equipped) or nil
end

-- Our ranked stats as other players see them.
local function myStats()
    local c = ns.char
    return { rating = c.rating, games = c.rankedGames, class = me.class, w = c.rankedW, l = c.rankedL,
        spec = Comm.MySpec(), ilvl = Comm.MyItemLevel() }
end

function Comm.Send(msg, channel, target)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    -- Whisper players on our realm by their plain name: WoW Forever answers
    -- "No player named …" to some realm-qualified forms, and the plain name
    -- always works on the same realm.
    if channel == "WHISPER" and type(target) == "string" then target = ns.DisplayName(target) end
    local ok, err = pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, msg, channel, target)
    if not ok then ns.DPrint("send failed: " .. tostring(err)) end
end

-- A player's stats, as they reported them. source: "met" (handshake or whisper
-- from someone we dueled), "guild" or "channel". Only "met" counts as verified.
local function rememberPlayer(name, stats, source)
    if not name or name == me.full then return end
    local p = ns.account.players[name] or {}
    ns.account.players[name] = p
    p.rating, p.games, p.w, p.l = stats.rating, stats.games, stats.w, stats.l
    p.class = stats.class or p.class
    p.spec = stats.spec or p.spec
    p.seen = time()
    if (SOURCE_RANK[source] or 0) > (SOURCE_RANK[p.source] or 0) then p.source = source end
    ns.Fire("PLAYERS_CHANGED")
end

function Comm.ShareStats(target)
    local msg = ns.Session.EncodeStats(myStats())
    if target then Comm.Send(msg, "WHISPER", target) end
    if IsInGuild and IsInGuild() then Comm.Send(msg, "GUILD") end
    local channelId = ns.Channel.Id()
    if channelId and ns.account.settings.shareChannel then Comm.Send(msg, "CHANNEL", channelId) end
end

-- Stats messages: who sent them is vouched for by the game; what they claim isn't.
local lastStatsFrom = {}
local function handleStats(sender, text, channel)
    local stats = ns.Session.DecodeStats(text)
    if not stats then return end
    local now = GetTime()
    if lastStatsFrom[sender] and now - lastStatsFrom[sender] < PEER_MIN_INTERVAL then return end
    lastStatsFrom[sender] = now
    local source = (channel == "WHISPER" and "met") or (channel == "GUILD" and "guild") or "channel"
    ns.DPrint(("Stats from %s via %s: %d (%d games)"):format(sender, source, stats.rating, stats.games))
    rememberPlayer(sender, stats, source)
end

-- Nonces tie handshake replies (and a match id) to one duel. WoW's math.random
-- returned 0 for a large range in testing, so don't rely on it alone: combine
-- the client's millisecond clock, a per-session counter and a small random part.
local nonceCount = 0
local function newNonce()
    nonceCount = nonceCount + 1
    local ms = math.floor((GetTime() or 0) * 1000) % 100000000
    local ok, r = pcall(math.random, 0, 999)
    return ("%d%03d%d"):format(ms, ok and tonumber(r) or 0, nonceCount % 10)
end

local function ladderBanned(name)
    return Rules.LadderBanned(DuelEloLadderData, ns.account.region, name)
end

-- Ranked eligibility vs this opponent (SPEC §3.3).
local function eligible(opp, peer)
    return Rules.Check({
        myLevel = ns.MyLevel(), oppLevel = peer.level, opp = opp,
        characters = ns.account.characters,
        oppBanned = ladderBanned(opp), meBanned = ladderBanned(me.full),
        pairTimes = ns.char.rankedLog[opp], now = time(),
    })
end

function Comm.NewEngine()
    return ns.Session.New({
        me = myStats,
        pref = function() return ns.account.settings.rankedPref end,
        farmAllowed = function(opp) return Data.RankedAllowed(ns.char, opp, time()) end,
        eligible = eligible,
        readiness = function() return ns.EvaluateReadiness() end,
        level = ns.MyLevel,
        fp = function() return ns.myFp end,
        strict = function() return ns.account.settings.strict end,
        sign = function(statement)
            return ns.char.key and ns.Statement.Sign(ns.char.key.secret, statement)
        end,
        myName = function() return me.full end,
        region = function() return ns.account.region end,
        serverTime = function() return GetServerTime and GetServerTime() or time() end,
        after = function(seconds, fn) C_Timer.After(seconds, fn) end,
        onSigned = function(matchId, fields) ns.Duel.OnSigned(matchId, fields) end,
        send = function(target, msg) Comm.Send(msg, "WHISPER", target) end,
        now = GetTime,
        nonce = newNonce,
        onChange = function(session) ns.Fire("SESSION_CHANGED", session) end,
        onPeer = function(name, stats) rememberPlayer(name, stats, "met") end,
    })
end

function Comm.OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= COMM_PREFIX or not ns.engine or not me.full then return end
    if type(sender) ~= "string" or ns.IsSecret(sender) or ns.IsSecret(text) then return end
    sender = ns.Parse.Normalize(sender, me.realm)
    if sender == me.full then return end  -- our own guild/channel broadcast
    if text:sub(1, 2) == "P~" then
        handleStats(sender, text, channel)
    else
        ns.engine:OnMessage(sender, text)
    end
end

-- Readiness is polled only while a ranked decision is open (never otherwise:
-- the addon stays idle outside duels).
local ticker
ns.Listen(function(event)
    if event ~= "SESSION_CHANGED" then return end
    local want = ns.engine and ns.engine:Polling()
    if want and not ticker then
        ticker = C_Timer.NewTicker(READY_POLL, function()
            if ns.engine then ns.engine:UpdateReadiness() end
        end)
    elseif not want and ticker then
        ticker:Cancel()
        ticker = nil
    end
end)
