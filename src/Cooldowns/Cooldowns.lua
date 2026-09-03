local ADDON, ns = ...

local Cooldowns = {}
ns.Cooldowns = Cooldowns

--------------------------------------------------------------------------
-- The cooldowns, in two layers
--
-- What this answers is one question the rest of the addon does not: how long
-- until the thing you win the fight with is back. The bars already draw a swipe
-- on every square, and a swipe on a square that is off the bottom of the screen
-- or on a page you are not standing in says nothing at all. Death Wish is three
-- minutes, Recklessness is thirty, Shield Wall is thirty, and a warrior counts
-- all three in their head because nothing on the screen counts them.
--
-- Two layers, because there are two of those questions and they are not asked
-- at the same rate.
--
--   rotation   the six to twelve seconds the fight is actually made of.
--              Stormstrike, Mortal Strike, Thunder Clap, Shield Slam. Looked at
--              constantly, pressed the moment it comes back, and read out of
--              the corner of the eye, so these are the big squares and they are
--              the top line.
--
--   long       the minutes. Recklessness, Shamanistic Rage, Shield Wall, a
--              trinket. Looked at twice a fight, so they are smaller and docked
--              under the line above rather than competing with it for the same
--              glance.
--
-- A row that drew both at one size was the version this replaced, and the
-- complaint against it is that it made a thirty minute cooldown and a ten second
-- one look like the same kind of fact.
--
-- Three sources, and the split is the whole of this file.
--
-- Your spec's two lists are facts and live in Class\<yours>.lua, which is the
-- rule every other part follows. Nothing here names a spell, and a spec that
-- registers neither field gets a row of trinkets or no row at all.
--
-- The trinkets are not a class fact and are the same two slots for everybody,
-- so they are here. Which trinket is worth a square is decided by the client:
-- an item with a use effect answers ns.ItemSpell with the name of it and a
-- passive one answers nothing, so the row carries the ones you press and skips
-- the ones you merely wear. That test is better than a cooldown reading,
-- because a passive trinket with a proc on it has a cooldown too and a square
-- saying "ready" about a proc is a square telling you to press something you
-- cannot press.
--
-- What is deliberately not here is a judgement about which cooldowns matter.
-- The class files list what is long and worth counting, IsSpellKnown drops
-- whatever this character has not learned or has not talented, and one switch
-- per entry drops whatever you personally do not want to look at. Three filters
-- and none of them is this file having an opinion about your spec.
--
-- Nothing in here draws. Row.lua is the row and Feature.lua is the settings,
-- which is the seam every part in this addon has.
--------------------------------------------------------------------------

-- Below this a cooldown is the global rather than the ability's own. The same
-- 1.5 Buttons\Slot.lua and Buffs\Racials.lua carry, and it is tested against
-- the whole duration rather than what is left of it: a three minute cooldown
-- with a second to run is still a cooldown, and a ready spell caught under the
-- global you just triggered is not.
local GCD = 1.5

-- How many entries one spec may put on each line of the row. Both are ceilings
-- rather than targets: the row is built once at login at the ceiling, because a
-- frame cannot be destroyed on these clients, and a spec that overran one would
-- lose squares off the end with nothing on screen saying so. Both are one or two
-- past the longest list any class file writes today.
local MAX_ROTATION = 7
local MAX_CLASS = 8

-- And how many you may add yourself, on top of whatever your class brought.
-- Six, and it is room reserved on screen rather than a target: the squares are
-- built at the ceiling at login whether you use them or not, so this number is
-- what the row costs to have the feature at all.
local MAX_MINE = 6

-- How many of your own aura slots the client will answer for. Forty, the same
-- number every aura scan in the addon stops at.
local SLOTS = 40

local NONE = {}

-- Which line a square is drawn on. Two strings rather than two booleans or a
-- number, because every place that reads one of them reads it in a comparison
-- and a misspelling is then a square on the wrong line rather than a nil error.
local ROTATION, LONG = "rotation", "long"
Cooldowns.ROTATION, Cooldowns.LONG = ROTATION, LONG

