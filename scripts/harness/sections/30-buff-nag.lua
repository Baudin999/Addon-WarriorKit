-- The buff nag
--
-- Two halves that take turns, and the assertions are mostly about the turns
-- rather than about the drawing. A missing sharpening stone must be noticed out
-- of combat and must go quiet the moment a fight starts, because you cannot
-- apply one mid pull. Blood Fury must be silent out of combat and loud in it,
-- because pressing it is only worth saying while you are swinging.
--
-- The one assertion here that is about a client API rather than about the
-- feature is the off hand. GetWeaponEnchantInfo answers six values on the
-- oldest shape and eight once the enchant's own id went in after the charges,
-- and on the eight value shape the main hand's enchant id sits exactly where
-- the six value shape puts "the off hand has an enchant". It is a number, and a
-- number is truthy. A parser that guessed the stride would report an enchanted
-- off hand forever, silently, on whichever of the two clients answers the shape
-- it did not guess. So the stub is driven in both shapes and the off hand is
-- read in both.
--
-- The shield is the other half of that: a shield takes no stone and a tank
-- holding one must never be nagged about it. That is the client's own
-- OffhandHasWeapon and not a reading of the slot, and the slot is filled with a
-- shield here to prove the difference.

local H = ...
local state = H.state
local WARRIOR, CHURN, frames = H.WARRIOR, H.CHURN, H.frames
local own, inCombat, advance = H.own, H.inCombat, H.advance
local swing, ns, fire = H.swing, H.ns, H.fire
local check = H.check

local Upkeep, Racials, Nag = ns.Upkeep, ns.Racials, ns.BuffNag

local ticker
for _, f in ipairs(frames) do
	if f.scripts.OnUpdate and f.origin:match("Buffs/Nag") then
		ticker = f
	end
end
check(ticker ~= nil, "the buff nag registered no ticker")

local function tick()
	ticker.scripts.OnUpdate(ticker, 0.2)
end

local function says(word)
	return Nag.Caption():find(word, 1, true) ~= nil
end

-- What a tick costs, measured twice: once with an entry switched off in the
-- missing-buff half, and once in the racial half with the clock moving,
-- which is the row's only moving state. Defined up here because both halves
-- use it.
local function churnBuffs(n)
	collectgarbage("collect")
	collectgarbage("stop")
	local start = collectgarbage("count")
	for _ = 1, n do
		advance(0.1)
		ticker.scripts.OnUpdate(ticker, 0.2)
	end
	local after = collectgarbage("count")
	collectgarbage("restart")
	return after - start
end

