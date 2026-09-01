local ADDON, ns = ...

local Row = {}
ns.CooldownRow = Row

--------------------------------------------------------------------------
-- The row
--
-- Two lines. The rotation cooldowns are big squares along the top and the long
-- ones are smaller squares docked under them, with your trinkets on the end of
-- the docked line. Cooldowns.lua decides what is on both and this file decides
-- when they are on the screen and what they look like.
--
-- One frame and one walk rather than two of each, because the two lines move
-- together, are dragged together, hide together and are read in one glance.
-- Two frames would have been two anchors to save, two settings, two preview
-- states and two entries in the placing list, for a block a player thinks of as
-- one thing.
--
-- Four decisions, and each one is the row rather than a detail of it.
--
-- It is up for the whole fight. That is the opposite of the buff nag, which is
-- only there when something is wrong, and the two questions are opposites: what
-- is missing is a thing you fix and then want gone, and how long until
-- Recklessness is a thing you ask again ten seconds later. A row that appeared
-- when a cooldown became ready would be telling you at exactly the moment you
-- no longer need telling.
--
-- Out of combat it is up only while something is still recovering, which is the
-- pull-or-wait question and the only reason to look at it between fights.
-- Everything ready is the resting state, and a row that sat there saying so
-- would be furniture inside a week. `/wk cooldowns idle on` keeps it up anyway
-- for anyone who disagrees.
--
-- Ready is worth a colour here, which is why this is the one row in the addon
-- built on ns.UI.Ability.SHOUT rather than on QUIET. The action bars use the
-- quiet palette because twenty-four green squares say nothing; five squares
-- with two of them green is the answer to what have I got, read in one glance
-- without counting.
--
-- Built out of UI\Ability.lua, which already draws the square, the swipe, the
-- timer and the border that carries a status, and already guards every write it
-- makes. This file adds no drawing of its own.
--------------------------------------------------------------------------

local FRAME_NAME = "WarriorKitCooldowns"

-- Two sizes, one per line.
--
-- 27 is the number Buffs\Nag.lua and Meter\Window.lua carry: the client stores
-- a spell icon at 64 texels, UI\Draw.lua crops the five texel border off each
-- edge, and the 54 that are left resample exactly onto 54 pixels or onto 27 and
-- nothing in between. That is the docked line.
--
-- 54 is the other exact size and it is the top line. Doubling rather than
-- picking a number in between is not a preference: 40 would draw 54 texels over
-- 38 pixels, which is most of the way between the two copies the client keeps
-- and is as blended as an icon gets. The two sizes this row may use are the two
-- the art has, and the same arithmetic is written out at length in the header
-- of UnitFrames\EnemyBars.lua.
--
-- The size difference is the whole reading. A big square is a press you are
-- waiting for right now and a small one is a press you are waiting for this
-- fight, and nobody has to be told which is which.
local ICON = 27
local BIG = 54
local GAP = 4

-- Between the two lines. The same gap the squares have between them, so the
-- block reads as one thing rather than two rows that happen to be near each
-- other.
local DOCK = 4

-- What the preview draws at while you are placing the row, under one so it
-- never looks like the real thing.
local PREVIEW_FADE = 0.75

local REFRESH = 0.1

local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost

local frame, place
local icons = {}
local built = false
local unit = 1
local elapsed = 0

-- What Place last laid out, so a tick that changes nothing does no work.
--
-- Three values and the middle one is the one that is easy to leave out. `mode`
-- is why the row is on the screen, `seen` is which build of the list was laid
-- out, and `count` is how many squares that put on the screen.
--
-- Comparing the list's length against `count` instead is the bug this carries a
-- name for: a quiet row draws nothing, so `count` is zero while the list is
-- five, the two never agree, and the row lays itself out again ten times a
-- second for as long as it is hidden. Comparing lengths at all is the same bug
-- one step quieter, because a rebuild that swaps one entry for another leaves
-- the length where it was and the row would go on drawing the old one.
local mode, seen, count = nil, -1, 0

--------------------------------------------------------------------------
-- What one square says to the mouse
--
-- The row has no caption under it, which is the other difference from the buff
-- nag. A nag square is a sentence about something you did wrong and needs the
-- words; a cooldown square is a picture of an ability with a number on it and
-- the picture is the sentence. What the tooltip adds is the part a number
-- cannot carry: which of the three reasons this square is here.
--------------------------------------------------------------------------

local function Detail(w)
	local entry = w.entry
	if w.status == "cooldown" then
		local remaining = w.start + w.duration - GetTime()
		if remaining >= 60 then
			return ("Back in %d minutes or so."):format(math.floor(remaining / 60))
		end
		return ("Back in %d seconds."):format(math.ceil(remaining))
	end
	if entry.present then
		return "Running right now. This is the window you pressed it for."
	end
	if entry.slot then
		return ("Worn in trinket %d and ready. The row carries a trinket only"
			.. " while it has something to press."):format(entry.slot == ns.Gear.TRINKET1 and 1 or 2)
	end
	return "Ready. Nothing is stopping this but you."
