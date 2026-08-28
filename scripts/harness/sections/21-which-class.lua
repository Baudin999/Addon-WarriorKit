-- Which class this is, and what it brought
--
-- Ten of the twelve parts do not care what you are. The ones that do read facts
-- off ns.Class rather than asking about a warrior, and a class that registered
-- no such fact has to be absent rather than merely quiet: a hidden charge button
-- is still a secure frame holding a key override, and a hidden world marker is
-- still a nameplate scan twenty times a second.
--
-- Every check below is written against what the registry says this character
-- brought, never against a fixed answer, so the same section is a gate on every
-- run: the warrior run proves the parts are built and the other runs prove they
-- are not. That is what makes it worth running the harness as more than one
-- class, and it is why this file takes the class on the command line instead of
-- flipping one here. Both halves are decided once, at PLAYER_LOGIN.
--
-- The CVar is the one worth stating plainly. Action targeting exists to serve
-- the charge button, so on a class without one the addon must leave the client's
-- own setting exactly as it found it, and "the addon does nothing" is only ever
-- provable by reading the thing it would have written.

local H = ...
local PLAYER_CLASS, WARRIOR, cvars = H.PLAYER_CLASS, H.WARRIOR, H.cvars
local ns, fire, check = H.ns, H.fire, H.check
local window = H.carry.window

local Class = ns.Class

--------------------------------------------------------------------------
-- The question itself
--------------------------------------------------------------------------

check(Class.Token() == PLAYER_CLASS,
	("the registry reads the class as %s and the client says %s")
		:format(tostring(Class.Token()), PLAYER_CLASS))
check(Class.Is(PLAYER_CLASS), ("a %s is not itself"):format(PLAYER_CLASS))
check(Class.Is("DRUID") == (PLAYER_CLASS == "DRUID"),
	("a %s reads as a druid"):format(PLAYER_CLASS))
check(Class.Is("WARRIOR") == WARRIOR,
	("the addon thinks a %s is%s a warrior"):format(PLAYER_CLASS, WARRIOR and " not" or ""))

-- A class nobody has written a file for is a supported class, not an error. It
-- gets everything that never asks and nothing that does.
local mine = Class.Mine()
check(mine == nil or mine.token == PLAYER_CLASS,
	("the registry handed a %s the file for %s")
		:format(PLAYER_CLASS, tostring(mine and mine.token)))
check((mine ~= nil) == (Class.Of("loadout") ~= nil or Class.Of("charge") ~= nil
	or Class.Of("reactive") ~= nil or Class.Of("swing") ~= nil
	or Class.Of("upkeep") ~= nil or Class.Of("forms") ~= nil),
	("a %s registered a file that fills in none of the six fields"):format(PLAYER_CLASS))

--------------------------------------------------------------------------
-- The charge button, which is built on one of those facts
--------------------------------------------------------------------------

local CHARGE = Class.Of("charge") ~= nil
check(ns.Charge.Available() == CHARGE,
	("the charge part disagrees with the registry about a %s"):format(PLAYER_CLASS))

check((_G.WarriorKitChargeButton ~= nil) == CHARGE,
	("the charge button %s built on a %s"):format(CHARGE and "was not" or "was", PLAYER_CLASS))
check((_G.WarriorKitChargeMarker ~= nil) == CHARGE,
	("the world marker %s built on a %s"):format(CHARGE and "was not" or "was", PLAYER_CLASS))
check(ns.Charge.Known("charge") == CHARGE,
	("a %s %s Charge"):format(PLAYER_CLASS, CHARGE and "does not know" or "knows"))

-- Put the client's own value back under the addon and let it decide again. A
-- class with the button is out of combat here, so the setting says on; anyone
-- else has to come out of this with the same "0" they went in with.
cvars.SoftTargetEnemy = "0"
fire("PLAYER_ENTERING_WORLD")
check(cvars.SoftTargetEnemy == (CHARGE and "3" or "0"),
	("action targeting came out at %s on a %s"):format(cvars.SoftTargetEnemy, PLAYER_CLASS))

-- The key. Refused rather than accepted and dropped, because a binding the
-- panel shows and nothing presses is worse than being told why.
local held = ns.db.chargeKey
local displaced, why = ns.ChargeIcon.Bind("F")
check((displaced ~= nil) == CHARGE,
	("binding the charge key on a %s came back %s"):format(PLAYER_CLASS, tostring(displaced or why)))
ns.ChargeIcon.Bind(held)

local status
for _, feature in ipairs(ns.features) do
	if feature.name == "charge" then
		status = feature.status()
	end
end
check(status ~= nil, "the charge part reports no status line")
check(CHARGE or (status and status:find(Class.Label(), 1, true) ~= nil),
	("the charge status line on a %s does not name the class: %s")
		:format(PLAYER_CLASS, tostring(status)))

--------------------------------------------------------------------------
-- The other four facts, each gating exactly one part
--------------------------------------------------------------------------

