-- Bakes src/Dungeons/Baked.lua out of Questie's own databases.
--
--   lua5.1 scripts/bake-dungeons.lua <path to a Questie folder>
--
-- Run through scripts/bake-dungeons.sh, which finds Questie and checks the
-- result. Everything this file knows is in one of two places and the split is
-- the whole point.
--
-- **The editorial half is here.** Which dungeons there are, what order their
-- bosses are fought in, and what level range each place is for. That is a
-- judgement, it is written out by hand below, and none of it is a number.
--
-- **Every number comes out of Questie.** A boss's creature id, its level, and
-- the item id and name of everything it drops are read from Questie's npcDB
-- and itemDB, which are generated from the client's own database rather than
-- typed by anybody. A boss name below that Questie does not have in that
-- dungeon is an error that stops the bake, so the editorial half is checked
-- against the generated half every time this runs. That is the only reason it
-- is safe to write a boss list by hand at all.
--
-- What is deliberately not here is where a boss stands. Questie files every
-- creature inside an instance at the coordinate {-1, -1}, which is its way of
-- saying it does not know, and there is no other source on this machine. So
-- the addon learns those from where you were standing when the boss died, and
-- Dungeons/Book.lua carries that side.

--------------------------------------------------------------------------
-- The editorial half
--
-- One entry per dungeon, in the order a character meets them. `zone` is
-- Questie's areaID for the instance, which is what its spawn tables are keyed
-- on. `bosses` are the creature names in the order they are fought, spelled
-- exactly as the client spells them, which the bake checks.
--------------------------------------------------------------------------

