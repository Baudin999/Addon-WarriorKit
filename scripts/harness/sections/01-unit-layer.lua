-- The shared unit layer
--
-- ns.Unit, on its own. Two things it promises are not visible in a screenshot
-- and are what everything above it is built on.
--
-- The first is that a colour is a reference. Every ticker in the addon guards
-- its widget writes by comparing what it is about to draw against what it drew
-- last, and for a colour that comparison is table identity, so the same state
-- has to answer the same table every time. A version of this layer that built
-- its answers would look right on screen and would write the gauge, the track,
-- the edge and the threat line five times a second forever.
--
-- The second is who a walk covers. The threat comparison asks who is closest to
-- taking a mob off you, so it has to skip you: counting the player makes every
-- mob you are holding look like it is about to be lost.

local H = ...
local guids, unitAlias, ns = H.guids, H.unitAlias, H.ns
local check = H.check

local Unit = ns.Unit
local Color, Level, Threat = Unit.Color, Unit.Level, Unit.Threat

-- A colour is the same table twice, or the guards above it are dead.
check(Color.Class("WARRIOR") == Color.Class("WARRIOR"),
	"the class colour is a fresh table on every call")
check(Color.ClassHex("WARRIOR"):match("^ff%x%x%x%x%x%x$") ~= nil,
	("the class escape is %q, expected ffRRGGBB"):format(Color.ClassHex("WARRIOR")))
check(Color.Class("NOTACLASS") == nil,
	"a class the client will not colour came back with a colour anyway")
check(Color.ClassHex(nil) == "ffffffff",
	"a nameless class did not fall back to white")

-- A green that answers two questions is the same green, which is the whole
-- reason the palette is one table and not two.
check(Color.threat.safe == Color.reaction.friendly,
	"safe and friendly are two different greens again")
check(Color.threat.off == Color.reaction.hostile,
	"off you and hostile are two different reds again")

-- The stub's mobs are reaction 2, which is hostile, and the player is a
-- warrior. Identity rather than value, for the reason above.
check(Color.Reaction("nameplate1") == Color.reaction.hostile,
	"a reaction 2 mob is not coloured hostile")
check(Color.Frame("nameplate1") == Color.frame.hostile,
	"a hostile mob is not marked as one that comes for you")
-- Whatever class this run came up as, since check.sh does two.
local playerClass = select(2, _G.UnitClass("player"))
check(Color.OfUnit("player") == Color.Class(playerClass),
	("the player's own frame is not wearing the %s colour"):format(tostring(playerClass)))
check(Color.OfUnit("nameplate1") == Color.reaction.hostile,
	"a mob with no class did not fall back to its reaction")

-- Dimming writes into one scratch table rather than allocating.
local dim = Color.Dim(Color.reaction.hostile, 0.5)
check(dim == Color.Dim(Color.reaction.friendly, 0.5),
	"dimming allocates a table instead of reusing its scratch")
check(math.abs(dim[1] - Color.reaction.friendly[1] * 0.5) < 1e-9,
	"the scratch does not carry the colour it was last handed")

-- Everything in the stub is level 62, player included, so every mob is an
-- even fight and none of them is an elite.
local tag, worth = Level.Of("nameplate1")
check(tag == "62", ("the level tag is %q, expected \"62\""):format(tag))
check(worth == Color.xp.even,
	"a mob at your own level is not on the even colour")

check(Unit.TargetToken("raid17") == "raid17target",
	("the target token is %q, expected \"raid17target\""):format(Unit.TargetToken("raid17")))

-- 4200 of 9000, floored to the integer that gets drawn rather than kept as
-- the ratio, because the integer is what the guards compare.
local health, maxHealth, percent = Unit.Health("nameplate1")
check(health == 4200 and maxHealth == 9000 and percent == 46,
	("health reads %d of %d at %d%%, expected 4200 of 9000 at 46%%")
		:format(health, maxHealth, percent))

-- Nobody but you in the group, so there is nobody to lose a mob to. A walk
-- that counted the player would answer 100 here and every bar you were
-- holding would draw as about to be lost.
check(ns.Unit.Roster.Size() < 2, "the harness starts in a group of more than one")
check(Threat.Top("nameplate1") == nil,
	"the threat walk counted the player as their own challenger")

-- The vanilla road. That client has no threat API at all and the colour
-- comes from who the mob is actually swinging at, which is the honest half
-- of the question it can answer. Called directly, because the API is
-- resolved into a local at load and cannot be taken away afterwards.
local shade, victim, mine = Threat.Swinging("nameplate1")
check(shade == Color.threat.idle and victim == nil and mine == false,
	"a mob swinging at nobody is not drawn idle")

