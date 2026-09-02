local ADDON, ns = ...

local Read = {}
ns.BookRead = Read

--------------------------------------------------------------------------
-- The client's spell book calls, behind one door
--
-- Every question the spell book window asks the client is asked here, and
-- nothing else in the folder names a client function. Same shape as
-- Talents/Read.lua and Quests/Client.lua, for the same reason: a window that
-- asked six globals in four places would break in four places on the next
-- build, and the book is one of the places the two clients this addon runs on
-- have been known to disagree.
--
-- **One row per spell, every rank under it.** The client's own book lists
-- Rend six times, once per rank, and a warrior at sixty scrolls three pages of
-- names they already know to find the one they came for. Here a spell is one
-- entry with its ranks in a list, in the order the book carries them, which
-- is ascending on every client. Grouped by name inside a tab, because a
-- rank's name is the one thing every client answers the same way; parsing the
-- rank line under it is localised and the number is not always where you
-- would expect.
--
-- **FUTURESPELL entries are left out.** Those are the greyed ranks the trainer
-- has not sold you yet. Drawing one would put a square on the screen you
-- cannot cast or drag, which is a worse picture than a rank missing from a
-- fold-out.
--
-- **Read at call time, not at load.** Nothing here is on a ticker: the book
-- is read when the window paints, which is when it opens and when the client
-- says the book changed. Reaching through _G each time costs a lookup and
-- buys the harness a way to stand the addon on a different book for one
-- section without reloading it.
--------------------------------------------------------------------------

-- BOOKTYPE_SPELL, written out so no global is needed.
local BOOK = "spell"

local NEEDED = {
	"GetNumSpellTabs", "GetSpellTabInfo",
	"GetSpellBookItemInfo", "GetSpellBookItemName",
}

local function Call(name)
	local f = _G[name]
	return type(f) == "function" and f or nil
end

-- Whether this client will let the book be read at all, and which call is
-- missing where it will not. Asked every time rather than once, because the
-- harness swaps the calls under a running addon and a cached answer would be
-- a lie for the rest of the run.
function Read.Available()
	for index = 1, #NEEDED do
		if not Call(NEEDED[index]) then
			return false, NEEDED[index] .. " is missing on this client"
		end
	end
	return true
end

--------------------------------------------------------------------------
-- One entry
--------------------------------------------------------------------------

local function Texture(index, id)
	local byBook = Call("GetSpellBookItemTexture")
	if byBook then
		local texture = byBook(index, BOOK)
		if texture then
			return texture
		end
	end
	local byId = Call("GetSpellTexture")
	if byId and id then
		return byId(id)
	end
	return nil
end

local function Passive(index)
	local ask = Call("IsPassiveSpell")
	if not ask then
		return false
	end
	return ask(index, BOOK) and true or false
end

-- What the client writes under a spell with no rank: nothing on a plain one,
-- the client's own word on a passive.
local function Sub(sub, passive)
	if sub and sub ~= "" then
		return sub
	end
	if passive then
		return type(_G.SPELL_PASSIVE) == "string" and _G.SPELL_PASSIVE or "Passive"
	end
	return ""
end

--------------------------------------------------------------------------
-- The whole book
--
-- A list of tabs. Each tab is its name, its icon and a list of spells; each
-- spell is its name, its icon, whether it is passive and a list of ranks; each
-- rank is the book index it lives at, the spell id where the client hands
-- one over, and the rank line as the client wrote it.
--------------------------------------------------------------------------

local function Entry(tab, index, byName)
	local kind, id = GetSpellBookItemInfo(index, BOOK)
	if kind ~= "SPELL" then
		return
	end
	local name, sub = GetSpellBookItemName(index, BOOK)
	if not name then
		return
	end
	local spell = byName[name]
	if not spell then
		local passive = Passive(index)
		spell = { name = name, icon = Texture(index, id), passive = passive, ranks = {} }
		byName[name] = spell
		tab.spells[#tab.spells + 1] = spell
	end
	spell.ranks[#spell.ranks + 1] = {
		index = index, id = id, label = Sub(sub, spell.passive),
	}
end

function Read.Tabs()
	local tabs = {}
	if not Read.Available() then
		return tabs
	end
	for at = 1, GetNumSpellTabs() do
		local name, icon, offset, count = GetSpellTabInfo(at)
		if type(offset) == "number" and type(count) == "number" then
			local tab = { name = name or ("Tab " .. at), icon = icon, spells = {} }
			local byName = {}
			for index = offset + 1, offset + count do
				Entry(tab, index, byName)
			end
			tabs[#tabs + 1] = tab
		end
	end
	return tabs
end

--------------------------------------------------------------------------
-- What a square casts, and what a drag picks up
--------------------------------------------------------------------------

-- What goes in the secure button's spell attribute. The id where the client
-- gave one, which both of these clients do; the name with the rank in
-- brackets after it where it did not, which is the form the client's own
-- macro parser has always taken.
function Read.Cast(spell, rank)
	if rank.id then
		return rank.id
	end
	if rank.label ~= "" then
		return ("%s(%s)"):format(spell.name, rank.label)
	end
	return spell.name
end

-- Onto the cursor. The book's own pickup first, because it is what the
-- client's own window calls and takes the index this file already holds;
-- PickupSpell by id where a client has only that.
function Read.Pickup(rank)
	local byBook = Call("PickupSpellBookItem")
	if byBook then
		byBook(rank.index, BOOK)
		return true
	end
	local byId = Call("PickupSpell")
	if byId and rank.id then
		byId(rank.id)
		return true
	end
	return false
end
