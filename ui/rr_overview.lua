-- Rescue Rangers - overview menu: every Rescue ship with its state, the statistics
-- md/rr_stats.xml keeps, the people in Stasis (md/rr_stasis.xml) and the order settings
-- of each Rescue ship. Opened from its own entry in vanilla's top-level icon row, right after the map.

---@diagnostic disable-next-line: unresolved-require
local ffi = require("ffi")
local C   = ffi.C

local PAGE         = 1972092402
local TOP_LEVEL_ID = "rescuerangers"
local ORDER_ID     = "RescueRangers"

-- Order param positions, as declared in aiscripts/order.rescue.rangers.sector.xml.
local P = { homeSector = 1, range = 2, homeStation = 3, dormitory = 4, oxygen = 5, getThemBack = 6, joinCrew = 7, logbook = 8, stasisMode = 9 }

local menu = {
  name            = "RescueRangersOverviewMenu",
  updateInterval  = 0.5,
  lastRefreshTime = 0.0,
}

local config = {
  infoLayer       = 4,
  contextLayer    = 2,
  refreshInterval = 5, -- seconds between rebuilds on the Rescue ships and Statistics tabs, age updates on Stasis
  eventRows       = 60,
  tabInputWidth   = 100, -- empty cells either side of the tab icons, room for the tab name
  mapSelectRetry  = 0.25,
  mapSelectTries  = 8,
  candidatesStale = 600, -- game seconds before the rent candidates are asked for again on tab open
  candidatesRetry = 30,  -- real seconds between two automatic asks
  confirmWidth    = 420,
}

local TABS = {
  { id = "rangers",  icon = "tlt_rescuerangers",      name = function() return ReadText(PAGE, 3001) end },
  { id = "stats",    icon = "pi_statistics",          name = function() return ReadText(1001, 2500) end },
  { id = "stasis",   icon = "pi_personnelmanagement", name = function() return ReadText(PAGE, 4000) end },
  { id = "settings", icon = "mapst_standing_orders",  name = function() return ReadText(1001, 2679) end },
}

-- Assign roles; `skill` is the potential skill field of a Stasis record (0-100).
local ROLES = {
  { id = "service", skill = "asService", text = function() return ReadText(20208, 20103) end },
  { id = "marine",  skill = "asMarine",  text = function() return ReadText(20208, 20203) end },
  { id = "pilot",   skill = "asPilot",   text = function() return ReadText(1001, 4847) end },
  { id = "manager", skill = "asManager", text = function() return ReadText(20208, 30301) end },
}
local SORTS = {
  { id = "name",     text = function() return ReadText(1001, 2809) end },
  { id = "skill",    text = function() return ReadText(1001, 9124) end },
  { id = "lostShip", text = function() return ReadText(PAGE, 4101) end },
  { id = "since",    text = function() return ReadText(PAGE, 4102) end },
  { id = "location", text = function() return ReadText(1001, 2943) end },
}
local SKILLS = {
  { key = "piloting", textId = 501 }, { key = "engineering", textId = 201 }, { key = "boarding", textId = 101 },
  { key = "management", textId = 301 }, { key = "morale", textId = 401 },
}

