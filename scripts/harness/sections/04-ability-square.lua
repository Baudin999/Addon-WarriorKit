-- The ability square
--
-- UI/Ability.lua and the two sources that feed it, Charge/Charge.lua for the
-- three charge abilities and Buttons/Slot.lua for an action slot.
--
-- Four things are checked and none of them is visible in a screenshot.
--
-- A look is a reference. Every ticker that draws a square guards its writes by
-- comparing the look it is about to draw against the one it drew last, and for
-- a table that comparison is identity. A palette that built its answers would
-- look right and would repaint every square five times a second forever, which
-- is the exact defect UI/Gauge.lua's section above tests the unit palette for.
--
-- Every status has a look. The vocabulary is a table in one file and the two
-- sources return strings; nothing but a test connects the two, and a source
-- that invented a ninth status would draw it as "no" and nobody would know.
--
-- The ladder's order. Slot.State's whole design is which of two true things it
-- says first, so every rung is driven and the ones that shadow each other are
-- driven together.
--
-- And that a redraw of an unchanged square writes nothing at all.

local H = ...
local WARRIOR, guids, inCombat = H.WARRIOR, H.guids, H.inCombat
local advance, logArgs, ns = H.advance, H.logArgs, H.ns
local fire, check = H.fire, H.check

local Ability = ns.UI.Ability
local Slot = ns.Slot

-- Every status the vocabulary names has a look in both shipped palettes,
-- and the same status hands back the same table every time.
local missing, unstable, named = 0, 0, 0
for status in pairs(Ability.STATUS) do
	named = named + 1
	for _, palette in ipairs({ Ability.SHOUT, Ability.QUIET }) do
		local look = Ability.Look(palette, status)
		if type(look) ~= "table" or type(look.color) ~= "table" or not look.alpha then
			missing = missing + 1
		elseif look ~= Ability.Look(palette, status) then
			unstable = unstable + 1
		end
	end
end
check(missing == 0, ("%d statuses have no look"):format(missing))
check(unstable == 0, ("%d looks are rebuilt per call, so no guard can hold"):format(unstable))

-- The two palettes are different tables all the way down, so editing one
-- cannot move the other. They ship with two of the five outcomes sharing a
-- colour by value and that is a choice; sharing one by reference would be
-- an accident waiting to be found in six months.
local shared = 0
for _, outcome in ipairs({ "go", "swap", "range", "cost", "empty", "no" }) do
	if Ability.SHOUT[outcome] == Ability.QUIET[outcome]
		or Ability.SHOUT[outcome].color == Ability.QUIET[outcome].color then
		shared = shared + 1
	end
end
check(shared == 0, ("%d looks are shared between the two palettes by reference"):format(shared))

-- Ready is the loud one on the HUD and the quiet one on a bar. That is the
-- whole reason there are two palettes rather than one, so it is asserted
-- rather than left as a comment.
check(Ability.SHOUT.go.alpha == 1 and Ability.QUIET.go.alpha == 1,
	"a ready square is drawn at full alpha in both palettes")
check(Ability.SHOUT.no.grey and Ability.QUIET.no.grey,
	"a square that does nothing is desaturated in both palettes")

-- The bars draw no rage bar and no mana bar, so what you can afford is
-- readable off the squares or nowhere. A blue hairline alone is a thing you
-- go looking for; the drain is what answers at a glance.
check(Ability.SHOUT.cost.grey and Ability.QUIET.cost.grey,
	"a spell you cannot afford is drawn in full colour, and there is no resource bar to read instead")
check(not Ability.SHOUT.range.grey and not Ability.QUIET.range.grey,
	"out of range drains the art too, so it cannot be told from out of rage")
check(Ability.SHOUT.range.color ~= Ability.SHOUT.no.color,
	"out of range is its own colour and not the grey everything else falls to")

-- Wrong stance drains too, and it shipped not draining. That is the one
-- outcome in the table where the press will not land and the art was drawn at
-- ready brightness anyway, so the whole of what the square said was an orange
-- hairline and a Whirlwind in Battle Stance read as pressable across the room.
-- The rule the rest of the table follows: a fact about you drains, a fact
-- about the mob does not.
check(Ability.SHOUT.swap.grey and Ability.QUIET.swap.grey,
	"the wrong stance is drawn in full colour, so a press that cannot land looks like one that can")

-- The two statuses the client has no opinion about fall to the plain no, for
-- the reason a shut reaction window does: neither is a state you can act on,
-- so there is nothing for a colour to tell you to do.
for _, status in ipairs({ "condition", "notarget", "reaction" }) do
	check(Ability.Look(Ability.QUIET, status) == Ability.QUIET.no,
		("%s is drawn as something other than the plain no"):format(status))
