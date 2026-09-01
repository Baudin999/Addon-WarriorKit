local ADDON, ns = ...

-- Everything Core and the panel need to know about the adventure guide.
-- Book.lua, Baked.lua, Sheets.lua, Art.lua, Places.lua, Loot.lua, Seen.lua,
-- Here.lua, Shelf.lua, Window.lua and Key.lua hold the behaviour, and this is
-- the only file in the folder that names anything outside it.

local function SetDungeons(value)
	ns.db.dungeons = value
	if value then
		ns.DungeonWindow.Build()
	else
		ns.DungeonWindow.Hide()
	end
	ns.DungeonKey.Apply()
end

--------------------------------------------------------------------------
-- The slash word
--------------------------------------------------------------------------

local function DungeonWord(arg, rawArg)
	local word, rest = arg:match("^(%S*)%s*(.-)$")

	if word == "key" then
		local key = rest:upper()
		if key == "NONE" then
			key = ""
		end
		local displaced, why = ns.DungeonKey.Bind(key)
		if not displaced then
			ns.Print(why)
		elseif key == "" then
			ns.Print("the dungeon log has no key now.")
		elseif displaced ~= "" then
			ns.Print(("%s opens the dungeon log. It shadows %s, and your saved bindings are untouched.")
				:format(key, displaced))
		else
			ns.Print(("%s opens the dungeon log. Nothing else was bound to it."):format(key))
		end
	elseif word == "book" then
		ns.Print(ns.DungeonBook.Describe() .. ".")
	elseif word == "maps" then
		ns.Print(ns.DungeonPlaces.Describe() .. ".")
	elseif word == "shelf" then
		ns.Print(ns.DungeonShelf.Describe() .. ".")
	elseif word == "seen" then
		ns.Print(ns.DungeonSeen.Describe() .. ".")
	elseif word == "here" then
		ns.Print(ns.DungeonHere.Describe() .. ".")
	elseif word == "forget" then
		ns.DungeonSeen.Forget()
		ns.Print("every boss position and every drop you had seen is gone.")
	elseif word == "on" or word == "off" then
		SetDungeons(word == "on")
		ns.Print("the dungeon log is " .. (ns.db.dungeons and "on" or "off") .. ".")
	elseif word == "" then
		if not ns.db.dungeons then
			ns.Print("the dungeon log is off. Type /wk dungeons on.")
			return
		end
		ns.DungeonWindow.Toggle()
	else
		ns.Print("dungeons takes on, off, key, book, maps, shelf, seen, here or forget.")
	end
	return rawArg
end

--------------------------------------------------------------------------

ns.Register({
	name = "dungeons",
	order = 29,

	switch = {
		key = "dungeons",
		label = "the dungeon log",
		apply = function(value) SetDungeons(value) end,
	},

	defaults = {
		-- On. There is no window on either client this replaces, so nothing is
		-- taken away by it being on, and the key it holds is one nothing else
		-- uses.
		dungeons = true,

		-- Shift-L, because L is the log key and this is the other log.
		--
		-- An override rather than a real binding, so a player's own binding
		-- file is never written to. Dungeons/Key.lua carries the argument.
		dungeonKey = "SHIFT-L",

		-- What that key was bound to before this took it, so the panel can say
		-- what is being shadowed rather than the player finding out.
		dungeonKeyDisplaced = "",

		-- Where each boss stands and what you have watched come off it, keyed
		-- by creature id. Empty, and filled in by looting. It is kept out of the
		-- reset in Core/Core.lua for the reason the quest log's drop ledger is:
		-- it is a record of what you have seen and not a preference.
		dungeonSeen = {},
	},

	words = {
		dungeons = DungeonWord,
	},

	help = {
		"dungeons, open the dungeon log",
		"dungeons on|off, the dungeon log and the key that opens it",
		"dungeons key <key|none>, which key opens it",
		"dungeons book, how many dungeons, bosses and drops the book has",
		"dungeons maps, whether this client has a map for each dungeon",
		"dungeons shelf, whether this client has a picture for each dungeon",
		"dungeons seen, how much the ledger has learned from your own runs",
		"dungeons here, which dungeon the window would open on where you stand",
		"dungeons forget, throw the ledger away",
	},

	status = function()
		return ("%s; %s; opens on %s"):format(
			ns.DungeonWindow.Describe(), ns.DungeonBook.Describe(),
			ns.DungeonKey.Describe())
	end,

	panel = function(ui)
		ui.Section("Dungeons", "Chores")
		ui.Lede("A shelf of dungeons, each wearing its own loading screen. Click one for its bosses, its map with them marked, and what they drop. Right click to come back.")
		ui.Check("the dungeon log",
			function() return ns.db.dungeons end,
			SetDungeons)
		ui.Hint("Neither of these clients ships an adventure guide, so nothing is being replaced and no key is being taken off the client.")
		ui.KeyField("key",
			function()
				if (ns.db.dungeonKey or "") ~= "" then
					return ns.db.dungeonKey
				end
				return "|cff808080not bound|r"
			end,
			function(combo)
				local ok, why = ns.DungeonKey.Bind(combo)
				if not ok and why then
					ns.Print(why)
				end
			end,
			function() ns.DungeonKey.Bind("") end)
		ui.Hint("Shift-L out of the box, and an override, so whatever you had on the key comes back the moment this is unbound. The map key opens this window too, on the dungeon you are standing in.")
		ui.Action(function() return "forget every boss you have placed" end,
			function() ns.DungeonSeen.Forget() end)
		ui.Hint("The marks on the map are where you were standing when you looted each boss, because nothing on either client will say where a boss stands. Forget them and they are learned again on your next run.")
		ui.Reading("the book", ns.DungeonBook.Describe)
		ui.Reading("the dungeon maps", ns.DungeonPlaces.Describe)
		ui.Reading("the shelf", ns.DungeonShelf.Describe)
		ui.Reading("what your own runs have added", ns.DungeonSeen.Describe)
		ui.Reading("where you are standing", ns.DungeonHere.Describe)
		ui.Reading("the drops on the boss you are reading", ns.DungeonLoot.Describe)
		ui.Reading("the key", ns.DungeonKey.Describe)
		ui.Reading("this window", ns.DungeonWindow.Describe)
	end,
})
