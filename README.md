# X4-RescueRangers
This extension allows you to rescue crews' members from the destroyed ships in a designated sector.
Always the closest possible spacesuit will be selected to rescue. 

## Compatibility
Compatible with `X4: Foundations 7.1`. At least it written and tested with this version.
Not created to use with fleets. It is a single ship script.
Several ships with one script will work in one sector, but it is not tested properly.

## Executing the order

You can select the order as any other, "default", from the "Navigation" section of  orders.
Please be aware - this order required the ship captain to have at least `one star` in the "Pilot" skill.

## Configuration

There are a several configuration options available. You can see all of them on a screenshot.

### Home Sector
This is a sector where the ship will rescue the crew. You can select it from the list of discovered sectors.

### Home Station
This is a station where the ship will be docked and wait for the next order. You can select it from the list of discovered stations in any sector.
The best option is to select a station in the same sector as the Home Sector.

### Ship - "Dormitory"

This is a ship where the rescued crew will be placed. You can select it from the list of your ships. The ship should enough capacity to place all rescued crews' members.

### Record to logbook

`Enabled` by default.

If enabled, the ship will record the events to the logbook. I.e. starts, travel to desired sector, flying to the target, attacking the target, destroying the target, etc. 

## Situation when both ships are full
The ship's captain will periodically call to the player to inform about absence of the order. Additionally, if the Record to logbook is enabled - it will be recorded there as well.