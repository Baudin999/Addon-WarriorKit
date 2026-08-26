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
-- Two halves, taking turns rather than sharing. Out of combat the row is what
-- is missing: no stone, no shout, no food. In combat it is the racial you own
-- and have not pressed. They cannot both be on screen, so the row is never
-- longer than the shorter question, and each half means one thing.
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
local CAPTION = 12     -- the line under the row, in pixels
local CAPTION_GAP = 4

-- The two palettes, and the one real difference between the halves.
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

local frame, caption, grab, title
local icons = {}
local shown = {}
local shownCount = 0
local built = false
local unit = 1
local elapsed = 0

-- What Place last decided, so a tick that changes nothing does no work at all.
-- `mode` is which half is on screen and `mask` is which entries within it, as
-- one bit per slot, because a number compares without allocating and a list of
-- entries does not.
local mode, mask = nil, -1

-- When the racial half last came up, so the tooltip can say how long you have
-- been sitting on a cooldown you own. Nothing in the client answers that: a
-- spell that is ready reports a duration of zero and no end time, so the only
-- honest source is the moment this row noticed. Recorded at the transition
-- inside Nag.Update, which is behind the comparison and runs when the row
-- changes rather than when it is drawn.
local racialSince = 0

local BIT = {}
for index = 1, 32 do
	BIT[index] = 2 ^ (index - 1)
end

-- The racial's square, as one entry shaped like an upkeep entry so Place can
-- treat both halves the same. Filled in at Place time rather than at login,
-- because the client can take a moment to answer for a spell.
local racial = { label = "" }

local function Whole(value)
	return math.floor(value + 0.5)
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
-- Neither applies to the racial half. You cannot be dead and in combat, and a
-- fight in a capital is still a fight.
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

-- One bit per missing entry. On the tick.
function Nag.MissingMask()
	local bits = 0
	for index = 1, ns.Upkeep.Count() do
		if ns.Upkeep.Missing(index) then
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

local function Collect()
	shownCount = 0

	if mode == "racial" then
		racial.texture = ns.Racials.Texture()
		racial.label = ns.Racials.Name() or ""
		shownCount = 1
		shown[1] = racial
		return
	end

	if mode ~= "upkeep" and mode ~= "preview" then
		return
	end

	for index = 1, ns.Upkeep.Count() do
		if mode == "preview" or ns.Upkeep.Missing(index) then
			shownCount = shownCount + 1
			shown[shownCount] = ns.Upkeep.Entry(index)
		end
	end
end

-- The line under the row. It exists because a square of drained art tells you
-- something is missing and not which hand, and "no stone" is a shorter sentence
-- than a picture.
local function Words()
	if mode == "racial" then
		return "press " .. racial.label
	end
	if mode == "preview" then
		return "everything this row watches"
	end
	local text = ""
	for slot = 1, shownCount do
		text = text .. (slot > 1 and ", " or "") .. (shown[slot].label or "")
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
-- button drag to turn the camera starts. ns.UI.Tip hands those buttons back
-- where the client will take them and says what it costs where it will not.
--
-- The three lines below are what this file used to write by hand into
-- GameTooltip, and the shape of them is now UI/Tooltip.lua's: a title, a line
-- that says what is wrong, and a hint that says what to type. The tooltip that
-- draws them is the addon's own, so hovering a nag square no longer raises a
-- parchment scroll over an interface that has none anywhere else.
--------------------------------------------------------------------------

-- The line that names the switch, which is the whole reason a tooltip on a nag
-- square knows anything about settings.
local function Silencer(entry)
	if entry == racial then
		return "Silence it with /wk buffs racial off, or from the panel."
	end
	if entry.word then
		return ("Silence it with /wk buffs %s off, or from the panel. That is per"
			.. " character."):format(entry.word)
	end
	return ("Take it off the row with /wk buffs remove %d, or from the panel.")
		:format(entry.spell or 0)
end

-- What the caption could not hold.
local function Detail(entry)
	if entry == racial then
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

local function Hover(w)
	ns.UI.Tip(w, function(tip)
		local entry = w.entry
		-- A square with nothing to say writes no lines, and a tooltip with no
		-- lines in it does not open. That is the same refusal this had against
		-- GameTooltip and it matters for the same reason: without it the
		-- previous square's sentence stays on screen pointing at this one.
		if not entry or (entry.label or "") == "" then
			return
		end
		tip.Title(entry.label, ns.UI.Color.text)
		tip.Line(Detail(entry))
		tip.Hint(Silencer(entry))
	end)
end

local function Place()
	Collect()

	-- The preview is the row being dragged, so its squares hand the mouse back
	-- and the parent gets the button. Every other mode is a square you can hover
	-- and a square you cannot move.
	local hoverable = mode ~= "preview"
	local palette = (mode == "racial") and URGENT or MISSING
	for slot = 1, #icons do
		local w = icons[slot]
		if slot <= shownCount then
			w.palette = palette
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

