-- Which opener, by stance and by what is trained
--
-- One button, three openers, and which one a press casts used to be decided by
-- combat and the cursor alone. Out of combat that was always Charge with a
-- swap to Battle Stance under it, so a fury warrior standing in Berserker
-- Stance paid a press and the rage on every pull for an ability the stance
-- they stood in already had. And nothing asked whether an opener was trained:
-- a level twenty warrior in a fight saw Intervene, fifty levels away, drawn as
-- unknown, and the macro carried a line for it.
--
-- So the stance decides and the spellbook gates, and this section drives every
-- edge of that: each stance out of combat, each stance in a fight with a mob, a
-- party member and nothing under the cursor, and each opener taken out of the
-- book. The macro is read back too, because the icon and the press have to
-- agree and the macro is where the press is.
--
-- The scene is put back the way it was found: combat, stance, the cursor and
-- the book are all shared with what runs after.

local H = ...
local ns, check, fire, advance = H.ns, H.check, H.fire, H.advance
local guids, inCombat, own = H.guids, H.inCombat, H.own

-- Warrior only, decided at login. 21-which-class proves the button is absent
-- on the other runs, and there is nothing here to read on them.
if ns.Charge.Available() then

local Charge = ns.Charge
local button = _G.WarriorKitChargeButton
local shapeshift = _G.WarriorKitShapeshift
local friendlyUnits = _G.WarriorKitFriendlyUnits

local MOB = "Creature-0-0-0-0-1234-00000077"
local MATE = "Player-1-00000078"

local was = {
	combat = inCombat.player, form = shapeshift.form,
	mouseover = guids.mouseover, target = guids.target,
	friendly = friendlyUnits.mouseover, party = _G.UnitPlayerOrPetInParty,
}

-- Every answer here is memoised per frame, so each question is asked on a
-- frame of its own.
local function state()
	advance(0.1)
	local key, unit = Charge.Pick()
	return key, unit, (Charge.State(key, unit))
end

local function macro()
	advance(0.1)
	ns.ChargeIcon.SyncMacro()
	return button:GetAttribute("macrotext") or ""
end

local function has(text, line)
	return text:find(line, 1, true) ~= nil
end

-- Taken out of the book or put back, by the ranks the class file lists, which
-- is the list Charge.Known walks. Names are read off the same file, because
-- the stub names a spell by its id and the macro is written in those names.
local function trained(key, yes)
	for _, id in ipairs(Charge.Ability(key).ranks) do
		own.unknown[id] = (not yes) or nil
	end
	fire("SPELLS_CHANGED")
end

local function name(key)
	return Charge.Name(key)
end

local function stance(index)
	return Charge.StanceName(index)
end

-- The cursor is over a party member. Assistable reads group membership off
-- this call, and the stub's flat false left Intervene unreachable.
local function mate(under)
	if under then
		guids.mouseover, friendlyUnits.mouseover = MATE, true
		_G.UnitPlayerOrPetInParty = function(unit) return unit == "mouseover" end
	else
		guids.mouseover, friendlyUnits.mouseover = nil, nil
		_G.UnitPlayerOrPetInParty = was.party
	end
end

guids.target = nil
guids.mouseover = MOB
friendlyUnits.mouseover = nil

--------------------------------------------------------------------------
-- The pull
--------------------------------------------------------------------------

inCombat.player = nil

shapeshift.form = 1
local key, unit, status = state()
check(key == "charge" and unit == "mouseover",
	("in Battle Stance the pull is %s on %s, not Charge on the mob under the cursor")
		:format(key, tostring(unit)))
check(status == "ready", ("Charge on a mob in Battle Stance is drawn %s"):format(status))

shapeshift.form = 3
key, unit, status = state()
check(key == "intercept" and unit == "mouseover",
	("in Berserker Stance the pull is %s on %s, not Intercept on the mob under the cursor")
		:format(key, tostring(unit)))
check(status == "ready",
	("Intercept out of combat is drawn %s, as if it needed a fight"):format(status))

shapeshift.form = 2
key, unit, status = state()
check(key == "charge",
	("in Defensive Stance the pull is %s, not Charge with the swap under it"):format(key))
check(status == "stance",
	("the swap Defensive Stance pays for Charge is drawn %s"):format(status))

local text = macro()
check(has(text, "/cast [nocombat,stance:3] " .. name("intercept")),
	"the macro has no Intercept for a pull from Berserker Stance")
check(has(text, "/cast [nocombat,nostance:1/3] " .. stance(1)),
	"the Battle Stance swap is not written to leave Berserker Stance alone")
