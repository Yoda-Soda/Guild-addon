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