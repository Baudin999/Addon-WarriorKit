-- The client this addon is tested against, assembled.
--
-- Each file beside this one installs one part of a stub of the 2.5.6 client
-- into _G and hands its own handles back on the table this returns. They load
-- in the order listed at the foot of this file, and each reads names the ones
-- before it put there, so that order is the dependency graph rather than a
-- tidy-up.
--
-- Nothing here is a client. It is enough of one to load every file in TOC
-- order and answer what ../sections asks. What it does not prove is that the
-- game agrees: every API here answers what these files say it answers, and a
-- stub that returns the wrong thing is a test that passes and a client that
-- does not.

local PLAYER_CLASS, load = ...
local UI_SCALE = 0.65

-- Client state a section is allowed to write.
--
-- Ten values the stub keeps as a plain variable and a section sets to drive
-- a scene: how much money is in the purse, what the repair bill is, who is
-- being inspected, how tall the screen is. Every one of them is read by the
-- client and written by a section, so a per-file copy would go stale on the
-- first write. They live on one table and both sides name it.
local state = {
	SCREEN_H = 1440, -- a height that is not 768, which is the whole point
	incomingHeals = 0,
	inspecting = nil,
	lootMethod = "group",
	paidBy = nil,
	purse = 0,
	repairBill = 0,
	repairsMerchant = true,
	talentShape = "modern",
	threatReader = nil,
	-- How many times the addon has asked for the interface to be rebuilt. A
	-- count rather than a flag, because the one control that asks is armed and
	-- the whole point of arming it is that the first press must not.
	reloads = 0,
}

-- Read here rather than beside the TOC walk, because the UnitClass stub is
-- installed long before the addon loads.
local WARRIOR = PLAYER_CLASS == "WARRIOR"

-- Every allocation gate in the harness, in one table.
--
-- One table rather than one local each because a gate is read from a section
-- file that has no other reason to know the rest of them exist, and a table
-- is one name to hand over instead of seven. Anything added here is a key.
--
-- All of them are ratchets rather than ceilings. Each sits just above what
-- the measurement reads today, and the next improvement lowers it in the same
-- commit. None of them is zero, because a gate of zero is a claim that a
-- sampled figure can never move.
local CHURN = {
	list = 0.05,
	skin = 0.5,
	meter = 0.2,
	bars = 0.05,
	swing = 0.05,
	buffs = 0.05,
	cooldowns = 0.05,
	cast = 0.05,
	world = 0.05,
	party = 0.05,
	hide = 0.05,
}

-- The bars' steady state, in KB per fifty ticks with two bars up, covering the
-- plate path and the list path both.
--
-- A ratchet, not a ceiling. It was 51.76 before the list collector stopped
-- allocating and 4.10 after, so the gate went in at 5.0. Then it measured 0.17
-- and the gate came to 0.5, then 0.09 and the gate came to 0.25. It measures
-- 0.00 now and the gate is 0.05.
--
-- What took it to zero is named and is not a scene change this time. The tick
-- was rebuilding the party or raid on every pass to get the unit list its
-- threat comparison walks, which is a table write and a token concat per
-- member, five times a second, for an answer that changes when somebody joins.
-- ns.Unit.Roster already held that list and rebuilds it on GROUP_ROSTER_UPDATE,
-- so the walk is gone and what is left on the tick allocates nothing at all.
--
-- The gate is 0.05 rather than 0.00 because a gate of zero is a claim the
-- measurement can never move, and this one is a sampled figure.

-- The skin's tick, in KB per fifty ticks across all three unit frames. Same
-- kind of ratchet. It was 18.75 while the level tag was built and then compared
-- on every tick, which is a tostring and a concat per frame to say a number
-- that changes when the unit does, and 0.00 once the tags were interned. Set at
-- the smallest figure that is not a claim the measurement can never move.

-- The meters' tick, in KB per fifty ticks, with a party of three, both panes up
-- and the clock running. Same kind of ratchet as the two above, measured on a
-- harder scene.
--
-- Those two are quoted with nothing moving, and a meter with nothing moving
-- allocates nothing at all: every write in Meter/Window.lua is guarded on a
-- number rather than on the string it would make, so a frozen meter measures
-- 0.00 here. A gate on that figure would be measuring the guards.
--
-- So the clock moves inside the loop. The seconds tick over, the rates fall
-- between them, and the strings that draw both have to be built. That is a
-- meter's real steady state and it cannot be zero. It measures 0.16 and the
-- gate is 0.20.
--
-- Which is not an argument that the guards are wasted. In a fight they save
-- very little, because the numbers move every tick and the string gets built
-- either way. What they buy is the other case entirely: a meter sitting on
-- screen between pulls, which is most of a session, costs nothing at all.

-- The cloned action bars' tick, in KB per fifty ticks across every square on
-- every bar the stub client has on, which is four bars of twelve.
--
-- Same kind of ratchet as the three above and quoted on the same terms. Nothing
-- in Bars.Update builds anything: the slot comes back off the button's own
-- action attribute, Slot.State returns loose values rather than a table, and
-- Ability.Draw compares before every write. Forty-eight squares with nothing
-- moving therefore measure 0.00, and the gate is the smallest figure that is
-- not a claim a sampled number can never move.
--
-- What would move it is the shape this addon has caught twice already: a table
-- built per square to carry the six values Ability.Draw takes as six
-- arguments. At forty-eight squares and ten ticks a second that is four hundred
-- and eighty throwaway tables a second, which is the number this gate exists to
-- refuse.

