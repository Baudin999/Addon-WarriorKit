-- The HUD getting out from under a screen window
--
-- The wash the section above reads puts the world behind the sheet in shadow
-- and can do nothing at all about the addon's own rectangles, because a
-- cooldown row is a frame over the world rather than part of it. UI/Hush.lua is
-- the other half, and what it answers is per frame: a part goes away for as long
-- as the sheet overlaps it and stays where it is otherwise. Same shape as the
-- wash, which is why it is read here and in the same order: the library's
-- behaviour behind the screen flag, off a getter the caller hands over, and the
-- character sheet is the one caller there is today.
--
-- Six things fail silently and all six are here.
--
-- **The parts have to be registered at all.** A part that builds a rectangle
-- over the world and forgets the one line that registers it draws over the
-- sheet and nothing says so: the sheet still comes up, the other seven still
-- move, and the one that did not looks like a row somebody wanted kept. So the
-- check is by name over the list of every row that has one, and every one that
-- was built in this run has to answer UI.Hushing.
--
-- **A part under the sheet has to go.** Read by placing one on the sheet rather
-- than by trusting where the run happened to leave it. Where these rows sit is
-- the player's, so a section that asserted against the default point would be a
-- section that passes until somebody drags a row.
--
-- **A part clear of the sheet has to stay.** This is the half the old
-- all-or-nothing switch got wrong and the reason the file changed: a sheet
-- pinned to one edge of the monitor was taking the swing timer off the other
-- edge. It is also the half a reader cannot check, because a row that is down
-- when it should be up looks exactly like the feature working.
--
-- **And it has to move when the sheet does.** The sheet is dragged and the rows
-- resize themselves as the fight goes, so the answer is swept off a tick rather
-- than worked out once when the window opened. The tick is beaten here by hand:
-- a sheet moved onto the far row has to take it away and give the near one back
-- without anything else being called.
--
-- **The row's own answer has to survive it.** The whole reason this is a hidden
-- parent rather than a Hide is that every one of these rows is driven by a tick
-- that shows and hides it as the fight goes. A mechanism that wrote the child's
-- own flag would be undone on the next tick, and it would also lie to /wk
-- status, which asks the row whether it is up. IsShown before and after has to
-- be the same answer; IsVisible is the one that changes.
--
-- **The unit blocks go by the other route and have to arrive anyway.** They
-- cannot go into a cell: each one is an anchor of ours with a secure unit
-- button inside it, so it is neither reparented nor hidden from Lua in a fight,
-- and a snippet on the guard is what takes it away. That is the half of this
-- feature reading cannot check, which is what harness/client/21-restricted.lua
-- exists for: the body runs in the sandbox, so a snippet that reaches for a
-- call the restricted environment has never had fails here rather than in a
-- pull. The one question the rows do not have is asked here too: the button's
-- own flag is the unit watch's answer and nothing here may write it.
--
-- **And the sheet has to be over them when the setting is off.** Off is for the
-- player who wants his swing timer wherever the sheet lands, and it is only
-- worth offering because the strata answer holds on its own: a screen window
-- sits at HIGH, over every row this addon draws and under every window the
-- player opens.

local H = ...
local ns, check = H.ns, H.check

local Window = ns.CharWindow
local UI = ns.UI

-- Every rectangle this addon draws over the world that carries a global name.
-- A run does not build all of them: the standing row refuses a class with no
-- slots to watch, the combat feed ships off. What is checked is what exists.
local ROWS = {
	"WarriorKitBuffs",
	"WarriorKitCooldowns",
	"WarriorKitStanding",
	"WarriorKitSwing",
	"WarriorKitProgress",
	"WarriorKitMeter",
	"WarriorKitLootFeed",
	"WarriorKitCombatFeed",
}

-- The three unit blocks, by the anchor that is hidden and the button inside it
-- that must not be. A run builds all three or none: the client stub either
-- carries SecureUnitButtonTemplate or it does not.
local BLOCKS = {
	{ anchor = "WarriorKitPlayerFrame", button = "WarriorKitPlayerButton" },
	{ anchor = "WarriorKitTargetFrame", button = "WarriorKitTargetButton" },
	{ anchor = "WarriorKitTargetOfTargetFrame", button = "WarriorKitTargetOfTargetButton" },
}

Window.Hide()

local sheet = _G.WarriorKitCharacter

local pulse = _G.WarriorKitHushPulse
check(pulse ~= nil, "no tick was ever armed, so nothing follows the sheet once it moves")

