-- DuelElo Probe: throwaway diagnostic addon.
-- Logs everything we need to know about how WoW Forever reports duels,
-- whether addon messages work, and whether SavedVariables persist.
-- The log is also written to DuelEloProbeDB so it can be read from disk.

local ADDON = ...
local PREFIX = "DuelEloProbe"   -- addon message prefix (max 16 chars)
local MAX_LOG = 1000

local pending = {}              -- log lines produced before SavedVariables load

local function safe(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    if v == nil then return "nil" end
    return tostring(v)
end

local function fmtArgs(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = safe((select(i, ...))) end
    return table.concat(t, " | ")
end

local function log(msg)
    local line = date("%H:%M:%S") .. " " .. msg
    print("|cff33ff99[Probe]|r " .. line)
    if DuelEloProbeDB then
        local L = DuelEloProbeDB.log
        L[#L + 1] = line
        while #L > MAX_LOG do table.remove(L, 1) end
    else
        pending[#pending + 1] = line
    end
end

-- Turn a client format string like "%2$s has fled from %1$s in a duel"
-- into a Lua pattern with captures, plus the argument index of each capture
-- (so captures can be mapped back to %1$s / %2$s regardless of text order).
local function toPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local order, n = {}, 0
    local p = fmt:gsub("%%(%d?)%$?s", function(idx)
        n = n + 1
        order[n] = tonumber(idx) or n
        return "\001"
    end)
    p = p:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("\001", "(.+)")
    return "^" .. p .. "$", order
end

local winPatterns = {
    { name = "KNOCKOUT", fmt = DUEL_WINNER_KNOCKOUT },
    { name = "RETREAT",  fmt = DUEL_WINNER_RETREAT },
}
for _, w in ipairs(winPatterns) do w.pattern, w.order = toPattern(w.fmt) end

---------------------------------------------------------------------------
-- Addon messaging
---------------------------------------------------------------------------

local function send(msg, channel, target)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        log("SEND FAILED: C_ChatInfo.SendAddonMessage does not exist")
        return
    end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel, target)
    log(("SEND '%s' via %s to %s -> ok=%s result=%s"):format(
        msg, channel, safe(target), tostring(ok), safe(res)))
end

---------------------------------------------------------------------------
-- Status report
---------------------------------------------------------------------------

local function exists(v) return v ~= nil and "yes" or "NO" end

local function status()
    local version, build, bdate, toc = GetBuildInfo()
    log(("BUILD version=%s build=%s date=%s interface=%s"):format(
        safe(version), safe(build), safe(bdate), safe(toc)))
    local name, realm = UnitFullName("player")
    log(("PLAYER name=%s realm=%s normalizedRealm=%s"):format(
        safe(name), safe(realm), safe(GetNormalizedRealmName and GetNormalizedRealmName())))
    log("API C_ChatInfo.SendAddonMessage=" .. exists(C_ChatInfo and C_ChatInfo.SendAddonMessage)
        .. " RegisterAddonMessagePrefix=" .. exists(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix)
        .. " issecretvalue=" .. exists(issecretvalue)
        .. " StartDuel=" .. exists(StartDuel)
        .. " C_Timer=" .. exists(C_Timer)
        .. " Settings=" .. exists(Settings)
        .. " PlaySound=" .. exists(PlaySound))
    log("TEMPLATE DUEL_COUNTDOWN = " .. safe(DUEL_COUNTDOWN))
    local function try(f, ...) local ok, v = pcall(f, ...) return ok and safe(v) or ("ERROR " .. safe(v)) end
    log(("RANDOM math.random(0,0x7fffffff)=%s  (0,999)=%s  (1,100)=%s  ()=%s  format%%x(255)=%s  GetTime=%s"):format(
        try(math.random, 0, 0x7fffffff), try(math.random, 0, 999), try(math.random, 1, 100), try(math.random),
        try(string.format, "%x", 255), safe(GetTime())))
    for _, w in ipairs(winPatterns) do
        log(("TEMPLATE DUEL_WINNER_%s = %s  -> pattern %s"):format(
            w.name, safe(w.fmt), safe(w.pattern)))
    end
    -- Art DuelElo depends on: rated-PvP tier icons and UI atlases.
    if C_PvP and C_PvP.GetPvpTierInfo then
        local seen = {}
        for id = 0, 200 do
            local ok, info = pcall(C_PvP.GetPvpTierInfo, id)
            if ok and type(info) == "table" and info.tierIconID and not seen[info.pvpTierEnum or -1] then
                seen[info.pvpTierEnum or -1] = true
                log(("ASSET tier enum=%s iconFileID=%s (tierID %d)"):format(
                    safe(info.pvpTierEnum), safe(info.tierIconID), id))
            end
        end
        if not next(seen) then log("ASSET C_PvP.GetPvpTierInfo returned no tiers") end
    else
        log("ASSET C_PvP.GetPvpTierInfo MISSING")
    end
    -- Does SetTexture report missing files? DuelElo's fallbacks rely on it.
    local t = UIParent:CreateTexture(nil, "BACKGROUND")
    t:Hide()
    log(("ASSET SetTexture(real 134400) -> %s   SetTexture(bogus 999999999) -> %s   SetTexture(bogus path) -> %s"):format(
        safe(t:SetTexture(134400)), safe(t:SetTexture(999999999)),
        safe(t:SetTexture("Interface\\DuelEloProbe\\does_not_exist"))))
    if GetFileIDFromPath then
        log(("ASSET GetFileIDFromPath(UI_RankedPvP_01) -> %s (expect 2023043)   (UI_RankedPvP_06) -> %s   (bogus) -> %s"):format(
            safe(GetFileIDFromPath("Interface\\PVPFrame\\Icons\\UI_RankedPvP_01")),
            safe(GetFileIDFromPath("Interface\\PVPFrame\\Icons\\UI_RankedPvP_06")),
            safe(GetFileIDFromPath("Interface\\DuelEloProbe\\does_not_exist"))))
    else
        log("ASSET GetFileIDFromPath MISSING")
    end
    for _, atlas in ipairs({ "nameplates-icon-elite-gold", "nameplates-icon-elite-silver", "groupfinder-icon-leader" }) do
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
        log(("ASSET atlas %s -> %s"):format(atlas, info and ("fileID " .. safe(info.file)) or "MISSING"))
    end

    if DuelEloProbeDB then
        log(("SAVEDVARS loads=%d firstLoad=%s lastLogout=%s"):format(
            DuelEloProbeDB.loads, safe(DuelEloProbeDB.firstLoad), safe(DuelEloProbeDB.lastLogout)))
    end
end

---------------------------------------------------------------------------
-- Probe v2: what DuelElo v1 needs (readiness reads, encoding, bit, levels).
-- Every read is pcall-wrapped: a missing API logs MISSING, never errors.
---------------------------------------------------------------------------

local witnessSeen = 0  -- winner messages for duels we weren't in (witness candidates)

-- Calls fn(...) and returns "ok" plus a printable summary, or the error.
local function call(fn, ...)
    if type(fn) ~= "function" then return false, "MISSING" end
    local res = { pcall(fn, ...) }
    if not res[1] then return false, "ERROR " .. safe(res[2]) end
    local out = {}
    for i = 2, table.maxn(res) do out[#out + 1] = safe(res[i]) end
    return true, #out > 0 and table.concat(out, ", ") or "(nothing)", res[2], res[3], res[4]
end

local function listKeys(t)
    if type(t) ~= "table" then return "MISSING" end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    return #keys > 0 and table.concat(keys, " ") or "(empty)"
end

-- The 3 longest base cooldowns in the active spellbook, for the cooldown reads.
local function scanSpellbook()
    local book = C_SpellBook
    if not (book and book.GetNumSpellBookSkillLines) then
        log("V2 SPELLBOOK C_SpellBook MISSING")
        return {}
    end
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local okLines, lines = pcall(book.GetNumSpellBookSkillLines)
    if not okLines then log("V2 SPELLBOOK GetNumSpellBookSkillLines ERROR " .. safe(lines)) return {} end
    local spells, long, items = {}, 0, 0
    for line = 1, (tonumber(lines) or 0) do
        local okInfo, info = pcall(book.GetSpellBookSkillLineInfo, line)
        if okInfo and type(info) == "table" and not info.offSpecID then
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local okItem, item = pcall(book.GetSpellBookItemInfo, i, bank)
                if okItem and type(item) == "table" and type(item.spellID) == "number" and not item.isPassive then
                    items = items + 1
                    local okBase, base = pcall(GetSpellBaseCooldown, item.spellID)
                    if okBase and type(base) == "number" and not (issecretvalue and issecretvalue(base)) and base >= 60000 then
                        long = long + 1
                        spells[#spells + 1] = { id = item.spellID, name = safe(item.name), base = base }
                    end
                end
            end
        end
    end
    log(("V2 SPELLBOOK lines=%s activeSpells=%d longCooldowns(>=60s)=%d"):format(safe(lines), items, long))
    table.sort(spells, function(a, b) return a.base > b.base end)
    return { spells[1], spells[2], spells[3] }
end

local function probeV2()
    log("V2 ---- probe v2 ----")
    local _, combat = call(UnitAffectingCombat, "player")
    log(("V2 COMBAT UnitAffectingCombat=%s InCombatLockdown=%s"):format(combat, select(2, call(InCombatLockdown))))

    -- Readiness inputs
    log(("V2 HEALTH UnitHealth=%s UnitHealthMax=%s"):format(select(2, call(UnitHealth, "player")),
        select(2, call(UnitHealthMax, "player"))))
    local mana = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
    log(("V2 POWER type=%s mana=%s manaMax=%s"):format(select(2, call(UnitPowerType, "player")),
        select(2, call(UnitPower, "player", mana)), select(2, call(UnitPowerMax, "player", mana))))
    local auras = C_UnitAuras
    log(("V2 AURAS GetAuraDataByIndex=%s GetPlayerAuraBySpellID=%s UnitBuff=%s"):format(
        exists(auras and auras.GetAuraDataByIndex), exists(auras and auras.GetPlayerAuraBySpellID), exists(UnitBuff)))
    if auras and auras.GetAuraDataByIndex then
        local n, firstId = 0, nil
        for i = 1, 40 do
            local ok, aura = pcall(auras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok then log("V2 AURAS read ERROR " .. safe(aura)) break end
            if not aura then break end
            n = n + 1
            firstId = firstId or safe(aura.spellId)
        end
        log(("V2 AURAS out-of-combat helpful=%d firstSpellId=%s"):format(n, safe(firstId)))
    end

    for _, sp in ipairs(scanSpellbook()) do
        local getCooldown = C_Spell and C_Spell.GetSpellCooldown
        local _, cd = call(getCooldown, sp.id)
        local okInfo, info = pcall(getCooldown, sp.id)
        if okInfo and type(info) == "table" then
            cd = ("start=%s duration=%s enabled=%s"):format(safe(info.startTime), safe(info.duration), safe(info.isEnabled))
        end
        log(("V2 COOLDOWN %s (%d) base=%dms now: %s"):format(sp.name, sp.id, sp.base, cd))
    end
    for _, slot in ipairs({ 13, 14 }) do
        log(("V2 TRINKET slot %d GetInventoryItemCooldown=%s"):format(slot,
            select(2, call(GetInventoryItemCooldown, "player", slot))))
    end

    -- Encoding and bit ops (signing, upload codes)
    log("V2 C_EncodingUtil: " .. listKeys(C_EncodingUtil))
    log(("V2 BIT bit=%s band=%s bxor=%s rshift=%s lshift=%s bnot=%s  bit32=%s"):format(exists(bit),
        exists(bit and bit.band), exists(bit and bit.bxor), exists(bit and bit.rshift), exists(bit and bit.lshift),
        exists(bit and bit.bnot), exists(bit32)))
    if bit and bit.bxor then
        log("V2 BIT bxor(0xFFFFFFFF, 1)=" .. select(2, call(bit.bxor, 0xFFFFFFFF, 1)) .. " (expect -2 or 4294967294)")
    end

    -- Clocks and levels
    log(("V2 TIME debugprofilestop=%s GetServerTime=%s time=%s"):format(select(2, call(debugprofilestop)),
        select(2, call(GetServerTime)), safe(time())))
    log(("V2 LEVEL UnitLevel=%s GetMaxLevelForPlayerExpansion=%s"):format(select(2, call(UnitLevel, "player")),
        select(2, call(GetMaxLevelForPlayerExpansion))))
    -- Forever names have surnames ("First Last"); log every way the client
    -- spells a name, for the player and (if any) the target.
    for _, unit in ipairs({ "player", "target" }) do
        if UnitExists and UnitExists(unit) then
            local n1, r1 = UnitName(unit)
            local n2, r2 = UnitFullName(unit)
            local guid = UnitGUID and UnitGUID(unit)
            local gi = guid and GetPlayerInfoByGUID and { pcall(GetPlayerInfoByGUID, guid) } or {}
            log(("V2 NAMES %s UnitName=[%s][%s] UnitFullName=[%s][%s] GetUnitName(true)=[%s] GUID=%s byGUID name=[%s] realm=[%s]")
                :format(unit, safe(n1), safe(r1), safe(n2), safe(r2),
                    safe(GetUnitName and GetUnitName(unit, true)), safe(guid), safe(gi[7]), safe(gi[8])))
        end
    end
    log(("V2 REALM GetRealmName=[%s] GetNormalizedRealmName=[%s] GetCurrentRegion=%s GetCurrentRegionName=%s")
        :format(safe(GetRealmName and GetRealmName()), safe(GetNormalizedRealmName and GetNormalizedRealmName()),
            safe(GetCurrentRegion and GetCurrentRegion()), safe(GetCurrentRegionName and GetCurrentRegionName())))
    log(("V2 PERCENT UnitHealthPercent=%s UnitPowerPercent=%s"):format(
        select(2, call(UnitHealthPercent, "player")), select(2, call(UnitPowerPercent, "player", 0))))
    local chans = { pcall(function() return GetChannelList() end) }
    local chanText = {}
    for i = 2, #chans, 3 do chanText[#chanText + 1] = safe(chans[i]) .. "." .. safe(chans[i + 1]) end
    log(("V2 CHANNELS swap=%s list: %s"):format(
        exists(C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex), table.concat(chanText, " ")))
    log(("V2 WITNESS winner messages for other players' duels this session: %d"):format(witnessSeen))

    -- Forever vs retail data the site shows: class roster, specs, map ids
    local okN, nText, numClasses = call(GetNumClasses)
    local classes = {}
    if okN and type(numClasses) == "number" then
        for i = 1, numClasses do
            local okC, _, cName, cFile = call(GetClassInfo, i)
            if okC and cFile then classes[#classes + 1] = safe(cFile) .. "=" .. safe(cName) end
        end
    end
    log(("V2 CLASSES GetNumClasses=%s %s"):format(nText, table.concat(classes, " ")))
    local okS, sText, index = call(GetSpecialization)
    local specInfo = "n/a"
    if okS and type(index) == "number" then specInfo = select(2, call(GetSpecializationInfo, index)) end
    log(("V2 SPEC GetSpecialization=%s GetSpecializationInfo=%s"):format(sText, specInfo))
    local si = C_SpecializationInfo
    local okS, siText, siIndex = call(si and si.GetSpecialization)
    log(("V2 SPEC C_SpecializationInfo.GetSpecialization=%s GetSpecializationInfo=%s (specs unlock at level 10 on retail)"):format(
        siText, okS and type(siIndex) == "number" and select(2, call(si.GetSpecializationInfo, siIndex)) or "n/a"))
    local okC, cText, config = call(C_ClassTalents and C_ClassTalents.GetActiveConfigID)
    local okI, _, import = call(okC and type(config) == "number" and C_Traits and C_Traits.GenerateImportString, config)
    log(("V2 TRAITS GetActiveConfigID=%s importString=%s"):format(cText,
        okI and type(import) == "string" and (#import .. " chars: " .. import:sub(1, 40)) or "n/a"))
    local mapId = C_Map and select(3, call(C_Map.GetBestMapForUnit, "player"))
    local mapInfo = C_Map and type(mapId) == "number" and select(3, call(C_Map.GetMapInfo, mapId))
    log(("V2 MAP GetBestMapForUnit=%s name=%s (log this in each capital and duel spot)"):format(
        safe(mapId), safe(type(mapInfo) == "table" and mapInfo.name or nil)))

    -- build snapshot (SPEC §3.13): classic talent API, item link format, cast events
    local okT, tText, tabs = call(GetNumTalentTabs)
    log(("V2 TALENTS GetNumTalentTabs=%s C_ClassTalents=%s C_Traits.GenerateImportString=%s"):format(tText,
        exists(C_ClassTalents), exists(C_Traits and C_Traits.GenerateImportString)))
    if okT and type(tabs) == "number" then
        for tab = 1, tabs do
            local _, nText, n = call(GetNumTalents, tab)
            local points, first = 0, "n/a"
            for i = 1, type(n) == "number" and n or 0 do
                local okI, text, name = call(GetTalentInfo, tab, i)
                if i == 1 then first = text end
                local rank = okI and select(5, GetTalentInfo(tab, i))
                if type(rank) == "number" then points = points + rank end
                if not okI or type(name) ~= "string" then break end
            end
            log(("V2 TALENTS tab %d GetNumTalents=%s points=%d first=%s (name, icon, tier, column, rank, max...)")
                :format(tab, nText, points, first))
        end
    end
    local _, link = call(GetInventoryItemLink, "player", 16)
    log(("V2 GEAR main hand link=%s GetItemSpell=%s C_Item.GetItemSpell=%s"):format(link, exists(GetItemSpell),
        exists(C_Item and C_Item.GetItemSpell)))
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local EVENTS = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT",
    "DUEL_REQUESTED", "DUEL_FINISHED", "DUEL_INBOUNDS", "DUEL_OUTOFBOUNDS",
    "DUEL_TO_THE_DEATH_REQUESTED",
    "START_TIMER", "STOP_TIMER_OF_TYPE",
    "CHAT_MSG_SYSTEM", "CHAT_MSG_ADDON",
}

local f = CreateFrame("Frame")
local failedEvents = {}
for _, ev in ipairs(EVENTS) do
    if not pcall(f.RegisterEvent, f, ev) then failedEvents[#failedEvents + 1] = ev end
end

local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON then return end
    local fresh = DuelEloProbeDB == nil
    DuelEloProbeDB = DuelEloProbeDB or { log = {}, loads = 0, firstLoad = date("%Y-%m-%d %H:%M:%S") }
    DuelEloProbeDB.loads = DuelEloProbeDB.loads + 1
    for _, line in ipairs(pending) do
        local L = DuelEloProbeDB.log
        L[#L + 1] = line
    end
    pending = {}
    log(("SAVEDVARS %s, loads=%d"):format(fresh and "FRESH (nothing loaded from disk)" or "LOADED from disk",
        DuelEloProbeDB.loads))
    if #failedEvents > 0 then
        log("EVENTS NOT SUPPORTED: " .. table.concat(failedEvents, ", "))
    end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        log("REGISTER prefix -> " .. safe(C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)))
    end
end

function handlers.PLAYER_LOGIN()
    status()
    probeV2()
end

function handlers.PLAYER_LOGOUT()
    if DuelEloProbeDB then DuelEloProbeDB.lastLogout = date("%Y-%m-%d %H:%M:%S") end
end

function handlers.DUEL_REQUESTED(challenger)
    log("EVENT DUEL_REQUESTED challenger=" .. safe(challenger))
    if type(challenger) == "string" then send("HELLO", "WHISPER", challenger) end
end

function handlers.CHAT_MSG_SYSTEM(msg, ...)
    log("SYSTEM " .. safe(msg))
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
    for _, w in ipairs(winPatterns) do
        if w.pattern then
            local caps = { msg:match(w.pattern) }
            if caps[1] then
                local args = {}
                for i, c in ipairs(caps) do args[w.order[i]] = c end
                local winner, loser = args[1], args[2]
                local me = UnitName("player")
                local function isMe(n) return n == me or (n and n:match("^([^%-]+)") == me) end
                local mine = isMe(winner) or isMe(loser)
                if not mine then witnessSeen = witnessSeen + 1 end
                log(("  MATCHED %s: winner=%s loser=%s involvesMe=%s"):format(
                    w.name, safe(winner), safe(loser), tostring(mine)))
            end
        end
    end
end

function handlers.CHAT_MSG_ADDON(prefix, text, channel, sender, ...)
    if prefix ~= PREFIX then return end
    log(("RECV '%s' via %s from %s extra=[%s]"):format(
        safe(text), safe(channel), safe(sender), fmtArgs(...)))
    if type(text) ~= "string" or type(sender) ~= "string" then return end
    if text == "HELLO" then
        send("HELLO_ACK", "WHISPER", sender)
    elseif text == "PING" then
        send("PONG", "WHISPER", sender)
    end
end

f:SetScript("OnEvent", function(_, event, ...)
    local h = handlers[event]
    if h then
        h(...)
    else
        log("EVENT " .. event .. " args=[" .. fmtArgs(...) .. "]")
    end
end)

if type(StartDuel) == "function" then
    hooksecurefunc("StartDuel", function(unit)
        local target = UnitName(unit or "target")
        local u = unit or "target"
        local guid = UnitGUID and UnitGUID(u)
        local gi = guid and GetPlayerInfoByGUID and { pcall(GetPlayerInfoByGUID, guid) } or {}
        log(("HOOK StartDuel unit=%s name=%s UnitClass=%s byGUID name=[%s] class=%s"):format(safe(unit), safe(target),
            select(2, call(UnitClass, u)), safe(gi[7]), safe(gi[3])))
        -- whole name from the GUID: on Forever UnitFullName gives (first, surname)
        local whole = gi[1] and type(gi[7]) == "string" and gi[7] ~= "" and gi[7]
        if whole then
            send("HELLO", "WHISPER", (gi[8] and gi[8] ~= "") and (whole .. "-" .. gi[8]) or whole)
        else
            local name, realm = UnitFullName(u)
            if type(name) == "string" then
                send("HELLO", "WHISPER", (realm and realm ~= "") and (name .. "-" .. realm) or name)
            end
        end
    end)
end

if type(AcceptDuel) == "function" then
    hooksecurefunc("AcceptDuel", function() log("HOOK AcceptDuel called") end)
else
    log("AcceptDuel MISSING")
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_DUELELOPROBE1 = "/probe"
SlashCmdList.DUELELOPROBE = function(input)
    local cmd, rest = (input or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "ping" and rest ~= "" then
        send("PING", "WHISPER", rest)
    elseif cmd == "pingtarget" then
        local name, realm = UnitFullName("target")
        if not name then log("No target.") return end
        send("PING", "WHISPER", (realm and realm ~= "") and (name .. "-" .. realm) or name)
    elseif cmd == "v2" then
        probeV2()
    elseif cmd == "clear" then
        DuelEloProbeDB.log = {}
        log("Log cleared.")
    else
        status()
        print("|cff33ff99[Probe]|r Commands: /probe  |  /probe v2  |  /probe ping Name-Realm  |  /probe pingtarget  |  /probe clear")
    end
end
