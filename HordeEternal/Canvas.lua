local _, addon = ...

local frame

local function AddText(parent, layer, template, text, point, relativeTo, relativePoint, x, y)
    local fontString = parent:CreateFontString(nil, layer, template)
    fontString:SetText(text)
    fontString:SetPoint(point, relativeTo, relativePoint, x, y)
    return fontString
end

local function CreateCanvas()
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", "HordeEternalCanvas", UIParent)
    frame:SetSize(760, 520)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0.08, 0.075, 0.07, 0.98)

    local function AddBorder(pointA, relativeA, pointB, relativeB, width, height)
        local border = frame:CreateTexture(nil, "BORDER")
        border:SetPoint(pointA, frame, relativeA)
        border:SetPoint(pointB, frame, relativeB)
        if width then
            border:SetWidth(width)
        end
        if height then
            border:SetHeight(height)
        end
        border:SetColorTexture(0.63, 0.43, 0.18, 1)
    end

    AddBorder("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, 2)
    AddBorder("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, 2)
    AddBorder("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", 2, nil)
    AddBorder("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", 2, nil)

    local header = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    header:SetHeight(112)
    header:SetColorTexture(0.19, 0.065, 0.055, 1)

    local emblem = frame:CreateTexture(nil, "ARTWORK")
    emblem:SetTexture("Interface\\AddOns\\HordeEternal\\media\\HordeEternalEmblem.tga")
    emblem:SetSize(64, 82)
    emblem:SetPoint("LEFT", header, "LEFT", 20, 0)

    AddText(frame, "OVERLAY", "GameFontNormalLarge", "THE HORDE ETERNAL", "LEFT", emblem, "RIGHT", 16, 13)
        :SetTextColor(0.96, 0.86, 0.64)
    AddText(frame, "OVERLAY", "GameFontNormal", "A NEW ZEALAND GUILD", "LEFT", emblem, "RIGHT", 16, -12)
        :SetTextColor(0.84, 0.70, 0.48)
    AddText(frame, "OVERLAY", "GameFontHighlight", "At reasonable hours.", "LEFT", emblem, "RIGHT", 16, -34)
        :SetTextColor(0.90, 0.87, 0.79)

    local closeButton = CreateFrame("Button", nil, frame)
    closeButton:SetSize(28, 28)
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -12)
    local closeLabel = closeButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeLabel:SetPoint("CENTER", closeButton, "CENTER", 0, 0)
    closeLabel:SetText("X")
    closeLabel:SetTextColor(0.90, 0.83, 0.69)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local content = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -130)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 58)
    content:SetColorTexture(0.18, 0.16, 0.13, 1)

    local contentTop = frame:CreateTexture(nil, "ARTWORK")
    contentTop:SetPoint("TOPLEFT", content, "TOPLEFT")
    contentTop:SetPoint("TOPRIGHT", content, "TOPRIGHT")
    contentTop:SetHeight(1)
    contentTop:SetColorTexture(0.44, 0.34, 0.21, 0.85)

    local contentBottom = frame:CreateTexture(nil, "ARTWORK")
    contentBottom:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT")
    contentBottom:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")
    contentBottom:SetHeight(1)
    contentBottom:SetColorTexture(0.44, 0.34, 0.21, 0.85)

    local contentLeft = frame:CreateTexture(nil, "ARTWORK")
    contentLeft:SetPoint("TOPLEFT", content, "TOPLEFT")
    contentLeft:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT")
    contentLeft:SetWidth(1)
    contentLeft:SetColorTexture(0.44, 0.34, 0.21, 0.85)

    local contentRight = frame:CreateTexture(nil, "ARTWORK")
    contentRight:SetPoint("TOPRIGHT", content, "TOPRIGHT")
    contentRight:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")
    contentRight:SetWidth(1)
    contentRight:SetColorTexture(0.44, 0.34, 0.21, 0.85)

    local message = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    message:SetPoint("CENTER", content, "CENTER", 0, 0)
    message:SetText("Good groups. Clear plans.")
    message:SetTextColor(0.89, 0.82, 0.68)

    local footer = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 3, 3)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    footer:SetHeight(42)
    footer:SetColorTexture(0.13, 0.12, 0.10, 1)

    AddText(frame, "OVERLAY", "GameFontHighlightSmall", "PVP RULESET  /  HORDE", "LEFT", footer, "LEFT", 18, 0)
        :SetTextColor(0.78, 0.69, 0.53)
    AddText(frame, "OVERLAY", "GameFontHighlightSmall", "TYPICAL START  /  7:30PM NZ", "RIGHT", footer, "RIGHT", -18, 0)
        :SetTextColor(0.78, 0.69, 0.53)

    frame:Hide()
    return frame
end

function addon.ToggleCanvas()
    local canvas = CreateCanvas()
    if canvas:IsShown() then
        canvas:Hide()
    else
        canvas:Show()
    end
end