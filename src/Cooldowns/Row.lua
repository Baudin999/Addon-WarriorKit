local ADDON, ns = ...

local Row = {}
ns.CooldownRow = Row

--------------------------------------------------------------------------
-- The row
--
-- One square per long cooldown, in the order the class file wrote them, with
-- your trinkets on the end. Cooldowns.lua decides what is on it and this file
-- decides when it is on the screen and what it looks like.
--
-- Three decisions, and each one is the row rather than a detail of it.
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

-- 27, the same number Buffs\Nag.lua and Meter\Window.lua carry: the client
-- stores a spell icon at 64 texels, UI\Draw.lua crops the five texel border off
-- each edge, and the 54 that are left resample exactly onto 54 pixels or onto
-- 27 and nothing in between.
local ICON = 27
local GAP = 4

-- What the preview draws at while you are placing the row, under one so it
-- never looks like the real thing.
local PREVIEW_FADE = 0.75

local REFRESH = 0.1

local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost

local frame, grab, title
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

local function Whole(value)
	return math.floor(value + 0.5)
end

--------------------------------------------------------------------------
-- What one square says to the mouse
--
-- The row has no caption under it, which is the other difference from the buff
-- nag. A nag square is a sentence about something you did wrong and needs the
-- words; a cooldown square is a picture of an ability with a number on it and
-- the picture is the sentence. What the tooltip adds is the part a number
-- cannot carry: which of the three reasons this square is here, and the word
-- that takes it away.
--------------------------------------------------------------------------

local function Silencer(entry)
	return ("Take it off this character's row with /wk cooldowns %s off, or from"
		.. " the panel. That is per character."):format(entry.key)
end

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
			hint = Silencer(entry),
		}
	end)
end

--------------------------------------------------------------------------
-- Laying it out
--------------------------------------------------------------------------

local function Place()
	seen = ns.Cooldowns.Epoch()
	local drawn = (mode == "quiet") and 0 or ns.Cooldowns.Count()

	-- The preview is the row being dragged, so its squares hand the mouse back
	-- and the parent frame gets the button.
	local hoverable = mode ~= "preview"
	for slot = 1, #icons do
		local w = icons[slot]
		if slot <= drawn then
			w.entry = ns.Cooldowns.Entry(slot)
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

	count = drawn
	if drawn == 0 then
		frame:Hide()
		return
	end

	frame:SetSize((drawn * (ICON + GAP) - GAP) * unit, ICON * unit)
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

	for slot = 1, #icons do
		ns.UI.Ability.Size(icons[slot], ICON * unit)
	end

	grab:ClearAllPoints()
	grab:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	grab:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

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

function Row.Reset()
	ns.db.cooldownPoint = ns.DefaultCopy("cooldownPoint")
	ns.db.cooldownZoom = ns.DefaultCopy("cooldownZoom")
	Row.Apply()
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
			-- icon inside it across two rows of pixels.
			ns.db.cooldownPoint = { point, "UIParent", relativePoint, Whole(x), Whole(y) }
			Row.Apply()
		end)

		grab = ns.UI.Box(frame, nil, ns.UI.Color.edge)
		grab:Hide()
		-- At the outline floor, because it is drawn over the world while the row
		-- is being placed and cannot drop the rim.
		title = ns.UI.Label(frame, ns.UI.OutlineFloor(), ns.UI.Color.heading,
			"LEFT", ns.UI.OUTLINE)
		title:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2 * unit)
		title:SetText("WarriorKit cooldowns")
		title:Hide()

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
