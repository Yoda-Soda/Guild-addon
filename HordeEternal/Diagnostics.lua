local _, addon = ...
local Compat = addon.Compat
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
    for _, path in ipairs(capabilities) do
        addon.Print(path .. "=" .. (Compat.HasFunction(path) and "present" or "missing/unavailable"))
    end
end