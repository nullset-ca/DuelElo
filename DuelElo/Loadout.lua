-- Loadout.lua: your own build at the start of each duel (SPEC §3.13; no WoW API).
-- LoadoutAdapter.lua reads the client; this file turns those reads into the
-- compact strings we store, hash, sign and upload. Each player records only
-- their own build; the site joins both halves of a match by its id.
-- The strings are a protocol shared with packages/core/src/loadout.ts and
-- pinned by spec/vectors/loadout.json.
local _, ns = ...

local Loadout = {}
ns.Loadout = Loadout

-- Equipment slots 1-18 except the shirt (4); the tabard (19) isn't gear.
Loadout.SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
Loadout.MAX_LIST = 40      -- buffs, cooldowns down and cooldowns used, per duel
Loadout.DETAIL_KEEP = 200  -- newest duels that keep their build snapshot
Loadout.SIG_TAG = "DS1"
Loadout.FORMATS = { classic = true, traits = true, none = true }

-- "|Hitem:19019:1900:0:0:0:0:1201:...|h" -> "19019:1900:0:0:0:1201" (item,
-- enchant, gems 1-3, random suffix), trailing zero fields dropped. Gem 4 and
-- everything after the suffix (unique id, level, bonus ids...) are left out.
function Loadout.ParseItemLink(link)
    if type(link) ~= "string" then return nil end
    local body = link:match("item:([%-%d:]+)")
    if not body then return nil end
    local f = {}
    for v in (body .. ":"):gmatch("([^:]*):") do f[#f + 1] = tonumber(v) or 0 end
    local item = f[1]
    if not item or item <= 0 then return nil end
    local out = { item, f[2] or 0, f[3] or 0, f[4] or 0, f[5] or 0, f[7] or 0 }
    for i = 1, #out do out[i] = ("%d"):format(out[i]) end
    while #out > 1 and out[#out] == "0" do out[#out] = nil end
    return table.concat(out, ":")
end

-- links[slot] = item link (nil for empty slots) -> "1=19019:1900,3=…", ascending slots.
function Loadout.Gear(links)
    local parts = {}
    for _, slot in ipairs(Loadout.SLOTS) do
        local item = Loadout.ParseItemLink(links[slot])
        if item then parts[#parts + 1] = slot .. "=" .. item end
    end
    return table.concat(parts, ",")
end

-- trees = { { { tier, column, rank }, ... }, ... } (three trees in Forever).
-- Talents ordered by (tier, column), ranks as digits, trailing zeros trimmed,
-- trees joined by "-" and trailing "-" trimmed: the calculator format
-- ("30305001302-05050005525010051").
function Loadout.ClassicTalents(trees)
    local out = {}
    for t, talents in ipairs(trees) do
        local sorted = {}
        for i, x in ipairs(talents) do sorted[i] = { tier = x[1] or 0, col = x[2] or 0, rank = x[3] or 0, i = i } end
        table.sort(sorted, function(a, b)
            if a.tier ~= b.tier then return a.tier < b.tier end
            if a.col ~= b.col then return a.col < b.col end
            return a.i < b.i
        end)
        local digits = {}
        for i, x in ipairs(sorted) do digits[i] = tostring(math.max(0, math.min(9, math.floor(x.rank)))) end
        out[t] = (table.concat(digits):gsub("0+$", ""))
    end
    return (table.concat(out, "-"):gsub("%-+$", ""))
end

-- Points per tree for a classic string: "305-05" -> { 8, 5 }.
function Loadout.TreePoints(talents)
    local points = {}
    for tree in (talents .. "-"):gmatch("([^%-]*)%-") do
        local n = 0
        for d in tree:gmatch("%d") do n = n + tonumber(d) end
        points[#points + 1] = n
    end
    return points
end

-- Comma-joined, capped list ("21562,1459"). Items are strings or numbers.
function Loadout.List(items)
    local out = {}
    for i = 1, math.min(#items, Loadout.MAX_LIST) do out[i] = tostring(items[i]) end
    return table.concat(out, ",")
end

-- Build identity: the first 16 hex of SHA-256("fmt|gear|talents").
function Loadout.Hash(fmt, gear, talents)
    return ns.Crypto.SHA256(fmt .. "|" .. gear .. "|" .. talents):sub(1, 16)
end

-- What a duel's own build signature covers. key = match id, or for casual
-- duels "C:<t>:<opp>" (the server rebuilds it from the record).
function Loadout.SignString(key, e)
    return table.concat({ Loadout.SIG_TAG, key, e.loadout or "", e.buffs or "", e.cds or "", e.used or "",
        e.late and "1" or "0" }, "|")
end

function Loadout.KeyOf(entry)
    return entry.match or ("C:%d:%s"):format(entry.t or 0, entry.opp or "")
end

-- Store a snapshot's build (once per distinct build) and put the duel's part
-- on the entry, signed with the character's secret.
-- snap = { fmt, gear, talents, spec, ilvl, buffs, cds, used, late }
function Loadout.Attach(char, entry, snap, secret, now)
    if type(snap) ~= "table" or not Loadout.FORMATS[snap.fmt] then return false end
    local gear, talents = snap.gear or "", snap.talents or ""
    local hash = Loadout.Hash(snap.fmt, gear, talents)
    char.loadouts = char.loadouts or {}
    if not char.loadouts[hash] then
        char.loadouts[hash] = { fmt = snap.fmt, gear = gear, talents = talents, spec = snap.spec, ilvl = snap.ilvl,
            t = now }
    end
    entry.loadout = hash
    entry.buffs = snap.buffs ~= "" and snap.buffs or nil
    entry.cds = snap.cds ~= "" and snap.cds or nil
    entry.used = snap.used ~= "" and snap.used or nil
    entry.late = snap.late or nil
    if secret then entry.loadoutSig = ns.Statement.Sign(secret, Loadout.SignString(Loadout.KeyOf(entry), entry)) end
    return true
end

-- Keep SavedVariables small: duels older than the newest DETAIL_KEEP drop
-- their snapshot (all of it, so what's left still matches its signature), and
-- builds no duel refers to are forgotten.
function Loadout.Prune(char)
    local duels = char.duels or {}
    for i = 1, #duels - Loadout.DETAIL_KEEP do
        local e = duels[i]
        e.loadout, e.buffs, e.cds, e.used, e.late, e.loadoutSig = nil, nil, nil, nil, nil, nil
    end
    local used = {}
    for _, e in ipairs(duels) do
        if e.loadout then used[e.loadout] = true end
    end
    for hash in pairs(char.loadouts or {}) do
        if not used[hash] then char.loadouts[hash] = nil end
    end
end
