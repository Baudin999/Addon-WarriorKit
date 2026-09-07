-- The rank refresh
--
-- Two claims, and the file is in service of them.
--
-- A spell you carry one rank of moves to the best rank you have trained, in
-- every slot it sits in, and nothing else in the bar moves with it. Macros,
-- items, empty slots and a spell already at the top are all left where they
-- are, and so is a rank the trainer has not sold you: 19-spellbook.lua carries
-- Battle Shout rank 3 as a FUTURESPELL, so the top of that name is rank 2 and
-- a file reading the greyed entry would say rank 3 and put a spell on the bar
-- that cannot be cast.
--
-- A spell you carry two ranks of does not move at all, either rank of it. That
-- is the whole of the downranking rule and it has to be silent rather than
-- refused: the count the panel prints comes off the same list the button
-- writes from, so a frozen spell must not be offered as something to fix.
--
-- The write goes through ns.CarrySpell, which is the part that was wrong and
-- could not be seen. This client's PickupSpell takes an id and raises on a
-- name, which is one of the two shapes the call has, so the file used to call
-- it straight and worked here while doing nothing on the other kind of client.
-- The name half of that shim is driven below on its own, because Buttons/
-- Layout.lua reaches it with spell names and nothing else in the suite does.

local H = ...
local ns, check, fire = H.ns, H.check, H.fire

local Ranks = ns.Ranks
local slots = _G.WarriorKitSlots

-- 19-spellbook.lua's book, by hand, because the point of the file is what the
-- reader makes of that book and a section that asked the book would be asking
-- the answer.
local REND_1, REND_3 = 772, 6547
local SHOUT_1, SHOUT_2, SHOUT_3 = 6673, 5242, 6192

----------------------------------------------------------------------
-- The scene
--
-- Every slot emptied and handed back at the foot of the file. Sections above
-- leave spells in slots, and a walk over all 120 of them would count those as
-- well: what this file says about a bar has to be about the bar it laid out.
----------------------------------------------------------------------

local held = {}
for slot, entry in pairs(slots) do
	held[slot] = entry
end
for slot in pairs(held) do
	slots[slot] = nil
end
Ranks.Forget()

local function put(slot, spell)
	slots[slot] = { spell = spell }
	Ranks.Forget()
end

-- What is in a slot, as an id, or nothing at all.
local function spellIn(slot)
	local kind, id = _G.GetActionInfo(slot)
	return kind == "spell" and id or nil
end

local function staleAt(slot)
	for _, entry in ipairs(Ranks.Stale()) do
		if entry.slot == slot then
			return entry
		end
	end
	return nil
end

----------------------------------------------------------------------
-- The client can do it
--
-- Both halves, because they are two questions and the file used to be refused
-- on the first. Reading the book needs no cursor and no quiet moment; writing
-- a slot needs both, and Layout holds that half.
----------------------------------------------------------------------

