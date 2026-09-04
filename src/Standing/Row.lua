local ADDON, ns = ...

local Row = {}
ns.StandingRow = Row

--------------------------------------------------------------------------
-- The row
--
-- One square per slot your class owns, in the order the plan writes them, in
-- the same place every time. Standing.lua says what is in each one and this
-- file decides when the row is on the screen and what a square looks like.
--
-- Four decisions, and each one is the row rather than a detail of it.
--
-- The empty slots are drawn. That is the opposite of what the client does and
-- it is the whole feature: Blizzard's row is as long as the number of totems
-- you have out, so the square in the second place is a different totem every
-- time you glance at it and the row has no shape to learn. Four fixed places
-- have one, and after a week the answer to "where is my Windfury" is a
-- position rather than a name. It also means the row says the thing a shifting
-- row cannot say at all, which is what is missing.
--
-- An empty slot is told apart by its colour and by nothing else. There is no
-- caption under the row and no letter on the square: the element is a colour on
-- the hairline, learned once, and four short words under four squares would be
-- more text than the row has information. Which colour is which is the class
-- file's to say, because a stance row will hand this one three different
-- colours and this file has no opinion about either set.
--
-- It is up in a fight, and out of one only while something is still standing.
-- That is the cooldown row's rule rather than the buff nag's, and for the same
-- reason: what is up is a question you ask again thirty seconds later, so a row
-- that appeared the moment something went wrong would arrive exactly when you
-- had stopped needing it. Everything down and no fight is the resting state and
-- the row is not there for it, because a row of four holes over your character
-- while you walk to the next pull is furniture. `/wk totems idle on` keeps it
-- up anyway.
--
-- Built out of UI\Aura.lua rather than UI\Ability.lua, which is the one choice
-- here that is not obvious. A totem is not a press. It has no cost, no range
-- and no stance, its sweep fills as it runs out rather than emptying as it
-- comes back, and the number over it is the thing you actually read. That is
-- the aura square's whole vocabulary and none of it is the ability square's.
--------------------------------------------------------------------------

local FRAME_NAME = "WarriorKitStanding"

-- 27, and the same number for the same reason Buffs\Nag.lua and
-- Cooldowns\Row.lua carry it: the client stores a spell icon at 64 texels,
-- UI\Draw.lua crops the five texel border off each edge, and the 54 that are
-- left resample exactly onto 54 pixels or onto 27 and nothing in between.
local ICON = 27
local GAP = 4

-- What the two numbers on a square may not grow past, which is UI\Aura.lua's
-- argument rather than this file's: a fourteen pixel timer over a sixteen pixel
-- icon covers the art it is annotating. The same pair the aura rows under the
-- unit frames pass, so a totem's seconds and a debuff's seconds are the same
-- size at the same square size.
local TIMER_CEILING, COUNT_CEILING = 14, 11

local REFRESH = 0.1

local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost

local frame, place
local icons = {}
local built = false
local unit = 1
local px = 1

-- The frame the events and the tick hang off, and the tick itself. Declared
-- here rather than at the foot of the file because Row.Apply is what arms and
-- stops the tick and is written above where they are made.
local events, tick

-- What Place last laid out, so a tick that changes nothing does no work. The
-- three values are the cooldown row's three and carry that file's reasoning:
-- `mode` is why the row is on the screen, `seen` is which build of the list was
-- laid out, and `count` is how many squares that put up.
local mode, seen, count = nil, -1, 0

--------------------------------------------------------------------------
-- What one square says to the mouse
--
-- The square is a picture and a number, which between them say what is there
-- and for how long. What the tooltip adds is the name, because a totem's art is
-- shared across its ranks and across half the element: Searing and Magma are
-- two fires and one glance.
--------------------------------------------------------------------------

-- A slot's name with a capital on it, for the title of a box. The plan writes
-- them lower case because that is how a sentence reads them, and a title is not
-- a sentence.
local function Titled(label)
	return label:sub(1, 1):upper() .. label:sub(2)
end

local function Hover(w)
	ns.Tip.Hang(w, function()
		local slot = w.slot
		-- A square with no slot behind it describes nothing, and a tooltip
		-- handed nothing does not open. Without that the previous square's
		-- sentence stays on screen pointing at this one.
		if not slot then
			return nil
		end
		if not w.present then
			return {
				kind = "note",
				title = Titled(slot.label),
				lines = { ("Nothing standing in your %s slot."):format(slot.label) },
			}
		end
		return {
			kind = "note",
			title = w.name or Titled(slot.label),
			lines = { ("Standing in your %s slot."):format(slot.label) },
		}
	end)
end