-- The swing timer's tick, in KB per fifty ticks with both hands running and the
-- Slam band drawn. This is the only thing in the addon that draws on every
-- frame, so it is the tick where an allocation costs the most.
--
-- Nothing on that path builds anything. The fill is one multiply and one
-- SetValue, the band is placed only when one of its two pixel edges moves, and
-- ns.Slam.Window hands back three numbers rather than a table.
--
-- It measured 0.03 with the fill rounded to a pixel and written only when that
-- pixel changed, and it measures 0.03 with the fill written unguarded on every
-- frame. That is the measurement the unguarded write was asked for: dropping
-- the guard bought smooth motion and cost nothing the collector can see. The
-- gate stays at 0.05. What is left of the 0.03 is the flip: the gauge repaints
-- its fill, its spent track and its four edges twice a swing, on the two ticks
-- the window opens and closes on.

-- The enemy cast fills, in KB per two hundred frames with two mobs each casting
-- a three second spell over and over. The second thing in the addon to draw on
-- every frame, and the one with the most of them on screen at once: fifteen
-- plates in a raid is fifteen fills and fifteen counting numbers.
--
-- Quoted with the mobs casting rather than idle, for the reason the meters are
-- quoted with the clock moving. Idle, the sweep is a walk and one IsShown per
-- bar and measures nothing, and a gate on that figure would be measuring the
-- early return.
--
-- It measures 0.00. The fill is a subtract, a divide and a SetValue, and the
-- number under it is drawn from a table of strings built once per tenth ever
-- shown, so a mob casting the same spell twice draws the second one out of the
-- first one's leavings. Written as a plain format call it measured 0.93, which
-- is a hundred and fifty throwaway strings a second at raid size.

local H = {
	UI_SCALE = UI_SCALE, PLAYER_CLASS = PLAYER_CLASS,
	WARRIOR = WARRIOR, CHURN = CHURN, state = state,
}

-- In order. Each one reads what the ones above it left on H.
for _, part in ipairs({
	"01-widgets",
	"02-text",
	"03-player",
	"04-hands",
	"05-quests",
	"06-log",
	"07-chat",
	-- Last of the seven that were here, because it layers over what 03-player
	-- and 06-log installed: a token the group knows about is answered from its
	-- own record and everything else falls through to the constants those two
	-- shipped. It also wraps CreateFrame, which every file above it defines or
	-- uses, so it has to be the last word on that as well.
	"09-group",
	-- After 09-group, because it makes a frame and 09-group is the last word on
	-- CreateFrame. It also wraps the UseContainerItem that 04-hands installed:
	-- the same call sells at a merchant and attaches at a mailbox, and which one
	-- it does is the flag the send pane sets, so both behaviours have to be
	-- reachable from one function the way they are in the game.
	"10-mail",
	-- Last, because it wraps the CreateFrame 09-group already wrapped and has to
	-- be the outermost of the two: a frame asked for with GameTooltipTemplate
	-- has to reach this whatever else is layered underneath.
	"11-tooltip",
	-- After 05-quests and after 09-group, and both matter. It replaces the two
	-- log calls 05-quests installed with a log that has zone headers in it,
	-- which is the shape the client really answers and the shape Quests/Log.lua
	-- exists to fold; the quest that file's clutter fixtures need you to be on
	-- is still in it. And it makes a frame, so it has to come after the last
	-- word on CreateFrame.
	--
	-- Below 11-tooltip rather than above it, which does not break that file's
	-- claim to be last: what it is last at is wrapping CreateFrame, and this
	-- file wraps nothing. It asks for one frame through the region helper and
	-- installs plain functions on _G beside it.
	"12-questlog",
	-- Last, and it reads what 03-player and 04-hands left: the item table it
	-- adds four pieces of gear to, and the worn table 04-hands answers every
	-- slot that is not a hand out of. One GetInventoryItemLink in this client
	-- rather than two wrapping each other.
	"13-character",
	-- Last, and it needs nothing but the Region table 01-widgets exported and
	-- the counted calls the files above installed: it defines the press that
	-- reaches all of them, and the client's own half of one.
	"14-secure",
	-- Last, and it layers over what 12-questlog.lua installed rather than
	-- replacing it: the same C_Map answers the quest log's two zones and the
	-- world map's tree, because both windows draw through UI/Chart.lua and a
	-- second C_Map would leave one of them reading the wrong one. It also fills
	-- in the two registers 05-quests.lua left empty on Questie's map module,
	-- and makes one frame, so it wants the last word on CreateFrame above it.
	"15-worldmap",
	-- Last, and it layers over 15-worldmap.lua the way that file layers over
	-- 12-questlog.lua: the same C_Map answers the quest log's zones, the world
	-- map's tree and the dungeon log's dungeons. It also wraps the two item
	-- lookups 04-hands.lua installed so they answer an id as well as a link,
	-- which is the one part of the addon that starts from an id.
	"16-dungeons",
}) do
	load("client/" .. part .. ".lua")(H)
end

return H
