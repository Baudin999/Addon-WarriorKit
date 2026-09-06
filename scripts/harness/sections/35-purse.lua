-- The purse
--
-- Feeds/Purse.lua is three numbers about money and Feeds/Stream.lua draws them
-- along the bottom of the loot feed. Its own section rather than a corner of
-- 31-feeds.lua, because none of this is about a column of rows: the feed above
-- the strip could be deleted and every question below would still be worth
-- asking.
--
-- Seven of them, and each is a way this has already gone wrong or could.
--
-- Does an unvouched zero stay out of the ledger. This one is not hypothetical
-- and it took two goes. It shipped, and it recorded an alt carrying sixty three
-- gold as carrying nothing; the first fix guessed which moment was answering 0,
-- guessed wrong, and recorded both characters as broke. GetMoney answers 0
-- while the client is still assembling the character, and 0 is a number you can
-- really be holding, so no amount of picking the right event settles it. Only
-- PLAYER_MONEY vouches for a zero, and that is what is asserted.
--
-- Does the strip cost the frame the height it takes. It hangs under the last
-- row and the feed above it has no idea it is there, so a frame sized to the
-- feed alone would draw the strip over the bottom row, which reads as a
-- clipping bug rather than as a missing sum.
--
-- Is the ticker on the strip. It is the only OnUpdate in this part and it beats
-- a second apart forever. The client stops calling OnUpdate on a frame whose
-- parent is hidden, so the strip being a child of the feed is the whole reason
-- a hidden feed costs nothing, and a ticker parented anywhere else would go on
-- beating into a window nobody can see.
--
-- Does the account total mean the account. It is the one number here the client
-- cannot be asked for: every other character's gold is something the addon
-- wrote down, and the two ways to get it wrong are counting this character
-- twice and counting the row it was written down at instead of the money it is
-- holding now. Both look right on a fresh install with one character on it.
--
-- Does the rate refuse to answer while the span is too short. The first coin of
-- a session over four seconds is a true number in the millions, and a status
-- line that prints it once per login is a status line nobody believes again.
--
-- Is the beat guarded. The claim in Feeds/Stream.lua is that a beat with
-- nothing to say writes nothing at all, and the only way to state that as a
-- test rather than as a measurement is to clear a cell by hand and watch a
-- quiet beat leave it cleared.
--
-- And does switching it off give the height back, rather than leaving a band of
-- empty window under the rows.

local H = ...
local ns, check = H.ns, H.check
local state, advance = H.state, H.advance
local frames, events, fire = H.frames, H.events, H.fire

local Purse = ns.Purse
local lootStream = ns.LootFeed.Stream()
local GOLD = 10000

local strip, held, hoard, rate = lootStream:Strip()
check(strip ~= nil, "the loot feed was built with no status strip")

check(strip:GetScript("OnUpdate") ~= nil, "the status strip registered no ticker")

-- On the strip itself, which is what makes a hidden feed free.
check(strip:GetParent() == _G.WarriorKitLootFeed,
	"the strip is not a child of the feed it hangs under")

-- All three cells shadowed, and all three at 14.
--
-- This is the one that got reported by eye, and it took two fixes. The strip
-- looks like it is painted on a surface, and the surface is a slider the player
-- drags to zero, at which point the strip is three numbers over the world. The
-- first fix read that as an argument for a rim and left the size at 12, two
-- under what a rim needs: an outline spends a pixel of every stroke, so the
-- hole in a 6 closed and the waist of an 8 filled in on the one line in the
-- window that is nothing but digits.
--
-- The second took the rim off. A rim is what a string carries when it has no
-- ground, the feed above these three paints its own now, and a shadow holds a
-- digit off whatever is behind it without spending a pixel of the digit. Flat
-- is still the state that loses them completely the moment the background goes,
-- which is why the shadow is asserted rather than assumed.
--
-- Checked here as well as by the grep in scripts/check.sh, because the grep
-- reads the call and this reads the font the client actually ended up with.
for _, entry in ipairs({
	{ "the held cell", held },
	{ "the account cell", hoard },
	{ "the rate cell", rate },
}) do
	local _, size, flags = entry[2]:GetFont()
	flags = flags or ""
	check(flags:find("OUTLINE", 1, true) == nil,
		("%s still carries a rim, which costs a pixel of every stroke")
			:format(entry[1]))
	check(select(1, entry[2]:GetShadowOffset()) ~= 0,
		("%s went flat, and the background under it slides to nothing")
			:format(entry[1]))
	check(size == 14,
		("%s is %s pixels and the strip is 20 to hold 14")
			:format(entry[1], tostring(size)))
