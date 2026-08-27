-- Which class this is
--
-- Ten of the twelve parts do not care. Two do: the charge button casts three
-- warrior abilities, and the loadout fills the bars with warrior spells. On
-- anyone else neither can do anything, so neither should be running, and the
-- charge part in particular has to be absent rather than merely quiet. A
-- hidden button is still a secure frame holding a key override, and a hidden
-- marker is still a nameplate scan twenty times a second.
--
-- Both halves are decided once, at PLAYER_LOGIN, which is why this file takes
-- a class on the command line instead of flipping one here. Every check below
-- is written against WARRIOR rather than against a fixed answer, so the same
-- section is a gate on both runs: the warrior run proves the parts are built
-- and the other run proves they are not.
--
-- The CVar is the one worth stating plainly. Action targeting exists to serve
-- the charge button, so on another class the addon must leave the client's own
-- setting exactly as it found it, and "the addon does nothing" is only ever
-- provable by reading the thing it would have written.

local H = ...
local PLAYER_CLASS, WARRIOR, cvars = H.PLAYER_CLASS, H.WARRIOR, H.cvars
local ns, fire, check = H.ns, H.fire, H.check
local window = H.carry.window

check(ns.IsWarrior() == WARRIOR,
	("the addon thinks a %s is%s a warrior"):format(PLAYER_CLASS, WARRIOR and " not" or ""))

check((_G.WarriorKitChargeButton ~= nil) == WARRIOR,
	("the charge button %s built on a %s"):format(WARRIOR and "was not" or "was", PLAYER_CLASS))
check((_G.WarriorKitChargeMarker ~= nil) == WARRIOR,
	("the world marker %s built on a %s"):format(WARRIOR and "was not" or "was", PLAYER_CLASS))
check(ns.Charge.Known("charge") == WARRIOR,
	("a %s %s Charge"):format(PLAYER_CLASS, WARRIOR and "does not know" or "knows"))

-- Put the client's own value back under the addon and let it decide again.
-- A warrior is out of combat here, so the setting says on; anyone else has
-- to come out of this with the same "0" they went in with.
cvars.SoftTargetEnemy = "0"
fire("PLAYER_ENTERING_WORLD")
check(cvars.SoftTargetEnemy == (WARRIOR and "3" or "0"),
	("action targeting came out at %s on a %s"):format(cvars.SoftTargetEnemy, PLAYER_CLASS))

-- The key. Refused rather than accepted and dropped, because a binding the
-- panel shows and nothing presses is worse than being told why.
local held = ns.db.chargeKey
local displaced, why = ns.ChargeIcon.Bind("F")
check((displaced ~= nil) == WARRIOR,
	("binding the charge key on a %s came back %s"):format(PLAYER_CLASS, tostring(displaced or why)))
ns.ChargeIcon.Bind(held)

-- The loadout's own class gate is not reached from here: this stub has no
-- PickupSpell, so Layout.CanWrite refuses before the class is asked, and a
-- check on the message would be a check on the missing stub. It reads the
-- same ns.IsWarrior as everything above.

-- The charge part's own tabs in the options window. Five on a warrior, one
-- page saying why on anyone else, rather than check boxes that write a setting
-- nothing on this character reads. Counted off the sections rather than off a
-- rail entry, because the rail is groups now and Fighting holds four parts.
local tabs = 0
for _, group in ipairs(window.groups) do
	for _, section in ipairs(group.sections) do
		if section.feature and section.feature.name == "charge" then
			tabs = tabs + 1
		end
	end
end
check(tabs == (WARRIOR and 5 or 1),
	("the charge part opened %d tabs on a %s"):format(tabs, PLAYER_CLASS))

local status
for _, feature in ipairs(ns.features) do
	if feature.name == "charge" then
		status = feature.status()
	end
end
check(status ~= nil, "the charge part reports no status line")
check(WARRIOR or (status and status:find("not a warrior", 1, true) ~= nil),
	("the charge status line on a %s does not say why: %s"):format(PLAYER_CLASS, tostring(status)))

print(("class   %s: charge button %s, world marker %s, action targeting %s, Charge page %d tab%s")
	:format(PLAYER_CLASS,
		_G.WarriorKitChargeButton and "built" or "not built",
		_G.WarriorKitChargeMarker and "built" or "not built",
		cvars.SoftTargetEnemy == "0" and "left alone" or ("driven to " .. cvars.SoftTargetEnemy),
		tabs, tabs == 1 and "" or "s"))
