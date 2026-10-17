local addon = { db = {} }
assert(loadfile("HordeEternal/Compat.lua"))("HordeEternal", addon)
assert(loadfile("HordeEternal/Catalog.lua"))("HordeEternal", addon)

assert(addon.Catalog.Initialize().shareEnabled == true, "new installs must share automatically")
addon.db = { catalog = { shareEnabled = false, remoteProfiles = {} } }
assert(addon.Catalog.Initialize().shareEnabled == true, "old opt-in defaults must migrate")
addon.Catalog.SetSharing(false)
assert(addon.Catalog.Initialize().shareEnabled == false, "explicit opt-out must survive initialization")
addon.db = {}

time = function() return 1000 end
C_TradeSkillUI = {
    GetAllRecipeIDs = function() return { 25124, 99999, 25124 } end,
    GetRecipeInfo = function(recipeID)
        return { recipeID = recipeID, name = "Minor Wizard Oil", learned = recipeID == 25124 }
    end,
    GetTradeSkillLineForRecipe = function() return 333 end,
    GetTradeSkillDisplayName = function(skillLineID) if skillLineID == 333 then return "Enchanting" end end,
}

local scanned, learned, reason = addon.Catalog.Scan()
assert(scanned == 2 and learned == 1 and reason == nil, "fallback IDs must survive and deduplicate")
local results = addon.Catalog.Search("wizard")
assert(#results == 1 and results[1].crafters[1].name == "You", "local recipes must appear without sharing")
assert(addon.db.catalog.shareEnabled == true, "sharing must default to enabled")
assert(addon.db.catalog.localProfile.recipes[1].skillLineID == 333)
local browse, total = addon.Catalog.Browse("", 333)
assert(total == 2 and #browse == 2, "browser must retain client-visible unlearned recipes")
assert(#addon.db.catalog.localProfile.recipes == 1, "unlearned recipes must not be advertised as craftable")
local professions, known, catalogued = addon.Catalog.Overview()
assert(#professions == 12 and known == 1 and catalogued == 2)
addon.db.catalog.remoteProfiles.Peer = { updatedAt = 900, recipes = {
    { recipeID = 25124, skillLineID = 333, itemName = "Minor Wizard Oil", professionName = "Enchanting" },
} }
professions, known, catalogued = addon.Catalog.Overview()
assert(known == 1 and catalogued == 2, "multiple crafters must not inflate guild recipe counts")
assert(#addon.Catalog.Search("wizard")[1].crafters == 2)
addon.db.catalog.remoteProfiles = {}
for recipeID = 100001, 100121 do
    addon.db.catalog.recipeIndex[tostring(recipeID)] = {
        recipeID = recipeID, skillLineID = 171, itemName = "Pagination " .. recipeID, professionName = "Alchemy",
    }
end
local pages, page
browse, total, pages, page = addon.Catalog.Browse("Pagination", 171, 3)
assert(#browse == 21 and total == 121 and pages == 3 and page == 3,
    "all recipes must remain reachable beyond the old 100-result cap")
browse, total, pages, page = addon.Catalog.Browse("Pagination", 171, 999)
assert(page == 3)
addon.db.catalog.recipeIndex = {}

local libraryVersion, libraryReady = "Forever", true
local libraryRecipe = { name = "Library Enchant", craftedItemId = 1234, effect = "+5 Agility", reagents = { [456] = 2 } }
local library = {
    GetGameVersion = function() return libraryVersion end,
    GetMeta = function() return "enUS", libraryVersion end,
    IsReady = function() return libraryReady end,
    Count = function() return 1 end,
    Iterate = function()
        local done = false
        return function()
            if done then return nil end
            done = true
            return 333, 54321, libraryRecipe
        end
    end,
}
LibStub = { GetLibrary = function(_, name, silent)
    assert(name == "LibProfessionDB-1.0" and silent)
    return library
end }
browse, total = addon.Catalog.Browse("agility", 333)
assert(total == 1 and browse[1].itemID == 1234 and #browse[1].crafters == 0)
assert(addon.Catalog.hasLibrary and browse[1].reagents[456] == 2)
local readyReport = addon.Catalog.LibraryReport()
assert(#readyReport == 2 and readyReport[2]:find("ready: 1 recipes", 1, true)
    and readyReport[2]:find("Standalone ProfessionDB is not required", 1, true),
    "an embedded library must not report a missing standalone addon as a failure")
assert(libraryRecipe.recipeID == nil, "library-owned records must remain untouched")
local getLibrary = LibStub.GetLibrary
LibStub.GetLibrary = function() return nil end
C_AddOns = {
    DoesAddOnExist = function(name) return name ~= "VersionCheck-1.0" end,
    GetAddOnInfo = function(name) return name, name, "", name == "Ace3", name == "ProfessionDB" and "DEP_MISSING" or "", "INSECURE" end,
    IsAddOnLoaded = function(name) return name == "Ace3", name == "Ace3" end,
    GetAddOnDependencies = function(name)
        assert(name == "ProfessionDB")
        return "Ace3", "VersionCheck-1.0"
    end,
}
local libraryReport = addon.Catalog.LibraryReport()
assert(libraryReport[1]:find("not registered", 1, true))
assert(libraryReport[2] == "ProfessionDB: not loaded; DEP_MISSING")
assert(libraryReport[3] == "Ace3: loaded" and libraryReport[4] == "VersionCheck-1.0: not found by WoW",
    "library diagnostics must distinguish a missing dependency from a missing library package")
C_AddOns.IsAddOnLoaded = function() return true, false end
assert(addon.Compat.AddOnStatus("Ace3") == "Ace3: loading", "loading must not be reported as fully loaded")
C_AddOns.GetAddOnInfo = function(name) return name, name, "", false, "DISABLED", "INSECURE" end
C_AddOns.IsAddOnLoaded = function() return false, false end
assert(addon.Compat.AddOnStatus("ProfessionDB") == "ProfessionDB: not loaded; DISABLED")
local restrictedStatus = {}
C_AddOns.GetAddOnInfo = function(name) return name, name, "", true, "", restrictedStatus end
canaccessvalue = function(value) return value ~= restrictedStatus end
assert(addon.Compat.AddOnStatus("ProfessionDB") == "ProfessionDB: addon status unavailable",
    "late restricted addon fields must not be used in diagnostics")
canaccessvalue, C_AddOns = nil, nil
LibStub.GetLibrary = function() error("lookup failed") end
assert(not addon.Catalog.RefreshLibrary() and addon.Catalog.source:find("lookup error", 1, true))
LibStub = nil
assert(not addon.Catalog.RefreshLibrary() and addon.Catalog.source:find("lookup missing", 1, true))
LibStub = { GetLibrary = getLibrary }
libraryVersion = "Vanilla"
assert(#addon.Catalog.Browse("agility") == 0 and not addon.Catalog.hasLibrary)
libraryVersion, libraryReady = "Forever", false
assert(not addon.Catalog.RefreshLibrary())
libraryReady = true
assert(addon.Catalog.RefreshLibrary(), "late-loaded library data must become available")
local originalDatabase = addon.db
addon.db = {}
local groupedDatabase = addon.Catalog.Initialize()
local clientProfessions = { [900333] = "Enchanting", [900171] = "Alchemy", [900182] = "Herbalism", [900777] = "Runecarving" }
C_TradeSkillUI.GetAllProfessionTradeSkillLines = function() return { 900333, 900171, 900182, 900777 } end
C_TradeSkillUI.GetProfessionInfoBySkillLineID = function(id) return { professionName = clientProfessions[id] } end
groupedDatabase.localProfile = { recipes = {
    { recipeID = 54321, skillLineID = 900333, professionName = "Enchanting", itemName = "Library Enchant" },
} }
groupedDatabase.recipeIndex = {
    ["54322"] = { recipeID = 54322, skillLineID = 900333, professionName = "Enchanting", itemName = "Client Enchant" },
    ["54323"] = { recipeID = 54323, skillLineID = 333, professionName = "Enchanting", itemName = "Older Enchant" },
    ["54324"] = { recipeID = 54324, skillLineID = 900171, professionName = "Alchemy", itemName = "Client Potion" },
}
professions, known, catalogued = addon.Catalog.Overview()
assert(#professions == 13 and known == 1 and catalogued == 4,
    "base, client, and library IDs must share profession rows without hiding distinct professions")
local professionNames = {}
for _, profession in ipairs(professions) do
    assert(not professionNames[profession.name], "duplicate profession name")
    professionNames[profession.name] = true
    if profession.name == "Enchanting" then
        assert(profession.id == 333 and profession.known == 1 and profession.total == 3)
        assert(profession.icon == "Interface\\Icons\\Trade_Engraving")
    elseif profession.name == "Herbalism" then
        assert(profession.gathering and profession.icon == "Interface\\Icons\\Trade_Herbalism")
    end
end
browse, total = addon.Catalog.Browse("", 333)
assert(total == 3 and #browse == 3, "the merged profession must open recipes from every ID")
browse, total = addon.Catalog.Browse("", 900333)
assert(total == 3, "client ID filters must resolve to the same profession")
assert(groupedDatabase.localProfile.recipes[1].skillLineID == 900333
    and groupedDatabase.recipeIndex["54322"].skillLineID == 900333, "grouping must not rewrite saved recipe ownership")
LibStub = nil
professions, known, catalogued = addon.Catalog.Overview()
assert(#professions == 13 and known == 1 and catalogued == 4 and not addon.Catalog.hasLibrary,
    "profession grouping must also work when the optional library is absent")
addon.db = originalDatabase
C_TradeSkillUI.GetAllProfessionTradeSkillLines, C_TradeSkillUI.GetProfessionInfoBySkillLineID = nil, nil
LibStub = nil
assert(not addon.Catalog.RefreshLibrary())
print("PASS: optional Forever library, effect search, version gates, and late readiness")

C_TradeSkillUI.GetTradeSkillLineForRecipe = nil
assert(addon.Catalog.Scan() == 2)
assert(addon.db.catalog.localProfile.recipes[1].skillLineID == 0, "unknown profession must remain unknown")

local savedProfile = addon.db.catalog.localProfile
C_TradeSkillUI.GetAllRecipeIDs = function() return nil end
scanned, learned, reason = addon.Catalog.Scan()
assert(scanned == nil and reason == "no recipe list available")
assert(addon.db.catalog.localProfile == savedProfile, "unavailable scans must preserve saved recipes")

print("PASS: recipe fallback, local search, sharing defaults, and unavailable scan preservation")

local displayEntry = { recipeID = 25124, itemName = "Minor Wizard Oil", itemLink = "|Hitem:20744|h[Minor Wizard Oil]|h" }
C_Spell = {
    GetSpellInfo = function() return { iconID = 123 } end,
    GetSpellDescription = function() return "Spell effect" end,
}
C_Item = {
    GetItemIconByID = function(itemID) assert(itemID == 20744) return 456 end,
    GetItemInfo = function() return "Minor Wizard Oil", displayEntry.itemLink end,
}
C_TooltipInfo = { GetHyperlink = function(link)
    assert(link == "item:20744")
    return { lines = { { leftText = "Minor Wizard Oil" }, { leftText = "Use: Increases spell damage." } } }
end }
local display = addon.Compat.RecipeDisplay(displayEntry, true)
assert(display.icon == 456 and display.description:find("spell damage", 1, true))
local hidden = {}
canaccessvalue = function(value) return value ~= hidden end
C_TooltipInfo.GetHyperlink = function() return { lines = { {}, { leftText = hidden } } } end
C_Spell.GetSpellInfo = function() return { iconID = hidden } end
C_Item.GetItemIconByID = function() return hidden end
display = addon.Compat.RecipeDisplay(displayEntry, true)
assert(display.icon == "Interface\\Icons\\INV_Misc_QuestionMark" and display.description == "Spell effect")
canaccessvalue = nil

local whisperedName, whisperedText
IsInGuild = function() return true end
ChatFrameUtil = { SendTellWithMessage = function(name, text) whisperedName, whisperedText = name, text end }
assert(addon.Compat.OpenCraftRequest(displayEntry, { name = "Crafter-Realm" }))
assert(whisperedName == "Crafter" and whisperedText:find(displayEntry.itemLink, 1, true))
local qualifiedCrafter = { name = "Other Crafter-Beta ClassicBetaPvP2" }
assert(addon.Compat.OpenCraftRequest(displayEntry, qualifiedCrafter))
assert(whisperedName == "Other Crafter", "whisper recipients must keep the surname but omit the realm")
assert(qualifiedCrafter.name == "Other Crafter-Beta ClassicBetaPvP2", "stored guild identities must remain realm-qualified")
assert(addon.Compat.OpenCraftRequest(displayEntry, { name = "Other Crafter" }))
assert(whisperedName == "Other Crafter", "unqualified first and last names must remain unchanged")
assert(not addon.Compat.OpenCraftRequest(displayEntry, { name = "You", isLocal = true }))
assert(not addon.Compat.OpenCraftRequest(displayEntry, { name = "bad\nname" }))
ChatFrameUtil.GetActiveWindow = function() return { GetText = function() return "Unsent message" end } end
assert(not addon.Compat.OpenCraftRequest(displayEntry, { name = "Crafter-Realm" }), "existing drafts must be preserved")
ChatFrameUtil, C_TooltipInfo, C_Item, C_Spell = nil, nil, nil, nil
assert(not addon.Compat.OpenCraftRequest(displayEntry, { name = "Crafter-Realm" }))
display = addon.Compat.RecipeDisplay(displayEntry, true)
assert(display.description == "Item details unavailable.")
print("PASS: guarded item details, cache fallbacks, and editable whisper drafts")

local methods = {}
for _, name in ipairs({
    "SetSize", "SetPoint", "SetFrameStrata", "SetToplevel", "SetClampedToScreen",
    "SetMovable", "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
    "SetTitle", "SetTexture", "SetTexCoord", "SetJustifyH", "SetWordWrap", "SetAllPoints",
    "SetHeight", "SetAutoFocus", "SetTextInsets", "SetMaxLetters", "RegisterForClicks",
    "SetScrollChild", "ClearAllPoints", "SetHighlightTexture", "SetJustifyV", "LockHighlight",
    "UnlockHighlight", "SetNormalFontObject", "SetID",
    "SetWidth", "SetScale", "SetNormalTexture", "SetPushedTexture", "SetDisabledTexture",
    "SetEnabled", "SetVerticalScroll", "ClearFocus",
}) do
    methods[name] = function() end
end
local function Widget(name)
    return setmetatable({ name = name, shown = true, scripts = {} }, { __index = methods })
end
function methods:SetText(text) self.text = text end
function methods:GetText() return self.text or "" end
function methods:GetName() return self.name end
function methods:SetPoint(...) self.point = { ... } end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width or 1024 end
function methods:GetHeight() return self.height or 768 end
function methods:SetScale(scale) self.scale = scale end
function methods:SetAlpha(alpha) self.alpha = alpha end
function methods:SetEnabled(enabled) self.enabled = enabled end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:SetChecked(checked) self.checked = checked end
function methods:GetChecked() return self.checked end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:CreateFontString() return Widget() end
function methods:CreateTexture() return Widget() end
function methods:GetStringHeight() return math.max(14, #(self.text or "") / 30 * 14) end
function methods:RegisterEvent(event)
    self.events = self.events or {}
    self.events[event] = true
end

UIParent = Widget("UIParent")
local frames = {}
local nativeTabs = true
local availableTabTemplate = "PanelTabButtonTemplate"
local atlasTabs = true
PanelTemplates_AnchorTabs = function() end
PanelTemplates_TabResize = function(tab) tab.sizedText = tab:GetText() end
CreateFrame = function(kind, name, parent, template)
    local widget = Widget(name)
    widget.parent = parent
    widget.template = template
    if template == "PortraitFrameTemplate" then widget.CloseButton = Widget() end
    if template == availableTabTemplate and nativeTabs then
        widget.Left = Widget()
        if atlasTabs then widget.LeftActive = Widget() end
    end
    frames[#frames + 1] = widget
    return widget
end

local printed
local published = 0
addon.Print = function(message) printed = message end
addon.Sync = { status = "Ready", Publish = function() published = published + 1 end }
addon.db = nil
assert(loadfile("HordeEternal/Canvas.lua"))("HordeEternal", addon)
assert(type(addon.ToggleCanvas) == "function", "canvas must load before the database exists")
addon.db = {}
addon.ToggleCanvas()
local canvas = frames[1]
assert(canvas:IsShown() and #canvas.tabs == 2, "fresh database must allow full window construction")
assert(canvas.tabs[1]:GetText() == "Guild" and canvas.tabs[2]:GetText() == "Crafting")
assert(canvas.tabs[1].sizedText == "Guild" and canvas.tabs[2].sizedText == "Crafting", "resize must use tab labels")
assert(addon.db.canvasTab == "crafting")
assert(canvas.selectedTab == 2 and canvas.tabStyle == "mainline")
assert(canvas.width == 720 and canvas.height == 600 and canvas.scale == 1)
UIParent.width, UIParent.height = 640, 480
canvas.scripts.OnEvent(canvas, "UI_SCALE_CHANGED")
assert(canvas.scale <= 480 / 660, "the window and external tabs must fit a small viewport")
UIParent.width, UIParent.height = nil, nil
canvas.scripts.OnEvent(canvas, "DISPLAY_SIZE_CHANGED")
assert(canvas.scale == 1)
assert(canvas.tabs[1].point[2] == canvas and canvas.tabs[1].point[3] == "BOTTOMLEFT")
assert(canvas.tabs[1].point[4] == 5 and canvas.tabs[1].point[5] == 2)
assert(canvas.tabs[2].point[1] == "TOPLEFT" and canvas.tabs[2].point[4] == 3)
assert(frames[2].point[1] == "BOTTOMRIGHT" and frames[2].point[5] == 6, "no empty internal tab footer")
canvas.tabs[1].scripts.OnClick()
assert(addon.db.canvasTab == "guild")
assert(canvas.selectedTab == 1)
canvas.tabs[2].scripts.OnClick()
assert(addon.db.canvasTab == "crafting")

local scanButton
for _, widget in ipairs(frames) do
    assert(widget.template ~= "UICheckButtonTemplate", "sharing must not require a checkbox")
    if widget:GetText() == "Rescan" then scanButton = widget end
end
assert(scanButton and scanButton.scripts.OnClick, "Scan must have a click handler")
assert(scanButton.point[1] == "TOPRIGHT" and scanButton.parent ~= scanButton.point[2].parent,
    "Rescan must sit in the page toolbar, not beside the filter")
GameTooltip = Widget()
function methods:SetOwner(owner) self.owner = owner end
function methods:AddLine(text) self.lastLine = text end
scanButton.scripts.OnEnter(scanButton)
assert(GameTooltip.owner == scanButton and GameTooltip:GetText() == "Rescan recipes")
scanButton.scripts.OnLeave()
assert(not GameTooltip:IsShown())
scanButton.scripts.OnClick()
assert(printed:find("no recipe list available", 1, true), "failed button scans must report a reason")
assert(published == 0, "failed scans must not publish")
C_TradeSkillUI.GetAllRecipeIDs = function() return { 25124 } end
C_TradeSkillUI.GetTradeSkillLineForRecipe = function() return 333 end
scanButton.scripts.OnClick()
assert(printed:find("1 checked; 1 learned", 1, true), "Scan click must scan and report success")
assert(published == 1, "successful scans must publish without opt-in")
assert(#addon.Catalog.Search("wizard") == 1)
local crafting = canvas.crafting
assert(crafting.headerTotal.point[1] == "TOPRIGHT" and crafting.headerTotal.point[5] == -28,
    "the header must be constrained horizontally without stretching into the content")
assert(not crafting.detail:IsShown() and crafting.rows[1].profession, "crafting must open on professions")
local enchantingRow
for _, row in ipairs(crafting.rows) do
    if row.profession and row.profession.id == 333 then enchantingRow = row end
end
assert(enchantingRow)
enchantingRow.scripts.OnClick(enchantingRow)
assert(crafting.detail:IsShown() and crafting.rows[1].entry.recipeID == 25124)
assert(not crafting.crafters[1].request:IsShown(), "do not whisper yourself")
addon.db.catalog.remoteProfiles["Crafter-Realm"] = {
    updatedAt = 900, recipes = addon.db.catalog.localProfile.recipes,
}
local crafterPresence = { ["Crafter-Realm"] = true, ["Absent Crafter-Realm"] = false }
addon.GuildState = {
    IsReady = function() return true end,
    Resolve = function(name) return addon.db.catalog.remoteProfiles[name] and name end,
    IsOnline = function(name) return crafterPresence[name] end,
}
addon.db.catalog.remoteProfiles["Absent Crafter-Realm"] = {
    updatedAt = 900, recipes = addon.db.catalog.localProfile.recipes,
}
addon.db.catalog.remoteProfiles["Unknown Crafter-Realm"] = {
    updatedAt = 900, recipes = addon.db.catalog.localProfile.recipes,
}
addon.RefreshCatalog()
local request
for _, row in ipairs(crafting.crafters) do
    if row.request.crafter.name == "Crafter-Realm" then request = row.request end
end
assert(request and request:IsShown())
assert(request.enabled and crafting.crafters[1].request.crafter.name == "Crafter-Realm")
assert(crafting.crafters[3].request.crafter.name == "Absent Crafter-Realm"
    and not crafting.crafters[3].request.enabled and crafting.crafters[3].alpha == 0.5
    and crafting.crafters[3].age:GetText():find("Offline", 1, true), "offline crafters must remain visible but disabled")
assert(not crafting.crafters[4].request.enabled
    and crafting.crafters[4].age:GetText():find("Status unavailable", 1, true), "unknown presence must not enable whispers")
ChatFrameUtil = { SendTellWithMessage = function(name, text) whisperedName, whisperedText = name, text end }
request.scripts.OnClick(request)
assert(whisperedName == "Crafter" and whisperedText:find("Minor Wizard Oil", 1, true))
whisperedName = nil
crafterPresence["Crafter-Realm"] = false
request.scripts.OnClick(request)
assert(whisperedName == nil and printed:find("offline", 1, true), "whisper actions must recheck status even before the row refreshes")
crafterPresence["Absent Crafter-Realm"] = true
addon.RefreshCatalog()
assert(crafting.crafters[1].request.crafter.name == "Absent Crafter-Realm"
    and crafting.crafters[1].request.enabled and crafting.crafters[1].alpha == 1,
    "reused rows must re-enable when the crafter comes online")
assert(crafting.crafters[3].request.crafter.name == "Crafter-Realm" and not crafting.crafters[3].request.enabled)
crafting.crafters[4].request.scripts.OnClick(crafting.crafters[4].request)
assert(whisperedName == nil, "unknown presence must also fail the whisper action gate")
assert(crafting.headerTotal:GetText():find("1 / 1", 1, true), "header must deduplicate guild recipe knowledge")
addon.db.catalog.localProfile.recipes[1].itemLink = displayEntry.itemLink
addon.RefreshCatalog()
C_Item = {
    GetItemInfo = function() return "Cached Wizard Oil", displayEntry.itemLink end,
    GetItemIconByID = function() return 789 end,
}
canvas.scripts.OnEvent(canvas, "ITEM_DATA_LOAD_RESULT", 20744, true)
assert(crafting.rows[1].label:GetText() == "Cached Wizard Oil" and crafting.rows[1].icon.texture == 789,
    "item-load events must refresh the selected recipe without another scan")
C_Item = nil
crafting.backButton.scripts.OnClick()
assert(not crafting.detail:IsShown() and crafting.rows[1].profession)
crafting.search:SetText("wizard")
crafting.search.scripts.OnTextChanged()
assert(crafting.rows[1].entry and crafting.detail:IsShown(), "global search must browse recipes")
crafting.search:SetText("no such recipe")
crafting.search.scripts.OnTextChanged()
assert(not crafting.rows[1]:IsShown(), "empty searches must hide stale recipe rows")
crafting.backButton.scripts.OnClick()
for recipeID = 100001, 100121 do
    addon.db.catalog.recipeIndex[tostring(recipeID)] = {
        recipeID = recipeID, skillLineID = 171, itemName = "Page recipe " .. recipeID, professionName = "Alchemy",
    }
end
addon.RefreshCatalog()
local alchemyRow
for _, row in ipairs(crafting.rows) do
    if row.profession and row.profession.id == 171 then alchemyRow = row end
end
alchemyRow.scripts.OnClick(alchemyRow)
assert(crafting.pageLabel:GetText():find("1 / 3", 1, true) and not crafting.previousButton.enabled)
crafting.nextButton.scripts.OnClick()
assert(crafting.rows[1].entry.recipeID == 100051)
crafting.nextButton.scripts.OnClick()
assert(crafting.rows[21]:IsShown() and not crafting.rows[22]:IsShown() and not crafting.nextButton.enabled)
crafting.search:SetText("100121")
crafting.search.scripts.OnTextChanged()
assert(crafting.rows[1].entry.recipeID == 100121 and crafting.pageLabel:GetText():find("1 / 1", 1, true))
crafting.backButton.scripts.OnClick()
ChatFrameUtil = nil
addon.GuildState = nil
addon.ToggleCanvas()
assert(not canvas:IsShown())
addon.ToggleCanvas()
assert(canvas:IsShown() and frames[1] == canvas)
print("PASS: profession home, paginated search, item-load refresh, whisper buttons, Rescan, and small viewport fit")

for _, sharingEnabled in ipairs({ true, false }) do
    nativeTabs = false
    frames = {}
    addon.db = {
        catalog = { shareEnabled = sharingEnabled, sharingDefaultsVersion = 1, remoteProfiles = {} },
        canvasTab = "guild", canvasTabVersion = 1,
    }
    assert(loadfile("HordeEternal/Canvas.lua"))("HordeEternal", addon)
    addon.ToggleCanvas()
    canvas = frames[1]
    assert(canvas:IsShown() and #canvas.tabs == 2 and canvas.tabs[1].isFallback)
    assert(addon.db.canvasTab == "guild", "saved tab selection must survive")
    assert(addon.db.catalog.shareEnabled == sharingEnabled, "UI construction must preserve sharing settings")
    canvas.tabs[2].scripts.OnClick()
    assert(addon.db.canvasTab == "crafting")
end
print("PASS: no sharing checkbox, fallback tabs, saved selection, and sharing settings")

nativeTabs = true
atlasTabs = false
FriendsFrameTab1 = {}
for _, template in ipairs({ "CharacterFrameTabButtonTemplate", "TabButtonTemplate" }) do
    availableTabTemplate = template
    frames = {}
    addon.db = {}
    assert(loadfile("HordeEternal/Canvas.lua"))("HordeEternal", addon)
    addon.ToggleCanvas()
    canvas = frames[1]
    assert(canvas.tabs[1].template == template and canvas.tabStyle == "classic")
    assert(canvas.tabs[1].point[4] == 10 and canvas.tabs[1].point[5] == 2)
    assert(canvas.tabs[2].point[1] == "LEFT" and canvas.tabs[2].point[4] == -15)
    assert(canvas.selectedTab == 2)
end
FriendsFrameTab1 = nil
print("PASS: Olympus-style external tab anchors, art-based spacing, and classic template fallbacks")

function methods:RegisterEvent(event)
    self.events = self.events or {}
    self.events[event] = true
end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:IsEventRegistered(event) return self.events and self.events[event] == true end

local timers, sent = {}, {}
local registered = false
GetTime = function() return 10 end
IsInGuild = function() return true end
GetNormalizedRealmName = function() return "ForeverRealm" end
UnitFullName = function() return "Podcast", "Clawson" end
GetGuildInfo = function() return "Horde Eternal", "Member", 5, "ForeverRealm" end
GetNumGuildMembers = function() return 2 end
GetGuildRosterInfo = function(index)
    return index == 1 and "Podcast Clawson-ForeverRealm" or "Podcast Clawson-OtherRealm"
end
Enum = { SendAddonMessageResult = { Success = 0 } }
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
C_ChatInfo = {
    InChatMessagingLockdown = function() return false end,
    AreOutgoingAddonChatMessagesRestricted = function() return false end,
    RegisterAddonMessagePrefix = function() registered = true end,
    IsAddonMessagePrefixRegistered = function() return registered end,
    SendAddonMessage = function(prefix, message, channel)
        assert(prefix == "HERC2" and channel == "GUILD")
        sent[#sent + 1] = message
        return 0
    end,
}
frames = {}
addon.db = nil
addon.CreateMinimapButton = function() end
SlashCmdList = {}
HordeEternalDB = nil
HordeEternalCharacterDB = nil
assert(loadfile("HordeEternal/GuildState.lua"))("HordeEternal", addon)
assert(loadfile("HordeEternal/Sync.lua"))("HordeEternal", addon)
assert(loadfile("HordeEternal/Core.lua"))("HordeEternal", addon)
local lifecycle = frames[2]
lifecycle.scripts.OnEvent(lifecycle, "ADDON_LOADED", "OtherAddon")
assert(addon.db == nil)
lifecycle.scripts.OnEvent(lifecycle, "ADDON_LOADED", "HordeEternal")
assert(addon.characterDB.catalog.shareEnabled == true and addon.db.catalog == nil)
lifecycle.scripts.OnEvent(lifecycle, "PLAYER_LOGIN")
while #timers > 0 do table.remove(timers, 1)() end
assert(#sent == 2 and sent[1] == "2|H|Horde Eternal@ForeverRealm|1|" and sent[2]:find("2|P|", 1, true) == 1,
    "login must scan, request, and publish automatically")

UnitFullName = function(unit)
    assert(unit == "player")
    return "Podcast", "Clawson"
end
GetNormalizedRealmName = function() return "ForeverRealm" end
assert(addon.Compat.IsPlayerName("Podcast Clawson"))
assert(addon.Compat.IsPlayerName("Podcast Clawson-ForeverRealm"))
assert(not addon.Compat.IsPlayerName("Podcast Clawson-OtherRealm"))
assert(not addon.Compat.IsPlayerName("Podcast"), "a shared first name must not match the local player")
assert(not addon.Compat.IsPlayerName("Podcast Othername"), "different surnames must remain different crafters")
for _, sender in ipairs({ "Podcast Clawson", "Podcast Clawson-ForeverRealm" }) do
    addon.Sync.Receive("HERC2", sent[1], "GUILD", sender)
    addon.Sync.Receive("HERC2", sent[2], "GUILD", sender)
    assert(addon.characterDB.catalog.remoteProfiles[sender] == nil, "own profile echoes must not enter the remote cache")
end
assert(#timers == 0, "own requests must not schedule redundant replies")
addon.Sync.Receive("HERC2", sent[2], "GUILD", "Podcast Clawson-OtherRealm")
assert(addon.characterDB.catalog.remoteProfiles["Podcast Clawson-OtherRealm"], "another realm's crafter must still sync")
addon.characterDB.catalog.remoteProfiles["Podcast Clawson"] = addon.characterDB.catalog.localProfile
addon.characterDB.catalog.remoteProfiles["Podcast Clawson-ForeverRealm"] = addon.characterDB.catalog.localProfile
local deduplicated = addon.Catalog.Search("wizard")
assert(#deduplicated == 1 and #deduplicated[1].crafters == 2,
    "cached own profiles must be removed while retaining the other crafter")
assert(addon.characterDB.catalog.remoteProfiles["Podcast Clawson"] == nil
    and addon.characterDB.catalog.remoteProfiles["Podcast Clawson-ForeverRealm"] == nil)
addon.characterDB.catalog.remoteProfiles["Podcast Clawson-OtherRealm"] = nil
deduplicated = addon.Catalog.Search("wizard")
assert(#deduplicated[1].crafters == 1 and deduplicated[1].crafters[1].name == "You"
    and deduplicated[1].crafters[1].isLocal, "the current player must appear once as You")
UnitFullName = function() return "Podcast Clawson", "ForeverRealm" end
assert(addon.Compat.IsPlayerName("Podcast Clawson-ForeverRealm"), "already-complete names must still work")
UnitFullName = function() return "Podcast Clawson", nil end
assert(addon.Compat.IsPlayerName("Podcast Clawson-ForeverRealm"), "missing realm uses the client's home realm")
UnitFullName = function() return "Podcast", "ForeverRealm" end
assert(addon.Compat.IsPlayerName("Podcast-ForeverRealm"), "actual realms must not be appended as surnames")
local inaccessibleIdentity = {}
canaccessvalue = function(value) return value ~= inaccessibleIdentity end
GetNormalizedRealmName = function() return inaccessibleIdentity end
assert(not addon.Compat.IsPlayerName("Podcast"), "an inaccessible home realm must not authorize a name match")
GetNormalizedRealmName = function() return "ForeverRealm" end
UnitFullName = function() return "Podcast Clawson", inaccessibleIdentity end
assert(not addon.Compat.IsPlayerName("Podcast Clawson"), "restricted tuple fields must not authorize identity matching")
UnitFullName = function() return inaccessibleIdentity, "ForeverRealm" end
assert(not addon.Compat.IsPlayerName("Podcast Clawson"))
canaccessvalue, UnitFullName, GetNormalizedRealmName = nil, nil, nil
assert(not addon.Compat.IsPlayerName("Podcast Clawson"), "missing identity APIs must not hide other profiles")
print("PASS: Forever split surnames, self-echo suppression, cached self cleanup, realm identity, and single You crafter")
GetNormalizedRealmName = function() return "ForeverRealm" end
UnitFullName = function() return "Podcast", "Clawson" end
assert(addon.GuildState.RefreshRoster())

C_ChatInfo.InChatMessagingLockdown = function() return true end
C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return true end
assert(addon.Sync.Publish() == true)
while #timers > 0 do table.remove(timers, 1)() end
assert(#sent == 3, "chat-policy flags must not preempt the addon-message API")
assert(addon.Sync.status == "Guild message accepted; delivery is unconfirmed")

assert(addon.Sync.Publish() == true)
addon.Sync.SetSharing(false)
while #timers > 0 do table.remove(timers, 1)() end
assert(#sent == 3, "opting out must cancel queued sends")

addon.Catalog.SetSharing(true)
assert(addon.Sync.Publish() == true)
IsInGuild = function() return false end
while #timers > 0 do table.remove(timers, 1)() end
assert(#sent == 3 and addon.Sync.status == "Join a guild before syncing")
addon.Sync.SetSharing(false)
IsInGuild = function() return true end
assert(addon.GuildState.RefreshRoster())

local attempts = 0
for _, outcome in ipairs({ "rejected", "nil", "error" }) do
    C_ChatInfo.SendAddonMessage = function()
        attempts = attempts + 1
        if outcome == "error" then error("mock send failure") end
        if outcome == "rejected" then return 9 end
    end
    addon.Catalog.SetSharing(true)
    assert(addon.Sync.Publish() == true)
    local previousAttempts = attempts
    while #timers > 0 do table.remove(timers, 1)() end
    assert(attempts == previousAttempts + 1, "failed sends must not retry indefinitely")
    if outcome == "error" then
        assert(addon.Sync.status == "Guild send error")
    else
        local expected = outcome == "rejected" and "result: 9" or "result: <nil>"
        assert(addon.Sync.status:find(expected, 1, true), "rejection status must show the actual send result")
    end
    addon.Sync.SetSharing(false)
end
print("PASS: automatic guild sync, addon API acceptance/refusal, and queued-send authorization")