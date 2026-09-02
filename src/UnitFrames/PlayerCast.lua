local ADDON, ns = ...

local PlayerCast = {}
ns.PlayerCast = PlayerCast

--------------------------------------------------------------------------
-- Your own cast bar
--
-- The last thing on this screen that was still Blizzard's. Every unit around
-- you is drawn by this addon and the one bar you are timing a press against
-- was a 2007 gold frame sitting under a HUD that has none, which is the single
-- loudest mismatch left in the interface.
--
-- A bar of its own rather than a chamber under the player block, and that is
-- the whole design decision in this file. The enemy row opens downward out of
-- the bar it belongs to because a mob's cast is one more thing about that mob.
-- Yours is not: under the player block is where your debuff row hangs, and a
-- chamber opening there would push that row down and pull it back up on every
-- cast, which is the row moving every time the fight gets interesting. So this
-- is furniture, placed once by dragging it, the same as the swing bars and the
-- meters. It ships under them on purpose. Charge icon, swing bars, cast bar is
-- one column of things you time a press against, and they read as one
-- instrument because they are the same width.
--
-- Almost nothing here is a second opinion about what a cast is.
-- UnitFrames/Cast.lua already owns four answers and this file asks it for all
-- of them: whether there is a cast worth drawing, how far along it is, what
-- the seconds left say, and what an unlocked frame previews. That file draws
-- the same cast in a different rectangle, and the two cannot disagree about a
-- channel draining backwards or about a bar sitting full for a fifth of a
-- second after the cast ended, because neither of them decides it.
--
-- What is this file's own is the half a mob's cast bar has no use for: the one
-- that failed. Interrupted, moved out of, or refused, your cast stops and the
-- bar goes red and holds for most of a second rather than vanishing, because a
-- cast that disappeared and a cast that finished look identical on a bar that
-- only ever empties. On a warrior that is Slam, which is the one cast in the
-- rotation and the one Swing/Slam.lua exists to time, so it is worth the hold.
--
-- Two rates, the same split every moving bar in this addon has. The client is
-- asked five times a second and again on every cast event, which is what puts
-- a bar up; the fill and the seconds move on every frame. See the head of
-- Swing/Gauges.lua for why the second one is not on a ticker.
--------------------------------------------------------------------------

local Cast = ns.Cast
local Gauge = ns.UI.Gauge
local Color = ns.Unit.Color

local FRAME_NAME = "WarriorKitPlayerCast"

-- How often the client is asked, which is the rate every readout in this addon
-- runs at. The events below are what make a cast appear at once rather than up
-- to a fifth of a second late; this is the belt behind them, because the
-- UNIT_SPELLCAST names are not proven on both of these clients and a missed
-- one would be a bar that never came up rather than a bar that came up slowly.
local POLL = 0.2

-- How long a cast that did not finish stays on the screen after it stopped.
--
-- Long enough to read across a pull and short enough that it is gone before
-- the next Slam, which at any weapon speed in this era is well over a second.
local HOLD = 0.7

local PAD = 5
local TEXT_FLOOR = 7
local TEXT_CEILING = 14

-- The glyph's share of the bar's height. Under the height less two hairlines at
-- every size the bar is allowed to be, so the name never lies across either
-- edge of the bar it is written in.
local TEXT_SHARE = 0.62

-- What the bar is allowed to be, shared with the panel and the slash word so
-- all three clamp to the same numbers.
local WIDTH_LOW, WIDTH_HIGH = 90, 400
local HEIGHT_LOW, HEIGHT_HIGH = 10, 40

local OPEN = Color.cast.open
local LOCKED = Color.cast.locked

-- A cast that stopped without finishing. Red out of the shared palette rather
-- than a fourth entry in Color.cast: that table is documented as what a cast on
-- something you can attack looks like, and this is the one state only your own
-- cast has. The hue is already held to the contrast floor, because the threat
-- and reaction ladders both carry the same table.
local FAILED = Color.hue.red

-- The frame round the bar, which is the palette's own answer for a frame round
-- a bar and is what the enemy bars draw. An edge is chrome: the fill carries
-- the colour and the rim only has to hold the bar off the world behind it.
local EDGE = Color.frame.idle

