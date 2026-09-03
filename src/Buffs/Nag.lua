local ADDON, ns = ...

local Nag = {}
ns.BuffNag = Nag

--------------------------------------------------------------------------
-- The row
--
-- A row of squares that appears when something is wrong and is not there at all
-- when nothing is. That is the whole design decision and it is worth stating,
-- because the other option was a row that is always up with the missing ones
-- lit.
--
-- A row that is always there is furniture. You stop seeing furniture in about a
-- week, which is exactly long enough to convince yourself the addon is watching
-- for you. A row that is only there when something is wrong carries its whole
-- message in existing: if you can see squares, go fix something, and there is
-- nothing to read when there is nothing to do.
--
-- The cost of that choice is that an empty row is a frame you cannot find to
-- drag. So unlocking shows every square this row would ever draw, at three
-- quarters alpha, which is the same trade Meter/Window.lua makes when it draws
-- an outline and a title around a pane that has no rows in it.
--
-- Two lines, taking turns rather than sharing. Out of combat the row is the out
-- line: what is missing that you put on before a pull, no stone, no shout, no
-- food. In combat it is the in line: the racial you own and have not pressed,
-- and whatever you dragged there because it lapses mid fight, a shaman's shield
-- being the one the feature was asked for. An entry can stand on both, and a
-- shield does. They cannot both be on screen, so the row is never longer than
-- the shorter question, and each line means one thing. Upkeep.lua holds the
-- lines and says which entry stands on which.
--
-- A square is a button as well as a picture. Clicking one opens the options
-- window on the page the row is set up on, because the square is the one thing
-- on screen you are certain to be looking at when you decide a nag is wrong,
-- and the page it is switched off on is nine groups away.
--
-- Built out of UI/Ability.lua rather than out of textures. That file already
-- draws a square with a cropped icon, a hairline that carries a status, a
-- cooldown swipe and a timer, and it already guards every write it makes
-- against the value on the widget. A second square-drawing thing in this addon
-- would be the third copy of the same six writes, which is what UI/Ability.lua
-- was extracted to stop.
--------------------------------------------------------------------------

local FRAME_NAME = "WarriorKitBuffs"

-- 27, and not a number picked for looking right. The client stores a spell icon
-- at 64 texels, UI/Draw.lua crops the five texel border off each edge, and the
-- 54 that are left resample exactly onto 54 pixels or onto 27 and nothing in
-- between. Meter/Window.lua carries the same number for the same reason.
local ICON = 27
local GAP = 4          -- one square to the next
-- The line under the row, in pixels, and at the outline floor because it is
-- drawn over the world and UI/Text.lua will not let an outline go under it. It
-- was 12, which is the one combination that is wrong both ways at once: too
-- small to carry a rim and with nothing behind it to drop the rim for.
local CAPTION = ns.UI.OutlineFloor()
local CAPTION_GAP = 4

-- The two palettes, and the one real difference between an aura and the racial.
--
-- Only `go` is ever reached in either of them. Everything this row draws is
-- something you could act on right now, which is what UI/Ability.lua's "ready"
-- means, and a square with nothing to say is not drawn at all. The other five
-- keys are here because Ability.Look takes a whole palette and a table missing
-- one would be a nil index on a tick rather than a wrong colour.
--
-- Red in both, because red is one sentence said twice: you are doing something
-- wrong. What differs is the art. A missing buff is drained, because the art is
-- a picture of a thing that is not on you. An unpressed racial is at full
-- colour, because the ability is there and ready and the only thing missing is
-- your thumb.
local RED = { 0.85, 0.25, 0.22 }
local QUIET = { 0.16, 0.16, 0.19 }

local MISSING = {
	go    = { color = RED, alpha = 1, grey = true },
	swap  = { color = RED, alpha = 1, grey = true },
	range = { color = RED, alpha = 1, grey = true },
	cost  = { color = RED, alpha = 1, grey = true },
	empty = { color = QUIET, alpha = 1, blank = true },
	no    = { color = QUIET, alpha = 0.55, grey = true },
}

local URGENT = {
	go    = { color = RED, alpha = 1 },
	swap  = { color = RED, alpha = 1 },
	range = { color = RED, alpha = 1 },
	cost  = { color = RED, alpha = 1 },
	empty = { color = QUIET, alpha = 1, blank = true },
	no    = { color = QUIET, alpha = 0.55, grey = true },
}

