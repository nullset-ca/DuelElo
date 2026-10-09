-- UI/Upload.lua: the Upload tab, upload codes and the "please upload" nudges
-- (SPEC §3.7). The code goes into the copy box (UI/Community.lua) because it
-- contains the character's secret key: never into chat.
local _, ns = ...
local L = ns.L

local SITE = "duelelo.com/upload"
local WARNING = L["Your code is hidden, so this is safe on stream. Press Ctrl+C to copy it, then paste it on %s (hidden there too). It contains your character's secret key: never paste it in chat."]:format(SITE)

local nudged = false  -- once per session

-- Raw DEFLATE via the client when it has C_EncodingUtil (flag Z), else nil (flag N).
local function compressor()
    local enc = C_EncodingUtil
    local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
    if not (enc and enc.CompressString and method) then return nil end
    return function(s)
        local ok, out = pcall(enc.CompressString, s, method)
        if ok and type(out) == "string" and not ns.IsSecret(out) then return out end
    end
end

-- Builds a code for the current character and remembers the export time.
function ns.MakeUploadCode(full)
    local me, char = ns.me, ns.char
    local now = time()
    local payload = ns.Export.Build(char, {
        name = me.name, realm = me.realm, class = me.class, level = ns.MyLevel(),
        region = ns.account.region, flavor = ns.FLAVOR, version = ns.VERSION, now = now, full = full,
    })
    local code = ns.Codec.UploadCode(payload, compressor())
    char.lastExport = now
    ns.Fire("UPLOAD_CHANGED")
    return code, payload
end

local function pendingText()
    local n = ns.Export.Pending(ns.char, ns.char.lastExport)
    local since = ns.char.lastExport and date("%b %d %H:%M", ns.char.lastExport) or nil
    return L["%s\n\n|cffffd100%d|r ranked  ·  |cffffd100%d|r casual  ·  |cffffd100%d|r witnessed  ·  |cffffd100%d|r reports"]:format(
        since and L["New since your last code (%s):"]:format(since) or L["Nothing uploaded yet from this character."],
        n.matches, n.casual, n.witnesses, n.reports)
end

-- Main window page (Main.lua adds it as the Upload tab).
function ns.BuildUploadPage(page)
    local intro = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", 12, -10)
    intro:SetPoint("RIGHT", -12, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText(L["Your ranked duels count on the official WoW Forever ladder once they're uploaded. One upload also verifies your opponents' side."])

    local counts = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    counts:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -16)
    counts:SetPoint("RIGHT", -12, 0)
    counts:SetJustifyH("LEFT")

    local full = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    full:SetSize(22, 22)
    full:SetPoint("TOPLEFT", counts, "BOTTOMLEFT", -4, -14)
    full.label = full:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    full.label:SetPoint("LEFT", full, "RIGHT", 2, 0)
    full.label:SetText(L["Full export (everything, not just what's new)"])

    local make = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    make:SetSize(200, 30)
    make:SetPoint("TOPLEFT", full, "BOTTOMLEFT", 4, -12)
    make:SetText(L["Create upload code"])
    make:SetScript("OnClick", function()
        local code = ns.MakeUploadCode(full:GetChecked())
        if ns.ShowCopyBox then ns.ShowCopyBox(L["DuelElo upload code"], WARNING, code, true) end
    end)

    local site = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    site:SetPoint("TOPLEFT", make, "BOTTOMLEFT", 0, -14)
    site:SetPoint("RIGHT", -12, 0)
    site:SetJustifyH("LEFT")
    site:SetText(L["Then paste it on %s (or /upload with the DuelElo Discord bot). Keep it private: it proves the duels are yours."]:format(SITE))

    page.Refresh = function() counts:SetText(pendingText()) end
end

-- Unverified ranked duels for the tab badge and the nudges.
function ns.UnverifiedCount()
    return ns.char and ns.Export.Unverified(ns.char) or 0
end

ns.Listen(function(event, entry)
    if event ~= "DUEL_RECORDED" or not (entry and entry.statement) then return end
    local unverified = ns.UnverifiedCount()
    if ns.Export.ShouldNudge(unverified, nudged, ns.account.settings.uploadNudges) then
        nudged = true
        ns.Print(L["%d ranked duels are waiting to be verified. Upload them: /duelelo upload"]:format(unverified))
    end
    ns.Fire("UPLOAD_CHANGED")
end)
