local addon = { db = {}, characterDB = {} }
assert(loadfile("HordeEternal/Compat.lua"))("HordeEternal", addon)
assert(loadfile("HordeEternal/Catalog.lua"))("HordeEternal", addon)
assert(loadfile("HordeEternal/GuildState.lua"))("HordeEternal", addon)

local guildName = "Horde Eternal"
local inGuild = true
local guildClubId = 503775441
C_Club = { GetGuildClubId = function() return guildClubId end }
local roster = { "Pod Cast-ForeverRealm", "Other Crafter-ForeverRealm" }
local onlineByName = { [roster[1]] = true, [roster[2]] = false }
local playerFirst, playerLast = "Pod", "Cast"
local unavailableRow, restrictedGUID
IsInGuild = function() return inGuild end
GetNormalizedRealmName = function() return "ForeverRealm" end
UnitFullName = function() return playerFirst, playerLast end
GetGuildInfo = function() return guildName, "Member", 5, "ForeverRealm" end
GetNumGuildMembers = function() return #roster end
GetGuildRosterInfo = function(index)
    if index == unavailableRow then return nil end
    return roster[index], "Member", 5, 60, "Mage", "City", "", "", onlineByName[roster[index]], nil, "MAGE", nil, nil, nil, nil, nil, restrictedGUID
end
local invalidations = 0
addon.Sync = { Invalidate = function() invalidations = invalidations + 1 end }
assert(addon.GuildState.IsAllowed(), "the configured guild club must be eligible")
assert(addon.GuildState.RefreshRoster())
assert(addon.GuildState.Resolve("Other Crafter") == roster[2])
local rosterRows = addon.GuildState.Rows()
assert(#rosterRows == 2 and rosterRows[1].name == roster[2]
    and rosterRows[1].classFile == "MAGE" and rosterRows[1].level == 60
    and rosterRows[1].rank == "Member" and rosterRows[1].rankIndex == 5,
    "the verified roster must retain member information for guild statistics")
assert(addon.GuildState.CanReset(), "only the configured local owner can reset")
assert(addon.GuildState.IsAdmin() == true, "Pod Cast must be identified as application administrator")
assert(addon.GuildState.AdminStatus() == "Application admin")
roster[3] = "Podcast Clawson-ForeverRealm"
playerFirst, playerLast = "Podcast", "Clawson"
assert(addon.GuildState.RefreshRoster() and addon.GuildState.IsAdmin() == false and not addon.GuildState.CanReset(),
    "the former administrator identity must not retain application permissions")
assert(addon.GuildState.AdminStatus() == "Guild member")
assert(not addon.GuildState.AcceptGeneration(2, roster[3]), "the former issuer must not authorize a new reset")
roster[3] = nil
playerFirst, playerLast = "Pod", "Cast"
assert(addon.GuildState.RefreshRoster() and addon.GuildState.IsAdmin() == true)
assert(not addon.GuildState.Resolve("Outsider"))
local database = addon.Catalog.Initialize()
assert(addon.GuildState.IsOnline(roster[1]) == true and addon.GuildState.IsOnline("Other Crafter") == false)
assert(addon.GuildState.IsOnline("Outsider") == nil)
roster[3] = "Zed Crafter-ForeverRealm"
onlineByName[roster[3]] = true
local sharedRecipes = { { recipeID = 1001, itemName = "Test item" } }
database.localProfile = { recipes = sharedRecipes }
database.remoteProfiles[roster[2]] = { recipes = sharedRecipes }
database.remoteProfiles[roster[3]] = { recipes = sharedRecipes }
assert(addon.GuildState.RefreshRoster())
local crafters = addon.Catalog.Search("Test item")[1].crafters
assert(crafters[1].name == "You" and crafters[2].name == roster[3] and crafters[3].name == roster[2],
    "online crafters must precede offline crafters, alphabetically within each group")
onlineByName[roster[2]], onlineByName[roster[3]] = true, false
assert(addon.GuildState.RefreshRoster())
crafters = addon.Catalog.Search("Test item")[1].crafters
assert(crafters[1].name == roster[2] and crafters[3].name == roster[3], "roster updates must reorder cached crafters")
onlineByName[roster[2]] = nil
assert(addon.GuildState.RefreshRoster() and addon.GuildState.IsOnline(roster[2]) == nil,
    "missing online status must not be inferred from cached recipes")
database.localProfile, database.remoteProfiles[roster[3]], roster[3] = nil, nil, nil
database.remoteProfiles[roster[2]] = { recipes = {} }
database.remoteProfiles["Departed Member-ForeverRealm"] = { recipes = {} }
unavailableRow = 2
assert(not addon.GuildState.RefreshRoster())
assert(addon.GuildState.IsAdmin() == nil and not addon.GuildState.CanReset(),
    "unreadable rosters must make administrator status unavailable without granting permissions")
