local ADDON, ns = ...

local Stance = {}
ns.Stance = Stance

--------------------------------------------------------------------------
-- The three stances
--
-- Which spell each one is, what it is called in this client's language, and
-- which one you are standing in. Three numbers and two questions, and they are
-- here rather than in a part because two parts ask them now. The charge button
-- swaps stance on the way to Charge, Intervene and Intercept; the stance keys
-- are the whole of what they do. Held in one place so the two cannot disagree
-- about what stance 2 is called.
--
-- The index is the number the `stance:` macro conditional counts in, so the
-- order of SPELLS is the order the generated macros are written against.
--------------------------------------------------------------------------

Stance.SPELLS = { 2457, 71, 2458 } -- 1 Battle, 2 Defensive, 3 Berserker
Stance.COUNT = #Stance.SPELLS

local names = {}
local epoch = 0

-- Resolved lazily and never cached as nil, so a name the client has not handed
-- over yet is asked for again rather than latched empty. Spell names are not
-- reliably available while files load, and a stance name baked into a macro as
-- the empty string is a macro line that casts nothing.
function Stance.Name(index)
	if not names[index] then
		names[index] = ns.SpellName(Stance.SPELLS[index])
	end
	return names[index]
end

-- Nil when the client will not say. Callers that need a verdict fall back to
-- IsUsableSpell rather than guessing, which is what Charge.State does.
function Stance.Current()
	if GetShapeshiftForm then
		return GetShapeshiftForm()
	end
	return nil
end

-- A number that moves when a name handed out above might have. Anything that
-- bakes a stance name into a macro compares this rather than the built string,
-- because building the string is the cost the comparison exists to avoid.
function Stance.Epoch()
	return epoch
end

-- A new rank changes nothing here. A locale reload changes every name.
local events = CreateFrame("Frame")
events:RegisterEvent("SPELLS_CHANGED")
events:SetScript("OnEvent", function()
	wipe(names)
	epoch = epoch + 1
end)
