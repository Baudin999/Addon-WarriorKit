-- The numbers that float off your character
--
-- ns.Ck.Stream and the part built on it. A stream is not a lane and this file
-- is where the difference is asserted rather than described: a message in a
-- column is re-aimed when the one above it goes, and a number is never re-aimed
-- at all, so its whole flight is a function of how long it has been alive.
--
-- Ten questions, and not one is answerable by reading the files.
--
-- Does a blow land on the right side. The rule is that a number is placed by
-- who it happened to and not by who caused it, so what is on the left is the
-- target's health moving and what is on the right is your own. A reader that
-- split on the source instead would look entirely correct until something
-- healed you.
--
-- The two anchors are `dealt` and `taken` and the ids were `mine` and `theirs`.
-- That rename is here rather than in a comment because it was a real inversion:
-- `mine` meant blows landing on me and sat on the right, so every name in the
-- feature said the opposite of what it did and the columns were the wrong way
-- round. Nothing but an assertion that names one column and reads the anchor
-- back can hold that still.
--
-- Do they start above the character. A number falls ninety pixels from where it
-- is born, so an anchor thirty below the middle of the screen spends the whole
-- flight below the feet. This is a default, and a default is the one thing a
-- section can assert about a placing the player owns after that.
--
-- Is a crushing blow gold. It is the one flag here that nobody can check by
-- reading: it sits two slots past the critical on a swing, it is sent for no
-- other shape of line, and the symptom of reading the wrong slot is a mob's
-- hardest hit drawn as an ordinary one.
--
-- Do the numbers go large to small and fade while they fall. Both are envelopes
-- evaluated from the fraction of the life elapsed rather than interpolated
-- between two stored ends, which is the whole reason the library is not a tween.
--
-- Does a number grow before it shrinks. This is the one the last three attempts
-- got wrong, and it is not a taste: every channel used to decay from the
-- instant of birth, which is the shape of a thing receding rather than of a
-- blow landing. A number now snaps up past its resting size inside the first
-- twentieth of a second, comes back, holds still for a beat and only then
-- falls. Three assertions, because "it grows" and "it overshoots" and "it holds
-- still" are three different ways of failing to be an impact and any one of
-- them can be lost on its own.
--
-- Does a critical start bigger and outlive a plain hit. That is one style table
-- against another and no branch on the tick, so what proves it is two numbers
-- in the air at once measured against each other.
--
-- Do they curve, and are they scattered. A number bows out of its fall at the
-- halfway point and comes back, two born in the same frame bow apart, and each
-- one is born a step above or below the row. The bow alone was not enough of
-- it: eighteen pixels of it around a sixty pixel glyph is inside the glyph, so
-- two blows a tenth of a second apart still meshed. Both are what stands
-- between a burst and one unreadable pile.
--
-- Does the same blow twice become one number. A bleed ticking four times is one
-- number carrying the total, and two different spells stay two numbers. This is
-- the behaviour a tween cannot have, because a tween owns its clock and a
-- number merged into has to keep the clock it already has.
--
-- Does the tick allocate nothing and give itself back. The addon spends most of
-- an evening with nothing in the air.
--
-- And does off mean off: the switch takes the reader off the combat log rather
-- than turning its handler into an early return.

local H = ...
local ns, fire, check = H.ns, H.fire, H.check
local logArgs, guids, CHURN = H.logArgs, H.guids, H.CHURN

local Stream = ns.Ck.Stream
local Numbers = ns.CombatTextNumbers
local Anchors = ns.CombatTextAnchors
local Blizz = ns.CombatTextBlizzard

local ME = "Player-0-00000e01"
local MOB = "Creature-0-0-0-0-9999-00000e02"

-- One line of the log, with every slot cleared first. A slot left over from the
-- line before is how a swing picks up a spell's critical flag.
local function clear(subevent, source, dest)
	for index = 1, 21 do
		logArgs[index] = nil
	end
	logArgs[1] = _G.GetTime()
	logArgs[2] = subevent
	logArgs[4] = source
	logArgs[8] = dest
end