end

-- An empty slot draws no art in either palette. Without this it fell to
-- "no", which has no `blank`, and twelve empty slots came up as twelve grey
-- question marks: the defect that made a half filled bar read as broken.
check(Ability.SHOUT.empty.blank and Ability.QUIET.empty.blank,
	"an empty slot still draws the fallback question mark in one of the palettes")
check(not Ability.Look(Ability.QUIET, "cooldown").blank,
	"a square on cooldown is drawn blank, so the art vanishes mid-fight")

--------------------------------------------------------------------------
-- The slot ladder
--------------------------------------------------------------------------

local slots = _G.WarriorKitSlots
local SLOT = 1

local function put(fields)
	slots[SLOT] = fields
end

-- Before anything asks whether the slot can be read, because "nobody has
-- asked yet" and "this client cannot" used to be the same answer here. Every
-- reader guarded on the raw probe, the probe was nil until something called
-- CanRead, and the only caller that did was Bars.Describe. So the bars came
-- up blank on every login and filled in the moment you typed /wk, and this
-- file could not see it because the line below primes the probe for the rest
-- of the run. It has to be the first thing the ladder does or it proves
-- nothing.
put({ texture = "Interface\\Icons\\Ability_Warrior_Charge" })
check(Slot.State(SLOT) ~= "empty",
	"a filled slot reads as empty until something else asks whether slots can be read")
check(Slot.Texture(SLOT) ~= nil,
	"a filled slot has no art until something else asks whether slots can be read")
slots[SLOT] = nil

check(Slot.CanRead(), "this stub client cannot read an action slot: " .. Slot.Describe())

slots[SLOT] = nil
check(Slot.State(SLOT) == "empty", "a slot with nothing in it is not empty")

put({})
check(Slot.State(SLOT) == "unknown", "a slot the client has no art for is not unknown")

-- Every rung below has art, so "unknown" is behind it and each answer is
-- the rung being tested rather than the one above it.
local ART = "Interface\\Icons\\Ability_Warrior_Charge"

put({ texture = ART })
check(Slot.State(SLOT) == "ready", "a slot with nothing wrong with it is not ready")
check(Slot.Texture(SLOT) == ART, "the slot's art is not read back")

-- The global is not a status and is still a swipe. Both halves are checked,
-- because the bug they replace was the swipe being withheld along with the
-- status, which left a press with nothing on screen to answer it.
put({ texture = ART, start = _G.GetTime(), duration = 1.5 })
local status, start, duration = Slot.State(SLOT)
check(status == "ready", "the global cooldown is being drawn as a cooldown")
check(start == _G.GetTime() and duration == 1.5,
	"the global's numbers are withheld, so a press draws no swipe at all")

-- And the numbers ride whatever the rest of the ladder decided, not just
-- "ready". A spell you cannot afford is still sweeping.
put({ texture = ART, start = _G.GetTime(), duration = 1.5, usable = false, noPower = true })
status, start, duration = Slot.State(SLOT)
check(status == "cost" and start == _G.GetTime() and duration == 1.5,
	"the global's swipe is dropped on any rung below ready")

put({ texture = ART, start = _G.GetTime(), duration = 1.6 })
status, start, duration = Slot.State(SLOT)
check(status == "cooldown", "a real cooldown is not reported as one")
check(start == _G.GetTime() and duration == 1.6, "the cooldown's own numbers are not passed through")

-- Nothing running means no swipe, which is what clears one that has ended.
put({ texture = ART })
status, start, duration = Slot.State(SLOT)
check(status == "ready" and start == nil and duration == nil,
	"a slot with no cooldown running is handing back numbers to sweep")

-- Already what is running. Two client calls folded into one answer, so both
-- are driven and the fold is what is checked rather than either call.
check(not Slot.Active(SLOT), "an idle slot is drawn as already running")
put({ texture = ART, current = true })
check(Slot.Active(SLOT), "the stance you are standing in is not drawn as active")
put({ texture = ART, repeating = true })
check(Slot.Active(SLOT), "an auto attack already swinging is not drawn as active")

-- Worn, which is a fact about the item and not a rung on the ladder, so it
-- is driven against a slot that is also on cooldown and unusable. All three
-- have to be sayable at once.
put({ texture = ART })
check(not Slot.Equipped(SLOT), "a slot holding nothing worn is drawn with the ring")
put({ texture = ART, equipped = true, usable = false, noPower = true,
	start = _G.GetTime(), duration = 30 })
