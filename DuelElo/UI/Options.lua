-- UI/Options.lua: DuelElo's page in Settings > AddOns, built with the game's
-- Settings API once SavedVariables are loaded. Everything here is also
-- reachable by slash command, so a Settings API change can't lock players out.
local _, ns = ...
local L = ns.L

local category

local function percent(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end

local function build()
    local s = ns.account.settings
    category = Settings.RegisterVerticalLayoutCategory("DuelElo")
    local layout = SettingsPanel:GetLayout(category)

    local function header(text)
        if CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end

    local function setting(key, tbl, varType, name, default)
        return Settings.RegisterAddOnSetting(category, "DUELELO_" .. key:upper(), key, tbl, varType, name, default)
    end

    local function button(name, text, onClick, tooltip)
        if CreateSettingsButtonInitializer then
            layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, true))
        end
    end

    header(L["DuelElo — ranked dueling for WoW Forever"])
    button(L["Setup guide"], L["Run setup again"], function() if ns.ShowSetup then ns.ShowSetup() end end,
        L["Walk through the first-time setup again."])

    -- Ranked
    header(L["Ranked duels"])
    local pref = setting("rankedPref", s, Settings.VarType.String, L["Ranked duels"], "ask")
    Settings.CreateDropdown(category, pref, function()
        local c = Settings.CreateControlTextContainer()
        c:Add("always", L["Always ranked"])
        c:Add("ask", L["Ask each time"])
        c:Add("never", L["Never ranked"])
        return c:GetData()
    end, L["When your opponent also has DuelElo: agree to ranked automatically, get asked, or always play casual."])

    local strict = setting("strict", s, Settings.VarType.Boolean, L["Wait for cooldowns"], false)
    Settings.CreateCheckbox(category, strict,
        L["Off: cooldowns and trinkets are shown, but don't stop a ranked duel. On: ranked waits until both players' trinkets and 1-minute-plus cooldowns are ready."])

    local nudges = setting("uploadNudges", s, Settings.VarType.Boolean, L["Upload reminders"], true)
    Settings.CreateCheckbox(category, nudges,
        L["Remind me (once per session) when ranked duels are waiting to be uploaded and verified."])

    local share = setting("shareChannel", s, Settings.VarType.Boolean, L["Share rating realm-wide"], true)
    Settings.CreateCheckbox(category, share,
        L["Share your rating with other DuelElo players on your realm and see theirs on the leaderboard."])
    share:SetValueChangedCallback(function(_, value) ns.SetChannelSharing(value) end)

    -- Results screen
    header(L["Results screen"])
    local results = setting("resultsScreen", s, Settings.VarType.Boolean, L["Show results screen"], true)
    Settings.CreateCheckbox(category, results, L["Show VICTORY / DEFEAT with your rank after each duel."])

    local scale = setting("resultsScale", s, Settings.VarType.Number, L["Results screen size"], 0.8)
    local opts = Settings.CreateSliderOptions(0.5, 1.5, 0.05)
    opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, percent)
    Settings.CreateSlider(category, scale, opts, L["How big the results screen is."])

    button(L["Preview"], L["Preview"], function() ns.Dev.ShowTest("promo") end, L["Show a sample promotion."])
    button(L["Position"], L["Reset position"], function() ns.Slash("resetpos") end,
        L["Move the results screen back to the middle of the screen. (Drag it to move it.)"])

    local chat = setting("chatSummary", s, Settings.VarType.Boolean, L["Chat summary"], true)
    Settings.CreateCheckbox(category, chat, L["Also print a one-line summary of each duel in chat."])

    -- Rank widget (SPEC §3.11)
    header(L["Rank widget"])
    local w = s.widget
    local function widgetSetting(key, varType, name, tooltip, kind, extra)
        local st = Settings.RegisterAddOnSetting(category, "DUELELO_WIDGET_" .. key:upper(), key, w, varType, name,
            ns.WidgetModel.DEFAULTS[key])
        st:SetValueChangedCallback(function()
            ns.WidgetModel.Validate(w)
            ns.Fire("WIDGET_CHANGED")
        end)
        if kind == "checkbox" then
            Settings.CreateCheckbox(category, st, tooltip)
        elseif kind == "dropdown" then
            Settings.CreateDropdown(category, st, function()
                local c = Settings.CreateControlTextContainer()
                for _, o in ipairs(extra) do c:Add(o[1], o[2]) end
                return c:GetData()
            end, tooltip)
        else
            local o = Settings.CreateSliderOptions(extra[1], extra[2], 0.05)
            o:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, percent)
            Settings.CreateSlider(category, st, o, tooltip)
        end
    end
    local B, S, N = Settings.VarType.Boolean, Settings.VarType.String, Settings.VarType.Number
    widgetSetting("shown", B, L["Show rank widget"], L["A small panel with your rank, recent results and trend."], "checkbox")
    widgetSetting("preset", S, L["Widget style"], L["Full, Compact (one row) or Minimal (text only)."], "dropdown",
        { { "full", L["Full"] }, { "compact", L["Compact"] }, { "minimal", L["Minimal"] } })
    widgetSetting("trend", S, L["Trend display"], L["Show the rating change as a number, a sparkline, both or neither."],
        "dropdown", { { "number", L["Number"] }, { "sparkline", L["Sparkline"] }, { "both", L["Both"] }, { "none", L["None"] } })
    widgetSetting("period", S, L["Trend period"], L["Which games the trend covers."], "dropdown",
        { { "session", L["This session"] }, { "today", L["Today"] }, { "last10", L["Last 10 ranked games"] } })
    widgetSetting("recent", N, L["Recent results"], L["How many result boxes to show."], "dropdown",
        { { 3, "3" }, { 5, "5" }, { 10, "10" } })
    widgetSetting("casual", B, L["Include casual results"], L["Also show casual duels in the result boxes."], "checkbox")
    widgetSetting("nameTag", B, L["Show name tag"], L["NAME · REALM under the widget (Full style)."], "checkbox")
    widgetSetting("fade", B, L["Fade during duels"], L["Dim the widget while a duel is on."], "checkbox")
    widgetSetting("pulse", B, L["Pulse on rating change"], L["Briefly pulse the trend when your rating changes."], "checkbox")
    widgetSetting("scale", N, L["Widget size"], L["How big the widget is."], "slider", { ns.WidgetModel.SCALE_MIN, ns.WidgetModel.SCALE_MAX })
    widgetSetting("opacity", N, L["Widget opacity"], L["How see-through the widget is."], "slider",
        { ns.WidgetModel.OPACITY_MIN, ns.WidgetModel.OPACITY_MAX })
    widgetSetting("locked", B, L["Lock widget"], L["Locked widgets can't be dragged."], "checkbox")
    button(L["Widget position"], L["Reset widget position"], function() ns.Slash("widget reset") end,
        L["Move the widget back to the top of the screen."])

    -- Sounds
    header(L["Sounds"])
    local labels = { victory = L["Victory"], defeat = L["Defeat"], promote = L["Promotion"], demote = L["Demotion"] }
    for _, moment in ipairs({ "victory", "defeat", "promote", "demote" }) do
        local snd = setting(moment, s.sounds, Settings.VarType.Number, L["%s sound"]:format(labels[moment]),
            ns.DEFAULT_SOUNDS[moment])
        snd:SetValueChangedCallback(function(_, value) ns.PlaySoundKit(value) end)
        Settings.CreateDropdown(category, snd, function()
            local c = Settings.CreateControlTextContainer()
            for _, cand in ipairs(ns.SOUND_CANDIDATES) do c:Add(cand[1], cand[2]) end
            return c:GetData()
        end, L["Plays when you pick it, so you can listen."])
    end

    -- Community
    header(L["Community"])
    button(L["Discord"], L["Join Discord"], function() ns.ShowDiscord() end,
        L["Feedback, bug reports and ideas. Shows an invite link you can copy."])

    Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    else
        ns.Print(L["Options unavailable here — type /duelelo help for commands."])
    end
end

ns.Listen(function(event)
    if event ~= "READY" or category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local ok, err = pcall(build)
    if not ok then
        category = nil
        geterrorhandler()("DuelElo options panel: " .. tostring(err))
    end
end)