local NAME_TEXT = Color.text.name
local TIMER_TEXT = Color.text.value

local frame, bar, spellName, timer, place
local built = false

-- One design pixel in this frame's units, which is exactly 1 once ns.UI.Adopt
-- has taken the frame onto the grid. Read again on every layout pass rather
-- than once at login, because off the grid it is a fraction of the screen
-- height and a monitor swap moves it.
local unit = 1

-- What is on the bar. One table rather than eight upvalues, so the tick's
-- guards and the clear that undoes them are the same list read twice.
--
--   spell    the text drawn on the left, guarded against being written again
--   note     the text drawn on the right, which is the seconds left or the
--            word that says why the bar stopped
--   look     the colour table last painted, compared by identity
--   start    when the cast began, in GetTime seconds
--   finish   when it ends
--   channel  whether the fill drains rather than fills
--   tenths   the tenth of a second last drawn, which is what the timer is
--            guarded on: a cast has about fifteen of them and this runs on
--            every frame
--   preview  the bar is drawing a cast this file made up, because the frames
--            are unlocked
--   hold     a failed cast is on the screen until this GetTime second
local drawn = {}

--------------------------------------------------------------------------
-- The guarded writes
--
-- Everything the tick reaches goes through one of these three. Each costs one
-- comparison in the common case, which on this bar is every frame of a cast
-- for the name and the colour and nine frames in ten for the number.
--------------------------------------------------------------------------

local function Look(color)
	if drawn.look ~= color then
		drawn.look = color
		Gauge.Paint(bar, bar.track, color)
	end
end

local function Spell(text)
	if drawn.spell ~= text then
		drawn.spell = text
		spellName:SetText(text)
	end
end

local function Note(text)
	if drawn.note ~= text then
		drawn.note = text
		timer:SetText(text)
	end
end

-- Everything the bar was carrying, forgotten, and the bar taken down.
--
-- Every field is cleared rather than the ones that look like they matter. The
-- guards above are the reason: a field left behind is a write that will not
-- happen the next time the same value comes round, and the symptom is a bar
-- showing the last cast's name for the length of this one.
function PlayerCast.Clear()
	if not built then
		return
	end
	drawn.spell, drawn.note, drawn.look = nil, nil, nil
	drawn.start, drawn.finish, drawn.channel = nil, nil, nil
	drawn.tenths, drawn.preview, drawn.hold = nil, nil, nil
	frame:Hide()
end

-- A cast onto the bar, from the client's answer or from the preview, so the
-- preview really is a preview: it goes through the same drawing rather than
-- through a second copy of it that can drift.
local function Draw(now, spell, start, finish, channel, immune)
	-- Plain fields on a table, unguarded on purpose: comparing three numbers to
	-- save writing three numbers is the guard costing more than the write.
	drawn.start, drawn.finish, drawn.channel = start, finish, channel
	drawn.hold = nil

	Spell(spell)
	Look(immune and LOCKED or OPEN)

	-- The fill's first frame, written here rather than left to the sweep. A bar
	-- that comes up carrying the last cast's position and corrects itself one
	-- frame later is a bar that jumps at the exact moment you started looking
	-- at it.
	bar:SetValue(Cast.Fraction(start, finish, now, channel)) -- unguarded: the moving edge, and there is nothing on a bar that was down to compare it against

	if not frame:IsShown() then
		frame:Show()
	end
end

--------------------------------------------------------------------------
-- What the client says, and what to do about it
--------------------------------------------------------------------------

