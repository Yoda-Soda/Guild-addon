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

_G["SLASH_" .. slashKey .. "1"] = "/" .. string.lower(addonName)
SlashCmdList[slashKey] = function(message)
    local command = string.lower(message or ""):match("^%s*(.-)%s*$")
    if command == "report" then
        addon.Report()
    elseif command == "library" then
        for _, line in ipairs(addon.Catalog.LibraryReport()) do addon.Print(line) end
    elseif command == "scan" then
        local scanned, learned, reason = addon.Catalog.Scan()
        if scanned then
            addon.Print("Scanned " .. scanned .. " recipes; " .. learned .. " learned.")
            if addon.Catalog.Initialize().shareEnabled then
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
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if addon.initialized then
            addon.CreateMinimapButton()
            if addon.GuildState then addon.GuildState.Start() end
            local scanned = addon.Catalog.Scan()
            addon.Sync.Start(scanned ~= nil)
            if addon.Members then addon.Members.Start() end
            addon.Print("Ready.")
        else
            addon.Print("Database unavailable; diagnostics remain available.")
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)