end

local function Hover(w)
	ns.Tip.Hang(w, function()
		local entry = w.entry
		-- A square with nothing to say describes nothing, and a tooltip handed
		-- nothing does not open. Without that the previous square's sentence
		-- stays on screen pointing at this one.
		if not entry or not entry.name then
			return nil
		end
		return {
			kind = "note",
			title = entry.name,
			lines = { Detail(w) },
		}
	end)
end

--------------------------------------------------------------------------
-- Laying it out
--------------------------------------------------------------------------

-- Both lines, in one walk.
--
-- The list arrives with the rotation entries first and each one tagged, so this
-- counts along one line until the tag changes and then starts the other. That
-- is why the order in Cooldowns.All is load bearing and says so.
--
-- A line with nothing on it takes no room at all, which is what makes one shape
-- cover four: a spec with both lists draws two lines, a spec with only long
-- cooldowns draws exactly what this row drew before either layer existed, and a
-- class nobody has written a file for draws its trinkets on the docked line
-- with nothing above them.
--
-- The size is written per square here rather than for every square in Apply,
-- because which line a square is on moves when the list is rebuilt and Apply
-- runs on a settings change. Both are layout rather than tick, so neither is on
-- the path the allocation gate measures.
local function Place()
	seen = ns.Cooldowns.Epoch()
	local drawn = (mode == "quiet") and 0 or ns.Cooldowns.Count()

	-- How many squares each line carries, counted before any of them is placed.
	--
	-- Both counts are needed up front because each line is centred under the
	-- wider of the two, and a line cannot be centred until the width of the
	-- other one is known.
	--
	-- A quiet row draws none of either, whatever the list says, which is why the
	-- count is taken off `drawn` rather than off the split alone.
	local fastCount, longCount = ns.Cooldowns.Split()
	if drawn == 0 then
		fastCount, longCount = 0, 0
	end

	local fastWide = fastCount > 0 and fastCount * (BIG + GAP) - GAP or 0
	local longWide = longCount > 0 and longCount * (ICON + GAP) - GAP or 0
	local wide = math.max(fastWide, longWide)

	-- Where each line starts, so the short one sits under the middle of the long
	-- one instead of against its left edge. Two big squares over one small one
	-- was a row that read as a mistake, because nothing else in the addon hangs
	-- a shorter row off the left.
	--
	-- Floored rather than halved. An odd difference halves to x.5, and a square
	-- drawn on a half pixel is the one thing that takes the icon off the grid,
	-- which is the whole argument the two sizes above are picked by. Half a
	-- pixel of asymmetry is invisible; a blurred icon is not.
	local fastLeft = math.floor((wide - fastWide) / 2)
	local longLeft = math.floor((wide - longWide) / 2)

	-- Whether there is a top line at all, because it decides where the docked
	-- line sits.
	local topped = fastCount > 0
	local dock = topped and -(BIG + DOCK) or 0

	-- The preview is the row being dragged, so its squares hand the mouse back
	-- and the parent frame gets the button.
	local hoverable = mode ~= "preview"
	local fast, long = 0, 0

	for slot = 1, #icons do
		local w = icons[slot]
		if slot <= drawn then
			local big = ns.Cooldowns.Layer(slot) == ns.Cooldowns.ROTATION
			local edge = big and BIG or ICON

			w.entry = ns.Cooldowns.Entry(slot)
			w:EnableMouse(hoverable)
			ns.UI.Ability.Size(w, edge * unit)
			local x
			if big then
				x = fastLeft + fast * (BIG + GAP)
			else
				x = longLeft + long * (ICON + GAP)
			end

			w:ClearAllPoints()
			w:SetPoint("TOPLEFT", frame, "TOPLEFT", x * unit,
				(big and 0 or dock) * unit)
			w:Show()

			if big then
				fast = fast + 1
			else
				long = long + 1
			end
		else
			w.entry = nil
			w:EnableMouse(false)
			w:Hide()
		end
	end

	count = drawn
	if drawn == 0 then
		frame:Hide()
		return
	end

	local tall = (topped and BIG or 0)
		+ ((topped and longCount > 0) and DOCK or 0)
		+ (longCount > 0 and ICON or 0)

	frame:SetSize(wide * unit, tall * unit)
	frame:Show()
end

--------------------------------------------------------------------------
-- Drawing
--
-- On the ticker. Nothing here allocates and nothing writes a value the widget
-- already carries, which UI\Ability.lua does the guarding for.
--------------------------------------------------------------------------

local function Paint()
	local fade = (mode == "preview") and PREVIEW_FADE or 1
	for slot = 1, count do
		local w = icons[slot]
		local status, start, duration, active = ns.Cooldowns.State(slot)
		w.fade = fade
		-- Kept on the widget for the tooltip, which is a hover rather than a
		-- tick and has nowhere else to read them from.
		w.status, w.start, w.duration = status, start, duration
		ns.UI.Ability.Draw(w, w.entry and w.entry.texture, status, start, duration,
			nil, active)
	end
