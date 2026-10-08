-- LoadoutAdapter.lua: reads your own build from the client for the duel
-- snapshot (SPEC §3.13). Every read is wrapped: a missing API, an error or a
-- secret value leaves that part empty ("none") instead of erroring.
-- Opponents are never inspected; each side uploads its own build.
local _, ns = ...
local Loadout = ns.Loadout

local Snapshot = {}
ns.Snapshot = Snapshot

local TRACK_MIN_MS = 10000  -- casts of spells with at least this base cooldown are logged
local PRECAST_SECS = -5     -- casts during the countdown count from this many seconds before the start
local TRINKET_SLOTS = { 13, 14 }

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn, ...) }
    if not res[1] then return nil end
    for i = 2, table.maxn(res) do
        if ns.IsSecret(res[i]) then return nil end
    end
    return unpack(res, 2, table.maxn(res))
end

local function readGear()
    local links = {}
    for _, slot in ipairs(Loadout.SLOTS) do
        local link = safe(GetInventoryItemLink, "player", slot)
        if type(link) == "string" then links[slot] = link end
    end
    return Loadout.Gear(links)
end

-- WoW Forever: three talent trees (GetTalentInfo returns name, icon, tier,
-- column, rank, ...). Nil when the API is missing or returns nothing useful.
local function readClassicTalents()
    local tabs = safe(GetNumTalentTabs)
    if type(tabs) ~= "number" or tabs < 1 or type(GetTalentInfo) ~= "function" then return nil end
    local trees = {}
    for tab = 1, tabs do
        local n = safe(GetNumTalents, tab)
        if type(n) ~= "number" then return nil end
        local talents = {}
        for i = 1, n do
            local name, _, tier, column, rank = safe(GetTalentInfo, tab, i)
            if type(name) ~= "string" or type(rank) ~= "number" then return nil end
            talents[i] = { tonumber(tier) or 0, tonumber(column) or 0, rank }
        end
        trees[tab] = talents
    end
    return Loadout.ClassicTalents(trees)
end

-- Retail (developer testing only): the talent loadout's import string.
local function readTraits()
    local ct, traits = C_ClassTalents, C_Traits
    if not (ct and ct.GetActiveConfigID and traits and traits.GenerateImportString) then return nil end
    local config = safe(ct.GetActiveConfigID)
    if type(config) ~= "number" then return nil end
    local s = safe(traits.GenerateImportString, config)
    return type(s) == "string" and s ~= "" and #s <= 2000 and s or nil
end

local function readTalents()
    local first, second = readClassicTalents, readTraits
    if ns.FLAVOR == "retail" then first, second = readTraits, readClassicTalents end
    local t = first()
    if t then return first == readTraits and "traits" or "classic", t end
    t = second()
    if t then return second == readTraits and "traits" or "classic", t end
    return "none", ""
end

-- Spell ids of our helpful auras (C_UnitAuras, else UnitBuff's 10th return).
local function readBuffs()
    local ids = {}
    local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for i = 1, Loadout.MAX_LIST do
        local id
        if byIndex then
            local aura = safe(byIndex, "player", i, "HELPFUL")
            if type(aura) ~= "table" then break end
            id = aura.spellId
        elseif type(UnitBuff) == "function" then
            local name, _, _, _, _, _, _, _, _, spellId = safe(UnitBuff, "player", i)
            if not name then break end
            id = spellId
        else
            break
        end
        if type(id) == "number" and not ns.IsSecret(id) then ids[#ids + 1] = id end
    end
    return Loadout.List(ids)
end

-- On-use spells of the equipped trinkets, so their casts are logged too.
local function trinketSpells()
    local spells = {}
    local itemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    for _, slot in ipairs(TRINKET_SLOTS) do
        local item = safe(GetInventoryItemID, "player", slot)
        if type(item) == "number" then
            local _, spellID = safe(itemSpell, item)
            if type(spellID) == "number" then spells[spellID] = true end
        end
    end
    return spells
end

---------------------------------------------------------------------------
-- One duel at a time: Start at the first countdown line, Finish at the result.
---------------------------------------------------------------------------

local current        -- { snap, startAt, casts, trinkets } while a duel runs
local baseCooldown = {}  -- spellID -> base cooldown ms (cached; false if unknown)

local tracker = CreateFrame("Frame")

local function isTracked(spellID)
    if current.trinkets[spellID] then return true end
    local base = baseCooldown[spellID]
    if base == nil then
        local ms = safe(GetSpellBaseCooldown, spellID)
        base = type(ms) == "number" and ms or false
        baseCooldown[spellID] = base
    end
    return base and base >= TRACK_MIN_MS
end

tracker:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if not current or unit ~= "player" or type(spellID) ~= "number" or ns.IsSecret(spellID) then return end
    if #current.casts >= Loadout.MAX_LIST or not isTracked(spellID) then return end
    local at = math.floor(GetTime() - current.startAt)
    current.casts[#current.casts + 1] = ("%d@%d"):format(spellID, math.max(PRECAST_SECS, at))
end)

local function readAll()
    local fmt, talents = readTalents()
    local cds = ns.CooldownsDown and ns.CooldownsDown() or {}
    return {
        fmt = fmt, talents = talents, gear = readGear(), spec = ns.Comm.MySpec(), ilvl = ns.Comm.MyItemLevel(),
        buffs = readBuffs(), cds = Loadout.List(cds),
    }
end

-- secondsLeft: the countdown's number ("Duel starting: 3").
function Snapshot.Start(secondsLeft)
    if current then return end
    local ok, snap = pcall(readAll)
    current = { snap = ok and snap or nil, startAt = GetTime() + (tonumber(secondsLeft) or 0), casts = {},
        trinkets = trinketSpells() }
    tracker:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end

-- Stop logging casts (the duel ended or was cancelled); the snapshot stays
-- until Finish or Reset.
function Snapshot.Stop()
    tracker:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end

-- The finished snapshot for the duel that just ended. Without a countdown we
-- read the build now and mark it late (buffs and cooldowns are then left out:
-- after a fight they say nothing about the start).
function Snapshot.Finish()
    Snapshot.Stop()
    local cur = current
    current = nil
    if cur and cur.snap then
        cur.snap.used = Loadout.List(cur.casts)
        return cur.snap
    end
    local ok, snap = pcall(readAll)
    if not ok or not snap then return nil end
    snap.buffs, snap.cds, snap.used, snap.late = "", "", "", true
    return snap
end

-- A new duel request: forget anything left over from one that never finished.
function Snapshot.Reset()
    Snapshot.Stop()
    current = nil
end
