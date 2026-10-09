-- UI/Setup.lua: the setup guide, a short popup that walks new players through
-- ranked duels, the rank widget and uploading. Opens once per account after
-- login (again when SETUP_VERSION grows) and any time with /duelelo setup.
-- Every choice here is also in Settings > AddOns > DuelElo. Built lazily.
local _, ns = ...
local L = ns.L

local SETUP_VERSION = 1   -- bump when a new step is something everyone should see
local SHOW_DELAY = 6      -- seconds after login, so the game's own popups go first
local COMBAT_RETRY = 10   -- seconds; never pop up in the middle of a fight
local SITE = "duelelo.com/upload"

local f
local step = 1

local function settings() return ns.account.settings end

local function widgetChanged()
    ns.WidgetModel.Validate(settings().widget)
    ns.Fire("WIDGET_CHANGED")
end

-- A UICheckButtonTemplate used as a checkbox or radio button. Its checked
-- state is redrawn from the settings, never read back from the button.
local function check(parent, label, onClick)
    local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    b:SetSize(22, 22)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.label:SetPoint("LEFT", b, "RIGHT", 2, 0)
    b.label:SetText(label)
    b:SetScript("OnClick", function()
        onClick()
        f.Refresh()
    end)
    return b
end

-- Lays controls out in a column under the page text; returns them by key.
local function column(page, items)
    local out, prev = {}, nil
    for _, it in ipairs(items) do
        local b
        if it.note then
            b = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            b:SetPoint("RIGHT", page, "RIGHT")
            b:SetJustifyH("LEFT")
            b:SetText(it.note)
        elseif it.button then
            b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        else
            b = check(page, it.label, it.onClick)
        end
        if it.button then
            b:SetSize(150, 24)
            b:SetText(it.label)
            b:SetScript("OnClick", it.onClick)
        end
        if prev then
            b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", it.indent or 0, -(it.gap or 2))
        else
            b:SetPoint("TOPLEFT", page.text, "BOTTOMLEFT", it.indent or 0, -10)
        end
        out[it.key] = b
        prev = b
    end
    page.controls = out
    return out
end

local STEPS = {
    {
        title = L["Welcome to DuelElo"],
        text = L["DuelElo tracks every duel you fight: wins, losses, streaks and who you beat.\n\nWhen your opponent also has DuelElo, you can agree to a |cffffd100ranked|r duel. Ranked duels move your rating and count on the official WoW Forever ladder.\n\nThis quick setup takes under a minute."],
    },
    {
        title = L["How ranked works"],
        text = L["A duel is ranked only when both players have DuelElo and agree before it starts. Both of you also need:\n\n|cffffd100-|r the same level\n|cffffd100-|r at least 95% health and mana\n|cffffd100-|r to be out of combat\n|cffffd100-|r no world buffs or other banned buffs (Darkmoon, campfire, objectives)\n\nWhen a duel request comes in, DuelElo checks this for you: green |cff20ff20Ready|r, or what's missing. Anything else is a casual duel: it's still recorded, with no rating change. Dueling the same player again within 7 days counts less each time."],
    },
    {
        title = L["Your ranked settings"],
        text = L["When your opponent also has DuelElo:"],
        build = function(page)
            local s = settings
            local c = column(page, {
                { key = "ask", label = L["Ask me each time (recommended)"], onClick = function() s().rankedPref = "ask" end },
                { key = "always", label = L["Always play ranked"], onClick = function() s().rankedPref = "always" end },
                { key = "never", label = L["Never play ranked (casual only)"], onClick = function() s().rankedPref = "never" end },
                { key = "strict", gap = 14, label = L["Wait for cooldowns"],
                    onClick = function() s().strict = not s().strict end },
                { key = "strictNote", note = L["Off: cooldowns and trinkets are shown, but don't stop a ranked duel. On: ranked waits until both players' trinkets and 1-minute-plus cooldowns are ready."],
                    indent = 26, gap = 0 },
                { key = "share", indent = -26, gap = 8, label = L["Share my rating with DuelElo players on my realm"],
                    onClick = function() ns.SetChannelSharing(not s().shareChannel) end },
            })
            return function()
                for _, k in ipairs({ "ask", "always", "never" }) do c[k]:SetChecked(s().rankedPref == k) end
                c.strict:SetChecked(s().strict)
                c.share:SetChecked(s().shareChannel)
            end
        end,
    },
    {
        title = L["Rank widget"],
        text = L["An optional small panel with your rank, recent results and rating trend, handy for streams. Drag it where you want it: it locks itself after the first move."],
        build = function(page)
            local w = function() return settings().widget end
            local function preset(p) return function() w().preset = p; widgetChanged() end end
            local c = column(page, {
                { key = "shown", label = L["Show the rank widget"], onClick = function() w().shown = not w().shown; widgetChanged() end },
                { key = "full", indent = 20, label = L["Full"], onClick = preset("full") },
                { key = "compact", indent = 0, label = L["Compact"], onClick = preset("compact") },
                { key = "minimal", indent = 0, label = L["Minimal"], onClick = preset("minimal") },
            })
            return function()
                c.shown:SetChecked(w().shown)
                for _, k in ipairs({ "full", "compact", "minimal" }) do
                    c[k]:SetChecked(w().preset == k)
                    c[k]:SetEnabled(w().shown)
                    c[k].label:SetFontObject(w().shown and "GameFontHighlight" or "GameFontDisable")
                end
            end
        end,
    },
    {
        title = L["Get on the ladder"],
        text = L["Ranked duels count on the official ladder once they're uploaded. After a dueling session:\n\n1. Type |cffffd100/duelelo upload|r (or open the Upload tab).\n2. Click |cffffd100Create upload code|r and copy it.\n3. Paste it on |cffffd100%s|r or use /upload with the DuelElo Discord bot.\n\nOne upload also verifies your opponents' side. Keep codes private: they prove the duels are yours."]:format(SITE),
        build = function(page)
            column(page, {
                { key = "discord", button = true, label = L["Join Discord"], onClick = function() ns.ShowDiscord() end },
            })
        end,
    },
}