end

-- And the ground that lets the rim come off, which is the row of rows getting
-- what the rows got.
--
-- Up the strip rather than along it, and that is the check worth having. A wash
-- running left to right is solid under the held reading and gone by the rate,
-- and one running right to left abandons the held reading instead; both draw a
-- rectangle, measure fine and leave one of the three numbers on the grass. Read
-- back off the texture, because which end is solid is the one thing about a
-- gradient that a call site cannot be asserted for.
do
	local wash = lootStream.statusWash
	check(wash ~= nil, "the strip has no ground under its three readings")
	check(wash.layer == "BACKGROUND",
		("the strip's wash is on %s, so it is over the numbers rather than under them")
			:format(tostring(wash.layer)))
	check(wash.allPoints, "the strip's wash does not cover the strip")

	local ramp = wash:GetGradient()
	check(ramp ~= nil and ramp.orientation == "VERTICAL",
		"the strip's wash runs along it, so it grounds one reading and abandons another")
	check(ramp.min[4] == ns.UI.Color.shadow[4] and ramp.max[4] == 0,
		("the strip washes from %s at its foot to %s at the hairline")
			:format(tostring(ramp.min[4]), tostring(ramp.max[4])))

	-- The same slider as the rows above, so the foot of the window darkens by
	-- as much as the column and the two never read as two surfaces.
	check(wash:GetAlpha() == ns.db.lootFeedAlpha / 100,
		("the strip's ground is at %s and the slider says %d%%")
			:format(tostring(wash:GetAlpha()), ns.db.lootFeedAlpha))
	check(wash:GetAlpha() == lootStream:Feed():Row(1).wash:GetAlpha(),
		"the strip and the rows are painted at different strengths")
end

-- One second of the client, which is one beat of the strip.
local function beat()
	strip:GetScript("OnUpdate")(strip, 1)
end

------------------------------------------------------------
-- Numbers as words
------------------------------------------------------------

check(ns.Coin(0) == "0s 0c", "an empty purse reads " .. ns.Coin(0))
check(ns.Coin(4237) == "42s 37c", "small change reads " .. ns.Coin(4237))
check(ns.Coin(12 * GOLD + 3450) == "12g 34s",
	"a two figure purse reads " .. ns.Coin(12 * GOLD + 3450))
-- Past a hundred gold the silver is dropped, and the thousands are grouped.
-- A five figure purse spends four glyphs on the part that moves when you
-- buy a drink, and 12405 with no commas in it is a number you have to count.
check(ns.Coin(12405 * GOLD + 6300) == "12,405g",
	"a five figure purse reads " .. ns.Coin(12405 * GOLD + 6300))
check(ns.Coin(-(3 * GOLD)) == "-3g 0s",
	"an hour that cost you money reads " .. ns.Coin(-(3 * GOLD)))

