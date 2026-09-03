local ADDON, ns = ...

local Seen = {}
ns.DungeonSeen = Seen

--------------------------------------------------------------------------
-- What you have actually seen in a dungeon
--
-- Two things the book cannot carry, both written the same way and both off the
-- same event: where a boss stands, and what came off it.
--
-- **Where a boss stands is not in any database on this machine.** Questie files
-- every creature inside an instance at the coordinate {-1, -1}, which is its
-- way of saying it does not know, and no call on either of these clients will
-- answer it. That is the whole reason the marks on the map are learned rather
-- than shipped. A position typed in from memory is a mark that says a boss is
-- somewhere it is not, on the one screen the player opened to find out, and it
-- would be indistinguishable from a right answer.
--
-- **So the corpse is the source.** Open the loot window on a boss and the
-- client will say which corpse each slot came out of, and where you are
-- standing is where the corpse is, because you walked to it. That is a better
-- number than the death would have given: a boss dies where the tank dragged
-- it, and you loot it where it fell.
--
-- **The drops come off the same window.** The Classic half of the book is
-- complete, because Questie's Classic database carries every creature's whole
-- drop table. The Outland half is nearly empty, because Questie's Burning
-- Crusade database only carries what its own quests need. So a drop the book
-- did not know about is written down the first time you see it, and the right
-- hand column fills itself in from your own runs.
--
-- LOOT_OPENED rather than the chat message, for the reason Quests/Drops.lua
-- gives one folder over: the chat says what you took and the window says what
-- was there, and a boss you walked away from with full bags still dropped it.
--
-- **Nothing here is a fallback for anything.** A client that will not say where
-- you are standing inside an instance records the drops and no position, and
-- the map draws the dungeon with no marks and a line saying which bosses it has
-- not seen you kill. That is the honest picture and it is the picture on the
-- first evening whatever the client answers.
--------------------------------------------------------------------------

local Chart = ns.UI.Chart

-- The most drops one boss's ledger row will hold. A boss has between six and
-- fifteen things on its table and the cap is what stops a row growing without
-- end on a creature that shares a name with something farmed all evening.
local ROOM = 40

local function Ledger()
	local held = ns.db and ns.db.dungeonSeen
	if type(held) ~= "table" then
		return nil
	end
	return held
end

local function Row(id)
	local held = Ledger()
	if not held then
		return nil
	end
	local row = held[id]
	if type(row) ~= "table" then
		row = { drops = {} }
		held[id] = row
	end
	if type(row.drops) ~= "table" then
		row.drops = {}
	end
	return row
end

--------------------------------------------------------------------------

-- Where you are standing, as the map and the two coordinates the chart draws
-- its points in. Nothing at all on a client that will not say, which inside an
-- instance is a real possibility and is why every caller checks.
local function Standing()
	local map, x, y = Chart.Here()
	if type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	return map, x, y
end

-- Write down where this boss was looted.
--
-- The first reading wins. A boss is looted once per run and the position does
-- not move between runs, so a second write would only ever be the same answer
-- or a worse one, and a worse one is what you get when somebody drags a corpse.
function Seen.Place(id, map, x, y)
	local row = Row(id)
	if not row or row.map then
		return false
	end
	row.map, row.x, row.y = map, x, y
	return true
end

-- Write down one drop, as the same { id, name } pair the baked rows are.
--
-- The name is the client's own, out of the link, which means it is in the
-- player's language. That is correct here and would be wrong in the book: the
-- baked name is a checksum against a generated table and has to be the name
-- that table holds, while this one is a row nothing checks because the client
-- is where it came from.
function Seen.Drop(id, itemId, name)
	local row = Row(id)
	if not row or type(itemId) ~= "number" or type(name) ~= "string" then
		return false
	end
	-- Nothing the bake already knows. The ledger is what the book is missing,
	-- which is the whole of what its reading claims, and a boss you run every
	-- week would otherwise write its own table into the saved variables one
	-- item at a time and change nothing on the screen.
	local boss = ns.DungeonBook.Boss(id)
	for _, drop in ipairs(boss and boss.loot or {}) do
		if drop[1] == itemId then
			return false
		end
	end
	for _, drop in ipairs(row.drops) do
		if drop[1] == itemId then
			return false
		end
	end
	if #row.drops >= ROOM then
		return false
	end
	row.drops[#row.drops + 1] = { itemId, name }
	return true
end

--------------------------------------------------------------------------

-- Every corpse in the loot window that the book knows as a boss, with the items
-- that were on it.
--
-- Only bosses. A loot window in a dungeon is mostly trash, and a ledger that
-- recorded every corpse would be a table of five hundred creatures nothing ever
-- reads, kept in the account's saved variables for the life of the install.
local function Bosses()
	local size = _G.GetNumLootItems
	local count = (type(size) == "function" and size()) or 0
	local found = nil
	for slot = 1, count do
		local read = _G.GetLootSourceInfo
		local ok, guid = pcall(read, slot)
		local npcId = (type(read) == "function" and ok) and ns.CreatureId(guid) or nil
		if npcId and ns.DungeonBook.Boss(npcId) then
			found = found or {}
			found[npcId] = found[npcId] or {}
			local link = ns.LootSlotLink(slot)
			local itemId = ns.ItemKind(link)
			if itemId then
				found[npcId][itemId] = (ns.ItemInfo(link)) or ""
			end
		end
	end
	return found
end

-- What the loot window just said, written down. Answers how many bosses it
-- learned something new about, which is what the harness measures.
function Seen.OnLoot()
	local found = Bosses()
	if not found then
		return 0
	end
	local map, x, y = Standing()
	local learned = 0
	for npcId, items in pairs(found) do
		local wrote = false
		if map and Seen.Place(npcId, map, x, y) then
			wrote = true
		end
		for itemId, name in pairs(items) do
			if name ~= "" and Seen.Drop(npcId, itemId, name) then
				wrote = true
			end
		end
		if wrote then
			learned = learned + 1
		end
	end
	if learned > 0 then
		ns.DungeonWindow.Refresh()
	end
	return learned
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("LOOT_OPENED")
events:SetScript("OnEvent", function()
	Seen.OnLoot()
end)

--------------------------------------------------------------------------

-- How much of the ledger there is: bosses placed on a map, and drops learned
-- that the bake did not know about.
function Seen.Count()
	local placed, drops = 0, 0
	for _, row in pairs(Ledger() or {}) do
		if type(row) == "table" then
			if type(row.map) == "number" then
				placed = placed + 1
			end
			drops = drops + #(row.drops or {})
		end
	end
	return placed, drops
end

-- Everything forgotten, which is the one thing a ledger of measurements needs
-- and a preference does not: a position learned on a client that answered
-- rubbish is a wrong mark that never comes off on its own.
function Seen.Forget()
	if not ns.db then
		return false
	end
	ns.db.dungeonSeen = {}
	ns.DungeonWindow.Refresh()
	return true
end

function Seen.Describe()
	local placed, drops = Seen.Count()
	if placed == 0 and drops == 0 then
		return "nothing yet: a boss is placed on the map and its drops written down the first time you loot it"
	end
	return ("%d bosses placed by looting them, %d drops the book did not have")
		:format(placed, drops)
end