local function Paint()
	local fade = 1
	if mode == "racial" then
		fade = Pulse()
	elseif mode == "preview" then
		fade = PREVIEW_FADE
	end
	for slot = 1, shownCount do
		local w = icons[slot]
		w.fade = fade
		ns.UI.Ability.Draw(w, w.art, "ready")
	end
end

function Nag.Update()
	if not built then
		return
	end

	local want, bits = "quiet", 0
	if not ns.db.buffs then
		want = "quiet"
	elseif not ns.db.locked then
		want = "preview"
	elseif Nag.Dead() then
		want = "quiet"
	elseif UnitAffectingCombat("player") then
		if ns.db.buffRacial and ns.Racials.Idle() then
			want = "racial"
		end
	elseif not Nag.Resting() then
		bits = Nag.MissingMask()
		if bits ~= 0 then
			want = "upkeep"
		end
	end

	if want ~= mode or bits ~= mask then
		if want == "racial" and mode ~= "racial" then
			racialSince = GetTime()
		end
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

	grab:ClearAllPoints()
	grab:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	grab:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

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
	local unlocked = not ns.db.locked
	frame:EnableMouse(unlocked)
	if unlocked then
		frame:RegisterForDrag("LeftButton")
		grab:Show()
		title:Show()
	else
		frame:RegisterForDrag()
		grab:Hide()
		title:Hide()
	end
end

function Nag.Reset()
	ns.db.buffPoint = { "CENTER", "UIParent", "CENTER", 0, 140 }
	ns.db.buffZoom = ns.DefaultFor("buffZoom")
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
	if not ns.db.buffRacial then
		return line .. "; racial off"
	end
	return line .. "; racial " .. ns.Racials.Describe()
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")

local function OnUpdate(_, delta)
	elapsed = elapsed + delta
	if elapsed < REFRESH then
		return
	end
	-- Subtracted rather than zeroed. Zeroing throws away whatever was left over
	-- and turns a tenth of a second into a whole frame more than that on a slow
	-- frame, which is the bug that made the swing timer run at a third of the
	-- rate it said it did.
	elapsed = elapsed - REFRESH
	ns.Perf.Start("buffs")
	Nag.Update()
	ns.Perf.Stop("buffs")
end

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("SPELLS_CHANGED")
-- The aura scan's whole reason for not being on the ticker. Filtered to the
-- player where the client will filter, the way Swing/Gauges.lua filters its
-- two, because UNIT_AURA fires for every mob on the screen.
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
		ns.UI.Adopt(frame, ns.db.buffZoom)
		unit = ns.UI.Unit(frame)
		frame:SetMovable(true)
		frame:SetClampedToScreen(true)
		frame:SetScript("OnDragStart", function(self)
			if not ns.db.locked then
				self:StartMoving()
			end
		end)
		frame:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			local point, _, relativePoint, x, y = self:GetPoint()
			-- Rounded, because a drag lands wherever the cursor was and this
			-- frame is on the grid, where a fractional offset rasterises every
			-- icon and every glyph inside it across two rows of pixels.
			ns.db.buffPoint = { point, "UIParent", relativePoint, Whole(x), Whole(y) }
			Nag.Apply()
		end)

		grab = ns.UI.Box(frame, nil, ns.UI.Color.edge)
		grab:Hide()
		title = ns.UI.Label(frame, ns.UI.Metric.font, ns.UI.Color.heading, "LEFT")
		title:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2 * unit)
		title:SetText("WarriorKit buffs")
		title:Hide()

		-- Outlined, which is UI.Label's default and is what the meters use for
		-- the same reason: this text sits over the world and a drop shadow
		-- disappears against a dark floor.
		caption = ns.UI.Label(frame, CAPTION, RED, "CENTER")

		-- Built once at the ceiling, because a frame cannot be destroyed on
		-- this client and a pool sized to the list would leak a square every
		-- time you added one.
		for slot = 1, ns.Upkeep.Ceiling() do
			icons[slot] = ns.UI.Ability.New(frame, nil, nil, MISSING)
			icons[slot]:Hide()
			-- The scripts go on once. Whether the square answers them is
			-- EnableMouse, written by Place every time the row changes.
			Hover(icons[slot])
		end

		built = true
		ns.Upkeep.Rebuild()
		Nag.Apply()

		-- The ticker lives on this frame, which is never hidden. On the row
		-- itself it would stop the moment the row hid and never come back, and
		-- the row is hidden almost all the time, which is the trap
		-- Charge/Icon.lua already carries a note about.
		events:SetScript("OnUpdate", OnUpdate)
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

	if event == "PLAYER_ENTERING_WORLD" or token == "player"
		or event == "PLAYER_EQUIPMENT_CHANGED" then
		ns.Upkeep.Refit()
		ns.Upkeep.Scan()
	end
end)

-- A resolution change moves every size in this file at once, the same way it
-- moves the meters and the swing bars.
ns.UI.OnRescale(function()
	Nag.Apply()
end)
