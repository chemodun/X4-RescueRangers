-- Filename: rr_fleet_units.lua
local ffi = require("ffi")
local C = ffi.C

local rr = {
  configBlackboard = "$RescueRangersConfig",
  logPrefix = "RR_GetThemBack - FleetUnits [Lua]",
}

local function DebugLevel()
  local playerId = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
  local config = GetNPCBlackboard(playerId, rr.configBlackboard)
  if type(config) == "table" and config.debugLevel then
    return tostring(config.debugLevel)
  end
  return "none"
end

local function Write(message, ...)
  DebugError(rr.logPrefix .. ": " .. string.format(message, ...))
end

-- A lost fleet unit keeps the destroyed ship's idcode, which MD cannot read.
function rr.FleetUnits(_, commander)
  local level = DebugLevel()
  local commander64 = ConvertStringTo64Bit(tostring(commander))
  if commander64 == 0 then
    Write("no commander given: %s", tostring(commander))
    return
  end
  local commanderId = ConvertStringToLuaID(tostring(commander64))
  local count = C.GetNumAllFleetUnits(commander64)
  local sent = 0
  if count > 0 then
    local units = ffi.new("FleetUnitID[?]", count)
    count = C.GetAllFleetUnits(units, count, commander64)
    for i = 0, count - 1 do
      local info = C.GetFleetUnitInfo(units[i])
      local idcode = ffi.string(info.idcode)
      if idcode ~= "" then
        AddUITriggeredEvent("RescueRangers.FleetUnits", "Result", { commander = commanderId, idcode = idcode })
        sent = sent + 1
        if level == "trace" then
          Write("commander %s: unit %s, macro %s, build task %s, replacement %s", tostring(commander64), idcode, ffi.string(info.macro), tostring(info.buildtaskid), tostring(info.replacementid))
        end
      end
    end
  end
  if level == "debug" or level == "trace" then
    Write("commander %s (%s): %d lost units, %d idcodes sent", tostring(commander64), tostring(GetComponentData(commanderId, "idcode")), count, sent)
  end
end

local function init()
  RegisterEvent("RescueRangers.FleetUnits", rr.FleetUnits)
end

Register_OnLoad_Init(init)
