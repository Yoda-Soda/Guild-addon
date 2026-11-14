local _, addon = ...
local Compat = addon.Compat
local Diagnostics = { traceEnabled = false }
addon.Diagnostics = Diagnostics
local entries = {}
local MAX_ENTRIES = 200
local eventDefinitions = {
    DATABASE_READY = { level = "INFO", text = "Database initialized" },
    DATABASE_UNAVAILABLE = { level = "ERROR", text = "Database initialization unavailable" },
    ACCESS_ENABLED = { level = "INFO", text = "Guild access enabled" },
    ACCESS_PAUSED = { level = "WARN", text = "Guild access paused" },
    ROSTER_UNAVAILABLE = { level = "WARN", text = "Complete readable roster unavailable", fields = {
        { name = "reason", values = { count = true, row = true, identity = true } }, { name = "row" },
    } },
    SCAN_STARTED = { level = "INFO", text = "Recipe scan started", trace = true },
    SCAN_UNAVAILABLE = { level = "WARN", text = "Recipe scan unavailable", fields = {
        { name = "reason", values = { access = true, api = true, source = true, list = true, limit = true } },
    } },
    SCAN_COMPLETE = { level = "INFO", text = "Recipe scan complete", fields = {
        { name = "scanned" }, { name = "learned" }, { name = "unavailable" },
    } },
    SCAN_INCOMPLETE = { level = "WARN", text = "Recipe scan incomplete; publication blocked", fields = {
        { name = "scanned" }, { name = "learned" }, { name = "unavailable" },
    } },
    SEND_UNAVAILABLE = { level = "ERROR", text = "Addon message send unavailable", fields = {
        { name = "state", values = { missing = true, error = true, unavailable = true } },
    } },
    SEND_REJECTED = { level = "ERROR", text = "Addon message send rejected or unconfirmed", fields = {
        { name = "result" },
    } },
    SEND_ACCEPTED = { level = "INFO", text = "Send accepted; receipt not confirmed", trace = true, fields = {
        { name = "bytes" },
    } },
    COMM_UNAVAILABLE = { level = "WARN", text = "Addon message APIs or prefix unavailable" },
    QUEUE_REJECTED = { level = "WARN", text = "Sync queue rejected a transfer", fields = {
        { name = "queued" }, { name = "bytes" },
    } },
    PROFILE_RECEIVED = { level = "INFO", text = "Recipe profile received", fields = { { name = "recipes" } } },
    PROFILE_REJECTED = { level = "WARN", text = "Recipe profile rejected", fields = {
        { name = "direction", values = { send = true, receive = true } },
        { name = "reason", values = { format = true, limit = true, stale = true } },
    } },
    PUBLISH_BLOCKED = { level = "WARN", text = "Recipe publication blocked", fields = {
        { name = "reason", values = { sharing = true, scan = true } },
    } },
    TRANSFER_CHUNK = { level = "INFO", text = "Recipe transfer chunk received", trace = true, fields = {
        { name = "part" }, { name = "total" }, { name = "bytes" },
    } },
    MESSAGE_REJECTED = { level = "WARN", text = "Guild message rejected", trace = true, fields = {
        { name = "reason", values = { format = true, sender = true, scope = true, generation = true, rate = true } },
    } },
    RESET_APPLIED = { level = "INFO", text = "Crafting reset applied", fields = { { name = "generation" } } },
    MEMBER_QUEUE_REJECTED = { level = "WARN", text = "Member profile could not be queued" },
}

