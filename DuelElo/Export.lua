-- Export.lua: what goes into an upload code (SPEC §2.6/§3.7; no WoW API).
-- The UI passes in the character data and context; Codec.lua turns the
-- payload into the DUELELO1 code. Upload codes contain the character's
-- secret key, so they are only ever shown in the copy box, never in chat.
local _, ns = ...

local Export = {}
ns.Export = Export

Export.NUDGE_AT = 5  -- unverified ranked duels before we suggest uploading

-- Signed ranked duels are "matches"; everything else is a casual record
-- (including test-era ranked duels, which were never signed).
local function isMatch(e)
    return type(e.statement) == "string" and (e.sigC ~= nil or e.sigD ~= nil)
end

local function newerThan(t, since)
    return since == nil or (tonumber(t) or 0) > since
end

-- Counts of records not yet exported: { matches, casual, reports, witnesses }.
function Export.Pending(char, since)
    local n = { matches = 0, casual = 0, reports = 0, witnesses = 0 }
    for _, e in ipairs(char.duels) do
        if newerThan(e.t, since) then
            if isMatch(e) then n.matches = n.matches + 1 else n.casual = n.casual + 1 end
        end
    end
    for _, r in ipairs(char.reports or {}) do
        if newerThan(r.t, since) then n.reports = n.reports + 1 end
    end
    for _, w in ipairs(char.witnesses or {}) do
        if newerThan(w.t, since) then n.witnesses = n.witnesses + 1 end
    end
    return n
end

-- ctx: { name, realm, class, level, region, flavor, version, now, full }
-- (full = ignore char.lastExport). Returns the §2.6 payload table.
function Export.Build(char, ctx)
    local since = not ctx.full and char.lastExport or nil
    local me = ctx.name .. "-" .. ctx.realm
    local payload = {
        v = 1, addon = ctx.version, flavor = ctx.flavor, region = ctx.region, exportedAt = ctx.now, since = since,
        characters = { {
            name = ctx.name, realm = ctx.realm, class = ctx.class, level = ctx.level,
            fp = ns.Crypto.Fingerprint(char.key.secret), secret = char.key.secret,
        } },
        matches = {}, casual = {}, witnesses = {}, reports = {}, loadouts = {},
    }
    -- builds (SPEC §3.13): each record names its own; the payload carries
    -- every referenced build once
    local builds, included = char.loadouts or {}, {}
    local function withBuild(rec, e)
        local b = e.loadout and builds[e.loadout]
        if not b then return rec end
        rec.loadout, rec.loadoutSig, rec.buffs, rec.cds, rec.used = e.loadout, e.loadoutSig, e.buffs, e.cds, e.used
        rec.late = e.late or nil
        if not included[e.loadout] then
            included[e.loadout] = true
            payload.loadouts[#payload.loadouts + 1] = { hash = e.loadout, fmt = b.fmt, gear = b.gear,
                talents = b.talents, spec = b.spec, ilvl = b.ilvl, t = b.t }
        end
        return rec
    end
    for _, e in ipairs(char.duels) do
        if newerThan(e.t, since) then
            if isMatch(e) then
                payload.matches[#payload.matches + 1] = withBuild({
                    statement = e.statement, sigC = e.sigC, sigD = e.sigD, fpC = e.fpC, fpD = e.fpD,
                    sigMismatch = e.sigMismatch, zone = e.zone, secs = e.secs, self = me,
                    spec = e.spec, ilvl = e.ilvl, oppSpec = e.oppSpec, oppIlvl = e.oppIlvl,
                }, e)
            elseif e.opp and (e.result == "W" or e.result == "L") then
                payload.casual[#payload.casual + 1] = withBuild({
                    t = e.t, opp = e.opp, result = e.result, how = e.how == "FLED" and "FLED" or "KO",
                    class = ctx.class, oppClass = e.class, zone = e.zone, secs = e.secs, level = ctx.level,
                }, e)
            end
        end
    end
    for _, w in ipairs(char.witnesses or {}) do
        if newerThan(w.t, since) then
            payload.witnesses[#payload.witnesses + 1] = { statement = w.statement, sig = w.sig, fp = w.fp }
        end
    end
    for _, r in ipairs(char.reports or {}) do
        if newerThan(r.t, since) then
            payload.reports[#payload.reports + 1] = {
                matchId = r.matchId, target = r.target, reason = r.reason, note = r.note, t = r.t,
            }
        end
    end
    return payload
end

-- Ranked duels since the last export that nobody has uploaded yet (as far as
-- we know: the official ladder data, once installed, marks confirmed ones).
function Export.Unverified(char, confirmed)
    local n = 0
    for _, e in ipairs(char.duels) do
        if isMatch(e) and newerThan(e.t, char.lastExport) and not (confirmed and confirmed[e.match]) then
            n = n + 1
        end
    end
    return n
end

-- Suggest uploading? At most once per session, and only if the player wants reminders.
function Export.ShouldNudge(unverified, nudgedThisSession, enabled)
    return enabled and not nudgedThisSession and unverified >= Export.NUDGE_AT
end
