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
-- **Ranks.lua's probe now passes.** That file walks the tabs and used to be
-- refused at GetSpellTabInfo; with this book under it the walk runs, over a
-- bar whose slots hold nothing it recognises, and answers that every slot is
-- at its best rank. No section asserts on either answer.

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
_G.PickupSpellBookItem = function(index, book)
	H.spellbook.pickups[#H.spellbook.pickups + 1] = index
	_G.WarriorKitCarrySpell(index, book)
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
