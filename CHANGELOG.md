# Changelog

## [2.00] - 2026-10-04

### Added

- `Rescue Rangers` overview in the top menu: Rescue ships, statistics, rescued people and per-ship settings.
- Stasis: rescued people kept on your stations or on space rented on NPC stations.
- Order options `Keep rescued on board as crew` and `Stasis`.
- `Rescue Rangers` page in the Extension Options.
- Czech, Polish, Turkish and Bulgarian translations.

### Changed

- Requires `Mod Support APIs`, `Options Helper` and `Print Extension List`.
- Nothing is written to the game's debug log unless `Debug Level` is `Debug` or `Trace`.
- A full Rescue ship and "Dormitory" tell you once, not every few minutes.
- The order can no longer be added to a repeat orders loop.

### Fixed

- A successful rescue was not recognized: no logbook entry, no pilot experience, no `Return them back` registration.
- With `Max gate distance to rescue` above 0, a Rescue ship that found nobody in one sector went home instead of searching the rest of its range.
- Several Rescue ships in one area: a person picked by a Rescue ship that then failed was skipped by all the others for good.
- Rescue ships started on 1.00 ignored losses in their own sector.
- `Mimic` subordinates always ran with `Return them back on Replacement Ship` off.
- `Return them back on Replacement Ship`: rescued people could be dropped from tracking, mixed up by equal names, returned on the wrong ship, or forgotten while the replacement was being built or all Rescue ships were busy. Older saves are repaired on load.
- Debug log errors when a Rescue ship was destroyed or undocked away from its Home Station.
- Wrong texts in the Traditional Chinese, Japanese, Korean and Simplified Chinese translations; the "cannot dock" message swapped the two ship names.

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
