-- Bakes src/Dungeons/Art.lua out of Blizzard's own instance tables.
--
--   lua5.1 scripts/bake-dungeon-art.lua <path to a folder of wago.tools exports>
--
-- Run through scripts/bake-dungeon-art.sh, which fetches the exports and checks
-- the result.
--
-- **What this is for.** The shelf is a page of cards, one per dungeon, and a
-- card wants a picture of the place. Retail draws that picture out of the
-- Encounter Journal's own art, which the 2.5 client does not ship: its
-- interface manifest has no interface/encounterjournal folder in it at all, so
-- there is nothing there to point at and no amount of asking the client will
-- make one.
--
-- What it does ship is the loading screen. Every instance in the game carries
-- one, it is a painting of that place made by the same artists, and it is the
-- picture a player has already looked at on the way in. So the card wears the
-- loading screen, and the join from a dungeon to its screen is what this bakes.
--
-- **The client will not answer this either.** LoadingScreens is a table the
-- client reads on the way into an instance and exposes to nothing; there is no
-- call on either of these clients that turns a dungeon into its art. A texture
-- is drawn by path all the same, which is the same fact Dungeons/Sheets.lua is
-- built on.
--
-- Three exports, and every one of them is Blizzard's own table:
--
--   map.csv       the 2.5 client's instance list, which is what says that
--                 "Coilfang: The Steamvault" is a five man and which loading
--                 screen it carries.
--   screens.csv   LoadingScreens, which turns that id into a file id.
--   files.csv     ManifestInterfaceData, which turns a file id into the path
--                 the texture is drawn by. Nothing is baked that this cannot
--                 name, because a path that does not resolve draws nothing at
--                 all and says nothing about it.
--
-- **The editorial half is eight lines and it is the names.** The book calls a
-- place what a player calls it, which for eight of the forty is not what the
-- client files it under. Everything else binds on the client's own name, or on
-- the part of it after the colon: Blizzard files the four Auchindoun wings and
-- the three Coilfang ones as "Auchindoun: Sethekk Halls" and "Coilfang: The
-- Underbog", and the book, like everybody at a summoning stone, calls them
-- Sethekk Halls and the Underbog.

--------------------------------------------------------------------------
-- The editorial half
--------------------------------------------------------------------------

local CALLED = {
	-- Blizzard's own table drops the article on three of them.
	["The Deadmines"] = "Deadmines",
	["The Stockade"] = "Stormwind Stockade",
	["The Temple of Atal'Hakkar"] = "Sunken Temple",
	-- One place to the client, two runs to everybody else, the same way the
	-- map bake beside this one has to split it.
	["Lower Blackrock Spire"] = "Blackrock Spire",
	["Upper Blackrock Spire"] = "Blackrock Spire",
	-- The one Hellfire wing whose second half is not what the book calls it.
	["Hellfire Ramparts"] = "Hellfire Citadel: Ramparts",
	-- The two Caverns of Time runs are filed under what happens in them rather
	-- than under where they are, which is the only pair in the game named that
	-- way and is why neither rule above reaches them.
	["Old Hillsbrad Foothills"] = "The Escape From Durnholde",
	["The Black Morass"] = "Opening of the Dark Portal",
}

-- What the client files a five man and a raid as. Everything else in the table
-- is a continent, a battleground, an arena, a boat or a test map, and a boat
-- with a loading screen is not a place the book names.
local PARTY, RAID = 1, 2

--------------------------------------------------------------------------

local CSV = dofile("scripts/csv.lua")
local Rows = CSV.Rows

--------------------------------------------------------------------------
-- The book
--------------------------------------------------------------------------

