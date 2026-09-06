-- The HUD standing down behind a screen window
--
-- The wash the section above reads puts the world behind the sheet in shadow
-- and can do nothing at all about the addon's own rectangles, because a
-- cooldown row is a frame over the world rather than part of it. UI/Hush.lua is
-- the other half: the rows go into a room that is shut for as long as a screen
-- window is up. Same shape as the wash, which is why it is read here and in the
-- same order: the library's behaviour behind the screen flag, off a getter the
-- caller hands over, and the character sheet is the one caller there is today.
--
-- Four things fail silently and all four are here.
--
-- **The rows have to be in the room at all.** A part that builds a rectangle
-- over the world and forgets the one line that registers it draws over the
-- sheet and nothing says so: the sheet still comes up, the other six still go
-- away, and the one that did not looks like a row somebody wanted kept. So the
-- check is by name over the list of every row that has one, and every one that
-- was built in this run has to be in there.
--
-- **The row's own answer has to survive it.** The whole reason this is a hidden
-- parent rather than a Hide is that every one of these rows is driven by a tick
-- that shows and hides it as the fight goes. A mechanism that wrote the child's
-- own flag would be undone on the next tick, and it would also lie to /wk
-- status, which asks the row whether it is up. IsShown before and after has to
-- be the same answer; IsVisible is the one that changes.
--
-- **It has to come back.** A room that is shut and not reopened is a HUD the
-- player loses for the session with no way to read what happened, which is the
-- one failure here worth more than the feature. Read on the way down and on the
-- way up, and again after the sheet is closed by a second route.
--
-- **The sheet has to be over them when the setting is off.** Off is for the
-- player who wants his swing timer while he reads a number off the sheet, and
-- it is only worth offering because the strata answer holds on its own: a
-- screen window sits at HIGH, over every row this addon draws and under every
-- window the player opens.

local H = ...
local ns, check = H.ns, H.check

local Window = ns.CharWindow

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

Window.Hide()

local room = _G.WarriorKitHush
check(room ~= nil, "no room was ever built, so nothing stands down behind the sheet")

local held = {}
for _, name in ipairs(ROWS) do
	local frame = _G[name]
	if frame then
		held[#held + 1] = name
		check(frame:GetParent() == room,
			("%s hangs off %s rather than off the room, so it draws over the sheet")
				:format(name, tostring(frame:GetParent() and frame:GetParent():GetName() or "nothing")))
	end
end
check(#held > 0, "not one row over the world was built in this run, so there is nothing to read")

----------------------------------------------------------------------
-- Down with the sheet, and back up after it
----------------------------------------------------------------------

do
	local was = {}
	for _, name in ipairs(held) do
		was[name] = _G[name]:IsShown()
	end

	Window.Show()
	check(not room:IsVisible(), "the sheet is up and the room is still open")
	for _, name in ipairs(held) do
		local frame = _G[name]
		check(not frame:IsVisible(),
			("%s is still on screen with the sheet up"):format(name))
		check(frame:IsShown() == was[name],
			("%s had its own shown flag written, so its next tick will put it back over the sheet")
				:format(name))
	end

	Window.Hide()
	check(room:IsVisible(), "the sheet went down and the HUD stayed away")
	for _, name in ipairs(held) do
		check(_G[name]:IsShown() == was[name],
			("%s came back in a different state from the one it went away in"):format(name))
	end
end

----------------------------------------------------------------------
-- Every route down, not just the method
--
-- Escape and the key both hide the frame without going through Window:Hide, and
-- the sheet is opened in a fight by a snippet that runs none of the library's
-- Lua. So the room is shut and opened off the frame's own scripts, which is
-- what a raw Hide on the frame reads.
----------------------------------------------------------------------

do
	Window.Show()
	check(not room:IsVisible(), "the sheet is up and the room is still open")
	_G.WarriorKitCharacter:Hide()
	check(room:IsVisible(),
		"the sheet was closed by Escape and the HUD never came back")
end

----------------------------------------------------------------------
-- The setting
--
-- Off has to reach a sheet that is already up, for the reason the wash section
-- gives: a tick box that does nothing until you shut the window and open it
-- again is a tick box you press twice. Put back at the foot of the block.
----------------------------------------------------------------------

do
	Window.Show()
	ns.db.characterQuiet = false
	Window.Quiet()
	check(room:IsVisible(),
		"the setting was turned off with the sheet up and the HUD stayed away")

	Window.Hide()
	Window.Show()
	check(room:IsVisible(),
		"the sheet was opened with the setting off and put the HUD away anyway")

	ns.db.characterQuiet = ns.DefaultCopy("characterQuiet")
end

----------------------------------------------------------------------
-- And over them either way
----------------------------------------------------------------------

local sheet = _G.WarriorKitCharacter
check(sheet:GetFrameStrata() == "HIGH",
	("the sheet sits at %s, which is not over the rows this addon draws over the world")
		:format(tostring(sheet:GetFrameStrata())))
check(not sheet:IsToplevel(),
	"the sheet is toplevel, so a click on a gear square lifts it over the bags")

Window.Hide()

print(("hush   %d rows over the world into a room shut behind the sheet, their own shown flags untouched, and back on every route down; the sheet at %s over them either way")
	:format(#held, sheet:GetFrameStrata()))
