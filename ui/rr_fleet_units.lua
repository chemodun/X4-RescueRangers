-- Filename: rr_fleet_units.lua
local ffi = require("ffi")
local C = ffi.C

local rr = {
  configBlackboard = "$RescueRangersConfig",
  logPrefix = "RR_GetThemBack - FleetUnit [Lua]",
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

-- A replacement's fleet unit keeps the lost ship's idcode, which MD cannot read.
function rr.FleetUnitOfReplacement(_, replacement)
  local level = DebugLevel()
  local replacement64 = ConvertStringTo64Bit(tostring(replacement))
  if replacement64 == 0 then
    Write("no replacement given: %s", tostring(replacement))
    return
  end
  local replacementIdcode = tostring(GetComponentData(ConvertStringToLuaID(tostring(replacement64)), "idcode"))
  local fleetUnit = C.GetFleetUnit(replacement64)
  if fleetUnit == 0 then
    if level ~= "none" then
      Write("replacement %s (%s) has no fleet unit", tostring(replacement64), replacementIdcode)
    end
    return
  end
  local info = C.GetFleetUnitInfo(fleetUnit)
  local idcode = ffi.string(info.idcode)
  if idcode == "" then
    if level ~= "none" then
      Write("replacement %s (%s): fleet unit %s has no idcode", tostring(replacement64), replacementIdcode, tostring(fleetUnit))
    end
    return
  end
  AddUITriggeredEvent("RescueRangers.FleetUnits", "Replacement", { replacement = ConvertStringToLuaID(tostring(replacement64)), idcode = idcode })
  if level == "trace" then
    Write("replacement %s (%s): fleet unit %s, lost ship %s, macro %s, build task %s", tostring(replacement64), replacementIdcode, tostring(fleetUnit), idcode, ffi.string(info.macro), tostring(info.buildtaskid))
  elseif level == "debug" then
    Write("replacement %s (%s) replaces lost ship %s", tostring(replacement64), replacementIdcode, idcode)
  end
end

local function init()
  RegisterEvent("RescueRangers.FleetUnit", rr.FleetUnitOfReplacement)
end

Register_OnLoad_Init(init)