local function done()
    ns.account.setup = SETUP_VERSION
end

local function finish(skipped)
    done()
    f:Hide()
    ns.Print(skipped and L["Setup skipped. Run it any time with /duelelo setup."]
        or L["You're all set! /duelelo opens your record; /duelelo setup runs this guide again."])
end

local function build()
    f = CreateFrame("Frame", "DuelEloSetupFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(440, 390)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetScript("OnHide", function()  -- closing it (X or Escape) counts as skipping
        if ns.SetupPending() then finish(true) end
    end)
    tinsert(UISpecialFrames, "DuelEloSetupFrame")

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("CENTER", f.TitleBg or f, f.TitleBg and "CENTER" or "TOP", 0, f.TitleBg and 0 or -12)
    f.title:SetText(L["DuelElo setup"])

    f.pages = {}
    for i, s in ipairs(STEPS) do
        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", 18, -32)
        page:SetPoint("BOTTOMRIGHT", -18, 44)
        page.heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        page.heading:SetPoint("TOPLEFT")
        page.heading:SetText(s.title)
        page.text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        page.text:SetPoint("TOPLEFT", page.heading, "BOTTOMLEFT", 0, -8)
        page.text:SetPoint("RIGHT")
        page.text:SetJustifyH("LEFT")
        page.text:SetSpacing(2)
        page.text:SetText(s.text)
        page.Refresh = s.build and s.build(page) or function() end
        f.pages[i] = page
    end

    f.back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.back:SetSize(100, 24)
    f.back:SetPoint("BOTTOMLEFT", 12, 12)
    f.back:SetScript("OnClick", function()
        if step == 1 then finish(true) else ns.SetupStep(step - 1) end
    end)

    f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.next:SetSize(100, 24)
    f.next:SetPoint("BOTTOMRIGHT", -12, 12)
    f.next:SetScript("OnClick", function()
        if step == #STEPS then finish(false) else ns.SetupStep(step + 1) end
    end)

    f.progress = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.progress:SetPoint("BOTTOM", 0, 18)

    f.Refresh = function()
        for i, page in ipairs(f.pages) do
            page:SetShown(i == step)
            if i == step then page.Refresh() end
        end
        f.back:SetText(step == 1 and L["Skip setup"] or L["Back"])
        f.next:SetText(step == #STEPS and L["Finish"] or L["Next"])
        f.progress:SetText(L["Step %d of %d"]:format(step, #STEPS))
    end
end

function ns.SetupStep(n)
    step = math.max(1, math.min(#STEPS, n))
    if f then f.Refresh() end
end

function ns.ShowSetup()
    if not f then build() end
    step = 1
    f.Refresh()
    f:Show()
end

-- True until this account has finished, skipped or closed the current guide.
function ns.SetupPending()
    return (tonumber(ns.account.setup) or 0) < SETUP_VERSION
end

local function showWhenCalm()
    if not ns.SetupPending() or (f and f:IsShown()) then return end
    if InCombatLockdown and InCombatLockdown() then
        C_Timer.After(COMBAT_RETRY, showWhenCalm)
        return
    end
    ns.ShowSetup()
end

ns.Listen(function(event)
    if event == "READY" and ns.SetupPending() then C_Timer.After(SHOW_DELAY, showWhenCalm) end
end)
