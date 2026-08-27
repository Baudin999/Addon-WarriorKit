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
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")

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