-- The coined form is the same rounding in three inks, which is the only claim
-- worth asserting: the escapes are the client's own and there is nothing to
-- test about a hex string, but a coloured reading that disagreed with the plain
-- one would be two formatters again, which is what Core keeps one of.
local function plain(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

check(plain(ns.Coined(12 * GOLD + 3450)) == ns.Coin(12 * GOLD + 3450),
	"the coined purse reads " .. plain(ns.Coined(12 * GOLD + 3450))
		.. " where the plain one reads " .. ns.Coin(12 * GOLD + 3450))
check(ns.Coined(12 * GOLD + 3450) ~= plain(ns.Coined(12 * GOLD + 3450)),
	"the coined purse carries no colour at all")

-- The exact form is what a hover gets: all three denominations, and the two
-- small ones padded so a column of them lines up.
check(plain(ns.Coined(109 * GOLD + 791, true)) == "109g 07s 91c",
	"the exact purse reads " .. plain(ns.Coined(109 * GOLD + 791, true)))
check(plain(ns.Coined(288, true)) == "02s 88c",
	"a purse with no gold in it reads " .. plain(ns.Coined(288, true)))
check(plain(ns.Coined(-(3 * GOLD), true)) == "-3g 00s 00c",
	"an hour that cost you money reads " .. plain(ns.Coined(-(3 * GOLD), true)))

------------------------------------------------------------
-- When the ledger is written
------------------------------------------------------------

local purseFrame
for _, f in ipairs(frames) do
	if f.origin and f.origin:match("Feeds/Purse") then
		purseFrame = f
	end
end
check(purseFrame ~= nil, "Feeds/Purse.lua registered nothing at all")

local function listens(event)
	for _, f in ipairs(events[event] or {}) do
		if f == purseFrame then
			return true
		end
	end
	return false
end

-- The whole of the fix, and the whole of the bug it fixes. At PLAYER_LOGIN this
-- client will tell you your name and will not yet tell you your money, so a
-- ledger written there records every alt as broke and leaves it that way until
-- the day that character next picks up a copper.
check(not listens("PLAYER_LOGIN"),
	"the purse is written at PLAYER_LOGIN, where GetMoney answers 0")
check(listens("PLAYER_ENTERING_WORLD"),
	"the purse is never written at the moment the money becomes real")
check(listens("PLAYER_MONEY"), "a coin picked up does not reach the ledger")
check(listens("PLAYER_LOGOUT"),
	"the last write of a session is missing, so an alt is remembered at its login figure")

------------------------------------------------------------
-- The account
------------------------------------------------------------

state.purse = 130 * GOLD
Purse.Start()
fire("PLAYER_MONEY")

local me = Purse.Mine()
check(me ~= nil, "the addon cannot say whose purse this is")
check(ns.db.purse[me] == 130 * GOLD,
	("this character is written down at %s and is carrying %d")
		:format(tostring(ns.db.purse[me]), 130 * GOLD))

ns.db.purse["Somebody-Elsewhere"] = 40 * GOLD
ns.db.purse["Another-Elsewhere"] = 5 * GOLD + 50 * 100
fire("PLAYER_MONEY")

check(Purse.Account() == 175 * GOLD + 50 * 100,
	("the account holds %s and the three characters hold %d")
		:format(tostring(Purse.Account()), 175 * GOLD + 50 * 100))

-- The live number wins over the row this character was last written down
-- at. Without that the middle cell lags every drop by an event, which is
-- invisible until the two disagree and then reads as gold going missing.
state.purse = 131 * GOLD
check(Purse.Account() == 176 * GOLD + 50 * 100,
	"a coin picked up did not reach the account total")

------------------------------------------------------------
-- An unvouched zero
------------------------------------------------------------

-- The defect this whole shape exists for, stated as a test. A client that has
-- not finished loading the character answers 0, and writing that down loses a
-- number nobody can get back until that character is played again.
local recorded = ns.db.purse[me]
state.purse = 0
fire("PLAYER_ENTERING_WORLD")
check(ns.db.purse[me] == recorded,
	("a zero from a client that was still loading overwrote %s with %s")
		:format(tostring(recorded), tostring(ns.db.purse[me])))

-- And a character that really does spend its last copper is still written down,
-- because spending is what fires PLAYER_MONEY and PLAYER_MONEY is the client
-- saying the number moved. Without this half the rule would be "never record a
-- zero", which loses the other direction instead.
fire("PLAYER_MONEY")
check(ns.db.purse[me] == 0,
	("a real zero was refused and the ledger still says %s")
		:format(tostring(ns.db.purse[me])))

state.purse = 131 * GOLD
fire("PLAYER_MONEY")

------------------------------------------------------------
-- The slope
------------------------------------------------------------

advance(30)
check(Purse.Rate() == nil, "a thirty second session was given a rate")
beat()
check(rate:GetText() == "",
	"the rate cell said " .. tostring(rate:GetText()) .. " before there was one")

-- Thirty gold over a minute is eighteen hundred an hour, which is the
-- arithmetic the whole strip exists for.
advance(30)
state.purse = 160 * GOLD
beat()
check(rate:GetText() == "+1,800g/h",
	"the rate cell says " .. tostring(rate:GetText()))
check(plain(held:GetText()) == "160g",
	"the held cell says " .. tostring(held:GetText()))
-- 205g 50s, and the fifty silver is dropped rather than shown. That is the
-- coarse form doing its job on the cell that reaches four figures first:
-- the middle of the strip is the narrowest of the three and the silver on
-- an account total is the digit nobody has ever wanted.
check(Purse.Account() == 205 * GOLD + 50 * 100,
	("the account holds %d"):format(Purse.Account()))
check(plain(hoard:GetText()) == "all 205g",
	"the account cell says " .. tostring(hoard:GetText()))

------------------------------------------------------------
-- A quiet beat
------------------------------------------------------------

held:SetText(nil)
beat()
check(held:GetText() == nil, "a beat with nothing to say wrote a cell anyway")

state.purse = 161 * GOLD
beat()
check(plain(held:GetText()) == "161g",
	"a beat after a coin left the cell at " .. tostring(held:GetText()))

------------------------------------------------------------
-- What it costs the frame
------------------------------------------------------------

local tall = _G.WarriorKitLootFeed:GetHeight()
ns.db.lootFeedPurse = false
lootStream:Apply()
local short = _G.WarriorKitLootFeed:GetHeight()
check(not strip:IsShown(), "the strip is still drawn with the setting off")
check(tall > short,
	("the frame is %s either way, so the strip costs it nothing")
		:format(tostring(tall)))

ns.db.lootFeedPurse = true
lootStream:Apply()
check(_G.WarriorKitLootFeed:GetHeight() == tall,
	("the strip came back and the frame is %s rather than %s")
		:format(tostring(_G.WarriorKitLootFeed:GetHeight()), tostring(tall)))

------------------------------------------------------------
-- The hover
------------------------------------------------------------

local Tip = ns.UI.Tooltip
strip:GetScript("OnEnter")(strip)
check(Tip.IsShown(), "hovering the strip opened nothing")
check(Tip.Text(1) == "The purse", "the tooltip is titled " .. tostring(Tip.Text(1)))

local names = 0
for index = 2, Tip.Lines() do
	local label = Tip.Text(index)
	if label == me or label == "Somebody-Elsewhere" or label == "Another-Elsewhere" then
		names = names + 1
	end
end
check(names == 3, ("the tooltip lists %d of the three characters"):format(names))

-- The session block under the account line. Three rows, and the middle one is
-- the number the strip has never had room for: what the evening made you,
-- rather than what you are holding and how fast it is moving.
local said = {}
for index = 2, Tip.Lines() do
	said[Tip.Text(index)] = true
end
for _, label in ipairs({ "Account", "Started with", "Earned", "An hour" }) do
	check(said[label], ("the hover has no %s row"):format(label))
end

-- And every figure on it is coined, which is the one thing that makes a purse
-- readable at a glance rather than a wall of digits.
local coined = false
for index = 2, Tip.Lines() do
	local _, value = Tip.Text(index)
	if (value or ""):find("|cff", 1, true) then
		coined = true
	end
end
check(coined, "not one figure in the hover is coloured by denomination")
strip:GetScript("OnLeave")(strip)

print(("purse  %s held, %s on the account across %d characters, %s")
	:format(ns.Coin(_G.GetMoney()), ns.Coin(Purse.Account()), names,
		rate:GetText() == "" and "no rate yet" or rate:GetText()))

-- The two invented characters go away, because the sections after this one
-- have nothing to do with them and a ledger with strangers in it is a
-- confusing thing to find in a later failure.
ns.db.purse["Somebody-Elsewhere"] = nil
ns.db.purse["Another-Elsewhere"] = nil