-- Does one list carry this slash word. Named because Cooldowns.Elsewhere asks
-- it four times over two lists and a class that has specs and a class that does
-- not are both answered by the same walk.
local function Claims(list, word)
	for index = 1, #(list or NONE) do
		if list[index].key == word then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------
-- The two trinkets
--
-- One entry each, built at load and filled in whenever the worn gear moves.
-- `slot` is what makes an entry a trinket: everything that reads state branches
-- on it once, because a worn item answers a different call from a spell and
-- nothing else about the two differs.
--
-- The keys are the words you type at them, so `/wk cooldowns trinket1 off`
-- silences the top one. Numbered rather than named after whatever is in the
-- slot today, because the switch is per character and outlives the trinket.
--------------------------------------------------------------------------

local TRINKETS = {
	{ key = "trinket1", slot = ns.Gear.TRINKET1 },
	{ key = "trinket2", slot = ns.Gear.TRINKET2 },
}

-- The whole list this character could draw, class first and trinkets last, held
-- once the client has answered for the class. Built the way Upkeep.Fixed builds
-- its own, and cached for the same reason: it cannot change after login.
local shipped

-- What is actually drawn, which is `shipped` with the switched off, the
-- unknown and the unnameable taken out. Rebuilt on an event, never on a tick.
local order = {}

-- And what is off the row on purpose: the entries this character could draw and
-- has switched off. Kept beside `order` and built in the same walk, because the
-- page draws both and a square you took off the row that is nowhere on the page
-- is a square you cannot put back.
--
-- The unlearned and the unnameable are on neither list. There is nothing to
-- show and nothing to drag: a trinket slot with a passive item in it and a
-- talent nobody has spent a point on are facts about the character rather than
-- squares somebody moved.
local shelf = {}

-- How many times the list has been rebuilt, so the row can tell that what it
-- laid out is stale without comparing the list to itself. A count rather than a
-- length, because a rebuild can leave the list exactly as long as it was and
-- hold different entries: one spell trained and another switched off in the same
-- moment is two squares changing places and no number moving.
local epoch = 0

-- Aura name to entry, for the scan. A burst cooldown that is running is the
-- other half of the question this row answers, and the client will not say so:
-- the spell's cooldown starts the moment you press it and says nothing about
-- whether the fifteen seconds you pressed it for are still going.
local wanted = {}

--------------------------------------------------------------------------
-- Resolving one entry
--------------------------------------------------------------------------

-- The first of an entry's ids this client both names and this character knows,
-- with the name and the picture taken off it.
--
-- Two questions in one walk and they are not the same question. A client that
-- cannot name an id is a client that never shipped the spell, which is most of
-- what separates Era from Burning Crusade in the class files. A character that
-- does not know a spell it can name is a talent unspent or a trainer unvisited,
-- and that one changes during a session, which is why SPELLS_CHANGED rebuilds.
local function Resolve(entry)
	entry.id, entry.name, entry.texture = nil, nil, nil
	for index = 1, #(entry.spells or NONE) do
		local id = entry.spells[index]
		local name = ns.SpellName(id)
		-- IsSpellKnown is not asked of an entry you added yourself. It answers no
		-- for a rank you have not trained, for anything an item casts and for a
		-- few spells it simply does not carry, and a square you typed out by id
		-- disappearing with nothing said is worse than one that reads ready when
		-- it should not. What your class file listed is still filtered, because
		-- that list is somebody else's guess about your character.
		if name and (entry.mine or IsSpellKnown(id)) then
			entry.id, entry.name = id, name
			entry.texture = ns.SpellTexture(id)
			return
		end
	end
end

