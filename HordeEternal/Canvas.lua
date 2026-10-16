local _, addon = ...

local frame
local emblemPath = "Interface\\AddOns\\HordeEternal\\media\\HordeEternalEmblem.tga"

local function CreateInset(parent)
    local ok, inset = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
    if ok and inset then
        return inset
    end
    return CreateFrame("Frame", nil, parent)
end

local function CreateCanvas()
    if frame then
        return frame
    end

    local ok, window = pcall(CreateFrame, "Frame", "HordeEternalCanvas", UIParent, "PortraitFrameTemplate")
    if ok and window and window.CloseButton then
        frame = window
    else
        if ok and window then
            window:Hide()
        end
        frame = CreateFrame("Frame", "HordeEternalCanvasBasic", UIParent, "BasicFrameTemplateWithInset")
    end

    frame:SetSize(338, 424)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)


    if frame.SetTitle then
        frame:SetTitle("Horde Eternal")
    elseif frame.TitleText then
        frame.TitleText:SetText("Horde Eternal")
    elseif frame.TitleContainer and frame.TitleContainer.TitleText then
        frame.TitleContainer.TitleText:SetText("Horde Eternal")
    end

    local portrait = frame.portrait or frame.Portrait
        or (frame.PortraitContainer and frame.PortraitContainer.portrait)
    if portrait then
        portrait:SetTexture(emblemPath)
        if not portrait.hordeEternalMasked then
            portrait:SetTexCoord(0, 1, 0, 1)
            if portrait.SetMask then
                portrait.hordeEternalMasked = pcall(portrait.SetMask, portrait,
                    "Interface\\CharacterFrame\\TempPortraitAlphaMask")
            end
        end
    elseif frame.SetPortraitToAsset then
        pcall(frame.SetPortraitToAsset, frame, emblemPath)
    else
        local emblem = frame:CreateTexture(nil, "ARTWORK")
        emblem:SetTexture(emblemPath)
        emblem:SetSize(38, 48)
        emblem:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -18)
    end

    local headerX = 62
    local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", frame, "TOPLEFT", headerX, -28)
    heading:SetText("A New Zealand guild")
    heading:SetJustifyH("LEFT")
    heading:SetWordWrap(false)

    local subheading = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subheading:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -1)
    subheading:SetText("PvP Horde  /  7:30pm NZ time")
    subheading:SetJustifyH("LEFT")
    subheading:SetWordWrap(false)

    local listBox = CreateInset(frame)
    listBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -56)
    listBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 118)

    local body = listBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("CENTER", listBox, "CENTER", 0, 0)
    body:SetText("Good groups. Clear plans.")

    local detail = CreateInset(frame)
    detail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 36)
    detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 36)
    detail:SetHeight(78)

    local detailTitle = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailTitle:SetPoint("TOPLEFT", detail, "TOPLEFT", 8, -6)
    detailTitle:SetText("AT REASONABLE HOURS")
    detailTitle:SetJustifyH("LEFT")

    local detailText = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailText:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -3)
    detailText:SetPoint("RIGHT", detail, "RIGHT", -8, 0)
    detailText:SetText("Organized groups around New Zealand evenings.")
    detailText:SetJustifyH("LEFT")
    detailText:SetJustifyV("TOP")

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