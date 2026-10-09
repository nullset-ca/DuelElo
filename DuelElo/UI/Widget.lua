-- UI/Widget.lua: the rank widget, a small stream-friendly HUD (SPEC §3.11).
-- Draws ns.WidgetModel's view model in one of three presets. Event-driven
-- only: it redraws on duel results, view/settings changes and ladder data.
local ADDON, ns = ...
local L = ns.L
local Model = ns.WidgetModel

local FONT = "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local UP = "|TInterface\\Buttons\\Arrow-Up-Up:12:12:0:-2|t"
local DOWN = "|TInterface\\Buttons\\Arrow-Down-Up:12:12:0:2|t"
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t"
local GREEN, RED, GREY = { 0.25, 0.9, 0.3 }, { 0.95, 0.3, 0.3 }, { 0.6, 0.6, 0.6 }
local MAX_BOXES, BOX = 10, 14
local FADED = 0.4          -- alpha factor while a duel is on (Fade during duels)
local PULSE = 0.6          -- seconds of the rating-change pulse

local SIZES = { full = { 280, 84 }, compact = { 264, 40 }, minimal = { 200, 22 } }

local f
local dueling, lastRating = false, nil

local function settings() return ns.account.settings.widget end

local function hex(rgb)
    return ("|cff%02x%02x%02x"):format(rgb[1] * 255, rgb[2] * 255, rgb[3] * 255)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function text(parent, size, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, flags or "OUTLINE")
    fs:SetShadowOffset(1, -1)
    return fs
end

local function newBox(parent)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetSize(BOX, BOX)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b.letter = text(b, 9)
    b.letter:SetPoint("CENTER", 0, 0)
    b.dot = b:CreateTexture(nil, "OVERLAY")
    b.dot:SetSize(3, 3)
    b.dot:SetPoint("BOTTOMRIGHT", -1, 1)
    b.dot:SetColorTexture(1, 1, 1, 0.9)
    return b
end

local function savePosition()
    local point, _, _, x, y = f:GetPoint()
    local w = settings()
    w.pos = { point, x, y }
    if not w.placed then
        -- locked after the first placement, so it can't be dragged by accident
        w.placed, w.locked = true, true
        ns.Print(L["Rank widget locked in place. (/duelelo widget unlock to move it)"])
    end
end

local function showMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ns.Slash("widget")  -- older clients: print the commands instead
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        local w = settings()
        root:CreateTitle(L["DuelElo rank widget"])
        root:CreateButton(w.locked and L["Unlock"] or L["Lock"], function()
            ns.Slash(w.locked and "widget unlock" or "widget lock")
        end)
        local preset = root:CreateButton(L["Preset"])
        for _, p in ipairs({ { "full", L["Full"] }, { "compact", L["Compact"] }, { "minimal", L["Minimal"] } }) do
            local key = p[1]
            preset:CreateRadio(p[2], function() return settings().preset == key end,
                function() ns.Slash("widget preset " .. key) end)
        end
        local trend = root:CreateButton(L["Trend display"])
        for _, t in ipairs({ { "number", L["Number"] }, { "sparkline", L["Sparkline"] }, { "both", L["Both"] }, { "none", L["None"] } }) do
            trend:CreateRadio(t[2], function() return settings().trend == t[1] end, function()
                settings().trend = t[1]
                ns.Fire("WIDGET_CHANGED")
            end)
        end
        root:CreateButton(L["Hide"], function() ns.Slash("widget hide") end)
        root:CreateButton(L["Options…"], function() if ns.OpenOptions then ns.OpenOptions() end end)
    end)
end

