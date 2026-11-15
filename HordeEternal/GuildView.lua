local _, addon = ...

local VISIBLE_ROWS = 6
local ROW_HEIGHT = 39
local ROW_WIDTH = 654
local DISCORD_ICON = "Interface\\AddOns\\HordeEternal\\media\\Discord.tga"
local MAIN_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local CLASS_STYLE = {
    WARRIOR = { 0.78, 0.61, 0.43, 0, 0.25, 0, 0.25 },
    MAGE = { 0.41, 0.80, 0.94, 0.25, 0.5, 0, 0.25 },
    ROGUE = { 1, 0.96, 0.41, 0.5, 0.75, 0, 0.25 },
    DRUID = { 1, 0.49, 0.04, 0.75, 1, 0, 0.25 },
    HUNTER = { 0.67, 0.83, 0.45, 0, 0.25, 0.25, 0.5 },
    SHAMAN = { 0, 0.44, 0.87, 0.25, 0.5, 0.25, 0.5 },
    PRIEST = { 1, 1, 1, 0.5, 0.75, 0.25, 0.5 },
    WARLOCK = { 0.58, 0.51, 0.79, 0.75, 1, 0.25, 0.5 },
    PALADIN = { 0.96, 0.55, 0.73, 0, 0.25, 0.5, 0.75 },
}

