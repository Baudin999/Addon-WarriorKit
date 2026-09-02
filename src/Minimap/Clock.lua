local ADDON, ns = ...

--------------------------------------------------------------------------
-- The clock
--
-- Blizzard's went with the rest of the minimap furniture, and it had to. It
-- draws its numbers on a strip of the old stone tile, so on a square map with
-- the ring stripped it was the last piece of Blizzard art on the screen,
-- hanging under the bottom edge looking like the one bit of the round map that
-- survived. Minimap/Shape.lua takes it off. This puts the reading back.
--
-- A tab, not a box beside the map. It hangs off the middle of the bottom of
-- the bezel and shares its top row of pixels with the bezel's bottom edge, and
-- the seam between the two is painted out, so the hairline runs round the map
-- and the clock together as one silhouette. That join is the whole reason this
-- is a file rather than four lines in Shape.lua.
--
-- What it says is local time. Blizzard's could be told to say either and
-- shipped saying the realm's, which is the time an addon needs and not the
-- time a person does; the realm's is one hover away. The twelve hour toggle is
-- read off the client's own CVar, because a player who set it set it for a
-- clock and this is the clock now.
--
-- The tick looks once a second and writes twice an hour. Everything else it
-- does is one string comparison.
--------------------------------------------------------------------------

local Clock = {}
ns.MinimapClock = Clock

local UI = ns.UI
local C = UI.Color

-- The black under the numbers is the bezel's own thickness, so the tab reads as
-- the same piece of furniture rather than as something stuck to it. SIDE is
-- wider because a number wants air at its ends, and a hairline three pixels off
-- a glyph reads as a box that did not fit.
local PAD = 3
local SIDE = 6

-- The smallest the tab is drawn, in the map's own units.
--
-- GetStringWidth on a font string the client has not laid out yet answers zero,
-- and a tab sized off that is a black speck under the map. These are what the
-- panel font needs for the widest reading either format can produce, and they
-- are the floor rather than the size, so a client whose text engine does answer
-- gets the tab its own font asked for.
local FLOOR_WIDTH, FLOOR_HEIGHT = 46, 16

-- How often the reading is looked at, which is not how often it is written. A
-- clock that says minutes has to be right within a second of the turn and there
-- is nothing to gain by asking more often than that.
local INTERVAL = 1

-- The widest reading each format can produce, which is what the tab is measured
-- against. Measuring the current reading instead would make it a tab that
-- changes width at ten o'clock.
local WIDEST = { [true] = "88:88", [false] = "88:88 PM" }

local frame, text, last
local military = true

--------------------------------------------------------------------------
-- What it says
--------------------------------------------------------------------------

-- Twenty four hours unless the client's own clock was told otherwise.
--
-- Absent reads as twenty four rather than as twelve. A client with no such CVar
-- is one whose clock never offered the choice, and a twenty four hour reading
-- is one everybody can parse, where a wrong guess the other way puts a pm on
-- the wrong half of the day.
local function Format()
	if type(GetCVar) ~= "function" then
		return true
	end
	local ok, value = pcall(GetCVar, "timeMgrUseMilitaryTime")
	if not ok or value == nil then
		return true
	end
	return value ~= "0"
end

-- What the face says. On the tick, so it is one date call, and on the twelve
-- hour side one gsub to take off a leading zero no clock a person reads has.
function Clock.Reading()
	if military then
		return date("%H:%M")
	end
	local reading = date("%I:%M %p")
	return (reading:gsub("^0", ""))
end

-- The realm's own time, which is the one an invite is quoted in. GetGameTime
-- answers it as two numbers rather than as a string, and it is probed for the
-- reason every name in this folder is probed: nothing installed here proves a
-- backported interface carries it.
function Clock.Realm()
	if type(GetGameTime) ~= "function" then
		return nil
	end
	local ok, hour, minute = pcall(GetGameTime)
	if not ok or type(hour) ~= "number" or type(minute) ~= "number" then
		return nil
	end
	if military then
		return ("%02d:%02d"):format(hour, minute)
	end
	local twelve = hour % 12
	if twelve == 0 then
		twelve = 12
	end
	return ("%d:%02d %s"):format(twelve, minute, hour >= 12 and "PM" or "AM")
end

