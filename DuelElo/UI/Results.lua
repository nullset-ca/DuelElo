-- UI/Results.lua: post-duel results panel (LoL style).
-- Ranked: framed panel with VICTORY/DEFEAT, emblem, animated rating bar, promotion banner.
-- Unranked: just the headline, no frame, never blocks the mouse.
-- The panel can be dragged (position is saved) and resized with /duelelo size.
local _, ns = ...
local L = ns.L
local Elo = ns.Elo

local FONT = STANDARD_TEXT_FONT
local RANKED_DURATION = 9
local UNRANKED_DURATION = 3.5
local INTRO = 0.6        -- seconds before the rating starts counting
local COUNT = 1.4        -- seconds the rating takes to count up/down

-- Sound kit IDs to audition with /duelelo sound <n>. PlaySound ignores unknown IDs.
ns.SOUND_CANDIDATES = {
    { 888,   L["Level up"] },
    { 8455,  L["PvP victory A"] },
    { 8454,  L["PvP victory B"] },
    { 31578, L["Epic loot toast"] },
    { 12891, L["Achievement"] },
    { 847,   L["Quest failed"] },
    { 8959,  L["Raid warning"] },
    { 8960,  L["Ready check"] },
    { 12867, L["Alarm"] },
    { 878,   L["Quest complete"] },
    { 619,   L["Quest abandoned"] },
    { 3332,  L["Gong"] },
}

-- Which sound plays for each moment. Override per account in settings.sounds.
local DEFAULT_SOUNDS = { victory = 8455, defeat = 847, promote = 888, demote = 8959 }
ns.DEFAULT_SOUNDS = DEFAULT_SOUNDS
local function soundFor(moment)
    local custom = ns.account and ns.account.settings.sounds
    return (custom and custom[moment]) or DEFAULT_SOUNDS[moment]
end
local DEFAULT_POS = { "CENTER", 0, 120 }

local WIN_RGB = { 1.0, 0.82, 0.2 }
local LOSS_RGB = { 0.9, 0.2, 0.2 }

local f, timer

local function play(kit)
    if kit then pcall(PlaySound, kit, "Master") end
end
ns.PlaySoundKit = play

local function easeOut(p) return 1 - (1 - p) ^ 3 end

