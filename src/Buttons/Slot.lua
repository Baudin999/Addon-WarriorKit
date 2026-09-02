local ADDON, ns = ...

local Slot = {}
ns.Slot = Slot

--------------------------------------------------------------------------
-- What one action slot is doing
--
-- The same answers Charge/Charge.lua works out for the three charge abilities,
-- worked out for an action slot instead. Both hand their answer to
-- UI/Ability.lua, which draws it, and neither knows the other exists.
--
-- Why two sources and not one. A charge display asks "would a press put this
-- ability on that mob", where the mob is picked by camera or by cursor and the
-- ability is picked by combat state, so the whole question is resolved in Lua
-- before any slot is involved. A bar button asks "would a press do what is in
-- this slot", where the slot is whatever the loadout wrote and the client owns
-- every part of the answer. The ladders look alike because they draw on the
-- same vocabulary; the inputs have nothing in common.
--
-- What they do share is the order, and the order is the design. What cannot be
-- fixed at all comes first, then what a click on something fixes, then what a
-- stance swap or a few seconds of rage fixes, then range. Reversing any two of
-- those makes the square say the less useful of two true things: a spell you
-- have no rage for and are also out of range of is a spell to walk towards,
-- and one you are out of range of and cannot cast in this stance is a spell to
-- swap for.
--
-- Everything here runs on the bar's ticker against every button on it, so
-- nothing allocates and nothing is cached that the client already holds.
-- check.sh's HOT list covers Slot.State, Slot.Spell, Slot.Aimless, Slot.Active
-- and Slot.Equipped.
--------------------------------------------------------------------------

-- Below this a cooldown is the global and not the ability's own, and the two
-- are worth different things on the square.
--
-- A real cooldown is a status: it is why the press did nothing, it lasts long
-- enough to plan around, and it gets a number counting down over it. The global
-- is not a status at all. It is one and a half seconds, every ability has it,
-- and greying the whole bar for it would say twenty-four true and useless
-- things at once.
--
-- What the global does get is the swipe, with no number and no status change.
-- This file used to withhold that too, on the grounds that a bar sweeping on
-- every press is a strobe. It is, and that strobe is the only thing on screen
-- that answers a key press: below the global a rage dump has no cooldown, no
-- colour change and nothing to count, so a bar that also refused the swipe
-- changed no pixel at all when you pressed it. That is what made the squares
-- feel like a picture of a bar rather than a bar. Blizzard's own buttons sweep,
-- and so does every bar addon; withholding it was the odd choice.
--
-- So Slot.State returns the cooldown numbers whether or not it returns the
-- "cooldown" status, and UI/Ability.lua draws the swipe off the numbers and the
-- countdown off the status.
--
-- Stated as its own constant rather than shared with Charge/Charge.lua's,
-- which holds the identical 1.5. They are the same number for the same reason
-- and could be one, but the charge abilities are three known spells on a
-- warrior and a bar slot is anything at all, so a client that ever moved one
-- would not have moved the other.
local GCD = 1.5

-- Which unit a range check is asked about. The client answers for the target
-- and nothing else, which is the honest limit of a range indicator on a bar:
-- with nothing targeted there is no distance to be out of.
local RANGE_UNIT = "target"

--------------------------------------------------------------------------
-- Can this client do it
--
-- Probed rather than assumed, the same way Buttons/Layout.lua probes the
-- action-writing API. None of these five is confirmed to exist on 2.5.6 by
-- anything installed here, and a bar that raises once per button per tick is
-- worse than a bar that draws every square grey.
--------------------------------------------------------------------------

local NEEDED = {
	"HasAction", "GetActionTexture", "GetActionCooldown",
	"IsUsableAction", "IsActionInRange",
}

-- nil until asked, then true or a reason string.
--
-- Every reader below goes through Slot.CanRead rather than testing this
-- directly, and that is not tidiness. Nil means nobody has looked yet, and a
-- reader that read nil as "cannot read" answered "empty" for every slot on
-- every bar: the only caller that asked was Bars.Describe, so the squares came
-- up blank at login and filled in the moment you typed /wk. A guard that gives
-- the same answer for "no" and "not yet" is a guard that lies once per session,
-- silently, at the worst moment.
--
-- The cost on the tick is a call and a comparison per read, which is what the
-- guard was already doing plus the call. Nothing here allocates, and check.sh's
-- HOT list still holds every one of them to that.
local probe

-- The three that say something about a slot beyond whether a press would land.
-- Resolved to locals rather than looked up per button per tick, and
-- deliberately not in NEEDED: a client missing one of these loses a tint or a
-- ring, and a client missing anything in NEEDED loses the bar. Those are not
-- the same loss and must not share a switch.
--
-- None of the three is called by anything installed on this machine, which is
-- the bar the rest of the file is held to, so none is assumed.
local isCurrent, isRepeating, isEquipped