local function Label(parent, text, x, y, width, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(text)
    return label
end

local function Tooltip(owner, title, text)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
end

local function Icon(parent, path, size, x, y)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    texture:SetTexture(path)
    texture:SetSize(size, size)
    texture:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return texture
end

local function Bare(name)
    return name and addon.Compat.CharacterLabel(name) or ""
end

local function Fill(parent, red, green, blue, alpha)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(parent)
    texture:SetColorTexture(red, green, blue, alpha)
    return texture
end

local function Rule(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, y)
    line:SetHeight(1)
    line:SetColorTexture(0.68, 0.56, 0.32, 0.3)
end

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function ClassIcon(texture, classFile)
    local style = CLASS_STYLE[classFile]
    if style then
        texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        texture:SetTexCoord(style[4], style[5], style[6], style[7])
    else
        texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

local function Arrow(parent, direction, title)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(24, 24)
    button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-Up")
    button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-Down")
    button:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-Disabled")
    button:SetScript("OnEnter", function(self) Tooltip(self, title) end)
    button:SetScript("OnLeave", HideTooltip)
    return button
end

local function SortValue(character, key)
    if key == "name" then return character.name:lower() end
    if key == "className" then return (character.className .. " " .. character.race):lower() end
    if key == "spec" then return character.spec ~= "Spec unknown" and character.spec:lower() or nil end
    if key == "rank" then
        if not character.rank or character.rank == "" then return nil end
        return string.format("%03d", character.rankIndex or 999) .. " " .. character.rank:lower()
    end
    if key == "main" then
        if character.state == "No main selected" then return nil end
        return (character.state == "Main" and "0 " or "1 ")
            .. (Bare(character.main) .. " " .. character.discord):lower()
    end
end

function addon.CreateGuildView(page, header, subheader)
    local view = { rows = {}, statRows = {}, mainsOnly = true, scrollOffset = 0, category = "classes", statsPage = 1 }
    local dirty, formMessage = false, ""
    local host = page
    page = CreateFrame("Frame", nil, host)
    page:SetAllPoints(host)
    Label(page, "Guild composition", 12, -10, 145, "GameFontNormal")
    local mains = CreateFrame("CheckButton", nil, page, "UIRadioButtonTemplate")
    mains:SetSize(18, 18)
    mains:SetPoint("TOPLEFT", page, "TOPLEFT", 162, -7)
    Label(page, "Mains", 184, -11, 56)
    local everyone = CreateFrame("CheckButton", nil, page, "UIRadioButtonTemplate")
    everyone:SetSize(18, 18)
    everyone:SetPoint("TOPLEFT", page, "TOPLEFT", 246, -7)
    Label(page, "All characters", 268, -11, 115)
    local profile = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    profile:SetSize(64, 24)
    profile:SetPoint("TOPRIGHT", page, "TOPRIGHT", -10, -3)
    profile:SetText("Edit")
    profile:SetScript("OnEnter", function(self) Tooltip(self, "Edit guild profile", "Your main character and Discord server nickname") end)
    profile:SetScript("OnLeave", HideTooltip)
    local profileSummary = Label(page, "", 400, -11, 224)
    profileSummary:SetJustifyH("RIGHT")
    profileSummary:SetTextColor(0.76, 0.74, 0.67)
    Rule(page, -34)

    local statTabs = {}
    for index, definition in ipairs({ { "classes", "Classes" }, { "races", "Races" }, { "specs", "Talents" } }) do
        local tab = CreateFrame("Button", nil, page)
        tab:SetSize(78, 24)
        tab:SetPoint("TOPLEFT", page, "TOPLEFT", 10 + (index - 1) * 84, -41)
        tab.label = Label(tab, definition[2], 0, -5, 78)
        tab.label:SetJustifyH("CENTER")
        tab.line = tab:CreateTexture(nil, "ARTWORK")
        tab.line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 6, 0)
        tab.line:SetSize(66, 2)
        tab.line:SetColorTexture(0.9, 0.72, 0.27, 1)
        tab:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        tab:SetScript("OnClick", function() view.category = definition[1]; view.statsPage = 1; view.Refresh() end)
        statTabs[definition[1]] = tab
    end
    local coverage = Label(page, "", 274, -49, 316)
    coverage:SetJustifyH("RIGHT")
    coverage:SetTextColor(0.72, 0.71, 0.66)
    local statsPrevious = Arrow(page, "Prev", "Previous statistics")
    statsPrevious:SetPoint("TOPRIGHT", page, "TOPRIGHT", -42, -41)
    local statsNext = Arrow(page, "Next", "More statistics")
    statsNext:SetPoint("TOPRIGHT", page, "TOPRIGHT", -12, -41)
    statsPrevious:SetScript("OnClick", function() view.statsPage = view.statsPage - 1; view.Refresh() end)
    statsNext:SetScript("OnClick", function() view.statsPage = view.statsPage + 1; view.Refresh() end)
    for index = 1, 9 do
        local cell = CreateFrame("Button", nil, page)
        cell:SetSize(208, 30)
        cell:SetPoint("TOPLEFT", page, "TOPLEFT", 14 + ((index - 1) % 3) * 226, -76 - math.floor((index - 1) / 3) * 32)
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetSize(20, 20)
        cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -2)
        cell.label = Label(cell, "", 27, 0, 92)
        cell.count = Label(cell, "", 124, 0, 82, "GameFontNormalSmall")
        cell.count:SetJustifyH("RIGHT")
        cell.track = cell:CreateTexture(nil, "BACKGROUND")
        cell.track:SetPoint("TOPLEFT", cell, "TOPLEFT", 27, -18)
        cell.track:SetSize(179, 4)
        cell.track:SetColorTexture(0, 0, 0, 0.45)
        cell.bar = cell:CreateTexture(nil, "ARTWORK")
        cell.bar:SetPoint("TOPLEFT", cell, "TOPLEFT", 27, -18)
        cell.bar:SetHeight(4)
        cell:SetScript("OnEnter", function(self)
            Tooltip(self, self.statName, self.statCount .. " of " .. self.population .. " counted characters ("
                .. self.percentage .. ")\nPopulation: " .. (view.mainsOnly and "declared mains" or "all guild characters")
                .. "\nUnknown reports are included in this population.")
        end)
        cell:SetScript("OnLeave", HideTooltip)
        view.statRows[index] = cell
    end
    local statsEmpty = Label(page, "", 18, -91, 640)
    Rule(page, -178)
    Label(page, "Character directory", 12, -197, 180, "GameFontNormal")
    local filter = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    filter:SetSize(390, 24)
    filter:SetPoint("TOPRIGHT", page, "TOPRIGHT", -16, -190)
    filter:SetAutoFocus(false)
    filter:SetMaxLetters(80)
    filter:SetTextInsets(22, 7, 2, 2)
    local searchIcon = filter:CreateTexture(nil, "ARTWORK")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", filter, "LEFT", 4, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    local placeholder = Label(filter, "Search characters", 24, -6, 330, "GameFontDisableSmall")
    filter:SetScript("OnTextChanged", function() view.scrollOffset = 0; view.Refresh() end)
    filter:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    filter:SetScript("OnEnter", function(self) Tooltip(self, "Search characters", "Name, class, race, guild role, main, spec, or Discord server nickname") end)
    filter:SetScript("OnLeave", HideTooltip)
    local headings = CreateFrame("Frame", nil, page)
    headings:SetSize(680, 22)
    headings:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -224)
    Fill(headings, 0, 0, 0, 0.4)
    local columns = {
        { key = "name", title = "Character", x = 31, width = 162 },
        { key = "className", title = "Class / Race", x = 199, width = 108 },
        { key = "spec", title = "Talents", x = 315, width = 102 },
        { key = "rank", title = "Role", x = 425, width = 92 },
        { key = "main", title = "Main / Nickname", x = 525, width = 118 },
    }
    local sortHeaders = {}
    for _, column in ipairs(columns) do
        local button = CreateFrame("Button", nil, headings)
        button:SetSize(column.width, 22)
        button:SetPoint("TOPLEFT", headings, "TOPLEFT", column.x, 0)
        button.label = Label(button, column.title, 0, -5, column.width - 14, "GameFontNormalSmall")
        button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        button.indicator = button:CreateTexture(nil, "ARTWORK")
        button.indicator:SetSize(8, 12)
        button.indicator:SetPoint("RIGHT", button, "RIGHT", -1, 0)
        button.indicator:SetTexture("Interface\\Buttons\\UI-SortArrow")
        button:SetScript("OnClick", function()
            if view.sortKey == column.key then view.sortAscending = not view.sortAscending
            else view.sortKey, view.sortAscending = column.key, true end
            view.scrollOffset = 0
            view.Refresh()
        end)
        button:SetScript("OnEnter", function(self)
            local direction = view.sortKey == column.key and view.sortAscending and "descending" or "ascending"
            Tooltip(self, "Sort by " .. column.title, column.key == "rank"
                and ("Guild rank order, " .. direction) or ("Sort " .. direction))
        end)
        button:SetScript("OnLeave", HideTooltip)
        sortHeaders[column.key] = button
    end
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetSize(ROW_WIDTH, VISIBLE_ROWS * ROW_HEIGHT)
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -248)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(ROW_WIDTH, VISIBLE_ROWS * ROW_HEIGHT)
    scroll:SetScrollChild(content)
    local empty = Label(content, "", 16, -30, 648)
    empty:SetJustifyH("CENTER")
    for index = 1, VISIBLE_ROWS + 1 do
        local row = CreateFrame("Button", nil, content)
        row:SetSize(ROW_WIDTH, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        row.background = Fill(row, 0, 0, 0, index % 2 == 0 and 0.27 or 0.12)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 5, -8)
        row.name = Label(row, "", 31, -5, 162, "GameFontNormalSmall")
        row.presence = Label(row, "", 43, -22, 150)
        row.mainIcon = Icon(row, MAIN_ICON, 12, 525, -5)
        row.statusDot = row:CreateTexture(nil, "ARTWORK")
        row.statusDot:SetSize(7, 7)
        row.statusDot:SetPoint("TOPLEFT", row, "TOPLEFT", 31, -25)
        row.statusDot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        row.className = Label(row, "", 199, -5, 108)
        row.race = Label(row, "", 199, -22, 108)
        row.spec = Label(row, "", 315, -5, 102)
        row.report = Label(row, "", 315, -22, 102)
        row.role = Label(row, "", 425, -5, 92)
        row.identity = Label(row, "", 541, -5, 102)
        row.contact = Label(row, "", 541, -22, 102)
        row.discordIcon = Icon(row, DISCORD_ICON, 12, 525, -22)
        for _, label in ipairs({ row.presence, row.race, row.report, row.contact }) do label:SetTextColor(0.65, 0.65, 0.61) end
        row:SetScript("OnEnter", function(self)
            local member = self.member
            if not member then return end
            local state = member.online == true and "Online" or member.online == false and "Offline" or "Online status unknown"
            local updated = member.updatedAt and member.updatedAt > 0 and date and date("%Y-%m-%d %H:%M", member.updatedAt) or "Unknown"
            Tooltip(self, Bare(member.name), state .. "\n" .. (member.rank or "") .. "\n"
                .. member.state .. (member.main and (": " .. Bare(member.main)) or "")
                .. "\n" .. member.className .. " / " .. member.race .. "\n" .. member.spec
                .. "\n" .. member.talents .. "\nLast reported: " .. updated
                .. "\n" .. (member.discord ~= "" and ("|T" .. DISCORD_ICON .. ":12:12|t ") or "")
                .. "Discord server nickname: " .. (member.discord ~= "" and member.discord or "Not shared"))
        end)
        row:SetScript("OnLeave", HideTooltip)
        view.rows[index] = row
    end
    local visibleRange = Label(page, "", 0, 0, 130)
    visibleRange:ClearAllPoints()
    visibleRange:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -14, 11)
    visibleRange:SetJustifyH("RIGHT")
    local directoryCount = Label(page, "", 0, 0, 470)
    directoryCount:ClearAllPoints()
    directoryCount:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 14, 11)
    directoryCount:SetTextColor(0.72, 0.71, 0.66)

    local locked = CreateFrame("Frame", nil, host)
    locked:SetAllPoints(host)
    local required = Label(locked, "Guild profile required", 24, -147, 660, "GameFontNormalLarge")
    required:SetJustifyH("CENTER")
    local requirements = Label(locked, "", 24, -187, 660)
    requirements:SetJustifyH("CENTER")
    requirements:SetWordWrap(true)
    local setup = CreateFrame("Button", nil, locked, "UIPanelButtonTemplate")
    setup:SetSize(180, 28)
    setup:SetPoint("TOP", locked, "TOP", 0, -238)
    setup:SetText("Set up guild profile")
    local shade = CreateFrame("Frame", nil, host)
    shade:SetAllPoints(host)
    shade:SetFrameStrata("DIALOG")
    shade:EnableMouse(true)
    Fill(shade, 0, 0, 0, 0.65)
    shade:Hide()
    local ok, editor = pcall(CreateFrame, "Frame", nil, shade, "BackdropTemplate")
    if not ok or not editor then editor = CreateFrame("Frame", nil, shade) end
    editor:SetSize(424, 224)
    editor:SetPoint("CENTER", host, "CENTER", 0, 20)
    editor:SetFrameStrata("DIALOG")
    editor:EnableMouse(true)
    addon.Compat.Call(editor.EnableKeyboard, editor, true)
    addon.Compat.Call(editor.SetPropagateKeyboardInput, editor, true)
    Fill(editor, 0.045, 0.045, 0.04, 1)
    if editor.SetBackdrop then
        editor:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    end
    Label(editor, "Your guild profile", 22, -20, 350, "GameFontNormal")
    local editorName = Label(editor, "", 24, -49, 372, "GameFontHighlight")
    local current = Label(editor, "", 24, -72, 372)
    local currentMainIcon = Icon(editor, MAIN_ICON, 12, 24, -72)
    current:SetTextColor(0.7, 0.7, 0.65)
    local main = CreateFrame("CheckButton", nil, editor, "UICheckButtonTemplate")
    main:SetSize(24, 24)
    main:SetPoint("TOPLEFT", editor, "TOPLEFT", 22, -93)
    Icon(editor, MAIN_ICON, 13, 50, -98)
    Label(editor, "This character is my main", 68, -99, 312)
    main:SetScript("OnEnter", function(self)
        Tooltip(self, "Main character", "Shared with this guild. Selecting this character replaces your previous main on this WoW account.")
    end)
    main:SetScript("OnLeave", HideTooltip)
    Icon(editor, DISCORD_ICON, 12, 24, -128)
    Label(editor, "Discord server nickname (shared with guild)", 42, -128, 356)
    local discord = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    discord:SetSize(288, 24)
    discord:SetPoint("TOPLEFT", editor, "TOPLEFT", 28, -148)
    discord:SetAutoFocus(false)
    discord:SetMaxLetters(32)
    discord:SetTextInsets(5, 5, 2, 2)
    local save = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    save:SetSize(72, 24)
    save:SetPoint("LEFT", discord, "RIGHT", 8, 0)
    save:SetText("Save")
    local status = Label(editor, "", 24, -187, 374)
    local close = CreateFrame("Button", nil, editor, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -4, -4)
    local function Discard()
        dirty, formMessage = false, ""
        discord:ClearFocus()
        editor:Hide()
        shade:Hide()
        view.Refresh()
    end
    close:SetScript("OnClick", Discard)
    discord:SetScript("OnEscapePressed", Discard)
    editor:SetScript("OnKeyDown", function(self, key)
        local escape = addon.Compat.IsReadable(key) and key == "ESCAPE"
        addon.Compat.Call(self.SetPropagateKeyboardInput, self, not escape)
        if escape then Discard() end
    end)
    local function Edited()
        dirty, formMessage = true, "Unsaved changes"
        status:SetText(formMessage)
        save:SetEnabled(true)
    end
    main:SetScript("OnClick", Edited)
    discord:SetScript("OnTextChanged", function(_, userInput) if userInput then Edited() end end)
    local function Save()
        local succeeded, reason = addon.Members.Save(main:GetChecked() == true, discord:GetText())
        if succeeded then dirty = false; discord:ClearFocus() end
        formMessage = reason
        view.Refresh()
    end
    save:SetScript("OnClick", Save)
    discord:SetScript("OnEnterPressed", Save)
    local function OpenProfile()
        view.Refresh()
        addon.Compat.Call(editor.SetPropagateKeyboardInput, editor, true)
        shade:Show()
        editor:Show()
    end
    profile:SetScript("OnClick", OpenProfile)
    setup:SetScript("OnClick", OpenProfile)
    editor:Hide()
    mains:SetScript("OnClick", function() view.mainsOnly = true; view.statsPage = 1; view.Refresh() end)
    everyone:SetScript("OnClick", function() view.mainsOnly = false; view.statsPage = 1; view.Refresh() end)
    local function RenderRows(matches, firstIndex)
        for index, row in ipairs(view.rows) do
            local memberIndex = firstIndex + index - 1
            local member = matches[memberIndex]
            row.member = member
            if member then
                local style = CLASS_STYLE[member.classFile] or { 0.9, 0.85, 0.65 }
                row.name:SetText(Bare(member.name))
                row.name:SetTextColor(style[1], style[2], style[3])
                local presence = {}
                if member.state == "Main" or member.state == "Alt" then presence[#presence + 1] = member.state end
                if member.online ~= true then presence[#presence + 1] = member.online == false and "Offline" or "Status unknown" end
                if member.level then presence[#presence + 1] = tostring(member.level) end
                row.presence:SetText(table.concat(presence, " / "))
                row.className:SetText(member.className)
                row.race:SetText(member.race)
                row.role:SetText(member.rank and member.rank ~= "" and member.rank or "Unknown")
                row.spec:SetText(member.spec == "Spec unknown" and "Unknown" or member.spec)
                local points = {}
                for spent in member.talents:gmatch(": (%d+)") do points[#points + 1] = spent end
                row.report:SetText(#points > 0 and table.concat(points, " / ") or "-")
                row.identity:SetText(member.main and Bare(member.main) or "No main selected")
                row.identity:ClearAllPoints()
                if member.main then
                    row.mainIcon:Show()
                    row.identity:SetPoint("TOPLEFT", row, "TOPLEFT", 541, -5)
                    row.identity:SetWidth(102)
                else
                    row.mainIcon:Hide()
                    row.identity:SetPoint("TOPLEFT", row, "TOPLEFT", 525, -5)
                    row.identity:SetWidth(118)
                end
                row.identity:SetTextColor(member.state == "Main" and 0.95 or 0.7, member.state == "Main" and 0.8 or 0.7,
                    member.state == "Main" and 0.35 or 0.65)
                row.contact:SetText(member.discord ~= "" and member.discord or "-")
                row.contact:ClearAllPoints()
                if member.discord ~= "" then
                    row.discordIcon:Show()
                    row.contact:SetPoint("TOPLEFT", row, "TOPLEFT", 541, -22)
                    row.contact:SetWidth(102)
                else
                    row.discordIcon:Hide()
                    row.contact:SetPoint("TOPLEFT", row, "TOPLEFT", 525, -22)
                    row.contact:SetWidth(118)
                end
                ClassIcon(row.icon, member.classFile)
                addon.Compat.Call(row.icon.SetDesaturated, row.icon, false)
                row:SetAlpha(1)
                if member.online == true then
                    row.background:SetColorTexture(0.025, 0.065, 0.035, memberIndex % 2 == 0 and 0.52 or 0.38)
                    row.statusDot:SetVertexColor(0.35, 0.9, 0.45, 1)
                    row.presence:SetTextColor(0.5, 0.85, 0.56)
                elseif member.online == false then
                    row.background:SetColorTexture(0.19, 0.19, 0.19, memberIndex % 2 == 0 and 0.72 or 0.58)
                    row.statusDot:SetVertexColor(0.55, 0.55, 0.55, 1)
                    row.presence:SetTextColor(0.64, 0.64, 0.64)
                    row.name:SetTextColor(0.7, 0.7, 0.7)
                    row.identity:SetTextColor(0.68, 0.68, 0.68)
                else
                    row.background:SetColorTexture(0.1, 0.085, 0.045, memberIndex % 2 == 0 and 0.45 or 0.3)
                    row.statusDot:SetVertexColor(0.9, 0.7, 0.3, 1)
                    row.presence:SetTextColor(0.83, 0.72, 0.43)
                end
                for _, text in ipairs({ row.className, row.role, row.spec }) do
                    if member.online == false then text:SetTextColor(0.65, 0.65, 0.65)
                    else text:SetTextColor(0.9, 0.89, 0.84) end
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(firstIndex + index - 2) * ROW_HEIGHT)
                row:Show()
            else row:Hide() end
        end
    end
    local cachedMatches, updatingScroll = {}, false
    function view.ScrollTo(offset)
        if not addon.Compat.IsReadable(offset) or type(offset) ~= "number" or offset ~= offset then return end
        local maximum = math.max(0, (#cachedMatches - VISIBLE_ROWS) * ROW_HEIGHT)
        view.scrollOffset = math.max(0, math.min(offset, maximum))
        updatingScroll = true
        scroll:SetVerticalScroll(view.scrollOffset)
        updatingScroll = false
        HideTooltip()
        local firstIndex = math.floor(view.scrollOffset / ROW_HEIGHT) + 1
        RenderRows(cachedMatches, firstIndex)
        local lastIndex = math.min(#cachedMatches, math.ceil((view.scrollOffset + VISIBLE_ROWS * ROW_HEIGHT) / ROW_HEIGHT))
        visibleRange:SetText(#cachedMatches > 0 and (firstIndex .. "-"
            .. lastIndex .. " / " .. #cachedMatches) or "0 / 0")
    end
    local function Scrolled(_, offset)
        if not updatingScroll then view.ScrollTo(offset) end
    end
    if type(scroll.HookScript) == "function" then scroll:HookScript("OnVerticalScroll", Scrolled)
    else scroll:SetScript("OnVerticalScroll", Scrolled) end
    addon.Compat.Call(scroll.EnableMouseWheel, scroll, true)
    local function MouseWheel(_, delta)
        if not addon.Compat.IsReadable(delta) or type(delta) ~= "number" or delta ~= delta
            or delta < -100 or delta > 100 then return end
        view.ScrollTo(view.scrollOffset - delta * ROW_HEIGHT * 3)
    end
    scroll:SetScript("OnMouseWheel", MouseWheel)
    for _, row in ipairs(view.rows) do
        addon.Compat.Call(row.EnableMouseWheel, row, true)
        row:SetScript("OnMouseWheel", MouseWheel)
    end
    function view.Refresh()
        if not addon.Members then return end
        local settings, name = addon.Members.Settings(), addon.Members.Self()
        local allowed = not addon.Members.CanView or addon.Members.CanView()
        local rows = addon.Members.Rows()
        local stats = addon.Members.Stats(view.mainsOnly, rows)
        local classFiles = {}
        for classFile in pairs(CLASS_STYLE) do
            local localized = addon.Compat.Field(LOCALIZED_CLASS_NAMES_MALE, classFile)
            local name = type(localized) == "string" and localized or classFile:sub(1, 1) .. classFile:sub(2):lower()
            classFiles[name] = classFile
        end
        for _, member in ipairs(rows) do
            if CLASS_STYLE[member.classFile] then classFiles[member.className] = member.classFile end
        end
        if not dirty then
            main:SetChecked(settings and settings.main == name or false)
            discord:SetText(settings and settings.discord or "")
        end
        main:SetEnabled(settings ~= nil)
        if settings then discord:Enable() else discord:Disable() end
        save:SetEnabled(settings ~= nil and dirty)
        status:SetText(formMessage)
        editorName:SetText(Bare(name))
        current:SetText("Main: " .. (settings and settings.main ~= "" and Bare(settings.main) or "No main selected"))
        current:ClearAllPoints()
        if settings and settings.main ~= "" then
            currentMainIcon:Show()
            current:SetPoint("TOPLEFT", editor, "TOPLEFT", 42, -72)
            current:SetWidth(354)
        else
            currentMainIcon:Hide()
            current:SetPoint("TOPLEFT", editor, "TOPLEFT", 24, -72)
            current:SetWidth(372)
        end
        profileSummary:SetText(Bare(name) .. (settings and settings.main == name and ("  |T" .. MAIN_ICON .. ":12:12|t") or ""))
        mains:SetChecked(view.mainsOnly)
        everyone:SetChecked(not view.mainsOnly)
        coverage:SetText(stats.total .. " counted / " .. stats.all .. " characters")
        for key, tab in pairs(statTabs) do
            local selected = key == view.category
            tab.label:SetTextColor(selected and 1 or 0.68, selected and 0.82 or 0.68, selected and 0.3 or 0.64)
            if selected then tab.line:Show() else tab.line:Hide() end
        end
        local counts, names = stats[view.category], {}
        for label in pairs(counts) do names[#names + 1] = label end
        table.sort(names, function(left, right)
            if counts[left] ~= counts[right] then return counts[left] > counts[right] end
            return left:lower() < right:lower()
        end)
        local statPages = math.max(1, math.ceil(#names / 9))
        view.statsPage = math.max(1, math.min(statPages, view.statsPage))
        for index, cell in ipairs(view.statRows) do
            local label = names[(view.statsPage - 1) * 9 + index]
            if label then
                local count = counts[label]
                local classFile = classFiles[label] or classFiles[label:match("^(.-): ")]
                local style = CLASS_STYLE[classFile] or { 0.78, 0.68, 0.42 }
                cell.statName, cell.statCount, cell.population = label, count, stats.total
                cell.percentage = stats.total > 0 and string.format("%.1f%%", count * 100 / stats.total) or "-"
                cell.label:SetText(label)
                cell.count:SetText(count .. " (" .. cell.percentage .. ")")
                cell.label:SetTextColor(count > 0 and 0.92 or 0.52, count > 0 and 0.91 or 0.52, count > 0 and 0.83 or 0.49)
                local offset = view.category == "races" and 0 or 27
                cell.label:ClearAllPoints()
                cell.label:SetPoint("TOPLEFT", cell, "TOPLEFT", offset, 0)
                cell.label:SetWidth(119 - offset)
                if view.category == "races" then cell.icon:Hide()
                else ClassIcon(cell.icon, classFile); cell.icon:Show() end
                for _, texture in ipairs({ cell.track, cell.bar }) do
                    texture:ClearAllPoints()
                    texture:SetPoint("TOPLEFT", cell, "TOPLEFT", offset, -18)
                end
                cell.track:SetWidth(206 - offset)
                cell.bar:SetColorTexture(style[1], style[2], style[3], 0.9)
                cell.bar:SetWidth(math.max(1, (206 - offset) * count / math.max(1, stats.total)))
                if count > 0 then cell.bar:Show() else cell.bar:Hide() end
                cell:Show()
            else cell:Hide() end
        end
        statsEmpty:SetText(view.category == "classes" and "No class reports" or "No reports in this selection")
        if #names == 0 then statsEmpty:Show() else statsEmpty:Hide() end
        if statPages > 1 then statsPrevious:Show(); statsNext:Show() else statsPrevious:Hide(); statsNext:Hide() end
        statsPrevious:SetEnabled(view.statsPage > 1)
        statsNext:SetEnabled(view.statsPage < statPages)
        local matches, needle = {}, (filter:GetText() or ""):lower()
        if needle == "" then placeholder:Show() else placeholder:Hide() end
        for _, member in ipairs(rows) do
            local text = table.concat({ member.name, member.className, member.race, member.state,
                member.main or "", member.spec, member.discord, member.rank or "" }, " "):lower()
            if text:find(needle, 1, true) then matches[#matches + 1] = member end
        end
        table.sort(matches, function(left, right)
            if view.sortKey then
                local leftValue, rightValue = SortValue(left, view.sortKey), SortValue(right, view.sortKey)
                if (leftValue == nil) ~= (rightValue == nil) then return leftValue ~= nil end
                if leftValue ~= rightValue then
                    if view.sortAscending then return leftValue < rightValue end
                    return leftValue > rightValue
                end
                return left.name:lower() < right.name:lower()
            end
            if (left.online == true) ~= (right.online == true) then return left.online == true end
            return left.name:lower() < right.name:lower()
        end)
        for key, button in pairs(sortHeaders) do
            if key == view.sortKey then
                button.indicator:SetTexCoord(0, 1, view.sortAscending and 0 or 1, view.sortAscending and 1 or 0)
                button.indicator:Show()
            else button.indicator:Hide() end
        end
        cachedMatches = matches
        updatingScroll = true
        content:SetHeight(math.max(VISIBLE_ROWS * ROW_HEIGHT, #matches * ROW_HEIGHT))
        updatingScroll = false
        view.ScrollTo(view.scrollOffset)
        empty:SetText(settings and "No matching characters" or "Waiting for a complete readable guild roster")
        if #matches == 0 then empty:Show() else empty:Hide() end
        directoryCount:SetText(#matches .. " characters" .. (stats.unassigned > 0 and (" / " .. stats.unassigned .. " without a main") or ""))
        if allowed then page:Show(); locked:Hide() else page:Hide(); locked:Show() end
        setup:SetEnabled(settings ~= nil)
        requirements:SetText(settings and "Main character and Discord server nickname must both be saved."
            or "Waiting for a complete readable guild roster.")
        if not allowed then HideTooltip() end
        if addon.db.canvasTab == "guild" and not allowed then
            header:SetText("Guild profile")
            subheader:SetText("Main character and Discord server nickname required")
        elseif addon.db.canvasTab == "guild" then
            header:SetText("Guild overview")
            subheader:SetText(stats.mains .. " mains / " .. stats.all .. " characters - " .. stats.unassigned .. " no main selected")
        end
    end
    host:SetScript("OnShow", function() view.Refresh() end)
    host:SetScript("OnHide", function() editor:Hide(); shade:Hide(); HideTooltip() end)
    addon.RefreshGuild = view.Refresh
    view.main, view.discord, view.save = main, discord, save
    view.profile, view.editor, view.close, view.shade = profile, editor, close, shade
    view.body, view.locked, view.setup, view.directoryCount = page, locked, setup, directoryCount
    view.mains, view.everyone, view.filter = mains, everyone, filter
    view.scroll, view.content, view.visibleRange = scroll, content, visibleRange
    view.coverage, view.status = coverage, status
    view.statTabs, view.statsNext, view.statsPrevious = statTabs, statsNext, statsPrevious
    view.sortHeaders = sortHeaders
    view.Refresh()
    return view
end