-- The click. Left button only, on the way up, and only while the square is
-- taking the mouse at all, which Place decides. The right button is already
-- handed back to the camera by ns.Tip.Hang.
--
-- It opens the page rather than dismissing the totem. Dropping one is
-- DestroyTotem, which Blizzard's own button calls from a hardware event and
-- nothing on this disk calls at all, and a call this addon has never seen
-- answered is not one to put under a square you click by accident.
local function Open(_, button)
	if button == "LeftButton" then
		ns.Options.Open(ns.Standing.Page())
	end
end

local function Press(w)
	w:SetScript("OnMouseUp", Open)
end

--------------------------------------------------------------------------
-- Laying it out
--------------------------------------------------------------------------

-- The squares the row has turned out to need. A frame cannot be destroyed on
-- these clients, so a square that has been built is kept.
local function Stock(wanted)
	for slot = #icons + 1, wanted do
		icons[slot] = ns.UI.Aura.New(frame)
		icons[slot]:Hide()
		-- The scripts go on once. Whether the square answers them is
		-- EnableMouse, written by Place every time the row changes.
		Hover(icons[slot])
		Press(icons[slot])
	end
	return #icons
end

-- cold: layout rather than tick, run when the plan is rebuilt or a setting moves.
local function Place()
	seen = ns.Standing.Epoch()
	local drawn = (mode == "quiet") and 0 or ns.Standing.Count()

	-- The preview is the row being dragged, so its squares hand the mouse back
	-- and the parent frame gets the button.
	local hoverable = mode ~= "preview"
	local wide, tall = 0, 0

	Stock(drawn)

	for index = 1, #icons do
		local w = icons[index]
		if index <= drawn then
			local slot = ns.Standing.Slot(index)
			w.slot = slot
			w:EnableMouse(hoverable)
			local side, height = ns.UI.Aura.Size(w, ICON * unit, px,
				math.floor(TIMER_CEILING * unit + 0.5),
				math.floor(COUNT_CEILING * unit + 0.5))
			ns.UI.Aura.Edge(w, slot.color)

			w:ClearAllPoints()
			w:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT",
				(index - 1) * (ICON + GAP) * unit, 0)
			w:Show()

			wide = wide + side + ((index > 1) and GAP * unit or 0)
			tall = height
		else
			w.slot = nil
			w:EnableMouse(false)
			w:Hide()
		end
	end

	count = drawn
	if drawn == 0 then
		frame:Hide()
		return
	end

	frame:SetSize(wide, tall)
	frame:Show()
end

--------------------------------------------------------------------------
-- Drawing
--
-- On the ticker. Nothing here allocates and nothing writes a value the widget
-- already carries, which UI\Aura.lua does the guarding for.
--------------------------------------------------------------------------

-- Every slot, as it was read this tick. Four lists made once at load and
-- written in place, because a table per square per tick is the allocation the
-- gate bans and this is the tick it would be on.
local present, art, expires, span, named = {}, {}, {}, {}, {}

-- Whether this tick has read them yet, cleared by Update at the top of every one.
local read = false

-- One read of every slot per tick, for the reason Cooldowns\Row.lua keeps one:
-- Wanted asks whether anything is standing, which is what puts the row on the
-- screen out of combat, and Paint asks each square what to draw. Both want the
-- same numbers and each was asking the client for its own copy.
local function Read()
	if read then
		return
	end
	read = true
	for index = 1, ns.Standing.Count() do
		local up, texture, ends, length, name = ns.Standing.State(index)
		present[index], art[index] = up, texture
		expires[index], span[index] = ends, length
		-- Into a list rather than onto the square, because Wanted reads every
		-- slot and the squares for them may not have been built yet: the first
		-- tick of a session asks what the row should be doing before Place has
		-- made anything for it to be doing it with.
		named[index] = name
	end
end

-- Is anything standing, off what Read already asked.
local function Any()
	for index = 1, ns.Standing.Count() do
		if present[index] then
			return true
		end
	end
	return false
end

local function Paint()
	Read()
	local now = GetTime()
	for index = 1, count do
		local w = icons[index]
		-- Kept on the widget for the tooltip, which is a hover rather than a
		-- tick and has nowhere else to read it from.
		w.present, w.name = present[index], named[index]
		ns.UI.Aura.Draw(w, art[index], present[index] and "mine" or "none",
			expires[index] or 0, span[index] or 0, 0, now)
	end
end

-- Why the row is on the screen, or "quiet" for the reasons it is not.
--
-- On the tick.
function Row.Wanted()
	if not ns.db.standing then
		return "quiet"
	end
	if ns.Standing.Count() == 0 then
		return "quiet"
	end
	if not ns.db.locked then
		return "preview"
	end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
		return "quiet"
	end
	Read()
	if UnitAffectingCombat("player") then
		return "fight"
	end
	if ns.db.standingIdle or Any() then
		return "standing"
	end
	return "quiet"
