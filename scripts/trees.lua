-- Which tree is allowed to name which, read off the source rather than trusted.
--
-- The addon is one namespace. Every file writes what it owns into `ns` and
-- reaches everything else through the same table, which means nothing in the
-- language stops Mail from calling into Bags or Character from calling into
-- Buttons. The architecture that says it should not was a sentence in a comment
-- in Core/Piles.lua, and a sentence is not a gate: by the time this file was
-- written there were thirty edges crossing trees that nobody had decided on.
--
-- One of them is worth naming because it is the whole argument. The mail window
-- wanted an item grid; the grid was parked in Bags because bags needed it first;
-- so Mail/Bags.lua names ns.BagsGrid. Nobody chose that. What should have
-- happened is that the grid moved to UI where both windows could see it, and the
-- only thing that would have forced the question is a gate refusing the shortcut.
--
--   lua5.1 ../scripts/trees.lua <file> [file...]      run from src/
--   TREES_REPORT=1 lua5.1 ../scripts/trees.lua ...    the edges, for seeding
--
-- Prints one line per violation and exits 1 if there were any.

--------------------------------------------------------------------------
-- The base
--------------------------------------------------------------------------

-- The six trees a feature may name freely, and they are not a preference. A
-- base tree is one that many trees depend on and that depends on nothing
-- outside the base, and both halves are measured. Run with TREES_REPORT=1 for
-- the table this was read off:
--
--   Core   32 trees name it, and it names UI and Class
--   UI     32 trees name it, and it names Ck, Perf and Unit
--   Unit   13 trees name it, and it names nothing at all
--   Class  10 trees name it, and it names Unit
--   Perf    9 trees name it, and it names Core and UI
--   Ck      4 trees name it, and it names UI
--
-- Two trees look like base from the in-degree alone and are not. UnitFrames is
-- named by nine, and eight of those are ns.BlizzHide, which is a switchboard
-- over Core/Attic.lua that ended up in UnitFrames because unit frames wanted it
-- first. Buttons is named by six while itself naming six. A tree that reaches
-- into half the addon is a hub, not a floor, and calling one base would exempt
-- every edge into it including the ones worth refusing.
--
-- Marking is the other side of the same test. It is a service by shape and
-- exactly one tree has ever asked it anything, so it stays a feature and that
-- one edge is written down below where it can be read.
local BASE = {
	Core = true, UI = true, Ck = true, Class = true, Unit = true, Perf = true,
}

local BASE_WORDS = "Core, UI, Ck, Class, Unit and Perf"

--------------------------------------------------------------------------
-- The exemptions
--------------------------------------------------------------------------