--------------------------------------------------------------------------
-- The ones you added yourself
--
-- A class file is somebody's list of what is worth counting for a spec, and
-- three things it cannot know: the spell you press on this character and on no
-- other, the one whoever wrote the file left out, and the one you want counted
-- for a fight next week and not after. So the row takes entries of your own,
-- the way the debuff row on an enemy bar does, and they are per character for
-- the reason the switches are.
--
-- An id and nothing else is saved. Which line one of yours draws on is held
-- with every other entry's line below, because moving Shield Wall to the top
-- line and moving one of yours there are the same act and two places answering
-- it is two places to keep in step.
--------------------------------------------------------------------------

local function MineKey(spellID)
	return "spell" .. spellID
end

-- One entry table per spell you added, held rather than rebuilt, so that a
-- rebuild hands the row the same table it was drawing and not a new one with
-- no aura state on it.
local mine = {}

local function MineEntry(spellID)
	local key = MineKey(spellID)
	local entry = mine[key]
	if not entry then
		entry = { key = key, spells = { spellID }, mine = true }
		mine[key] = entry
	end
	return entry
end

function Cooldowns.Mine()
	return ns.dbc.cooldownMine
end

function Cooldowns.IsMine(key)
	return mine[key] ~= nil
end

--------------------------------------------------------------------------
-- Where a square sits
--
-- Two facts about an entry, and both are yours rather than the class file's:
-- which of the two lines it draws on, and how far along that line it is.
--
-- `cooldownLine` holds only what you moved, so an entry you never touched
-- follows its class file and goes on following it when that file changes its
-- mind. `cooldownOrder` is the whole row written out as a list of keys, saved
-- every time anything moves, because what changes when you move a square is
-- the order of the two either side of it as much as the one you dragged.
--------------------------------------------------------------------------

local function LineOf(entry, shippedLine)
	local moved = ns.dbc.cooldownLine[entry.key]
	if moved == ROTATION or moved == LONG then
		return moved
	end
	return shippedLine
end

-- Where one key sits in the order you arranged, or nil for one you never
-- touched.
local function Rank(key)
	local saved = ns.dbc.cooldownOrder
	for index = 1, #saved do
		if saved[index] == key then
			return index
		end
	end
	return nil
end

-- The list in the order the row draws it.
--
-- The rotation line first, which is not a preference: Row.lua counts along one
-- line until the tag changes and starts the other, so an entry out of place
-- there is a long cooldown drawn at rotation size on the top line.
--
-- Inside a line, whatever order you put it in, and everything you never moved
-- after everything you did, in the order its class file wrote it. That is what
-- keeps a spell you train tomorrow from landing in the middle of a row you
-- arranged last week.
local function Sort(list)
	local rank, tail = {}, #ns.dbc.cooldownOrder
	for index = 1, #list do
		rank[list[index].key] = Rank(list[index].key) or (tail + index)
	end
	table.sort(list, function(a, b)
		if (a.layer == ROTATION) ~= (b.layer == ROTATION) then
			return a.layer == ROTATION
		end
		return rank[a.key] < rank[b.key]
	end)
end

-- Write the row down as it stands, so the next sort reproduces it.
local function Remember(list)
	local saved = ns.dbc.cooldownOrder
	wipe(saved)
	for index = 1, #list do
		saved[index] = list[index].key
	end
end