-- Statistics counters in display order; the event log texts take the same kinds.
local COUNTERS = {
  { key = "ejected",     textId = 3040 },
  { key = "rescued",     textId = 3041 },
  { key = "lost",        textId = 3042 },
  { key = "toDormitory", textId = 3043 },
  { key = "toStasis",    textId = 3064 },
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
local EVENT_TEXT = { rescued = 3050, ejected = 3051, lost = 3052, toDormitory = 3053, joinedCrew = 3054, returned = 3055, toStasis = 3065 }
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

-- Rescued people the last Stasis pass found no place for (the order's pilot flag); 0 while Stasis is off.
local function stasisNoPlaceOf(id64, stasisMode)
  local mode = (stasisMode == 2 and "overflow") or (stasisMode == 3 and "instead") or ((stasisMode == 0) and rr.cfg.stasisMode) or "off"
  if mode ~= "overflow" and mode ~= "instead" then
    return 0
  end
  local pilot = GetComponentData(luaId(id64), "assignedpilot")
  if not pilot then
    return 0
  end
  return math.floor(tonumber(GetNPCBlackboard(ConvertIDTo64Bit(pilot), "$rescueRangersStasisNoPlace")) or 0)
end

local function stateOf(id64, noPlace)
  if queuedOrder(id64, "RescueShip") then
    return ReadText(PAGE, 3030), "text_positive"
  end
  if noPlace > 0 then
    return ReadText(PAGE, 3067), "text_warning", string.format(pageText(3068), noPlace)
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
  local stasisMode = math.floor(tonumber(value(P.stasisMode)) or 0)
  local state, stateColor, stateHint = stateOf(id64, stasisNoPlaceOf(id64, stasisMode))
  return {
    id64         = id64,
    idcode       = ffi.string(C.GetObjectIDCode(id64)),
    name         = nameOf(id64),
    mode         = (station ~= 0) and "sector" or "fleet",
    sector       = sectorNameOf(id64),
    homeSector   = nameOf(componentOf(value(P.homeSector))),
    homeSectorId = componentOf(value(P.homeSector)),
    range        = math.floor(tonumber(value(P.range)) or 0),
    stasisMode   = stasisMode,
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
    stateHint    = stateHint,
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

local function formatDuration(seconds)
  seconds = math.max(0, math.floor(seconds))
  if seconds < 3600 then
    return ConvertTimeString(seconds, "%M:%S")
  elseif seconds < 86400 then
    return ConvertTimeString(seconds, "%h:%M:%S")
  end
  return ConvertTimeString(seconds, "%d " .. ReadText(1001, 104) .. " %h:%M")
end

local function formatAgo(seconds)
  return string.format(pageText(3061), formatDuration(seconds))
end

local function formatMoney(amount)
  return ConvertMoneyString(tonumber(amount) or 0, false, true, 0, true)
end

-- Options-level Stasis mode ('off', 'overflow', 'instead') as text.
local function stasisModeText(mode)
  if mode == "overflow" then
    return pageText(4050)
  elseif mode == "instead" then
    return pageText(4051)
  end
  return ReadText(1001, 7726)
end

-- *** Stasis data: md/rr_stasis.xml publishes it; components arrive as LuaIDs, MD false as 0 ***

local function readStasis()
  local data = GetNPCBlackboard(rr.playerId, "$RescueRangersStasis")
  return (type(data) == "table") and data or nil
end

local function roleOf(id)
  for _, role in ipairs(ROLES) do
    if role.id == id then
      return role
    end
  end
  return ROLES[1]
end

local function potentialStars(value)
  return Helper.displaySkill(math.floor((tonumber(value) or 0) * 15 / 100))
end

local function textOf(value)
  local text = (value ~= nil and value ~= 0) and tostring(value) or ""
  return (text ~= "") and text or "-"
end

local function rangerLabel(person)
  if person.rangerName == nil or person.rangerName == 0 then
    return textOf(person.ranger)
  end
  return string.format("%s (%s)", tostring(person.rangerName), textOf(person.ranger))
end

local function personMatches(person, filter)
  if filter == "" then
    return true
  end
  for _, value in ipairs({ person.name, person.lostShip, person.stationName, person.rangerName, person.ranger }) do
    if value ~= nil and value ~= 0 and string.find(string.lower(tostring(value)), filter, 1, true) then
      return true
    end
  end
  return false
end

-- The filtered and sorted Stasis records.
local function stasisPeople(data, state)
  local role = roleOf(state.role)
  local filter = string.lower(state.filter or "")
  local list = {}
  for _, person in ipairs((data and data.people) or {}) do
    if personMatches(person, filter) then
      local primary = ""
      if state.sort == "skill" then
        primary = string.format("%03d", 100 - math.floor(tonumber(person[role.skill]) or 0))
      elseif state.sort == "lostShip" then
        primary = (textOf(person.lostShip) ~= "-") and string.lower(tostring(person.lostShip)) or "\127"
      elseif state.sort == "since" then
        primary = string.format("%012d", math.floor(tonumber(person.since) or 0))
      elseif state.sort == "location" then
        primary = string.lower(textOf(person.stationName))
      end
      list[#list + 1] = { person = person, primary = primary, name = string.lower(textOf(person.name)) }
    end
  end
  table.sort(list, function(a, b)
    if a.primary ~= b.primary then
      return a.primary < b.primary
    elseif a.name ~= b.name then
      return a.name < b.name
    end
    return (tonumber(a.person.key) or 0) < (tonumber(b.person.key) or 0)
  end)
  local people = {}
  for i, entry in ipairs(list) do
    people[i] = entry.person
  end
  return people
end

-- Player ships (player stations for a manager) with free people space, most space first.
local function assignTargets(roleId)
  local targets = {}
  local stations = (roleId == "manager")
  local n = stations and C.GetNumAllFactionStations("player") or C.GetNumAllFactionShips("player")
  if n > 0 then
    local buf = ffi.new("UniverseID[?]", n)
    if stations then
      n = C.GetAllFactionStations(buf, n, "player")
    else
      n = C.GetAllFactionShips(buf, n, "player")
    end
    for i = 0, n - 1 do
      local id64 = ConvertStringTo64Bit(tostring(buf[i]))
      local crew, capacity = crewOf(id64)
      if capacity > crew and not GetComponentData(luaId(id64), "isnpcassignmentrestricted") then
        local label = shipLabel(id64)
        local target = { id64 = id64, label = label, free = capacity - crew, sortKey = string.lower(label) }
        if stations then
          local manager = componentOf(GetComponentData(luaId(id64), "tradenpc"))
          if isAlive(manager) then
            target.managerName = nameOf(manager)
            target.managerStars = potentialStars(C.GetEntityCombinedSkill(manager, nil, "manager"))
          end
        end
        targets[#targets + 1] = target
      end
    end
  end
  table.sort(targets, function(a, b)
    if a.free ~= b.free then
      return a.free > b.free
    end
    return a.sortKey < b.sortKey
  end)
  return targets
end

-- Where rent candidates are measured from: sector-mode home sectors and fleet-mode ships.
local function candidateSources(rangers)
  local from, seen = {}, {}
  for _, ranger in ipairs(rangers) do
    local id64 = 0
    if ranger.mode == "sector" then
      id64 = ranger.homeSectorId
    elseif ranger.mode == "fleet" then
      id64 = ranger.id64
    end
    if id64 ~= 0 and not seen[tostring(id64)] then
      seen[tostring(id64)] = true
      from[#from + 1] = luaId(id64)
    end
  end
  return from
end

local function candidateText(entry)
  return string.format(pageText(4121), textOf(entry.stationName), textOf(entry.ownerName), textOf(entry.sectorName),
    tostring(math.floor(tonumber(entry.distance) or 0)), tostring(math.floor(tonumber(entry.free) or 0)))
end

-- Status text, color and mouse-over of a lease: debt, then relation, closing, no docking, paid.
local function leaseStatus(lease, now, cap)
  local debt = tonumber(lease.debt) or 0
  if debt > 0 then
    return string.format(pageText(4108), formatMoney(debt)), "text_negative", nil
  elseif toBool(lease.blocked) and lease.reason == "relation" then
    return pageText(4109), "text_negative", nil
  elseif toBool(lease.closing) then
    return pageText(4110), "text_warning", nil
  elseif lease.docking ~= nil and not toBool(lease.docking) then
    return pageText(4111), "text_warning", nil
  end
  local text = string.format(pageText(4107), formatDuration((tonumber(lease.paidUntil) or now) - now))
  if cap and (tonumber(lease.fee) or 0) > cap then
    return text, "text_warning", pageText(4113)
  end
  return text, "text_normal", nil
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
  elseif event.kind == "toDormitory" or event.kind == "toStasis" then
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
    id = TOP_LEVEL_ID, name = ReadText(PAGE, 1), icon = "tlt_rescuerangers", shortcut = "",
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
  menu.confirmFrame = nil
  menu.confirmKeys = nil
  menu.peopleTable = nil
  menu.detailTable = nil
  menu.actionTable = nil
  menu.refreshQueued = nil
  menu.sliderActive = nil
  menu.filterActive = nil
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
  menu.stasis = menu.stasis or { selected = {}, filter = "", sort = "name", role = "service" }
  menu.stasis.wantCandidates = (menu.tab == "stasis")
  Helper.setTabScrollCallback(menu, menu.onTabScroll)
  menu.createFrame()
end

function menu.selectTab(id)
  if menu.tab == id then
    return
  end
  menu.tab = id
  menu.stasis.wantCandidates = (id == "stasis")
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
  menu.filterActive = nil
  menu.peopleTable = nil
  menu.detailTable = nil
  menu.actionTable = nil
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
  elseif menu.tab == "stasis" then
    menu.createStasisPanel(Helper.frameBorder, top, width, rangers)
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
    row[8]:createText(ranger.state, { halign = "left", color = Color[ranger.stateColor], mouseOverText = ranger.stateHint })
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
  local cols = 6
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 1, x = x, y = y, width = leftWidth, maxVisibleHeight = bottom - y })
  ftable:setColWidthPercent(2, 12)
  ftable:setColWidthPercent(3, 12)
  ftable:setColWidthPercent(4, 12)
  ftable:setColWidthPercent(5, 12)
  ftable:setColWidthPercent(6, 16)
  titleRow(ftable, cols, ReadText(1001, 2637))
  local rows = rowGroup(ftable)
  if not stats then
    noticeRow(rows, cols, ReadText(PAGE, 3059))
  else
    for _, counter in ipairs(COUNTERS) do
      local row = rows:addRow(true, {})
      row[1]:setColSpan(cols - 1):createText(ReadText(PAGE, counter.textId), { halign = "left" })
      row[cols]:createText(tostring(stats[counter.key] or 0), { halign = "right" })
    end
    local row = rows:addRow(false, { bgColor = Color["row_background_unselectable"] })
    row[1]:setColSpan(cols):createText(string.format(pageText(3046), formatAgo(C.GetCurrentGameTime() - (tonumber(stats.since) or 0))), { halign = "left", color = Color["text_inactive"] })
  end

  titleRow(ftable, cols, ReadText(PAGE, 3048))
  rows = rowGroup(ftable)
  headerRow(rows, { ReadText(1001, 5), ReadText(PAGE, 3012), ReadText(PAGE, 3015), ReadText(PAGE, 3066), ReadText(PAGE, 3016), ReadText(PAGE, 3049) },
    { "left", "right", "right", "right", "right", "right" })
  local now = C.GetCurrentGameTime()
  local listed = {}
  local rowOf = {}
  local function statsRow(label, entry, idcode)
    local row = rows:addRow({ "ranger", idcode }, {})
    rowOf[idcode] = row.index
    row[1]:createText(label, { halign = "left" })
    row[2]:createText(tostring(entry and entry.rescued or 0), { halign = "right" })
    row[3]:createText(tostring(entry and entry.toDormitory or 0), { halign = "right" })
    row[4]:createText(tostring(entry and entry.toStasis or 0), { halign = "right" })
    row[5]:createText(tostring(entry and entry.joinedCrew or 0), { halign = "right" })
    local last = entry and tonumber(entry.last) or 0
    row[6]:createText((last > 0) and formatAgo(now - last) or "-", { halign = "right" })
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

-- Options of the per-ship Stasis dropdown; ids are the order param values.
local function stasisModeOptions()
  local default = string.format("%s (%s)", ReadText(1001, 3231), stasisModeText(rr.cfg.stasisMode))
  local options = {}
  for value, text in ipairs({ default, ReadText(1001, 7726), pageText(4050), pageText(4051) }) do
    options[value] = { id = tostring(value - 1), text = text, icon = "", displayremoveoption = false, mouseovertext = text }
  end
  return options
end

function menu.createSettingsPanel(x, y, width, rangers)
  local bottom = buttonBar(x, width)
  local cols = 7
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 1, x = x, y = y, width = width, maxVisibleHeight = bottom - y })
  ftable:setColWidthPercent(2, 10)
  ftable:setColWidthPercent(3, 12)
  ftable:setColWidthPercent(4, 12)
  ftable:setColWidthPercent(5, 12)
  ftable:setColWidthPercent(6, 12)
  ftable:setColWidthPercent(7, 16)
  titleRow(ftable, cols, ReadText(1001, 2679))
  local rows = rowGroup(ftable)
  headerRow(rows, { ReadText(1001, 5), ReadText(PAGE, 104), ReadText(PAGE, 105), ReadText(PAGE, 106), ReadText(PAGE, 107), ReadText(PAGE, 109), ReadText(PAGE, 4000) },
    { "left", "left", "center", "center", "center", "center", "left" })
  if #rangers == 0 then
    noticeRow(rows, cols, ReadText(PAGE, 3056))
  end
  local size = Helper.scaleX(Helper.standardTextHeight)
  local inset = rr.isV9 and Helper.standardContainerOffset or 0
  local boxX = math.max(0, math.floor((width * 0.12 - inset - size) / 2))
  local rowOf = {}
  menu.createSettingsAllRow(rows, rangers, size, boxX)
  for _, ranger in ipairs(rangers) do
    local row = rows:addRow({ "ranger", ranger.idcode }, {})
    rowOf[ranger.idcode] = row.index
    local label = string.format("%s (%s)", ranger.name, ranger.idcode)
    if ranger.mode == "mimic" then
      row[1]:createText("   " .. label, { halign = "left", mouseOverText = ReadText(PAGE, 3057) })
      row[2]:setColSpan(6):createText(string.format(pageText(3017), string.format("%s (%s)", ranger.commander.name, ranger.commander.idcode)), { halign = "left", color = Color["text_inactive"] })
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
      row[7]:createDropDown(stasisModeOptions(), { startOption = tostring(ranger.stasisMode), height = Helper.standardTextHeight, mouseOverText = ReadText(PAGE, 3058) })
      row[7].handlers.onDropDownConfirmed = function(_, id) return menu.setParam(ranger.id64, P.stasisMode, math.floor(tonumber(id) or 0)) end
    end
  end
  restoreRows(ftable, "settings", rowOf)
end

-- One row for every Rescue ship at once; a checkbox is on only when it is on for all of them.
function menu.createSettingsAllRow(rows, rangers, size, boxX)
  local main = {}
  for _, ranger in ipairs(rangers) do
    if ranger.mode ~= "mimic" then
      main[#main + 1] = ranger
    end
  end
  if #main < 2 then
    return
  end
  local mouseOver = ReadText(PAGE, 3063)
  local row = rows:addRow({ "all" }, {})
  row[1]:createText(ReadText(PAGE, 3019), { halign = "left", font = Helper.standardFontBold, mouseOverText = mouseOver })

  local max, common = 0, main[1].range
  for _, ranger in ipairs(main) do
    max = math.max(max, rangeMax(ranger.piloting), ranger.range)
    if ranger.range ~= common then
      common = nil
    end
  end
  if max > 0 then
    local options = {}
    for value = 0, max do
      options[#options + 1] = { id = tostring(value), text = tostring(value), icon = "", displayremoveoption = false }
    end
    row[2]:createDropDown(options, { startOption = common and tostring(common) or "", textOverride = common and "" or "-", height = Helper.standardTextHeight, mouseOverText = mouseOver })
    row[2].handlers.onDropDownConfirmed = function(_, id)
      local value = math.floor(tonumber(id) or 0)
      return menu.setParamAll(P.range, function(ranger)
        local target = math.min(value, math.max(rangeMax(ranger.piloting), ranger.range))
        if ranger.range ~= target then
          return target
        end
      end)
    end
  else
    row[2]:createText("0", { halign = "left", color = Color["text_inactive"], mouseOverText = ReadText(PAGE, 3018) })
  end

  for col, key in pairs({ [3] = "oxygen", [4] = "getThemBack", [5] = "joinCrew", [6] = "logbook" }) do
    local allOn = true
    for _, ranger in ipairs(main) do
      allOn = allOn and ranger[key] == true
    end
    row[col]:createCheckBox(allOn, { width = size, height = size, scaling = false, x = boxX, mouseOverText = mouseOver })
    row[col].handlers.onClick = function(_, checked)
      local on = toBool(checked)
      return menu.setParamAll(P[key], function(ranger)
        if ranger[key] ~= on then
          return on
        end
      end)
    end
  end

  local mode = main[1].stasisMode
  for _, ranger in ipairs(main) do
    if ranger.stasisMode ~= mode then
      mode = nil
      break
    end
  end
  row[7]:createDropDown(stasisModeOptions(), { startOption = mode and tostring(mode) or "", textOverride = mode and "" or "-", height = Helper.standardTextHeight, mouseOverText = mouseOver })
  row[7].handlers.onDropDownConfirmed = function(_, id)
    local value = math.floor(tonumber(id) or 0)
    return menu.setParamAll(P.stasisMode, function(ranger)
      if ranger.stasisMode ~= value then
        return value
      end
    end)
  end
end

function menu.setParam(id64, index, value)
  menu.sliderActive = nil
  local ok = applyParams(id64, { [index] = value })
  if not ok then
    debugLog("settings: param %d of %s not applied.", index, tostring(id64))
  end
  menu.refreshQueued = true
end

-- `valueOf(ranger)` gives the new value, or nil to leave that ship alone; read fresh, the tab does not auto-refresh.
function menu.setParamAll(index, valueOf)
  menu.sliderActive = nil
  local applied, failed = 0, 0
  for _, ranger in ipairs(collectRangers()) do
    if ranger.mode ~= "mimic" then
      local value = valueOf(ranger)
      if value ~= nil then
        if applyParams(ranger.id64, { [index] = value }) then
          applied = applied + 1
        else
          failed = failed + 1
        end
      end
    end
  end
  debugLog("settings: param %d for all: %d applied, %d not applied.", index, applied, failed)
  menu.refreshQueued = true
end

-- *** Stasis tab: not on the refresh timer, rebuilt on RescueRangers.StasisChanged ***

local function sendStasis(control, param)
  debugLog("stasis: %s sent.", control)
  AddUITriggeredEvent("RescueRangers.Stasis", control, param)
end

function menu.requestCandidates(rangers, force)
  local now = getElapsedTime()
  if not force then
    if menu.stasis.askedAt and now - menu.stasis.askedAt < config.candidatesRetry then
      return
    end
    local data = readStasis()
    local at = tonumber(data and data.candidatesAt) or -1
    if at >= 0 and C.GetCurrentGameTime() - at < config.candidatesStale then
      return
    end
  end
  menu.stasis.askedAt = now
  local from = candidateSources(rangers)
  traceLog("stasis: candidates asked, measured from %d places, forced %s.", #from, tostring(force == true))
  sendStasis("Candidates", { from = from })
end

function menu.createStasisPanel(x, y, width, rangers)
  local bottom = buttonBar(x, width)
  local state = menu.stasis
  if state.wantCandidates then
    state.wantCandidates = nil
    menu.requestCandidates(rangers, false)
  end
  local data = readStasis()
  local leftWidth = math.floor(width * 0.55)
  local rightX = x + leftWidth + Helper.borderSize
  local rightWidth = width - leftWidth - Helper.borderSize

  -- Selection and the current person only ever refer to shown records.
  local people = stasisPeople(data, state)
  local shown = {}
  for _, person in ipairs(people) do
    shown[person.key] = person
  end
  for key in pairs(state.selected) do
    if not shown[key] then
      state.selected[key] = nil
    end
  end
  if state.current ~= nil and not shown[state.current] then
    state.current = nil
  end
  menu.stasisShown = shown

  local controlsBottom = menu.createStasisControls(x, y, leftWidth)
  local actionsTop = menu.createStasisActions(x, bottom, leftWidth, #people)
  menu.createStasisPeople(x, controlsBottom + Helper.borderSize, leftWidth, actionsTop - Helper.borderSize, data, people)

  local detailBottom = menu.createStasisDetail(rightX, y, rightWidth)
  local rentTop = menu.createStasisRent(rightX, detailBottom + Helper.borderSize, bottom, rightWidth, data)
  menu.createStasisLocations(rightX, detailBottom + Helper.borderSize, rentTop - Helper.borderSize, rightWidth, data)
end

-- Filter, sort and role; returns the y under the table.
function menu.createStasisControls(x, y, width)
  local state = menu.stasis
  local cols = 3
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 1, x = x, y = y, width = width, reserveScrollBar = false })
  ftable:setColWidthPercent(2, 25)
  ftable:setColWidthPercent(3, 25)
  titleRow(ftable, cols, ReadText(PAGE, 4000))
  local row = ftable:addRow(true, { fixed = true })
  row[1]:createEditBox({ defaultText = ReadText(1001, 3250), height = Helper.standardTextHeight }):setText(state.filter, { halign = "left", x = Helper.standardTextOffsetx })
  row[1].handlers.onEditBoxActivated = function() menu.filterActive = true end
  row[1].handlers.onEditBoxDeactivated = function(_, text)
    menu.filterActive = nil
    if text ~= state.filter then
      state.filter = text
      menu.refreshQueued = true
    end
  end
  local sorts = {}
  for _, sort in ipairs(SORTS) do
    sorts[#sorts + 1] = { id = sort.id, text = sort.text(), icon = "", displayremoveoption = false }
  end
  row[2]:createDropDown(sorts, { startOption = state.sort, height = Helper.standardTextHeight, mouseOverText = ReadText(1001, 2906) })
  row[2].handlers.onDropDownConfirmed = function(_, id)
    if id ~= state.sort then
      state.sort = id
      menu.refreshQueued = true
    end
  end
  local roles = {}
  for _, role in ipairs(ROLES) do
    roles[#roles + 1] = { id = role.id, text = role.text(), icon = "", displayremoveoption = false }
  end
  row[3]:createDropDown(roles, { startOption = state.role, height = Helper.standardTextHeight, mouseOverText = ReadText(PAGE, 4131) })
  row[3].handlers.onDropDownConfirmed = function(_, id)
    if id ~= state.role then
      state.role = id
      state.target = nil
      menu.refreshQueued = true
    end
  end
  return ftable.properties.y + ftable:getFullHeight()
end

-- No row group: its interplay with GetSelectedRows is unknown.
function menu.createStasisPeople(x, y, width, bottomY, data, people)
  local state = menu.stasis
  local role = roleOf(state.role)
  local cols = 5
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 2, x = x, y = y, width = width, maxVisibleHeight = bottomY - y, multiSelect = true })
  ftable:setColWidthPercent(2, 14)
  ftable:setColWidthPercent(3, 16)
  ftable:setColWidthPercent(4, 16)
  ftable:setColWidthPercent(5, 26)
  headerRow(ftable, { ReadText(1001, 2809), role.text(), ReadText(PAGE, 4101), ReadText(PAGE, 4102), ReadText(1001, 2943) })
  menu.peopleTable = ftable
  menu.peopleRowKey = {}
  menu.peopleRowOf = {}
  menu.peopleOrder = {}
  if #people == 0 then
    noticeRow(ftable, cols, ReadText(PAGE, (#((data and data.people) or {}) > 0) and 4106 or 4100))
  end
  local now = C.GetCurrentGameTime()
  for _, person in ipairs(people) do
    local key = person.key
    local row = ftable:addRow({ "person", key }, { multiSelected = state.selected[key] == true })
    menu.peopleRowKey[row.index] = key
    menu.peopleRowOf[key] = row.index
    menu.peopleOrder[#menu.peopleOrder + 1] = key
    row[1]:createText(textOf(person.name), { halign = "left" })
    row[2]:createText(potentialStars(person[role.skill]), { halign = "left" })
    row[3]:createText(textOf(person.lostShip), { halign = "left" })
    row[4]:createText(formatAgo(now - (tonumber(person.since) or now)), { halign = "left" })
    row[5]:createText(textOf(person.stationName), { halign = "left" })
  end
  if state.current ~= nil and menu.peopleRowOf[state.current] then
    ftable:setSelectedRow(menu.peopleRowOf[state.current])
  end
  if menu.topRows.stasis then
    ftable:setTopRow(menu.topRows.stasis)
  end
end

local function selectedCountText()
  local count = 0
  for _ in pairs(menu.stasis.selected) do
    count = count + 1
  end
  return string.format("%s: %d", ReadText(1001, 17), count)
end

-- Selected keys in list order; one person for a pilot or manager, the current one when selected.
local function selectedKeys(single)
  local state = menu.stasis
  if single and state.current ~= nil and state.selected[state.current] then
    return { state.current }
  end
  local keys = {}
  for _, key in ipairs(menu.peopleOrder or {}) do
    if state.selected[key] then
      keys[#keys + 1] = key
      if single then
        break
      end
    end
  end
  return keys
end

-- Target, Assign, Dismiss, Select all, the count; placed above bottomY, returns its top.
function menu.createStasisActions(x, bottomY, width, peopleCount)
  local state = menu.stasis
  local cols = 5
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 3, x = x, y = 0, width = width, reserveScrollBar = false })
  ftable:setColWidthPercent(2, 13)
  ftable:setColWidthPercent(3, 13)
  ftable:setColWidthPercent(4, 13)
  ftable:setColWidthPercent(5, 15)
  local row = ftable:addRow(true, { fixed = true })
  local options, valid = {}, {}
  for _, target in ipairs(assignTargets(state.role)) do
    local id = tostring(target.id64)
    local text = string.format(pageText(4130), target.label, target.free)
    if target.managerName then
      text = string.format(pageText(4133), target.label, target.free, target.managerName, target.managerStars)
    end
    options[#options + 1] = { id = id, text = text, icon = "", displayremoveoption = false }
    valid[id] = true
  end
  if not (state.target and valid[state.target]) then
    state.target = options[1] and options[1].id or nil
  end
  local none = (state.role == "manager") and 4129 or 4128
  row[1]:createDropDown(options, {
    startOption = state.target or "", textOverride = (#options == 0) and ReadText(PAGE, none) or nil,
    active = #options > 0, height = Helper.standardTextHeight, mouseOverText = ReadText(PAGE, (state.role == "manager") and 4134 or 4127),
  })
  row[1].handlers.onDropDownConfirmed = function(_, id) state.target = id end
  row[2]:createButton({ active = #options > 0 and peopleCount > 0 }):setText(ReadText(1001, 3263), { halign = "center" })
  row[2].handlers.onClick = function() return menu.buttonAssign() end
  row[3]:createButton({ active = peopleCount > 0 }):setText(ReadText(1001, 12891), { halign = "center" })
  row[3].handlers.onClick = function() return menu.buttonDismiss() end
  row[4]:createButton({ active = peopleCount > 0 }):setText(ReadText(PAGE, 4126), { halign = "center" })
  row[4].handlers.onClick = function() return menu.buttonSelectAll() end
  row[5]:createText(selectedCountText(), { halign = "right" })
  menu.actionTable = ftable
  menu.countCell = { row.index, 5 }
  ftable.properties.y = bottomY - ftable:getFullHeight()
  return ftable.properties.y
end

-- Texts of the detail panel for a record, or its empty state.
local function detailTexts(person)
  local texts = { title = person and textOf(person.name) or ReadText(PAGE, 4000) }
  for _, skill in ipairs(SKILLS) do
    texts[skill.key] = person and Helper.displaySkill(tonumber(person[skill.key]) or 0) or "-"
  end
  for _, role in ipairs(ROLES) do
    texts[role.skill] = person and potentialStars(person[role.skill]) or "-"
  end
  texts.lostShip = person and textOf(person.lostShip) or "-"
  texts.ranger = person and rangerLabel(person) or "-"
  texts.since = person and formatAgo(C.GetCurrentGameTime() - (tonumber(person.since) or 0)) or "-"
  texts.location = person and textOf(person.stationName) or "-"
  return texts
end

-- The current person; updated in place on a row change, never rebuilt. Returns the y under it.
function menu.createStasisDetail(x, y, width)
  local state = menu.stasis
  local person = (state.current ~= nil) and menu.stasisShown[state.current] or nil
  local texts = detailTexts(person)
  local cols = 4
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 4, x = x, y = y, width = width, reserveScrollBar = false, highlightMode = "off" })
  ftable:setColWidthPercent(1, 22)
  ftable:setColWidthPercent(2, 28)
  ftable:setColWidthPercent(3, 22)
  local cells = {}
  cells.title = { titleRow(ftable, cols, texts.title).index, 1 }
  local row = ftable:addRow(false, { bgColor = Color["row_title_background"] })
  row[1]:setColSpan(2):createText(ReadText(1001, 1918), { halign = "left", font = Helper.standardFontBold })
  row[3]:setColSpan(2):createText(ReadText(PAGE, 4132), { halign = "left", font = Helper.standardFontBold })
  for i, skill in ipairs(SKILLS) do
    row = ftable:addRow(false, {})
    row[1]:createText(ReadText(1013, skill.textId), { halign = "left" })
    row[2]:createText(texts[skill.key], { halign = "left" })
    cells[skill.key] = { row.index, 2 }
    local role = ROLES[i]
    if role then
      row[3]:createText(role.text(), { halign = "left" })
      row[4]:createText(texts[role.skill], { halign = "left" })
      cells[role.skill] = { row.index, 4 }
    end
  end
  for _, info in ipairs({
    { key = "lostShip", label = ReadText(PAGE, 4101) },
    { key = "ranger",   label = ReadText(PAGE, 4103) },
    { key = "since",    label = ReadText(PAGE, 4102) },
    { key = "location", label = ReadText(1001, 2943) },
  }) do
    row = ftable:addRow(false, {})
    row[1]:createText(info.label, { halign = "left" })
    row[2]:setColSpan(3):createText(texts[info.key], { halign = "left" })
    cells[info.key] = { row.index, 2 }
  end
  menu.detailTable = ftable
  menu.detailCells = cells
  return ftable.properties.y + ftable:getFullHeight()
end

function menu.updateStasisDetail()
  if not (menu.detailTable and menu.detailTable.id and menu.detailCells) then
    return
  end
  local state = menu.stasis
  local texts = detailTexts((state.current ~= nil) and menu.stasisShown[state.current] or nil)
  for key, cell in pairs(menu.detailCells) do
    Helper.updateCellText(menu.detailTable.id, cell[1], cell[2], texts[key] or "-")
  end
end

function menu.updateStasisAges()
  if not (menu.peopleTable and menu.peopleTable.id and menu.peopleRowKey and menu.stasisShown) then
    return
  end
  local now = C.GetCurrentGameTime()
  for rowIndex, key in pairs(menu.peopleRowKey) do
    local person = menu.stasisShown[key]
    if person then
      Helper.updateCellText(menu.peopleTable.id, rowIndex, 4, formatAgo(now - (tonumber(person.since) or now)))
    end
  end
  menu.updateStasisDetail()
end

function menu.updateStasisCount()
  if menu.actionTable and menu.actionTable.id and menu.countCell then
    Helper.updateCellText(menu.actionTable.id, menu.countCell[1], menu.countCell[2], selectedCountText())
  end
end

local function leasedStations(data)
  local leased = {}
  for _, lease in ipairs((data and data.leases) or {}) do
    leased[tostring(componentOf(lease.station))] = true
  end
  return leased
end

-- Player stations holding our people, then every lease, each with an End lease button.
function menu.createStasisLocations(x, y, bottomY, width, data)
  local cols = 6
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 5, x = x, y = y, width = width, maxVisibleHeight = bottomY - y })
  ftable:setColWidthPercent(2, 18)
  ftable:setColWidthPercent(3, 9)
  ftable:setColWidthPercent(4, 9)
  ftable:setColWidthPercent(5, 22)
  ftable:setColWidthPercent(6, 14)
  titleRow(ftable, cols, ReadText(PAGE, 4104))
  local rows = rowGroup(ftable)
  headerRow(rows, { ReadText(1001, 3), ReadText(1001, 9040), ReadText(1001, 47), ReadText(PAGE, 4105), ReadText(1001, 12), "" },
    { "left", "left", "right", "right", "left", "left" })

  local counts, order = {}, {}
  for _, person in ipairs((data and data.people) or {}) do
    local id64 = componentOf(person.station)
    local key = tostring(id64)
    if not counts[key] then
      order[#order + 1] = id64
    end
    counts[key] = (counts[key] or 0) + 1
  end
  local free = {}
  for _, place in ipairs((data and data.places) or {}) do
    free[tostring(componentOf(place.station))] = math.floor(tonumber(place.free) or 0)
  end
  local leased = leasedStations(data)

  local listed = 0
  for _, id64 in ipairs(order) do
    local key = tostring(id64)
    if not leased[key] and isAlive(id64) then
      local row = rows:addRow({ "location", key }, {})
      row[1]:createText(shipLabel(id64), { halign = "left" })
      row[2]:createText(tostring(GetComponentData(luaId(id64), "ownername")), { halign = "left" })
      row[3]:createText(tostring(counts[key]), { halign = "right" })
      row[4]:createText(tostring(free[key] or 0), { halign = "right" })
      listed = listed + 1
    end
  end

  local now = C.GetCurrentGameTime()
  local percent = tonumber(rr.cfg.stasisAutoRentPercent) or 0
  local cap = (percent > 0) and (GetPlayerMoney() * percent / 100) or nil
  for _, lease in ipairs((data and data.leases) or {}) do
    local key = tostring(componentOf(lease.station))
    local count = counts[key] or 0
    local status, color, mouseOver = leaseStatus(lease, now, cap)
    local row = rows:addRow({ "location", key }, {})
    row[1]:createText(textOf(lease.stationName), { halign = "left" })
    row[2]:createText(textOf(lease.ownerName), { halign = "left" })
    if count == 0 then
      row[3]:createText("0", { halign = "right", color = Color["text_warning"], mouseOverText = ReadText(PAGE, 4112) })
    else
      row[3]:createText(tostring(count), { halign = "right" })
    end
    row[4]:createText(free[key] and tostring(free[key]) or "-", { halign = "right" })
    row[5]:createText(status, { halign = "left", color = Color[color], mouseOverText = mouseOver })
    row[6]:createButton({ active = not toBool(lease.closing) }):setText(ReadText(PAGE, 4114), { halign = "center" })
    row[6].handlers.onClick = function() return sendStasis("EndLease", { station = lease.station }) end
    listed = listed + 1
  end
  if listed == 0 then
    noticeRow(rows, cols, ReadText(PAGE, 4124))
  end
end

-- Fee, auto-rent, the candidates and the order's proposals; placed above bottomY, at most
-- half the space from topY down. Returns its top.
function menu.createStasisRent(x, topY, bottomY, width, data)
  local state = menu.stasis
  local cols = 4
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 6, x = x, y = topY, width = width, maxVisibleHeight = math.floor((bottomY - topY) / 2) })
  ftable:setColWidthPercent(3, 16)
  ftable:setColWidthPercent(4, 20)
  titleRow(ftable, cols, ReadText(PAGE, 4115))
  local rows = rowGroup(ftable)
  local row = rows:addRow(false, {})
  row[1]:setColSpan(cols):createText(string.format(pageText(4116), formatMoney(data and data.rentFee)), { halign = "left", wordwrap = true })
  local percent = tonumber(rr.cfg.stasisAutoRentPercent) or 0
  row = rows:addRow(false, {})
  row[1]:setColSpan(cols):createText((percent > 0) and string.format(pageText(4117), math.floor(percent)) or pageText(4118),
    { halign = "left", wordwrap = true, color = Color["text_inactive"] })

  local leased = leasedStations(data)
  local options, byId = {}, {}
  for _, candidate in ipairs((data and data.candidates) or {}) do
    local id = tostring(componentOf(candidate.station))
    if not leased[id] then
      local text = candidateText(candidate)
      options[#options + 1] = { id = id, text = text, icon = "", displayremoveoption = false, mouseovertext = text }
      byId[id] = candidate
    end
  end
  if not (state.candidate and byId[state.candidate]) then
    state.candidate = options[1] and options[1].id or nil
  end
  row = rows:addRow(true, {})
  row[1]:setColSpan(2):createDropDown(options, {
    startOption = state.candidate or "", textOverride = (#options == 0) and ReadText(PAGE, 4122) or nil,
    active = #options > 0, height = Helper.standardTextHeight,
  })
  row[1].handlers.onDropDownConfirmed = function(_, id) state.candidate = id end
  row[3]:createButton({ active = #options > 0 }):setText(ReadText(PAGE, 4119), { halign = "center" })
  row[3].handlers.onClick = function()
    local candidate = state.candidate and byId[state.candidate]
    if candidate then
      return sendStasis("Rent", { station = candidate.station })
    end
  end
  row[4]:createButton({}):setText(ReadText(PAGE, 4120), { halign = "center" })
  row[4].handlers.onClick = function() return menu.requestCandidates(collectRangers(), true) end

  for _, proposal in ipairs((data and data.proposals) or {}) do
    row = rows:addRow(true, {})
    local ranger = string.format("%s (%s)", textOf(proposal.rangerName), textOf(proposal.ranger))
    row[1]:setColSpan(3):createText(string.format(pageText(4123), ranger, math.floor(tonumber(proposal.need) or 0), candidateText(proposal)),
      { halign = "left", wordwrap = true, color = Color["text_warning"] })
    row[4]:createButton({}):setText(ReadText(PAGE, 4119), { halign = "center" })
    row[4].handlers.onClick = function() return sendStasis("Rent", { station = proposal.station }) end
  end

  ftable.properties.y = bottomY - ftable:getVisibleHeight()
  return ftable.properties.y
end

function menu.buttonAssign()
  local state = menu.stasis
  local keys = selectedKeys(state.role == "pilot" or state.role == "manager")
  if #keys == 0 or not state.target then
    traceLog("stasis: assign skipped, %d selected, target %s.", #keys, tostring(state.target))
    return
  end
  debugLog("stasis: assign %d as %s to %s.", #keys, state.role, tostring(state.target))
  sendStasis("Assign", { keys = keys, target = luaId(state.target), role = state.role })
end

function menu.buttonDismiss()
  local keys = selectedKeys(false)
  if #keys > 0 then
    menu.openConfirm(keys)
  end
end

function menu.buttonSelectAll()
  ---@type integer[]
  local rows = {}
  local selected = {}
  for _, key in ipairs(menu.peopleOrder or {}) do
    rows[#rows + 1] = menu.peopleRowOf[key]
    selected[key] = true
  end
  if #rows == 0 or not (menu.peopleTable and menu.peopleTable.id) then
    return
  end
  menu.stasis.selected = selected
  local firstRow = rows[1] or 0
  local currentRow = (menu.stasis.current ~= nil) and menu.peopleRowOf[menu.stasis.current] or nil
  SetSelectedRows(menu.peopleTable.id, rows, currentRow or firstRow)
  menu.updateStasisCount()
end

-- Dismiss confirmation, a frame on the context layer; Cancel is preselected.
function menu.openConfirm(keys)
  menu.closeConfirm()
  menu.confirmKeys = keys
  local width = Helper.scaleX(config.confirmWidth)
  local frame = Helper.createFrameHandle(menu, {
    layer = config.contextLayer, standardButtons = { close = true }, width = width, autoFrameHeight = true,
    x = math.floor((Helper.viewWidth - width) / 2), y = math.floor(Helper.viewHeight / 3),
  })
  frame:setBackground("solid", { color = Color["frame_background_semitransparent"] })
  local ftable = frame:addTable(2, { tabOrder = 1, x = Helper.borderSize, y = Helper.borderSize, width = width - 2 * Helper.borderSize, reserveScrollBar = false })
  titleRow(ftable, 2, ReadText(1001, 12891))
  local row = ftable:addRow(false, {})
  row[1]:setColSpan(2):createText(string.format(pageText(4125), #keys), { halign = "left", wordwrap = true })
  row = ftable:addRow(true, {})
  row[1]:createButton({}):setText(ReadText(1001, 2821), { halign = "center" })
  row[1].handlers.onClick = function() return menu.confirmDismiss() end
  row[2]:createButton({}):setText(ReadText(1001, 64), { halign = "center" })
  row[2].handlers.onClick = function() return menu.closeConfirm() end
  ftable:setSelectedRow(row.index)
  ftable:setSelectedCol(2)
  menu.confirmFrame = frame
  frame:display()
end

function menu.closeConfirm()
  menu.confirmKeys = nil
  if menu.confirmFrame then
    menu.confirmFrame = nil
    Helper.clearFrame(menu, config.contextLayer)
  end
end

function menu.confirmDismiss()
  local keys = menu.confirmKeys
  menu.closeConfirm()
  if keys and #keys > 0 then
    debugLog("stasis: dismiss %d.", #keys)
    sendStasis("Dismiss", { keys = keys })
  end
end

local function onStasisChanged()
  if menu.open and menu.tab == "stasis" then
    menu.refreshQueued = true
  end
end

local function selectOnMap(id64, tries)
  local map = Helper.getMenu("MapMenu")
  if map ~= nil and map.shown and map.holomap ~= nil and map.holomap ~= 0 then
    map.addSelectedComponent(id64)
  elseif tries > 0 then
    Helper.addDelayedOneTimeCallbackOnUpdate(function() selectOnMap(id64, tries - 1) end, false, getElapsedTime() + config.mapSelectRetry)
  end
end

-- The selected Rescue ship, or on the Stasis tab the current person's station.
local function selectedObject()
  if menu.tab == "stasis" then
    local current = menu.stasis.current
    local person = (current ~= nil) and menu.stasisShown and menu.stasisShown[current]
    local id64 = person and componentOf(person.station) or 0
    return isAlive(id64) and id64 or nil
  end
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
  local id64 = selectedObject()
  if not id64 then
    return
  end
  traceLog("showOnMap: %s.", ffi.string(C.GetObjectIDCode(id64)))
  Helper.closeMenuAndOpenNewMenu(menu, "MapMenu", { 0, 0, true, id64 })
  menu.cleanup()
  Helper.addDelayedOneTimeCallbackOnUpdate(function() selectOnMap(id64, config.mapSelectTries) end, false, getElapsedTime() + config.mapSelectRetry)
end

-- A multiselect table re-reports its row on redraws: a person row only updates cells in place.
function menu.onRowChanged(_row, rowdata, uitable)
  if type(rowdata) ~= "table" then
    return
  end
  if rowdata[1] == "ranger" then
    menu.selected[menu.tab] = rowdata[2]
    menu.topRows[menu.tab] = GetTopRow(uitable)
  elseif rowdata[1] == "person" then
    local state = menu.stasis
    state.current = rowdata[2]
    menu.topRows.stasis = GetTopRow(uitable)
    local selected = {}
    for _, row in ipairs(GetSelectedRows(uitable) or {}) do
      local key = menu.peopleRowKey and menu.peopleRowKey[row]
      if key ~= nil then
        selected[key] = true
      end
    end
    state.selected = selected
    menu.updateStasisDetail()
    menu.updateStasisCount()
  end
end

function menu.onSelectElement(uitable, _modified, _row, isdblclick, input)
  if isdblclick or input ~= "mouse" then
    local rowdata = Helper.getCurrentRowData(menu, uitable)
    if type(rowdata) == "table" and rowdata[1] == "ranger" and menu.tab ~= "settings" then
      menu.selected[menu.tab] = rowdata[2]
      menu.buttonShowOnMap()
    elseif type(rowdata) == "table" and rowdata[1] == "person" then
      menu.stasis.current = rowdata[2]
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
  if menu.refreshQueued and not menu.filterActive then
    menu.refreshQueued = nil
    return menu.createFrame()
  end
  if menu.open and menu.tab ~= "settings" and getElapsedTime() - menu.lastRefreshTime >= config.refreshInterval then
    if menu.tab ~= "stasis" then
      return menu.createFrame()
    end
    menu.lastRefreshTime = getElapsedTime()
    menu.updateStasisAges()
  end
  if menu.infoFrame then
    menu.infoFrame:update()
  end
  if menu.confirmFrame then
    menu.confirmFrame:update()
  end
end

-- A third argument means the view is already gone: never refuse that close.
function menu.onCloseElement(dueToClose, _layer, forced)
  if menu.confirmFrame and not forced then
    menu.closeConfirm()
    return
  end
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
  RegisterEvent("RescueRangers.StasisChanged", onStasisChanged)
end

Register_OnLoad_Init(Init)
