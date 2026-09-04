local ADDON, ns = ...

local Standing = {}
ns.Standing = Standing

--------------------------------------------------------------------------
-- What you have out
--
-- A shaman drops four totems into four slots and cannot see any of them
-- without turning the camera round. The client's own answer is a row of icons
-- welded to the player frame that appears and disappears as totems come and
-- go, so the square that was Windfury a moment ago is now Mana Spring and the
-- row is a different length every time you look at it. There is nothing to
-- learn the shape of, which is what makes it unreadable in a fight.
--
-- So this row is the four slots, always in the same order and always in the
-- same place, and a slot with nothing in it is a hole rather than a square
-- that went away. That is the whole design: you learn where earth lives once,
-- and afterwards the question "is my Windfury still up" is answered by the
-- shape of the row rather than by reading four names.
--
-- The word "standing" is doing two jobs and both are meant. A totem stands on
-- the ground until it runs out or dies, and a warrior stands in one of three
-- stances. Those are the same question asked of two classes: which of the
-- slots my class owns am I filling right now, and for how much longer. Nothing
-- in this folder knows what a totem is. It reads a plan off Class\<yours>.lua
-- and a reader named by that plan, and a stance row is a second reader and a
-- second plan rather than a second part.
--
-- Meter\Standing.lua is a different word wearing the same letters: that file is
-- where you stand on a mob's threat table. Neither names the other and neither
-- has a namespace the other could take.
--
-- Nil is the gate here as everywhere else in Class\. A class that registered no
-- `standing` builds no frame, arms no ticker and opens no page, which is every
-- class but the shaman today.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- The readers
--
-- One per `kind` a plan can name, and each answers the same five things about
-- one slot: whether it is filled, what art to draw, when it runs out, how long
-- it was filled for, and what the thing in it is called.
--
-- This table is the seam the part is built around. A totem is read out of
-- GetTotemInfo, which counts slots the client numbers itself; a stance would be
-- read out of GetShapeshiftForm, which answers one number and no clock at all.
-- Neither of those is a fact about Warcraft that belongs in a class file, and
-- neither is a fact about a row of squares that belongs in Row.lua, so they
-- live here and a plan names the one it wants.
--
-- Nothing allocates. Row.lua reads every slot on its tick.
--------------------------------------------------------------------------

local READERS = {}

-- The client's own call, and every number in it is the client's. `duration` is
-- zero for a slot the server has answered about but not filled, which is why it
-- is tested rather than the `haveTotem` flag alone: Blizzard's own totem button
-- draws on the duration for the same reason.
--
-- GetTotemInfo may return nothing at all, which the client's API documentation
-- says out loud, so the first value is tested for truth rather than compared.
function READERS.totem(slot)
	if not GetTotemInfo then
		return false
	end
	local have, name, start, duration, icon = GetTotemInfo(slot.index)
	if not have or not duration or duration <= 0 then
		return false
	end
	return true, icon, start + duration, duration, name
end

--------------------------------------------------------------------------
-- The plan this character brought
--
-- Resolved at login and again whenever the client changes its mind about what
-- you know, never on a tick. Held as a list rather than asked for per square,
-- because the row walks it ten times a second and Class.Of is two table
-- lookups behind a class token.
--------------------------------------------------------------------------

local slots = {}
local reader
local epoch = 0

-- What a class handed over, or nil. Read through Class.Of, so a spec may put a
-- different plan in front of its class's, which is what a druid's four forms
-- against a shaman's four slots would want.
local function Plan()
	return ns.Class.Of("standing")
end

function Standing.Rebuild()
	wipe(slots)
	local plan = Plan()
	reader = plan and READERS[plan.kind] or nil

	-- A plan naming a reader that does not exist draws nothing rather than
	-- erroring on the first tick, which is what a class file being ahead of
	-- this one looks like.
	if plan and reader then
		for index = 1, #plan.slots do
			slots[index] = plan.slots[index]
		end
	end

	epoch = epoch + 1
end

function Standing.Count()
	return #slots
end

function Standing.Slot(index)
	return slots[index]
end

-- A number that moves when the list was built again, which is what the row
-- compares to decide whether it has to lay itself out.
function Standing.Epoch()
	return epoch
end

-- One slot, right now: filled, art, when it runs out, how long it was filled
-- for, what it is called.
--
-- On the tick, so it allocates nothing and holds nothing.
function Standing.State(index)
	local slot = slots[index]
	if not slot or not reader then
		return false
	end
	return reader(slot)
end

--------------------------------------------------------------------------
-- What the addon says about it
--------------------------------------------------------------------------

-- Whether this character has a row at all.
--
-- Off the registry rather than off the built list, because the four questions
-- below it are asked by the options window and the window is built at
-- PLAYER_LOGIN alongside this part rather than after it. A part whose page
-- appears or not depending on which of two login handlers ran first is a page
-- that is there on some sessions.
function Standing.Available()
	local mine = Plan()
	return (mine and READERS[mine.kind]) ~= nil
end

-- The class's own word for a row of these, for a slash word and a page title
-- to be built out of. "totems" today, "stances" the day a warrior file writes
-- one, and neither word is anywhere in this folder.
--
-- Read off the registry for the reason Available is, and it costs two table
-- lookups: nothing on a tick asks what the row is called.
function Standing.Word()
	local mine = Plan()
	return mine and mine.word or "totems"
end

-- The page this row is arranged on, which is the class's own word with a
-- capital on it. Held here rather than written out in Feature.lua because a
-- square you click opens the page by its title, and a title in two files is two
-- files that can disagree about it.
function Standing.Page()
	local word = Standing.Word()
	return word:sub(1, 1):upper() .. word:sub(2)
end

-- One of them, singular, for a sentence to name.
function Standing.One()
	local mine = Plan()
	return mine and mine.one or "slot"
end

-- Why there is no row, or nil because there is one. Named rather than silent,
-- because a switch that does nothing and says nothing reads as a broken addon
-- rather than as a part that is not for you.
function Standing.Refusal()
	if not ns.Class.Token() then
		return nil
	end
	local mine = Plan()
	if not mine then
		return ("a %s has no slots to watch, so there is no row"):format(ns.Class.Label())
	end
	if not READERS[mine.kind] then
		return ("a %s asks for a %s row and this addon has no reader for one")
			:format(ns.Class.Label(), tostring(mine.kind))
	end
	return nil
end

-- How many are filled right now, which is what the status line and the page
-- reading both say. Off the tick, so the read is fresh rather than whatever the
-- row last drew.
function Standing.Up()
	local up = 0
	for index = 1, #slots do
		if Standing.State(index) then
			up = up + 1
		end
	end
	return up
end

function Standing.Describe()
	if not ns.db.standing then
		return "off"
	end
	local refusal = Standing.Refusal()
	if refusal then
		return refusal
	end
	return ("%d of %d %s up"):format(Standing.Up(), #slots, Standing.Word())
end
