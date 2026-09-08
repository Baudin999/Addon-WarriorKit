local ADDON, ns = ...

local UI = ns.UI

--------------------------------------------------------------------------
-- What a tooltip says
--
-- UI/Tooltip.lua is a box that draws a list of lines. This is the part that
-- decides which lines, and it is the part other files hook into.
--
-- **A hover names a subject, not a tooltip.** A caller says what is under the
-- cursor, which is a table like `{ kind = "item", link = link }` or
-- `{ kind = "note", title = "Loot", lines = { ... } }`, and this file works out
-- what the whole addon has to say about it. Before this every caller assembled
-- its own box, and the result was seventeen hovers with seventeen shapes: some
-- put air before the hint line and some did not, some coloured the title and
-- some left it gold, four of them raised Blizzard's parchment instead. None of
-- that was a decision anybody made. It was a decision nobody owned.
--
-- **Three bands, always in this order.**
--
--   head   the name of the thing. The client's own text where the client has
--          any, the caller's title where it has none.
--   body   the facts the caller knows and the client does not.
--   extra  what everything else in the addon has to say about it.
--
-- There was a fourth, and cutting it is the point of the shape rather than a
-- loss to it. `hint` was one blue line at the bottom of every box in the addon
-- naming the switch that turns the thing off or the slash word that prints the
-- rest, and by the time twenty five call sites had one it was furniture. A
-- sentence you have read four hundred times is not read at all, it is a line of
-- the fight you are covering, and on a box that follows the pointer round the
-- world it is on screen the whole evening. What a hover is for is the thing
-- under the cursor. Where the settings are is what the settings window is for,
-- and `/wk help` prints every word.
--
-- Air goes between two bands that both have something in them, and nowhere
-- else. That single rule is most of what "consistent" means here, and it is
-- worth more than any amount of care at the call sites, because the call sites
-- are written months apart by somebody reading a different file.
--
-- **Anything can hook into the extra band.** A part calls Tip.Source once, at
-- load, saying which kind of subject it has something to say about and where
-- the line goes. The auction price on a loot row was the first of these and it
-- used to be four lines inside Feeds/Loot.lua, which meant an item hovered
-- anywhere else in the addon did not get it. It is a source now, so a mail
-- attachment and a chat link get the same line for free. That is the whole
-- reason this file exists rather than a Build function inside the box.
--
-- **A source may not draw and may not decide the shape.** It answers an array
-- of line specs or nothing at all, the same value a caller's own `lines` is.
-- Nothing registered here can title a tooltip, open one, reorder a band or
-- suppress another source. The extension point is deliberately narrow: a part
-- that could rewrite the whole box is a part that can put the addon back where
-- it was.
--
-- **And one thing does not fit in a band at all.** Shift held over a piece of
-- gear puts what you are wearing beside what you are pointing at, and that is a
-- second description of a second object rather than a line about this one. So
-- it is a second hook with a different shape: Tip.SetCompare takes a function
-- that answers subjects, each of which is built by Tip.Build the same as any
-- other, and UI/Tooltip.lua draws them in boxes of their own. See Beside below
-- and Character/Compare.lua, which is the only part that hands one in.
--------------------------------------------------------------------------

local Tip = {}
ns.Tip = Tip

-- Which of UI/Scan.lua's kinds a subject reads with, and which of its own
-- fields the arguments come from.
--
-- A kind absent from this table has no text inside the client, which is `note`
-- and is the addon's own furniture: a filter chip, a settings control. Those
-- draw the caller's title and nothing else in the head band, which is correct
-- and is not a fallback.
--
-- `talent` is a square on the talent window. Its two fields are whatever the
-- client's setter wants on this build, which Talents/Read.lua settles once
-- and UI/Scan.lua's entry for the kind explains.
--
-- `spell` is what a subject the client knows but nobody is carrying reads with,
-- and it is here for the nag row. A square that says a buff is missing was the
-- one hover in the addon whose head was a phrase this addon wrote, because
-- there is no aura index for an aura you do not have; with an id there is a
-- question to ask and the box reads like every other one.
local READS = {
	item      = { "link" },
	action    = { "slot" },
	spell     = { "spell" },
	buff      = { "unit", "index" },
	debuff    = { "unit", "index" },
	inventory = { "unit", "slot" },
	unit      = { "unit" },
	talent    = { "tab", "index" },
}