local function newAnim(region, setup, looping)
    local ag = region:CreateAnimationGroup()
    setup(ag)
    if looping then ag:SetLooping(looping) end
    return ag
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function build()
    f = CreateFrame("Frame", "DuelEloResults", UIParent, "BackdropTemplate")
    f:SetSize(440, 480)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:Hide()
    tinsert(UISpecialFrames, "DuelEloResults")

    local c = CreateFrame("Frame", nil, f)
    c:SetSize(440, 460)
    c:SetPoint("TOP", 0, -14)
    f.content = c

    f.headline = c:CreateFontString(nil, "OVERLAY")
    f.headline:SetFont(FONT, 64, "THICKOUTLINE")
    f.headline:SetPoint("TOP", 0, 0)
    f.headline:SetShadowOffset(3, -3)
    f.headlineIn = newAnim(f.headline, function(ag)
        local s = ag:CreateAnimation("Scale")
        s:SetScaleFrom(1.8, 1.8)
        s:SetScaleTo(1, 1)
        s:SetDuration(0.35)
        s:SetSmoothing("OUT")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetDuration(0.25)
    end)

    f.vs = c:CreateFontString(nil, "OVERLAY")
    f.vs:SetShadowOffset(1, -1)

    -- Dark band behind the unranked banner, fading out to both sides.
    f.band = {}
    for i, side in ipairs({ "RIGHT", "LEFT" }) do
        local t = c:CreateTexture(nil, "BACKGROUND")
        t:SetSize(300, 120)
        t:SetPoint("TOP" .. side, c, "TOP", 0, 10)
        t:SetColorTexture(1, 1, 1, 1)
        local clear, dark = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.8)
        if i == 1 then t:SetGradient("HORIZONTAL", clear, dark) else t:SetGradient("HORIZONTAL", dark, clear) end
        f.band[i] = t
    end
    f.vs:SetPoint("TOP", f.headline, "BOTTOM", 0, -8)

    -- Emblem with a slowly rotating glow behind it and a flash for rank changes.
    f.emblem = c:CreateTexture(nil, "ARTWORK")
    f.emblem:SetSize(176, 176)
    f.emblem:SetPoint("TOP", f.vs, "BOTTOM", 0, -6)

    f.glow = c:CreateTexture(nil, "BACKGROUND")
    f.glow:SetTexture("Interface\\Cooldown\\star4")
    f.glow:SetBlendMode("ADD")
    f.glow:SetSize(320, 320)
    f.glow:SetPoint("CENTER", f.emblem)
    f.glowSpin = newAnim(f.glow, function(ag)
        local r = ag:CreateAnimation("Rotation")
        r:SetDegrees(-360)
        r:SetDuration(40)
    end, "REPEAT")

    f.flash = c:CreateTexture(nil, "OVERLAY")
    f.flash:SetAllPoints(f.emblem)
    f.flash:SetBlendMode("ADD")
    f.flash:SetAlpha(0)
    f.flashAnim = newAnim(f.flash, function(ag)
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0)
        a:SetDuration(0.8)
        local s = ag:CreateAnimation("Scale")
        s:SetScaleFrom(1, 1)
        s:SetScaleTo(1.35, 1.35)
        s:SetDuration(0.8)
    end)

    f.rank = c:CreateFontString(nil, "OVERLAY")
    f.rank:SetFont(FONT, 26, "THICKOUTLINE")
    f.rank:SetPoint("TOP", f.emblem, "BOTTOM", 0, -2)

    -- Rating bar
    f.bar = CreateFrame("StatusBar", nil, c)
    f.bar:SetSize(320, 16)
    f.bar:SetPoint("TOP", f.rank, "BOTTOM", 0, -12)
    f.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.bar:SetMinMaxValues(0, 1)
    local bg = f.bar:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -2, 2)
    bg:SetPoint("BOTTOMRIGHT", 2, -2)
    bg:SetColorTexture(0, 0, 0, 0.8)

    f.rating = c:CreateFontString(nil, "OVERLAY")
    f.rating:SetFont(FONT, 18, "OUTLINE")
    f.rating:SetPoint("TOP", f.bar, "BOTTOM", 0, -8)

    f.delta = c:CreateFontString(nil, "OVERLAY")
    f.delta:SetFont(FONT, 22, "THICKOUTLINE")
    f.delta:SetPoint("LEFT", f.bar, "RIGHT", 12, 0)
    f.deltaIn = newAnim(f.delta, function(ag)
        local s = ag:CreateAnimation("Scale")
        s:SetScaleFrom(1.8, 1.8)
        s:SetScaleTo(1, 1)
        s:SetDuration(0.4)
        s:SetSmoothing("OUT")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetDuration(0.25)
    end)

    f.banner = c:CreateFontString(nil, "OVERLAY")
    f.banner:SetFont(FONT, 24, "THICKOUTLINE")
    f.banner:SetPoint("TOP", f.rating, "BOTTOM", 0, -14)
    f.bannerIn = newAnim(f.banner, function(ag)
        local s = ag:CreateAnimation("Scale")
        s:SetScaleFrom(2, 2)
        s:SetScaleTo(1, 1)
        s:SetDuration(0.3)
        s:SetSmoothing("OUT")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetDuration(0.2)
    end)

    f.hint = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("TOP", f.banner, "BOTTOM", 0, -18)
    f.hint:SetText(L["Click anywhere to continue"])

    -- Report this duel (SPEC §3.6); only for duels vs other DuelElo players.
    f.report = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.report:SetSize(80, 20)
    f.report:SetPoint("BOTTOMRIGHT", -14, 12)
    f.report:SetText(L["Report"])
    -- Nudge (SPEC §3.7): ranked results only count once someone uploads them.
    f.pending = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.pending:SetPoint("BOTTOMLEFT", 14, 16)
    f.pending:SetPoint("RIGHT", f.report, "LEFT", -8, 0)
    f.pending:SetJustifyH("LEFT")
    f.pending:SetText(L["Pending verification: upload (/duelelo upload) or let your opponent upload"])

    f.report:SetScript("OnClick", function(self)
        f:Hide()
        ns.ShowReport(self.entry)
    end)

    f.contentIn = newAnim(c, function(ag)
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetDuration(0.25)
    end)

    -- Click to dismiss; drag to move (and remember where).
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnMouseDown", function() f.dragged = false end)
    f:SetScript("OnDragStart", function() f.dragged = true f:StartMoving() end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        ns.account.settings.resultsPos = { point, x, y }
    end)
    f:SetScript("OnMouseUp", function() if not f.dragged then f:Hide() end end)
    -- Never stand between the player and a real fight.
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function() f:Hide() end)
    f:SetScript("OnHide", function()
        f:SetScript("OnUpdate", nil)
        f.glowSpin:Stop()
        if timer then timer:Cancel() timer = nil end
    end)
