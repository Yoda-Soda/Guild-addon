local _, addon = ...

local Sync = { status = "Sharing disabled" }
addon.Sync = Sync

local PREFIX = "HERC2"
local CHUNK_SIZE = 170
local MAX_MESSAGE_SIZE = 220
local MAX_PARTS = 96
local MAX_PROFILE_BYTES = CHUNK_SIZE * MAX_PARTS
local MAX_RECIPES = 1200
local MAX_REMOTE_PROFILES = 1000
local MAX_REMOTE_RECIPES = 100000
local MAX_QUEUE = 120
local SEND_INTERVAL = 1.1
local MAX_ASSEMBLIES = 32
local ASSEMBLY_TTL = 180
local REQUEST_TIMEOUT = 300
local RECONCILE_INTERVAL = 180
local MAX_REQUESTS = 8
local INVENTORY_BATCH = 8
local QUEUE_RESERVE = 16
local INVENTORY_BATCH_INTERVAL = 15

local queue = {}
local queueRunning = false
local queueSerial = 0
local pendingReset
local announcedSerial
local transferCounter = 0
local assemblies = {}
local lastRequestBySender = {}
local receiveWindows = {}
local inventoryBook, requests, snapshotAssemblies = {}, {}, {}
local lastSnapshotRequest = {}
local inventoryDue
local inventoryBuild
local inventoryCursor = 1
local maintenanceElapsed = 0
local stats = { applied = 0, retries = 0, failed = 0 }
local QueueInventory, ReceiveInventory, ReceiveRequest, ReceiveSnapshot
local listener = CreateFrame("Frame")

local function Now()
    local value = addon.Compat.Value(GetTime)
    return type(value) == "number" and value or 0
end

local function ScheduleInventory()
    local due = Now() + 3
    inventoryDue = inventoryDue and math.min(inventoryDue, due) or due
end

local function Escape(value)
    local text = tostring(value or ""):gsub("%%", "%%25")
    text = text:gsub("|", "%%7C"):gsub("~", "%%7E"):gsub(";", "%%3B")
    return (text:gsub("%c", " "))
end