-- Every kind a subject may name. `note` is here and not above because it is a
-- real kind that a source can register against; it simply has no client text.
local KINDS = {
	note = true, item = true, action = true, spell = true,
	buff = true, debuff = true, inventory = true, unit = true,
	talent = true,
}

-- The bands a source may write into, and the order they are drawn in. `head` is
-- not on this list on purpose: the name of the thing is the caller's and the
-- client's, and a source that could retitle a tooltip is a source that can make
-- one hover disagree with the next.
local BANDS = { "body", "extra" }

local function IsBand(name)
	for index = 1, #BANDS do
		if BANDS[index] == name then
			return true
		end
	end
	return false
end

local sources = {}
local taken = {}

-- The subset of the above that declared a stamp, kept as its own list rather
-- than found by walking `sources` every tick. UI/Fresh.lua reads it a few times
-- a second for as long as a box is on screen, and most sources have no stamp:
-- walking the whole list to skip four of them is a cost paid on the tick to
-- save four table reads at load.
local stamped = {}

-- What the hover that is up was opened with, so a key going down can redraw it.
-- See Tip.Again.
local open

-- What a subject is worth putting a second box beside, handed in by the part
-- that knows.
--
-- **This is a hand-in and not a source, and the difference is the whole shape
-- of the thing.** A source adds a line to the box. This adds a box: shift held
-- over a helmet in your bags puts the helmet you are wearing next to it, and
-- over a ring it puts both of the rings you are wearing. Nothing about that
-- fits in the extra band. It is a second description of a second thing.
--
-- It is one function rather than a list for the reason UI/Tooltip.lua takes one
-- anchor frame rather than a list: there is one answer to "what would this
-- replace", it belongs to whichever part of the addon knows about worn gear,
-- and two parts both answering would put two boxes up that disagree.
--
-- And it is handed in rather than reached for, which is the rule this whole
-- folder is held to. What goes beside a tooltip depends on what you can wear,
-- what you have on and which key is down, and none of those three is something
-- a drawing layer is allowed to know. Character/Compare.lua knows all three and
-- pushes the answer in, the same way Settings/Settings.lua pushes in where the
-- box goes.
local compare

-- Handed the subject, answers an array of subjects to draw beside it, or
-- nothing at all. Answered as whether anything is hooked up, which is the shape
-- UI.Tooltip.SetAnchor has.
function Tip.SetCompare(fn)
	compare = type(fn) == "function" and fn or nil
	return compare ~= nil
end

--------------------------------------------------------------------------
-- Registering
--------------------------------------------------------------------------

