local _, addon = ...
local Members = { status = "Waiting for guild roster", wireVersion = 0 }
addon.Members = Members
local PREFIX = "HEGM1"
local assemblies, windows, requests = {}, {}, {}
local activeScope, listener, pending, lastPublished, lastRequested
local counter = 0
local inventoryDue, inventoryBuild
local offers, recovery = {}, {}
local relayAssemblies, recentReplies = {}, {}
local inventoryCursor = 1
local ScheduleInventory, ReceiveRelay

function Members.Invalidate()
    Members.wireVersion = Members.wireVersion + 1
    activeScope, pending, lastPublished, lastRequested = nil, nil, nil, nil
    assemblies, windows, requests = {}, {}, {}
    offers, recovery, inventoryDue, inventoryBuild = {}, {}, nil, nil
    relayAssemblies, recentReplies, inventoryCursor = {}, {}, 1
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
        offers, recovery, inventoryDue, inventoryBuild = {}, {}, nil, nil
        relayAssemblies, recentReplies, inventoryCursor = {}, {}, 1
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
    local previous = database.profiles[name]
    local unchanged = previous and previous.id == database.own.id
        and previous.race == (race or "") and previous.spec == (spec or "") and previous.talents == (talents or "")
    local factsRevision = previous and previous.factsRevision or 0
    if not unchanged or factsRevision == 0 then
        if factsRevision >= 2147483647 then
            Members.status = "Character report revision limit reached"
            if addon.LogEvent then addon.LogEvent("MEMBER_PROFILE_REJECTED", { reason = "format" }) end
            return nil
        end
        factsRevision = factsRevision + 1
    end
    local profile = {
        id = database.own.id, race = race or "", spec = spec or "", talents = talents or "",
        updatedAt = unchanged and previous.updatedAt or (type(stamp) == "number" and math.floor(stamp) or 0),
        factsRevision = factsRevision,
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

local function Decode(payload, count)
    local fields, position = {}, 1
    while true do
        local separator = payload:find("~", position, true)
        local part = payload:sub(position, separator and separator - 1 or #payload)
        fields[#fields + 1] = part:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
        if #fields > (count or 10) then return nil end
        if not separator then break end
        position = separator + 1
    end
    if #fields ~= (count or 10) then return nil end
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
    if queued then lastPublished = Now(); ScheduleInventory() end
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

function Members.Stats(mainsOnly, rows)
    local stats = { total = 0, all = 0, mains = 0, alts = 0, unassigned = 0, classes = {}, races = {}, specs = {} }
    if not Members.CanView() then return stats end
    for _, class in ipairs({ { "WARRIOR", "Warrior" }, { "PALADIN", "Paladin" }, { "HUNTER", "Hunter" },
        { "ROGUE", "Rogue" }, { "PRIEST", "Priest" }, { "SHAMAN", "Shaman" }, { "MAGE", "Mage" },
        { "WARLOCK", "Warlock" }, { "DRUID", "Druid" } }) do
        local localized = addon.Compat.Field(LOCALIZED_CLASS_NAMES_MALE, class[1])
        stats.classes[type(localized) == "string" and localized or class[2]] = 0
    end
    for _, row in ipairs(rows or Members.Rows()) do
        stats.all = stats.all + 1
        if row.state == "Main" then stats.mains = stats.mains + 1
        elseif row.state == "Alt" then stats.alts = stats.alts + 1
        else stats.unassigned = stats.unassigned + 1 end
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
    if not previous or not previous.factsRevision or previous.id ~= id then
        database.profiles[sender] = { id = id, race = race, spec = spec, talents = talents, updatedAt = updatedAt }
    end
    if not existing or revision > existing.revision then
        database.groups[id] = { revision = revision, main = main, discord = discord }
    end
    Prune(database)
    Changed()
    return true
end

local function Rejected(reason)
    Members.status = "Member profile rejected: " .. reason
    if addon.LogEvent then addon.LogEvent("MEMBER_PROFILE_REJECTED", { reason = reason }) end
    return false
end

local function Payload(values)
    local encoded = {}
    for index, value in ipairs(values) do encoded[index] = Escape(value) end
    return table.concat(encoded, "~")
end

local function Snapshot(owner, recipient)
    local database = Context()
    local profile = database and database.profiles[owner]
    local group = profile and database.groups[profile.id]
    if not addon.GuildState.Resolve(owner) or not profile or not group
        or not Integer(profile.factsRevision, 2147483647) or profile.factsRevision < 1 then return nil end
    if group.main ~= "" and not addon.GuildState.Resolve(group.main) then return nil end
    if not Text(profile.id, 40) or not profile.id:match("^%d+%-%d+%-%d+$")
        or not Integer(group.revision, 2147483647) or group.revision < 1
        or not Text(group.main, 100) or not Text(group.discord, 32)
        or not Text(profile.race, 40) or not Text(profile.spec, 60) or not Text(profile.talents, 320)
        or not Integer(profile.updatedAt, 4294967295) then Rejected("format"); return nil end
    local values = { addon.GuildState.key, profile.id, group.revision, group.main, group.discord,
        profile.race, profile.spec, profile.talents, profile.updatedAt, "3", owner, profile.factsRevision, "" }
    local canonical = Payload(values)
    values[13] = recipient or ""
    local payload = Payload(values)
    if #payload > 1200 then Rejected("format"); return nil end
    return payload, addon.Compat.Fingerprint(canonical), group.revision, profile.factsRevision
end

local function QueueRelay(messages, owner, recipient)
    local queued = addon.Sync and addon.Sync.QueueMembers
        and addon.Sync.QueueMembers(messages, { memberRelay = true, owner = owner, recipient = recipient, expires = Now() + 180 })
    if not queued then
        Members.status = "Member catch-up could not be queued; retry scheduled"
        if addon.LogEvent then addon.LogEvent("MEMBER_QUEUE_REJECTED") end
    end
    return queued
end

ScheduleInventory = function()
    local due = Now() + 3
    inventoryDue = inventoryDue and math.min(inventoryDue, due) or due
end

function Members.Reconcile()
    if not Context() or not C_Timer or type(C_Timer.After) ~= "function" then return false end
    if inventoryBuild then return true end
    local database, scope, ticket = Context(), addon.GuildState.key, {}
    local owners = {}
    for owner in pairs(database.profiles) do owners[#owners + 1] = owner end
    table.sort(owners)
    local cursor, processed = math.min(inventoryCursor, math.max(1, #owners)), 0
    inventoryBuild = ticket
    local function Step()
        if inventoryBuild ~= ticket then return end
        if not Context() or addon.GuildState.key ~= scope then inventoryBuild = nil; return end
        local owner = owners[cursor]
        if owner and processed < 8 then
            local _, checksum, revision, factsRevision = Snapshot(owner)
            if checksum then
                local message = "2|I|" .. Escape(scope) .. "|"
                    .. table.concat({ Escape(owner), revision, factsRevision, checksum }, "~")
                if not QueueRelay({ message }, owner) then
                    inventoryBuild, inventoryCursor, inventoryDue = nil, cursor, Now() + 15
                    return
                end
            end
            cursor, processed = cursor + 1, processed + 1
            C_Timer.After(0, Step)
        else
            inventoryBuild = nil
            inventoryCursor = cursor <= #owners and cursor or 1
            inventoryDue = Now() + (inventoryCursor == 1 and 180 or 15)
        end
    end
    C_Timer.After(0, Step)
    return true
end

local function NeedsReport(owner, revision, factsRevision, checksum)
    local _, currentChecksum, currentRevision, currentFacts = Snapshot(owner)
    if not currentChecksum then return true end
    if revision > currentRevision or factsRevision > currentFacts then return true end
    if revision == currentRevision and factsRevision == currentFacts and checksum ~= currentChecksum then Rejected("conflict") end
    return false
end

local function RequestReport(owner, offer, attempt)
    local provider = offer.providers[math.min(attempt, #offer.providers)]
    if not provider or not addon.GuildState.Resolve(provider) then return false end
    counter = counter + 1
    local transfer = math.floor(Now() * 1000) .. "-" .. counter
    local message = table.concat({ "2", "W", transfer, Escape(addon.GuildState.key),
        Escape(provider), Escape(owner), offer.checksum }, "|")
    if not QueueRelay({ message }, owner, provider) then return false end
    recovery[owner] = { transfer = transfer, provider = provider, checksum = offer.checksum,
        revision = offer.revision, factsRevision = offer.factsRevision, attempt = attempt, deadline = Now() + 180 }
    return true
end

local function StoreSnapshot(owner, fields)
    local database = Context()
    local id, revision, factsRevision = fields[2], tonumber(fields[3]), tonumber(fields[12])
    local previous, group = database.profiles[owner], database.groups[id]
    if previous and previous.id ~= id then return Rejected("identity") end
    if id == database.own.id and (revision > database.own.revision
        or (revision == database.own.revision and (fields[4] ~= database.own.main
            or fields[5] ~= (database.own.discordNicknameVersion == 1 and database.own.discord or "")))) then
        return Rejected("conflict")
    end
    if group and revision == group.revision and (fields[4] ~= group.main or fields[5] ~= group.discord) then
        return Rejected("conflict")
    end
    if previous and previous.factsRevision == factsRevision
        and (previous.race ~= fields[6] or previous.spec ~= fields[7] or previous.talents ~= fields[8]
            or previous.updatedAt ~= tonumber(fields[9])) then return Rejected("conflict") end
    if not group or revision > group.revision then
        database.groups[id] = { revision = revision, main = fields[4], discord = fields[5] }
    end
    if not previous or not previous.factsRevision or factsRevision > previous.factsRevision then
        database.profiles[owner] = { id = id, race = fields[6], spec = fields[7], talents = fields[8],
            updatedAt = tonumber(fields[9]), factsRevision = factsRevision }
    end
    Prune(database)
    Members.status = "Member profile catch-up applied"
    Changed()
    return true
end

ReceiveRelay = function(sender, message)
    local scope, row = message:match("^2|I|([^|]+)|([^|]+)$")
    if scope then
        if scope ~= Escape(addon.GuildState.key) then return end
        local owner, revision, factsRevision, checksum = row:match("^([^~]+)~(%d+)~(%d+)~(%d+%-%d+)$")
        owner = owner and owner:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
        owner = owner and addon.GuildState.Resolve(owner)
        revision, factsRevision = tonumber(revision), tonumber(factsRevision)
        if not owner or addon.Compat.IsPlayerName(owner) or not Integer(revision, 2147483647) or revision < 1
            or not Integer(factsRevision, 2147483647) or factsRevision < 1 or #checksum > 11 then return end
        if not NeedsReport(owner, revision, factsRevision, checksum) then return end
        local offer = offers[owner]
        if not offer or revision > offer.revision or (revision == offer.revision and factsRevision > offer.factsRevision) then
            local previousRequest = recovery[owner]
            if previousRequest then relayAssemblies[previousRequest.provider .. "|" .. previousRequest.transfer] = nil end
            offer = { revision = revision, factsRevision = factsRevision, checksum = checksum, providers = { sender } }
            offers[owner], recovery[owner] = offer, nil
        end
        if offer.revision ~= revision or offer.factsRevision ~= factsRevision then return end
        if offer.checksum ~= checksum then return Rejected("conflict") end
        local found = false
        for _, provider in ipairs(offer.providers) do if provider == sender then found = true end end
        if not found and #offer.providers < 3 then offer.providers[#offer.providers + 1] = sender end
        offer.updatedAt = Now()
        local count = 0
        for _ in pairs(recovery) do count = count + 1 end
        if not recovery[owner] and count < 8 and (not offer.cooldown or Now() >= offer.cooldown) then RequestReport(owner, offer, 1) end
        return
    end
    local transfer, requestScope, provider, owner, checksum = message:match("^2|W|(%d+%-%d+)|([^|]+)|([^|]+)|([^|]+)|(%d+%-%d+)$")
    if transfer then
        if #transfer > 40 or requestScope ~= Escape(addon.GuildState.key) then return end
        if provider ~= Escape(Members.Self() or "") then return end
        owner = owner:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
        owner = addon.GuildState.Resolve(owner)
        if not owner then return end
        local payload, currentChecksum = Snapshot(owner, sender)
        if not payload or checksum ~= currentChecksum then return end
        local key = sender .. "|" .. owner
        if recentReplies[key] and Now() - recentReplies[key] < 10 then return end
        local count = 0
        for previous, stamp in pairs(recentReplies) do
            if Now() - stamp >= 10 then recentReplies[previous] = nil else count = count + 1 end
        end
        if count >= 128 then return end
        local packets, total = {}, math.ceil(#payload / 140)
        for part = 1, total do
            packets[#packets + 1] = table.concat({ "2", "R", transfer, part, total,
                payload:sub((part - 1) * 140 + 1, part * 140) }, "|")
        end
        if QueueRelay(packets, owner, sender) then recentReplies[key] = Now() end
        return
    end
    local part, total, piece
    transfer, part, total, piece = message:match("^2|R|(%d+%-%d+)|(%d+)|(%d+)|(.*)$")
    part, total = tonumber(part), tonumber(total)
    if not transfer or #transfer > 40 or not part or not total or total < 1 or total > 9
        or part < 1 or part > total or #piece > 140 then return end
    local requestedOwner, request
    for candidate, pendingRequest in pairs(recovery) do
        if pendingRequest.transfer == transfer and pendingRequest.provider == sender then requestedOwner, request = candidate, pendingRequest; break end
    end
    if not request then return end
    local key = sender .. "|" .. transfer
    local assembly = relayAssemblies[key]
    if not assembly then
        assembly = { pieces = {}, total = total, received = 0, bytes = 0 }
        relayAssemblies[key] = assembly
    end
    if assembly.total ~= total then return Rejected("format") end
    if assembly.pieces[part] and assembly.pieces[part] ~= piece then return Rejected("conflict") end
    if not assembly.pieces[part] then
        assembly.pieces[part] = piece
        assembly.received, assembly.bytes = assembly.received + 1, assembly.bytes + #piece
    end
    if assembly.bytes > 1200 then relayAssemblies[key] = nil; return Rejected("format") end
    if assembly.received ~= total then return end
    relayAssemblies[key] = nil
    local fields = Decode(table.concat(assembly.pieces), 13)
    if not fields or fields[1] ~= addon.GuildState.key or fields[10] ~= "3" or fields[11] ~= requestedOwner
        or not addon.GuildState.Resolve(requestedOwner) or addon.Compat.IsPlayerName(requestedOwner)
        or fields[13] ~= Members.Self() or not Text(fields[2], 40) or not fields[2]:match("^%d+%-%d+%-%d+$")
        or tonumber(fields[3]) ~= request.revision or tonumber(fields[12]) ~= request.factsRevision
        or not Text(fields[4], 100) or not Text(fields[5], 32) or not Text(fields[6], 40) or not Text(fields[7], 60)
        or not Text(fields[8], 320) or not Integer(tonumber(fields[9]), 4294967295)
        or (fields[4] ~= "" and not addon.GuildState.Resolve(fields[4])) then return Rejected("format") end
    fields[13] = ""
    if addon.Compat.Fingerprint(Payload(fields)) ~= request.checksum then return Rejected("checksum") end
    if StoreSnapshot(requestedOwner, fields) then recovery[requestedOwner], offers[requestedOwner] = nil, nil end
end

function Members.Maintain()
    if not Members.started or not Context() then return end
    local now = Now()
    if inventoryDue and now >= inventoryDue then Members.Reconcile() end
    local count = 0
    for _ in pairs(recovery) do count = count + 1 end
    for owner, offer in pairs(offers) do
        local request = recovery[owner]
        if request and not addon.GuildState.Resolve(request.provider) then request.deadline = now end
        if not addon.GuildState.Resolve(owner) then
            if request then relayAssemblies[request.provider .. "|" .. request.transfer] = nil end
            offers[owner], recovery[owner] = nil, nil
            if request then count = count - 1 end
        elseif request and now >= request.deadline then
            relayAssemblies[request.provider .. "|" .. request.transfer] = nil
            if request.attempt >= 3 then
                recovery[owner], offer.cooldown = nil, now + 180
                count = count - 1
                if addon.LogEvent then addon.LogEvent("MEMBER_RECOVERY_EXHAUSTED") end
            elseif not RequestReport(owner, offer, request.attempt + 1) then
                request.attempt, request.deadline = request.attempt + 1, now + 180
            end
        elseif not request and count < 8 and now - offer.updatedAt < 360
            and (not offer.cooldown or now >= offer.cooldown) then
            if RequestReport(owner, offer, 1) then count = count + 1 end
        elseif not request and now - offer.updatedAt >= 360 then offers[owner] = nil end
    end
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
    if message:sub(1, 2) == "2|" then ReceiveRelay(sender, message); return end
    if message == "1|Q|" .. Escape(addon.GuildState.key) then
        if not requests[sender] or now - requests[sender] >= 30 then
            requests[sender] = now
            Members.Schedule()
            ScheduleInventory()
        end
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
        ScheduleInventory()
    end
    Changed()
end

function Members.Start()
    Members.started = true
    if not listener then
        listener = CreateFrame("Frame")
        for _, event in ipairs({ "PLAYER_TALENT_UPDATE", "ACTIVE_COMBAT_CONFIG_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
            "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_CREATED", "TRAIT_CONFIG_DELETED", "TRAIT_CONFIG_LIST_UPDATED" }) do
            addon.Compat.Call(listener.RegisterEvent, listener, event)
        end
        listener:SetScript("OnEvent", function() Members.Schedule() end)
        local elapsedTotal = 0
        listener:SetScript("OnUpdate", function(_, elapsed)
            if not addon.Compat.IsReadable(elapsed) or type(elapsed) ~= "number" or elapsed ~= elapsed
                or elapsed < 0 or elapsed > 60 then return end
            elapsedTotal = elapsedTotal + elapsed
            if elapsedTotal >= 1 then elapsedTotal = 0; Members.Maintain() end
        end)
    end
    Members.RosterReady()
end