local CLASSIC = {
	{ name = "Ragefire Chasm", zone = 2437, low = 13, high = 18, bosses = {
		"Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan",
	} },
	{ name = "Wailing Caverns", zone = 718, low = 17, high = 24, bosses = {
		"Lady Anacondra", "Lord Cobrahn", "Kresh", "Lord Pythas", "Skum",
		"Lord Serpentis", "Verdan the Everliving", "Mutanus the Devourer",
	} },
	{ name = "The Deadmines", zone = 1581, low = 17, high = 26, bosses = {
		"Rhahk'Zor", "Miner Johnson", "Sneed's Shredder", "Gilnid", "Mr. Smite",
		"Captain Greenskin", "Edwin VanCleef", "Cookie",
	} },
	{ name = "Shadowfang Keep", zone = 209, low = 22, high = 30, bosses = {
		"Rethilgore", "Fenrus the Devourer", "Razorclaw the Butcher",
		"Baron Silverlaine", "Commander Springvale", "Odo the Blindwatcher",
		"Deathsworn Captain", "Wolf Master Nandos", "Archmage Arugal",
	} },
	{ name = "Blackfathom Deeps", zone = 719, low = 24, high = 32, bosses = {
		"Ghamoo-ra", "Lady Sarevess", "Gelihast", "Baron Aquanis",
		"Twilight Lord Kelris", "Old Serra'kis", "Aku'mai",
	} },
	{ name = "The Stockade", zone = 717, low = 24, high = 32, bosses = {
		"Targorr the Dread", "Kam Deepfury", "Hamhock", "Bazil Thredd",
		"Dextren Ward", "Bruegal Ironknuckle",
	} },
	{ name = "Gnomeregan", zone = 721, low = 29, high = 38, bosses = {
		"Grubbis", "Viscous Fallout", "Electrocutioner 6000",
		"Crowd Pummeler 9-60", "Mekgineer Thermaplugg",
	} },
	{ name = "Razorfen Kraul", zone = 491, low = 29, high = 38, bosses = {
		"Roogug", "Aggem Thorncurse", "Death Speaker Jargba",
		"Overlord Ramtusk", "Agathelos the Raging", "Charlga Razorflank",
	} },
	{ name = "Scarlet Monastery: Graveyard", zone = 796, low = 26, high = 36, bosses = {
		"Interrogator Vishas", "Bloodmage Thalnos",
	} },
	{ name = "Scarlet Monastery: Library", zone = 796, low = 29, high = 39, bosses = {
		"Houndmaster Loksey", "Arcanist Doan",
	} },
	{ name = "Scarlet Monastery: Armory", zone = 796, low = 32, high = 42, bosses = {
		"Herod",
	} },
	{ name = "Scarlet Monastery: Cathedral", zone = 796, low = 35, high = 45, bosses = {
		"High Inquisitor Fairbanks", "Scarlet Commander Mograine",
		"High Inquisitor Whitemane",
	} },
	{ name = "Razorfen Downs", zone = 722, low = 33, high = 45, bosses = {
		"Tuten'kash", "Mordresh Fire Eye", "Glutton", "Ragglesnout",
		"Plaguemaw the Rotting", "Amnennar the Coldbringer",
	} },
	{ name = "Uldaman", zone = 1337, low = 36, high = 46, bosses = {
		"Revelosh", "Baelog", "Ironaya", "Obsidian Sentinel",
		"Ancient Stone Keeper", "Galgann Firehammer", "Grimlok", "Archaedas",
	} },
	{ name = "Zul'Farrak", zone = 1176, low = 42, high = 50, bosses = {
		"Antu'sul", "Theka the Martyr", "Witch Doctor Zum'rah",
		"Nekrum Gutchewer", "Shadowpriest Sezz'ziz", "Sergeant Bly",
		"Hydromancer Velratha", "Gahz'rilla", "Chief Ukorz Sandscalp", "Zerillis",
	} },
	{ name = "Maraudon", zone = 2100, low = 46, high = 55, bosses = {
		"Noxxion", "Razorlash", "Lord Vyletongue", "Meshlok the Harvester",
		"Celebras the Cursed", "Landslide", "Tinkerer Gizlock", "Rotgrip",
		"Princess Theradras",
	} },
	{ name = "The Temple of Atal'Hakkar", zone = 1477, low = 50, high = 60, bosses = {
		"Atal'alarion", "Dreamscythe", "Weaver", "Hazzas", "Morphaz",
		"Jammal'an the Prophet", "Ogom the Wretched", "Shade of Eranikus",
		"Avatar of Hakkar",
	} },
	{ name = "Blackrock Depths", zone = 1584, low = 52, high = 60, bosses = {
		"Lord Roccor", "Bael'Gar", "Houndmaster Grebmar",
		"High Interrogator Gerstahn", "Pyromancer Loregrain", "Lord Incendius",
		"Warder Stilgiss", "Fineous Darkvire", "Verek", "Golem Lord Argelmach",
		"Hurley Blackbreath", "Phalanx", "Plugger Spazzring",
		"Ambassador Flamelash", "Panzor the Invincible", "Magmus",
		"General Angerforge", "Emperor Dagran Thaurissan",
	} },
	{ name = "Lower Blackrock Spire", zone = 1583, low = 55, high = 60, bosses = {
		"Highlord Omokk", "Shadow Hunter Vosh'gajin", "War Master Voone",
		"Mother Smolderweb", "Urok Doomhowl", "Quartermaster Zigris",
		"Halycon", "Gizrul the Slavener", "Overlord Wyrmthalak",
	} },
	{ name = "Upper Blackrock Spire", zone = 1583, low = 58, high = 60, bosses = {
		"Pyroguard Emberseer", "Solakar Flamewreath", "Goraluk Anvilcrack",
		"Jed Runewatcher", "Warchief Rend Blackhand", "Gyth", "The Beast",
		"General Drakkisath",
	} },
	{ name = "Dire Maul: East", zone = 2557, low = 55, high = 60, bosses = {
		"Pusillin", "Zevrim Thornhoof", "Hydrospawn", "Lethtendris",
		"Alzzin the Wildshaper",
	} },
	{ name = "Dire Maul: West", zone = 2557, low = 55, high = 60, bosses = {
		"Tendris Warpwood", "Illyanna Ravenoak", "Magister Kalendris",
		"Tsu'zee", "Immol'thar", "Prince Tortheldrin",
	} },
	{ name = "Dire Maul: North", zone = 2557, low = 57, high = 60, bosses = {
		"Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik",
		"Captain Kromcrush", "Cho'Rush the Observer", "King Gordok",
	} },
	{ name = "Scholomance", zone = 2057, low = 58, high = 60, bosses = {
		"Kirtonos the Herald", "Jandice Barov", "Rattlegore", "Marduk Blackpool",
		"Vectus", "Ras Frostwhisper", "Instructor Malicia",
		"Doctor Theolen Krastinov", "Lorekeeper Polkelt", "The Ravenian",
		"Lord Alexei Barov", "Lady Illucia Barov", "Darkmaster Gandling",
	} },
	{ name = "Stratholme", zone = 2017, low = 58, high = 60, bosses = {
		"Skul", "Fras Siabi", "Hearthsinger Forresten", "The Unforgiven",
		"Timmy the Cruel", "Malor the Zealous", "Cannon Master Willey",
		"Archivist Galford", "Balnazzar", "Magistrate Barthilas", "Stonespine",
		"Nerub'enkan", "Maleki the Pallid", "Baroness Anastari",
		"Ramstein the Gorger", "Baron Rivendare",
	} },
}

