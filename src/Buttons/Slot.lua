local ADDON, ns = ...

local Slot = {}
ns.Slot = Slot

--------------------------------------------------------------------------
-- What one action slot is doing
--
-- The same eight answers Charge/Charge.lua works out for the three charge
-- abilities, worked out for an action slot instead. Both hand their answer to
-- UI/Ability.lua, which draws it, and neither knows the other exists.
--
-- Why two sources and not one. A charge display asks "would a press put this
-- ability on that mob", where the mob is picked by camera or by cursor and the
-- ability is picked by combat state, so the whole question is resolved in Lua
-- before any slot is involved. A bar button asks "would a press do what is in
-- this slot", where the slot is whatever the loadout wrote and the client owns
-- every part of the answer. The ladders look alike because the eight answers
-- are the same eight; the inputs have nothing in common.
--
-- What they do share is the order, and the order is the design. What cannot be
-- fixed at all comes first, then what a stance swap or a few seconds of rage
-- fixes, then range. Reversing any two of those makes the square say the less
-- useful of two true things: a spell you have no rage for and are also out of
-- range of is a spell to walk towards, and one you are out of range of and
-- cannot cast in this stance is a spell to swap for.
--
-- Everything here runs on the bar's ticker against every button on it, so
-- nothing allocates and nothing is cached that the client already holds.
-- check.sh's HOT list covers Slot.State, Slot.Active and Slot.Equipped.
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
	end
	if probe ~= true then
		return false, probe
	end
	return true
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

	-- Two returns, and the second is the whole reason this is not a boolean.
	-- IsUsableAction says no for a spell you cannot afford and for one you
	-- cannot cast in this stance, and on a warrior those are the two states a
	-- bar spends its life in. Collapsing them loses the only distinction worth
	-- drawing.
	local usable, noPower = IsUsableAction(slot)
	if not usable then
		return noPower and "cost" or "stance", swipeStart, swipeDuration
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