-- Which places the book wants a picture for, in the order it lists them, which
-- is the order a character meets them and the order the shelf lays its cards
-- out in. A wing is the book's own label and the part before the colon is the
-- place, so the four Scarlet Monastery entries ask for one card between them.
local function Wanted()
	local ns = { DungeonBook = {} }
	local chunk = assert(loadfile("src/Dungeons/Baked.lua"))
	chunk("WarriorKit", ns)
	local order, seen = {}, {}
	for _, dungeon in ipairs(ns.DungeonBook.DUNGEONS or {}) do
		local place = dungeon.name:match("^([^:]+)") or dungeon.name
		if not seen[place] then
			seen[place] = true
			order[#order + 1] = place
		end
	end
	return order
end

--------------------------------------------------------------------------
-- The client's instances
--------------------------------------------------------------------------

-- Every instance the 2.5 client has, as the loading screen id it carries, filed
-- under both the name Blizzard gives it and the part of that name after the
-- colon. Both, because the book calls eleven of the fifteen Outland wings by
-- their second half and the client calls none of them that.
--
-- The full name wins where the two collide, which nothing in this book does
-- and which is what stops a wing called after its keep from taking the keep's
-- own card.
local function Screens(maps)
	local out = {}
	for _, map in ipairs(maps) do
		local kind = tonumber(map.InstanceType)
		local screen = tonumber(map.LoadingScreenID)
		if (kind == PARTY or kind == RAID) and screen and screen > 0 then
			local wing = map.MapName_lang:match("^[^:]+:%s*(.+)$")
			if wing and not out[wing] then
				out[wing] = screen
			end
			out[map.MapName_lang] = screen
		end
	end
	return out
end

-- Which file each loading screen is, as the narrow one. There are three columns
-- and on this client only the narrow one is ever filled in: the wide pair were
-- added for widescreen monitors two expansions after this art was drawn, and
-- every row of the 2.5 table carries a zero in both.
local function Files(screens)
	local out = {}
	for _, row in ipairs(screens) do
		local file = tonumber(row.NarrowScreenFileDataID)
		if file and file > 0 then
			out[tonumber(row.ID)] = file
		end
	end
	return out
end

-- Which path each file id is filed under. The manifest carries the folder and
-- the name in two columns and the client wants them joined with its own
-- separator and no extension, which is how every texture Blizzard names in its
-- own code is written.
local function Paths(manifest)
	local out = {}
	for _, row in ipairs(manifest) do
		local path = (row.FilePath .. row.FileName):gsub("/", "\\")
		out[tonumber(row.ID)] = (path:gsub("%.[Bb][Ll][Pp]$", ""))
	end
	return out
end

--------------------------------------------------------------------------

local function Quote(text)
	return '"' .. text:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local function Write(handle, art, order)
	handle:write("\nArt.PLACES = {\n")
	for _, place in ipairs(order) do
		handle:write(("\t[%s] = %s,\n"):format(Quote(place), Quote(art[place])))
	end
	handle:write("}\n")
end

--------------------------------------------------------------------------

local root = ...
if not root then
	io.stderr:write("usage: lua5.1 bake-dungeon-art.lua <path to a folder of exports>\n")
	os.exit(2)
end
root = root:gsub("/$", "")

local function Load(name)
	local held, why = Rows(root .. "/" .. name)
	if not held then
		io.stderr:write(tostring(why) .. "\n")
		os.exit(1)
	end
	return held
end

local screens = Screens(Load("map.csv"))
local files = Files(Load("screens.csv"))
local paths = Paths(Load("files.csv"))

local complaints, art, order = {}, {}, {}

for _, place in ipairs(Wanted()) do
	local called = CALLED[place] or place
	local screen = screens[called]
	local path = screen and paths[files[screen] or -1]
	if not screen then
		complaints[#complaints + 1] =
			("%s: this client has no instance called %q"):format(place, called)
	elseif not path then
		complaints[#complaints + 1] =
			("%s: loading screen %d is in no manifest"):format(place, screen)
	else
		art[place] = path
		order[#order + 1] = place
	end
end

if #complaints > 0 then
	for _, line in ipairs(complaints) do
		io.stderr:write(line .. "\n")
	end
	io.stderr:write(("%d places did not resolve: nothing was written\n"):format(#complaints))
	os.exit(1)
end

local out = assert(io.open("src/Dungeons/Art.lua", "w"))
out:write([[
local ADDON, ns = ...

-- Generated by ./scripts/bake-dungeon-art.sh. Do not hand edit.
--
-- The picture on a dungeon's card, as the loading screen the client has for it.
--
-- The Encounter Journal's art is what retail draws here and the 2.5 client does
-- not ship a byte of it: its interface manifest has no encounterjournal folder
-- at all. What it does ship is the loading screen of every instance in the
-- game, which is a painting of that place by the same artists and the picture a
-- player has already looked at on the way in.
--
-- Nothing here was typed. The instance list and the loading screen each one
-- carries come out of the 2.5 client's own Map table, the file out of
-- LoadingScreens, and the path out of ManifestInterfaceData, all through
-- scripts/bake-dungeon-art.lua. A path nobody generated is a path somebody
-- remembered, and a texture path that does not resolve draws nothing at all and
-- says nothing about it.
--
-- Several places share a picture and that is Blizzard's own filing rather than
-- a gap here: the three Coilfang wings are one screen, the four Auchindoun ones
-- are another, and the two Caverns of Time runs are a third.

local Art = {}
ns.DungeonArt = Art
]])
Write(out, art, order)
out:close()

print(("%d places have a picture"):format(#order))
