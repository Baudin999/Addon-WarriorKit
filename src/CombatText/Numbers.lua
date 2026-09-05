local ADDON, ns = ...

local UI = ns.UI
local Stream = ns.Ck.Stream
local Anchors = ns.CombatTextAnchors

local Numbers = {}
ns.CombatTextNumbers = Numbers

--------------------------------------------------------------------------
-- What the fight is doing to you, in numbers
--
-- Every blow that lands on you falls away from a point beside your left
-- shoulder, and every blow you land on something falls away from one on your
-- right. Damage is white, healing is green, and a hit the game itself calls
-- more than a hit is gold.
--
-- **Where the split comes from.** A number is placed by who it happened to and
-- not by who caused it, which is the one rule that makes two columns readable
-- at a glance: everything on the left is your health going down, everything on
-- the right is the target's. A heal on yourself is on the left with the damage
-- for the same reason, because it is your own bar moving.
--
-- **Only your own end of it.** The log names every creature in range and a
-- reader that drew all of it would be four other people's numbers over your
-- screen. Something you or yours did, or something done to you, and nothing
-- else. ns.Unit.Roster.Owner is the same door Feeds/Combat.lua asks that
-- through, so a pet, an imp and a totem are covered without this file knowing
-- what any of them are.
--
-- **The same blow twice is one number.** A bleed ticking four times in six
-- seconds used to be four numbers stacked on each other, each unreadable
-- because of the next. They merge instead: the number already in the air takes
-- the new amount, swells, and keeps its place in its own fall. That is the
-- single biggest thing that makes a stream of numbers readable, and it is the
-- reason this is built on a pool of items rather than on tweens, because a
-- tween owns its clock and a number merged into has to keep the clock it has.
--
-- **A big hit is drawn bigger.** A forty and a nine hundred at the same size
-- throw away the one thing you can read without looking. Every number is scaled
-- against the biggest one of the fight so far, which resets when you leave
-- combat so that the last pull's boss does not flatten the next one's trash.
--
-- Nothing here decides where the numbers come from. That is three rectangles in
-- CombatText/Anchors.lua that you drag.
--------------------------------------------------------------------------

-- The three colours, and they are the whole readout at a glance.
--
-- Held as tables this file owns rather than read off UI.Color, for the reason
-- Feeds/Combat.lua holds its own: these are the meaning of a number over the
-- world and not the palette of a panel, and the guard below compares a colour
-- by identity. The green and the gold are the same two values the combat feed
-- draws a heal and a critical in, because one fact must not have two colours.
local DAMAGE = { 0.95, 0.95, 0.97 }
local HEAL = { 0.34, 0.80, 0.44 }
local BIG = { 1.00, 0.82, 0.20 }

-- How far into its life a number may be and still be merged into. Past the
-- hold it is already fading and the eye has finished with it, so adding to one
-- reads as a number changing its mind rather than as one blow.
local MERGE_BEFORE = 0.45

-- What a number is scaled by, between the smallest hit of the fight and the
-- biggest. A narrow band on purpose, and it was too wide the first time: at
-- 0.78 to 1.20 an ordinary hit late in a fight was drawn at four fifths of a
-- setting that was itself too small, and the two shrinkings compounded into a
-- number you had to go looking for. The band says which of two numbers was the
-- bigger hit and that is all it is for; the setting says how big numbers are.
local FLOOR, REACH = 0.88, 0.30

-- Every number is drawn in one font, at the smallest size an outline is legible
-- at, and the size on the settings page is a multiplier on top of it.
--
-- That is the opposite of the obvious design, which is a font object per size,
-- and it is better for two reasons. The stream already scales every frame it
-- carries, so a size setting expressed as a scale costs nothing at all beyond
-- what a number was going to pay anyway; and a font rebuilt when a slider moves
-- is a CreateFont per step of the drag, which the client never collects.
--
-- Read off UI/Text.lua rather than typed, so the one number that decides
-- whether an outline closes up its own counters lives in one place.
local BASE = UI.OutlineFloor()

-- Where the numbers are on a line, read from the one place that knows. The two
-- other readers of the combat log still hold copies of this table and the note
-- beside it in Core/CombatLog.lua says why they are a separate commit.
local SHAPES = ns.CombatLog.SHAPES

-- Whether a GUID is you or something of yours, which is the whole of the filter
-- that keeps four other people's numbers off your screen.
local Mine = ns.Unit.Roster.Mine

local pool = {}
local styles = {}
local biggest = 0
local subscribed = false

--------------------------------------------------------------------------

