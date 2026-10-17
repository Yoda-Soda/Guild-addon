local _, addon = ...

local Catalog = {}
addon.Catalog = Catalog

local MAX_RECIPE_IDS = 5000
local MAX_SEARCH_RESULTS = 100
local PAGE_SIZE = 50

local professionDefinitions = {
    { id = 171, name = "Alchemy", icon = "Trade_Alchemy" },
    { id = 164, name = "Blacksmithing", icon = "Trade_BlackSmithing" },
    { id = 185, name = "Cooking", icon = "INV_Misc_Food_15" },
    { id = 333, name = "Enchanting", icon = "Trade_Engraving" },
    { id = 202, name = "Engineering", icon = "Trade_Engineering" },
    { id = 129, name = "First Aid", icon = "Spell_Holy_SealOfSacrifice" },
    { id = 356, name = "Fishing", icon = "Trade_Fishing", gathering = true },
    { id = 182, name = "Herbalism", icon = "Trade_Herbalism", gathering = true },
    { id = 165, name = "Leatherworking", icon = "Trade_LeatherWorking" },
    { id = 186, name = "Mining", icon = "Trade_Mining" },
    { id = 393, name = "Skinning", icon = "INV_Misc_Pelt_Wolf_01", gathering = true },
    { id = 197, name = "Tailoring", icon = "Trade_Tailoring" },
}

local function IsReadableTable(value)
    if type(value) ~= "table" or not addon.Compat.IsReadable(value) then
        return false
    end
    return type(canaccesstable) ~= "function" or canaccesstable(value)
end

local function Field(source, key)
    if not IsReadableTable(source) then
        return nil
    end
    local ok, value = pcall(function()
        return source[key]
    end)
    if not ok or not addon.Compat.IsReadable(value) then
        return nil
    end
    return value
end

local function Call(callback, ...)
    if type(callback) ~= "function" then
        return nil
    end
    local results = addon.Compat.Call(callback, ...)
    return results and results[2] or nil
end

local function OutputName(hyperlink, fallback)
    if type(hyperlink) == "string" then
        local name = hyperlink:match("%[([^%]]+)%]")
        if name and name ~= "" then
            return name
        end
    end
    return fallback
end

local libraryRecipes, cachedLibrary, cachedCount = {}, nil, nil
Catalog.source = "Observed recipes only; LibProfessionDB is not loaded"
Catalog.hasLibrary = false