-- One part's standing offer to say something about a kind of thing.
--
--   name   what it is, for the assert below and for Describe
--   kind   the subject kind it answers about, or "*" for every kind
--   band   body or extra
--   order  where it sits inside that band, low first
--   fill   handed the subject, answers an array of line specs or nothing
--
-- The order is unique inside a band and the assert says which two collided,
-- because two sources at the same number are drawn in whatever order the TOC
-- happens to load them in, and a line that moves when an unrelated file is
-- added to the TOC is the kind of defect nobody ever tracks down.
function Tip.Source(source)
	assert(type(source) == "table" and type(source.name) == "string",
		"a tooltip source must be a table with a name")
	assert(source.kind == "*" or KINDS[source.kind],
		("%s registered for %s, which is not a subject kind")
			:format(source.name, tostring(source.kind)))
	assert(IsBand(source.band),
		("%s registered for the band %s, and the bands are %s")
			:format(source.name, tostring(source.band), table.concat(BANDS, ", ")))
	assert(type(source.order) == "number",
		("%s registered no order, and an order decides where its line lands")
			:format(source.name))
	assert(type(source.fill) == "function",
		("%s registered no fill, so it can never say anything"):format(source.name))
	-- Optional, and the only optional field on a source. A line that cannot
	-- change while you look at it needs none, which is most of them; a line
	-- carrying a figure that moves declares what makes it move, and UI/Fresh.lua
	-- reads that rather than rebuilding the box to find out. What a stamp is
	-- worth and why it is floored is written in that file's header.
	assert(source.stamp == nil or type(source.stamp) == "function",
		("%s registered a stamp that is not a function, and a stamp is read on a tick")
			:format(source.name))

	local key = source.band .. ":" .. source.order
	assert(not taken[key],
		("%s and %s both registered order %d in the %s band")
			:format(source.name, tostring(taken[key]), source.order, source.band))
	taken[key] = source.name

	sources[#sources + 1] = source
	table.sort(sources, function(a, b)
		return a.order < b.order
	end)
	if source.stamp then
		stamped[#stamped + 1] = source
	end
	return source
end

-- Every source that declared a stamp, handed out rather than copied because
-- UI/Fresh.lua walks it on a tick and a copy per pass is the allocation this
-- whole mechanism exists to avoid. Nothing else reads it, and nothing may
-- write it.
function Tip.Stamped()
	return stamped
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

-- Every line spec a caller or a source handed over, onto the end of a band.
--
-- A source that answers a single spec rather than an array is taken as meaning
-- one line, because `{ "Vendor", "12g" }` is a line and `{ { "Vendor", "12g" } }`
-- is a list holding one, and the two are one bracket apart at every call site.
-- The test is whether the first entry is itself a table.
local function Pour(band, lines)
	if type(lines) ~= "table" then
		return band
	end
	-- An empty table is a source that had nothing to say and said so with a
	-- constructor rather than a nil. Poured as a spec it would draw a blank
	-- line, which is the one thing a source is not allowed to do.
	if lines[1] == nil and lines.blank == nil then
		return band
	end
	if type(lines[1]) ~= "table" then
		band[#band + 1] = lines
		return band
	end
	for index = 1, #lines do
		band[#band + 1] = lines[index]
	end
	return band
end

-- What every registered source has to say about this subject, in order.
local function FromSources(subject, want, band)
	for index = 1, #sources do
		local source = sources[index]
		if source.band == want and (source.kind == "*" or source.kind == subject.kind) then
			Pour(band, source.fill(subject))
		end
	end
	return band
end

-- The client's own lines for the subject, or nil where there are none.
--
-- An item subject that also names the bag and slot it is lying in is read from
-- there rather than from its link, and it is the same item either way. The
-- difference is what the client can see: handed a link it knows only what the
-- item does to whoever picks it up, so a soulbound sword in your own bag comes
-- back saying "Binds when picked up" forever. Handed the slot it is in, it says
-- "Soulbound", because from there the binding is a fact it can check.
--
-- The kind stays `item`, which is the point of doing it here and not with a
-- kind of its own. Every source registered for items -- the vendor price, the
-- auction value -- says the same thing about a stack in your bags as it does
-- about the same stack on a loot row, and a `bag` kind would have quietly cost
-- the bags all of them.
--
-- The link is the fallback and not a lesser answer. A square whose bag and slot
-- have gone stale between the hover and the read, and a client with no
-- SetBagItem on it, both land there and get the text every other item hover in
-- the addon gets.
local function Head(subject)
	if subject.kind == "item" and subject.bag and subject.slot then
		local lines = UI.Scan.Read("bag", subject.bag, subject.slot)
		if lines then
			return lines
		end
	end
	local read = READS[subject.kind]
	if not read then
		return nil
	end
	return UI.Scan.Read(subject.kind, subject[read[1]], read[2] and subject[read[2]])
end

-- The whole tooltip, as the table UI/Tooltip.lua draws.
--
-- Nil for a subject with nothing in any band. That is the honest answer to a
-- row whose entry has gone and to a nag square with nothing to nag about, and
-- without it the last hover's sentence stays on screen pointing at this one.
function Tip.Build(subject)
	if type(subject) ~= "table" or not KINDS[subject.kind] then
		return nil
	end

	local data = { scan = Head(subject), title = subject.title, color = subject.color }

	local filled = {
		body = FromSources(subject, "body", Pour({}, subject.lines)),
		extra = FromSources(subject, "extra", {}),
	}

	-- Air between two bands that both have something in them, and nowhere else.
	--
	-- The head is not in the loop, so nothing is ever spaced off the title. It
	-- already has a hairline under it and the air either side of that, and a
	-- spacer on top of the rule reads as two separators doing one job. The loot
	-- feed used to write that spacer by hand and the cooldown row did not, which
	-- is the sort of thing nobody notices until the two boxes are on screen one
	-- after the other.
	local first = true
	for _, name in ipairs(BANDS) do
		local band = filled[name]
		if #band > 0 then
			if not first then
				data[#data + 1] = { blank = true }
			end
			for index = 1, #band do
				data[#data + 1] = band[index]
			end
			first = false
		end
	end

	if #data < 1 and not data.scan and not data.title then
		return nil
	end
	return data
end

-- The finished descriptions of whatever goes beside this subject, or nil.
--
-- Each one is built by Tip.Build, so a compare box is the same three bands in
-- the same order with the same air between them as the box it sits next to, and
-- every source that had something to say about the hovered item says it about
-- the worn one too. That is the whole reason the comparison is a subject rather
-- than a run of lines: a vendor price on the item under the cursor and none on
-- the item you are wearing would be two boxes that do not read as a pair.
--
-- A subject in the list that builds to nothing is dropped rather than passed
-- on. UI/Tooltip.lua would skip it anyway; dropping it here means the count the
-- box reports is the count of boxes and not of attempts.
local function Beside(subject)
	if not compare then
		return nil
	end
	local wanted = compare(subject)
	if type(wanted) ~= "table" or #wanted < 1 then
		return nil
	end

	local built
	for index = 1, #wanted do
		local data = Tip.Build(wanted[index])
		if data then
			built = built or {}
			built[#built + 1] = data
		end
	end
	return built
end

--------------------------------------------------------------------------
-- Putting one up
--------------------------------------------------------------------------

-- The kinds an item arriving late can change, and whether the box that is up
-- came out thin enough to be worth rebuilding when one does.
--
-- **The client does not always know what an item is at the moment you hover
-- it.** An item is a number until the server has sent its data, and until then
-- every setter in UI/Scan.lua answers about it with nothing at all or with the
-- one line that says so. There is no way to ask the client to hurry and no way
-- to tell from the answer that a better one is coming. The event is the only
-- notice there is, and until this existed nothing in the addon was listening
-- for it on behalf of a box already on screen: the head band was scanned once,
-- at the moment the pointer arrived, and a hover held through the fetch showed
-- whatever had been true a tenth of a second too early.
--
-- That is a tooltip with a name and no stats, and it is a tooltip with nothing
-- in it at all where the caller had no title of its own to fall back on. Both
-- are the same defect and this is the half that fixes it. UI/Fresh.lua's header
-- says the head band has no stamp until somebody can say which call makes it
-- stale; this is that call, and it is an event rather than a stamp, which is
-- why it is here rather than there.
--
-- **Thin, rather than a comparison against the id that arrived.** An `item`
-- subject carries a link and the id could be read out of it, but an `inventory`
-- subject carries a slot and there is no id in a slot without another call, so
-- half the hovers on the character sheet could not be matched at all. What is
-- worth having instead is the state: a box whose head is thin is rebuilt when
-- any item lands, and it stops being rebuilt the moment its own does, because
-- the head is no longer thin. A box that already reads properly ignores the
-- event outright, which is every hover in an evening bar the few seconds after
-- one lands on something the client has never seen.
local FETCHED = { item = true, inventory = true }

-- What the client publishes in place of an item it has not fetched yet. Read
-- through _G because a client that does not carry it is a client where the
-- first test below is the whole answer, and a missing global is not an error.
local function Retrieving()
	local text = _G.RETRIEVING_ITEM_INFO
	return type(text) == "string" and text or nil
end

-- The link the item behind a subject is asked about with.
--
-- An `item` carries one. An `inventory` is a worn slot and carries none, so it
-- is asked for: a trinket you press has a Use line the same as a book does, and
-- the character sheet is nineteen hovers that all read a slot.
local function Carried(subject)
	if type(subject.link) == "string" then
		return subject.link
	end
	if subject.kind ~= "inventory" then
		return nil
	end
	local lookup = _G.GetInventoryItemLink
	if type(lookup) ~= "function" then
		return nil
	end
	local asked, link = pcall(lookup, subject.unit, subject.slot)
	return asked and link or nil
end

local function Thin(subject, data)
	if not FETCHED[subject.kind] then
		return false
	end
	if not data or not data.scan or not data.scan[1] then
		return true
	end
	local waiting = Retrieving()
	if waiting ~= nil and data.scan[1][1] == waiting then
		return true
	end
	-- And the box that is complete except for the one line the item is for. A
	-- Use line is the spell's own sentence and the client fetches that
	-- separately, so a tooltip carrying the name, the level and the requirement
	-- can still be a tooltip that has not finished. UI/Scan.lua's Waiting is
	-- both halves of it: whether one is coming, and the ask that makes it come.
	return UI.Scan.Waiting(Carried(subject))
end

-- Open on an owner, describing a subject.
--
-- `above` opens the box over the owner rather than beside it, which is what
-- anything smaller than the cursor has to ask for. It is an argument as well as
-- a field on the subject because a caller with a fixed answer says it once at
-- the call site, and a caller whose answer depends on what it is describing
-- says it on the subject.
--
-- `place` is where the box goes, for a hover that is not willing to take the
-- setting's answer. An icon standing for an object is the whole of that list:
-- the box is that object's label and it belongs on it. Same two ways of saying
-- it as `above`, and for the same reason.
function Tip.Open(owner, subject, above, place)
	if type(subject) ~= "table" then
		open = nil
		UI.Fresh.Stop()
		return UI.Tooltip.Show(owner, nil)
	end
	-- Built here rather than inside the call below, because two things have to
	-- read it before it is drawn: the arm underneath and the thinness test that
	-- decides whether a late arriving item is worth rebuilding for.
	local data = Tip.Build(subject)
	-- Held so a modifier pressed while the box is already up can redraw it, and
	-- so a client that answers about this thing a second later can. See
	-- Tip.Again and Tip.Arrived below, which are the two readers.
	open = { owner = owner, subject = subject, above = above, place = place,
		thin = Thin(subject, data) }
	-- After the box is built and before it is handed over, and armed on the
	-- subject rather than on the box: a rebuild comes back through here with the
	-- same subject table and must not read as a new hover. UI/Fresh.lua's Arm
	-- says what happens if it does.
	UI.Fresh.Arm(subject)
	return UI.Tooltip.Show(owner, data, above or subject.above,
		place or subject.place, Beside(subject))
end

-- The same hover again, from nothing but a key going down.
--
-- **This is what makes shift comparison work at all.** A comparison is not a
-- fact about the item, it is a fact about what you are holding down, and that
-- changes while the box is on screen and the pointer has not moved. There is no
-- second OnEnter coming, so whoever watches the key asks for the box again and
-- it is rebuilt from the subject the hover named.
--
-- False where no hover is live, which is most of the time and is why the
-- watcher may call this on every press without asking first.
--
-- **A live hover is `open` and not a box on screen**, and the two are different
-- in the one case this has to serve. A hover whose client text had not arrived
-- yet drew no box at all, because a subject with nothing in any band is refused
-- rather than drawn empty, and that is precisely the box a late arriving item
-- has to be able to put up. Reading IsShown here meant the boxes that most
-- needed rebuilding were the ones that could not be. `open` is cleared by
-- Tip.Close, so it says what the pointer is on rather than what is drawn.
function Tip.Again()
	if not open then
		return false
	end
	local held = open
	Tip.Open(held.owner, held.subject, held.above, held.place)
	return true
end

-- The client fetched an item, and the box on screen may have been waiting for
-- it.
--
-- Answered as whether the box was built again, which is false on nearly every
-- event: no hover is live, or the one that is already reads properly. See the
-- Thin comment above for why the id that arrived is not compared against the
-- one in the box.
--
-- Public because scripts/harness drives it. There is no other caller: the
-- registration below is the whole of the wiring.
function Tip.Arrived()
	if not open or not open.thin then
		return false
	end
	return Tip.Again()
end

-- Registered through pcall for the reason every client call in this addon is:
-- the event is not on every flavour this addon loads on, and a client that
-- refuses it is a client where a hover held through a fetch shows what it
-- showed before this file existed rather than an error.
--
-- Two events and one handler, because there are two fetches and a box waiting
-- on either is in the same state. The item is the first: a link is a number
-- until the server has sent what it stands for. The spell behind its Use line
-- is the second and it is fetched separately, so a book whose item arrived long
-- ago is still a box with the line it exists for missing. See Thin above and
-- UI/Scan.lua's Waiting.
local fetched = CreateFrame("Frame")
local listening = pcall(fetched.RegisterEvent, fetched, "GET_ITEM_INFO_RECEIVED")
if pcall(fetched.RegisterEvent, fetched, "SPELL_DATA_LOAD_RESULT") then
	listening = true
end
if listening then
	fetched:SetScript("OnEvent", Tip.Arrived)
end

--------------------------------------------------------------------------
-- Waiting for the pointer to hold still
--
-- A grid of a hundred squares is crossed on the way to the one you want, and
-- a box that opens over every square on the path is a box flickering its way
-- across the window. So a caller that hangs over a grid asks for the box only
-- once the pointer has stopped. Tip.Settle arms a wait, the tick below reads
-- the pointer every frame while one is armed, a move past DRIFT pixels starts
-- the wait again from where the pointer is now, and the box opens on the frame
-- the wait runs out. Leaving the owner cancels it, through Tip.Close, and a
-- wait of nought is Tip.Open.
--
-- A box already up on the same owner is redrawn on the spot rather than taken
-- through the wait again. The client's own bag template refreshes a square's
-- box by calling its OnEnter while the pointer has not moved, and the one
-- thing this must never do is take down a box you were reading to make you
-- wait for the same one.
--
-- The wait is the caller's number and not this file's. How long a pointer has
-- to hold still is a fact about the window it is over, a bag has a setting for
-- it, and this layer may not know the name of a setting.
--
-- Nothing is allocated on the tick. The one pending hover is a table filled in
-- at the arm and read at the open, and the pointer is two numbers.
--------------------------------------------------------------------------

-- How far the pointer may wander, in physical pixels, and still count as
-- holding still. Two is a hand resting on a mouse; three is a hand moving it.
local DRIFT = 2

-- How long the hand holds on a piece of chrome before it gets a box.
--
-- The client's own tooltip describes a thing you act on: an item, a spell, a
-- unit. It has never described a tab, a close mark, a filter chip or the hint
-- under a settings row, and this addon does, which is right where the words
-- are worth having and wrong where a pointer on its way somewhere else crosses
-- three of them and opens three boxes. So the furniture waits for the hand to
-- stop and a thing waits for nothing. This is the number the furniture waits,
-- and it is one number rather than four so that every bit of chrome in the
-- addon answers a held pointer at the same moment.
--
-- It was 0.4, which is long enough to feel like the addon thinking about it.
-- Four tenths of a second is roughly a deliberate pause, and what the number
-- has to be instead is the shortest gap that reads as a hand stopping rather
-- than a hand passing through: a pointer crossing a row of chips on its way
-- somewhere else is over each of them for a few dozen milliseconds, and one
-- that has arrived is over one of them for good. 0.15 clears the first and is
-- under what anybody reports as a delay.
Tip.HOLD = 0.15

-- What the wait will open, filled in at the arm.
local pending = { owner = nil, subject = nil, above = nil, place = nil }

-- How long the caller asked for, how long the pointer has held so far, and
-- where it was when the count last started. A wait of nought means nothing is
-- armed, which is the ordinary state.
local wait, still = 0, 0
local heldX, heldY = 0, 0

-- What the wait runs on. Hidden whenever nothing is armed, for the reason
-- UI/Tooltip.lua hides its linger: a tick that answers "no" sixty times a
-- second for a whole evening is the shape of every addon that costs a frame.
local settle = CreateFrame("Frame")
settle:Hide()

local function Cancel()
	if wait <= 0 then
		return false
	end
	wait, still = 0, 0
	settle:Hide()
	return true
end

-- The pointer left. The box counts itself down rather than going at once; see
-- UI/Tooltip.lua for why and for what `now` is. A wait that had not run out
-- goes with it: the thing it was waiting to describe is no longer under the
-- pointer.
function Tip.Close(now)
	open = nil
	Cancel()
	-- The box lingers and the refresh does not. What is on screen for the next
	-- second is a description of something you have already looked away from,
	-- and keeping a figure inside it moving would be the addon paying to correct
	-- a sentence nobody is reading any more.
	UI.Fresh.Stop()
	return UI.Tooltip.Close(now)
end

-- Where the pointer is, in physical pixels, or nothing on a client that will
-- not say. Read here rather than through UI/Tooltip.lua's own reading because
-- that one is a local of that file and this is a different question: not
-- where to put the box, but whether the hand has stopped.
local function Pointer()
	if type(GetCursorPosition) ~= "function" then
		return nil, nil
	end
	return GetCursorPosition()
end

-- The frame the wait ran out on. Its own function and marked cold so the walk
-- from the tick stops here: Tip.Open builds the box, which is a hover's worth
-- of allocation, and it runs once per hover rather than once per frame.
-- cold: Land opens the box once, on the frame the wait ran out, and hides the tick with it
local function Land()
	wait, still = 0, 0
	settle:Hide()
	Tip.Open(pending.owner, pending.subject, pending.above, pending.place)
end

-- Open on an owner once the pointer has held still on it for `seconds`.
--
-- The same four arguments as Tip.Open and the wait after them. Nought, or a
-- subject with nothing in it, is the plain open: nothing to wait for and
-- nothing to wait with. So is a box already up on this owner, for the reason
-- the header gives, and so is a client that will not say where the pointer is,
-- because a wait that cannot see the hand stop is a box that never opens.
--
-- Answers what Tip.Open answers when it opened on the spot, and false while
-- the wait is running.
function Tip.Settle(owner, subject, above, place, seconds)
	seconds = tonumber(seconds) or 0
	if type(subject) ~= "table" or seconds <= 0 then
		Cancel()
		return Tip.Open(owner, subject, above, place)
	end
	if UI.Tooltip.IsShown() and UI.Tooltip.Owner() == owner then
		Cancel()
		return Tip.Open(owner, subject, above, place)
	end
	local x, y = Pointer()
	if not x or not y then
		Cancel()
		return Tip.Open(owner, subject, above, place)
	end
	pending.owner, pending.subject = owner, subject
	pending.above, pending.place = above, place
	wait, still = seconds, 0
	heldX, heldY = x, y
	settle:Show()
	return false
end

-- One frame of the wait. The pointer is read, a move past DRIFT starts the
-- count again from where it is now, and a count that reaches the wait opens
-- the box. True on the frame it opened.
function Tip.Settling(elapsed)
	if wait <= 0 then
		return false
	end
	local x, y = Pointer()
	if x and y and (math.abs(x - heldX) > DRIFT or math.abs(y - heldY) > DRIFT) then
		heldX, heldY, still = x, y, 0
		return false
	end
	still = still + (tonumber(elapsed) or 0)
	if still < wait then
		return false
	end
	Land()
	return true
end

UI.Ticker(settle, 0, "settle", Tip.Settling)

-- What is left of the wait, for scripts/harness.lua. Nought when nothing is
-- armed, which is both "opened" and "never asked": the two are told apart by
-- UI.Tooltip.IsShown, the way the linger's reading is.
function Tip.Waiting()
	if wait <= 0 then
		return 0
	end
	return wait - still
end

--------------------------------------------------------------------------
-- Hanging one on a frame
--
-- A mouse enabled frame swallows every button that lands on it, and the right
-- button drag that turns the camera is one of those. Everything in this addon
-- you can hover sits over the middle of the screen, which is exactly where that
-- drag starts, so a tooltip bought at the price of a camera that will not turn
-- is a bad trade made silently.
--
-- There are two shapes of this and the client answers only one of them.
--
-- **A frame that answers a click and wants the other buttons back** is
-- UI.PassCamera, and SetPassThroughButtons is the only call that does it. That
-- one arrived in 10.1.5 and this client is 2.5.6: nothing on disk calls it
-- outside a retail path, and Questie's map library stubs it to a no-op for a
-- retail bug. So it is probed, and on the live client the probe fails and a
-- right drag begun on such a frame still stops there. Those frames are buttons
-- inside windows and none of them is large.
--
-- **A frame whose whole answer is the hover** is UI.HoverOnly, and that one the
-- client does have. Motion and clicks are separate flags: turn the clicks off
-- and every button that lands on the frame falls through to the world, while
-- OnEnter and OnLeave still fire. SetMouseClickEnabled arrived in 9.0 and was
-- backported; OPie ships `## Interface: 20506` and calls it unguarded on a
-- slider thumb it hangs OnEnter on, which is the same frame in the same shape.
--
-- The difference is worth the two functions because the character sheet is the
-- size of the monitor. Nineteen gear rows, four readings and a column of stats
-- answer nothing but the hover, and passed through SetPassThroughButtons alone
-- they were most of a screen the camera would not turn in.
--------------------------------------------------------------------------

function UI.PassCamera(owner)
	if type(owner.SetPassThroughButtons) ~= "function" then
		return false
	end
	return pcall(owner.SetPassThroughButtons, owner, "RightButton", "MiddleButton")
end

-- The mouse for the hover and nothing else. EnableMouse first because that is
-- what turns motion on, then the clicks off, because a frame with no clicks and
-- no motion is a frame with no mouse at all.
--
-- Falls back to handing the camera its two buttons where the client has no
-- click flag, which is the most a caller could have asked for before this
-- existed.
function UI.HoverOnly(owner)
	owner:EnableMouse(true)
	if type(owner.SetMouseClickEnabled) == "function"
		and pcall(owner.SetMouseClickEnabled, owner, false) then
		return true
	end
	return UI.PassCamera(owner)
end

-- The convenience for the ordinary case: a frame whose whole answer to the
-- mouse is a tooltip. `describe` is handed the frame and answers a subject, or
-- nothing at all for a frame with nothing to say.
--
-- A caller that also wants to paint on the way in and out, which every row in a
-- feed does, hangs its own scripts and calls Tip.Open and Tip.Close from inside
-- them, and calls UI.PassCamera itself.
function Tip.Hang(owner, describe)
	owner:SetScript("OnEnter", function(self)
		Tip.Open(self, describe(self))
	end)
	owner:SetScript("OnLeave", function()
		Tip.Close()
	end)
	UI.PassCamera(owner)
	return owner
end

-- How many parts have hooked something in, for the panel. It reads as a count
-- rather than a list because the list is the source code and the count is the
-- thing a player can check against what they can see.
function Tip.Describe()
	local total = #sources
	if total < 1 then
		return "nothing is hooked into the tooltips"
	end
	if total == 1 then
		return ("one part adds a line to what a hover says, and it is %s")
			:format(sources[1].name)
	end
	return ("%d parts add lines to what a hover says"):format(total)
end

-- Every source's name, in the order they are drawn. Handed out because "the
-- auction line comes after the vendor line" is a claim scripts/harness.lua has
-- to be able to make, and there is no answering it from the outside otherwise.
function Tip.Sources()
	local names = {}
	for index = 1, #sources do
		names[index] = sources[index].name
	end
	return names
end
