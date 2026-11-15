local _, addon = ...

local frame
local emblemPath = "Interface\\AddOns\\HordeEternal\\media\\HordeEternalEmblem.tga"

local function RefreshAdminStatus()
    if not frame then return end
    local role = addon.GuildState and addon.GuildState.AdminStatus and addon.GuildState.AdminStatus()
        or "Admin status unavailable"
    frame.applicationRole = role
    local title = "Horde Eternal - " .. role
    if frame.SetTitle then frame:SetTitle(title)
    elseif frame.TitleText then frame.TitleText:SetText(title)
    elseif frame.TitleContainer and frame.TitleContainer.TitleText then frame.TitleContainer.TitleText:SetText(title) end
end

local function FormatAge(timestamp)
    timestamp = tonumber(timestamp)
    if not timestamp or timestamp <= 0 then
        return "scan time unknown"
    end
    local age = math.max(0, time() - timestamp)
    if age < 3600 then
        return math.max(1, math.floor(age / 60)) .. "m ago"
    end
    if age < 86400 then
        return math.floor(age / 3600) .. "h ago"
    end
    return math.floor(age / 86400) .. "d ago"
end

local function CreateInset(parent)
    local ok, inset = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
    if ok and inset then
        return inset
    end
    return CreateFrame("Frame", nil, parent)
end

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function TextTooltip(owner, title, text)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
end

local function ArrowButton(parent, direction, title)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(26, 26)
    button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-Up")
    button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-Down")
    button:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-Disabled")
    button:SetScript("OnEnter", function(self) TextTooltip(self, title) end)
    button:SetScript("OnLeave", HideTooltip)
    return button
end

local function RecipeTooltip(owner)
    if not GameTooltip or not owner.entry then return end
    local display = addon.Compat.RecipeDisplay(owner.entry)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if not addon.Compat.Call(GameTooltip.SetHyperlink, GameTooltip, display.tooltipLink) then
        GameTooltip:SetText(display.name)
        GameTooltip:AddLine("Item details unavailable.", 1, 1, 1, true)
    end
    GameTooltip:Show()
end

function addon.HideProfessionCorrection()
    local window = addon.professionCorrection
    if window then window.selected = nil; window:StopMovingOrSizing(); window:Hide() end
    HideTooltip()
end

