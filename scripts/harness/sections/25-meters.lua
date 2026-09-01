-- The meters
--
-- Four questions, and only the first of them is about drawing.
--
-- Does the frame come up on the grid, in the size the settings ask for, and
-- does changing a setting reshape it without building a second copy of it. A
-- frame cannot be destroyed on this client, so a pane rebuilt per setting
-- change is a leak that never shows up in game and never stops growing.
--
-- Does the combat log parser read the right slot. The client hands over
-- sixteen values in a fixed order and the amount is in a different one for a
-- swing than for a spell, so the whole of that half is positional and a stub
-- that answered a named table would prove nothing about it.
--
-- Does the group filter hold. The log carries every fight in range: the other
-- party's pull, both sides of the duel by the mailbox, and every mob in the
-- pack. A pet's damage has to land on its owner and a stranger's has to land
-- nowhere, and those two are the same test from opposite ends.
--
-- And does a segment start and stop when a fight does, rather than when a
-- bleed ticks. The tail of the last pull opening a new segment would replace
-- the numbers you are still reading with two ticks of damage, which is the
-- kind of defect nobody reports because it looks like the meter resetting for
-- some reason of its own.

local H = ...
local state = H.state
local CHURN, frames, guids = H.CHURN, H.frames, H.guids
local unitClass, unitName, realPlayers = H.unitClass, H.unitName, H.realPlayers
local inCombat, advance, logArgs = H.inCombat, H.advance, H.logArgs
local talentTrees, ns, fire = H.talentTrees, H.ns, H.fire
local check = H.check
local drawn = H.carry.drawn

local meterTicker
for _, f in ipairs(frames) do
	if f.scripts.OnUpdate and f.origin:match("Meter/Window") then
		meterTicker = f
	end
end
check(meterTicker ~= nil, "the meters registered no ticker")

-- Before anything in this file has ever been in a fight. Nothing has been
-- recorded and no segment has ever opened, so the clock reads zero, and
-- dividing a total of nothing by it is a nan that reaches the pane as
-- -9223372036854775808. This is the first tick of every session and it ran
-- that way until Meter.lua stopped dividing by Meter.Elapsed directly.
check(ns.Meter.Idle(), "something was recorded before the first fight")
check(ns.Meter.Elapsed() == 0,
	("the clock reads %s before the first fight"):format(tostring(ns.Meter.Elapsed())))
check(ns.Meter.Total("dps") == 0,
	("the group total reads %s before the first fight"):format(tostring(ns.Meter.Total("dps"))))
meterTicker.scripts.OnUpdate(meterTicker, 0.25)

local frame = _G.WarriorKitMeter
check(frame ~= nil, "no meter frame came up")
local damagePane = ns.MeterWindow.Pane("damage")
local threatPane = ns.MeterWindow.Pane("threat")
check(damagePane ~= nil and threatPane ~= nil, "the meters built fewer than two panes")

----------------------------------------------------------------------
-- The shape
----------------------------------------------------------------------

check(math.abs(ns.UI.Pixel(frame) - 1) < 1e-9,
	("the meters are not on the grid: one pixel is %.4f units"):format(ns.UI.Pixel(frame)))

-- The gap between the two panes, which is the only number in the frame's
-- width that is not a setting.
local PANE_GAP = 8
check(damagePane:GetWidth() == ns.db.meterWidth,
	("a pane is %.0f px, the setting says %d"):format(damagePane:GetWidth(), ns.db.meterWidth))
check(frame:GetWidth() == ns.db.meterWidth * 2 + PANE_GAP,
	("the frame is %.0f px, two panes and a gap is %d")
		:format(frame:GetWidth(), ns.db.meterWidth * 2 + PANE_GAP))