--------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------

-- What the face has no room for. This clock is not a setting, so the reading it
-- does not show is a hover away rather than gone.
local function Hover(w)
	w:EnableMouse(true)
	ns.Tip.Hang(w, function()
		local lines = { { "Local", Clock.Reading() } }
		local realm = Clock.Realm()
		if realm then
			lines[#lines + 1] = { "Realm", realm }
		end
		return {
			kind = "note",
			title = date("%A, %d %B %Y"),
			lines = lines,
		}
	end)
end

local function Build()
	local bezel = ns.MinimapShape.Bezel()
	if not bezel then
		return false
	end

	-- Named, the way the corral's face next door is named, because a frame a
	-- player can point at is a frame they can name back in a bug report and one
	-- /framestack can find.
	frame = CreateFrame("Frame", "WarriorKitClock", bezel)
	local px = ns.Pixel(frame)
	frame.bg = ns.Fill(frame, "BACKGROUND", C.window[1], C.window[2], C.window[3],
		C.window[4])
	frame.bg:SetAllPoints()
	frame.edges = ns.Outline(frame, C.hairline[1], C.hairline[2], C.hairline[3], 1)
	ns.EdgeSize(frame.edges, px)

	-- One pixel of overlap, so the tab's top edge and the bezel's bottom edge
	-- land in the same row rather than in two rows with a line of world between
	-- them.
	frame:SetPoint("TOP", bezel, "BOTTOM", 0, px)

	text = UI.Label(frame, UI.Metric.font, C.text, "CENTER", UI.FLAT)
	text:SetPoint("CENTER")

	-- The seam. The bezel's bottom edge is already covered, because a child
	-- frame draws over its parent whatever layer either of them is on, and the
	-- tab's own background is that child. What is left is the tab's own top
	-- edge, and this is one band of the fill colour laid over it, inset a pixel
	-- at each end so the outline still turns both corners and the two boxes read
	-- as one shape.
	frame.seam = ns.Fill(frame, "ARTWORK", C.window[1], C.window[2], C.window[3],
		C.window[4])
	frame.seam:SetPoint("TOPLEFT", frame, "TOPLEFT", px, 0)
	frame.seam:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -px, 0)
	frame.seam:SetHeight(px)

	Hover(frame)
	return true
end

--------------------------------------------------------------------------

-- Read the format, size the tab to the widest reading it can produce, and put
-- the current one on it. Run at login and again whenever the twelve hour toggle
-- moves, never on a tick.
function Clock.Apply()
	if not frame and not Build() then
		return false
	end

	military = Format()
	last = nil

	local px = ns.Pixel(frame)
	text:SetText(WIDEST[military])
	frame:SetSize(
		math.max(FLOOR_WIDTH, text:GetStringWidth() + SIDE * 2 * px),
		math.max(FLOOR_HEIGHT, text:GetStringHeight() + PAD * 2 * px))

	Clock.Update()
	return true
end

-- One comparison, and a write on the two ticks an hour where it fails.
function Clock.Update()
	if not text then
		return false
	end
	local reading = Clock.Reading()
	if reading ~= last then
		last = reading
		text:SetText(reading)
		return true
	end
	return false
end

-- What the tab is showing, for the panel and for /wk status. Nil until it has
-- been built, which is the state a client with no Minimap frame stays in.
function Clock.Describe()
	if not frame then
		return nil
	end
	return last
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")

-- Off with the square. The tab is parented to the bezel, so it is already off
-- the screen; this is so that a hidden clock is not also a string comparison
-- five thousand times an evening.
local function Tick()
	if ns.db and ns.db.minimapSquare then
		Clock.Update()
	end
end

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CVAR_UPDATE")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		Clock.Apply()
		-- The ticker lives on this frame, which is never hidden. On the tab it
		-- would stop the moment the square went off and never start again.
		ns.UI.Ticker(events, INTERVAL, "clock", Tick)
	elseif frame and Format() ~= military then
		-- CVAR_UPDATE carries every CVar the client writes. The one this file
		-- has a stake in is the twelve hour toggle, and it changes both what the
		-- reading says and how wide the widest one is, so it is a rebuild rather
		-- than a repaint. Everything else is compared away here.
		Clock.Apply()
	end
end)
