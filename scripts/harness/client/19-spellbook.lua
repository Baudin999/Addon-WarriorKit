-- The spell book, every rank of it, and the client's own window
--
-- 03-player.lua answers three book indices, which is all the drag readers
-- ever asked: what a spell dropped on a row is. The spell book window walks
-- the tabs, and this file is the client's answer to that: two tabs, the
-- entries in each, a rank line under every one, a passive, and a rank the
-- trainer has not sold yet.
--
-- **The first three indices are 03-player.lua's, unchanged.** Rend, Thunder
-- Clap and Battle Shout at one, two and three with the ids that file carries,
-- because the buff page, the cooldown row and the mouseover page all drag off
-- those three by index and a book that moved them would move three sections
-- with it. The ranks are appended after them, which is a shape the real book
-- does not have, and it is deliberate: the reader groups by name rather than
-- by neighbour, and a fixture whose ranks sat side by side could not tell the
-- two apart.
--
-- **The ids past the first three are fixture numbers, not the game's.** The
-- window never compares one against anything but itself: an id is what a
-- square is armed with and what a section reads back off it. Nothing here is
-- baked game data and none of it should be copied out.
--
-- **Ranks.lua reads its ranks off this book.** That file walks the tabs and
-- used to be refused at GetSpellTabInfo. With this book under it and the
-- PickupSpell below beside it, both halves of that file run: 87-spell-ranks
-- lays spells into the action slots 05-quests.lua models and presses the
-- button. Three ranks of Rend and two of Battle Shout with a greyed third are
-- what that section counts against, so moving an entry here moves it.

local H = ...
local region = H.region

local TABS = {
	{ name = "General", icon = "Interface\\Icons\\BookGeneral", offset = 0, count = 7 },
	{ name = "Fury", icon = "Interface\\Icons\\BookFury", offset = 7, count = 3 },
}

local ENTRIES = {
	{ kind = "SPELL", id = 772, name = "Rend", sub = "Rank 1" },
	{ kind = "SPELL", id = 6343, name = "Thunder Clap", sub = "Rank 1" },
	{ kind = "SPELL", id = 6673, name = "Battle Shout", sub = "Rank 1" },
	{ kind = "SPELL", id = 6546, name = "Rend", sub = "Rank 2" },
	{ kind = "SPELL", id = 6547, name = "Rend", sub = "Rank 3" },
	{ kind = "SPELL", id = 5242, name = "Battle Shout", sub = "Rank 2" },
	-- The greyed rank the trainer still has. A window that drew this would
	-- put a square on the screen nobody can cast.
	{ kind = "FUTURESPELL", id = 6192, name = "Battle Shout", sub = "Rank 3" },
	{ kind = "SPELL", id = 2687, name = "Bloodrage", sub = "" },
	{ kind = "SPELL", id = 12317, name = "Enrage", sub = "", passive = true },
	{ kind = "SPELL", id = 18499, name = "Berserker Rage", sub = "" },
}

-- `reads` counts entries handed over, so a section can tell a book that was
-- walked from one that was marked stale and left alone. The window walked this
-- at login and again on every SPELLS_CHANGED with nobody looking at it, and a
-- read that does not happen leaves no other trace.
H.spellbook = { tabs = TABS, entries = ENTRIES, pickups = {}, reads = 0 }

_G.GetNumSpellTabs = function()
	return #TABS
end

_G.GetSpellTabInfo = function(tab)
	local entry = TABS[tab]
	if not entry then
		return nil
	end
	return entry.name, entry.icon, entry.offset, entry.count
end

local function Entry(index, book)
	if book ~= "spell" then
		return nil
	end
	return ENTRIES[index]
end

_G.GetSpellBookItemInfo = function(index, book)
	local entry = Entry(index, book)
	if not entry then
		return nil
	end
	H.spellbook.reads = H.spellbook.reads + 1
	return entry.kind, entry.id
end

_G.GetSpellBookItemName = function(index, book)
	local entry = Entry(index, book)
	if not entry then
		return nil
	end
	return entry.name, entry.sub
end

_G.GetSpellBookItemTexture = function(index, book)
	local entry = Entry(index, book)
	if not entry then
		return nil
	end
	return "Interface\\Icons\\A" .. entry.id
end

_G.IsPassiveSpell = function(index, book)
	local entry = Entry(index, book)
	return entry ~= nil and entry.passive == true
end

