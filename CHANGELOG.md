# Changelog

## [2.00] - 2026-10-??

### Added

- Order option `Keep rescued on board as crew`.
- `Rescue Rangers` page in the Extension Options: extra rescue range, Stasis defaults, top menu entry, `Debug Level`.
- `Rescue Rangers` overview in the top menu: Rescue ships, statistics, Stasis and per-ship settings.
- Stasis: rescued people kept on your stations or on space rented on NPC stations, managed from the overview's `Stasis` tab, and returned on Replacement Ships too.
- Requires `Mod Support APIs`, `Options Helper` and `Print Extension List`.
- Czech, Polish, Turkish and Bulgarian translations.

### Changed

- Nothing is written to the game's debug log unless `Debug Level` is set to `Debug` or `Trace`.
- A full Rescue ship and "Dormitory" no longer call you every few minutes: one notice until there is free space again.
- Workshop sync is off by default, as for other extensions.

### Fixed

- A successful rescue was not recognized after the rescue flight: no "rescued" logbook entry, no pilot experience, and `Return them back` never registered the person.
- `Return them back`: a rescued person was often dropped from tracking between docking at the Rescue ship and being registered, so they never returned to the Replacement Ship.
- Several Rescue ships in one area: a person picked by a Rescue ship that then failed, was destroyed or got other orders was skipped by all other Rescue ships for good.
- Rescue ships whose order was started with version 1.00 ignored ship losses in their own sector.
- With a `Max gate distance to rescue` above 0, a Rescue ship that found nobody in one sector went home instead of checking the other sectors in range. Spacesuits left from losses during a rescue flight are now picked up too.
- `Mimic` subordinates always ran with `Return them back on Replacement Ship` off.
- `Return them back on Replacement Ship` could stop tracking losses and replacements while all Rescue ships were busy for more than 5 minutes.
- `Return them back on Replacement Ship`: rescued crew is now returned on the replacement of the very ship they were lost from. Before, any recent loss of the same model nearby could take its place, even one from a fleet without `Lost Ships Replacement`.
- `Return them back on Replacement Ship`: rescued crew whose Replacement Ship took more than an hour to build and arrive was forgotten before it joined the fleet.
- `Return them back on Replacement Ship`: crew members were tracked by name, so two people with the same name could be skipped or mixed up. They are tracked one by one now; a save from an older version is converted on load.
- The order can no longer be added to a repeat orders loop.
- A Rescue ship destroyed while on the order wrote errors to the game's debug log.
- A Rescue ship undocking from a station other than its Home Station wrote an error to the game's debug log.
- The Traditional Chinese translation showed Bengali text in several places.
- Japanese, Korean and Simplified Chinese: some logbook messages put the person, sector, count or destination in the wrong place, or left one out.
- The "cannot dock" message named the Rescue ship and the "dormitory" ship the wrong way round.

## [1.06] - 2025-06-16

### Fixed

- Fixed an unnecessary undocking on applying the order. Thanks [staeuber](https://forum.egosoft.com/memberlist.php?mode=viewprofile&u=132068) for the proposed solution.

### Changed

- Debug logging get rid of separate files per ship and now uses a common game debug log file.

## [1.05] - 2025-03-20

### Added

- Added a new feature to "return" rescued crew on the Replacement Ship. Works in conjunction with the `Lost Ships Replacement` feature of 7.50 game version.

## [1.04] - 2025-03-05

### Fixed

- Wrong error in non-Fleet mode if Rescue ship can't dock on Dormitory.

## [1.03] - 2025-03-02

### Added

- Added a new "Fleet support" mode. If `Home station` is not set - the `Fleet support` mode is enabled.

## [1.01] - 2024-12-26

### Added

- Added a new option to define a range of sectors where the ship can rescue the crew members.
- Added a new option to select the priority of the rescue by the oxygen remained in the spacesuit instead of the distance to the ship.
- Added a possibility to use in fleet mode with the `Mimic` order.

## [1.00] - 2024-12-17

### Added

- Initial release of the Rescue Rangers extension.
- Allows rescuing crew members from destroyed ships in a designated sector.
- Configuration options for home sector, home station, ship dormitory, and logbook recording.
- Compatibility with X4: Foundations 7.1.
