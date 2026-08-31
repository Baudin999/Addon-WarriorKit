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
-- hundred and fifty is past the busiest zone in the game with a full log and
-- every Questie category on; past it the picture is confetti rather than an
-- answer, and the footer says how many were left off.
local CROWD = 250

-- How big one of Questie's icons is drawn here.
--
-- Its own number rather than Questie's. Questie scales its icons off the
-- client's map, which is a canvas that zooms, and this chart zooms the picture
-- under marks that stay the same size on purpose: a mark is a thing you look
-- for on a screen and it wants the same pixels at every zoom. Fourteen is about
-- what Questie draws at the client's default scale.
local BADGE = 14

-- One of Questie's modules, or nil. The same accessor and the same warning as
-- Quests/Where.lua's: ImportModule hands back a fresh empty table for a name it
-- has never heard of, so the module coming back proves nothing and every caller
-- checks for the field it is about to read.
local function Module(name)
	local loader = _G.QuestieLoader
	if not loader or type(loader.ImportModule) ~= "function" then
		return nil
	end
	local ok, module = pcall(loader.ImportModule, loader, name)
	if not ok or type(module) ~= "table" then
		return nil
	end
	return module
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
	}
end

--------------------------------------------------------------------------
-- The two registers
--------------------------------------------------------------------------

-- One bag of frame names into the list. Questie keys the quest register by
-- name and fills the manual one by position, and pairs walks both.
local function Take(into, names, map)
	if type(names) ~= "table" then
		return 0
	end
	local took = 0
	for _, name in pairs(names) do
		if #into >= CROWD then
			return took
		end
		local point = type(name) == "string" and Read(name, map)
		if point then
			into[#into + 1] = point
			took = took + 1
		end
	end
	return took
end

local function FromQuests(into, register, map)
	for _, names in pairs(register) do
		Take(into, names, map)
	end
end

-- Everything Questie puts on a map that is not one of your quests: the flight
-- masters, the trainers, the vendors, whatever its menu has switched on. Nested
-- one deeper than the quest register, kind then id then names.
local function FromManual(into, register, map)
	for _, byId in pairs(register) do
		if type(byId) == "table" then
			for _, names in pairs(byId) do
				Take(into, names, map)
			end
		end
	end
end

--------------------------------------------------------------------------

-- Every marker Questie has for one zone.
--
-- An empty list is the ordinary answer rather than a failure, and there are
-- four ways to get one: Questie is not installed, its database has not compiled
-- yet, it has drawn nothing for this zone, or its own settings have every
-- category switched off. Pins.Describe is what tells them apart.
function Pins.Of(map)
	local out = {}
	if type(map) ~= "number" then
		return out
	end
	local questie = Module("QuestieMap")
	if not questie then
		return out
	end
	if type(questie.questIdFrames) == "table" then
		FromQuests(out, questie.questIdFrames, map)
	end
	if type(questie.manualFrames) == "table" then
		FromManual(out, questie.manualFrames, map)
	end
	return out
end

-- You, as a point the chart draws as the client's own arrow rather than in
-- somebody else's art. Nothing at all on a map you are not standing on, which
-- is every zone but one.
function Pins.You(map)
	local here, x, y = Chart.Here()
	if here ~= map or type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	return { x = x, y = y, kind = Chart.YOU, name = "you",
		note = { ("%.1f, %.1f"):format(x, y) } }
end

-- How many markers Questie is holding altogether, which is the number that says
-- whether it has finished drawing rather than whether this zone has anything in
-- it.
function Pins.Held()
	local questie = Module("QuestieMap")
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
	if not Module("QuestieMap") then
		return "Questie is not answering, so the map has no markers on it"
	end
	local held = Pins.Held()
	if held == 0 then
		return "Questie is loaded and has drawn no markers yet"
	end
	return ("reading Questie, which is holding %d markers"):format(held)
end