-- Five times a second and again on every cast event. Everything that decides
-- whether there is a bar at all is here; the sweep below only moves what this
-- put up.
function PlayerCast.Update(now)
	if not built or not ns.db then
		return
	end
	if not ns.db.playerCast then
		PlayerCast.Clear()
		return
	end

	-- Unlocked, the bar previews itself and the client is not asked at all. A
	-- cast bar is empty almost all of the time, so "unlock the frames and drag
	-- it" would otherwise mean dragging a rectangle you cannot see.
	if not ns.db.locked then
		drawn.preview = true
		Draw(now, Cast.Preview(now))
		return
	end
	if drawn.preview then
		-- Locked again. Cleared rather than left to fall through, because what
		-- is on the bar is a cast this file made up and the branch below would
		-- leave it there until you happened to cast something.
		PlayerCast.Clear()
	end
	if drawn.hold then
		return -- a failed cast is holding, and the sweep is what takes it off
	end

	local spell, start, finish, channel, immune = Cast.Live("player", now)
	if not spell then
		if frame:IsShown() then
			PlayerCast.Clear()
		end
		return
	end

	Draw(now, spell, start, finish, channel, immune)
end

-- A cast that stopped without finishing, named by the event that stopped it.
--
-- Nothing happens where the bar was already down, which is most of what these
-- events are: UNIT_SPELLCAST_FAILED is also what the client says when a press
-- was refused before anything started, and a red bar for a spell that never
-- began is the addon inventing a cast to report the failure of.
function PlayerCast.Fail(word)
	if not built or not ns.db or not ns.db.playerCast then
		return
	end
	if drawn.preview or not drawn.start or not frame:IsShown() then
		return
	end
	drawn.hold = GetTime() + HOLD
	Look(FAILED)
	Note(word)
	-- So the seconds are written again if another cast lands inside the hold.
	drawn.tenths = nil
end

-- The moving edge, on every frame, and the only thing this file draws that is
-- not a readout.
--
-- The fill is written as a fraction with nothing in front of it, for the reason
-- the head of Swing/Gauges.lua sets out: a rounded fill is a throttle as well
-- as a quantiser, and an animation is drawn on the frame the screen is drawn on
-- or it is drawn in steps.
--
-- A cast that has run out of time is over here rather than at the next poll.
-- The client would say so within a fifth of a second, and a fifth of a second
-- is exactly what a bar sitting full at the end of a cast looks like.
function PlayerCast.Sweep(now)
	if not built or not frame:IsShown() then
		return
	end

	-- A failed cast holds where it stopped. Nothing is written while it does,
	-- which is the point: the bar you are looking at is the bar as it was at
	-- the moment the cast died.
	if drawn.hold then
		if now >= drawn.hold then
			PlayerCast.Clear()
		end
		return
	end

	-- A preview rolls over instead of ending, because the poll is up to a fifth
	-- of a second away and a fifth of a second of empty bar on every loop is
	-- the flicker a preview exists to rule out.
	if drawn.preview and drawn.finish - now <= 0 then
		Draw(now, Cast.Preview(now))
	end

	local left = drawn.finish - now
	if left <= 0 then
		PlayerCast.Clear()
		return
	end

	bar:SetValue(Cast.Fraction(drawn.start, drawn.finish, now, drawn.channel)) -- unguarded: the moving edge, and a frame it does not write is a frame it does not move on

	-- Guarded on the tenth that gets drawn rather than on the float behind it.
	local tenths = math.floor(left * 10)
	if drawn.tenths ~= tenths then
		drawn.tenths = tenths
		Note(Cast.Seconds(tenths))
	end
end

--------------------------------------------------------------------------
-- Building and laying out
--------------------------------------------------------------------------

local function Build()
	frame = CreateFrame("Frame", FRAME_NAME, UIParent)
	ns.UI.Adopt(frame, ns.db.playerCastZoom)
	unit = ns.UI.Unit(frame)
	place = ns.UI.Placeable(frame, {
		name = "WarriorKit cast",
		moved = function(anchor)
			ns.db.playerCastPoint = anchor
			PlayerCast.Apply()
		end,
	})

	bar = Gauge.New(frame)
	-- Pinned to one corner and given a size by the layout rather than stretched
	-- across the frame, which is what the swing bars do and is the same
	-- decision: a frame sized by two opposing anchors has a rectangle only the
	-- client knows, and every size in this addon is one the addon can measure.
	bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	bar:SetMinMaxValues(0, 1)
	-- Made after the fill, because within one draw layer the order is the order
	-- the textures were made and this one has to stay on top of both of them.
	bar.edges = ns.Outline(bar, EDGE[1], EDGE[2], EDGE[3], 1, "OVERLAY")

	-- Both on the bar rather than on the frame, so they sit over the fill. Flat
	-- and unshadowed: this is an opaque surface the addon painted itself, which
	-- is the whole of what ns.UI.FLAT means.
	spellName = ns.UI.Label(bar, TEXT_CEILING, NAME_TEXT, "LEFT", ns.UI.FLAT)
	timer = ns.UI.Label(bar, TEXT_CEILING, TIMER_TEXT, "RIGHT", ns.UI.FLAT)
	-- Hung off the gauge under the names UnitFrames/Cast.lua gives the same two
	-- strings, for the reason PlayerCast.Bar exists: what was written on the bar
	-- has to be readable from the harness and from a macro, and the alternative
	-- is this file handing out its own state table.
	bar.spell, bar.timer = spellName, timer

	frame:Hide()
	built = true