-- The two that say which spell a press would cast. Same tier as the three
-- above and for the same reason: a client missing either loses the two rungs
-- that know more than the client does, and keeps the bar.
--
-- GetMacroSpell is the one that was never asked for. GetActionInfo alone says
-- "macro" and stops there, which is where the honest answer used to end, and it
-- ends there on five of the twelve keys the warrior plan writes.
local readAction, macroSpell

-- Whether what is in a slot is aimed at an enemy. Same tier again: a client
-- without it loses the one rung that knows about the target with nothing
-- selected, and keeps the bar. Blizzard's own 2.5.6 API documentation lists it
-- under C_ActionBar with the loose name beside it, and nothing installed on
-- this machine calls either, so both are looked for.
local isHarmful

function Slot.CanRead()
	if probe == nil then
		probe = true
		for _, name in ipairs(NEEDED) do
			if type(_G[name]) ~= "function" then
				probe = name .. " is missing on this client"
				break
			end
		end
		isCurrent = type(IsCurrentAction) == "function" and IsCurrentAction or nil
		isRepeating = type(IsAutoRepeatAction) == "function" and IsAutoRepeatAction or nil
		isEquipped = type(IsEquippedAction) == "function" and IsEquippedAction or nil
		readAction = type(GetActionInfo) == "function" and GetActionInfo or nil
		macroSpell = type(GetMacroSpell) == "function" and GetMacroSpell or nil
		if C_ActionBar and type(C_ActionBar.IsHarmfulAction) == "function" then
			isHarmful = C_ActionBar.IsHarmfulAction
		elseif type(IsHarmfulAction) == "function" then
			isHarmful = IsHarmfulAction
		end
	end
	if probe ~= true then
		return false, probe
	end
	return true
end

-- Whether this client can be asked which spell is in a slot at all, and the
-- reason when it cannot. Its own answer rather than folded into CanRead,
-- because the two losses are not the same size: without this the bar still
-- draws every square and only the two rungs that outrank the client go quiet.
--
-- Buttons/Reaction.lua asks this once at login instead of probing GetActionInfo
-- for itself, so there is one answer to the question rather than two that can
-- disagree.
function Slot.CanName()
	local can, why = Slot.CanRead()
	if not can then
		return false, why
	end
	if not readAction then
		return false, "GetActionInfo is missing on this client, so no square can be told from another"
	end
	return true
end

-- Which spell a press on this slot would cast, in the client's own name for it,
-- plus whether the slot got there through a macro.
--
-- The macro half is the whole reason this exists. GetActionInfo answers "spell"
-- for a plain spell and "macro" for a macro, and every part of this addon that
-- wanted to know what a square held stopped at the second answer. The warrior
-- plan puts five of its twelve bar 1 keys in macros, so the gates that outrank
-- the client had a hole in them exactly where the loadout put things: an
-- Overpower in a macro drew ready all fight, and a Shield Bash in one drew
-- pressable with no shield on.
--
-- GetMacroSpell resolves a macro's conditionals to the spell the client would
-- actually cast, which is what draws the cooldown and the tooltip on Blizzard's
-- own macro buttons. Its return shape differs across clients, so all three are
-- read and the first thing that names a spell wins rather than a fixed index.
--
-- Never held against the slot. What a macro resolves to changes with the
-- cursor and with the target, so a memo keyed on the macro would be wrong
-- between one tick and the next; ns.SpellNameHeld holds the only part that is
-- stable, which is what a spell id is called.
function Slot.Spell(slot)
	if not slot or not Slot.CanName() then
		return nil, false
	end
	local kind, id = readAction(slot)
	if kind == "spell" then
		return ns.SpellNameHeld(id), false
	end
	if kind ~= "macro" or not macroSpell then
		return nil, false
	end
	local first, _, third = macroSpell(id)
	if type(first) == "string" then
		return first, true
	end
	if type(first) == "number" then
		return ns.SpellNameHeld(first), true
	end
	if type(third) == "number" then
		return ns.SpellNameHeld(third), true
	end
	return nil, true
end

--------------------------------------------------------------------------
-- The ladder
--------------------------------------------------------------------------

-- What art the slot is holding, or nil for an empty one. Split out because the
-- texture changes when the loadout changes and the status changes ten times a
-- second, and the caller guards the two separately.
function Slot.Texture(slot)
	if not slot or not Slot.CanRead() then
		return nil
	end
	return GetActionTexture(slot)
end

-- How many of it there are: charges on an ability, or the stack on an item.
-- Returns nil rather than 1 for the ordinary case, so the caller can guard on
-- nil and never draw a "1" over an icon that only ever had one.
function Slot.Count(slot)
	if not slot or not Slot.CanRead() or type(GetActionCount) ~= "function" then
		return nil
	end
	local count = GetActionCount(slot)
	if type(count) ~= "number" or count < 2 then
		return nil
	end
	return count