check(Slot.Equipped(SLOT), "a wielded weapon draws no equipped ring")
check(Slot.State(SLOT) == "cooldown",
	"being equipped moved the slot off the rung it was on")

-- Cost and stance are the same "not usable" from the client and the second
-- return is the only thing that tells them apart. Both are driven, because
-- collapsing them is the mistake this split exists to prevent.
put({ texture = ART, usable = false, noPower = true })
check(Slot.State(SLOT) == "cost", "no rage is not reported as cost")
put({ texture = ART, usable = false, noPower = false })
check(Slot.State(SLOT) == "stance", "the wrong stance is not reported as stance")

-- Cooldown outranks both, because a spell you cannot afford and which is
-- also on cooldown is one to wait for rather than one to build rage for.
put({ texture = ART, start = _G.GetTime(), duration = 6, usable = false, noPower = true })
check(Slot.State(SLOT) == "cooldown", "cost is being reported ahead of cooldown")

--------------------------------------------------------------------------
-- What is in the slot, and the macro that used to hide it
--
-- GetActionInfo answers "macro" and an index, and every reader in the addon
-- used to stop there. The warrior plan puts five of its twelve bar 1 keys in
-- macros, so both of the gates that outrank the client had a hole in them
-- exactly where the loadout puts things.
--------------------------------------------------------------------------

do
	local macroSpells = _G.WarriorKitMacroSpells
	local unusableSpells = _G.WarriorKitUnusableSpells

	put({ texture = ART, spell = 1464 })
	check(Slot.Spell(SLOT) == "Spell1464", "a slot holding a plain spell does not name it")

	put({ texture = ART, macro = 3 })
	check(Slot.Spell(SLOT) == nil, "a macro the client resolves to nothing is being named as a spell")

	macroSpells[3] = "Shield Bash"
	local behind, viaMacro = Slot.Spell(SLOT)
	check(behind == "Shield Bash", "a macro's conditionals are not resolved to the spell behind them")
	check(viaMacro, "a macro square is not reported as one, so the ladder asks the wrong call about it")

	-- Which is the whole reason the usable rung asks about the spell. The slot
	-- answers for the macro and not for what the macro would cast, so a Shield Bash
	-- behind #showtooltip drew pressable with no shield on: the slot says fine and
	-- the spell says no.
	unusableSpells["Shield Bash"] = "other"
	check(Slot.State(SLOT) == "stance",
		"a macro whose spell the client refuses is drawn ready, because the slot was asked and not the spell")
	unusableSpells["Shield Bash"] = "power"
	check(Slot.State(SLOT) == "cost", "a macro's spell has no rage and the square will not say so")
	unusableSpells["Shield Bash"] = nil
	check(Slot.State(SLOT) == "ready", "a macro whose spell is fine is not drawn ready")

	-- A macro with no spell behind it falls back to the slot, which is the honest
	-- answer: a /startattack with no /cast in it has no spell to ask about.
	macroSpells[3] = nil
	put({ texture = ART, macro = 3, usable = false, noPower = true })
	check(Slot.State(SLOT) == "cost",
		"a macro with no spell behind it stopped asking the slot as well")
end

--------------------------------------------------------------------------
-- Range, and the client that never answers
--------------------------------------------------------------------------

-- With nothing targeted the question is not asked at all. Without that
-- guard every button answers nil on every tick you stand around untargeted,
-- and the fortieth nil prints a warning about a client fault that is not
-- one. Twenty-four buttons reach forty in under a second.
guids.target = nil
put({ texture = ART, range = 0 })
check(Slot.State(SLOT) == "ready",
	"a slot is out of range with nothing targeted, which is not a distance")

guids.target = "Creature-0-0-0-0-1234-00000099"
check(Slot.State(SLOT) == "range", "an out of range target is not reported as range")

put({ texture = ART, range = 1 })
check(Slot.State(SLOT) == "ready", "an in range target is not reported as ready")

-- nil is not out of range. Both calls answer it for honest reasons: the
-- action has no range, the unit cannot take it, the client has not decided.
put({ texture = ART, range = nil })
check(Slot.State(SLOT) == "ready", "an unanswered range check is blocking the square")

