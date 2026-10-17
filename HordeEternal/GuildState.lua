local _, addon = ...

local Guild = { ready = false, serial = 0, members = {}, aliases = {}, online = {}, details = {} }
addon.GuildState = Guild
local OWNER = "Podcast Clawson"
local MAX_MEMBERS = 1000
local listener

local function Invalidate()
    Guild.ready = false
    Guild.members, Guild.aliases, Guild.online = {}, {}, {}
    Guild.details = {}
    Guild.serial = Guild.serial + 1
    if addon.Sync and addon.Sync.Invalidate then addon.Sync.Invalidate() end
    if addon.Members and addon.Members.Invalidate then addon.Members.Invalidate() end
end

local function CurrentContext()
    local inGuild, state = addon.Compat.Value(IsInGuild)
    if state ~= "available" then return nil end
    if inGuild == false then return false end
    if inGuild ~= true then return nil end
    local info = addon.Compat.Call(GetGuildInfo, "player")
    local home = addon.Compat.Value(GetNormalizedRealmName)
    if not info or type(info[2]) ~= "string" or info[2] == ""
        or type(home) ~= "string" or home == "" then return nil end
    local guildRealm = info[5]
    if type(guildRealm) ~= "string" or guildRealm == "" then guildRealm = home end
    return info[2] .. "@" .. guildRealm, home
end

function Guild.CheckContext()
    local key, home = CurrentContext()
    if not key then
        if Guild.key or Guild.ready then Invalidate() end
        Guild.key, Guild.home = nil, nil
        if key == false and addon.db then
            local database = addon.Catalog.Initialize()
            database.remoteProfiles = {}
            database.guildKey = nil
        end
        return false
    end
    if Guild.key ~= key then
        Invalidate()
        Guild.key, Guild.home = key, home
        local database = addon.Catalog.Initialize()
        if database.guildKey ~= key then
            database.remoteProfiles = {}
            database.generation, database.resetIssuer = 1, nil
            database.guildKey = key
        end
    end
    return true
end

local function Canonical(name)
    if type(name) ~= "string" or name == "" or #name > 100 or name:find("[%c|]") then return nil end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. Guild.home
end

function Guild.Resolve(name)
    if not Guild.ready or not addon.Compat.IsReadable(name) or type(name) ~= "string" then return nil end
    local key = Guild.aliases[name:lower()]
    return type(key) == "string" and key or nil
end

function Guild.IsReady()
    return Guild.CheckContext() and Guild.ready
end

function Guild.IsOnline(name)
    if not Guild.IsReady() then return nil end
    local canonical = Guild.Resolve(name)
    if not canonical then return nil end
    return Guild.online[canonical]
end

function Guild.Authority()
    return Guild.Resolve(OWNER)
end

