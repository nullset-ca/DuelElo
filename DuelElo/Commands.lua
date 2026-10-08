-- Commands.lua: slash commands, the minimap compartment button, and the
-- community touches (Discord link, welcome and one-time invite).
local ADDON, ns = ...
local L = ns.L
local Dev = ns.Dev

local DISCORD_URL = "https://discord.gg/8Jyz7g4p64"  -- permanent invite to the community server
local DISCORD_NUDGE_AT = 10       -- after this many duels, mention the Discord once

-- Addons can't open a browser, so the Discord link is shown in a copy box.
-- In chat it's a clickable |Haddon:...|h link that opens the same box.
ns.DISCORD_URL = DISCORD_URL
local DISCORD_LINK_DATA = "addon:" .. ADDON .. ":discord"
local DISCORD_LINK = ("|cff8c9eff|H%s|h[Discord]|h|r"):format(DISCORD_LINK_DATA)

function ns.ShowDiscord()
    if ns.ShowCopyBox then
        ns.ShowCopyBox(L["DuelElo Discord"], L["Feedback, bug reports and ideas are welcome!\nPress Ctrl+C to copy the invite, then paste it into your browser."], DISCORD_URL)
    else
        ns.Print(L["Discord: %s"]:format(DISCORD_URL))
    end
end

if SetItemRef then
    hooksecurefunc("SetItemRef", function(link)
        if link == DISCORD_LINK_DATA then ns.ShowDiscord() end
    end)
end

---------------------------------------------------------------------------
-- Sound picker: /duelelo sound            list candidates
--               /duelelo sound 3          play candidate 3
--               /duelelo sound promote 3  use candidate 3 for promotions
---------------------------------------------------------------------------

local SOUND_MOMENTS = { victory = true, defeat = true, promote = true, demote = true }

local function soundCommand(a, b)
    local list = ns.SOUND_CANDIDATES or {}
    local n = tonumber(a)
    if n and list[n] then
        ns.PlaySoundKit(list[n][1])
        ns.Print(L["Playing %d: %s"]:format(n, list[n][2]))
    elseif SOUND_MOMENTS[a] and tonumber(b) and list[tonumber(b)] then
        local pick = list[tonumber(b)]
        ns.account.settings.sounds[a] = pick[1]
        ns.PlaySoundKit(pick[1])
        ns.Print(L["%s sound set to %s"]:format(a, pick[2]))
    else
        for i, s in ipairs(list) do ns.Print(("%d. %s"):format(i, s[2])) end
        ns.Print(L["/duelelo sound <n> to listen, /duelelo sound <victory|defeat|promote|demote> <n> to choose"])
    end
end

---------------------------------------------------------------------------
-- Rank widget: /duelelo widget show|hide|lock|unlock|reset|preset <p>|scale <n>|opacity <n>
---------------------------------------------------------------------------

local function widgetCommand(a, b)
    local w = ns.account.settings.widget
    if a == "show" or a == "hide" then
        w.shown = a == "show"
    elseif a == "lock" or a == "unlock" then
        w.locked = a == "lock"
    elseif a == "reset" then
        w.pos = nil
    elseif a == "preset" and ns.WidgetModel.PRESETS[b] then
        w.preset = b
    elseif (a == "scale" or a == "opacity") and tonumber(b) then
        w[a] = tonumber(b) / 100
    else
        ns.Print(L["Rank widget: %s, %s, %s, %d%% size, %d%% opacity"]:format(w.shown and L["shown"] or L["hidden"],
            w.preset, w.locked and L["locked"] or L["unlocked"], w.scale * 100 + 0.5, w.opacity * 100 + 0.5))
        ns.Print(L["/duelelo widget show|hide|lock|unlock|reset|preset full|compact|minimal|scale 50-200|opacity 30-100"])
        return
    end
    ns.WidgetModel.Validate(w)
    ns.Fire("WIDGET_CHANGED")
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

-- Developer tools: hidden from help and refused unless dev mode is on.
local DEV_COMMANDS = { demo = true, test = true, art = true, debug = true }

local function setDev(on)
    ns.account.dev = on
    if not on then
        ns.debugOn = false
        if ns.demo then Dev.ToggleDemo() end
    end
end

