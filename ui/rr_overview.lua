-- Rescue Rangers - overview menu: every Rescue ship with its state, the statistics
-- md/rr_stats.xml keeps, and the order settings of each Rescue ship. Opened from
-- its own entry in vanilla's top-level icon row, right after the map.

---@diagnostic disable-next-line: unresolved-require
local ffi = require("ffi")
local C   = ffi.C

local PAGE         = 1972092402
local TOP_LEVEL_ID = "rescuerangers"
local ORDER_ID     = "RescueRangers"

-- Order param positions, as declared in aiscripts/order.rescue.rangers.sector.xml.
local P = { homeSector = 1, range = 2, homeStation = 3, dormitory = 4, oxygen = 5, getThemBack = 6, joinCrew = 7, logbook = 8 }

local menu = {
  name            = "RescueRangersOverviewMenu",
  updateInterval  = 0.5,
  lastRefreshTime = 0.0,
}

local config = {
  infoLayer       = 4,
  refreshInterval = 5, -- seconds between rebuilds on the Rescue ships and Statistics tabs
  eventRows       = 60,
  tabInputWidth   = 100, -- empty cells either side of the tab icons, room for the tab name
  mapSelectRetry  = 0.25,
  mapSelectTries  = 8,
}

local TABS = {
  { id = "rangers",  icon = "order_rescuerangers",    name = function() return ReadText(PAGE, 3001) end },
  { id = "stats",    icon = "pi_statistics",          name = function() return ReadText(1001, 2500) end },
  { id = "settings", icon = "mapst_standing_orders",  name = function() return ReadText(1001, 2679) end },
}

-- Statistics counters in display order; the event log texts take the same kinds.
local COUNTERS = {
  { key = "ejected",     textId = 3040 },
  { key = "rescued",     textId = 3041 },
  { key = "lost",        textId = 3042 },
  { key = "toDormitory", textId = 3043 },
  { key = "joinedCrew",  textId = 3044 },
  { key = "returned",    textId = 3045 },
}
-- Graph series, one line each over the hourly buckets.
local SERIES = {
  { key = "ejected",  textId = 3040, color = "graph_data_1" },
  { key = "rescued",  textId = 3041, color = "graph_data_4" },
  { key = "lost",     textId = 3042, color = "graph_data_2" },
  { key = "returned", textId = 3045, color = "graph_data_6" },
}
local GRAPH_HOURS = 24
local Y_STEPS = { 1, 2, 5, 10, 20, 50, 100, 200, 500 }
local EVENT_TEXT = { rescued = 3050, ejected = 3051, lost = 3052, toDormitory = 3053, joinedCrew = 3054, returned = 3055 }
local EVENT_COLOR = { rescued = "text_positive", lost = "text_negative", returned = "text_positive" }

local rr = {
  playerId   = nil,
  cfg        = {},
  debugLevel = "none",
  isV9       = false, -- 9.00 has table row groups, 8.00 has not
}

-- *** debug helpers ***

local function readConfig()
  local cfg = GetNPCBlackboard(rr.playerId, "$RescueRangersConfig")
  rr.cfg = (type(cfg) == "table") and cfg or {}
  rr.debugLevel = tostring(rr.cfg.debugLevel or "none")
end

local function debugLog(fmt, ...)
  if rr.debugLevel == "debug" or rr.debugLevel == "trace" then
    DebugError("RR_Overview: " .. string.format(fmt, ...))
  end
end

local function traceLog(fmt, ...)
  if rr.debugLevel == "trace" then
    DebugError("RR_Overview: " .. string.format(fmt, ...))
  end
end

-- *** data ***

local function pageText(id)
  return tostring(ReadText(PAGE, id))
end

local function toBool(value)
  return value == true or value == 1
end

local function luaId(id64)
  return ConvertStringToLuaID(tostring(id64))
end

-- An order param's object or sector as an id64, 0 for none.
local function componentOf(value)
  if value == nil or value == 0 or value == false then
    return 0
  end
  local ok, id64 = pcall(ConvertIDTo64Bit, value)
  if ok and id64 then
    return id64
  end
  return 0
end

local function isAlive(id64)
  return id64 ~= 0 and IsValidComponent(luaId(id64))
end

local function nameOf(id64)
  if not isAlive(id64) then
    return ""
  end
  return tostring(GetComponentData(luaId(id64), "name"))
end

local function shipLabel(id64)
  if not isAlive(id64) then
    return "-"
  end
  return string.format("%s (%s)", nameOf(id64), ffi.string(C.GetObjectIDCode(id64)))
end

local function sectorNameOf(id64)
  local sector = GetComponentData(luaId(id64), "sectorid")
  return sector and tostring(GetComponentData(sector, "name")) or ""
end

