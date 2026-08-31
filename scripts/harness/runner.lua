-- The order everything happens in.
--
-- Stand the client up, load the addon over it in TOC order, put Blizzard's own
-- frames in front of it, fire the three login events, then run every section
-- under ./sections against the result.
--
-- The section list at the foot of this file is the run order and it is load
-- bearing. Sections leave state behind on purpose: a measurement taken in one
-- is compared in a later one, the skin is fitted in one and taken off again
-- three down, and 27-swing-visible ends by putting the client back the way the
-- sections after it expect it. Reordering that list is a change to what is
-- being tested. Everything one section hands to a later one goes through
-- H.carry and is named at both ends.

local ROOT, PLAYER_CLASS, load, only = ...

local H = load("client/init.lua")(PLAYER_CLASS, load)
local ns = {}
H.ns, H.carry = ns, {}

local order = {}
for line in io.lines(ROOT .. "/WarriorKit.toc") do
	line = line:gsub("\r", ""):gsub("\\", "/")
	if line:match("^[A-Za-z].*%.lua$") then
		order[#order + 1] = line
	end
end
for _, path in ipairs(order) do
	H.loading.file = path
	assert(loadfile(ROOT .. "/" .. path))("WarriorKit", ns)
	H.loading.file = "runtime"
end
H.order = order

-- Over a copy of the list, not the list.
--
-- Several parts unregister ADDON_LOADED from inside their own handler for it,
-- which is what the client asks you to do and is what Core does first of all.
-- Removing an entry from the list this is walking shifts every frame after it
-- down by one, so ipairs skipped whichever frame was next, and the part that
-- got skipped depended on the order the TOC happened to load them in. The chat
-- part registered its events in that handler and did not get one, which is a
-- feature that would have worked in the game and failed here.
local events = H.events
local function fire(event, ...)
	local list = events[event]
	if not list then
		return
	end
	local watching = {}
	for index = 1, #list do
		watching[index] = list[index]
	end
	for _, f in ipairs(watching) do
		if f.scripts.OnEvent then
			f.scripts.OnEvent(f, event, ...)
		end
	end
end
H.fire = fire

load("client/08-blizzard.lua")(H)

_G.WarriorKitDB, _G.WarriorKitCharDB = {}, {}
fire("ADDON_LOADED", "WarriorKit")

-- The whole run is at the design size, whatever size the addon ships at.
--
-- Everything the addon draws in a window is a design number multiplied by the
-- pixel of the frame it is in, and the sections below assert on those numbers:
-- a row is a whole number of pixels tall, a hairline is one pixel, an anchor
-- offset is not half of one. At a quarter stop of the UI size slider none of
-- that is true, and Settings/Settings.lua is explicit that it is not meant to
-- be: a window is the one thing in the addon allowed to go soft, that is the
-- price the slider charges, and Settings.Grid names the stops that pay it.
--
-- So the size is set before the first window is built rather than moved
-- afterwards, because a window carries the pixel it was built at in the anchors
-- of its own chrome. Section 17 is where the stops themselves are walked.
ns.Settings.Set(1)

fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")

-- The tooltip's linger, run out.
--
-- Leaving a hoverable thing starts a countdown rather than taking the box down,
-- because a box that vanishes on the frame you cross a row is a box you cannot
-- read. Every section that used to assert "the tooltip is gone after OnLeave"
-- has to run that countdown down first, and it goes through one helper rather
-- than a Sweep call per section so that what a section is saying stays "the
-- pointer left and the box went" rather than a number of seconds.
--
-- The whole of the range, so no section carries a number that has to change
-- when the shipped linger does.
function H.tipSettle()
	local _, longest = ns.UI.Tooltip.LingerRange()
	ns.UI.Tooltip.Sweep(longest + 1)
	return ns.UI.Tooltip.IsShown()
end

local failures = 0
function H.check(ok, message)
	if not ok then
		failures = failures + 1
		print("  FAIL " .. message)
	end
end

local SECTIONS = {
	"01-unit-layer",
	"02-layout-engine",
	"03-gauge",
	"04-ability-square",
	"05-action-bars",
	"06-debuff-row",
	"07-tracked-debuff",
	"08-bars-zoom",
	"09-cast-row",
	"10-unit-frame-skin",
	"11-skin-rails",
	"12-debuff-square-size",
	"13-incoming-heal",
	"14-aura-row",
	"15-skin-fit",
	"16-options-window",
	"17-ui-size-slider",
	"18-which-bar",
	"19-resolution-change",
	"20-loadouts",
	"21-which-class",
	"22-chores",
	"23-minimap",
	"24-clutter-window",
	"25-meters",
	"26-swing-timer",
	"27-swing-visible",
	"28-cost",
	"29-social",
	"30-buff-nag",
	"31-feeds",
	"32-breakdown",
	"33-anchors",
	"34-game-menu",
	"35-purse",
	"36-font-roles",
	"37-player-cast",
	"38-bar-look",
	"39-party-raid",
	"40-loot-feed",
	"41-voice",
	"42-cooldown-row",
	"43-blizzard-hide",
	"44-hover",
	"45-chat-keys",
	"46-mail",
	"47-quest-log",
	-- Last, and it registers a source of its own that stays registered. A
	-- section after this one would be reading tooltips with the harness's own
	-- line hooked into them.
	"48-tooltips",
	"49-world-hover",
	-- After 48-tooltips, which is fine and is worth saying why: what that
	-- section leaves registered is a source that answers only a subject
	-- carrying its own probe field, and nothing here carries one.
	"50-experience-rails",
	-- It moves the addon's lock and puts it back, so it wants everything above
	-- it built and nothing above it disturbed. Second to last for that reason.
	"51-placing",
	-- It takes Blizzard's character sheet out of the attic and puts it back, and
	-- it moves the weapon skill the whole miss calculation is built on. Both are
	-- scene changes, so it goes under everything that reads either: the hide
	-- section three dozen lines above, and the placing walk directly over it,
	-- which counts this window among the six it holds to the lock.
	"52-character",
	-- Last, and it has to be: it puts every setting in the account file back
	-- to what the addon ships with, twice over, which is the one thing in the
	-- suite that would pull the scene out from under every section above it.
	"53-shipped-defaults",
}

-- Naming a section runs every section up to and including it, rather than that
-- one on its own. A section reads what the ones above it left behind, so one
-- run in isolation is not a smaller version of the suite, it is a crash. The
-- prefix is the smallest run that can honestly answer for the section named.
local stop
if only then
	for index, section in ipairs(SECTIONS) do
		if section == only then
			stop = index
		end
	end
	if not stop then
		io.stderr:write(("harness: no section called %s\n"):format(only))
		os.exit(2)
	end
end

for index, section in ipairs(SECTIONS) do
	load("sections/" .. section .. ".lua")(H)
	if index == stop then
		break
	end
end

return failures