function Guild.Rows()
    if not Guild.IsReady() then return {} end
    local rows = {}
    for _, detail in pairs(Guild.details) do rows[#rows + 1] = detail end
    table.sort(rows, function(left, right) return left.name:lower() < right.name:lower() end)
    return rows
end

function Guild.CanReset()
    if not Guild.IsReady() then return false end
    local authority = Guild.Authority()
    return authority ~= nil and addon.Compat.IsPlayerName(authority)
end

function Guild.Generation()
    return addon.Catalog.Initialize().generation or 1
end

function Guild.AcceptGeneration(generation, issuer)
    if not Guild.IsReady() or type(generation) ~= "number" or generation ~= math.floor(generation)
        or generation < 2 or generation > 2147483647 or generation <= Guild.Generation() then return false end
    local authority = Guild.Authority()
    if not authority or Guild.Resolve(issuer) ~= authority then return false end
    local database = addon.Catalog.Initialize()
    database.localProfile = nil
    database.remoteProfiles = {}
    database.recipeIndex = {}
    database.generation = generation
    database.resetIssuer = authority
    addon.Catalog.scannedThisSession = false
    addon.db.craftingGenerations = addon.db.craftingGenerations or {}
    addon.db.craftingGenerations[Guild.key] = { generation = generation, issuer = authority }
    Guild.serial = Guild.serial + 1
    if addon.Sync and addon.Sync.Invalidate then addon.Sync.Invalidate() end
    return true
end

function Guild.RefreshRoster()
    if not Guild.CheckContext() then return false end
    local count = addon.Compat.Value(GetNumGuildMembers)
    if type(count) ~= "number" or count < 1 or count > MAX_MEMBERS or count ~= math.floor(count) then
        Invalidate()
        return false
    end
    local members, aliases, online, details, selfPresent = {}, {}, {}, {}, false
    local function AddAlias(alias, canonical)
        alias = alias:lower()
        if aliases[alias] == nil then aliases[alias] = canonical
        elseif aliases[alias] ~= canonical then aliases[alias] = false end
    end
    for index = 1, count do
        local info = addon.Compat.Call(GetGuildRosterInfo, index)
        local name = info and Canonical(info[2])
        if not name or members[name:lower()] then
            Invalidate()
            return false
        end
        members[name:lower()] = name
        if type(info[10]) == "boolean" then online[name] = info[10] end
        details[name] = {
            name = name, rank = type(info[3]) == "string" and info[3] or nil,
            rankIndex = type(info[4]) == "number" and info[4] >= 0 and info[4] <= 100
                and info[4] == math.floor(info[4]) and info[4] or nil,
            level = type(info[5]) == "number" and info[5] or nil,
            className = type(info[6]) == "string" and info[6] or nil,
            zone = type(info[7]) == "string" and info[7] ~= "" and not info[7]:find("[%c|]") and info[7] or nil,
            classFile = type(info[12]) == "string" and info[12] or nil,
            online = online[name],
        }
        AddAlias(name, name)
        AddAlias(name:match("^(.*)%-[^%-]+$") or name, name)
        if addon.Compat.IsPlayerName(name) then selfPresent = true end
    end
    local key = CurrentContext()
    if not selfPresent or key ~= Guild.key or addon.Compat.Value(GetNumGuildMembers) ~= count then
        Invalidate()
        return false
    end
    Guild.members, Guild.aliases, Guild.online, Guild.ready = members, aliases, online, true
    Guild.details = details
    local database = addon.Catalog.Initialize()
    local generations = addon.db.craftingGenerations
    local saved = type(generations) == "table" and generations[Guild.key]
    if type(saved) == "table" then Guild.AcceptGeneration(saved.generation, saved.issuer) end
    for name in pairs(database.remoteProfiles) do
        if not Guild.Resolve(name) then database.remoteProfiles[name] = nil end
    end
    addon.Catalog.CacheLocalProfile()
    if addon.RefreshCatalog then addon.RefreshCatalog() end
    if addon.Members then addon.Members.RosterReady() end
    if addon.RefreshGuild then addon.RefreshGuild() end
    return true
end

function Guild.Start()
    if not listener then
        listener = CreateFrame("Frame")
        listener:RegisterEvent("GUILD_ROSTER_UPDATE")
        listener:RegisterEvent("PLAYER_GUILD_UPDATE")
        listener:SetScript("OnEvent", function(_, event, unit)
            if event == "PLAYER_GUILD_UPDATE" then
                if not addon.Compat.IsReadable(unit) or unit ~= "player" then return end
                Invalidate()
                Guild.CheckContext()
                addon.Compat.Call(C_GuildInfo and C_GuildInfo.GuildRoster)
            elseif Guild.RefreshRoster() and addon.Sync and addon.Sync.RosterReady then
                addon.Sync.RosterReady()
            end
            if addon.RefreshCatalog then addon.RefreshCatalog() end
            if addon.RefreshGuild then addon.RefreshGuild() end
        end)
    end
    Guild.CheckContext()
    Guild.RefreshRoster()
    addon.Compat.Call(C_GuildInfo and C_GuildInfo.GuildRoster)
end