function addon.ShowProfessionCorrection(manual)
    if not addon.GuildState or not addon.GuildState.IsAllowed() then addon.HideProfessionCorrection(); return end
    local profile = addon.Catalog.Initialize().localProfile
    if not manual and (not profile or not profile.professionConflict) then return end
    local window = addon.professionCorrection
    if not window then
        local ok, candidate = pcall(CreateFrame, "Frame", "HordeEternalProfessionCorrection", UIParent, "BasicFrameTemplateWithInset")
        window = ok and candidate or CreateFrame("Frame", "HordeEternalProfessionCorrectionBasic", UIParent)
        addon.professionCorrection = window
        window:SetSize(480, 390)
        window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        window:SetFrameStrata("DIALOG")
        window:SetToplevel(true)
        window:SetClampedToScreen(true)
        window:SetMovable(true)
        window:EnableMouse(true)
        window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", window.StartMoving)
        window:SetScript("OnDragStop", window.StopMovingOrSizing)
        local background = window:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(window)
        background:SetColorTexture(0.04, 0.04, 0.04, 0.98)
        local title = window.TitleText or window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if not window.TitleText then title:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -12) end
        title:SetText("Profession correction")
        local heading = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        heading:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -40)
        heading:SetPoint("TOPRIGHT", window, "TOPRIGHT", -18, -40)
        heading:SetJustifyH("LEFT")
        heading:SetWordWrap(true)
        window.heading = heading
        local status = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 18, 61)
        status:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -18, 61)
        status:SetJustifyH("LEFT")
        status:SetWordWrap(true)
        window.status = status
        window.rows = {}
        for index = 1, 8 do
            local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
            button:SetSize(440, 26)
            button:SetPoint("TOPLEFT", window, "TOPLEFT", 20, -76 - (index - 1) * 28)
            button:SetScript("OnClick", function()
                window.selected = button.profession and button.profession.id
                window.Refresh()
            end)
            window.rows[index] = button
        end
        local modes = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        modes:SetSize(164, 24)
        modes:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 18, 18)
        modes:SetScript("OnClick", function()
            window.mode = window.mode == "restore" and "remove" or "restore"
            window.selected, window.expected = nil, nil
            window.Refresh()
        end)
        window.modes = modes
        local confirm = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        confirm:SetSize(110, 24)
        confirm:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -18, 18)
        confirm:SetText("Confirm")
        confirm:SetScript("OnEnter", function(self)
            TextTooltip(self, "Confirm cached profession correction", "This changes your cached learned recipes, not your in-game professions.")
        end)
        confirm:SetScript("OnLeave", HideTooltip)
        confirm:SetScript("OnClick", function()
            local action = window.mode == "restore" and addon.Catalog.ConfirmProfessionRelearned or addon.Catalog.ConfirmProfessionUnlearned
            local succeeded, reason = action(window.selected, window.expected)
            local current = addon.Catalog.Initialize().localProfile
            if succeeded and not current.professionConflict then addon.HideProfessionCorrection()
            else window.Refresh(); status:SetText(reason or "Confirmation unavailable.") end
        end)
        window.confirm = confirm
        local later = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        later:SetSize(70, 24)
        later:SetPoint("RIGHT", confirm, "LEFT", -8, 0)
        later:SetText("Later")
        later:SetScript("OnClick", addon.HideProfessionCorrection)
        window.later = later
        local close = window.CloseButton or CreateFrame("Button", nil, window, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -2, -2)
        close:SetScript("OnClick", addon.HideProfessionCorrection)
        window.Refresh = function()
            local current = addon.Catalog.Initialize().localProfile
            if window.expected ~= current then window.expected = current; window.selected = nil end
            local choices = window.mode == "restore" and addon.Catalog.WithdrawnPrimaryProfessions()
                or addon.Catalog.PrimaryProfessions(current)
            heading:SetText(window.mode == "restore" and "Which profession did you relearn?" or "Which primary profession did you unlearn?")
            modes:SetText(window.mode == "restore" and "Recorded professions" or "Previously removed")
            status:SetText(#choices == 0 and "No matching professions." or "")
            for index, row in ipairs(window.rows) do
                row.profession = choices[index]
                if row.profession then
                    row:SetText(row.profession.name)
                    if row.profession.id == window.selected then row:LockHighlight() else row:UnlockHighlight() end
                    row:Show()
                else row:Hide() end
            end
            confirm:SetEnabled(window.selected ~= nil and (window.mode == "restore" or (current and current.professionConflict)) == true)
            local width, height = addon.Compat.Value(UIParent.GetWidth, UIParent), addon.Compat.Value(UIParent.GetHeight, UIParent)
            if type(width) == "number" and width > 0 and type(height) == "number" and height > 0 then
                window:SetScale(math.min(1, width / 500, height / 410))
            end
        end
        if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = window:GetName() end
        window:SetScript("OnHide", function() window.selected = nil; HideTooltip() end)
        window:Hide()
    end
    if not manual then window.mode = "remove" end
    window.Refresh()
    window:Show()
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

    frame:SetSize(720, 600)
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

    local function FitWindow()
        local width = addon.Compat.Value(UIParent.GetWidth, UIParent)
        local height = addon.Compat.Value(UIParent.GetHeight, UIParent)
        if type(width) == "number" and width > 0 and type(height) == "number" and height > 0 then
            frame:SetScale(math.min(1, width / 740, height / 660))
        end
    end
    FitWindow()


    frame.RefreshAdminStatus = RefreshAdminStatus
    RefreshAdminStatus()

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
    local headerTotal = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headerTotal:SetPoint("TOPLEFT", frame, "TOPLEFT", headerX, -28)
    headerTotal:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -48, -28)
    headerTotal:SetJustifyH("LEFT")
    headerTotal:SetWordWrap(false)

    local headerSub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headerSub:SetPoint("TOPLEFT", headerTotal, "BOTTOMLEFT", 0, -1)
    headerSub:SetPoint("TOPRIGHT", headerTotal, "BOTTOMRIGHT", 0, -1)
    headerSub:SetJustifyH("LEFT")
    headerSub:SetWordWrap(false)

    if addon.Diagnostics then
        local logs = CreateFrame("Button", nil, frame)
        logs:SetSize(24, 24)
        logs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -27)
        logs:SetNormalTexture("Interface\\Icons\\INV_Misc_Note_01")
        logs:SetScript("OnClick", addon.Diagnostics.ToggleWindow)
        logs:SetScript("OnEnter", function(self) TextTooltip(self, "Diagnostics") end)
        logs:SetScript("OnLeave", HideTooltip)
        frame.logsButton = logs
    end

    local pageHost = CreateFrame("Frame", nil, frame)
    pageHost:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -56)
    pageHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    local guildPage = CreateFrame("Frame", nil, pageHost)
    guildPage:SetAllPoints(pageHost)
    local craftingPage = CreateFrame("Frame", nil, pageHost)
    craftingPage:SetAllPoints(pageHost)

    local listBox = CreateInset(craftingPage)
    listBox:SetPoint("TOPLEFT", craftingPage, "TOPLEFT", 0, -32)
    listBox:SetPoint("BOTTOMRIGHT", craftingPage, "BOTTOMRIGHT", 0, 34)

    local backButton = ArrowButton(craftingPage, "Prev", "All professions")
    backButton:SetPoint("TOPLEFT", craftingPage, "TOPLEFT", 4, -2)
    local breadcrumb = craftingPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    breadcrumb:SetPoint("TOPLEFT", craftingPage, "TOPLEFT", 38, -8)
    breadcrumb:SetPoint("TOPRIGHT", craftingPage, "TOPRIGHT", -244, -8)
    breadcrumb:SetJustifyH("LEFT")
    breadcrumb:SetWordWrap(false)

    local search = CreateFrame("EditBox", nil, listBox, "InputBoxTemplate")
    search:SetHeight(24)
    search:SetPoint("TOPLEFT", listBox, "TOPLEFT", 12, -12)
    search:SetPoint("TOPRIGHT", listBox, "TOPRIGHT", -12, -12)
    search:SetAutoFocus(false)
    search:SetTextInsets(5, 5, 2, 2)
    search:SetMaxLetters(80)
    local placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", search, "LEFT", 8, 0)
    placeholder:SetText("Filter recipes")

    local scanButton = CreateFrame("Button", nil, craftingPage, "UIPanelButtonTemplate")
    scanButton:SetSize(76, 24)
    scanButton:SetPoint("TOPRIGHT", craftingPage, "TOPRIGHT", -6, -3)
    scanButton:SetText("Rescan")
    scanButton:RegisterForClicks("LeftButtonUp")
    scanButton:SetScript("OnEnter", function(self)
        TextTooltip(self, "Rescan recipes",
            "Refresh your learned recipes and share them with the guild when sharing is enabled.\n\nThis does not scan other players or teach new recipes.")
    end)
    scanButton:SetScript("OnLeave", HideTooltip)

    local hideUnusable = CreateFrame("CheckButton", nil, craftingPage, "UICheckButtonTemplate")
    hideUnusable:SetSize(24, 24)
    hideUnusable:SetPoint("TOPRIGHT", craftingPage, "TOPRIGHT", -210, -3)
    hideUnusable:SetHitRectInsets(0, -120, 0, 0)
    hideUnusable:SetChecked(addon.db.hideUnusableRecipes == true)
    local usabilityLabel = hideUnusable:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    usabilityLabel:SetPoint("LEFT", hideUnusable, "RIGHT", 0, 0)
    usabilityLabel:SetWidth(120)
    usabilityLabel:SetJustifyH("LEFT")
    usabilityLabel:SetWordWrap(false)
    usabilityLabel:SetText("Hide unusable")
    hideUnusable:SetScript("OnEnter", function(self)
        TextTooltip(self, "Hide unusable items",
            "Hide items with unmet level, profession, or equipment requirements for this character.\n\nUnknown requirements remain visible. This does not filter by who can craft the recipe.")
    end)
    hideUnusable:SetScript("OnLeave", HideTooltip)

    local resultsScroll = CreateFrame("ScrollFrame", nil, listBox, "UIPanelScrollFrameTemplate")
    resultsScroll:SetPoint("TOPLEFT", listBox, "TOPLEFT", 10, -46)
    resultsScroll:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -28, 38)
    local resultsContent = CreateFrame("Frame", nil, resultsScroll)
    resultsContent:SetSize(670, 1)
    resultsScroll:SetScrollChild(resultsContent)

    local pageLabel = listBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageLabel:SetPoint("BOTTOM", listBox, "BOTTOM", 0, 13)

    local status = craftingPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", craftingPage, "BOTTOMLEFT", 10, 4)
    status:SetPoint("BOTTOMRIGHT", craftingPage, "BOTTOMRIGHT", -10, 4)
    status:SetHeight(26)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(true)

    local empty = resultsContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("TOPLEFT", resultsContent, "TOPLEFT", 8, -24)
    empty:SetPoint("TOPRIGHT", resultsContent, "TOPRIGHT", -8, -24)
    empty:SetJustifyH("CENTER")
    empty:SetWordWrap(true)

    local detail = CreateInset(craftingPage)
    detail:SetPoint("TOPRIGHT", craftingPage, "TOPRIGHT", 0, -32)
    detail:SetPoint("BOTTOMRIGHT", craftingPage, "BOTTOMRIGHT", 0, 34)
    detail:SetWidth(264)
    local detailIcon = CreateFrame("Button", nil, detail)
    detailIcon:SetSize(40, 40)
    detailIcon:SetPoint("TOPLEFT", detail, "TOPLEFT", 10, -12)
    detailIcon.texture = detailIcon:CreateTexture(nil, "ARTWORK")
    detailIcon.texture:SetAllPoints(detailIcon)
    detailIcon:SetScript("OnEnter", RecipeTooltip)
    detailIcon:SetScript("OnLeave", HideTooltip)
    local detailTitle = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailTitle:SetPoint("TOPLEFT", detail, "TOPLEFT", 58, -10)
    detailTitle:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -10, -10)
    detailTitle:SetHeight(48)
    detailTitle:SetJustifyH("LEFT")
    detailTitle:SetJustifyV("TOP")
    detailTitle:SetWordWrap(true)
    local detailScroll = CreateFrame("ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", detail, "TOPLEFT", 10, -66)
    detailScroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -28, 12)
    local detailContent = CreateFrame("Frame", nil, detailScroll)
    detailContent:SetSize(226, 1)
    detailScroll:SetScrollChild(detailContent)
    local detailText = detailContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailText:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 0, 0)
    detailText:SetPoint("TOPRIGHT", detailContent, "TOPRIGHT", -4, 0)
    detailText:SetJustifyH("LEFT")
    detailText:SetWordWrap(true)
    local craftersTitle = detailContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    craftersTitle:SetJustifyH("LEFT")

    local countsTooltip = CreateFrame("Frame", nil, craftingPage)
    countsTooltip:SetPoint("TOPLEFT", headerTotal, "TOPLEFT", 0, 0)
    countsTooltip:SetPoint("BOTTOMRIGHT", headerSub, "BOTTOMRIGHT", 0, 0)
    countsTooltip:EnableMouse(true)
    countsTooltip:SetScript("OnEnter", function(self)
        TextTooltip(self, "Guild recipe coverage", addon.Catalog.source
            .. "\n\nEach recipe is counted once, including your character. Only received guild profiles are included."
            .. "\n\nA database snapshot is not proof that every listed recipe is obtainable on the current build.")
    end)
    countsTooltip:SetScript("OnLeave", HideTooltip)

    local resultRows, crafterRows = {}, {}
    local selectedEntry, selectedDisplay, selectedProfession
    local cachedResults, cachedHome, cachedWidth = {}, true, 670
    local recipeScrollOffset, updatingResultsScroll = 0, false
    local ScrollResults
    local RefreshResults
    local watchedItems, requestedItems = {}, {}
    local refreshPending = false
    local function QueueFilterRefresh()
        if refreshPending then return end
        if C_Timer and type(C_Timer.After) == "function" then
            refreshPending = true
            if not addon.Compat.Call(C_Timer.After, 0.1, function()
                refreshPending = false
                if frame:IsShown() and craftingPage:IsShown() then RefreshResults() end
            end) then refreshPending = false end
        else
            RefreshResults()
        end
    end

    local function ShowDetail(entry, requestData)
        local changed = not selectedEntry or not entry or selectedEntry.key ~= entry.key
        selectedEntry = entry
        detailIcon.entry = entry
        for _, row in ipairs(crafterRows) do row:Hide() end
        if not entry then
            selectedDisplay = nil
            detailTitle:SetText("Recipe details")
            detailText:SetText("No recipe selected.")
            detailIcon:Hide()
            craftersTitle:Hide()
            detailContent:SetHeight(40)
            return
        end
        local display = addon.Compat.RecipeDisplay(entry, true)
        selectedDisplay = display
        detailIcon.texture:SetTexture(display.icon)
        detailIcon:Show()
        detailTitle:SetText(display.name)
        local text = entry.professionName .. "\n\n" .. display.description
        local _, usageReason = addon.Compat.RecipeUsability(entry)
        text = text .. "\n\n" .. usageReason
        if entry.availability then text = text .. "\n\n" .. entry.availability end
        local materials = {}
        for itemID in pairs(entry.reagents or {}) do materials[#materials + 1] = itemID end
        table.sort(materials)
        if #materials > 0 then
            text = text .. "\n\nMaterials"
            for _, itemID in ipairs(materials) do
                local name = addon.Compat.Value(C_Item and C_Item.GetItemInfo, itemID)
                text = text .. "\n" .. entry.reagents[itemID] .. " x "
                    .. (type(name) == "string" and name or ("Item " .. itemID))
                if requestData and type(name) ~= "string" then
                    addon.Compat.Call(C_Item and C_Item.RequestLoadItemDataByID, itemID)
                end
            end
        end
        detailText:SetText(text)
        local textHeight = addon.Compat.Value(detailText.GetStringHeight, detailText)
        local offset = math.max(40, type(textHeight) == "number" and textHeight or 80) + 20
        craftersTitle:ClearAllPoints()
        craftersTitle:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 0, -offset)
        craftersTitle:SetPoint("TOPRIGHT", detailContent, "TOPRIGHT", -4, -offset)
        craftersTitle:SetText(#entry.crafters > 0 and ("Crafters (" .. #entry.crafters .. ")") or "No known guild crafter")
        craftersTitle:Show()
        offset = offset + 24
        for index, crafter in ipairs(entry.crafters) do
            local row = crafterRows[index]
            if not row then
                row = CreateFrame("Frame", nil, detailContent)
                row:SetHeight(44)
                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
                row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -34, -2)
                row.name:SetJustifyH("LEFT")
                row.name:SetWordWrap(false)
                row.age = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.age:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -18)
                row.age:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -18)
                row.age:SetJustifyH("LEFT")
                row.age:SetWordWrap(false)
                row.request = CreateFrame("Button", nil, row)
                row.request:SetSize(28, 28)
                row.request:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, 0)
                row.request:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
                row.request:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Down")
                row.request:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
                row.request:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
                row.request:SetScript("OnEnter", function(self)
                    TextTooltip(self, "Whisper " .. addon.Compat.CharacterLabel(self.crafter.name),
                        "Opens an editable crafting request. Nothing is sent automatically.")
                end)
                row.request:SetScript("OnLeave", HideTooltip)
                row.request:SetScript("OnClick", function(self)
                    local opened, reason = addon.Compat.OpenCraftRequest(self.entry, self.crafter)
                    status:SetText(opened and ("Whisper draft opened for " .. addon.Compat.CharacterLabel(self.crafter.name) .. ".") or reason)
                    if not opened then addon.Print(reason) end
                end)
                crafterRows[index] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 0, -offset)
            row:SetPoint("TOPRIGHT", detailContent, "TOPRIGHT", -4, -offset)
            row.name:SetText(addon.Compat.CharacterLabel(crafter.name))
            local presence = crafter.isOnline == true and "Online"
                or crafter.isOnline == false and "Offline" or "Status unavailable"
            row.age:SetText(presence .. " - Scanned " .. FormatAge(crafter.updatedAt))
            row:SetAlpha(crafter.isOnline == true and 1 or 0.5)
            row.request.entry, row.request.crafter = entry, crafter
            row.request:SetEnabled(not crafter.isLocal and crafter.isOnline == true)
            if crafter.isLocal then row.request:Hide() else row.request:Show() end
            row:Show()
            offset = offset + 44
        end
        detailContent:SetHeight(offset)
        if changed then detailScroll:SetVerticalScroll(0) end
        if requestData then addon.Compat.RequestRecipeData(display) end
        for _, row in ipairs(resultRows) do
            if row.entry and row.entry.key == entry.key then row:LockHighlight() else row:UnlockHighlight() end
        end
    end

    local function RenderResults()
        local step, columns = cachedHome and 56 or 46, cachedHome and 2 or 1
        local height = addon.Compat.Value(resultsScroll.GetHeight, resultsScroll)
        if type(height) ~= "number" or height <= 0 then height = 344 end
        local maximum = math.max(0, math.ceil(#cachedResults / columns) * step - height)
        recipeScrollOffset = math.max(0, math.min(recipeScrollOffset, maximum))
        updatingResultsScroll = true
        resultsScroll:SetVerticalScroll(recipeScrollOffset)
        updatingResultsScroll = false
        local firstIndex = math.floor(recipeScrollOffset / step) * columns + 1
        local visibleCount = math.min(48, (math.ceil(height / step) + 1) * columns)
        for slot = 1, math.min(visibleCount, #cachedResults - firstIndex + 1) do
            local index = firstIndex + slot - 1
            local entry = cachedResults[index]
            local row = resultRows[slot]
            if not row then
                row = CreateFrame("Button", nil, resultsContent)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(32, 32)
                row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 46, -7)
                row.label:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -7)
                row.label:SetJustifyH("LEFT")
                row.label:SetWordWrap(false)
                row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.detail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 46, 7)
                row.detail:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 7)
                row.detail:SetJustifyH("LEFT")
                row.detail:SetWordWrap(false)
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                row:SetScript("OnEnter", function(self)
                    if self.profession then TextTooltip(self, self.profession.name, self.detail:GetText())
                    else RecipeTooltip(self) end
                end)
                row:SetScript("OnLeave", HideTooltip)
                row:SetScript("OnClick", function(self)
                    if self.profession then
                        selectedProfession, selectedEntry = self.profession.id, nil
                        RefreshResults(true)
                    elseif self.entry then ShowDetail(self.entry, true) end
                end)
                addon.Compat.Call(row.EnableMouseWheel, row, true)
                row:SetScript("OnMouseWheel", function(_, delta)
                    if addon.Compat.IsReadable(delta) and type(delta) == "number" and delta == delta
                        and delta >= -100 and delta <= 100 then
                        ScrollResults(recipeScrollOffset - delta * (cachedHome and 56 or 46) * 3)
                    end
                end)
                resultRows[slot] = row
            end
            row:UnlockHighlight()
            row.entry, row.profession = nil, nil
            row:ClearAllPoints()
            if cachedHome then
                row.profession = entry
                local width = (cachedWidth - 12) / 2
                row:SetSize(width, 52)
                row:SetPoint("TOPLEFT", resultsContent, "TOPLEFT", ((index - 1) % 2) * (width + 12), -math.floor((index - 1) / 2) * 56)
                row.icon:SetTexture(entry.icon)
                row.label:SetText(entry.name)
                row.detail:SetText(entry.gathering and entry.total == 0 and "Gathering profession"
                    or (entry.known .. " / " .. entry.total .. " guild-known / catalogued"))
            else
                row.entry = entry
                row:SetSize(cachedWidth, 44)
                row:SetPoint("TOPLEFT", resultsContent, "TOPLEFT", 0, -(index - 1) * 46)
                local display = addon.Compat.RecipeDisplay(entry)
                row.icon:SetTexture(display.icon)
                row.label:SetText(display.name)
                row.detail:SetText(hideUnusable:GetChecked() and entry.usable == nil and entry.usageReason
                    or (#entry.crafters > 0 and (#entry.crafters .. " crafter(s)") or "No known guild crafter"))
                if selectedEntry and selectedEntry.key == entry.key then row:LockHighlight() end
            end
            local unknown = not cachedHome and #entry.crafters == 0
            addon.Compat.Call(row.icon.SetDesaturated, row.icon, unknown)
            row.icon:SetVertexColor(unknown and 0.65 or 1, unknown and 0.65 or 1, unknown and 0.65 or 1)
            row.label:SetTextColor(unknown and 0.55 or 1, unknown and 0.55 or 0.82, unknown and 0.55 or 0)
            row.detail:SetTextColor(unknown and 0.45 or 0.82, unknown and 0.45 or 0.82, unknown and 0.45 or 0.82)
            row:Show()
        end
        for slot = math.min(visibleCount, math.max(0, #cachedResults - firstIndex + 1)) + 1, #resultRows do
            resultRows[slot].entry, resultRows[slot].profession = nil, nil
            resultRows[slot]:Hide()
        end
        if cachedHome then pageLabel:SetText(#cachedResults .. " professions")
        else
            local lastIndex = math.min(#cachedResults, math.ceil((recipeScrollOffset + height) / step))
            pageLabel:SetText(#cachedResults > 0 and (firstIndex .. "-" .. lastIndex .. " / " .. #cachedResults .. " recipes") or "0 recipes")
        end
    end
    ScrollResults = function(offset)
        if not addon.Compat.IsReadable(offset) or type(offset) ~= "number" or offset ~= offset then return end
        recipeScrollOffset = offset
        HideTooltip()
        RenderResults()
    end
    local function ResultsScrolled(_, offset)
        if not updatingResultsScroll then ScrollResults(offset) end
    end
    if type(resultsScroll.HookScript) == "function" then resultsScroll:HookScript("OnVerticalScroll", ResultsScrolled)
    else resultsScroll:SetScript("OnVerticalScroll", ResultsScrolled) end
    addon.Compat.Call(resultsScroll.EnableMouseWheel, resultsScroll, true)
    resultsScroll:SetScript("OnMouseWheel", function(_, delta)
        if addon.Compat.IsReadable(delta) and type(delta) == "number" and delta == delta and delta >= -100 and delta <= 100 then
            ScrollResults(recipeScrollOffset - delta * (cachedHome and 56 or 46) * 3)
        end
    end)

    RefreshResults = function(resetScroll)
        local localProfile = addon.Catalog.Initialize().localProfile
        if localProfile and localProfile.professionConflict then
            addon.Sync.status = "Confirm which primary profession was unlearned; recipe sharing paused"
        end
        if addon.Members and addon.Members.CanView and not addon.Members.CanView() then
            cachedResults = {}
            recipeScrollOffset = 0
            selectedEntry = nil
            for _, row in ipairs(resultRows) do row.entry, row.profession = nil, nil; row:Hide() end
            ShowDetail(nil)
            if addon.db.canvasTab == "crafting" then
                headerTotal:SetText("Guild profile")
                headerSub:SetText("Main character and Discord server nickname required")
            end
            return
        end
        local query = search:GetText() or ""
        local professions, known, total = addon.Catalog.Overview()
        local home = selectedProfession == nil and query == ""
        local results, matchCount
        local selectedCoverage
        local pendingItems = {}
        watchedItems = {}
        if home then
            results, matchCount = professions, #professions
            breadcrumb:SetText("Professions")
            detail:Hide()
            backButton:Hide()
            listBox:SetPoint("BOTTOMRIGHT", craftingPage, "BOTTOMRIGHT", 0, 34)
        else
            results, matchCount, watchedItems, pendingItems =
                addon.Catalog.BrowseAll(query, selectedProfession, hideUnusable:GetChecked() == true)
            local title = "All recipes"
            for _, profession in ipairs(professions) do
                if profession.id == selectedProfession then title = profession.name; selectedCoverage = profession; break end
            end
            breadcrumb:SetText(title)
            detail:Show()
            backButton:Show()
            listBox:SetPoint("BOTTOMRIGHT", craftingPage, "BOTTOMRIGHT", -272, 34)
        end
        local contentWidth = home and 670 or 398
        resultsContent:SetWidth(contentWidth)
        if query == "" then placeholder:Show() else placeholder:Hide() end
        empty:SetText(hideUnusable:GetChecked() and "No matching recipes." or "No recipes catalogued.")
        if #results == 0 then empty:Show() else empty:Hide() end
        cachedResults, cachedHome, cachedWidth = results, home, contentWidth
        updatingResultsScroll = true
        resultsContent:SetHeight(math.max(80, home and math.ceil(#results / 2) * 56 or #results * 46))
        updatingResultsScroll = false
        if resetScroll then recipeScrollOffset = 0 end
        RenderResults()
        if not home then
            local selected
            for _, entry in ipairs(results) do
                if selectedEntry and entry.key == selectedEntry.key then selected = entry break end
            end
            local target = selected or results[1]
            ShowDetail(target, target and (not selectedEntry or target.key ~= selectedEntry.key))
        else
            ShowDetail(nil)
        end
        local remoteCount = 0
        for _ in pairs(addon.Catalog.RemoteProfiles()) do
            remoteCount = remoteCount + 1
        end
        if (addon.db.canvasTab ~= "guild" or not frame.guild) and (addon.db.canvasTab ~= "map" or not frame.map) then
            if selectedCoverage then
                headerTotal:SetText(selectedCoverage.known .. " / " .. selectedCoverage.total .. " " .. selectedCoverage.name .. " recipes")
            else headerTotal:SetText(known .. " / " .. total .. " guild recipes") end
            headerSub:SetText("Guild-known / " .. (addon.Catalog.hasLibrary and "catalogue" or "observed recipes")
                .. (selectedCoverage and " for this profession" or "")
                .. "  -  " .. remoteCount .. " guild profiles")
        end
        status:SetText(addon.Sync.status)
        if C_Timer and type(C_Timer.After) == "function" then
            local requested = 0
            for itemID in pairs(pendingItems) do
                if not requestedItems[itemID] then
                    requestedItems[itemID] = true
                    addon.Compat.Call(C_Item and C_Item.RequestLoadItemDataByID, itemID)
                    requested = requested + 1
                    if requested >= 8 then break end
                end
            end
        end
    end

    hideUnusable:SetScript("OnClick", function(self)
        addon.db.hideUnusableRecipes = self:GetChecked() == true
        requestedItems = {}
        RefreshResults(true)
    end)
    search:SetScript("OnTextChanged", function()
        RefreshResults(true)
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    backButton:SetScript("OnClick", function()
        selectedProfession, selectedEntry = nil, nil
        search:SetText("")
        search:ClearFocus()
        RefreshResults(true)
    end)
    scanButton:SetScript("OnClick", function()
        addon.Catalog.RefreshLibrary(true)
        local scanned, learned, reason = addon.Catalog.Scan()
        if scanned then
            addon.Sync.status = "Scan complete: " .. tostring(learned or 0) .. " learned"
            addon.Print("Recipe scan complete: " .. scanned .. " checked; " .. (learned or 0) .. " learned.")
            if addon.Catalog.Initialize().shareEnabled then
                addon.Sync.Publish()
            end
        else
            addon.Sync.status = "Scan unavailable: " .. tostring(reason)
            addon.Print("Recipe scan unavailable: " .. tostring(reason) .. ".")
        end
        RefreshResults()
    end)
    addon.RefreshCatalog = function()
        if frame:IsShown() and addon.db.canvasTab == "crafting" then QueueFilterRefresh() end
    end

    frame.crafting = {
        search = search, backButton = backButton, rows = resultRows, detail = detail,
        hideUnusable = hideUnusable, detailText = detailText,
        crafters = crafterRows, scroll = resultsScroll, content = resultsContent, ScrollTo = ScrollResults,
        pageLabel = pageLabel, headerTotal = headerTotal, status = status,
    }

    frame:SetScript("OnShow", function()
        if addon.GuildState and addon.GuildState.IsAllowed and not addon.GuildState.IsAllowed() then
            addon.HideCanvas()
            return
        end
        RefreshAdminStatus()
        requestedItems = {}
        addon.RefreshGuild()
        if addon.db.canvasTab == "crafting" then RefreshResults() end
    end)
    frame:SetScript("OnHide", HideTooltip)
    frame:SetScript("OnEvent", function(_, event, dataID)
        if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
            FitWindow()
        elseif event == "ADDON_LOADED" then
            addon.Catalog.RefreshLibrary()
            addon.RefreshCatalog()
        elseif frame:IsShown() and craftingPage:IsShown() and hideUnusable:GetChecked()
            and (event == "PLAYER_LEVEL_UP" or event == "SKILL_LINES_CHANGED" or event == "SPELLS_CHANGED"
                or event == "UPDATE_FACTION" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "TOOLTIP_DATA_UPDATE"
                or event == "SPELL_DATA_LOAD_RESULT" or event == "SPELL_TEXT_UPDATE"
                or ((event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED")
                    and addon.Compat.IsReadable(dataID) and type(dataID) == "number" and watchedItems[dataID])) then
            QueueFilterRefresh()
        elseif frame:IsShown() and craftingPage:IsShown() and selectedEntry and selectedDisplay
            and addon.Compat.IsReadable(dataID) and type(dataID) == "number"
            and (dataID == selectedDisplay.itemID or dataID == selectedDisplay.recipeID
                or (selectedEntry.reagents and selectedEntry.reagents[dataID])) then
            ShowDetail(selectedEntry, false)
            for _, row in ipairs(resultRows) do
                if row.entry and row.entry.key == selectedEntry.key then
                    row.icon:SetTexture(selectedDisplay.icon)
                    row.label:SetText(selectedDisplay.name)
                end
            end
        end
    end)
    for _, event in ipairs({ "ITEM_DATA_LOAD_RESULT", "SPELL_DATA_LOAD_RESULT", "SPELL_TEXT_UPDATE",
        "ADDON_LOADED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "GET_ITEM_INFO_RECEIVED",
        "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "UPDATE_FACTION",
        "PLAYER_EQUIPMENT_CHANGED", "TOOLTIP_DATA_UPDATE" }) do
        addon.Compat.Call(frame.RegisterEvent, frame, event)
    end

    if addon.CreateGuildView then frame.guild = addon.CreateGuildView(guildPage, headerTotal, headerSub) end

    local mapPage
    if addon.CreateGuildMapView then
        mapPage = CreateFrame("Frame", nil, pageHost)
        mapPage:SetAllPoints(pageHost)
        frame.map = addon.CreateGuildMapView(mapPage, headerTotal, headerSub)
    end

    ShowDetail(nil)

    local pages = { guild = guildPage, crafting = craftingPage }
    if mapPage then pages.map = mapPage end
    local tabs = {}
    local definitions = {
        { key = "guild", label = "Guild" },
        { key = "crafting", label = "Crafting" },
    }
    if mapPage then definitions[#definitions + 1] = { key = "map", label = "Map" } end
    local friendsTab = _G.FriendsFrameTab1
    local useOldTabs = type(friendsTab) == "table" and friendsTab.LeftActive == nil
        or (type(friendsTab) ~= "table" and PanelTemplates_AnchorTabs == nil)
    local tabTemplates = useOldTabs
        and { "CharacterFrameTabButtonTemplate", "PanelTabButtonTemplate", "TabButtonTemplate" }
        or { "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate", "TabButtonTemplate" }

    local function SelectTab(key)
        if addon.Members and addon.Members.CanView and not addon.Members.CanView() then key = "guild" end
        if not pages[key] then
            return
        end
        for pageKey, page in pairs(pages) do
            if pageKey == key then
                page:Show()
            else
                page:Hide()
            end
        end
        for index, tab in ipairs(tabs) do
            local selected = tab.key == key
            if selected then
                frame.selectedTab = index
            end
            if tab.isFallback or not PanelTemplates_SelectTab then
                if selected then
                    tab:LockHighlight()
                    tab:SetNormalFontObject("GameFontHighlight")
                else
                    tab:UnlockHighlight()
                    tab:SetNormalFontObject("GameFontNormal")
                end
            elseif selected then
                pcall(PanelTemplates_SelectTab, tab)
            elseif PanelTemplates_DeselectTab then
                pcall(PanelTemplates_DeselectTab, tab)
            end
        end
        addon.db.canvasTab = key
        if key == "guild" and frame.guild then frame.guild.Refresh()
        elseif key == "map" and frame.map then frame.map.Refresh()
        elseif key == "crafting" then RefreshResults() end
    end

    if frame.guild then
        local guildRefreshPending = false
        addon.RefreshGuild = function()
            if not frame:IsShown() then return end
            RefreshAdminStatus()
            if addon.Members and addon.Members.CanView and not addon.Members.CanView() then
                RefreshResults()
                SelectTab("guild")
            elseif addon.db.canvasTab == "guild" then
                if not C_Timer or type(C_Timer.After) ~= "function" then frame.guild.Refresh()
                elseif not guildRefreshPending then
                    guildRefreshPending = true
                    C_Timer.After(0.1, function()
                        guildRefreshPending = false
                        if frame:IsShown() and addon.db.canvasTab == "guild" then frame.guild.Refresh() end
                    end)
                end
            end
            if addon.GuildMap then addon.GuildMap.Refresh() end
        end
    end

    for index, definition in ipairs(definitions) do
        local tab = nil
        for attempt, template in ipairs(tabTemplates) do
            local tabName = frame:GetName() .. "Tab" .. index .. "Template" .. attempt
            local ok, candidate = pcall(CreateFrame, "Button", tabName, frame, template)
            if ok and candidate and (candidate.Left or candidate.LeftActive
                or _G[tabName .. "Left"] or _G[tabName .. "LeftDisabled"]) then
                tab = candidate
                break
            elseif ok and candidate then
                candidate:Hide()
            end
        end
        if not tab then
            tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            tab:SetSize(96, 22)
            tab.isFallback = true
        end
        tab:SetText(definition.label)
        if not tab.isFallback and PanelTemplates_TabResize then
            pcall(PanelTemplates_TabResize, tab, 0)
        end
        frame.tabStyle = frame.tabStyle or (tab.LeftActive and PanelTemplates_AnchorTabs and "mainline" or "classic")
        tab.key = definition.key
        tab:SetID(index)
        tab:RegisterForClicks("LeftButtonUp")
        tab:SetScript("OnClick", function()
            SelectTab(definition.key)
        end)
        if index == 1 then
            tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT",
                frame.tabStyle == "mainline" and 5 or 10, 2)
        elseif tab.isFallback then
            tab:SetPoint("LEFT", tabs[index - 1], "RIGHT", 6, 0)
        elseif frame.tabStyle == "mainline" then
            tab:SetPoint("TOPLEFT", tabs[index - 1], "TOPRIGHT", 3, 0)
        else
            tab:SetPoint("LEFT", tabs[index - 1], "RIGHT", -15, 0)
        end
        tabs[index] = tab
    end
    frame.tabs = tabs
    frame.numTabs = #tabs
    if addon.db.canvasTabVersion ~= 1 then
        addon.db.canvasTab = "crafting"
        addon.db.canvasTabVersion = 1
    end
    local initialTab = pages[addon.db.canvasTab] and addon.db.canvasTab or "crafting"
    SelectTab(initialTab)

    frame:Hide()
    return frame
end

function addon.HideCanvas()
    if frame then frame:StopMovingOrSizing(); frame:Hide() end
    addon.HideProfessionCorrection()
    HideTooltip()
end

function addon.ToggleCanvas()
    if addon.GuildState and addon.GuildState.IsAllowed and not addon.GuildState.IsAllowed() then
        addon.HideCanvas()
        return
    end
    local canvas = CreateCanvas()
    if canvas:IsShown() then
        canvas:Hide()
    else
        canvas:Show()
    end
end