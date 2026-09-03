local ADDON, ns = ...

local EnemyBars = {}
ns.EnemyBars = EnemyBars

-- The debuff row, as it ships, is not here.
--
-- Which debuffs matter is a spec question, so the list is a fact about your
-- spec and lives in Class\<yours>.lua under `debuffs`, which is the rule every
-- other part of the addon follows. Nothing in this file names a spell any more.
-- An arms warrior watches Rend, Deep Wound and Mortal Strike; a protection one
-- watches Sunder and wants the room back; an enhancement shaman applies none of
-- the five and used to be handed all of them anyway, because this list was one
-- constant and it was saved per account.
--
-- Rank 1 IDs in those files, because matching happens on the localised name:
-- every rank counts, another warrior's Sunder shows up, and one entry covers a
-- spell you will re-rank six times.
--
-- This is still the starting list and not the list. What a bar tracks is
-- ns.dbc.barsSpells, which the panel and `bars debuff` edit, because which
-- debuffs matter is a fight question as well as a spec one.

-- The most a bar will track. The aura scan is forty slots against every name on
-- the list, per mob, on every reading and on every aura the mob gains or loses,
-- and the row still has to fit above a
-- bar that is 120 pixels wide at its narrowest. Ten is past anything a warrior
-- applies and cheap enough not to be worth arguing about.
local MAX_SPELLS = 10

-- What the panel's picker offers is not here either, for the same reason and
-- with one addition: it is a class fact rather than a spec one, so it sits on
-- the class table under `suggested` and every spec of that class shares it. The
-- picker is a shortlist of what you could put on the row, and a fury warrior
-- who wants to watch Sunder for one fight should not have to type a number to
-- get at a spell his own class applies.
--
-- It is a shortlist and not a limit either way, because the panel also takes a
-- bare spell ID and so does `bars debuff add`. An ID this client cannot name is
-- dropped from the offer rather than shown as a blank row.
--
-- Every ID in those lists is the ID of the aura that lands on the mob, never
-- the ID of the spell or talent that applies it. For a ranked spell those are
-- the same thing and rank 1 covers every rank. For a proc and for a stun bolted
-- onto a charge they are two different spells with two different names, and the
-- one you find first is the wrong one. Deep Wounds is the case that got shipped
-- broken: 12162 is the talent, the picker offered it, and the square never lit
-- up once. See REPLACED below.

-- An ID this addon offered that no aura will ever carry, and the ID that works
-- in its place.
--
-- 12162 is the Deep Wounds talent. The client names it "Deep Wounds" and
-- ns.SpellName answers happily, so nothing looked wrong: the picker showed the
-- entry, the square drew, and it stayed dark through every fight. The aura that
-- actually lands is 12721, and the client calls that one "Deep Wound",
-- singular. Since the scan matches on the name, one letter was the whole bug.
--
-- Two doors have to be shut, not one. A saved list keeps whatever was already
-- in it, because the spec's own list is read once on a fresh character and
-- never again, so anyone who picked Deep Wounds before this fix still carries
-- the dead ID. And a bare number goes on through the panel's text field and
-- `bars debuff add`, where Wowhead's search for "deep wounds" still lands on
-- the talent first. So the swap happens at login and again inside AddSpell.
local REPLACED = {
	[12162] = 12721, -- the Deep Wounds talent, for the Deep Wound bleed
}

-- How often every bar is read off the client from the top, in seconds.
--
-- It was a fifth of a second, which is the rate every readout in this addon
-- runs at, and on this one it was a poll: thirty client calls per bar per pass
-- to find out that a mob nothing had happened to still had the same name, the
-- same level and the same debuffs. Fifteen plates made that about 2,400 calls a
-- second.
--
-- The client already says when a mob's health, auras, threat or target move,
-- and Attach registers for all four against the plate's own token. What is left
-- for a pass over everything is the part no event carries: a plate that should
-- no longer have a bar, the line saying who else is on the mob, and a client
-- that fires none of the four. A second is soon enough for all three.
local VERIFY = 1

-- One empty table handed back wherever the registry answers nothing, so a class
-- with no file and a client that has not said what you are both walk zero
-- entries instead of raising.
local NONE = {}

-- Pixels, not units.
--
-- Every widget here sits on the pixel grid in UI/Pixel.lua, where one unit is
-- one physical pixel, so these are the sizes the bar actually occupies on the
-- monitor and they are the same on every monitor. That is the point of the
-- grid and it is also the one thing it costs: a 21 pixel bar is a fifth of the
-- screen height on a laptop and a tenth of it on a 4K panel. `bars zoom` is the
-- answer to that, and it is a whole number because a fractional one would put
-- everything back on half pixels.
--
-- The icon's edge is ns.db.barsIconSize and only the gap between icons is
-- fixed, because the row is as long as the list now and the list is yours.
--
-- This used to say 16 and 32 were the two sizes with a right answer. They are
-- not, and the square has never been drawn at either of them, for two reasons
-- that both live in this part of the addon.
--
-- The square carries a one pixel border and the art is inset inside it, so a
-- 20 pixel setting draws 18 pixels of icon. And ns.UI.Icon crops five texels
-- off each edge to lose the border the client bakes into the art, so 54 texels
-- are sampled and not 64. The client keeps half sized copies and picks the pair
-- nearest what was asked for, so the exact sizes are the ones 54 halves down
-- to, which is 54 and 27 rather than 32 and 16.
--
-- Add the border back and the only setting in the 16 to 32 range that draws one
-- texel per pixel is 29. 20 draws 18 pixels from 54 texels, which is 58 percent
-- of the way between two stored copies and about as blended as it gets.
-- EnemyBars.IconAdvice is where that arithmetic lives, the panel and the slash
-- word both read it, and the harness checks the number it names is really
-- exact rather than trusting a comment.
local ICON_GAP = 4

-- What the square's edge may be set to. Named here rather than written into the
-- panel and the slash word separately, because EnemyBars.IconAdvice has to
-- search the same range those two offer or it will name a size neither reaches.
--
-- The ceiling is 56 rather than a round number. 54 texels survive the crop, the
-- border takes two pixels, so 56 is the largest square where a stored texel
-- still lands on a screen pixel. Above it the client is stretching a 54 texel
-- picture over more pixels than it has and the art goes soft again, so a higher
-- ceiling would only offer sizes that look worse than the one below them.
--
-- It was 32, which was chosen when the row was four fixed icons on a 180 pixel
-- bar. That put the whole top half of the useful range out of reach: `bars zoom`
-- did not work, so the only way to get a big icon was this number, and this
-- number stopped well short of one.
local ICON_MIN, ICON_MAX = 16, 56

-- Even, and that is the whole reason it is not 21. Replace centres the gauge on
-- the mob, so the offset is half the bar height, and half of 21 is half a pixel:
-- every bar the addon has drawn had its origin off a boundary and everything
-- inside it drawn across two rows. PlaceOnPlate rounded that away and gave up
-- half a pixel of centring. An even bar gives up nothing.
local PLATE_BAR_HEIGHT = 22
local LIST_BAR_HEIGHT = 28

-- Both sized off ns.UI.OutlineFloor, which is 14, and that is the whole of the
-- type on this bar.
--
-- PLATE_TEXT was 12 while the threat number and the targeted-by line were
-- raised to 14 to clear the floor, so the mob's name was drawn smaller than the
-- list of who else was on it, and the name, the health number and the level all
-- carried an outline UI/Text.lua says closes up a glyph's counters below 14.
-- That is the whole of "coarse": not blurry, mush. TOP_TEXT is the room the
-- taller of the two sits in, and at 15 it clipped that glyph by a pixel.
local TOP_TEXT = 16
local PLATE_TEXT = 14
local LIST_TEXT = 14
local COUNT_TEXT_SIZE = 11
local NAME_MAX = 8
local RAID_ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- The look: flat fills, one pixel edges, no gloss and no gradient. The bar is
-- drawn from coloured rectangles rather than from UI-StatusBar, which is the
-- 2007 glass texture and reads like it. Nothing here is a file path, so there
-- is no art asset that has to still exist on this client.
--
-- Every colour on that list now comes out of ns.Unit.Color rather than out of
-- this file. It used to be declared here and declared again in Skin.lua, four
-- of the nine with the same literals typed twice, which held right up until
-- somebody warmed the green on one of them.
local Color = ns.Unit.Color
local Level = ns.Unit.Level
local Roster = ns.Unit.Roster
local Threat = ns.Unit.Threat
local Flow = ns.UI.Flow
-- The gauge itself is UI/Gauge.lua's, and the spent part behind it with it.
-- Both used to be here and the same pair of writes was in Skin.lua as well,
-- down to the fifth and the nine tenths.
local Gauge = ns.UI.Gauge
-- The cast row under the gauge, which is a widget of its own rather than
-- forty more lines in here. It knows nothing about a plate, a list or a pool:
-- this file hands it a widget and it draws on it.
local Cast = ns.Cast
-- One debuff square, drawn. The row on a bar here and the row under the skinned
-- target block are the same twelve lines and the same four guarded writes, so
-- they are one file rather than two copies. The palette the square wears,
-- including the edge this file used to name, is in there with it.
local Aura = ns.UI.Aura

local BACKDROP = Color.backdrop
local NAME_TEXT = Color.text.name
local TARGET_TEXT = Color.text.target
-- The name's third state, and the same table the level tag wears for the same
-- fact, so the two of them are one channel saying one thing twice.
local WORTHLESS = Color.xp.none
local HEALTH_TEXT = Color.text.value
local QUEST_TEXT = Color.text.quest

-- Which bar is yours, said with the one channel nothing else on the bar is
-- using. The fill, the track and the number above belong to threat, the level
-- glyph belongs to what the kill is worth, and the frame belongs to reaction,
-- so a fourth colour would be a fourth thing to read on a bar that already has
-- three. Alpha is free.
--
-- Attach calls SetIgnoreParentAlpha, which throws away the client's own
-- nameplateNotSelectedAlpha, and that is deliberate rather than an oversight to
-- undo: the plate's alpha also fades with distance and through the plate's own
-- fade in, and in list mode there is no plate and no alpha to inherit. The bars
-- answer this themselves so the answer is the same in both modes and means one
-- thing only.
--
-- With nothing targeted every bar is bright. Dimming the whole screen to say
-- "none of these" is noise, and it is the moment you most want to read threat
-- off a mob that is not yours yet.
local TARGET_ALPHA = 1.00
local OTHER_ALPHA = 0.55

-- How long a bar takes to arrive and to leave, in seconds.
--
-- A plate is put up and taken down in one frame, and a bar that follows it
-- exactly appears and vanishes the same way: at fifteen plates in a pull that
-- is fifteen rectangles blinking on, which reads as a glitch rather than as
-- mobs coming into range. The two numbers are not equal on purpose. Coming in
-- is information arriving and wants to be quick; going out is a bar you have
-- already read and the eye is helped by the tail, so it is the slower of the
-- two by half again.
--
-- Both are short enough that the whole ramp is over before a bar that has just
-- arrived could be stale: a plate arriving marks its widget and the next frame
-- draws it.
--
-- This is a multiplier on the alpha above, never a replacement for it: the two
-- say different things and both have to survive. Which bar is yours is 1.00
-- against 0.55, and a bar arriving is that number climbing from nothing.
local FADE_IN = 0.15
local FADE_OUT = 0.22

-- Every widget with a ramp still running, as a set. Empty is the normal state
-- and the driver's first line, so a screen full of settled bars costs one
-- `next` per frame.
local fading = {}

-- Every widget an event has said something about and no frame has drawn yet, as
-- a set. Same shape as `fading` above and for the same reason: empty is the
-- normal state and the pass that drains it opens by saying so.
local dirty = {}

-- The per-frame pass, kept rather than discarded so it can be switched off.
--
-- A frame with no chamber open, no ramp running and nothing marked has no work
-- at all, and a ticker with no work is one the client should not be calling
-- sixty times a second. Whatever puts work on it starts it and the frame that
-- finds none left stops it.
local moving

local function Wake()
	if moving and not moving:Running() then
		moving:Start()
	end
end

local anchor, header, place
-- Assigned in the events section at the foot of the file, because it is the
-- event frame's business and that frame is made down there. Declared up here
-- because EnemyBars.Rebuild is what turns the cast events on and off and sits
-- above it. Nothing can reach Rebuild before the file has finished loading.
local CastEvents
local pool, attached, listWidgets = {}, {}, {}
-- Every enemy plate the client currently has up, kept by the add and remove
-- events. GetNamePlates builds a fresh table on every call, and both the list
-- collector and the attach walk wanted one on every reading.
local plateUnits = {}

-- Probed rather than called, the way Unit/Role.lua reads its optional APIs: a
-- client without one of these treats every player as unflagged, which is a
-- missing bar rather than an error on every reading.
local UnitIsPVP, UnitIsPVPFreeForAll = _G.UnitIsPVP, _G.UnitIsPVPFreeForAll
local UnitFactionGroup = _G.UnitFactionGroup