local function swing(source, dest, amount, crit, crushing)
	clear("SWING_DAMAGE", source, dest)
	logArgs[12] = amount
	logArgs[18] = crit
	logArgs[20] = crushing
	fire("COMBAT_LOG_EVENT_UNFILTERED")
end

local function spellHit(source, dest, spellId, amount, crit)
	clear("SPELL_PERIODIC_DAMAGE", source, dest)
	logArgs[12] = spellId
	logArgs[13] = "Rend"
	logArgs[15] = amount
	logArgs[21] = crit
	fire("COMBAT_LOG_EVENT_UNFILTERED")
end

local function spellHeal(source, dest, spellId, amount)
	clear("SPELL_HEAL", source, dest)
	logArgs[12] = spellId
	logArgs[13] = "Bandage"
	logArgs[15] = amount
	fire("COMBAT_LOG_EVENT_UNFILTERED")
end

-- The newest number in the air. Push appends, so the last entry is the one the
-- line just made.
local function newest()
	return Stream.At(Stream.Count())
end

local function beat(delta, times)
	local tick = H.tick("numbers")
	for _ = 1, times or 1 do
		tick:Beat(delta)
	end
end

-- Both channels of one number, read off the frame the way the client would.
local function readAt(item)
	local _, relative, _, x, y = item.frame:GetPoint(1)
	return relative, x, y, item.frame.scale or 1, item.frame:GetAlpha()
end

-- Where a number actually is, which is not what its own anchor says.
--
-- A frame's offsets are read in its own scale, and the stream divides every one
-- of them by the envelope for exactly that reason: a number swelling from six
-- tenths of its resting size to one and a sixth writes a smaller offset on
-- every one of those frames and does not move on the screen at all. Multiplying
-- the offset back by the scale is the only way to ask whether it moved.
local function screenAt(item)
	local _, x, y, scale = readAt(item)
	return x * scale, y * scale
end

local function isGold(item)
	local r, g, b = item.frame.text:GetTextColor()
	return r > 0.9 and g > 0.7 and b < 0.4
end

local function isGreen(item)
	local r, g, b = item.frame.text:GetTextColor()
	return r < 0.5 and g > 0.7 and b < 0.6
end

guids.player = ME
fire("PLAYER_ENTERING_WORLD")
fire("GROUP_ROSTER_UPDATE")

-- Whatever the sections above left in the air, because three of them fire
-- combat log lines and this part has been reading the log since login. Clear is
-- the switch-off path as well, so this is the first thing it answers for.
Stream.Clear()
check(Stream.Count() == 0,
	("%d numbers still in the air after clearing"):format(Stream.Count()))

----------------------------------------------------------------------
-- It armed itself at login
----------------------------------------------------------------------

-- Before anything below applies a setting, because that is the whole of this
-- question. Apply subscribes to the combat log, and nothing in a real session
-- calls it until you change something: a part that only arms on a settings
-- change is a part that does nothing at all until you open the options window,
-- which is what a restart of the game showed and no assertion here caught.
-- Every other part of this addon comes up on PLAYER_LOGIN and so does this one.
swing(MOB, ME, 111)
check(Stream.Count() == 1,
	"the numbers were not reading the combat log until a setting was applied")
Stream.Clear()

ns.db.hits = true
ns.db.hitsMerge = true
Numbers.Apply()

----------------------------------------------------------------------
-- Which side, and what colour
----------------------------------------------------------------------

