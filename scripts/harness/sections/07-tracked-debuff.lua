-- A tracked debuff lights its square up
--
-- Everything above measures where the squares sit. Nothing measured whether
-- one ever comes on, and that is the half that shipped broken.
--
-- The row matches auras by name, and the name a proc's aura carries is not the
-- name of the talent that grants it. The picker offered 12162, the Deep Wounds
-- talent, which resolves to "Deep Wounds" and is a hidden passive no mob ever
-- carries. What lands is 12721, and the client calls it "Deep Wound". One
-- letter, no error anywhere, and a square that stayed dark through every fight.
--
-- So: put the bleed on the mob and assert the slot comes on, goes desaturated
-- for somebody else's bleed and goes out when it falls off. Track the talent
-- and the first of those goes red, which is the whole point of this block.

local H = ...
local debuffs, ns, check = H.debuffs, H.ns, H.check
local CheckPacked, widget = H.carry.CheckPacked, H.carry.widget

-- The shortlist offers the aura, never the spell that applies it. This is
-- the assertion that fails the moment 12162 goes back in SUGGESTED.
for _, spellID in ipairs(ns.EnemyBars.Suggestions()) do
	check(spellID ~= 12162,
		"the picker offers 12162, the Deep Wounds talent, which lands on nobody")
end

-- Off the list first. The bleed ships on the bar, and the question this asks
-- is what happens when somebody types the talent id at a list that does not
-- already carry it, which is what a player who dropped it and went looking on
-- Wowhead does.
check((ns.EnemyBars.RemoveSpell(12721)), "Deep Wound would not come off the shipped list")

-- Typing the talent's id gets you the bleed, because Wowhead's search for
-- deep wounds finds the talent first and the panel takes a bare number.
local ok, named = ns.EnemyBars.AddSpell(12162)
check(ok, "the Deep Wounds talent id would not go on the list at all")
check(named == "Deep Wound",
	("adding 12162 put %q on the bar, expected Deep Wound"):format(tostring(named)))
check(ns.EnemyBars.Slot(12162) == nil, "the dead talent id went on the list as itself")
local slot = ns.EnemyBars.Slot(12721)
check(slot ~= nil, "Deep Wound is on the bar and has no slot")
-- Falls back to whatever slot the talent id took, so a run with 12162 put
-- back reaches the assertions below instead of dying on a nil index. Those
-- are the ones that name the symptom a player sees: the square is there,
-- the mob is bleeding, and it never comes on.
slot = slot or ns.EnemyBars.Slot(12162) or 1

local function Square()
	return ns.EnemyBars.WidgetFor("nameplate1").icons[slot]
end

debuffs.nameplate1 = {
	{ name = "Deep Wound", count = 3, expires = _G.GetTime() + 9,
	  duration = 12, source = "player" },
}
ns.EnemyBars.Update()
check(Square().shownState == "mine",
	("the mob is bleeding from Deep Wound and slot %d reads %q, expected mine")
		:format(slot, tostring(Square().shownState)))
-- The number and the unit it is in, which is one reading and not two. Nine
-- seconds is read in seconds; a half hour buff on the same square reads 28 and
-- " m", which is what stopped four digits landing on a sixteen pixel icon.
--
-- Written out with the space the client puts there, because the row above ours
-- on the screen is the client's own and it says "56 s".
check(Square().shownLeft == 9 and Square().shownUnit == " s",
	("the square says %s%s, the aura has 9 seconds")
		:format(tostring(Square().shownLeft), tostring(Square().shownUnit)))
check(Square().timer.text == "9 s",
	("the square drew %q over the art, expected \"9 s\""):format(tostring(Square().timer.text)))

-- And the colour, which is the client's rule rather than ours: counted in
-- seconds it is white, counted in minutes it is gold. Two rows of auras that
-- disagree about what a colour means are two rows you have to read separately.
local Color = ns.Unit.Color
local function tintOf(square)
	local r, g, b = square.timer:GetTextColor()
	return { r, g, b }
