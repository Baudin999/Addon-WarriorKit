local ADDON, ns = ...

local Stack = {}
ns.BagsStack = Stack

--------------------------------------------------------------------------
-- Putting the loose piles together
--
-- Twelve cloth in one slot and eighteen in another is two slots holding one
-- stack's worth. This walks the five bags, finds two partial stacks of the same
-- item, and drags one onto the other until there is at most one partial left
-- per item. Twelve and eighteen come out twenty and ten, which is the whole of
-- what it promises: a free slot where there were two half-full ones.
--
-- **It is not a sort.** Nothing is moved to a different pile, nothing is put in
-- a different bag, and the order of what you carry is the order you picked it
-- up in. Bags/Bags.lua already groups what you own into piles for the window to
-- draw, so a real sort would be the addon rearranging bags it has no other
-- reason to touch. Combining stacks is the one move that is only ever an
-- improvement: it frees slots and it loses nothing.
--
-- **The move is Blizzard's own, twice.** Picking up a stack and dropping it on
-- another of the same item is what the client does when you do it with the
-- mouse, and the split is theirs too: drop twelve onto eighteen and the target
-- fills to twenty and the remaining ten stays on the cursor, which ClearCursor
-- puts back where it came from. Nothing here calls SplitContainerItem and
-- nothing here decides how many to move. Baganator's Sorting/CombineStacks.lua
-- is the same two calls in the same order and its comment says the same thing.
--
-- **A pass cannot see the result of its own work.** A pickup locks both slots
-- and the server clears them a moment later, so the sweep is a ticker: read the
-- bags, merge every pair it can, wait, read again. It stops on the first pass
-- that finds nothing to merge and nothing still locked, which is also what
-- catches a move the server dropped on the floor.
--
-- The bank is not here, for the reason Bags/Bags.lua gives at its own bag
-- numbers: five bags is what you are carrying.
--------------------------------------------------------------------------

-- The backpack and the four on the belt.
local FIRST_BAG, LAST_BAG = 0, 4

-- A fifth of a second a pass, which is Comfort/Vendor.lua's interval and for
-- the same reason: it is how long the server takes to unlock a slot it has
-- moved something out of.
local INTERVAL = 0.2

-- Five seconds of trying. Longer than any bagful takes and short enough that a
-- slot the server never unlocks does not leave a ticker running forever.
local MAX_PASSES = 25

local frame
local running = false
local passes, merged = 0, 0
local ticker

-- Whether a sweep has ever run this session, which is the difference between
-- "nothing has been stacked" and "the last run found nothing to stack". They
-- read the same off the count alone, because a run resets it.
local ran = false

-- The partial stacks the last read found, pooled the way Bags/Bags.lua pools
-- its entries and for the same reason: this walks a hundred and fifty slots
-- every fifth of a second while it is running, and a table per slot would be
-- garbage the collector walks in the middle of a frame.
--
-- Entries past `held` are stale and are never read. Every field of an entry
-- inside it is written on every read, because the entry handed back is the one
-- some other slot used on the last pass.
local partials = {}
local held = 0

--------------------------------------------------------------------------

-- Every partial stack in the five bags, into the pool, and how many slots this
-- pass could not judge.
--
-- The second number is what keeps the sweep alive. A slot locked from this
-- sweep's own move will read differently once the server has finished with it,
-- and an item the client has not cached has no stack size yet, so both mean
-- "look again" rather than "nothing here". Stopping on either is how the third
-- stack of an item gets left behind while the first two are still in flight.
--
-- A full stack is not a partial and neither is something that does not stack,
-- so both are skipped rather than pooled. That is what keeps the walk below
-- over the handful of slots that can move rather than over everything you own.
local function Read()
	local used, waiting = 0, 0
	for bag = FIRST_BAG, LAST_BAG do
		for slot = 1, ns.ContainerSlots(bag) do
			local link = ns.ContainerItemLink(bag, slot)
			local id, size = link and ns.ItemKind(link), link and ns.ItemStack(link)
			local count, locked = ns.ContainerItem(bag, slot)
			if link and (id == nil or size == nil or locked) then
				waiting = waiting + 1
			elseif link and size > 1 and count and count < size then
				used = used + 1
				local entry = partials[used]
				if not entry then
					entry = {}
					partials[used] = entry
				end
				entry.bag, entry.slot, entry.id, entry.taken = bag, slot, id, false
			end
		end
	end
	held = used
	return used, waiting