-- Whether a unit gets a bar at all. One function because it is one rule asked
-- from three places: the plate arriving, the tick deciding whether a bar
-- stays, and the list collector.
--
-- Attackable is the client's answer and it is most of the rule. A player of
-- the other faction is the exception, and the flag is the rest of it. On a PvP
-- realm a Horde player standing in Durotar is attackable and unflagged, and a
-- bar on them is a bar on somebody who has not started anything; the moment
-- either of you does, the flag goes up and the bar with it. A player of your
-- own faction is left to the client, because a duel does not flag anybody and
-- a bar on your duel partner is the point of the duel.
--
-- Free-for-all counts as flagged. Gurubashi is the one place a player of the
-- other faction is attackable under a flag that is not the PvP one.
local function Wanted(unit)
	if not UnitCanAttack("player", unit) then
		return false
	end
	if not UnitIsPlayer(unit) then
		return true
	end
	if type(UnitFactionGroup) == "function" and UnitFactionGroup(unit) == UnitFactionGroup("player") then
		return true
	end
	if type(UnitIsPVP) == "function" and UnitIsPVP(unit) then
		return true
	end
	return type(UnitIsPVPFreeForAll) == "function" and UnitIsPVPFreeForAll(unit) == true
end
-- ns.dbc.barsSpells, resolved. Names because the aura scan matches on the
-- localised name, textures because the row draws them, and both indexed by slot
-- so the tick reads two arrays rather than calling into the spell API. Rebuilt
-- by Retrack whenever the list changes, which is the only time it can.
local trackedNames, trackedIcons = {}, {}
-- IDs on the list this client will not name. Kept rather than deleted, because
-- an account plays both flavours and a spell Era has never heard of should come
-- back when you log into the TBC character it was added on.
local unresolved = {}
local targeters = {}
-- unit token -> that member's pet token. Built once against the fixed token set
-- rather than concatenated per member per tick, for the reason
-- ns.Unit.TargetToken exists.
local PET_FOR = { player = "pet" }
for index = 1, 40 do
	PET_FOR["raid" .. index] = "raidpet" .. index
end
for index = 1, 4 do
	PET_FOR["party" .. index] = "partypet" .. index
end
local haveTarget = false -- gathered once a tick, read by every widget
local firstSeen, seenCounter = {}, 0
local scratch = {}
local stripped, pending = {}, {}
-- Bumped by anything that changes the shape of a widget, which is how a pooled
-- widget knows its layout is stale. See Attach.
local layoutEpoch = 0
local warnedNameplates = false
local warnedThreat = false

--------------------------------------------------------------------------
-- The tracked list
--
-- Which debuffs the row above a bar shows, as an array of spell IDs in the
-- order they are drawn. It lives in ns.db, so it is one setting the panel edits
-- and `bars debuff` edits and neither owns; everything below is the only code
-- allowed to write it, because every write has to be followed by a re-resolve
-- and a relayout and a caller that forgot one would leave a row of blank
-- squares.
--
-- Matching is by localised name, which is what makes rank 1 enough. That is
-- also why two IDs that resolve to the same name are refused: they would be two
-- identical icons lighting up and going out together.
--------------------------------------------------------------------------

-- A fresh table every time. The saved list is mutated in place by Add and
-- Remove, so a caller handed the module's own copy would be editing the
-- default, and the next reset would restore whatever it had been edited into.
-- The border the square draws round its art, one pixel on each of four sides,
-- so the art is two pixels smaller than the number in the panel.
local ICON_BORDER = 2

-- What a debuff square really draws on screen at a given setting, and whether
-- the client has to blend two stored copies to do it.
--
-- Three numbers decide it and two of them are not the setting. The square is
-- barsIconSize design pixels, so the zoom multiplies it. The border is one
-- screen pixel a side and does not scale, so it takes two off whatever that
-- comes to. And ns.UI.Icon crops the art to 54 texels, so the sizes where one
-- stored texel lands on one pixel are 54 and 27 rather than the powers of two
-- everybody expects.
--
-- Returns the drawn size in screen pixels, whether it is exact, and the nearest
-- setting in the range that would be. That last one moves with the zoom: at 1x
-- it is 29, which draws 27 off the half size copy, and at 2x it is 28, which
-- draws 54 off the full size copy and is the sharpest a spell icon gets.
--
-- Read out of ns.UI.IconSizes rather than typed, so changing the crop in
-- UI/Draw.lua moves the advice instead of leaving a stale number in a note.
function EnemyBars.IconAdvice(size, zoom, low, high)
	size = size or ns.db.barsIconSize
	zoom = zoom or ns.db.barsZoom or 1
	low, high = low or ICON_MIN, high or ICON_MAX

	local function drawnAt(setting)
		return setting * zoom - ICON_BORDER
	end

	local wanted = {}
	for _, drawn in ipairs(ns.UI.IconSizes()) do
		wanted[drawn] = true
	end

	local nearest = nil
	for setting = low, high do
		if wanted[drawnAt(setting)] then
			if not nearest or math.abs(setting - size) < math.abs(nearest - size) then
				nearest = setting
			end
		end
	end

	return drawnAt(size), wanted[drawnAt(size)] or false, nearest
end

-- The range the panel and the slash word both offer, so neither writes it out.
function EnemyBars.IconRange()
	return ICON_MIN, ICON_MAX
end

-- The same answer as a sentence, because three callers want to say it and none
-- of them should be re-deriving it.
function EnemyBars.DescribeIcon(size, zoom)
	local drawn, exact, nearest = EnemyBars.IconAdvice(size, zoom)
	if exact then
		return ("%d screen pixels of art inside the border, one stored texel per pixel")
			:format(drawn)
	end
	if not nearest then
		return ("%d screen pixels of art inside the border, blended from two stored copies, and nothing in this range is exact at this zoom")
			:format(drawn)
	end
	return ("%d screen pixels of art inside the border, blended from two stored copies. %d is the size that is not")
		:format(drawn, nearest)
end

-- What this spec ships with, as a list of its own that the caller may edit.
--
-- Empty for a class nobody has written a file for and for a character whose
-- class the client has not named yet, which are the same two nils every other
-- part of the addon gets back from the registry and treats as "do not build".
function EnemyBars.DefaultSpells()
	local list = {}
	for index, spellID in ipairs(ns.Class.Of("debuffs") or NONE) do
		list[index] = spellID
	end
	return list
end

-- The list this character tracks, seeded from the spec the first time it is
-- asked for.
--
-- Seeded here rather than in the defaults table because the class is not
-- reliably known while the files load, which is the rule Class.lua states and
-- the reason Loadouts.All seeds its rows the same way. Asked before the client
-- will say what you are, this hands back the empty list and records nothing, so
-- a read that early cannot latch a warrior onto no debuffs for the session.
--
-- A list that already has something in it counts as seeded whether this put it
-- there or Core's migration carried it over from the account file, because the
-- one thing this must never do is overwrite a row you edited.
function EnemyBars.Spells()
	local list = ns.dbc.barsSpells
	if ns.dbc.barsSpellsSeeded then
		return list
	end
	if #list > 0 then
		ns.dbc.barsSpellsSeeded = true
		return list
	end
	if not ns.Class.Token() then
		return list
	end

	ns.dbc.barsSpellsSeeded = true
	for index, spellID in ipairs(ns.Class.Of("debuffs") or NONE) do
		list[index] = spellID
	end
	return list
end

-- What the panel's picker offers: every debuff your class puts on a mob, off
-- the class table rather than the spec's, because a shortlist that only offered
-- what your own tree applies would be a picker you cannot use to add the one
-- thing you went looking for.
function EnemyBars.Suggestions()
	return ns.Class.Of("suggested") or NONE
end

function EnemyBars.MaxSpells()
	return MAX_SPELLS
end

-- Which slot a spell is in, or nil. The panel asks so it can leave a debuff you
-- already track out of the picker.
function EnemyBars.Slot(spellID)
	for index, id in ipairs(EnemyBars.Spells()) do
		if id == spellID then
			return index
		end
	end
	return nil
end

-- The IDs the list carries that this client cannot name, so the panel and
-- /wk status can say so rather than leaving a row silently short.
function EnemyBars.Unresolved()
	return unresolved
end

-- Swap every dead ID on the saved list for the one that works, once, at login.
-- It runs before the first Resolve, so no name has been taken off a dead ID yet
-- and nothing downstream has to know this happened. It edits the list and
-- nothing else, because at login the anchor does not exist and a relayout from
-- here would raise. Resolve is the next line in that handler.
--
-- A list that already carries the replacement drops the dead entry rather than
-- keeping both. Two IDs that resolve to one name are two squares lighting up
-- and going out together, which is exactly what AddSpell refuses to create.
function EnemyBars.Repair()
	local list = EnemyBars.Spells()
	for index = #list, 1, -1 do
		local live = REPLACED[list[index]]
		if live then
			if EnemyBars.Slot(live) then
				table.remove(list, index)
			else
				list[index] = live
			end
		end
	end
end