end

---------------------------------------------------------------------------
-- Showing
---------------------------------------------------------------------------

local function setEmblem(key, color)
    ns.SetEmblem(f.emblem, key)
    ns.SetEmblem(f.flash, key)
    f.glow:SetVertexColor(color[1], color[2], color[3], 0.55)
    if f:GetBackdrop() then f:SetBackdropBorderColor(color[1], color[2], color[3], 1) end
end

local function setRank(r, placementText)
    if placementText then
        setEmblem("UNRANKED", { 0.6, 0.6, 0.6 })
        f.rank:SetText(placementText)
        f.rank:SetTextColor(0.8, 0.8, 0.8)
        f.bar:SetStatusBarColor(0.6, 0.6, 0.6)
    else
        setEmblem(r.key, r.color)
        f.rank:SetText(r.label)
        f.rank:SetTextColor(r.color[1], r.color[2], r.color[3])
        f.bar:SetStatusBarColor(r.color[1], r.color[2], r.color[3])
    end
end

local function showBanner(text, rgb, sound)
    f.banner:SetText(text)
    f.banner:SetTextColor(rgb[1], rgb[2], rgb[3])
    f.banner:Show()
    f.bannerIn:Play()
    f.flashAnim:Play()
    play(sound)
end

local function startTimer(seconds)
    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(seconds, function() timer = nil f:Hide() end)
end

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function place()
    local s = ns.account.settings
    f:SetScale(s.resultsScale or 0.8)
    local pos = s.resultsPos or DEFAULT_POS
    f:ClearAllPoints()
    f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
end

local function showUnranked(e)
    f.report:Hide()
    f.pending:Hide()
    f:EnableMouse(false)
    f:ClearBackdrop()
    for _, region in ipairs({ f.emblem, f.glow, f.flash, f.rank, f.bar, f.rating, f.delta, f.banner, f.hint }) do
        region:Hide()
    end
    f.content:SetScale(0.85)
    f.vs:SetFont(FONT, 20, "OUTLINE")
    for _, t in ipairs(f.band) do t:Show() end
    local t = ns.char.totals
    f.vs:SetText(L["vs %s   ·   Record %d-%d"]:format(e.oppText, t.w, t.l))
    f:Show()
    f.contentIn:Play()
    f.headlineIn:Play()
    startTimer(UNRANKED_DURATION)
end

