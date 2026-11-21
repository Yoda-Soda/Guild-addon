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
function methods:SetScrollChild(child) self.scrollChild = child end
function methods:SetVerticalScroll(offset)
    self.offset = offset
    if self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self, offset) end
end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:SetDesaturated(desaturated) self.desaturated = desaturated end
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
CreateFrame = function(_, _, _, template)
    local widget = Widget()
    if template == "UIPanelScrollFrameTemplate" then
        widget.ScrollBar = Widget()
        widget.ScrollBar.scripts.OnValueChanged = function(_, offset) widget:SetVerticalScroll(offset) end
    end
    return widget
end
function methods:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
GameTooltip = Widget()
assert(loadfile("HordeEternal/GuildView.lua"))("HordeEternal", addon)
local discordFile = assert(io.open("HordeEternal/media/Discord.tga", "rb"))
local discordBytes = discordFile:read("*a")
discordFile:close()
assert(#discordBytes == 16402 and discordBytes:byte(3) == 2 and discordBytes:byte(13) == 64
    and discordBytes:byte(15) == 64 and discordBytes:byte(17) == 32 and discordBytes:byte(18) == 40,
    "the supplied Discord artwork must be packaged as a 64px alpha-enabled TGA")
addon.db.canvasTab = "guild"
player = "Main Person-Realm"
addon.Members.Capture()
local header, subheader = Widget(), Widget()
local view = addon.CreateGuildView(Widget(), header, subheader)
assert(not view.editor.shown and #view.rows == 7, "the directory must use six visible rows plus one recycled buffer row")
assert(view.profile:GetText() == "Edit" and view.profile.width == 64 and view.profile.height == 24
    and view.profile.point[1] == "TOPRIGHT" and view.profile.icon == nil,
    "profile editing must use a compact labelled Edit button instead of cog artwork")
view.profile.scripts.OnEnter(view.profile)
assert(GameTooltip:GetText() == "Edit guild profile", "the Edit button must preserve its profile tooltip")
view.profile.scripts.OnLeave(view.profile)
assert(not GameTooltip.shown, "leaving the Edit button must hide the tooltip")
view.profile.scripts.OnClick()
assert(view.editor.shown and view.shade.shown, "the profile dialog must cover the directory with an input-blocking shade")
for index, row in ipairs(view.rows) do
    assert(row.width == 654 and row.height == 39)
    local cells = { row.name, row.className, row.spec, row.role, row.identity }
    for column = 1, #cells - 1 do
        assert(cells[column].point[4] + cells[column].width < cells[column + 1].point[4],
            "member table text columns must never overlap")
    end
    assert(cells[5].point[4] + cells[5].width <= row.width)
end
assert(view.scroll.height == 6 * 39 and view.scroll.scrollChild == view.content,
    "the fixed-height scrolling directory must fit above the footer")
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
assert(view.rows[1].identity:GetText() == "Main Person" and view.rows[1].presence:GetText() == "Main",
    "the selected main must show first name and surname without realm or a competing prefix")
assert(view.rows[1].mainIcon.shown and view.rows[1].mainIcon.texture == "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
    and view.rows[1].identity.point[4] > view.rows[1].mainIcon.point[4] + view.rows[1].mainIcon.width
    and view.rows[1].mainIcon.point[4] == view.rows[1].discordIcon.point[4]
    and view.rows[1].mainIcon.point[5] == view.rows[1].identity.point[5],
    "the Main/Discord column must pair a gold star, not the guild-leader crown, with the main name")
assert(view.rows[1].discordIcon.shown and view.rows[1].discordIcon.texture == "Interface\\AddOns\\HordeEternal\\media\\Discord.tga"
    and view.rows[1].contact:GetText() == "my.discord"
    and view.rows[1].discordIcon.point[4] + view.rows[1].discordIcon.width < view.rows[1].contact.point[4],
    "shared server nicknames need the supplied Discord icon without covering the text")
assert(view.rows[2].discordIcon.shown and view.rows[2].mainIcon.shown and view.rows[2].identity:GetText() == "Main Person"
    and view.rows[2].presence:GetText():find("Alt /", 1, true),
    "an alt's Main/Discord column must mark its referenced main name, while still identifying the character as an alt")
assert(view.rows[1].statusDot.vertexColor[2] == 0.9 and view.rows[1].background.color[2] > view.rows[1].background.color[1],
    "online characters must have an unmistakable green presence indicator")
assert(not view.rows[1].presence:GetText():find("Online", 1, true)
    and not view.rows[1].presence:GetText():find(" / $"),
    "online rows must not repeat the Online label or leave a dangling separator")
assert(view.rows[2].presence:GetText():find("Status unknown", 1, true)
    and view.rows[2].statusDot.vertexColor[1] == 0.9, "unknown status must be amber, not styled as offline")
roster[1].online = false
view.Refresh()
assert(view.rows[1].presence:GetText():find("Offline", 1, true) and not view.rows[1].icon.desaturated
    and view.rows[1].background.color[1] == view.rows[1].background.color[2]
    and view.rows[1].name.textColor[1] == view.rows[1].name.textColor[2],
    "offline characters must have gray rows and muted names while keeping class icons in colour")
roster[1].online = true
view.Refresh()
assert(not view.rows[1].icon.desaturated and view.rows[1].statusDot.vertexColor[2] == 0.9
    and view.rows[1].name.textColor[1] ~= view.rows[1].name.textColor[2],
    "a reconnecting character must restore class colour and online styling on the reused row")
assert(not view.rows[1].presence:GetText():find("Online", 1, true)
    and not view.rows[1].presence:GetText():find("Offline", 1, true), "recycled online rows must clear stale presence words")
assert(view.statRows[1].count:GetText() == "1 (100.0%)")
view.everyone.scripts.OnClick()
assert(not view.mains:GetChecked() and view.everyone:GetChecked() and view.coverage:GetText():find("2 counted", 1, true))
assert(view.statRows[1].count:GetText() == "1 (50.0%)", "percentages must use the selected character population")
assert(view.statRows[1].label.point[4] + view.statRows[1].label.width < view.statRows[1].count.point[4],
    "adding percentage text must not overlap the category name")
assert(view.directoryCount:GetText():find("characters", 1, true) and not view.directoryCount:GetText():find("members", 1, true))
for index = 1, 53 do roster[#roster + 1] = { name = "Roster Person " .. index .. "-Realm", className = "Mage" } end
view.Refresh()
assert(not view.rows[2].discordIcon.shown and not view.rows[2].mainIcon.shown,
    "a row reused for an unconfigured character must hide the nickname and main icons")
assert(not view.nextPage and not view.previous and view.content.height == #roster * 39,
    "member pagination controls must be replaced by a virtual scrolling extent")
local firstMember = view.rows[1].member
local savedRows, savedStats, savedCreateFrame = addon.Members.Rows, addon.Members.Stats, CreateFrame
addon.Members.Rows = function() error("scrolling must not rebuild the roster") end
addon.Members.Stats = function() error("scrolling must not rebuild statistics") end
CreateFrame = function() error("scrolling must reuse pooled rows") end
view.scroll.scripts.OnMouseWheel(view.scroll, -1)
assert(view.scrollOffset == 3 * 39 and view.rows[1].member ~= firstMember)
view.rows[1].scripts.OnMouseWheel(view.rows[1], -1)
assert(view.scrollOffset == 6 * 39, "the mouse wheel must work over member rows")
view.scroll.ScrollBar:SetValue(20)
assert(view.scrollOffset == 20 and view.rows[7].shown and view.rows[1].point[5] == 0
    and view.visibleRange:GetText():find("1-7 /", 1, true),
    "scrollbar input must render a partial-row buffer and accurate visible range")
view.ScrollTo(-100)
assert(view.scrollOffset == 0, "scrolling must clamp at the first character")
addon.Members.Rows, addon.Members.Stats, CreateFrame = savedRows, savedStats, savedCreateFrame
view.ScrollTo(100000)
assert(view.scrollOffset == (#roster - 6) * 39 and view.rows[6].shown and not view.rows[7].shown,
    "scrolling must clamp at the final six characters without allocating extra rows")
local oldOffset = view.scrollOffset
view.Refresh()
assert(view.scrollOffset == oldOffset, "roster refreshes must preserve the current scroll offset when possible")
local oldRoster = roster
roster = { oldRoster[1], oldRoster[2], oldRoster[3] }
view.Refresh()
assert(view.scrollOffset == 0 and not view.rows[4].shown,
    "shrinking the roster must clamp scrolling and hide recycled rows")
roster = oldRoster
view.Refresh()
view.filter:SetText("Unknown Person")
view.filter.scripts.OnTextChanged()
assert(view.scrollOffset == 0 and view.rows[1].member.name == "Unknown Person-Realm" and not view.rows[2].shown)
view.rows[1].scripts.OnEnter(view.rows[1])
assert(GameTooltip:GetText() == "Unknown Person")
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
view.ScrollTo(5 * 39)
view.sortHeaders.name.scripts.OnClick()
assert(view.scrollOffset == 0 and view.sortKey == "name" and view.sortAscending
    and view.rows[1].member.name == "Main Person-Realm", "sorting a heading must reset scrolling and sort all filtered characters")
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
print("PASS: Guild view pooled scrolling, profile drafts/save, statistics, search/sort, and roster availability")

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

do
    local active, clock = nil, 5000
    local guildRows = {
        { name = "Main Person-Realm", className = "Shaman", online = true },
        { name = "Peer Person-Realm", className = "Mage", online = true },
        { name = "Arrival Person-Realm", className = "Warrior", online = true },
        { name = "Alt Person-Realm", className = "Paladin", online = true },
    }
    GetTime = function() return clock end
    time = function() return 1000 + clock end
    IsInGuild = function() return true end
    C_Timer = { After = function(_, callback) active.timers[#active.timers + 1] = callback end }
    C_ChatInfo.SendAddonMessage = function(prefix, message, channel)
        assert(channel == "GUILD" and #message <= 220)
        active.sent[#active.sent + 1] = { prefix = prefix, message = message }
        return 0
    end
    local function Copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, item in pairs(value) do result[key] = Copy(item) end
        return result
    end
    local function Client(name, saved)
        local client = { name = name, timers = {}, sent = {}, spec = "Enhancement", logs = {} }
        active = client
        local instance = { db = saved or {} }
        client.addon = instance
        assert(loadfile("HordeEternal/Compat.lua"))("HordeEternal", instance)
        instance.Compat.IsPlayerName = function(candidate) return candidate == active.name end
        instance.Compat.PlayerGuildFacts = function() return "Orc", active.spec, active.spec .. ": 31" end
        instance.LogEvent = function(code, fields) client.logs[#client.logs + 1] = { code = code, fields = fields } end
        instance.GuildState = {
            key = "Guild@Realm", serial = 1, ready = true, IsReady = function() return true end,
            Generation = function() return 1 end,
            Rows = function() return guildRows end,
            Resolve = function(candidate)
                for _, member in ipairs(guildRows) do if member.name == candidate then return candidate end end
            end,
        }
        instance.Catalog = { Initialize = function() return { shareEnabled = false } end }
        assert(loadfile("HordeEternal/Members.lua"))("HordeEternal", instance)
        assert(loadfile("HordeEternal/Sync.lua"))("HordeEternal", instance)
        instance.Sync.Start(false)
        instance.Members.Start()
        return client
    end
    local function Flush(client)
        active = client
        local steps = 0
        while #client.timers > 0 do
            table.remove(client.timers, 1)()
            steps = steps + 1
            assert(steps < 500, "member catch-up must remain bounded")
        end
    end
    local function Deliver(sender, receiver, kind, start, corrupt)
        active = receiver
        local delivered = 0
        for index = start or 1, #sender.sent do
            local packet = sender.sent[index]
            if packet.prefix == "HEGM1" and packet.message:sub(1, #kind) == kind then
                local message = packet.message
                if corrupt then message = message:sub(1, -2) .. "X" end
                receiver.addon.Sync.Receive(packet.prefix, message, "GUILD", sender.name)
                delivered = delivered + 1
            end
        end
        return delivered
    end
    local function Recover(holder, receiver, corrupt)
        clock = clock + 11
        active = holder
        local cached = holder.addon.db.memberGuilds["Guild@Realm"]
        local selfReport = cached.profiles[holder.name]
        assert(selfReport and selfReport.factsRevision and cached.groups[selfReport.id],
            "holder must retain a versioned self report before inventory")
        assert(holder.addon.Compat.Fingerprint("test"), "shared checksum helper must be available")
        local inventoryStart, requestStart, replyStart = #holder.sent + 1, #receiver.sent + 1, #holder.sent + 1
        assert(holder.addon.Members.Reconcile())
        Flush(holder)
        assert(Deliver(holder, receiver, "2|I|", inventoryStart) > 0,
            "missing member inventory from " .. holder.name .. " at " .. clock .. ": " .. holder.addon.Members.status
                .. "; sent=" .. (#holder.sent - inventoryStart + 1)
                .. "; sync=" .. holder.addon.Sync.status)
        Flush(receiver)
        Deliver(receiver, holder, "2|W|", requestStart)
        Flush(holder)
        return Deliver(holder, receiver, "2|R|", replyStart, corrupt)
    end
    local owner = Client("Main Person-Realm")
    assert(owner.addon.Members.Save(true, "Original Nick"))
    Flush(owner)
    local peer = Client("Peer Person-Realm")
    assert(peer.addon.Members.Save(true, "Peer Nick"))
    Flush(peer)
    Deliver(owner, peer, "1|P|")
    active = peer
    assert(not peer.addon.db.memberGuilds["Guild@Realm"].profiles[owner.name].factsRevision,
        "legacy owner broadcasts must not invent a relay revision")
    assert(Recover(owner, peer) > 0, "the owner inventory must upgrade the peer to a versioned report")
    local alt = Client("Alt Person-Realm", Copy(owner.addon.db))
    Flush(alt)
    assert(Recover(alt, peer) > 0, "a peer must retain the original alt's shared account link")
    local original = Copy(peer.addon.db.memberGuilds["Guild@Realm"].profiles[owner.name])
    local originalGroup = Copy(peer.addon.db.memberGuilds["Guild@Realm"].groups[original.id])
    guildRows[1].online = false
    guildRows[4].online = false
    local reloadedPeer = Client(peer.name, Copy(peer.addon.db))
    Flush(reloadedPeer)
    local arrival = Client("Arrival Person-Realm")
    Flush(arrival)
    local inventoryStart = #reloadedPeer.sent + 1
    Deliver(arrival, reloadedPeer, "1|Q|")
    Flush(reloadedPeer)
    clock = clock + 4
    active = reloadedPeer
    reloadedPeer.addon.Members.Maintain()
    Flush(reloadedPeer)
    local requestStart, replyStart = #arrival.sent + 1, #reloadedPeer.sent + 1
    assert(Deliver(reloadedPeer, arrival, "2|I|", inventoryStart) > 0,
        "a login greeting must announce cached offline member reports")
    Flush(arrival)
    Deliver(arrival, reloadedPeer, "2|W|", requestStart)
    Flush(reloadedPeer)
    assert(Deliver(reloadedPeer, arrival, "2|R|", replyStart) > 0)
    active = arrival
    assert(not arrival.addon.Members.CanView(), "peer reports must not bypass local profile setup")
    assert(arrival.addon.Members.Save(true, "Arrival Nick"))
    local data = arrival.addon.db.memberGuilds["Guild@Realm"]
    assert(data.profiles[owner.name].factsRevision == original.factsRevision
        and data.profiles[owner.name].updatedAt == original.updatedAt,
        "relays must preserve the original character report revision and timestamp")
    local display = arrival.addon.Members.Rows()[1]
    assert(display.name == owner.name and display.main == owner.name and display.discord == "Original Nick"
        and display.race == "Orc" and display.spec == "Enhancement" and display.talents == "Enhancement: 31"
        and display.online == false, "all requested fields must appear under the offline original character")
    local altDisplay = arrival.addon.Members.Rows()[4]
    assert(altDisplay.name == alt.name and altDisplay.state == "Alt" and altDisplay.main == owner.name
        and altDisplay.discord == "Original Nick" and altDisplay.online == false,
        "an offline alt must retain its original main link and account nickname through a relay")
    active = owner
    assert(owner.addon.Members.Save(true, "Updated Nick"))
    Flush(owner)
    assert(Recover(owner, arrival) > 0)
    assert(data.groups[original.id].discord == "Updated Nick")
    local newerGroup = Copy(data.groups[original.id])
    active = owner
    owner.spec = "Restoration"
    owner.addon.Members.Capture()
    local newerFacts = Copy(owner.addon.db.memberGuilds["Guild@Realm"].profiles[owner.name])
    local peerData = reloadedPeer.addon.db.memberGuilds["Guild@Realm"]
    peerData.profiles[owner.name], peerData.groups[original.id] = Copy(newerFacts), Copy(originalGroup)
    assert(Recover(reloadedPeer, arrival, true) > 0)
    assert(data.profiles[owner.name].factsRevision == original.factsRevision,
        "corrupted replies must preserve the previous report")
    local retryStart, retryReply = #arrival.sent + 1, #reloadedPeer.sent + 1
    clock = clock + 181
    active = arrival
    arrival.addon.Members.Maintain()
    Flush(arrival)
    assert(Deliver(arrival, reloadedPeer, "2|W|", retryStart) > 0, "a corrupted reply must be retried")
    Flush(reloadedPeer)
    Deliver(reloadedPeer, arrival, "2|R|", retryReply)
    assert(data.profiles[owner.name].spec == "Restoration"
        and data.groups[original.id].discord == newerGroup.discord,
        "newer character facts must combine with newer account settings without rolling either back")
    peerData.profiles[owner.name], peerData.groups[original.id] = Copy(original), Copy(originalGroup)
    assert(Recover(reloadedPeer, arrival) == 0, "stale member inventories must not request older reports")
    peerData.profiles[owner.name], peerData.groups[original.id] = Copy(newerFacts), Copy(newerGroup)
    peerData.profiles[owner.name].race = "Troll"
    assert(Recover(reloadedPeer, arrival) == 0, "same-version differing reports must be treated as conflicts")
    assert(data.profiles[owner.name].race == "Orc")
    local conflictLogged = false
    for _, event in ipairs(arrival.logs) do
        if event.code == "MEMBER_PROFILE_REJECTED" and event.fields.reason == "conflict" then conflictLogged = true end
    end
    assert(conflictLogged, "member conflicts must be logged without including private fields")
    active = owner
    assert(owner.addon.Members.Save(false, ""))
    Flush(owner)
    assert(Recover(owner, arrival) > 0)
    assert(data.groups[original.id].main == "" and data.groups[original.id].discord == "",
        "a newer declaration must propagate explicit main and nickname clearing")
    peerData.profiles[owner.name], peerData.groups[original.id] = Copy(newerFacts), Copy(newerGroup)
    assert(Recover(reloadedPeer, arrival) == 0 and data.groups[original.id].discord == "",
        "older peer copies must not resurrect cleared account settings")
    peerData.profiles[owner.name], peerData.groups[original.id] = Copy(newerFacts), Copy(newerGroup)
    peerData.profiles[owner.name].factsRevision = newerFacts.factsRevision + 1
    clock = clock + 11
    active = reloadedPeer
    inventoryStart = #reloadedPeer.sent + 1
    reloadedPeer.addon.Members.Reconcile()
    Flush(reloadedPeer)
    Deliver(reloadedPeer, arrival, "2|I|", inventoryStart)
    active = arrival
    arrival.addon.GuildState.key = "Another Guild@Realm"
    arrival.addon.Members.Invalidate()
    local sentBefore = #arrival.sent
    Flush(arrival)
    assert(#arrival.sent == sentBefore, "queued member requests must not cross guild contexts")
    local large = Client("Peer Person-Realm")
    assert(large.addon.Members.Save(true, "Large Guild"))
    Flush(large)
    local largeData = large.addon.db.memberGuilds["Guild@Realm"]
    largeData.groups[original.id] = Copy(originalGroup)
    for index = 1, 20 do
        local name = "Cached Alt " .. index .. "-Realm"
        guildRows[#guildRows + 1] = { name = name, className = "Mage", online = false }
        largeData.profiles[name] = Copy(original)
    end
    active = large
    local originalChecksum, checksums = large.addon.Compat.Fingerprint, 0
    large.addon.Compat.Fingerprint = function(payload) checksums = checksums + 1; return originalChecksum(payload) end
    local batchStart = #large.sent + 1
    assert(large.addon.Members.Reconcile())
    while #large.timers > 0 do
        local before = checksums
        table.remove(large.timers, 1)()
        assert(checksums - before <= 1, "each inventory callback must serialize at most one member report")
    end
    local inventoryPackets = 0
    for index = batchStart, #large.sent do
        if large.sent[index].message:sub(1, 4) == "2|I|" then inventoryPackets = inventoryPackets + 1 end
    end
    assert(inventoryPackets == 8 and checksums == 8, "member inventories must use batches of at most eight records")
    clock = clock + 16
    large.addon.Members.Maintain()
    Flush(large)
    assert(checksums == 16, "later batches must continue the cache rather than repeating the first records")
    print("PASS: automatic offline member relay after reload, setup lock, report versions, independent settings/facts merge, checksum retry, stale/conflict rejection, and guild isolation")
end