local _, addon = ...
local Map = {}
addon.GuildMap = Map
local MAP_WIDTH, MAP_HEIGHT, LOCATION_PAGE_SIZE = 684, 372, 3

local function Allowed()
    if addon.GuildState and addon.GuildState.IsAllowed and not addon.GuildState.IsAllowed() then return false end
    return addon.Members and type(addon.Members.CanView) == "function" and addon.Members.CanView()
        and addon.GuildState and addon.GuildState.IsReady()
end

function Map.Index()
    local root = addon.Compat.MapInfo(947)
    if not root then
        local mapID = addon.Compat.Value(C_Map and C_Map.GetBestMapForUnit, "player")
        local visited = {}
        for _ = 1, 12 do
            local info = addon.Compat.MapInfo(mapID)
            if not info or visited[info.mapID] then break end
            root, visited[info.mapID] = info, true
            if info.parentMapID == 0 then break end
            mapID = info.parentMapID
        end
    end
    if not root then return nil end
    local index = { root = root.mapID, names = {}, maps = { [root.mapID] = root } }
    local queue, visited, count = { root.mapID }, {}, 1
    local cursor = 1
    while cursor <= #queue do
        local id = queue[cursor]
        cursor = cursor + 1
        if not visited[id] then
            visited[id] = true
            local children = addon.Compat.MapChildren(id)
            if not children then return nil end
            for _, info in ipairs(children) do
                if not index.maps[info.mapID] then
                    count = count + 1
                    if count > 2048 then return nil end
                    index.maps[info.mapID] = info
                    queue[#queue + 1] = info.mapID
                    local previous = index.names[info.name]
                    if previous == nil then index.names[info.name] = info.mapID
                    elseif previous ~= info.mapID then index.names[info.name] = false end
                end
            end
        end
    end
    return index
end

local function MapScope(info, mapID, index)
    local seen = {}
    for _ = 1, 12 do
        if not info or seen[info.mapID] then break end
        if info.mapID == mapID then return true, false end
        if info.parentMapID == 0 then return false, info.mapID ~= index.root end
        seen[info.mapID] = true
        info = index.maps[info.parentMapID] or addon.Compat.MapInfo(info.parentMapID)
    end
    return false, true
end

function Map.Markers(summary, mapID, index)
    local markers, byID, unplaced = {}, {}, {}
    local shown = index and index.maps[mapID]
    if not shown then return markers, summary.zones end
    for _, zone in ipairs(summary.zones) do
        local id = index.names[zone.name]
        if type(id) == "number" then
            local info = index.maps[id]
            local inScope, detached = MapScope(info, mapID, index)
            local seen = {}
            if inScope and (shown.mapType <= 1 or mapID == index.root) then
                for _ = 1, 12 do
                    if not info or seen[info.mapID] or info.mapType <= 2 then break end
                    seen[info.mapID] = true
                    info = index.maps[info.parentMapID] or addon.Compat.MapInfo(info.parentMapID)
                end
            end
            if inScope or detached then
                local position = inScope and info and addon.Compat.MapRect(info.mapID, mapID)
                if position then
                    local marker = byID[info.mapID]
                    if not marker then
                        marker = { mapID = info.mapID, name = info.name, x = position.x, y = position.y, count = 0, characters = {} }
                        byID[info.mapID] = marker
                        markers[#markers + 1] = marker
                    end
                    marker.count = marker.count + zone.count
                    for _, character in ipairs(zone.characters) do marker.characters[#marker.characters + 1] = character end
                else
                    unplaced[#unplaced + 1] = {
                        mapID = id, name = zone.name, count = zone.count,
                        characters = zone.characters, unplaced = true,
                    }
                end
            end
        else
            unplaced[#unplaced + 1] = zone
        end
    end
    table.sort(markers, function(left, right) return left.name:lower() < right.name:lower() end)
    return markers, unplaced
end

function Map.Summary()
    local summary = { zones = {}, online = 0, located = 0, unknown = 0 }
    if not Allowed() then return summary end
    local byZone = {}
    for _, character in ipairs(addon.GuildState.Rows()) do
        if character.online == true then
            summary.online = summary.online + 1
            if character.zone then
                local zone = byZone[character.zone]
                if not zone then
                    zone = { name = character.zone, count = 0, characters = {} }
                    byZone[character.zone] = zone
                    summary.zones[#summary.zones + 1] = zone
                end
                zone.count = zone.count + 1
                zone.characters[#zone.characters + 1] = character
                summary.located = summary.located + 1
            else summary.unknown = summary.unknown + 1 end
        end
    end
    table.sort(summary.zones, function(left, right)
        if left.count ~= right.count then return left.count > right.count end
        return left.name:lower() < right.name:lower()
    end)
    return summary
end

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function ShowTooltip(owner, location)
    if not GameTooltip or not location then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(location.name)
    GameTooltip:AddLine(location.count .. " guild characters", 1, 0.82, 0)
    local names = {}
    for _, character in ipairs(location.characters) do
        local zone = character.zone
        names[#names + 1] = addon.Compat.CharacterLabel(character.name)
            .. (type(zone) == "string" and zone ~= location.name and (" - " .. zone) or "")
    end
    table.sort(names)
    for index = 1, math.min(12, #names) do GameTooltip:AddLine(names[index], 1, 1, 1, true) end
    if #names > 12 then GameTooltip:AddLine("+" .. (#names - 12) .. " more characters", 0.7, 0.7, 0.7) end
    GameTooltip:Show()
end

local function Label(parent, text, x, y, width, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(text)
    return label
end

local function Tool(parent, texture, title)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(26, 26)
    button:SetNormalTexture(texture)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    button:SetScript("OnEnter", function(self)
        if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(title); GameTooltip:Show() end
    end)
    button:SetScript("OnLeave", HideTooltip)
    return button
end

local function DrawPins(parent, pool, markers, width, height, scale, navigate, goParent)
    for _, pin in ipairs(pool) do pin:Hide(); pin.location = nil end
    for index = 1, math.min(100, #markers) do
        local location = markers[index]
        local pin = pool[index]
        if not pin then
            pin = CreateFrame("Button", nil, parent)
            pin:SetSize(30, 30)
            pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local rim = pin:CreateTexture(nil, "BACKGROUND")
            rim:SetAllPoints(pin)
            rim:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
            rim:SetVertexColor(0.92, 0.74, 0.3, 1)
            local fill = pin:CreateTexture(nil, "ARTWORK")
            fill:SetSize(25, 25)
            fill:SetPoint("CENTER", pin, "CENTER", 0, 0)
            fill:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
            fill:SetVertexColor(0.12, 0.1, 0.07, 1)
            pin.text = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            pin.text:SetPoint("CENTER", pin, "CENTER", 0, 0)
            pin:SetScript("OnEnter", function(self) ShowTooltip(self, self.location) end)
            pin:SetScript("OnLeave", HideTooltip)
            pin:SetScript("OnClick", function(self, mouseButton)
                if not addon.Compat.IsReadable(mouseButton) then return end
                if mouseButton == "RightButton" then goParent()
                elseif (mouseButton == nil or mouseButton == "LeftButton") and self.location then navigate(self.location.mapID) end
            end)
            pool[index] = pin
        end
        pin.location = location
        local level = addon.Compat.Value(parent.GetFrameLevel, parent)
        if type(level) == "number" then addon.Compat.Call(pin.SetFrameLevel, pin, level + 100) end
        pin:SetScale(1 / scale)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", parent, "TOPLEFT", location.x * width * scale, -location.y * height * scale)
        pin.text:SetText(tostring(location.count))
        pin:Show()
    end
end

local lastRosterRequest

function Map.Hide()
    if Map.view then
        for _, pin in ipairs(Map.view.pins) do pin:Hide(); pin.location = nil end
    end
    Map.index = nil
    HideTooltip()
end

function Map.SetEnabled(enabled)
    if type(enabled) ~= "boolean" or not addon.db then return end
    addon.db.showGuildMap = enabled
    if Map.view then
        Map.view.enabled:SetChecked(enabled)
        if Map.view.visible then Map.view.Refresh() end
    end
end

function Map.RequestRoster()
    if not Allowed() then return end
    local now = addon.Compat.Value(GetTime)
    if type(now) ~= "number" or (lastRosterRequest and now - lastRosterRequest < 10) then return end
    lastRosterRequest = now
    addon.Compat.Call(C_GuildInfo and C_GuildInfo.GuildRoster)
end

function Map.Refresh()
    if Map.view and Map.view.visible then Map.view.Refresh() end
end

function Map.Start()
    if Map.listener then return end
    local listener = CreateFrame("Frame")
    Map.listener = listener
    for _, event in ipairs({ "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "ADDON_LOADED", "ZONE_CHANGED_NEW_AREA" }) do
        addon.Compat.Call(listener.RegisterEvent, listener, event)
    end
    listener:SetScript("OnEvent", function(_, event)
        if addon.Compat.IsReadable(event) and event == "ZONE_CHANGED_NEW_AREA" then Map.RequestRoster() end
        Map.Refresh()
    end)
end

function addon.CreateGuildMapView(page, header, subheader)
    local view = { pins = {}, tiles = {}, zoneRows = {}, listPage = 1, visible = false }
    Map.view = view
    local back = Tool(page, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", "Parent map")
    back:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -3)
    local world = Tool(page, "Interface\\Icons\\INV_Misc_Map_01", "World overview")
    world:SetPoint("LEFT", back, "RIGHT", 5, 0)
    local here = Tool(page, "Interface\\Minimap\\MinimapArrow", "Your current zone")
    here:SetPoint("LEFT", world, "RIGHT", 5, 0)
    local title = Label(page, "Guild map", 112, -10, 372, "GameFontNormal")
    local refresh = Tool(page, "Interface\\Buttons\\UI-RefreshButton", "Refresh guild roster and map")
    refresh:SetPoint("TOPRIGHT", page, "TOPRIGHT", -10, -3)
    local native = Tool(page, "Interface\\WorldMap\\WorldMap-Icon", "Open the world map")
    native:SetPoint("RIGHT", refresh, "LEFT", -5, 0)
    local viewport = CreateFrame("Frame", nil, page)
    viewport:SetSize(MAP_WIDTH, MAP_HEIGHT)
    viewport:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -36)
    local background = viewport:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(viewport)
    background:SetColorTexture(0.035, 0.035, 0.03, 1)
    local canvas = CreateFrame("Frame", nil, viewport)
    canvas:SetPoint("CENTER", viewport, "CENTER", 0, 0)
    local unavailable = Label(viewport, "", 28, -170, MAP_WIDTH - 56)
    unavailable:SetJustifyH("CENTER")
    unavailable:SetWordWrap(true)
    local caption = Label(page, "", 12, -420, 498)
    caption:SetTextColor(0.7, 0.7, 0.66)
    local enabled = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    enabled:SetSize(24, 24)
    enabled:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 8, 7)
    Label(enabled, "Guild markers", 28, -6, 200)
    enabled:SetScript("OnClick", function()
        Map.SetEnabled(enabled:GetChecked() == true)
        view.Refresh()
    end)
    local listStatus = Label(page, "", 516, -420, 172)
    listStatus:SetJustifyH("RIGHT")
    for rowIndex = 1, LOCATION_PAGE_SIZE do
        local row = CreateFrame("Button", nil, page)
        row:SetSize(222, 44)
        row:SetPoint("TOPLEFT", page, "TOPLEFT", 8 + (rowIndex - 1) * 230, -446)
        local band = row:CreateTexture(nil, "BACKGROUND")
        band:SetAllPoints(row)
        band:SetColorTexture(0, 0, 0, 0.28)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.name = Label(row, "", 9, -7, 172, "GameFontNormalSmall")
        row.count = Label(row, "", 184, -7, 30, "GameFontNormalSmall")
        row.count:SetJustifyH("RIGHT")
        row.state = Label(row, "", 9, -25, 202)
        row.state:SetTextColor(0.65, 0.65, 0.61)
        row:SetScript("OnEnter", function(self) ShowTooltip(self, self.location) end)
        row:SetScript("OnLeave", HideTooltip)
        row:SetScript("OnClick", function(self)
            if self.mapID then view.mapID = self.mapID; view.Refresh() end
        end)
        view.zoneRows[rowIndex] = row
    end
    local previous = Tool(page, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", "Previous zones")
    previous:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -114, 8)
    local nextPage = Tool(page, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", "Next zones")
    nextPage:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -14, 8)
    local pagination = Label(page, "", 0, 0, 70)
    pagination:ClearAllPoints()
    pagination:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -46, 15)
    pagination:SetJustifyH("CENTER")
    previous:SetScript("OnClick", function() view.listPage = view.listPage - 1; view.Refresh() end)
    nextPage:SetScript("OnClick", function() view.listPage = view.listPage + 1; view.Refresh() end)

    local function Navigate(mapID)
        view.mapID = mapID
        view.Refresh()
    end
    local function GoParent()
        if not Allowed() then return end
        local info = addon.Compat.MapInfo(view.mapID)
        if info and info.parentMapID > 0 then Navigate(info.parentMapID) end
    end
    local function MapMouseUp(_, mouseButton)
        if addon.Compat.IsReadable(mouseButton) and mouseButton == "RightButton" then GoParent() end
    end
    back:SetScript("OnClick", GoParent)
    viewport:EnableMouse(true)
    viewport:SetScript("OnMouseUp", MapMouseUp)
    canvas:EnableMouse(true)
    canvas:SetScript("OnMouseUp", MapMouseUp)
    world:SetScript("OnClick", function() Navigate(Map.index and Map.index.root) end)
    here:SetScript("OnClick", function()
        local id = addon.Compat.Value(C_Map and C_Map.GetBestMapForUnit, "player")
        if type(id) == "number" then Navigate(id) end
    end)
    native:SetScript("OnClick", function() addon.Compat.Call(C_Map and C_Map.OpenWorldMap, view.mapID) end)
    refresh:SetScript("OnClick", function()
        Map.index = nil
        Map.RequestRoster()
        addon.GuildState.RefreshRoster()
        view.Refresh()
    end)

    function view.Refresh()
        for _, tile in ipairs(view.tiles) do tile:Hide() end
        for _, pin in ipairs(view.pins) do pin:Hide(); pin.location = nil end
        for _, row in ipairs(view.zoneRows) do row:Hide(); row.location = nil; row.mapID = nil end
        enabled:SetChecked(addon.db.showGuildMap ~= false)
        if not Allowed() then
            HideTooltip()
            canvas:Hide()
            unavailable:SetText("Complete guild profile and readable roster required")
            unavailable:Show()
            caption:SetText("")
            listStatus:SetText("")
            pagination:SetText("")
            back:SetEnabled(false)
            previous:SetEnabled(false)
            nextPage:SetEnabled(false)
            if addon.db.canvasTab == "map" then
                header:SetText("Guild map")
                subheader:SetText("Complete guild profile and readable roster required")
            end
            return
        end
        local index = Map.index or Map.Index()
        Map.index = index
        local summary = Map.Summary()
        view.mapID = view.mapID or index and index.root
        local info = addon.Compat.MapInfo(view.mapID)
        if info and index then index.maps[info.mapID] = info end
        title:SetText(info and info.name or "Guild map unavailable")
        back:SetEnabled(info ~= nil and info.parentMapID > 0)
        local art = info and addon.Compat.MapArt(view.mapID)
        local markers, unplaced = {}, summary.zones
        if info and index then markers, unplaced = Map.Markers(summary, view.mapID, index) end
        if art and index then
            local scale = math.min(MAP_WIDTH / art.width, MAP_HEIGHT / art.height)
            local width, height = art.width * scale, art.height * scale
            canvas:SetSize(width, height)
            canvas:Show()
            unavailable:Hide()
            for tileIndex, data in ipairs(art.tiles) do
                local tile = view.tiles[tileIndex]
                if not tile then tile = canvas:CreateTexture(nil, "BACKGROUND"); view.tiles[tileIndex] = tile end
                tile:ClearAllPoints()
                tile:SetPoint("TOPLEFT", canvas, "TOPLEFT", data.x * width, -data.y * height)
                tile:SetSize(data.width * width, data.height * height)
                tile:SetTexCoord(0, data.u, 0, data.v)
                tile:SetTexture(data.fileID)
                tile:Show()
            end
            if addon.db.showGuildMap ~= false then DrawPins(canvas, view.pins, markers, width, height, 1, Navigate, GoParent) end
        else
            canvas:Hide()
            unavailable:SetText("Map artwork or readable map data unavailable")
            unavailable:Show()
        end
        local unplotted = 0
        for _, zone in ipairs(unplaced) do unplotted = unplotted + zone.count end
        caption:SetText(summary.online .. " online / " .. summary.located .. " located / " .. summary.unknown .. " unknown"
            .. (unplotted > 0 and (" / " .. unplotted .. " unplotted") or ""))
        local locations = {}
        for _, marker in ipairs(markers) do locations[#locations + 1] = marker end
        for _, zone in ipairs(unplaced) do locations[#locations + 1] = zone end
        table.sort(locations, function(left, right)
            if left.count ~= right.count then return left.count > right.count end
            return left.name:lower() < right.name:lower()
        end)
        listStatus:SetText(#locations .. " locations")
        local pages = math.max(1, math.ceil(#locations / LOCATION_PAGE_SIZE))
        view.listPage = math.max(1, math.min(pages, view.listPage))
        for rowIndex, row in ipairs(view.zoneRows) do
            local zone = locations[(view.listPage - 1) * LOCATION_PAGE_SIZE + rowIndex]
            if zone then
                local id = zone.mapID or index and index.names[zone.name]
                row.mapID = type(id) == "number" and id or nil
                row.location = zone
                row.name:SetText(zone.name)
                row.count:SetText(tostring(zone.count))
                local detail = row.mapID and addon.Compat.MapInfo(row.mapID)
                row.state:SetText(not zone.unplaced and detail and (detail.mapType == 2 and "Continent" or "Zone")
                    or "Map position unavailable")
                row:Show()
            end
        end
        pagination:SetText(view.listPage .. " / " .. pages)
        previous:SetEnabled(view.listPage > 1)
        nextPage:SetEnabled(view.listPage < pages)
        if addon.db.canvasTab == "map" then
            header:SetText("Guild map")
            subheader:SetText(summary.online .. " online characters / " .. summary.located .. " located / roster snapshot")
        end
    end
    page:SetScript("OnShow", function() view.visible = true; Map.RequestRoster(); view.Refresh() end)
    page:SetScript("OnHide", function() view.visible = false; HideTooltip() end)
    view.back, view.world, view.here, view.refresh, view.native = back, world, here, refresh, native
    view.enabled, view.nextPage, view.previous, view.unavailable = enabled, nextPage, previous, unavailable
    view.canvas, view.caption = canvas, caption
    view.viewport = viewport
    view.Refresh()
    return view
end