--------------------------------------------------------------------------
-- The reaction window
--
-- Overpower is not a spell you press, it is a spell the fight hands you for
-- a few seconds after the mob dodges. The client does not know that:
-- IsUsableAction says yes for the whole fight, which is why the square was
-- drawn ready for the whole fight, and why nothing in this file could catch
-- it until the stub grew a combat log the slot ladder reads.
--
-- Driven rather than described, because the mechanism is four things and
-- every one of them is a place to be wrong: the dodge opens it, the clock
-- shuts it, the press shuts it early, and somebody else's dodge is not
-- yours. Revenge is the same window off a different line, so it is driven
-- through the two shapes a block arrives in and not just the tidy one.
--------------------------------------------------------------------------

local ME = "Player-0-0000000r"
local MOB = "Creature-0-0000000r"
local OVERPOWER, REVENGE = 11585, 25288 -- a later rank of each, on purpose

-- Sixteen values matter here and each subevent puts the one this reads in a
-- different slot, so the slot is a parameter. Twelve carries an amount on a
-- swing and a spell id on anything with a spell in front of it, which is
-- what it is left holding when the test is about a later slot.
local function logLine(subevent, source, dest, at, value)
	for index = 1, 21 do
		logArgs[index] = nil
	end
	logArgs[1] = _G.GetTime()
	logArgs[2] = subevent
	logArgs[4] = source
	logArgs[8] = dest
	logArgs[12] = 300
	logArgs[at] = value
	fire("COMBAT_LOG_EVENT_UNFILTERED")
end

guids.target = nil
guids.player = ME

put({ texture = ART, spell = OVERPOWER })

if not WARRIOR then
	-- Neither ability exists on another class, so nothing is registered and
	-- no square is gated. Asserted rather than assumed, because a tracker
	-- that came up anyway would grey a square this character cannot have and
	-- would read every line of the combat log in the game to do it.
	check(not ns.Reaction.Watching(),
		"a reaction window is tracked on a class that has neither ability: " .. ns.Reaction.Describe())
	check(ns.Reaction.Of(SLOT) == nil, "a slot is read as a reaction on another class")
	check(Slot.State(SLOT) == "ready", "a square is gated on a window that could never open")
	logLine("SWING_MISSED", ME, MOB, 12, "DODGE")
	-- The warrior's own key, written out rather than read off the registry,
	-- because the point of this branch is that a class which never registered it
	-- has nothing answering to it.
	check(not ns.Reaction.Open("overpower"),
		"a dodge opened a window on a class with nothing to press")
	check(Slot.State(SLOT) == "ready", "a dodge changed a square on another class")
	put({ texture = ART })
