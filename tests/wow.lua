-- Fake WoW API: just enough of the client for Parse/Data/Core to run headless.
local M = {}

local ADDON_FILES = { "Locale.lua", "Parse.lua", "Ladder.lua", "Crypto.lua", "Statement.lua", "Loadout.lua", "Codec.lua",
    "Export.lua", "Elo.lua", "Glicko.lua", "Rules.lua", "Readiness.lua", "WidgetModel.lua", "Leaderboard.lua",
    "Session.lua", "Data.lua", "BannedAuras.lua", "Core.lua", "Keys.lua", "Comm.lua", "Channel.lua", "Duel.lua",
    "Dev.lua", "Commands.lua", "ReadinessAdapter.lua", "LoadoutAdapter.lua" }

-- opts.units: { player = {name, realm, class}, target = {...}, ... }
-- opts.db / opts.charDB: SavedVariables as loaded from disk (nil = fresh install)
function M.new(opts)
    opts = opts or {}
    local env = {
        frames = {},
        printed = {},
        secrets = {},
        units = opts.units or {},
    }
    env.units.player = env.units.player or { name = "Ashvale", realm = "Sargeras", class = "PALADIN" }

    DuelEloDB, DuelEloCharDB = opts.db, opts.charDB
    DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
    DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"
    DUEL_COUNTDOWN = "Duel starting: %d"

    function CreateFrame()
        local f = { events = {}, scripts = {} }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterEvent(e) self.events[e] = nil end
        function f:SetScript(name, fn) self.scripts[name] = fn end
        env.frames[#env.frames + 1] = f
        return f
    end

    SetItemRef = function() end
    StartDuel = function() end
    AcceptDuel = function() end

    -- Addon messaging: everything sent is captured in env.sent.
    env.sent, env.timers, env.clock, env.inGuild = {}, {}, 1000, false
    C_ChatInfo = {
        RegisterAddonMessagePrefix = function(p) env.prefix = p return 0 end,
        SendAddonMessage = function(prefix, msg, channel, target)
            env.sent[#env.sent + 1] = { prefix = prefix, msg = msg, channel = channel, target = target }
        end,
    }
    function GetTime() return env.clock end
    function IsInGuild() return env.inGuild end
    env.tickers = {}
    C_Timer = {
        After = function(_, fn) env.timers[#env.timers + 1] = fn end,
        NewTicker = function(_, fn)
            local t = { fn = fn }
            function t:Cancel() self.cancelled = true end
            env.tickers[#env.tickers + 1] = t
            return t
        end,
    }
    -- Run every live ticker once (one poll interval passing).
    function env.tick()
        for _, t in ipairs(env.tickers) do if not t.cancelled then t.fn() end end
    end
    function env.liveTickers()
        local n = 0
        for _, t in ipairs(env.tickers) do if not t.cancelled then n = n + 1 end end
        return n
    end

    -- Custom channels, chat frames, and the bits of player info we record.
    -- env.channels: name -> channel number, like /1 General. A new channel takes
    -- the lowest free number, as in game; opts.channels replaces the defaults.
    env.channels = opts.channels or { General = 1, Trade = 2, LocalDefense = 3, LookingForGroup = 4 }
    env.filters, env.removedFrom = {}, {}
    function JoinTemporaryChannel(name)
        if env.channels[name] then return end
        local used = {}
        for _, id in pairs(env.channels) do used[id] = true end
        local id = 1
        while used[id] do id = id + 1 end
        env.channels[name] = id
    end
    function LeaveChannelByName(name) env.channels[name] = nil end
    function GetChannelName(name) return env.channels[name] or 0 end
    function GetChannelList()
        local ids = {}
        for name, id in pairs(env.channels) do ids[#ids + 1] = { id, name } end
        table.sort(ids, function(a, b) return a[1] < b[1] end)
        local out = {}
        for _, c in ipairs(ids) do out[#out + 1] = c[1]; out[#out + 1] = c[2]; out[#out + 1] = false end
        return unpack(out)
    end
    C_ChatInfo.SwapChatChannelsByChannelIndex = function(a, b)
        for name, id in pairs(env.channels) do
            if id == a then env.channels[name] = b elseif id == b then env.channels[name] = a end
        end
    end
    -- The game joining a channel by itself (zoning, or rejoining at login).
    function env.gameJoins(name)
        JoinTemporaryChannel(name)
        env.fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", "", "", env.channels[name] .. ". " .. name)
    end
    NUM_CHAT_WINDOWS = 2
    ChatFrame1, ChatFrame2 = { id = 1 }, { id = 2 }
    function ChatFrame_RemoveChannel(cf, name) env.removedFrom[#env.removedFrom + 1] = cf.id .. ":" .. name end
    function ChatFrame_AddMessageEventFilter(event, fn) env.filters[event] = fn end
    C_Map = { GetBestMapForUnit = function() return 84 end }  -- Stormwind
    function GetSpecialization() return 1 end
    function GetSpecializationInfo() return 253 end            -- Beast Mastery
    function GetAverageItemLevel() return 615.4, 612.7 end
    function GetCurrentRegion() return 1 end
    env.toc = opts.toc or 16001  -- WoW Forever
    function GetBuildInfo() return "1.16.1", "60000", "Oct 1 2026", env.toc end
    function GetServerTime() return os.time() end
    function debugprofilestop() return os.clock() * 1000 end
    function UnitGUID() return "Player-1234-0ABCDEF0" end
    function UnitLevel(unit) return (env.units[unit] or {}).level or 30 end
    function hooksecurefunc(name, hook)
        local orig = _G[name]
        _G[name] = function(...) orig(...); hook(...) end
    end

    -- Player state read by ReadinessAdapter. Tests change env.vitals and
    -- env.spells; a spell is { id, baseMs, start, duration }.
    env.vitals = { combat = false, health = 100, healthMax = 100, mana = 100, manaMax = 100,
        trinkets = { [13] = { 0, 0, 1 }, [14] = { 0, 0, 1 } }, auras = {} }
    env.spells = {}
    function UnitAffectingCombat() return env.vitals.combat end
    function UnitHealth() return env.vitals.health end
    function UnitHealthMax() return env.vitals.healthMax end
    function UnitPower() return env.vitals.mana end
    function UnitPowerMax() return env.vitals.manaMax end
    function GetInventoryItemCooldown(_, slot) return unpack(env.vitals.trinkets[slot]) end
    UnitBuff = nil  -- only the fallback test defines it
    -- build snapshot reads (SPEC §3.13): absent unless a test defines them
    GetNumTalentTabs, GetNumTalents, GetTalentInfo = nil, nil, nil
    GetInventoryItemLink, GetInventoryItemID, GetItemSpell = nil, nil, nil
    C_UnitAuras = { GetPlayerAuraBySpellID = function(id) return env.vitals.auras[id] end }
    C_SpellBook = {
        GetNumSpellBookSkillLines = function() return 1 end,
        GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #env.spells } end,
        GetSpellBookItemInfo = function(i)
            local s = env.spells[i]
            return s and { itemType = 1, spellID = s[1], isPassive = false }
        end,
    }
    local function spell(id)
        for _, s in ipairs(env.spells) do if s[1] == id then return s end end
    end
    function GetSpellBaseCooldown(id) return spell(id)[2], 1500 end
    C_Spell = { GetSpellCooldown = function(id)
        local s = spell(id)
        return { startTime = s[3], duration = s[4], isEnabled = true, modRate = 1 }
    end }

    function issecretvalue(v) return env.secrets[v] == true end
    function UnitExists(unit) return env.units[unit] ~= nil end
    function UnitFullName(unit)
        local u = env.units[unit]
        if u then return u.name, u.realm end
    end
    function UnitClass(unit)
        local u = env.units[unit]
        if u then return u.class, u.class end
    end
    function GetNormalizedRealmName() return env.units.player.realm end
    time = os.time
    date = os.date
    print = function(s) env.printed[#env.printed + 1] = s end
    geterrorhandler = function() return error end
    SlashCmdList = {}

    -- Deliver an event to every frame registered for it.
    function env.fire(event, ...)
        for _, f in ipairs(env.frames) do
            if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
        end
    end

    function env.slash(input) SlashCmdList.DUELELO(input) end

    function env.runTimers()
        local t = env.timers
        env.timers = {}
        for _, fn in ipairs(t) do fn() end
    end

    -- An addon message arriving from another player.
    function env.addonMsg(sender, text, channel)
        env.fire("CHAT_MSG_ADDON", env.prefix or "DuelElo", text, channel or "WHISPER", sender)
    end

    -- Most recent message we sent whose text starts with `kind` (e.g. "H", "R~").
    function env.lastSent(kind)
        for i = #env.sent, 1, -1 do
            if env.sent[i].msg:sub(1, #kind) == kind then return env.sent[i] end
        end
    end

    -- Load the addon files the way the client does, then log in.
    function env.load()
        env.ns = {}
        for _, file in ipairs(ADDON_FILES) do
            assert(loadfile("DuelElo/" .. file))("DuelElo", env.ns)
        end
        return env.ns
    end

    function env.login()
        env.load()
        env.fire("ADDON_LOADED", "DuelElo")
        env.fire("PLAYER_LOGIN")
        return env.ns
    end

    function env.lastPrint() return env.printed[#env.printed] end

    return env
end

return M
