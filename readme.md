# Witchen Mechanica

A magic-themed Dwarf Fortress tech/automation mod by Tachytaenius.
Requires DFHack.

Not finished or ready to play!

There is no information about versioning, changelogging, or releasing yet.
It'll probably be taken from the mod Tachy Guns.

## Installation

A plugin (`v47utils`) is required to get creating units to work reliably in certain conditions (by calling DF's own code), and is also used to cancel jobs properly.
It won't be required in future versions of DFHack.

- The script `signal-mechanics` and its dependency `site-load-detector` are also required.
They can be found [here](https://github.com/Tachytaenius/df-hacking-modding/blob/v47/signal-mechanics.lua) and [here](https://github.com/Tachytaenius/df-hacking-modding/blob/v47/site-load-detector.lua).
Once installed as scripts, place these lines in `dfhack-config/init/onLoad.init`:
`enable site-load-detector`, then
`enable signal-mechanics`
- Assuming there is no `v47utils` plugin already, copy the built `v47utils` plugin from the folder appropriate to your build of DF in my plugins folder [here](https://github.com/Tachytaenius/df-hacking-modding/tree/v47/plugins/build) and paste it into `hack/plugins` in your DF(Hack) installation.
- Merge `raw` with your DF(Hack) installation's `raw`.
- Paste the contents of `add-to-entity.txt` into the entity definition (under `raw/entity_*.txt`) for whichever type of civilisation you want to have access to the mod's features.
	Likely `MOUNTAIN`, for vanilla dwarves.
	Note that it's wise to keep these lines together for updating or uninstalling the mod.

Now a new world should have access to the mod's features.

## Uninstallation

In your DF(Hack) installation,
- If you are sure nothing else uses it, delete the scripts `signal-mechanics` and `site-load-detector` and remove their enablement lines from `dfhack-config/init/onLoad.init`.
- If you are sure nothing else uses it, delete `hack/plugins/v47utils.plug.*`.
- Delete the files `raw/objects/*witchen_mechanica*.txt` (where `raw` is *not* within a world save).
- Delete `raw/init.d/init-witchen-mechanica.lua`.
- Delete `raw/scripts/witchen-mechanica.lua`.
- Delete `raw/scripts/witchen-mechanica` (a directory).
- Delete the lines from the `add-to-entity.txt` files from your entity definitions.

## Updating

Uninstall then reinstall, to be sure. Just overwriting is not necessarily safe, if any files were moved/deleted.
