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

	local key = source.band .. ":" .. source.order
	assert(not taken[key],
		("%s and %s both registered order %d in the %s band")
			:format(source.name, tostring(taken[key]), source.order, source.band))
	taken[key] = source.name

	sources[#sources + 1] = source
	table.sort(sources, function(a, b)
		return a.order < b.order
	end)
	return source
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
		return UI.Tooltip.Show(owner, nil)
	end
	-- Held so a modifier pressed while the box is already up can redraw it. See
	-- Tip.Again below, which is the only reader.
	open = { owner = owner, subject = subject, above = above, place = place }
	return UI.Tooltip.Show(owner, Tip.Build(subject), above or subject.above,
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
-- False where nothing is up, which is most of the time and is why the watcher
-- may call this on every press without asking first.
function Tip.Again()
	if not open or not UI.Tooltip.IsShown() then
		return false
	end
	local held = open
	Tip.Open(held.owner, held.subject, held.above, held.place)
	return true
end

-- The pointer left. The box counts itself down rather than going at once; see
-- UI/Tooltip.lua for why and for what `now` is.
function Tip.Close(now)
	open = nil
	return UI.Tooltip.Close(now)
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
-- SetPassThroughButtons hands the two the camera wants back. It arrived in
-- 1.14.4 and 10.0 and neither target client is proven to carry it, so it is
-- probed and then pcalled rather than trusted: a name that exists while
-- refusing these arguments would raise once per hoverable frame at login.
--
-- Where the client has neither, a right drag begun on one of these frames does
-- not turn the camera. That is the real price of every tooltip in the addon and
-- it is worth saying out loud rather than discovering. It was written once in
-- Buffs/Nag.lua for the four squares of a nag row; a feed of four hundred rows
-- is the same trap at forty times the area, which is what moved it here.
--------------------------------------------------------------------------

function UI.PassCamera(owner)
	if type(owner.SetPassThroughButtons) ~= "function" then
		return false
	end
	return pcall(owner.SetPassThroughButtons, owner, "RightButton", "MiddleButton")
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
