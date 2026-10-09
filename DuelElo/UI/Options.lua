-- UI/Options.lua: DuelElo's page in Settings > AddOns. A canvas page drawn
-- with our own controls: pages built from the Settings API's controls are
-- run by Blizzard's settings search, and on WoW Forever that taints it
-- ("DuelElo has been blocked from an action only available to the Blizzard
-- UI" while typing in the search box). Everything here is also reachable by
-- slash command, so a Settings API change can't lock players out.
local _, ns = ...
local L = ns.L

local category, panel

local WIDTH = 560
local LABEL_X, CONTROL_X = 16, 300

local function percent(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
local function settings() return ns.account.settings end
local function widget() return ns.account.settings.widget end

local function widgetChanged()
    ns.WidgetModel.Validate(widget())
    ns.Fire("WIDGET_CHANGED")
end

local function tooltip(owner, title, text)
    if not text then return end
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Lays controls out top to bottom on `content`; each control registers a
-- refresh function that redraws it from the settings.
local function layout(content)
    local y, refreshers = -8, {}
    local api = { controls = {} }

    local function refreshAll() for _, fn in ipairs(refreshers) do fn() end end
    api.Refresh = refreshAll

    function api.header(text)
        y = y - 10
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        fs:SetPoint("TOPLEFT", LABEL_X, y)
        fs:SetText(text)
        y = y - 28
    end

    function api.note(text)
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", LABEL_X, y)
        fs:SetWidth(WIDTH - 2 * LABEL_X)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        y = y - 30
    end

    function api.check(key, label, tip, get, set)
        local b = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        b:SetSize(24, 24)
        b:SetPoint("TOPLEFT", LABEL_X - 4, y)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.label:SetPoint("LEFT", b, "RIGHT", 4, 0)
        b.label:SetText(label)
        b:SetScript("OnClick", function()
            set(not get())
            refreshAll()
        end)
        tooltip(b, label, tip)
        refreshers[#refreshers + 1] = function() b:SetChecked(get() and true or false) end
        api.controls[key] = b
        y = y - 28
    end

    local function rowLabel(label)
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", LABEL_X + 4, y - 5)
        fs:SetText(label)
        return fs
    end

    -- A button showing the current choice; left-click for the next, right-click the previous.
    function api.cycle(key, label, tip, options, get, set)
        rowLabel(label)
        local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        b:SetSize(200, 24)
        b:SetPoint("TOPLEFT", CONTROL_X, y)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local function index()
            for i, o in ipairs(options) do if o[1] == get() then return i end end
            return 1
        end
        b:SetScript("OnClick", function(_, button)
            local i = index() + (button == "RightButton" and -1 or 1)
            if i > #options then i = 1 elseif i < 1 then i = #options end
            set(options[i][1])
            refreshAll()
        end)
        tooltip(b, label, tip and (tip .. "\n" .. L["Click for the next choice, right-click for the previous."]))
        refreshers[#refreshers + 1] = function() b:SetText(options[index()][2]) end
        api.controls[key] = b
        y = y - 30
    end

    -- "-  80%  +" for sizes and opacity.
    function api.stepper(key, label, tip, min, max, step, get, set)
        rowLabel(label)
        local minus = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        minus:SetSize(28, 24)
        minus:SetPoint("TOPLEFT", CONTROL_X, y)
        minus:SetText("-")
        local value = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        value:SetPoint("LEFT", minus, "RIGHT", 8, 0)
        value:SetWidth(56)
        local plus = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        plus:SetSize(28, 24)
        plus:SetPoint("LEFT", value, "RIGHT", 8, 0)
        plus:SetText("+")
        local function bump(d)
            local v = math.floor((get() + d) * 100 + 0.5) / 100  -- whole percents, no float drift
            set(math.max(min, math.min(max, v)))
            refreshAll()
        end
        minus:SetScript("OnClick", function() bump(-step) end)
        plus:SetScript("OnClick", function() bump(step) end)
        tooltip(minus, label, tip)
        tooltip(plus, label, tip)
        refreshers[#refreshers + 1] = function() value:SetText(percent(get())) end
        api.controls[key] = { minus = minus, plus = plus }
        y = y - 30
    end

    function api.button(key, label, text, tip, onClick)
        rowLabel(label)
        local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        b:SetSize(200, 24)
        b:SetPoint("TOPLEFT", CONTROL_X, y)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        tooltip(b, label, tip)
        api.controls[key] = b
        y = y - 30
    end

    function api.Height() return -y + 16 end
    return api
end

local function build()
    panel = CreateFrame("Frame", "DuelEloOptionsPanel")
    panel.name = "DuelElo"

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH, 100)
    scroll:SetScrollChild(content)

    local ui = layout(content)
    local s, w = settings, widget

    ui.header(L["DuelElo — ranked dueling for WoW Forever"])
    ui.button("setup", L["Setup guide"], L["Run setup again"], L["Walk through the first-time setup again."],
        function() if ns.ShowSetup then ns.ShowSetup() end end)

    ui.header(L["Ranked duels"])
    ui.cycle("rankedPref", L["Ranked duels"],
        L["When your opponent also has DuelElo: agree to ranked automatically, get asked, or always play casual."],
        { { "ask", L["Ask each time"] }, { "always", L["Always ranked"] }, { "never", L["Never ranked"] } },
        function() return s().rankedPref end, function(v) s().rankedPref = v end)
    ui.check("strict", L["Wait for cooldowns"],
        L["Off: cooldowns and trinkets are shown, but don't stop a ranked duel. On: ranked waits until both players' trinkets and 1-minute-plus cooldowns are ready."],
        function() return s().strict end, function(v) s().strict = v end)
    ui.check("uploadNudges", L["Upload reminders"],
        L["Remind me (once per session) when ranked duels are waiting to be uploaded and verified."],
        function() return s().uploadNudges end, function(v) s().uploadNudges = v end)
    ui.check("shareChannel", L["Share rating realm-wide"],
        L["Share your rating with other DuelElo players on your realm and see theirs on the leaderboard."],
        function() return s().shareChannel end, function(v) ns.SetChannelSharing(v) end)

    ui.header(L["Results screen"])
    ui.check("resultsScreen", L["Show results screen"], L["Show VICTORY / DEFEAT with your rank after each duel."],
        function() return s().resultsScreen end, function(v) s().resultsScreen = v end)
    ui.stepper("resultsScale", L["Results screen size"], L["How big the results screen is."], 0.5, 1.5, 0.05,
        function() return s().resultsScale end, function(v) s().resultsScale = v end)
    ui.button("preview", L["Preview"], L["Preview"], L["Show a sample promotion."],
        function() ns.Dev.ShowTest("promo") end)
    ui.button("resetpos", L["Position"], L["Reset position"],
        L["Move the results screen back to the middle of the screen. (Drag it to move it.)"],
        function() ns.Slash("resetpos") end)
    ui.check("chatSummary", L["Chat summary"], L["Also print a one-line summary of each duel in chat."],
        function() return s().chatSummary end, function(v) s().chatSummary = v end)

    ui.header(L["Rank widget"])
    local function wset(key) return function(v) w()[key] = v; widgetChanged() end end
    local function wget(key) return function() return w()[key] end end
    ui.check("shown", L["Show rank widget"], L["A small panel with your rank, recent results and trend."],
        wget("shown"), wset("shown"))
    ui.cycle("preset", L["Widget style"], L["Full, Compact (one row) or Minimal (text only)."],
        { { "full", L["Full"] }, { "compact", L["Compact"] }, { "minimal", L["Minimal"] } }, wget("preset"), wset("preset"))
    ui.cycle("trend", L["Trend display"], L["Show the rating change as a number, a sparkline, both or neither."],
        { { "number", L["Number"] }, { "sparkline", L["Sparkline"] }, { "both", L["Both"] }, { "none", L["None"] } },
        wget("trend"), wset("trend"))
    ui.cycle("period", L["Trend period"], L["Which games the trend covers."],
        { { "session", L["This session"] }, { "today", L["Today"] }, { "last10", L["Last 10 ranked games"] } },
        wget("period"), wset("period"))
    ui.cycle("recent", L["Recent results"], L["How many result boxes to show."],
        { { 3, "3" }, { 5, "5" }, { 10, "10" } }, wget("recent"), wset("recent"))
    ui.check("casual", L["Include casual results"], L["Also show casual duels in the result boxes."],
        wget("casual"), wset("casual"))
    ui.check("nameTag", L["Show name tag"], L["NAME · REALM under the widget (Full style)."], wget("nameTag"), wset("nameTag"))
    ui.check("fade", L["Fade during duels"], L["Dim the widget while a duel is on."], wget("fade"), wset("fade"))
    ui.check("pulse", L["Pulse on rating change"], L["Briefly pulse the trend when your rating changes."],
        wget("pulse"), wset("pulse"))
    ui.stepper("scale", L["Widget size"], L["How big the widget is."],
        ns.WidgetModel.SCALE_MIN, ns.WidgetModel.SCALE_MAX, 0.05, wget("scale"), wset("scale"))
    ui.stepper("opacity", L["Widget opacity"], L["How see-through the widget is."],
        ns.WidgetModel.OPACITY_MIN, ns.WidgetModel.OPACITY_MAX, 0.05, wget("opacity"), wset("opacity"))
    ui.check("locked", L["Lock widget"], L["Locked widgets can't be dragged."], wget("locked"), wset("locked"))
    ui.button("widgetpos", L["Widget position"], L["Reset widget position"],
        L["Move the widget back to the top of the screen."], function() ns.Slash("widget reset") end)

    ui.header(L["Sounds"])
    local labels = { victory = L["Victory"], defeat = L["Defeat"], promote = L["Promotion"], demote = L["Demotion"] }
    for _, moment in ipairs({ "victory", "defeat", "promote", "demote" }) do
        ui.cycle("sound_" .. moment, L["%s sound"]:format(labels[moment]), L["Plays when you pick it, so you can listen."],
            ns.SOUND_CANDIDATES,
            function() return s().sounds[moment] or ns.DEFAULT_SOUNDS[moment] end,
            function(v)
                s().sounds[moment] = v
                ns.PlaySoundKit(v)
            end)
    end

    ui.header(L["Community"])
    ui.button("discord", L["Discord"], L["Join Discord"],
        L["Feedback, bug reports and ideas. Shows an invite link you can copy."], function() ns.ShowDiscord() end)

    content:SetHeight(ui.Height())
    panel.controls, panel.Refresh = ui.controls, ui.Refresh
    panel:SetScript("OnShow", ui.Refresh)
    ui.Refresh()

    category = Settings.RegisterCanvasLayoutCategory(panel, "DuelElo")
    Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        if panel then panel.Refresh() end
        Settings.OpenToCategory(category:GetID())
    else
        ns.Print(L["Options unavailable here — type /duelelo help for commands."])
    end
end

ns.Listen(function(event)
    if event ~= "READY" or category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local ok, err = pcall(build)
    if not ok then
        category = nil
        geterrorhandler()("DuelElo options panel: " .. tostring(err))
    end
end)