end

-- Why the row is on the screen, or "quiet" for the reasons it is not.
--
-- On the tick.
function Row.Wanted()
	if not ns.db.cooldowns then
		return "quiet"
	end
	if not ns.db.locked then
		return "preview"
	end
	if ns.Cooldowns.Count() == 0 then
		return "quiet"
	end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
		return "quiet"
	end
	if UnitAffectingCombat("player") then
		return "fight"
	end
	if ns.db.cooldownIdle or ns.Cooldowns.Busy() then
		return "waiting"
	end
	return "quiet"
end

function Row.Update()
	if not built then
		return
	end

	local want = Row.Wanted()
	if want ~= mode or seen ~= ns.Cooldowns.Epoch() then
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

function Row.Apply()
	if not built then
		return
	end

	local point = ns.db.cooldownPoint
	frame:ClearAllPoints()
	frame:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	ns.UI.Rezoom(frame, ns.db.cooldownZoom)

	-- The sizes are not written here. Which line a square is on decides how big
	-- it is, that moves when the list is rebuilt, and Place writes both together
	-- on the very next tick because the two lines below force it to.
	--
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
	ns.db.cooldownPoint = ns.DefaultCopy("cooldownPoint")
	ns.db.cooldownZoom = ns.DefaultCopy("cooldownZoom")
	Row.Apply()
end

-- The four numbers the row is drawn out of: the two sizes and the two gaps.
--
-- Handed out because the options page draws the row as it will look, and the
-- one thing that page must not do is pick its own sizes. Two squares that mean
-- "you are waiting for this right now" and "you are waiting for this fight" are
-- told apart by nothing but how big they are, so a page that drew them at a
-- ratio of its own would be teaching the wrong reading of the thing it is there
-- to arrange.
function Row.Metrics()
	return BIG, ICON, GAP, DOCK
end

-- One square, for scripts/harness.lua, handed out for the reason Buffs\Nag.lua
-- hands its own out: the harness has to measure what was drawn and there is no
-- honest way to do that from outside.
function Row.Icon(slot)
	return icons[slot]
end

function Row.Shown()
	return count
end

function Row.Mode()
	return mode
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")

local function OnUpdate(_, delta)
	elapsed = elapsed + delta
	if elapsed < REFRESH then
		return
	end
	-- Subtracted rather than zeroed, so a slow frame does not turn a tenth of a
	-- second into a whole frame more than that.
	elapsed = elapsed - REFRESH
	ns.Perf.Start("cooldowns")
	Row.Update()
	ns.Perf.Stop("cooldowns")
end

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("SPELLS_CHANGED")
-- Which burst window is open, out of your own auras. Filtered to the player
-- where the client will filter, because UNIT_AURA fires for every mob on the
-- screen.
if type(events.RegisterUnitEvent) == "function" then
	events:RegisterUnitEvent("UNIT_AURA", "player")
	events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
else
	events:RegisterEvent("UNIT_AURA")
	events:RegisterEvent("UNIT_INVENTORY_CHANGED")
end

events:SetScript("OnEvent", function(_, event, token)
	if event == "PLAYER_LOGIN" then
		frame = CreateFrame("Frame", FRAME_NAME, UIParent)
		ns.UI.Adopt(frame, ns.db.cooldownZoom)
		unit = ns.UI.Unit(frame)
		place = ns.UI.Placeable(frame, {
			name = "WarriorKit cooldowns",
			moved = function(anchor)
				ns.db.cooldownPoint = anchor
				Row.Apply()
			end,
		})

		-- Built once at the ceiling, because a frame cannot be destroyed on
		-- these clients and a pool sized to the list would leak a square every
		-- time you switched one back on.
		for slot = 1, ns.Cooldowns.Ceiling() do
			icons[slot] = ns.UI.Ability.New(frame, nil, nil, ns.UI.Ability.SHOUT)
			icons[slot]:Hide()
			-- The scripts go on once. Whether the square answers them is
			-- EnableMouse, written by Place every time the row changes.
			Hover(icons[slot])
		end

		built = true
		ns.Cooldowns.Rebuild()
		Row.Apply()

		-- The ticker lives on this frame, which is never hidden. On the row
		-- itself it would stop the moment the row hid and never come back, and
		-- the row is hidden between every fight.
		events:SetScript("OnUpdate", OnUpdate)
		return
	end

	if not built then
		return
	end

	if event == "UNIT_AURA" then
		ns.Cooldowns.Scan()
		return
	end

	-- A trainer visit, a talent point and a trinket swap all change what is on
	-- the row rather than what it says, so all three rebuild the list.
	if event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD"
		or event == "PLAYER_EQUIPMENT_CHANGED" or token == "player" then
		ns.Cooldowns.Rebuild()
	end
end)

-- A resolution change moves every size in this file at once, the same way it
-- moves the buff row and the swing bars.
ns.UI.OnRescale(function()
	Row.Apply()
end)
