local addon = { db = {} }
assert(loadfile("HordeEternal/Compat.lua"))("HordeEternal", addon)
assert(loadfile("HordeEternal/Members.lua"))("HordeEternal", addon)
local now, player, ready = 10, "Main Person-Realm", true
local roster = {
    { name = "Main Person-Realm", className = "Shaman", classFile = "SHAMAN", online = true, rank = "Officer", rankIndex = 1 },
    { name = "Alt Person-Realm", className = "Paladin", classFile = "PALADIN", online = false, rank = "Raider", rankIndex = 3 },
    { name = "Unknown Person-Realm", className = "Mage", classFile = "MAGE" },
}
addon.Compat.IsPlayerName = function(name) return name == player end
addon.GuildState = {
    key = "Guild@Realm", IsReady = function() return ready end,
    Rows = function() return ready and roster or {} end,
    Resolve = function(name)
        if not ready then return nil end
        for _, row in ipairs(roster) do if row.name == name then return name end end
    end,
}
local sent, timers = {}, {}
addon.Sync = { QueueMembers = function(packets) for _, packet in ipairs(packets) do sent[#sent + 1] = packet end return true end }
GetTime = function() return now end
time = function() return 1000 + now end
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
UnitRace = function() return "Orc", "Orc", 2 end
C_ClassTalents = { GetActiveConfigID = function() return 7 end }
local spent = { 5, 31, 15 }
C_Traits = {
    ConfigHasStagedChanges = function() return false end,
    GetConfigInfo = function(id) assert(id == 7); return { treeIDs = { 9 } } end,
    GetGroupDisplayInfoByTreeID = function(id)
        assert(id == 9)
        return { { groupID = 1, displayName = "Elemental" }, { groupID = 2, displayName = "Enhancement" }, { groupID = 3, displayName = "Restoration" } }
    end,
    GetGroupCurrencyInfo = function(id, groups)
        assert(id == 7 and #groups == 3)
        return { { traitNodeGroupID = 3, currencyInfos = { { spent = spent[3] } } },
            { traitNodeGroupID = 1, currencyInfos = { { spent = spent[1] } } },
            { traitNodeGroupID = 2, currencyInfos = { { spent = spent[2] } } } }
    end,
}
local race, spec, points = addon.Compat.PlayerGuildFacts()
assert(race == "Orc" and spec == "Enhancement" and points:find("Enhancement: 31", 1, true))
C_Traits.ConfigHasStagedChanges = function() return true end
assert(select(2, addon.Compat.PlayerGuildFacts()) == nil, "uncommitted talent edits must not be advertised")
C_Traits.ConfigHasStagedChanges = function() return false end
spent = { 20, 20, 11 }
assert(select(2, addon.Compat.PlayerGuildFacts()) == "Hybrid")
spent = { 0, 0, 0 }
assert(select(2, addon.Compat.PlayerGuildFacts()) == "No talents spent")
local secret = {}
spent[1] = secret
canaccessvalue = function(value) return value ~= secret end
assert(select(2, addon.Compat.PlayerGuildFacts()) == nil, "restricted tree points must not be guessed")
UnitRace = function() return "Orc", "Orc", secret end
assert(addon.Compat.PlayerGuildFacts() == nil, "late race returns must be guarded")
canaccessvalue = nil
UnitRace = function() return "Orc", "Orc", 2 end
spent = { 5, 31, 15 }
assert(not addon.Members.CanView() and #addon.Members.Rows() == 0 and addon.Members.Stats(false).all == 0,
    "unconfigured accounts must not expose guild information")
assert(addon.Members.Save(true, "   "))
assert(not addon.Members.CanView(), "a main without a nonblank server nickname must stay locked")
assert(addon.Members.Save(false, "Server Nickname"))
assert(not addon.Members.CanView(), "a server nickname without a main must stay locked")
assert(addon.Members.Save(true, "test.handle"))
assert(addon.Members.CanView())
addon.Members.Settings().discordNicknameVersion = nil
assert(not addon.Members.CanView(), "old handles require confirmation as a server nickname")
assert(addon.Members.Settings().discord == "test.handle", "migration must preserve the old text for editing")
assert(addon.Members.Save(true, "test.handle"))
assert(addon.Members.Settings().main == player)
local stats = addon.Members.Stats(true)
assert(stats.total == 1 and stats.mains == 1 and stats.all == 3 and stats.classes.Shaman == 1 and stats.races.Orc == 1)
assert(addon.Members.Stats(false).races.Unknown == 2)
player = "Alt Person-Realm"
UnitRace = function() return "Tauren", "Tauren", 6 end
addon.Members.Capture()
local rows = addon.Members.Rows()
assert(rows[2].state == "Alt" and rows[2].main == "Main Person-Realm" and rows[2].discord == "test.handle")
assert(rows[3].state == "No main selected" and rows[3].race == "Unknown")
local departedMain = table.remove(roster, 1)
addon.Members.Capture()
assert(addon.Members.Settings().main == "" and #addon.Members.Rows() == 0 and not addon.Members.CanView(),
    "a departed main must not leave alts advertising an invalid guild link")
table.insert(roster, 1, departedMain)
player = "Main Person-Realm"
addon.Members.Capture()
player = "Alt Person-Realm"
assert(addon.Members.Save(true, "new.handle"))
rows = addon.Members.Rows()
assert(rows[1].state == "Alt" and rows[2].state == "Main", "selecting a new main must demote the old one")
assert(addon.Members.Stats(true).classes.Paladin == 1 and addon.Members.Stats(true).classes.Shaman == 0)
assert(addon.Members.Save(false, ""))
assert(addon.Members.Stats(true).total == 0 and #addon.Members.Rows() == 0 and addon.Members.Settings().discord == "")
assert(not addon.Members.Save(true, "bad|Hlink") and not addon.Members.Save(true, string.rep("x", 33)))
assert(addon.Members.Save(true, "contact"))
addon.Members.Publish()
local packets = sent
addon.db = {}
player = "Unknown Person-Realm"
for index = #packets, 1, -1 do addon.Members.Receive("HEGM1", packets[index], "GUILD", "Alt Person-Realm") end
assert(#addon.Members.Rows() == 0, "receiving profiles must not unlock an unconfigured account")
assert(addon.Members.Save(true, "Receiver Nickname"))
rows = addon.Members.Rows()
assert(rows[2].state == "Main" and rows[2].discord == "contact" and rows[2].race == "Tauren",
    "bounded profiles must round-trip and assemble reordered chunks")
local before = addon.Members.Stats(true).total
addon.Members.Receive("HEGM1", packets[1], "GUILD", "Outsider-Realm")
addon.Members.Receive("HEGM1", packets[1], "WHISPER", "Alt Person-Realm")
assert(addon.Members.Stats(true).total == before)
ready = false
assert(#addon.Members.Rows() == 0 and not addon.Members.Save(true, "test"))
ready = true
table.remove(roster, 2)
assert(addon.Members.Stats(true).total == 1 and addon.Members.Stats(true).classes.Paladin == 0,
    "the departed character must not count as a main while the receiver's own main remains")
assert(addon.Members.Save(false, ""))
print("PASS: guild profiles, one-main switching, alt links, Discord clearing, race coverage, talent estimates, and bounded profile exchange")

local methods = {}
for _, method in ipairs({ "SetPoint", "SetSize", "SetWidth", "SetHeight", "SetJustifyH", "SetJustifyV", "SetWordWrap",
    "SetAutoFocus", "SetMaxLetters", "SetTextInsets", "SetScrollChild", "SetHighlightTexture", "ClearAllPoints",
    "SetVerticalScroll", "SetNormalTexture", "SetDisabledTexture", "ClearFocus", "SetOwner", "AddLine", "Enable", "Disable",
    "SetAllPoints", "SetColorTexture", "SetTextColor", "SetTexCoord", "SetFrameStrata", "EnableMouse", "SetPushedTexture" }) do
    methods[method] = function() end
end
local function Widget() return setmetatable({ scripts = {} }, { __index = methods }) end
function methods:SetPoint(...) self.point = { ... } end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetTexCoord(...) self.coordinates = { ... } end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:SetText(text) self.text = text end
function methods:GetText() return self.text or "" end
function methods:SetEnabled(enabled) self.enabled = enabled end
function methods:SetChecked(checked) self.checked = checked end
function methods:GetChecked() return self.checked end
function methods:SetAlpha(alpha) self.alpha = alpha end
function methods:SetTexture(texture) self.texture = texture end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:CreateFontString() return Widget() end
function methods:CreateTexture() return Widget() end
CreateFrame = function() return Widget() end
GameTooltip = Widget()
assert(loadfile("HordeEternal/GuildView.lua"))("HordeEternal", addon)
addon.db.canvasTab = "guild"
player = "Main Person-Realm"
addon.Members.Capture()
local header, subheader = Widget(), Widget()
local view = addon.CreateGuildView(Widget(), header, subheader)
assert(not view.editor.shown and #view.rows == 6, "profile editing must not occupy the member workspace or require nested list scrolling")
view.profile.scripts.OnClick()
assert(view.editor.shown and view.shade.shown, "the profile dialog must cover the directory with an input-blocking shade")
for index, row in ipairs(view.rows) do
    assert(row.width == 680 and row.height == 39 and row.point[5] == -(index - 1) * 39)
    local cells = { row.name, row.className, row.spec, row.role, row.identity }
    for column = 1, #cells - 1 do
        assert(cells[column].point[4] + cells[column].width < cells[column + 1].point[4],
            "member table text columns must never overlap")
    end
    assert(cells[5].point[4] + cells[5].width <= row.width)
end
assert(248 + #view.rows * 39 < 538 - 34, "the directory must fit above the footer without a scroll frame")
assert(view.mains:GetChecked() and not view.everyone:GetChecked() and view.locked.shown and not view.body.shown
    and header:GetText() == "Guild profile", "unconfigured users must see setup instead of counts or character data")
view.main:SetChecked(true)
view.main.scripts.OnClick()
view.discord:SetText("my.discord")
view.discord.scripts.OnTextChanged(view.discord, true)
view.Refresh()
assert(view.discord:GetText() == "my.discord" and view.main:GetChecked(), "roster refreshes must not discard an unsaved profile draft")
view.save.scripts.OnClick()
assert(addon.Members.Settings().main == player and addon.Members.Settings().discord == "my.discord")
assert(view.body.shown and not view.locked.shown, "saving a main and server nickname must unlock information")
assert(view.coverage:GetText():find("1 counted", 1, true)
    and view.statRows[1].statName == "Shaman" and view.statRows[1].statCount == 1)
assert(view.statRows[1].count:GetText() == "1 (100.0%)")
view.everyone.scripts.OnClick()
assert(not view.mains:GetChecked() and view.everyone:GetChecked() and view.coverage:GetText():find("2 counted", 1, true))
assert(view.statRows[1].count:GetText() == "1 (50.0%)", "percentages must use the selected character population")
assert(view.statRows[1].label.point[4] + view.statRows[1].label.width < view.statRows[1].count.point[4],
    "adding percentage text must not overlap the category name")
assert(view.directoryCount:GetText():find("characters", 1, true) and not view.directoryCount:GetText():find("members", 1, true))
for index = 1, 53 do roster[#roster + 1] = { name = "Roster Person " .. index .. "-Realm", className = "Mage" } end
view.Refresh()
assert(view.nextPage.enabled and not view.previous.enabled)
view.nextPage.scripts.OnClick()
assert(view.page == 2 and view.previous.enabled)
view.nextPage.scripts.OnClick()
assert(view.page == 3 and view.nextPage.enabled)
for _ = 1, 7 do view.nextPage.scripts.OnClick() end
assert(view.page == 10 and not view.nextPage.enabled and view.rows[1].shown and not view.rows[2].shown)
view.filter:SetText("Unknown Person")
view.filter.scripts.OnTextChanged()
assert(view.page == 1 and view.rows[1].member.name == "Unknown Person-Realm" and not view.rows[2].shown)
view.rows[1].scripts.OnEnter(view.rows[1])
assert(GameTooltip:GetText() == "Unknown Person-Realm")
ready = false
view.Refresh()
assert(not view.save.enabled and not view.main.enabled and not view.rows[1].shown)
ready = true
view.Refresh()
assert(view.main.enabled and header:GetText() == "Guild overview")
view.close.scripts.OnClick()
assert(not view.editor.shown and not view.shade.shown)
view.statTabs.races.scripts.OnClick()
assert(view.category == "races" and view.statRows[1].statName == "Unknown")
assert(not view.statRows[1].icon.shown and view.statRows[1].label.point[4] == 0,
    "race counts must not use placeholder class icons")
view.statTabs.classes.scripts.OnClick()
assert(view.statRows[1].icon.shown and view.statRows[1].label.point[4] == 27,
    "reusing a stat cell must restore the class layout")
for _, cell in ipairs(view.statRows) do
    assert(cell.icon.texture == "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES",
        "all nine classes need real class icons even with no roster class token")
end
view.profile.scripts.OnClick()
view.discord:SetText("discard.this")
view.discord.scripts.OnTextChanged(view.discord, true)
view.editor.scripts.OnKeyDown(view.editor, "ESCAPE")
assert(not view.editor.shown and not view.shade.shown and addon.Members.Settings().discord == "my.discord")
view.profile.scripts.OnClick()
assert(view.discord:GetText() == "my.discord", "cancelling profile editing must discard unsaved changes")
view.close.scripts.OnClick()
local realStats = addon.Members.Stats
addon.Members.Stats = function(mainsOnly)
    local result = realStats(mainsOnly)
    result.specs = {}
    for index = 1, 14 do result.specs["Talent group " .. index] = index end
    return result
end
view.statTabs.specs.scripts.OnClick()
assert(view.statsNext.shown and view.statsNext.enabled and not view.statsPrevious.enabled)
view.statsNext.scripts.OnClick()
assert(view.statsPage == 2 and not view.statsNext.enabled and view.statRows[5].shown and not view.statRows[6].shown,
    "all talent breakdowns must remain reachable without resizing the layout")
addon.Members.Stats = realStats
view.statTabs.classes.scripts.OnClick()
assert(view.statsPage == 1 and not view.statsNext.shown)
view.filter:SetText("")
view.filter.scripts.OnTextChanged()
view.page = 5
view.sortHeaders.name.scripts.OnClick()
assert(view.page == 1 and view.sortKey == "name" and view.sortAscending
    and view.rows[1].member.name == "Main Person-Realm", "sorting a heading must reset pagination and sort all filtered characters")
view.sortHeaders.name.scripts.OnClick()
assert(not view.sortAscending and view.rows[1].member.name == "Unknown Person-Realm")
assert(view.sortHeaders.name.indicator.shown)
view.sortHeaders.rank.scripts.OnClick()
assert(view.sortAscending and view.rows[1].member.rank == "Officer" and view.rows[1].role:GetText() == "Officer")
assert(not view.sortHeaders.name.indicator.shown and view.sortHeaders.rank.indicator.shown)
view.sortHeaders.rank.scripts.OnClick()
assert(view.rows[1].member.name == "Main Person-Realm", "unknown guild roles must stay after known ranks in both directions")
view.filter:SetText("Officer")
view.filter.scripts.OnTextChanged()
assert(view.rows[1].member.name == "Main Person-Realm" and not view.rows[2].shown, "guild role must be searchable")
view.filter:SetText("")
view.filter.scripts.OnTextChanged()
view.sortHeaders.spec.scripts.OnClick()
assert(view.sortKey == "spec" and view.rows[1].member.name == "Main Person-Realm")
view.sortHeaders.className.scripts.OnClick()
assert(view.sortKey == "className" and view.rows[1].member.className == "Mage")
view.sortHeaders.main.scripts.OnClick()
assert(view.sortKey == "main" and view.rows[1].member.state == "Main")
assert(addon.Members.Save(true, "   "))
assert(view.locked.shown and not view.body.shown and header:GetText() == "Guild profile"
    and view.rows[1].member == nil, "clearing the nickname must immediately remove displayed character details and counts")
assert(addon.Members.Save(true, "Server Nickname"))
assert(not view.locked.shown and view.body.shown)
player = "Unknown Person-Realm"
assert(addon.Members.CanView(), "alts inherit completed main and server-nickname setup from their account")
player = "Main Person-Realm"
print("PASS: Guild view default mains radio, profile drafts/save, all-character statistics, directory pagination/filtering, and roster availability")

function methods:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function methods:IsEventRegistered(event) return self.events and self.events[event] or false end
local generation = 1
addon.GuildState.Generation = function() return generation end
addon.GuildState.serial = 1
addon.GuildState.ready = true
addon.Catalog = { Initialize = function() return { shareEnabled = false } end }
IsInGuild = function() return ready end
local wire = {}
local prefixes = {}
Enum = { SendAddonMessageResult = { Success = 0 } }
C_ChatInfo = {
    IsAddonMessagePrefixRegistered = function(prefix) return prefixes[prefix] == true end,
    RegisterAddonMessagePrefix = function(prefix) prefixes[prefix] = true end,
    SendAddonMessage = function(prefix, message, channel)
        assert(channel == "GUILD" and #message <= 220)
        wire[#wire + 1] = { prefix = prefix, message = message }
        return 0
    end,
}
assert(loadfile("HordeEternal/Sync.lua"))("HordeEternal", addon)
timers = {}
addon.Members.Invalidate()
addon.Sync.Start(false)
assert(addon.Members.Save(true, "first.handle"))
assert(addon.Members.Publish())
local function Flush()
    local count = 0
    while #timers > 0 do
        count = count + 1
        assert(count < 100, "member broadcasts must stay bounded")
        table.remove(timers, 1)()
    end
end
Flush()
local oldPackets = wire
wire = {}
assert(prefixes.HEGM1 and #oldPackets > 1, "member profiles must use the real queue even when crafting sharing is off")
now = now + 31
assert(addon.Members.Save(true, "latest.handle"))
assert(addon.Members.Publish())
assert(addon.Members.Save(true, "latest.handle"))
generation, addon.GuildState.serial = 2, 2
addon.Sync.Invalidate()
assert(addon.Sync.QueueMembers({ "1|Q|Guild@Realm" }))
Flush()
local newPackets = wire
wire = {}
addon.db = {}
player = "Unknown Person-Realm"
addon.Members.Invalidate()
for _, packet in ipairs(newPackets) do addon.Sync.Receive(packet.prefix, packet.message, "GUILD", "Main Person-Realm") end
for _, packet in ipairs(oldPackets) do
    if packet.prefix == "HEGM1" then addon.Sync.Receive(packet.prefix, packet.message, "GUILD", "Main Person-Realm") end
end
rows = addon.Members.Rows()
assert(#rows == 0, "network updates must not bypass the local setup requirement")
assert(addon.Members.Save(true, "Receiver Nickname"))
rows = addon.Members.Rows()
assert(rows[1].state == "Main" and rows[1].discord == "latest.handle", "older declarations must not undo a newer main/Discord revision")
local profileTable = addon.db.memberGuilds
addon.Sync.Invalidate()
assert(addon.db.memberGuilds == profileTable, "crafting transport invalidation must not erase member information")
addon.Members.Receive("HEGM1", "1|Q|Guild@Realm", "GUILD", "Main Person-Realm")
addon.GuildState.key = "Other Guild@Realm"
Flush()
assert(#wire == 0, "a delayed member response must not cross guild contexts")
print("PASS: real member transport, opt-out independence, revision ordering, member persistence, and guild-change cancellation")