do
	local left, right = Anchors.Of("dealt"), Anchors.Of("taken")
	check(left ~= right, "both columns come off the same anchor")

	-- The ids and the sides in one place, because the two are what got swapped.
	-- `dealt` is the left one and it carries what you land; the shipped pair
	-- said `mine` for blows landing on you and put them on the left.
	local dealt = ns.DefaultCopy("hitsDealtPoint")
	local taken = ns.DefaultCopy("hitsTakenPoint")
	check(dealt[4] < 0 and taken[4] > 0,
		("the columns ship at %d and %d, and what you deal is the left one")
			:format(dealt[4], taken[4]))

	-- And above the character rather than below it. A number falls the whole of
	-- ns.db.hitsDrop from where it is born, so an anchor under the feet is an
	-- anchor whose whole flight is in the grass.
	check(dealt[5] > 0 and taken[5] > 0,
		("the columns ship at %d and %d off the middle, and a number falls from there")
			:format(dealt[5], taken[5]))

	swing(ME, MOB, 340)
	local anchor = select(1, readAt(newest()))
	check(anchor == left,
		"a blow you landed did not come off the left anchor")

	swing(MOB, ME, 120)
	anchor = select(1, readAt(newest()))
	check(anchor == right,
		"a blow that landed on you did not come off the right anchor")

	-- Neither end is yours, which in a raid is nearly every line the client
	-- sends and is the whole of the filter.
	local held = Stream.Count()
	swing(MOB, "Creature-0-0-0-0-9999-0000ffff", 900)
	check(Stream.Count() == held,
		"a blow between two other creatures drew a number on your screen")

	spellHeal(ME, ME, 4321, 210)
	check(isGreen(newest()), "a heal on you is not green")
	local healAnchor = select(1, readAt(newest()))
	check(healAnchor == right,
		"a heal on you did not come off the same anchor the damage you take does")

	Stream.Clear()
end

----------------------------------------------------------------------
-- A crushing blow is gold, and it is not the critical flag
----------------------------------------------------------------------

do
	-- One number per blow here, because every one of these four carries the same
	-- key but for the flag being read, and what is under test is the flag.
	ns.db.hitsMerge = false

	swing(MOB, ME, 200)
	check(not isGold(newest()), "an ordinary hit is drawn gold")

	swing(MOB, ME, 200, true)
	check(isGold(newest()), "a critical is not gold")

	-- The one nobody can read off the source: crushing is two slots past the
	-- critical and is sent on the swing alone.
	swing(MOB, ME, 200, nil, true)
	check(isGold(newest()), "a crushing blow is not gold")

	-- And the slot past it is not read as one. A glancing blow is a reduced hit
	-- and drawing it as the fight's biggest moment would be the same mistake in
	-- the other direction.
	clear("SWING_DAMAGE", MOB, ME)
	logArgs[12] = 200
	logArgs[19] = true
	fire("COMBAT_LOG_EVENT_UNFILTERED")
	check(not isGold(newest()), "a glancing blow is drawn as more than a hit")

	Stream.Clear()
	ns.db.hitsMerge = true
end

----------------------------------------------------------------------
-- A critical does not merge into the ordinary hit before it
----------------------------------------------------------------------

do
	-- Same spell, same side, one after the other. They share everything the key
	-- is made of but the flag, and the flag is in the key for this: a critical
	-- folded into the tick before it takes the gold off the one that earned it.
	spellHit(ME, MOB, 772, 100)
	spellHit(ME, MOB, 772, 900, true)
	check(Stream.Count() == 2,
		("a critical merged into the ordinary tick before it, %d in the air")
			:format(Stream.Count()))
	check(isGold(Stream.At(2)), "the critical of a pair is not gold")
	check(not isGold(Stream.At(1)), "an ordinary tick went gold beside a critical")

	-- And the ordinary tick after it still finds its own kind, which is the
	-- merge a key made of the spell alone would have refused.
	spellHit(ME, MOB, 772, 50)
	check(Stream.Count() == 2,
		("a tick that should have merged made a third number"))
	check(Stream.At(1).amount == 150,
		("the ordinary number reads %s and the two ticks were 100 and 50")
			:format(tostring(Stream.At(1).amount)))

	Stream.Clear()
end

----------------------------------------------------------------------
-- It arrives before it leaves
----------------------------------------------------------------------