-- One entry onto the list, on the line you moved it to or the one it shipped
-- on. A trinket is not resolved here: its name comes off the item in the slot
-- and Refit is what reads that.
local function Take(entry, line)
	entry.layer = LineOf(entry, line)
	shipped[#shipped + 1] = entry
	if not entry.slot then
		Resolve(entry)
	end
end

-- Everything about this character's row is decided again from scratch. Called
-- by anything that adds, drops or moves an entry, and by nothing on a tick.
local function Reshape()
	shipped = nil
	Cooldowns.Rebuild()
end

--------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------

function Cooldowns.Ceiling()
	return MAX_ROTATION + MAX_CLASS + #TRINKETS + MAX_MINE
end

function Cooldowns.Count()
	return #order
end

function Cooldowns.Epoch()
	return epoch
end

function Cooldowns.Entry(index)
	return order[index]
end

function Cooldowns.ShelfCount()
	return #shelf
end

function Cooldowns.Shelved(index)
	return shelf[index]
end

-- How many drawn squares each line carries. Two numbers rather than a list,
-- because both callers walk the entries themselves and neither wants a table
-- built per layout. The rotation entries lead the list, which is the property
-- Sort is built to keep, so this counts until the tag changes and stops.
function Cooldowns.Split()
	local fast = 0
	while fast < #order and order[fast + 1].layer == ROTATION do
		fast = fast + 1
	end
	return fast, #order - fast
end

-- The at-th drawn square on one line, or nil past the end of it. What the page
-- reads a square off, and what a drop is measured against: `at` counts squares
-- you can see, because that is what the mouse landed on.
function Cooldowns.OnRow(line, at)
	local seen = 0
	for index = 1, #order do
		if order[index].layer == line then
			seen = seen + 1
			if seen == at then
				return order[index]
			end
		end
	end
	return nil
end

-- What your spec brought, in two lines, plus the two trinket slots everybody
-- has.
--
-- One list rather than two, tagged, because everything downstream asks the same
-- four questions of every entry and only the row cares where a square is drawn.
-- Splitting the list would have meant a second epoch, a second scan, a second
-- switch table and two copies of State.
--
-- Rotation first, because that is the order the row draws them in and the row
-- walks this list once.
--
-- Nil until the client says what class this is, which is the rule Class.lua
-- states: an answer taken at file scope would be nil, and a nil written down
-- once would leave a warrior with no row for the session.
function Cooldowns.All()
	if shipped then
		return shipped
	end
	if not ns.Class.Token() then
		return NONE
	end

	local fast = ns.Class.Of("rotation") or NONE
	local long = ns.Class.Of("cooldowns") or NONE
	assert(#fast <= MAX_ROTATION,
		("%s puts %d entries on the rotation line and the cap is %d")
			:format(ns.Class.Spec.Says(), #fast, MAX_ROTATION))
	assert(#long <= MAX_CLASS,
		("%s puts %d entries on the cooldown row and the cap is %d")
			:format(ns.Class.Spec.Says(), #long, MAX_CLASS))

	-- Resolved as each one is taken rather than only in Rebuild, because the
	-- options page is built off this list and names its rows with the client's
	-- own name for each spell. A page built a moment before the first
	-- rebuild would carry the entry's key instead, and a label is a string the
	-- page keeps rather than a question it asks again.
	shipped = {}
	for index = 1, #fast do
		Take(fast[index], ROTATION)
	end
	for index = 1, #long do
		Take(long[index], LONG)
	end
	for index = 1, #TRINKETS do
		Take(TRINKETS[index], LONG)
	end
	-- Yours last, so one you add lands at the end of the docked line and stays
	-- there until you move it, rather than appearing somewhere in the middle of
	-- a row you already know the shape of.
	local own = Cooldowns.Mine()
	for index = 1, #own do
		Take(MineEntry(own[index]), LONG)
	end

	Sort(shipped)
	return shipped
end

-- Which entry on the row already answers for a spell, or nil for one nothing on
-- it has heard of.
--
-- Every id an entry carries, and the name as well. An entry with two ids is one
-- button under two names, and a spell dragged on by a rank the class file did
-- not list would otherwise arrive as a second square counting the same cooldown
-- down beside the first.
function Cooldowns.Owner(spellID)
	local name = ns.SpellName(spellID)
	local list = Cooldowns.All()
	for index = 1, #list do
		local entry = list[index]
		for at = 1, #(entry.spells or NONE) do
			if entry.spells[at] == spellID then
				return entry
			end
		end
		if name and entry.name == name then
			return entry
		end
	end
	return nil
end

-- Add a spell of your own. Returns true and its name, or false and the
-- sentence to print, which is the shape EnemyBars.AddSpell hands back and for
-- the same reason: the panel and the slash word say the same thing about the
-- same refusal.
function Cooldowns.Add(spellID)
	spellID = tonumber(spellID)
	if not spellID or spellID <= 0 or spellID ~= math.floor(spellID) then
		return false, "a spell id is a whole number. It is the last part of the"
			.. " spell's Wowhead address."
	end

	local name = ns.SpellName(spellID)
	if not name then
		return false, ("this client does not know spell %d."):format(spellID)
	end

	-- A spell the row already knows about is switched back on rather than added
	-- again. That is the same act said two ways: dragging Death Wish back onto
	-- the row and typing its id are both "count this one", and the one that
	-- refused because a square you had switched off was still on the list was
	-- refusing to do the thing it was asked for.
	local owner = Cooldowns.Owner(spellID)
	if owner then
		if Cooldowns.Watched(owner.key) then
			return false, name .. " is already on the row."
		end
		Cooldowns.SetWatched(owner.key, true)
		return true, name
	end

	local own = Cooldowns.Mine()
	if #own >= MAX_MINE then
		return false, ("the row takes %d of your own at most. Take one off first.")
			:format(MAX_MINE)
	end

	own[#own + 1] = spellID
	-- Watched, whatever the switch said last time this key was here. Adding a
	-- square back and having it not appear is the one thing nobody would think
	-- to check the switches for.
	ns.dbc.cooldownWatch[MineKey(spellID)] = nil
	Reshape()
	return true, name
end

-- Take one of yours off, and take the switch, the line and the place with it. A
-- key that is gone from the row leaving three settings behind is what makes
-- adding the same spell back a week later behave differently from adding it the
-- first time.
function Cooldowns.Drop(spellID)
	spellID = tonumber(spellID)
	local own = Cooldowns.Mine()
	for index = 1, #own do
		if own[index] == spellID then
			local key = MineKey(spellID)
			table.remove(own, index)
			mine[key] = nil
			ns.dbc.cooldownLine[key] = nil
			ns.dbc.cooldownWatch[key] = nil
			local saved = ns.dbc.cooldownOrder
			for at = #saved, 1, -1 do
				if saved[at] == key then
					table.remove(saved, at)
				end
			end
			Reshape()
			return true, ns.SpellName(spellID) or ("spell " .. spellID)
		end
	end
	return false
end

-- One place along its own line, or false where there is nowhere to go.
--
-- Along the whole list rather than along what is drawn, because the panel shows
-- every entry including the ones you switched off, and a square that jumped two
-- places because something invisible was in the way is a control that does not
-- do what it says.
function Cooldowns.Move(key, step)
	local list = Cooldowns.All()
	local at
	for index = 1, #list do
		if list[index].key == key then
			at = index
		end
	end
	if not at then
		return false
	end

	local to = at + step
	if to < 1 or to > #list or list[to].layer ~= list[at].layer then
		return false
	end

	list[at], list[to] = list[to], list[at]
	Remember(list)
	Cooldowns.Rebuild()
	return true
end

-- The other line. The entry keeps the place it held in the order, so it lands
-- among its new neighbours where it stood among its old ones rather than at an
-- end you then have to walk it back from.
function Cooldowns.SetLine(key, line)
	ns.dbc.cooldownLine[key] = line
	local list = Cooldowns.All()
	for index = 1, #list do
		if list[index].key == key then
			list[index].layer = line
		end
	end
	Sort(list)
	Remember(list)
	Cooldowns.Rebuild()
end

--------------------------------------------------------------------------
-- Where a square was dropped
--
-- Two calls, and between them they are the whole of what the page writes. A
-- square is dropped onto a line at a place along it, or it is dragged off and
-- switched off. Everything the page used to carry, a tick box and two step
-- buttons and a line button and a cross per entry, said one of those two things
-- in five controls and a paragraph explaining them.
--
-- The line and the place are one act here rather than two. Dragging Shield Wall
-- from the docked line to the third square of the top line is one gesture, and
-- a pair of calls that moved the line and then walked it into place would draw
-- the row twice and leave it wrong in between.
--------------------------------------------------------------------------

-- Where an entry goes in the whole list to land at a place on one line.
--
-- Before the square it was dropped on, or after the last entry already on that
-- line when it was dropped past the end. An empty line takes the top of the
-- list or the bottom of it, which is the same rule stated for the case with
-- nothing to sit beside: the rotation entries lead the list and the docked ones
-- follow, and Row.lua walks that in one pass.
local function Slot(list, line, anchor)
	if anchor then
		for index = 1, #list do
			if list[index] == anchor then
				return index
			end
		end
	end
	for index = #list, 1, -1 do
		if list[index].layer == line then
			return index + 1
		end
	end
	return line == ROTATION and 1 or (#list + 1)
end

-- One square onto a line, at a place along it. Switched back on if it was off,
-- because a square you dragged onto the row is one you want counted and there
-- is nothing else the gesture could mean.
--
-- `at` counts the drawn squares on that line rather than the entries on the
-- list, because it comes off the page and the page draws what you can see. A
-- place past the end of the line is the end of it.
function Cooldowns.Place(key, line, at)
	local anchor = Cooldowns.OnRow(line, at)
	if anchor and anchor.key == key then
		return false
	end

	local list = Cooldowns.All()
	local from
	for index = 1, #list do
		if list[index].key == key then
			from = index
		end
	end
	if not from then
		return false
	end

	local entry = table.remove(list, from)
	entry.layer = line
	ns.dbc.cooldownLine[key] = line
	ns.dbc.cooldownWatch[key] = nil

	table.insert(list, Slot(list, line, anchor), entry)
	Remember(list)
	Cooldowns.Rebuild()
	return true
end

-- A spell dropped on the row: off your spellbook, off the other line, or off
-- the squares under the row that are not on it.
--
-- Matched against the whole list before anything is added, because the spell
-- you are holding is nearly always one the row has already heard of. Adding it
-- again would be a second square counting the same cooldown down beside the
-- first, and Owner is what makes dragging one back on the same act as never
-- having taken it off.
function Cooldowns.Put(spellID, line, at)
	spellID = tonumber(spellID)
	if not spellID then
		return false, "that is not a spell this row can count."
	end

	local owner = Cooldowns.Owner(spellID)
	if owner then
		Cooldowns.Place(owner.key, line, at)
		return true, owner.name or ns.SpellName(spellID)
	end

	local ok, message = Cooldowns.Add(spellID)
	if not ok then
		return false, message
	end
	Cooldowns.Place(MineKey(spellID), line, at)
	return true, message
end

-- Back to the row your class ships: everything you added dropped, every line
-- and every place put back.
--
-- The switches are deliberately left alone. Whether Shield Wall is worth a
-- square and where that square goes are two answers, and a button that throws
-- both away is a button nobody presses twice.
function Cooldowns.ResetRow()
	wipe(ns.dbc.cooldownMine)
	wipe(ns.dbc.cooldownLine)
	wipe(ns.dbc.cooldownOrder)
	wipe(mine)
	Reshape()
end

-- Which line one drawn entry belongs on. The row is the only caller and it asks
-- once per square per layout, never on a tick.
function Cooldowns.Layer(index)
	local entry = order[index]
	return entry and entry.layer or LONG
end

-- Which class claims a slash word this character has no entry for, or nil for a
-- word nobody claims, which is an ordinary typo. The same answer Upkeep gives
-- and for the same reason: `/wk cooldowns iceblock` on a warrior would
-- otherwise fall through to the bare on|off toggle, switch the whole row off
-- and report that it had done something else.
function Cooldowns.Elsewhere(word)
	for _, def in pairs(ns.Class.All()) do
		if Claims(def.rotation, word) or Claims(def.cooldowns, word) then
			return def.label
		end
		for index = 1, #(def.specs or NONE) do
			local spec = def.specs[index]
			if Claims(spec.rotation, word) or Claims(spec.cooldowns, word) then
				return spec.label .. " " .. def.label
			end
		end
	end
	return nil
end

function Cooldowns.ByWord(word)
	local list = Cooldowns.All()
	for index = 1, #list do
		if list[index].key == word then
			return list[index]
		end
	end
	return nil
end

--------------------------------------------------------------------------
-- What you have switched off
--
-- Per character, and the argument is the one Buffs\Feature.lua makes for its
-- own: whether Shield Wall is worth a square is a fact about the character and
-- not a preference about the row. A tank wants it. The same account's alt has
-- not learned it, which IsSpellKnown answers, and the same account's second
-- warrior has learned it and never presses it, which only you can answer.
--------------------------------------------------------------------------

function Cooldowns.Watched(key)
	return ns.dbc.cooldownWatch[key] ~= false
end

function Cooldowns.SetWatched(key, on)
	-- A branch rather than `on and nil or false`, which is shorter and wrong:
	-- `and nil` is falsy, the `or` takes over, and every call writes false.
	if on then
		ns.dbc.cooldownWatch[key] = nil
	else
		ns.dbc.cooldownWatch[key] = false
	end
	Cooldowns.Rebuild()
end

-- What you have added, in one phrase, for the panel to read back. The count
-- against the ceiling as well as the names, because the refusal when the list
-- is full is otherwise the first anybody hears of there being a ceiling.
function Cooldowns.Own()
	local own = Cooldowns.Mine()
	if #own == 0 then
		return "nothing, the row is what your class file lists"
	end
	local names = ""
	for index = 1, #own do
		names = names .. (index > 1 and ", " or "")
			.. (ns.SpellName(own[index]) or ("spell " .. own[index]))
	end
	return ("%d of %d: %s"):format(#own, MAX_MINE, names)
end

-- How many are switched off, and their names in one phrase, so a silenced entry
-- is visible somewhere. A square you turned off six weeks ago and cannot find
-- any trace of is the same defect as one you learned to ignore.
function Cooldowns.Silent()
	local list = Cooldowns.All()
	local count, names = 0, ""
	for index = 1, #list do
		local entry = list[index]
		if not Cooldowns.Watched(entry.key) then
			count = count + 1
			names = names .. (count > 1 and ", " or "") .. (entry.name or entry.key)
		end
	end
	return count, names
end

-- What is in the two trinket slots, and whether it is a thing you press.
--
-- Read whenever the worn gear moves and never on the tick. The name is the use
-- effect's rather than the item's, because that is what the tooltip on the
-- square has to say and it is the string the aura scan matches on: an item
-- called Bloodlust Brooch puts an aura on you under the name of its effect.
function Cooldowns.Refit()
	for index = 1, #TRINKETS do
		local entry = TRINKETS[index]
		local link = GetInventoryItemLink("player", entry.slot)
		local spell = ns.ItemSpell(link)
		local item, icon = ns.ItemInfo(link)
		entry.id = nil
		entry.name = spell
		entry.item = item
		entry.texture = spell and icon or nil
	end
end

-- What is in one trinket slot, in the panel's words. Three answers and the
-- middle one is the whole reason the slot can be empty on the row while
-- something is sitting in it: a trinket with no use effect is worn rather than
-- pressed, and nothing about wearing it is worth a square.
function Cooldowns.Worn(slot)
	for index = 1, #TRINKETS do
		local entry = TRINKETS[index]
		if entry.slot == slot then
			if not entry.item then
				return "empty"
			end
			if not entry.name then
				return entry.item .. ", worn rather than pressed"
			end
			return entry.item .. ", " .. entry.name
		end
	end
	return "empty"
end

-- Rebuild the drawn list out of what this character has, has learned and has
-- left switched on. On an event, never on a tick.
function Cooldowns.Rebuild()
	Cooldowns.Refit()

	for index = #order, 1, -1 do
		order[index] = nil
	end
	for index = #shelf, 1, -1 do
		shelf[index] = nil
	end
	for name in pairs(wanted) do
		wanted[name] = nil
	end

	local list = Cooldowns.All()
	for index = 1, #list do
		local entry = list[index]
		if not entry.slot then
			Resolve(entry)
		end
		entry.present = false
		if entry.name and Cooldowns.Watched(entry.key) then
			order[#order + 1] = entry
			wanted[entry.name] = entry
		elseif entry.name then
			shelf[#shelf + 1] = entry
		end
	end

	epoch = epoch + 1
	Cooldowns.Scan()
end

-- Which of the drawn entries are running right now, as auras on you. Called
-- from UNIT_AURA and never from the ticker, which is the rule Buffs\Upkeep.lua
-- states at length: forty slots ten times a second is four hundred lookups to
-- learn what one event already said.
function Cooldowns.Scan()
	for index = 1, #order do
		order[index].present = false
	end

	local index = 1
	while index <= SLOTS do
		local name = ns.BuffName("player", index)
		if not name then
			break
		end
		local entry = wanted[name]
		if entry then
			entry.present = true
		end
		index = index + 1
	end
end

--------------------------------------------------------------------------
-- What one square is doing
--
-- On the tick. Nothing below allocates.
--------------------------------------------------------------------------

-- The status, the swipe and whether the window it opens is still open, as four
-- values rather than a table, because a table here is one allocation per square
-- per tick to say what four values already say.
--
-- Four of the ten statuses are reachable. "empty" is a slot past the end of the
-- list, "unknown" is the client refusing to answer for something it otherwise
-- lists, "cooldown" is a real wait and "ready" is a press. Range and cost are
-- not asked: a cooldown row that greyed Death Wish out because you are ten rage
-- short would be answering a question the bar already answers, and the answer
-- moves twice a second.
function Cooldowns.State(index)
	local entry = order[index]
	if not entry then
		return "empty", 0, 0, false
	end

	local start, duration, enabled
	if entry.slot then
		start, duration, enabled = ns.InventoryCooldown(entry.slot)
	else
		start, duration, enabled = ns.SpellCooldown(entry.id)
	end

	if enabled == false then
		return "unknown", 0, 0, false
	end
	if duration and duration > GCD then
		return "cooldown", start, duration, entry.present
	end
	return "ready", start, duration, entry.present
end

-- Is anything on the row still recovering. What the row is up for out of
-- combat, and the reason it is not up the rest of the time.
--
-- On the tick.
function Cooldowns.Busy()
	for index = 1, #order do
		local status = Cooldowns.State(index)
		if status == "cooldown" then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------

-- Why there is no row, in this character's own words, or nil where there is
-- one. Said once here so the panel, the slash word and the status line give the
-- same reason rather than three sentences that have to be kept in step.
function Cooldowns.Refusal()
	if #order > 0 then
		return nil
	end
	local list = Cooldowns.All()
	if #list <= #TRINKETS
		and not ns.Class.Of("cooldowns") and not ns.Class.Of("rotation") then
		return ("nothing is listed for a %s, so the row carries your trinkets and"
			.. " nothing else"):format(ns.Class.Spec.Says())
	end
	local silent = Cooldowns.Silent()
	if silent > 0 then
		return "everything this character has is switched off"
	end
	return "nothing on the list is learned yet, so there is nothing to count"
end

function Cooldowns.Describe()
	if not ns.db.cooldowns then
		return "off"
	end

	local refusal = Cooldowns.Refusal()
	if refusal then
		return refusal
	end

	local silent, names = Cooldowns.Silent()
	local tail = silent > 0 and ("; " .. names .. " switched off") or ""

	local waiting = 0
	for index = 1, #order do
		local status = Cooldowns.State(index)
		if status == "cooldown" then
			waiting = waiting + 1
		end
	end
	if waiting == 0 then
		return ("%d tracked, all ready"):format(#order) .. tail
	end
	return ("%d tracked, %d on cooldown"):format(#order, waiting) .. tail
end