check(has(text, "/cast [nocombat,nostance:3] " .. name("charge")),
	"Charge is written to fire on the same press as Intercept")
check(has(text, "/cast [combat,@mouseover,harm,nodead] " .. name("intercept"))
	and has(text, "/cast [combat,@mouseover,help,nodead] " .. name("intervene")),
	"the fight's half of the macro lost a line")

--------------------------------------------------------------------------
-- The fight
--------------------------------------------------------------------------

inCombat.player = true

shapeshift.form = 3
key, unit, status = state()
check(key == "intercept" and unit == "mouseover" and status == "ready",
	("a mob under the cursor in Berserker Stance is %s on %s, %s"):format(key, tostring(unit), status))

shapeshift.form = 1
key, unit, status = state()
check(key == "intercept" and status == "stance",
	("a mob under the cursor in Battle Stance is %s, %s, not Intercept behind a swap"):format(key, status))

mate(true)
shapeshift.form = 2
key, unit, status = state()
check(key == "intervene" and unit == "mouseover" and status == "ready",
	("a party member under the cursor in Defensive Stance is %s on %s, %s"):format(key, tostring(unit), status))

shapeshift.form = 3
key, unit, status = state()
check(key == "intervene" and status == "stance",
	("a party member under the cursor in Berserker Stance is %s, %s, not Intervene behind a swap"):format(key, status))
mate(false)

-- Nothing under the cursor: the opener your own stance owns, and Intercept
-- from Battle Stance, which owns none in a fight.
shapeshift.form = 2
key, unit, status = state()
check(key == "intervene" and unit == nil and status == "notarget",
	("an empty cursor in Defensive Stance shows %s on %s, %s"):format(key, tostring(unit), status))

shapeshift.form = 3
key, unit, status = state()
check(key == "intercept" and unit == nil and status == "notarget",
	("an empty cursor in Berserker Stance shows %s on %s, %s"):format(key, tostring(unit), status))

shapeshift.form = 1
key = state()
check(key == "intercept", ("an empty cursor in Battle Stance shows %s"):format(key))

--------------------------------------------------------------------------
-- What is not in the book
--------------------------------------------------------------------------

-- Fifty levels short of Intervene. A party member under the cursor is a mob's
-- opener greyed, never an ability that cannot be cast.
trained("intervene", false)
mate(true)
shapeshift.form = 2
key, unit = state()
check(key ~= "intervene",
	"an untrained Intervene is picked for a party member under the cursor")
check(unit == nil, ("an untrained Intervene still takes %s"):format(tostring(unit)))
mate(false)
text = macro()
check(not has(text, name("intervene")), "the macro carries a line for an untrained Intervene")

-- And thirty short of Intercept. The fight shows Charge, greyed for being in
-- one, and the macro's fight half is empty.
trained("intercept", false)
guids.mouseover = MOB
shapeshift.form = 1
key, unit, status = state()
check(key == "charge" and status == "combat",
	("a warrior with only Charge sees %s, %s, in a fight"):format(key, status))
text = macro()
check(not has(text, name("intercept")), "the macro carries a line for an untrained Intercept")
check(has(text, "/cast [nocombat,nostance:1] " .. stance(1)) and has(text, "/cast [nocombat] " .. name("charge")),
	"with Intercept untrained the Charge lines still make room for it")

-- Standing in Berserker Stance without Intercept cannot happen in the game,
-- since the stance is the prerequisite, and the answer is still the honest
-- one: Charge, behind the swap.
inCombat.player = nil
shapeshift.form = 3
key, unit, status = state()
check(key == "charge" and status == "stance",
	("Berserker Stance without Intercept picks %s, %s"):format(key, status))

-- Level one. Nothing to cast, and the macro says so by casting nothing.
trained("charge", false)
shapeshift.form = 1
key, unit, status = state()
check(key == "charge" and status == "unknown",
	("a warrior with no opener sees %s, %s"):format(key, status))
text = macro()
check(not has(text, "/cast "), "the macro casts something for a warrior who has trained nothing")

--------------------------------------------------------------------------
-- Put back
--------------------------------------------------------------------------

trained("charge", true)
trained("intercept", true)
trained("intervene", true)
inCombat.player = was.combat
shapeshift.form = was.form
guids.mouseover, guids.target = was.mouseover, was.target
friendlyUnits.mouseover = was.friendly
_G.UnitPlayerOrPetInParty = was.party
macro()

print("stance Intercept from Berserker Stance, Charge behind the swap from the other two; three openers gated on the book, the macro with them")

end
