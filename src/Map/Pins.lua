local ADDON, ns = ...

local Pins = {}
ns.MapPins = Pins

--------------------------------------------------------------------------
-- Questie's markers, read off Questie's own frames
--
-- The world map this addon draws is its own frame, so nothing Questie hangs on
-- Blizzard's map lands on it. That is the whole problem this file solves, and
-- the way it solves it is worth stating, because the obvious way is wrong.
--
-- **It does not ask the database again.** Quests/Where.lua does that, for one
-- quest at a time, and it is the right shape there: one quest, one answer, and
-- a window that would otherwise have nothing to draw. Asking it for a whole
-- zone means deciding, in this addon, which quests you can pick up, which ones
-- are the wrong faction, the wrong level, the wrong race, already done, in a
-- chain you have not started, or blacklisted. Questie has ten thousand lines
-- deciding exactly that and it decides it every time your log changes.
--
-- **So it reads what Questie already decided.** Questie draws its icons by
-- making one frame per marker and handing that frame to HereBeDragons to place
-- on the client's map. The frames are the answer: each one carries the map it
-- belongs to, where on it, the texture Questie chose, the colour it tinted it
-- and the quest it came from. This walks them and turns them into the points
-- UI/Chart.lua draws. Turn a Questie setting off and the markers go, because
-- the frames go.
--
-- The two registers are QuestieMap.questIdFrames, which is every quest marker
-- keyed by quest, and QuestieMap.manualFrames, which is everything else it
-- puts on a map: the flight masters, the trainers, the class notes. Both are
-- read, because "all of Questie's markers" means both.
--
-- **A frame being hidden is not the test.** Questie's icons are hidden all the
-- time in ordinary use: the client's map is shut, HereBeDragons has taken its
-- pins back, the icon is off screen. What means "do not draw this" is Questie's
-- own flag, `hidden`, which is what it sets when its own rules say the marker
-- should not be up. Reading IsShown instead draws nothing at all, because on a
-- client whose world map is in this addon's attic Blizzard's map is never up.
--
-- **Every read is guarded and the whole thing degrades to an empty list.**
-- Questie may not be installed, may be a version whose internals moved, or may
-- not have compiled its database yet. An empty list is a map with no markers on
-- it and a line in the footer saying why, which is the same bargain
-- Quests/Where.lua makes.
--------------------------------------------------------------------------

local Chart = ns.UI.Chart

-- The most markers one zone gets.
--
-- A frame and six textures each, pooled and reused across every zone you click,
-- so the cap is what the pool grows to rather than what one draw costs. Two
-- hundred and fifty is past most zones in the game with a full log, and past it
-- the picture is confetti rather than an answer.
local CROWD = 250

-- What a marker is worth when the zone is fuller than that.
--
-- Questie's registers are hash tables and pairs walks them in no order, so a cap
-- applied as it walks keeps whichever markers the hash handed over first. In a
-- zone past the cap that drops whole quests at random, and the quest it drops is
-- as likely to be the turn-in you opened the map to find as it is to be the
-- ninetieth kobold. It also changes on every reload, which is why the marker
-- that went missing yesterday is back today.
--
-- So the markers are sorted before they are cut. Questie types every icon it
-- draws, and three of those types matter here: `complete` is the question mark
-- over whoever takes the quest off you, `available` is the exclamation mark over
-- whoever hands one out, and everything else is the crowd -- the monsters, the
-- objects, the items, the events, and every flight master and trainer out of the
-- manual register. The crowd is what fills a zone, so the crowd is what is cut.
--
-- The same order does a second job. The board draws front to back, so the tier a
-- marker is in is also what it is drawn over, and a turn-in standing on the same
-- NPC as three objective dots lands on top of them rather than under them.
local CROWD_TIER, AVAILABLE_TIER, TURNIN_TIER = 1, 2, 3
local TIER = { available = AVAILABLE_TIER, complete = TURNIN_TIER }

