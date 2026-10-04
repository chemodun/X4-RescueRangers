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
  contextWidth    = 260, -- vanilla InteractMenu width, as the map's person context
  mouseOutRange   = 100, -- the person context closes once the mouse is this far outside it, as vanilla Personnel
  getThemBackTtl  = 1800, -- seconds $RRGetThemBackEnabled stays valid, as md/rr_getthemback.xml checks it
}

local TABS = {
  { id = "rangers",  icon = "tlt_rescuerangers",      name = function() return ReadText(PAGE, 3001) end },
  { id = "stats",    icon = "pi_statistics",          name = function() return ReadText(1001, 2500) end },
  { id = "stasis",   icon = "pi_personnelmanagement", name = function() return ReadText(PAGE, 3012) end },
  { id = "settings", icon = "mapst_standing_orders",  name = function() return ReadText(1001, 2679) end },
}

-- Suitability roles; `skill` is the potential skill field of a person (0-100), `role`/`post` its GetPersonCombinedSkill args.
local ROLES = {
  { id = "service", skill = "asService", role = "service", text = function() return ReadText(20208, 20103) end },
  { id = "marine",  skill = "asMarine",  role = "marine",  text = function() return ReadText(20208, 20203) end },
  { id = "pilot",   skill = "asPilot",   post = "aipilot", text = function() return ReadText(1001, 4847) end },
  { id = "manager", skill = "asManager", post = "manager", text = function() return ReadText(20208, 30301) end },
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
  { key = "pickedUp",    textId = 3079 },
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
  { key = "pickedUp", textId = 3079, color = "graph_data_7" },
  { key = "returned", textId = 3045, color = "graph_data_6" },
}
local GRAPH_HOURS = 24
local Y_STEPS = { 1, 2, 5, 10, 20, 50, 100, 200, 500 }
local EVENT_TEXT = { rescued = 3050, ejected = 3051, lost = 3052, toDormitory = 3053, joinedCrew = 3054, returned = 3055, toStasis = 3065, pickedUp = 3080 }
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

-- Crew on board (the pilot not counted), the crew capacity and the unassigned (rescued not yet moved).
local function crewOf(id64)
  if not isAlive(id64) then
    return 0, 0, 0
  end
  local capacity = C.GetPeopleCapacity(id64, "", false)
  local numroles = C.GetNumAllRoles()
  local count, unassigned = 0, 0
  if numroles > 0 then
    local buf = ffi.new("PeopleInfo[?]", numroles)
    local n = C.GetPeople2(buf, numroles, id64, true)
    for i = 0, n - 1 do
      count = count + buf[i].amount
      if ffi.string(buf[i].id) == "unassigned" then
        unassigned = buf[i].amount
      end
    end
  end
  return count, capacity, unassigned
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

-- The Stasis mode a ship runs with: its order param, the Options mode for 0.
local function stasisModeOf(param)
  return (param == 2 and "overflow") or (param == 3 and "instead") or ((param == 0) and tostring(rr.cfg.stasisMode or "off")) or "off"
end

