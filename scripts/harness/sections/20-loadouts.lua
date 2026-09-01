-- Loadouts
--
-- The macro is the whole feature. Everything else in this part is a panel row
-- or an override binding, and what a key press actually sends is one string on
-- one attribute, so that string is what is asserted: the lines, their order,
-- the two rules that drop a line, the fight that defers the lot, and the
-- delete that has to move every binding under it onto a different button.
--
-- What this cannot prove: that the client runs two /equipslot lines off one
-- press, or what it does with a full bag when a two hander comes off. Nothing
-- installed on either client calls /equipslot, so those two answers are a key
-- press in game and nothing else.

local H = ...
local ns, fire, check = H.ns, H.fire, H.check

local BATTLE, DEFENSIVE, BERSERKER = 1, 2, 3

local function LoadoutMacro(index)
	return _G[ns.Loadouts.ButtonName(index)]:GetAttribute("macrotext") or ""
end

local link = _G.WarriorKitItemLink

-- One seeded per form your class has, and seeded once rather than on every
-- login. A class with no forms is seeded nothing at all, because a row bound to
-- a stance it cannot enter is a row to delete; it gets the same three by hand
-- here, since everything below this is about what a press sends and that is the
-- same job either way.
local FORMS = ns.Stance.Count()

if FORMS > 0 then
	check(ns.Loadouts.Count() == FORMS,
		("%d loadouts were seeded for %d forms"):format(ns.Loadouts.Count(), FORMS))
	check(ns.Loadouts.Get(DEFENSIVE).stance == 2,
		"the second seeded loadout is not bound to the second form")
else
	check(ns.Loadouts.Count() == 0,
		("%d loadouts were seeded on a class with no forms"):format(ns.Loadouts.Count()))
	for index = 1, 3 do
		ns.Loadouts.Add("Set " .. index)
	end
end