-- How big one of Questie's icons is drawn here.
--
-- Its own number rather than Questie's. Questie scales its icons off the
-- client's map, which is a canvas that zooms, and this chart zooms the picture
-- under marks that stay the same size on purpose: a mark is a thing you look
-- for on a screen and it wants the same pixels at every zoom. Fourteen is about
-- what Questie draws at the client's default scale.
local BADGE = 14

-- Questie's map module, or nil. What this file reads off it is questIdFrames, a
-- table Questie fills in as it draws rather than a call, so the check is on the
-- field at each read below. ns.Questie in Core is the probe.
local function Map()
	return ns.Questie("QuestieMap")
end

--------------------------------------------------------------------------
-- One frame, unpicked
--------------------------------------------------------------------------

-- What Questie tinted the icon, or nothing. Questie replaces the texture's own
-- SetVertexColor with one of its own that records the four numbers on the
-- texture, so the fields are read first and the client's getter is the
-- fallback for a build where it has not.
local function Tint(texture)
	if type(texture.r) == "number" and type(texture.g) == "number"
		and type(texture.b) == "number" then
		return { texture.r, texture.g, texture.b, texture.a or 1 }
	end
	if type(texture.GetVertexColor) ~= "function" then
		return nil
	end
	local ok, r, g, b, a = pcall(texture.GetVertexColor, texture)
	if not ok or type(r) ~= "number" then
		return nil
	end
	return { r, g, b, a or 1 }
end