end

-- Whether there is nothing live and attackable selected. The one definition of
-- "nothing to aim at" in the addon: Aimed below reads it for every square and
-- Buttons/Requires.lua reads it in front of every threshold, because a
-- threshold read off no unit is not a fact. Two copies of three unit calls is
-- how the two drift, and the drift would be silent.
function Slot.Aimless()
	return not UnitExists(RANGE_UNIT) or UnitIsDead(RANGE_UNIT)
		or not UnitCanAttack("player", RANGE_UNIT)
end

-- The rung the client's own bar does not have.
--
-- IsUsableAction knows about your resources, your stance, your cooldowns and
-- what you are wearing, and nothing about the target. Blizzard's own button
-- colours the icon off that call alone, so a Flame Shock in an inn with
-- nothing selected draws white on their bar and drew ready on this one. The
-- range rung could not catch it, because with nothing targeted there is no
-- distance to be out of and it skips itself, and the condition rung only
-- speaks for the spells a class file names. Every other attack on the bar fell
-- through to ready.
--
-- The fact the client does hold is whether the slot is aimed at an enemy, and
-- an attack with nothing to attack is a press that does nothing. A spell that
-- is not harmful is left alone on purpose: a heal or a shield with nothing
-- selected lands on you under the self cast setting, and a totem has no target
-- at all, so for both of those the press does something and the square stays
-- ready.
--
-- Asked of the spell where a macro is what is in the slot, for the reason
-- Refused below asks ns.SpellUsable there, and of the slot for everything
-- else. A macro that resolves to no spell falls back to the slot, which is the
-- honest answer for a /startattack with no /cast in it. Both are read against
-- the target, as range is: a mouseover macro hovered over a mob with nothing
-- targeted is the one press this reads wrong, and it reads it grey rather
-- than lit.
local function Aimed(slot, spell, macro)
	local harmful
	if macro and spell then
		harmful = ns.SpellHarmful(spell)
	elseif isHarmful then
		harmful = isHarmful(slot)
	end
	if harmful and Slot.Aimless() then
		return "notarget"
	end
	return nil
end

-- The two rungs that know more than the client does, as one question, or nil
-- when neither has anything to say. Most of the bar is nil in two table
-- lookups.
--
-- Overpower and Revenge are not spells you press, they are spells the fight
-- hands you, and the client will not say so. IsUsableAction answers yes for
-- Overpower in Battle Stance whether or not anything has dodged you, so without
-- this the square said "ready" for the whole of every fight. Execute is the
-- same defect read off the target instead of out of the log: usable from full
-- health down, and castable for the last fifth of a fight.
-- Buttons/Reaction.lua and Buttons/Requires.lua own the two mechanisms; this
-- asks each of them one question.
--
-- Above the usable split rather than below it, and that is the ladder's own
-- rule rather than a preference: what cannot be fixed at all comes first. A
-- shut window is not something you can do anything about, and neither is a mob
-- at half health, and a wrong stance is. Putting them here also fixes the one
-- square on a warrior's bar that shouted all fight for nothing. Overpower
-- sitting in Defensive Stance used to draw orange "swap" from the first pull to
-- the last, which is a colour saying "swap and press this" over a press that
-- would not land. Now the orange appears on the two or three seconds where
-- swapping really would let you press it, and the rest of the time the square
-- is quiet.
--
-- The order between the two is arbitrary today, because no ability a class file
-- names is both a reactive and a condition. Written in the order the harness
-- already drives.
local function Beyond(spell)
	local reactive = ns.Reaction.OfSpell(spell)
	if reactive and not ns.Reaction.Open(reactive) then
		return "reaction"
	end
	return ns.Requires.State(spell)
end

-- The client's own answer, as a status or nil for a press that would land.
--
-- Two returns from the client, and the second is the whole reason this is not a
-- boolean. It says no for a spell you cannot afford and for one you cannot cast
-- in this stance, and on a warrior those are the two states a bar spends its
-- life in. Collapsing them loses the only distinction worth drawing.
--
-- It is also the whole of the stance rule for the two reactive abilities.
-- Overpower is Battle Stance only and Revenge is Defensive Stance only, and the
-- client already refuses both in the wrong stance with a "not enough power" of
-- false, which is exactly the shape this splits on. Nothing above had to learn
-- about stances.
--
-- Asked of the spell rather than of the slot where a macro is what is in it.
-- IsUsableAction on a macro slot does not answer for the spell the macro would
-- cast, which is how a Shield Bash behind `#showtooltip` drew pressable with no
-- shield on. ns.SpellUsable is the same question at the level the client will
-- answer it, returning the same pair in the same order, and Charge/Charge.lua
-- has been asking it that way all along.
local function Refused(slot, spell, macro)
	local usable, noPower
	if macro and spell then
		usable, noPower = ns.SpellUsable(spell)
	else
		usable, noPower = IsUsableAction(slot)
	end
	if usable then
		return nil
	end
	return noPower and "cost" or "stance"
