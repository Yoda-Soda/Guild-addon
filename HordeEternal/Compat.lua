local addonName, addon = ...

addon.name = addonName
addon.Compat = {}
local Compat = addon.Compat

function Compat.IsReadable(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        return false
    end
    if type(canaccessvalue) == "function" and not canaccessvalue(value) then
        return false
    end
    return true
end

function Compat.SafeText(value)
    if not Compat.IsReadable(value) then
        return "<restricted>"
    end
    local valueType = type(value)
    if valueType == "nil" then
        return "<nil>"
    end
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end
    return "<non-scalar>"
end

function Compat.CharacterLabel(name)
    if not Compat.IsReadable(name) or type(name) ~= "string" or name == "" or name:find("[%c|]") then return "Unknown" end
    return name:match("^[^-]+") or "Unknown"
end

local function Pack(...)
    return { count = select("#", ...), ... }
end

function Compat.Call(callback, ...)
    if not Compat.IsReadable(callback) or type(callback) ~= "function" then
        return nil, "missing"
    end
    local arguments = Pack(...)
    local ok, values = pcall(function()
        return Pack(callback(unpack(arguments, 1, arguments.count)))
    end)
    if not ok then
        return nil, "error"
    end
    local results = { n = values.count + 1, [1] = true }
    for index = 1, values.count do
        local value = values[index]
        if not Compat.IsReadable(value) then
            return nil, "unavailable"
        end
        results[index + 1] = value
    end
    return results, "available"
end

function Compat.Value(callback, ...)
    local results, state = Compat.Call(callback, ...)
    if not results then
        return nil, state
    end
    return results[2], "available"
end

function Compat.AddOnStatus(name)
    local api = C_AddOns
    if Compat.Value(api and api.DoesAddOnExist, name) == false then
        return name .. ": not found by WoW"
    end
    local info, state = Compat.Call(api and api.GetAddOnInfo, name)
    if not info then return name .. ": addon status " .. state end
    if type(info[2]) ~= "string" or info[2] == "" then return name .. ": addon identity unavailable" end
    local loaded = Compat.Call(api and api.IsAddOnLoaded, name)
    local status = "load status unavailable"
    if loaded then
        status = loaded[3] == true and "loaded" or loaded[2] == true and "loading" or "not loaded"
    end
    if type(info[6]) == "string" and info[6] ~= "" then status = status .. "; " .. info[6] end
    if Compat.Value(api and api.DoesAddOnHaveLoadError, name) == true then
        status = status .. "; Lua loading error"
    end
    return name .. ": " .. status
end

function Compat.OwnRecipeSource(strict)
    local api = C_TradeSkillUI
    if type(api) ~= "table" then return false, "profession recipe APIs missing" end
    for _, name in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting", "IsDataSourceChanging" }) do
        local callback = api[name]
        if type(callback) == "function" then
            local value, state = Compat.Value(callback)
            if state ~= "available" or type(value) ~= "boolean" then return false, "profession source unavailable" end
            if value then return false, name == "IsDataSourceChanging" and "profession data is loading" or "not this character's profession" end
        elseif strict and (name == "IsTradeSkillLinked" or name == "IsTradeSkillGuild") then
            return false, "profession ownership checks unavailable"
        end
    end
    return true
end

function Compat.PlayerGuildFacts()
    local race = Compat.Value(UnitRace, "player")
    if type(race) ~= "string" or #race > 40 or race:find("[%c|]") then race = nil end
    local function Field(source, key)
        return Compat.Field(source, key)
    end
    local function Count(source)
        if not Compat.IsReadable(source) or type(source) ~= "table"
            or (type(canaccesstable) == "function" and not canaccesstable(source)) then return nil end
        return Compat.Value(function() return #source end)
    end
    local configID = Compat.Value(C_ClassTalents and C_ClassTalents.GetActiveConfigID)
    if type(configID) ~= "number" then return race end
    if Compat.Value(C_Traits and C_Traits.ConfigHasStagedChanges, configID) ~= false then return race end
    local config = Compat.Value(C_Traits and C_Traits.GetConfigInfo, configID)
    local trees = Field(config, "treeIDs")
    local treeID = Field(trees, 1)
    if type(treeID) ~= "number" or Count(trees) ~= 1 then return race end
    local displays = Compat.Value(C_Traits and C_Traits.GetGroupDisplayInfoByTreeID, treeID)
    local count = Count(displays)
    if type(count) ~= "number" or count < 1 or count > 4 then return race end
    local ids, names = {}, {}
    for index = 1, count do
        local display = Field(displays, index)
        local id, name = Field(display, "groupID"), Field(display, "displayName")
        if index > 4 or type(id) ~= "number" or names[id] or type(name) ~= "string"
            or #name > 60 or name == "" or name:find("[%c|]") then return race end
        ids[#ids + 1], names[id] = id, name
    end
    if #ids == 0 then return race end
    local currency = Compat.Value(C_Traits and C_Traits.GetGroupCurrencyInfo, configID, ids)
    if Count(currency) ~= #ids then return race end
    local points, seen = {}, {}
    for index = 1, #ids do
        local group = Field(currency, index)
        local id = Field(group, "traitNodeGroupID")
        local values = Field(group, "currencyInfos")
        local spent = Field(Field(values, 1), "spent")
        if not names[id] or seen[id] or type(spent) ~= "number" or spent < 0 or spent > 100
            or spent ~= math.floor(spent) or Count(values) ~= 1 then return race end
        seen[id], points[id] = true, spent
    end
    local maximum, winner, tied, distribution = 0, nil, false, {}
    for _, id in ipairs(ids) do
        local spent = points[id]
        distribution[#distribution + 1] = names[id] .. ": " .. spent
        if spent > maximum then maximum, winner, tied = spent, names[id], false
        elseif spent == maximum then tied = true end
    end
    local spec = maximum == 0 and "No talents spent" or tied and "Hybrid" or winner
    return race, spec, table.concat(distribution, ", ")
end

local function MapNumber(value, minimum, maximum)
    return type(value) == "number" and value == value and value >= minimum and value <= maximum
end

local function MapArray(source, maximum)
    if not Compat.IsReadable(source) or type(source) ~= "table"
        or (type(canaccesstable) == "function" and not canaccesstable(source)) then return nil end
    local count = Compat.Value(function() return #source end)
    if not MapNumber(count, 0, maximum) then return nil end
    return count
end

local function MapDetails(source)
    local id, name = Compat.Field(source, "mapID"), Compat.Field(source, "name")
    local parent, mapType = Compat.Field(source, "parentMapID"), Compat.Field(source, "mapType")
    if not MapNumber(id, 1, 1000000) or id ~= math.floor(id) or type(name) ~= "string" or name == ""
        or #name > 120 or name:find("[%c|]") or not MapNumber(parent, 0, 1000000)
        or not MapNumber(mapType, 0, 6) then return nil end
    return { mapID = id, name = name, parentMapID = parent, mapType = mapType }
end

function Compat.MapInfo(mapID)
    if not MapNumber(mapID, 1, 1000000) then return nil end
    return MapDetails(Compat.Value(C_Map and C_Map.GetMapInfo, mapID))
end

function Compat.MapChildren(mapID)
    local source, state = Compat.Value(C_Map and C_Map.GetMapChildrenInfo, mapID, nil, false)
    if source == nil and state == "available" then return {} end
    local count = MapArray(source, 2048)
    if not count then return nil end
    local children = {}
    for index = 1, count do
        local info = MapDetails(Compat.Field(source, index))
        if not info then return nil end
        children[#children + 1] = info
    end
    return children
end

function Compat.MapRect(mapID, parentID)
    if mapID == parentID then return { x = 0.5, y = 0.5 } end
    local values = Compat.Call(C_Map and C_Map.GetMapRectOnMap, mapID, parentID)
    if not values then return nil end
    local left, right, top, bottom = values[2], values[3], values[4], values[5]
    for _, index in ipairs({ 2, 3, 4, 5 }) do if not MapNumber(values[index], -8, 8) then return nil end end
    if right <= left or bottom <= top then return nil end
    local x, y = (left + right) / 2, (top + bottom) / 2
    if not MapNumber(x, 0, 1) or not MapNumber(y, 0, 1) then return nil end
    return { x = x, y = y }
end

function Compat.MapArt(mapID)
    local layers = Compat.Value(C_Map and C_Map.GetMapArtLayers, mapID)
    local layer = Compat.Field(layers, 1)
    local width, height = Compat.Field(layer, "layerWidth"), Compat.Field(layer, "layerHeight")
    local tileWidth, tileHeight = Compat.Field(layer, "tileWidth"), Compat.Field(layer, "tileHeight")
    if not MapNumber(width, 1, 16384) or not MapNumber(height, 1, 16384)
        or not MapNumber(tileWidth, 1, 4096) or not MapNumber(tileHeight, 1, 4096) then return nil end
    local columns, rows = math.ceil(width / tileWidth), math.ceil(height / tileHeight)
    if columns * rows > 64 then return nil end
    local textures = Compat.Value(C_Map and C_Map.GetMapArtLayerTextures, mapID, 1)
    if MapArray(textures, 64) ~= columns * rows then return nil end
    local tiles = {}
    for row = 0, rows - 1 do
        for column = 0, columns - 1 do
            local fileID = Compat.Field(textures, row * columns + column + 1)
            if not MapNumber(fileID, 1, 2147483647) then return nil end
            local visibleWidth, visibleHeight = math.min(tileWidth, width - column * tileWidth), math.min(tileHeight, height - row * tileHeight)
            tiles[#tiles + 1] = { fileID = fileID, x = column * tileWidth / width, y = row * tileHeight / height,
                width = visibleWidth / width, height = visibleHeight / height,
                u = visibleWidth / tileWidth, v = visibleHeight / tileHeight }
        end
    end
    return { width = width, height = height, tiles = tiles }
end

function Compat.IsPlayerName(name)
    if not Compat.IsReadable(name) or type(name) ~= "string" then return false end
    local identity = Compat.Call(UnitFullName, "player")
    if not identity or type(identity[2]) ~= "string" or identity[2] == "" then return false end
    local playerName, realm = identity[2], identity[3]
    if type(GetNormalizedRealmName) == "function" then
        local home, state = Compat.Value(GetNormalizedRealmName)
        if state ~= "available" or type(home) ~= "string" or home == "" then return false end
        if type(realm) == "string" and realm ~= "" and realm ~= home
            and not playerName:find(" ", 1, true) then
            playerName, realm = playerName .. " " .. realm, home
        elseif realm == nil or realm == "" then
            realm = home
        end
    end
    local candidate = name:lower()
    if candidate == playerName:lower() then return true end
    return type(realm) == "string" and realm ~= ""
        and candidate == (playerName .. "-" .. realm):lower()
end

function Compat.HasFunction(path)
    local value = _G
    for component in string.gmatch(path, "[^.]+") do
        if not Compat.IsReadable(value) then
            return false
        end
        if type(value) ~= "table" then
            return false
        end
        if type(canaccesstable) == "function" and not canaccesstable(value) then
            return false
        end
        value = value[component]
    end
    return Compat.IsReadable(value) and type(value) == "function"
end

function Compat.Field(source, key)
    if not Compat.IsReadable(source) or type(source) ~= "table"
        or (type(canaccesstable) == "function" and not canaccesstable(source)) then return nil end
    local ok, value = pcall(function() return source[key] end)
    if ok and Compat.IsReadable(value) then return value end
    return nil
end

function Compat.RecipeDisplay(entry, withDetails)
    local display = {
        name = entry.itemName, icon = "Interface\\Icons\\INV_Misc_QuestionMark",
        recipeID = entry.recipeSpellID or entry.recipeID,
        itemID = entry.itemID,
    }
    local output = Compat.Value(C_TradeSkillUI and C_TradeSkillUI.GetRecipeOutputItemData, display.recipeID)
    local outputLink = Compat.Field(output, "hyperlink") or entry.itemLink
    if type(outputLink) == "string" then
        display.itemID = tonumber(outputLink:match("item:(%d+)"))
    end
    local spell = Compat.Value(C_Spell and C_Spell.GetSpellInfo, display.recipeID)
    local spellIcon = Compat.Field(spell, "iconID")
    if type(spellIcon) == "number" then display.icon = spellIcon end
    if display.itemID then
        local icon = Compat.Value(C_Item and C_Item.GetItemIconByID, display.itemID)
        if type(icon) == "number" then display.icon = icon end
        local info = Compat.Call(C_Item and C_Item.GetItemInfo, display.itemID)
        if info and type(info[2]) == "string" and type(info[3]) == "string" then
            display.name, display.link = info[2], info[3]
        end
        display.tooltipLink = "item:" .. display.itemID
    else
        local link = Compat.Value(C_Spell and C_Spell.GetSpellLink, display.recipeID)
        if type(link) == "string" then display.link = link end
        display.tooltipLink = "spell:" .. display.recipeID
    end
    if withDetails then
        local tooltip = Compat.Value(C_TooltipInfo and C_TooltipInfo.GetHyperlink, display.tooltipLink)
        local lines, text = Compat.Field(tooltip, "lines"), {}
        for index = 2, 40 do
            local line = Compat.Field(lines, index)
            if not line then break end
            local left, right = Compat.Field(line, "leftText"), Compat.Field(line, "rightText")
            if type(left) == "string" and left ~= "" then
                text[#text + 1] = left .. (type(right) == "string" and right ~= "" and ("  " .. right) or "")
            end
        end
        if #text > 0 then
            display.description = table.concat(text, "\n")
        else
            local description = entry.effect or Compat.Value(C_Spell and C_Spell.GetSpellDescription, display.recipeID)
            display.description = type(description) == "string" and description ~= "" and description
                or "Item details unavailable."
        end
    end
    return display
end

function Compat.RecipeUsability(entry)
    local itemID = entry.itemID
    if not itemID and type(entry.itemLink) == "string" then
        itemID = tonumber(entry.itemLink:match("item:(%d+)"))
    end
    if not itemID then
        local output = Compat.Value(C_TradeSkillUI and C_TradeSkillUI.GetRecipeOutputItemData,
            entry.recipeSpellID or entry.recipeID)
        local link = Compat.Field(output, "hyperlink")
        if type(link) == "string" then itemID = tonumber(link:match("item:(%d+)")) end
    end
    if type(itemID) ~= "number" or itemID <= 0 then return nil, "Requirements unknown" end
    local info, state = Compat.Call(C_Item and C_Item.GetItemInfo, itemID)
    if not info or type(info[2]) ~= "string" or type(info[6]) ~= "number" or info[6] < 0 then
        return nil, "Requirements unknown", itemID, state == "available" and info and info[2] == nil
    end
    local level = Compat.Value(UnitLevel, "player")
    if type(level) ~= "number" or level < 1 then return nil, "Requirements unknown" end
    if level < info[6] then return false, "Requires level " .. info[6], itemID end
    local types = Compat.Field(Enum, "TooltipDataLineType")
    local requirement, equipment = Compat.Field(types, "UsageRequirement"), Compat.Field(types, "EquipSlot")
    local itemName, errorLine = Compat.Field(types, "ItemName"), Compat.Field(types, "ErrorLine")
    if type(requirement) ~= "number" or type(equipment) ~= "number"
        or type(itemName) ~= "number" or type(errorLine) ~= "number" then
        return nil, "Requirements unknown"
    end
    local tooltip, tooltipState = Compat.Value(C_TooltipInfo and C_TooltipInfo.GetHyperlink, "item:" .. itemID)
    if tooltip == nil then return nil, "Requirements unknown", itemID, tooltipState == "available" end
    local lines = Compat.Field(tooltip, "lines")
    if not Compat.Field(lines, 1) then return nil, "Requirements unknown" end
    local count = Compat.Value(function() return #lines end)
    if type(count) ~= "number" or count < 1 or count > 80 then return nil, "Requirements unknown" end
    local named = false
    for index = 1, count do
        local line = Compat.Field(lines, index)
        if type(line) ~= "table" or (type(canaccesstable) == "function" and not canaccesstable(line)) then
            return nil, "Requirements unknown"
        end
        local values = Compat.Call(function()
            return line.type, line.leftColor, line.rightColor, line.leftText, line.rightText
        end)
        if not values or type(values[2]) ~= "number" then return nil, "Requirements unknown" end
        local lineType = values[2]
        if lineType == itemName then named = type(values[5]) == "string" and values[5] ~= "" end
        if lineType == errorLine then
            return false, type(values[5]) == "string" and values[5] or "Unmet item requirements", itemID
        end
        if lineType == requirement or lineType == equipment then
            for side = 1, 2 do
                local color, text = values[side + 2], values[side + 4]
                if side == 1 or color ~= nil or (type(text) == "string" and text ~= "") then
                    local red, green, blue = Compat.Field(color, "r"), Compat.Field(color, "g"), Compat.Field(color, "b")
                    if type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number"
                        or red < 0 or red > 1 or green < 0 or green > 1 or blue < 0 or blue > 1 then
                        return nil, "Requirements unknown"
                    end
                    if red >= 0.8 and green <= 0.25 and blue <= 0.25 then
                        return false, type(text) == "string" and text ~= "" and text or "Unmet item requirements", itemID
                    end
                end
            end
        end
    end
    if not named then return nil, "Requirements unknown" end
    return true, "Requirements met", itemID
end

function Compat.RequestRecipeData(display)
    if display.itemID then
        Compat.Call(C_Item and C_Item.RequestLoadItemDataByID, display.itemID)
    end
    Compat.Call(C_Spell and C_Spell.RequestLoadSpellData, display.recipeID)
end

function Compat.OpenCraftRequest(entry, crafter)
    if type(crafter) ~= "table" or crafter.isLocal or not Compat.IsReadable(crafter.name)
        or type(crafter.name) ~= "string" or crafter.name == "" or #crafter.name > 128
        or crafter.name:find("[%c|]") then return false, "Crafter unavailable." end
    if Compat.Value(IsInGuild) ~= true then return false, "Join a guild before contacting a guild crafter." end
    if addon.GuildState and (not addon.GuildState.IsReady() or not addon.GuildState.Resolve(crafter.name)) then
        return false, "This crafter is not verified in the current guild roster."
    end
    if addon.GuildState and addon.GuildState.IsOnline(crafter.name) ~= true then
        return false, "This crafter is offline or their online status is unavailable."
    end
    if not ChatFrameUtil or type(ChatFrameUtil.SendTellWithMessage) ~= "function" then
        return false, "Whisper editor unavailable."
    end
    local active = Compat.Value(ChatFrameUtil.GetActiveWindow)
    if active then
        local draft = Compat.Value(active.GetText, active)
        if type(draft) == "string" and draft ~= "" then
            return false, "Finish or close your current chat draft first."
        end
    end
    local display = Compat.RecipeDisplay(entry)
    local item = display.link or display.name:gsub("[|%c]", "")
    local message = "Hi! Could you craft " .. item .. " for me? I can provide materials."
    if #message > 255 then
        message = "Hi! Could you craft " .. display.name:gsub("[|%c]", ""):sub(1, 120)
            .. " for me? I can provide materials."
    end
    local recipient = crafter.name:match("^[^-]+")
    if not recipient then return false, "Crafter unavailable." end
    local result, state = Compat.Call(ChatFrameUtil.SendTellWithMessage, recipient, message)
    if not result then return false, "Whisper editor " .. state .. "." end
    return true
end