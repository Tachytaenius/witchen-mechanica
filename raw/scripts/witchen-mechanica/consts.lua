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
hopperRepeatInterval = 20
hopperMaxItemCapacity = 4 -- Count, not volume

-- Automata
automatonPylonRadius = 12
automatonWorkSmallMagicPuffChance = 0.02
automatonWorkLargeMagicPuffChance = 0.005
automatonWorkSmallMagicPuffSize = 6
automatonWorkLargeMagicPuffSize = 12

-- Medical
administerMedicationReactionName = "ADMINISTER_MEDICATION"
restConscious = true -- Stop resting in hospital from causing unconsciousness that zeroes pain. Note that this means that resting units can be made to move to burrows (if the require recovery flag in the health struct is not set) etc
enablePainFix = true -- Stop gruesome wounds from becoming painless rapidly, to make pain relief meaningfully useful
enableBringToBedWhenRestingOnFloor = true -- Pick up resting units who aren't resting in a bed when there is an available hospital bed. Useful because anaesthesia can only be performed at buildings (beds being the obvious choice) due to technical reasons
enableMedicationFailureAnnouncements = false
woundPainInitialisedBit = 23
woundPainRecordBitsStart = 24
woundPainRecordBitsEnd = 31
painFixInitialRecordedPainMultiplier = 0.8
painFixRepeatInterval = 6 -- Best to keep this low. The higher it is the less performance impact the pain fix will have, but the lower it is the more precise we can be about recorded pain.
painFixDecrementRate = 20 -- Every n pain fix repeats, decrement by the decrement amount
painFixDecrementAmount = 1 -- Every painFixRepeatInterval * painFixDecrementRate ticks
internalAnalgesicPainThreshold = 22 -- If local anaesthetic can't be applied to a body part because it's internal (and general anaesthesia isn't to be used)
bodyPartLocalAnaestheticPainThreshold = 18
generalAnaestheticPainThreshold = 54
applicationTypePriority = {"contact", "ingested", "inhaled", "injected"}
painRewindChancePerTick = 1 - 1 / 40
handleFlooredRestingRepeatInterval = 250
checkMedicationNeededRepeatInterval = 150

-- Game's own value(s)
sleepinessTimerDecrease = 19 -- Presumably the sleepiness timer goes up by 1 and is then lowered by 20...?
painUnconsciousThreshold = 100
painLimit = 200
gamePainReductionChancePerTick = 1 / 30 -- At default rate. Source is Putnam
