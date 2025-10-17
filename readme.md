# Witchen Mechanica

A magic-themed Dwarf Fortress tech/automation mod by Tachytaenius.
Requires DFHack.

Not finished or ready to play!
The plugin and its builds are unfinished!

There is no information about versioning, changelogging, or releasing yet.
It'll probably be taken from the mod Tachy Guns.

## Installation

A plugin (`summon`) is required to get creating units to work reliably in certain conditions.
It calls code within the DF executable, but won't be required in future versions of DFHack.

- Assuming there is no `summon` plugin already, copy the built plugin from the folder appropriate to your build of DF in `plugins/build` and paste it into `hack/plugins` in your DF(Hack) installation.
- Merge `raw` with your DF(Hack) installation's `raw`.
- Paste the contents of `add-to-entity.txt` into the entity definition (under `raw/entity_*.txt`) for whichever type of civilisation you want to have access to the mod's features.
	Likely `MOUNTAIN`, for vanilla dwarves.
	Note that it's wise to keep these lines together for updating or uninstalling the mod.

Now a new world should have access to the mod's features.

## Uninstallation

In your DF(Hack) installation,
- Delete `hack/plugins/summon.plug.*`.
- Delete the files `raw/objects/*witchen_mechanica*.txt`.
- Delete `raw/init.d/init-witchen-mechanica.lua`.
- Delete `raw/scripts/witchen-mechanica.lua`.
- Delete `raw/scripts/witchen-mechanica` (a directory).
- Delete the lines from the `add-to-entity.txt` files from your entity definitions.

## Updating

Uninstall then reinstall, to be sure. Just overwriting is not necessarily safe, if any files were moved/deleted.

## Building the Plugin

TODO
