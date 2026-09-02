-- Nothing to aim at
--
-- The rung of Buttons/Slot.lua's ladder that Blizzard's own bar does not have.
-- IsUsableAction knows nothing about the target and their button colours off
-- that call alone, so a Flame Shock in an inn drew ready on their bar and on
-- this one. The rung reads one more fact off the client, whether the slot is
-- an attack, and every edge of that fact is driven here: no target, a friendly
-- one, a dead one, where the rung sits against the others, and the two shapes
-- a macro takes.
--
-- Its own section rather than the tail of the square's, because that file is
-- at its line budget and the question here is one the client's bar never asks.
-- It reads the slot the square section left primed and puts it back empty.

local H = ...
local guids, ns, check = H.guids, H.ns, H.check

local Slot = ns.Slot
local slots = _G.WarriorKitSlots
local SLOT = 1
local ART = "Interface\\Icons\\Ability_Warrior_Charge"

local function put(fields)
	slots[SLOT] = fields
end

local deadUnits, friendlyUnits = _G.WarriorKitDeadUnits, _G.WarriorKitFriendlyUnits
local macroSpells = _G.WarriorKitMacroSpells
local harmfulSpells = _G.WarriorKitHarmfulSpells
local MOB = "Creature-0-0-0-0-1234-00000099"

guids.target = nil
put({ texture = ART, harmful = true })
check(Slot.State(SLOT) == "notarget",
	"an attack with nothing targeted is drawn ready, which is the whole bug")

-- A heal, a shield or a totem is not an attack, and with nothing selected
-- the press still does something, so the square stays lit.
put({ texture = ART })
check(Slot.State(SLOT) == "ready", "a spell that needs no target is gated on having one")

-- Something you may not hit is nothing to aim at either.
guids.target = MOB
friendlyUnits.target = true
put({ texture = ART, harmful = true })
check(Slot.State(SLOT) == "notarget", "an attack aimed at something friendly is drawn ready")
friendlyUnits.target = nil
deadUnits.target = true
check(Slot.State(SLOT) == "notarget", "an attack aimed at a corpse is drawn ready")
deadUnits.target = nil

-- With a live enemy selected the rung is silent and range has the square.
put({ texture = ART, harmful = true, range = 0 })
check(Slot.State(SLOT) == "range", "an attack on a live enemy is being gated on something other than range")
put({ texture = ART, harmful = true, range = 1 })
check(Slot.State(SLOT) == "ready", "an attack on a live enemy in range is not drawn ready")

-- Where it sits. A click on something fixes it and no amount of rage does,
-- so it outranks cost and stance; a real cooldown still outranks it,
-- because the swipe counts that one down and nothing counts this one.
guids.target = nil
put({ texture = ART, harmful = true, usable = false, noPower = true })
check(Slot.State(SLOT) == "notarget", "no rage is being reported ahead of nothing to hit")
put({ texture = ART, harmful = true, usable = false, noPower = false })
check(Slot.State(SLOT) == "notarget", "the wrong stance is being reported ahead of nothing to hit")
put({ texture = ART, harmful = true, start = _G.GetTime(), duration = 6 })
check(Slot.State(SLOT) == "cooldown", "nothing to hit is being reported ahead of a real cooldown")

-- A macro is asked about its spell, not about itself. The slot says it is
-- not an attack and the spell behind it says it is, and the spell wins.
macroSpells[3] = "Flame Shock"
harmfulSpells["Flame Shock"] = true
put({ texture = ART, macro = 3 })
check(Slot.State(SLOT) == "notarget",
	"an attack behind a macro is drawn ready with nothing targeted, because the slot was asked and not the spell")
harmfulSpells["Flame Shock"] = nil
check(Slot.State(SLOT) == "ready", "a macro whose spell is not an attack is gated on a target")

-- And one with no spell behind it falls back to the slot, as the usable
-- rung does.
macroSpells[3] = nil
put({ texture = ART, macro = 3, harmful = true })
check(Slot.State(SLOT) == "notarget", "a macro with no spell behind it stopped asking the slot as well")

slots[SLOT] = nil

print("aimed  an attack with nothing to hit reads notarget; a heal, a totem and a macro with no attack behind it stay ready")
