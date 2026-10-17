local addon = { db = {}, initialized = true }
assert(loadfile("HordeEternal/Compat.lua"))("HordeEternal", addon)
assert(loadfile("HordeEternal/Catalog.lua"))("HordeEternal", addon)
local timers, frames = {}, {}
CreateFrame = function()
    local frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(_, callback) self.handler = callback end
    frames[#frames + 1] = frame
    return frame
end
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
time = function() return 1000 end
local openID, loading, linked, guild, unavailable = 333, false, false, false, false
local recipeLists = { [333] = { 25124 }, [171] = { 2330 } }
local names = { [333] = "Enchanting", [171] = "Alchemy" }
local scanCount, published, refreshed = 0, 0, 0
C_TradeSkillUI = {
    IsTradeSkillLinked = function() return linked end,
    IsTradeSkillGuild = function() return guild end,
    IsDataSourceChanging = function() return loading end,
    GetBaseProfessionInfo = function() return { professionID = openID, professionName = names[openID] } end,
    GetAllProfessionTradeSkillLines = function() return { 333, 171 } end,
    GetProfessionInfoBySkillLineID = function(id) return { professionID = id, professionName = names[id] } end,
    GetProfessionSpells = function(id)
        assert(id == openID, "a current-profession scan must not read another profession's context-dependent recipes")
        if unavailable then return nil end
        return recipeLists[id]
    end,
    GetAllRecipeIDs = function()
        scanCount = scanCount + 1
        if unavailable then return nil end
        return recipeLists[openID]
    end,
    GetRecipeInfo = function(id) return { recipeID = id, name = "Recipe " .. id, learned = true } end,
    GetTradeSkillLineForRecipe = function(id) return id == 25124 and 333 or 171 end,
    GetTradeSkillDisplayName = function(id) return names[id] end,
}
addon.Sync = { Publish = function() published = published + 1 end }
addon.RefreshCatalog = function() refreshed = refreshed + 1 end
addon.Catalog.Start()
addon.Catalog.Start()
assert(#frames == 1 and frames[1].events.TRADE_SKILL_SHOW and frames[1].events.NEW_RECIPE_LEARNED)
local function Event(event) frames[1].handler(nil, event) end
local function Flush()
    local callbacks = 0
    while #timers > 0 do
        callbacks = callbacks + 1
        assert(callbacks <= 10, "profession retries must remain bounded")
        table.remove(timers, 1)()
    end
end
Event("TRADE_SKILL_SHOW")
Event("TRADE_SKILL_LIST_UPDATE")
Event("TRADE_SKILL_DETAILS_UPDATE")
assert(#timers == 1, "opening/list events must coalesce")
Flush()
assert(scanCount == 1 and published == 1 and refreshed == 1 and #addon.Catalog.Search("25124") == 1)
Event("TRADE_SKILL_DATA_SOURCE_CHANGING")
openID = 171
Event("TRADE_SKILL_DATA_SOURCE_CHANGED")
Flush()
assert(published == 2 and #addon.Catalog.Search("25124") == 1 and #addon.Catalog.Search("2330") == 1,
    "automatically scanning a second window must preserve and share both professions")
Event("TRADE_SKILL_SHOW")
Event("TRADE_SKILL_CLOSE")
local beforeClose = scanCount
Flush()
assert(scanCount == beforeClose, "closing the profession must cancel delayed scans")
linked = true
Event("TRADE_SKILL_SHOW")
Flush()
assert(scanCount == beforeClose and published == 2, "a linked profession must not be recorded or shared as this character's recipes")
linked, guild = false, true
Event("TRADE_SKILL_DATA_SOURCE_CHANGED")
Flush()
assert(scanCount == beforeClose)
guild, loading = false, true
Event("TRADE_SKILL_DATA_SOURCE_CHANGED")
table.remove(timers, 1)()
assert(#timers == 1 and scanCount == beforeClose)
loading = false
Flush()
assert(scanCount == beforeClose + 1 and published == 3, "data readiness retries must recover without clicking Rescan")
local profile = addon.Catalog.Initialize().localProfile
local secret = {}
canaccessvalue = function(value) return value ~= secret end
linked = secret
Event("TRADE_SKILL_SHOW")
Flush()
assert(addon.Catalog.Initialize().localProfile == profile, "restricted source identity must not mutate learned ownership")
canaccessvalue, linked = nil, false
unavailable = true
Event("TRADE_SKILL_DATA_SOURCE_CHANGED")
local callbacksBefore = scanCount
Flush()
assert(scanCount == callbacksBefore + 3 and published == 3, "unavailable recipe data must stop after bounded retries")
assert(addon.Catalog.Initialize().localProfile == profile and not addon.Catalog.scannedThisSession)
unavailable = false
recipeLists[171] = {}
Event("TRADE_SKILL_LIST_UPDATE")
Flush()
assert(#addon.Catalog.Search("25124") == 1 and #addon.Catalog.Search("2330") == 1,
    "an empty profession window must not clear other learned recipes")
addon.Catalog.SetSharing(false)
recipeLists[171] = { 2330 }
Event("NEW_RECIPE_LEARNED")
Flush()
assert(published == 3 and refreshed >= 4, "automatic scans must honour recipe sharing opt-out")
local professionRemoved = true
C_TradeSkillUI.IsRecipeProfessionLearned = function(id) if id == 25124 then return not professionRemoved end return true end
addon.Catalog.Scan()
assert(#addon.Catalog.Search("25124") == 0 and #addon.Catalog.Search("2330") == 1,
    "a positively unlearned profession must withdraw cached claims without clearing other professions")
Event("TRADE_SKILL_CLOSE")
openID = nil
C_TradeSkillUI.GetProfessionSpells = function(id) return recipeLists[id] end
C_TradeSkillUI.IsRecipeProfessionLearned = nil
assert(addon.Catalog.Scan() == 2 and #addon.Catalog.Search("25124") == 1 and #addon.Catalog.Search("2330") == 1,
    "background scans should collect all professions when the client exposes readable recipes without an open window")
local persisted = addon.db
local reloaded = { db = persisted }
assert(loadfile("HordeEternal/Catalog.lua"))("HordeEternal", reloaded)
reloaded.Compat = addon.Compat
assert(#reloaded.Catalog.Search("25124") == 1 and #reloaded.Catalog.Search("2330") == 1,
    "combined per-character profession knowledge must survive addon reloads")
print("PASS: incremental profession scans, automatic open/update capture, coalescing/retries, close cancellation, source guards, and sharing consent")