-- Every edge that crosses trees today, with the number of times it is named and
-- why it is allowed. Three rules hold this list honest, and they are the rules
-- scripts/shape.lua's list keeps, for the same reasons.
--
-- An entry needs a reason. An edge nobody explained is the invisible debt this
-- file exists to make visible, so a missing `why` fails like a violation.
--
-- An entry ratchets, in both directions and by two files. An edge named fewer
-- times than its entry claims fails here until the number comes down, so
-- deleting a call cannot be spent quietly on room to add another. A number that
-- goes up fails in scripts/ratchet.lua, which reads the committed copy of this
-- file and refuses the edit that raises a ceiling to meet the code that just
-- broke it.
--
-- An entry that matches nothing fails. An edge removed leaves its entry behind,
-- and an allow-list full of permissions for code that no longer exists is a list
-- nobody can read as a work list.
--
-- Read as a work list, the entries fall into four kinds.
--
-- A service in the wrong tree. ns.BlizzHide answers one question for the whole
-- addon and eight trees ask it; ns.Castable answers whether a spell is ready
-- and three do. Neither is a fact about the tree it lives in. These come off
-- the list by moving the file, not by editing the code that calls it.
--
-- A window naming another window's widget. Mail -> Bags and Bags -> Mail are
-- the pair, and they point at a grid that belongs in UI. Settings -> Character
-- is the same shape one layer up.
--
-- Two features that genuinely are one feature. Hover and Buttons name each
-- other because a key that casts on what the mouse is over is a binding on a
-- bar square; there is no version of that where one of them does not know
-- about the other. This kind is what an allow-list is actually for.
--
-- A feature reading another feature's data. Map -> Quests, UnitFrames ->
-- Quests, Mail -> Feeds. These are honest dependencies between things that are
-- separately useful, and the entry is the documentation.
local ALLOWED = {
	-- A service in the wrong tree.
	{ from = "Character", sym = "BlizzHide", uses = 2,
	  why = "the sheet takes the client's character frame off the screen" },
	{ from = "Talents", sym = "BlizzHide", uses = 2,
	  why = "the talent window takes the client's off the screen" },
	{ from = "Spellbook", sym = "BlizzHide", uses = 2,
	  why = "the spell book takes the client's off the screen" },
	{ from = "Progress", sym = "BlizzHide", uses = 1,
	  why = "the level bar takes the client's own off the screen" },
	{ from = "Bags", sym = "BlizzHide", uses = 1,
	  why = "the bag window takes the client's bags off the screen" },
	{ from = "Chat", sym = "BlizzHide", uses = 1,
	  why = "the chat window takes the client's frames off the screen" },
	{ from = "Merchant", sym = "BlizzHide", uses = 1,
	  why = "the merchant window takes the client's off the screen" },
	{ from = "Map", sym = "BlizzHide", uses = 1,
	  why = "the map takes the client's world map off the screen" },
	{ from = "Buffs", sym = "Castable", uses = 2,
	  why = "the racial nag asks whether the racial is off cooldown" },
	{ from = "AdHoc", sym = "Castable", uses = 1,
	  why = "a loadout square asks whether the spell on it is ready" },
	{ from = "Cooldowns", sym = "Castable", uses = 1,
	  why = "a cooldown row asks whether the ability on it is ready" },

	-- A window naming another window's widget.
	{ from = "Mail", sym = "BagsGrid", uses = 2,
	  why = "the attachment picker reads the bag window's own squares" },
	{ from = "Bags", sym = "MailBags", uses = 1,
	  why = "a bag square dresses itself for the mail window that is open over it" },
	{ from = "Settings", sym = "Compare", uses = 4,
	  why = "the options panel owns the switch for the sheet's compare tooltip" },
	{ from = "Meter", sym = "BreakdownWindow", uses = 1,
	  why = "a meter row opens the breakdown for the fight it is showing" },
	{ from = "Character", sym = "BarTrace", uses = 5,
	  why = "the sheet's trace reuses the bar trace's frame naming" },

	-- Two features that are one feature.
	{ from = "Buttons", sym = "Hover", uses = 2,
	  why = "a bar square draws the hover key that is lent to it" },
	{ from = "Hover", sym = "Bars", uses = 2,
	  why = "hover casting rebinds the bar squares it borrows keys from" },
	{ from = "AdHoc", sym = "Hover", uses = 1,
	  why = "a loadout square asks what the hover key is carrying" },
	{ from = "Bags", sym = "Wanted", uses = 5,
	  why = "the bag window's filter is Comfort's list of what you keep" },
	{ from = "Bags", sym = "Destroy", uses = 3,
	  why = "the bag window's delete row is Comfort's" },
	{ from = "Bags", sym = "Vendor", uses = 2,
	  why = "the merchant row sells greys through Comfort's seller" },
	{ from = "Bags", sym = "Repair", uses = 3,
	  why = "the merchant row pays for mending through Comfort's" },

	-- A feature reading another feature's data.
	{ from = "Map", sym = "QuestWhere", uses = 1,
	  why = "the map pins the quest log's own answer for where a quest is" },
	{ from = "Map", sym = "QuestClient", uses = 1,
	  why = "the map reads which turn-ins the quest log knows about" },
	{ from = "Map", sym = "DungeonHere", uses = 1,
	  why = "the map asks whether you are standing in a dungeon it has a map for" },
	{ from = "Map", sym = "DungeonWindow", uses = 1,
	  why = "the map opens the dungeon log for the dungeon you are in" },
	{ from = "UnitFrames", sym = "QuestDrops", uses = 2,
	  why = "an enemy bar says what the mob on it drops for a quest you are on" },
	{ from = "Character", sym = "Upkeep", uses = 1,
	  why = "the sheet reads which weapon enchant the buff watcher is tracking" },
	{ from = "UnitFrames", sym = "Upkeep", uses = 1,
	  why = "an aura row reads the same weapon enchant" },
	{ from = "Charge", sym = "EnemyBars", uses = 3,
	  why = "the charge marker sits above the enemy bar on the same nameplate" },
	{ from = "CombatText", sym = "Reaction", uses = 2,
	  why = "the filter asks whether a reaction window is open before it speaks" },
	{ from = "CombatText", sym = "Requires", uses = 2,
	  why = "the filter reads why an ability refused, to say it once" },
	{ from = "Mail", sym = "Purse", uses = 1,
	  why = "a recipient is one of yours if the purse has seen the name" },
	{ from = "Mail", sym = "People", uses = 1,
	  why = "a recipient is somebody you know if the chat roster has them" },
	{ from = "UnitFrames", sym = "Marking", uses = 4,
	  why = "a unit frame draws the raid mark that Marking put on the unit" },
}