else
	-- The key is the class's own and is read off the registry rather than
	-- written here, because Class/Warrior.lua is where a reactive ability is
	-- named now and a literal here would keep passing after that file dropped it.
	local reactive = ns.Class.Of("reactive")
	check(reactive and reactive[1] and reactive[1].key == "overpower",
		"the warrior file no longer registers Overpower as its first reactive")
	local OVERPOWER_KEY = reactive and reactive[1] and reactive[1].key

	check(ns.Reaction.Of(SLOT) == OVERPOWER_KEY,
		"a slot holding a later rank of Overpower is not recognised as Overpower")
	check(Slot.State(SLOT) == "reaction",
		"Overpower is drawn ready with nothing having dodged you, which is the whole bug")

	-- Nothing to hit outranks a shut window: a window read off no unit is not
	-- a fact, and a click fixes one of the two.
	put({ texture = ART, spell = OVERPOWER, harmful = true })
	check(Slot.State(SLOT) == "notarget", "a shut window is being reported ahead of nothing to hit")
	put({ texture = ART, spell = OVERPOWER })

	-- Somebody else's fight does not arm your button.
	logLine("SWING_MISSED", "Player-0-0000009r", MOB, 12, "DODGE")
	check(Slot.State(SLOT) == "reaction", "a stranger's attack being dodged opened your window")

	-- And neither does a miss that is not a dodge.
	logLine("SWING_MISSED", ME, MOB, 12, "PARRY")
	check(Slot.State(SLOT) == "reaction", "a parry opened the Overpower window, and only a dodge does")

	logLine("SWING_MISSED", ME, MOB, 12, "DODGE")
	check(Slot.State(SLOT) == "ready", "the target dodged you and Overpower is still not pressable")

	advance(4.9)
	check(Slot.State(SLOT) == "ready", "the window shut before its five seconds were up")
	advance(0.2)
	check(Slot.State(SLOT) == "reaction", "the window never lapsed, so the square stays lit forever")

	-- A dodged special counts too, and it carries the miss type five slots
	-- further along. A parser reading one index for both fails here.
	logLine("SPELL_MISSED", ME, MOB, 15, "DODGE")
	check(Slot.State(SLOT) == "ready", "only a dodged white hit opens the window")

	-- Spending it shuts it. The server takes the window away on the press and
	-- says nothing, so without this the square stays lit for the rest of the
	-- five seconds after the one press it had.
	logLine("SPELL_CAST_SUCCESS", ME, MOB, 12, OVERPOWER)
	check(Slot.State(SLOT) == "reaction", "pressing Overpower left its window open")

	-- Revenge is the same window off your own block, dodge or parry. Its own
	-- clock, so opening one does not open the other.
	put({ texture = ART, spell = REVENGE })
	check(Slot.State(SLOT) == "reaction", "Revenge is drawn ready with nothing having hit you")
	logLine("SWING_MISSED", MOB, ME, 12, "DODGE")
	check(Slot.State(SLOT) == "ready", "dodging a mob did not open Revenge")

	put({ texture = ART, spell = OVERPOWER })
	check(Slot.State(SLOT) == "reaction", "your own dodge opened the Overpower window too")

	-- A block that stops the whole hit is a miss event. A block that stops part
	-- of it is a landed hit carrying a blocked amount, which is the far more
	-- common one on a tank, and it sits in slot 16 on a swing and slot 19 on a
	-- special. A parser that read only the miss events would leave Revenge dark
	-- through most of the fight it was open in.
	advance(6)
	put({ texture = ART, spell = REVENGE })
	check(Slot.State(SLOT) == "reaction", "the Revenge window never lapsed")
	logLine("SWING_DAMAGE", MOB, ME, 16, 40)
	check(Slot.State(SLOT) == "ready", "a partial block did not open Revenge")

	advance(6)
	check(Slot.State(SLOT) == "reaction", "the Revenge window never lapsed")
	logLine("SPELL_DAMAGE", MOB, ME, 19, 40)
	check(Slot.State(SLOT) == "ready", "a partially blocked special did not open Revenge")

	-- A hit you did nothing about is not a window. Slot 16 is the blocked part
	-- and slot 12 is the amount, so a parser reading the wrong one opens Revenge
	-- on every hit you take.
	advance(6)
	logLine("SWING_DAMAGE", MOB, ME, 16, 0)
	check(Slot.State(SLOT) == "reaction", "an unblocked hit opened the Revenge window")

	-- Where the rungs meet. A real cooldown outranks a shut window, because the
	-- swipe counts that one down and nothing counts this one down. A shut window
	-- outranks the wrong stance, because swapping stance would not let you press
	-- it and an orange square saying "swap" would be telling you to.
	put({ texture = ART, spell = OVERPOWER, start = _G.GetTime(), duration = 6 })
	check(Slot.State(SLOT) == "cooldown", "a shut window is being reported ahead of a real cooldown")
	put({ texture = ART, spell = OVERPOWER, usable = false, noPower = false })
	check(Slot.State(SLOT) == "reaction", "the wrong stance is being reported ahead of a shut window")

	-- And with the window open the client's own no comes back, which is what
	-- makes the orange mean something: swap now and the press lands.
	logLine("SWING_MISSED", ME, MOB, 12, "DODGE")
	check(Slot.State(SLOT) == "stance",
		"an open window hides the wrong stance, so the square never says to swap")
	put({ texture = ART, spell = OVERPOWER, usable = false, noPower = true })
	check(Slot.State(SLOT) == "cost", "an open window hides having no rage")

	-- Combat dropping shuts both. A window still open after the mob is down is
	-- a square saying press me at a corpse.
	inCombat.player = false
	fire("PLAYER_REGEN_ENABLED")
	put({ texture = ART, spell = OVERPOWER })
	check(Slot.State(SLOT) == "reaction", "the window survived the end of the fight")

	-- The same hole, on the gate above the client's. An Overpower behind
	-- #showtooltip drew ready all fight, because this file asked what spell was
	-- in the slot and a macro is not a spell.
	advance(6)
	local wrapped = _G.WarriorKitMacroSpells
	wrapped[7] = "Overpower"
	put({ texture = ART, macro = 7 })
	check(ns.Reaction.Of(SLOT) == OVERPOWER_KEY,
		"an Overpower wrapped in a macro is not recognised as Overpower")
	check(Slot.State(SLOT) == "reaction",
		"an Overpower wrapped in a macro is drawn ready with nothing having dodged you")
	logLine("SWING_MISSED", ME, MOB, 12, "DODGE")
	check(Slot.State(SLOT) == "ready", "the macro square does not open with the window")
	wrapped[7] = nil
	advance(6)

	-- Everything that is not one of the two is untouched, which is the other
	-- twenty-three squares on the bar.
	put({ texture = ART, spell = 1464 })
	check(ns.Reaction.Of(SLOT) == nil, "an ordinary spell is being tracked as a reaction")
	check(Slot.State(SLOT) == "ready", "an ordinary spell is gated on a reaction window")
	put({ texture = ART })
	check(ns.Reaction.Of(SLOT) == nil,
		"a slot the client names no spell for is being tracked as a reaction")

	check(ns.Reaction.Watching(),
		"no reaction window is tracked on a warrior: " .. ns.Reaction.Describe())
