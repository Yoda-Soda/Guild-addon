local addon = {}
assert(loadfile("HordeEternal/Compat.lua"))("HordeEternal", addon)
assert(loadfile("HordeEternal/GuildMap.lua"))("HordeEternal", addon)
local ready, configured = true, true
local characters = {
    { name = "First Character-BetaClassicBetaPvP2", zone = "Orgrimmar", online = true },
    { name = "Second Character", zone = "Orgrimmar", online = true },
    { name = "Third Character", zone = "The Barrens", online = true },
    { name = "Offline Character", zone = "The Barrens", online = false },
    { name = "Unknown Presence", zone = "The Barrens" },
    { name = "No Location", online = true },
}
addon.GuildState = { IsReady = function() return ready end, Rows = function() return characters end }
addon.Members = { CanView = function() return configured end }
local summary = addon.GuildMap.Summary()
assert(summary.online == 4 and summary.located == 3 and summary.unknown == 1)
assert(#summary.zones == 2 and summary.zones[1].name == "Orgrimmar" and summary.zones[1].count == 2)
assert(#summary.zones[1].characters == 2 and summary.zones[2].count == 1,
    "map counts must represent only this guild's online characters with known roster locations")
configured = false
assert(#addon.GuildMap.Summary().zones == 0, "map data must respect required profile setup")
configured, ready = true, false
assert(addon.GuildMap.Summary().online == 0, "unreadable rosters must not display stale locations")
print("PASS: single-guild zone counts, online/unknown distinctions, and setup/roster location gates")

ready = true
local maps = {
    [947] = { mapID = 947, name = "Azeroth", parentMapID = 0, mapType = 1 },
    [12] = { mapID = 12, name = "Kalimdor", parentMapID = 947, mapType = 2 },
    [85] = { mapID = 85, name = "Orgrimmar", parentMapID = 12, mapType = 3 },
    [10] = { mapID = 10, name = "The Barrens", parentMapID = 12, mapType = 3 },
}
local rectangles = { ["12:947"] = { 0.1, 0.5, 0.2, 0.8 }, ["85:12"] = { 0.6, 0.8, 0.1, 0.3 }, ["10:12"] = { 0.3, 0.5, 0.4, 0.8 } }
C_Map = {
    GetMapInfo = function(id) return maps[id] end,
    GetMapChildrenInfo = function(id, kind, recursive)
        assert(kind == nil and recursive == false)
        if id == 947 then return { maps[12] } end
        if id == 12 then return { maps[85], maps[10] } end
        return {}
    end,
    GetMapRectOnMap = function(id, parent)
        local bounds = rectangles[id .. ":" .. parent]
        if bounds then return unpack(bounds) end
    end,
    GetMapArtLayers = function() return { { layerWidth = 1000, layerHeight = 700, tileWidth = 512, tileHeight = 512 } } end,
    GetMapArtLayerTextures = function(_, layer) assert(layer == 1); return { 101, 102, 103, 104 } end,
}
local index = addon.GuildMap.Index()
assert(index and index.names.Orgrimmar == 85)
local markers = addon.GuildMap.Markers(summary, 947, index)
assert(#markers == 1 and markers[1].mapID == 12 and markers[1].count == 3
    and markers[1].x == 0.3 and markers[1].y == 0.5, "world view must aggregate counts by continent")
markers = addon.GuildMap.Markers(summary, 12, index)
assert(#markers == 2 and markers[1].count == 2 and markers[1].x == 0.7)
assert(addon.GuildMap.Markers(summary, 85, index)[1].count == 2)
rectangles["12:947"] = { -0.1, 0.7, 0.2, 0.8 }
assert(#addon.GuildMap.Markers(summary, 947, index) == 1,
    "a continent extending beyond the map edge must remain visible when its center is on the world map")
maps[13] = { mapID = 13, name = "Eastern Kingdoms", parentMapID = 947, mapType = 2 }
maps[90] = { mapID = 90, name = "Undercity", parentMapID = 13, mapType = 3 }
rectangles["13:947"] = { 0.6, 1.1, 0.1, 0.9 }
rectangles["90:13"] = { 0.3, 0.5, 0.3, 0.5 }
characters[#characters + 1] = { name = "Eastern Character-BetaClassicBetaPvP2", zone = "Undercity", online = true }
local singleContinentChildren = C_Map.GetMapChildrenInfo
C_Map.GetMapChildrenInfo = function(id, kind, recursive)
    assert(recursive == false)
    if id == 947 then return { maps[12], maps[13] } end
    if id == 13 then return { maps[90] } end
    return singleContinentChildren(id, kind, recursive)
end
local twoContinentMarkers = addon.GuildMap.Markers(addon.GuildMap.Summary(), 947, addon.GuildMap.Index())
assert(#twoContinentMarkers == 2 and twoContinentMarkers[1].count == 1 and twoContinentMarkers[2].count == 3,
    "the two-continent world view must show totals for both continents")
table.remove(characters)
C_Map.GetMapChildrenInfo = singleContinentChildren
rectangles["12:947"] = { 0.1, 0.5, 0.2, 0.8 }
local art = addon.Compat.MapArt(12)
assert(#art.tiles == 4 and art.tiles[2].fileID == 102 and art.tiles[3].fileID == 103
    and art.tiles[4].u == 488 / 512 and art.tiles[4].v == 188 / 512, "map tiles must preserve native order and crop edge tiles")
local secret = {}
canaccessvalue = function(value) return value ~= secret end
rectangles["85:12"][4] = secret
assert(addon.Compat.MapRect(85, 12) == nil, "late restricted map rectangle returns must be guarded")
maps[85].name = secret
assert(addon.GuildMap.Index() == nil, "restricted map metadata must not create a partial authoritative index")
maps[85].name = "Orgrimmar"
C_Map.GetMapArtLayerTextures = function() return { 101, 102, 103, secret } end
assert(addon.Compat.MapArt(12) == nil)
canaccessvalue = nil
local originalChildren = C_Map.GetMapChildrenInfo
C_Map.GetMapChildrenInfo = function(id)
    if id == 947 then return { maps[12] } end
    if id == 12 then return { maps[85], maps[10], { mapID = 999, name = "Orgrimmar", parentMapID = 12, mapType = 3 } } end
    return {}
end
assert(addon.GuildMap.Index().names.Orgrimmar == false, "ambiguous zone names must not be placed by guessing")
C_Map.GetMapChildrenInfo = originalChildren
print("PASS: guarded map metadata/art, tile order/cropping, continent totals, zone projection, and ambiguous location fallback")

rectangles["85:12"] = { 0.6, 0.8, 0.1, 0.3 }
C_Map.GetMapArtLayerTextures = function() return { 101, 102, 103, 104 } end
C_Map.GetBestMapForUnit = function(unit) assert(unit == "player"); return 85 end
local opened
C_Map.OpenWorldMap = function(id) opened = id end
local methods = {}
for _, name in ipairs({ "SetPoint", "SetSize", "SetWidth", "SetHeight", "SetJustifyH", "SetWordWrap", "SetTextColor",
    "SetHighlightTexture", "SetAllPoints", "SetColorTexture", "SetVertexColor", "SetScale", "ClearAllPoints", "ClearFocus" }) do
    methods[name] = function() end
end
methods.EnableMouse = function() end
local function Widget() return setmetatable({ scripts = {}, shown = true }, { __index = methods }) end
function methods:SetScript(event, handler) self.scripts[event] = handler end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:IsShown() return self.shown end
function methods:GetFrameLevel() return 1 end
function methods:SetFrameLevel(level) self.level = level end
function methods:SetScale(scale) self.scale = scale end
function methods:HookScript(event, callback) self.scripts[event] = callback end
function methods:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function methods:SetPoint(...) self.point = { ... } end
function methods:SetText(text) self.text = text end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetTexCoord(...) self.coordinates = { ... } end
function methods:SetNormalTexture(texture) self.texture = texture end
function methods:SetEnabled(enabled) self.enabled = enabled end
function methods:SetChecked(checked) self.checked = checked end
function methods:GetChecked() return self.checked end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:CreateTexture() return Widget() end
function methods:CreateFontString() return Widget() end
function methods:SetOwner(owner) self.owner = owner end
function methods:AddLine(line)
    self.line = line
    self.lines = self.lines or {}
    self.lines[#self.lines + 1] = line
end
local frames = {}
CreateFrame = function(_, _, parent)
    local frame = Widget()
    frame.parent = parent
    frames[#frames + 1] = frame
    return frame
end
GameTooltip = Widget()
addon.db = { canvasTab = "map" }
local header, subheader = Widget(), Widget()
local view = addon.CreateGuildMapView(Widget(), header, subheader)
assert(view.viewport.width == 684 and view.viewport.height == 372 and #view.zoneRows == 3,
    "the map should occupy the main width with a compact location strip instead of a narrow sidebar")
for index, row in ipairs(view.zoneRows) do
    assert(row.point[4] + row.width <= 700 and row.point[5] == -446)
    if index > 1 then
        assert(view.zoneRows[index - 1].point[4] + view.zoneRows[index - 1].width < row.point[4])
    end
end
assert(view.canvas.shown and view.tiles[4].shown and view.tiles[1].texture == 101 and view.pins[1].location.count == 3,
    "the map view must load actual map textures and continent counts")
assert(header.text == "Guild map")
assert(view.zoneRows[1].name.text == "Kalimdor" and view.zoneRows[1].count.text == "3",
    "the top-level location strip must present continent totals")
view.pins[1].scripts.OnEnter(view.pins[1])
assert(GameTooltip.text == "Kalimdor")
assert(table.concat(GameTooltip.lines, "\n"):find("First Character", 1, true)
    and not table.concat(GameTooltip.lines, "\n"):find("BetaClassicBetaPvP2", 1, true),
    "map tooltips must retain character names and surnames but never display realm suffixes")
view.pins[1].scripts.OnClick(view.pins[1])
assert(view.mapID == 12 and #view.pins >= 2 and view.pins[2].shown)
view.zoneRows[1].scripts.OnClick(view.zoneRows[1])
assert(view.mapID == 85 and view.pins[1].location.count == 2)
view.back.scripts.OnClick()
assert(view.mapID == 12)
view.world.scripts.OnClick()
assert(view.mapID == 947)
view.here.scripts.OnClick()
assert(view.mapID == 85)
view.native.scripts.OnClick()
assert(opened == 85, "native map opening must remain an explicit user action")
configured = false
view.Refresh()
assert(not view.canvas.shown and not view.pins[1].shown and view.unavailable.shown)
configured = true
view.Refresh()
assert(view.canvas.shown)
print("PASS: map artwork rendering, count tooltips, continent/zone navigation, native-map action, and profile-lock clearing")

local worldCanvas = Widget()
worldCanvas:SetSize(1000, 700)
WorldMapFrame = Widget()
local shownMap, scale = 947, 1
WorldMapFrame.GetCanvas = function() return worldCanvas end
WorldMapFrame.GetMapID = function() return shownMap end
WorldMapFrame.SetMapID = function(_, id) shownMap = id end
WorldMapFrame.ScrollContainer = Widget()
WorldMapFrame.ScrollContainer.GetCanvasScale = function() return scale end
local hook
hooksecurefunc = function(target, method, callback)
    assert(target == WorldMapFrame and method == "SetMapID")
    hook = callback
end
local now, rosterRequests = 100, 0
GetTime = function() return now end
C_GuildInfo = { GuildRoster = function() rosterRequests = rosterRequests + 1 end }
addon.GuildMap.Start()
assert(hook and WorldMapFrame.scripts.OnShow and addon.GuildMap.listener.events.GUILD_ROSTER_UPDATE)
WorldMapFrame.scripts.OnShow()
addon.GuildMap.RequestRoster()
assert(rosterRequests == 1, "map-opening requests must be coalesced")
local nativePins = {}
for _, frame in ipairs(frames) do if frame.parent == worldCanvas then nativePins[#nativePins + 1] = frame end end
assert(#nativePins == 1 and nativePins[1].shown and nativePins[1].location.count == 3)
assert(nativePins[1].level == 101, "guild counts must sit above native map artwork and overlays")
assert(addon.GuildMap.nativeFilter and addon.GuildMap.nativeFilter.button.shown)
addon.GuildMap.nativeFilter.button.scripts.OnClick()
assert(addon.GuildMap.nativeFilter.panel.shown)
addon.GuildMap.nativeFilter.check:SetChecked(false)
addon.GuildMap.nativeFilter.check.scripts.OnClick(addon.GuildMap.nativeFilter.check)
assert(addon.db.showGuildMap == false and not nativePins[1].shown and not view.enabled:GetChecked(),
    "the native map filter must hide guild markers and synchronize the addon toggle")
addon.GuildMap.nativeFilter.check:SetChecked(true)
addon.GuildMap.nativeFilter.check.scripts.OnClick(addon.GuildMap.nativeFilter.check)
assert(nativePins[1].shown and view.enabled:GetChecked())
view.enabled:SetChecked(false)
view.enabled.scripts.OnClick()
assert(not view.pins[1].shown and not nativePins[1].shown and not addon.GuildMap.nativeFilter.check:GetChecked(),
    "the addon checkbox must synchronize the native filter and hide markers on both maps")
view.enabled:SetChecked(true)
view.enabled.scripts.OnClick()
assert(view.pins[1].shown and nativePins[1].shown and addon.GuildMap.nativeFilter.check:GetChecked())
assert(nativePins[1].point[4] == 300 and nativePins[1].point[5] == -350)
scale = 2
WorldMapFrame.ScrollContainer.scripts.OnUpdate(nil, 0.5)
assert(nativePins[1].scale == 0.5 and nativePins[1].point[4] == 600,
    "world-map zoom must keep count-pin screen size stable")
addon.db.showGuildMap = false
addon.GuildMap.RefreshWorld()
assert(not nativePins[1].shown and nativePins[1].location == nil)
addon.db.showGuildMap = true
shownMap = 12
hook()
assert(nativePins[1].location.count == 2)
configured = false
addon.GuildMap.Refresh()
assert(not nativePins[1].shown and nativePins[1].location == nil,
    "losing profile access must clear native-map locations, not just the addon view")
configured = true
ready = false
addon.GuildMap.RefreshWorld()
assert(not nativePins[1].shown)
ready = true
addon.GuildMap.RefreshWorld()
WorldMapFrame.scripts.OnHide()
assert(not nativePins[1].shown)
now = now + 11
addon.GuildMap.listener.scripts.OnEvent(nil, "ZONE_CHANGED_NEW_AREA")
assert(rosterRequests == 2)
print("PASS: native world-map markers, toggle, scale correction, map switches, profile/roster invalidation, and bounded roster requests")