end

function Row.Update()
	if not built then
		return
	end

	read = false
	local want = Row.Wanted()
	if want ~= mode or seen ~= ns.Standing.Epoch() then
		mode = want
		Place()
	end

	if count > 0 then
		Paint()
	end
end

--------------------------------------------------------------------------
-- Layout, lock and reset
--
-- Everything a setting can move. At login and on a settings change, never from
-- a tick.
--------------------------------------------------------------------------

-- The tick, armed by the switch going on and stopped by it going off.
--
-- It lives on the events frame, which is never hidden. On the row itself it
-- would stop the moment the row hid and never come back, and the row is hidden
-- between every fight.
local function Beat()
	if ns.db.standing and ns.Standing.Count() > 0 then
		if not tick then
			tick = ns.UI.Ticker(ns.UI.Forever, REFRESH, "standing", Row.Update)
		elseif not tick:Running() then
			tick:Start()
		end
	elseif tick then
		tick:Stop()
	end
end

function Row.Apply()
	if not built then
		return
	end

	Beat()
	local point = ns.db.standingPoint
	frame:ClearAllPoints()
	frame:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	ns.UI.Rezoom(frame, ns.db.standingZoom)
	unit = ns.UI.Unit(frame)
	px = ns.UI.Pixel(frame)

	-- Force the next tick to lay the row out again, whatever it decides. A zoom
	-- change moves every square and the mode has not moved with it.
	mode, seen = nil, -1
	Row.Lock()
	Row.Update()
end

-- Mouse only while unlocked, which is the rule every draggable frame in the
-- addon follows: a mouse enabled frame swallows every button that lands on it,
-- including the right button drag that turns the camera.
function Row.Lock()
	if not built then
		return
	end
	place:Lock(not ns.db.locked)
end

function Row.Reset()
	ns.db.standingPoint = ns.DefaultCopy("standingPoint")
	ns.db.standingZoom = ns.DefaultCopy("standingZoom")
	Row.Apply()
end

-- One square, for scripts/harness.lua, handed out for the reason Buffs\Nag.lua
-- hands its own out: the harness has to measure what was drawn and there is no
-- honest way to do that from outside.
function Row.Icon(index)
	return icons[index]
end

function Row.Shown()
	return count
end

function Row.Mode()
	return mode
end

--------------------------------------------------------------------------

events = CreateFrame("Frame")

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELLS_CHANGED")
-- What the client says when a slot fills or empties. The row would read the
-- same answer off its own tick a tenth of a second later, and it does; this is
-- what makes the square appear on the frame the totem landed rather than on the
-- next one.
events:RegisterEvent("PLAYER_TOTEM_UPDATE")

-- Built once, and only for a class that has slots to draw.
--
-- Nothing is made at all on a class whose file wrote no plan: no frame, no
-- placeable and no ticker, which is what Charge/Icon.lua does for the same
-- reason. A hidden frame is still a frame the client walks, and a placeable one
-- is still a rectangle in the list of things `/wk unlock` puts a rim around.
--
-- Called on both login events rather than on the first, because a plan may be
-- written inside a spec and which spec you are is not reliably known at
-- PLAYER_LOGIN. A class that answers late gets its row on the next one.
local function Build()
	if built or not ns.Standing.Available() then
		return
	end

	-- Before the frame, because the name over it while you are placing it is
	-- the class's own word for the row.
	ns.Standing.Rebuild()

	frame = CreateFrame("Frame", FRAME_NAME, UIParent)
	ns.UI.Adopt(frame, ns.db.standingZoom)
	unit = ns.UI.Unit(frame)
	px = ns.UI.Pixel(frame)
	place = ns.UI.Placeable(frame, {
		name = "WarriorKit " .. ns.Standing.Word(),
		moved = function(anchor)
			ns.db.standingPoint = anchor
			Row.Apply()
		end,
	})

	built = true
	Row.Apply()
end

events:SetScript("OnEvent", function(_, event)
	if not built then
		Build()
		return
	end

	if event == "PLAYER_TOTEM_UPDATE" then
		Row.Update()
		return
	end

	-- A spec you respecced into can hand over a different plan, so both of the
	-- other events rebuild rather than refit. That is a walk of four entries,
	-- off a tick.
	ns.Standing.Rebuild()
	Row.Apply()
end)

-- A resolution change moves every size in this file at once, the same way it
-- moves the meters and the swing bars.
ns.UI.OnRescale(function()
	Row.Apply()
end)
