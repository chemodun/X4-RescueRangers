# Changelog

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