local TBC = {
	{ name = "Hellfire Ramparts", zone = 3562, low = 59, high = 62, bosses = {
		"Watchkeeper Gargolmar", "Omor the Unscarred", "Vazruden", "Nazan",
	} },
	{ name = "The Blood Furnace", zone = 3713, low = 60, high = 63, bosses = {
		"The Maker", "Broggok", "Keli'dan the Breaker",
	} },
	{ name = "The Slave Pens", zone = 3717, low = 61, high = 64, bosses = {
		"Mennu the Betrayer", "Rokmar the Crackler", "Quagmirran",
	} },
	{ name = "The Underbog", zone = 3716, low = 62, high = 65, bosses = {
		"Hungarfen", "Ghaz'an", "Swamplord Musel'ek", "The Black Stalker",
	} },
	{ name = "Mana-Tombs", zone = 3792, low = 64, high = 67, bosses = {
		"Pandemonius", "Tavarok", "Nexus-Prince Shaffar",
	} },
	{ name = "Auchenai Crypts", zone = 3790, low = 65, high = 68, bosses = {
		"Shirrak the Dead Watcher", "Exarch Maladaar",
	} },
	{ name = "Old Hillsbrad Foothills", zone = 2367, low = 66, high = 68, bosses = {
		"Lieutenant Drake", "Captain Skarloc", "Epoch Hunter",
	} },
	{ name = "Sethekk Halls", zone = 3791, low = 67, high = 69, bosses = {
		"Darkweaver Syth", "Talon King Ikiss",
	} },
	{ name = "The Steamvault", zone = 3715, low = 68, high = 70, bosses = {
		"Hydromancer Thespia", "Mekgineer Steamrigger", "Warlord Kalithresh",
	} },
	{ name = "The Black Morass", zone = 2366, low = 68, high = 70, bosses = {
		"Chrono Lord Deja", "Temporus", "Aeonus",
	} },
	{ name = "Shadow Labyrinth", zone = 3789, low = 69, high = 70, bosses = {
		"Ambassador Hellmaw", "Blackheart the Inciter", "Grandmaster Vorpil",
		"Murmur",
	} },
	{ name = "The Shattered Halls", zone = 3714, low = 69, high = 70, bosses = {
		"Grand Warlock Nethekurse", "Blood Guard Porung", "Warbringer O'mrogg",
		"Warchief Kargath Bladefist",
	} },
	{ name = "The Mechanar", zone = 3849, low = 69, high = 70, bosses = {
		"Gatewatcher Gyro-Kill", "Gatewatcher Iron-Hand",
		"Mechano-Lord Capacitus", "Nethermancer Sepethrea",
		"Pathaleon the Calculator",
	} },
	{ name = "The Botanica", zone = 3847, low = 70, high = 70, bosses = {
		"Commander Sarannis", "High Botanist Freywinn", "Thorngrin the Tender",
		"Laj", "Warp Splinter",
	} },
	{ name = "The Arcatraz", zone = 3848, low = 70, high = 70, bosses = {
		"Zereketh the Unbound", "Dalliah the Doomsayer",
		"Wrath-Scryer Soccothrates", "Harbinger Skyriss",
	} },
}

-- How many creatures a drop may be shared with before it stops being this
-- boss's loot and starts being something that falls off anything in the game.
-- Cloth is on eight hundred creatures, a stack of milk on four hundred, and the
-- items an adventure guide exists to show are on one. Eight is well clear of
-- both ends and is the only number in this file that is a judgement about data
-- rather than about dungeons.
local SHARED = 8

-- Item classes that are never worth a row. 0 is a consumable and 7 is a trade
-- good, which between them are every stack of bread, milk and cloth that
-- survives the count above.
local JUNK = { [0] = true, [7] = true }

--------------------------------------------------------------------------
-- Questie, read
--------------------------------------------------------------------------

local function Slurp(path)
	local handle = io.open(path, "r")
	if not handle then
		return nil
	end
	local text = handle:read("*a")
	handle:close()
	return text
end

-- One of Questie's generated tables. Each is a Lua table written inside a long
-- string in the file that declares it, which is how Questie keeps it out of the
-- chunk's constant table, so it is pulled out and run rather than parsed.
local function Table(path, key)
	local text = Slurp(path)
	if not text then
		return nil, path .. " is not there"
	end
	local body = text:match(key .. "%s*=%s*%[%[(return .-)%]%]")
	if not body then
		return nil, path .. " has no " .. key .. " in it"
	end
	local chunk, why = loadstring(body)
	if not chunk then
		return nil, why
	end
	return chunk()
