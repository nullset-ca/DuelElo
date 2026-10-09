-- Core.lua: shared helpers (printing, listeners, unit names) and event wiring.
-- The work lives in Comm.lua, Channel.lua, Duel.lua, Dev.lua and Commands.lua,
-- which load after this file; handlers reach them through ns at event time.
local ADDON, ns = ...
local Parse, Data = ns.Parse, ns.Data

local PREFIX_TEXT = "|cffffd100DuelElo|r "
local GUILD_SHARE_DELAY = 15      -- seconds after login before sharing stats with the guild
local CHANNEL_JOIN_DELAY = 30     -- join after General/Trade so we don't take /1 or /2
local PLAYER_KEEP = 90 * 86400    -- forget players not heard from in this long

-- The logged-in character; filled at PLAYER_LOGIN. Modules keep a reference
-- to this table, so it is updated in place, never replaced.
local me = { name = nil, realm = nil, full = nil, class = nil }
ns.me = me

local listeners = {}
ns.debugOn = false

function ns.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end
local isSecret = ns.IsSecret

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "?"

-- Which client this is (SPEC §3.12). DuelElo is for WoW Forever; retail is
-- only the developer's test bed, and its data never reaches the ladder.
function ns.FlavorOf(toc)
    toc = tonumber(toc)
    if not toc then return "unknown" end
    if toc >= 16000 and toc <= 16999 then return "forever" end
    if toc >= 110000 then return "retail" end
    return "unknown"
end
ns.FLAVOR = ns.FlavorOf(GetBuildInfo and select(4, GetBuildInfo()))

function ns.Print(msg)
    print(PREFIX_TEXT .. msg)
end

function ns.DPrint(msg)
    if ns.debugOn then ns.Print("|cff888888" .. msg .. "|r") end
end

-- Listeners are called as fn(event, ...) e.g. fn("DUEL_RECORDED", entry).
function ns.Listen(fn)
    listeners[#listeners + 1] = fn
end

function ns.Fire(event, ...)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, event, ...)
        if not ok then geterrorhandler()(err) end
    end
end

---------------------------------------------------------------------------
-- Unit helpers
---------------------------------------------------------------------------

-- What GetNormalizedRealmName strips from a realm's display name.
local function normalizeRealm(realm) return (realm:gsub("[%s%-']", "")) end

-- A unit's name and realm (nil on our own realm). WoW Forever names have
-- surnames ("Duelio Vodee"): there UnitFullName returns the surname where
-- retail returns the realm, while GetPlayerInfoByGUID gives the whole name on
-- both clients and a realm only for other realms. Chat and addon messages use
-- that whole name. UnitFullName stays the fallback (NPCs, older clients).
local function unitNameRealm(unit)
    local guid = UnitGUID and UnitGUID(unit)
    if type(guid) == "string" and not isSecret(guid) and GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
        if ok and type(name) == "string" and name ~= "" and not isSecret(name) and not isSecret(realm) then
            return name, (type(realm) == "string" and realm ~= "") and normalizeRealm(realm) or nil
        end
    end
    local name, realm = UnitFullName(unit)
    if type(name) ~= "string" or isSecret(name) or isSecret(realm) then return nil end
    return name, (type(realm) == "string" and realm ~= "") and realm or nil
end

function ns.UnitFullName(unit)
    if not UnitExists(unit) then return nil end
    local name, realm = unitNameRealm(unit)
    if not name then return nil end
    return Parse.Normalize(realm and (name .. "-" .. realm) or name, me.realm)
end

-- "Thrall-Sargeras" -> "Thrall" when Sargeras is our realm.
function ns.DisplayName(full)
    local name, realm = Parse.SplitName(full)
    if realm == me.realm then return name end
    return full
end

-- The official ladder entry for a player (default: us), from DuelElo_Ladder.
function ns.OfficialEntry(name)
    return ns.Ladder.Entry(DuelEloLadderData, ns.account and ns.account.region, name or me.full)
end

-- The ladder data addon is load-on-demand: load it if installed.
local function loadLadder()
    local load = C_AddOns and C_AddOns.LoadAddOn
    if load and pcall(load, ns.Ladder.ADDON) and DuelEloLadderData then ns.Fire("LADDER_LOADED") end
end

-- Our level, or nil if the client hides it.
function ns.MyLevel()
    local level = UnitLevel and UnitLevel("player")
    if type(level) ~= "number" or isSecret(level) then return nil end
    return level
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON then return end
    DuelEloDB = Data.InitAccount(DuelEloDB)
    DuelEloCharDB = Data.InitChar(DuelEloCharDB)
    ns.account, ns.char = DuelEloDB, DuelEloCharDB
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(ns.Comm.PREFIX)
    end
    frame:UnregisterEvent("ADDON_LOADED")
end

function handlers.PLAYER_LOGIN()
    local name, realm = unitNameRealm("player")
    me.name = name
    -- our realm from GetNormalizedRealmName: on Forever UnitFullName's "realm" is the surname
    local normalized = GetNormalizedRealmName and GetNormalizedRealmName()
    me.realm = (type(normalized) == "string" and normalized ~= "") and normalized or realm
    me.full = Parse.Normalize(name, me.realm)
    me.class = select(2, UnitClass("player"))
    ns.engine = ns.Comm.NewEngine()
    ns.account.region = GetCurrentRegion and GetCurrentRegion() or ns.account.region
    ns.myFp = ns.Keys.Ensure(ns.char)
    Data.RegisterCharacter(ns.account, me.full, me.class, ns.MyLevel()).fp = ns.myFp
    Data.PrunePlayers(ns.account.players, time(), PLAYER_KEEP)
    ns.sessionStart = { t = time(), rating = ns.char.rating }  -- the widget's "this session" trend
    C_Timer.After(GUILD_SHARE_DELAY, function() ns.Comm.ShareStats(nil) end)
    C_Timer.After(CHANNEL_JOIN_DELAY, ns.Channel.Join)
    loadLadder()
    ns.Fire("READY")
end

function handlers.PLAYER_LEVEL_UP(level)
    if type(level) == "number" and not isSecret(level) then
        Data.RegisterCharacter(ns.account, me.full, me.class, level)
    end
end

function handlers.CHAT_MSG_SYSTEM(msg)
    ns.HandleSystemMessage(msg)
end

function handlers.DUEL_REQUESTED(challenger)
    if type(challenger) == "string" and not isSecret(challenger) then
        ns.Duel.RememberOpponent(Parse.Normalize(challenger, me.realm), "D")
    end
end

function handlers.DUEL_FINISHED()
    if ns.engine then ns.engine:Finished() end
    ns.Snapshot.Stop()
end

function handlers.CHAT_MSG_ADDON(prefix, text, channel, sender)
    ns.Comm.OnAddonMessage(prefix, text, channel, sender)
end

for event in pairs(handlers) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, ...) handlers[event](...) end)
