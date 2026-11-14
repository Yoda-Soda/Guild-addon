local _, addon = ...
local Members = { status = "Waiting for guild roster", wireVersion = 0 }
addon.Members = Members
local PREFIX = "HEGM1"
local assemblies, windows, requests = {}, {}, {}
local activeScope, listener, pending, lastPublished, lastRequested
local counter = 0

function Members.Invalidate()
    Members.wireVersion = Members.wireVersion + 1
    activeScope, pending, lastPublished, lastRequested = nil, nil, nil, nil
    assemblies, windows, requests = {}, {}, {}
end

local function Now()
    local value = addon.Compat.Value(GetTime)
    return type(value) == "number" and value or 0
end

local function Text(value, limit)
    return addon.Compat.IsReadable(value) and type(value) == "string" and #value <= limit
        and not value:find("[%c|]")
end

local function Integer(value, maximum)
    return type(value) == "number" and value >= 0 and value <= maximum and value == math.floor(value)
end

local function Changed()
    if addon.RefreshGuild then addon.RefreshGuild() end
end

local function Context()
    if not addon.db or not addon.GuildState.IsReady() then return nil end
    local scope = addon.GuildState.key
    if activeScope ~= scope then
        activeScope = scope
        assemblies, windows, requests = {}, {}, {}
        pending, lastPublished, lastRequested = nil, nil, nil
    end
    if type(addon.db.memberGuilds) ~= "table" then addon.db.memberGuilds = {} end
    local database = addon.db.memberGuilds[scope]
    if type(database) ~= "table" then
        database = { profiles = {}, groups = {} }
        addon.db.memberGuilds[scope] = database
    end
    if type(database.profiles) ~= "table" then database.profiles = {} end
    if type(database.groups) ~= "table" then database.groups = {} end
    if type(database.own) ~= "table" then
        local stamp = addon.Compat.Value(time)
        database.own = {
            id = tostring(type(stamp) == "number" and math.floor(stamp) or 0) .. "-"
                .. math.random(100000, 999999) .. "-" .. math.random(100000, 999999),
            revision = 1, main = "", discord = "",
        }
    end
    return database
end

function Members.Self()
    if not addon.GuildState.IsReady() then return nil end
    for _, row in ipairs(addon.GuildState.Rows()) do
        if addon.Compat.IsPlayerName(row.name) then return row.name end
    end
end

function Members.Settings()
    local database = Context()
    return database and database.own
end

function Members.CanView()
    local settings = Members.Settings()
    if not settings then return false end
    return Text(settings.main, 100) and settings.main ~= "" and addon.GuildState.Resolve(settings.main) ~= nil
        and settings.discordNicknameVersion == 1 and Text(settings.discord, 32) and settings.discord:find("%S") ~= nil
end

local function Prune(database)
    local used = {}
    for name, profile in pairs(database.profiles) do
        if not addon.GuildState.Resolve(name) then database.profiles[name] = nil
        else used[profile.id] = true end
    end
    for id in pairs(database.groups) do
        if not used[id] and id ~= database.own.id then database.groups[id] = nil end
    end
end

function Members.Capture()
    local database, name = Context(), Members.Self()
    if not database or not name then return nil end
    Prune(database)
    if database.own.main ~= "" and not addon.GuildState.Resolve(database.own.main) then
        database.own.main = ""
        database.own.revision = math.min(2147483647, database.own.revision + 1)
        Members.wireVersion = Members.wireVersion + 1
    end
    local race, spec, talents = addon.Compat.PlayerGuildFacts()
    local stamp = addon.Compat.Value(time)
    local profile = {
        id = database.own.id, race = race or "", spec = spec or "", talents = talents or "",
        updatedAt = type(stamp) == "number" and math.floor(stamp) or 0,
    }
    database.profiles[name] = profile
    database.groups[database.own.id] = {
        revision = database.own.revision, main = database.own.main,
        discord = database.own.discordNicknameVersion == 1 and database.own.discord or "",
    }
    return profile, database.own
end

local function Escape(value)
    return (tostring(value):gsub("%%", "%%25"):gsub("~", "%%7E"))
end