end

guids.player = nil

print(("react  %s"):format(ns.Reaction.Describe()))

--------------------------------------------------------------------------
-- What the fight has to have done first
--
-- The other half of "the client has no opinion", and a different mechanism
-- from the windows above. A reaction window lives on the server, arrives down
-- the combat log and has to be clocked. Execute's twenty percent is sitting in
-- the client the whole time and only has to be read. Both end in the same
-- place: a square that stops shouting for four fifths of every fight.
--
-- Driven rather than described, because the number is a class fact and the
-- rung's whole value is where it sits: above the split that says whether to
-- swap stance or wait for rage, since neither of those puts a mob under a
-- fifth of its health.
--------------------------------------------------------------------------

do
	local health, healthMax = _G.WarriorKitHealth, _G.WarriorKitHealthMax
	local deadUnits, friendlyUnits = _G.WarriorKitDeadUnits, _G.WarriorKitFriendlyUnits
	local EXECUTE = 20662 -- a later rank, on purpose

	guids.target = "Creature-0-0-0-0-1234-00000099"
	healthMax.target, health.target = 1000, 500
	put({ texture = ART, spell = EXECUTE })

	if not WARRIOR then
		-- No class but the warrior names a condition, so nothing is registered and
		-- no square is gated. Asserted rather than assumed, because a reader that
		-- came up anyway would grey a square on a rule this character has no
		-- ability for.
		check(not ns.Requires.Watching(),
			"a condition is read on a class that names none: " .. ns.Requires.Describe())
		check(ns.Requires.State("Execute") == nil, "a spell is gated on another class's condition")
		check(Slot.State(SLOT) == "ready", "a square is gated on a condition that could never apply")
	else
		-- The number is the class file's and is read off the registry rather than
		-- written here, because a literal would keep passing after that file moved it.
		local mine = ns.Class.Of("requires")
		check(mine and mine[1] and mine[1].spell == 5308 and mine[1].below == 20,
			"the warrior file no longer names Execute's twenty percent")

		check(Slot.State(SLOT) == "condition",
			"Execute is drawn ready at half health, which is the whole bug")

		-- Both sides of the line and the line itself. The comparison is two
		-- integers multiplied out rather than a floored percentage, because 20.1%
		-- floors to 20 and would open the square a tick before the server does.
		health.target = 201
		check(Slot.State(SLOT) == "condition", "Execute came in at 20.1%, a tick before the server")
		health.target = 200
		check(Slot.State(SLOT) == "ready", "Execute never comes in at exactly twenty percent")
		health.target = 50
		check(Slot.State(SLOT) == "ready", "Execute is gated below the threshold as well as above it")

		-- Nothing to aim it at outranks the threshold, because a threshold read off
		-- no unit is not a fact. All three shapes of no target are driven: none at
		-- all, a corpse, and something you may not swing at.
		guids.target = nil
		check(Slot.State(SLOT) == "notarget", "Execute is drawn ready with nothing targeted")
		guids.target = "Creature-0-0-0-0-1234-00000099"
		deadUnits.target = true
		check(Slot.State(SLOT) == "notarget", "Execute is drawn ready at a corpse")
		deadUnits.target = nil
		friendlyUnits.target = true
		check(Slot.State(SLOT) == "notarget", "Execute is drawn ready at something you cannot attack")
		friendlyUnits.target = nil

		-- A client that will not say what the target's health is says nothing,
		-- rather than greying a square for as long as it stays quiet.
		healthMax.target = 0
		check(Slot.State(SLOT) == "ready", "an unanswered health reading is blocking the square")
		healthMax.target, health.target = 1000, 500

		-- Where the rungs meet. A real cooldown outranks the condition, because the
		-- swipe counts that one down and nothing counts this one down.
		put({ texture = ART, spell = EXECUTE, start = _G.GetTime(), duration = 6 })
		check(Slot.State(SLOT) == "cooldown", "a condition is being reported ahead of a real cooldown")

		-- And the condition outranks the wrong stance, because swapping stance would
		-- not put the mob under a fifth of its health and an orange square saying
		-- "swap" would be telling you to.
		put({ texture = ART, spell = EXECUTE, usable = false, noPower = false })
		check(Slot.State(SLOT) == "condition", "the wrong stance is being reported ahead of a condition")
		health.target = 100
		check(Slot.State(SLOT) == "stance", "a met condition hides the wrong stance")
		health.target = 500

		-- A macro reaches this rung too, which is the whole point of resolving one.
		local wrapped = _G.WarriorKitMacroSpells
		wrapped[9] = "Execute"
		put({ texture = ART, macro = 9 })
		check(Slot.State(SLOT) == "condition",
			"an Execute wrapped in a macro is drawn ready at half health")
		wrapped[9] = nil

		-- Everything else on the bar is untouched, which is the other twenty-three
		-- squares.
		put({ texture = ART, spell = 1464 })
		check(ns.Requires.State("Spell1464") == nil, "an ordinary spell is matched to a condition")
		check(Slot.State(SLOT) == "ready", "an ordinary spell is gated on a condition")

		check(ns.Requires.Watching(),
			"no condition is read on a warrior: " .. ns.Requires.Describe())
	end

	print(("cond   %s"):format(ns.Requires.Describe()))

	-- Put the client back the way the sections after this one expect it.
	health.target, healthMax.target = nil, nil
	guids.target = nil
	slots[SLOT] = nil
