local addon = { db = {}, characterDB = {} }
assert(loadfile("HordeEternal/Compat.lua"))("HordeEternal", addon)
assert(loadfile("HordeEternal/Catalog.lua"))("HordeEternal", addon)
assert(loadfile("HordeEternal/GuildState.lua"))("HordeEternal", addon)

local guildName = "Horde Eternal"
local inGuild = true
local roster = { "Podcast Clawson-ForeverRealm", "Other Crafter-ForeverRealm" }
local onlineByName = { [roster[1]] = true, [roster[2]] = false }
local playerFirst, playerLast = "Podcast", "Clawson"
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
assert(addon.GuildState.RefreshRoster())
assert(addon.GuildState.Resolve("Other Crafter") == roster[2])
local rosterRows = addon.GuildState.Rows()
assert(#rosterRows == 2 and rosterRows[1].name == roster[2]
    and rosterRows[1].classFile == "MAGE" and rosterRows[1].level == 60
    and rosterRows[1].rank == "Member" and rosterRows[1].rankIndex == 5,
    "the verified roster must retain member information for guild statistics")
assert(addon.GuildState.CanReset(), "only the configured local owner can reset")
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
roster[3] = "Podcast Clawson-OtherRealm"
assert(addon.GuildState.RefreshRoster())
assert(not addon.GuildState.CanReset(), "an ambiguous owner name must not authorize a reset")
roster[3] = nil
playerFirst, playerLast = "Other", "Crafter"
assert(addon.GuildState.RefreshRoster() and not addon.GuildState.CanReset())
guildName = "Another Guild"
assert(addon.GuildState.RefreshRoster())
database = addon.Catalog.Initialize()
assert(next(database.remoteProfiles) == nil, "changing guild must clear the previous guild's profiles")
database.remoteProfiles[roster[1]] = { recipes = {} }
inGuild = false
assert(not addon.GuildState.IsReady() and next(addon.Catalog.Initialize().remoteProfiles) == nil)
assert(invalidations > 0)
print("PASS: complete guild rosters, departure cleanup, context changes, and unique owner authorization")

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
roster = { "Podcast Clawson-ForeverRealm", "Other Crafter-ForeverRealm", "Returning Member-ForeverRealm", "Alt Character-ForeverRealm" }

local function NewClient(first, last, ids, account, character)
    local client = { first = first, last = last, ids = ids, sent = {}, timers = {} }
    Activate(client)
    local instance = { Print = function() end, CreateMinimapButton = function() end }
    client.addon = instance
    HordeEternalDB = account
    HordeEternalCharacterDB = character
    for _, module in ipairs({ "Compat", "GuildState", "Catalog", "Sync", "Core" }) do
        assert(loadfile("HordeEternal/" .. module .. ".lua"))("HordeEternal", instance)
    end
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

local account = {
    schemaVersion = 1, minimapPos = 42, minimapPositionVersion = 1, canvasTab = "guild",
    memberGuilds = { preserved = { main = "Podcast Clawson", discord = "test.handle" } },
    futureTool = { preserved = true }, catalog = { localProfile = { recipes = { { recipeID = 999 } } } },
}
local owner = NewClient("Podcast", "Clawson", { 1001 }, account)
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
assert(peer.addon.Catalog.Scan() == 0 and peer.addon.Sync.Publish())
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
print("PASS: reset cancels partial transfers, empty profession updates, alt isolation, and departed-member exclusion")