function addon.LogEvent(code, fields)
    if not Compat.IsReadable(code) or type(code) ~= "string" then return false end
    local definition = eventDefinitions[code]
    if not definition or (definition.trace and not Diagnostics.traceEnabled) then return false end
    if not Compat.IsReadable(fields) then return false end
    if fields ~= nil and (type(fields) ~= "table"
        or (type(canaccesstable) == "function" and not canaccesstable(fields))) then return false end
    local parts = {}
    for _, field in ipairs(definition.fields or {}) do
        local value = fields and fields[field.name]
        if Compat.IsReadable(value) then
            if field.values then
                if type(value) == "string" and field.values[value] then
                    parts[#parts + 1] = field.name .. "=" .. value
                end
            elseif type(value) == "number" and value == value and value >= 0
                and value <= 2147483647 and value == math.floor(value) then
                parts[#parts + 1] = field.name .. "=" .. tostring(value)
            end
        end
    end
    local detail = table.concat(parts, " ")
    local stamp = Compat.Value(GetTime)
    if type(stamp) ~= "number" or stamp ~= stamp or stamp < 0 or stamp > 2147483647 then stamp = 0 end
    local previous = entries[#entries]
    if previous and previous.code == code and previous.detail == detail
        and stamp >= previous.updatedAt and stamp - previous.updatedAt <= 5 then
        previous.updatedAt = stamp
        previous.repeats = math.min(previous.repeats + 1, 2147483647)
    else
        if #entries >= MAX_ENTRIES then table.remove(entries, 1) end
        entries[#entries + 1] = { code = code, detail = detail, updatedAt = stamp, repeats = 1 }
    end
    if Diagnostics.Refresh then Diagnostics.Refresh() end
    return true
end

function Diagnostics.Clear()
    entries = {}
    if Diagnostics.Refresh then Diagnostics.Refresh() end
end

function Diagnostics.Count()
    return #entries
end

function Diagnostics.SetTrace(enabled)
    if not Compat.IsReadable(enabled) or type(enabled) ~= "boolean" then return false end
    Diagnostics.traceEnabled = enabled
    if Diagnostics.Refresh then Diagnostics.Refresh() end
    return true
end

function Diagnostics.Lines(filter)
    if not Compat.IsReadable(filter) or (filter ~= "WARN" and filter ~= "ERROR") then filter = nil end
    local lines = {}
    for _, entry in ipairs(entries) do
        local definition = eventDefinitions[entry.code]
        if not filter or definition.level == filter or (filter == "WARN" and definition.level == "ERROR") then
            lines[#lines + 1] = string.format("[%0.1fs] %s %s: %s%s%s", entry.updatedAt,
                definition.level, entry.code, definition.text, entry.detail ~= "" and " " .. entry.detail or "",
                entry.repeats > 1 and " (x" .. entry.repeats .. ")" or "")
        end
    end
    return lines
end

local function Allowed()
    return addon.GuildState and type(addon.GuildState.IsAllowed) == "function" and addon.GuildState.IsAllowed()
end

function Diagnostics.ReportText(filter)
    if not Compat.IsReadable(filter) or (filter ~= "WARN" and filter ~= "ERROR") then filter = nil end
    local build = Compat.Call(GetBuildInfo)
    local lines = {
        "Horde Eternal diagnostics - current session",
        "Version=" .. Compat.SafeText(build and build[2]) .. " build=" .. Compat.SafeText(build and build[3])
            .. " interface=" .. Compat.SafeText(build and build[5]) .. " project=" .. Compat.SafeText(WOW_PROJECT_ID),
        "Database=" .. (addon.initialized and "ready" or "unavailable")
            .. " guildAccess=" .. (Allowed() and "allowed" or "unavailable"),
        "ApplicationRole=" .. (addon.GuildState and addon.GuildState.AdminStatus and addon.GuildState.AdminStatus()
            or "Admin status unavailable"),
        "FreshRecipeScan=" .. (addon.Catalog and addon.Catalog.scannedThisSession and "yes" or "no")
            .. " records=" .. #entries .. "/" .. MAX_ENTRIES
            .. " filter=" .. (filter == "ERROR" and "errors" or filter == "WARN" and "warnings+errors" or "all")
            .. " detailed=" .. (Diagnostics.traceEnabled and "on" or "off"),
        "",
    }
    local records = Diagnostics.Lines(filter)
    if #records == 0 then records[1] = "No matching events." end
    for _, line in ipairs(records) do lines[#lines + 1] = line end
    return table.concat(lines, "\n"), #lines
end

function Diagnostics.HideWindow()
    if Diagnostics.window then
        Diagnostics.window:StopMovingOrSizing()
        Diagnostics.window.edit:ClearFocus()
        Diagnostics.window:Hide()
    end
end

function Diagnostics.Refresh(force)
    local window = Diagnostics.window
    if not window or not window:IsShown() then return end
    if not Allowed() then Diagnostics.HideWindow(); return end
    if not force and Compat.Value(window.edit.HasFocus, window.edit) == true then return end
    local text, lines = Diagnostics.ReportText(window.filter)
    window.edit:SetText(text)
    window.edit:SetHeight(math.max(280, lines * 28))
    window.trace:SetChecked(Diagnostics.traceEnabled)
    for _, button in ipairs(window.filters) do
        if button.filter == window.filter then button:LockHighlight() else button:UnlockHighlight() end
    end
end

local function CreateLogWindow()
    if Diagnostics.window then return Diagnostics.window end
    local ok, window = pcall(CreateFrame, "Frame", "HordeEternalDiagnostics", UIParent, "BasicFrameTemplateWithInset")
    if not ok or not window then window = CreateFrame("Frame", "HordeEternalDiagnosticsBasic", UIParent) end
    Diagnostics.window = window
    window:SetSize(680, 420)
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
    if window.TitleText then window.TitleText:SetText("Horde Eternal diagnostics")
    else
        local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -12)
        title:SetPoint("TOPRIGHT", window, "TOPRIGHT", -36, -12)
        title:SetJustifyH("LEFT")
        title:SetText("Horde Eternal diagnostics")
    end
    local close = window.CloseButton or CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", Diagnostics.HideWindow)
    local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -70)
    scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -34, 16)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetMaxLetters(60000)
    edit:SetWidth(630)
    edit:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    edit:SetScript("OnEscapePressed", Diagnostics.HideWindow)
    scroll:SetScrollChild(edit)
    window.edit, window.scroll = edit, scroll
    window.filters = {}
    local offset = 16
    for _, definition in ipairs({ { text = "All", width = 60 }, { text = "Warnings", filter = "WARN", width = 90 },
        { text = "Errors", filter = "ERROR", width = 60 } }) do
        local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        button:SetSize(definition.width, 22)
        button:SetPoint("TOPLEFT", window, "TOPLEFT", offset, -36)
        button:SetText(definition.text)
        button.filter = definition.filter
        button:SetScript("OnClick", function()
            edit:ClearFocus()
            window.filter = button.filter
            scroll:SetVerticalScroll(0)
            Diagnostics.Refresh(true)
        end)
        window.filters[#window.filters + 1] = button
        offset = offset + definition.width + 4
    end
    local trace = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
    trace:SetSize(22, 22)
    trace:SetPoint("TOPLEFT", window, "TOPLEFT", 264, -36)
    local traceLabel = trace:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    traceLabel:SetPoint("LEFT", trace, "RIGHT", 2, 0)
    traceLabel:SetText("Detailed")
    trace:SetScript("OnClick", function() Diagnostics.SetTrace(trace:GetChecked() == true) end)
    window.trace = trace
    local selectAll = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    selectAll:SetSize(96, 22)
    selectAll:SetPoint("TOPRIGHT", window, "TOPRIGHT", -86, -36)
    selectAll:SetText("Select All")
    selectAll:SetScript("OnClick", function()
        Diagnostics.Refresh(true)
        edit:SetFocus()
        edit:HighlightText()
    end)
    window.selectAll = selectAll
    local clear = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    clear:SetSize(66, 22)
    clear:SetPoint("TOPRIGHT", window, "TOPRIGHT", -16, -36)
    clear:SetText("Clear")
    clear:SetScript("OnClick", function() edit:ClearFocus(); Diagnostics.Clear(); Diagnostics.Refresh(true) end)
    window.clear = clear
    local function FitWindow()
        local width, height = Compat.Value(UIParent.GetWidth, UIParent), Compat.Value(UIParent.GetHeight, UIParent)
        if type(width) == "number" and width > 0 and type(height) == "number" and height > 0 then
            window:SetScale(math.min(1, width / 700, height / 440))
        end
    end
    window:SetScript("OnShow", function() FitWindow(); Diagnostics.Refresh(true) end)
    window:SetScript("OnHide", function() edit:ClearFocus() end)
    window:SetScript("OnEvent", function() FitWindow() end)
    Compat.Call(window.RegisterEvent, window, "UI_SCALE_CHANGED")
    Compat.Call(window.RegisterEvent, window, "DISPLAY_SIZE_CHANGED")
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = window:GetName() end
    FitWindow()
    window:Hide()
    return window
end

function Diagnostics.ToggleWindow()
    if not Allowed() then Diagnostics.HideWindow(); return end
    local window = CreateLogWindow()
    if window:IsShown() then Diagnostics.HideWindow()
    else window:Show(); Diagnostics.Refresh(true) end
end

local capabilities = {
    "GetBuildInfo",
    "issecretvalue",
    "canaccessvalue",
    "canaccesstable",
    "C_Spell.GetSpellInfo",
    "C_Spell.GetSpellCooldown",
    "C_SpellBook.IsSpellKnown",
    "C_UnitAuras.GetAuraDataByIndex",
    "C_Container.GetContainerItemInfo",
    "C_Item.GetItemInfo",
    "C_AddOns.GetScriptsDisallowedForBeta",
    "C_Secrets.HasSecretRestrictions",
    "C_Secrets.ShouldAurasBeSecret",
    "C_Secrets.ShouldCooldownsBeSecret",
    "Settings.RegisterCanvasLayoutCategory",
}

function addon.Print(message)
    print(addon.name .. ": " .. message)
end

function addon.Report()
    addon.Print("Capability report; gameplay behavior is unverified.")
    if Compat.HasFunction("GetBuildInfo") then
        local ok, version, build, buildDate, interface = pcall(GetBuildInfo)
        if ok then
            addon.Print("Version=" .. Compat.SafeText(version)
                .. " build=" .. Compat.SafeText(build)
                .. " date=" .. Compat.SafeText(buildDate)
                .. " interface=" .. Compat.SafeText(interface))
        else
            addon.Print("GetBuildInfo failed; error content not logged.")
        end
    end
    addon.Print("Project ID=" .. Compat.SafeText(WOW_PROJECT_ID)
        .. " (not a reliable flavor discriminator)")
    addon.Print("Database=" .. addon.databaseStatus)
    if addon.GuildState and addon.GuildState.AdminStatus then
        addon.Print("Application role: " .. addon.GuildState.AdminStatus())
    end
    for _, path in ipairs(capabilities) do
        addon.Print(path .. "=" .. (Compat.HasFunction(path) and "present" or "missing/unavailable"))
    end
end