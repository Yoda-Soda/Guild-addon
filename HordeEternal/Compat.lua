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