do
	ns.db.hitsMerge = false
	swing(MOB, ME, 500)
	local item = Stream.At(1)
	local _, _, _, bornScale = readAt(item)
	local bornX, bornY = screenAt(item)

	-- A twentieth of a second, which is where an ordinary hit's attack peaks.
	-- The number has to be bigger than it was born, and this is the assertion
	-- three attempts at this feature failed: every channel used to decay from
	-- birth, so nothing in the air ever grew and the whole thing read as a
	-- caption drifting off rather than as a blow landing.
	beat(0.05)
	local _, _, _, peakScale = readAt(item)
	check(peakScale > bornScale,
		("a number does not grow on the way in, %.3f to %.3f"):format(bornScale, peakScale))

	-- And it went past where it is going to rest rather than easing up to it.
	-- Overshoot is what separates an impact from an appearance, and a number
	-- that merely grew into place would pass the check above.
	beat(0.05)
	local _, _, _, settleScale = readAt(item)
	check(settleScale < peakScale,
		("a number does not overshoot its rest, peak %.3f and settling %.3f")
			:format(peakScale, settleScale))

	-- Still exactly where it was born through all of that. The fall is held for
	-- the first tenth of the life, so what the eye gets is a number that snaps
	-- up, holds where it landed and only then leaves. Within a unit of its own
	-- offset, because the offset is rounded to a whole one and the scale it is
	-- read in has moved under it.
	local heldX, heldY = screenAt(item)
	check(math.abs(heldY - bornY) <= bornScale and math.abs(heldX - bornX) <= bornScale,
		("a number left before it had held still, %.1f,%.1f to %.1f,%.1f")
			:format(bornX, bornY, heldX, heldY))

	-- Past the beat it falls, it bows out of the fall, and it is smaller than it
	-- rested at. The drift and the attack are two channels multiplied and this
	-- is the drift on its own, with the attack long finished.
	beat(0.05, 2)
	local _, midX, midY, midScale, midAlpha = readAt(item)
	local _, fellY = screenAt(item)
	check(midScale < settleScale,
		("a number grew rather than shrank once it had settled, %.3f to %.3f")
			:format(settleScale, midScale))
	check(fellY < bornY,
		("a number rose rather than fell, %.1f to %.1f"):format(bornY, fellY))
	check(midAlpha <= 1, "a number is drawn more than solid")
	check(math.abs(midX) > 0,
		("a number did not bow out of its fall, it is at %d"):format(midX))

	-- Past the hold it fades, and it is still falling while it does. Both
	-- envelopes run off the same clock and neither waits for the other.
	beat(0.05, 14)
	local _, _, lateY, lateScale, lateAlpha = readAt(item)
	check(lateAlpha < 1,
		("a number is still solid at %.2f of its life"):format(lateAlpha))
	check(lateY < midY, "a number stopped falling while it faded")
	check(lateScale < midScale, "a number stopped shrinking while it faded")

	Stream.Clear()
	ns.db.hitsMerge = true
end

----------------------------------------------------------------------
-- A critical starts bigger and outlives a plain hit
----------------------------------------------------------------------

do
	ns.db.hitsMerge = false
	swing(MOB, ME, 400)
	swing(MOB, ME, 400, true)
	check(Stream.Count() == 2,
		("two blows made %d numbers"):format(Stream.Count()))

	local plain, crit = Stream.At(1), Stream.At(2)
	local _, _, _, plainScale = readAt(plain)
	local _, _, _, critScale = readAt(crit)
	check(critScale > plainScale,
		("a critical is not born bigger, %.3f against %.3f"):format(critScale, plainScale))

	-- Long enough that the ordinary hit's life has run out and the critical's
	-- has not, which is the whole of "fades a bit slower" and is one style table
	-- against another rather than a branch anywhere.
	beat(0.1, 14)
	check(plain.frame == nil or Stream.Count() == 1,
		"an ordinary hit outlived a critical thrown after it")
	check(Stream.Count() >= 1, "the critical went with the ordinary hit")

	Stream.Clear()
	ns.db.hitsMerge = true
end

----------------------------------------------------------------------
-- The same blow twice is one number
----------------------------------------------------------------------