--------------------------------------------------------------------------
-- How loud, and why there is no sound
--
-- The brief for this feature was that you should feel bad about not pressing
-- Blood Fury, which is a request for something you cannot ignore rather than
-- for a grey square in a corner. Nothing in this addon flashes or makes a noise
-- today, so adding either is a new kind of thing here and has to be argued for
-- rather than dropped in.
--
-- What it does: the racial square breathes. Its alpha runs between a floor and
-- full over 1.6 seconds and back, which at the ticker's ten hertz is sixteen
-- steps and reads as a pulse rather than a strobe. It is on by default, because
-- a nag you can ignore is not the feature that was asked for, and `buffs pulse
-- off` turns it into a still square for anyone who disagrees.
--
-- What it does not do: play a sound. A sound in a raid competes with the sounds
-- you are already listening for, it fires whether or not you are looking at the
-- screen, and it is the one kind of interface element you cannot glance past.
-- Blood Fury coming off cooldown is not an emergency; it is a fact you would
-- like to notice within a few seconds. A pulsing icon in the middle of the
-- screen is exactly the right volume for that and a chime is not.
--
-- The alpha is quantised to twentieths on purpose. Every ticker in this addon
-- compares before it writes, and a continuous curve would write a new alpha on
-- every tick forever, including the ticks where the change is invisible.
--------------------------------------------------------------------------

local PULSE_CYCLE = 1.6
local PULSE_FLOOR = 0.35
local PULSE_STEPS = 20
local TWO_PI = math.pi * 2

-- What the preview draws at while you are placing the row. Under one, so a
-- preview never looks like the real thing having gone off at once.
local PREVIEW_FADE = 0.75

local REFRESH = 0.1

local IsResting = _G.IsResting
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost

-- The page a square opens, by the title of its section. A title rather than a
-- part name because that is what the rail lists and what Options.Open takes.
local PAGE = "Missing buffs"

local frame, caption, place
local icons = {}
local shown = {}
local shownCount = 0
local built = false
local unit = 1

-- What Place last decided, so a tick that changes nothing does no work at all.
-- `mode` is which line is on screen and `mask` is which entries within it, as
-- one bit per slot, because a number compares without allocating and a list of
-- entries does not.
local mode, mask = nil, -1

-- When the racial last came off cooldown in a fight, so the tooltip can say how
-- long you have been sitting on a cooldown you own. Nothing in the client
-- answers that: a spell that is ready reports a duration of zero and no end
-- time, so the only honest source is the moment this row noticed. `racialIdle`
-- is what it noticed last tick, so the moment is the transition and not every
-- tick after it.
local racialSince, racialIdle = 0, false

local BIT = {}
for index = 1, 32 do
	BIT[index] = 2 ^ (index - 1)
end

local Whole = ns.UI.Whole

-- The square and the gap between two, for the page that draws the row as it
-- will look. Handed out rather than copied, the way Cooldowns/Row.lua hands its
-- own to Cooldowns/Panel.lua: a page that picked its own size would be drawing
-- a different row from the one it exists to arrange.
function Nag.Metrics()
	return ICON, GAP
end


--------------------------------------------------------------------------
-- What wants to be on screen
--------------------------------------------------------------------------

-- Nagging a corpse about its sharpening stone is noise, and so is nagging
-- somebody standing in an inn who has not put one on yet on purpose. Both are
-- states where the row would be up for a long time with nothing to do about it,
-- which is how a signal becomes furniture.
--
-- The rested case is a setting because it is a real disagreement: if you buff
-- up in the bank before every raid then you want the row there. The dead case
-- is not, because nobody wants it.
--
-- Neither applies to the in line. You cannot be dead and in combat, and a fight
-- in a capital is still a fight.
function Nag.Resting()
	if ns.db.buffResting then
		return false
	end
	if type(IsResting) ~= "function" then
		return false
	end
	return IsResting() and true or false
end

function Nag.Dead()
	if type(UnitIsDeadOrGhost) ~= "function" then
		return false
	end
	return UnitIsDeadOrGhost("player") and true or false
end

