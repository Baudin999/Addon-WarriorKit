local ADDON, ns = ...

local Racials = {}
ns.Racials = Racials

--------------------------------------------------------------------------
-- The racial you are not pressing
--
-- This is a different question from the one Upkeep.lua answers and it deserved
-- saying out loud rather than being folded in beside the sharpening stone.
--
-- A missing buff is something that should be up and is not. You fix it by
-- applying it, you fix it out of combat, and the row is quiet during a fight
-- because there is nothing you could do about it mid pull.
--
-- Blood Fury is the opposite of all three. It is not a buff you keep up, it is
-- two minutes of attack power sitting on a key you forget to press, and the
-- only moment it is worth saying anything at all is the moment you are swinging
-- at something with it off cooldown. So this half fires in combat, when the
-- other half is deliberately silent, and the two can never be on screen at
-- once. That is what lets them share one row: they are not competing for space,
-- they are taking turns.
--
-- The long personal cooldowns are not here. Death Wish and Recklessness are
-- timed by hand on purpose and are item 7 in todo.md; a row that started
-- nagging about them would be that feature, built early and in the wrong place.
--------------------------------------------------------------------------

-- The race token, which is UnitRace's second return and is the same string in
-- every locale. The first return is the localised name and matching on it would
-- work in English and nowhere else.
--
-- Probed rather than trusted. Nothing installed on this machine calls UnitRace
-- unguarded, and a nil call on the tick is the failure that gets the whole
-- addon offered up for disabling.
local UnitRace = _G.UnitRace

-- Below this a cooldown is the global rather than the ability's own. The same
-- 1.5 Buttons/Slot.lua carries, stated again here for the reason that file
-- states: they are the same number for the same reason and a client that ever
-- moved one would not have moved the other.
local GCD = 1.5

--------------------------------------------------------------------------
-- One racial per race, and whether an idle one is worth shouting about
--
-- `nag` is the whole editorial decision in this file. Two of these are
-- throughput: they are damage you are choosing not to do, they come back every
-- two or three minutes, and forgetting one across a whole boss fight is free
-- damage thrown away. Those two get nagged about.
--
-- The rest are situational and are listed with nag off. Nagging you to press
-- Stoneform because it happens to be ready would be exactly wrong: it is a
-- cooldown you spend when something bleeds you, and a row that shouted about it
-- every fight would teach you to ignore the row, which costs you Blood Fury as
-- well. They are here anyway so the status line and the panel can name your
-- racial and say why it is never nagged, which is a better answer than silence.
--
-- Every id below is the one Wowhead's TBC Classic database gives for that spell
-- slug, checked against the cooldown the page states. Blood Fury has a second
-- proof: 20572 appears as a buff with uptime in this install's own Details
-- saved variables, recorded off a live 2.5.6 session, so it is the id this
-- client actually casts and not a database entry that happens to share a name.
--
-- Blood elves are absent on purpose. Arcane Torrent is two spells split by
-- power type, no warrior can be one on either client, and it is an interrupt
-- rather than a cooldown, so it would ship with nag off and never draw. An
-- entry that can never draw is not coverage.
local BY_RACE = {
	-- Blood Fury, 2 minute cooldown, attack power for 15 seconds. The reason
	-- this feature exists.
	Orc = { spell = 20572, nag = true },

	-- Berserking, 3 minute cooldown. Haste rather than attack power and the
	-- same argument: pressed on cooldown or thrown away.
	Troll = { spell = 26297, nag = true },

	-- War Stomp, 2 minutes. An area stun. Worth having and worth spending when
	-- something needs stunning, which is not "whenever it is ready".
	Tauren = { spell = 20549 },

	-- Will of the Forsaken, 2 minutes. Scourge is the token the client uses for
	-- undead, not "Undead". Spent on a fear, so never on a timer.
	Scourge = { spell = 7744 },

	-- Stoneform, 3 minutes. A defensive spent on a bleed or a poison.
	Dwarf = { spell = 20594 },

	-- Escape Artist, 1.75 minutes. Spent on a root.
	Gnome = { spell = 20589 },

	-- Perception, 3 minutes. Stealth detection, and nothing to do with damage.
	Human = { spell = 20600 },

	-- Shadowmeld, 10 seconds. Cannot be used in combat at all on this client,
	-- so it could never appear on a row that only draws in combat.
	NightElf = { spell = 20580 },

	-- Gift of the Naaru, 3 minutes. A heal over time, spent when you are hurt.
	Draenei = { spell = 28880 },
}

-- Asked every time and looked up only when the answer moves, which is the shape
-- ns.IsWarrior uses and for the same reason. Race data is not reliably there
-- while files load, and a nil cached at load would lock an orc out of this for
-- the whole session. What is cached is the lookup, not the client's answer, so
-- the entry table stays the same table between ticks and nothing that compares
-- by identity sees it move.
local token, mine

function Racials.Mine()
	if type(UnitRace) ~= "function" then
		return nil
	end
	local _, now = UnitRace("player")
	if not now then
		return mine or nil
	end
	if now ~= token then
		token = now
		mine = BY_RACE[now] or false
	end
	return mine or nil
end

-- The spell id of your racial, or nil for a race with none listed.
function Racials.Spell()
	local entry = Racials.Mine()
	return entry and entry.spell or nil
end

-- This client's own name for it, and nil where the client does not know the id.
-- Nil is what makes the entry undrawable rather than drawn blank.
function Racials.Name()
	local spell = Racials.Spell()
	return spell and ns.SpellName(spell) or nil
end

function Racials.Texture()
	local spell = Racials.Spell()
	return spell and ns.SpellTexture(spell) or nil
end

-- Whether your racial is one this row will ever shout about.
function Racials.Worth()
	local entry = Racials.Mine()
	return entry ~= nil and entry.nag == true
end

-- Off cooldown right now.
--
-- A global sweep is not a cooldown, which is the rule the action bar squares
-- already follow. Blood Fury has no global of its own, but the ability you just
-- pressed put one on the client and the racial would read as busy for a second
-- and a half of every rotation if that counted.
--
-- On the tick.
function Racials.Ready()
	local spell = Racials.Spell()
	if not spell then
		return false
	end
	local _, duration, enabled = ns.SpellCooldown(spell)
	if enabled == false then
		return false
	end
	if duration and duration > GCD then
		return false
	end
	return true
end

-- Ready, worth shouting about, and this client can name the spell. The combat
-- half of the test lives in Nag.lua, because whether you are in a fight is a
-- fact about the row rather than about the racial.
--
-- On the tick.
function Racials.Idle()
	if not Racials.Worth() then
		return false
	end
	if not Racials.Name() then
		return false
	end
	return Racials.Ready()
end

function Racials.Describe()
	if type(UnitRace) ~= "function" then
		return "this client does not answer UnitRace, so no racial is watched"
	end
	local entry = Racials.Mine()
	if not entry then
		return "no racial listed for your race"
	end
	local name = Racials.Name()
	if not name then
		return ("spell %d, which this client cannot name"):format(entry.spell)
	end
	if not entry.nag then
		return name .. ", which is situational rather than damage, so it is never nagged"
	end
	return name .. (Racials.Ready() and ", ready" or ", on cooldown")
end