-- A header, a hairline and one row per setting, with the gap only between
-- rows and not hanging off the bottom. A row is the icon plus a pixel above
-- and below it, which is what makes the icon rather than the text decide
-- how tall the meter is.
local HEADER, RULE, ROW, ROW_GAP = 16, 1, 29, 1
local wanted = HEADER + RULE + ns.db.meterRows * (ROW + ROW_GAP) - ROW_GAP
check(frame:GetHeight() == wanted,
	("the frame is %.0f px tall, a header and %d rows is %d")
		:format(frame:GetHeight(), ns.db.meterRows, wanted))

-- A row icon lands one stored texel on one pixel, at the two zooms that can.
--
-- This is the gate for the defect that reached the user: the icon drew 12
-- screen pixels of art out of a 54 texel source, the renderer blended the 27
-- copy with the 13.5 copy, and every icon on the meter came out soft. The
-- sizes that are exact are not a matter of taste, they are 54 and 27 and
-- nothing between, and ns.UI.IconSizes is where they come from, so this
-- moves on its own if the crop in UI/Draw.lua ever changes.
for _, zoom in ipairs({ 1, 2 }) do
	local drawn, exact = ns.MeterWindow.IconAdvice(zoom)
	check(exact, ("a row icon draws %d screen pixels at %dx, which is not a size the client stores")
		:format(drawn, zoom))
end

-- Every string on the meter is big enough to survive its own outline.
--
-- All of them are outlined and all of them have to be: the meter has no
-- background, so flat text over a pale floor is not softer, it is gone. That
-- rules out the fallback ns.UI.NumberFont takes for a number on a debuff
-- square, and leaves a hard minimum instead. The floor is read from
-- UI/Text.lua rather than written here, so one number governs both parts.
--
-- The headers were the ones this caught. The rows went to 14 off the report
-- from the client; the headers stayed at 12 and were the same defect sitting
-- one line above it, unnoticed because nobody reads a header twice.
local floor = ns.UI.OutlineFloor()
for _, entry in ipairs({
	{ "a row's number", damagePane.rows[1].value },
	{ "a row's name", damagePane.rows[1].name },
	{ "the left header", damagePane.left },
	{ "the right header", damagePane.right },
	{ "the threat header", threatPane.left },
}) do
	local _, size, flags = entry[2]:GetFont()
	flags = flags or ""
	check(size and (size >= floor or not flags:find("OUTLINE", 1, true)),
		("%s is outlined at %s pixels and the floor is %d")
			:format(entry[1], tostring(size), floor))
	-- The other half of the same rule, and the meter is where it is most
	-- visible: fourteen pixel rows of prose are what the report about fuzzy
	-- text was actually looking at.
	check(not flags:find("MONOCHROME", 1, true),
		("%s has the rasteriser turned off, which broke Arial Narrow's stems"
			.. " the last time it was tried"):format(entry[1]))
end