-- One bit per missing entry on one line. On the tick.
--
-- `idle` is your racial's readiness, asked once by Update and handed down rather
-- than asked again inside the walk.
function Nag.MissingMask(line, idle)
	local bits = 0
	for index = 1, ns.Upkeep.Count() do
		if ns.Upkeep.On(ns.Upkeep.Entry(index), line) and ns.Upkeep.Missing(index, idle) then
			bits = bits + BIT[index]
		end
	end
	return bits
end

--------------------------------------------------------------------------
-- Laying it out
--
-- Reached only from behind the comparison in Nag.Update, so it runs when the
-- row changes and not when the row is drawn. That is what lets it write frames
-- and build strings freely, which is the same licence Charge/Charge.lua's plate
-- placement has and for the same reason.
--------------------------------------------------------------------------

-- Which line a mode draws, or nil for a mode that draws every entry.
local LINE_OF = { upkeep = ns.Upkeep.OUT, combat = ns.Upkeep.IN }

local function Collect()
	shownCount = 0
	if mode ~= "upkeep" and mode ~= "combat" and mode ~= "preview" then
		return
	end

	local line = LINE_OF[mode]
	for index = 1, ns.Upkeep.Count() do
		local entry = ns.Upkeep.Entry(index)
		if not line or (ns.Upkeep.On(entry, line) and ns.Upkeep.Missing(index)) then
			shownCount = shownCount + 1
			shown[shownCount] = entry
		end
	end
end

-- What one square says under itself. A missing aura is named; the racial is an
-- instruction, because there is nothing missing about it except your thumb.
local function Word(entry)
	if entry.racial then
		return "press " .. (entry.label or "")
	end
	return entry.label or ""
end

-- The line under the row. It exists because a square of drained art tells you
-- something is missing and not which hand, and "no stone" is a shorter sentence
-- than a picture.
local function Words()
	if mode == "preview" then
		return "everything this row watches"
	end
	local text = ""
	for slot = 1, shownCount do
		text = text .. (slot > 1 and ", " or "") .. Word(shown[slot])
	end
	return text
end

--------------------------------------------------------------------------
-- What one square says to the mouse
--
-- The caption has to fit four squares' worth of words on one line over your
-- character, so it says "bare weapon" and stops. That is the right length for a
-- thing you read at a glance mid-raid and it is not enough to act on if you
-- have never seen the row before. The tooltip is where the rest goes: what the
-- square is about, what fixes it, and the name of the switch that silences it,
-- so somebody tired of one square can turn it off from the square rather than
-- reading the whole panel looking for it.
--
-- Buttons/Square.lua owns this shape for the action bars and this follows it.
-- OnEnter and OnLeave, anchored to the square, and refused outright when there
-- is nothing to say rather than left to fill itself in from whatever the
-- tooltip was last handed, which would leave the previous square's sentence on
-- screen pointing at this one. It is not shared with that file: every step
-- there is about an action slot read off a secure button's attribute and handed
-- to the client to describe, and none of the three has anything to do with a
-- sharpening stone.
--
-- A square takes the mouse only while the row is locked and drawn, which is two
-- decisions.
--
-- Drawn, because six of the ten squares are hidden at any moment and enabling
-- the mouse on all ten at login would leave invisible mouse traps sitting over
-- the middle of the screen.
--
-- Locked, because unlocked the row is a thing you drag. The parent frame owns
-- that drag, and a square on top of it taking the mouse would eat the button
-- before the drag started. That is the same trap Nag.Lock carries a note about
-- one level up, met again one level down.
--
-- The row sits above the middle of the screen, which is exactly where a right
-- button drag to turn the camera starts. ns.Tip.Hang hands those buttons back
-- where the client will take them and says what it costs where it will not.
--
-- The three lines below are what this file used to write by hand into the
-- client's own tooltip, and the shape of them is now UI/Tip.lua's: a title, a line that
-- says what is wrong, and a hint that says what to type. It is handed over as
-- one subject rather than written a call at a time, so what a square says is a
-- value this file returns rather than a sequence it has to perform. The tooltip
-- that draws it is the addon's own, so hovering a nag square no longer raises a
-- parchment scroll over an interface that has none anywhere else.
--
-- What the square names, which is the last thing that made this box read unlike
-- every other one.
--
-- An action square hands UI/Tip.lua its slot, an aura hands it a unit and an
-- index, and both get the client's own words at the top with the addon's
-- underneath. A nag square handed over `note`, which reads nothing, so its head
-- was "food" in the caption's voice while the box eight pixels away had a spell
-- name, a rank and a cast time. The reason was real: there is no aura index for
-- an aura that is not on you.
--
-- There is still a handle on all three shapes, and Subject picks the one that
-- fits. A racial or a watched buff is an id, which UI/Scan.lua now takes. A
-- bare hand is a worn slot, which it always took, and the weapon's own tooltip
-- is the right thing to read for a square whose whole complaint is what is not
-- on that weapon. Only an entry with neither is left saying `note`.
--
-- The title goes along regardless. UI/Tooltip.lua draws the client's lines
-- instead of a title where there are any and the title where there are none, so
-- the caption's phrase is what an older client and an empty slot fall back to
-- rather than a second heading nobody sees.
--------------------------------------------------------------------------