-- Rescued people the last Stasis pass found no place for (the order's pilot flag); 0 while Stasis is off.
local function stasisNoPlaceOf(pilot, stasisNow)
  if not pilot or (stasisNow ~= "overflow" and stasisNow ~= "instead") then
    return 0
  end
  return math.floor(tonumber(GetNPCBlackboard(ConvertIDTo64Bit(pilot), "$rescueRangersStasisNoPlace")) or 0)
end

-- The container a docked ship sits in, 0 while under way.
local function dockedAtOf(id64)
  if not GetComponentData(luaId(id64), "isdocked") then
    return 0
  end
  return ConvertStringTo64Bit(tostring(C.GetContextByClass(id64, "container", false)))
end

-- The station or ship the pilot's deepest command heads for, 0 for none.
local function headingToOf(pilot)
  local stack = pilot and GetComponentData(pilot, "aicommandstack") or {}
  for i = #stack, 1, -1 do
    local param = stack[i].param
    if param and IsComponentClass(param, "container") then
      return ConvertIDTo64Bit(param)
    end
  end
  return 0
end

-- The person a rescue flight is after and the sector the suit is in, from the order's pilot record.
local function rescueTargetOf(pilot)
  local data = pilot and GetNPCBlackboard(ConvertIDTo64Bit(pilot), "$rescueData")
  if type(data) ~= "table" then
    return nil, ""
  end
  local target = componentOf(data.target)
  return tostring(data.person or ""), isAlive(target) and sectorNameOf(target) or ""
end

local function readRanger(id64, settingsFrom)
  local params = GetOrderParams(luaId(settingsFrom), "default") or {}
  local function value(i)
    return params[i] and params[i].value
  end
  local station = componentOf(value(P.homeStation))
  local dormitory = componentOf(value(P.dormitory))
  local crew, capacity, unassigned = crewOf(id64)
  local dormCrew, dormCapacity = crewOf(dormitory)
  local stasisMode = math.floor(tonumber(value(P.stasisMode)) or 0)
  local stasisNow = stasisModeOf(stasisMode)
  local pilot = GetComponentData(luaId(id64), "assignedpilot")
  local rescuing = queuedOrder(id64, "RescueShip")
  local rescuePerson, rescueSector
  if rescuing then
    rescuePerson, rescueSector = rescueTargetOf(pilot)
  end
  local sectorId = GetComponentData(luaId(id64), "sectorid")
  return {
    id64         = id64,
    idcode       = ffi.string(C.GetObjectIDCode(id64)),
    name         = nameOf(id64),
    mode         = (station ~= 0) and "sector" or "fleet",
    sector       = sectorId and tostring(GetComponentData(sectorId, "name")) or "",
    sectorKey    = sectorId and tostring(ConvertIDTo64Bit(sectorId)) or "",
    sectorOwner  = sectorId and tostring(GetComponentData(sectorId, "owner") or "") or "",
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
    unassigned   = unassigned,
    dormCrew     = dormCrew,
    dormCapacity = dormCapacity,
    stasisNow    = stasisNow,
    noPlace      = stasisNoPlaceOf(pilot, stasisNow),
    rescuing     = rescuing,
    rescuePerson = rescuePerson,
    rescueSector = rescueSector,
    dockedAt     = dockedAtOf(id64),
    headingTo    = headingToOf(pilot),
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
  for _, value in ipairs({ person.name, person.lostShip, person.placeName, person.rangerName, person.ranger }) do
    if value ~= nil and value ~= 0 and string.find(string.lower(tostring(value)), filter, 1, true) then
      return true
    end
  end
  return false
end

-- Seeds and names of a station's unassigned people, read once per list build.
local function unassignedOn(station, cache)
  local key = tostring(station)
  if not cache[key] then
    local present = { seeds = {}, names = {} }
    if isAlive(station) then
      for _, npc in ipairs(GetRoleTierNPCs(station, "unassigned", 0) or {}) do
        present.seeds[tostring(npc.seed)] = true
        present.names[npc.name] = true
      end
    end
    cache[key] = present
  end
  return cache[key]
end

-- A record from before `$seed` matches by name.
local function recordOnStation(record, cache)
  local present = unassignedOn(componentOf(record.station), cache)
  if record.seed ~= nil then
    return present.seeds[tostring(record.seed)] == true
  end
  return present.names[record.name] == true
end

-- People Get-Them-Back still returns, "<container>|<name>" -> lost ship; none while no Rescue ship has it on.
local function readGetThemBack()
  local due = {}
  local enabled = tonumber(GetNPCBlackboard(rr.playerId, "$RRGetThemBackEnabled"))
  if not enabled or enabled + config.getThemBackTtl < C.GetCurrentGameTime() then
    return due
  end
  local list = GetNPCBlackboard(rr.playerId, "$RescueRangersGetThemBack")
  for _, entry in ipairs((type(list) == "table") and list or {}) do
    due[tostring(componentOf(entry.container)) .. "|" .. tostring(entry.name)] = textOf(entry.shipLabel or entry.shipId)
  end
  return due
end

local function recordPerson(record, due)
  local person = {}
  for key, value in pairs(record) do
    person[key] = value
  end
  person.recordKey = record.key
  person.seed = (record.seed ~= nil) and C.ConvertStringTo64Bit(tostring(record.seed)) or nil
  person.container = componentOf(record.station)
  person.name = textOf(record.name)
  person.placeName = textOf(record.stationName)
  person.due = due[tostring(person.container) .. "|" .. person.name]
  return person
end

-- An unassigned person aboard a ship, read live; `ranger` is the Rescue ship it is on, or nil.
local function shipPerson(ship, npc, ranger, due, skillBuf, numSkills)
  local seed = C.ConvertStringTo64Bit(tostring(npc.seed))
  local person = {
    key        = "s" .. tostring(ship) .. ":" .. tostring(npc.seed),
    container  = ship,
    seed       = seed,
    name       = tostring(npc.name),
    placeName  = shipLabel(ship),
    ranger     = ranger and ranger.idcode,
    rangerName = ranger and ranger.name,
    rangerId   = ranger and ranger.id64,
  }
  for i = 0, C.GetPersonSkills3(skillBuf, numSkills, seed, ship) - 1 do
    person[ffi.string(skillBuf[i].id)] = skillBuf[i].value
  end
  for _, role in ipairs(ROLES) do
    person[role.skill] = C.GetPersonCombinedSkill(ship, seed, role.role, role.post)
  end
  person.due = due[tostring(ship) .. "|" .. person.name]
  person.lostShip = person.due
  return person
end

-- Every rescued person: Stasis records still on their station (Upkeep drops the others within 60 s),
-- then the unassigned people aboard the Rescue ships and their Dormitories.
local function rescuedAll(data, rangers)
  local due = readGetThemBack()
  local all, onStation = {}, {}
  for _, record in ipairs((data and data.people) or {}) do
    if recordOnStation(record, onStation) then
      all[#all + 1] = recordPerson(record, due)
    end
  end
  local numSkills = C.GetNumSkills()
  local skillBuf = ffi.new("SkillInfo[?]", numSkills)
  local seen = {}
  local function addShip(id64, ranger)
    local key = tostring(id64)
    if seen[key] or not isAlive(id64) then
      return
    end
    seen[key] = true
    for _, npc in ipairs(GetRoleTierNPCs(id64, "unassigned", 0) or {}) do
      all[#all + 1] = shipPerson(id64, npc, ranger, due, skillBuf, numSkills)
    end
  end
  for _, ranger in ipairs(rangers) do
    addShip(ranger.id64, ranger)
  end
  for _, ranger in ipairs(rangers) do
    addShip(ranger.dormitory, nil)
  end
  return all
end

-- Changes when someone arrives, leaves or stops being due back; the list is rebuilt then.
local function rescuedSignature(all)
  local keys = {}
  for i, person in ipairs(all) do
    keys[i] = tostring(person.key) .. (person.due and "+" or "")
  end
  table.sort(keys)
  return table.concat(keys, ",")
end

-- The filtered and sorted rescued people.
local function rescuedPeople(all, state)
  local role = roleOf(state.role)
  local filter = string.lower(state.filter or "")
  local list = {}
  for _, person in ipairs(all) do
    if personMatches(person, filter) then
      local primary = ""
      if state.sort == "skill" then
        primary = string.format("%03d", 100 - math.floor(tonumber(person[role.skill]) or 0))
      elseif state.sort == "lostShip" then
        primary = (textOf(person.lostShip) ~= "-") and string.lower(tostring(person.lostShip)) or "\127"
      elseif state.sort == "since" then
        primary = person.since and string.format("%012d", math.floor(tonumber(person.since) or 0)) or "\127"
      elseif state.sort == "location" then
        primary = string.lower(person.placeName)
      end
      list[#list + 1] = { person = person, primary = primary, name = string.lower(person.name) }
    end
  end
  table.sort(list, function(a, b)
    if a.primary ~= b.primary then
      return a.primary < b.primary
    elseif a.name ~= b.name then
      return a.name < b.name
    end
    local ka, kb = a.person.key, b.person.key
    if type(ka) == type(kb) then
      return ka < kb
    end
    return type(ka) == "number"
  end)
  local people = {}
  for i, entry in ipairs(list) do
    people[i] = entry.person
  end
  return people
end

-- Stasis places, then the Dormitory ships, each with room for all `marked` and none of them aboard already.
local function moveTargets(marked, data, rangers)
  local targets, seen = {}, {}
  for _, person in ipairs(marked) do
    seen[tostring(person.container)] = true
  end
  local function add(id64, free, kind)
    local key = tostring(id64)
    if not seen[key] and free >= #marked and isAlive(id64) then
      seen[key] = true
      targets[#targets + 1] = { id64 = id64, text = string.format("%s: %s", kind, string.format(pageText(4130), shipLabel(id64), free)) }
    end
  end
  local stasis = ReadText(PAGE, 4000)
  for _, place in ipairs((data and data.places) or {}) do
    add(componentOf(place.station), math.floor(tonumber(place.free) or 0), stasis)
  end
  local dormitory = ReadText(20104, 31603)
  for _, ranger in ipairs(rangers) do
    if isAlive(ranger.dormitory) then
      local crew, capacity = crewOf(ranger.dormitory)
      add(ranger.dormitory, capacity - crew, dormitory)
    end
  end
  return targets
end

-- A person Get-Them-Back still returns, while the tab does not allow reassigning them.
local function isHeld(person)
  return person ~= nil and person.due ~= nil and not menu.stasis.allowReassign
end

-- What MD's ResolvePerson takes: a Stasis key, or a ship's person by name and skills.
local function personRef(person)
  if person.recordKey then
    return { key = person.recordKey }
  end
  local ref = { container = luaId(person.container), name = person.name, ranger = person.rangerId and luaId(person.rangerId) or nil }
  for _, skill in ipairs(SKILLS) do
    ref[skill.key] = person[skill.key]
  end
  return ref
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

-- Text in the owner faction's colour; plain when the owner is unknown.
local function factionColored(text, owner)
  local color = (owner ~= nil and owner ~= "") and GetFactionData(owner, "color") or nil
  return color and (Helper.convertColorToText(color) .. text .. "\27X") or text
end

local function shipHint(ranger)
  local text = ReadText(PAGE, 3010) .. ReadText(1001, 120) .. " " .. modeText(ranger)
  if ranger.commander then
    text = text .. "\n" .. string.format(pageText(3017), string.format("%s (%s)", ranger.commander.name, ranger.commander.idcode))
  end
  return text
end

local function statusOf(ranger)
  if ranger.rescuing then
    return ReadText(PAGE, 3030), "text_positive"
  elseif ranger.dockedAt ~= 0 then
    return ReadText(1001, 3249), "text_normal"
  end
  return ReadText(PAGE, 3031), "text_normal"
end

-- The order flies home to the home station in Sector mode, to the Dormitory otherwise; any other flight is to Stasis.
local function activityOf(ranger)
  if ranger.rescuing then
    return ranger.rescuePerson and string.format(pageText(3071), ranger.rescuePerson, ranger.rescueSector) or "-"
  end
  if ranger.dockedAt ~= 0 or ranger.headingTo == 0 then
    return "-"
  end
  local parking = (ranger.station ~= 0) and ranger.station or ranger.dormitory
  if ranger.headingTo == parking then
    return string.format(pageText(3073), shipLabel(parking))
  elseif ranger.stasisNow ~= "off" then
    return string.format(pageText(3072), shipLabel(ranger.headingTo))
  end
  return "-"
end

-- Where the rescued go next, and the room left there.
local function destinationOf(ranger)
  if ranger.joinCrew then
    local free = ranger.capacity - ranger.crew
    return string.format(pageText(3074), ReadText(1001, 80), free), (free <= 0) and "text_negative" or "text_normal"
  end
  if ranger.stasisNow == "instead" then
    return ReadText(PAGE, 4000), "text_normal"
  end
  if not isAlive(ranger.dormitory) then
    return "-", "text_normal"
  end
  local free = ranger.dormCapacity - ranger.dormCrew
  local text = string.format(pageText(3074), shipLabel(ranger.dormitory), free)
  if ranger.stasisNow == "overflow" then
    return string.format(pageText(3075), text), (free <= 0) and "text_warning" or "text_normal"
  end
  return text, (free <= 0) and "text_negative" or "text_normal"
end

-- The order's own stop rules: a full ship with nowhere to move the rescued takes no more.
local function warningOf(ranger)
  if ranger.noPlace > 0 then
    return ReadText(PAGE, 3067), "text_warning", string.format(pageText(3068), ranger.noPlace)
  end
  local shipFull = ranger.capacity - ranger.crew <= 0
  if ranger.joinCrew then
    return shipFull and ReadText(PAGE, 3078) or "", "text_negative"
  end
  if ranger.stasisNow == "instead" then
    return "", "text_normal"
  end
  if not isAlive(ranger.dormitory) then
    return ReadText(PAGE, 3077), "text_negative"
  end
  if ranger.stasisNow == "overflow" or ranger.dormCapacity - ranger.dormCrew > 0 then
    return "", "text_normal"
  end
  if shipFull then
    return ReadText(PAGE, 3078), "text_negative"
  end
  return ReadText(PAGE, 3076), "text_warning"
end

-- Rescue ships by the sector they are in now; a Mimic follows its commander when both are there.
local function sectorGroups(rangers)
  local groups, byKey = {}, {}
  for _, ranger in ipairs(rangers) do
    local group = byKey[ranger.sectorKey]
    if not group then
      group = { name = ranger.sector, owner = ranger.sectorOwner, rangers = {}, has = {} }
      byKey[ranger.sectorKey] = group
      groups[#groups + 1] = group
    end
    group.rangers[#group.rangers + 1] = ranger
    group.has[ranger.idcode] = true
  end
  for _, group in ipairs(groups) do
    for _, ranger in ipairs(group.rangers) do
      ranger.indent = (ranger.commander ~= nil) and group.has[ranger.commander.idcode] or false
      ranger.groupKey = ranger.indent and ranger.sortKey or string.lower(ranger.name .. " " .. ranger.idcode)
    end
    table.sort(group.rangers, function(a, b) return a.groupKey < b.groupKey end)
  end
  table.sort(groups, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
  return groups
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
  elseif event.kind == "pickedUp" then
    return string.format(pageText(textId), tostring(event.person or ""), other, tostring(event.sector or ""))
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
  menu.contextFrame = nil
  menu.confirmPeople = nil
  menu.peopleTable = nil
  menu.detailTable = nil
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
  menu.stasis = menu.stasis or { marked = {}, filter = "", sort = "name", role = "service" }
  menu.stasis.allowReassign = toBool(rr.cfg.stasisAllowReassign)
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
  -- 8.00 has no row groups: a half-height gap separates a later section, as 9.00's group container does
  local last = ftable.rows[#ftable.rows]
  if not rr.isV9 and last ~= nil then
    local gap = ftable:addRow(false, { fixed = last.properties.fixed })
    gap[1]:setColSpan(cols):createText(" ", { fontsize = 1, minRowHeight = Helper.standardTextHeight / 2 })
  end
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
  menu.closeContext()
  Helper.clearDataForRefresh(menu, config.infoLayer)
  menu.sliderActive = nil
  menu.filterActive = nil
  menu.peopleTable = nil
  menu.detailTable = nil
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
    menu.createRangersPanel(Helper.frameBorder, top, width, rangers)
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
    -- button_border_hidden is 9.00 only; reading it on 8.00 logs a colour error
    row[i + 1]:createButton({ height = iconSize, bgColor = Color["toplevel_button_background"], borderColor = rr.isV9 and Color["button_border_hidden"] or nil, mouseOverText = tab.name() })
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

function menu.createRangersPanel(x, y, width, rangers)
  local bottom = buttonBar(x, width)
  local cols = 6
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 1, x = x, y = y, width = width, maxVisibleHeight = bottom - y })
  ftable:setColWidthPercent(2, 8)
  ftable:setColWidthPercent(3, 24)
  ftable:setColWidthPercent(4, 8)
  ftable:setColWidthPercent(5, 24)
  ftable:setColWidthPercent(6, 14)
  titleRow(ftable, cols, ReadText(PAGE, 3001))
  local rows = rowGroup(ftable)
  headerRow(rows, {
    ReadText(1001, 5), ReadText(1001, 12), ReadText(1001, 12822), ReadText(PAGE, 3069), ReadText(PAGE, 3070), ReadText(1001, 8342),
  }, { "left", "left", "left", "right", "left", "left" })
  if #rangers == 0 then
    noticeRow(rows, cols, ReadText(PAGE, 3056))
  end
  local rowOf = {}
  for _, group in ipairs(sectorGroups(rangers)) do
    local sectorRow = ftable:addRow(false, { bgColor = Color["row_title_background"] })
    sectorRow[1]:setColSpan(cols):createText(factionColored(group.name, group.owner), { halign = "left", font = Helper.standardFontBold })
    rows = rowGroup(ftable)
    for _, ranger in ipairs(group.rangers) do
      local row = rows:addRow({ "ranger", ranger.idcode }, {})
      rowOf[ranger.idcode] = row.index
      local label = string.format("%s (%s)", ranger.name, ranger.idcode)
      row[1]:createText(ranger.indent and ("   " .. label) or label, { halign = "left", mouseOverText = shipHint(ranger) })
      local status, statusColor = statusOf(ranger)
      row[2]:createText(status, { halign = "left", color = Color[statusColor] })
      local activity = activityOf(ranger)
      row[3]:createText(activity, { halign = "left", mouseOverText = activity })
      row[4]:createText(tostring(ranger.unassigned), { halign = "right" })
      local goesTo, goesToColor = destinationOf(ranger)
      row[5]:createText(goesTo, { halign = "left", color = Color[goesToColor], mouseOverText = goesTo })
      local warning, warningColor, warningHint = warningOf(ranger)
      row[6]:createText(warning, { halign = "left", color = Color[warningColor], mouseOverText = warningHint })
    end
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
  -- unittext is 9.00 only, 8.00 logs a widget error for it
  graph:setXAxis({ startvalue = 1 - GRAPH_HOURS, endvalue = 0, granularity = 3, offset = 0, gridcolor = Color["graph_grid"], unittext = rr.isV9 and ReadText(1001, 102) or nil })
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
  local percent = { [2] = 10, [3] = 12, [4] = 16, [5] = 12, [6] = 12, [7] = 16 }
  for col = 2, cols do
    ftable:setColWidthPercent(col, percent[col])
  end
  titleRow(ftable, cols, ReadText(1001, 2679))
  local rows = rowGroup(ftable)
  headerRow(rows, { ReadText(1001, 5), ReadText(PAGE, 104), ReadText(PAGE, 105), ReadText(PAGE, 106), ReadText(PAGE, 107), ReadText(PAGE, 109), ReadText(PAGE, 4000) },
    { "left", "left", "center", "center", "center", "center", "left" })
  if #rangers == 0 then
    noticeRow(rows, cols, ReadText(PAGE, 3056))
  end
  local size = Helper.scaleX(Helper.standardTextHeight)
  local inset = rr.isV9 and Helper.standardContainerOffset or 0
  local boxX = {}
  for col = 3, 6 do
    boxX[col] = math.max(0, math.floor((width * percent[col] / 100 - inset - size) / 2))
  end
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
        row[col]:createCheckBox(on, { width = size, height = size, scaling = false, x = boxX[col], mouseOverText = ReadText(PAGE, 3058) })
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
    row[col]:createCheckBox(allOn, { width = size, height = size, scaling = false, x = boxX[col], mouseOverText = mouseOver })
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

-- *** Rescued tab (id "stasis"): rebuilt on RescueRangers.StasisChanged or a changed people list, not on the timer ***

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

  -- Marks and the current person only ever refer to shown people.
  local all = rescuedAll(data, rangers)
  menu.peopleSignature = rescuedSignature(all)
  local people = rescuedPeople(all, state)
  local shown = {}
  for _, person in ipairs(people) do
    shown[person.key] = person
  end
  for key in pairs(state.marked) do
    if not shown[key] then
      state.marked[key] = nil
    end
  end
  if state.current ~= nil and not shown[state.current] then
    state.current = nil
  end
  menu.stasisShown = shown
  menu.stasisList = people
  menu.stasisCount = #all

  local controlsBottom = menu.createStasisControls(x, y, leftWidth)
  local actionsTop = menu.createStasisActions(x, bottom, leftWidth, people, data, rangers)
  menu.createStasisPeople(x, controlsBottom + Helper.borderSize, leftWidth, actionsTop - Helper.borderSize, people)

  local detailBottom = menu.createStasisDetail(rightX, y, rightWidth)
  local rentTop = menu.createStasisRent(rightX, detailBottom + Helper.borderSize, bottom, rightWidth, data)
  menu.createStasisLocations(rightX, detailBottom + Helper.borderSize, rentTop - Helper.borderSize, rightWidth, data)
end

-- Filter, sort, suitability role and the reassign switch; returns the y under the table.
function menu.createStasisControls(x, y, width)
  local state = menu.stasis
  local cols = 4
  local size = Helper.scaleX(Helper.standardTextHeight)
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 1, x = x, y = y, width = width, reserveScrollBar = false })
  ftable:setColWidth(1, size, false)
  ftable:setColWidthPercent(3, 25)
  ftable:setColWidthPercent(4, 25)
  titleRow(ftable, cols, ReadText(PAGE, 3012))
  local row = ftable:addRow(true, { fixed = true })
  row[1]:setColSpan(2):createEditBox({ defaultText = ReadText(1001, 3250), height = Helper.standardTextHeight }):setText(state.filter, { halign = "left", x = Helper.standardTextOffsetx })
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
  row[3]:createDropDown(sorts, { startOption = state.sort, height = Helper.standardTextHeight, mouseOverText = ReadText(1001, 2906) })
  row[3].handlers.onDropDownConfirmed = function(_, id)
    if id ~= state.sort then
      state.sort = id
      menu.refreshQueued = true
    end
  end
  local roles = {}
  for _, role in ipairs(ROLES) do
    roles[#roles + 1] = { id = role.id, text = role.text(), icon = "", displayremoveoption = false }
  end
  row[4]:createDropDown(roles, { startOption = state.role, height = Helper.standardTextHeight, mouseOverText = ReadText(PAGE, 4131) })
  row[4].handlers.onDropDownConfirmed = function(_, id)
    if id ~= state.role then
      state.role = id
      menu.refreshQueued = true
    end
  end
  row = ftable:addRow(true, { fixed = true })
  row[1]:createCheckBox(state.allowReassign, { width = size, height = size, scaling = false, mouseOverText = ReadText(PAGE, 4137) })
  row[1].handlers.onClick = function(_, checked) return menu.setAllowReassign(checked) end
  row[2]:setColSpan(3):createText(ReadText(PAGE, 4136), { halign = "left", mouseOverText = ReadText(PAGE, 4137) })
  return ftable.properties.y + ftable:getFullHeight()
end

function menu.setAllowReassign(checked)
  local state = menu.stasis
  state.allowReassign = checked and true or false
  rr.cfg.stasisAllowReassign = state.allowReassign and 1 or 0
  debugLog("stasis: reassigning people due back %s.", state.allowReassign and "allowed" or "blocked")
  sendStasis("AllowReassign", { value = state.allowReassign })
  menu.refreshQueued = true
end

local function sinceText(person, now)
  return person.since and formatAgo(now - (tonumber(person.since) or now)) or "-"
end

local function dueText(person)
  return person.due and string.format(pageText(4138), person.due) or nil
end

-- A checkbox per person marks them for the bar below; the row selection is the current person.
function menu.createStasisPeople(x, y, width, bottomY, people)
  local state = menu.stasis
  local role = roleOf(state.role)
  local cols = 6
  local size = Helper.scaleX(Helper.standardTextHeight)
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 2, x = x, y = y, width = width, maxVisibleHeight = bottomY - y })
  ftable:setColWidth(1, size, false)
  ftable:setColWidthPercent(3, 14)
  ftable:setColWidthPercent(4, 22)
  ftable:setColWidthPercent(5, 12)
  ftable:setColWidthPercent(6, 24)
  headerRow(ftable, { "", ReadText(1001, 2809), role.text(), ReadText(PAGE, 4101), ReadText(PAGE, 4102), ReadText(1001, 2943) })
  menu.peopleTable = ftable
  menu.peopleRowKey = {}
  menu.peopleRowOf = {}
  menu.peopleOrder = {}
  if #people == 0 then
    noticeRow(ftable, cols, ReadText(PAGE, (menu.stasisCount > 0) and 4106 or 4100))
  end
  local now = C.GetCurrentGameTime()
  for _, person in ipairs(people) do
    local key = person.key
    local row = ftable:addRow({ "person", key }, {})
    menu.peopleRowKey[row.index] = key
    menu.peopleRowOf[key] = row.index
    menu.peopleOrder[#menu.peopleOrder + 1] = key
    row[1]:createCheckBox(state.marked[key] == true, { width = size, height = size, scaling = false })
    row[1].handlers.onClick = function(_, checked) return menu.markPerson(key, checked) end
    row[2]:createText(person.name, { halign = "left" })
    row[3]:createText(potentialStars(person[role.skill]), { halign = "left" })
    row[4]:createText(textOf(person.lostShip), { halign = "left", color = person.due and Color["text_positive"] or nil, mouseOverText = dueText(person) })
    row[5]:createText(sinceText(person, now), { halign = "left" })
    row[6]:createText(person.placeName, { halign = "left" })
  end
  if state.current ~= nil and menu.peopleRowOf[state.current] then
    ftable:setSelectedRow(menu.peopleRowOf[state.current])
  end
  if menu.topRows.stasis then
    ftable:setTopRow(menu.topRows.stasis)
  end
end

local function keepTopRow()
  if menu.peopleTable and menu.peopleTable.id then
    menu.topRows.stasis = GetTopRow(menu.peopleTable.id)
  end
end

function menu.markPerson(key, checked)
  menu.stasis.marked[key] = checked and true or nil
  keepTopRow()
  menu.refreshQueued = true
end

-- The marked ones among `people`, in their order.
local function markedOf(people)
  local marked = {}
  for _, person in ipairs(people) do
    if menu.stasis.marked[person.key] then
      marked[#marked + 1] = person
    end
  end
  return marked
end

-- Target, Move, Dismiss, Select all, the marked count; all but Select all need marked people.
-- Placed above bottomY, returns its top.
function menu.createStasisActions(x, bottomY, width, people, data, rangers)
  local state = menu.stasis
  local marked = markedOf(people)
  local cols = 5
  local ftable = menu.infoFrame:addTable(cols, { tabOrder = 3, x = x, y = 0, width = width, reserveScrollBar = false })
  ftable:setColWidthPercent(2, 13)
  ftable:setColWidthPercent(3, 13)
  ftable:setColWidthPercent(4, 13)
  ftable:setColWidthPercent(5, 15)
  local row = ftable:addRow(true, { fixed = true })
  local options, valid = {}, {}
  if #marked > 0 then
    for _, target in ipairs(moveTargets(marked, data, rangers)) do
      local id = tostring(target.id64)
      options[#options + 1] = { id = id, text = target.text, icon = "", displayremoveoption = false, mouseovertext = target.text }
      valid[id] = true
    end
  end
  if not (state.target and valid[state.target]) then
    state.target = options[1] and options[1].id or nil
  end
  row[1]:createDropDown(options, {
    startOption = state.target or "", textOverride = (#options == 0) and ReadText(PAGE, (#marked == 0) and 4129 or 4128) or nil,
    active = #options > 0, height = Helper.standardTextHeight, mouseOverText = ReadText(PAGE, 4127),
  })
  row[1].handlers.onDropDownConfirmed = function(_, id) state.target = id end
  row[2]:createButton({ active = #options > 0 }):setText(ReadText(PAGE, 4135), { halign = "center" })
  row[2].handlers.onClick = function() return menu.buttonMove() end
  local dismissable = 0
  for _, person in ipairs(marked) do
    if not isHeld(person) then
      dismissable = dismissable + 1
    end
  end
  row[3]:createButton({ active = dismissable > 0 }):setText(pageText(4141), { halign = "center" })
  row[3].handlers.onClick = function() return menu.buttonDismiss() end
  local allMarked = (#people > 0) and (#marked == #people)
  row[4]:createButton({ active = #people > 0 }):setText(ReadText(PAGE, allMarked and 4139 or 4126), { halign = "center" })
  row[4].handlers.onClick = function() return menu.buttonSelectAll(not allMarked) end
  row[5]:createText(string.format("%s: %d", ReadText(1001, 17), #marked), { halign = "right" })
  ftable.properties.y = bottomY - ftable:getFullHeight()
  return ftable.properties.y
end

-- Texts of the detail panel for a person, or its empty state.
local function detailTexts(person)
  local texts = { title = person and person.name or ReadText(PAGE, 3012) }
  for _, skill in ipairs(SKILLS) do
    texts[skill.key] = person and Helper.displaySkill(tonumber(person[skill.key]) or 0) or "-"
  end
  for _, role in ipairs(ROLES) do
    texts[role.skill] = person and potentialStars(person[role.skill]) or "-"
  end
  texts.lostShip = person and textOf(person.lostShip) or "-"
  texts.ranger = person and rangerLabel(person) or "-"
  texts.since = person and sinceText(person, C.GetCurrentGameTime()) or "-"
  texts.location = person and person.placeName or "-"
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

-- The ages in place, or a rebuild when someone arrived or left (Rescue ships and Dormitories send no event).
function menu.updateStasisAges()
  if not (menu.peopleTable and menu.peopleTable.id and menu.peopleRowKey and menu.stasisShown) then
    return
  end
  if rescuedSignature(rescuedAll(readStasis(), collectRangers())) ~= menu.peopleSignature then
    keepTopRow()
    menu.refreshQueued = true
    return
  end
  local now = C.GetCurrentGameTime()
  for rowIndex, key in pairs(menu.peopleRowKey) do
    local person = menu.stasisShown[key]
    if person then
      Helper.updateCellText(menu.peopleTable.id, rowIndex, 5, sinceText(person, now))
    end
  end
  menu.updateStasisDetail()
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

local function refsOf(people)
  local refs = {}
  for i, person in ipairs(people) do
    refs[i] = personRef(person)
  end
  return refs
end

function menu.buttonMove()
  local state = menu.stasis
  local marked = markedOf(menu.stasisList or {})
  if #marked == 0 or not state.target then
    traceLog("stasis: move skipped, %d marked, target %s.", #marked, tostring(state.target))
    return
  end
  debugLog("stasis: move %d to %s.", #marked, tostring(state.target))
  state.marked = {}
  sendStasis("Move", { people = refsOf(marked), target = luaId(state.target) })
end

-- People due back are kept unless reassigning them is allowed.
function menu.buttonDismiss()
  local people, held = {}, 0
  for _, person in ipairs(markedOf(menu.stasisList or {})) do
    if isHeld(person) then
      held = held + 1
    else
      people[#people + 1] = person
    end
  end
  if #people > 0 then
    local text = string.format(pageText(4125), #people)
    if held > 0 then
      text = text .. "\n" .. string.format(pageText(4140), held)
    end
    menu.openConfirm(people, nil, text)
  end
end

function menu.buttonSelectAll(mark)
  local marked = {}
  if mark then
    for _, person in ipairs(menu.stasisList or {}) do
      marked[person.key] = true
    end
  end
  menu.stasis.marked = marked
  keepTopRow()
  menu.refreshQueued = true
end

-- Dismiss confirmation, a frame on the context layer; Cancel is preselected.
function menu.openConfirm(people, title, text)
  menu.closeContext()
  menu.confirmPeople = people
  local width = Helper.scaleX(config.confirmWidth)
  local frame = Helper.createFrameHandle(menu, {
    layer = config.contextLayer, standardButtons = { close = true }, width = width, autoFrameHeight = true,
    x = math.floor((Helper.viewWidth - width) / 2), y = math.floor(Helper.viewHeight / 3),
  })
  frame:setBackground("solid", { color = Color["frame_background_semitransparent"] })
  local ftable = frame:addTable(2, { tabOrder = 1, x = Helper.borderSize, y = Helper.borderSize, width = width - 2 * Helper.borderSize, reserveScrollBar = false })
  titleRow(ftable, 2, title or pageText(4141))
  local row = ftable:addRow(false, {})
  row[1]:setColSpan(2):createText(text or string.format(pageText(4125), #people), { halign = "left", wordwrap = true })
  row = ftable:addRow(true, {})
  row[1]:createButton({}):setText(ReadText(1001, 2821), { halign = "center" })
  row[1].handlers.onClick = function() return menu.confirmDismiss() end
  row[2]:createButton({}):setText(ReadText(1001, 64), { halign = "center" })
  row[2].handlers.onClick = function() return menu.closeContext() end
  ftable:setSelectedRow(row.index)
  ftable:setSelectedCol(2)
  menu.contextFrame = frame
  frame:display()
end

function menu.closeContext()
  menu.confirmPeople = nil
  menu.mouseOutBox = nil
  if menu.contextFrame then
    menu.contextFrame = nil
    Helper.clearFrame(menu, config.contextLayer)
  end
end

function menu.confirmDismiss()
  local people = menu.confirmPeople
  menu.closeContext()
  if people and #people > 0 then
    debugLog("stasis: dismiss %d.", #people)
    sendStasis("Dismiss", { people = refsOf(people) })
  end
end

-- A person's container and NPC seed; a Stasis record without `$seed` is matched by name on its station, the skills decide between namesakes.
local function personOf(person)
  local container = person and person.container or 0
  if not isAlive(container) then
    return nil
  end
  if person.seed then
    return container, person.seed
  end
  local matches = {}
  for _, npc in ipairs(GetRoleTierNPCs(container, "unassigned", 0) or {}) do
    if npc.name == person.name then
      matches[#matches + 1] = C.ConvertStringTo64Bit(tostring(npc.seed))
    end
  end
  if #matches > 1 then
    local numSkills = C.GetNumSkills()
    local buf = ffi.new("SkillInfo[?]", numSkills)
    for _, seed in ipairs(matches) do
      local same = true
      for i = 0, C.GetPersonSkills3(buf, numSkills, seed, container) - 1 do
        local value = tonumber(person[ffi.string(buf[i].id)])
        if value ~= nil and value ~= buf[i].value then
          same = false
          break
        end
      end
      if same then
        return container, seed
      end
    end
  end
  return container, matches[1]
end

-- The person entries of vanilla's map crew context (menu_map createInfoContext), Fire through our Dismiss;
-- unlike vanilla, also on a leased NPC station: Stasis people are the player's wherever they stay.
-- Work somewhere else and Fire stay inactive for a person due back unless reassigning is allowed.
function menu.openPersonContext(key, x, y)
  local person = menu.stasisShown and menu.stasisShown[key]
  local container, seed = personOf(person)
  if not seed then
    debugLog("stasis: no person aboard for %s.", textOf(person and person.name))
    return
  end
  local held = isHeld(person)
  local heldText = held and (dueText(person) .. "\n" .. ReadText(PAGE, 4137)) or nil
  menu.closeContext()
  local width = Helper.scaleX(config.contextWidth)
  local frame = Helper.createFrameHandle(menu, {
    layer = config.contextLayer, standardButtons = { close = true }, width = width, autoFrameHeight = true, x = x, y = 0,
    closeOnUnhandledClick = true,
  })
  frame:setBackground("solid", { color = Color["frame_background_semitransparent"] })
  local ftable = frame:addTable(1, { tabOrder = 1, x = Helper.borderSize, y = Helper.borderSize, width = width - 2 * Helper.borderSize, highlightMode = "off" })
  local containerLuaId = luaId(container)
  local isUnlocked = IsInfoUnlockedForPlayer(containerLuaId, "name")
  local name = ffi.string(C.GetPersonName(seed, container))
  local row = ftable:addRow(false, { fixed = true, bgColor = Color["row_background_blue"] })
  row[1]:createText(Helper.unlockInfo(isUnlocked, name), Helper.headerRowCenteredProperties)
  local scheduled = C.IsPersonTransferScheduled(container, seed)
  local arrived = C.HasPersonArrived(container, seed)
  local instance = C.GetInstantiatedPerson(seed, container)
  local entity = (instance ~= 0) and ConvertStringTo64Bit(tostring(instance)) or nil
  local function addEntry(text, onClick, active, mouseOverText)
    local entry = ftable:addRow(true, { fixed = true })
    entry[1]:createButton({ bgColor = Color["button_background_hidden"], height = Helper.standardTextHeight, active = active ~= false, mouseOverText = mouseOverText }):setText(text)
    entry[1].handlers.onClick = onClick
  end
  if scheduled then
    addEntry(ReadText(1001, 9435), function() C.ReleasePersonFromCrewTransfer(container, seed); menu.closeContext() end)
  end
  if arrived then
    addEntry(ReadText(1002, 3008), function()
      local hire = entity and { "signal", entity, 0 } or { "signal", container, 0, seed }
      -- AssignHiredActor refuses a person on an NPC station: hand it a player-owned instance instead.
      if not GetComponentData(container, "isplayerowned") then
        local npc = entity or ConvertStringTo64Bit(tostring(C.CreateNPCFromPerson(seed, container)))
        if not GetComponentData(npc, "isplayerowned") then
          C.SetComponentOwner(npc, "player")
        end
        hire = { "signal", npc, 0 }
      end
      traceLog("stasis: %s works somewhere else.", name)
      Helper.closeMenuAndOpenNewMenu(menu, "MapMenu", { 0, 0, true, container, nil, "hire", hire })
      menu.cleanup()
    end, not held, heldText)
  end
  addEntry(ReadText(1002, 15800), function()
    menu.openConfirm({ person }, string.format(tostring(ReadText(1001, 11202)), name), ReadText(1001, 11201))
  end, not held, heldText)
  if not scheduled and arrived then
    local actor = { context = containerLuaId, person = ConvertStringToLuaID(tostring(seed)) }
    if entity and C.GetContextByClass(entity, "container", false) == C.GetContextByClass(C.GetPlayerID(), "container", false) then
      actor = entity
    end
    addEntry(ReadText(1001, 3216), function()
      menu.closeContext()
      Helper.closeMenuForNewConversation(menu, "default", actor)
      menu.cleanup()
    end, isUnlocked)
  end
  if frame.properties.x + width > Helper.viewWidth then
    frame.properties.x = Helper.viewWidth - width - Helper.frameBorder
  end
  local height = frame:getUsedHeight()
  frame.properties.y = (y + height > Helper.viewHeight) and (Helper.viewHeight - height - Helper.frameBorder) or y
  menu.contextFrame = frame
  frame:display()
  local fx, fy = frame.properties.x - Helper.viewWidth / 2, Helper.viewHeight / 2 - frame.properties.y
  menu.mouseOutBox = {
    x1 = fx - config.mouseOutRange, x2 = fx + width + config.mouseOutRange,
    y1 = fy + config.mouseOutRange, y2 = fy - height - config.mouseOutRange,
  }
end

function menu.onTableRightMouseClick(uitable, row, posx, posy)
  if not (menu.peopleTable and uitable == menu.peopleTable.id) then
    return
  end
  local key = menu.peopleRowKey and menu.peopleRowKey[row]
  if key == nil then
    return
  end
  local x, y = GetLocalMousePosition()
  if x == nil then
    x, y = posx, -posy
  end
  menu.openPersonContext(key, x + Helper.viewWidth / 2, Helper.viewHeight / 2 - y)
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

-- The selected Rescue ship, or on the Rescued tab the current person's station or ship.
local function selectedObject()
  if menu.tab == "stasis" then
    local current = menu.stasis.current
    local person = (current ~= nil) and menu.stasisShown and menu.stasisShown[current]
    local id64 = person and person.container or 0
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

-- A person row only updates cells in place: a rebuild from here breaks the frame being built.
function menu.onRowChanged(_row, rowdata, uitable)
  if type(rowdata) ~= "table" then
    return
  end
  if rowdata[1] == "ranger" then
    menu.selected[menu.tab] = rowdata[2]
    menu.topRows[menu.tab] = GetTopRow(uitable)
  elseif rowdata[1] == "person" then
    local state = menu.stasis
    if menu.mouseOutBox and rowdata[2] ~= state.current then
      menu.closeContext()
    end
    state.current = rowdata[2]
    menu.topRows.stasis = GetTopRow(uitable)
    menu.updateStasisDetail()
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
  if menu.contextFrame then
    menu.contextFrame:update()
  end
  if menu.mouseOutBox and ((GetControllerInfo() ~= "gamepad") or C.IsMouseEmulationActive()) then
    local mx, my = GetLocalMousePosition()
    local box = menu.mouseOutBox
    if (mx and (mx < box.x1 or mx > box.x2)) or (my and (my > box.y1 or my < box.y2)) then
      menu.closeContext()
    end
  end
end

-- A third argument means the view is already gone: never refuse that close.
function menu.onCloseElement(dueToClose, _layer, forced)
  if menu.contextFrame and not forced then
    menu.closeContext()
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