-- Crew on board (the pilot not counted) and the crew capacity.
local function crewOf(id64)
  if not isAlive(id64) then
    return 0, 0
  end
  local capacity = C.GetPeopleCapacity(id64, "", false)
  local numroles = C.GetNumAllRoles()
  local count = 0
  if numroles > 0 then
    local buf = ffi.new("PeopleInfo[?]", numroles)
    local n = C.GetPeople2(buf, numroles, id64, true)
    for i = 0, n - 1 do
      count = count + buf[i].amount
    end
  end
  return count, capacity
end

local function pilotingOf(id64)
  local pilot = GetComponentData(luaId(id64), "assignedpilot")
  if not pilot then
    return 0
  end
  for _, skill in ipairs(GetComponentData(pilot, "skills") or {}) do
    if skill.name == "piloting" then
      return tonumber(skill.value) or 0
    end
  end
  return 0
end

-- The same limit the order's own slider has.
local function rangeMax(piloting)
  local base = (piloting < 6) and 0 or ((piloting < 9) and 1 or ((piloting < 12) and 2 or 3))
  local extra = math.floor(tonumber(rr.cfg.extraRange) or 0)
  return base + math.max(0, extra)
end

local function queuedOrder(id64, orderdef)
  local n = C.GetNumOrders(id64)
  if n > 0 then
    local buf = ffi.new("Order[?]", n)
    n = C.GetOrders(buf, n, id64)
    for i = 0, n - 1 do
      if ffi.string(buf[i].orderdef) == orderdef then
        return true
      end
    end
  end
  return false
end

local function stateOf(id64)
  if queuedOrder(id64, "RescueShip") then
    return ReadText(PAGE, 3030), "text_positive"
  end
  if GetComponentData(luaId(id64), "isdocked") then
    return ReadText(1001, 3249), "text_normal"
  end
  return ReadText(PAGE, 3031), "text_normal"
end

local function readRanger(id64, settingsFrom)
  local params = GetOrderParams(luaId(settingsFrom), "default") or {}
  local function value(i)
    return params[i] and params[i].value
  end
  local station = componentOf(value(P.homeStation))
  local dormitory = componentOf(value(P.dormitory))
  local crew, capacity = crewOf(id64)
  local dormCrew, dormCapacity = crewOf(dormitory)
  local state, stateColor = stateOf(id64)
  return {
    id64         = id64,
    idcode       = ffi.string(C.GetObjectIDCode(id64)),
    name         = nameOf(id64),
    mode         = (station ~= 0) and "sector" or "fleet",
    sector       = sectorNameOf(id64),
    homeSector   = nameOf(componentOf(value(P.homeSector))),
    range        = math.floor(tonumber(value(P.range)) or 0),
    station      = station,
    dormitory    = dormitory,
    oxygen       = toBool(value(P.oxygen)),
    getThemBack  = toBool(value(P.getThemBack)),
    joinCrew     = toBool(value(P.joinCrew)),
    logbook      = toBool(value(P.logbook)),
    crew         = crew,
    capacity     = capacity,
    dormCrew     = dormCrew,
    dormCapacity = dormCapacity,
    state        = state,
    stateColor   = stateColor,
    piloting     = pilotingOf(id64),
  }
end