-- What the caption could not hold.
local function Detail(entry)
	if entry.racial then
		local idle = GetTime() - racialSince
		if racialSince > 0 and idle >= 1 then
			return ("Off cooldown for %d seconds and doing nothing there. Press it.")
				:format(idle)
		end
		return "Off cooldown. Press it."
	end
	if entry.hint then
		return entry.hint
	end
	-- One you added yourself. The client's own name for the aura is the only
	-- thing this addon knows about it, which is the honest sentence to write.
	return (entry.name or ("Spell " .. tostring(entry.spell)))
		.. " is not on you. You put it on the row yourself."
end

-- The one sentence every square ends on. It is a body line and not the blue
-- hint band that used to sit under every box in the addon: this square is the
-- one place a click does something, and a box that did not say so would be a
-- button nobody finds.
local CLICK = "Click it to open the page this row is set up on."

-- The subject one square is about, in whichever of the three kinds this square
-- has a handle for. Everything under the head is the same lines whichever one
-- it picks.
local function Subject(entry)
	local subject = {
		kind = "note",
		title = Word(entry),
		lines = { Detail(entry), CLICK },
	}
	if entry.spell then
		subject.kind = "spell"
		subject.spell = entry.spell
	elseif entry.hand then
		subject.kind = "inventory"
		subject.unit = "player"
		subject.slot = entry.hand
	end
	return subject
end

local function Hover(w)
	ns.Tip.Hang(w, function()
		local entry = w.entry
		-- A square with nothing to say describes nothing, and a tooltip handed
		-- nothing does not open. That is the same refusal this had against
		-- the client's own tooltip and it matters for the same reason: without it the
		-- previous square's sentence stays on screen pointing at this one.
		if not entry or (entry.label or "") == "" then
			return nil
		end
		return Subject(entry)
	end)
end

-- The click. Left button only, on the way up, and only while the square is
-- taking the mouse at all, which Place decides: a hidden square answers no
-- script because it has no mouse to answer with, and the preview hands the
-- button to the parent for the drag. The right button is already handed back
-- to the camera by ns.Tip.Hang.
local function Open(_, button)
	if button == "LeftButton" then
		ns.Options.Open(PAGE)
	end
end

local function Press(w)
	w:SetScript("OnMouseUp", Open)
end

-- cold: layout, run on a settings change and a rescale rather than on a tick.
local function Place()
	Collect()

	-- The preview is the row being dragged, so its squares hand the mouse back
	-- and the parent gets the button. Every other mode is a square you can hover
	-- and a square you cannot move.
	local hoverable = mode ~= "preview"
	for slot = 1, #icons do
		local w = icons[slot]
		if slot <= shownCount then
			w.palette = shown[slot].racial and URGENT or MISSING
			w.art = shown[slot].texture
			w.entry = shown[slot]
			w:EnableMouse(hoverable)
			w:ClearAllPoints()
			w:SetPoint("TOPLEFT", frame, "TOPLEFT", (slot - 1) * (ICON + GAP) * unit, 0)
			w:Show()
		else
			w.entry = nil
			w:EnableMouse(false)
			w:Hide()
		end
	end

	if shownCount == 0 then
		-- Cleared as well as hidden. A hidden frame holding the last thing it
		-- said is a string nobody can see and everybody who asks the frame what
		-- it says gets, which is what the harness found when it asked.
		caption:SetText("")
		frame:Hide()
		return
	end

	local width = (shownCount * (ICON + GAP) - GAP) * unit
	frame:SetSize(width, (ICON + CAPTION_GAP + CAPTION) * unit)
	caption:SetText(Words())
	frame:Show()
