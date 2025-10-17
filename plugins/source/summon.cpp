// Used for summoning units in v0.47.05 in a way that is safe for use within event hooks etc, unlike modtools/create-unit (related to core (un)suspension)
// By Tachytaenius

#include <string>
#include <vector>

#include "PluginManager.h"
#include "VersionInfo.h"
#include "MiscUtils.h"

#include "df/world.h"
#include "df/unit.h"
#include "df/interaction_effect_summon_unitst.h"

using std::string;
using std::vector;

using namespace DFHack;

DFHACK_PLUGIN("summon");

static command_result do_command(color_ostream &out, vector<string> &parameters);

DFhackCExport command_result plugin_init(color_ostream &out, std::vector <PluginCommand> &commands) {
    commands.push_back(PluginCommand(
        plugin_name,
        "Usage: summon raceId casteId x y z",
        do_command));

    return CR_OK;
}

static intptr_t getRebaseDelta() {
	return Core::getInstance().vinfo->getRebaseDelta();
}

static command_result do_command(color_ostream &out, vector<string> &parameters) {
	// TODO: Actual argument parameter checking etc so's not to crash
	if (parameters.size() != 5) {
		out.printerr("Usage: summon raceId casteId x y z\n");
		return CR_FAILURE;
	}

	int32_t raceId = std::stoi(parameters[0]);
	int16_t casteId = std::stoi(parameters[1]);
	int16_t x = std::stoi(parameters[2]);
	int16_t y = std::stoi(parameters[3]);
	int16_t z = std::stoi(parameters[4]);

	CoreSuspender suspend;

	auto interactionEffect = df::allocate<df::interaction_effect_summon_unitst>();
	interactionEffect->unk_1.push_back(raceId);
	interactionEffect->unk_2.push_back(casteId);

	// Credit to Quietust for finding the addresses!
	// TODO: Test all.
	#if defined(_WIN32)
		#ifdef DFHACK64
			size_t address = 0x1402066f0;
		#else
			size_t address = 0x005b8840;
		#endif
	#elif defined(_DARWIN)
		#ifdef DFHACK64
			size_t address = 0x10025b750;
		#else
			size_t address = 0x002a12d0;
		#endif
	#elif defined(_LINUX)
		#ifdef DFHACK64
			size_t address = 0x004f5b10;
		#else
			size_t address = 0x08161d60;
		#endif
	#else
		#error Unknown OS
	#endif

	typedef void (THISCALL *summonUnitFunc)(
		df::world *,
		df::unit *,
		df::interaction_effect_summon_unitst *,
		short,
		short,
		short
	);
	summonUnitFunc summonUnit = (summonUnitFunc)(address + getRebaseDelta());
	summonUnit(df::global::world, nullptr, interactionEffect, x, y, z);

	delete interactionEffect;

	return CR_OK;
}