assert(addon.GuildState.AdminStatus() == "Admin status unavailable")
assert(#addon.GuildState.Rows() == 0, "an unreadable roster must not expose stale statistics")
assert(addon.GuildState.IsOnline(roster[1]) == nil, "invalidating the roster must discard cached presence")
assert(database.remoteProfiles["Departed Member-ForeverRealm"], "partial rosters must not delete profiles")
assert(next(addon.Catalog.RemoteProfiles()) == nil, "unverified membership must not display crafters")
unavailableRow = nil
local secret = {}
canaccessvalue = function(value) return value ~= secret end
onlineByName[roster[2]] = secret
assert(not addon.GuildState.RefreshRoster() and addon.GuildState.IsOnline(roster[2]) == nil,
    "restricted online values must never authorize whispering")
onlineByName[roster[2]] = false
restrictedGUID = secret
assert(not addon.GuildState.RefreshRoster(), "late inaccessible roster fields must be guarded")
assert(database.remoteProfiles["Departed Member-ForeverRealm"])
canaccessvalue, restrictedGUID = nil, nil
assert(addon.GuildState.RefreshRoster())
assert(database.remoteProfiles["Departed Member-ForeverRealm"] == nil and database.remoteProfiles[roster[2]])
roster[3] = "Pod Cast-OtherRealm"
assert(addon.GuildState.RefreshRoster())
assert(addon.GuildState.IsAdmin() == nil and not addon.GuildState.CanReset(),
    "an ambiguous administrator name must not grant or claim application authority")
roster[3] = nil
playerFirst, playerLast = "Other", "Crafter"
assert(addon.GuildState.RefreshRoster() and addon.GuildState.IsAdmin() == false and not addon.GuildState.CanReset())
guildName = "Another Guild"
guildClubId = 123456
assert(not addon.GuildState.IsAllowed() and not addon.GuildState.RefreshRoster(),
    "another guild must not activate the addon")
database = addon.Catalog.Initialize()
assert(next(database.remoteProfiles) == nil, "changing guild must clear the previous guild's profiles")
database.remoteProfiles[roster[1]] = { recipes = {} }
inGuild = false
assert(not addon.GuildState.IsReady() and next(addon.Catalog.Initialize().remoteProfiles) == nil)
assert(invalidations > 0)
inGuild, guildClubId = true, 503775441
assert(addon.GuildState.RefreshRoster())
local retainedProfile = { recipes = {} }
local retainedProfiles = addon.Catalog.Initialize().remoteProfiles
retainedProfiles[roster[2]] = retainedProfile
guildClubId = nil
assert(not addon.GuildState.IsAllowed() and not addon.GuildState.RefreshRoster())
assert(retainedProfiles[roster[2]] == retainedProfile,
    "temporarily unavailable guild identity must preserve the guild cache")
guildClubId = "503775441"
assert(addon.GuildState.IsAllowed() and addon.GuildState.RefreshRoster(),
    "a readable string club ID must resolve to the same guild")
guildClubId = secret
canaccessvalue = function(value) return value ~= secret end
assert(not addon.GuildState.IsAllowed(), "restricted club IDs must not be compared")
canaccessvalue, guildClubId = nil, 503775441
local directClubApi = C_Club.GetGuildClubId
C_Club.GetGuildClubId = nil
C_Club.GetSubscribedClubs = function()
    return { { clubType = 0, clubId = 503775441 }, { clubType = 2, clubId = guildClubId } }
end
assert(addon.GuildState.IsAllowed(), "subscribed guild identity must not depend on list position")
guildClubId = 123456
assert(not addon.GuildState.IsAllowed(), "a community ID must not authorize another guild")
C_Club.GetGuildClubId, guildClubId = directClubApi, 503775441
local clubApi = C_Club
canaccesstable = function(value) return value ~= clubApi end
assert(not addon.GuildState.IsAllowed(), "inaccessible club namespaces must fail closed before field access")
canaccesstable = nil
C_Club = nil
assert(not addon.GuildState.IsAllowed(), "missing club APIs must not fall back to guild name alone")
C_Club = clubApi
local savedRealmName, savedGuildInfo = GetNormalizedRealmName, GetGuildInfo
local savedRoster, savedOnline = roster, onlineByName
local savedFirst, savedLast = playerFirst, playerLast
local savedGuildKey = addon.GuildState.key
local savedGuildCache = addon.db.craftingGuilds[savedGuildKey]
GetNormalizedRealmName = function() return "" end
GetGuildInfo = function() return guildName, "Member", 5, nil end
assert(addon.GuildState.IsAllowed(), "an explicitly empty home realm must not block the verified guild")
roster, onlineByName = { "Pod Cast", "Other Crafter" }, { ["Pod Cast"] = true, ["Other Crafter"] = false }
playerFirst, playerLast = "Pod", "Cast"
assert(addon.Compat.IsPlayerName("Pod Cast") and not addon.Compat.IsPlayerName("Pod"),
    "realm-less player matching must retain the full surname")
assert(not addon.Compat.IsPlayerName("Pod Cast-OtherRealm"),
    "an empty realm must not authorize an arbitrary realm-qualified identity")
assert(addon.GuildState.RefreshRoster(), "a readable realm-less guild roster must become ready")
assert(addon.GuildState.key == guildName .. "@club:503775441" and addon.GuildState.home == "",
    "realm-less storage must use the verified club scope without inventing a realm")
assert(addon.GuildState.Resolve("Pod Cast") == "Pod Cast"
    and addon.GuildState.Resolve("Other Crafter") == "Other Crafter"
    and addon.GuildState.IsAdmin() == true,
    "realm-less roster and administrator identities must not gain a trailing hyphen")
assert(addon.db.craftingGuilds[savedGuildKey] == savedGuildCache,
    "a realm-less scope must preserve the separate realm-qualified guild cache")
guildClubId = 123456
assert(not addon.GuildState.IsAllowed(), "an empty realm must not bypass the required guild club ID")
guildClubId = 503775441
GetNormalizedRealmName = function() return secret end
canaccessvalue = function(value) return value ~= secret end
assert(not addon.GuildState.IsAllowed() and not addon.Compat.IsPlayerName("Pod Cast"),
    "a restricted realm must not be treated as an explicitly empty realm")
canaccessvalue = nil
GetNormalizedRealmName = function() return nil end
assert(not addon.GuildState.IsAllowed() and not addon.Compat.IsPlayerName("Pod Cast"),
    "a missing realm result must remain unavailable")
GetNormalizedRealmName, GetGuildInfo = savedRealmName, savedGuildInfo
roster, onlineByName, playerFirst, playerLast = savedRoster, savedOnline, savedFirst, savedLast
assert(addon.GuildState.RefreshRoster() and addon.GuildState.key == savedGuildKey
    and addon.db.craftingGuilds[savedGuildKey] == savedGuildCache,
    "restoring realm-qualified identity must reuse its original guild cache")
print("PASS: complete guild rosters, departure cleanup, context changes, and unique owner authorization")
print("PASS: empty-realm guild access, roster/self/admin identity, isolated cache scopes, and restricted/missing realm rejection")

local active, clock = nil, 100
local createdFrames = {}
CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:IsEventRegistered(event) return self.events[event] == true end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    createdFrames[#createdFrames + 1] = frame
    return frame
end
local function Activate(client)
    active = client
    playerFirst, playerLast = client.first, client.last
end
GetTime = function() return clock end
time = function() return 1000 + clock end
C_Timer = { After = function(_, callback) active.timers[#active.timers + 1] = callback end }
Enum = { SendAddonMessageResult = { Success = 0 } }
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    IsAddonMessagePrefixRegistered = function() return true end,
    SendAddonMessage = function(prefix, message, channel)
        assert(prefix == "HERC2" and channel == "GUILD" and #message <= 220)
        active.sent[#active.sent + 1] = message
        return 0
    end,
}
C_GuildInfo = { GuildRoster = function() end }
C_TradeSkillUI = {
    GetAllRecipeIDs = function() return active.ids end,
    GetRecipeInfo = function(recipeID) return { recipeID = recipeID, name = "Recipe " .. recipeID, learned = true } end,
    GetTradeSkillLineForRecipe = function() return 171 end,
    GetTradeSkillDisplayName = function(skill) if skill == 171 then return "Alchemy" end end,
}
SlashCmdList = {}
guildName, inGuild = "Horde Eternal", true
roster = { "Pod Cast-ForeverRealm", "Other Crafter-ForeverRealm", "Returning Member-ForeverRealm", "Alt Character-ForeverRealm" }

local function NewClient(first, last, ids, account, character)
    local client = { first = first, last = last, ids = ids, sent = {}, timers = {}, messages = {}, buttons = 0 }
    local firstFrame = #createdFrames + 1
    Activate(client)
    local instance = {
        Print = function(message) client.messages[#client.messages + 1] = message end,
        CreateMinimapButton = function() client.buttons = client.buttons + 1 end,
    }
    client.addon = instance
    HordeEternalDB = account
    HordeEternalCharacterDB = character
    for _, module in ipairs({ "Compat", "GuildState", "Catalog", "Sync", "Core" }) do
        assert(loadfile("HordeEternal/" .. module .. ".lua"))("HordeEternal", instance)
    end
    client.syncFrame = createdFrames[firstFrame]
    local lifecycle = createdFrames[#createdFrames]
    lifecycle.scripts.OnEvent(lifecycle, "ADDON_LOADED", "HordeEternal")
    lifecycle.scripts.OnEvent(lifecycle, "PLAYER_LOGIN")
    return client
end

local function Flush(client)
    Activate(client)
    local callbacks = 0
    while #client.timers > 0 do
        callbacks = callbacks + 1
        assert(callbacks < 500, "timers must remain bounded")
        table.remove(client.timers, 1)()
    end
end

local function Latest(client, kind)
    for index = #client.sent, 1, -1 do
        if client.sent[index]:sub(1, 4) == "2|" .. kind .. "|" then return client.sent[index] end
    end
    error("missing message kind " .. kind)
end

local function Deliver(message, sender, receiver)
    Activate(receiver)
    receiver.addon.Sync.Receive("HERC2", message, "GUILD", sender.first .. " " .. sender.last .. "-ForeverRealm")
end

local repeatedScan = NewClient("Pod", "Cast", { 1001, 1002, 1003, 1004, 1005, 1006 })
local firstComplete = repeatedScan.addon.Catalog.Initialize().localProfile
assert(repeatedScan.addon.Catalog.Scan() == 6
    and repeatedScan.addon.Catalog.Initialize().localProfile == firstComplete,
    "an unchanged complete rescan must not replace the profile object captured by queued chunks")
assert(repeatedScan.addon.Sync.Publish())
Flush(repeatedScan)
local completeTransfers = {}
for _, message in ipairs(repeatedScan.sent) do
    local id, part, total = message:match("^2|P|[^|]+|%d+|([^|]+)|%d+|(%d+)|(%d+)|")
    if id then
        completeTransfers[id] = completeTransfers[id] or { parts = 0, total = tonumber(total) }
        completeTransfers[id].parts = completeTransfers[id].parts + 1
    end
end
local transferCount = 0
for _, transfer in pairs(completeTransfers) do
    transferCount = transferCount + 1
    assert(transfer.parts == transfer.total, "repeated identical scans must not interrupt a queued transfer")
end
assert(transferCount == 1, "repeated publication of the same queued profile must coalesce instead of flooding the queue")
local beforeRepeatedInventory = #repeatedScan.sent + 1
for _ = 1, 4 do
    Activate(repeatedScan)
    clock = clock + 1
    repeatedScan.addon.Catalog.Scan()
    repeatedScan.addon.Sync.Publish()
    repeatedScan.syncFrame.scripts.OnUpdate(nil, 1)
end
Flush(repeatedScan)
local inventorySent = false
for index = beforeRepeatedInventory, #repeatedScan.sent do
    if repeatedScan.sent[index]:sub(1, 4) == "2|I|" then inventorySent = true end
end
assert(inventorySent, "repeated scans must not indefinitely postpone the inventory needed by upgraded peers")

local account = {
    schemaVersion = 1, minimapPos = 42, minimapPositionVersion = 1, canvasTab = "guild",
    memberGuilds = { preserved = { main = "Podcast Clawson", discord = "test.handle" } },
    futureTool = { preserved = true }, catalog = { localProfile = { recipes = { { recipeID = 999 } } } },
}
local owner = NewClient("Pod", "Cast", { 1001 }, account)
local beforeAdminReport = owner.addon.GuildState.Generation()
SlashCmdList.HORDEETERNAL("admin")
assert(owner.messages[#owner.messages] == "Application role: Application admin"
    and owner.addon.GuildState.Generation() == beforeAdminReport,
    "administrator status must be visible through a read-only command")
local peer = NewClient("Other", "Crafter", { 2001 })
local returning = NewClient("Returning", "Member", { 3001 })
Flush(owner)
Flush(peer)
Flush(returning)
local oldOwnerProfile = Latest(owner, "P")
assert(account.catalog == nil and owner.addon.characterDB.catalog.localProfile.recipes[1].recipeID == 1001,
    "legacy account-wide profession ownership must not migrate to a character")
Activate(peer)
assert(not peer.addon.Sync.ResetCrafting(false) and not peer.addon.Sync.ResetCrafting(true))
assert(peer.addon.GuildState.Generation() == 1)
Activate(owner)
assert(not owner.addon.Sync.ResetCrafting(true), "a destructive reset requires confirmation")
owner.addon.Sync.ResetCrafting(false)
clock = clock + 31
assert(not owner.addon.Sync.ResetCrafting(true), "confirmation must expire")
owner.addon.Sync.Publish()
owner.addon.Sync.ResetCrafting(false)
local beforeReset = #owner.sent
assert(owner.addon.Sync.ResetCrafting(true))
assert(owner.addon.db.craftingGuilds["Horde Eternal@ForeverRealm"].resetIssuer == roster[1],
    "reset issuer missing after reset: shared=" .. tostring(owner.addon.db.craftingGuilds["Horde Eternal@ForeverRealm"].resetIssuer)
        .. " raw=" .. tostring(rawget(owner.addon.characterDB.catalog, "resetIssuer")))
Flush(owner)
assert(owner.addon.GuildState.Generation() == 2)
assert(account.minimapPos == 42 and account.canvasTab == "guild" and account.futureTool.preserved,
    "crafting resets must preserve other addon settings and tools")
assert(account.memberGuilds.preserved.discord == "test.handle", "crafting resets must preserve guild member profiles")
for index = beforeReset + 1, #owner.sent do
    assert(owner.sent[index]:find("|Horde Eternal@ForeverRealm|2|", 1, true), "old queued messages must not survive a reset")
end
Deliver(Latest(owner, "H"), owner, peer)
assert(peer.addon.GuildState.Generation() == 2,
    "peer generation " .. peer.addon.GuildState.Generation() .. " after " .. Latest(owner, "H"))
Deliver(oldOwnerProfile, owner, peer)
assert(peer.addon.Catalog.Initialize().remoteProfiles[roster[1]] == nil, "old-generation packets must not restore cleared profiles")
Deliver(Latest(returning, "H"), returning, peer)
Flush(peer)
Deliver(Latest(peer, "H"), peer, returning)
assert(returning.addon.GuildState.Generation() == 2,
    "a returning member must learn the persisted reset from an online peer without the owner")
Activate(returning)
local resetPrefix = "2|H|Horde Eternal@ForeverRealm|99|"
returning.addon.Sync.Receive("HERC2", resetPrefix .. roster[1], "GUILD", "Outsider-ForeverRealm")
returning.addon.Sync.Receive("HERC2", resetPrefix .. roster[2], "GUILD", roster[2])
returning.addon.Sync.Receive("HERC2", "2|H|Other Guild@ForeverRealm|99|" .. roster[1], "GUILD", roster[2])
returning.addon.Sync.Receive("HERC1", "1|Q|", "GUILD", roster[2])
assert(returning.addon.GuildState.Generation() == 2, "outsiders, wrong issuers, old protocols and other guilds must be rejected")
print("PASS: owner-confirmed crafting resets, offline peer catch-up, generation rejection, and settings preservation")

Activate(peer)
local partPrefix = "2|P|Horde Eternal@ForeverRealm|2|7-1|1131|"
peer.addon.Sync.Receive("HERC2", partPrefix .. "1|2|1001~171~Alchemy~", "GUILD", roster[1])
Activate(owner)
owner.addon.Sync.ResetCrafting(false)
assert(owner.addon.Sync.ResetCrafting(true))
Flush(owner)
Deliver(Latest(owner, "H"), owner, peer)
Activate(peer)
peer.addon.Sync.Receive("HERC2", partPrefix .. "2|2|Recipe 1001~Recipe 1001", "GUILD", roster[1])
assert(peer.addon.Catalog.Initialize().remoteProfiles[roster[1]] == nil, "old partial transfers must not survive reset")
partPrefix = "2|P|Horde Eternal@ForeverRealm|3|8-1|1131|"
peer.addon.Sync.Receive("HERC2", partPrefix .. "2|2|Recipe 1001~Recipe 1001", "GUILD", roster[1])
peer.addon.Sync.Receive("HERC2", partPrefix .. "2|2|Recipe 1001~Recipe 1001", "GUILD", roster[1])
peer.addon.Sync.Receive("HERC2", partPrefix .. "1|2|1001~171~Alchemy~", "GUILD", roster[1])
assert(#peer.addon.Catalog.Initialize().remoteProfiles[roster[1]].recipes == 1,
    "valid reordered chunks and duplicate chunks must assemble once")
peer.addon.Sync.Receive("HERC2", "2|P|Horde Eternal@ForeverRealm|3|9-1|1130|1|1|9998~171~Alchemy~Old item~Old recipe", "GUILD", roster[1])
assert(peer.addon.Catalog.Initialize().remoteProfiles[roster[1]].recipes[1].recipeID == 1001,
    "an older profile arriving late must not replace newer shared crafting data")
peer.ids = {}
assert(peer.addon.Catalog.Scan() == 0 and not peer.addon.Sync.Publish(),
    "an empty context must not erase recipes scanned from a different profession window")
local learnedRecipeInfo = C_TradeSkillUI.GetRecipeInfo
peer.ids = { 2001 }
C_TradeSkillUI.GetRecipeInfo = function(id) return { recipeID = id, name = "Recipe " .. id, learned = false } end
assert(peer.addon.Catalog.Scan() == 1 and peer.addon.Sync.Publish())
C_TradeSkillUI.GetRecipeInfo = learnedRecipeInfo
Flush(peer)
Deliver(Latest(owner, "H"), owner, returning)
Deliver(Latest(peer, "P"), peer, returning)
assert(#returning.addon.Catalog.Initialize().remoteProfiles[roster[2]].recipes == 0,
    "empty current profiles must withdraw old profession claims")
Activate(peer)
peer.ids = nil
assert(peer.addon.Catalog.Scan() == nil and not peer.addon.Sync.Publish(), "failed scans must not publish cached claims")
local mainProfile = owner.addon.characterDB.catalog.localProfile
Activate(owner)
Deliver(Latest(peer, "P"), peer, owner)
local sharedProfiles = owner.addon.Catalog.Initialize().remoteProfiles
local sharedIndex = owner.addon.Catalog.Initialize().recipeIndex
local alt = NewClient("Alt", "Character", {}, owner.addon.db)
Flush(alt)
assert(alt.addon.GuildState.Generation() == 3, "an alt must inherit its account's known guild generation")
assert(#alt.addon.characterDB.catalog.localProfile.recipes == 0 and owner.addon.characterDB.catalog.localProfile == mainProfile,
    "an empty alt must not inherit or overwrite the main character's recipes")
assert(alt.addon.Catalog.Initialize().remoteProfiles == sharedProfiles
    and alt.addon.Catalog.Initialize().recipeIndex == sharedIndex,
    "alts in the same guild must inherit the newest guild cache immediately")
assert(alt.addon.Catalog.RemoteProfiles()[roster[1]].recipes[1].recipeID == 1001,
    "the previous character must be shown as its own cached crafter, not as the alt's learned recipes")
assert(alt.addon.Catalog.RemoteProfiles()[roster[2]] and alt.addon.Catalog.RemoteProfiles()[roster[4]] == nil,
    "remote guild knowledge must survive switching characters without showing self duplicates")
assert(rawget(alt.addon.characterDB.catalog, "remoteProfiles") == nil
    and owner.addon.db.craftingGuilds["Horde Eternal@ForeverRealm"].remoteProfiles == sharedProfiles,
    "shared guild data must persist only in account storage, not duplicated in character saved variables")
local failedAlt = NewClient("Alt", "Character", nil, owner.addon.db, alt.addon.characterDB)
Flush(failedAlt)
for _, message in ipairs(failedAlt.sent) do assert(message:sub(1, 4) ~= "2|P|", "an unavailable alt scan must send no recipe profile") end
local function SavedCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, entry in pairs(value) do copy[key] = SavedCopy(entry) end
    return copy
end
local savedAccount = SavedCopy(owner.addon.db)
local reloadedAlt = NewClient("Alt", "Character", {}, savedAccount, SavedCopy(alt.addon.characterDB))
assert(reloadedAlt.addon.Catalog.RemoteProfiles()[roster[1]].recipes[1].recipeID == 1001,
    "the shared cache must survive saving and reloading without runtime metatables")
local savedOnlyAccount = SavedCopy(owner.addon.db)
savedOnlyAccount.craftingGuilds["Horde Eternal@ForeverRealm"].remoteProfiles[roster[1]] = nil
local savedOnlyMain = NewClient("Pod", "Cast", nil, savedOnlyAccount, SavedCopy(owner.addon.characterDB))
assert(savedOnlyMain.addon.characterDB.catalog.localProfile.recipes[1].recipeID == 1001
    and not savedOnlyMain.addon.Sync.Publish(), "an unavailable fresh scan must retain the saved character profile without publishing it")
local savedOnlyAlt = NewClient("Alt", "Character", {}, savedOnlyMain.addon.db)
local savedResults = savedOnlyAlt.addon.Catalog.Search("Recipe 1001")
assert(#savedResults == 1 and #savedResults[1].crafters == 1 and savedResults[1].crafters[1].name == roster[1],
    "an alt must see a complete saved crafter profile even when the main's login scan APIs are unavailable")
assert(savedOnlyAlt.addon.characterDB.catalog.localProfile.learned == 0 and not savedResults[1].crafters[1].isLocal,
    "recovering a saved crafter must not give the alt that character's learned recipes")
local incompleteAccount, incompleteCharacter = SavedCopy(owner.addon.db), SavedCopy(owner.addon.characterDB)
incompleteAccount.craftingGuilds["Horde Eternal@ForeverRealm"].remoteProfiles[roster[1]] = nil
incompleteCharacter.catalog.localProfile.unavailable = 1
local incompleteMain = NewClient("Pod", "Cast", nil, incompleteAccount, incompleteCharacter)
assert(incompleteMain.addon.Catalog.Initialize().remoteProfiles[roster[1]] == nil,
    "an incomplete saved scan must not become an account-wide crafting claim")
local legacyCharacter = { schemaVersion = 1, catalog = {
    guildKey = "Horde Eternal@ForeverRealm", generation = 3,
    remoteProfiles = { [roster[2]] = { updatedAt = 1500, recipes = { { recipeID = 5001, itemName = "Migrated recipe" } } } },
    recipeIndex = { ["5002"] = { recipeID = 5002, itemName = "Migrated definition", skillLineID = 171 } },
} }
local migratedAlt = NewClient("Alt", "Character", {}, savedAccount, legacyCharacter)
assert(migratedAlt.addon.Catalog.RemoteProfiles()[roster[2]].recipes[1].recipeID == 5001
    and migratedAlt.addon.Catalog.Initialize().recipeIndex["5002"], "same-generation character caches must migrate into shared guild storage")
local staleCharacter = { schemaVersion = 1, catalog = {
    guildKey = "Horde Eternal@ForeverRealm", generation = 2,
    localProfile = { recipes = { { recipeID = 9999 } } },
    remoteProfiles = { [roster[2]] = { updatedAt = 9999, recipes = { { recipeID = 9999 } } } },
} }
local staleAlt = NewClient("Alt", "Character", nil, savedAccount, staleCharacter)
assert(staleAlt.addon.characterDB.catalog.localProfile == nil and not staleAlt.addon.Sync.Publish()
    and staleAlt.addon.Catalog.RemoteProfiles()[roster[2]].recipes[1].recipeID == 5001,
    "a stale character must not resurrect pre-reset local or guild recipe data")
Activate(returning)
table.remove(roster, 2)
assert(returning.addon.GuildState.RefreshRoster())
assert(returning.addon.Catalog.Initialize().remoteProfiles["Other Crafter-ForeverRealm"] == nil,
    "a departed member's profile must be pruned")
Deliver(Latest(peer, "P"), peer, returning)
assert(returning.addon.Catalog.Initialize().remoteProfiles["Other Crafter-ForeverRealm"] == nil,
    "departed members must not be able to restore their profile")
local opened, reason = returning.addon.Compat.OpenCraftRequest({}, { name = "Other Crafter-ForeverRealm" })
assert(not opened and reason:find("current guild roster", 1, true), "stale crafter buttons must recheck membership")
Activate(owner)
assert(owner.addon.Sync.Publish())
local beforeFailedScan = #owner.sent
owner.ids = nil
assert(owner.addon.Catalog.Scan() == nil)
Flush(owner)
assert(#owner.sent == beforeFailedScan, "failed rescans must invalidate already queued profiles")
owner.ids = { 1001 }
local recipeInfo = C_TradeSkillUI.GetRecipeInfo
C_TradeSkillUI.GetRecipeInfo = function(recipeID) return { recipeID = recipeID, name = "Unreadable recipe" } end
owner.addon.Catalog.Scan()
assert(not owner.addon.Sync.Publish(), "incomplete learned-state scans must not advertise authoritative profiles")
C_TradeSkillUI.GetRecipeInfo = recipeInfo
assert(owner.addon.Catalog.Scan() == 1 and owner.addon.Sync.Publish())
local beforeLeave = #owner.sent
inGuild = false
Flush(owner)
assert(#owner.sent == beforeLeave and not owner.addon.GuildState.ready, "leaving guild must cancel pending broadcasts")
local guildless = NewClient("Pod", "Cast", { 1001 })
Flush(guildless)
assert(not guildless.addon.guildActive and guildless.buttons == 0 and #guildless.messages == 0
    and #guildless.sent == 0 and not guildless.addon.Catalog.listener,
    "guildless startup must create no addon controls, scan listeners, announcements, or messages")
assert(guildless.addon.Catalog.Scan() == nil and not guildless.addon.Catalog.Initialize().localProfile,
    "guildless scans must not update learned recipes")
inGuild, guildClubId = true, 123456
local outsider = NewClient("Pod", "Cast", { 1001 })
local openings = 0
outsider.addon.ToggleCanvas = function() openings = openings + 1 end
SlashCmdList.HORDEETERNAL("")
SlashCmdList.HORDEETERNAL("scan")
Flush(outsider)
assert(not outsider.addon.guildActive and outsider.buttons == 0 and #outsider.messages == 0
    and #outsider.sent == 0 and openings == 0 and not outsider.addon.Catalog.Initialize().localProfile,
    "another guild must neither activate the addon nor bypass eligibility with slash commands")
print("PASS: reset cancels partial transfers, empty profession updates, alt isolation, and departed-member exclusion")

inGuild, guildClubId, clock = true, 503775441, 2000
roster = { "Pod Cast-ForeverRealm", "Other Crafter-ForeverRealm", "Returning Member-ForeverRealm", "Alt Character-ForeverRealm" }
local source = NewClient("Pod", "Cast", { 1001, 1002 })
local provider = NewClient("Other", "Crafter", { 2001 })
local newcomer = NewClient("Returning", "Member", { 3001 })
Flush(source); Flush(provider); Flush(newcomer)
local function DeliverKind(sender, receiver, kind, start)
    for index = start or 1, #sender.sent do
        if sender.sent[index]:sub(1, 4) == "2|" .. kind .. "|" then Deliver(sender.sent[index], sender, receiver) end
    end
end
local function Announce(client)
    Activate(client)
    local start = #client.sent + 1
    assert(client.addon.Sync.Reconcile())
    Flush(client)
    return start
end
local function Recover(holder, receiver, start)
    DeliverKind(holder, receiver, "I", start)
    local requestStart, replyStart = #receiver.sent + 1, #holder.sent + 1
    Flush(receiver)
    DeliverKind(receiver, holder, "W", requestStart)
    Flush(holder)
    DeliverKind(holder, receiver, "R", replyStart)
end
Recover(source, provider, Announce(source))
Activate(provider)
local original = provider.addon.Catalog.Initialize().remoteProfiles[roster[1]]
assert(original and original.revision == 1 and #original.recipes == 2,
    "inventory/request exchange must recover the original owner's revisioned profile")
Recover(provider, newcomer, Announce(provider))
Activate(newcomer)
local relayed = newcomer.addon.Catalog.Initialize().remoteProfiles[roster[1]]
assert(relayed and relayed.revision == original.revision and relayed.updatedAt == original.updatedAt
    and relayed.fingerprint == original.fingerprint and #relayed.recipes == 2,
    "a retained peer must recover an absent owner's profile without inventing a newer revision or timestamp")
do
    local previousOnline = onlineByName[roster[1]]
    onlineByName[roster[1]] = false
    local cachedHolder = NewClient("Other", "Crafter", nil,
        SavedCopy(provider.addon.db), SavedCopy(provider.addon.characterDB))
    Flush(cachedHolder)
    clock = clock + 4
    Activate(cachedHolder)
    cachedHolder.syncFrame.scripts.OnUpdate(nil, 1)
    Flush(cachedHolder)
    assert(not cachedHolder.addon.Catalog.scannedThisSession,
        "the relay regression must exercise a holder with no fresh local profession scan")
    local newArrival = NewClient("Returning", "Member", nil)
    Flush(newArrival)
    local responseStart = #cachedHolder.sent + 1
    Deliver(Latest(newArrival, "H"), newArrival, cachedHolder)
    Flush(cachedHolder)
    clock = clock + 4
    Activate(cachedHolder)
    cachedHolder.syncFrame.scripts.OnUpdate(nil, 1)
    Flush(cachedHolder)
    local announcedCache = false
    for index = responseStart, #cachedHolder.sent do
        if cachedHolder.sent[index]:sub(1, 4) == "2|I|" then announcedCache = true end
    end
    assert(announcedCache,
        "a newcomer greeting must promptly advertise cached peers even when the holder cannot publish its own recipes")
    Recover(cachedHolder, newArrival, responseStart)
    Activate(newArrival)
    local recovered = newArrival.addon.Catalog.Initialize().remoteProfiles[roster[1]]
    assert(recovered and recovered.revision == original.revision and recovered.fingerprint == original.fingerprint,
        "automatic newcomer catch-up must preserve the offline original owner's recipe revision")
    local known = newArrival.addon.Catalog.Search("Recipe 1001")
    assert(#known == 1 and known[1].crafters[1].name == roster[1] and known[1].crafters[1].isOnline == false,
        "relayed recipes must be visible under the offline owner without requiring a local scan")
    onlineByName[roster[1]] = previousOnline
end
Activate(source)
local beforeWithdrawal = source.addon.Catalog.Initialize().localProfile.revision
local learnedAPI = C_TradeSkillUI.GetRecipeInfo
C_TradeSkillUI.IsRecipeProfessionLearned = function() return false end
C_TradeSkillUI.GetRecipeInfo = function(id) return { recipeID = id, name = "Recipe " .. id, learned = false } end
source.ids = { 1001, 1002 }
assert(source.addon.Catalog.Scan() == 2)
local withdrawal = source.addon.Catalog.Initialize().localProfile
assert(#withdrawal.recipes == 0 and withdrawal.revision > beforeWithdrawal,
    "confirmed profession removal must create an empty higher-revision withdrawal")
C_TradeSkillUI.IsRecipeProfessionLearned, C_TradeSkillUI.GetRecipeInfo = nil, learnedAPI
clock = clock + 11
Recover(source, provider, Announce(source))
clock = clock + 11
Recover(provider, newcomer, Announce(provider))
Activate(newcomer)
assert(#newcomer.addon.Catalog.Initialize().remoteProfiles[roster[1]].recipes == 0,
    "an offline owner withdrawal must propagate through a peer and remove stale crafting claims")
local stale = "2|P|Horde Eternal@ForeverRealm|1|99-1|9999|1|1|1001~171~Alchemy~Stale item~Stale recipe"
newcomer.addon.Sync.Receive("HERC2", stale, "GUILD", roster[1])
assert(#newcomer.addon.Catalog.Initialize().remoteProfiles[roster[1]].recipes == 0,
    "late legacy packets must not resurrect recipes after a revisioned withdrawal")
Activate(source)
source.ids = { 1001 }
assert(source.addon.Catalog.Scan() == 1)
clock = clock + 11
local pendingStart = Announce(source)
DeliverKind(source, newcomer, "I", pendingStart)
Activate(newcomer)
assert(newcomer.addon.Sync.Progress() >= 1)
table.remove(roster, 1)
assert(newcomer.addon.GuildState.RefreshRoster())
assert(not newcomer.addon.Catalog.Initialize().remoteProfiles["Pod Cast-ForeverRealm"]
    and newcomer.addon.Sync.Progress() == 0, "verified departure must prune profile and pending recovery")
local sentBeforeDeparture = #newcomer.sent
Flush(newcomer)
assert(#newcomer.sent == sentBeforeDeparture, "departed owners must not leave queued recovery requests")
print("PASS: revisioned peer recovery, original-owner preservation, profession withdrawals, stale rejection, and departure cancellation")

roster = { "Pod Cast-ForeverRealm", "Other Crafter-ForeverRealm", "Returning Member-ForeverRealm", "Alt Character-ForeverRealm" }
clock = clock + 20
local retrySource = NewClient("Pod", "Cast", { 4101, 4102, 4103 })
local backup = SavedCopy(retrySource.addon.db)
local backupCharacter = SavedCopy(retrySource.addon.characterDB)
local retryProvider = NewClient("Other", "Crafter", { 4201 })
local retryReceiver = NewClient("Returning", "Member", { 4301 })
Flush(retrySource); Flush(retryProvider); Flush(retryReceiver)
Recover(retrySource, retryProvider, Announce(retrySource))
local sourceInventory = Announce(retrySource)
DeliverKind(retrySource, retryReceiver, "I", sourceInventory)
local providerInventory = Announce(retryProvider)
DeliverKind(retryProvider, retryReceiver, "I", providerInventory)
Flush(retryReceiver)
Activate(retryReceiver)
clock = clock + 301
retryReceiver.syncFrame.scripts.OnUpdate(nil, 1)
local retryStart, responseStart = #retryReceiver.sent + 1, #retryProvider.sent + 1
Flush(retryReceiver)
DeliverKind(retryReceiver, retryProvider, "W", retryStart)
Flush(retryProvider)
local chunks = {}
for index = responseStart, #retryProvider.sent do
    if retryProvider.sent[index]:sub(1, 4) == "2|R|" then chunks[#chunks + 1] = retryProvider.sent[index] end
end
assert(#chunks > 1, "multi-part snapshots must exercise chunk reassembly")
for index = #chunks, 1, -1 do Deliver(chunks[index], retryProvider, retryReceiver) end
Deliver(chunks[1], retryProvider, retryReceiver)
Activate(retryReceiver)
local pending, applied, retries = retryReceiver.addon.Sync.Progress()
assert(pending == 0 and applied >= 1 and retries >= 1
    and #retryReceiver.addon.Catalog.Initialize().remoteProfiles[roster[1]].recipes == 3,
    "a missing provider must fall back to a retained peer and accept reordered chunks once")
Activate(retrySource)
retrySource.ids = { 4101, 4102, 4103, 4104 }
clock = clock - 200
assert(retrySource.addon.Catalog.Scan() == 4)
local latestRevision = retrySource.addon.Catalog.Initialize().localProfile.revision
clock = clock + 11
Recover(retrySource, retryProvider, Announce(retrySource))
local newInventory = Announce(retrySource)
DeliverKind(retrySource, retryReceiver, "I", newInventory)
local requestIndex, chunkIndex = #retryReceiver.sent + 1, #retrySource.sent + 1
Flush(retryReceiver)
DeliverKind(retryReceiver, retrySource, "W", requestIndex)
Flush(retrySource)
local validChunks = {}
for index = chunkIndex, #retrySource.sent do
    if retrySource.sent[index]:sub(1, 4) == "2|R|" then validChunks[#validChunks + 1] = retrySource.sent[index] end
end
assert(#validChunks > 0)
for index, chunk in ipairs(validChunks) do
    Deliver(index == 1 and chunk:sub(1, -2) .. "X" or chunk, retrySource, retryReceiver)
end
Activate(retryReceiver)
assert(retryReceiver.addon.Catalog.Initialize().remoteProfiles[roster[1]].revision < latestRevision,
    "a checksum failure must preserve the last valid profile")
clock = clock + 301
retryReceiver.syncFrame.scripts.OnUpdate(nil, 1)
local nextRequest, nextResponse = #retryReceiver.sent + 1, #retrySource.sent + 1
Flush(retryReceiver)
DeliverKind(retryReceiver, retrySource, "W", nextRequest)
Flush(retrySource)
DeliverKind(retrySource, retryReceiver, "R", nextResponse)
Activate(retryReceiver)
assert(retryReceiver.addon.Catalog.Initialize().remoteProfiles[roster[1]].revision == latestRevision,
    "retry must recover the newer revision even with an older source timestamp")
local restoredOwner = NewClient("Pod", "Cast", { 4101 }, backup, backupCharacter)
Flush(restoredOwner)
clock = clock + 11
Recover(retryProvider, restoredOwner, Announce(retryProvider))
Activate(restoredOwner)
assert(restoredOwner.addon.Catalog.Initialize().localProfile.revision > latestRevision
    and restoredOwner.addon.Catalog.scannedThisSession,
    "a fresh owner restored from backup must recover above peer-retained revisions")
print("PASS: provider fallback, reordered/checksummed snapshots, backward clocks, and restored-owner revision recovery")

clock = clock + 20
local missed = NewClient("Alt", "Character", { 4401 })
Flush(missed)
DeliverKind(retrySource, missed, "I", Announce(retrySource))
Flush(missed)
local initialRequests = #missed.sent
for _ = 1, 3 do
    Activate(missed)
    clock = clock + 301
    missed.syncFrame.scripts.OnUpdate(nil, 1)
    Flush(missed)
end
Activate(missed)
local waiting, _, retryCount, failureCount = missed.addon.Sync.Progress()
assert(waiting == 0 and retryCount == 2 and failureCount == 1,
    "missing providers must exhaust exactly three attempts without an immediate retry loop")
local requestCount = 0
for _, message in ipairs(missed.sent) do if message:sub(1, 4) == "2|W|" then requestCount = requestCount + 1 end end
assert(requestCount == 3 and #missed.sent >= initialRequests, "recovery must emit only three requests in one retry round")
local beforeCooldown = #missed.sent
clock = clock + 10
missed.syncFrame.scripts.OnUpdate(nil, 1)
Flush(missed)
local afterCount = 0
for _, message in ipairs(missed.sent) do if message:sub(1, 4) == "2|W|" then afterCount = afterCount + 1 end end
assert(afterCount == requestCount and #missed.sent >= beforeCooldown)
missed.addon.Sync.SetSharing(false)
DeliverKind(retrySource, missed, "I", Announce(retrySource))
Activate(missed)
assert(missed.addon.Sync.Progress() == 0, "sharing opt-out must cancel and refuse recipe recovery")
local unavailableOwner = NewClient("Pod", "Cast", nil, SavedCopy(backup), SavedCopy(backupCharacter))
Flush(unavailableOwner)
local priorCounter = unavailableOwner.addon.characterDB.catalog.scanRevision
clock = clock + 11
Recover(retryProvider, unavailableOwner, Announce(retryProvider))
Activate(unavailableOwner)
assert(not unavailableOwner.addon.Catalog.scannedThisSession
    and unavailableOwner.addon.characterDB.catalog.scanRevision == priorCounter
    and not unavailableOwner.addon.Sync.Publish(),
    "a restored unavailable owner may retain peer data but cannot issue or publish a fresh learned claim")
print("PASS: bounded retry exhaustion/cooldown, consent cancellation, and unavailable-owner recovery safety")

clock = clock + 20
for index = 5, 180 do roster[index] = "Crafter " .. index .. "-ForeverRealm" end
local largeGuild = NewClient("Other", "Crafter", { 4501 })
Flush(largeGuild)
Activate(largeGuild)
local largeCache = largeGuild.addon.Catalog.Initialize().remoteProfiles
for index = 5, #roster do
    local profile = { recipes = {}, revision = 1, generation = 1, updatedAt = 1000 }
    profile.fingerprint = largeGuild.addon.Catalog.Fingerprint(largeGuild.addon.Catalog.EncodeProfile(profile))
    largeCache[roster[index]] = profile
end
do
    local originalEncode = largeGuild.addon.Catalog.EncodeProfile
    local encodes = 0
    largeGuild.addon.Catalog.EncodeProfile = function(...)
        encodes = encodes + 1
        return originalEncode(...)
    end
    assert(largeGuild.addon.Sync.Reconcile() and encodes == 0,
        "inventory reconciliation must not encode every guild profile synchronously")
    local pending = #largeGuild.timers
    assert(largeGuild.addon.Sync.Reconcile() and #largeGuild.timers == pending,
        "repeated reconciliation must share one pending inventory build")
    local steps = 0
    while #largeGuild.timers > 0 do
        local before = encodes
        table.remove(largeGuild.timers, 1)()
        assert(encodes - before <= 1, "each inventory callback must validate at most one profile")
        steps = steps + 1
        assert(steps < 500)
    end
    assert(encodes == 177, "incremental inventory must still validate every eligible profile")
    assert(largeGuild.addon.Sync.Reconcile())
    local sentBefore = #largeGuild.sent
    largeGuild.addon.Sync.SetSharing(false)
    Flush(largeGuild)
    assert(#largeGuild.sent == sentBefore, "sharing opt-out must cancel an unfinished inventory build")
    largeGuild.addon.Catalog.EncodeProfile = originalEncode
    assert(largeGuild.addon.Sync.SetSharing(true))
    Flush(largeGuild)
end
local batchStart = Announce(largeGuild)
local packets = 0
for index = batchStart, #largeGuild.sent do if largeGuild.sent[index]:sub(1, 4) == "2|I|" then packets = packets + 1 end end
assert(packets > 0 and packets <= 8, "large-guild inventory announcements must use bounded queue batches")
clock = clock + 16
Activate(largeGuild)
local secondBatch = #largeGuild.sent + 1
largeGuild.syncFrame.scripts.OnUpdate(nil, 1)
Flush(largeGuild)
assert(#largeGuild.sent >= secondBatch, "periodic maintenance must continue unfinished inventory batches")
Activate(largeGuild)
local primaryPayload = "601~171~Alchemy~A~A;602~333~Enchanting~B~B;603~202~Engineering~C~C"
largeGuild.addon.Sync.Receive("HERC2", "2|P|Horde Eternal@ForeverRealm|1|700-1|1000|1|1|" .. primaryPayload,
    "GUILD", roster[4])
assert(not largeGuild.addon.Catalog.Initialize().remoteProfiles[roster[4]],
    "an incoming profile with three primary professions must be rejected before storage")
primaryPayload = "601~171~Alchemy~A~A;602~333~Enchanting~B~B"
largeGuild.addon.Sync.Receive("HERC2", "2|P|Horde Eternal@ForeverRealm|1|700-2|1000|1|1|" .. primaryPayload,
    "GUILD", roster[4])
assert(#largeGuild.addon.Catalog.Initialize().remoteProfiles[roster[4]].recipes == 2,
    "a valid two-primary legacy profile must remain compatible")
print("PASS: large-guild inventory batching with reserved queue capacity")