-- Every Rescue ship, each Mimic right after its commander.
local function collectRangers()
  local rangers, byId, mimics = {}, {}, {}
  local n = C.GetNumAllFactionShips("player")
  if n > 0 then
    local buf = ffi.new("UniverseID[?]", n)
    n = C.GetAllFactionShips(buf, n, "player")
    for i = 0, n - 1 do
      local id64 = ConvertStringTo64Bit(tostring(buf[i]))
      local order = ffi.new("Order")
      if C.GetDefaultOrder(order, id64) then
        local orderdef = ffi.string(order.orderdef)
        if orderdef == ORDER_ID then
          local ranger = readRanger(id64, id64)
          ranger.sortKey = string.lower(ranger.name .. " " .. ranger.idcode)
          rangers[#rangers + 1] = ranger
          byId[tostring(id64)] = ranger
        elseif orderdef == "Assist" then
          mimics[#mimics + 1] = id64
        end
      end
    end
  end
  for _, id64 in ipairs(mimics) do
    local commander = GetCommander(luaId(id64))
    local parent = commander and byId[tostring(ConvertIDTo64Bit(commander))]
    if parent then
      local mimic = readRanger(id64, parent.id64)
      mimic.mode = "mimic"
      mimic.commander = parent
      mimic.sortKey = parent.sortKey .. "\1" .. string.lower(mimic.name .. " " .. mimic.idcode)
      rangers[#rangers + 1] = mimic
    end
  end
  table.sort(rangers, function(a, b) return a.sortKey < b.sortKey end)
  return rangers
end

local function readStats()
  local stats = GetNPCBlackboard(rr.playerId, "$RescueRangersStats")
  return (type(stats) == "table") and stats or nil
end

local function rangerStatsOf(stats, idcode)
  for _, entry in ipairs((stats and stats.rangers) or {}) do
    if entry.id == idcode then
      return entry
    end
  end
  return nil
end

local function formatAgo(seconds)
  seconds = math.max(0, math.floor(seconds))
  local text
  if seconds < 3600 then
    text = ConvertTimeString(seconds, "%M:%S")
  elseif seconds < 86400 then
    text = ConvertTimeString(seconds, "%h:%M:%S")
  else
    text = ConvertTimeString(seconds, "%d " .. ReadText(1001, 104) .. " %h:%M")
  end
  return string.format(pageText(3061), text)
end

local function modeText(ranger)
  if ranger.mode == "mimic" then
    return ReadText(20208, 41201)
  elseif ranger.mode == "fleet" then
    return ReadText(1001, 9919)
  end
  return ReadText(1001, 11284)
end

local function baseText(ranger)
  if ranger.mode == "sector" then
    return shipLabel(ranger.station)
  end
  return shipLabel(ranger.dormitory)
end

local function eventText(event)
  local textId = EVENT_TEXT[event.kind]
  if not textId then
    return tostring(event.kind)
  end
  local ranger = event.rangerName and string.format("%s (%s)", tostring(event.rangerName), tostring(event.ranger)) or ""
  local other = event.other and string.format("%s (%s)", tostring(event.other), tostring(event.otherId)) or ""
  if event.kind == "rescued" then
    return string.format(pageText(textId), ranger, tostring(event.person or ""), tostring(event.sector or ""))
  elseif event.kind == "ejected" then
    return string.format(pageText(textId), other, tostring(event.count or 0), tostring(event.sector or ""))
  elseif event.kind == "lost" then
    return string.format(pageText(textId), tostring(event.person or ""), tostring(event.sector or ""))
  elseif event.kind == "toDormitory" then
    return string.format(pageText(textId), ranger, tostring(event.count or 0), other)
  elseif event.kind == "joinedCrew" then
    return string.format(pageText(textId), ranger, tostring(event.count or 0))
  elseif event.kind == "returned" then
    return string.format(pageText(textId), tostring(event.count or 0), other)
  end
  return tostring(event.kind)
end

-- *** order settings: the map menu's way, a planned default with every param copied ***

local function formatParam(value)
  if type(value) ~= "table" then
    return tostring(value)
  end
  local out = {}
  for _, x in ipairs(value) do
    out[#out + 1] = formatParam(x)
  end
  return "[" .. table.concat(out, ",") .. "]"
end

local function paramDiff(id64)
  local lid = luaId(id64)
  local a = GetOrderParams(lid, "default") or {}
  local okB, b = pcall(GetOrderParams, lid, "planneddefault")
  b = (okB and b) or {}
  local diff = {}
  for i, p in ipairs(a) do
    if p.type ~= "internal" then
      local x, y = formatParam(p.value), b[i] and formatParam(b[i].value) or "nil"
      if x ~= y then
        diff[#diff + 1] = i .. ":" .. x .. "->" .. y
      end
    end
  end
  return diff
end

local function settableValue(param, value)
  if param.type == "bool" and type(value) == "number" then
    return value ~= 0
  end
  return value
end

-- Restarts the ship's default order with `changes` ({ [position] = value }); nothing is
-- applied unless the copy matches the running order exactly.
local function applyParams(id64, changes)
  local lid = luaId(id64)
  local order = ffi.new("Order")
  if not C.GetDefaultOrder(order, id64) or ffi.string(order.orderdef) ~= ORDER_ID then
    debugLog("settings: %s has no Rescue Rangers default order.", tostring(id64))
    return false
  end
  local current = GetOrderParams(lid, "default") or {}
  C.CreateOrder(id64, ORDER_ID, true)
  for i, param in ipairs(current) do
    if param.type ~= "internal" then
      SetOrderParam(lid, "planneddefault", i, nil, settableValue(param, param.value))
    end
  end
  local copy = paramDiff(id64)
  if #copy > 0 then
    C.RemovePlannedDefaultOrder(id64)
    debugLog("settings: copy for %s differs, nothing applied: %s", ffi.string(C.GetObjectIDCode(id64)), table.concat(copy, " "))
    return false
  end
  local count = 0
  for i, value in pairs(changes) do
    SetOrderParam(lid, "planneddefault", i, nil, value)
    count = count + 1
  end
  local changed = paramDiff(id64)
  if #changed ~= count then
    C.RemovePlannedDefaultOrder(id64)
    debugLog("settings: %s changed %d params instead of %d, nothing applied: %s", ffi.string(C.GetObjectIDCode(id64)), #changed, count, table.concat(changed, " "))
    return false
  end
  C.ResetOrderLoop(id64)
  C.EnablePlannedDefaultOrder(id64, false)
  debugLog("settings: %s restarted with %s", ffi.string(C.GetObjectIDCode(id64)), table.concat(changed, " "))
  return true
end

-- *** top-level entry ***

local function addTopLevelEntry()
  ---@type table[]
  local list = Helper.topLevelMenus
  local pos = #list + 1
  for i, entry in ipairs(list) do
    if entry.id == TOP_LEVEL_ID then
      return
    end
    if entry.id == "map" then
      pos = i + 1
    end
  end
  table.insert(list, pos, {
    id = TOP_LEVEL_ID, name = ReadText(PAGE, 1), icon = "order_rescuerangers", shortcut = "",
    menu = menu.name, helpOverlayID = "toplevel_rescuerangers", helpOverlayText = ReadText(PAGE, 3000), param = { 0, 0 },
  })
  debugLog("top-level entry added at %d of %d.", pos, #list)
end

local function removeTopLevelEntry()
  ---@type table[]
  local list = Helper.topLevelMenus
  for i, entry in ipairs(list) do
    if entry.id == TOP_LEVEL_ID then
      table.remove(list, i)
      debugLog("top-level entry removed.")
      return
    end
  end
end

-- Unset counts as on: the first load reads the config before the MD creates it.
local function topMenuIconOn()
  return rr.cfg.topMenuIcon == nil or toBool(rr.cfg.topMenuIcon)
end

local function syncTopLevelEntry()
  if topMenuIconOn() then
    addTopLevelEntry()
  else
    removeTopLevelEntry()
  end
end

local function onTopMenuIconChanged()
  readConfig()
  syncTopLevelEntry()
end

-- *** menu ***

function menu.cleanup()
  menu.open = false
  menu.infoFrame = nil
  menu.refreshQueued = nil
  menu.sliderActive = nil
end

function menu.onShowMenu(state)
  menu.open = true
  readConfig()
  syncTopLevelEntry()
  if not state or menu.tab == nil then
    menu.tab = menu.tab or "rangers"
    menu.selected = menu.selected or {}
    menu.topRows = menu.topRows or {}
  end
  Helper.setTabScrollCallback(menu, menu.onTabScroll)
  menu.createFrame()
end

function menu.selectTab(id)
  if menu.tab == id then
    return
  end
  menu.tab = id
  traceLog("tab: %s.", id)
  menu.refreshQueued = true
end

function menu.onTabScroll(direction)
  local step = (direction == "right") and 1 or ((direction == "left") and -1 or 0)
  if step == 0 then
    return
  end
  if topMenuIconOn() then
    Helper.scrollTopLevel(menu, TOP_LEVEL_ID, step)
    return
  end
  for i, tab in ipairs(TABS) do
    if tab.id == menu.tab then
      menu.selectTab(TABS[(i - 1 + step) % #TABS + 1].id)
      return
    end
  end
end

function menu.viewCreated(_layer, ...)
end

local function titleRow(ftable, cols, text)
  local properties = { fixed = true }
  for key, value in pairs(Helper.headerRowProperties or {}) do
    properties[key] = value
  end
  local row = ftable:addRow(false, properties)
  row[1]:setColSpan(cols):createText(text, Helper.headerRowCenteredProperties)
  return row
end

local function rowGroup(ftable)
  return rr.isV9 and ftable:addRowGroup({}) or ftable
end

local function headerRow(rows, texts, aligns)
  local row = rows:addRow(false, { fixed = true, bgColor = Color["row_title_background"] })
  for i, text in ipairs(texts) do
    row[i]:createText(text, { halign = (aligns and aligns[i]) or "left", font = Helper.standardFontBold })
  end
  return row
end

local function noticeRow(rows, cols, text)
  local row = rows:addRow(false, { bgColor = Color["row_background_unselectable"] })
  row[1]:setColSpan(cols):createText(text, { halign = "center", wordwrap = true, color = Color["text_inactive"] })
end

function menu.createFrame()
  Helper.clearDataForRefresh(menu, config.infoLayer)
  menu.sliderActive = nil
  menu.infoFrame = Helper.createFrameHandle(menu, {
    layer           = config.infoLayer,
    standardButtons = { back = true, close = true, help = false },
    width           = Helper.viewWidth,
    height          = Helper.viewHeight,
    x               = 0,
    y               = 0,
  })
  menu.infoFrame:setBackground("solid", { color = Color["frame_background_semitransparent"] })

  local topLevelBottom = topMenuIconOn() and Helper.createTopLevelTab(menu, TOP_LEVEL_ID, menu.infoFrame, "", nil, true) or nil
  local top = menu.createTabRow(topLevelBottom) + Helper.borderSize
  local width = Helper.viewWidth - 2 * Helper.frameBorder
  local rangers = collectRangers()
  local stats = readStats()
  if menu.tab == "stats" then
    menu.createStatsPanel(Helper.frameBorder, top, width, rangers, stats)
  elseif menu.tab == "settings" then
    menu.createSettingsPanel(Helper.frameBorder, top, width, rangers)
  else
    menu.createRangersPanel(Helper.frameBorder, top, width, rangers, stats)
  end

  menu.infoFrame:display()
  menu.lastRefreshTime = getElapsedTime()
end

-- Centred tab icons with the current tab's name under them; returns the y under the bar.
function menu.createTabRow(topLevelBottom)
  local iconSize  = Helper.scaleX(Helper.sidebarWidth)
  local inputSize = Helper.scaleX(config.tabInputWidth)
  local cols      = #TABS + 2
  local width     = #TABS * iconSize + 2 * inputSize + (#TABS + 1) * Helper.borderSize
  local bgColor   = Color["toplevel_background_default"]
  local y         = ((topLevelBottom or 0) > 0) and (topLevelBottom + Helper.borderSize) or Helper.frameBorder

  local ftable = menu.infoFrame:addTable(cols, {
    tabOrder = 21, x = Helper.viewWidth / 2 - width / 2, y = y,
    scaling = false, reserveScrollBar = false, skipTabChange = true,
  })
  ftable:setColWidth(1, inputSize)
  for i = 1, #TABS do
    ftable:setColWidth(i + 1, iconSize)
  end
  ftable:setColWidth(cols, inputSize)
  ftable:setDefaultBackgroundColSpan(1, cols)

  local row = ftable:addRow(true, { fixed = true, borderBelow = false, bgColor = bgColor })
  local currentName = ""
  for i, tab in ipairs(TABS) do
    local current = (tab.id == menu.tab)
    row[i + 1]:createButton({ height = iconSize, bgColor = Color["toplevel_button_background"], borderColor = Color["button_border_hidden"], mouseOverText = tab.name() })
        :setIcon(tab.icon, { color = current and Color["icon_normal"] or Color["icon_inactive"] })
    if current then
      currentName = tostring(tab.name())
    else
      row[i + 1].handlers.onClick = function() return menu.selectTab(tab.id) end
    end
  end
  row = ftable:addRow(false, { fixed = true, borderBelow = false, bgColor = bgColor, scaling = true })
  row[1]:setColSpan(cols):createText(currentName, { halign = "center", x = 0, font = Helper.standardFontOutlined })

  return ftable.properties.y + ftable:getFullHeight()
end

local function restoreRows(ftable, key, rowOf)
  local selected = menu.selected[key]
  if selected and rowOf[selected] then
    ftable:setSelectedRow(rowOf[selected])
  end
  if menu.topRows[key] then
    ftable:setTopRow(menu.topRows[key])
  end
end

-- Buttons under a panel; returns the y the panel above may use up to.
local function buttonBar(x, width)
  local ftable = menu.infoFrame:addTable(3, { tabOrder = 30, x = x, width = width, reserveScrollBar = false })
  ftable:setColWidthPercent(1, 60)
  local row = ftable:addRow(true, { fixed = true })
  row[2]:createButton({}):setText(ReadText(1001, 3408), { halign = "center" })
  row[2].handlers.onClick = function() return menu.buttonShowOnMap() end
  row[3]:createButton({}):setText(ReadText(1001, 6401), { halign = "center" })
  row[3].handlers.onClick = function() menu.refreshQueued = true end
  local height = ftable:getFullHeight()
  ftable.properties.y = Helper.viewHeight - Helper.frameBorder - height
  return ftable.properties.y - Helper.borderSize
end

function menu.createRangersPanel(x, y, width, rangers, stats)
  local bottom = buttonBar(x, width)
  local cols = 9
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 1, x = x, y = y, width = width, maxVisibleHeight = bottom - y })
  ftable:setColWidthPercent(2, 7)
  ftable:setColWidthPercent(3, 12)
  ftable:setColWidthPercent(4, 14)
  ftable:setColWidthPercent(5, 17)
  ftable:setColWidthPercent(6, 7)
  ftable:setColWidthPercent(7, 7)
  ftable:setColWidthPercent(8, 9)
  ftable:setColWidthPercent(9, 7)
  titleRow(ftable, cols, ReadText(PAGE, 3001))
  local rows = rowGroup(ftable)
  headerRow(rows, {
    ReadText(1001, 5), ReadText(PAGE, 3010), ReadText(1001, 2943), ReadText(PAGE, 3013), ReadText(PAGE, 3011),
    ReadText(1001, 80), ReadText(PAGE, 3014), ReadText(1001, 12), ReadText(PAGE, 3012),
  }, { "left", "left", "left", "left", "left", "right", "right", "left", "right" })
  if #rangers == 0 then
    noticeRow(rows, cols, ReadText(PAGE, 3056))
  end
  local rowOf = {}
  for _, ranger in ipairs(rangers) do
    local row = rows:addRow({ "ranger", ranger.idcode }, {})
    rowOf[ranger.idcode] = row.index
    local label = string.format("%s (%s)", ranger.name, ranger.idcode)
    row[1]:createText((ranger.mode == "mimic") and ("   " .. label) or label, { halign = "left" })
    row[2]:createText(modeText(ranger), { halign = "left" })
    row[3]:createText(ranger.sector, { halign = "left" })
    row[4]:createText(string.format("%s (%d)", ranger.homeSector, ranger.range), { halign = "left", mouseOverText = ReadText(PAGE, 104) })
    row[5]:createText(baseText(ranger), { halign = "left", mouseOverText = (ranger.mode == "sector") and ReadText(PAGE, 102) or ReadText(PAGE, 103) })
    row[6]:createText(string.format("%d / %d", ranger.crew, ranger.capacity), { halign = "right" })
    row[7]:createText((ranger.dormitory ~= 0) and string.format("%d / %d", ranger.dormCrew, ranger.dormCapacity) or "-", { halign = "right" })
    row[8]:createText(ranger.state, { halign = "left", color = Color[ranger.stateColor] })
    local entry = rangerStatsOf(stats, ranger.idcode)
    row[9]:createText(tostring(entry and entry.rescued or 0), { halign = "right" })
  end
  restoreRows(ftable, "rangers", rowOf)
end

function menu.createStatsPanel(x, y, width, rangers, stats)
  local bottom = buttonBar(x, width)
  local leftWidth = math.floor(width * 0.45)
  local rightX = x + leftWidth + Helper.borderSize
  local rightWidth = width - leftWidth - Helper.borderSize

  -- Left: the totals, then one row per Rescue ship.
  local cols = 5
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 1, x = x, y = y, width = leftWidth, maxVisibleHeight = bottom - y })
  ftable:setColWidthPercent(2, 14)
  ftable:setColWidthPercent(3, 14)
  ftable:setColWidthPercent(4, 14)
  ftable:setColWidthPercent(5, 18)
  titleRow(ftable, cols, ReadText(1001, 2637))
  local rows = rowGroup(ftable)
  if not stats then
    noticeRow(rows, cols, ReadText(PAGE, 3059))
  else
    for _, counter in ipairs(COUNTERS) do
      local row = rows:addRow(true, {})
      row[1]:setColSpan(4):createText(ReadText(PAGE, counter.textId), { halign = "left" })
      row[5]:createText(tostring(stats[counter.key] or 0), { halign = "right" })
    end
    local row = rows:addRow(false, { bgColor = Color["row_background_unselectable"] })
    row[1]:setColSpan(cols):createText(string.format(pageText(3046), formatAgo(C.GetCurrentGameTime() - (tonumber(stats.since) or 0))), { halign = "left", color = Color["text_inactive"] })
  end

  titleRow(ftable, cols, ReadText(PAGE, 3048))
  rows = rowGroup(ftable)
  headerRow(rows, { ReadText(1001, 5), ReadText(PAGE, 3012), ReadText(PAGE, 3015), ReadText(PAGE, 3016), ReadText(PAGE, 3049) },
    { "left", "right", "right", "right", "right" })
  local now = C.GetCurrentGameTime()
  local listed = {}
  local rowOf = {}
  local function statsRow(label, entry, idcode)
    local row = rows:addRow({ "ranger", idcode }, {})
    rowOf[idcode] = row.index
    row[1]:createText(label, { halign = "left" })
    row[2]:createText(tostring(entry and entry.rescued or 0), { halign = "right" })
    row[3]:createText(tostring(entry and entry.toDormitory or 0), { halign = "right" })
    row[4]:createText(tostring(entry and entry.joinedCrew or 0), { halign = "right" })
    local last = entry and tonumber(entry.last) or 0
    row[5]:createText((last > 0) and formatAgo(now - last) or "-", { halign = "right" })
  end
  for _, ranger in ipairs(rangers) do
    listed[ranger.idcode] = true
    statsRow(string.format("%s (%s)", ranger.name, ranger.idcode), rangerStatsOf(stats, ranger.idcode), ranger.idcode)
  end
  -- Rescue ships that are gone, or no longer on the order, keep their counts.
  for _, entry in ipairs((stats and stats.rangers) or {}) do
    if not listed[entry.id] then
      statsRow(string.format("%s (%s)", tostring(entry.name), tostring(entry.id)), entry, tostring(entry.id))
    end
  end
  restoreRows(ftable, "stats", rowOf)

  -- Right: the hourly graph, then the newest events first.
  local graphBottom = menu.createGraph(rightX, y, rightWidth, math.floor((bottom - y) * 0.4), stats)
  local eventsY = graphBottom + Helper.borderSize
  local etable = menu.infoFrame:addTable(2, { tabOrder = 2, x = rightX, y = eventsY, width = rightWidth, maxVisibleHeight = bottom - eventsY })
  etable:setColWidthPercent(1, 16)
  titleRow(etable, 2, ReadText(PAGE, 3047))
  local erows = rowGroup(etable)
  local events = (stats and stats.events) or {}
  if #events == 0 then
    noticeRow(erows, 2, ReadText(PAGE, 3059))
  end
  local shown = 0
  for i = #events, 1, -1 do
    local event = events[i]
    local row = erows:addRow(true, {})
    row[1]:createText(formatAgo(now - (tonumber(event.t) or now)), { halign = "left", color = Color["text_inactive"] })
    row[2]:createText(eventText(event), { halign = "left", wordwrap = true, color = Color[EVENT_COLOR[event.kind] or "text_normal"] })
    shown = shown + 1
    if shown >= config.eventRows then
      break
    end
  end
end

-- One line per series over the last GRAPH_HOURS game hours; returns the y under it.
function menu.createGraph(x, y, width, height, stats)
  local current = math.floor(C.GetCurrentGameTime() / 3600)
  local byHour = {}
  for _, bucket in ipairs((stats and stats.hours) or {}) do
    byHour[tonumber(bucket.h) or -1] = bucket
  end
  local cols = #SERIES
  local gtable = menu.infoFrame:addTable(cols, { tabOrder = 3, x = x, y = y, width = width, reserveScrollBar = false, highlightMode = "off" })
  titleRow(gtable, cols, ReadText(PAGE, 3062))
  local legend = gtable:addRow(false, { fixed = true })
  for i, series in ipairs(SERIES) do
    legend[i]:createText(ReadText(PAGE, series.textId), { halign = "center", color = Color[series.color] })
  end
  local graphRow = gtable:addRow(false, { fixed = true })
  local graph = graphRow[1]:setColSpan(cols):createGraph({ height = math.max(Helper.scaleY(120), height - gtable:getFullHeight() - Helper.borderSize), scaling = false })
  local maxY = 1
  for _, series in ipairs(SERIES) do
    local record = graph:addDataRecord({
      markertype = "square", markersize = 5, markercolor = Color[series.color],
      linetype = "normal", linewidth = 2, linecolor = Color[series.color],
      mouseOverText = ReadText(PAGE, series.textId),
    })
    for hour = current - GRAPH_HOURS + 1, current do
      local bucket = byHour[hour]
      local value = bucket and tonumber(bucket[series.key]) or 0
      maxY = math.max(maxY, value)
      record:addData(hour - current, value)
    end
  end
  local yStep = Y_STEPS[#Y_STEPS]
  for _, step in ipairs(Y_STEPS) do
    if maxY / step <= 8 then
      yStep = step
      break
    end
  end
  graph:setXAxis({ startvalue = 1 - GRAPH_HOURS, endvalue = 0, granularity = 3, offset = 0, gridcolor = Color["graph_grid"], unittext = ReadText(1001, 102) })
  graph:setXAxisLabel(ReadText(1001, 6519), { fontsize = 9 })
  graph:setYAxis({ startvalue = 0, endvalue = (math.ceil(maxY / yStep) + 0.5) * yStep, granularity = yStep, offset = 0, gridcolor = Color["graph_grid"] })
  graph:setYAxisLabel(ReadText(1001, 6521), { fontsize = 9 })
  return gtable.properties.y + gtable:getFullHeight()
end

function menu.createSettingsPanel(x, y, width, rangers)
  local bottom = buttonBar(x, width)
  local cols = 6
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 1, x = x, y = y, width = width, maxVisibleHeight = bottom - y })
  ftable:setColWidthPercent(2, 10)
  ftable:setColWidthPercent(3, 14)
  ftable:setColWidthPercent(4, 14)
  ftable:setColWidthPercent(5, 14)
  ftable:setColWidthPercent(6, 14)
  titleRow(ftable, cols, ReadText(1001, 2679))
  local rows = rowGroup(ftable)
  headerRow(rows, { ReadText(1001, 5), ReadText(PAGE, 104), ReadText(PAGE, 105), ReadText(PAGE, 106), ReadText(PAGE, 107), ReadText(PAGE, 109) },
    { "left", "left", "center", "center", "center", "center" })
  if #rangers == 0 then
    noticeRow(rows, cols, ReadText(PAGE, 3056))
  end
  local size = Helper.scaleX(Helper.standardTextHeight)
  local inset = rr.isV9 and Helper.standardContainerOffset or 0
  local boxX = math.max(0, math.floor((width * 0.14 - inset - size) / 2))
  local rowOf = {}
  for _, ranger in ipairs(rangers) do
    local row = rows:addRow({ "ranger", ranger.idcode }, {})
    rowOf[ranger.idcode] = row.index
    local label = string.format("%s (%s)", ranger.name, ranger.idcode)
    if ranger.mode == "mimic" then
      row[1]:createText("   " .. label, { halign = "left", mouseOverText = ReadText(PAGE, 3057) })
      row[2]:setColSpan(5):createText(string.format(pageText(3017), string.format("%s (%s)", ranger.commander.name, ranger.commander.idcode)), { halign = "left", color = Color["text_inactive"] })
    else
      row[1]:createText(label, { halign = "left" })
      local max = rangeMax(ranger.piloting)
      -- A dropdown, not a slider: a row with a slider cell may hold no checkbox.
      if max > 0 or ranger.range > 0 then
        local options = {}
        for value = 0, math.max(max, ranger.range) do
          options[#options + 1] = { id = tostring(value), text = tostring(value), icon = "", displayremoveoption = false }
        end
        row[2]:createDropDown(options, { startOption = tostring(ranger.range), height = Helper.standardTextHeight, mouseOverText = ReadText(PAGE, 3058) })
        row[2].handlers.onDropDownConfirmed = function(_, id) return menu.setParam(ranger.id64, P.range, math.floor(tonumber(id) or 0)) end
      else
        row[2]:createText("0", { halign = "left", color = Color["text_inactive"], mouseOverText = ReadText(PAGE, 3018) })
      end
      local function checkbox(col, index, on)
        row[col]:createCheckBox(on, { width = size, height = size, scaling = false, x = boxX, mouseOverText = ReadText(PAGE, 3058) })
        row[col].handlers.onClick = function(_, checked) return menu.setParam(ranger.id64, index, checked) end
      end
      checkbox(3, P.oxygen, ranger.oxygen)
      checkbox(4, P.getThemBack, ranger.getThemBack)
      checkbox(5, P.joinCrew, ranger.joinCrew)
      checkbox(6, P.logbook, ranger.logbook)
    end
  end
  restoreRows(ftable, "settings", rowOf)
end

function menu.setParam(id64, index, value)
  menu.sliderActive = nil
  local ok = applyParams(id64, { [index] = value })
  if not ok then
    debugLog("settings: param %d of %s not applied.", index, tostring(id64))
  end
  menu.refreshQueued = true
end

local function selectOnMap(id64, tries)
  local map = Helper.getMenu("MapMenu")
  if map ~= nil and map.shown and map.holomap ~= nil and map.holomap ~= 0 then
    map.addSelectedComponent(id64)
  elseif tries > 0 then
    Helper.addDelayedOneTimeCallbackOnUpdate(function() selectOnMap(id64, tries - 1) end, false, getElapsedTime() + config.mapSelectRetry)
  end
end

local function selectedShip()
  local idcode = menu.selected[menu.tab]
  if not idcode then
    return nil
  end
  for _, ranger in ipairs(collectRangers()) do
    if ranger.idcode == idcode then
      return ranger.id64
    end
  end
  return nil
end

function menu.buttonShowOnMap()
  local id64 = selectedShip()
  if not id64 then
    return
  end
  traceLog("showOnMap: %s.", tostring(menu.selected[menu.tab]))
  Helper.closeMenuAndOpenNewMenu(menu, "MapMenu", { 0, 0, true, id64 })
  menu.cleanup()
  Helper.addDelayedOneTimeCallbackOnUpdate(function() selectOnMap(id64, config.mapSelectTries) end, false, getElapsedTime() + config.mapSelectRetry)
end

function menu.onRowChanged(_row, rowdata, uitable)
  if type(rowdata) == "table" and rowdata[1] == "ranger" then
    menu.selected[menu.tab] = rowdata[2]
    menu.topRows[menu.tab] = GetTopRow(uitable)
  end
end

function menu.onSelectElement(uitable, _modified, _row, isdblclick, input)
  if isdblclick or input ~= "mouse" then
    local rowdata = Helper.getCurrentRowData(menu, uitable)
    if type(rowdata) == "table" and rowdata[1] == "ranger" and menu.tab ~= "settings" then
      menu.selected[menu.tab] = rowdata[2]
      menu.buttonShowOnMap()
    end
  end
end

function menu.onUpdate()
  if menu.sliderActive then
    if menu.infoFrame then
      menu.infoFrame:update()
    end
    return
  end
  if menu.refreshQueued then
    menu.refreshQueued = nil
    return menu.createFrame()
  end
  if menu.open and menu.tab ~= "settings" and getElapsedTime() - menu.lastRefreshTime >= config.refreshInterval then
    return menu.createFrame()
  end
  if menu.infoFrame then
    menu.infoFrame:update()
  end
end

function menu.onCloseElement(dueToClose)
  Helper.closeMenu(menu, dueToClose)
  menu.cleanup()
end

-- Read by onShowMenu as "restored", never for its value.
function menu.onSaveState()
  return true
end

local function Init()
  rr.playerId = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
  rr.isV9 = C.GetGameVersion().major >= 9
  readConfig()
  if Helper then
    Helper.registerMenu(menu)
    syncTopLevelEntry()
  end
  RegisterEvent("RescueRangers.TopMenuIcon", onTopMenuIconChanged)
end

Register_OnLoad_Init(Init)