do
	spellHit(ME, MOB, 772, 100)
	local first = newest()

	-- Long enough for the first tick's own attack to be over, so what is
	-- measured across the merge below is the merge and not the birth.
	beat(0.05, 5)
	local _, _, _, restScale = readAt(first)

	spellHit(ME, MOB, 772, 150)
	check(Stream.Count() == 1,
		("the same bleed twice made %d numbers"):format(Stream.Count()))

	-- And it swells from the size it is being drawn at rather than from the
	-- size a new number starts at. Both are one line in Stream.Bump and the
	-- wrong one is not subtle on a screen: a bleed ticking is a number that
	-- flinches down to six tenths and grows back on every tick.
	beat(0.02)
	local _, _, _, bumpedScale = readAt(first)
	check(bumpedScale > restScale,
		("a number merged into shrank first, %.3f to %.3f"):format(restScale, bumpedScale))
	check(first.amount == 250,
		("a merged number reads %s and the two ticks were 100 and 150")
			:format(tostring(first.amount)))
	check(first.frame.text:GetText() == 250 or first.frame.text:GetText() == "250",
		("a merged number draws %s"):format(tostring(first.frame.text:GetText())))

	-- The same bleed on the other side of you is a different thing happening.
	spellHit(MOB, ME, 772, 90)
	check(Stream.Count() == 2,
		"the same spell landing on you merged into the one you landed")

	-- And a different spell is a different number whichever way it went.
	spellHit(ME, MOB, 1160, 60)
	check(Stream.Count() == 3,
		("a different spell merged into another one, %d in the air")
			:format(Stream.Count()))

	-- Switched off, every tick is its own number again.
	ns.db.hitsMerge = false
	Stream.Clear()
	spellHit(ME, MOB, 772, 100)
	spellHit(ME, MOB, 772, 100)
	check(Stream.Count() == 2,
		"the same bleed twice is one number with merging switched off")

	Stream.Clear()
	ns.db.hitsMerge = true
end

----------------------------------------------------------------------
-- Two numbers in one frame do not draw on top of each other
----------------------------------------------------------------------

do
	ns.db.hitsMerge = false
	spellHit(ME, MOB, 772, 100)
	spellHit(ME, MOB, 1160, 100)

	-- Apart before either of them has moved, which is the half the bow cannot
	-- do. The bow is zero at birth and zero again at the end of the fall, and
	-- with a beat in front of it there is a tenth of a second at the start
	-- where it is zero as well: two numbers whose only difference was the bow
	-- were drawn on top of each other for the whole of the part of the flight
	-- the eye actually reads.
	local one, two = Stream.At(1), Stream.At(2)
	local _, _, oneBorn = readAt(one)
	local _, _, twoBorn = readAt(two)
	check(oneBorn ~= twoBorn,
		("two numbers born together start on the same row at %d"):format(oneBorn))

	beat(0.05, 6)
	local _, oneX, oneY = readAt(one)
	local _, twoX, twoY = readAt(two)
	check(oneX ~= twoX or oneY ~= twoY,
		("two numbers born together are drawn at the same place, %d,%d"):format(oneX, oneY))
	check(oneX * twoX <= 0,
		("two numbers born together bow the same way, %d and %d"):format(oneX, twoX))

	Stream.Clear()
	ns.db.hitsMerge = true
end

----------------------------------------------------------------------
-- The tick costs nothing and gives itself back
----------------------------------------------------------------------

do
	swing(MOB, ME, 300)
	swing(ME, MOB, 300)
	local tick = H.tick("numbers")
	local one = Stream.At(1)
	-- Off the birth frame first, so the compare below is against a position this
	-- number has already written rather than against nothing.
	tick:Beat(0.05)

	-- Beaten at no delta at all, which is the measurement worth gating. Every
	-- write here is compared against what this number last wrote, so a pass
	-- where nothing moved has to cost nothing, and a number spends its last
	-- third moving under a pixel a frame. What it would otherwise book is a
	-- relayout per number per frame for a position that did not change.
	--
	-- Not measured while they move, and 79-floating-messages.lua says why in its
	-- own words: the client stub keeps a table per anchor, so a number crossing
	-- pixels measures the harness rather than the addon. The real client
	-- allocates nothing in SetPoint.
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 200 do
		tick:Beat(0)
	end
	local churn = collectgarbage("count") - before
	collectgarbage("restart")
	check(churn < CHURN.numbers,
		("the numbers tick churns %.2f KB per 200 still beats, gate is %.2f")
			:format(churn, CHURN.numbers))

	-- And the guard is a guard rather than luck: a still pass writes no anchor
	-- at all, which the stub can answer for because it counts them.
	local held = one and one.frame:GetNumPoints() or 0
	tick:Beat(0)
	check((one and one.frame:GetNumPoints() or 0) == held,
		"a pass where nothing moved wrote an anchor anyway")

	-- Out to nothing, and the tick stops itself rather than being told.
	for _ = 1, 60 do
		tick:Beat(0.1)
	end
	check(Stream.Count() == 0,
		("%d numbers still in the air after their whole life"):format(Stream.Count()))
	check(not tick:Running(),
		"the numbers tick is still running with nothing in the air")
