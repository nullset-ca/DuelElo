-- ReadinessAdapter.lua: reads the client into Readiness inputs. Every read is
-- wrapped so a missing API, an error or a secret value leaves that input nil
-- ("couldn't read it", which Readiness counts as failed) instead of erroring.
local _, ns = ...
local Readiness = ns.Readiness

local LONG_COOLDOWN_MS = 60000  -- base cooldown that counts as a "long" cooldown
local GCD_MAX = 1.5             -- shorter cooldowns are just the global cooldown
local TRINKET_SLOTS = { 13, 14 }
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

-- Calls fn(...) and returns its results only if it succeeded and none of them
-- is a secret value.
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn, ...) }
    if not res[1] then return nil end
    for i = 2, table.maxn(res) do
        if ns.IsSecret(res[i]) then return nil end
    end
    return unpack(res, 2, table.maxn(res))
end

local function readCombat()
    local v = safe(UnitAffectingCombat, "player")
    if v == nil then return nil end
    return v and true or false
end

local function readHealth()
    local cur, max = safe(UnitHealth, "player"), safe(UnitHealthMax, "player")
    if type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
    return cur / max
end

-- Only mana counts (rage/energy/runic power start low by design). Any
-- character with a mana pool is checked, whatever form or spec it's in.
local function readMana()
    local max = safe(UnitPowerMax, "player", MANA)
    if type(max) ~= "number" then return nil end
    if max <= 0 then return false end
    local cur = safe(UnitPower, "player", MANA)
    if type(cur) ~= "number" then return nil end
    return cur / max
end

-- Spellbook spells with a long base cooldown, rebuilt when the spellbook changes.
local longSpells
local function scanLongSpells()
    local book = C_SpellBook
    if not (book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo
        and book.GetSpellBookItemInfo) then return nil end
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local spellType = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
    local list = {}
    local lines = safe(book.GetNumSpellBookSkillLines)
    if type(lines) ~= "number" then return nil end
    for line = 1, lines do
        local info = safe(book.GetSpellBookSkillLineInfo, line)
        if type(info) == "table" and not info.isGuild and not info.shouldHide and not info.offSpecID then
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = safe(book.GetSpellBookItemInfo, i, bank)
                if type(item) == "table" and item.itemType == spellType and not item.isPassive
                    and not item.isOffSpec and type(item.spellID) == "number" then
                    local base = safe(GetSpellBaseCooldown, item.spellID)
                    if type(base) == "number" and base >= LONG_COOLDOWN_MS then
                        list[#list + 1] = item.spellID
                    end
                end
            end
        end
    end
    return list
end

local function cooling(start, duration)
    return type(start) == "number" and type(duration) == "number" and start > 0 and duration > GCD_MAX
end

local function readCooldowns()
    longSpells = longSpells or scanLongSpells()
    if not longSpells or not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local n = 0
    for _, id in ipairs(longSpells) do
        local cd = safe(C_Spell.GetSpellCooldown, id)
        if type(cd) ~= "table" then return nil end
        if ns.IsSecret(cd.startTime) or ns.IsSecret(cd.duration) then return nil end
        if cooling(cd.startTime, cd.duration) then n = n + 1 end
    end
    return n
end

local function readTrinkets()
    local n = 0
    for _, slot in ipairs(TRINKET_SLOTS) do
        local ok, start, duration, enable = pcall(GetInventoryItemCooldown, "player", slot)
        if not ok or ns.IsSecret(start) or ns.IsSecret(duration) then return nil end
        if enable ~= 0 and cooling(start, duration) then n = n + 1 end
    end
    return n
end

-- One lookup per banned ID; older clients without C_UnitAuras fall back to
-- walking the player's buffs (spell ID is UnitBuff's 10th return).
local function readBanned()
    local banned = ns.BANNED_AURAS or {}
    local n = 0
    local byId = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if byId then
        for id in pairs(banned) do
            local ok, aura = pcall(byId, id)
            if not ok or ns.IsSecret(aura) then return nil end
            if aura ~= nil then n = n + 1 end
        end
        return n
    end
    if type(UnitBuff) ~= "function" then return nil end
    for i = 1, 40 do
        local ok, name, _, _, _, _, _, _, _, _, id = pcall(UnitBuff, "player", i)
        if not ok or ns.IsSecret(id) then return nil end
        if not name then break end
        if banned[id] then n = n + 1 end
    end
    return n
end

-- Long cooldowns still running right now, for the duel's build snapshot
-- (SPEC §3.13): "spellID:seconds left", trinkets as "i<itemID>:seconds left".
-- Unreadable cooldowns are left out.
function ns.CooldownsDown()
    longSpells = longSpells or scanLongSpells()
    local now, out = GetTime(), {}
    local get = C_Spell and C_Spell.GetSpellCooldown
    for _, id in ipairs(get and longSpells or {}) do
        local cd = safe(get, id)
        if type(cd) == "table" and not ns.IsSecret(cd.startTime) and not ns.IsSecret(cd.duration)
            and cooling(cd.startTime, cd.duration) then
            out[#out + 1] = ("%d:%d"):format(id, math.max(1, math.floor(cd.startTime + cd.duration - now + 0.5)))
        end
    end
    for _, slot in ipairs(TRINKET_SLOTS) do
        local start, duration, enable = safe(GetInventoryItemCooldown, "player", slot)
        local item = safe(GetInventoryItemID, "player", slot)
        if type(item) == "number" and enable ~= 0 and cooling(start, duration) then
            out[#out + 1] = ("i%d:%d"):format(item, math.max(1, math.floor(start + duration - now + 0.5)))
        end
    end
    return out
end

-- Reads stop at combat: in combat every other read may be secret, and the
-- combat bit alone already blocks ranked.
function ns.ReadReadinessInputs()
    local inCombat = readCombat()
    if inCombat ~= false then return { inCombat = inCombat, health = 1, mana = false,
        cooldowns = 0, trinkets = 0, banned = 0 } end
    return {
        inCombat = false,
        health = readHealth(),
        mana = readMana(),
        cooldowns = readCooldowns(),
        trinkets = readTrinkets(),
        banned = readBanned(),
    }
end

-- mask, counts, unknown for the local player right now.
function ns.EvaluateReadiness()
    return Readiness.Evaluate(ns.ReadReadinessInputs())
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("SPELLS_CHANGED")
frame:SetScript("OnEvent", function() longSpells = nil end)