-- Onto the cursor, the way 05-quests.lua models a spell there: the book
-- index and the book. Counted, so a section can tell a drag that picked
-- something up from one that was refused.
--
-- The id goes with it so the thing on the cursor can be put down again. A
-- pickup that filled the hands with something PlaceAction could not place read
-- as a working drag right up until a slot came back empty.
_G.PickupSpellBookItem = function(index, book)
	H.spellbook.pickups[#H.spellbook.pickups + 1] = index
	local entry = Entry(index, book)
	_G.WarriorKitCarrySpell(index, book, entry and entry.id)
end

-- The other way onto the cursor, and the one Buttons/Ranks.lua takes.
--
-- **This client takes an id and refuses a name.** That is one of the two
-- shapes the call has across clients and nothing installed on this machine
-- proves which 2.5.6 is, which is the whole reason ns.CarrySpell exists: it
-- tries both spellings and reads the cursor back. Modelled as the strict one
-- rather than as a call that takes anything, because a stub that answered to
-- both would let a caller that guessed wrong pass, and a caller that guessed
-- wrong is exactly the bug ns.CarrySpell was written to absorb.
--
-- A name reaches here from Buttons/Layout.lua, which composes a loadout out of
-- spell names, so the fallback that turns a name into an id is on the tested
-- path too and is not theory.
--
-- FUTURESPELL is refused. The trainer has not sold it to you, the client will
-- not put it on the cursor, and a fixture that handed one over would let a
-- reader that ignored the greyed ranks look the same as one that skipped them.
_G.PickupSpell = function(id)
	if type(id) ~= "number" then
		error("this client's PickupSpell takes a spell id, not " .. type(id))
	end
	for index, entry in ipairs(ENTRIES) do
		if entry.id == id and entry.kind == "SPELL" then
			H.spellbook.pickups[#H.spellbook.pickups + 1] = index
			_G.WarriorKitCarrySpell(index, "spell", id)
			return
		end
	end
	-- An id this book does not carry leaves the hands empty rather than
	-- raising, which is what the client does for a spell you have not learnt.
	_G.ClearCursor()
end

-- Present so Buttons/Layout.lua can answer that a loadout is writable at all,
-- and modelled no further than that. Nothing in the suite composes a loadout,
-- so a macro on the cursor has no reader; a stub that pretended otherwise
-- would be a fixture asserting about itself.
_G.PickupMacro = function()
	_G.ClearCursor()
end

--------------------------------------------------------------------------
-- The book, seen through GetSpellInfo
--
-- 03-player.lua answers that call off a flat table of ids it names, and every
-- id it does not carry comes back as "Spell6547". That was fine while nothing
-- compared the answer with a book entry. Buttons/Ranks.lua does exactly that,
-- on every slot on your bars: it reads the id out of a slot, asks for its
-- name, and looks the name up in the book it walked. Against the flat table
-- every rank past the first three is a spell of its own with nobody else
-- sharing its name, so nothing is ever behind anything and the whole feature
-- reads as a bar that is already up to date.
--
-- Wrapped here rather than written into that file because the ranks are here.
-- The earlier answer is kept for everything this book does not carry, which is
-- most of the ids in the suite, so the two are one call and not a fork.
--
-- The name direction is the same lookup read backwards, and it is the seventh
-- return. ns.CarrySpell reads the id there when PickupSpell has refused a
-- name, which is the shape Buttons/Layout.lua reaches it in, so without it the
-- name half of that shim has no answer on this client. The last entry wearing
-- a name is the top rank you have trained, which is the rank the live call
-- hands back when you ask it by name.
--------------------------------------------------------------------------

local function Look(want, field)
	local found
	for _, entry in ipairs(ENTRIES) do
		if entry[field] == want and entry.kind == "SPELL" then
			found = entry
		end
	end
	return found
end

local Flat = _G.GetSpellInfo

_G.GetSpellInfo = function(spell)
	if type(spell) == "string" then
		local entry = Look(spell, "name")
		local name, rank, icon, cast = Flat(spell)
		if not entry then
			return name, rank, icon, cast
		end
		return entry.name, rank, icon, cast, nil, nil, entry.id
	end
	local entry = type(spell) == "number" and Look(spell, "id")
	if not entry then
		return Flat(spell)
	end
	local _, rank, icon, cast = Flat(spell)
	return entry.name, rank, icon, cast, nil, nil, entry.id
end

--------------------------------------------------------------------------
-- The client's own window
--
-- ToggleSpellBook is the P key. A plain global, as on both clients, and the
-- stub's own version records the book it was asked for and shows the window,
-- so a section can tell the client's key from the addon's by which of the
-- two moved.
--------------------------------------------------------------------------

local frame = region("frame", _G.UIParent, "SpellBookFrame")
frame:SetSize(384, 512)
frame:Hide()

H.spellbookKey = { books = {} }
function _G.ToggleSpellBook(book)
	H.spellbookKey.books[#H.spellbookKey.books + 1] = book
	frame:Show()
end