SLASH_DUELELO1 = "/duelelo"
SLASH_DUELELO2 = "/delo"
SlashCmdList.DUELELO = function(input)
    local cmd, arg, arg2 = (input or ""):match("^%s*(%S*)%s*(%S*)%s*(%S*)")
    cmd, arg, arg2 = cmd:lower(), arg:lower(), arg2:lower()
    local settings = ns.account.settings
    if DEV_COMMANDS[cmd] and not ns.account.dev then
        ns.Print(L["Dev mode is off. (/duelelo dev on)"])
        return
    end
    if cmd == "dev" then
        if arg == "on" or arg == "off" then setDev(arg == "on") end
        ns.Print(L["Dev mode: %s  (/duelelo dev on|off)"]:format(ns.account.dev and L["on"] or L["off"]))
    elseif cmd == "test" then
        Dev.ShowTest(arg)
    elseif cmd == "size" then
        local n = tonumber(arg)
        if n then
            settings.resultsScale = math.max(50, math.min(150, n)) / 100
            Dev.ShowTest("promo")
        end
        ns.Print(L["Results screen size: %d%%  (/duelelo size 50-150)"]:format(settings.resultsScale * 100 + 0.5))
    elseif cmd == "resetpos" then
        settings.resultsPos = nil
        ns.Print(L["Results screen position reset."])
        Dev.ShowTest("win")
    elseif cmd == "art" then
        Dev.Art(arg)
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        if ns.OpenOptions then ns.OpenOptions() end
    elseif cmd == "upload" then
        if ns.ShowUploadTab then ns.ShowUploadTab() end
    elseif cmd == "widget" then
        widgetCommand(arg, arg2)
    elseif cmd == "sound" then
        soundCommand(arg, arg2)
    elseif cmd == "channel" then
        if arg == "on" or arg == "off" then ns.SetChannelSharing(arg == "on") end
        ns.Print(L["Realm-wide leaderboard sharing: %s  (/duelelo channel on|off)"]:format(
            settings.shareChannel and L["on"] or L["off"]))
    elseif cmd == "discord" or cmd == "feedback" then
        ns.ShowDiscord()
    elseif cmd == "version" then
        ns.Print(L["Version %s"]:format(ns.VERSION))
    elseif cmd == "ranked" then
        if arg == "always" or arg == "ask" or arg == "never" then
            settings.rankedPref = arg
        end
        ns.Print(L["Ranked duels: %s  (/duelelo ranked always|ask|never)"]:format(settings.rankedPref))
    elseif cmd == "strict" then
        if arg == "on" or arg == "off" then settings.strict = arg == "on" end
        ns.Print(L["Strict ranked (cooldowns ready on both sides): %s  (/duelelo strict on|off)"]:format(
            settings.strict and L["on"] or L["off"]))
    elseif cmd == "results" then
        settings.resultsScreen = not settings.resultsScreen
        ns.Print(L["Results screen %s"]:format(settings.resultsScreen and L["on"] or L["off"]))
    elseif cmd == "debug" then
        Dev.ToggleDebug()
    elseif cmd == "chat" then
        settings.chatSummary = not settings.chatSummary
        ns.Print(L["Chat summary %s"]:format(settings.chatSummary and L["on"] or L["off"]))
    elseif cmd == "demo" then
        Dev.ToggleDemo()
    elseif cmd == "help" then
        ns.Print(L["Ranked dueling for WoW Forever. Commands (everything is also in Settings > AddOns > DuelElo):"])
        ns.Print(L["  /duelelo — open your record, leaderboard and stats"])
        ns.Print(L["  /duelelo options — open the settings"])
        ns.Print(L["  /duelelo ranked always|ask|never — ranked duel preference"])
        ns.Print(L["  /duelelo strict on|off — only play ranked when both sides' cooldowns are ready"])
        ns.Print(L["  /duelelo size 50-150 — results screen size, with a preview (drag it to move it)"])
        ns.Print(L["  /duelelo resetpos  |  /duelelo sound"])
        ns.Print(L["  /duelelo upload — create an upload code for the WoW Forever ladder"])
        ns.Print(L["  /duelelo widget — rank widget for streams: show|hide|lock|unlock|preset full|compact|minimal"])
        ns.Print(L["  /duelelo results  |  /duelelo chat  |  /duelelo channel on|off  |  /duelelo version"])
        ns.Print(L["  /duelelo discord — feedback, bug reports and ideas on our %s"]:format(DISCORD_LINK))
        if ns.account.dev then
            ns.Print(L["  Dev: /duelelo test <kind>  |  demo  |  art <mode>  |  debug  |  dev off"])
        end
    elseif cmd == "" then
        if ns.ToggleMain then ns.ToggleMain() end
    else
        ns.Print(L["Unknown command '%s'. Type /duelelo help."]:format(cmd))
    end
end
ns.Slash = SlashCmdList.DUELELO

-- Minimap addon-compartment button (declared in the .toc).
function DuelElo_OnAddonCompartmentClick()
    if ns.ToggleMain then ns.ToggleMain() end
end

function DuelElo_OnAddonCompartmentEnter(_, button)
    if not (GameTooltip and ns.char) then return end
    local c = ns.char
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine("DuelElo")
    if c.rankedGames >= ns.Elo.PLACEMENTS then
        local r = ns.Elo.Rank(c.rating)
        GameTooltip:AddLine(L["%s  ·  %d (estimated)"]:format(r.label, c.rating), r.color[1], r.color[2], r.color[3])
    else
        GameTooltip:AddLine(L["Placements %d / %d"]:format(c.rankedGames, ns.Elo.PLACEMENTS), 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(L["Record %d-%d"]:format(c.totals.w, c.totals.l), 1, 1, 1)
    GameTooltip:AddLine(L["Click to open"], 0.5, 0.5, 0.5)
    GameTooltip:AddLine(L["Feedback: /duelelo discord"], 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

function DuelElo_OnAddonCompartmentLeave()
    if GameTooltip then GameTooltip:Hide() end
end

-- One-time hello for new installs.
ns.Listen(function(event)
    if event ~= "READY" or ns.account.welcomed then return end
    ns.account.welcomed = true
    ns.Print(L["Thanks for installing DuelElo, ranked dueling for WoW Forever!"])
    ns.Print(L["Duel anyone and your record is tracked automatically."])
    ns.Print(L["If your opponent also has DuelElo, you can agree to a |cffffd100ranked|r duel. /duelelo opens your record."])
    ns.Print(L["Questions or ideas? Come say hi on our %s."]:format(DISCORD_LINK))
end)

-- One-time invite once someone has actually used the addon for a while.
ns.Listen(function(event)
    if event ~= "DUEL_RECORDED" or ns.account.discordNudged then return end
    if ns.char.totals.w + ns.char.totals.l < DISCORD_NUDGE_AT then return end
    ns.account.discordNudged = true
    ns.Print(L["Enjoying DuelElo? Tell us what you'd like next on our %s (/duelelo discord)."]:format(DISCORD_LINK))
end)