local function Decode(payload)
    local fields = {}
    for part in (payload .. "~"):gmatch("(.-)~") do
        fields[#fields + 1] = part:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
        if #fields > 10 then return nil end
    end
    if #fields ~= 10 then return nil end
    return fields
end

function Members.Publish()
    local profile, own = Members.Capture()
    if not profile or not addon.Sync or not addon.Sync.QueueMembers then return false end
    local values = { addon.GuildState.key, own.id, own.revision, own.main,
        own.discordNicknameVersion == 1 and own.discord or "",
        profile.race, profile.spec, profile.talents, profile.updatedAt, "2" }
    for index, value in ipairs(values) do values[index] = Escape(value) end
    local payload = table.concat(values, "~")
    if #payload > 1200 then
        Members.status = "Member profile exceeds the sharing limit"
        if addon.LogEvent then addon.LogEvent("MEMBER_QUEUE_REJECTED") end
        return false
    end
    counter = counter + 1
    local transfer = math.floor(Now() * 1000) .. "-" .. counter
    local packets, total = {}, math.ceil(#payload / 140)
    for part = 1, total do
        packets[#packets + 1] = table.concat({ "1", "P", transfer, part, total,
            payload:sub((part - 1) * 140 + 1, part * 140) }, "|")
    end
    Members.wireVersion = Members.wireVersion + 1
    local queued = addon.Sync.QueueMembers(packets)
    Members.status = queued and "Member profile queued; delivery unconfirmed" or "Member profile could not be queued"
    if not queued and addon.LogEvent then addon.LogEvent("MEMBER_QUEUE_REJECTED") end
    if queued then lastPublished = Now() end
    return queued
end

function Members.Schedule()
    if pending or not C_Timer or type(C_Timer.After) ~= "function" then return end
    local scope = addon.GuildState.key
    local ticket = {}
    pending = ticket
    C_Timer.After(math.max(2, 30 - (Now() - (lastPublished or -30))), function()
        if pending ~= ticket then return end
        pending = nil
        if addon.GuildState.IsReady() and addon.GuildState.key == scope then Members.Publish(); Changed() end
    end)
end

function Members.Save(isMain, discord)
    local database, name = Context(), Members.Self()
    if not database or not name then return false, "Waiting for a complete readable guild roster." end
    if type(isMain) ~= "boolean" or not Text(discord, 32) then return false, "Discord server nickname must be plain text, at most 32 characters." end
    discord = discord:match("^%s*(.-)%s*$")
    local own = database.own
    if own.revision >= 2147483647 then return false, "Member profile revision limit reached." end
    local main = isMain and name or own.main == name and "" or own.main
    own.main, own.discord, own.revision = main, discord, own.revision + 1
    own.discordNicknameVersion = 1
    Members.wireVersion = Members.wireVersion + 1
    Members.Capture()
    Members.Schedule()
    Changed()
    return true, "Profile saved; guild update scheduled."
end

function Members.Rows()
    local database = Context()
    if not database or not Members.CanView() then return {} end
    Prune(database)
    local mainGroups = {}
    for id, group in pairs(database.groups) do
        local main = addon.GuildState.Resolve(group.main)
        if main then
            if mainGroups[main] == nil then mainGroups[main] = id
            elseif mainGroups[main] ~= id then mainGroups[main] = false end
        end
    end
    local rows = {}
    for _, roster in ipairs(addon.GuildState.Rows()) do
        local profile = database.profiles[roster.name]
        local id = profile and profile.id or mainGroups[roster.name]
        local group = id and database.groups[id]
        local main = group and addon.GuildState.Resolve(group.main)
        local state = main and (main == roster.name and "Main" or "Alt") or "No main selected"
        rows[#rows + 1] = {
            name = roster.name, className = roster.className or "Unknown", classFile = roster.classFile,
            level = roster.level, rank = roster.rank, rankIndex = roster.rankIndex, online = roster.online,
            main = main, state = state, discord = group and group.discord or "",
            race = profile and profile.race ~= "" and profile.race or "Unknown",
            spec = profile and profile.spec ~= "" and profile.spec or "Spec unknown",
            talents = profile and profile.talents or "", updatedAt = profile and profile.updatedAt,
        }
    end
    return rows
end

function Members.Stats(mainsOnly)
    local stats = { total = 0, all = 0, mains = 0, unassigned = 0, classes = {}, races = {}, specs = {} }
    if not Members.CanView() then return stats end
    for _, class in ipairs({ { "WARRIOR", "Warrior" }, { "PALADIN", "Paladin" }, { "HUNTER", "Hunter" },
        { "ROGUE", "Rogue" }, { "PRIEST", "Priest" }, { "SHAMAN", "Shaman" }, { "MAGE", "Mage" },
        { "WARLOCK", "Warlock" }, { "DRUID", "Druid" } }) do
        local localized = addon.Compat.Field(LOCALIZED_CLASS_NAMES_MALE, class[1])
        stats.classes[type(localized) == "string" and localized or class[2]] = 0
    end
    for _, row in ipairs(Members.Rows()) do
        stats.all = stats.all + 1
        if row.state == "Main" then stats.mains = stats.mains + 1 end
        if row.state == "No main selected" then stats.unassigned = stats.unassigned + 1 end
        if not mainsOnly or row.state == "Main" then
            stats.total = stats.total + 1
            for _, pair in ipairs({ { stats.classes, row.className }, { stats.races, row.race },
                { stats.specs, row.className .. ": " .. row.spec } }) do
                pair[1][pair[2]] = (pair[1][pair[2]] or 0) + 1
            end
        end
    end
    return stats
end

local function Store(sender, payload)
    local fields, database = Decode(payload), Context()
    if not fields or not database or fields[1] ~= addon.GuildState.key or fields[10] ~= "2" then return false end
    local scope, id, revision, main, discord, race, spec, talents, updatedAt = unpack(fields)
    revision, updatedAt = tonumber(revision), tonumber(updatedAt)
    if not Text(scope, 200) or not Text(id, 40) or not id:match("^%d+%-%d+%-%d+$")
        or not Integer(revision, 2147483647) or revision < 1 or not Integer(updatedAt, 4294967295)
        or not Text(main, 100) or not Text(discord, 32) or not Text(race, 40) or not Text(spec, 60)
        or not Text(talents, 320) or (main ~= "" and not addon.GuildState.Resolve(main)) then return false end
    local existing = database.groups[id]
    if id == database.own.id then
        if revision > database.own.revision or main ~= database.own.main or discord ~= database.own.discord then return false end
    end
    if existing and revision == existing.revision and (existing.main ~= main or existing.discord ~= discord) then return false end
    local previous = database.profiles[sender]
    if previous and previous.updatedAt > updatedAt then return false end
    database.profiles[sender] = { id = id, race = race, spec = spec, talents = talents, updatedAt = updatedAt }
    if not existing or revision > existing.revision then
        database.groups[id] = { revision = revision, main = main, discord = discord }
    end
    Prune(database)
    Changed()
    return true
end

function Members.Receive(prefix, message, channel, sender)
    if not addon.Compat.IsReadable(prefix) or not addon.Compat.IsReadable(message)
        or not addon.Compat.IsReadable(channel) or not addon.Compat.IsReadable(sender)
        or prefix ~= PREFIX or channel ~= "GUILD" or type(message) ~= "string" or #message > 220 or message:find("%c")
        or not Context() or not Text(sender, 100) or addon.Compat.IsPlayerName(sender) then return end
    sender = addon.GuildState.Resolve(sender)
    if not sender then return end
    local now = Now()
    local window = windows[sender]
    if not window or now - window.started >= 30 then window = { started = now, count = 0 }; windows[sender] = window end
    window.count = window.count + 1
    if window.count > 30 then return end
    if message == "1|Q|" .. Escape(addon.GuildState.key) then
        if not requests[sender] or now - requests[sender] >= 30 then requests[sender] = now; Members.Schedule() end
        return
    end
    local transfer, part, total, piece = message:match("^1|P|(%d+%-%d+)|(%d+)|(%d+)|(.*)$")
    part, total = tonumber(part), tonumber(total)
    if not transfer or #transfer > 40 or not part or not total or total < 1 or total > 9
        or part < 1 or part > total or #piece > 140 then return end
    for name, assembly in pairs(assemblies) do if now - assembly.created > 60 then assemblies[name] = nil end end
    local assembly = assemblies[sender]
    if not assembly or assembly.transfer ~= transfer then
        local count = 0
        for _ in pairs(assemblies) do count = count + 1 end
        if not assembly and count >= 32 then return end
        assembly = { transfer = transfer, total = total, pieces = {}, count = 0, created = now }
        assemblies[sender] = assembly
    end
    if assembly.total ~= total then return end
    if not assembly.pieces[part] then assembly.pieces[part] = piece; assembly.count = assembly.count + 1 end
    if assembly.count == total then
        assemblies[sender] = nil
        local payload = table.concat(assembly.pieces)
        if #payload <= 1200 then Store(sender, payload) end
    end
end

function Members.RosterReady()
    if not Members.started or not Context() then return end
    Members.Capture()
    if not lastRequested or Now() - lastRequested >= 30 then
        lastRequested = Now()
        addon.Sync.QueueMembers({ "1|Q|" .. Escape(addon.GuildState.key) })
        Members.Schedule()
    end
    Changed()
end

function Members.Start()
    Members.started = true
    if not listener then
        listener = CreateFrame("Frame")
        for _, event in ipairs({ "PLAYER_TALENT_UPDATE", "ACTIVE_COMBAT_CONFIG_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
            addon.Compat.Call(listener.RegisterEvent, listener, event)
        end
        listener:SetScript("OnEvent", function() Members.Schedule() end)
    end
    Members.RosterReady()
end