local function Unescape(value)
    return (value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function Split(value, separator)
    local result = {}
    local start = 1
    while true do
        local index = value:find(separator, start, true)
        if not index then
            result[#result + 1] = value:sub(start)
            return result
        end
        result[#result + 1] = value:sub(start, index - 1)
        start = index + #separator
    end
end

local function IsGuildMember()
    local isInGuild = addon.Compat.Value(IsInGuild)
    return isInGuild == true
end

local function SharingEnabled()
    local catalog = addon.db and addon.Catalog.Initialize()
    return catalog and catalog.shareEnabled == true
end

local function ClearQueue()
    for index = #queue, 1, -1 do
        queue[index] = nil
    end
end

function Sync.Invalidate()
    local retained = {}
    if addon.GuildState and addon.GuildState.ready then
        for _, job in ipairs(queue) do
            if job.prefix == "HEGM1" and job.scope == addon.GuildState.key then
                job.generation, job.serial = addon.GuildState.Generation(), addon.GuildState.serial
                retained[#retained + 1] = job
            end
        end
    end
    ClearQueue()
    for _, job in ipairs(retained) do queue[#queue + 1] = job end
    queueSerial = queueSerial + 1
    queueRunning = false
    assemblies, lastRequestBySender, receiveWindows = {}, {}, {}
    inventoryBook, requests, snapshotAssemblies = {}, {}, {}
    lastSnapshotRequest = {}
    inventoryDue = nil
    inventoryBuild = nil
    inventoryCursor = 1
    pendingReset = nil
end

local function GuildReady()
    if not IsGuildMember() then
        if addon.GuildState then addon.GuildState.CheckContext() end
        Sync.status = "Join a guild before syncing"
        return false
    end
    if not addon.GuildState or not addon.GuildState.IsReady() then
        Sync.status = "Guild sync paused: waiting for a complete readable roster"
        return false
    end
    return true
end

local function CommunicationReady(prefix)
    prefix = prefix or PREFIX
    if not C_ChatInfo or type(C_ChatInfo.RegisterAddonMessagePrefix) ~= "function"
        or type(C_ChatInfo.IsAddonMessagePrefixRegistered) ~= "function"
        or type(C_ChatInfo.SendAddonMessage) ~= "function"
        or not C_Timer or type(C_Timer.After) ~= "function" then
        Sync.status = "Guild message APIs unavailable"
        if addon.LogEvent then addon.LogEvent("COMM_UNAVAILABLE") end
        return false
    end
    if addon.Compat.Value(C_ChatInfo.IsAddonMessagePrefixRegistered, prefix) ~= true then
        addon.Compat.Call(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
    end
    if addon.Compat.Value(C_ChatInfo.IsAddonMessagePrefixRegistered, prefix) ~= true then
        Sync.status = "Guild message prefix registration failed"
        if addon.LogEvent then addon.LogEvent("COMM_UNAVAILABLE") end
        return false
    end
    return true
end

local function SendOne(job)
    if not GuildReady() then return false end
    if job.scope ~= addon.GuildState.key or job.generation ~= addon.GuildState.Generation()
        or job.serial ~= addon.GuildState.serial then return false end
    if job.recipe and not SharingEnabled() then return true end
    if job.request and requests[job.owner] ~= job.request then return true end
    if job.owner and not addon.GuildState.Resolve(job.owner) then return true end
    if job.recipient and not addon.GuildState.Resolve(job.recipient) then return true end
    if job.expires and Now() > job.expires then return true end
    if job.ownProfile and (not addon.Catalog.scannedThisSession
        or job.ownProfile ~= addon.Catalog.Initialize().localProfile) then return true end
    if job.snapshot and addon.Catalog.Initialize().remoteProfiles[job.owner] ~= job.snapshot then return true end
    if job.prefix == "HEGM1" and addon.Members and job.memberVersion ~= addon.Members.wireVersion then return true end
    if not job.control and (not addon.Catalog.scannedThisSession
        or job.profile ~= addon.Catalog.Initialize().localProfile) then
        Sync.status = "Discarded a queued profile superseded by a rescan"
        return true
    end
    if not CommunicationReady(job.prefix) then
        return false
    end
    local results, state = addon.Compat.Call(C_ChatInfo.SendAddonMessage, job.prefix or PREFIX, job.message, "GUILD")
    if not results then
        Sync.status = "Guild send " .. state
        if addon.LogEvent then addon.LogEvent("SEND_UNAVAILABLE", { state = state }) end
        return false
    end
    local resultType = Enum and Enum.SendAddonMessageResult
    if not resultType or results[2] ~= resultType.Success then
        Sync.status = "Guild message rejected or delivery unconfirmed (result: "
            .. addon.Compat.SafeText(results[2]) .. ")"
        if addon.LogEvent then addon.LogEvent("SEND_REJECTED", { result = results[2] }) end
        return false
    end
    Sync.status = "Guild message accepted; delivery is unconfirmed"
    if addon.LogEvent then addon.LogEvent("SEND_ACCEPTED", { bytes = #job.message }) end
    return true
end

local function Pump()
    if queueRunning or #queue == 0 then
        return
    end
    if not SharingEnabled() and not queue[1].control then
        ClearQueue()
        return
    end
    if not CommunicationReady() or not GuildReady() then
        return
    end
    queueRunning = true
    local scheduledSerial = queueSerial
    C_Timer.After(SEND_INTERVAL, function()
        if scheduledSerial ~= queueSerial then return end
        queueRunning = false
        if #queue == 0 then return end
        if not SharingEnabled() and not queue[1].control then
            ClearQueue()
            return
        end
        if SendOne(queue[1]) then
            table.remove(queue, 1)
            Pump()
        end
    end)
end

local function Queue(message, control, prefix, metadata)
    if type(message) ~= "string" or #message > MAX_MESSAGE_SIZE or #queue >= MAX_QUEUE then
        Sync.status = "Guild sync queue full or message too large"
        if addon.LogEvent then addon.LogEvent("QUEUE_REJECTED", { queued = #queue,
            bytes = type(message) == "string" and #message or 0 }) end
        return false
    end
    local job = {
        message = message, control = control, prefix = prefix,
        memberVersion = prefix == "HEGM1" and addon.Members and addon.Members.wireVersion or nil,
        scope = addon.GuildState.key, generation = addon.GuildState.Generation(),
        serial = addon.GuildState.serial,
        profile = not control and addon.Catalog.Initialize().localProfile or nil,
    }
    for key, value in pairs(metadata or {}) do job[key] = value end
    queue[#queue + 1] = job
    Pump()
    return true
end

function Sync.QueueMembers(messages)
    if not GuildReady() or not CommunicationReady("HEGM1") or type(messages) ~= "table"
        or #messages < 1 or #messages > 9 or #queue + #messages > MAX_QUEUE then return false end
    for _, message in ipairs(messages) do
        if type(message) ~= "string" or #message > MAX_MESSAGE_SIZE then return false end
    end
    for _, message in ipairs(messages) do Queue(message, true, "HEGM1") end
    return true
end

local function BuildRows(profile)
    if type(profile) ~= "table" or type(profile.recipes) ~= "table"
        or #profile.recipes > MAX_RECIPES then
        return nil
    end
    local rows = {}
    for _, recipe in ipairs(profile.recipes) do
        if type(recipe) == "table" and type(recipe.recipeID) == "number"
            and type(recipe.itemName) == "string" then
            rows[#rows + 1] = table.concat({
                tostring(recipe.recipeID),
                tostring(tonumber(recipe.skillLineID) or 0),
                Escape(recipe.professionName),
                Escape(recipe.itemName),
                Escape(recipe.recipeName),
            }, "~")
        end
    end
    table.sort(rows)
    return rows
end

function Sync.Publish()
    local catalog = addon.db and addon.Catalog.Initialize()
    local profile = catalog and catalog.localProfile
    if not catalog or catalog.shareEnabled ~= true or type(profile) ~= "table" then
        Sync.status = "Enable sharing and scan recipes first"
        if addon.LogEvent then addon.LogEvent("PUBLISH_BLOCKED", { reason = "sharing" }) end
        return false
    end
    if not addon.Catalog.scannedThisSession then
        Sync.status = "Rescan this character before publishing recipes"
        if addon.LogEvent then addon.LogEvent("PUBLISH_BLOCKED", { reason = "scan" }) end
        return false
    end
    if not CommunicationReady() or not GuildReady() then return false end
    for _, job in ipairs(queue) do
        if not job.control and job.profile == profile and job.scope == addon.GuildState.key
            and job.generation == addon.GuildState.Generation() and job.serial == addon.GuildState.serial then
            ScheduleInventory()
            return true
        end
    end
    local rows = BuildRows(profile)
    if not rows then
        Sync.status = "Local recipe profile is invalid or too large"
        if addon.LogEvent then addon.LogEvent("PROFILE_REJECTED", { direction = "send", reason = "format" }) end
        return false
    end
    if #addon.Catalog.PrimaryProfessions(profile) > 2 then
        if addon.LogEvent then addon.LogEvent("PROFESSION_CONFLICT", { count = #addon.Catalog.PrimaryProfessions(profile) }) end
        Sync.status = "Primary profession confirmation required before publishing"
        return false
    end
    local payload = table.concat(rows, ";")
    if #payload > MAX_PROFILE_BYTES then
        Sync.status = "Recipe profile exceeds the sync limit"
        if addon.LogEvent then addon.LogEvent("PROFILE_REJECTED", { direction = "send", reason = "limit" }) end
        return false
    end
    transferCounter = transferCounter + 1
    local transferID = tostring(math.floor(Now() * 1000)) .. "-" .. tostring(transferCounter)
    local sourceUpdatedAt = math.floor(tonumber(profile.updatedAt) or 0)
    local scope = Escape(addon.GuildState.key)
    local generation = tostring(addon.GuildState.Generation())
    local header = table.concat({ "2", "P", scope, generation, transferID, tostring(sourceUpdatedAt), "96", "96", "" }, "|")
    local chunkSize = math.min(CHUNK_SIZE, MAX_MESSAGE_SIZE - #header)
    if chunkSize < 16 then
        Sync.status = "Guild identity exceeds the message limit"
        return false
    end
    local total = math.max(1, math.ceil(#payload / chunkSize))
    if total > MAX_PARTS or #queue + total > MAX_QUEUE then
        Sync.status = "Recipe profile exceeds the sync queue limit"
        if addon.LogEvent then addon.LogEvent("QUEUE_REJECTED", { queued = #queue, bytes = #payload }) end
        return false
    end
    for part = 1, total do
        local piece = payload:sub((part - 1) * chunkSize + 1, part * chunkSize)
        if not Queue(table.concat({ "2", "P", scope, generation, transferID, tostring(sourceUpdatedAt), tostring(part), tostring(total), piece }, "|")) then
            return false
        end
    end
    Sync.status = "Recipe profile queued in " .. total .. " parts"
    ScheduleInventory()
    return true
end

function Sync.Request()
    local catalog = addon.db and addon.Catalog.Initialize()
    if not catalog or not GuildReady() or not CommunicationReady() then
        return false
    end
    local queued = Queue(table.concat({ "2", "H", Escape(addon.GuildState.key),
        tostring(addon.GuildState.Generation()), Escape(catalog.resetIssuer or "") }, "|"), true)
    if queued then ScheduleInventory() end
    return queued
end

local function DecodeProfile(payload)
    local recipes = {}
    local seen = {}
    if payload == "" then return recipes end
    for row in payload:gmatch("[^;]+") do
        if #recipes >= MAX_RECIPES then
            return nil
        end
        local fields = Split(row, "~")
        if #fields ~= 5 then
            return nil
        end
        local recipeID = tonumber(fields[1])
        local skillLineID = tonumber(fields[2])
        local professionName = Unescape(fields[3])
        local itemName = Unescape(fields[4])
        local recipeName = Unescape(fields[5])
        if not recipeID or recipeID < 1 or recipeID > 10000000 or recipeID ~= math.floor(recipeID) or seen[recipeID]
            or not skillLineID or skillLineID < 0 or skillLineID > 10000000 or skillLineID ~= math.floor(skillLineID)
            or #professionName > 80 or #itemName > 120 or #recipeName > 120
            or professionName:find("[%c|]") or itemName:find("[%c|]") or recipeName:find("[%c|]") then
            return nil
        end
        seen[recipeID] = true
        recipes[#recipes + 1] = {
            recipeID = recipeID,
            skillLineID = skillLineID,
            professionName = professionName,
            itemName = itemName,
            recipeName = recipeName,
        }
    end
    return #recipes > 0 and recipes or nil
end

local function AllowReceive(sender)
    local now = Now()
    local window = receiveWindows[sender]
    if not window or now - window.startedAt >= 10 then
        window = { startedAt = now, count = 0 }
        receiveWindows[sender] = window
    end
    window.count = window.count + 1
    return window.count <= 40
end

local function StoreProfile(sender, payload, sourceUpdatedAt)
    local recipes = DecodeProfile(payload)
    local database = addon.db and addon.Catalog.Initialize()
    if not recipes or not database or not GuildReady() or not addon.GuildState.Resolve(sender) then
        if addon.LogEvent then addon.LogEvent("PROFILE_REJECTED", { direction = "receive", reason = "format" }) end
        return false
    end
    if #addon.Catalog.PrimaryProfessions({ recipes = recipes }) > 2 then
        if addon.LogEvent then addon.LogEvent("PROFILE_REJECTED", { direction = "receive", reason = "professions" }) end
        return false
    end
    local remoteProfiles = database.remoteProfiles
    local profileCount, recipeCount = 0, 0
    for name, profile in pairs(remoteProfiles) do
        profileCount = profileCount + 1
        if type(profile) == "table" and type(profile.recipes) == "table" then
            recipeCount = recipeCount + #profile.recipes
        end
    end
    local previous = remoteProfiles[sender]
    if type(previous) == "table" and previous.revision then
        if addon.LogEvent then addon.LogEvent("PROFILE_REJECTED", { direction = "receive", reason = "stale" }) end
        return false
    end
    if type(previous) == "table" and type(previous.updatedAt) == "number" and sourceUpdatedAt > 0
        and previous.updatedAt > sourceUpdatedAt then
        if addon.LogEvent then addon.LogEvent("PROFILE_REJECTED", { direction = "receive", reason = "stale" }) end
        return false
    end
    local previousCount = type(previous) == "table" and type(previous.recipes) == "table"
        and #previous.recipes or 0
    if (previous == nil and profileCount >= MAX_REMOTE_PROFILES)
        or recipeCount - previousCount + #recipes > MAX_REMOTE_RECIPES then
        Sync.status = "Remote recipe cache limit reached"
        if addon.LogEvent then addon.LogEvent("PROFILE_REJECTED", { direction = "receive", reason = "limit" }) end
        return false
    end
    remoteProfiles[sender] = {
        recipes = recipes,
        updatedAt = sourceUpdatedAt > 0 and sourceUpdatedAt or time(),
        receivedAt = time(),
    }
    Sync.status = "Received recipe profile from " .. addon.Compat.CharacterLabel(sender)
    if addon.LogEvent then addon.LogEvent("PROFILE_RECEIVED", { recipes = #recipes }) end
    if addon.RefreshCatalog then
        addon.RefreshCatalog()
    end
    return true
end

local function ReceiveProfile(sender, transferID, sourceUpdatedAt, part, total, piece)
    sourceUpdatedAt = tonumber(sourceUpdatedAt)
    part, total = tonumber(part), tonumber(total)
    if not sourceUpdatedAt or sourceUpdatedAt < 0 or sourceUpdatedAt > 4294967295
        or not transferID:match("^%d+%-%d+$")
        or not part or not total or total < 1 or total > MAX_PARTS or part < 1 or part > total
        or #piece > MAX_MESSAGE_SIZE then
        if addon.LogEvent then addon.LogEvent("PROFILE_REJECTED", { direction = "receive", reason = "format" }) end
        return
    end
    if addon.LogEvent then addon.LogEvent("TRANSFER_CHUNK", { part = part, total = total, bytes = #piece }) end
    local key = sender .. "|" .. transferID
    local now = Now()
    for assemblyKey, current in pairs(assemblies) do
        if now - current.createdAt > ASSEMBLY_TTL then
            assemblies[assemblyKey] = nil
        end
    end
    local assembly = assemblies[key]
    if not assembly or assembly.total ~= total or assembly.sourceUpdatedAt ~= sourceUpdatedAt then
        local count = 0
        for _ in pairs(assemblies) do
            count = count + 1
        end
        if count >= MAX_ASSEMBLIES then
            if addon.LogEvent then addon.LogEvent("PROFILE_REJECTED", { direction = "receive", reason = "limit" }) end
            return
        end
        assembly = {
            createdAt = now,
            total = total,
            sourceUpdatedAt = sourceUpdatedAt,
            parts = {},
            received = 0,
        }
        assemblies[key] = assembly
    end
    if assembly.parts[part] == nil then
        assembly.parts[part] = piece
        assembly.received = assembly.received + 1
    end
    if assembly.received ~= assembly.total then
        return
    end
    local payload = table.concat(assembly.parts)
    assemblies[key] = nil
    if #payload <= MAX_PROFILE_BYTES then
        StoreProfile(sender, payload, assembly.sourceUpdatedAt)
    end
end

local function Integer(value, maximum)
    value = tonumber(value)
    return value and value == value and value >= 0 and value <= maximum and value == math.floor(value) and value or nil
end

local function FingerprintValid(value)
    if type(value) ~= "string" or #value > 11 then return false end
    local first, second = value:match("^(%d+)%-(%d+)$")
    return Integer(first, 65520) ~= nil and Integer(second, 65520) ~= nil
end

local function LocalOwner()
    for _, name in pairs(addon.GuildState.members) do
        if addon.Compat.IsPlayerName(name) then return name end
    end
end

local function VerifiedProfile(owner)
    local database = addon.Catalog.Initialize()
    local profile = database.remoteProfiles[owner]
    if type(profile) ~= "table" or not Integer(profile.revision, 2147483647) or profile.revision < 1
        or profile.generation ~= addon.GuildState.Generation() or not FingerprintValid(profile.fingerprint) then return nil end
    if addon.Compat.IsPlayerName(owner) and (not addon.Catalog.scannedThisSession or profile ~= database.localProfile) then return nil end
    local payload = addon.Catalog.EncodeProfile(profile)
    if not payload or addon.Catalog.Fingerprint(payload) ~= profile.fingerprint then return nil end
    if #addon.Catalog.PrimaryProfessions(profile) > 2 then return nil end
    return profile, payload
end

local function QueueInventoryPackets(header, rows)
    table.sort(rows, function(left, right)
        if (left.own ~= nil) ~= (right.own ~= nil) then return left.own ~= nil end
        return left.text < right.text
    end)
    local packets, pieces, size, ownProfile = {}, {}, #header, nil
    for _, row in ipairs(rows) do
        if #header + #row.text > MAX_MESSAGE_SIZE then return false end
        if size + #row.text + 1 > MAX_MESSAGE_SIZE and #pieces > 0 then
            packets[#packets + 1] = { text = header .. table.concat(pieces, ";"), own = ownProfile }
            pieces, size, ownProfile = {}, #header, nil
        end
        pieces[#pieces + 1], size = row.text, size + #row.text + 1
        ownProfile = row.own or ownProfile
    end
    if #pieces > 0 then packets[#packets + 1] = { text = header .. table.concat(pieces, ";"), own = ownProfile } end
    if #packets == 0 then inventoryCursor = 1; return true end
    local budget = math.min(INVENTORY_BATCH, MAX_QUEUE - #queue - QUEUE_RESERVE)
    if budget < 1 then return false end
    local first = math.min(inventoryCursor, #packets)
    if first > 1 and packets[1].own and budget > 1 then
        Queue(packets[1].text, true, nil, { recipe = true, ownProfile = packets[1].own })
        budget = budget - 1
    end
    local last = math.min(#packets, first + budget - 1)
    for index = first, last do
        local packet = packets[index]
        Queue(packet.text, true, nil, { recipe = true, ownProfile = packet.own })
    end
    inventoryCursor = last < #packets and last + 1 or 1
    return true
end

QueueInventory = function()
    if not SharingEnabled() or not GuildReady() or not CommunicationReady() then return false end
    if inventoryBuild then return true end
    local ticket, serial = {}, queueSerial
    local scope, generation = addon.GuildState.key, addon.GuildState.Generation()
    local header = table.concat({ "2", "I", Escape(scope), tostring(generation), "" }, "|")
    local owners, rows = {}, {}
    for owner in pairs(addon.Catalog.Initialize().remoteProfiles) do owners[#owners + 1] = owner end
    inventoryBuild = ticket
    local cursor = 1
    local function Step()
        if inventoryBuild ~= ticket or serial ~= queueSerial then return end
        if not SharingEnabled() or not GuildReady() or addon.GuildState.key ~= scope
            or addon.GuildState.Generation() ~= generation then
            inventoryBuild = nil
            return
        end
        local owner = owners[cursor]
        if owner then
            cursor = cursor + 1
            if addon.GuildState.Resolve(owner) then
                local profile = VerifiedProfile(owner)
                if profile then
                    rows[#rows + 1] = { text = table.concat({ Escape(owner), profile.revision, profile.fingerprint,
                        #profile.recipes }, "~"), own = addon.Compat.IsPlayerName(owner) and profile or nil }
                end
            end
            C_Timer.After(0, Step)
        else
            inventoryBuild = nil
            local queued = QueueInventoryPackets(header, rows)
            if not queued then
                Sync.status = "Recipe inventory could not be queued; retry scheduled"
                if addon.LogEvent then addon.LogEvent("QUEUE_REJECTED", { queued = #queue }) end
            end
            inventoryDue = Now() + (queued and inventoryCursor == 1 and RECONCILE_INTERVAL or INVENTORY_BATCH_INTERVAL)
        end
    end
    C_Timer.After(0, Step)
    return true
end

local function RequestSnapshot(owner, advertisement, attempt)
    local provider = advertisement.providers[math.min(attempt, #advertisement.providers)]
    if not provider or not addon.GuildState.Resolve(provider) or not LocalOwner() then return false end
    transferCounter = transferCounter + 1
    local request = { id = math.floor(Now() * 1000) .. "-" .. transferCounter, provider = provider,
        revision = advertisement.revision, fingerprint = advertisement.fingerprint, count = advertisement.count,
        deadline = Now() + REQUEST_TIMEOUT, attempt = attempt }
    local message = table.concat({ "2", "W", Escape(addon.GuildState.key), addon.GuildState.Generation(), request.id,
        Escape(provider), Escape(owner), request.revision, request.fingerprint }, "|")
    if #message > MAX_MESSAGE_SIZE or #queue >= MAX_QUEUE then return false end
    requests[owner] = request
    if not Queue(message, true, nil, { recipe = true, request = request, owner = owner, recipient = provider }) then
        requests[owner] = nil
        return false
    end
    return true
end

local function NeedsSnapshot(owner, revision, fingerprint)
    local current = addon.Catalog.Initialize().remoteProfiles[owner]
    if type(current) ~= "table" or not Integer(current.revision, 2147483647) then return true end
    if current.revision < revision then return true end
    if current.revision == revision and current.fingerprint ~= fingerprint then
        if addon.Compat.IsPlayerName(owner) then return true end
        if addon.LogEvent then addon.LogEvent("PROFILE_REJECTED", { direction = "receive", reason = "conflict" }) end
    end
    return false
end

ReceiveInventory = function(sender, body)
    local rows = Split(body, ";")
    if #rows < 1 or #rows > MAX_REMOTE_PROFILES then return end
    local decoded = {}
    for _, row in ipairs(rows) do
        local fields = Split(row, "~")
        if #fields ~= 4 then return end
        local owner = addon.GuildState.Resolve(Unescape(fields[1]))
        local revision, count = Integer(fields[2], 2147483647), Integer(fields[4], MAX_RECIPES)
        if not owner or not revision or revision < 1 or not count or not FingerprintValid(fields[3]) then return end
        decoded[#decoded + 1] = { owner = owner, revision = revision, fingerprint = fields[3], count = count }
    end
    for _, advertised in ipairs(decoded) do
        local owner = advertised.owner
        if NeedsSnapshot(owner, advertised.revision, advertised.fingerprint) then
            local previous = inventoryBook[owner]
            if not previous or advertised.revision > previous.revision then
                local size = 0
                for _ in pairs(inventoryBook) do size = size + 1 end
                if previous or size < MAX_REMOTE_PROFILES then
                    advertised.providers = { sender }
                    inventoryBook[owner] = advertised
                    requests[owner] = nil
                    previous = advertised
                end
            end
            if previous and previous.revision == advertised.revision and previous.fingerprint == advertised.fingerprint
                and previous.count == advertised.count then
                local found = false
                for _, provider in ipairs(previous.providers) do if provider == sender then found = true end end
                if not found and #previous.providers < 3 then previous.providers[#previous.providers + 1] = sender end
                previous.updatedAt = Now()
                if not requests[owner] and (not previous.exhaustedUntil or Now() >= previous.exhaustedUntil) then
                    local activeCount = 0
                    for _ in pairs(requests) do activeCount = activeCount + 1 end
                    if activeCount < MAX_REQUESTS then RequestSnapshot(owner, previous, 1) end
                end
            end
        end
    end
end

ReceiveRequest = function(sender, body)
    local fields = Split(body, "|")
    if #fields ~= 5 or not fields[1]:match("^%d+%-%d+$") or #fields[1] > 40 then return end
    local recipient, owner = addon.GuildState.Resolve(Unescape(fields[2])), addon.GuildState.Resolve(Unescape(fields[3]))
    local revision = Integer(fields[4], 2147483647)
    if recipient ~= LocalOwner() or not owner or not revision or not SharingEnabled() then return end
    local profile, payload = VerifiedProfile(owner)
    if not profile or profile.revision ~= revision or profile.fingerprint ~= fields[5] then return end
    local last = lastSnapshotRequest[sender .. "|" .. owner]
    if last and Now() - last < 10 then return end
    local histories = 0
    for key, stamp in pairs(lastSnapshotRequest) do
        if Now() - stamp >= 10 then lastSnapshotRequest[key] = nil else histories = histories + 1 end
    end
    if histories >= 128 then return end
    local header = table.concat({ "2", "R", Escape(addon.GuildState.key), addon.GuildState.Generation(), fields[1],
        Escape(sender), Escape(owner), profile.revision, profile.fingerprint, math.floor(tonumber(profile.updatedAt) or 0),
        "96", "96", "" }, "|")
    local chunkSize = math.min(CHUNK_SIZE, MAX_MESSAGE_SIZE - #header)
    if chunkSize < 16 then
        if addon.LogEvent then addon.LogEvent("PROFILE_REJECTED", { direction = "send", reason = "limit" }) end
        return
    end
    local total = math.max(1, math.ceil(#payload / chunkSize))
    if total > MAX_PARTS or #queue + total > MAX_QUEUE then
        if addon.LogEvent then addon.LogEvent("PROFILE_REJECTED", { direction = "send", reason = "limit" }) end
        return
    end
    lastSnapshotRequest[sender .. "|" .. owner] = Now()
    for part = 1, total do
        local message = table.concat({ "2", "R", Escape(addon.GuildState.key), addon.GuildState.Generation(), fields[1],
            Escape(sender), Escape(owner), profile.revision, profile.fingerprint, math.floor(tonumber(profile.updatedAt) or 0),
            part, total, payload:sub((part - 1) * chunkSize + 1, part * chunkSize) }, "|")
        Queue(message, true, nil, { recipe = true, owner = owner, recipient = sender, snapshot = profile,
            ownProfile = addon.Compat.IsPlayerName(owner) and profile or nil, expires = Now() + REQUEST_TIMEOUT })
    end
end

ReceiveSnapshot = function(sender, body)
    local fields = Split(body, "|")
    if #fields ~= 9 or not fields[1]:match("^%d+%-%d+$") or #fields[1] > 40 then return end
    local recipient, owner = addon.GuildState.Resolve(Unescape(fields[2])), addon.GuildState.Resolve(Unescape(fields[3]))
    local request = owner and requests[owner]
    local revision, updatedAt = Integer(fields[4], 2147483647), Integer(fields[6], 4294967295)
    local part, total = Integer(fields[7], MAX_PARTS), Integer(fields[8], MAX_PARTS)
    if recipient ~= LocalOwner() or not request or request.id ~= fields[1] or request.provider ~= sender
        or revision ~= request.revision or fields[5] ~= request.fingerprint or not updatedAt
        or not part or not total or part < 1 or total < 1 or part > total then return end
    local key = sender .. "|" .. request.id
    local assembly = snapshotAssemblies[key]
    if not assembly then
        local count, senderCount = 0, 0
        for _, current in pairs(snapshotAssemblies) do
            count = count + 1
            if current.provider == sender then senderCount = senderCount + 1 end
        end
        if count >= MAX_ASSEMBLIES or senderCount >= 4 then return end
        assembly = { parts = {}, total = total, updatedAt = updatedAt, bytes = 0, received = 0, createdAt = Now(),
            provider = sender, owner = owner }
        snapshotAssemblies[key] = assembly
    end
    if assembly.total ~= total or assembly.updatedAt ~= updatedAt then return end
    if not assembly.parts[part] then
        assembly.parts[part] = fields[9]
        assembly.bytes, assembly.received = assembly.bytes + #fields[9], assembly.received + 1
    end
    if assembly.bytes > MAX_PROFILE_BYTES then snapshotAssemblies[key] = nil; return end
    if assembly.received ~= total then return end
    snapshotAssemblies[key] = nil
    local payload = table.concat(assembly.parts)
    local recipes = DecodeProfile(payload)
    if not recipes or #recipes ~= request.count or addon.Catalog.Fingerprint(payload) ~= request.fingerprint
        or addon.Catalog.EncodeProfile({ recipes = recipes }) ~= payload then
        if addon.LogEvent then addon.LogEvent("PROFILE_REJECTED", { direction = "receive", reason = "checksum" }) end
        return
    end
    if #addon.Catalog.PrimaryProfessions({ recipes = recipes }) > 2 then
        if addon.LogEvent then addon.LogEvent("PROFILE_REJECTED", { direction = "receive", reason = "professions" }) end
        return
    end
    local database = addon.Catalog.Initialize()
    local previous = database.remoteProfiles[owner]
    if not NeedsSnapshot(owner, revision, request.fingerprint) then requests[owner] = nil; return end
    local count, recipeCount = 0, 0
    for _, profile in pairs(database.remoteProfiles) do
        count = count + 1
        if type(profile) == "table" and type(profile.recipes) == "table" then recipeCount = recipeCount + #profile.recipes end
    end
    local previousCount = type(previous) == "table" and type(previous.recipes) == "table" and #previous.recipes or 0
    if (not previous and count >= MAX_REMOTE_PROFILES) or recipeCount - previousCount + #recipes > MAX_REMOTE_RECIPES then return end
    database.remoteProfiles[owner] = { recipes = recipes, revision = revision, fingerprint = request.fingerprint,
        generation = addon.GuildState.Generation(), updatedAt = updatedAt, receivedAt = time() }
    requests[owner] = nil
    stats.applied = stats.applied + 1
    Sync.status = "Verified recipe revision " .. revision .. " applied"
    if addon.LogEvent then addon.LogEvent("PROFILE_RECEIVED", { recipes = #recipes }) end
    if addon.Compat.IsPlayerName(owner) and addon.Catalog.scannedThisSession then
        addon.Catalog.Scan()
        inventoryDue = Now() + 3
    end
    if addon.RefreshCatalog then addon.RefreshCatalog() end
end

function Sync.Progress()
    local pending = 0
    for _ in pairs(requests) do pending = pending + 1 end
    return pending, stats.applied, stats.retries, stats.failed
end

function Sync.PruneMembers()
    for owner, advertisement in pairs(inventoryBook) do
        if not addon.GuildState.Resolve(owner) then
            inventoryBook[owner], requests[owner] = nil, nil
        else
            local retained = {}
            for _, provider in ipairs(advertisement.providers) do
                if addon.GuildState.Resolve(provider) then retained[#retained + 1] = provider end
            end
            advertisement.providers = retained
            local request = requests[owner]
            if request and not addon.GuildState.Resolve(request.provider) then request.deadline = Now() end
        end
    end
    for key, assembly in pairs(snapshotAssemblies) do
        if not addon.GuildState.Resolve(assembly.owner) or not addon.GuildState.Resolve(assembly.provider) then
            snapshotAssemblies[key] = nil
        end
    end
    for key in pairs(lastSnapshotRequest) do
        local sender, owner = key:match("^([^|]+)|(.+)$")
        if not addon.GuildState.Resolve(sender) or not addon.GuildState.Resolve(owner) then lastSnapshotRequest[key] = nil end
    end
    for index = #queue, 1, -1 do
        local job = queue[index]
        if (job.owner and not addon.GuildState.Resolve(job.owner))
            or (job.recipient and not addon.GuildState.Resolve(job.recipient))
            or (job.request and requests[job.owner] ~= job.request) then table.remove(queue, index) end
    end
end

function Sync.Reconcile()
    if not Sync.started or not GuildReady() then return false end
    local queued = QueueInventory()
    inventoryDue = Now() + (queued and inventoryCursor == 1 and RECONCILE_INTERVAL or INVENTORY_BATCH_INTERVAL)
    return queued
end

listener:SetScript("OnUpdate", function(_, elapsed)
    if not addon.Compat.IsReadable(elapsed) or type(elapsed) ~= "number" or not Sync.started then return end
    if elapsed ~= elapsed or elapsed < 0 or elapsed > 60 then return end
    maintenanceElapsed = maintenanceElapsed + elapsed
    if maintenanceElapsed < 1 then return end
    maintenanceElapsed = 0
    if not GuildReady() then return end
    local now = Now()
    if inventoryDue and now >= inventoryDue then Sync.Reconcile() end
    for key, assembly in pairs(snapshotAssemblies) do
        if now - assembly.createdAt > ASSEMBLY_TTL then snapshotAssemblies[key] = nil end
    end
    for owner, advertisement in pairs(inventoryBook) do
        local request = requests[owner]
        if request and now >= request.deadline then
            snapshotAssemblies[request.provider .. "|" .. request.id] = nil
            if request.attempt >= 3 then
                requests[owner], advertisement.exhaustedUntil = nil, now + RECONCILE_INTERVAL
                stats.failed = stats.failed + 1
                Sync.status = "Recipe synchronization exhausted three attempts"
                if addon.LogEvent then addon.LogEvent("RECOVERY_EXHAUSTED") end
            elseif RequestSnapshot(owner, advertisement, request.attempt + 1) then
                stats.retries = stats.retries + 1
                if addon.LogEvent then addon.LogEvent("RECOVERY_RETRY", { attempt = request.attempt + 1 }) end
            else
                request.attempt = request.attempt + 1
                request.deadline = now + 30
            end
        elseif not request and (not advertisement.exhaustedUntil or now >= advertisement.exhaustedUntil)
            and now - advertisement.updatedAt < REQUEST_TIMEOUT
            and NeedsSnapshot(owner, advertisement.revision, advertisement.fingerprint) then
            local activeCount = 0
            for _ in pairs(requests) do activeCount = activeCount + 1 end
            if activeCount < MAX_REQUESTS then RequestSnapshot(owner, advertisement, 1) end
        elseif now - advertisement.updatedAt > REQUEST_TIMEOUT * 2 and not request then inventoryBook[owner] = nil end
    end
end)

function Sync.Receive(prefix, message, channel, sender)
    if addon.Compat.IsReadable(prefix) and prefix == "HEGM1" and addon.Members then
        addon.Members.Receive(prefix, message, channel, sender)
        return
    end
    if not addon.Compat.IsReadable(prefix) or not addon.Compat.IsReadable(message)
        or not addon.Compat.IsReadable(channel) or not addon.Compat.IsReadable(sender)
        or prefix ~= PREFIX or channel ~= "GUILD" or type(message) ~= "string"
        or #message > MAX_MESSAGE_SIZE or type(sender) ~= "string" or #sender > 100
        or not GuildReady() or addon.Compat.IsPlayerName(sender) then
        return
    end
    sender = addon.GuildState.Resolve(sender)
    if not sender then
        if addon.LogEvent then addon.LogEvent("MESSAGE_REJECTED", { reason = "sender" }) end
        return
    end
    if not AllowReceive(sender) then
        if addon.LogEvent then addon.LogEvent("MESSAGE_REJECTED", { reason = "rate" }) end
        return
    end
    local kind, scope, generation, body = message:match("^2|([A-Z])|([^|]+)|(%d+)|(.*)$")
    generation = tonumber(generation)
    if not kind or Unescape(scope) ~= addon.GuildState.key or not generation
        or generation < 1 or generation > 2147483647 then
        if addon.LogEvent then addon.LogEvent("MESSAGE_REJECTED", { reason = "format" }) end
        return
    end
    if kind == "H" then
        if body:find("|", 1, true) then return end
        local previousGeneration = addon.GuildState.Generation()
        if generation > previousGeneration then
            if not addon.GuildState.AcceptGeneration(generation, Unescape(body)) then return end
            addon.Catalog.Scan()
            if addon.RefreshCatalog then addon.RefreshCatalog() end
            Sync.status = "Crafting data reset to generation " .. generation
            Sync.Request()
        end
        local now = Now()
        local lastRequest = lastRequestBySender[sender]
        if not lastRequest or now - lastRequest >= 30 then
            lastRequestBySender[sender] = now
            local serial = addon.GuildState.serial
            C_Timer.After(math.random(1, 4), function()
                if not GuildReady() or serial ~= addon.GuildState.serial or not addon.GuildState.Resolve(sender) then return end
                if generation < addon.GuildState.Generation() then Sync.Request()
                elseif SharingEnabled() then Sync.Publish() end
            end)
        end
        return
    end
    if generation ~= addon.GuildState.Generation() then return end
    if (kind == "I" or kind == "W" or kind == "R") and not SharingEnabled() then return end
    if kind == "I" then ReceiveInventory(sender, body); return end
    if kind == "W" then ReceiveRequest(sender, body); return end
    if kind == "R" then ReceiveSnapshot(sender, body); return end
    if kind ~= "P" or generation ~= addon.GuildState.Generation() then
        if addon.LogEvent then addon.LogEvent("MESSAGE_REJECTED", { reason = "generation" }) end
        return
    end
    local transferID, sourceUpdatedAt, part, total, piece = body:match("^([%d%-]+)|(%d+)|(%d+)|(%d+)|(.*)$")
    if transferID then
        ReceiveProfile(sender, transferID, sourceUpdatedAt, part, total, piece)
    end
end

function Sync.Start(publishLocal)
    Sync.started = true
    if not listener:IsEventRegistered("CHAT_MSG_ADDON") then
        pcall(listener.RegisterEvent, listener, "CHAT_MSG_ADDON")
        listener:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
            Sync.Receive(prefix, message, channel, sender)
        end)
    end
    if not addon.db or not GuildReady() then return end
    announcedSerial = addon.GuildState.serial
    Sync.Request()
    if SharingEnabled() and publishLocal ~= false then Sync.Publish() end
end

function Sync.RosterReady()
    if not Sync.started or not GuildReady() or announcedSerial == addon.GuildState.serial then return end
    local scanned = addon.Catalog.Scan()
    Sync.Start(scanned ~= nil)
end

function Sync.ResetCrafting(confirm)
    if not GuildReady() or not addon.GuildState.CanReset() then
        Sync.status = "Only application administrator Pod Cast, uniquely identified in this guild, can create a crafting reset"
        return false
    end
    if not CommunicationReady() then return false end
    local generation = addon.GuildState.Generation()
    if not confirm then
        pendingReset = { generation = generation, serial = addon.GuildState.serial, expires = Now() + 30 }
        Sync.status = "Reset crafting data for this guild? Run /hordeeternal resetcrafting confirm within 30 seconds"
        return false
    end
    if not pendingReset or pendingReset.generation ~= generation or pendingReset.serial ~= addon.GuildState.serial
        or Now() > pendingReset.expires then
        Sync.status = "Reset confirmation expired or guild data changed; run /hordeeternal resetcrafting again"
        return false
    end
    if not addon.GuildState.AcceptGeneration(generation + 1, addon.GuildState.Authority()) then return false end
    local scanned = addon.Catalog.Scan()
    Sync.Request()
    if SharingEnabled() and scanned ~= nil then Sync.Publish() end
    if addon.RefreshCatalog then addon.RefreshCatalog() end
    Sync.status = "Crafting generation " .. (generation + 1) .. " created; guild announcement queued"
    return true
end

function Sync.SetSharing(enabled)
    if type(enabled) ~= "boolean" or not addon.Catalog.SetSharing(enabled) then
        return false
    end
    if enabled then
        local scanned, _, reason = addon.Catalog.Scan()
        Sync.Start(scanned ~= nil)
        if not scanned then
            Sync.status = "Sharing enabled; local scan failed: " .. tostring(reason)
        end
        return true
    end
    ClearQueue()
    inventoryBook, requests, snapshotAssemblies = {}, {}, {}
    lastSnapshotRequest = {}
    inventoryDue = nil
    inventoryBuild = nil
    inventoryCursor = 1
    Sync.status = "Sharing disabled; received profiles remain cached locally"
    return true
end