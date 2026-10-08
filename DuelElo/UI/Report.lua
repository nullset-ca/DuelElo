-- UI/Report.lua: "Report this duel" dialog (SPEC §3.6). The report is kept in
-- DuelEloCharDB.reports and sent with the next upload; moderators decide.
-- Built lazily on first use.
local _, ns = ...
local L = ns.L

local REASONS = {
    { "THROWN", L["Thrown / win-trading"] },
    { "HELP", L["Outside help"] },
    { "BANNED", L["Banned buff or consumable"] },
    { "EXPLOIT", L["Exploit"] },
    { "OTHER", L["Other"] },
}

local ERRORS = {
    duplicate = L["You already reported this duel."],
    limit = L["You've sent 20 reports today. Try again tomorrow."],
    note = L["The note is too long (140 characters at most)."],
    reason = L["Pick a reason first."],
}

local f, current, choice

local function pick(code)
    choice = code
    for _, b in ipairs(f.reasons) do b:SetChecked(b.code == code) end
    f.send:SetEnabled(code ~= nil)
end

local function build()
    f = CreateFrame("Frame", "DuelEloReportFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(340, 268)
    f:SetPoint("CENTER", 0, 80)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    tinsert(UISpecialFrames, "DuelEloReportFrame")  -- close with Escape

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("CENTER", f.TitleBg or f, f.TitleBg and "CENTER" or "TOP", 0, f.TitleBg and 0 or -12)
    f.title:SetText(L["Report a duel"])

    f.who = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.who:SetPoint("TOPLEFT", 16, -34)

    f.reasons = {}
    for i, r in ipairs(REASONS) do
        local b = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        b:SetSize(22, 22)
        b:SetPoint("TOPLEFT", 14, -52 - (i - 1) * 24)
        b.code = r[1]
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.label:SetPoint("LEFT", b, "RIGHT", 2, 0)
        b.label:SetText(r[2])
        b:SetScript("OnClick", function() pick(r[1]) end)  -- behaves like radio buttons
        f.reasons[i] = b
    end

    f.noteLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.noteLabel:SetPoint("TOPLEFT", 18, -180)
    f.noteLabel:SetText(L["Note (optional, 140 characters)"])
    f.note = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.note:SetSize(300, 22)
    f.note:SetPoint("TOPLEFT", 22, -196)
    f.note:SetAutoFocus(false)
    f.note:SetMaxLetters(ns.Data.REPORT_NOTE_MAX)
    f.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    f.send = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.send:SetSize(110, 24)
    f.send:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 12)
    f.send:SetText(L["Send report"])
    f.send:SetScript("OnClick", function()
        local ok, why = ns.Data.AddReport(ns.char, {
            target = current.opp, matchId = current.match, reason = choice, note = f.note:GetText(),
        }, time())
        if ok then
            ns.Print(L["Report saved. It's sent to the moderators with your next upload."])
            f:Hide()
            ns.Fire("REPORTS_CHANGED")
        else
            ns.Print(ERRORS[why] or L["Couldn't save the report."])
        end
    end)

    f.cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.cancel:SetSize(110, 24)
    f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 12)
    f.cancel:SetText(L["Cancel"])
    f.cancel:SetScript("OnClick", function() f:Hide() end)
end

-- Duels against other DuelElo players carry a match id; only those can be reported.
function ns.CanReport(entry)
    return entry ~= nil and entry.match ~= nil and entry.opp ~= nil and not ns.demo
        and not ns.Data.Reported(ns.char, entry.match)
end

function ns.ShowReport(entry)
    if not ns.CanReport(entry) then
        if entry and entry.match and ns.Data.Reported(ns.char, entry.match) then ns.Print(ERRORS.duplicate) end
        return
    end
    if not f then build() end
    current = entry
    f.who:SetText(L["vs %s  ·  %s"]:format(ns.DisplayName(entry.opp), date("%b %d %H:%M", entry.t or time())))
    f.note:SetText("")
    pick(nil)
    f:Show()
end
