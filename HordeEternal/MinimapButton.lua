local addonName, addon = ...

local iconTexture = "Interface\\AddOns\\HordeEternal\\media\\HordeEternalEmblem.tga"

local function Position(button, angle)
    if not Minimap then
        return
    end
    local radiusX = Minimap:GetWidth() / 2 + 5
    local radiusY = Minimap:GetHeight() / 2 + 5
    local radians = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radiusX,
        math.sin(radians) * radiusY)
end

local function CursorAngle()
    if not Minimap or not UIParent or type(GetCursorPosition) ~= "function" then
        return nil
    end
    local centerX, centerY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if type(centerX) ~= "number" or type(centerY) ~= "number"
        or type(cursorX) ~= "number" or type(cursorY) ~= "number"
        or type(scale) ~= "number" or scale <= 0 then
        return nil
    end
    return math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
end

function addon.CreateMinimapButton()
    if addon.minimapButton or not Minimap then
        return
    end

    local button = CreateFrame("Button", "HordeEternalMinimapButton", Minimap)
    addon.minimapButton = button
    button:SetSize(33, 33)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("CENTER", button, "CENTER")
    border:SetTexture(136430)

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(22, 22)
    background:SetPoint("CENTER", button, "CENTER")
    background:SetTexture(136467)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(iconTexture)
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER", button)

    local settings = addon.db
    local angle = type(settings.minimapPos) == "number" and settings.minimapPos or 315
    Position(button, angle)
    Minimap:HookScript("OnSizeChanged", function()
        Position(button, angle)
    end)

    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            addon.ToggleCanvas()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local cursorAngle = CursorAngle()
            if cursorAngle then
                Position(button, cursorAngle)
            end
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        local cursorAngle = CursorAngle()
        if cursorAngle then
            angle = cursorAngle
            settings.minimapPos = angle
        end
        Position(button, angle)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Horde Eternal")
        GameTooltip:AddLine("Click to open or close")
        GameTooltip:AddLine("Drag to reposition")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end