end
local function same(a, b)
	return math.abs(a[1] - b[1]) < 1e-9 and math.abs(a[2] - b[2]) < 1e-9
		and math.abs(a[3] - b[3]) < 1e-9
end
check(same(tintOf(Square()), Color.text.name),
	("nine seconds is drawn %.2f %.2f %.2f and the client draws a countdown in"
		.. " paper white"):format(unpack(tintOf(Square()))))

debuffs.nameplate1[1].expires = _G.GetTime() + 9 * 60
ns.EnemyBars.Update()
check(Square().shownUnit == " m" and Square().timer.text == "9 m",
	("nine minutes left and the square says %q"):format(tostring(Square().timer.text)))
check(same(tintOf(Square()), Color.text.duration),
	("nine minutes is drawn %.2f %.2f %.2f and the client draws a duration in"
		.. " gold"):format(unpack(tintOf(Square()))))
debuffs.nameplate1[1].expires = _G.GetTime() + 9
ns.EnemyBars.Update()

-- The sweep, which is the other half of the timer and the half you read from
-- across the screen. The client is handed the application time and the length,
-- reversed, so the square fills as the bleed runs out rather than emptying the
-- way a cooldown does.
local swipe = Square().swipe
check(swipe.cdDuration == 12 and math.abs(swipe.cdStart - (_G.GetTime() - 3)) < 1e-6,
	("the square's sweep runs %s from %s, expected 12 from three seconds ago")
		:format(tostring(swipe.cdDuration), tostring(swipe.cdStart)))
check(swipe.cdReverse == true, "the sweep empties the square as the bleed runs out")
check(Square().shownCount == 3,
	("the square says a stack of %s, the aura has 3"):format(tostring(Square().shownCount)))

-- Another warrior's bleed is dimmed rather than dropped, which is how you
-- see that the mob has it and that refreshing it is not your call.
debuffs.nameplate1[1].source = "party1"
ns.EnemyBars.Update()
check(Square().shownState == "theirs",
	("somebody else's Deep Wound reads %q, expected theirs"):format(tostring(Square().shownState)))

debuffs.nameplate1 = nil
ns.EnemyBars.Update()
check(Square().shownState == "none",
	("the bleed fell off and the square reads %q, expected none"):format(tostring(Square().shownState)))
check(Square().shownLeft == 0 and Square().shownCount == 0,
	"the square kept the timer and the stack after the bleed fell off")
check(Square().swipe.cdDuration == 0,
	"the square kept its sweep after the bleed fell off")

-- The saved list is what outlives the fix. Defaults are read once on a
-- fresh account, so anyone who picked Deep Wounds before it still carries
-- 12162 and would keep carrying it forever. Login repairs the list itself.
local saved = ns.EnemyBars.Spells()
local before = #saved
saved[#saved + 1] = 12162
ns.EnemyBars.Repair()
ns.EnemyBars.Retrack()
check(#saved == before,
	("repairing a list that already tracked the bleed left %d entries, expected %d")
		:format(#saved, before))
check(ns.EnemyBars.Slot(12162) == nil, "the repair left the dead talent id on the list")

check((ns.EnemyBars.RemoveSpell(12721)), "Deep Wound would not come off the list")
saved[#saved + 1] = 12162
ns.EnemyBars.Repair()
ns.EnemyBars.Retrack()
check(ns.EnemyBars.Slot(12162) == nil, "the repair left the dead talent id on the list")
check(ns.EnemyBars.Slot(12721) ~= nil, "the repair dropped the bleed instead of renaming it")

-- Back to the shipped list, because the churn figure below is quoted against it.
ns.db.barsIconSize = ns.DefaultFor("barsIconSize")
ns.EnemyBars.ResetSpells()
check(#ns.EnemyBars.Spells() == 5, "the reset did not put the five back")
CheckPacked("after the debuff scan")
widget = ns.EnemyBars.WidgetFor("nameplate1")

-- Left for the sections below.
H.carry.widget = widget
