local ADDON, ns = ...

local Loot = {}
ns.DungeonLoot = Loot

--------------------------------------------------------------------------
-- A drop, asked about
--
-- The book carries an item as two things: the id, and the name the item had
-- when the bake read it. Everything else on the row comes off the client.
--
-- **The name is a checksum, not the label.** The label is the client's, because
-- the client is running in the player's language and this addon is not going to
-- ship a translation of eight hundred item names. What the baked name is for is
-- the other thing: an id that resolves to an item with a different name on it
-- is an id that is wrong, and a wrong id is the one failure this whole part
-- must not have. It does not draw a blank or an error. It draws a real sword,
-- with a real icon and a real tooltip, that this boss does not drop, and
-- nothing on the screen says so.
--
-- So the two names are compared, and a row the client disagrees with is
-- dropped and counted. Dungeons/Feature.lua reports the count, which is the
-- gate: if the bake ever goes wrong, a reading in the settings window says how
-- many rows the client refused rather than the window quietly lying.
--
-- **The picture cannot miss and the name can.** GetItemInfoInstant reads the
-- client's own item database and answers the icon for anything that exists.
-- GetItemInfo reads a cache, and a cache is empty for an item you have never
-- seen, which for a dungeon you have not run is most of the column. So a row
-- the client has not cached is drawn from the baked name in the quiet colour
-- with its icon already correct, the item is asked for, and the window repaints
-- when the answer arrives. Nothing waits and nothing is blank.
--
-- **Grade decides the order.** An adventure guide is read for the two purple
-- lines in a list of twelve, so the column is sorted by what the client grades
-- each item at, highest first, and by item level under that. The grade is the
-- one fact about an item that no database here carries and the client always
-- knows.
--------------------------------------------------------------------------

local UI = ns.UI
local C = UI.Color

-- What is in the client's own database for an item, by id: the picture, and
-- where it is worn. Both come out of GetItemInfoInstant, which cannot miss.
local function Instant(id)
	local lookup = (_G.C_Item and _G.C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
	if type(lookup) ~= "function" then
		return nil, nil
	end
	local ok, _, _, _, equip, icon = pcall(lookup, id)
	if not ok then
		return nil, nil
	end
	return icon, equip
end

-- What the client's cache has for an item: its name, its grade, its own level
-- and the link a tooltip is opened on. Nothing at all for an item the client
-- has never had to draw.
local function Cached(id)
	local lookup = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
	if type(lookup) ~= "function" then
		return nil
	end
	local ok, name, link, quality, level = pcall(lookup, id)
	if not ok or type(name) ~= "string" then
		return nil
	end
	return name, link, quality or 1, level or 0
end

-- Ask the client to fetch an item it has not cached.
--
-- Probed, because the call is newer than the older of the two clients this
-- ships for. Without it the row still draws, from the baked name and the
-- picture, and fills itself in the first time the client has any other reason
-- to load the item. That is a slower window, not a wrong one.
local function Ask(id)
	local fetch = _G.C_Item and _G.C_Item.RequestLoadItemDataByID
	if type(fetch) ~= "function" then
		return false
	end
	return (pcall(fetch, id))
end

-- How many rows the client has refused since login, and how many it has not
-- answered for yet. Counted rather than merely dropped: a book that has gone
-- wrong has to be visible from the settings window.
local refused, waiting = 0, 0

-- Whether two names are the same item. Compared exactly. There is no case
-- folding and no trimming, because both halves come out of a generated table
-- and a client's own database, neither of which has ever put a space on the end
-- of an item name, and a loose comparison is a checksum that stops catching
-- things.
local function Same(baked, held)
	return baked == held
end

--------------------------------------------------------------------------

-- One row of the right hand column, or nothing at all where the client says the
-- book is wrong about this id.
function Loot.Row(drop)
	local id, baked = drop[1], drop[2]
	if type(id) ~= "number" then
		return nil
	end

	local icon, equip = Instant(id)
	local name, link, quality, level = Cached(id)

	if name and not Same(baked, name) then
		refused = refused + 1
		return nil
	end

	if not name then
		waiting = waiting + 1
		Ask(id)
	end

	return {
		id = id,
		name = name or baked,
		link = link,
		icon = icon,
		equip = equip,
		-- Nil rather than a grade for an item the client has not cached. The
		-- caller draws a row with no grade in the quiet colour, which is the
		-- honest picture: this is the name the book has and the client has not
		-- confirmed it yet.
		quality = name and quality or nil,
		level = name and level or nil,
	}
end

-- Every drop of one boss, as rows, in the order the column draws them.
--
-- The counters are reset per boss rather than accumulated over the session,
-- because what the reading is for is "is this book right", and a number that
-- only ever grows answers "has anything ever been wrong" instead.
function Loot.Rows(boss)
	refused, waiting = 0, 0
	local rows = {}
	for _, drop in ipairs(ns.DungeonBook.Loot(boss)) do
		rows[#rows + 1] = Loot.Row(drop)
	end
	table.sort(rows, function(a, b)
		local left, right = a.quality or -1, b.quality or -1
		if left ~= right then
			return left > right
		end
		if (a.level or 0) ~= (b.level or 0) then
			return (a.level or 0) > (b.level or 0)
		end
		return a.name < b.name
	end)
	return rows
end

-- What the last boss asked about cost: how many rows the client refused, and
-- how many it has not answered for yet.
function Loot.Tally()
	return refused, waiting
end

-- What one row's words are drawn in. The client's own grade colours, which is
-- what every other item in this addon is drawn in, and the quiet colour for a
-- row the client has not confirmed.
function Loot.Tint(row)
	if not row.quality then
		return C.quiet
	end
	return UI.Quality[row.quality] or C.text
end

function Loot.Describe()
	local dropped, pending = Loot.Tally()
	if dropped == 0 and pending == 0 then
		return "the client confirmed every drop on the boss you are reading"
	end
	if dropped == 0 then
		return ("the client has not cached %d of the drops on the boss you are reading yet")
			:format(pending)
	end
	return ("the client refused %d of the drops on the boss you are reading, which means the book is wrong about them")
		:format(dropped)
end