function Catalog.RefreshLibrary(force)
    local values, lookupState = addon.Compat.Call(Field(LibStub, "GetLibrary"), LibStub, "LibProfessionDB-1.0", true)
    local library = values and values[2]
    local function Unavailable(reason)
        libraryRecipes, cachedLibrary, cachedCount = {}, nil, nil
        Catalog.source, Catalog.hasLibrary = reason, false
        return false
    end
    if not IsReadableTable(library) then
        local reason = not values and ("library lookup " .. lookupState)
            or library == nil and "LibProfessionDB is not registered with LibStub"
            or "LibProfessionDB instance is unreadable or invalid"
        return Unavailable("Observed recipes only; " .. reason)
    end
    if Call(library.GetGameVersion, library) ~= "Forever" then
        return Unavailable("Observed recipes only; LibProfessionDB is not using Forever data")
    end
    local meta = addon.Compat.Call(library.GetMeta, library)
    if Call(library.IsReady, library) ~= true or not meta or meta[3] ~= "Forever" then
        return Unavailable("Observed recipes only; LibProfessionDB data is not ready")
    end
    local count = Call(library.Count, library)
    if type(count) ~= "number" or count < 1 or count > MAX_RECIPE_IDS or count ~= math.floor(count) then
        return Unavailable("Observed recipes only; LibProfessionDB count is unavailable or too large")
    end
    if not force and cachedLibrary == library and cachedCount == count then return true end
    local iterator = Call(library.Iterate, library)
    if type(iterator) ~= "function" then
        return Unavailable("Observed recipes only; LibProfessionDB iterator is unavailable")
    end
    local recipes, names, localizedNames = {}, {}, {}
    for _, profession in ipairs(professionDefinitions) do names[profession.id] = profession.name end
    for index = 1, count + 1 do
        local values = addon.Compat.Call(iterator)
        if not values then return Unavailable("Observed recipes only; LibProfessionDB read failed") end
        local professionID, recipeID, data = values[2], values[3], values[4]
        if professionID == nil then
            if index ~= count + 1 then return Unavailable("Observed recipes only; LibProfessionDB data is incomplete") end
            libraryRecipes, cachedLibrary, cachedCount = recipes, library, count
            Catalog.source, Catalog.hasLibrary = "LibProfessionDB Forever snapshot", true
            return true
        end
        local name = Field(data, "name")
        if type(professionID) ~= "number" or type(recipeID) ~= "number" or recipeID <= 0
            or recipeID ~= math.floor(recipeID) or type(name) ~= "string" then
            return Unavailable("Observed recipes only; LibProfessionDB recipe data is incomplete")
        end
        local itemID, effect = Field(data, "craftedItemId"), Field(data, "effect")
        local professionName = localizedNames[professionID]
        if not professionName then
            local localized = Call(C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName, professionID)
            professionName = type(localized) == "string" and localized or names[professionID] or "Profession"
            localizedNames[professionID] = professionName
        end
        local reagents, sourceReagents = {}, Field(data, "reagents")
        if IsReadableTable(sourceReagents) then
            local reagentCount = 0
            for item, quantity in pairs(sourceReagents) do
                reagentCount = reagentCount + 1
                if reagentCount > 50 then break end
                if addon.Compat.IsReadable(item) and addon.Compat.IsReadable(quantity)
                    and type(item) == "number" and item > 0 and type(quantity) == "number" and quantity > 0 then
                    reagents[item] = quantity
                end
            end
        end
        local availability
        if Call(library.IsHiddenRecipe, library, recipeID) == true then
            availability = Call(library.IsBorrowed, library, recipeID, "hidden") == "Vanilla"
                and "Availability unconfirmed: Vanilla marks this recipe unobtainable."
                or "Marked unobtainable by the recipe database."
        end
        recipes[#recipes + 1] = {
            recipeID = recipeID, recipeSpellID = recipeID, skillLineID = professionID,
            recipeName = name, itemName = name,
            professionName = professionName,
            itemID = type(itemID) == "number" and itemID > 0 and itemID or nil,
            effect = type(effect) == "string" and effect or nil,
            reagents = reagents, availability = availability,
        }
    end
    return Unavailable("Observed recipes only; LibProfessionDB count does not match its data")
end

