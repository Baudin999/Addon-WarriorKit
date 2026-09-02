local ADDON, ns = ...

local Blizz = {}
ns.BagsBlizzard = Blizz

--------------------------------------------------------------------------
-- The client's bags, and the key that opens them
--
-- The same shape as Map/Blizzard.lua and Quests/Blizzard.lua, so this header
-- only writes down where this one differs.
--
-- **Nothing goes in the attic.** The client's bags are not a frame you hide,
-- they are frames the client only ever shows through nine named calls. Take the
-- nine and the frames are never built onto the screen in the first place, which
-- is cheaper than caging thirteen containers and cannot leave one of them
-- half-placed on the way past. There is no equivalent for a map or a mailbox,
-- which is why those two are caged and this one is not.
--
-- **All nine, not just the toggle.** B is `ToggleBackpack`, the bag buttons on
-- the bar are `ToggleBag`, the binding for all of them is `ToggleAllBags`, and
-- then there are the six the client calls on your behalf: `OpenAllBags` when
-- you talk to a merchant or open the bank, `CloseAllBags` when you walk away
-- from either, and the backpack and single-bag pairs under those. Take the
-- toggle alone and the first merchant you speak to puts five of Blizzard's bags
-- on the screen beside this window.
--
-- **A replacement, not a hook.** Everything else in this addon that touches a
-- Blizzard frame uses hooksecurefunc, which runs after the client's own code
-- and cannot stop it, and stopping it is the entire job here. What was on each
-- name is kept so the switch can hand all nine back exactly.
--
-- **This is the one part that will argue with another bag addon.** Baganator
-- and Bagnon take the same names, and whichever of us loads last is the one
-- holding them. That is not a bug to work around, it is what replacing the bags
-- means, and the panel says so rather than the two of us fighting over B every
-- reload.
--------------------------------------------------------------------------

-- What the window does when the client asks for the bags.
--
-- Named functions at file scope rather than closures made at the swap, because
-- the swap runs on the once-a-second pass and a fresh closure a second is
-- garbage the collector walks. It is also what makes "are we already holding
-- it" a comparison rather than a guess.
--
-- Every one of them ignores its arguments. `ToggleBag` and `OpenBag` are handed
-- a bag number and there is one window for all five, so which bag the client
-- meant is not a question this window has an answer to.
--
-- **And none of them answers anything, because none of Blizzard's nine does.**
-- One of the nine is read. `CloseAllWindows` opens with
-- `local bagsVisible = CloseAllBags()` and hands that back as "something was
-- closed"; `ToggleGameMenu` runs a chain of elseifs and the branch under
-- `securecall("CloseAllWindows")` is the one that puts the system menu on the
-- screen. So a `CloseAllBags` that says yes on a press with no bags open is
-- escape that closes windows, cancels a cursor, and never once opens the menu,
-- with nothing on the screen to say why. The bag window's own Show, Hide and
-- Toggle answer whether they did anything, which every other caller wants and
-- this one must not see.
local function Toggle()
	ns.BagsWindow.Toggle()
end

local function Open()
	ns.BagsWindow.Show()
end

local function Close()
	ns.BagsWindow.Hide()
end

-- Every name the client opens or shuts a bag through, and what this window does
-- instead. Probed one at a time, because a build that does not carry one of them
-- is a build where the other eight still have to be taken.
local KEYS = {
	{ name = "ToggleBackpack", ours = Toggle },
	{ name = "ToggleAllBags",  ours = Toggle },
	{ name = "ToggleBag",      ours = Toggle },
	{ name = "OpenAllBags",    ours = Open },
	{ name = "OpenBackpack",   ours = Open },
	{ name = "OpenBag",        ours = Open },
	{ name = "CloseAllBags",   ours = Close },
	{ name = "CloseBackpack",  ours = Close },
	{ name = "CloseBag",       ours = Close },
}

-- What each name held before this addon took it. Written once per name and
-- never again, so a second addon that took one of these after us is not
-- swallowed by a later pass of Apply.
local kept = {}

local held = false
local shut = false

--------------------------------------------------------------------------

local function Remember(entry)
	if kept[entry.name] == nil and type(_G[entry.name]) == "function" then
		kept[entry.name] = _G[entry.name]
	end
	return kept[entry.name] ~= nil
end

local function Take(entry)
	if _G[entry.name] == entry.ours then
		return true
	end
	if not Remember(entry) then
		return false
	end
	_G[entry.name] = entry.ours
	return true
end

local function Give(entry)
	if _G[entry.name] ~= entry.ours or type(kept[entry.name]) ~= "function" then
		return false
	end
	_G[entry.name] = kept[entry.name]
	return true
end

-- Whatever the client already had open, shut, once.
--
-- The takeover happens at login and a bag left open across a reload comes back
-- open, so without this the client's bags sit on the screen for the session with
-- no call left that can close them: we are holding the one that would.
local function ShutTheirs()
	if shut or type(kept.CloseAllBags) ~= "function" then
		return false
	end
	shut = true
	pcall(kept.CloseAllBags)
	return true
end

--------------------------------------------------------------------------

-- Whether the client's bags should be out of the way right now. Two switches
-- and no third: the keys open this window, so there is never a moment where the
-- bags are unreachable.
function Blizz.Wanted()
	return (ns.db.bags and ns.db.bagsHideBlizz) and true or false
end

-- Walked on every call rather than only when the switch moves, and on the
-- once-a-second pass rather than once at login, for the reason Map/Blizzard.lua
-- gives: an addon that loads after this one and takes one of these names back
-- would otherwise hold it for the session. Everything here is a comparison once
-- it has taken.
--
-- Always true, which is the one place this differs from every other applier on
-- that pass. False on that pass means work a combat lockdown refused and puts
-- the whole pass on the PLAYER_REGEN_ENABLED retry. Nothing here can be refused
-- that way: a global is not a protected frame and writing one in a fight is
-- allowed. The only thing that can go wrong is a name this build does not carry,
-- and that is not work to retry every second for the rest of the session. It is
-- a fact about the client, and Blizz.Found is where it is reported.
function Blizz.Apply()
	local wanted = Blizz.Wanted()
	for index = 1, #KEYS do
		if wanted then
			Take(KEYS[index])
		else
			Give(KEYS[index])
		end
	end
	if wanted then
		ShutTheirs()
	end
	held = wanted
	return true
end

function Blizz.Held()
	return held
end

-- How many of the nine this client has. Public because "the bags did not open"
-- is a question with two answers on a build that spells one of these
-- differently, and the panel has to be able to tell them apart.
function Blizz.Found()
	local found = 0
	for index = 1, #KEYS do
		if kept[KEYS[index].name] or type(_G[KEYS[index].name]) == "function" then
			found = found + 1
		end
	end
	return found, #KEYS
end

function Blizz.Describe()
	if not ns.db.bagsHideBlizz then
		return "on screen, and B opens them"
	end
	local found, of = Blizz.Found()
	if not held then
		return ("on screen; %d of %d calls found on this client"):format(found, of)
	end
	return ("shut, and B opens this one; %d of %d calls taken"):format(found, of)
end

-- On the once-a-second pass, beside Map/Blizzard.lua, Chat/Blizzard.lua and
-- Character/Blizzard.lua, all of which are on it for the same reason.
ns.BlizzHide.Also(Blizz.Apply)