end

-- Everything a setting can move. Called at login, whenever a number in the
-- panel changes and whenever the grid moves under the frame. Never from the
-- tick.
function PlayerCast.Apply()
	if not built or not ns.db then
		return
	end

	local point = ns.db.playerCastPoint
	frame:ClearAllPoints()
	frame:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	ns.UI.Rezoom(frame, ns.db.playerCastZoom)
	unit = ns.UI.Unit(frame)

	local width, height = ns.db.playerCastWidth, ns.db.playerCastHeight
	frame:SetSize(width * unit, height * unit)
	bar:SetSize(width * unit, height * unit)
	-- One screen pixel, and one at every zoom, which is what ns.Pixel answers
	-- and ns.UI.Unit does not.
	ns.EdgeSize(bar.edges, ns.Pixel(bar))

	-- Taken off the bar's height rather than fixed, because the bar is a
	-- setting: the same code draws a ten pixel line and a forty pixel block.
	-- Floored at seven, under which nothing is legible and the bar should be
	-- made taller instead.
	local size = math.max(TEXT_FLOOR,
		math.min(TEXT_CEILING, math.floor(height * TEXT_SHARE)))
	-- Raw, not in units. Everything else here is a design pixel multiplied by
	-- the zoom and a font size is the one thing that is not: inside a frame
	-- ns.UI.Adopt has taken onto the grid, a font size already is a pixel
	-- height. Multiplied, this asked for a fraction at any UI scale that is not
	-- a whole number of pixels, SetFont refuses one, and the readback in
	-- UI/Text.lua then failed its fallback too and handed back a font object
	-- with no font on it. The bar drew no spell name and no seconds.
	local font = ns.UI.Font(size, ns.UI.FLAT)
	spellName:SetFontObject(font)
	timer:SetFontObject(font)

	timer:ClearAllPoints()
	timer:SetPoint("RIGHT", bar, "RIGHT", -PAD * unit, 0)
	-- Pinned to the number rather than given a width, so a long spell name
	-- yields to the seconds left. The seconds are the half you act on.
	spellName:ClearAllPoints()
	spellName:SetPoint("LEFT", bar, "LEFT", PAD * unit, 0)
	spellName:SetPoint("RIGHT", timer, "LEFT", -PAD * unit, 0)

	-- The fonts and the sizes moved, so whatever the tick last wrote was
	-- measured against the old ones and every guard above would keep it.
	-- Losing a fifth of a second of one cast to a setting change costs nothing
	-- that a second list of fields to keep true would not cost more of.
	PlayerCast.Clear()
	PlayerCast.Lock()
end

-- Locked is the normal state. Unlocked the bar takes the mouse, draws a rim and
-- carries its own name, because a bar that is empty almost all of the time is
-- otherwise a piece of screen you have to find from memory.
function PlayerCast.Lock()
	if not built then
		return
	end
	place:Lock(not ns.db.locked)
	PlayerCast.Update(GetTime())
end

function PlayerCast.Reset()
	ns.db.playerCastPoint = ns.DefaultCopy("playerCastPoint")
	PlayerCast.Apply()
end

-- What the bar is allowed to be. One source for the panel's two sliders and the
-- clamp the slash word goes through, because two copies of a range is two
-- chances for one of them to accept a number the other would refuse.
function PlayerCast.SizeRange()
	return WIDTH_LOW, WIDTH_HIGH, HEIGHT_LOW, HEIGHT_HIGH
