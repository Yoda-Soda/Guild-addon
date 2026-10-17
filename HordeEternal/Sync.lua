local _, addon = ...

local Sync = { status = "Sharing disabled" }
addon.Sync = Sync

local PREFIX = "HERC2"
local CHUNK_SIZE = 170
local MAX_MESSAGE_SIZE = 220
local MAX_PARTS = 96
local MAX_PROFILE_BYTES = CHUNK_SIZE * MAX_PARTS
local MAX_RECIPES = 1200
local MAX_REMOTE_PROFILES = 100
local MAX_REMOTE_RECIPES = 20000
local MAX_QUEUE = 120
local SEND_INTERVAL = 1.1
local MAX_ASSEMBLIES = 32
local ASSEMBLY_TTL = 180

local queue = {}
local queueRunning = false
local queueSerial = 0
local pendingReset
local announcedSerial
local transferCounter = 0
local assemblies = {}
local lastRequestBySender = {}
local receiveWindows = {}
local listener = CreateFrame("Frame")

local function Now()
    local value = addon.Compat.Value(GetTime)
    return type(value) == "number" and value or 0
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
    ClearQueue()
    queueSerial = queueSerial + 1
    queueRunning = false
    assemblies, lastRequestBySender, receiveWindows = {}, {}, {}
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

local function CommunicationReady()
    if not C_ChatInfo or type(C_ChatInfo.RegisterAddonMessagePrefix) ~= "function"
        or type(C_ChatInfo.IsAddonMessagePrefixRegistered) ~= "function"
        or type(C_ChatInfo.SendAddonMessage) ~= "function"
        or not C_Timer or type(C_Timer.After) ~= "function" then
        Sync.status = "Guild message APIs unavailable"
        return false
    end
    if addon.Compat.Value(C_ChatInfo.IsAddonMessagePrefixRegistered, PREFIX) ~= true then
        addon.Compat.Call(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
    if addon.Compat.Value(C_ChatInfo.IsAddonMessagePrefixRegistered, PREFIX) ~= true then
        Sync.status = "Guild message prefix registration failed"
        return false
    end
    return true
end

local function SendOne(job)
    if not GuildReady() then return false end
    if job.scope ~= addon.GuildState.key or job.generation ~= addon.GuildState.Generation()
        or job.serial ~= addon.GuildState.serial then return false end
    if not job.control and (not addon.Catalog.scannedThisSession
        or job.profile ~= addon.Catalog.Initialize().localProfile) then
        Sync.status = "Discarded a queued profile superseded by a rescan"
        return true
    end
    if not CommunicationReady() then
        return false
    end
    local results, state = addon.Compat.Call(C_ChatInfo.SendAddonMessage, PREFIX, job.message, "GUILD")
    if not results then
        Sync.status = "Guild send " .. state
        return false
    end
    local resultType = Enum and Enum.SendAddonMessageResult
    if not resultType or results[2] ~= resultType.Success then
        Sync.status = "Guild message rejected or delivery unconfirmed (result: "
            .. addon.Compat.SafeText(results[2]) .. ")"
        return false
    end
    Sync.status = "Guild message accepted; delivery is unconfirmed"
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

local function Queue(message, control)
    if type(message) ~= "string" or #message > MAX_MESSAGE_SIZE or #queue >= MAX_QUEUE then
        Sync.status = "Guild sync queue full or message too large"
        return false
    end
    queue[#queue + 1] = {
        message = message, control = control,
        scope = addon.GuildState.key, generation = addon.GuildState.Generation(),
        serial = addon.GuildState.serial,
        profile = not control and addon.Catalog.Initialize().localProfile or nil,
    }
    Pump()
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
        return false
    end
    if not addon.Catalog.scannedThisSession then
        Sync.status = "Rescan this character before publishing recipes"
        return false
    end
    if not CommunicationReady() or not GuildReady() then return false end
    local rows = BuildRows(profile)
    if not rows then
        Sync.status = "Local recipe profile is invalid or too large"
        return false
    end
    local payload = table.concat(rows, ";")
    if #payload > MAX_PROFILE_BYTES then
        Sync.status = "Recipe profile exceeds the sync limit"
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
        return false
    end
    for part = 1, total do
        local piece = payload:sub((part - 1) * chunkSize + 1, part * chunkSize)
        if not Queue(table.concat({ "2", "P", scope, generation, transferID, tostring(sourceUpdatedAt), tostring(part), tostring(total), piece }, "|")) then
            return false
        end
    end
    Sync.status = "Recipe profile queued in " .. total .. " parts"
    return true
end

function Sync.Request()
    local catalog = addon.db and addon.Catalog.Initialize()
    if not catalog or not GuildReady() or not CommunicationReady() then
        return false
    end
    return Queue(table.concat({ "2", "H", Escape(addon.GuildState.key),
        tostring(addon.GuildState.Generation()), Escape(catalog.resetIssuer or "") }, "|"), true)
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
    local previousCount = type(previous) == "table" and type(previous.recipes) == "table"
        and #previous.recipes or 0
    if (previous == nil and profileCount >= MAX_REMOTE_PROFILES)
        or recipeCount - previousCount + #recipes > MAX_REMOTE_RECIPES then
        Sync.status = "Remote recipe cache limit reached"
        return false
    end
    remoteProfiles[sender] = {
        recipes = recipes,
        updatedAt = sourceUpdatedAt > 0 and sourceUpdatedAt or time(),
        receivedAt = time(),
    }
    Sync.status = "Received recipe profile from " .. sender
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
        return
    end
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

function Sync.Receive(prefix, message, channel, sender)
    if not addon.Compat.IsReadable(prefix) or not addon.Compat.IsReadable(message)
        or not addon.Compat.IsReadable(channel) or not addon.Compat.IsReadable(sender)
        or prefix ~= PREFIX or channel ~= "GUILD" or type(message) ~= "string"
        or #message > MAX_MESSAGE_SIZE or type(sender) ~= "string" or #sender > 100
        or not GuildReady() or addon.Compat.IsPlayerName(sender) then
        return
    end
    sender = addon.GuildState.Resolve(sender)
    if not sender or not AllowReceive(sender) then return end
    local kind, scope, generation, body = message:match("^2|([A-Z])|([^|]+)|(%d+)|(.*)$")
    generation = tonumber(generation)
    if not kind or Unescape(scope) ~= addon.GuildState.key or not generation
        or generation < 1 or generation > 2147483647 then return end
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
    if kind ~= "P" or generation ~= addon.GuildState.Generation() then
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
        Sync.status = "Only Podcast Clawson, uniquely identified in this guild, can create a crafting reset"
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
    Sync.status = "Sharing disabled; received profiles remain cached locally"
    return true
end