function Catalog.LibraryReport()
    if Catalog.RefreshLibrary(true) then
        return {
            Catalog.source,
            "LibProfessionDB ready: " .. cachedCount .. " recipes. Standalone ProfessionDB is not required.",
        }
    end
    local lines = { Catalog.source, addon.Compat.AddOnStatus("ProfessionDB") }
    local dependencies, state = addon.Compat.Call(C_AddOns and C_AddOns.GetAddOnDependencies, "ProfessionDB")
    if dependencies then
        for index = 2, math.min(dependencies.n, 11) do
            local name = dependencies[index]
            if type(name) == "string" and name ~= "" then
                lines[#lines + 1] = addon.Compat.AddOnStatus(name)
            end
        end
    else
        lines[#lines + 1] = "ProfessionDB dependency list " .. state
    end
    return lines
end

function Catalog.Initialize()
    local storage = addon.characterDB or addon.db
    if type(storage.catalog) ~= "table" then
        storage.catalog = { localProfile = nil, remoteProfiles = {}, shareEnabled = true }
    end
    local database = storage.catalog
    if type(database.remoteProfiles) ~= "table" then
        database.remoteProfiles = {}
    end
    for name in pairs(database.remoteProfiles) do
        if addon.Compat.IsPlayerName(name) then database.remoteProfiles[name] = nil end
    end
    if type(database.recipeIndex) ~= "table" then
        database.recipeIndex = {}
    end
    if database.generation == nil then database.generation = 1 end
    if database.sharingDefaultsVersion ~= 1 then
        database.shareEnabled = true
        database.sharingDefaultsVersion = 1
    end
    if type(database.shareEnabled) ~= "boolean" then
        database.shareEnabled = true
    end
    return database
end

function Catalog.RemoteProfiles()
    local profiles = Catalog.Initialize().remoteProfiles
    if not addon.GuildState then return profiles end
    if not addon.GuildState.IsReady() then return {} end
    local visible = {}
    for name, profile in pairs(profiles) do
        if addon.GuildState.Resolve(name) then visible[name] = profile end
    end
    return visible
end

local function RecipeCandidates(api)
    local candidates, professionNames = {}, {}
    local professionCount = 0
    local hasRecipeList = false
    local function AddRecipe(recipeSpellID, skillLineID)
        if addon.Compat.IsReadable(recipeSpellID) and type(recipeSpellID) == "number"
            and recipeSpellID > 0 and not candidates[recipeSpellID] then
            candidates[recipeSpellID] = skillLineID or true
        end
    end

    local skillLines = Call(api.GetAllProfessionTradeSkillLines)
    if IsReadableTable(skillLines) then
        local lineCount = 0
        for _, skillLineID in ipairs(skillLines) do
            lineCount = lineCount + 1
            if lineCount > 100 then
                break
            end
            if type(skillLineID) == "number" and addon.Compat.IsReadable(skillLineID) then
                professionCount = professionCount + 1
                local info = Call(api.GetProfessionInfoBySkillLineID, skillLineID)
                local professionID = Field(info, "professionID")
                local professionName = Field(info, "professionName")
                if type(professionName) == "string" then
                    professionNames[skillLineID] = professionName
                end
                if type(professionID) == "number" and type(api.GetProfessionSpells) == "function" then
                    local spells = Call(api.GetProfessionSpells, professionID, skillLineID)
                    if IsReadableTable(spells) then
                        hasRecipeList = true
                        for _, spellID in ipairs(spells) do
                            AddRecipe(spellID, skillLineID)
                        end
                    end
                end
            end
        end
    end

    if type(api.GetAllRecipeIDs) == "function" then
        local allRecipeIDs = Call(api.GetAllRecipeIDs)
        if IsReadableTable(allRecipeIDs) then
            hasRecipeList = true
            for _, recipeSpellID in ipairs(allRecipeIDs) do
                AddRecipe(recipeSpellID, nil)
            end
        end
    end

    return candidates, professionNames, professionCount, hasRecipeList
end

function Catalog.Scan()
    Catalog.scannedThisSession = false
    local api = C_TradeSkillUI
    if type(api) ~= "table" or type(api.GetRecipeInfo) ~= "function" then
        return nil, nil, "profession recipe APIs missing"
    end

    local candidates, professionNames, professionCount, hasRecipeList = RecipeCandidates(api)
    local recipeIDs = {}
    for recipeSpellID in pairs(candidates) do
        recipeIDs[#recipeIDs + 1] = recipeSpellID
    end
    table.sort(recipeIDs)
    local recipeCount = #recipeIDs
    if recipeCount == 0 and not hasRecipeList then
        return nil, nil, "no recipe list available"
    end
    if recipeCount > MAX_RECIPE_IDS then
        return nil, nil, "recipe list exceeds scan limit"
    end

    local recipes, observed = {}, {}
    local learnedCount = 0
    local unavailableCount = 0
    for _, recipeSpellID in ipairs(recipeIDs) do
        if type(recipeSpellID) == "number" and addon.Compat.IsReadable(recipeSpellID) then
            local info = Call(api.GetRecipeInfo, recipeSpellID)
            if IsReadableTable(info) then
                local learned = Field(info, "learned")
                if type(learned) == "boolean" then
                    local recipeID = Field(info, "recipeID")
                    local recipeName = Field(info, "name")
                    if type(recipeID) == "number" and type(recipeName) == "string" then
                        local output = Call(api.GetRecipeOutputItemData, recipeSpellID)
                        local hyperlink = Field(output, "hyperlink")
                        local skillLineID = Call(api.GetTradeSkillLineForRecipe, recipeID)
                        if type(skillLineID) ~= "number" then
                            skillLineID = candidates[recipeSpellID]
                        end
                        local professionName
                        if type(skillLineID) == "number" then
                            professionName = Call(api.GetTradeSkillDisplayName, skillLineID)
                            professionName = professionName or professionNames[skillLineID]
                        end
                        local recipe = {
                            recipeID = recipeID,
                            recipeSpellID = recipeSpellID,
                            skillLineID = type(skillLineID) == "number" and skillLineID or 0,
                            professionName = type(professionName) == "string" and professionName or "Profession",
                            recipeName = recipeName,
                            itemName = OutputName(hyperlink, recipeName),
                            itemLink = type(hyperlink) == "string" and hyperlink or nil,
                        }
                        observed[tostring(recipeID)] = recipe
                        if learned then
                            recipes[#recipes + 1] = recipe
                            learnedCount = learnedCount + 1
                        end
                    else
                        unavailableCount = unavailableCount + 1
                    end
                elseif learned == nil then
                    unavailableCount = unavailableCount + 1
                end
            else
                unavailableCount = unavailableCount + 1
            end
        end
    end

    local now = Call(time) or 0
    local database = Catalog.Initialize()
    local indexed = 0
    for _ in pairs(database.recipeIndex) do indexed = indexed + 1 end
    for key, recipe in pairs(observed) do
        if database.recipeIndex[key] or indexed < MAX_RECIPE_IDS then
            if not database.recipeIndex[key] then indexed = indexed + 1 end
            database.recipeIndex[key] = recipe
        end
    end
    database.localProfile = {
        recipes = recipes,
        updatedAt = now,
        scanned = recipeCount,
        learned = learnedCount,
        unavailable = unavailableCount,
        professions = professionCount,
    }
    Catalog.scannedThisSession = unavailableCount == 0
    return recipeCount, learnedCount, nil, unavailableCount
end

local function Entries(includeUnlearned)
    local database = Catalog.Initialize()
    local matches = {}
    local function AddRecipe(recipe)
        if type(recipe) ~= "table" or type(recipe.recipeID) ~= "number"
            or type(recipe.itemName) ~= "string" then return nil end
        local key = tostring(recipe.recipeID)
        local entry = matches[key]
        if not entry then
            entry = {
                key = key, recipeID = recipe.recipeID,
                recipeSpellID = recipe.recipeSpellID or recipe.recipeID,
                skillLineID = recipe.skillLineID or 0,
                itemName = recipe.itemName, recipeName = recipe.recipeName,
                professionName = recipe.professionName or "Profession",
                itemLink = recipe.itemLink, itemID = recipe.itemID, effect = recipe.effect,
                reagents = recipe.reagents, availability = recipe.availability, crafters = {},
            }
            matches[key] = entry
        else
            entry.itemLink = entry.itemLink or recipe.itemLink
            if entry.skillLineID == 0 and type(recipe.skillLineID) == "number" then
                entry.skillLineID = recipe.skillLineID
                entry.professionName = recipe.professionName or entry.professionName
            end
        end
        return entry
    end
    if includeUnlearned then
        Catalog.RefreshLibrary()
        for _, recipe in ipairs(libraryRecipes) do AddRecipe(recipe) end
        for _, recipe in pairs(database.recipeIndex) do AddRecipe(recipe) end
    end
    local profiles = {}
    if type(database.localProfile) == "table" then
        profiles[#profiles + 1] = { name = "You", profile = database.localProfile, isOnline = true }
    end
    for name, profile in pairs(Catalog.RemoteProfiles()) do
        if type(name) == "string" and type(profile) == "table" then
            profiles[#profiles + 1] = {
                name = name, profile = profile,
                isOnline = addon.GuildState and addon.GuildState.IsOnline(name),
            }
        end
    end

    for _, source in ipairs(profiles) do
        local recipes = source.profile.recipes
        if type(recipes) == "table" then
            for _, recipe in ipairs(recipes) do
                local entry = AddRecipe(recipe)
                if entry then
                    local duplicate = false
                    for _, crafter in ipairs(entry.crafters) do
                        if crafter.name == source.name then duplicate = true end
                    end
                    if not duplicate then
                        entry.crafters[#entry.crafters + 1] = {
                            name = source.name, updatedAt = source.profile.updatedAt,
                            isLocal = source.name == "You",
                            isOnline = source.isOnline,
                        }
                    end
                end
            end
        end
    end

    return matches
end

local function ProfessionGroups(entries)
    local professions, byID, byName = {}, {}, {}
    local function AddProfession(id, name, icon, gathering, alias)
        if type(id) ~= "number" or byID[id] then return end
        name = type(name) == "string" and name ~= "" and name or "Profession"
        local nameKey = name ~= "Profession" and name:lower() or nil
        local profession = nameKey and byName[nameKey]
        if not profession then
            profession = {
                id = id, name = name, gathering = gathering,
                icon = "Interface\\Icons\\" .. (icon or "INV_Misc_Book_09"),
                known = 0, total = 0,
            }
            professions[#professions + 1] = profession
            if nameKey then byName[nameKey] = profession end
        end
        byID[id] = profession
        if alias then byName[alias:lower()] = profession end
    end
    for _, definition in ipairs(professionDefinitions) do
        local name = Call(C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName, definition.id)
        AddProfession(definition.id, type(name) == "string" and name or definition.name,
            definition.icon, definition.gathering, definition.name)
    end
    local lines = Call(C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines)
    if IsReadableTable(lines) then
        for index, id in ipairs(lines) do
            if index > 100 then break end
            if addon.Compat.IsReadable(id) and type(id) == "number" and not byID[id] then
                local info = Call(C_TradeSkillUI.GetProfessionInfoBySkillLineID, id)
                local name = Field(info, "professionName")
                if type(name) == "string" then AddProfession(id, name) end
            end
        end
    end
    for _, entry in pairs(entries) do AddProfession(entry.skillLineID, entry.professionName) end
    return byID, professions
end

local function FilterEntries(query, skillLineID, includeUnlearned)
    local needle = type(query) == "string" and query:lower() or ""
    local results = {}
    local entries = Entries(includeUnlearned)
    local byID = skillLineID and ProfessionGroups(entries)
    for _, entry in pairs(entries) do
        table.sort(entry.crafters, function(left, right)
            if (left.isOnline == true) ~= (right.isOnline == true) then return left.isOnline == true end
            return left.name:lower() < right.name:lower()
        end)
        local searchable = (entry.itemName .. " " .. (entry.recipeName or "")
            .. " " .. entry.professionName .. " " .. (entry.effect or "")):lower()
        if (not skillLineID or (byID[skillLineID] and byID[entry.skillLineID] == byID[skillLineID]))
            and (needle == "" or searchable:find(needle, 1, true)) then
            results[#results + 1] = entry
        end
    end
    table.sort(results, function(left, right)
        if left.itemName:lower() ~= right.itemName:lower() then
            return left.itemName:lower() < right.itemName:lower()
        end
        if left.professionName ~= right.professionName then
            return left.professionName:lower() < right.professionName:lower()
        end
        return left.recipeID < right.recipeID
    end)
    return results
end

function Catalog.Search(query)
    local results = FilterEntries(query, nil, false)
    local truncated = math.max(0, #results - MAX_SEARCH_RESULTS)
    for index = #results, MAX_SEARCH_RESULTS + 1, -1 do
        results[index] = nil
    end
    return results, truncated
end

function Catalog.Browse(query, skillLineID, page)
    local results = FilterEntries(query, skillLineID, true)
    local total = #results
    local pages = math.max(1, math.ceil(total / PAGE_SIZE))
    page = math.max(1, math.min(pages, math.floor(tonumber(page) or 1)))
    local visible = {}
    for index = (page - 1) * PAGE_SIZE + 1, math.min(total, page * PAGE_SIZE) do
        visible[#visible + 1] = results[index]
    end
    return visible, total, pages, page
end

function Catalog.Overview()
    local entries = Entries(true)
    local byID, professions = ProfessionGroups(entries)
    local known, total = 0, 0
    for _, entry in pairs(entries) do
        local profession = byID[entry.skillLineID]
        total = total + 1
        profession.total = profession.total + 1
        if #entry.crafters > 0 then
            known = known + 1
            profession.known = profession.known + 1
        end
    end
    table.sort(professions, function(left, right) return left.name:lower() < right.name:lower() end)
    return professions, known, total
end

function Catalog.SetSharing(enabled)
    if type(enabled) ~= "boolean" then
        return false
    end
    Catalog.Initialize().shareEnabled = enabled
    return true
end