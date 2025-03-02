# Rescue Rangers

This extension allows you to rescue crews' members from the destroyed ships in a designated sector.
Always the closest possible spacesuit will be selected to rescue.

## Compatibility

Compatible with `X4: Foundations 7.1`. At least it written and tested with this version.

## Features

Several ships with one order can work in one sector or crossed sectors.
`Mimic` order in a fleet is fully supported.
From version 1.03 can work without `Home station` set - in the `Fleet support` mode.

## Download

You can download the latest version via Steam client - [Rescue Rangers](https://steamcommunity.com/sharedfiles/filedetails/?id=3385833966)
Or you can do it via the [Rescue Rangers](https://www.nexusmods.com/x4foundations/mods/1571)

## Executing the order

You can select the order as any other, "default", from the "Navigation" section of  orders.
Please be aware - this order requires the ship captain to have at least `one star` in the "Pilot" skill.

## Configuration

There are several configuration options available. You can see all of them on a screenshot.

### Home Sector

This is a sector where the ship will rescue the crew. You can select it from the list of discovered sectors.

### Max gate distance to rescue

This is a maximum distance from the Home Sector to the sector where the ship can rescue the crews' members. The ship will not react to ship destructions in the sectors further than this distance.
Default value is `0`.

### Home Station

This is a station where the ship will be docked and wait for the next order. You can select it from the list of discovered stations in any sector.
The best option is to select a station in the same sector as the Home Sector.

If during setup the order the station was not selected, the ship will be in the `Fleet support` mode. In this mode, the ship will dock to the "Dormitory" ship and will assume the current sector as the Home Sector for rescue operations.

### Ship - "Dormitory"

This is a ship where the rescued crew will be placed. You can select it from the list of your ships. The ship should have enough capacity to place all rescued crews' members.
Please take into account - in the `Fleet support` mode the "Dormitory" has to be capable to provide docking for the Rescuer ship.

### Priority by oxygen remained

`Disabled` by default.
This option allows you to select the priority of the rescue by the oxygen remaining in the spacesuit instead of the distance to the ship. If enabled, the ship will try to rescue the crews' members with the lowest oxygen remaining in the spacesuit.

### Record to logbook

`Enabled` by default.

If enabled, the ship will record the events to the logbook. I.e. starts, travel to desired sector, flying to the target, attacking the target, destroying the target, etc.

## Situation when both ships are full

The ship's captain will periodically call to the player to inform about absence of the order. Additionally, if the Record to logbook is enabled - it will be recorded there as well.

## Links

There is a thread on EgoSoft forum - [[Mod/AIScript] Order "Rescue Rangers"](https://forum.egosoft.com/viewtopic.php?p=5260786). Feel free to ask any questions or report issues there.