local function showRanked(e)
    f.report.entry = e
    f.report:SetShown(ns.CanReport ~= nil and ns.CanReport(e))
    f.pending:SetShown(e.statement ~= nil and ns.account.settings.uploadNudges)
    f:EnableMouse(true)
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0.03, 0.03, 0.05, 0.92)
    for _, region in ipairs({ f.emblem, f.glow, f.flash, f.rank, f.bar, f.rating, f.hint }) do
        region:Show()
    end
    f.banner:Hide()
    f.delta:Hide()
    f.content:SetScale(1)
    f.vs:SetFont(FONT, 16, "OUTLINE")
    for _, t in ipairs(f.band) do t:Hide() end
    f.vs:SetText(L["vs %s"]:format(e.oppText))

    local placing = e.placement and e.placement < Elo.PLACEMENTS
    local revealing = e.placement == Elo.PLACEMENTS
    local before, after = e.before, e.after
    local startRank = Elo.Rank(before)
    local function placementText(n) return L["Placements  %d / %d"]:format(n, Elo.PLACEMENTS) end

    -- initial state
    if placing or revealing then
        setRank(nil, placementText(e.placement - 1))
        f.bar:SetValue((e.placement - 1) / Elo.PLACEMENTS)
        f.rating:SetText("")
    else
        setRank(startRank)
        f.bar:SetValue(startRank.progress)
        f.rating:SetText(before)
    end
    local won = e.result == "W"
    f.delta:SetText((placing or revealing) and "" or ((e.delta >= 0 and "|cff20ff20+" or "|cffff4040") .. e.delta .. "|r"))

    f:Show()
    f.contentIn:Play()
    f.headlineIn:Play()
    f.glowSpin:Play()
    play(soundFor(won and "victory" or "defeat"))

    local elapsed, shown, finished = 0, startRank.label, false
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < INTRO then return end
        if not f.delta:IsShown() then f.delta:Show() f.deltaIn:Play() end
        local p = math.min(1, (elapsed - INTRO) / COUNT)
        local k = easeOut(p)

        if placing or revealing then
            f.bar:SetValue((e.placement - 1 + k) / Elo.PLACEMENTS)
        else
            local cur = math.floor(before + (after - before) * k + 0.5)
            local r = Elo.Rank(cur)
            if r.label ~= shown then
                shown = r.label
                setRank(r)
            end
            f.bar:SetValue(r.progress)
            f.rating:SetText(cur)
        end

        if p >= 1 and not finished then
            finished = true
            f:SetScript("OnUpdate", nil)
            if placing then
                f.rank:SetText(placementText(e.placement))
            elseif revealing then
                local r = Elo.Rank(after)
                setRank(r)
                f.bar:SetValue(r.progress)
                f.rating:SetText(after)
                showBanner(L["RANKED: %s"]:format(r.label:upper()), r.color, soundFor("promote"))
            else
                local cmp = Elo.CompareRank(startRank, Elo.Rank(after))
                if cmp > 0 then
                    showBanner(L["PROMOTED"], WIN_RGB, soundFor("promote"))
                elseif cmp < 0 then
                    showBanner(L["DEMOTED"], LOSS_RGB, soundFor("demote"))
                end
            end
        end
    end)
    startTimer(RANKED_DURATION)
end

-- e: a recorded duel entry (see Data.Record / Data.ApplyRanked)
function ns.ShowResult(e)
    if not f then build() end
    f:Hide()
    place()
    local won = e.result == "W"
    local rgb = won and WIN_RGB or LOSS_RGB
    f.headline:SetText(won and L["VICTORY"] or L["DEFEAT"])
    f.headline:SetTextColor(rgb[1], rgb[2], rgb[3])
    local name = ns.DisplayName(e.opp or "?")
    local c = e.class and C_ClassColor and C_ClassColor.GetClassColor(e.class)
    e = setmetatable({ oppText = c and c:WrapTextInColorCode(name) or name }, { __index = e })
    if e.ranked then showRanked(e) else showUnranked(e) end
end

ns.Listen(function(event, entry)
    if event == "DUEL_RECORDED" and ns.account.settings.resultsScreen then
        ns.ShowResult(entry)
    end
end)