end

-- Returns a status from UI/Ability.lua's vocabulary, plus the cooldown start
-- and duration when there is one.
function Slot.State(slot)
	if not slot or not Slot.CanRead() then
		return "empty"
	end
	if not HasAction(slot) then
		return "empty"
	end

	-- An empty slot answered above, so a slot with no art is one the client
	-- has not resolved yet rather than one with nothing in it.
	if not GetActionTexture(slot) then
		return "unknown"
	end

	local start, duration, enabled = GetActionCooldown(slot)
	local running = enabled and enabled ~= 0 and duration and duration > 0
		and start and start > 0
	if running and duration > GCD then
		return "cooldown", start, duration
	end
	-- A global. Not a status, so the ladder carries on and whatever it decides
	-- is returned with the swipe's two numbers stapled on. Nil when nothing is
	-- running, which is what UI/Ability.lua reads as "clear the swipe".
	local swipeStart, swipeDuration
	if running then
		swipeStart, swipeDuration = start, duration
	end

	-- Resolved once and handed to both of the rungs that want it, because
	-- reading it is a client call and each rung used to make its own. A macro
	-- resolves through here too, which is the whole of the fix for a plan that
	-- puts five of its twelve keys in macros.
	local spell, macro = Slot.Spell(slot)

	-- Above the two rungs that outrank the client, and that is the ladder's
	-- own rule once more: a shut window or a threshold read off no unit is not
	-- a fact, and Requires.lua already refuses to read one. Nothing selected is
	-- also the one state on the bar a single click fixes, so it is the first
	-- thing worth saying.
	local aimed = Aimed(slot, spell, macro)
	if aimed then
		return aimed, swipeStart, swipeDuration
	end

	local beyond = Beyond(spell)
	if beyond then
		return beyond, swipeStart, swipeDuration
	end

	local refused = Refused(slot, spell, macro)
	if refused then
		return refused, swipeStart, swipeDuration
	end

	-- Asked only when there is something to be at a distance from. Without
	-- that guard the check answers nil on every button on every tick you are
	-- standing around untargeted, and ns.OutOfRange counts nils towards the
	-- once-a-session warning that this client answers no range checks at all.
	-- Twenty-four buttons would reach the fortieth nil in under a second and
	-- print a sentence about a client fault that is not one.
	--
	-- ns.OutOfRange owns what a nil answer means past that point.
	-- Charge/Charge.lua asks the identical question of a spell and a unit, and
	-- reaches it only with a unit it has already checked exists.
	if UnitExists(RANGE_UNIT) and ns.OutOfRange(IsActionInRange(slot, RANGE_UNIT)) then
		return "range", swipeStart, swipeDuration
	end

	return "ready", swipeStart, swipeDuration
end

-- Whether a press would be asking for something already happening: the stance
-- you are standing in, the auto attack already swinging, a shout already up.
--
-- Its own answer rather than a tenth status, because it is not a rung on the
-- ladder and does not compete with one. The active stance is also "ready", and
-- on a warrior the active stance is the single most useful thing a bar can say
-- at a glance, so it has to be drawable on top of whatever the ladder decided.
--
-- Auto attack is folded in with the current action rather than flashed. The
-- client flashes it, which is twenty years of habit and also the reason people
-- install addons that stop it. A steady tint says the same thing and does not
-- pull the eye off the fight.
function Slot.Active(slot)
	if not slot or not Slot.CanRead() then
		return false
	end
	if isCurrent and isCurrent(slot) then
		return true
	end
	if isRepeating and isRepeating(slot) then
		return true
	end
	return false
end

-- Whether the slot holds an item you are wearing or wielding. Blizzard draws a
-- green border for this and it is worth keeping: an item slot on a bar is a
-- trinket or a weapon swap, and whether the swap has already happened is the
-- one thing the icon alone cannot tell you.
--
-- Its own answer for the same reason Slot.Active is. Being equipped is not a
-- reason a press does or does not land, so it cannot be a rung, and an equipped
-- weapon can be on cooldown and out of range at the same time.
function Slot.Equipped(slot)
	if not slot or not Slot.CanRead() or not isEquipped then
		return false
	end
	return isEquipped(slot) and true or false
end

function Slot.Describe()
	local can, why = Slot.CanRead()
	if not can then
		return "unreadable: " .. why
	end
	return "readable"
end