end

-- One drag, from the later slot onto the earlier one.
--
-- That direction rather than the other because it is the one that reads right
-- afterwards: the full stack ends up nearer the front of your bags and whatever
-- would not fit drifts to the back. The client decides how much moves, and
-- ClearCursor puts the remainder back in the slot it came from.
--
-- Both slots are locked by this and neither is looked at again on this pass,
-- which is what `taken` is for. The next pass reads them off the client.
local function Drag(target, source)
	if not ns.PickupContainerItem(source.bag, source.slot) then
		return false
	end
	ns.PickupContainerItem(target.bag, target.slot)
	ClearCursor()
	target.taken, source.taken = true, true
	return true
end

-- Every pair of partials of one item that this pass can reach.
--
-- Each merge either fills the target or empties the source, so the number of
-- partial stacks of that item goes down by one every time and the sweep cannot
-- circle. Pairs of different items are all done in the same pass, because
-- nothing one move touches is anything another move reads.
local function Pair()
	local moves = 0
	for first = 1, held - 1 do
		local target = partials[first]
		if not target.taken then
			for second = first + 1, held do
				local source = partials[second]
				if not source.taken and source.id == target.id and Drag(target, source) then
					moves = moves + 1
					break
				end
			end
		end
	end
	return moves
end

local function Tick()
	passes = passes + 1

	-- A cursor with something on it is a drag the player started, and a pickup
	-- now would drop it somewhere they did not ask for. Waiting is the right
	-- answer rather than stopping: they are mid-drag, not done.
	if GetCursorInfo() then
		if passes >= MAX_PASSES then
			Stack.Stop()
		end
		return
	end

	local _, waiting = Read()
	local moves = Pair()
	merged = merged + moves
	if (moves == 0 and waiting == 0) or passes >= MAX_PASSES then
		Stack.Stop()
	end
end

--------------------------------------------------------------------------
-- Starting and stopping
--------------------------------------------------------------------------

function Stack.Stop()
	if not running then
		return false
	end
	running = false
	if ticker then
		ticker:Stop()
	end
	-- A sentence either way, because every sweep is a press somebody made and a
	-- press that says nothing reads as a button that does nothing. This is the
	-- one place the addon speaks about stacking, so the nothing-to-do case is
	-- the answer to "did that work", not noise.
	if merged > 0 then
		ns.Print(("combined %d stack%s."):format(merged, merged == 1 and "" or "s"))
	else
		ns.Print("nothing in your bags is worth putting together.")
	end
	return true
end

-- The sweep, because something asked for it. False and a reason where it cannot
-- start, because a press is something a player is waiting for an answer to.
function Stack.Run()
	if running then
		return false, "your bags are already being stacked"
	end
	if GetCursorInfo() then
		return false, "your cursor is holding something"
	end
	if not frame then
		frame = CreateFrame("Frame")
	end
	running, ran = true, true
	passes, merged = 0, 0
	if ticker then
		ticker:Start()
	else
		ticker = ns.UI.Ticker(frame, INTERVAL, "bagstack", Tick)
	end
	return true
end

-- The same sweep with the refusal said out loud, which is what a press wants.
-- The button in the window's footer and the press on the settings page both
-- come here, so the sentence a refused press prints is written once and the two
-- of them cannot drift into saying different things about the same refusal.
function Stack.Press()
	local going, why = Stack.Run()
	if not going then
		ns.Print(why .. ".")
	end
	return going
end

-- Whether a sweep is in flight, so the panel and the window say something true
-- while the ticker is running rather than only afterwards.
function Stack.Running()
	return running
end

function Stack.Describe()
	if running then
		return ("stacking, %d combined so far"):format(merged)
	end
	if not ran then
		return "idle, nothing has been stacked this session"
	end
	if merged == 0 then
		return "idle, the last run found nothing to put together"
	end
	return ("idle, the last run combined %d stack%s")
		:format(merged, merged == 1 and "" or "s")
end