end

----------------------------------------------------------------------
-- The client's own numbers are put away and given back
----------------------------------------------------------------------

do
	-- What this character had before the addon touched anything. Set to
	-- something other than the default so a restore that writes a guess rather
	-- than the remembered value is visible.
	local names = {
		"floatingCombatTextCombatDamage_v2",
		"floatingCombatTextCombatLogPeriodicSpells_v2",
		"floatingCombatTextPetMeleeDamage_v2",
		"floatingCombatTextCombatHealing_v2",
	}
	ns.db.hits, ns.db.hitsQuiet = false, true
	Numbers.Apply()
	for index = 1, #names do
		_G.SetCVar(names[index], "1")
	end
	ns.dbc.hitsPrior = {}

	ns.db.hits = true
	Numbers.Apply()
	local down, all = Blizz.Quiet()
	check(down == all,
		("%d of the client's %d damage number settings are off, expected all of them")
			:format(down, all))

	-- And the master is not one of them. It carries the dodges, the combo
	-- points and the energy gains, none of which this part draws, so taking it
	-- would delete a dozen readouts to stop one duplicate.
	check(_G.GetCVar("enableFloatingCombatText") ~= "0",
		"the part took the client's whole combat text and not its damage numbers")

	ns.db.hits = false
	Numbers.Apply()
	down = Blizz.Quiet()
	check(down == 0,
		("%d of the client's damage number settings are still off after switching this part off")
			:format(down))
	for index = 1, #names do
		check(_G.GetCVar(names[index]) == "1",
			("%s came back as %s and it was 1"):format(names[index],
				tostring(_G.GetCVar(names[index]))))
	end

	-- Left alone entirely when the setting says so, which is the escape hatch
	-- for anybody who wants both.
	ns.db.hits, ns.db.hitsQuiet = true, false
	Numbers.Apply()
	down = Blizz.Quiet()
	check(down == 0,
		("the part put %d of the client's settings away with quiet switched off"):format(down))

	ns.db.hitsQuiet = true
	Numbers.Apply()
end

----------------------------------------------------------------------
-- Off means off
----------------------------------------------------------------------

do
	swing(MOB, ME, 100)
	check(Stream.Count() == 1, "the part is not drawing while it is switched on")

	ns.db.hits = false
	Numbers.Apply()
	check(Stream.Count() == 0,
		"switching the numbers off left one on the screen")

	swing(MOB, ME, 100)
	check(Stream.Count() == 0,
		"a blow drew a number with the part switched off")

	ns.db.hits = true
	Numbers.Apply()
	swing(MOB, ME, 100)
	check(Stream.Count() == 1, "the part did not come back on")
	Stream.Clear()
end

-- Put back what this section changed, so nothing below reads a client the
-- harness left half configured.
ns.db.hits, ns.db.hitsQuiet = true, true
Numbers.Apply()

print(("hits   left for what you land and right for what lands on you, white,"
	.. " green and gold; a crushing blow reads off slot 20, %d styles that snap"
	.. " up, hold and then fall, merging on, %d of the client's own %d damage"
	.. " settings put away, %d in the air")
	:format(3, select(1, Blizz.Quiet()), select(2, Blizz.Quiet()), Stream.Count()))