end

-- The bar itself, for scripts/harness.lua and for a macro. Handed out rather
-- than kept private for the reason SwingGauges.Bar is: the harness has to
-- measure what was drawn, and there is no other way to reach it.
function PlayerCast.Bar()
	return bar
end

--------------------------------------------------------------------------

-- One line for /wk status and for the panel.
function PlayerCast.Describe()
	if not ns.db.playerCast then
		if ns.db.hideBlizzPlayerCast then
			return "off, and Blizzard's own is hidden, so nothing draws your casts"
		end
		return "off, and Blizzard's own cast bar is where it always was"
	end
	if not ns.HasCastInfo() then
		return "|cffd08040this client answers no UnitCastingInfo|r, so the bar never draws"
	end
	if not ns.db.locked then
		return "on, and previewing itself because the frames are unlocked: a cast,"
			.. " then a channel, five seconds around"
	end
	return ("on, %d by %d pixels, and a cast that is interrupted or moved out of"
		.. " holds red for %.1f seconds rather than vanishing")
		:format(ns.db.playerCastWidth, ns.db.playerCastHeight, HOLD)
end

--------------------------------------------------------------------------
-- The tick and the events
--
-- The ticker lives on the event frame, which is never hidden. On the bar it
-- would stop the moment the bar came down and never come back, which is the
-- trap Charge/Icon.lua and Swing/Gauges.lua both carry a note about. Sweep's
-- first line is what makes a bar that is down free anyway.
--------------------------------------------------------------------------

local elapsed = 0

local function OnUpdate(_, delta)
	if not built then
		return
	end
	ns.Perf.Start("playercast")
	elapsed = elapsed + delta
	if elapsed >= POLL then
		elapsed = 0
		PlayerCast.Update(GetTime())
	end
	PlayerCast.Sweep(GetTime())
	ns.Perf.Stop("playercast")
end

-- What the client says about your own casting, and what each one means here.
--
-- Every name is registered through pcall and filtered to the player where the
-- client can filter, the same as Swing/Gauges.lua does with the two it takes.
-- None of these is proven on both of the clients this addon ships for, and a
-- name one of them has never heard of refuses the registration rather than
-- raising. What that costs is nothing: the poll above asks the client five
-- times a second regardless, so a missing event is a bar up to a fifth of a
-- second late and not a bar that never comes up.
local WATCHED = {
	"UNIT_SPELLCAST_START",
	"UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_CHANNEL_STOP",
}

-- The two that are not a change of state but a reason, so each carries the word
-- the bar draws. Written in this addon's own English rather than taken from a
-- client global, the same as everything else it says.
local STOPPED = {
	UNIT_SPELLCAST_INTERRUPTED = "interrupted",
	UNIT_SPELLCAST_FAILED = "failed",
	UNIT_SPELLCAST_FAILED_QUIET = "failed",
}

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")

-- pcall'd because a client that does not carry one of these seven raises on
-- the register rather than answering, and the other six are worth having.
local function Watch(event)
	pcall(ns.RegisterUnitEvent, events, event, "player")
end

for index = 1, #WATCHED do
	Watch(WATCHED[index])
end
for event in pairs(STOPPED) do
	Watch(event)
end

events:SetScript("OnEvent", function(_, event, token)
	if event == "PLAYER_LOGIN" then
		Build()
		PlayerCast.Apply()
		events:SetScript("OnUpdate", OnUpdate)
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		PlayerCast.Apply()
		return
	end
	-- Filtered here as well as at registration, because a client with no
	-- RegisterUnitEvent hands over every unit's casts and the pet's are not
	-- yours.
	if token ~= nil and token ~= "player" then
		return
	end
	if STOPPED[event] then
		PlayerCast.Fail(STOPPED[event])
		return
	end
	PlayerCast.Update(GetTime())
end)

-- A resolution change moves every size in this file at once, the same way it
-- moves the swing bars under it.
ns.UI.OnRescale(function()
	PlayerCast.Apply()
end)