local function Resolve()
	local count = 0
	wipe(unresolved)
	for _, spellID in ipairs(EnemyBars.Spells()) do
		local name = ns.SpellName(spellID)
		if name then
			count = count + 1
			trackedNames[count] = name
			trackedIcons[count] = ns.SpellTexture(spellID)
		else
			unresolved[#unresolved + 1] = spellID
		end
	end
	-- Trimmed rather than left long, because #trackedNames is what the row
	-- length, the aura scan and the tick all count in.
	for index = #trackedNames, count + 1, -1 do
		trackedNames[index] = nil
		trackedIcons[index] = nil
	end
end

-- The list moved, so every widget's row is the wrong length and every widget is
-- the wrong height. ApplyLayout bumps the epoch and re-lays the bars that are
-- up; the ones in the pool take theirs when they next attach, which is what the
-- epoch is for.
function EnemyBars.Retrack()
	Resolve()
	EnemyBars.ApplyLayout()
	EnemyBars.Rebuild()
end

-- Returns true and the spell's name, or false and the sentence to print.
function EnemyBars.AddSpell(spellID)
	spellID = tonumber(spellID)
	if not spellID or spellID <= 0 or spellID ~= math.floor(spellID) then
		return false, "a spell id is a whole number. It is the last part of the spell's Wowhead address."
	end
	-- Typed the talent, got the bleed. The caller prints the name that comes
	-- back, so the substitution says itself: you asked for Deep Wounds and the
	-- addon tells you Deep Wound is on the bar.
	spellID = REPLACED[spellID] or spellID

	local name = ns.SpellName(spellID)
	if not name then
		return false, ("this client does not know spell %d."):format(spellID)
	end

	local list = EnemyBars.Spells()
	for _, id in ipairs(list) do
		if id == spellID or ns.SpellName(id) == name then
			return false, name .. " is already on the bar."
		end
	end
	if #list >= MAX_SPELLS then
		return false, ("the bar tracks %d debuffs at most. Take one off first."):format(MAX_SPELLS)
	end

	list[#list + 1] = spellID
	EnemyBars.Retrack()
	return true, name
end

-- Returns true and the name it took off, or false when the list never had it.
function EnemyBars.RemoveSpell(spellID)
	spellID = tonumber(spellID)
	local list = EnemyBars.Spells()
	for index, id in ipairs(list) do
		if id == spellID then
			table.remove(list, index)
			EnemyBars.Retrack()
			return true, ns.SpellName(id) or ("spell " .. id)
		end
	end
	return false
end

-- Back to what this spec ships with. The table is emptied and refilled rather
-- than replaced, because ns.dbc holds the one the client saves and swapping it
-- for a fresh table would leave the saved variable pointing at the old one.
function EnemyBars.ResetSpells()
	local list = ns.dbc.barsSpells
	for index = #list, 1, -1 do
		list[index] = nil
	end
	ns.dbc.barsSpellsSeeded = true
	for index, spellID in ipairs(ns.Class.Of("debuffs") or NONE) do
		list[index] = spellID
	end
	EnemyBars.Retrack()
end

-- One line for the panel note and for /wk status: the names, in order, or what
-- is wrong with the list.
function EnemyBars.DescribeSpells()
	if #trackedNames == 0 then
		return "nothing tracked, so the row above each bar is empty"
	end
	local line = table.concat(trackedNames, ", ")
	if #unresolved > 0 then
		line = line .. (", and %d this client cannot name"):format(#unresolved)
	end
	return line
end

-- Cut on a character, not on a byte. Names arrive as UTF-8 and sub() counts
-- bytes, so a plain slice through a two or three byte sequence on a non-English
-- realm draws a replacement glyph on the end of every long name.
local function ShortName(name)
	if not name then
		return "?"
	end
	if #name <= NAME_MAX then
		return name -- every name this short is at most NAME_MAX characters too
	end
	local byte, count = 0, 0
	while byte < #name do
		if count >= NAME_MAX then
			return name:sub(1, byte)
		end
		local lead = name:byte(byte + 1)
		byte = byte + (lead < 0xC0 and 1 or (lead < 0xE0 and 2 or (lead < 0xF0 and 3 or 4)))
		count = count + 1
	end
	return name
end

--------------------------------------------------------------------------
-- Data gathering
--------------------------------------------------------------------------

-- The coloured label for one group member, cached against the name it was
-- built from. Group composition changes when someone joins or leaves, not five
-- times a second, so the format call and the ShortName slice now run on a
-- change rather than on a tick.
local labels = {}

local function Label(unit, owner)
	local subject = owner or unit
	local name = UnitName(subject)
	local entry = labels[unit]
	if entry and entry.name == name then
		return entry.label
	end
	local _, class = UnitClass(subject)
	local label = ("|c%s%s%s|r"):format(Color.ClassHex(class), owner and "*" or "", ShortName(name))
	if entry then
		entry.name, entry.label = name, label
	else
		labels[unit] = { name = name, label = label }
	end
	return label
end

-- Hoisted out of BuildTargeters rather than declared inside it, because two
-- closures per call is two closures per reading for the life of the
-- session. They read the same two module tables either way.
local function Record(unit, owner)
	local targetUnit = ns.Unit.TargetToken(unit)
	if not UnitExists(targetUnit) then
		return
	end
	local guid = UnitGUID(targetUnit)
	if not guid then
		return
	end
	local label = Label(unit, owner)
	targeters[guid] = targeters[guid] and (targeters[guid] .. " " .. label) or label
end

local function Member(unit, petUnit)
	Record(unit)
	if UnitExists(petUnit) then
		Record(petUnit, unit)
	end
end

-- guid -> "Name *Pet Name", for the line above each bar that says who else is
-- already on this mob.
--
-- Who is in the group no longer comes from here. It used to: this function
-- rebuilt the whole party or raid on every tick, eighty unit queries in a forty
-- man five times a second, and then the threat comparison walked what came out.
-- ns.Unit.Roster already had that list, built on GROUP_ROSTER_UPDATE, because
-- the meters needed the same thing and got it right. What is left here is the
-- half that genuinely does move between two ticks, which is what each member is
-- currently targeting.
local function BuildTargeters()
	wipe(targeters)
	-- Asked once here rather than once per mob in UpdateWidget. It is the same
	-- answer for every bar on the screen and this already runs exactly once a
	-- tick in both modes.
	haveTarget = UnitExists("target")

	local group = Roster.Units()
	for index = 1, #group do
		local unit = group[index]
		Member(unit, PET_FOR[unit])
	end
end

-- The colour and the line of text above the gauge. The colour is the one thing
-- on the widget that is not about health: it paints the gauge, the edge around
-- it and the line above it.
--
-- Both halves of the question live in ns.Unit.Threat now, which is also where
-- the meter reads them. What stays here is the wording, because how a bar
-- phrases a number is the bar's business and shortening a name is presentation.
--
-- While you hold the mob the number that matters is the nearest challenger, not
-- your own permanent 100%.
--
-- Three values rather than the line they make, and that is the whole of why
-- this is not a format on the tick. The line changes when the percentage rolls
-- over a whole number or when a different player is behind you; the numbers
-- behind it are what says whether either happened. Building the string first
-- and comparing it afterwards is one throwaway string per engaged bar per tick
-- to find out that nothing moved, and the guard scan does not count a format as
-- an allocation, which is how it stayed there.
--
--   colour      always
--   percent     the number worth printing, or nil for none
--   who         the name beside it
--   mode        nil on a client with the threat API, and one of three words on
--               a client without, so the two questions cannot be told apart by
--               luck when both answer nothing
local function ThreatState(unit)
	local color, percent, challenger = Threat.State(unit)
	if color then
		return color, percent, challenger and UnitName(challenger) or nil, nil
	end

	-- Vanilla has no threat API. The colour comes from who the mob is swinging
	-- at instead: you, someone else, or nobody yet. That is not threat. It
	-- cannot warn you before a mob turns, only tell you after it has. It is the
	-- honest half of the question that client can answer, and it beats a screen
	-- of identical grey bars.
	local shade, victim, mine = Threat.Swinging(unit)
	if not victim then
		return shade, nil, nil, "nobody"
	end
	if mine then
		return shade, nil, nil, "you"
	end
	return shade, nil, UnitName(victim), "them"
end

-- The wording, reached only when one of the three above moved. ShortName walks
-- a name a character at a time, so it is on this side of the guard along with
-- the format.
local function ThreatLabel(percent, who, mode)
	if mode == "you" then
		return "on you"
	elseif mode == "them" then
		return "on " .. ShortName(who)
	elseif mode then
		return ""
	end
	if not percent then
		return ""
	end
	if who then
		return ("%d%% %s"):format(percent, ShortName(who))
	end
	return ("%d%%"):format(percent)
end

-- The per-slot tables are reused rather than rebuilt, so `found` carries one
-- table per tracked spell for the life of the session and `active` says
-- whether this mob has it. A fresh table per matched debuff per mob per tick
-- is the kind of garbage that shows up as a stutter on a pull rather than as a
-- number on a frame counter.
--
-- A shorter list leaves the tail of `found` behind rather than trimming it. The
-- entries past #trackedNames are never read and never cleared, which costs one
-- table each and saves the tick from caring that the list can move.
local function ScanDebuffs(unit, found)
	for i = 1, #trackedNames do
		local slotData = found[i]
		if not slotData then
			slotData = {}
			found[i] = slotData
		end
		slotData.active = false
	end

	local index = 1
	while index <= 40 do
		local name, count, expires, duration, source
		if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
			local aura = C_UnitAuras.GetDebuffDataByIndex(unit, index)
			if not aura then
				break
			end
			name, count, expires = aura.name, aura.applications, aura.expirationTime
			duration, source = aura.duration, aura.sourceUnit
		else
			local auraName, _, auraCount, _, auraDuration, expirationTime, unitCaster =
				UnitAura(unit, index, "HARMFUL")
			if not auraName then
				break
			end
			name, count, expires = auraName, auraCount, expirationTime
			duration, source = auraDuration, unitCaster
		end

		for slot, trackedName in ipairs(trackedNames) do
			if name == trackedName then
				local slotData = found[slot]
				slotData.active = true
				slotData.count = count or 0
				slotData.expires = expires or 0
				-- The sweep's half of the timing, and the reason the fallback
				-- reads the fifth return rather than skipping it: the expiry
				-- says when the debuff ends and a wedge needs the fraction.
				slotData.duration = duration or 0
				slotData.mine = (source == "player")
			end
		end
		index = index + 1
	end
end

-- The tracked row, one square per spell on the list.
--
-- Three states per square and not eight: nobody has it, someone else has it,
-- you have it. What each of the three looks like is ns.UI.Aura's, and what
-- stays here is which of them this slot is in, which is the only part of the
-- answer a tracked list has and a live aura row does not.
--
-- Bounded by the widget as well as by the list. FitIcons makes the row as long
-- as the list and LayoutWidget calls it, but this runs on every reading and on
-- every aura event whether or not a layout has happened since the list moved, and a nil
-- index on a ticker is a thousand errors a minute rather than one.
--
-- It is a function rather than a block in UpdateWidget because it is the one
-- part of that tick that is about a list rather than about a unit, and because
-- the tick is on shape.lua's list and every line of it has to be paid for.
local function DrawDebuffs(widget, unit, now)
	ScanDebuffs(unit, scratch)
	for slot = 1, math.min(#trackedNames, #widget.icons) do
		local aura = scratch[slot]
		local active = aura and aura.active
		-- The art is the same texture every tick for the life of the setting,
		-- because a slot here stands for a spell you asked to watch rather than
		-- for an aura the mob happens to have. ns.UI.Aura guards it, so passing
		-- it every pass costs one comparison.
		Aura.Draw(widget.icons[slot], trackedIcons[slot],
			active and (aura.mine and "mine" or "theirs") or "none",
			active and aura.expires or 0, active and aura.duration or 0,
			active and aura.count or 0, now)
	end
end

--------------------------------------------------------------------------
-- Widget
--------------------------------------------------------------------------

local Text = ns.UI.Label

-- The row, fitted to the list. A frame cannot be destroyed on this client, so a
-- shorter list hides its tail rather than freeing it and a longer one grows into
-- squares that are already there: a widget that has carried eight and now
-- carries three keeps five hidden holders for the next time you add one.
--
-- The square itself is ns.UI.Aura's. It used to be twelve lines here and the
-- same four guarded writes in UpdateWidget, and the row under the skinned
-- target block wanted every one of them. The two rows are the same code now,
-- which is what stops them drifting apart the way this file's palette and
-- Skin.lua's did before ns.Unit.Color existed.
local function FitIcons(widget)
	for index = 1, #trackedNames do
		local holder = widget.icons[index]
		if not holder then
			holder = Aura.New(widget)
			widget.icons[index] = holder
		end
		holder:Show()
	end
	for index = #trackedNames + 1, #widget.icons do
		widget.icons[index]:Hide()
	end
end

-- The tracked row as a layout node, packed right and wrapped.
--
-- Right against the gauge's right edge is where it has always been and where it
-- stays: the icons are what you glance at, the gauge's right end is where the
-- health number already is, and a row that grew rightwards would walk off the
-- bar. The length is yours, and ten icons at thirty two pixels is 356 and wider
-- than any bar this addon will draw. So the row wraps upwards instead of
-- overflowing, every line right aligned under the one above it, and the bottom
-- line is the one nearest the gauge and the one that fills first. That is
-- `lineOrder = "up"`.
--
-- Every square is taller than it is wide, because the time stands over the art
-- rather than on it. How much taller is UI/Aura.lua's answer and nothing here
-- works it out again: the strip is the timer's own type height, and the type
-- size is already that file's arithmetic off the square and this widget's
-- ceiling. That height comes back beside the node, because the strip the threat
-- line shares with the bottom line of icons is as tall as an icon and the icon
-- is no longer the setting.
--
-- Split out of LayoutWidget rather than left in it. That function places every
-- region of the widget in one pass and is on scripts/shape.lua's list at a
-- number it may not exceed, and the row is the one part of it that is about a
-- list rather than about the widget.
local function IconRow(widget, iconSize, iconGap, width, px, timerCeiling, countCeiling)
	FitIcons(widget)
	local icons = {
		direction = "row", wrap = true, justify = "end", lineOrder = "up",
		gap = iconGap, width = width, alignX = "start", alignY = "end",
	}
	local height = iconSize
	for index = 1, #trackedNames do
		local wide, tall = Aura.Size(widget.icons[index], iconSize, px,
			timerCeiling, countCeiling)
		height = tall
		icons[index] = { frame = widget.icons[index], width = wide, height = tall }
	end
	return icons, height
end

-- What the client says has moved on one mob.
--
-- Four events, registered against the plate's own unit token when a bar
-- attaches, and every one of them is something a bar draws: the aura row, the
-- health gauge, the threat number, and who the mob is swinging at on a client
-- with no threat API. Between them they are the whole of what the five hertz
-- pass was polling for, and polling for it meant thirty client calls per bar
-- whether or not anything had happened.
--
-- Marked rather than drawn, because a mob taking four hits in one frame is four
-- events and one bar. The per-frame pass draws what is marked, so a change is on
-- screen on the next frame rather than up to a fifth of a second later.
--
-- The unit is compared even though ns.RegisterUnitEvent asked the client to
-- filter, because a client without RegisterUnitEvent gets the plain
-- registration and hands over every unit it tracks. Both live clients filter;
-- the comparison is what makes the fallback correct rather than merely quiet.
local WATCHED = {
	"UNIT_HEALTH",
	"UNIT_AURA",
	"UNIT_THREAT_LIST_UPDATE",
	"UNIT_TARGET",
}

local function Touched(widget, _, unit)
	if unit == widget.unit then
		dirty[widget] = true
		Wake()
	end
end

-- cold: builds one nameplate widget, on the tick a plate first appears.
local function CreateWidget()
	local widget = CreateFrame("Frame", nil, UIParent)
	widget:EnableMouse(false) -- never steal a click from the nameplate underneath
	-- The widget is the frame the unit events land on, so there is no second
	-- frame per plate to build, hide and pool alongside it. Attach registers
	-- them against the token and Unhost gives them back.
	widget:SetScript("OnEvent", Touched)

	-- On the grid, and off whatever scale the plate it ends up parented to
	-- carries. A nameplate is scaled by three client settings at once and the
	-- product is never a whole number, so a bar that inherited it would have
	-- every edge, every icon and every glyph resampled by a fraction. This is
	-- the single call that makes the rest of the file able to say 21 and mean
	-- twenty one pixels.
	ns.UI.Adopt(widget, ns.db.barsZoom)

	-- One framed box with two chambers in it, health above and cast below, and
	-- one outline round both. There used to be a third bar above the health for
	-- threat, three pixels tall, which sat empty whenever nothing was pulling and
	-- read as a fill somebody forgot to finish. Threat is the fill, the track and
	-- a number on the line above.
	local box = CreateFrame("Frame", nil, widget)
	local bg = ns.Fill(box, "BACKGROUND", BACKDROP[1], BACKDROP[2], BACKDROP[3], BACKDROP[4])
	bg:SetAllPoints()
	-- The frame carries reaction, not threat. Threat had it at full strength on
	-- all four sides, while ns.Unit.Color's own edgeDim note says such an edge
	-- "shouted louder than anything inside it". Fifteen plates ringed in red said
	-- what the fill already said.
	local frame = Color.frame.hostile
	box.edges = ns.Outline(box, frame[1], frame[2], frame[3], 1)
	widget.box = box

	widget.health = Gauge.New(box)

	-- The level sits inside the gauge, left of the name, as a font string. It
	-- used to be a chip off the gauge's left end, on its own dark plate, closed
	-- by a five pixel reaction stripe. The reason given was that inside the gauge
	-- it covered the left end of the fill, the end a mob still has at ten
	-- percent. True of a chip, and the chip was the bug: it drew an opaque plate
	-- over the fill. A glyph does not, and the mob's name has sat in this strip
	-- since the first bar. What the chip cost was the widget's shape: marker,
	-- gap, tag, box is four left edges and a staircase for a silhouette.
	widget.levelText = Text(widget.health, PLATE_TEXT, Color.xp.none, "LEFT", ns.UI.FLAT)

	-- The second chamber of the same box, under the health gauge and inside the
	-- same frame. See the head of Cast.lua.
	Cast.Build(widget)

	widget.name = Text(widget.health, PLATE_TEXT, NAME_TEXT, "LEFT", ns.UI.FLAT)
	widget.healthText = Text(widget.health, PLATE_TEXT, HEALTH_TEXT, "RIGHT", ns.UI.FLAT)
	widget.threatText = Text(widget, PLATE_TEXT, HEALTH_TEXT, "LEFT")

	-- SetRaidTargetIconTexture picks one of eight out of a single sheet, so this
	-- takes the sampling fix without the crop that comes with a spell icon.
	widget.marker = ns.UI.Crisp(widget:CreateTexture(nil, "OVERLAY"))
	widget.marker:SetTexture(RAID_ICON_TEXTURE)
	widget.marker:Hide()

	-- What this mob is still wanted for, in gold off the box's right edge: the
	-- raid marker's mirror image. Both sit outside the box on purpose. The box
	-- is what PlateFootprint hands the nameplate driver as the click target, so
	-- a badge inside it would either take the room the mob's name is clipped
	-- into or grow the hit box by the width of a string.
	--
	-- Outlined, which is the role a string over the world takes: there is no
	-- fill behind this one and a shadow has nothing to be darker than.
	widget.questText = Text(widget, PLATE_TEXT, QUEST_TEXT, "LEFT", ns.UI.OUTLINE)
	widget.questText:Hide()

	-- Empty. The row is as long as the list and the list is a setting, so
	-- FitIcons builds it and LayoutWidget calls FitIcons.
	widget.icons = {}

	widget.targetedBy = Text(widget, PLATE_TEXT, HEALTH_TEXT, "CENTER")

	-- The outline of what actually takes the mouse, drawn only while the frames
	-- are unlocked.
	--
	-- The hit box is Blizzard's UnitFrame and the addon cannot resize it, so
	-- the honest thing is to show where it is. Without this the boundary is
	-- invisible, and a drag that turns the camera over one part of a bar and
	-- refuses over another reads as the addon being flaky rather than as two
	-- rectangles that do not line up.
	local hitbox = CreateFrame("Frame", nil, widget)
	hitbox.edges = ns.Outline(hitbox, 0.95, 0.35, 0.35, 0.9)
	hitbox:Hide()
	widget.hitbox = hitbox

	return widget
end

-- Shown while unlocked, and only when there is a hit box to draw. With
-- clickthrough on there is none: the plate has no mouse and nothing is being
-- taken, so an outline would be claiming something that is not true.
local function ShowHitbox(widget)
	widget.hitbox:SetShown(widget.hitbox.hosted and not ns.db.locked and not ns.db.barsClickThrough)
end

-- What the client needs to know to stop two bars landing on each other, and
-- what it needs to know for a click on a bar to reach the mob. Sent in
-- UIParent's units because that is what the nameplate driver counts in, and
-- only from a widget on a plate: the list spaces itself and nothing under it
-- takes a click.
--
-- The height sent is the casting one unconditionally, because the widget really
-- does grow and a driver told the idle figure would space plates so a chamber
-- opened into the bar underneath. Spacing for the taller case is right in both
-- states; for the shorter one, neither. The width is just the bar now that the
-- tag is gone.
--
-- It is the box round the bar and not the bar, and that is the half that makes
-- a bar clickable rather than merely spaced. The frame the game hit-tests is
-- the plate's, our bar takes no mouse of its own, and PlaceOnPlate hangs the
-- bar off the plate's centre by the gauge: the bar reaches `gaugeMid` above
-- that centre and the rest below, and the two are not equal, because the debuff
-- row and the threat line are above the gauge and only the cast chamber is
-- below. A plate as tall as the bar covers the bar's middle and neither end, so
-- a click lands on the mob over the health bar and on nothing over the icons.
-- Twice the longer reach is the smallest box centred where the plate is that
-- holds the whole bar, and every pixel of that targets.
--
-- It costs a little spacing, since two plates now stand as far apart as the
-- taller half needs on both sides. That is the right way to be wrong: the
-- alternative is bars that touch.
local function PlateFootprint(widget, width, unit)
	local tall = widget:GetHeight() + (widget.boxOpen - widget.boxIdle)
	local height = tall
	if ns.db.barsStyle == "replace" then
		local shift = ns.db.barsOffset * unit
		height = 2 * math.max(widget.gaugeMid + shift, tall - widget.gaugeMid - shift)
	end
	ns.Plates.SetFootprint(
		ns.UI.Convert(width, widget, UIParent),
		ns.UI.Convert(height, widget, UIParent))
end

-- The two regions that hang outside the box, one off each edge.
--
-- Off the box's left edge, which is now the widget's own: with the tag gone
-- there is one line down the left of the assembly, and the marker is outside
-- it. The quest badge is the same three units off the other side, so the two
-- things that hang outside the bar hang by the same amount.
--
-- Both are outside on purpose and it is the same reason twice. The box is what
-- PlateFootprint hands the nameplate driver as the click target, so anything
-- placed inside it either takes the room the mob's name is clipped into or
-- grows the hit box by the width of a string nobody clicks.
--
-- Its own function rather than eight lines of LayoutWidget because that one is
-- the longest in the addon and is allow-listed for it: two regions that share a
-- reason for where they sit are the cheapest eight lines it has to give up.
local function PlaceOutside(widget, font, unit, barHeight, pad)
	widget.marker:ClearAllPoints()
	widget.marker:SetSize(barHeight + pad, barHeight + pad)
	widget.marker:SetPoint("RIGHT", widget.box, "LEFT", -3 * unit, 0)

	widget.questText:SetFontObject(font)
	widget.questText:ClearAllPoints()
	widget.questText:SetPoint("LEFT", widget.box, "RIGHT", 3 * unit, 0)
	widget.shownQuest = nil -- the font moved, so the tick remeasures the string
end

-- Everything stacks upwards from the gauge, which sits on the widget's bottom
-- edge. That way one anchor point places the whole thing. The row above the
-- gauge is shared: threat on the left, debuff icons packed to the right, so
-- neither has to be centred into the other's way.
--
-- This used to be a hundred and eighty lines of SetPoint. It is a tree handed
-- to ns.UI.Flow now, and the widget's own height falls out of the measurement
-- rather than being derived by hand from four other numbers. What that bought,
-- beyond the length: the icon row wraps because the row node says wrap, not
-- because this function works out how many fit and anchors each square to the
-- gauge's corner with the row width subtracted.
--
-- The strings inside the gauge are still anchored by hand below the tree, and
-- the reason is the same for each: their size is whatever the mob happens to be
-- called or what level it is, so it is not known when the layout runs. A layout
-- that had to re-run on a name change would be a layout running on the tick.
-- See the note at the top of UI/Flow.lua.
--
-- Two conversions, and telling them apart is the whole of why `bars zoom` works
-- now and did not before.
--
-- `unit` turns a number from the constants above into the units this widget is
-- drawn in. On the grid it is 1: a design pixel is a unit, and the zoom on the
-- frame's scale is what makes that unit a 1x1, 2x2 or 3x3 block of screen
-- pixels. Off the grid, on a client with no SetIgnoreParentScale, it is the
-- fraction that keeps the bar the same physical size, which is as close as that
-- client gets.
--
-- `px` is one screen pixel, and it is for hairlines, insets and nothing else.
-- An edge is one pixel at every zoom, the same as every rule in the options
-- window. A design that grows does not want a border that grows with it.
--
-- Every size here used to go through `px`, including the ones that are sizes in
-- the design. On the grid that is a divide by the zoom, the frame's scale
-- multiplies it straight back, and the bar measured 180 by 62 screen pixels at
-- zoom 1, 2 and 3 alike. The setting had never done anything.
-- cold: places every region of one widget, on a rescale or a settings change.
local function LayoutWidget(widget, width, onPlate)
	-- Measured here rather than baked into a constant, because the same widget
	-- is laid out on a nameplate and in the list and a reparent can move the
	-- scale under it. Everything below is in these units.
	local px = ns.Pixel(widget)
	local unit = ns.UI.Unit(widget)
	local barHeight = (onPlate and PLATE_BAR_HEIGHT or LIST_BAR_HEIGHT) * unit
	local boxHeight = barHeight + px * 2 -- the gauge, plus the hairline around it
	local iconSize = ns.db.barsIconSize * unit
	local iconGap = ICON_GAP * unit
	-- Five, not four: four next to a one pixel hairline reads as three.
	local pad = 5 * unit
	local fontSize = math.floor((onPlate and PLATE_TEXT or LIST_TEXT) * unit + 0.5)
	local font = ns.UI.Font(fontSize, ns.UI.FLAT)

	-- Two strings on this widget have nothing behind them. The level, the name
	-- and the health number sit on the gauge's fill, and behind its spent end is
	-- the track at nine tenths over a backdrop at seventeen twentieths: about one
	-- and a half percent of the world reaches them, which is a known dark colour
	-- and all a shadow needs. The threat line and the targeted-by line sit in the
	-- gap above the gauge with no known colour behind them, so they keep the
	-- outline, and the floor is a hard minimum for those two, not a switch.
	--
	-- With PLATE_TEXT at the floor this is the same object as `font` at zoom 1
	-- and the bar carries one type size. The max stays because `bars zoom` can
	-- take the widget off the grid on a client with no SetIgnoreParentScale, and
	-- there the two part company again.
	local openFont = ns.UI.Font(math.max(fontSize, ns.UI.OutlineFloor()), ns.UI.OUTLINE)

	-- Both numbers on an icon are sized off the icon rather than off the bar,
	-- because the icon is a setting now: a fourteen pixel timer on a sixteen
	-- pixel square covers the art it is annotating. That arithmetic is
	-- ns.UI.Aura's, since the row under the skinned target block wants the same
	-- answer; what stays here is the ceiling, which is this widget's own type
	-- size and is what stops a large square carrying larger type than the bar
	-- it sits on.
	local timerCeiling = fontSize
	local countCeiling = math.floor(COUNT_TEXT_SIZE * unit + 0.5)

	local icons, iconHeight = IconRow(widget, iconSize, iconGap, width, px,
		timerCeiling, countCeiling)
	local count = #trackedNames

	-- The cast chamber, inside the box rather than under it. What comes back is
	-- how tall it is and nothing else: it is not in the column below, so it has
	-- no node there. See the head of Cast.lua.
	local castHeight = Cast.Fit(widget, unit, px, onPlate)

	-- The strip between the gauge and whatever is above it. The threat number
	-- shares it with the bottom row of icons, so it is an icon tall; with
	-- nothing tracked there are no icons to share it with and it is as tall as
	-- its own text, which is the whole of what an empty list costs in height.
	local lineHeight = count > 0 and iconHeight
		or math.max(fontSize, ns.UI.OutlineFloor())

	-- Only the bottom line is beside the threat number, so only the bottom line
	-- takes width away from it. Asked of Flow rather than worked out again here,
	-- so there is one rule for where a line breaks.
	local lines = Flow.Lines(icons)
	local bottomWidth = (count > 0 and lines[1]) and lines[1].main or 0

	widget:SetWidth(width)
	widget.onPlate = onPlate -- PlaceOnPlate centres on a plate and not in the list

	Flow.Arrange(widget, {
		direction = "column", width = width, align = "stretch",

		-- Wider than the bar and centred on it, so a long list of names
		-- overhangs both sides evenly rather than clipping on one.
		{ frame = widget.targetedBy, width = width + 60 * unit,
			height = TOP_TEXT * unit, align = "center" },

		{ direction = "column", gap = iconGap, align = "stretch",

			-- Two things in one strip. The icons take the full width to wrap
			-- against and the threat line takes what the bottom line of them
			-- leaves, which is why this is a stack and not a row: in a row each
			-- would reserve space from the other and the icons would wrap early.
			{ direction = "stack",
				{ frame = widget.threatText, alignX = "start", alignY = "end",
					width = math.max(24 * unit, width - bottomWidth - 8 * unit),
					height = lineHeight },
				icons,
			},

			-- The gauge is the inside of the box, less the hairline around it.
			-- It grows rather than carrying a height, so the two hairlines come
			-- off the box's own measurement and the gauge is exactly what is
			-- left however the numbers round.
			-- Measured at its idle height: the health gauge and the hairline
			-- round it. The cast chamber grows the box downward outside this
			-- tree and after it has run, which is why it is not a node. Flow
			-- measures once at layout, and a chamber that comes and goes five
			-- times a fight is a state, not a measurement.
			{ frame = widget.box, height = boxHeight, pad = px, align = "stretch",
				direction = "column",
				{ frame = widget.health, grow = 1 },
			},
		},
	})

	ns.EdgeSize(widget.box.edges, px)
	widget.threatText:SetFontObject(openFont)
	widget.targetedBy:SetFontObject(openFont)

	--------------------------------------------------------------------------
	-- Sized by their own content, so they are anchored rather than arranged
	--------------------------------------------------------------------------

	-- Given the width of "100%" and kept there. Arial Narrow is proportional and
	-- the name's right edge is pinned to this string, so without a reserved
	-- column the name re-measured and re-clipped on every percent change: the
	-- mob's name walked as it died, once per bar per tick.
	widget.healthText:SetFontObject(font)
	widget.healthText:SetText("100%")
	widget.healthText:SetWidth(ns.UI.Round(widget, widget.healthText:GetStringWidth()))
	widget.shownPercent = nil -- the width is set from a string the tick did not write
	widget.healthText:ClearAllPoints()
	widget.healthText:SetPoint("RIGHT", widget.health, "RIGHT", -pad, 0)

	-- The level, then the name, then the number, left to right along one gauge.
	-- Coloured on the XP scale, which is the five hues threat wears on the fill
	-- under it: the second argument for keeping the tag outside, and an argument
	-- about two fills competing. A 14 pixel outlined numeral over a flat fill
	-- reads as a label, the way the name beside it does.
	local showLevel = ns.db.barsLevel
	widget.levelText:SetShown(showLevel)
	widget.levelText:SetFontObject(font)
	widget.levelText:ClearAllPoints()
	widget.levelText:SetPoint("LEFT", widget.health, "LEFT", pad, 0)
	widget.levelTag = nil -- the font moved, so the tick remeasures the string

	-- Pinned between the level and the number rather than given a width, so a
	-- long name yields to both. Anchored to the gauge when there is no level:
	-- pinned to a hidden string it would be indented by whatever the last mob's
	-- level measured.
	widget.name:SetFontObject(font)
	widget.name:ClearAllPoints()
	if showLevel then
		widget.name:SetPoint("LEFT", widget.levelText, "RIGHT", pad, 0)
	else
		widget.name:SetPoint("LEFT", widget.health, "LEFT", pad, 0)
	end
	widget.name:SetPoint("RIGHT", widget.healthText, "LEFT", -pad, 0)

	-- The box's two heights: what Flow measured, and what it becomes while
	-- something casts. Both stored, so Cast's switch is one SetHeight against a
	-- number rather than this arithmetic done again on the tick.
	widget.boxIdle = boxHeight
	widget.boxOpen = castHeight > 0 and (boxHeight + px + castHeight) or boxHeight
	widget.box:SetHeight(widget.boxIdle)

	PlaceOutside(widget, font, unit, barHeight, pad)

	-- Where the gauge's middle sits below the widget's top edge, which is what
	-- PlaceOnPlate centres on the mob, and where the box's bottom edge is at
	-- rest, which is what the `above` style stands on the plate. Read off the
	-- layout rather than added up from the constants again: Flow pins everything
	-- to the widget's top left, so a change to any row above the gauge moves both
	-- of these without being told.
	local _, _, _, _, gaugeY = widget.health:GetPoint()
	widget.gaugeMid = -(gaugeY or 0) + widget.health:GetHeight() / 2
	widget.boxBottom = widget.gaugeMid + widget.health:GetHeight() / 2 + px

	if onPlate then
		PlateFootprint(widget, width, unit)
	end
end

-- Anchored by the top, with no horizontal offset left to apply. Both used to be
-- the other way round and both were the tag's doing: the widget hung by its
-- bottom edge, so anything reserved below the gauge came back out of the offset
-- or the health bar climbed off the mob, and the tag hung off the box's left, so
-- the widget was shifted right by half of it, recomputed on the tick because "9"
-- and "42r+" do not measure the same. Hanging by the top makes the chamber free:
-- it opens downward and nothing above it moves, so the gauge is over the mob
-- casting or not, which is what the reserved row bought without the air.
local function PlaceOnPlate(widget)
	local plate = widget.plate
	if not plate then
		return
	end

	-- Anchored to the frame that takes the mouse, not to the plate around it.
	--
	-- That frame is the hit box. Our bar is standing in for it, so the two
	-- should occupy the same strip of screen by construction rather than by a
	-- constant that happened to line up, and where they do not line up the
	-- result is a bar that eats a drag along part of its length and passes it
	-- along the rest, with nothing on screen saying where the boundary is.
	--
	-- Where the UnitFrame is coincident with the plate, which is the usual
	-- shape, this places identically to the old anchor. Where it is not, the
	-- bar moves onto the hit box, which is the point. barsOffset still nudges.
	local host = plate.UnitFrame or plate

	local unit = ns.UI.Unit(widget)
	-- Measured by LayoutWidget off the arranged tree. The fallback is for a
	-- widget placed before it has been laid out, which the next layout corrects.
	local mid = widget.gaugeMid or 0

	widget:ClearAllPoints()
	if ns.db.barsStyle == "replace" then
		-- Sit where the Blizzard bar was, so the bar still reads as the mob's.
		--
		-- No rounding, and that is the change worth naming. The bar height is
		-- even now and every row above it is a whole number, so the offset is
		-- whole by construction. It used to be 11.5 on the default style: every
		-- bar had its origin off a boundary and everything inside it drawn across
		-- two rows, and the fix was to round the centring away instead.
		widget:SetPoint("TOP", host, "CENTER", 0, mid + ns.db.barsOffset * unit)
	else
		-- Above the plate rather than over it, so the box's bottom edge lands on
		-- the plate's top and a chamber opens downward from there, toward the
		-- mob. That is the only direction that does not push the health bar.
		widget:SetPoint("TOP", host, "TOP", 0,
			(widget.boxBottom or widget:GetHeight()) + ns.db.barsOffset * unit)
	end
end

-- Every write in here is guarded against the value already on the widget.
--
-- The version this replaced guarded the cheap comparisons, the colour tables
-- and the level string, and left the expensive writes open: the name, the
-- health number, the targeted-by line, the track colour, the raid marker and
-- sixteen calls across the four debuff holders. That is about thirty widget
-- writes per mob per tick, and at fifteen plates and five ticks a second it is
-- roughly two thousand font string and texture updates every second, nearly
-- all of them writing the value that was already there.
--
-- A guard costs one comparison. A SetText costs a string measure and a
-- relayout whether or not the text changed. That ratio is why the rule here is
-- that nothing writes without asking first.
--
-- The caches live on the widget rather than in a module table because widgets
-- are pooled and their drawn state survives pooling, so the cache stays true
-- across a release and a reattach. LayoutWidget clears the ones it invalidates.
-- The raid target icon, which is the one region on the widget that swaps a
-- texture rather than writing a colour or a string. Guarded on the index, and
-- nil covers both halves of off: the marking switch is down, or nobody has
-- marked this one.
local function PaintMarker(widget, unit)
	local raidIcon = ns.db.barsMarker and GetRaidTargetIndex(unit) or nil
	if widget.shownMarker == raidIcon then
		return
	end
	widget.shownMarker = raidIcon
	if raidIcon then
		SetRaidTargetIconTexture(widget.marker, raidIcon)
		widget.marker:Show()
	else
		widget.marker:Hide()
	end
end

-- What this mob is still wanted for, in the four characters a bar has room for.
--
-- The string itself is Quests/Drops.lua's, because working it out means reading
-- Questie's registry and this file has no business knowing that Questie exists.
-- What arrives here is `3/8`, `!`, or nothing.
--
-- Guarded on the string, which covers all three of the ways it moves: a plate
-- pooled onto a different mob, the seventh of eight dying, and the switch going
-- off. Nil is both halves of off, the way the raid marker's nil is: the setting
-- is down, or no quest of yours wants this one.
local function PaintQuest(widget, guid)
	-- The npc id behind the GUID, parsed only when the widget changes mobs. The
	-- parse is a string match and a tonumber, which is nothing on its own and is
	-- fifteen of them per reading on a pull; the badge under it is one
	-- table index once the creature has been asked about.
	if widget.questGuid ~= guid then
		widget.questGuid = guid
		widget.questNpc = ns.CreatureId(guid)
	end
	local badge = ns.db.barsQuest and ns.QuestDrops.Badge(widget.questNpc) or nil
	if widget.shownQuest == badge then
		return
	end
	widget.shownQuest = badge
	if badge then
		widget.questText:SetText(badge)
		widget.questText:Show()
	else
		widget.questText:Hide()
	end
end

-- The one place a widget's alpha is written, because two things decide it and
-- neither knows about the other.
--
-- `baseAlpha` is which bar is yours, written by the tick and by the target
-- change that moved it.
-- `fade` is how far through arriving or leaving this bar is, written by the
-- ramp on every frame. They multiply: a bar that is not your target and is
-- halfway in is 0.55 of half, and both facts are still on screen.
--
-- The guard is on the product and not on either half, which is what makes this
-- safe to call from both of them. A tick that recomputes the same base while a
-- ramp is stopped writes nothing.
local function PaintAlpha(widget)
	local alpha = (widget.baseAlpha or TARGET_ALPHA) * (widget.fade or 1)
	if widget.shownAlpha ~= alpha then
		widget.shownAlpha = alpha
		widget:SetAlpha(alpha)
	end
end

-- What the kill is worth, said on the two places that can carry it: the level
-- tag and the name.
--
-- Guarded on the string and on the colour table's identity, the way the frame
-- is: this runs on every reading and on every event about the mob, and a level
-- changes when the mob does. Two things it used to do and no longer has to: measure its own string
-- to resize a frame, and call PlaceOnPlate, because a tag that changed width
-- moved the assembly's centre. The name yields through one anchor now.
--
-- The level is asked for outside the barsLevel branch and written inside it,
-- for the reason the edge is asked for outside: the colour is also what the
-- name is about to be told, and turning the level number off must not turn off
-- "this one pays you nothing".
--
-- The name carries three states and grey beats the other two. Grey means the
-- kill pays nothing, because the mob is too far below you or because somebody
-- else tagged it, and the name is the loudest text on the bar because that is a
-- decision you make at pull range and a level tag is two characters wide. It
-- wins over the warm colour your target wears rather than yielding to it: which
-- mob is yours is already said by the alpha, and a mob you picked up by mistake
-- is exactly the one that has to tell you it is worth nothing.
local function PaintWorth(widget, unit, guid, isTarget)
	-- The tag and the level under it, read when the widget changes mobs and not
	-- on the tick, the way PaintQuest reads the creature id. A mob keeps the
	-- level and the classification it spawned at, so UnitLevel twice and
	-- UnitClassification once per bar per tick were four answers to a question
	-- that had already been answered.
	--
	-- The tap is not in there and must not be. Somebody else tagging the mob is
	-- the half of "is this kill worth anything" that moves between two frames,
	-- so ns.TapDenied is asked live inside Level.WorthAt.
	if widget.worthGuid ~= guid then
		widget.worthGuid = guid
		widget.worthTag, widget.worthLevel = Level.Tagged(unit)
	end

	local tag = widget.worthTag
	local xp = Level.WorthAt(unit, widget.worthLevel or 0)
	if ns.db.barsLevel then
		if widget.levelTag ~= tag then
			widget.levelTag = tag
			widget.levelText:SetText(tag)
		end
		if widget.levelColor ~= xp then
			widget.levelColor = xp
			widget.levelText:SetTextColor(xp[1], xp[2], xp[3])
		end
	end

	local text = xp == WORTHLESS and WORTHLESS
		or (isTarget and TARGET_TEXT or NAME_TEXT)
	if widget.nameColor ~= text then
		widget.nameColor = text
		widget.name:SetTextColor(text[1], text[2], text[3])
	end
end

-- The gauge, the track behind it and the threat number take the one colour, so
-- a single identity guard covers the three of them. These are the five module
-- constants, so identity is the right comparison.
--
-- The edge is not one of them any more; see the note in CreateWidget. What pays
-- for losing it is the track: the spent part keeps three tenths of the hue
-- rather than a fifth, so a mob at ten percent reads as yours across the bar's
-- width instead of round its rim. That fraction is UI/Gauge.lua's.
--
-- The line above the gauge is guarded on the three values it is made of rather
-- than on itself. See ThreatState: building the string first and comparing it
-- afterwards was one throwaway string per engaged bar per pass to find out that
-- nothing had moved.
local function PaintThreat(widget, unit)
	local color, percent, who, mode = ThreatState(unit)
	if widget.threatColor ~= color then
		widget.threatColor = color
		Gauge.Paint(widget.health, widget.health.track, color)
		widget.threatText:SetTextColor(color[1], color[2], color[3])
	end
	if widget.threatPercent ~= percent or widget.threatWho ~= who
		or widget.threatMode ~= mode then
		widget.threatPercent, widget.threatWho, widget.threatMode = percent, who, mode
		widget.threatText:SetText(ThreatLabel(percent, who, mode))
	end
end

local function UpdateWidget(widget, unit, guid)
	local now = GetTime()
	-- Kept so the event drain can redraw this widget without asking the client
	-- for a GUID it was handed a moment ago.
	widget.guid = guid

	local health, healthMax = UnitHealth(unit), UnitHealthMax(unit)
	local scale = healthMax > 0 and healthMax or 1
	if widget.shownMax ~= scale then
		widget.shownMax = scale
		widget.health:SetMinMaxValues(0, scale)
	end
	if widget.shownHealth ~= health then
		widget.shownHealth = health
		widget.health:SetValue(health)
	end

	PaintThreat(widget, unit)

	-- The frame, which is reaction and nothing else: hostile draws chrome and
	-- disappears, neutral draws amber and does not. Read here rather than under
	-- the barsLevel switch, deliberately, because turning the mob level off
	-- turns off what a kill is worth and must not turn off "do not cleave this
	-- one".
	local edge = Color.Frame(unit)
	if widget.edgeColor ~= edge then
		widget.edgeColor = edge
		ns.Recolor(widget.box.edges, edge)
	end

	local name = UnitName(unit) or ""
	if widget.shownName ~= name then
		widget.shownName = name
		widget.name:SetText(name)
	end

	-- Compared as the integer that gets drawn, not as the ratio behind it. A
	-- mob losing one point of health out of four thousand does not redraw a
	-- number that still says 99%.
	local percent = healthMax > 0 and math.floor(health / healthMax * 100) or -1
	if widget.shownPercent ~= percent then
		widget.shownPercent = percent
		widget.healthText:SetText(percent >= 0 and (percent .. "%") or "")
	end

	PaintMarker(widget, unit)
	PaintQuest(widget, guid)

	-- Your current target, said twice: brighter than everything else on the
	-- screen, and warm rather than white on the name. The alpha is what you see
	-- from across a pull and the name colour is what confirms it once you are
	-- looking. Both guarded for the same reason as the edge.
	--
	-- The alpha guard compares the number and not isTarget, because it moves on
	-- two things: which mob is yours, and whether you have one at all. Guarding
	-- on isTarget alone would leave every bar dim after you dropped target.
	--
	-- The name is PaintWorth's, because what it says is mostly about the kill
	-- and only partly about the target.
	local isTarget = UnitIsUnit(unit, "target")
	PaintWorth(widget, unit, guid, isTarget)

	local alpha = (isTarget or not haveTarget) and TARGET_ALPHA or OTHER_ALPHA
	if widget.baseAlpha ~= alpha then
		widget.baseAlpha = alpha
		PaintAlpha(widget)
	end

	local by = targeters[guid] or ""
	if widget.shownTargeters ~= by then
		widget.shownTargeters = by
		widget.targetedBy:SetText(by)
	end

	DrawDebuffs(widget, unit, now)

	-- What the client says this mob is casting. Last, because it is the one
	-- thing on the widget that is not read out of the unit's own state, and
	-- because the cast events call it again on their own for the unit they
	-- name. Everything it does is guarded in there.
	Cast.Update(widget, unit)
end

--------------------------------------------------------------------------
-- Blizzard nameplate visuals
--
-- The UnitFrame stays shown, because that is the frame the game hit-tests for
-- clicks. Killing it would kill ctrl-click marking and targeting. Only its
-- visible pieces get switched off.
--
-- This used to say the cast bar was deliberately left alone so interrupts
-- stayed visible, and it was right for as long as nothing here drew one. The
-- bars draw their own now, so leaving Blizzard's up is two cast bars for one
-- cast, in two places, disagreeing about where the mob is. It goes with the
-- rest, and only while `bars cast` is on: switch ours off and Blizzard's is
-- what says when to Pummel again.
--------------------------------------------------------------------------

-- ns.Strip and ns.Unstrip in Core do the work for the art, because the artwork
-- part strips Blizzard bar art through the same two calls. The cast bar is the
-- exception and goes through Core/Attic.lua instead: see PlateCage below.

-- `every` is what Restore passes and Strip does not.
--
-- Two of these regions are hidden only while a setting says so, and the list
-- has to be longer on the way back than it was on the way in. Built from the
-- settings in both directions, a plate stripped while `bars marker` was on and
-- restored after it was switched off would keep Blizzard's raid icon hidden for
-- the rest of the session: the walk that was supposed to give it back no longer
-- had it on the list. Nothing said anything and the only symptom was a marker
-- that had gone for good. Restore gives back everything this file has ever
-- taken; ns.Unstrip is a no-op on a region that was never taken, so asking for
-- all of them costs a table lookup.
local function PlateRegions(plate, every)
	local unitFrame = plate.UnitFrame
	if not unitFrame then
		return nil
	end
	local regions = {
		unitFrame.healthBar or unitFrame.HealthBarsContainer,
		unitFrame.name,
		unitFrame.LevelFrame,
		unitFrame.ClassificationFrame,
		unitFrame.selectionHighlight,
		unitFrame.aggroHighlight,
	}
	if every or ns.db.barsMarker then
		regions[#regions + 1] = unitFrame.RaidTargetFrame or unitFrame.raidIcon or unitFrame.RaidTargetIcon
	end
	return regions
end

-- The one region on a plate that goes in the attic rather than under ns.Strip.
--
-- Blizzard's plate cast bar is the same CastingBarFrame mixin the target's bar
-- is, and that mixin shows itself with SetShown. SetShown is resolved in C and
-- never reads the Lua Show that ns.Strip put a Hide in, so the bar came back on
-- the first cast of the session and stayed back for the rest of it: two cast
-- bars for one cast, ours on the plate and Blizzard's under it. That is the
-- same bug UnitFrames/Blizzard.lua's header describes for the target's bar, on
-- the same mixin, found the same way.
--
-- Core/Attic.lua was the answer there and it is the answer here. A frame whose
-- parent is hidden is not drawn whatever the mixin calls on the frame itself,
-- and Attic.Sweep re-checks every caged frame once a second.
--
-- Only the cast bar. Everything in PlateRegions above is the plate's own art
-- and its health bar; nothing re-shows those, and the client anchors to them,
-- so caging them would take them out of the plate's chain to fix a bug they do
-- not have.
--
-- Read off the client's own XML rather than guessed. Both clients this addon
-- runs on, 2.5.6 and 1.15.9, declare the plate's cast bar as
-- `CastBarsContainer.castBar`: a container frame the health bar's container is
-- anchored under, with the bar inside it. That is the same shape PlateRegions
-- already reads the health bar through. The bare `castBar` this used to read
-- was a key neither client carries, so the lookup answered nil, nothing went
-- in the attic, and Blizzard's bar came up under the plate on the first cast
-- of every fight with `bars cast` on and the switch saying it was hidden. The
-- bare key stays as the second answer for a build that predates the container.
--
-- Only the bar, not the container. The client anchors the health bar to the
-- container, so caging it would move that anchor out of the plate's chain to
-- fix a bug the container does not have.
--
-- `every` is what Restore passes, for the reason PlateRegions takes one: a bar
-- caged while `bars cast` was on has to be handed back after the setting goes
-- off, and a list built from the setting would no longer have it to hand.
local function PlateCage(plate, every)
	local unitFrame = plate.UnitFrame
	if not unitFrame or not (every or ns.db.barsCast) then
		return nil
	end
	local container = unitFrame.CastBarsContainer
	if type(container) == "table" and container.castBar then
		return container.castBar
	end
	return unitFrame.castBar
end

-- A plate is a hole in the camera, and the hole is not ours. Our widget calls
-- EnableMouse(false) on itself and none of its children ever take the mouse,
-- so what swallows a button over a bar is the UnitFrame underneath: a mouse
-- enabled secure button, which is exactly how a click on a plate targets and
-- where ctrl-click marking gets its unit.
--
-- A mouse enabled frame takes every button that lands on it, so the only lever
-- here used to be the whole plate or none of it, and the camera drag was the
-- price of click targeting. SetPassThroughButtons is the lever the client
-- actually offers: the frame keeps the mouse, and the buttons named in the
-- call fall through to whatever is underneath, which for a nameplate is the
-- world and the camera.
--
-- Details calls it unguarded in `functions/slash.lua`, which its 20506 TOC
-- loads, for exactly this, its own click-through options. That is what proves
-- it is here. Questie replaces it with a no-op on its world map pin with the
-- comment "hack to avoid in-combat error", which is what proves it is
-- protected, so it goes through the same pending queue as everything else
-- combat refuses.
--
-- Left cannot be the one handed back. The click that targets a plate is a left
-- click on the frame, and a button that passes through never reaches the frame
-- at all, so handing left back is click-through by another name. Right is the
-- one worth giving away: it costs Blizzard's right-click-to-interact and
-- ctrl-right-click cross marking on a plate, and it buys the camera.
local CAMERA_BUTTONS = {
	right = { "RightButton" },
	left = { "LeftButton" },
	both = { "LeftButton", "RightButton" },
}

-- nil until the call has been tried, false on a client without the method,
-- true once one has gone through. Reported by Describe, never inferred.
local passThrough

-- Buttons is one of the CAMERA_BUTTONS tables or nil for "hand nothing back".
-- unpack is avoided because there are at most two and a spread would need a
-- guard of its own on a client that renamed it.
local function PlatePassThrough(unitFrame, buttons)
	if type(unitFrame.SetPassThroughButtons) ~= "function" then
		passThrough = false
		return true -- nothing to apply and nothing to undo
	end
	if ns.Blocked(unitFrame) then
		return false
	end
	local ok
	if not buttons then
		ok = pcall(unitFrame.SetPassThroughButtons, unitFrame)
	elseif buttons[2] then
		ok = pcall(unitFrame.SetPassThroughButtons, unitFrame, buttons[1], buttons[2])
	else
		ok = pcall(unitFrame.SetPassThroughButtons, unitFrame, buttons[1])
	end
	if ok then
		passThrough = true
	end
	return ok
end

-- Whether the pass-through path is doing anything on this client, for the
-- status line. "off" is a setting, "unavailable" is a client.
function EnemyBars.CameraState()
	if ns.db.barsClickThrough then
		return "moot" -- the plate has no mouse at all, so every button is through
	end
	if not CAMERA_BUTTONS[ns.db.barsCamera] then
		return "off"
	end
	if passThrough == false then
		return "unavailable"
	end
	if passThrough == nil then
		return "unproven"
	end
	return ns.db.barsCamera
end

-- Both halves are idempotent and neither touches a plate that is already where
-- it should be. EnableMouse on a secure frame taints it, and a taint on the
-- button that targets is worth carrying only when a setting has asked for it.
--
-- The pass-through state is tracked separately from the mouse state, because a
-- plate arrives mouse enabled and therefore never needs the EnableMouse call,
-- and the old single guard would have skipped the pass-through with it.
local function PlateMouse(plate, enabled, buttons)
	local unitFrame = plate.UnitFrame
	if not unitFrame or not unitFrame.EnableMouse then
		return true
	end
	local complete = true

	if (not unitFrame.wkMouseOff) ~= enabled then
		if ns.Blocked(unitFrame) then
			complete = false
		else
			unitFrame:EnableMouse(enabled)
			unitFrame.wkMouseOff = (not enabled) or nil
		end
	end

	-- Only meaningful while the plate still has the mouse. A plate with no
	-- mouse passes every button already.
	local wanted = enabled and buttons or nil
	if unitFrame.wkPassThrough ~= wanted then
		if PlatePassThrough(unitFrame, wanted) then
			unitFrame.wkPassThrough = wanted
		else
			complete = false
		end
	end

	return complete
end

local function StripPlate(plate)
	local complete = PlateMouse(plate, not ns.db.barsClickThrough, CAMERA_BUTTONS[ns.db.barsCamera])
	local replacing = ns.db.barsStyle == "replace"
	local regions = replacing and PlateRegions(plate) or nil
	for _, region in ipairs(regions or {}) do
		if not ns.Strip(region) then
			complete = false
		end
	end
	local cage = replacing and PlateCage(plate) or nil
	if cage and not ns.Attic.Vanish(cage) then
		complete = false
	end
	stripped[plate] = true
	if not complete then
		pending[plate] = "strip" -- finish once combat drops
	else
		pending[plate] = nil
	end
end

-- Unconditional, because the setting that put a plate in this state may have
-- changed since. Both halves no-op on a plate that was never touched.
local function RestorePlate(plate)
	local complete = PlateMouse(plate, true, nil)
	for _, region in ipairs(PlateRegions(plate, true) or {}) do
		if not ns.Unstrip(region) then
			complete = false
		end
	end
	local cage = PlateCage(plate, true)
	if cage and not ns.Attic.Return(cage) then
		complete = false
	end
	if complete then
		stripped[plate] = nil
		pending[plate] = nil
	else
		pending[plate] = "restore"
	end
end

local function FlushPending()
	for plate, action in pairs(pending) do
		if action == "strip" then
			StripPlate(plate)
		else
			RestorePlate(plate)
		end
	end
end

--------------------------------------------------------------------------
-- Modes
--------------------------------------------------------------------------

local function NameplatesEnabled()
	if not C_NamePlate then
		return false
	end
	if GetCVarBool then
		return GetCVarBool("nameplateShowEnemies") and true or false
	end
	return true
end

-- "auto" follows the nameplate cvar: plates when they are on, the stacked
-- panel when they are off.
function EnemyBars.Mode()
	local mode = ns.db.barsMode
	if mode == "auto" then
		return NameplatesEnabled() and "plates" or "list"
	end
	return mode
end

-- A coordinate snapped to the frame's own pixel.
--
-- ns.UI.Round is the same arithmetic for a size, and it floors at one pixel,
-- which is right for a width and wrong for a position: nought is a real place
-- to stand and so is anywhere left of it.
local function Snap(frame, value)
	local px = ns.Pixel(frame)
	return math.floor(value / px + 0.5) * px
end

-- Everything that ends a widget's life on a plate, taken out of Release because
-- a fading bar does half of it now and the other half when the ramp lands.
local function Unhost(widget)
	widget.plate = nil
	-- The events go back with the plate. A pooled widget still registered
	-- against a token the client has handed to another mob is a widget marked
	-- dirty by somebody else's aura.
	widget.unit = nil
	dirty[widget] = nil
	for index = 1, #WATCHED do
		widget:UnregisterEvent(WATCHED[index])
	end
	-- Cleared before the reparent, so no anchor survives pointing at a plate
	-- this widget is about to stop being a child of.
	widget.hitbox:Hide()
	widget.hitbox:ClearAllPoints()
	widget.hitbox.hosted = nil
	widget:ClearAllPoints()
	widget:SetParent(UIParent)
end

-- Back in the pool, drawn state and all.
--
-- A pooled widget keeps everything the tick drew on it, which is what the
-- caches on it are for. A half finished cast is the one piece of that which is
-- about the mob rather than about the widget, so it does not travel.
local function Retire(widget)
	Cast.Clear(widget)
	widget:Hide()
	fading[widget] = nil
	widget.fade, widget.fadeGoal, widget.fadeHome = 1, 1, nil
	pool[#pool + 1] = widget
end

-- Put a widget on the ramp and answer whether it is really on one.
--
-- `from` is where the ramp starts and nil means carry on from wherever the bar
-- already is, which is what a mob dying halfway through arriving wants: it
-- turns round from there rather than snapping to full first.
--
-- The switch is read here and nowhere else. With `bars fade` off this sets the
-- alpha and answers false, so every caller has one branch instead of two and a
-- bar appears and disappears the way it always did.
local function StartFade(widget, from, goal)
	if from then
		widget.fade = from
	end
	widget.fadeGoal = goal
	if ns.db.barsFade then
		fading[widget] = true
		Wake()
	else
		widget.fade = goal
		fading[widget] = nil
	end
	PaintAlpha(widget)
	return fading[widget] == true
end

-- The ramp itself, run once per frame off the bars' own ticker.
--
-- Per frame and not on the second the readouts take, for the reason
-- the cast fill is: this is a moving edge, and a moving edge drawn five times a
-- second is drawn in steps. The note at the head of EnemyBars.Sweep is the long
-- version.
--
-- Nothing here allocates and nothing writes unless a bar actually moved, which
-- is what makes it free to leave running: with no bar arriving or leaving the
-- set is empty and the whole function is one `next`.
local function Fades(delta)
	if not next(fading) then
		return
	end
	for widget in pairs(fading) do
		local goal = widget.fadeGoal or 1
		local value = widget.fade or 1
		if value < goal then
			value = math.min(goal, value + delta / FADE_IN)
		elseif value > goal then
			value = math.max(goal, value - delta / FADE_OUT)
		end
		widget.fade = value
		PaintAlpha(widget)
		if value == goal then
			fading[widget] = nil
			if widget.fadeHome then
				Retire(widget)
			elseif goal == 0 then
				-- A list row, which is not pooled and keeps its slot. The cast
				-- is cleared here rather than when the row dropped off, so the
				-- chamber does not close under a bar that is still on screen.
				Cast.Clear(widget)
				widget:Hide()
			end
		end
	end
end

-- The widgets the events marked, drawn.
--
-- On the per-frame pass rather than on the verify below, so a mob that loses
-- health or gains a debuff is redrawn on the next frame. What it costs when
-- nothing has happened is the `next` on the first line.
--
-- The unit is checked again because a plate can be released between the frame
-- an event marked its widget and the frame this reaches it.
local function Flush()
	if not next(dirty) then
		return
	end
	for widget in pairs(dirty) do
		dirty[widget] = nil
		local unit = widget.unit
		if unit and attached[unit] == widget then
			UpdateWidget(widget, unit, widget.guid)
		end
	end
end

local function Attach(unit)
	if not ns.db.bars or EnemyBars.Mode() ~= "plates" then
		return
	end
	if attached[unit] or not Wanted(unit) then
		return
	end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then
		return
	end

	-- Before StripPlate and before the driver has been told anything, because
	-- this is the one moment a plate is still the size the client shipped and
	-- the spacing arithmetic needs that figure.
	ns.Plates.Measure(plate)

	StripPlate(plate)

	local widget = table.remove(pool) or CreateWidget()
	ns.UI.Rezoom(widget, ns.db.barsZoom)
	widget:SetParent(plate)
	widget:SetFrameStrata(plate:GetFrameStrata())
	widget:SetFrameLevel(math.min(plate:GetFrameLevel() + 5, 100))
	if widget.SetIgnoreParentAlpha then
		widget:SetIgnoreParentAlpha(true)
	end

	-- `bars width` pixels, the same figure the list uses, and the same number of
	-- screen pixels on every monitor because the widget is on the grid.
	--
	-- It used to be the width of the plate under it, and that was a loop with no
	-- fixed point: LayoutWidget hands the driver a footprint, the driver sizes
	-- every plate to it, and the next bar measured off a plate came back changed.
	-- Which way it ran depended on the scale the client puts on a nameplate
	-- against the scale it puts on UIParent. Wider every round on one, narrower
	-- on another, and a setting change ran it again. There was never a width the
	-- bars settled on, and no setting that chose one.
	--
	-- LayoutWidget is around sixty anchor, font and size calls, and this runs
	-- for every nameplate the game puts up, which in a busy zone is several a
	-- second. The epoch is what keeps it off that path: anything that changes
	-- the shape bumps it, so a widget coming back out of the pool is laid out
	-- again only when the shape it already has is out of date.
	local width = ns.db.barsWidth * ns.UI.Unit(widget)
	if widget.laidWidth ~= width or widget.laidEpoch ~= layoutEpoch then
		widget.laidWidth, widget.laidEpoch = width, layoutEpoch
		LayoutWidget(widget, width, true)
	end

	widget.plate = plate
	PlaceOnPlate(widget)

	widget.hitbox:ClearAllPoints()
	widget.hitbox.hosted = plate.UnitFrame ~= nil
	if widget.hitbox.hosted then
		widget.hitbox:SetAllPoints(plate.UnitFrame)
	end
	ShowHitbox(widget)

	StartFade(widget, 0, 1)
	widget:Show()
	attached[unit] = widget

	-- The token this widget answers for, and the four events that say something
	-- about it. Both go on together: Touched compares the token, so a widget
	-- carrying events and no token would ignore every one of them.
	widget.unit = unit
	widget.guid = UnitGUID(unit)
	for index = 1, #WATCHED do
		ns.RegisterUnitEvent(widget, WATCHED[index], unit)
	end

	-- Marked rather than drawn here. A widget out of the pool still carries the
	-- last mob's name and health, and the next frame is a great deal sooner than
	-- the next verify.
	dirty[widget] = true
	Wake()
end

-- `now` means take it off the screen this frame, which is what a settings
-- change and a mode switch want: a ghost of the old shape fading out over a
-- rebuild is a bar drawn to a design that no longer exists.
-- cold: takes a widget off a plate, on the tick that plate goes.
local function Release(unit, now)
	local widget = attached[unit]
	if not widget then
		return
	end
	attached[unit] = nil

	-- Where the bar stood, in UIParent's units, taken before the reparent
	-- moves it. A fading bar is held on the screen rather than on the plate,
	-- because the plate is gone: the client hides it the moment the mob is out
	-- of range or dead, and a child of a hidden frame does not draw whatever
	-- its own alpha says.
	local left, bottom
	if not now then
		left = ns.UI.Convert(widget:GetLeft(), widget, UIParent)
		bottom = ns.UI.Convert(widget:GetBottom(), widget, UIParent)
	end

	Unhost(widget)

	if now or not left or not bottom or not StartFade(widget, nil, 0) then
		Retire(widget)
		return
	end
	widget.fadeHome = true -- the ramp pools it when it lands
	-- Snapped, because the position came off a plate and a plate's origin is
	-- wherever the mob was standing, which is a fraction of a pixel. Everything
	-- else on the grid is anchored in whole ones and a bar spending a fifth of a
	-- second drawn across two rows on the way out is the one thing the eye is
	-- actually looking at.
	widget:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
		Snap(widget, ns.UI.Convert(left, UIParent, widget)),
		Snap(widget, ns.UI.Convert(bottom, UIParent, widget)))
end

local function ReleaseAll()
	for unit in pairs(attached) do
		Release(unit, true)
	end
	-- The ghosts of mobs that left a moment ago go with them. A rebuild is a
	-- shape change, and a bar still fading out is drawn to the shape being
	-- left behind.
	for widget in pairs(fading) do
		if widget.fadeHome then
			Retire(widget)
		end
	end
	for plate in pairs(stripped) do
		RestorePlate(plate)
	end
end

-- Walks GetNamePlates, which allocates, so it runs on a rebuild and never on a
-- tick. Everything after this point reads plateUnits, which the add and remove
-- events keep current for free.
local function SyncPlates()
	wipe(plateUnits)
	if not C_NamePlate then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then
			plateUnits[unit] = true
			ns.Plates.Measure(plate)
		end
	end
end

local function AttachAll()
	for unit in pairs(plateUnits) do
		Attach(unit)
	end
end

-- Every tick in list mode used to build a table for the list, a table for the
-- seen set, a table for each mob in it, a closure to add one and a closure to
-- sort them, and hand all of it to the collector a fifth of a second later. At
-- five ticks a second and eight mobs that is around seventy tables and ten
-- closures a second, allocated and dropped, for a list whose contents rarely
-- change. Nothing here allocates now: the entries are reused in place, the two
-- helpers are file scope rather than closures, and the plate list is the one
-- this module already keeps from the add and remove events rather than a fresh
-- table from GetNamePlates.
local collected, collectSeen = {}, {}
local collectCount = 0

local function ByFirstSeen(a, b)
	return a.order < b.order
end

local function Collect(unit)
	if not UnitExists(unit) or UnitIsDead(unit) or not Wanted(unit) then
		return
	end
	local guid = UnitGUID(unit)
	if not guid or collectSeen[guid] then
		return
	end
	collectSeen[guid] = true
	if not firstSeen[guid] then
		seenCounter = seenCounter + 1
		firstSeen[guid] = seenCounter
	end

	collectCount = collectCount + 1
	local entry = collected[collectCount]
	if not entry then
		entry = {}
		collected[collectCount] = entry
	end
	entry.unit, entry.guid, entry.order = unit, guid, firstSeen[guid]
end

-- Returns how many of `collected` are live, not a list. A caller that kept the
-- table past the next tick would be reading the tick after it.
local function CollectUnits()
	wipe(collectSeen)
	collectCount = 0

	Collect("target")
	Collect("focus")
	for unit in pairs(plateUnits) do
		Collect(unit)
	end

	-- Sorting the live prefix of a table that is longer than the prefix would
	-- sort the stale entries in with it, so the tail is trimmed first. table.sort
	-- has no length argument.
	for index = #collected, collectCount + 1, -1 do
		collected[index] = nil
	end
	table.sort(collected, ByFirstSeen)

	if collectCount == 0 and seenCounter > 500 then
		wipe(firstSeen)
		seenCounter = 0
	end
	return collectCount
end

local function UpdateList()
	local shown = math.min(CollectUnits(), ns.db.barsMax)
	local width = ns.db.barsWidth * ns.UI.Unit(anchor)

	for index = 1, shown do
		local widget = listWidgets[index]
		if not widget then
			widget = CreateWidget()
			listWidgets[index] = widget
			widget:SetParent(anchor)
			LayoutWidget(widget, width, false)
			widget:ClearAllPoints()
			if index == 1 then
				widget:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
			else
				widget:SetPoint("BOTTOMLEFT", listWidgets[index - 1], "TOPLEFT", 0, 4)
			end
		end
		UpdateWidget(widget, collected[index].unit, collected[index].guid)
		-- A row arrives on the ramp and a row on its way out turns round on it,
		-- which is the mob that died and was replaced in the same slot before
		-- the tail ran out. Neither branch is reached by a row that is already
		-- up, which is nearly every row on nearly every tick.
		if not widget:IsShown() then
			StartFade(widget, 0, 1)
			widget:Show()
		elseif widget.fadeGoal == 0 then
			StartFade(widget, nil, 1)
		end
	end
	for index = shown + 1, #listWidgets do
		local widget = listWidgets[index]
		if widget:IsShown() and widget.fadeGoal ~= 0 then
			if not StartFade(widget, nil, 0) then
				Cast.Clear(widget)
				widget:Hide()
			end
		end
	end
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

-- How many bars are actually drawn right now, in whichever mode is running.
-- Read by the performance tab, which cannot say whether 0.31 ms is cheap
-- without it.
function EnemyBars.Count()
	if EnemyBars.Mode() ~= "plates" then
		local shown = 0
		for _, widget in ipairs(listWidgets) do
			if widget:IsShown() then
				shown = shown + 1
			end
		end
		return shown
	end
	local count = 0
	for _ in pairs(attached) do
		count = count + 1
	end
	return count
end

-- The charge marker anchors above our bar when there is one on the plate.
function EnemyBars.WidgetFor(unit)
	return attached[unit]
end

-- One line for /wk status, covering the two things about the bars that are the
-- client's answer rather than a setting: what the grid resolved to, and whether
-- the driver agreed to space plates the way the bars need.
function EnemyBars.Describe()
	return ns.UI.Describe() .. "; " .. ns.Plates.Describe()
end

function EnemyBars.ApplyLayout()
	if not anchor then
		return
	end
	layoutEpoch = layoutEpoch + 1
	local point = ns.db.barsPoint
	anchor:ClearAllPoints()
	anchor:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	ns.UI.Rezoom(anchor, ns.db.barsZoom)
	-- Rezoomed first, because the unit a design pixel occupies is read off the
	-- frame and the zoom is what decides it. Sizing before the rezoom lays the
	-- list out for the zoom it is leaving.
	local unit = ns.UI.Unit(anchor)
	anchor:SetSize(ns.db.barsWidth * unit, 20 * unit)
	for _, widget in ipairs(listWidgets) do
		ns.UI.Rezoom(widget, ns.db.barsZoom)
		LayoutWidget(widget, ns.db.barsWidth * ns.UI.Unit(widget), false)
	end
	-- The bars already sitting on plates take the same width, and nothing else
	-- would reach them: a widget on a plate is laid out when it attaches, and
	-- these are attached. Sized off their own pixel rather than the anchor's,
	-- because a plate widget can be on a zoom of its own until Rebuild runs.
	for _, widget in pairs(attached) do
		ns.UI.Rezoom(widget, ns.db.barsZoom)
		widget.laidWidth = ns.db.barsWidth * ns.UI.Unit(widget)
		widget.laidEpoch = layoutEpoch
		LayoutWidget(widget, widget.laidWidth, true)
		PlaceOnPlate(widget)
	end
end

function EnemyBars.ApplyLock()
	if not anchor then
		return
	end
	local unlocked = not ns.db.locked
	place:Lock(unlocked)
	anchor:EnableMouse(unlocked)
	header:SetShown(unlocked and EnemyBars.Mode() == "list")
	for _, widget in pairs(attached) do
		ShowHitbox(widget)
	end
end

-- Called whenever a setting changes the shape of things.
function EnemyBars.Rebuild()
	if not anchor then
		return
	end
	layoutEpoch = layoutEpoch + 1
	ReleaseAll()
	SyncPlates()
	for _, widget in ipairs(listWidgets) do
		ns.UI.Rezoom(widget, ns.db.barsZoom)
		-- Off the ramp as well as off the screen. A rebuild is a shape change,
		-- and a bar left halfway through arriving would finish arriving into a
		-- layout that no longer exists.
		fading[widget] = nil
		widget.fade, widget.fadeGoal = 1, 1
		-- And off the sweep's set. A row hidden with its chamber still open
		-- would be swept every frame for the length of a cast nobody can see.
		Cast.Clear(widget)
		widget:Hide()
	end
	if ns.db.bars and EnemyBars.Mode() == "plates" then
		AttachAll()
	end
	-- Only while there is a row for them to reach, and only on a client that
	-- answers for a unit that is not you. See CAST_EVENTS.
	CastEvents(ns.db.bars and ns.db.barsCast and ns.HasCastInfo()
		and EnemyBars.Mode() == "plates")
	ns.Plates.Apply()
	EnemyBars.ApplyLock()
end

-- The cast fills, and nothing else, on every frame.
--
-- Split off EnemyBars.Update rather than folded into it, because the two are
-- different kinds of thing running at different rates. Everything Update draws
-- is a readout, and a readout drawn when the client says it moved is one nobody
-- can fault. A cast fill is a moving edge, and a moving edge is an animation: it is
-- drawn on the frame the screen is drawn on or it is drawn in steps. That
-- argument is Swing/Gauges.lua's and the note at the head of it is the long
-- version.
--
-- What this costs when nothing is casting is nothing at all. It used to walk
-- every bar on the screen and ask each one's chamber whether it was shown,
-- which at fifteen plates and sixty frames is about a thousand client calls a
-- second to learn that nobody is casting. Cast.lua keeps the set of open
-- chambers instead, so the walk is as long as the number of casts, and with no
-- cast up the pass this runs on has stopped itself.
--
-- Both modes still, and no mode check. EnemyBars.Mode reads a CVar, which is a
-- reasonable thing to do once a second and not sixty times, and the set holds
-- whichever kind of widget has a chamber open.
function EnemyBars.Sweep()
	Cast.SweepAll()
end

-- Every bar read off the client from the top.
--
-- Once a second now rather than five times, because the four events registered
-- in Attach are what says a bar has moved and this is the belt behind them: a
-- mob whose events this client does not fire, a plate that should no longer
-- carry a bar at all, and the targeted-by line, which is about who else is on
-- the mob rather than about the mob. Everything else arrives marked.
function EnemyBars.Update()
	if not anchor or not ns.db.bars then
		return
	end

	if EnemyBars.Mode() == "plates" then
		-- The roster walk is the whole party or raid, and in a forty man it is
		-- eighty unit queries. It only feeds the targeted-by line on a bar, so
		-- with no bars up there is nothing to feed and no reason to walk. This
		-- used to run before the mode check, five times a second, in every
		-- zone with the nameplate key switched off.
		if not next(attached) then
			return
		end
		BuildTargeters()
		for unit, widget in pairs(attached) do
			if UnitExists(unit) and Wanted(unit) then
				UpdateWidget(widget, unit, UnitGUID(unit))
			else
				Release(unit)
			end
		end
	else
		BuildTargeters()
		UpdateList()
	end
end

--------------------------------------------------------------------------

local lastMode
local events = CreateFrame("Frame")

-- You pressed tab, and every bar on the screen has to say so.
--
-- Every bar on a plate marked, because which one is yours is a comparison
-- across all of them rather than a fact about any one. The list takes the whole
-- pass instead: a row there is found by position rather than by unit, so there
-- is no widget to mark.
local function Retarget()
	if next(attached) then
		BuildTargeters()
		for _, widget in pairs(attached) do
			dirty[widget] = true
		end
		Wake()
	else
		EnemyBars.Update()
	end
end

-- What moves every frame, in one named function because a ticker takes one.
--
-- And what stops it. Three sets decide whether there is anything to do: the
-- chambers Cast.lua holds, the ramps in `fading`, and the widgets an event has
-- marked. All three empty is a settled screen, and a settled screen should not
-- be paying for an OnUpdate. Wake is what starts it again, from Cast's Show,
-- from StartFade and from the event handler.
local function Moving(delta)
	EnemyBars.Sweep()
	Fades(delta)
	Flush()
	if moving and Cast.Idle() and not next(fading) and not next(dirty) then
		moving:Stop()
	end
end

-- The cast events, and what they are and are not for.
--
-- They are not what the feature is built on. ns.CastingInfo is read again for
-- every bar on every reading, so a client that never fires one of these for a
-- nameplate unit draws exactly the same bar a second later. That is deliberate
-- after the Deep Wounds bug: a feature whose only source is an event nobody has
-- proved fires is a feature that draws nothing and says nothing.
--
-- What they buy is that second, and it is worth more than it was: the reading
-- behind them used to run five times as often. A cast that starts just after
-- one is most of a one and a half second window old before any bar admits it,
-- which is most of the reason to look.
--
-- Registered only while there is something to draw with them, because
-- registered they wake this frame on every cast every unit the client tracks
-- starts, which in a raid is a great many for the eight of them that land on a
-- mob with a bar. Rebuild is what turns them on and off, so a setting change
-- reaches them for free.
local CAST_EVENTS = {
	"UNIT_SPELLCAST_START",
	"UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_CHANNEL_STOP",
}

local isCastEvent = {}
for _, event in ipairs(CAST_EVENTS) do
	isCastEvent[event] = true
end

local castRegistered = false

CastEvents = function(wanted)
	wanted = wanted and true or false
	if castRegistered == wanted then
		return
	end
	castRegistered = wanted
	for _, event in ipairs(CAST_EVENTS) do
		if wanted then
			events:RegisterEvent(event)
		else
			events:UnregisterEvent(event)
		end
	end
end

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("CVAR_UPDATE")
-- Which bar is yours is the loudest thing on the screen and it is said on every
-- bar at once, so it is the one readout the per-unit events cannot mark: the
-- alpha on fifteen bars moves because you pressed tab. A second of every bar
-- being bright is not a verify being late, it is the wrong picture.
events:RegisterEvent("PLAYER_TARGET_CHANGED")
if C_NamePlate then
	events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	-- The PvP flag going up or down on a unit with a plate. The reading would
	-- catch a bar that has to go, a second later; what it cannot
	-- catch is a plate that arrived unflagged and has no bar for the tick to
	-- look at, which is every enemy player who flags in front of you.
	events:RegisterEvent("UNIT_FACTION")
end

events:SetScript("OnEvent", function(_, event, arg1)
	if isCastEvent[event] then
		-- Plate mode only, and the list is not an oversight. A widget in the
		-- list is found by position rather than by unit, so the lookup would be
		-- a walk of every bar for every cast in the zone, to save a fifth of a
		-- second on the mode that runs when nameplates are switched off.
		local casting = attached[arg1]
		if casting then
			Cast.Update(casting, arg1, true)
		end
		return
	end

	if event == "NAME_PLATE_UNIT_ADDED" then
		plateUnits[arg1] = true
		Attach(arg1)
		return
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		plateUnits[arg1] = nil
		Release(arg1)
		return
	elseif event == "UNIT_FACTION" then
		if plateUnits[arg1] then
			if not attached[arg1] then
				Attach(arg1)
			elseif not Wanted(arg1) then
				Release(arg1)
			end
		end
		return
	elseif event == "PLAYER_TARGET_CHANGED" then
		Retarget()
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		FlushPending()
		ns.Plates.Flush()
		return
	elseif event == "CVAR_UPDATE" then
		if EnemyBars.Mode() ~= lastMode then
			lastMode = EnemyBars.Mode()
			EnemyBars.Rebuild()
		end
		return
	elseif event == "PLAYER_ENTERING_WORLD" then
		lastMode = EnemyBars.Mode()
		EnemyBars.Rebuild()
		ns.Plates.Warn()
		if not warnedNameplates and ns.db.barsMode == "auto" and not NameplatesEnabled() then
			warnedNameplates = true
			ns.Print("enemy nameplates are off, so the bars are running as a panel. Press V for the attached version.")
		end
		if not warnedThreat and ns.db.bars and not ns.HasThreat() then
			warnedThreat = true
			ns.Print("this client has no threat API, so the bars colour by who each mob is hitting instead.")
		end
		return
	end

	-- PLAYER_LOGIN
	EnemyBars.Repair()
	Resolve()
	if #unresolved > 0 then
		ns.Print("these ids on the debuff list are not spells this client knows, so they draw"
			.. " nothing and keep their place: " .. table.concat(unresolved, ", ") .. ".")
	end

	anchor = CreateFrame("Frame", "WarriorKitEnemyBarsAnchor", UIParent)
	-- On the grid too, so a list bar is snapped in both axes rather than only
	-- sized in whole pixels. A bar on a nameplate cannot have this: its origin
	-- is wherever the mob is standing, which is a moving fraction of a pixel no
	-- addon can read or round.
	ns.UI.Adopt(anchor, ns.db.barsZoom)
	-- No name, because the label above an unlocked anchor is only right in list
	-- mode: in nameplate mode nothing hangs off this frame and a caption over
	-- an empty rectangle would be pointing at nothing. That conditional is
	-- ApplyLock's below, and the header it shows is this file's own.
	place = ns.UI.Placeable(anchor, {
		moved = function(point)
			ns.db.barsPoint = point
		end,
	})

	header = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	header:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
	header:SetText("WarriorKit enemies")
	header:Hide()

	EnemyBars.ApplyLayout()
	EnemyBars.Rebuild()

	-- Two tickers off one frame, at two rates and under two gauges. The cast
	-- fills, the arrival ramps and the widgets an event marked run every frame,
	-- and that pass stops itself when all three are empty. See EnemyBars.Sweep.
	-- The reading behind them is the second.
	moving = ns.UI.Ticker(events, 0, "cast", Moving)
	-- Told where to send a chamber opening, now rather than at load, because the
	-- tick it starts does not exist until the line above has run.
	Cast.OnWake(Wake)
	ns.UI.Ticker(events, VERIFY, "bars", EnemyBars.Update)
end)

-- A resolution change moves every size in this file at once, and a UI scale
-- change moves the nameplates the bars are anchored to. Both come through here
-- rather than through a ticker noticing.
ns.UI.OnRescale(function()
	EnemyBars.ApplyLayout()
	EnemyBars.Rebuild()
end)