end

--------------------------------------------------------------------------

-- Questie's own column numbers, named rather than counted at each use.
local NPC_NAME, NPC_HEALTH, NPC_LOW, NPC_RANK, NPC_SPAWNS = 1, 3, 4, 6, 7
local ITEM_NAME, ITEM_DROPS, ITEM_LEVEL, ITEM_REQUIRES, ITEM_CLASS = 1, 2, 9, 10, 12

-- Every area that is part of one instance.
--
-- An instance is not one area. Blackrock Depths is nineteen of them, the Sunken
-- Temple is six, and Questie files a creature under whichever wing it stands
-- in rather than under the dungeon. So the dungeon's areaID is expanded through
-- Questie's own sub-area table, transitively, and a boss is looked for in the
-- whole family. Written as a walk rather than one lookup because the tree is
-- two deep in places: a wing of a wing.
local function Family(parents, zone)
	local family, added = { [zone] = true }, true
	while added do
		added = false
		for child, parent in pairs(parents) do
			if family[parent] and not family[child] then
				family[child] = true
				added = true
			end
		end
	end
	return family
end

-- Every creature of that name standing anywhere in that instance. A name rather
-- than an id because the editorial half above is a list of names, and more than
-- one answer is a real possibility: several dungeons hold two creatures of one
-- name and only one of them is the boss.
local function Find(npcs, family, name)
	local zoned, called = {}, {}
	for id, npc in pairs(npcs) do
		if npc[NPC_NAME] == name then
			called[#called + 1] = id
			local spawns = npc[NPC_SPAWNS]
			for zone in pairs(spawns or {}) do
				if family[zone] then
					zoned[#zoned + 1] = id
					break
				end
			end
		end
	end
	table.sort(zoned)
	table.sort(called)
	-- Standing in the dungeon is the answer wherever Questie has one. Where it
	-- has none, the name on its own is: about a fifth of the bosses in the game
	-- carry no spawn row at all, because they are summoned, walled in behind an
	-- event, or simply missing from the dump, and every one of those has
	-- `spawns = nil` and `zoneID = 0`. A name with exactly one creature behind
	-- it in the whole game is not an ambiguity, and a name with two is refused
	-- below rather than guessed at.
	if #zoned > 0 then
		return zoned, "in the dungeon"
	end
	-- Where the name is on more than one creature and none of them is placed,
	-- the biggest one is the boss. That is not a guess about the game, it is
	-- what the copies are: Harbinger Skyriss splits into two illusions of
	-- himself, each carrying the same name and a tenth of the health, and the
	-- only thing in the row that separates them is the number.
	table.sort(called, function(a, b)
		return (npcs[a][NPC_HEALTH] or 0) > (npcs[b][NPC_HEALTH] or 0)
	end)
	if #called > 1 and (npcs[called[1]][NPC_HEALTH] or 0) == (npcs[called[2]][NPC_HEALTH] or 0) then
		return {}, "shared by equals"
	end
	return called, "by name alone"
end

-- What one creature drops that is worth a row. Sorted by what the client will
-- ask for it, highest first, which is the order an adventure guide reads in.
local function Drops(items, npc)
	local out = {}
	for id, item in pairs(items) do
		local drops = item[ITEM_DROPS]
		if drops and #drops <= SHARED and not JUNK[item[ITEM_CLASS] or -1] then
			for _, who in ipairs(drops) do
				if who == npc then
					out[#out + 1] = {
						id = id,
						name = item[ITEM_NAME],
						level = item[ITEM_LEVEL] or 0,
						requires = item[ITEM_REQUIRES] or 0,
					}
					break
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.level ~= b.level then
			return a.level > b.level
		end
		return a.name < b.name
	end)
	return out
end

--------------------------------------------------------------------------

local function Quote(text)
	return '"' .. text:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

-- One dungeon, resolved against Questie. Anything that will not resolve is
-- returned as a complaint rather than dropped, because a boss the bake could
-- not find is a mistake in the list above and not a fact about the game.
local function Resolve(entry, npcs, items, parents, complaints)
	local out = { name = entry.name, low = entry.low, high = entry.high, bosses = {} }
	local family = Family(parents, entry.zone)
	for order, name in ipairs(entry.bosses) do
		local found, how = Find(npcs, family, name)
		if #found == 0 then
			complaints[#complaints + 1] =
				("%s: nothing in the game is called %q"):format(entry.name, name)
		elseif how == "shared by equals" then
			complaints[#complaints + 1] =
				("%s: %q is on more than one creature and nothing tells them apart"):format(entry.name, name)
		else
			local npc = npcs[found[1]]
			local loot = Drops(items, found[1])
			out.bosses[order] = {
				id = found[1],
				name = name,
				level = npc[NPC_LOW] or 0,
				rank = npc[NPC_RANK] or 0,
				loot = loot,
			}
		end
	end
	return out
end

local function Write(handle, dungeons)
	handle:write("\nBook.DUNGEONS = {\n")
	for _, dungeon in ipairs(dungeons) do
		handle:write(("\t{ name = %s, era = %s, low = %d, high = %d, bosses = {\n")
			:format(Quote(dungeon.name), Quote(dungeon.era), dungeon.low, dungeon.high))
		for _, boss in ipairs(dungeon.bosses) do
			handle:write(("\t\t{ id = %d, name = %s, level = %d, loot = {\n")
				:format(boss.id, Quote(boss.name), boss.level))
			for _, item in ipairs(boss.loot) do
				handle:write(("\t\t\t{ %d, %s },\n"):format(item.id, Quote(item.name)))
			end
			handle:write("\t\t} },\n")
		end
		handle:write("\t} },\n")
	end
	handle:write("}\n")
end

--------------------------------------------------------------------------

local root = ...
if not root then
	io.stderr:write("usage: lua5.1 bake-dungeons.lua <path to a Questie folder>\n")
	os.exit(2)
end
root = root:gsub("/$", "")

-- Which area is inside which, for every area in the game. Two tables in one
-- file, the second overriding the first, which is Questie's own arrangement.
local parents = {}
for _, key in ipairs({ "subZoneToParentZone", "subZoneToParentZoneOverride" }) do
	local held, why = Table(root .. "/Database/Zones/data/subZoneToParentZone.lua",
		"ZoneDB%.private%." .. key)
	if not held then
		io.stderr:write(tostring(why) .. "\n")
		os.exit(1)
	end
	for child, parent in pairs(held) do
		parents[child] = parent
	end
end

local complaints = {}
local baked, counts = {}, {}

for _, flavour in ipairs({
	{ era = "classic", list = CLASSIC, dir = "Classic", stem = "classic" },
	{ era = "tbc", list = TBC, dir = "TBC", stem = "tbc" },
}) do
	local npcs, why = Table(("%s/Database/%s/%sNpcDB.lua"):format(root, flavour.dir, flavour.stem),
		"QuestieDB%.npcData")
	if not npcs then
		io.stderr:write(tostring(why) .. "\n")
		os.exit(1)
	end
	local items
	items, why = Table(("%s/Database/%s/%sItemDB.lua"):format(root, flavour.dir, flavour.stem),
		"QuestieDB%.itemData")
	if not items then
		io.stderr:write(tostring(why) .. "\n")
		os.exit(1)
	end

	local bosses, loot, seen = 0, 0, 0
	for _, entry in ipairs(flavour.list) do
		local dungeon = Resolve(entry, npcs, items, parents, complaints)
		dungeon.era = flavour.era
		baked[#baked + 1] = dungeon
		seen = seen + 1
		for _, boss in ipairs(dungeon.bosses) do
			bosses = bosses + 1
			loot = loot + #boss.loot
		end
	end
	counts[#counts + 1] = ("%s: %d dungeons, %d bosses, %d drops")
		:format(flavour.era, seen, bosses, loot)
end

if #complaints > 0 then
	for _, line in ipairs(complaints) do
		io.stderr:write(line .. "\n")
	end
	io.stderr:write(("%d boss names did not resolve: nothing was written\n"):format(#complaints))
	os.exit(1)
end

local out = assert(io.open("src/Dungeons/Baked.lua", "w"))
out:write([[
local ADDON, ns = ...

-- Generated by ./scripts/bake-dungeons.sh. Do not hand edit.
--
-- Which dungeons there are and what order their bosses are fought in is written
-- out by hand in scripts/bake-dungeons.lua. Every number below -- each creature
-- id, each level, each item id and each item name -- is read out of Questie's
-- own generated databases, which come from the client rather than from anybody
-- typing them. A boss name in that list that Questie cannot find in that
-- instance stops the bake, so the two halves check each other.
--
-- Where a boss stands is not here. Questie files every creature inside an
-- instance at {-1, -1}, which is its way of saying it does not know, so the
-- addon learns a position from where you were standing when the boss died.
-- Dungeons/Book.lua carries that side.

local Book = ns.DungeonBook
]])
Write(out, baked)
out:close()

for _, line in ipairs(counts) do
	print(line)
end