local guard = _G.WarriorKitHushGuard
check(guard ~= nil, "no guard was ever built, so the unit blocks draw over the sheet")

local held = {}
for _, name in ipairs(ROWS) do
	local frame = _G[name]
	if frame then
		held[#held + 1] = name
		check(UI.Hushing(frame) == "cell",
			("%s is registered as %s rather than in a cell, so it draws over the sheet")
				:format(name, tostring(UI.Hushing(frame))))
	end
end
check(#held > 0, "not one row over the world was built in this run, so there is nothing to read")

local blocks = {}
for _, spec in ipairs(BLOCKS) do
	local anchor = _G[spec.anchor]
	if anchor then
		blocks[#blocks + 1] = spec
		check(UI.Hushing(anchor) == "guard",
			("%s is registered as %s, and a cell is shut by a Lua Hide the client refuses on a frame holding a secure button")
				:format(spec.anchor, tostring(UI.Hushing(anchor))))
	end
end
check(#blocks > 0, "not one unit block was built in this run, so there is nothing to read")

-- One frame of the client, which is what the sweep hangs off. A tenth of a
-- second so a single beat is a whole interval and the tick runs its body.
local function Beat()
	local tick = ns.UI.Ticking("hush", pulse)
	check(tick ~= nil, "the sweep is not running with the sheet up, so nothing follows it")
	if tick then
		tick:Beat(0.2)
	end
end

-- Where a row was, so the block that moves it can put it back. Three of these
-- carry a point the player set and the rest carry the one they ship with, and a
-- section that left either changed is a section that breaks the one below it.
local function Point(frame)
	local point, relative, relativePoint, x, y = frame:GetPoint(1)
	return { point = point, relative = relative, relativePoint = relativePoint, x = x, y = y }
end

local function Restore(frame, saved)
	frame:ClearAllPoints()
	if saved.point then
		frame:SetPoint(saved.point, saved.relative, saved.relativePoint, saved.x, saved.y)
	end
end

----------------------------------------------------------------------
-- On the sheet, and clear of it
--
-- Two rows, one parked in the middle of the sheet and one parked a monitor
-- away from it, and the answer has to differ. Anchored to the sheet itself
-- rather than to a coordinate, because where the sheet is is the run's business
-- and this only needs one row inside it and one outside.
----------------------------------------------------------------------

local near, far = _G[held[1]], _G[held[2] or held[1]]
check(near ~= far, "only one row over the world was built, so there is nothing to tell apart")

local nearWas, farWas = Point(near), Point(far)
local nearShown, farShown = near:IsShown(), far:IsShown()

do
	near:ClearAllPoints()
	near:SetPoint("CENTER", sheet, "CENTER", 0, 0)
	far:ClearAllPoints()
	far:SetPoint("CENTER", sheet, "CENTER", 40000, 0)

	Window.Show()
	check(not near:IsVisible(),
		("%s is in the middle of the sheet and still on screen"):format(held[1]))
	check(far:IsVisible(),
		("%s is a monitor clear of the sheet and went away with it, which is the whole thing this stopped doing")
			:format(held[2]))
	check(near:IsShown() == nearShown,
		("%s had its own shown flag written, so its next tick will put it back over the sheet")
			:format(held[1]))

	-- And the pair swaps when the sheet moves, off the tick and nothing else.
	-- Moving the sheet is what a drag does; UI/Placeable.lua's snippet writes the
	-- same point from inside a fight.
	near:ClearAllPoints()
	near:SetPoint("CENTER", sheet, "CENTER", 40000, 0)
	far:ClearAllPoints()
	far:SetPoint("CENTER", sheet, "CENTER", 0, 0)
	Beat()
	check(near:IsVisible(),
		("%s came out from under the sheet and stayed away"):format(held[1]))
	check(not far:IsVisible(),
		("%s went under the sheet and the sweep never noticed"):format(held[2]))

	Window.Hide()
	check(near:IsVisible() and far:IsVisible(),
		"the sheet went down and a row stayed away")
	check(near:IsShown() == nearShown and far:IsShown() == farShown,
		"a row came back in a different state from the one it went away in")

	Restore(near, nearWas)
	Restore(far, farWas)
end

----------------------------------------------------------------------
-- The unit blocks, which the snippet takes away
--
-- Same two questions and one more: the anchor is what may be written and the
-- button inside it is the client's.
----------------------------------------------------------------------

do
	local anchorWas, buttonWas = {}, {}
	for _, spec in ipairs(blocks) do
		anchorWas[spec.anchor] = Point(_G[spec.anchor])
		buttonWas[spec.button] = _G[spec.button]:IsShown()
		check(_G[spec.anchor]:IsShown(),
			("%s is down before the sheet is up, so nothing here reads anything")
				:format(spec.anchor))
	end

	local one = blocks[1]
	_G[one.anchor]:ClearAllPoints()
	_G[one.anchor]:SetPoint("CENTER", sheet, "CENTER", 0, 0)
	for index = 2, #blocks do
		_G[blocks[index].anchor]:ClearAllPoints()
		_G[blocks[index].anchor]:SetPoint("CENTER", sheet, "CENTER", 40000, 0)
	end

	Window.Show()
	check(not _G[one.anchor]:IsShown(),
		("%s is under the sheet and still on screen"):format(one.anchor))
	for index = 2, #blocks do
		check(_G[blocks[index].anchor]:IsShown(),
			("%s is clear of the sheet and the snippet took it away anyway")
				:format(blocks[index].anchor))
	end
	for _, spec in ipairs(blocks) do
		check(_G[spec.button]:IsShown() == buttonWas[spec.button],
			("%s had its own shown flag written, so the unit watch's answer was overwritten")
				:format(spec.button))
	end

	Window.Hide()
	for _, spec in ipairs(blocks) do
		check(_G[spec.anchor]:IsShown(),
			("%s stayed away after the sheet went down"):format(spec.anchor))
		check(_G[spec.button]:IsShown() == buttonWas[spec.button],
			("%s came back in a different state from the one it went away in")
				:format(spec.button))
		Restore(_G[spec.anchor], anchorWas[spec.anchor])
	end
end

----------------------------------------------------------------------
-- Every route down, not just the method
--
-- Escape and the key both hide the frame without going through Window:Hide, and
-- the sheet is opened in a fight by a snippet that runs none of the library's
-- Lua. So the parts go and come back off the frame's own scripts, which is what
-- a raw Hide on the frame reads.
----------------------------------------------------------------------

do
	local nearAgain = Point(near)
	near:ClearAllPoints()
	near:SetPoint("CENTER", sheet, "CENTER", 0, 0)

	Window.Show()
	check(not near:IsVisible(), "the sheet is up and the row under it is still on screen")
	sheet:Hide()
	check(near:IsVisible(),
		"the sheet was closed by Escape and the row under it never came back")

	Restore(near, nearAgain)
end

----------------------------------------------------------------------
-- The setting
--
-- Off has to reach a sheet that is already up, for the reason the wash section
-- gives: a tick box that does nothing until you shut the window and open it
-- again is a tick box you press twice. Put back at the foot of the block.
----------------------------------------------------------------------

do
	local nearAgain = Point(near)
	near:ClearAllPoints()
	near:SetPoint("CENTER", sheet, "CENTER", 0, 0)
	local anchorAgain = Point(_G[blocks[1].anchor])
	_G[blocks[1].anchor]:ClearAllPoints()
	_G[blocks[1].anchor]:SetPoint("CENTER", sheet, "CENTER", 0, 0)

	Window.Show()
	ns.db.characterQuiet = false
	Window.Quiet()
	check(near:IsVisible(),
		"the setting was turned off with the sheet up and the row under it stayed away")
	check(_G[blocks[1].anchor]:IsShown(),
		("the setting was turned off with the sheet up and %s stayed away")
			:format(blocks[1].anchor))

	Window.Hide()
	Window.Show()
	check(near:IsVisible(),
		"the sheet was opened with the setting off and put the row under it away anyway")
	check(_G[blocks[1].anchor]:IsShown(),
		("the sheet was opened with the setting off and put %s away anyway")
			:format(blocks[1].anchor))

	ns.db.characterQuiet = ns.DefaultCopy("characterQuiet")
	Window.Hide()
	Restore(near, nearAgain)
	Restore(_G[blocks[1].anchor], anchorAgain)
end

----------------------------------------------------------------------
-- And over them either way
----------------------------------------------------------------------

check(sheet:GetFrameStrata() == "HIGH",
	("the sheet sits at %s, which is not over the rows this addon draws over the world")
		:format(tostring(sheet:GetFrameStrata())))
check(not sheet:IsToplevel(),
	"the sheet is toplevel, so a click on a gear square lifts it over the bags")

Window.Hide()

print(("hush   %d rows and %d unit blocks out from under the sheet and only where it lands on them, the blocks by a snippet that may do it in a fight, their own shown flags untouched, swept again as the sheet moves and back on every route down; the sheet at %s over them either way")
	:format(#held, #blocks, sheet:GetFrameStrata()))