local function showTooltip(self)
    local m = self.model
    if not m then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("DuelElo")
    if m.placements then
        GameTooltip:AddLine(L["Placements %d / %d"]:format(m.placements.done, m.placements.total), 0.7, 0.7, 0.7)
    else
        local c = m.color or GREY
        GameTooltip:AddLine(("%s  ·  %d %s"):format(m.label, m.rating, m.official and L["(official)"] or L["(estimated)"]),
            c[1], c[2], c[3])
    end
    GameTooltip:AddLine(L["Ranked record %d-%d"]:format(m.record.w, m.record.l), 1, 1, 1)
    if m.peak and m.peak > 0 then GameTooltip:AddLine(L["Peak %d"]:format(m.peak), 1, 1, 1) end
    if m.rd then GameTooltip:AddLine(L["Rating confidence ±%d"]:format(m.rd + 0.5), 0.8, 0.8, 0.8) end
    local labels = { session = L["This session"], today = L["Today"], last10 = L["Last 10 ranked"] }
    GameTooltip:AddLine(L["%s: %s over %d games"]:format(labels[settings().period], Model.TrendText(m.trend.value),
        m.trend.games), 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Click: open DuelElo  ·  Right-click: menu"], 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function build()
    f = CreateFrame("Button", "DuelEloWidget", UIParent, "BackdropTemplate")
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({
        bgFile = WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.02, 0.03, 0.06, 0.82)

    f:SetScript("OnDragStart", function(self) if not settings().locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    f:SetScript("OnClick", function(self, button)
        if button == "RightButton" then showMenu(self) elseif ns.ToggleMain then ns.ToggleMain() end
    end)
    f:SetScript("OnEnter", showTooltip)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.emblem = f:CreateTexture(nil, "ARTWORK")
    f.label = text(f, 12)
    f.rating = text(f, 18, "THICKOUTLINE")
    f.tag = text(f, 9)
    f.trend = text(f, 12)
    f.pulse = f.trend:CreateAnimationGroup()
    local a = f.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(0.2)
    a:SetToAlpha(1)
    a:SetDuration(PULSE)

    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetStatusBarTexture(BAR)
    f.bar:SetMinMaxValues(0, 1)
    f.bar.bg = f.bar:CreateTexture(nil, "BACKGROUND")
    f.bar.bg:SetAllPoints()
    f.bar.bg:SetColorTexture(1, 1, 1, 0.12)
    f.next = text(f, 9, "")

    f.pips = {}
    for i = 1, ns.Elo.PLACEMENTS do
        local p = f:CreateTexture(nil, "ARTWORK")
        p:SetSize(8, 4)
        p:SetPoint("LEFT", f.bar, "LEFT", (i - 1) * 10, 0)
        f.pips[i] = p
    end

    f.boxes = {}
    for i = 1, MAX_BOXES do f.boxes[i] = newBox(f) end

    f.spark = CreateFrame("Frame", nil, f)
    f.spark:SetSize(70, 16)
    f.spark.lines = {}
    f.spark.dot = f.spark:CreateTexture(nil, "OVERLAY")
    f.spark.dot:SetSize(4, 4)
    f.spark.dot:SetColorTexture(1, 1, 1, 1)

    f.name = text(f, 8, "")
    f.name:SetTextColor(0.75, 0.75, 0.8)

    local events = CreateFrame("Frame")
    events:RegisterEvent("ADDON_LOADED")
    -- pet battles may not exist on every client: registering an unknown event errors
    pcall(events.RegisterEvent, events, "PET_BATTLE_OPENING_START")
    pcall(events.RegisterEvent, events, "PET_BATTLE_CLOSE")
    events:SetScript("OnEvent", function(_, event, name)
        if event == "ADDON_LOADED" then
            if name == "DuelElo_Ladder" then ns.RefreshWidget() end
        elseif event == "PET_BATTLE_OPENING_START" then
            f:Hide()
        else
            ns.RefreshWidget()
        end
    end)
end

---------------------------------------------------------------------------
-- Layout per preset
---------------------------------------------------------------------------

local function layout(w, m)
    local preset = w.preset
    local size = SIZES[preset]
    f:SetSize(size[1], size[2])
    for _, r in ipairs({ f.emblem, f.label, f.rating, f.tag, f.trend, f.bar, f.next, f.spark, f.name }) do
        r:ClearAllPoints()
    end
    local full, compact = preset == "full", preset == "compact"
    f.emblem:SetShown(not (preset == "minimal"))
    f.bar:SetShown(full and m.progress ~= nil)
    f.next:SetShown(full)
    f.name:SetShown(full and w.nameTag)
    for _, p in ipairs(f.pips) do p:SetShown(full and m.placements ~= nil) end

    if full then
        f.emblem:SetSize(56, 56)
        f.emblem:SetPoint("LEFT", 8, 2)
        f.label:SetPoint("TOPLEFT", f.emblem, "TOPRIGHT", 6, -2)
        f.rating:SetPoint("LEFT", f.label, "RIGHT", 6, 0)
        f.tag:SetPoint("BOTTOMLEFT", f.rating, "BOTTOMRIGHT", 3, 1)
        f.trend:SetPoint("TOPRIGHT", -10, -9)
        f.bar:SetSize(120, 4)
        f.bar:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -7)
        f.next:SetPoint("LEFT", f.bar, "RIGHT", 6, 0)
        f.spark:SetPoint("TOPRIGHT", -10, -42)
        f.name:SetPoint("BOTTOMRIGHT", -10, 6)
    elseif compact then
        f.emblem:SetSize(32, 32)
        f.emblem:SetPoint("LEFT", 5, 0)
        f.label:SetPoint("TOPLEFT", f.emblem, "TOPRIGHT", 4, -3)
        f.rating:SetPoint("BOTTOMLEFT", f.emblem, "BOTTOMRIGHT", 4, 2)
        f.tag:SetPoint("BOTTOMLEFT", f.rating, "BOTTOMRIGHT", 3, 1)
        f.trend:SetPoint("RIGHT", -8, 0)
        f.spark:SetPoint("RIGHT", f.trend, "LEFT", -6, 0)
    else
        f.label:SetPoint("LEFT", 8, 0)
        f.rating:SetPoint("LEFT", f.label, "RIGHT", 5, 0)
        f.tag:SetPoint("LEFT", f.rating, "RIGHT", 3, 0)
        f.trend:SetPoint("LEFT", f.tag, "RIGHT", 6, 0)
    end
    f.rating:SetFont(FONT, preset == "minimal" and 12 or (compact and 14 or 18), preset == "minimal" and "OUTLINE" or "THICKOUTLINE")
end

local function drawBoxes(w, m)
    local shown = w.preset ~= "minimal" and #m.recent or 0
    local anchorFull = w.preset == "full"
    for i, b in ipairs(f.boxes) do
        local r = m.recent[i]
        if i <= shown and r then
            b:ClearAllPoints()
            if anchorFull then
                b:SetPoint("BOTTOMLEFT", f.emblem, "BOTTOMRIGHT", 6 + (i - 1) * (BOX + 2), 2)
            else
                b:SetPoint("LEFT", f.label, "LEFT", 96 + (i - 1) * (BOX + 2), -7)
            end
            local c = r.result == "W" and GREEN or RED
            local newest = i == #m.recent
            b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
            b:SetBackdropColor(c[1], c[2], c[3], newest and 0.55 or (r.ranked and 0.15 or 0.05))
            b.letter:SetText(r.result)
            b.letter:SetTextColor(newest and 1 or c[1], newest and 1 or c[2], newest and 1 or c[3])
            b.dot:SetShown(r.fled)
            b:Show()
        else
            b:Hide()
        end
    end
end

local function drawSparkline(points, rising)
    local s = f.spark
    for _, l in ipairs(s.lines) do l:Hide() end
    s.dot:Hide()
    if #points < 2 then return end
    local wdt, hgt = s:GetWidth(), s:GetHeight()
    local c = rising and GREEN or RED
    local function at(i) return (i - 1) / (#points - 1) * wdt, points[i] * hgt end
    for i = 2, #points do
        local l = s.lines[i - 1]
        if not l then
            l = s:CreateLine(nil, "ARTWORK")
            l:SetThickness(1.5)
            s.lines[i - 1] = l
        end
        local x1, y1 = at(i - 1)
        local x2, y2 = at(i)
        l:SetStartPoint("BOTTOMLEFT", s, x1, y1)
        l:SetEndPoint("BOTTOMLEFT", s, x2, y2)
        l:SetColorTexture(c[1], c[2], c[3], 0.9)
        l:Show()
    end
    local x, y = at(#points)
    s.dot:ClearAllPoints()
    s.dot:SetPoint("CENTER", s, "BOTTOMLEFT", x, y)
    s.dot:Show()
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function applyAlpha()
    local w = settings()
    f:SetAlpha(w.opacity * ((w.fade and dueling) and FADED or 1))
end

function ns.RefreshWidget()
    if not ns.account then return end
    local w = settings()
    if not w.shown or (C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()) then
        if f then f:Hide() end
        return
    end
    if not f then build() end

    local official = Model.OfficialRating(DuelEloLadderData, ns.account.region, ns.me.full)
    local m = Model.Build(ns.ViewData(), w, {
        official = (not ns.demo) and official or nil,
        sessionStart = ns.demo and 0 or (ns.sessionStart and ns.sessionStart.t or 0),
        dayStart = time() - (tonumber(date("%H")) * 3600 + tonumber(date("%M")) * 60 + tonumber(date("%S"))),
        name = ns.me.full,
    })
    f.model = m

    layout(w, m)
    local color = m.color or GREY
    f:SetBackdropBorderColor(color[1], color[2], color[3], 1)
    ns.SetEmblem(f.emblem, m.tierKey)
    f.label:SetText(m.placements and L["Placements %d / %d"]:format(m.placements.done, m.placements.total)
        or m.label:upper())
    f.label:SetTextColor(color[1], color[2], color[3])
    f.rating:SetText(m.placements and "" or m.rating)
    f.tag:SetText(m.placements and "" or (m.official and CHECK or "|cff9d9d9d" .. L["est."] .. "|r"))

    if m.progress then
        f.bar:SetValue(m.progress.fraction)
        f.bar:SetStatusBarColor(color[1], color[2], color[3])
        f.next:SetText(m.progress.toNext and L["%d to %s"]:format(m.progress.toNext, m.progress.nextLabel) or L["Top tier"])
    elseif m.placements then
        for i, p in ipairs(f.pips) do
            local done = i <= m.placements.done
            p:SetColorTexture(done and 0.9 or 0.35, done and 0.8 or 0.35, done and 0.4 or 0.35, 1)
        end
        f.next:ClearAllPoints()
        f.next:SetPoint("LEFT", f.pips[#f.pips], "RIGHT", 6, 0)
        f.next:SetText("")
    end

    local v = m.trend.value
    local showNumber = w.trend == "number" or w.trend == "both"
    local arrow = v > 0 and UP or (v < 0 and DOWN or "")
    f.trend:SetText(showNumber and (hex(v >= 0 and GREEN or RED) .. arrow .. " " .. Model.TrendText(v) .. "|r") or "")
    local showSpark = (w.trend == "sparkline" or w.trend == "both") and w.preset ~= "minimal"
    f.spark:SetShown(showSpark)
    if showSpark then drawSparkline(m.trend.points, v >= 0) end

    drawBoxes(w, m)
    local name, realm = ns.Parse.SplitName(ns.me.full or "")
    f.name:SetText(((name or "") .. (realm and (" · " .. realm) or "")):upper())

    f:SetScale(w.scale)
    f:ClearAllPoints()
    local pos = w.pos
    if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("TOP", UIParent, "TOP", 0, -120) end
    applyAlpha()
    f:Show()

    if w.pulse and lastRating and lastRating ~= m.rating then f.pulse:Play() end
    lastRating = m.rating
end

ns.Listen(function(event, arg)
    if event == "READY" or event == "DUEL_RECORDED" or event == "VIEW_CHANGED" or event == "WIDGET_CHANGED"
        or event == "LADDER_LOADED" then
        if event == "DUEL_RECORDED" then dueling = false end
        ns.RefreshWidget()
    elseif event == "SESSION_CHANGED" then
        -- a pending or active duel; nil once it's over (or cancelled)
        dueling = arg ~= nil
        if f and f:IsShown() then applyAlpha() end
    end
end)
