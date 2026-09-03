local ADDON, ns = ...

local Castable = {}
ns.Castable = Castable

--------------------------------------------------------------------------
-- Would a press of this spell land
--
-- The ladder Buttons/Slot.lua climbs for an action slot, climbed for a spell
-- instead, and the one place it is climbed for anything that is not a slot.
--
-- Why it exists. The cooldown row asked the client one question, whether the
-- spell's own cooldown was running, and drew "ready" on every other answer.
-- Bloodthirst at five rage read ready. Overpower read ready with nothing
-- having dodged you. Berserking read ready on a shaman for the whole of its
-- three minutes. The bars had every one of those rungs and the row had none,
-- because the row was written to count minutes and then got read as a bar.
-- Two readers of one fact disagreeing is the defect, so the fact is answered
-- once, here, and both read it.
--
--   Castable.Beyond   the two rungs the client cannot answer at all: a shut
--                     reaction window and an unmet condition. Buttons/Slot.lua
--                     asks it by name for a square, State below asks it for a
--                     spell, and Buttons/Reaction.lua and Buttons/Requires.lua
--                     own the two mechanisms behind it.
--
--   Castable.State    the whole ladder for one spell: its own cooldown, then
--                     nothing to aim it at, then Beyond, then whatever the
--                     client refuses it for. Cooldowns/Cooldowns.lua asks it
--                     for every square on the row and Buffs/Racials.lua asks
--                     it for your racial.
--
-- Slot.State keeps its own copy of the lower rungs on purpose. Those are asked
-- of the slot, through IsUsableAction and IsActionInRange, which know what is
-- in the slot better than a spell id does, and a macro is a slot with no one
-- id. What a slot and a spell share is exactly Beyond, and it is shared.
--
-- The order is the ladder's own rule, stated in Slot.lua and not restated
-- here: what cannot be fixed at all comes first, then what a click fixes, then
-- what a stance swap or a few seconds of rage fixes. Range is not asked. A
-- square on the cooldown row is a picture of an ability with a number on it,
-- not a button, and the bar under your hand already colours for range.
--
-- Two names for one spell, and each rung is asked in the one it answers best.
-- The cooldown is read off the id, because every rank shares one cooldown and
-- the id is what the row counts by. Everything else is read off the client's
-- own name for the spell, because a name resolves through your spellbook to
-- the rank you press: IsUsableSpell of rank one of Earth Shock answers for
-- thirty mana, and the rank on your bar costs five hundred. Slot.lua asks the
-- same call by name for a macro, for the same reason.
--
-- Memoised per frame per spell. GetTime is frame-constant, the row and a bar
-- holding the same spell ask in the same frame, and the racial is asked by two
-- rows; Charge/Charge.lua holds its own state the same way. Four tables keyed
-- by spell, filled once per spell ever asked about and written in place after
-- that, so the tick allocates nothing.
--
-- Everything below runs on three tickers. check.sh's HOT list covers it.
--------------------------------------------------------------------------

-- Below this a cooldown is the global and not the ability's own. The same 1.5
-- Buttons/Slot.lua and Charge/Charge.lua carry, stated again for the reason
-- each of them states: the same number for the same reason, and a client that
-- ever moved one would not have moved the others.
local GCD = 1.5

-- The two rungs that know more than the client does, as one question, or nil
-- when neither has anything to say. Most of a bar is nil in two table lookups.
--
-- Overpower and Revenge are not spells you press, they are spells the fight
-- hands you, and the client will not say so. IsUsableAction answers yes for
-- Overpower in Battle Stance whether or not anything has dodged you, so
-- without this the square said "ready" for the whole of every fight. Execute
-- is the same defect read off the target instead of out of the log: usable
-- from full health down, and castable for the last fifth of a fight.
--
-- Above the usable split rather than below it, and that is the ladder's own
-- rule rather than a preference: what cannot be fixed at all comes first. A
-- shut window is not something you can do anything about, and neither is a
-- mob at half health, and a wrong stance is. Overpower sitting in Defensive
-- Stance used to draw orange "swap" from the first pull to the last, which is
-- a colour saying "swap and press this" over a press that would not land. Now
-- the orange appears on the two or three seconds where swapping really would
-- let you press it, and the rest of the time the square is quiet.
--
-- The order between the two is arbitrary today, because no ability a class
-- file names is both a reactive and a condition. Written in the order the
-- harness already drives.
function Castable.Beyond(name)
	local reactive = ns.Reaction.OfSpell(name)
	if reactive and not ns.Reaction.Open(reactive) then
		return "reaction"
	end
	return ns.Requires.State(name)
end

-- The ladder, walked once. Castable.State is the memo in front of it.
--
-- Six of the ten statuses are reachable. "unknown" is the client refusing to
-- answer for the spell, "cooldown" a real wait, and "notarget", "reaction",
-- "condition", "cost" and "stance" the reasons a press would do nothing.
-- "ready" is a press. "empty" and "combat" are a slot's and Charge's and
-- cannot come out of here.
--
-- The swipe's two numbers ride along under every status but "unknown", the
-- way Slot.State returns them: a global is not a status, and the swipe is the
-- one thing on screen that answers a key press.
local function Answer(spell)
	local start, duration, enabled = ns.SpellCooldown(spell)
	if enabled == false then
		return "unknown"
	end
	local running = duration and duration > 0 and start and start > 0
	if running and duration > GCD then
		return "cooldown", start, duration
	end
	local swipeStart, swipeDuration
	if running then
		swipeStart, swipeDuration = start, duration
	end

	-- Nothing to aim it at, for an ability aimed at something. Slot.Aimless
	-- owns what "nothing" means, and Requires.lua refuses to read a threshold
	-- off a unit that is not there, so this stands above Beyond.
	local name = ns.SpellNameHeld(spell)
	if name and ns.SpellHarmful(name) and ns.Slot.Aimless() then
		return "notarget", swipeStart, swipeDuration
	end

	local beyond = name and Castable.Beyond(name)
	if beyond then
		return beyond, swipeStart, swipeDuration
	end

	-- The client's own answer, and the second return is the whole reason this
	-- is not a boolean: no for a spell you cannot afford and no for one you
	-- cannot cast in this stance, and on a warrior those are the two states a
	-- fight is made of.
	local usable, noPower = ns.SpellUsable(name or spell)
	if not usable then
		return noPower and "cost" or "stance", swipeStart, swipeDuration
	end
	return "ready", swipeStart, swipeDuration
end

-- The frame each spell was last answered in, and the answer.
local askedAt, statusOf, startOf, durationOf = {}, {}, {}, {}

-- Returns a status from UI/Ability.lua's vocabulary, and the swipe's start and
-- duration where there is one.
function Castable.State(spell)
	local now = GetTime()
	if askedAt[spell] ~= now then
		askedAt[spell] = now
		statusOf[spell], startOf[spell], durationOf[spell] = Answer(spell)
	end
	return statusOf[spell], startOf[spell], durationOf[spell]
end