end

--------------------------------------------------------------------------
-- What a redraw costs
--------------------------------------------------------------------------

-- Count the writes rather than trust the guards. Each of these shadows the
-- method on one region of one widget, so the metatable's own is untouched
-- and every other square in the addon still draws normally.
local writes = 0
local function countWrites(host, method)
	host[method] = function() writes = writes + 1 end
end

local w = Ability.New(_G.UIParent, nil, nil, Ability.QUIET)
Ability.Size(w, 27)
countWrites(w.icon, "SetTexture")
countWrites(w.icon, "SetDesaturated")
countWrites(w, "SetAlpha")
countWrites(w.cooldown, "SetCooldown")
countWrites(w.timer, "SetText")
countWrites(w.count, "SetText")
for index = 1, 4 do
	countWrites(w.edges[index], "SetColorTexture")
end

Ability.Draw(w, ART, "ready")
local first = writes
check(first > 0, "the first draw of a square wrote nothing")

writes = 0
for _ = 1, 50 do
	Ability.Draw(w, ART, "ready")
end
check(writes == 0,
	("redrawing an unchanged square 50 times wrote %d times"):format(writes))

-- A status change writes, and writes once rather than once per tick.
writes = 0
for _ = 1, 50 do
	Ability.Draw(w, ART, "range")
end
check(writes > 0 and writes <= 6,
	("one status change over 50 ticks wrote %d times"):format(writes))

-- The fade is the caller's half of alpha and moves without the status
-- moving, which is what the charge icon's "ready" mode does.
writes = 0
w.fade = 0
Ability.Draw(w, ART, "range")
check(writes == 1, ("a fade change wrote %d times, expected the one alpha"):format(writes))
w.fade = 1
Ability.Draw(w, ART, "range")

--------------------------------------------------------------------------
-- What a square answers to the hand
--------------------------------------------------------------------------

-- On its own widget, and that is not tidiness. Every write on `w` above is
-- shadowed by a counter that records the call and stores nothing, so
-- reading a texture or a string back off it answers whatever was there
-- before the shadow went on. These checks are readbacks, so they need a
-- square nobody has instrumented.
local feel = Ability.New(_G.UIParent, nil, "SecureActionButtonTemplate",
	Ability.QUIET)
Ability.Size(feel, 27)

-- An empty slot draws no art. The fallback question mark is still there for
-- a square whose look has no `blank`, which is every other status, so both
-- sides are driven off the same widget.
Ability.Draw(feel, nil, "empty")
check(feel.icon:GetTexture() == nil,
	"an empty slot is drawing the fallback question mark")
Ability.Draw(feel, nil, "unknown")
check(feel.icon:GetTexture() ~= nil,
	"a slot the client has not resolved is drawing nothing, so the square vanishes")

-- The swipe follows the numbers and the countdown follows the status, which
-- is what lets a global sweep the square without greying it or putting a
-- 1.4 on it.
Ability.Draw(feel, ART, "ready", _G.GetTime(), 1.5)
check(feel.cooldown.cdStart == _G.GetTime() and feel.cooldown.cdDuration == 1.5,
	"a global cooldown draws no swipe, so a press changes nothing on screen")
