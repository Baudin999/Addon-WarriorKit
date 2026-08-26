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
-- check.sh's HOT list covers Slot.State.
--------------------------------------------------------------------------

-- Below this a cooldown is the global and not the ability's own. Drawing a
-- swipe for the global turns the whole bar into a strobe on every press, which
-- is what every action bar addon suppresses and why the number is here.
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

local probe -- nil until asked, then true or a reason string

function Slot.CanRead()
	if probe == nil then
		probe = true
		for _, name in ipairs(NEEDED) do
			if type(_G[name]) ~= "function" then
				probe = name .. " is missing on this client"
				break
			end
		end
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
	if not slot or probe ~= true then
		return nil
	end
	return GetActionTexture(slot)
end

-- How many of it there are: charges on an ability, or the stack on an item.
-- Returns nil rather than 1 for the ordinary case, so the caller can guard on
-- nil and never draw a "1" over an icon that only ever had one.
function Slot.Count(slot)
	if not slot or probe ~= true or type(GetActionCount) ~= "function" then
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
	if not slot or probe ~= true then
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
	if enabled and enabled ~= 0 and duration and duration > GCD and start and start > 0 then
		return "cooldown", start, duration
	end

	-- Two returns, and the second is the whole reason this is not a boolean.
	-- IsUsableAction says no for a spell you cannot afford and for one you
	-- cannot cast in this stance, and on a warrior those are the two states a
	-- bar spends its life in. Collapsing them loses the only distinction worth
	-- drawing.
	local usable, noPower = IsUsableAction(slot)
	if not usable then
		return noPower and "cost" or "stance"
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
		return "range"
	end

	return "ready"
end

function Slot.Describe()
	local can, why = Slot.CanRead()
	if not can then
		return "unreadable: " .. why
	end
	return "readable"
end
