-- UI/Community.lua: a small window with a selected, read-only text box, for
-- links (and later export codes) the player copies out of the game.
-- Built lazily on first use.
local _, ns = ...

local box

local function build()
    local f = CreateFrame("Frame", "DuelEloCopyFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(380, 160)
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
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    edit:SetScript("OnEnterPressed", function() f:Hide() end)
    f.edit = edit

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(84, 22)
    close:SetPoint("BOTTOM", 0, 14)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() f:Hide() end)

    box = f
end

function ns.ShowCopyBox(title, text, value)
    if not box then build() end
    box.title:SetText(title)
    box.text:SetText(text)
    box.value = value
    box.edit:SetText(value)
    box:Show()
    box.edit:SetFocus()
    box.edit:HighlightText()
end
