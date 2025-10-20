--@ module = true

-- Core
version = "0.1.0"
DFVersion = "0.47.05"
modKey = "witchen-mechanica"

-- Turrets
perturbedTargetVectorLength = 1000 -- Due to integer-only target locations
squadRoomIsTurretFlagKey = 31
turretCooldownMachineInfoBitsStart = 26
turretCooldownMachineInfoBitsEnd = 31
turretCooldownTimerLength = 3
turretMagicPuffSize = 50

-- Hoppers
hopperTimerLength = 20
hopperMaxItemCapacity = 4 -- Count, not volume

-- Automata
automatonPylonRadius = 12
automatonWorkSmallMagicPuffChance = 0.02
automatonWorkLargeMagicPuffChance = 0.005
automatonWorkSmallMagicPuffSize = 6
automatonWorkLargeMagicPuffSize = 12
