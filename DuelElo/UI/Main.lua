-- UI/Main.lua: main window with History, Leaderboard and Stats tabs.
-- Built lazily on first open so the addon costs nothing at login.
local _, ns = ...
local L = ns.L
local Data = ns.Data

local ROW_H = 20
local WIN_COLOR = "|cff20ff20"
local LOSS_COLOR = "|cffff4040"

local frame

local function classColored(text, classFile)
    local c = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
    return c and c:WrapTextInColorCode(text) or text
end

local function className(classFile)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile
end

local function pct(w, l)
    return ("%d%%"):format(math.floor(Data.WinRate(w, l) * 100 + 0.5))
end

---------------------------------------------------------------------------
-- History tab
---------------------------------------------------------------------------

local function initRow(row, e)
    if not row.when then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.when = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.when:SetPoint("LEFT", 6, 0)
        row.when:SetWidth(96)
        row.when:SetJustifyH("LEFT")
        row.result = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.result:SetPoint("LEFT", row.when, "RIGHT", 4, 0)
        row.result:SetWidth(18)
        row.opp = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.opp:SetPoint("LEFT", row.result, "RIGHT", 6, 0)
        row.opp:SetPoint("RIGHT", -138, 0)
        row.opp:SetJustifyH("LEFT")
        row.how = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.how:SetPoint("RIGHT", -8, 0)
        row.delta = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.delta:SetPoint("RIGHT", -46, 0)
        -- "!" reports a duel vs another DuelElo player (SPEC §3.6)
        row.report = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.report:SetSize(20, 16)
        row.report:SetPoint("RIGHT", -96, 0)
        row.report:SetText("!")
        row.report:SetScript("OnClick", function(self) ns.ShowReport(self.entry) end)
        row.report:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(L["Report this duel"])
            GameTooltip:AddLine(L["Throwing, outside help, banned buffs, exploits…"], 1, 1, 1)
            GameTooltip:Show()
        end)
        row.report:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- ✔ when the site confirmed this duel (F2; the data addon lists confirmed matches)
        row.verified = CreateFrame("Frame", nil, row)
        row.verified:SetSize(14, 14)
        row.verified:SetPoint("RIGHT", -120, 0)
        row.verified.icon = row.verified:CreateTexture(nil, "OVERLAY")
        row.verified.icon:SetAllPoints()
        row.verified.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        row.verified:EnableMouse(true)
        row.verified:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(L["Verified by the community"])
            GameTooltip:AddLine(L["Both players' signatures were checked on the site."], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row.verified:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    row.verified:SetShown(ns.Ladder.Verified(DuelEloLadderData, ns.account and ns.account.region, e.entry))
    row.report.entry = e.entry
    row.report:SetShown(ns.CanReport ~= nil and ns.CanReport(e.entry))
    row.bg:SetColorTexture(1, 1, 1, (e.index % 2 == 0) and 0.04 or 0)
    row.when:SetText(date("%b %d  %H:%M", e.entry.t or 0))
    local won = e.entry.result == "W"
    row.result:SetText(won and (WIN_COLOR .. "W|r") or (LOSS_COLOR .. "L|r"))
    row.opp:SetText(classColored(ns.DisplayName(e.entry.opp or "?"), e.entry.class))
    row.how:SetText(e.entry.how == "FLED" and "fled" or "")
    local d = e.entry.ranked and e.entry.delta
    row.delta:SetText(d and ((d >= 0 and WIN_COLOR .. "+" or LOSS_COLOR) .. d .. "|r") or "")
end

local function buildHistory(page)
    local box = CreateFrame("Frame", nil, page, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", 4, -4)
    box:SetPoint("BOTTOMRIGHT", -22, 4)
    local bar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Frame", initRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)

    local empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER")
    empty:SetText(L["No duels yet.\nChallenge someone!"])

    page.Refresh = function()
        local duels = ns.ViewData().duels
        local rows = {}
        for i = #duels, 1, -1 do
            rows[#rows + 1] = { entry = duels[i], index = #rows + 1 }
        end
        box:SetDataProvider(CreateDataProvider(rows))
        empty:SetShown(#rows == 0)
    end
end

---------------------------------------------------------------------------
-- Leaderboard tab
---------------------------------------------------------------------------

local LB_ROW_H = 26

local SOURCE_TEXT = {
    met = L["You've dueled them"],
    guild = L["Guildmate · self-reported"],
    channel = L["Realm channel · self-reported"],
}

local function timeAgo(t)
    local s = time() - (t or 0)
    if s < 3600 then return L["%d min ago"]:format(math.max(1, math.floor(s / 60))) end
    if s < 86400 then return L["%d h ago"]:format(math.floor(s / 3600)) end
    return L["%d days ago"]:format(math.floor(s / 86400))
end

local function showPlayerTooltip(row)
    local p = row.player
    if not p then return end
    local r = ns.Elo.Rank(p.rating)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(classColored(ns.DisplayName(p.name), p.class))
    GameTooltip:AddLine(L["%s  ·  %d rating"]:format(r.label, p.rating), r.color[1], r.color[2], r.color[3])
    if p.official then
        GameTooltip:AddLine(p.rank and L["Official rank #%d"]:format(p.rank) or L["Not ranked this season"], 1, 1, 1)
        for _, b in ipairs(p.badges or {}) do GameTooltip:AddLine(ns.Ladder.BadgeName(b), 1, 0.82, 0) end
        if p.banned then GameTooltip:AddLine(L["Banned from the ranked ladder"], 1, 0.25, 0.25) end
        GameTooltip:Show()
        return
    end
    GameTooltip:AddLine(L["Ranked %d-%d  (%s)"]:format(p.w, p.l, pct(p.w, p.l)), 1, 1, 1)
    if p.isMe then
        GameTooltip:AddLine(L["This is you"], 1, 0.82, 0)
    else
        GameTooltip:AddLine(SOURCE_TEXT[p.source] or SOURCE_TEXT.met, 0.6, 0.6, 0.6)
        if p.seen then GameTooltip:AddLine(L["Last seen %s"]:format(timeAgo(p.seen)), 0.6, 0.6, 0.6) end
    end
    GameTooltip:Show()
end

local function initLeaderRow(row, e)
    if not row.name then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.marker = ns.CreateMarker(row, 24)
        row.marker:SetPoint("LEFT", 4, 0)
        row.pos = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.pos:SetPoint("LEFT", 30, 0)
        row.pos:SetWidth(34)
        row.pos:SetJustifyH("RIGHT")
        row.tier = row:CreateTexture(nil, "ARTWORK")
        row.tier:SetSize(22, 22)
        row.tier:SetPoint("LEFT", row.pos, "RIGHT", 6, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", row.tier, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", -110, 0)
        row.name:SetJustifyH("LEFT")
        row.rating = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.rating:SetPoint("RIGHT", -62, 0)
        row.record = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.record:SetPoint("RIGHT", -6, 0)
        row:EnableMouse(true)
        row:SetScript("OnEnter", showPlayerTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local p = e.player
    row.player = p
    if p.isMe then
        row.bg:SetColorTexture(1, 0.82, 0, 0.14)
    else
        row.bg:SetColorTexture(1, 1, 1, (p.pos % 2 == 0) and 0.04 or 0)
    end
    row.marker:SetMarker(p.marker)
    row.pos:SetText(p.pos or "–")
    local r = ns.Elo.Rank(p.rating)
    ns.SetEmblem(row.tier, r.key)
    row.name:SetText(classColored(ns.DisplayName(p.name), p.class))
    -- Ratings we haven't seen first-hand (guild/channel) are self-reported.
    row.rating:SetText(p.verified and p.rating or ("|cff9d9d9d" .. p.rating .. "*|r"))
    if p.official then
        row.record:SetText(p.banned and (LOSS_COLOR .. L["banned"] .. "|r") or (#(p.badges or {}) > 0 and "|cffffd100★|r" or ""))
    else
        row.record:SetText(("%s%d|r-%s%d|r"):format(WIN_COLOR, p.w, LOSS_COLOR, p.l))
    end
end

-- The official ladder (DuelElo_Ladder data addon) as leaderboard rows.
local function officialRows()
    local me = ns.me.full
    local rows = {}
    for _, e in ipairs(ns.Ladder.Build(DuelEloLadderData, ns.account.region)) do
        local known = ns.account.players[e.name]
        rows[#rows + 1] = { player = {
            name = e.name, rating = e.rating, pos = e.rank, marker = e.marker, class = known and known.class,
            official = true, verified = true, isMe = e.name == me, rank = e.rank, badges = e.badges, banned = e.banned,
        } }
    end
    return rows
end

local function buildLeaderboard(page)
    -- Official (from the site) vs Nearby (what this client heard in game).
    page.mode = nil
    local function modeButton(label, mode, anchor)
        local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        b:SetSize(90, 20)
        if anchor then b:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 6, -2) end
        b:SetText(label)
        b:SetScript("OnClick", function()
            page.mode = mode
            page.Refresh()
        end)
        return b
    end
    page.officialButton = modeButton(L["Official"], "official")
    page.nearbyButton = modeButton(L["Nearby"], "nearby", page.officialButton)

    local box = CreateFrame("Frame", nil, page, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", 4, -26)
    box:SetPoint("BOTTOMRIGHT", -22, 24)
    local bar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(LB_ROW_H)
    view:SetElementInitializer("Frame", initLeaderRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)

    local footer = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", 8, 6)
    footer:SetPoint("BOTTOMRIGHT", -8, 6)
    footer:SetJustifyH("LEFT")

    local empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER")
    empty:SetText(L["No ranked players yet.\nPlayers appear here after their 10 placement games."])

    page.Refresh = function()
        local hasOfficial = not ns.demo and ns.Ladder.Region(DuelEloLadderData, ns.account.region) ~= nil
        local mode = page.mode or (hasOfficial and "official" or "nearby")
        page.officialButton:SetEnabled(hasOfficial and mode ~= "official")
        page.nearbyButton:SetEnabled(mode ~= "nearby")
        if mode == "official" and hasOfficial then
            local rows = officialRows()
            box:SetDataProvider(CreateDataProvider(rows))
            empty:SetShown(#rows == 0)
            local data = DuelEloLadderData[ns.account.region]
            footer:SetText(L["Official WoW Forever ladder  ·  updated %s"]:format(date("%b %d", data.generated or 0)))
            return
        end
        local list, myPos = ns.Leaderboard.Build(ns.ViewPlayers(), ns.MyLeaderboardEntry(), time())
        local unverified = 0
        for _, p in ipairs(list) do if not p.verified then unverified = unverified + 1 end end
        local rows = {}
        for i, p in ipairs(list) do rows[i] = { player = p } end
        box:SetDataProvider(CreateDataProvider(rows))
        empty:SetShown(#rows == 0)
        footer:SetText(L["%d ranked players%s%s"]:format(#list,
            myPos and L["  ·  You are #%d"]:format(myPos) or "",
            unverified > 0 and "  ·  |cff9d9d9d" .. L["* self-reported, not dueled by you"] .. "|r" or ""))
    end
end

---------------------------------------------------------------------------
-- Stats tab
---------------------------------------------------------------------------

-- A titled two-column list: names on the left, values on the right.
local function makeColumn(page, title, x, width, y)
    local head = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", x, y or -10)
    head:SetText(title)
    local names = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    names:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
    names:SetJustifyH("LEFT")
    names:SetSpacing(5)
    local values = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    values:SetPoint("TOPRIGHT", names, "TOPLEFT", width, 0)
    values:SetJustifyH("RIGHT")
    values:SetSpacing(5)
    return function(rows)
        local n, v = {}, {}
        for i, r in ipairs(rows) do n[i], v[i] = r[1], r[2] end
        names:SetText(#n > 0 and table.concat(n, "\n") or "|cff808080" .. L["None yet"] .. "|r")
        values:SetText(table.concat(v, "\n"))
    end
end

local function sortedBuckets(map, limit)
    local list = {}
    for key, b in pairs(map) do list[#list + 1] = { key = key, b = b } end
    table.sort(list, function(a, b)
        local ga, gb = a.b.w + a.b.l, b.b.w + b.b.l
        if ga ~= gb then return ga > gb end
        return a.key < b.key
    end)
    if limit then for i = #list, limit + 1, -1 do list[i] = nil end end
    return list
end

local function wl(b)
    return ("%s%d|r-%s%d|r  %s"):format(WIN_COLOR, b.w, LOSS_COLOR, b.l, pct(b.w, b.l))
end

-- Ranked summary and fight facts, from whatever data is on view.
local function rankedSummary(c)
    local rows = {}
    if c.rankedGames >= ns.Elo.PLACEMENTS then
        local r = ns.Elo.Rank(c.rating)
        local col = ("|cff%02x%02x%02x"):format(r.color[1] * 255, r.color[2] * 255, r.color[3] * 255)
        -- "Estimated" until the official ladder (DuelElo_Ladder data addon) says otherwise
        rows[#rows + 1] = { L["Estimated rank"], ("%s%s|r  ·  %d"):format(col, r.label, c.rating) }
        rows[#rows + 1] = { L["Peak"], c.peak > 0 and tostring(c.peak) or "-" }
    else
        rows[#rows + 1] = { L["Rank"], L["Placements %d / %d"]:format(c.rankedGames, ns.Elo.PLACEMENTS) }
    end
    rows[#rows + 1] = { L["Ranked record"], wl({ w = c.rankedW or 0, l = c.rankedL or 0 }) }
    if c.legacy then
        rows[#rows + 1] = { L["Test-era rating"], L["%d  (%d-%d, archived)"]:format(c.legacy.rating, c.legacy.w or 0, c.legacy.l or 0) }
    end

    -- Average fight length and favourite dueling spot (recorded since v0.3).
    local secs, n, zones = 0, 0, {}
    for _, e in ipairs(c.duels) do
        if e.secs then secs, n = secs + e.secs, n + 1 end
        if e.zone then zones[e.zone] = (zones[e.zone] or 0) + 1 end
    end
    if n > 0 then rows[#rows + 1] = { L["Average duel"], ("%ds"):format(math.floor(secs / n + 0.5)) } end
    local bestZone, bestCount = nil, 0
    for z, count in pairs(zones) do
        if count > bestCount then bestZone, bestCount = z, count end
    end
    local info = bestZone and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(bestZone)
    if info and info.name then rows[#rows + 1] = { L["Favourite spot"], info.name } end
    return rows
end

local function buildStats(page)
    local setClasses = makeColumn(page, L["By class"], 12, 170)
    local setOpps = makeColumn(page, L["Most dueled"], 196, 170)
    local setRanked = makeColumn(page, L["Ranked"], 12, 354, -248)
    page.Refresh = function()
        setRanked(rankedSummary(ns.ViewData()))
        local rows = {}
        for _, it in ipairs(sortedBuckets(ns.ViewData().byClass)) do
            rows[#rows + 1] = { classColored(className(it.key), it.key), wl(it.b) }
        end
        setClasses(rows)
        rows = {}
        for _, it in ipairs(sortedBuckets(ns.ViewData().byOpp, 13)) do
            rows[#rows + 1] = { classColored(ns.DisplayName(it.key), it.b.class), wl(it.b) }
        end
        setOpps(rows)
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function refresh()
    if not frame or not frame:IsShown() then return end
    local c = ns.ViewData()
    local title = "DuelElo  |cff808080v" .. ns.VERSION .. "|r"
    frame.title:SetText(ns.demo and (title .. "  |cffff8000" .. L["(demo data)"] .. "|r") or title)
    frame.record:SetText(("%s%d|r  -  %s%d|r"):format(WIN_COLOR, c.totals.w, LOSS_COLOR, c.totals.l))
    -- The official rating from duelelo.com wins over the local estimate.
    local official = not ns.demo and ns.OfficialEntry()
    if official then
        local r = ns.Elo.Rank(official.rating)
        ns.SetEmblem(frame.emblem, r.key)
        frame.rankName:SetText(r.label)
        frame.rankName:SetTextColor(r.color[1], r.color[2], r.color[3])
        frame.rankSub:SetText(L["Official %d%s"]:format(official.rating,
            official.rank and ("  ·  #%d"):format(official.rank) or ""))
        frame.marker:SetMarker(ns.Leaderboard.Marker(official.rank))
    elseif c.rankedGames >= ns.Elo.PLACEMENTS then
        local r = ns.Elo.Rank(c.rating)
        ns.SetEmblem(frame.emblem, r.key)
        frame.rankName:SetText(r.label)
        frame.rankName:SetTextColor(r.color[1], r.color[2], r.color[3])
        local _, myPos = ns.Leaderboard.Build(ns.ViewPlayers(), ns.MyLeaderboardEntry(), time())
        frame.rankSub:SetText(myPos and L["Estimated %d  ·  #%d"]:format(c.rating, myPos) or L["Estimated %d"]:format(c.rating))
        frame.marker:SetMarker(ns.Leaderboard.Marker(myPos))
    else
        ns.SetEmblem(frame.emblem, "UNRANKED")
        frame.rankName:SetText(L["Unranked"])
        frame.rankName:SetTextColor(0.7, 0.7, 0.7)
        frame.rankSub:SetText(L["Placements %d / %d"]:format(c.rankedGames, ns.Elo.PLACEMENTS))
        frame.marker:SetMarker(nil)
    end
    local streak = ""
    if c.streak > 1 then
        streak = L["  ·  %sWin streak %d|r"]:format(WIN_COLOR, c.streak)
    elseif c.streak < -1 then
        streak = L["  ·  %sLoss streak %d|r"]:format(LOSS_COLOR, -c.streak)
    end
    frame.summary:SetText(L["%s win rate  ·  Best streak %d%s"]:format(
        pct(c.totals.w, c.totals.l), c.bestStreak, streak))
    frame.pages[frame.selectedTab].Refresh()
end

local function selectTab(id)
    frame.selectedTab = id
    PanelTemplates_SetTab(frame, id)
    for i, page in ipairs(frame.pages) do page:SetShown(i == id) end
    refresh()
end

local function build()
    local f = CreateFrame("Frame", "DuelEloMainFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(440, 508)
    f:SetPoint("CENTER")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetScript("OnShow", refresh)
    tinsert(UISpecialFrames, "DuelEloMainFrame")  -- close with Escape

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("CENTER", f.TitleBg or f, f.TitleBg and "CENTER" or "TOP", 0, f.TitleBg and 0 or -12)

    -- Header: rank emblem on the left, record on the right.
    f.emblem = f:CreateTexture(nil, "ARTWORK")
    f.emblem:SetSize(60, 60)
    f.emblem:SetPoint("TOPLEFT", 12, -26)
    f.rankName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.rankName:SetPoint("TOPLEFT", f.emblem, "TOPRIGHT", 4, -14)
    f.rankSub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.rankSub:SetPoint("TOPLEFT", f.rankName, "BOTTOMLEFT", 0, -4)
    f.marker = ns.CreateMarker(f, 26)
    f.marker:SetPoint("LEFT", f.rankName, "RIGHT", 4, 2)

    f.record = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.record:SetPoint("TOPRIGHT", -20, -36)
    f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.summary:SetPoint("TOPRIGHT", f.record, "BOTTOMRIGHT", 0, -6)

    f.pages = {}
    for i, builder in ipairs({ buildHistory, buildLeaderboard, buildStats, ns.BuildUploadPage }) do
        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", 10, -90)
        page:SetPoint("BOTTOMRIGHT", -8, 36)  -- footer below for Discord / Options
        builder(page)
        f.pages[i] = page
    end

    f.Tabs = {}
    for i, label in ipairs({ L["History"], L["Leaderboard"], L["Stats"], L["Upload"] }) do
        local tab = CreateFrame("Button", "DuelEloMainFrameTab" .. i, f, "PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(label)
        if i == 1 then
            tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 8, 2)
        else
            tab:SetPoint("LEFT", f.Tabs[i - 1], "RIGHT", 4, 0)
        end
        tab:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            selectTab(self:GetID())
        end)
        f.Tabs[i] = tab
    end
    PanelTemplates_SetNumTabs(f, #f.Tabs)

    local options = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    options:SetSize(72, 22)
    -- Inside the frame: the tabs hang below it and need its full width.
    options:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
    options:SetText(L["Options"])
    options:SetScript("OnClick", function()
        f:Hide()
        if ns.OpenOptions then ns.OpenOptions() end
    end)

    local discord = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    discord:SetSize(72, 22)
    discord:SetPoint("RIGHT", options, "LEFT", -4, 0)
    discord:SetText(L["Discord"])
    discord:SetScript("OnClick", function() ns.ShowDiscord() end)
    discord:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Join the DuelElo Discord"])
        GameTooltip:AddLine(L["Feedback, bug reports and ideas"], 1, 1, 1)
        GameTooltip:Show()
    end)
    discord:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local setup = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    setup:SetSize(72, 22)
    setup:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
    setup:SetText(L["Setup"])
    setup:SetScript("OnClick", function() if ns.ShowSetup then ns.ShowSetup() end end)

    f:Hide()
    frame = f
    selectTab(1)
end

function ns.ToggleMain()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end

function ns.ShowMain()
    if not frame then build() end
    frame:Show()
end

local UPLOAD_TAB = 4

function ns.ShowUploadTab()
    ns.ShowMain()
    selectTab(UPLOAD_TAB)
end

-- "Upload (N)" while ranked duels wait for verification (SPEC §3.7 badge).
local function updateUploadBadge()
    local tab = frame and frame.Tabs[UPLOAD_TAB]
    if not tab then return end
    local n = ns.account.settings.uploadNudges and ns.UnverifiedCount() or 0
    tab:SetText(n >= ns.Export.NUDGE_AT and L["Upload (%d)"]:format(n) or L["Upload"])
    PanelTemplates_TabResize(tab, 0)
end

ns.Listen(function(event)
    if event == "DUEL_RECORDED" or event == "VIEW_CHANGED" or event == "PLAYERS_CHANGED" or event == "LADDER_LOADED"
        or event == "REPORTS_CHANGED" then
        refresh()
    end
    if event == "UPLOAD_CHANGED" then
        updateUploadBadge()
        if frame and frame.selectedTab == UPLOAD_TAB then refresh() end
    end
end)