-- cold: Build makes one number's frame, on the spawn a busier second than any before it needs another
local function Build()
	local frame = CreateFrame("Frame", nil, UIParent)
	-- A point rather than a box. What is seen is the string, which overflows it
	-- in every direction, and a frame sized to the text would have to be
	-- resized on every number.
	frame:SetSize(1, 1)
	-- Over the world and under every window the addon draws.
	frame:SetFrameStrata("MEDIUM")
	frame:Hide()
	-- Outlined rather than shadowed, which is the opposite of what the loot
	-- captions chose and is the rule rather than the exception. A rim reads as
	-- a health number over a mob, and that is exactly what this is.
	frame.text = UI.Label(frame, BASE, DAMAGE, "CENTER", UI.OUTLINE)
	frame.text:SetPoint("CENTER")
	return frame
end

-- hot: Release is handed to a style as onGone and called back through the field when a number has finished falling
local function Release(frame)
	pool[#pool + 1] = frame
end

--------------------------------------------------------------------------

-- The styles, rebuilt whenever a setting behind them moves.
--
-- Three tables rather than three branches on the tick. A critical is the
-- ordinary style with a larger start, a punch on the front of it and a later
-- fade, and saying that as data is what makes "crits start bigger and fade
-- slower" a number somebody can change rather than code somebody has to read.
function Numbers.Reshape()
	local db = ns.db
	local life, drop, arc = db.hitsLife, db.hitsDrop, db.hitsArc
	-- The size, as the multiplier every envelope below is written in. One at the
	-- outline floor and up from there, so a number is never drawn smaller than
	-- the size its own rim was chosen for.
	local grow = db.hitsSize / BASE

	styles.plain = Stream.Style({
		seconds = life, drop = drop, arc = arc,
		fromScale = grow, toScale = 0.85 * grow,
		onGone = Release,
	})

	-- Longer, taller and gold. The punch is the part that reads as impact: a
	-- number merely born bigger reads as a bigger font, and one that swells for
	-- an eighth of a second and settles reads as a hit landing.
	styles.big = Stream.Style({
		seconds = life * 1.35, drop = drop * 1.1, arc = arc,
		fromScale = 1.45 * grow, toScale = 1.05 * grow,
		punch = 0.35 * grow, punchFor = 0.14,
		holdFor = 0.62,
		onGone = Release,
	})

	-- A word rather than a number, so it rises instead of falling and does not
	-- bow at all. A negative drop is a lift, which is the one place the stream's
	-- vocabulary reads oddly and is better than a second field that means the
	-- same thing with the sign the other way round.
	styles.call = Stream.Style({
		seconds = life * 1.6, drop = -16, arc = 0,
		fromScale = 1.45 * grow, toScale = 1.15 * grow,
		punch = 0.4 * grow, punchFor = 0.12,
		holdFor = 0.6,
		onGone = Release,
	})
end

--------------------------------------------------------------------------

-- What this number is scaled by, against the biggest hit of the fight.
--
-- The running maximum is written here rather than tracked by an event, because
-- the number that sets it is the number being drawn and there is no earlier
-- moment to notice it in.
local function Weight(amount)
	if amount > biggest then
		biggest = amount
	end
	if biggest <= 0 then
		return 1
	end
	return FLOOR + REACH * (amount / biggest)
end

-- One frame told what to say.
--
-- Both writes are compared first and both comparisons pay: a bleed ticking for
-- the same amount onto the frame it used last time writes neither the text nor
-- the colour, and a number merged into rewrites only its total.
--
-- Separate from taking a frame off the pool, because a number merged into is
-- already holding one and the only thing that changes about it is the total.
local function Write(frame, text, color)
	if frame.said ~= text then
		frame.said = text
		frame.text:SetText(text)
	end
	if frame.tint ~= color then
		frame.tint = color
		frame.text:SetTextColor(color[1], color[2], color[3])
	end
	return frame
end

local function Dress(text, color)
	local frame = pool[#pool]
	if frame then
		pool[#pool] = nil
	else
		frame = Build()
	end
	return Write(frame, text, color)
end

--------------------------------------------------------------------------

-- One number, on screen.
--
--   amount  what to draw
--   side    "mine" for the left anchor, "theirs" for the right
--   heal    whether it is health going up
--   big     whether the game called it more than a hit
--   key     what a later number has to match to merge into this one
function Numbers.Show(amount, side, heal, big, key)
	local style = big and styles.big or styles.plain
	local color = DAMAGE
	if heal then
		color = HEAL
	elseif big then
		color = BIG
	end

	local weight = Weight(amount)
	if ns.db.hitsMerge and key then
		-- Find hands back the first number carrying this key, so the key has to
		-- carry everything that makes two blows the same thing to look at. The
		-- caller folds the kind into it for exactly that reason: a critical and
		-- an ordinary tick of one bleed are two things to see, and a key that
		-- did not separate them would either merge them, which takes the gold
		-- off the one that earned it, or find the wrong one and refuse a merge
		-- the next tick was entitled to.
		local live = Stream.Find(key, MERGE_BEFORE)
		if live then
			live.amount = live.amount + amount
			Write(live.frame, live.amount, color)
			return Stream.Bump(live, Weight(live.amount))
		end
	end

	local frame = Dress(amount, color)
	local item = Stream.Push(Anchors.Of(side), frame, style, weight, key)
	item.amount = amount
	return item
end

-- One word above your head, which is the third anchor and the one thing here
-- that is not a number. CombatText/Calls.lua decides when.
function Numbers.Word(text)
	local frame = Dress(text, BIG)
	return Stream.Push(Anchors.Of("calls"), frame, styles.call, 1, nil)
end

--------------------------------------------------------------------------

-- hot: Numbers.OnLog is a combat log reader, called back out of ns.CombatLog's list
--
-- The positions are ns.CombatLog.SHAPES and the reason they are read from there
-- rather than from a table in this file is written beside them: two other
-- readers each hold a copy and a third one is how the three drift.
function Numbers.OnLog(_, subevent, _, sourceGUID, _, _, _, destGUID,
	_, _, _, a12, _, _, a15, _, _, a18, _, a20, a21, me)
	if not me or not ns.db.hits then
		return false
	end

	local shape = SHAPES[subevent]
	-- A miss carries no number, and drawing the word for one is a decision
	-- about what this part is for rather than a line of code, so it is not
	-- taken here.
	if not shape or not shape.amount then
		return false
	end

	-- Which of the two columns, and the answer decides everything after it. A
	-- blow is placed by who it happened to, so what is on the left is your own
	-- health moving and what is on the right is the target's.
	local onMe = Mine(destGUID, me)
	local byMe = Mine(sourceGUID, me)
	if not onMe and not byMe then
		return false
	end

	local amount = (shape.amount == 12) and a12 or a15
	if type(amount) ~= "number" or amount <= 0 then
		return false
	end

	-- More than a hit, which is three different flags depending on the shape of
	-- the line. Crushing is the swing's alone: it is a melee mechanic and the
	-- client sends it nowhere else.
	local big
	if shape.crushing then
		big = a18 or a20
	elseif shape.crit == 18 then
		big = a18
	else
		big = a21
	end

	-- The merge key, as arithmetic rather than as a joined string, because this
	-- is the busiest event the client sends and a string a line is a string a
	-- line. Three facts go into it and every one of them makes two blows a
	-- different thing to look at: which spell, which side of you it landed on,
	-- and whether the game called it more than a hit. A swing has no spell and
	-- shares zero, which merges a main hand and an off hand landing together and
	-- is the right answer, because they draw on top of each other otherwise.
	local key = ((shape.spell and a12 or 0) * 2 + (onMe and 1 or 0)) * 2
		+ (big and 1 or 0)
	Numbers.Show(amount, onMe and "mine" or "theirs", shape.heal, big and true, key)
	return true
end

--------------------------------------------------------------------------

-- On and off, which is the switch and nothing else.
--
-- Off takes this file off the combat log rather than turning its handler into
-- an early return, so an evening with the numbers off costs the client nothing
-- at all on its busiest event. Core/CombatLog.lua unregisters from the client
-- entirely once the last reader has gone.
function Numbers.Apply()
	Numbers.Reshape()

	local want = ns.db.hits and ns.CombatLog.Ready()
	if want and not subscribed then
		subscribed = ns.CombatLog.Subscribe(Numbers.OnLog)
	elseif not want and subscribed then
		ns.CombatLog.Unsubscribe(Numbers.OnLog)
		subscribed = false
		-- Everything still in the air comes down at once. A frame left flying
		-- with nothing advancing it would sit on the screen until a reload.
		Stream.Clear()
	end

	if ns.db.hits then
		Anchors.Apply()
	end
	-- Last, because it is the only thing here that reaches outside the addon.
	ns.CombatTextBlizzard.Apply()
end

-- How many are on screen, for the harness and for the status line.
function Numbers.Count()
	return Stream.Count()
end

-- The biggest hit of the fight, which is what every number is scaled against.
function Numbers.Biggest()
	return biggest
end

function Numbers.Describe()
	if not ns.db.hits then
		return "off"
	end
	if not ns.CombatLog.Ready() then
		return "on, but this client has no combat log"
	end
	return ("on, %d in the air"):format(Stream.Count())
end

--------------------------------------------------------------------------

-- Armed at login, which is how every part of this addon comes up and is not
-- something the settings page can do for it. Apply is the only way in: it
-- subscribes to the combat log, builds the styles and places the anchors, and
-- with the part switched off it does none of the three. Nothing else calls it
-- until you change something, so without this line the numbers would appear the
-- first time you opened the options window and never before.
--
-- And the scale is measured against this fight rather than against the session.
-- A boss that hit for nine thousand would otherwise flatten every number of the
-- next hour's trash into the floor.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		Numbers.Apply()
		return
	end
	biggest = 0
end)
