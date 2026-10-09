-- UI/Community.lua: a small window with a selected, read-only text box, for
-- links and upload codes the player copies out of the game. Secret values
-- (upload codes) stay hidden unless the player asks, so it's safe on stream.
-- Built lazily on first use.
local _, ns = ...
local L = ns.L

local box

local function build()
    local f = CreateFrame("Frame", "DuelEloCopyFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(380, 176)
    f:SetPoint("CENTER", 0, 160)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "DuelEloCopyFrame")  -- close with Escape

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("CENTER", f.TitleBg or f, f.TitleBg and "CENTER" or "TOP", 0, f.TitleBg and 0 or -12)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", 16, -34)
    f.text:SetPoint("TOPRIGHT", -16, -34)
    f.text:SetJustifyH("CENTER")

    local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    edit:SetSize(320, 22)
    edit:SetPoint("BOTTOM", 0, 44)
    edit:SetAutoFocus(false)
    -- no length limit: upload codes are long (InputBoxTemplate may cap the text)
    if edit.SetMaxLetters then edit:SetMaxLetters(0) end
    if edit.SetMaxBytes then edit:SetMaxBytes(0) end
    -- Read-only: typing puts the value back, so a stray key can't break the link.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(f.value)
            self:HighlightText()
        end
    end)
    edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    -- Ctrl+C (Cmd+C on a Mac) feedback; not every client has OnKeyDown on edit boxes.
    pcall(edit.SetScript, edit, "OnKeyDown", function(_, key)
        local mod = (IsControlKeyDown and IsControlKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown())
        if key == "C" and mod then
            f.copied = true
            f.mask:SetText(L["Copied!"])
        end
    end)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    edit:SetScript("OnEnterPressed", function() f:Hide() end)
    f.edit = edit

    -- Stands in for the text while a secret value is hidden. The edit box is
    -- only made invisible (alpha 0): it keeps focus and the selection, so
    -- Ctrl+C still copies the real value.
    f.mask = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.mask:SetPoint("CENTER", edit, "CENTER")

    f.reveal = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.reveal:SetSize(100, 22)
    f.reveal:SetPoint("BOTTOMLEFT", 16, 14)
    f.reveal:SetScript("OnClick", function()
        f.revealed = not f.revealed
        f.Redraw()
        edit:SetFocus()
        edit:HighlightText()
    end)

    f.Redraw = function()
        local hidden = f.secret and not f.revealed
        edit:SetAlpha(hidden and 0 or 1)
        f.mask:SetShown(hidden)
        f.mask:SetText(f.copied and L["Copied!"] or L["Code hidden · Ctrl+C copies it"])
        f.reveal:SetShown(f.secret)
        f.reveal:SetText(f.revealed and L["Hide code"] or L["Show code"])
    end

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(84, 22)
    close:SetPoint("BOTTOM", 0, 14)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() f:Hide() end)

    box = f
end

-- secret: hide the value on screen (it still copies) until "Show code".
function ns.ShowCopyBox(title, text, value, secret)
    if not box then build() end
    box.secret, box.revealed, box.copied = secret and true or false, false, false
    box.Redraw()
    box.title:SetText(title)
    box.text:SetText(text)
    box.value = value
    box.edit:SetText(value)
    box:Show()
    box.edit:SetFocus()
    box.edit:HighlightText()
end