check((feel.timer:GetText() or "") == "",
	"a global cooldown is being counted down like a real one")
check(feel.shownLook == Ability.Look(Ability.QUIET, "ready"),
	"a swiping square changed its look, so the whole bar greys on every press")

Ability.Draw(feel, ART, "ready")
check(feel.cooldown.cdDuration == 0, "the swipe is not cleared when the cooldown ends")

-- A real cooldown still gets its number, which is the half of the split
-- that was already right and is the half a change here would break.
Ability.Draw(feel, ART, "cooldown", _G.GetTime(), 30)
check((feel.timer:GetText() or "") ~= "", "a real cooldown lost its countdown")

-- The active tint sits on top of the ladder rather than replacing a rung,
-- so it is driven against a status that is not "ready".
Ability.Draw(feel, ART, "cost", nil, nil, nil, true)
check(feel.active:IsShown(), "the stance you are standing in draws no active tint")
check(feel.active:GetBlendMode() == "ADD",
	"the active tint is not additive, so it is a muddy rectangle over the art")

-- And the edge of it, which is the half you can see across a screen. The
-- tint alone at 22% over bright art is invisible, and the case that proves
-- it is a queued Heroic Strike: armed, and the square said nothing.
check(feel.armed[1]:IsShown(), "a queued ability draws no ring, so an armed square looks idle")
check(feel.armed[1].layer == "OVERLAY",
	"the armed ring is under the art, where the art will cover it")
check(feel.shownLook == Ability.Look(Ability.QUIET, "cost"),
	"the armed ring took over the border, which the status owns")

Ability.Draw(feel, ART, "cost")
check(not feel.active:IsShown(), "the active tint is not cleared when the ability stops")
check(not feel.armed[1]:IsShown(), "the armed ring outlived the swing")

-- The equipped ring, which is a second outline inside the status border and
-- so has to be able to be on while the border says something else.
Ability.Draw(feel, ART, "range", nil, nil, nil, false, true)
check(feel.equipped[1]:IsShown(), "a worn item draws no equipped ring")
check(feel.shownLook == Ability.Look(Ability.QUIET, "range"),
	"the equipped ring took over the border, which the status owns")
check(feel.equipped[1].layer == "OVERLAY",
	"the equipped ring is under the art, where the art will cover it")
Ability.Draw(feel, ART, "range")
check(not feel.equipped[1]:IsShown(), "the equipped ring outlived the item")

-- The two the client draws by itself, which is why nothing on the tick
-- touches them and why only their existence can be checked.
check(feel.hover and feel.hover.layer == "HIGHLIGHT",
	"a square has no highlight layer, so hovering it does nothing")
check(feel.pushed ~= nil,
	"a button draws nothing on the way down, so a click has no answer")

local drawn = Ability.New(_G.UIParent, nil, nil, Ability.SHOUT)
check(drawn.pushed == nil, "a plain frame was given a pushed texture it cannot draw")

-- A running cooldown writes the timer, and only when the number it would
-- show has moved. Above ten seconds that is whole seconds, so at a tenth of
-- a second between ticks nine ticks in ten write nothing.
--
-- The first draw of the cooldown is taken outside the count, because it
-- carries the status change into it and would measure the look's six
-- writes rather than the timer's. What is measured is the steady state,
-- which is the one that runs for the length of a fight.
local base = _G.GetTime()
Ability.Draw(w, ART, "cooldown", base, 30)

writes = 0
for _ = 1, 50 do
	advance(0.1)
	Ability.Draw(w, ART, "cooldown", base, 30)
end
-- Five seconds pass, so five whole-second boundaries are crossed and the
-- string is built five times instead of fifty.
check(writes <= 6,
	("a cooldown above ten seconds wrote the timer %d times in 50 ticks"):format(writes))

-- And that none of it allocates. This is the figure that goes wrong from a
-- one line change and is invisible everywhere else.
collectgarbage()
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 50 do
	Ability.Draw(w, ART, "ready")
end
local churned = collectgarbage("count") - before
collectgarbage("restart")
collectgarbage("restart")
check(churned < 0.05,
	("redrawing an unchanged square 50 times allocated %.2f KB"):format(churned))

slots[SLOT] = nil
guids.target = nil

print(("ability %d statuses over 2 palettes, the ladder walked to every rung,"
	.. " 0 writes on 50 unchanged redraws, %.2f KB"):format(named, churned))