--------------------------------------------------------------------------
-- The scan
--------------------------------------------------------------------------

local Words = dofile((arg[0]:gsub("[^/\\]+$", "words.lua")))

-- The keywords that open a block on their own. `for`, `while` and `do` are
-- handled in the walk below because the first two open the block their `do`
-- would otherwise open a second time.
local OPENS = {
	["function"] = true, ["if"] = true, ["repeat"] = true,
}

local function Slurp(path)
	local handle = io.open(path, "r")
	if not handle then return nil end
	local text = handle:read("*a")
	handle:close()
	return text
end

-- The tree a path belongs to. Run from src/ the paths arrive as ./Tree/File.lua
-- and run from the repo root as src/Tree/File.lua, and both spellings answer
-- the same tree.
local function TreeOf(path)
	local clean = path:gsub("^%./", ""):gsub("^src/", "")
	return clean:match("^([^/]+)/")
end

-- Every `ns.Symbol` a file names, with the line, whether it is a top-level write
-- and whether it sits at file scope.
--
-- File scope is depth zero, and it is the difference between a reference that
-- resolves when the file loads and one that resolves when something calls it.
-- `local Where = ns.QuestWhere` at the top of a file is a load-order dependency;
-- the same line inside a function is not, and the toc rule below only bites the
-- first kind.
local function Names(text)
	local words, out, depth, pending = Words(text), {}, 0, false
	for index = 1, #words do
		local token = words[index]
		local word = token.word

		if word == "end" or word == "until" then
			depth = depth - 1
		elseif word == "do" then
			-- `for ... do` and `while ... do` open one block between them, not
			-- two, and the `do` can be a long way from its keyword: `for _, x
			-- in ipairs(t) do` puts four tokens between them. Reading the token
			-- before the `do` therefore misses every one of them and left the
			-- depth climbing all the way down a file, so file scope stopped
			-- being depth zero and ninety-seven of Core's declarations went
			-- unowned. A flag set by the keyword is what the depth is measured
			-- with instead.
			if pending then
				pending = false
			else
				depth = depth + 1
			end
		elseif word == "for" or word == "while" then
			-- The keyword opens the block. Its `do` is the same block's, and
			-- the flag is what tells the two apart.
			depth = depth + 1
			pending = true
		elseif OPENS[word] then
			depth = depth + 1
		end

		if word == "ns" then
			local sym, after = text:match("^ns%s*%.%s*([%a_][%w_]*)()", token.pos)
			if sym then
				-- A file claims a name two ways and both are a claim.
				-- `ns.X = X` is the one nearly every file writes, and
				-- `function ns.X()` is the one Core writes ninety-seven times
				-- and Feeds/Loot.lua writes once. Missing the second would
				-- leave ns.QualityWord owned by nobody and every call to it
				-- unchecked, which is a hole in the shape of the rule.
				-- Read off the text and not off the previous token alone. An
				-- anonymous `function()` whose first statement writes a field
				-- of somebody else's table puts `function` immediately before
				-- an `ns`, and taking that as a declaration handed ns.db to
				-- whichever slash command happened to set it first.
				local before = words[index - 1]
				local declared = before ~= nil and before.word == "function"
					and text:match("^function%s*ns%s*%.%s*[%a_][%w_]*%s*%(",
						before.pos) ~= nil
				out[#out + 1] = {
					sym = sym,
					line = token.line,
					-- The `function` keyword has already opened a block by the
					-- time its name is read, so a declaration at file scope
					-- measures one deep rather than none.
					top = depth == (declared and 1 or 0),
					-- `ns.X = ` and not `ns.X == `, and not `ns.X.y = ` either:
					-- writing a field of somebody else's table is not a claim
					-- on the name.
					write = declared or text:match("^%s*=[^=]", after) ~= nil,
				}
			end
		end
	end
	-- The walk has to come back to where it started. A file that ends at any
	-- other depth means the block counting lost track somewhere, and every
	-- file-scope answer after that point is a guess. Two bugs in this counter
	-- were found by hand before this line existed, and both would have failed
	-- here on the first run: a `for ... do` counted as two blocks, and then the
	-- same pair counted as none.
	return out, depth