-- What the hover says: the thing's own name at the top, the quest under it and
-- the coordinate under that.
--
-- The coordinate rather than a distance, for the reason the quest log's map
-- gives: a distance is the number that goes stale the moment you walk, and a
-- coordinate is what you type into the thing every player already has open.
local function Told(data, x, y)
	local lines = {}
	local quest = type(data.QuestData) == "table" and data.QuestData.name or nil
	if type(quest) == "string" and quest ~= "" and quest ~= data.Name then
		lines[#lines + 1] = quest
	end
	lines[#lines + 1] = ("%.1f, %.1f"):format(x, y)
	return lines
end

-- One marker, or nothing at all.
--
-- Everything is type checked rather than assumed. This is another addon's
-- frame, read by name out of the global table, and the one guarantee worth
-- having is that a Questie that has changed shape draws fewer markers rather
-- than raising in the middle of a map.
local function Read(name, map)
	local frame = _G[name]
	if type(frame) ~= "table" or frame.miniMapIcon or frame.hidden then
		return nil
	end
	if frame.UiMapID ~= map or type(frame.x) ~= "number" or type(frame.y) ~= "number" then
		return nil
	end
	local texture = frame.texture
	if type(texture) ~= "table" or type(texture.GetTexture) ~= "function" then
		return nil
	end
	local ok, art = pcall(texture.GetTexture, texture)
	if not ok or not art then
		return nil
	end
	local data = type(frame.data) == "table" and frame.data or {}
	return {
		x = frame.x, y = frame.y,
		icon = art, tint = Tint(texture), size = BADGE,
		name = type(data.Name) == "string" and data.Name or "a Questie marker",
		note = Told(data, frame.x, frame.y),
	}, TIER[data.Type] or CROWD_TIER
end

--------------------------------------------------------------------------
-- The two registers
--------------------------------------------------------------------------

-- One bag of frame names into the tiers. Questie keys the quest register by
-- name and fills the manual one by position, and pairs walks both.
--
-- Every name is read rather than stopping at the cap, because the cap is now
-- applied to the sorted list and there is nothing to sort until the walk is
-- done. The walk is the same length Pins.Held already runs on every redraw.
local function Take(bag, names, map)
	if type(names) ~= "table" then
		return
	end
	for _, name in pairs(names) do
		if type(name) == "string" then
			local point, tier = Read(name, map)
			if point then
				local into = bag[tier]
				into[#into + 1] = point
			end
		end
	end
end

local function FromQuests(bag, register, map)
	for _, names in pairs(register) do
		Take(bag, names, map)
	end
end

-- Everything Questie puts on a map that is not one of your quests: the flight
-- masters, the trainers, the vendors, whatever its menu has switched on. Nested
-- one deeper than the quest register, kind then id then names.
local function FromManual(bag, register, map)
	for _, byId in pairs(register) do
		if type(byId) == "table" then
			for _, names in pairs(byId) do
				Take(bag, names, map)
			end
		end
	end
end

-- The cut, and the order the survivors are drawn in.
--
-- Room is handed out from the top tier down, so a turn-in only ever loses its
-- place to another turn-in and the crowd gets whatever is left. The list comes
-- back the other way up, crowd first, because the board draws in order and the
-- last mark placed is the one on top.
local function Ranked(bag)
	local room = CROWD
	local kept = {}
	for tier = TURNIN_TIER, CROWD_TIER, -1 do
		local fits = #bag[tier]
		if fits > room then
			fits = room
		end
		kept[tier] = fits
		room = room - fits
	end
	local out = {}
	for tier = CROWD_TIER, TURNIN_TIER do
		local list = bag[tier]
		for index = 1, kept[tier] do
			out[#out + 1] = list[index]
		end
	end
	return out
end

--------------------------------------------------------------------------

-- Every marker Questie has for one zone.
--
-- An empty list is the ordinary answer rather than a failure, and there are
-- four ways to get one: Questie is not installed, its database has not compiled
-- yet, it has drawn nothing for this zone, or its own settings have every
-- category switched off. Pins.Describe is what tells them apart.
function Pins.Of(map)
	if type(map) ~= "number" then
		return {}
	end
	local questie = Map()
	if not questie then
		return {}
	end
	local bag = { {}, {}, {} }
	if type(questie.questIdFrames) == "table" then
		FromQuests(bag, questie.questIdFrames, map)
	end
	if type(questie.manualFrames) == "table" then
		FromManual(bag, questie.manualFrames, map)
	end
	return Ranked(bag)
end

-- You, as a point the chart draws as the client's own arrow rather than in
-- somebody else's art. Nothing at all on a map you are not standing on, which
-- is every zone but one.
--
-- Asked of the map being drawn rather than of the map you are on, which is what
-- puts the arrow on the continent picture as well as on the zone one. The
-- client answers a position against whatever map it is handed, so Kalimdor
-- answers for anybody standing anywhere on Kalimdor. Comparing the zone you are
-- in against the map on the board was the reason the continent came out with
-- everything on it except you.
--
-- The unit goes with the point, because the board takes every point carrying
-- one again on its own tick. That is how the arrow follows you across a zone
-- with the window open.
function Pins.You(map)
	local x, y = Chart.Spot(map, "player")
	if not x then
		return nil
	end
	return { x = x, y = y, kind = Chart.YOU, unit = "player", name = "you",
		note = ("%.1f, %.1f"):format(x, y) }
end

--------------------------------------------------------------------------
-- Where one quest's markers went
--------------------------------------------------------------------------

-- The name the client gives a map, or the number. A map the client will not
-- name is still a fact worth printing, because the number is what tells two
-- zones apart in a sentence about the wrong one.
local function Named(map)
	local name = Chart.Name(map)
	if type(name) == "string" and name ~= "" then
		return name
	end
	return "map " .. tostring(map)
end

-- The kinds of marker on the map, counted, in name order. Questie's own word
-- for each: available, complete, monster, object, item, event. Which kinds are
-- there is the difference between a quest whose turn-in was dropped and a quest
-- Questie still thinks you have work left on, and those want opposite fixes.
local function Kinds(counted)
	local names = {}
	for kind in pairs(counted) do
		names[#names + 1] = kind
	end
	table.sort(names)
	local said = {}
	for index = 1, #names do
		said[index] = ("%d %s"):format(counted[names[index]], names[index])
	end
	return table.concat(said, ", ")
end

-- Every map this quest's markers are on except the one being asked about, in
-- id order so two runs of the same command read the same.
local function Elsewhere(counted)
	local maps = {}
	for map in pairs(counted) do
		maps[#maps + 1] = map
	end
	table.sort(maps)
	local said = {}
	for index = 1, #maps do
		said[index] = ("%d on %s"):format(counted[maps[index]], Named(maps[index]))
	end
	return table.concat(said, ", ")
end

-- Where one quest's markers are, said in a line.
--
-- This answers the question Pins.Of cannot. Pins.Of hands back the markers that
-- survived and says nothing about the ones that did not, which is the right
-- shape for drawing a picture and the wrong shape for working out why a
-- question mark you were expecting is not on it. There are five answers and
-- they want different fixes: Questie is not answering at all, Questie never
-- made a marker for the quest, it made one and hid it under one of its own
-- settings, it filed one under a different zone, or it is on this map and the
-- board is drawing it.
--
-- Written against the quest rather than the zone because that is the shape of
-- the complaint. Nobody notices that a zone is four markers short. They notice
-- that the quest they just finished has nowhere to hand it in.
function Pins.Chase(questId, map)
	local questie = Map()
	if not questie then
		return "Questie is not answering"
	end
	local register = questie.questIdFrames
	local names = type(register) == "table" and register[questId] or nil
	if type(names) ~= "table" then
		return "Questie holds no marker for it"
	end
	local here, turnin, hidden, mini = 0, 0, 0, 0
	local away, kinds = {}, {}
	for _, name in pairs(names) do
		local frame = type(name) == "string" and _G[name] or nil
		if type(frame) == "table" then
			local data = type(frame.data) == "table" and frame.data or {}
			if frame.miniMapIcon then
				mini = mini + 1
			elseif frame.hidden then
				hidden = hidden + 1
			elseif frame.UiMapID == map then
				here = here + 1
				local kind = type(data.Type) == "string" and data.Type or "untyped"
				kinds[kind] = (kinds[kind] or 0) + 1
				if kind == "complete" then
					turnin = turnin + 1
				end
			elseif type(frame.UiMapID) == "number" then
				away[frame.UiMapID] = (away[frame.UiMapID] or 0) + 1
			end
		end
	end
	if turnin > 0 then
		return ("its turn-in is on %s, with %d marker(s) there altogether")
			:format(Named(map), here)
	end
	-- What is on this map is the first half of every answer, including the
	-- answer that nothing is. The second half is the reason, and there are four
	-- of them: the markers are on another zone, Questie has hidden them, they
	-- are minimap copies with no map twin, or there are none.
	local said = here > 0
		and ("%d marker(s) on %s (%s) and none of them a turn-in")
			:format(here, Named(map), Kinds(kinds))
		or ("nothing on %s"):format(Named(map))
	if next(away) then
		return ("%s; Questie has %s"):format(said, Elsewhere(away))
	end
	if hidden > 0 then
		return ("%s; Questie has hidden %d more"):format(said, hidden)
	end
	if here > 0 then
		return said
	end
	if mini > 0 then
		return ("%s; Questie holds %d minimap marker(s) for it and nothing for a map")
			:format(said, mini)
	end
	return said .. "; Questie holds no marker for it"
end

-- How many markers Questie is holding altogether, which is the number that says
-- whether it has finished drawing rather than whether this zone has anything in
-- it.
function Pins.Held()
	local questie = Map()
	local register = questie and questie.questIdFrames
	if type(register) ~= "table" then
		return 0
	end
	local held = 0
	for _, names in pairs(register) do
		if type(names) == "table" then
			for _ in pairs(names) do
				held = held + 1
			end
		end
	end
	return held
end

-- The most markers one zone is allowed. Handed out so the window can say how
-- many it left off rather than quietly drawing two hundred and fifty of four
-- hundred.
function Pins.Crowd()
	return CROWD
end

function Pins.Describe()
	if not Map() then
		return "Questie is not answering, so the map has no markers on it"
	end
	local held = Pins.Held()
	if held == 0 then
		return "Questie is loaded and has drawn no markers yet"
	end
	return ("reading Questie, which is holding %d markers"):format(held)
end
