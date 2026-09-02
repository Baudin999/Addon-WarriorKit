local ADDON, ns = ...

local Cost = {}
ns.TalentCost = Cost

local Read = ns.TalentRead

--------------------------------------------------------------------------
-- What unlearning costs
--
-- No call on either client answers this. The price is decided on the server
-- and it reaches the client exactly once: when you ask your trainer to unlearn
-- your talents, the client fires CONFIRM_TALENT_WIPE with the price in copper
-- and puts up its own dialog with the figure in it. That is the only true
-- number there is, so this file catches it, writes it down for this
-- character with the day it was quoted, and the window reads it back.
--
-- **The schedule is well known and is not a fact the client hands over.** The
-- first reset is one gold, the second five, and each after that five more up
-- to fifty, and the figure comes back down over the months you leave it. So
-- the window says two things and keeps them apart: the price the trainer last
-- quoted, which is a fact with a date on it, and what the schedule says the
-- next one will be, which is an estimate and is worded as one. A window that
-- printed the estimate as a price would be wrong on the day the decay had
-- taken five gold off, which is the day you most wanted to know.
--
-- **A quote is not a wipe.** The dialog can be cancelled, and most of the
-- time it is: it is the cheapest way to read the price. So the count of
-- resets this character has paid for moves only when a quote is followed by
-- every tree emptying, which is what the client says with the same event it
-- says everything else about your talents with.
--
-- Per character, because the price is. Two characters on one account have
-- two histories with their trainers and the account-wide table would make one
-- of them lie about the other.
--------------------------------------------------------------------------

-- The schedule, in copper. One gold for the first, then five, ten, fifteen and
-- so on to fifty.
local FIRST = 10000
local STEP = 50000
local CAP = 500000

-- Whether a quote is standing. Set when the trainer's dialog goes up and
-- cleared when the trees empty or the next talent event arrives with points
-- still in them, which is the dialog having been cancelled.
local armed = false

-- The points in every tree the last time anybody looked, so a wipe can be told
-- from a character who never had any.
local spent = 0

local function Ledger()
	return ns.dbc
end

--------------------------------------------------------------------------

-- The trainer's dialog went up with a price in it. Written down whether or not
-- the player goes through with it: the quote is the fact, and the wipe is
-- counted separately below.
function Cost.Quoted(copper)
	local db = Ledger()
	if not db or not tonumber(copper) then
		return false
	end
	db.respecQuote = math.floor(tonumber(copper))
	db.respecQuoteAt = time()
	armed = true
	spent = Read.Spent()
	return true
end

-- The talents changed. Three things can be true: a quote was standing and the
-- trees are now empty, which is a reset paid for; a quote was standing and
-- they are not, which is a dialog cancelled; or nothing was standing, which is
-- a point being spent and none of this file's business.
function Cost.Changed()
	local now = Read.Spent()
	if armed then
		local db = Ledger()
		if now == 0 and spent > 0 and db then
			db.respecCount = (tonumber(db.respecCount) or 0) + 1
			armed = false
		elseif now > 0 then
			armed = false
		end
	end
	spent = now
	return armed
end

-- What the schedule says the next reset costs, off how many this character
-- has paid for. An estimate, and the caller words it as one.
function Cost.Next()
	local db = Ledger()
	local count = db and tonumber(db.respecCount) or 0
	if count < 1 then
		return FIRST
	end
	return math.min(CAP, STEP * count)
end

function Cost.Count()
	local db = Ledger()
	return db and tonumber(db.respecCount) or 0
end

-- The last quote and when, or nil for a character whose trainer has never been
-- asked.
function Cost.Quote()
	local db = Ledger()
	if not db or not tonumber(db.respecQuote) then
		return nil
	end
	return db.respecQuote, db.respecQuoteAt
end

-- The day a quote was given, worded for a sentence. The clock is the one the
-- harness freezes and the loot feed reads, so a date here is the same date
-- there.
local function Day(when)
	if type(when) ~= "number" then
		return "some time ago"
	end
	local text = date("%d %b", when)
	return type(text) == "string" and text:gsub("^0", "") or "some time ago"
end

-- One sentence for the foot of the window and for the panel.
function Cost.Describe()
	local quote, when = Cost.Quote()
	local coming = ns.Coin(Cost.Next())
	if quote then
		return ("your trainer quoted %s on %s to unlearn everything; the schedule says about %s next time, and less if you leave it a while")
			:format(ns.Coin(quote), Day(when), coming)
	end
	return ("unlearning everything costs about %s by the schedule; ask your trainer for the exact price, the dialog can be cancelled")
		:format(coming)
end

-- The same two facts in a few words, for a reading on the panel, which never
-- wraps.
function Cost.Brief()
	local quote, when = Cost.Quote()
	if quote then
		return ("%s quoted on %s"):format(ns.Coin(quote), Day(when))
	end
	return ("about %s, never quoted"):format(ns.Coin(Cost.Next()))
end

--------------------------------------------------------------------------
-- Events
--
-- Both registrations are pcalled: the older client fires CHARACTER_POINTS_CHANGED
-- and the newer fires PLAYER_TALENT_UPDATE as well, and registering an event a
-- client has never heard of raises rather than being ignored.
--------------------------------------------------------------------------

local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "CONFIRM_TALENT_WIPE")
pcall(events.RegisterEvent, events, "PLAYER_TALENT_UPDATE")
pcall(events.RegisterEvent, events, "CHARACTER_POINTS_CHANGED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, first)
	if event == "CONFIRM_TALENT_WIPE" then
		Cost.Quoted(first)
	elseif event == "PLAYER_LOGIN" then
		spent = Read.Spent()
	else
		Cost.Changed()
	end
end)