end

--------------------------------------------------------------------------
-- Drawing
--
-- On the ticker. Nothing here allocates and nothing writes a value the widget
-- already carries, which UI/Ability.lua does the guarding for.
--------------------------------------------------------------------------

local function Pulse()
	if not ns.db.buffPulse then
		return 1
	end
	local phase = (GetTime() % PULSE_CYCLE) / PULSE_CYCLE
	local wave = 0.5 - 0.5 * math.cos(phase * TWO_PI)
	return Whole((PULSE_FLOOR + (1 - PULSE_FLOOR) * wave) * PULSE_STEPS) / PULSE_STEPS
end

-- The racial square breathes and nothing else does. A missing aura is a fact
-- and sits still; the racial is a press, and the pulse is what the brief asked
-- for. Pulse is asked once per paint rather than once per square, because the
-- wave is one number and the comparison inside Draw is what keeps a square
-- whose alpha did not move from being written.
local function Paint()
	local fade = (mode == "preview") and PREVIEW_FADE or 1
	local breath = Pulse()
	for slot = 1, shownCount do
		local w = icons[slot]
		w.fade = (shown[slot].racial and mode ~= "preview") and breath or fade
		ns.UI.Ability.Draw(w, w.art, "ready")
	end
end

function Nag.Update()
	if not built then
		return
	end

	local want, bits = "quiet", 0
	local fighting = UnitAffectingCombat("player")

	-- Asked once a tick, here, because two things want the same answer: whether
	-- the racial square is missing, and the moment below that the tooltip counts
	-- from. It is a spell name and a cooldown read, and it used to be both twice.
	local idle = fighting and ns.Racials.Idle() or false

	if not ns.db.buffs then
		want = "quiet"
	elseif not ns.db.locked then
		want = "preview"
	elseif Nag.Dead() then
		want = "quiet"
	elseif fighting then
		bits = Nag.MissingMask(ns.Upkeep.IN, idle)
		if bits ~= 0 then
			want = "combat"
		end
	elseif not Nag.Resting() then
		bits = Nag.MissingMask(ns.Upkeep.OUT)
		if bits ~= 0 then
			want = "upkeep"
		end
	end

	-- The moment the racial came up, kept whether or not its square is drawn,
	-- because the row can be quiet with the racial switched off and still owe
	-- the number to a square that comes back later.
	if idle and not racialIdle then
		racialSince = GetTime()
	end
	racialIdle = idle

	if want ~= mode or bits ~= mask then
		mode, mask = want, bits
		Place()
	end

	if shownCount > 0 then
		Paint()
	end
end

--------------------------------------------------------------------------
-- Layout, lock and reset
--
-- Everything a setting can move. At login and on a settings change, never from
-- a tick.
--------------------------------------------------------------------------

function Nag.Apply()
	if not built then
		return
	end

	local point = ns.db.buffPoint
	frame:ClearAllPoints()
	frame:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	ns.UI.Rezoom(frame, ns.db.buffZoom)

	for slot = 1, #icons do
		ns.UI.Ability.Size(icons[slot], ICON * unit)
	end

	caption:ClearAllPoints()
	caption:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(ICON + CAPTION_GAP) * unit)
	caption:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(ICON + CAPTION_GAP) * unit)


	-- Force the next tick to lay the row out again, whatever it decides. A zoom
	-- change moves every square and the mask has not moved with it.
	mode, mask = nil, -1
	Nag.Lock()
	Nag.Update()
end

-- Mouse only while unlocked, which is the rule Meter/Window.lua and the charge
-- icon both follow. A mouse enabled frame swallows every button that lands on
-- it including the right button drag that turns the camera, and this row sits
-- above the middle of the screen, which is where that drag starts.
function Nag.Lock()
	if not built then
		return
	end
	place:Lock(not ns.db.locked)
end

