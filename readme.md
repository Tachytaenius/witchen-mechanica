# Witchen Mechanica

A magic-themed Dwarf Fortress tech/automation mod by Tachytaenius.
Requires DFHack.

There is no information about versioning, changelogging, or releasing yet.
It'll probably be taken from the mod Tachy Guns.

## Installation

- Merge `raw` with your DF(Hack) installation's `raw`.
- Paste the contents of `add-to-entity.txt` into the entity definition for whichever type of civilisation you want to have access to the mod's features.
	Likely `MOUNTAIN`, for vanilla dwarves.
	Note that it's wise to keep these lines together for updating or uninstalling the mod.

Now a new world should have access to the mod's features.

## Uninstallation

- Search for "witchen_mechanica" in your DF(Hack) installation's `raw/objects` and delete the text files in there.
- Delete `raw/init.d/init-witchen-mechanica.lua`.
- Delete `raw/scripts/witchen-mechanica.lua`.
- Delete `raw/scripts/witchen-mechanica` (a directory).
- Delete the lines from the `add-to-entity.txt` files from your entity definitions.