guids["nameplate1target"] = "Player-0-00000042"
shade, victim, mine = Threat.Swinging("nameplate1")
check(shade == Color.threat.off and victim == "nameplate1target" and mine == false,
	"a mob on somebody else is not drawn as off you")

unitAlias["nameplate1target"] = { player = true }
shade, victim, mine = Threat.Swinging("nameplate1")
check(shade == Color.threat.safe and mine == true,
	"a mob swinging at you is not drawn as yours")
unitAlias["nameplate1target"] = nil
guids["nameplate1target"] = nil

----------------------------------------------------------------------
-- Contrast
--
-- The palette's one invariant, and the reason it has a shaping pass at all.
-- Every colour this addon fills a bar with is dark enough that Color.paper
-- clears TEXT_RATIO on it, and every short coloured token drawn on one of
-- those fills clears TOKEN_RATIO.
--
-- This is the check that would have caught the bug the whole thing came out
-- of. The player frame drew a white name on the warrior tan, which is
-- 2.4:1, and nothing anywhere said so. The threat amber was worse at 1.6:1.
--
-- Measured rather than compared against the shaped numbers, so it is not the
-- shaping pass marking its own work: Color.Contrast is the WCAG formula and
-- the two ratios are the thresholds, and a fill that arrived by any route,
-- including RAID_CLASS_COLORS for a class the table does not carry, has to
-- clear them the same way.
----------------------------------------------------------------------

local worstFill, worstFillAt = 99, nil
for _, fill in ipairs(Color.fills) do
	local ratio = Color.Contrast(Color.paper, fill)
	if ratio < worstFill then
		worstFill, worstFillAt = ratio, fill
	end
end
check(worstFill >= Color.TEXT_RATIO - 1e-6,
	("a fill sits at %.2f:1 under the name on it, and the floor is %.1f: %.2f %.2f %.2f")
		:format(worstFill, Color.TEXT_RATIO, worstFillAt[1], worstFillAt[2], worstFillAt[3]))

local worstToken, worstTokenAt = 99, nil
for _, token in ipairs(Color.tokens) do
	for _, fill in ipairs(Color.fills) do
		local ratio = Color.Contrast(token, fill)
		if ratio < worstToken then
			worstToken, worstTokenAt = ratio, token
		end
	end
end
check(worstToken >= Color.TOKEN_RATIO - 1e-6,
	("a token sits at %.2f:1 on the worst fill, and the floor is %.1f: %.2f %.2f %.2f")
		:format(worstToken, Color.TOKEN_RATIO, worstTokenAt[1], worstTokenAt[2],
			worstTokenAt[3]))

-- The spent end of a gauge, which is where a name spends most of a fight.
-- Color.Dim takes the fill to three tenths in sRGB, which is darker than the
-- fill in luminance by more than the ceiling's own margin, so the name only
-- gets easier to read as the mob dies. Asserted rather than reasoned about,
-- because Color.track is a tuning number somebody will raise.
for _, fill in ipairs(Color.fills) do
	local track = { fill[1] * Color.track, fill[2] * Color.track, fill[3] * Color.track }
	check(Color.Contrast(Color.paper, track) >= Color.TEXT_RATIO - 1e-6,
		("the spent end of a %.2f %.2f %.2f gauge reads at %.2f:1")
			:format(fill[1], fill[2], fill[3], Color.Contrast(Color.paper, track)))
end

-- A class the table does not carry comes in through RAID_CLASS_COLORS and
-- has to be shaped on the way, or the one class this addon has never heard
-- of is the one that draws an unreadable bar.
check(Color.class.DEATHKNIGHT == nil,
	"the palette carries a death knight, so the fallback below tests nothing")
local unknown = Color.Class("DEATHKNIGHT")
check(unknown and Color.Contrast(Color.paper, unknown) >= Color.TEXT_RATIO - 1e-6,
	("a class off the end of the palette came through at %.2f:1")
		:format(unknown and Color.Contrast(Color.paper, unknown) or 0))
-- And its tint is the client's own, unshaped, because a name in a chat line
-- is text ON the colour and wants the bright one.
check(Color.ClassHex("DEATHKNIGHT") == "ffc41e3a",
	("a death knight's chat colour came back %q, not the client's own")
		:format(Color.ClassHex("DEATHKNIGHT")))

local summary = Color.Describe()
print(("colour %s"):format(summary))
print("unit   palette shared, colours by reference, threat walk skips you, vanilla fallback")
