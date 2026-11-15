local addonName, addon = ...
local databaseName = addonName .. "DB"
local characterDatabaseName = addonName .. "CharacterDB"
local slashKey = string.upper(addonName)
local frame = CreateFrame("Frame")

addon.databaseStatus = "not initialized"
addon.initialized = false

local function InitializeDatabase()
    local database = _G[databaseName]
    if database == nil then
        database = { schemaVersion = 1 }
        _G[databaseName] = database
    end
    if type(database) ~= "table" or database.schemaVersion ~= 1 then
        addon.databaseStatus = "incompatible; existing data preserved"
        return
    end
    if database.minimapPositionVersion == nil then
        if database.minimapPos == nil or database.minimapPos == 225 then
            database.minimapPos = 315
        end
        database.minimapPositionVersion = 1
    end
    if type(database.minimapPos) ~= "number" or database.minimapPos ~= database.minimapPos
        or math.abs(database.minimapPos) > 360 then
        database.minimapPos = 315
    end
    local characterDatabase = _G[characterDatabaseName]
    if characterDatabase == nil then
        characterDatabase = { schemaVersion = 1 }
        _G[characterDatabaseName] = characterDatabase
    end
    if type(characterDatabase) ~= "table" or characterDatabase.schemaVersion ~= 1 then
        addon.databaseStatus = "incompatible character data; existing data preserved"
        return
    end
    database.catalog = nil
    addon.characterDB = characterDatabase
    addon.db = database
    addon.Catalog.scannedThisSession = false
    addon.Catalog.Initialize()
    addon.databaseStatus = "ready (schema 1)"
    addon.initialized = true
end

function addon.HideGuildUI()
    if addon.guildActive and addon.LogEvent then addon.LogEvent("ACCESS_PAUSED") end
    addon.guildActive = false
    if addon.minimapButton then
        addon.minimapButton:SetScript("OnUpdate", nil)
        addon.minimapButton:Hide()
    end
    if addon.HideCanvas then addon.HideCanvas() end
    if addon.Diagnostics then addon.Diagnostics.HideWindow() end
    if addon.GuildMap and addon.GuildMap.Hide then addon.GuildMap.Hide() end
    if addon.Catalog.Pause then addon.Catalog.Pause() end
    addon.Catalog.scannedThisSession = false
end

function addon.RefreshGuildAccess()
    if not addon.initialized or not addon.GuildState then return end
    if not addon.GuildState.CheckContext() then addon.HideGuildUI(); return end
    if not addon.guildActive then
        addon.guildActive = true
        if addon.LogEvent then addon.LogEvent("ACCESS_ENABLED") end
        addon.CreateMinimapButton()
        local scanned = addon.Catalog.Scan()
        addon.Sync.Start(scanned ~= nil)
        addon.Catalog.Start()
        if addon.Members then addon.Members.Start() end
        if addon.GuildMap then addon.GuildMap.Start() end
        addon.Print("Ready.")
    end
    if addon.minimapButton then addon.minimapButton:Show() end
end

_G["SLASH_" .. slashKey .. "1"] = "/" .. string.lower(addonName)
SlashCmdList[slashKey] = function(message)
    if not addon.GuildState or not addon.GuildState.IsAllowed() then
        addon.HideGuildUI()
        return
    end
    local command = string.lower(message or ""):match("^%s*(.-)%s*$")
    if command == "report" then
        addon.Report()
    elseif command == "admin" then
        addon.Print("Application role: " .. addon.GuildState.AdminStatus())
    elseif command == "professions" then
        addon.ShowProfessionCorrection(true)
    elseif command == "logs" then
        addon.Diagnostics.ToggleWindow()
    elseif command == "logs clear" then
        addon.Diagnostics.Clear()
    elseif command == "logs trace on" or command == "logs trace off" then
        addon.Diagnostics.SetTrace(command == "logs trace on")
    elseif command == "library" then
        for _, line in ipairs(addon.Catalog.LibraryReport()) do addon.Print(line) end
    elseif command == "scan" then
        local scanned, learned, reason = addon.Catalog.Scan()
        if scanned then
            if reason then addon.Print(reason .. ". Recipe sharing paused.")
            else addon.Print("Scanned " .. scanned .. " recipes; " .. learned .. " learned.") end
            if addon.Catalog.scannedThisSession and addon.Catalog.Initialize().shareEnabled then
                addon.Sync.Publish()
            end
        else
            addon.Print("Recipe scan unavailable: " .. reason .. ".")
        end
    elseif command == "share on" then
        if addon.Sync.SetSharing(true) then
            addon.Print("Recipe sharing enabled. Guild delivery is not confirmed by the send API.")
        else
            addon.Print("Recipe sharing could not be enabled.")
        end
    elseif command == "share off" then
        addon.Sync.SetSharing(false)
        addon.Print("Recipe sharing disabled. Profiles already received by guildmates cannot be recalled.")
    elseif command == "sync" then
        addon.Sync.Request()
        addon.Print(addon.Sync.status)
    elseif command == "resetcrafting" or command == "resetcrafting confirm" then
        addon.Sync.ResetCrafting(command == "resetcrafting confirm")
        addon.Print(addon.Sync.status)
    else
        addon.ToggleCanvas()
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon == addonName then
        InitializeDatabase()
        if addon.LogEvent then addon.LogEvent(addon.initialized and "DATABASE_READY" or "DATABASE_UNAVAILABLE") end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if addon.initialized then
            if addon.GuildState then addon.GuildState.Start() end
            addon.RefreshGuildAccess()
        elseif addon.GuildState and addon.GuildState.IsAllowed() then
            addon.Print("Database unavailable; diagnostics remain available.")
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)