check(ns.Reaction.Watching() == (Class.Of("reactive") ~= nil),
	("the reaction windows disagree with the registry on a %s: %s")
		:format(PLAYER_CLASS, ns.Reaction.Describe()))
check(ns.Slam.Available() == (Class.Of("swing") ~= nil),
	("the swing window disagrees with the registry on a %s"):format(PLAYER_CLASS))
check((ns.Layout.Plan() ~= nil) == (Class.Of("loadout") ~= nil),
	("the loadout disagrees with the registry on a %s"):format(PLAYER_CLASS))
check(ns.Stance.Count() == #(Class.Of("forms") or {}),
	("the stance list is %d long and the registry gave %d")
		:format(ns.Stance.Count(), #(Class.Of("forms") or {})))

-- The loadout refuses by naming the class rather than by naming a warrior. This
-- stub has no PickupSpell, so CanApply refuses on the client before the class is
-- reached; Layout.Refusal is the sentence the panel and the status line read and
-- is asked directly.
check(ns.Layout.Refusal():find(Class.Label(), 1, true) ~= nil,
	("the loadout refusal on a %s does not name the class: %s")
		:format(PLAYER_CLASS, ns.Layout.Refusal()))

-- What your class puts on the buff row is merged in, and nobody else's is.
local shipped = ns.Upkeep.Fixed()
local added = #shipped - 3
check(added == #(Class.Of("upkeep") or {}),
	("the buff row took %d class entries and the registry gave %d")
		:format(added, #(Class.Of("upkeep") or {})))
check(#shipped <= ns.Upkeep.Ceiling() - 6,
	("the buff row is %d long and the row was built for %d")
		:format(#shipped, ns.Upkeep.Ceiling() - 6))
check((ns.Upkeep.ByWord("shout") ~= nil) == WARRIOR,
	("battle shout is %s on the row of a %s")
		:format(WARRIOR and "missing from" or "on", PLAYER_CLASS))
check(WARRIOR or ns.Upkeep.Elsewhere("shout") == "warrior",
	("a %s is not told which class the word shout belongs to"):format(PLAYER_CLASS))

--------------------------------------------------------------------------
-- The rail entry named after you
--
-- One group, third, holding every page that only exists because of what you
-- are, and no group named after a class you are not. A class that opened no
-- such page has no entry at all, which is the whole point: the window shows
-- your class's settings and nobody else's.
--------------------------------------------------------------------------

local classGroup, at
for index, group in ipairs(window.groups) do
	if group.name == (Class.Name() or Class.Label()) then
		classGroup, at = group, index
	end
end

local classPages = 0
for _, group in ipairs(window.groups) do
	for _, section in ipairs(group.sections) do
		if section.feature and section.feature.name == "charge" then
			classPages = classPages + 1
		end
	end
end

check(classPages == (CHARGE and 5 or 0),
	("the charge part opened %d pages on a %s"):format(classPages, PLAYER_CLASS))

if classGroup then
	check(at == 3, ("the group named after you sits at %d and belongs at 3"):format(at))
	check(#classGroup.sections > 0,
		("the %s group is in the rail with nothing on it"):format(classGroup.name))
	-- Every page under it came from a part that is gated on a class fact. A page
	-- that belongs to everybody landing here would be a setting somebody cannot
	-- find on the character they were looking for it on.
	for _, section in ipairs(classGroup.sections) do
		local part = section.feature and section.feature.name
		check(part == "charge" or part == "buttons" or part == "swing",
			("%s put %q under the class group and is not gated on a class")
				:format(tostring(part), section.title))
	end
else
	check(not CHARGE and ns.Layout.Plan() == nil and not ns.Slam.Available(),
		("a %s opened a class page and got no rail entry for it"):format(PLAYER_CLASS))
end

-- No group is named after a class this character is not.
for _, group in ipairs(window.groups) do
	for token, def in pairs(Class.All()) do
		local proper = def.label:sub(1, 1):upper() .. def.label:sub(2)
		check(group.name ~= proper or token == PLAYER_CLASS,
			("the rail holds a group called %s on a %s"):format(group.name, PLAYER_CLASS))
	end
end

-- A part that is not built here takes no row on Start here either. A switch
-- pointing at a page that does not exist is worse than no switch.
for _, feature in ipairs(ns.features) do
	if feature.name == "charge" then
		check(ns.Options.SwitchAvailable(feature) == CHARGE,
			("the charge switch reads available on a %s"):format(PLAYER_CLASS))
	end
end

print(("class   %s: %s, charge button %s, action targeting %s, %d class page%s under %s")
	:format(PLAYER_CLASS,
		mine and "a file of its own" or "no file, and none needed",
		_G.WarriorKitChargeButton and "built" or "not built",
		cvars.SoftTargetEnemy == "0" and "left alone" or ("driven to " .. cvars.SoftTargetEnemy),
		classGroup and #classGroup.sections or 0,
		(classGroup and #classGroup.sections or 0) == 1 and "" or "s",
		classGroup and classGroup.name or "no rail entry"))