function Nag.Reset()
	ns.db.buffPoint = ns.DefaultCopy("buffPoint")
	ns.db.buffZoom = ns.DefaultCopy("buffZoom")
	Nag.Apply()
end

-- One square, for scripts/harness.lua. Handed out rather than kept private for
-- the reason Meter/Window.lua hands out its panes: the harness has to measure
-- what was drawn, and there is no honest way to do that from outside.
function Nag.Icon(slot)
	return icons[slot]
end

function Nag.Shown()
	return shownCount
end

function Nag.Mode()
	return mode
end

function Nag.Caption()
	return caption and caption:GetText() or ""
end

function Nag.Describe()
	if not ns.db.buffs then
		return "off"
	end
	local line = ns.Upkeep.Describe()
	if not ns.Upkeep.Watched("racial") then
		return line .. "; racial off"
	end
	return line .. "; racial " .. ns.Racials.Describe()
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
local tick -- the refresh ticker, armed once, see below


events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("SPELLS_CHANGED")
-- The aura scan's whole reason for not being on the ticker. Filtered to the
-- player where the client will filter, the way Swing/Gauges.lua filters its
-- two, because UNIT_AURA fires for every mob on the screen.
ns.RegisterUnitEvent(events, "UNIT_AURA", "player")
ns.RegisterUnitEvent(events, "UNIT_INVENTORY_CHANGED", "player")

events:SetScript("OnEvent", function(_, event, token)
	if event == "PLAYER_LOGIN" then
		frame = CreateFrame("Frame", FRAME_NAME, UIParent)
		ns.UI.Adopt(frame, ns.db.buffZoom)
		unit = ns.UI.Unit(frame)
		place = ns.UI.Placeable(frame, {
			name = "WarriorKit buffs",
			moved = function(anchor)
				ns.db.buffPoint = anchor
				Nag.Apply()
			end,
		})

		-- Outlined, which is what the meters use for the same reason: this
		-- text sits over the world and a drop shadow disappears against a
		-- dark floor.
		caption = ns.UI.Label(frame, CAPTION, RED, "CENTER", ns.UI.OUTLINE)

		-- Built once at the ceiling, because a frame cannot be destroyed on
		-- this client and a pool sized to the list would leak a square every
		-- time you added one.
		for slot = 1, ns.Upkeep.Ceiling() do
			icons[slot] = ns.UI.Ability.New(frame, nil, nil, MISSING)
			icons[slot]:Hide()
			-- The scripts go on once. Whether the square answers them is
			-- EnableMouse, written by Place every time the row changes.
			Hover(icons[slot])
			Press(icons[slot])
		end

		built = true
		ns.Upkeep.Rebuild()
		Nag.Apply()

		-- The ticker lives on this frame, which is never hidden. On the row
		-- itself it would stop the moment the row hid and never come back, and
		-- the row is hidden almost all the time, which is the trap
		-- Charge/Icon.lua already carries a note about.
		--
		-- Armed once. UI.Ticker appends and refuses a second tick of this name
		-- on this frame, so a branch that arms one has to be a branch that runs
		-- once.
		if not tick then
			tick = ns.UI.Ticker(ns.UI.Forever, REFRESH, "buffs", Nag.Update)
		end
		return
	end

	if not built then
		return
	end

	if event == "UNIT_AURA" then
		ns.Upkeep.Scan()
		return
	end

	if event == "SPELLS_CHANGED" then
		-- A rank you just trained changes nothing about the name, and a racial
		-- you did not have a moment ago is a character you just logged into.
		ns.Upkeep.Rebuild()
		return
	end

	if event == "PLAYER_ENTERING_WORLD" then
		-- Rebuilt rather than refitted, because the racial resolves off the
		-- client's answer for your race and that answer can arrive after
		-- PLAYER_LOGIN. A rebuild is a walk of a dozen entries, off a tick.
		ns.Upkeep.Rebuild()
		return
	end

	if token == "player" or event == "PLAYER_EQUIPMENT_CHANGED" then
		ns.Upkeep.Refit()
		ns.Upkeep.Scan()
	end
end)

-- A resolution change moves every size in this file at once, the same way it
-- moves the meters and the swing bars.
ns.UI.OnRescale(function()
	Nag.Apply()
end)
