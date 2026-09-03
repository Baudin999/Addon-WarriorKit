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
-- slug, checked against the cooldown the page states.
--
-- Two races carry three ids, and that is the bug this table shipped with. The
-- client ships Blood Fury and Berserking once per power type, one spell per
-- class group with its own id and its own cost, and a character knows exactly
-- one of the three. This file held one id per race, the warrior's Blood Fury
-- and the rogue's Berserking, so a troll shaman was asked about a spell they
-- never learned, the client answered no cooldown for it, and the racial read
-- ready through the whole of its three minutes and nagged while it was.
-- Racials.Spell walks the list for the id this character knows.
--
-- The three Blood Furies, off Wowhead's TBC pages: 20572 costs nothing and
-- gives attack power, and is the one a warrior, a hunter and a rogue know.
-- 20572 has a second proof, it appears as a buff with uptime in this
-- install's own Details saved variables recorded off a live 2.5.6 session.
-- 33697 gives attack power and spell damage, and is the shaman's. 33702 gives
-- spell damage and healing, and is the mage's, the warlock's and the priest's.
--
-- The three Berserkings, the same way: 26296 costs 5 rage and is the
-- warrior's. 20554 costs 6% of base mana and is what every mana user knows,
-- the shaman on this account among them. 26297 costs 10 energy and is the
-- rogue's. Nothing else about the three differs.
--
-- Blood elves are absent on purpose. Arcane Torrent is two spells split by
-- power type, no warrior can be one on either client, and it is an interrupt
-- rather than a cooldown, so it would ship with nag off and never draw. An
-- entry that can never draw is not coverage.
local BY_RACE = {
	-- Blood Fury, 2 minute cooldown, 15 seconds of attack power. The reason
	-- this feature exists.
	Orc = { spells = { 20572, 33697, 33702 }, nag = true },

	-- Berserking, 3 minute cooldown. Haste rather than attack power and the
	-- same argument: pressed on cooldown or thrown away.
	Troll = { spells = { 26296, 20554, 26297 }, nag = true },

	-- War Stomp, 2 minutes. An area stun. Worth having and worth spending when
	-- something needs stunning, which is not "whenever it is ready".
	Tauren = { spells = { 20549 } },

	-- Will of the Forsaken, 2 minutes. Scourge is the token the client uses for
	-- undead, not "Undead". Spent on a fear, so never on a timer.
	Scourge = { spells = { 7744 } },

	-- Stoneform, 3 minutes. A defensive spent on a bleed or a poison.
	Dwarf = { spells = { 20594 } },

	-- Escape Artist, 1.75 minutes. Spent on a root.
	Gnome = { spells = { 20589 } },

	-- Perception, 3 minutes. Stealth detection, and nothing to do with damage.
	Human = { spells = { 20600 } },

	-- Shadowmeld, 10 seconds. Cannot be used in combat at all on this client,
	-- so it could never appear on a row that only draws in combat.
	NightElf = { spells = { 20580 } },

	-- Gift of the Naaru, 3 minutes. A heal over time, spent when you are hurt.
	Draenei = { spells = { 28880 } },
}

-- Held from the first answer that is not nil, which is ns.Class.Token's rule and
-- is here for the same two reasons.
--
-- Race data is not reliably there while the files load, so an answer taken then
-- would be nil and a nil written down would lock an orc out of this for the
-- whole session. Nothing is written down until the client has spoken.
--
-- After that it is a local read. A character does not change race, and the row
-- asked this three times a tick through Worth, Name and Ready: six calls to
-- UnitRace every tenth of a second to be told the same word all evening.
local token, mine

-- The one of the race's ids this character knows, held once found. Below.
local known

function Racials.Mine()
	if token then
		return mine or nil
	end
	if type(UnitRace) ~= "function" then
		return nil
	end
	local _, now = UnitRace("player")
	if not now then
		return nil
	end
	token = now
	mine = BY_RACE[now] or false
	return mine or nil
end

-- Drops the held race so the next ask reads the client again.
--
-- Nothing in a session calls this and nothing should: a race is settled before
-- you log in. scripts/harness.lua is four characters in one process, and this
-- is how it changes its mind about which one it is.
function Racials.Forget()
	token, mine, known = nil, nil, nil
end

-- The spell id of your racial, or nil for a race with none listed.
--
-- The first of the race's ids this client names and this character knows,
-- which is the walk Cooldowns/Cooldowns.lua's Resolve makes for the row and
-- for the same reason: an id is one class's copy of the spell, and only the
-- book says which copy is yours. Held once IsSpellKnown has said yes to one,
-- because a character does not change class either.
--
-- Until it says yes, the first id the client can name is answered and nothing
-- is held. That is a client whose book has not loaded yet, or one that does
-- not carry racials in IsSpellKnown at all, and on the first the next ask
-- gets it right while a held guess would have been wrong all session. On the
-- second the walk is three cheap calls a tick, which is what the row paid to
-- read the race before it was held, and Describe says which of the two you
-- are on.
function Racials.Spell()
	if known then
		return known
	end
	local entry = Racials.Mine()
	if not entry then
		return nil
	end
	local first
	for index = 1, #entry.spells do
		local id = entry.spells[index]
		if ns.SpellNameHeld(id) then
			first = first or id
			if IsSpellKnown(id) then
				known = id
				return id
			end
		end
	end
	return first
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

-- Whether a press would land right now.
--
-- Buttons/Castable.lua's ladder, which is the action bars' own, and the whole
-- of it: a global sweep is not a cooldown, a real one is, and a Berserking you
-- cannot afford is not a press either. This used to read the cooldown alone,
-- so a warrior at four rage was told to press a five rage racial.
--
-- On the tick.
function Racials.Ready()
	local id = Racials.Spell()
	if not id then
		return false
	end
	return ns.Castable.State(id) == "ready"
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
		return ("spell %d, which this client cannot name"):format(entry.spells[1])
	end
	if not entry.nag then
		return name .. ", which is situational rather than damage, so it is never nagged"
	end
	local id = Racials.Spell()
	local book = known and "known" or "not known to this character, so the first the client names"
	return ("%s (spell %d, %s), %s"):format(name, id, book, ns.Castable.State(id))
end