-- What a square says to the mouse.
--
-- Read off ns.UI.Tooltip rather than recorded through a stubbed GameTooltip,
-- which is what this did while the nag wrote its three lines into Blizzard's
-- parchment. The addon has its own tooltip now and the square opens that
-- one, so the readback is the real thing the player sees: the lines that
-- were actually laid out, and the frame it was actually anchored to. A stub
-- that went on recording GameTooltip calls would pass on a nag square that
-- had stopped saying anything at all.
local function hover(slot)
	local square = Nag.Icon(slot)
	local enter = square:GetScript("OnEnter")
	check(enter and square:GetScript("OnLeave"),
		"a nag square has no hover scripts, so it can never say what it means")
	ns.UI.Tooltip.Close()
	if enter then
		enter(square)
	end
	if not ns.UI.Tooltip.IsShown() then
		return "", nil
	end
	local parts = {}
	for index = 1, ns.UI.Tooltip.Lines() do
		local left, right = ns.UI.Tooltip.Text(index)
		parts[#parts + 1] = tostring(left or "")
		if right then
			parts[#parts + 1] = tostring(right)
		end
	end
	return table.concat(parts, "\n"), ns.UI.Tooltip.Owner()
end

----------------------------------------------------------------------
-- Which shape this client answers in
----------------------------------------------------------------------

own.wide = false
check(Upkeep.EnchantShape() == 3, "six returns did not read as a stride of three")
own.wide = true
check(Upkeep.EnchantShape() == 4, "eight returns did not read as a stride of four")

----------------------------------------------------------------------
-- The main hand
----------------------------------------------------------------------

ns.db.locked = true
own.race, own.raceName = "Orc", "Orc"
swing.mainhand = _G.WarriorKitItemLink("Arcanite Reaper")
swing.offhand, swing.off = nil, nil
own.main, own.mainLeft, own.off, own.offLeft = false, 0, false, 0
fire("PLAYER_EQUIPMENT_CHANGED")
tick()

check(Nag.Mode() == "upkeep", "a bare weapon out of combat drew nothing")
check(says("bare weapon"), "a bare main hand was not nagged about")

own.main, own.mainLeft = true, 1500 * 1000
tick()
check(not says("bare weapon"), "a sharpened weapon was nagged about anyway")
check(math.floor(Upkeep.Left(ns.Gear.MAINHAND)) == 1500,
	"the main hand's remaining time did not come back in seconds")

----------------------------------------------------------------------
-- The off hand, a shield, and the stride
----------------------------------------------------------------------

swing.offhand = _G.WarriorKitItemLink("Aegis")
swing.off = nil -- OffhandHasWeapon is false for a shield, which is the rule
fire("PLAYER_EQUIPMENT_CHANGED")
tick()
check(not says("bare off hand"), "a shield was nagged about")

-- A real weapon in that hand with nothing on it, read on the eight value
-- shape, where a guessed stride of three would find the main hand's enchant
-- id sitting in the off hand's "has an enchant" slot and say it was fine.
swing.off = 1.8
fire("PLAYER_EQUIPMENT_CHANGED")
tick()
check(says("bare off hand"),
	"a bare off hand was not nagged about, which is the stride read wrongly")

own.off, own.offLeft = true, 900 * 1000
tick()
check(not says("bare off hand"), "a sharpened off hand was nagged about anyway")

-- And again on the six value shape, so neither branch of the decode is only
-- ever run one way round.
own.wide = false
own.off = false
tick()
check(says("bare off hand"), "the six value shape lost the off hand")
own.wide = true
own.off = true
tick()

----------------------------------------------------------------------
-- Switching one entry off
--
-- The request this section exists for: a character with no sharpening stones
-- does not need to be told about the main hand every time it leaves combat.
--
-- Driven with both hands bare, because the failure worth catching is not
-- that the switch works, it is that it works on one entry. A filter written
-- against the wrong index, or a row that hides the square without taking the
-- entry off the list, silences the neighbour too and looks fine in a
-- screenshot of a character who is only missing one thing.
----------------------------------------------------------------------

swing.offhand = _G.WarriorKitItemLink("Thrash Blade")
swing.off = 1.8
own.main, own.mainLeft = false, 0
own.off, own.offLeft = false, 0
fire("PLAYER_EQUIPMENT_CHANGED")
tick()
check(says("bare weapon") and says("bare off hand"),
	"both hands are bare and the row does not say so: " .. Nag.Caption())

local watched = Upkeep.Count()
Upkeep.SetWatched("mainhand", false)
Nag.Apply()
tick()
check(not says("bare weapon"), "switching the main hand off left it on the row")
check(says("bare off hand"), "switching the main hand off took the off hand with it")
check(Upkeep.Count() == watched - 1,
	("%d entries are watched with one switched off, and %d were before")
		:format(Upkeep.Count(), watched))

-- Off the list the tick walks, not drawn at nothing and not checked and
-- thrown away. This is the assertion that makes "off" mean off: a square at
-- alpha zero would pass every check above it and still cost four calls a
-- tick and a square of screen nobody can use.
local walked = false
for index = 1, Upkeep.Count() do
	if Upkeep.Entry(index).key == "mainhand" then
		walked = true
	end
end
check(not walked,
	"a switched off entry is still on the list the tick walks, so it is being"
		.. " asked about and the answer thrown away")

-- Not counted anywhere either, and said out loud. A status line reporting
-- squares you cannot see has moved the nag rather than turned it off.
local counted = 0
for index = 1, Upkeep.Count() do
	if Upkeep.Missing(index) then
		counted = counted + 1
	end
end
check(Nag.Shown() == counted,
	("%d squares are drawn and %d entries are missing"):format(Nag.Shown(), counted))
check(Upkeep.Describe():find(("%d tracked, %d missing")
	:format(Upkeep.Count(), counted), 1, true) ~= nil,
	"the status line counts entries the row does not: " .. Upkeep.Describe())
check(Upkeep.Describe():find("bare weapon switched off", 1, true) ~= nil,
	"nothing anywhere says what was switched off: " .. Upkeep.Describe())
check(Nag.Describe():find("bare weapon switched off", 1, true) ~= nil,
	"/wk status does not carry it: " .. Nag.Describe())

-- And it costs nothing. The gate is the same figure the racial half is held
-- to, because a filter that rebuilt the watched list once a tick would be
-- the obvious way to write this and would show up here rather than in a
-- stutter somebody reports six weeks later.
churnBuffs(50)
local silentChurn = churnBuffs(50)
check(silentChurn <= CHURN.buffs,
	("the row allocated %.2f KB over 50 ticks with an entry switched off, gate is %.2f")
		:format(silentChurn, CHURN.buffs))

----------------------------------------------------------------------
-- Where the switch lives
--
-- This character's saved variables and not the account's, which is the whole
-- argument for the setting: a bank alt that will never own a sharpening
-- stone and a raiding main that always does want opposite answers, and one
-- account-wide key would give them the same one.
----------------------------------------------------------------------

check(ns.dbc.buffWatch ~= nil, "the switch list is not in the character table")
check(ns.db.buffWatch == nil, "the switch list is in the account table")
check(ns.dbc == _G.WarriorKitCharDB,
	"the table the switch lands in is not the one the TOC saves per character")
check(_G.WarriorKitCharDB.buffWatch.mainhand == false,
	"switching an entry off never reached the saved variables")

-- The round trip. What the client writes at logout is that table and what it
-- hands back at login is the same table with Core's defaults backfilled into
-- whatever is absent, so a reload is modelled by handing the list back as a
-- fresh copy of what was saved. Anything cached outside the saved table
-- fails here.
local reloaded = {}
for key, value in pairs(_G.WarriorKitCharDB.buffWatch) do
	reloaded[key] = value
end
ns.dbc.buffWatch = reloaded
Upkeep.Rebuild()
Nag.Apply()
tick()
check(not Upkeep.Watched("mainhand"),
	"the switch did not survive the round trip through saved variables")
check(not says("bare weapon"),
	"a reload put the entry that was switched off back on the row")

----------------------------------------------------------------------
-- What a square says to the mouse
--
-- The caption is two words and the tooltip is where the rest goes: what the
-- square is about, and the name of the switch that silences it, so somebody
-- tired of one square can turn it off from the square.
----------------------------------------------------------------------

local hoverText, hoverOwner = hover(1)
check(hoverOwner == Nag.Icon(1), "the tooltip is not anchored to the square you hovered")
check(hoverText:find("bare off hand", 1, true) ~= nil,
	"the tooltip does not name the square it is on: " .. hoverText)
check(hoverText:find("shield", 1, true) ~= nil,
	"the tooltip does not carry what the caption could not: " .. hoverText)
check(hoverText:find("/wk buffs offhand off", 1, true) ~= nil,
	"the tooltip does not name the switch that silences the square: " .. hoverText)

-- The client's own words above them, which is what used to be missing and is
-- the whole difference between this box and every other one in the addon.
--
-- A bare hand has no aura to point a scanner at, and it does have a weapon, so
-- the square reads with the worn slot the way the buff row's enchant square
-- does. What the game says about the sword takes the head, exactly where an
-- action square's spell name goes, and the two lines this file wrote stay under
-- it. The check above ran before this one on purpose: unseeded, the client
-- answers nothing and the caption's phrase stands, which is what the older
-- client and an empty slot both get.
H.tooltips.inventory[H.tooltipKey("player", ns.Gear.OFFHAND)] = {
	{ "Thrash Blade" },
	{ "One-Hand", "Sword" },
}
hoverText = hover(1)
check(hoverText:find("Thrash Blade", 1, true) ~= nil,
	"a square about a bare weapon never asks the client about that weapon: " .. hoverText)
check(hoverText:find("Sword", 1, true) ~= nil,
	"the client's lines came back with only the first of them: " .. hoverText)
check(hoverText:find("shield", 1, true) ~= nil,
	"the client's words pushed out what this file had to say: " .. hoverText)
check(hoverText:find("/wk buffs offhand off", 1, true) ~= nil,
	"the client's words pushed out the switch: " .. hoverText)
H.tooltips.inventory[H.tooltipKey("player", ns.Gear.OFFHAND)] = nil

local leave = Nag.Icon(1):GetScript("OnLeave")
if leave then
	leave(Nag.Icon(1))
end
check(owned == nil, "the tooltip stays up after the cursor has left the square")

-- Mouse only while the row is locked and drawn. A hidden square that still
-- took the mouse would be an invisible trap over the middle of the screen,
-- and a square that took it while the row was unlocked would eat the drag
-- that moves the row.
check(Nag.Icon(1).mouse == true, "a drawn square does not take the mouse, so it never hovers")
check(Nag.Icon(Upkeep.Ceiling()).mouse == false,
	"a hidden square takes the mouse, which is an invisible trap over the world")
ns.db.locked = false
Nag.Lock()
tick()
check(Nag.Mode() == "preview", "unlocking did not put the row into preview")
check(Nag.Icon(1).mouse == false,
	"a square eats the mouse while the row is unlocked, so the row cannot be dragged")
ns.db.locked = true
Nag.Lock()
tick()

-- Back on, so nothing below this inherits a silenced main hand.
Upkeep.SetWatched("mainhand", true)
Nag.Apply()
tick()
check(says("bare weapon"), "switching the entry back on did not put it back")
check(_G.WarriorKitCharDB.buffWatch.mainhand == nil,
	"switching an entry back on left a key behind in the saved variables")
check(select(1, Upkeep.Silent()) == 0,
	"the status line still reports something switched off")

own.main, own.mainLeft = true, 1500 * 1000
swing.off, swing.offhand = nil, nil
own.off, own.offLeft = true, 900 * 1000
fire("PLAYER_EQUIPMENT_CHANGED")
tick()

----------------------------------------------------------------------
-- Battle Shout, which is the one entry gated on class
----------------------------------------------------------------------

own.auras[1] = { name = "Battle Shout", expires = _G.GetTime() + 120 }
fire("UNIT_AURA", "player")
tick()
check(not says("battle shout"), "Battle Shout was nagged about while it was up")

own.auras[1] = nil
fire("UNIT_AURA", "player")
tick()
if WARRIOR then
	check(says("battle shout"), "Battle Shout falling off said nothing")
else
	check(not says("battle shout"),
		"a hunter was told to keep Battle Shout up")
end

----------------------------------------------------------------------
-- Food, which is not
----------------------------------------------------------------------

check(says("food"), "an unfed character was not nagged about food")
own.auras[1] = { name = "Well Fed", expires = _G.GetTime() + 900 }
fire("UNIT_AURA", "player")
tick()
check(not says("food"), "Well Fed did not count as food")
own.auras[1] = nil
fire("UNIT_AURA", "player")

----------------------------------------------------------------------
-- Which racial you own
----------------------------------------------------------------------

check(Racials.Name() == "Blood Fury", "an orc did not get Blood Fury")
check(Racials.Spell() == 20572, "Blood Fury is not 20572")
check(Racials.Worth(), "Blood Fury is not worth nagging about")

own.race, own.raceName = "Troll", "Troll"
check(Racials.Name() == "Berserking", "a troll did not get Berserking")
check(Racials.Spell() == 26297, "Berserking is not 26297")
check(Racials.Worth(), "Berserking is not worth nagging about")

own.race, own.raceName = "Dwarf", "Dwarf"
check(Racials.Name() == "Stoneform", "a dwarf did not get Stoneform")
check(not Racials.Worth(),
	"Stoneform is nagged about, and a defensive spent on a bleed is not a rotation")

-- A race with nothing listed answers nothing rather than answering the last
-- race's spell, which is what a cache keyed on nothing would have done.
own.race, own.raceName = "Goblin", "Goblin"
check(Racials.Spell() == nil, "a race with no racial listed kept the last one")

own.race, own.raceName = "Orc", "Orc"

----------------------------------------------------------------------
-- The racial half, in a fight
----------------------------------------------------------------------

inCombat.player = true
tick()
check(Nag.Mode() == "racial", "Blood Fury off cooldown in a fight drew nothing")
check(Nag.Shown() == 1, "the racial half drew more than one square")
check(Nag.Caption() == "press Blood Fury",
	"the caption read " .. Nag.Caption())
check(not says("bare weapon"),
	"a missing stone shouted in combat, where you cannot do anything about it")

-- The racial square's own tooltip. It says which racial, how long it has
-- been sitting there, and how to switch the half off. The elapsed figure is
-- this row's own record: a spell that is ready reports a duration of zero
-- and no end time, so nothing in the client can answer it.
advance(12)
local racialText = hover(1)
check(racialText:find("Blood Fury", 1, true) ~= nil,
	"the racial tooltip does not name the racial: " .. racialText)
check(racialText:find("Instant", 1, true) == nil,
	"a client with no setter for a spell id answered one anyway: " .. racialText)

-- And with the id asked about, which is the shape a racial and an added flask
-- both have and the shape there is no aura index for. The head is the client's
-- description of the spell, the same as an action square's, and the elapsed
-- figure and the switch are still underneath.
H.tooltips.spell[20572] = {
	{ "Blood Fury" },
	{ "Instant", "cast" },
	{ "Increases attack power. Lasts 15 sec." },
}
racialText = hover(1)
check(racialText:find("Increases attack power", 1, true) ~= nil,
	"the racial square never asks the client what the racial does: " .. racialText)
check(racialText:find("12 seconds", 1, true) ~= nil,
	"the racial tooltip does not say how long it has been ready: " .. racialText)
check(racialText:find("/wk buffs racial off", 1, true) ~= nil,
	"the racial tooltip does not name the switch: " .. racialText)
H.tooltips.spell[20572] = nil

-- Pressed. The cooldown is the only thing that says so and it is what takes
-- the square off the screen.
own.cooldowns[20572] = { _G.GetTime(), 120 }
tick()
check(Nag.Mode() == "quiet", "pressing Blood Fury left the square on screen")
check(Nag.Shown() == 0, "a spent racial still drew a square")

-- A global sweep is not the ability's own cooldown. Reading it as one would
-- blink the square out for a second and a half after every other press.
own.cooldowns[20572] = { _G.GetTime(), 1.5 }
tick()
check(Nag.Mode() == "racial", "a global cooldown counted as the racial being spent")
own.cooldowns[20572] = nil

-- Turned off, the racial half goes quiet and the missing stone stays quiet
-- too, because combat is combat.
ns.db.buffRacial = false
tick()
check(Nag.Mode() == "quiet", "the racial setting did nothing")
ns.db.buffRacial = true
tick()

----------------------------------------------------------------------
-- The pulse
----------------------------------------------------------------------

local before = Nag.Icon(1).shownAlpha
advance(0.8) -- half a cycle
tick()
check(Nag.Icon(1).shownAlpha ~= before, "the racial square did not pulse")
check(Nag.Icon(1).shownAlpha >= 0.3 and Nag.Icon(1).shownAlpha <= 1,
	"the pulse left the square at " .. tostring(Nag.Icon(1).shownAlpha))

ns.db.buffPulse = false
tick()
check(Nag.Icon(1).shownAlpha == 1, "pulse off did not leave the square at full alpha")
ns.db.buffPulse = true

----------------------------------------------------------------------
-- What a tick costs
--
-- Measured in the racial half with the clock moving, which is the row's only
-- moving state. Standing still it writes nothing at all, and a gate on that
-- figure would be a gate on the guards rather than on the tick.
----------------------------------------------------------------------

churnBuffs(50)
local churned = churnBuffs(50)
check(churned <= CHURN.buffs,
	("the buff row allocated %.2f KB over 50 ticks, and the gate is %.2f")
		:format(churned, CHURN.buffs))

----------------------------------------------------------------------
-- Out of combat again, and the two states that silence the row
----------------------------------------------------------------------

inCombat.player = nil
tick()
check(Nag.Mode() == "upkeep", "leaving combat did not put the missing buffs back")

own.resting = true
tick()
check(Nag.Mode() == "quiet", "the row nagged somebody sitting in an inn")
ns.db.buffResting = true
tick()
check(Nag.Mode() == "upkeep", "the setting for nagging while resting did nothing")
ns.db.buffResting = false
own.resting = false

own.dead = true
tick()
check(Nag.Mode() == "quiet", "the row nagged a corpse about its sharpening stone")
own.dead = false
tick()

----------------------------------------------------------------------
-- Nothing missing means nothing drawn
----------------------------------------------------------------------

own.main = true

-- Every aura the row is actually watching, read off the live list rather than
-- written out as two names here. The list is the three that ship plus whatever
-- Class/<yours>.lua added, so a pair of literals would only ever buff a warrior
-- and would leave a mage's armour square lit with nothing wrong.
for index = #own.auras, 1, -1 do
	own.auras[index] = nil
end
for index = 1, ns.Upkeep.Count() do
	local entry = ns.Upkeep.Entry(index)
	if entry.name then
		own.auras[#own.auras + 1] = { name = entry.name, expires = _G.GetTime() + 900 }
	end
end
fire("UNIT_AURA", "player")
tick()
check(Nag.Mode() == "quiet", "a fully buffed character was still shown a row")
check(Nag.Shown() == 0, "a row with nothing wrong drew a square")

-- Unlocked it comes back as a preview of everything it watches, because a
-- frame you cannot see is a frame you cannot drag.
ns.db.locked = false
Nag.Lock()
tick()
check(Nag.Mode() == "preview", "unlocking did not show the row")
check(Nag.Shown() == Upkeep.Count(),
	("the preview drew %d squares of %d"):format(Nag.Shown(), Upkeep.Count()))
ns.db.locked = true
Nag.Lock()

----------------------------------------------------------------------
-- The list you keep, which is where a flask goes
----------------------------------------------------------------------

local tracked = Upkeep.Count()
local added, said = Upkeep.Add(17038)
check(added, "adding a spell to the row was refused: " .. tostring(said))
check(Upkeep.Count() == tracked + 1, "an added spell did not reach the list")

tick()
check(says("Spell17038"), "an added buff that is not on you was not nagged about")

-- Appended rather than written to a fixed index. The aura scan stops at the
-- first slot the client will not name, so a gap left by a class whose row is
-- shorter would hide everything after it.
local at = #own.auras + 1
own.auras[at] = { name = "Spell17038", expires = _G.GetTime() + 3600 }
fire("UNIT_AURA", "player")
tick()
check(not says("Spell17038"), "an added buff that is on you was nagged about anyway")
own.auras[at] = nil
fire("UNIT_AURA", "player")

check(Upkeep.Add(17038) == false, "the same spell went on the row twice")
check(Upkeep.Add("not a number") == false, "a word was taken as a spell id")

for extra = 1, Upkeep.MaxExtra() do
	Upkeep.Add(17038 + extra)
end
check(#Upkeep.Extra() == Upkeep.MaxExtra(),
	("the list holds %d and the cap is %d"):format(#Upkeep.Extra(), Upkeep.MaxExtra()))
check(Upkeep.Add(19999) == false, "the list went past its own cap")

for _ = 1, Upkeep.MaxExtra() do
	Upkeep.Remove(Upkeep.Extra()[1])
end
check(#Upkeep.Extra() == 0, "removing every added spell left something behind")
check(Upkeep.Count() == tracked, "the list did not come back to what it was")

----------------------------------------------------------------------
-- Whole pixels at every zoom
--
-- The general anchor sweep at the end of this file catches the row at
-- whatever zoom it is left in. This walks all three, because the row ships
-- at 2x and the offsets between squares are the design number multiplied by
-- the zoom.
----------------------------------------------------------------------

own.main, own.off = false, false
for index = #own.auras, 1, -1 do
	own.auras[index] = nil
end
fire("UNIT_AURA", "player")

local shipped = ns.db.buffZoom
local off = 0
for _, zoom in ipairs({ 1, 2, 3 }) do
	ns.db.buffZoom = zoom
	Nag.Apply()
	tick()
	for slot = 1, Nag.Shown() do
		local square = Nag.Icon(slot)
		local px = ns.UI.Pixel(square)
		for _, point in ipairs(square.points or {}) do
			local x, y = (point[4] or 0) / px, (point[5] or 0) / px
			if math.abs(x - math.floor(x + 0.5)) > 1e-6
				or math.abs(y - math.floor(y + 0.5)) > 1e-6 then
				off = off + 1
			end
		end
	end
end
check(off == 0, ("%d square anchors were off a whole pixel"):format(off))
ns.db.buffZoom = shipped
Nag.Apply()
tick()

-- The tooltip is put away rather than left open. Everything else in this
-- section is deliberately left drawn for the anchor sweep, but a tooltip
-- still up here is one anchored to a nag square, and the sections after this
-- one hover things of their own.
ns.UI.Tooltip.Close()

-- Left drawn on purpose. The anchor sweep at the end of this file walks
-- every frame on the grid, and a row that had put itself away would be a row
-- that sweep never looked at.
print(("buffs  %d tracked, %d missing, %s; racial %s; %.2f KB per 50 ticks, gate is %.2f")
	:format(Upkeep.Count(), Nag.Shown(), Nag.Mode(),
		Racials.Describe(), churned, CHURN.buffs))
