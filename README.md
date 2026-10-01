# Rescue Rangers

This extension allows you to rescue crews' members from the destroyed ships in a designated sector.
Always the closest possible spacesuit will be selected to rescue.

## Compatibility

Compatible with `X4: Foundations 7.1`. At least it written and tested with this version.

## Requirements

- `Mod Support APIs` by [SirNukes](https://next.nexusmods.com/profile/sirnukes?gameId=2659) to be installed and enabled. Version `1.95` and upper is required.
  - It is available via Steam - [SirNukes Mod Support APIs](https://steamcommunity.com/sharedfiles/filedetails/?id=2042901274)
  - Or via the Nexus Mods - [Mod Support APIs](https://www.nexusmods.com/x4foundations/mods/503)
- `Options Helper`, to provide the in-game options page. Version `1.10` and upper is required.
  - It is available via Steam - [Options Helper](https://steamcommunity.com/sharedfiles/filedetails/?id=3715253556)
  - Or via the Nexus Mods - [Options Helper](https://www.nexusmods.com/x4foundations/mods/2089)
- `Print Extension List`, to record the game version and the enabled extensions in the log. Version `1.00` and upper is required.
  - It is available via Steam - [Print Extension List](https://steamcommunity.com/sharedfiles/filedetails/?id=3770927339)
  - Or via the Nexus Mods - [Print Extension List](https://www.nexusmods.com/x4foundations/mods/2191)

## Features

Several ships with one order can work in one sector or crossed sectors.
`Mimic` order in a fleet is fully supported.
From version 1.03 can work without `Home station` set - in the `Fleet support` mode.
From version 1.07 the `Rescue Rangers` overview in the top menu shows every Rescue ship, the rescue statistics and each Rescue ship's settings.

## How it works

The ship with order "Rescue Rangers" will wait docked in the Home Station or "Dormitory" ship for event, when any player ship in the Home Sector (or sector where the "Dormitory" is located) will be destroyed. After that, the ship will fly to find spacesuits and fly to it to rescue the crew's members.
When the ship will collect all crew's members it will fly back to the Home Sector and dock to the Home Station or "Dormitory" ship.
If case it will be full before the ship will collect all crew's members - it will try to transfer the rescued crew to the "Dormitory" ship and continue the rescue operation.
If Rescue ship will return to the Home Station, it will not immediately transfer the rescued crew to the "Dormitory" ship. It will wait for the some period of "silence" before to do it.
As in "Fleet support" mode it will dock to the "Dormitory" ship then it will transfer the rescued crew immediately after the docking.
If the "Dormitory" ship will be full - the Rescue ship will try to inform you.
Please don't forget to check the "Dormitory" ship and transfer the rescued crew to new ships.

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

The highest value you can select depends on the captain's `Pilot` skill: `0` for up to one star, `1` for two stars, `2` for three stars and `3` for four or five stars. The `Extra max gate distance above the pilot skill limit` setting in the Extension Options adds to it, see `Rescue Rangers options`.

When the sector of a loss has no spacesuits left, the ship checks the other sectors in range, nearest first.

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

### Return them back on Replacement Ship

`Disabled` by default.

If enabled, the rescued crew will be "returned" on the Replacement Ship, when it will rejoin to fleet.
The `Lost Ships Replacement` feature should be enabled for appropriate fleet commander or station. And for sure - the game version should be at least 7.50.

The rescued crew is returned on the replacement of the very ship they were lost from. Ships lost outside a fleet with `Lost Ships Replacement` get no replacement, so their rescued crew stays where the Rescue ship put it.

A loss is remembered for two hours: a Replacement Ship finished later than that (for example, while the shipyards were short of resources) gets no rescued crew back.

**Important note**: This feature is configured on each Rescue ship separately!

#### Explanation video

[Return them back on Replacement Ship](https://youtube.com/watch?v=OaU6-RikfnI)

### Keep rescued on board as crew

`Disabled` by default.

If enabled, the rescued crews' members join the Rescue ship's crew right away: as `Service crew`, or as `Marines` when their boarding skill is higher than their engineering skill. They are not transferred to the "Dormitory" ship, so you can take them from the Rescue ship directly. When the Rescue ship has no free space left, it stops rescuing and tells you once, until you move some crew off it.

### Record to logbook

`Enabled` by default.

If enabled, the ship will record the events to the logbook. I.e. starts, travel to desired sector, flying to the target, attacking the target, destroying the target, etc.

## Rescue Rangers options

These options are on the `Rescue Rangers` page of the `Extension options` menu. They apply to all Rescue ships.

### Extra max gate distance above the pilot skill limit

From `0` (the default) to `5`. Raises the highest `Max gate distance to rescue` you can select for any Rescue ship by this number. It changes only what the order menu lets you pick; set the distance on each Rescue ship as before.

### Show the Rescue Rangers overview in the top menu

`Enabled` by default. Adds the `Rescue Rangers` overview to the row of top menu icons, right after the map.

### Debug Level

Sets how much the extension writes to the game's debug log:

- `None` - nothing, the default.
- `Debug` - one line per action: order start and settings, rescue target selected, rescue result, transfers to the "Dormitory", and the main steps of `Return them back on Replacement Ship`. Please use this level for a log attached to a problem report.
- `Trace` - in addition, every spacesuit checked, every loop of the order, and the vanilla docking and undocking details.

## Rescue Rangers overview

Open it with its icon in the top menu, right after the map. It has three tabs:

- `Rescue ships` - every ship on the order, each Mimic right under its commander: mode (`Sector`, `Fleet` or `Mimic`), current location, home sector with its rescue range, home station or "Dormitory", crew on board, the "Dormitory" load, the current state, and how many people it rescued. Double-click a row, or use `Show on Map`, to see the ship on the map.
- `Statistics` - how many crew members were ejected from your lost ships, rescued, died in space, moved to "Dormitories", joined a Rescue ship's crew and were returned on Replacement Ships; the same per Rescue ship, including the ones that are gone; and the recent events. Counting starts when the extension is first loaded in a game.
- `Settings` - each Rescue ship's `Max gate distance to rescue` and its four options. A change applies at once and restarts that ship's order, as the same change in the order menu does. A Mimic follows its commander's settings.

## Situation when both ships are full

The Rescue ship shows an on-screen notice once, when it and the "Dormitory" ship run out of space. If the Record to logbook is enabled, the same notice goes to the logbook. It stays silent after that, until there is free space again. With `Keep rescued on board as crew` enabled, the Rescue ship alone being full is enough for the notice.

## Links

There is a thread on EgoSoft forum - [[Mod/AIScript] Order "Rescue Rangers"](https://forum.egosoft.com/viewtopic.php?p=5260786). Feel free to ask any questions or report issues there.