local can, why = Ranks.CanApply()
check(can, ("the rank refresh is refused on this client: %s"):format(tostring(why)))
check(#Ranks.Stale() == 0,
	("an empty bar has %d slots holding an older rank"):format(#Ranks.Stale()))
check(Ranks.Describe():find("best rank", 1, true) ~= nil,
	("an empty bar reads as %q"):format(Ranks.Describe()))

----------------------------------------------------------------------
-- One rank on the bars, in two places
--
-- Rend rank 1 twice and Battle Shout rank 1 once, with a macro and an item
-- between them. Twice is the case that decides whether the rule counts ranks
-- or counts slots: the same rank in two slots is a warrior's stance pages, not
-- a decision about mana, and counting slots would freeze it.
----------------------------------------------------------------------

put(1, REND_1)
put(2, SHOUT_1)
slots[3] = { macro = 7 }
slots[4] = { item = 6948 }
put(5, REND_1)

local stale = Ranks.Stale()
check(#stale == 3,
	("three slots are behind and the walk found %d"):format(#stale))
check(stale[1].slot == 1 and stale[2].slot == 2 and stale[3].slot == 5,
	("the stale list is not in slot order: %d, %d, %d")
		:format(stale[1].slot, stale[2].slot, stale[3].slot))
check(staleAt(1).to == REND_3,
	("rend rank 1 is to be moved to %d and the top rank is %d")
		:format(staleAt(1).to, REND_3))
check(staleAt(5).to == REND_3, "the second slot holding rend rank 1 is going somewhere else")

-- The greyed rank. Battle Shout rank 3 is a FUTURESPELL in the book, so the
-- best rank of that name is rank 2 and not rank 3.
check(staleAt(2).to == SHOUT_2,
	("battle shout is to be moved to %d, and rank 2 is %d with the greyed rank at %d")
		:format(staleAt(2).to, SHOUT_2, SHOUT_3))

check(Ranks.Describe():find("3 slots", 1, true) ~= nil,
	("three slots behind reads as %q"):format(Ranks.Describe()))

----------------------------------------------------------------------
-- The write
----------------------------------------------------------------------

local ok, report = Ranks.Apply()
check(ok, ("the refresh refused with %s"):format(tostring(report)))
check(report.moved == 3 and #report.failed == 0,
	("the refresh moved %d slots and failed on %d")
		:format(report.moved, #report.failed))

check(spellIn(1) == REND_3 and spellIn(5) == REND_3,
	("rend came out as %s and %s")
		:format(tostring(spellIn(1)), tostring(spellIn(5))))
check(spellIn(2) == SHOUT_2,
	("battle shout came out as %s"):format(tostring(spellIn(2))))

-- Everything that is not a plain spell, untouched.
check(select(2, _G.GetActionInfo(3)) == 7, "the macro in slot 3 was rewritten")
check(select(2, _G.GetActionInfo(4)) == 6948, "the item in slot 4 was rewritten")
check(_G.GetCursorInfo() == nil, "the refresh left the old rank on the cursor")

check(#Ranks.Stale() == 0,
	("the bar is still %d slots behind after a refresh"):format(#Ranks.Stale()))

----------------------------------------------------------------------
-- Two ranks on the bars
--
-- The rule. Rend at rank 1 and rank 3 together is a player keeping a cheap
-- rank beside the big one, so neither slot moves and neither is counted.
-- Battle Shout beside it is left at rank 1 to prove the freeze is per name
-- rather than a switch over the whole bar.
----------------------------------------------------------------------

put(1, REND_1)
put(5, REND_3)
put(2, SHOUT_1)

check(staleAt(1) == nil and staleAt(5) == nil,
	"a spell carried at two ranks was offered as something to fix")
check(staleAt(2) ~= nil,
	"freezing one spell's ranks froze every other spell on the bar as well")
check(#Ranks.Stale() == 1,
	("one slot is behind and the walk found %d"):format(#Ranks.Stale()))

local moved = select(2, Ranks.Apply()).moved
check(moved == 1, ("the refresh moved %d slots and only battle shout was behind"):format(moved))
check(spellIn(1) == REND_1 and spellIn(5) == REND_3,
	("the downranked rend moved: %s and %s")
		:format(tostring(spellIn(1)), tostring(spellIn(5))))

----------------------------------------------------------------------
-- What drops the list
--
-- The count is cached because the panel asks for it on every click. Both
-- events that can make it wrong drop it, and the slot re-read catches the
-- window between a cached list and a write.
----------------------------------------------------------------------

put(1, REND_1)
slots[5] = nil
Ranks.Forget()
check(#Ranks.Stale() == 1, "the bar is not one slot behind before the cache is tested")

-- Cached, then the slot changes underneath without the event. The write has to
-- read the slot again and leave it alone, because the id it was told to
-- replace is no longer the id in the slot.
slots[1] = { spell = SHOUT_1 }
local after = select(2, Ranks.Apply())
check(after.moved == 0,
	("a slot that changed under a cached list was written anyway: %d moved"):format(after.moved))
check(spellIn(1) == SHOUT_1, "the slot that changed underneath was overwritten")

slots[1] = { spell = REND_1 }
fire("ACTIONBAR_SLOT_CHANGED", 1)
check(#Ranks.Stale() == 1, "a slot moving did not drop the cached count")

slots[1] = nil
fire("SPELLS_CHANGED")
check(#Ranks.Stale() == 0, "the spellbook changing did not drop the cached count")

----------------------------------------------------------------------
-- When it will not run
--
-- Neither refusal is a reason the feature is unavailable, so the reading is
-- allowed to carry on counting through both, and the panel's own guard is the
-- pair of them together with a count above zero.
----------------------------------------------------------------------

put(1, REND_1)

do
	local realLockdown = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end

	local fought, refusal = Ranks.Apply()
	check(not fought and refusal == ns.Layout.BUSY_COMBAT,
		("the refresh in combat answered %s"):format(tostring(refusal)))
	check(spellIn(1) == REND_1, "a slot was written in combat")
	check(Ranks.Describe():find("older rank", 1, true) ~= nil,
		("the reading stops counting in combat: %q"):format(Ranks.Describe()))

	_G.InCombatLockdown = realLockdown
end

do
	H.hold({ id = 6948, link = nil })
	local holding, refusal = Ranks.Apply()
	check(not holding and refusal == ns.Layout.BUSY_CURSOR,
		("the refresh with a full cursor answered %s"):format(tostring(refusal)))
	check(spellIn(1) == REND_1, "a slot was written with something already on the cursor")
	_G.ClearCursor()
end

----------------------------------------------------------------------
-- Both spellings of the pickup
--
-- ns.CarrySpell is what the refresh goes through and what makes the file work
-- on a client it was not written against. This one takes an id, so the id goes
-- straight through and the name comes back through GetSpellInfo. Driven here
-- because the name is Buttons/Layout.lua's way in and nothing in the suite
-- composes a loadout.
----------------------------------------------------------------------

check(ns.CarrySpell(REND_3), "an id this client's PickupSpell takes was refused")
check(_G.GetCursorInfo() ~= nil, "a pickup that reported success left the hands empty")
_G.ClearCursor()

check(ns.CarrySpell("Rend"), "a spell name was not turned into an id this client takes")
check(_G.GetCursorInfo() ~= nil, "the name half of the pickup left the hands empty")
_G.ClearCursor()

check(not ns.CarrySpell(900001), "a spell nobody knows was picked up")
check(_G.GetCursorInfo() == nil, "a refused pickup left something on the cursor")

----------------------------------------------------------------------
-- The bar, back the way it was found
----------------------------------------------------------------------

for slot in pairs(slots) do
	slots[slot] = nil
end
for slot, entry in pairs(held) do
	slots[slot] = entry
end
Ranks.Forget()

print(("spell ranks %s; 3 slots moved, 2 ranks of one spell frozen, %s")
	:format(Ranks.Describe(), tostring(select(1, Ranks.CanApply())) == "true"
		and "both pickups" or "one pickup"))
