local ADDON, ns = ...

local Stance = {}
ns.Stance = Stance

--------------------------------------------------------------------------
-- The forms you can stand in
--
-- Which spell each one is, what it is called in this client's language, and
-- which one you are standing in. Two parts ask: the charge button swaps stance
-- on the way to Charge, Intervene and Intercept, and the loadouts page offers
-- one per stance to bind a weapon set to. Held in one place so the two cannot
-- disagree about what stance 2 is called.
--
-- Which forms exist is a fact about your class and lives in Class\<yours>.lua
-- as `forms`. The index is the number the `stance:` macro conditional counts
-- in, so the order that file writes them in is the order the generated macros
-- are written against. A class with no forms answers zero here and both callers
-- fall away: the charge macro is not built at all on that class, and the
-- loadouts page offers a weapon set with no stance on it, which is a thing it
-- already supports.
--
-- Nothing here is read at load. The class is not reliably known while the files
-- load, so a form list taken then would be empty for the session.
--------------------------------------------------------------------------

local names = {}
local epoch = 0

local function Spells()
	return ns.Class.Of("forms")
end

function Stance.Count()
	local spells = Spells()
	return spells and #spells or 0
end

-- Resolved lazily and never cached as nil, so a name the client has not handed
-- over yet is asked for again rather than latched empty. Spell names are not
-- reliably available while files load, and a stance name baked into a macro as
-- the empty string is a macro line that casts nothing.
function Stance.Name(index)
	if not names[index] then
		local spells = Spells()
		local spell = spells and spells[index]
		names[index] = spell and ns.SpellName(spell)
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
