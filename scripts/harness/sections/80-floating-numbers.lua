-- The numbers that float off your character
--
-- ns.Ck.Stream and the part built on it. A stream is not a lane and this file
-- is where the difference is asserted rather than described: a message in a
-- column is re-aimed when the one above it goes, and a number is never re-aimed
-- at all, so its whole flight is a function of how long it has been alive.
--
-- Eight questions, and not one is answerable by reading the files.
--
-- Does a blow land on the right side. The rule is that a number is placed by
-- who it happened to and not by who caused it, so what is on the left is your
-- own health moving and what is on the right is the target's. A reader that
-- split on the source instead would put your own damage on the left and look
-- entirely correct until something hit you.
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
-- Does a critical start bigger and outlive a plain hit. That is one style table
-- against another and no branch on the tick, so what proves it is two numbers
-- in the air at once measured against each other.
--
-- Do they curve. A number bows out of its fall at the halfway point and comes
-- back, and two born in the same frame bow apart, which is the only thing
-- standing between a burst and one unreadable pile.
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
	local left, right = Anchors.Of("mine"), Anchors.Of("theirs")
	check(left ~= right, "both columns come off the same anchor")

	swing(MOB, ME, 120)
	local hit = newest()
	local anchor = select(1, readAt(hit))
	check(anchor == left,
		"a blow that landed on you did not come off the left anchor")

	swing(ME, MOB, 340)
	anchor = select(1, readAt(newest()))
	check(anchor == right,
		"a blow you landed did not come off the right anchor")

	-- Neither end is yours, which in a raid is nearly every line the client
	-- sends and is the whole of the filter.
	local held = Stream.Count()
	swing(MOB, "Creature-0-0-0-0-9999-0000ffff", 900)
	check(Stream.Count() == held,
		"a blow between two other creatures drew a number on your screen")

	spellHeal(ME, ME, 4321, 210)
	check(isGreen(newest()), "a heal on you is not green")
	local healAnchor = select(1, readAt(newest()))
	check(healAnchor == left,
		"a heal on you did not come off the same anchor your damage does")

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
-- Large to small, fading while it falls, and curving on the way
----------------------------------------------------------------------

do
	ns.db.hitsMerge = false
	swing(MOB, ME, 500)
	local item = Stream.At(1)
	local _, bornX, bornY, bornScale, bornAlpha = readAt(item)

	beat(0.05, 4)
	local _, midX, midY, midScale, midAlpha = readAt(item)

	check(midScale < bornScale,
		("a number grew rather than shrank, %.3f to %.3f"):format(bornScale, midScale))
	check(midY < bornY,
		("a number rose rather than fell, %d to %d"):format(bornY, midY))
	check(bornAlpha <= 1 and midAlpha <= 1, "a number is drawn more than solid")
	check(math.abs(midX) > math.abs(bornX),
		("a number did not bow out of its fall, %d to %d"):format(bornX, midX))

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
	spellHit(ME, MOB, 772, 150)
	check(Stream.Count() == 1,
		("the same bleed twice made %d numbers"):format(Stream.Count()))
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
	beat(0.05, 6)

	local one, two = Stream.At(1), Stream.At(2)
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

print(("hits   left for what lands on you and right for what you land, white,"
	.. " green and gold; a crushing blow reads off slot 20, %d styles, merging"
	.. " on, %d in the air"):format(3, Stream.Count()))