-- Every setting that reshapes it reuses the frames it already made.
local built = #frames
ns.db.meterRows = 4
ns.MeterWindow.Apply()
check(#frames == built, ("changing the row count built %d new frames"):format(#frames - built))
check(damagePane.visible == 4, "the pane did not take the new row count")
check(not damagePane.rows[5]:IsShown(), "a row past the setting was left on screen")
check(ns.MeterWindow.Pane("damage") == damagePane, "the pane was replaced rather than resized")

ns.db.meterThreat = false
ns.MeterWindow.Apply()
check(frame:GetWidth() == ns.db.meterWidth,
	"the frame kept the threat pane's width after the pane was turned off")
check(not threatPane:IsShown(), "the threat pane was turned off and stayed on screen")

ns.db.meterThreat = true
ns.db.meterRows = 6
ns.MeterWindow.Apply()
check(#frames == built, "turning the threat pane off and on again built new frames")

----------------------------------------------------------------------
-- The group
----------------------------------------------------------------------

local BAUDIN = "Player-0-00000001"
local SNEAKY = "Player-0-00000002"
local PET = "Pet-0-00000002"
local FROST = "Player-0-00000003"
local STRANGER = "Player-0-00000099"
local TOTEM = "Creature-0-0000-000-totem"

guids.player, unitClass.player, unitName.player = BAUDIN, "WARRIOR", "Baudin"
guids.party1, unitClass.party1, unitName.party1 = SNEAKY, "HUNTER", "Sneakyman"
guids.partypet1 = PET
guids.party2, unitClass.party2, unitName.party2 = FROST, "PRIEST", "Frostbite"
realPlayers.party1, realPlayers.party2 = true, true
fire("GROUP_ROSTER_UPDATE")

check(ns.Unit.Roster.Size() == 3,
	("the group has %d members in it, expected 3"):format(ns.Unit.Roster.Size()))
check(ns.Unit.Roster.Owner(PET) == SNEAKY, "a pet's damage does not land on its owner")
check(ns.Unit.Roster.Owner(BAUDIN) == BAUDIN, "your own damage does not land on you")
check(ns.Unit.Roster.Owner(STRANGER) == nil, "somebody else's fight is inside the group filter")
local who, class = ns.Unit.Roster.Who(SNEAKY)
check(who == "Sneakyman" and class == "HUNTER",
	("the roster has %s the %s"):format(tostring(who), tostring(class)))

----------------------------------------------------------------------
-- The log
--
-- Sixteen values in the order the client hands them over. The amount is at
-- 12 for a swing and at 15 for everything with a spell in front of it, and
-- reading the wrong one is the whole failure mode this models.
--
-- `wasted` is the slot after the amount, which is 13 on a swing and 16 on
-- everything else. The client puts three different things there and they
-- are all the same thing: overkill on a damage event, overheal on a heal.
-- One parameter rather than three, because a stub that gave each of them
-- its own argument would let a parser that reads a swing's overkill out of
-- slot 16 pass.
----------------------------------------------------------------------

local function log(subevent, source, dest, white, amount, wasted)
	for index = 1, 21 do
		logArgs[index] = nil
	end
	logArgs[1] = GetTime()
	logArgs[2] = subevent
	logArgs[4] = source
	logArgs[8] = dest
	logArgs[12] = white
	logArgs[15] = amount
	if white then
		logArgs[13] = wasted
	else
		logArgs[16] = wasted
	end
	fire("COMBAT_LOG_EVENT_UNFILTERED")
end

inCombat.player = true
fire("PLAYER_REGEN_DISABLED")
check(ns.Meter.Running(), "combat started and no segment opened")

log("SWING_DAMAGE", BAUDIN, nil, 1000)
log("SPELL_DAMAGE", SNEAKY, nil, nil, 500)
log("SPELL_DAMAGE", PET, nil, nil, 300)
log("SPELL_DAMAGE", STRANGER, nil, nil, 9999)
log("SPELL_HEAL", FROST, nil, nil, 400, 150)
advance(10)

local ranked = ns.Meter.Rank("dps")
check(#ranked == 2, ("%d rows did damage, expected 2"):format(#ranked))
check(ranked[1].guid == BAUDIN and ns.Meter.Amount(ranked[1], "dps") == 1000,
	("the top row is %s on %d"):format(tostring(ns.Unit.Roster.Who(ranked[1].guid)),
		ns.Meter.Amount(ranked[1], "dps")))
check(ranked[2].guid == SNEAKY and ns.Meter.Amount(ranked[2], "dps") == 800,
	("the hunter and their pet came to %d, expected 800")
		:format(ns.Meter.Amount(ranked[2], "dps")))
check(ns.Meter.Rate(ranked[1], "dps") == 100,
	("1000 damage over ten seconds reads as %.1f"):format(ns.Meter.Rate(ranked[1], "dps")))
check(ns.Meter.Total("dps") == 180,
	("the group total is %.1f, and 1800 over ten seconds is 180"):format(ns.Meter.Total("dps")))

local healed = ns.Meter.Rank("hps")
check(#healed == 1 and healed[1].guid == FROST, "the healer is not the only row with healing on it")
check(ns.Meter.Amount(healed[1], "hps") == 250,
	("400 healed into 150 of overheal counted as %d, expected 250")
		:format(ns.Meter.Amount(healed[1], "hps")))

----------------------------------------------------------------------
-- The ends of a fight
----------------------------------------------------------------------

inCombat.player = false
fire("PLAYER_REGEN_ENABLED")
check(not ns.Meter.Running(), "combat dropped and the segment stayed open")

local frozen = ns.Meter.Elapsed()
advance(5)
check(ns.Meter.Elapsed() == frozen,
	("the clock ran on to %ds after the fight ended at %ds"):format(ns.Meter.Elapsed(), frozen))

-- A bleed ticking on a mob that is already down. Nobody is in combat, so
-- this is not a fight and must not be treated as the start of one.
log("SPELL_PERIODIC_DAMAGE", BAUDIN, nil, nil, 77)
check(not ns.Meter.Running(), "a tick after the fight opened a new segment")
check(ns.Meter.Amount(ns.Meter.Rank("dps")[1], "dps") == 1000,
	"the tail of the last fight was written over the fight itself")

-- Somebody else's pull. They are in combat and you are not yet, which is
-- the case the whole rule exists for.
inCombat.party1 = true
log("SPELL_DAMAGE", SNEAKY, nil, nil, 250)
check(ns.Meter.Running(), "somebody else's pull did not open a segment")
local opened = ns.Meter.Rank("dps")
check(#opened == 1 and opened[1].guid == SNEAKY,
	("the new segment came up with %d rows from the old one"):format(#opened - 1))

-- A totem is not a pet and no unit token ever points at one, so the summon
-- in the log is the only place the client says whose it is.
log("SPELL_SUMMON", FROST, TOTEM)
log("SPELL_DAMAGE", TOTEM, nil, nil, 120)
local summoned = nil
for _, slot in ipairs(ns.Meter.Rank("dps")) do
	if slot.guid == FROST then
		summoned = slot
	end
end
check(summoned ~= nil and ns.Meter.Amount(summoned, "dps") == 120,
	"what a member summoned did not land on the member")

-- And one heal in this segment, so the toggle below has something to swap
-- to. Nobody has healed since the pull opened it, and a pane that is empty
-- because the fight was quiet proves nothing about the pane.
log("SPELL_HEAL", FROST, nil, nil, 600, 100)

----------------------------------------------------------------------
-- Overkill
--
-- The last hit of a fight is reported at what it swung for, not at what
-- the mob had left, and the difference is handed over beside it. Counting
-- the swing is counting health the mob did not have, and on a five second
-- pull it is most of the chart.
--
-- Three hits, because there are three ways to get this wrong: read a
-- swing's overkill out of the spell slot, read a spell's out of the swing
-- slot, or subtract the minus one the client sends on every hit that
-- killed nothing and hand back more damage than was dealt.
--
-- Small numbers on purpose. This lands in the segment the pane assertions
-- further down are drawn from, and those expect the hunter on top, so what
-- is checked here has to stay under their 250.
----------------------------------------------------------------------

log("SWING_DAMAGE", BAUDIN, nil, 5000, nil, 4900)
log("SPELL_DAMAGE", BAUDIN, nil, nil, 2000, 1900)
log("SPELL_DAMAGE", BAUDIN, nil, nil, 40, -1)

local killer = nil
for _, slot in ipairs(ns.Meter.Rank("dps")) do
	if slot.guid == BAUDIN then
		killer = slot
	end
end
check(killer ~= nil and ns.Meter.Amount(killer, "dps") == 240,
	("7,040 swung with 6,800 of it overkill counted as %s, expected 240")
		:format(killer and tostring(ns.Meter.Amount(killer, "dps")) or "no row at all"))
check(ns.Meter.Amount(ns.Meter.Rank("dps")[1], "dps") == 250,
	("the hunter is on %d and the overkill went somewhere it should not have")
		:format(ns.Meter.Amount(ns.Meter.Rank("dps")[1], "dps")))

----------------------------------------------------------------------
-- A totem that was already down when the fight started
--
-- The summon is the only place the client says whose a totem is, and it
-- happens before the pull, because that is when totems get dropped. A
-- segment opens by rebuilding the roster, so a roster rebuild that forgot
-- what it had been told by the log dropped the totem's whole fight.
----------------------------------------------------------------------

inCombat.player, inCombat.party1 = false, false
fire("PLAYER_REGEN_ENABLED")

local PRE = "Creature-0-0000-000-searing"
log("SPELL_SUMMON", FROST, PRE)
fire("GROUP_ROSTER_UPDATE") -- somebody zones in between pulls
check(ns.Unit.Roster.Owner(PRE) == FROST,
	"a roster change forgot whose totem it is")

inCombat.player = true
fire("PLAYER_REGEN_DISABLED")
log("SPELL_DAMAGE", PRE, nil, nil, 640)
local burning = ns.Meter.Rank("dps")
check(#burning == 1 and burning[1].guid == FROST
		and ns.Meter.Amount(burning[1], "dps") == 640,
	"a totem dropped before the pull did not put its damage on anyone")

-- And it stops being ours when its owner is not. The totem is still
-- burning; it is somebody else's fight now.
realPlayers.party2, guids.party2 = nil, nil
fire("GROUP_ROSTER_UPDATE")
check(ns.Unit.Roster.Owner(PRE) == nil,
	"a totem kept counting after its owner left the group")
realPlayers.party2, guids.party2 = true, FROST
fire("GROUP_ROSTER_UPDATE")

-- Put the segment the pane assertions below are drawn from back the way
-- they expect to find it: the hunter on top, the priest healing.
inCombat.player, inCombat.party1 = false, false
fire("PLAYER_REGEN_ENABLED")
inCombat.player = true
fire("PLAYER_REGEN_DISABLED")
log("SPELL_DAMAGE", SNEAKY, nil, nil, 250)
log("SPELL_SUMMON", FROST, TOTEM)
log("SPELL_DAMAGE", TOTEM, nil, nil, 120)
log("SPELL_HEAL", FROST, nil, nil, 600, 100)

----------------------------------------------------------------------
-- Spec icons
----------------------------------------------------------------------

ns.Unit.Spec.Refresh()
check(ns.Unit.Spec.Known(BAUDIN), "your own spec did not resolve out of your talent trees")

-- The icon is whichever tree the stub has the most points in, read off the stub
-- rather than written out here. A run that came up as one spec has had its
-- points moved into that spec's tree before login, so naming Arms would be
-- naming whichever run happened to be first rather than the rule being
-- asserted: the icon on the row is the winning tree's own.
do
	local winner, most = 1, -1
	for index, tree in ipairs(talentTrees.player) do
		if tree.points > most then
			winner, most = index, tree.points
		end
	end
	local icon = ns.Unit.Spec.Icon(BAUDIN, "WARRIOR")
	check(icon == talentTrees.player[winner].icon,
		("the spec icon is %q, and %d points are in %s")
			:format(icon, most, talentTrees.player[winner].name))
end

-- The other signature. One build leads with a numeric tab id and one leads
-- with the tree's name, and the addon tells them apart on the type of the
-- first value rather than on how far down the tail a nil turns up.
state.talentShape = "old"
ns.Unit.Spec.Forget()
ns.Unit.Spec.Refresh()
check(ns.Unit.Spec.Known(BAUDIN), "the older GetTalentTabInfo signature was not read")
state.talentShape = "modern"

-- Nobody has committed to anything yet, so there is no spec to draw and the
-- class icon stands in.
local spent = {}
for index, tree in ipairs(talentTrees.player) do
	spent[index] = tree.points
	tree.points = (index == 1) and 2 or 1
end
ns.Unit.Spec.Forget()
ns.Unit.Spec.Refresh()
check(not ns.Unit.Spec.Known(BAUDIN), "three points in a tree were taken for a spec")
local sheet, left = ns.Unit.Spec.Icon(BAUDIN, "WARRIOR")
check(sheet:find("CharacterCreate", 1, true) ~= nil and left == 0,
	("the fallback drew %q rather than the class sheet"):format(sheet))
for index, tree in ipairs(talentTrees.player) do
	tree.points = spent[index]
end

-- And somebody else's, which is an inspect and an answer rather than a read.
ns.Unit.Spec.Forget()
ns.Unit.Spec.Refresh()
check(ns.Unit.Spec.Request(SNEAKY), "no inspect went out for a party member in range")
check(state.inspecting == "party1",
	("the inspect went to %s"):format(tostring(state.inspecting)))
fire("INSPECT_READY", SNEAKY)
check(ns.Unit.Spec.Known(SNEAKY), "the inspect was answered and no spec came back")
local hunter = ns.Unit.Spec.Icon(SNEAKY, "HUNTER")
check(hunter:find("Marksmanship", 1, true) ~= nil,
	("the inspected spec icon is %q, and 40 points are in Marksmanship"):format(hunter))
check(state.inspecting == nil, "the inspect was never handed back")

-- An inspect the client never answers. There is no event for one, so the
-- only thing standing between a dropped request and a queue parked forever
-- is the expiry. Asked for, never answered, and then the next member has to
-- get a request of their own.
ns.Unit.Spec.Forget()
state.inspecting = nil
advance(10)
check(ns.Unit.Spec.Request(SNEAKY), "the first inspect did not go out")
check(state.inspecting == "party1", "the first inspect went to the wrong unit")
state.inspecting = nil
advance(10)
check(ns.Unit.Spec.Request(FROST), "a dropped inspect parked the queue for good")
check(state.inspecting == "party2",
	("the second inspect went to %s"):format(tostring(state.inspecting)))
fire("INSPECT_READY", FROST)
check(ns.Unit.Spec.Known(FROST), "the second inspect was answered and nothing came back")

----------------------------------------------------------------------
-- Threat
--
-- The percentage is the client's. What is asserted here is the half that is
-- not: that the rate of change is measured across a real interval and that
-- the projection off it lands where the arithmetic says.
----------------------------------------------------------------------

local threatPct = { player = 100, party1 = 50, party2 = 10 }
state.threatReader = function(source)
	local pct = threatPct[source]
	if not pct then
		return nil
	end
	return pct >= 100, 3, pct, pct, pct * 100
end

guids.target = "Creature-0-0000-000-boss"
check(ns.MeterThreat.Ready(), "the threat probe says this client has no api")
check(ns.MeterThreat.Watching(), "there is a mob targeted and nothing to measure against")

ns.MeterThreat.Update() -- plants the reference, measures nothing
local planted = ns.MeterThreat.Rank()
check(#planted == 3, ("%d members have threat on it, expected 3"):format(#planted))
check(planted[1].guid == BAUDIN and planted[1].tanking,
	"the member holding the mob is not top of the list")
check(ns.MeterThreat.Soonest() == nil,
	"a projection came out of the very first sample, which has nothing to compare against")

advance(1)
threatPct.party1 = 70
ns.MeterThreat.Update()

local soonest, when = ns.MeterThreat.Soonest()
check(soonest ~= nil and soonest.guid == SNEAKY,
	"the member climbing towards the pull was not the one picked out")
-- Twenty points in a second, four tenths of it into the average, so eight
-- points a second against the thirty that are left.
check(when and math.abs(when - 3.75) < 0.01,
	("the projection says %s seconds, the arithmetic says 3.75"):format(tostring(when)))
check(ns.MeterThreat.Tanking().guid == BAUDIN, "the wrong member is holding the mob")

-- Falling threat is not a projection. Somebody who stopped is not on their
-- way to taking anything.
advance(1)
threatPct.party1 = 40
ns.MeterThreat.Update()
advance(1)
threatPct.party1 = 20
ns.MeterThreat.Update()
check(ns.MeterThreat.Soonest() == nil, "a member whose threat is falling was projected to pull")

----------------------------------------------------------------------
-- What ends up on the rows
----------------------------------------------------------------------

threatPct.party1 = 82
ns.db.meterMode = "dps"
meterTicker.scripts.OnUpdate(meterTicker, 0.25)

check(damagePane.rows[1]:IsShown(), "the meter ticked and drew no rows")
check(damagePane.rows[1].name:GetText() == "Sneakyman",
	("the top damage row says %q"):format(tostring(damagePane.rows[1].name:GetText())))
check(threatPane.rows[1].value:GetText() == "100%",
	("the top threat row says %q"):format(tostring(threatPane.rows[1].value:GetText())))
check(damagePane.left:GetText() == "DPS", "the damage header is not labelled")

-- The bar behind the top row fills the pane and everything under it is
-- shorter, which is the whole of what a bar says.
local top = damagePane.rows[1].bar:GetWidth()
check(top == ns.db.meterWidth,
	("the top bar is %.0f px across a %d px pane"):format(top, ns.db.meterWidth))

-- And how faint it is, which is a setting rather than a constant. The row
-- guards its colour write on the player's class, so the half of this worth
-- asserting is not that the number arrives but that moving it lands on the
-- next tick: a slider whose effect waits for somebody in the group to change
-- class is a slider that does nothing.
local shipped = ns.DefaultFor("meterBarAlpha") / 100
check(math.abs(damagePane.rows[1].bar.a - shipped) < 1e-6,
	("the bars drew at %.2f alpha, the default says %.2f")
		:format(damagePane.rows[1].bar.a, shipped))
ns.db.meterBarAlpha = 60
ns.MeterWindow.Apply()
meterTicker.scripts.OnUpdate(meterTicker, 0.25)
check(math.abs(damagePane.rows[1].bar.a - 0.6) < 1e-6,
	("the opacity setting says 60 percent, the bar drew at %.2f")
		:format(damagePane.rows[1].bar.a))
ns.db.meterBarAlpha = ns.DefaultFor("meterBarAlpha")
ns.MeterWindow.Apply()
meterTicker.scripts.OnUpdate(meterTicker, 0.25)

-- The header carries two clicks. The right one is the whole of the toggle;
-- the left one opens the breakdown, and is asserted where the breakdown is.
check(damagePane.button ~= nil, "the damage header is not clickable")
damagePane.button.scripts.OnClick(damagePane.button, "RightButton")
check(ns.db.meterMode == "hps", "right clicking the header did not swap to healing")
meterTicker.scripts.OnUpdate(meterTicker, 0.25)
check(damagePane.left:GetText() == "HPS", "the pane swapped and the header did not")
check(damagePane.rows[1].name:GetText() == "Frostbite",
	("the healing pane is topped by %q"):format(tostring(damagePane.rows[1].name:GetText())))
-- And the two who did damage and no healing are off the pane rather than
-- sitting on it at zero.
check(not damagePane.rows[2]:IsShown(),
	"a member who healed nothing kept their row when the pane swapped to healing")
damagePane.button.scripts.OnClick(damagePane.button, "RightButton")

-- The left button on the same strip opens the breakdown. It is asserted
-- here rather than in the breakdown's own section because what is being
-- claimed is about the meter: that the strip carries two clicks and they do
-- not run into each other.
check(not ns.BreakdownWindow.IsShown(),
	"the breakdown window was open before anything opened it")
damagePane.button.scripts.OnClick(damagePane.button, "LeftButton")
check(ns.BreakdownWindow.IsShown(),
	"a left click on the meter header did not open the breakdown")
check(ns.db.meterMode == "dps", "opening the breakdown also swapped the meter")
damagePane.button.scripts.OnClick(damagePane.button, "LeftButton")
check(not ns.BreakdownWindow.IsShown(),
	"a second left click on the meter header did not close the breakdown")

-- The projection reaching the header, name and all. Soonest is asserted on
-- its own above; this is the other half, that what it works out gets drawn.
advance(1)
threatPct.party1 = 90
ns.MeterThreat.Update()
meterTicker.scripts.OnUpdate(meterTicker, 0.25)
check(threatPane.right:GetText():find("Sneakyman", 1, true) ~= nil,
	("the header does not name the member converging on you: %q")
		:format(tostring(threatPane.right:GetText())))

-- And back to quiet, which is the state the two exits below are about.
advance(1)
threatPct.party1 = 30
ns.MeterThreat.Update()

-- Losing the mob and getting it back. Both of the header's early exits leave
-- by a different door from the one that draws a projection, so both have to
-- forget what they last showed on the way out. While they did not, a target
-- that came back to the same quiet state found the projection guard already
-- satisfied and the header went on reading "no target" over a full list of
-- rows underneath it.
meterTicker.scripts.OnUpdate(meterTicker, 0.25)
check(threatPane.right:GetText() == "held",
	("the threat header says %q with the mob held and nobody climbing")
		:format(tostring(threatPane.right:GetText())))

guids.target = nil
meterTicker.scripts.OnUpdate(meterTicker, 0.25)
check(threatPane.right:GetText() == "no target",
	("the target went away and the header says %q")
		:format(tostring(threatPane.right:GetText())))

guids.target = "Creature-0-0000-000-boss"
meterTicker.scripts.OnUpdate(meterTicker, 0.25)
check(threatPane.right:GetText() ~= "no target",
	"the target came back and the header was still reading no target")

----------------------------------------------------------------------
-- Allocation
----------------------------------------------------------------------

-- The clock moves inside the loop, which is the difference between this and
-- the two churn gates above. A meter with the fight frozen allocates
-- literally nothing, because every write in the file is guarded on a number
-- and none of the numbers moved; measuring that would be measuring the
-- guards and calling it the steady state. A fight is seconds ticking over
-- and a DPS figure falling between them, so that is what is measured.
local function meterChurn(n)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, n do
		advance(0.05)
		meterTicker.scripts.OnUpdate(meterTicker, 0.05)
	end
	local after = collectgarbage("count")
	collectgarbage("restart")
	return (after - before) / (n / 50)
end

meterChurn(200)
local meterKb = meterChurn(200)
check(meterKb <= CHURN.meter,
	("the meters allocate %.2f KB per 50 ticks, the gate is %.2f"):format(meterKb, CHURN.meter))

print(("meters %d rows, %.0f x %.0f px, %d damage and %d threat, %.2f KB per 50 ticks, gate is %.2f")
	:format(ns.db.meterRows, frame:GetWidth(), frame:GetHeight(),
		#ns.Meter.Rank("dps"), #ns.MeterThreat.Rank(), meterKb, CHURN.meter))

----------------------------------------------------------------------
-- Put the client back the way the sections after this one expect it.
----------------------------------------------------------------------

state.threatReader = nil
guids.player, guids.party1, guids.partypet1, guids.party2, guids.target = nil, nil, nil, nil, nil
unitClass.player, unitClass.party1, unitClass.party2 = nil, nil, nil
unitName.player, unitName.party1, unitName.party2 = nil, nil, nil
realPlayers.party1, realPlayers.party2 = nil, nil
inCombat.player, inCombat.party1 = nil, nil
fire("GROUP_ROSTER_UPDATE")