end

-- Load order, straight off the toc, and per file rather than per tree.
--
-- Per tree was the first version of this and it was wrong. The toc names Core
-- three times: the registry first, then Core\\Panel.lua after UI\\Widgets.lua
-- because a page is built out of the kit, then Core\\MenuSkin.lua after that.
-- Ranking a tree by where it first appears called both of those load-time nils
-- and neither is. A file is what the client loads, so a file is what this
-- counts.
local function LoadOrder()
	local handle = io.open("WarriorKit.toc", "r")
		or io.open("src/WarriorKit.toc", "r")
	if not handle then return nil end
	local rank, at = {}, 0
	for line in handle:lines() do
		local entry = line:match("^([%w_\\]+%.lua)%s*$")
		if entry then
			at = at + 1
			rank["./" .. entry:gsub("\\", "/")] = at
		end
	end
	handle:close()
	return rank
end

--------------------------------------------------------------------------
-- The gate
--------------------------------------------------------------------------

local paths = { ... }
local failures = {}

local function Fail(text)
	failures[#failures + 1] = text
end

local order = LoadOrder()
if not order then
	Fail("trees: WarriorKit.toc is missing and nothing can say what loads first")
	print(failures[1])
	os.exit(1)
end

-- Pass one: who owns what. Derived rather than declared, so a file moved between
-- trees moves its symbols with it and this list never goes stale.
local owner, holder, named, where = {}, {}, {}, {}
for _, path in ipairs(paths) do
	local text = Slurp(path)
	if text then
		local tree = TreeOf(path)
		local left
		named[path], left = Names(text)
		if left ~= 0 then
			Fail(("%s: the block walk ended %d deep instead of level, so nothing here can be trusted")
				:format(path, left))
		end
		for _, one in ipairs(named[path]) do
			if one.write and one.top then
				local held = owner[one.sym]
				if held and held ~= tree then
					Fail(("%s:%d ns.%s is written at the top of %s as well as %s, so no tree owns it")
						:format(path, one.line, one.sym, tree, held))
				elseif not held then
					owner[one.sym] = tree
					holder[one.sym] = path
					where[one.sym] = ("%s:%d"):format(path, one.line)
				end
			end
		end
	end
end

-- Pass two: every edge that crosses a tree, counted.
local edges, sites = {}, {}
for _, path in ipairs(paths) do
	local tree = TreeOf(path)
	for _, one in ipairs(named[path] or {}) do
		local held = owner[one.sym]
		if held and held ~= tree then
			local key = tree .. "\0" .. one.sym
			edges[key] = (edges[key] or 0) + 1
			sites[key] = sites[key] or {}
			sites[key][#sites[key] + 1] = {
				path = path, line = one.line, top = one.top,
				from = tree, to = held, sym = one.sym,
			}
		end
	end
end

local exempt, claimed = {}, {}
for _, entry in ipairs(ALLOWED) do
	local key = entry.from .. "\0" .. entry.sym
	if not entry.why then
		Fail(("trees: %s -> ns.%s is allow-listed with no reason given")
			:format(entry.from, entry.sym))
	elseif exempt[key] then
		Fail(("trees: %s -> ns.%s is allow-listed twice")
			:format(entry.from, entry.sym))
	else
		exempt[key] = entry
	end
end

-- Pass three: the three rules, over every edge.
local keys = {}
for key in pairs(edges) do keys[#keys + 1] = key end
table.sort(keys)

for _, key in ipairs(keys) do
	local list = sites[key]
	local first = list[1]
	local uses = edges[key]
	local entry = exempt[key]
	claimed[key] = true

	-- The base is closed. A tree everything is allowed to name may not name a
	-- feature back, because the moment it does, every feature depends on that
	-- feature through the floor and no entry below records it.
	if BASE[first.from] and not BASE[first.to] then
		Fail(("%s:%d %s is in the base and names ns.%s, which %s owns (%s). The base may not reach into a feature.")
			:format(first.path, first.line, first.from, first.sym, first.to,
				where[first.sym]))

	elseif not BASE[first.to] then
		if not entry then
			Fail(("%s:%d names ns.%s, which %s owns (%s). A feature may name "
				.. "%s and its own tree; anything else needs an entry in "
				.. "scripts/trees.lua.")
				:format(first.path, first.line, first.sym, first.to,
					where[first.sym], BASE_WORDS))
		elseif uses > entry.uses then
			Fail(("%s:%d %s -> ns.%s is named %d times, over %d")
				:format(first.path, first.line, first.from, first.sym, uses,
					entry.uses))
		elseif uses < entry.uses then
			Fail(("trees: %s -> ns.%s is down to %d and its entry still says %d: lower it")
				:format(first.from, first.sym, uses, entry.uses))
		end
	end

	-- The toc rule, which is about load time rather than about architecture and
	-- so is not something an entry above can excuse. A file-scope capture of a
	-- symbol whose file loads later is nil, every time, on every client. The
	-- same reference inside a function is fine: it resolves when something calls
	-- it, which is long after every file has loaded.
	--
	-- This one runs over base edges too. The base is where a load-time nil is
	-- most likely and least visible, because a file that captures ns.UI too
	-- early gets nil and fails somewhere else entirely.
	for _, site in ipairs(list) do
		if site.top then
			local mine = order[site.path]
			local theirs = order[holder[site.sym]]
			if mine and theirs and theirs > mine then
				Fail(("%s:%d captures ns.%s at file scope and %s loads after it in the toc, so it is nil here")
					:format(site.path, site.line, site.sym, holder[site.sym]))
			end
		end
	end
end

for _, entry in ipairs(ALLOWED) do
	local key = entry.from .. "\0" .. entry.sym
	if not claimed[key] then
		Fail(("trees: %s -> ns.%s is allow-listed and no longer happens: delete the entry")
			:format(entry.from, entry.sym))
	end
end

--------------------------------------------------------------------------
-- The readout
--------------------------------------------------------------------------

-- What the base set was chosen off, and what an entry's number is set to. The
-- only way to seed either at what the code measures rather than at what sounded
-- about right.
if os.getenv("TREES_REPORT") then
	local into, outof, trees = {}, {}, {}
	for _, path in ipairs(paths) do
		local tree = TreeOf(path)
		trees[tree] = true
		for _, one in ipairs(named[path] or {}) do
			local held = owner[one.sym]
			if held and held ~= tree then
				into[held] = into[held] or {}
				into[held][tree] = true
				outof[tree] = outof[tree] or {}
				outof[tree][held] = true
			end
		end
	end
	local function Count(set)
		local n = 0
		for _ in pairs(set or {}) do n = n + 1 end
		return n
	end
	local list = {}
	for tree in pairs(trees) do list[#list + 1] = tree end
	table.sort(list, function(a, b) return Count(into[a]) > Count(into[b]) end)
	print("-- named by how many trees, and what each one names --")
	for _, tree in ipairs(list) do
		local out = {}
		for held in pairs(outof[tree] or {}) do out[#out + 1] = held end
		table.sort(out)
		print(("%-12s %2d  %s"):format(tree, Count(into[tree]),
			table.concat(out, " ")))
	end
	print("\n-- every edge that crosses a tree --")
	for _, key in ipairs(keys) do
		local first = sites[key][1]
		if not BASE[first.to] then
			print(("%-12s -> %-16s x%d"):format(first.from, "ns." .. first.sym,
				edges[key]))
			for _, site in ipairs(sites[key]) do
				print(("      %s:%d%s"):format(site.path, site.line,
					site.top and "  [file scope]" or ""))
			end
		end
	end
	os.exit(0)
end

if #failures > 0 then
	table.sort(failures)
	for _, one in ipairs(failures) do print(one) end
	print(("trees FAIL: %d"):format(#failures))
	os.exit(1)
end

local crossings = 0
for key in pairs(edges) do
	if not BASE[sites[key][1].to] then crossings = crossings + 1 end
end
print(("trees  %d symbols, %d edges cross a tree, %d allowed")
	:format((function()
		local n = 0
		for _ in pairs(owner) do n = n + 1 end
		return n
	end)(), crossings, #ALLOWED))
os.exit(0)
