local addonName, addon = ...
local databaseName = addonName .. "DB"
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
    if type(database.minimapPos) ~= "number" or database.minimapPos ~= database.minimapPos
        or math.abs(database.minimapPos) > 360 then
        database.minimapPos = 225
    end
    addon.db = database
    addon.databaseStatus = "ready (schema 1)"
    addon.initialized = true
end

_G["SLASH_" .. slashKey .. "1"] = "/" .. string.lower(addonName)
SlashCmdList[slashKey] = function(message)
    if string.lower(message or "") == "report" then
        addon.Report()
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
            addon.Print("Ready.")
        else
            addon.Print("Database unavailable; diagnostics remain available.")
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)