-- The seed has to tell "no forms" from "the client has not said yet", and the
-- two read the same: an unresolved class has no file, so it counts zero forms
-- exactly as a mage does. loadoutsSeeded is the one answer in the addon that is
-- kept, so a read before the client answers must record nothing, or a warrior
-- who was asked one event too early carries an empty list for the life of the
-- character. Take the token away rather than the class, because Mine and Of
-- both go through it and this is the state the addon is in for the whole of
-- ADDON_LOADED.
do
	local realToken = ns.Class.Token
	local held = ns.dbc.loadoutsSeeded
	local before = #ns.dbc.loadouts

	ns.dbc.loadoutsSeeded = nil
	ns.Class.Token = function() return nil end

	local list = ns.Loadouts.All()
	check(not ns.dbc.loadoutsSeeded,
		"the loadout seed latched before the client had named the class")
	check(#list == before,
		("the loadout list came back %d long before the class was known and was %d")
			:format(#list, before))

	ns.Class.Token = realToken
	ns.dbc.loadoutsSeeded = held
	check(ns.dbc.loadoutsSeeded == true,
		"the seed had not run by the time the section that reads it did")
end

-- The stance line, or nothing on a class that has none. A loadout with no stance
-- is a weapon set with a key on it, which is a path this section reaches twice.
local function Lines(...)
	local want = {}
	if FORMS > 0 then
		want[1] = "/cast [nostance:2] " .. ns.Stance.Name(2)
	end
	for index = 1, select("#", ...) do
		want[#want + 1] = select(index, ...)
	end
	return table.concat(want, "\n")
end

ns.Loadouts.SetItem(DEFENSIVE, ns.Gear.MAINHAND, link("Bloodspiller"))
ns.Loadouts.SetItem(DEFENSIVE, ns.Gear.OFFHAND, link("Aegis"))

-- Main hand before off hand, because going from a two hander to a one hander
-- and a shield the first line is what frees the hand the second one needs.
check(LoadoutMacro(DEFENSIVE) == Lines(
	"/equipslot 16 Bloodspiller",
	"/equipslot 17 Aegis"),
	"the defensive macro is not its lines in order:\n" .. LoadoutMacro(DEFENSIVE))

-- A shield is not a main hand and a two hander is not an off hand. Both are
-- refused with a reason rather than saved and left to fail as a macro line.
check(ns.Loadouts.SetItem(BATTLE, ns.Gear.MAINHAND, link("Aegis")) == nil,
	"a shield was accepted into the main hand")
check(ns.Loadouts.SetItem(BATTLE, ns.Gear.OFFHAND, link("Arcanite Reaper")) == nil,
	"a two hander was accepted into the off hand")

-- A two hander in the main hand takes the off hand line out, whatever is saved
-- in that slot, because both hands are already spoken for.
ns.Loadouts.SetItem(BATTLE, ns.Gear.OFFHAND, link("Aegis"))
ns.Loadouts.SetItem(BATTLE, ns.Gear.MAINHAND, link("Arcanite Reaper"))
check(not LoadoutMacro(BATTLE):find("equipslot 17", 1, true),
	"a two hander left the off hand line in the macro:\n" .. LoadoutMacro(BATTLE))

-- The combat rule is a conditional on the equip lines and nothing else. The
-- stance still swaps mid fight; only the hands wait.
ns.dbc.loadoutSwapCombat = false
ns.Loadouts.Apply()
check(LoadoutMacro(DEFENSIVE) == Lines(
	"/equipslot [nocombat] 16 Bloodspiller",
	"/equipslot [nocombat] 17 Aegis"),
	"the combat rule did not reach both equip lines:\n" .. LoadoutMacro(DEFENSIVE))
ns.dbc.loadoutSwapCombat = true
ns.Loadouts.Apply()

-- A loadout with no stance is weapons and a key and nothing else, which is the
-- shape every custom one starts in.
local custom = ns.Loadouts.Add("Sword and board")
check(custom == 4, ("a fourth loadout did not land at 4, got %s"):format(tostring(custom)))
ns.Loadouts.SetItem(custom, ns.Gear.MAINHAND, link("Bloodspiller"))
check(LoadoutMacro(custom) == "/equipslot 16 Bloodspiller",
	"a loadout with no stance still cast one:\n" .. LoadoutMacro(custom))

-- One key cannot be two loadouts. The second claim is refused, and refused
-- without taking the key off the first, because two on one key is the mistake
-- the panel cannot show you afterwards.
check(ns.Loadouts.Bind(BATTLE, "SHIFT-1") ~= nil, "the client would not take SHIFT-1")
check(ns.Loadouts.Bind(DEFENSIVE, "SHIFT-1") == nil,
	"two loadouts were allowed to claim SHIFT-1")
check(ns.Loadouts.Describe(BATTLE) == "SHIFT-1",
	"a refused claim moved the key off the loadout that already held it")

-- Deleting a row shifts every row under it onto a different secure button, so
-- every binding is rebuilt from the list rather than only the one that moved.
-- Without that, SHIFT-2 would still be pointing at the macro Berserker used to
-- carry and would quietly do somebody else's job.
ns.Loadouts.Bind(custom, "SHIFT-2")
check(ns.Loadouts.Remove(BERSERKER), "the third loadout would not delete")
check(ns.Loadouts.Count() == 3, "the list is the wrong length after a delete")
check(ns.Loadouts.Get(3).name == "Sword and board", "the custom loadout did not shift down")
check(LoadoutMacro(3):find("Bloodspiller", 1, true) ~= nil,
	"the shifted loadout's macro did not follow it:\n" .. LoadoutMacro(3))
check(_G.GetBindingAction("SHIFT-2", true) == ("CLICK %s:LeftButton"):format(ns.Loadouts.ButtonName(3)),
	"a delete left a key bound to the button the deleted row was on")
check(LoadoutMacro(4) == "", "the button the list no longer reaches still carries a macro")

-- An attribute cannot be written under lockdown, so a loadout changed in a
-- fight is held and written when the fight ends. Both halves are asserted,
-- because a part that only did the first would silently lose the change.
do
	local realLockdown = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	ns.Loadouts.SetItem(DEFENSIVE, ns.Gear.MAINHAND, link("Arcanite Reaper"))
	check(not LoadoutMacro(DEFENSIVE):find("Arcanite", 1, true),
		"a secure macro was rewritten in combat")
	_G.InCombatLockdown = realLockdown
	fire("PLAYER_REGEN_ENABLED")
	check(LoadoutMacro(DEFENSIVE):find("Arcanite", 1, true) ~= nil,
		"the loadout changed in combat never landed after it:\n" .. LoadoutMacro(DEFENSIVE))
end

-- The key surviving the client building its binding set again.
--
-- This is the bug the whole of ns.Rebind exists for. The client throws every
-- override away when it builds that set, and it builds it once during login
-- after PLAYER_LOGIN has already taken these keys, so a loadout key was dead
-- before anyone could press it and setting it again by hand every session was
-- the only thing that appeared to work.
--
-- The pass waits a frame, for the reason Core/Core.lua gives, so the frame is
-- driven here rather than assumed.
--
-- On a key no cloned bar wants. SHIFT-1 is one of the action bar's own, and a
-- rebuild puts the bars back on the event while this pass is still a frame
-- away, so the middle assertion below would be reading somebody else's
-- override rather than an empty key. The loadout still wins that key in the
-- end, because its pass runs after the bars', and that is the order it should
-- win in: a key typed into this panel beats a clone standing in for a bar.
do
	local KEY = "CTRL-F9"
	check(ns.Loadouts.Bind(1, KEY) ~= nil, "the client would not take " .. KEY)

	local held = ("CLICK %s:LeftButton"):format(ns.Loadouts.ButtonName(1))
	check(_G.GetBindingAction(KEY, true) == held,
		"the first loadout was not holding its key before the rebuild")

	_G.WarriorKitRebuildBindings()
	check(_G.GetBindingAction(KEY, true) == "",
		"the client stub kept an override the game would have thrown away")

	for _, f in ipairs(H.frames) do
		if f.scripts.OnUpdate and f.origin:match("Core/Core") then
			f.scripts.OnUpdate(f, 0)
		end
	end
	check(_G.GetBindingAction(KEY, true) == held,
		"the loadout key never came back after the client rebuilt its bindings")
end

print(("loadout %d of %d rows, %d secure buttons, defensive sends %d characters")
	:format(ns.Loadouts.Count(), ns.Loadouts.MAX, ns.Loadouts.MAX, #LoadoutMacro(DEFENSIVE)))
