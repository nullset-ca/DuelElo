-- UI/Prompt.lua: the "Ranked or casual?" prompt shown while a duel request is
-- pending and the opponent also has DuelElo. Hidden otherwise.
local _, ns = ...
local L = ns.L

local LINGER = 3          -- seconds the final decision stays visible after the lock
local GREEN, GREY, GOLD, RED = "|cff20ff20", "|cffaaaaaa", "|cffffd100", "|cffff4040"

local f, hideTimer

local function oppName(s)
    local name = ns.DisplayName(s.opp)
    local c = s.peer and s.peer.class and C_ClassColor and C_ClassColor.GetClassColor(s.peer.class)
    return c and c:WrapTextInColorCode(name) or name, name
end

-- Why ranked isn't happening, by R-message reason code (see Rules.REASONS).
local REASONS = {
    F = L["Ranked limit vs %s reached for now"],
    N = L["%s only plays casual duels"],
    D = L["%s chose casual"],
    L = L["Different levels — casual only"],
    A = L["Same account — casual only"],
    B = L["Ladder ban — casual only"],
    U = L["%s waits for cooldowns before ranked"],
}
-- Reasons that come from the rules rather than a choice: shown for our side too.
local RULE_REASONS = { F = true, L = true, A = true, B = true }

-- "Ready", or baseline problems in red and cooldown info in grey.
local function readyText(mask, counts, unknown)
    if not mask then return GREY .. "…|r" end
    local baseline, info = ns.Readiness.Problems(mask, counts, unknown)
    local parts = {}
    if #baseline > 0 then
        parts[1] = RED .. L["Not ready: %s"]:format(table.concat(baseline, ", ")) .. "|r"
    else
        parts[1] = GREEN .. L["Ready"] .. "|r"
    end
    if #info > 0 then parts[#parts + 1] = GREY .. L["%s recharging"]:format(table.concat(info, ", ")) .. "|r" end
    local unchecked = ns.Readiness.Unchecked(mask, unknown)
    if #unchecked > 0 then
        parts[#parts + 1] = GREY .. L["%s unchecked"]:format(table.concat(unchecked, ", ")) .. "|r"
    end
    return table.concat(parts, GREY .. "  ·  |r")
end

local function build()
    f = CreateFrame("Frame", "DuelEloPrompt", UIParent, "BackdropTemplate")
    f:SetSize(340, 126)
    f:SetPoint("TOP", 0, -215)  -- just below the duel request popup
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.03, 0.03, 0.05, 0.92)
    f:SetBackdropBorderColor(1, 0.82, 0, 1)
    f:EnableMouse(true)
    f:Hide()

    f.emblem = f:CreateTexture(nil, "ARTWORK")
    f.emblem:SetSize(40, 40)
    f.emblem:SetPoint("TOPLEFT", 10, -10)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f.emblem, "TOPRIGHT", 8, -2)
    f.title:SetPoint("RIGHT", -34, 0)
    f.title:SetJustifyH("LEFT")

    -- "?" with the ranked rules, so "Not ready: health" never needs guessing.
    f.help = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.help:SetSize(22, 20)
    f.help:SetPoint("TOPRIGHT", -8, -8)
    f.help:SetText("?")
    f.help:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Ranked rules"])
        GameTooltip:AddLine(L["Both players agree before the duel starts."], 1, 1, 1, true)
        GameTooltip:AddLine(L["Both need: the same level, at least 95% health and mana, out of combat, no banned buffs."], 1, 1, 1, true)
        GameTooltip:AddLine(L["Cooldowns and trinkets are shown for information. They only block ranked if a player turned on Wait for cooldowns."], 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(L["Otherwise it's a casual duel: recorded, no rating change."], 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(L["If the game hides health or mana from addons, they show as unchecked: check each other before you start."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    f.help:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)

    -- Per-side readiness (shown to both players, SPEC §3.2)
    f.readyMe = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.readyMe:SetPoint("TOPLEFT", f.emblem, "BOTTOMLEFT", 0, -6)
    f.readyMe:SetPoint("RIGHT", -10, 0)
    f.readyMe:SetJustifyH("LEFT")
    f.readyThem = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.readyThem:SetPoint("TOPLEFT", f.readyMe, "BOTTOMLEFT", 0, -2)
    f.readyThem:SetPoint("RIGHT", -10, 0)
    f.readyThem:SetJustifyH("LEFT")

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.status:SetPoint("BOTTOM", 0, 14)

    f.ranked = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.ranked:SetSize(110, 24)
    f.ranked:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 10)
    f.ranked:SetText(L["Ranked"])
    f.ranked:SetScript("OnClick", function() ns.engine:Consent(true) end)

    f.casual = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.casual:SetSize(110, 24)
    f.casual:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 10)
    f.casual:SetText(L["Casual"])
    f.casual:SetScript("OnClick", function() ns.engine:Consent(false) end)
end

local function setButtons(shown)
    f.ranked:SetShown(shown)
    f.casual:SetShown(shown)
    f.status:SetShown(not shown)
end

-- What to say about the opponent's side of the agreement.
local function theirSide(s, plain)
    if s.theirConsent == true then return GREEN .. L["%s wants ranked"]:format(plain) .. "|r" end
    if s.theirConsent == false then
        return GREY .. (REASONS[s.theirReason] or REASONS.D):format(plain) .. "|r"
    end
    return GREY .. L["Waiting for %s…"]:format(plain) .. "|r"
end

local function render(s)
    if hideTimer then hideTimer:Cancel() hideTimer = nil end
    if not s or not s.peer or s.status == "noaddon" then
        if f then f:Hide() end
        return
    end
    if not f then build() end

    local colored, plain = oppName(s)
    f.title:SetText(GOLD .. "DuelElo|r  " .. L["vs %s"]:format(colored))

    f.readyMe:SetText("")
    f.readyThem:SetText("")
    if s.status == "incompatible" or s.status == "outdated" then
        ns.SetEmblem(f.emblem, "UNRANKED")
        f.sub:SetText("")
        setButtons(false)
        f.status:SetText(GREY .. (s.status == "outdated"
            and L["%s needs to update DuelElo for ranked — casual duel"]
            or L["%s has a different DuelElo version — casual duel"]):format(plain) .. "|r")
        f:Show()
        hideTimer = C_Timer.NewTimer(LINGER * 2, function() f:Hide() end)
        return
    end
    if not s.ineligible then
        f.readyMe:SetText(L["You: %s"]:format(readyText(s.myReady, s.myCounts, s.myUnknown)))
        f.readyThem:SetText(L["%s: %s"]:format(plain, readyText(s.theirReady)))
    end

    local p = s.peer
    if p.games >= ns.Elo.PLACEMENTS then
        local r = ns.Elo.Rank(p.rating)
        ns.SetEmblem(f.emblem, r.key)
        f.sub:SetText(L["%s  ·  %d rating  ·  %d-%d"]:format(r.label, p.rating, p.w, p.l))
    else
        ns.SetEmblem(f.emblem, "UNRANKED")
        f.sub:SetText(L["In placements (%d / %d)"]:format(p.games, ns.Elo.PLACEMENTS))
    end

    if s.locked then
        setButtons(false)
        f.status:SetText(s.status == "ranked" and (GREEN .. L["Ranked duel — good luck!"] .. "|r")
            or (GREY .. L["Casual duel"] .. "|r"))
        hideTimer = C_Timer.NewTimer(LINGER, function() f:Hide() end)
    elseif s.countdown then
        setButtons(false)
        f.status:SetText(GREY .. L["Waiting for %s's decision…"]:format(plain) .. "|r")
    elseif s.myConsent == nil then
        setButtons(true)
        -- the dev preview renders fake sessions the engine doesn't know about
        local live = ns.engine and ns.engine.session == s
        f.ranked:SetEnabled((s.theirConsent ~= false or s.theirReason == "U") and (not live or ns.engine:CanConsent()))
    elseif s.myConsent == false then
        setButtons(false)
        local why = RULE_REASONS[s.myReason] and (REASONS[s.myReason]):format(plain) or L["You chose casual"]
        f.status:SetText(GREY .. why .. "|r")
    elseif s.theirConsent == true then
        setButtons(false)
        f.status:SetText(GREEN .. (s.role == "D" and L["Both agreed — accept the duel to lock in ranked"]
            or L["Both agreed — ranked once %s accepts"]:format(plain)) .. "|r")
    else
        setButtons(false)
        f.status:SetText(theirSide(s, plain))
    end
    f:Show()
end

ns.Listen(function(event, session)
    if event == "SESSION_CHANGED" then render(session) end
end)
