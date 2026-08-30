local ADDON, ns = ...

local Purse = {}
ns.Purse = Purse

local C = ns.UI.Color

--------------------------------------------------------------------------
-- The purse
--
-- Three numbers about money, for the strip along the bottom of the loot feed:
-- what this character is carrying, what every character on the account is
-- carrying between them, and how fast the total is moving.
--
-- **Why it hangs off the loot feed.** That window is already the answer to
-- "what did I just get", and gold was the one part of a pull it could not
-- say. Coin gets a row when it drops and the row scrolls away with everything
-- else; what you actually want to know an hour later is the slope, and a slope
-- belongs on a status line rather than in a list.
--
-- **Why the account total is written down rather than asked for.** The client
-- will only ever tell you about the character you are standing in. Every other
-- character's gold is a number this addon recorded the last time you logged out
-- of them, which is why the ledger lives in WarriorKitDB, the account's table,
-- and not in the per character one beside it.
--
-- The key is name and realm, not name. The client will let you make the same
-- name twice across realms and a ledger keyed on the name alone would have the
-- two of them overwriting each other, which reads as gold that vanishes when
-- you swap realms.
--
-- **Why the rate is since this session and says so.** Gold an hour is a slope
-- and a slope needs two points; the earlier one can only be the moment the
-- addon started counting. A reload starts it again. That is honest rather than
-- convenient: the alternative carries the rate across a gap the addon slept
-- through, which divides what you earned by hours you were not playing.
--
-- Nothing here is on a ticker of its own. Feeds/Stream.lua reads these on the
-- status strip's beat and the strip only has a beat while it is on screen,
-- which is why every answer below is cached and every cache is invalidated by
-- an event rather than by time.
--------------------------------------------------------------------------

-- Gold, for the one line here that divides by it. The formatter that used to
-- need this pair is ns.Coin in Core now, and the silver went with it.
local GOLD = ns.GOLD
local HOUR = 3600

-- Under a minute there is no slope worth drawing. The first copper of a session
-- divided by four seconds is nine hundred thousand gold an hour, which is a
-- true number and a useless one, so the cell stays empty until the span behind
-- it is long enough to mean something.
local SETTLE = 60

--------------------------------------------------------------------------
-- Whose purse
--------------------------------------------------------------------------

-- The key this character is written down under, or nil on a client that will
-- not say who you are yet.
--
-- GetRealmName is probed rather than called. Nothing in this install proves it
-- is on both flavours, and a client that will not answer gets the bare name,
-- which is wrong only for someone who has the same name on two realms and is
-- still better than an error at login.
local function Who()
	local name = UnitName("player")
	if type(name) ~= "string" or name == "" then
		return nil
	end

	local realm = _G.GetRealmName
	if type(realm) == "function" then
		local ok, said = pcall(realm)
		if ok and type(said) == "string" and said ~= "" then
			return name .. "-" .. said
		end
	end
	return name
end

local mine = nil

-- Which purse the client is standing in.
--
-- Resolved on first use rather than at a login event, and that is not belt and
-- braces. Feeds/Stream.lua builds and paints the strip at PLAYER_LOGIN, and
-- this file does not hear anything until PLAYER_ENTERING_WORLD, which is
-- strictly later. A ledger walked with no idea which row is yours counts this
-- character twice, once out of the ledger and once out of GetMoney, so the
-- account total would read high by whatever you are carrying for as long as
-- the loading screen lasts.
--
-- Handed out as well as used here, because two callers probing a client that
-- may not answer could otherwise disagree about which row is yours.
function Purse.Mine()
	if not mine then
		mine = Who()
	end
	return mine
end

-- A name with the realm suffix off and the case flattened, which is what two
-- names have to agree on to be the same character. The ledger's own keys carry
-- the realm and are compared through here rather than directly, because the
-- question below is asked with a name somebody typed.
local function Bare(name)
	if type(name) ~= "string" then
		return nil
	end
	local trimmed = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%-.*$", "")
	if trimmed == "" then
		return nil
	end
	return trimmed:lower()
end

-- Whether this is a character on your own account.
--
-- The ledger is the only list of those the addon has. It is written at every
-- login and every change of money, so it holds every character you have played
-- since the addon arrived and nothing else, which is exactly the question and
-- is the reason this is a reader here rather than a second list somewhere.
--
-- Handed out for the mail window, which colours a recipient by who they are and
-- has to be able to tell your bank alt from a stranger before it will let a
-- stack of ore go to either. Mail/Feature.lua is the only caller and it is the
-- only file in that part allowed to name this one.
--
-- Two characters of the same name on different realms read as the same person,
-- which is the trade Chat/People.lua already documents and takes for the same
-- reason: a name is what you type, and a realm is not.
function Purse.Knows(name)
	local wanted = Bare(name)
	local ledger = ns.db and ns.db.purse
	if not wanted or not ledger then
		return false
	end
	for who in pairs(ledger) do
		if Bare(who) == wanted then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------
-- The ledger
--------------------------------------------------------------------------

-- Registered through Feeds/Loot.lua, because the status line is that feed's
-- and a default nothing on screen reads is a default that rots.
function Purse.Defaults()
	return {
		-- Copper against "Name-Realm", one entry per character you have played
		-- since the addon arrived. A character that is absent is absent rather
		-- than zero, which is the difference between "not counted yet" and
		-- "broke", and the tooltip says which.
		purse = {},

		-- The strip itself. Off, the loot feed is the column it always was and
		-- the frame loses the height back.
		lootFeedPurse = true,
	}
end

-- What you are carrying, or nil for a client that has not finished saying.
--
-- GetMoney answers 0 while the character is still being assembled, and 0 is
-- also a number you can really be holding, so the broken answer and the true
-- one are the same answer and nothing downstream can tell them apart. This
-- shipped, and it recorded an alt carrying sixty three gold as carrying
-- nothing; the first attempt at a fix guessed at which moment was the liar,
-- guessed wrong, and recorded both characters as broke.
--
-- So no moment is trusted. The tie is broken by which event is asking.
-- PLAYER_MONEY is the client saying the number moved, and it is the only thing
-- in the game that vouches for a zero. Everything else records a number it can
-- stand behind and records nothing at all otherwise, which is why a character
-- you have not played is missing from the ledger rather than sitting in it at
-- nought. A character that really does spend its last copper is written down by
-- the PLAYER_MONEY that spending fires.
local function Money(certain)
	local copper = GetMoney() or 0
	if copper == 0 and not certain then
		return nil
	end
	return copper
end

local others, dirty = 0, true

-- Every other character's gold, summed.
--
-- This character is skipped rather than added, because GetMoney is live and the
-- ledger entry for the character you are standing in is only as fresh as the
-- last event. Adding both would double the purse you can see for as long as the
-- two disagree.
local function Others()
	local sum = 0
	local ledger = ns.db and ns.db.purse
	if not ledger then
		return sum
	end

	local me = Purse.Mine()
	for who, copper in pairs(ledger) do
		if who ~= me then
			sum = sum + (tonumber(copper) or 0)
		end
	end
	return sum
end

-- This character's money, written down where the others can see it.
function Purse.Note(certain)
	local ledger = ns.db and ns.db.purse
	local me = Purse.Mine()
	local copper = Money(certain)
	if not ledger or not me or not copper then
		return false
	end
	ledger[me] = copper
	dirty = true
	return true
end

-- Everything, everywhere, in copper.
--
-- The walk is cached because it only moves when a character is written down,
-- which is a login, a logout and a change of money, and never the beat that
-- reads this.
function Purse.Account()
	if dirty then
		dirty = false
		others = Others()
	end
	return others + (GetMoney() or 0)
end

--------------------------------------------------------------------------
-- The slope
--------------------------------------------------------------------------

local openedAt, opening = nil, nil

-- The session's earlier point, and it refuses an unvouched zero for the reason
-- the ledger does. A baseline of nought on a character carrying fifty gold
-- reports that fifty as an hour's earnings, which is the same defect as the
-- ledger's and louder, because it is on screen and moving.
function Purse.Start(certain)
	local copper = Money(certain)
	if not copper then
		return false
	end
	openedAt, opening = GetTime(), copper
	return true
end

-- Copper an hour this session, and the seconds it was measured over. Nil for
-- the rate while the span is still too short to divide by.
function Purse.Rate()
	if not openedAt then
		return nil, 0
	end

	local elapsed = GetTime() - openedAt
	if elapsed < SETTLE then
		return nil, elapsed
	end
	return ((GetMoney() or 0) - opening) * HOUR / elapsed, elapsed
end

--------------------------------------------------------------------------
-- Numbers as words
--------------------------------------------------------------------------

-- The right hand cell. Empty while the session has no slope yet, because the
-- honest alternative is a number nobody should read.
local function RateText(perHour)
	if perHour == false then
		return ""
	end
	if perHour == 0 then
		return "0g/h"
	end
	if perHour > 0 then
		return "+" .. ns.Thousands(perHour) .. "g/h"
	end
	return "-" .. ns.Thousands(-perHour) .. "g/h"
end

-- What colour that cell is. Stable tables, handed back rather than built, for
-- the reason Feeds/Loot.lua keeps its own quality palette: this is read on a
-- ticker and every guard downstream compares a colour by identity.
local function Tone(perHour)
	if perHour == false or perHour == 0 then
		return C.quiet
	end
	if perHour > 0 then
		return C.tick
	end
	return C.loss
end

--------------------------------------------------------------------------
-- The status line
--------------------------------------------------------------------------

local heldAt, heldText = nil, ""
local hoardAt, hoardText = nil, ""
local rateAt, rateText = nil, ""

-- The three cells, and nil for all of them when the strip should not be drawn.
--
-- This runs on the strip's beat, which is why every branch is a comparison and
-- only the branch that took builds a string. The rate is compared in whole gold
-- rather than in copper: the copper figure moves every frame the clock does and
-- the text it renders to changes about once a minute.
function Purse.Line()
	if not ns.db or not ns.db.lootFeedPurse then
		return nil
	end

	local held = GetMoney() or 0
	if held ~= heldAt then
		heldAt = held
		heldText = ns.Coined(held)
		-- And written down from here, which is what makes the ledger heal
		-- itself. Every event this file listens to fires once, at a moment
		-- somebody else decided; this branch fires a second after the loading
		-- screen and again on every change, off a reading the strip is already
		-- showing you. If the number on screen is right then the number in the
		-- ledger is right, and the two cannot drift.
		Purse.Note()
		if not openedAt then
			Purse.Start()
		end
	end

	local hoard = Purse.Account()
	if hoard ~= hoardAt then
		hoardAt = hoard
		hoardText = "all " .. ns.Coined(hoard)
	end

	local rate = Purse.Rate()
	local perHour = rate and math.floor(rate / GOLD) or false
	if perHour ~= rateAt then
		rateAt = perHour
		rateText = RateText(perHour)
	end

	return heldText, hoardText, rateText, Tone(perHour)
end

--------------------------------------------------------------------------
-- The tooltip
--------------------------------------------------------------------------

-- Richest first. A scratch table reused rather than made, because this is the
-- only allocation on a hover and a fresh one per hover is a fresh one per
-- twitch of the mouse along the bottom of the feed.
local order = {}

local function Sorted(ledger)
	for index = #order, 1, -1 do
		order[index] = nil
	end
	for who in pairs(ledger) do
		order[#order + 1] = who
	end
	table.sort(order, function(a, b)
		return (tonumber(ledger[a]) or 0) > (tonumber(ledger[b]) or 0)
	end)
	return order
end

-- The session's own block: what you sat down with, what the evening has made
-- you, and what that is an hour.
--
-- Three rows where this used to be one sentence. The sentence carried the rate
-- and the span and nothing to judge either against, and the number a player
-- wants at the end of a run is the difference between the two ends of it, which
-- the sentence never said out loud.
--
-- The label is what carries the colour rather than the figure. A coined figure
-- is already three colours, one per denomination, and a fourth laid over the
-- top of it would say "this went the wrong way" in the same ink the copper is
-- written in.
local function Session(lines)
	local rate, elapsed = Purse.Rate()

	lines[#lines + 1] = { blank = true }
	lines[#lines + 1] = { ("This session, %d min"):format(math.floor(elapsed / 60)),
		color = C.heading }

	if not opening then
		lines[#lines + 1] = { "Started with", "not counted yet" }
		return lines
	end

	local earned = (GetMoney() or 0) - opening
	lines[#lines + 1] = { "Started with", ns.Coined(opening, true) }
	lines[#lines + 1] = { "Earned", ns.Coined(earned, true), color = Tone(earned) }

	-- The same refusal the strip makes, said in words because a hover has room
	-- for the reason. Under a minute there is no slope, and the honest thing to
	-- print is why rather than a number nobody should read.
	if not rate then
		lines[#lines + 1] = { "An hour", "too short a session to divide by" }
		return lines
	end
	lines[#lines + 1] = { "An hour", ns.Coined(rate, true), color = Tone(rate) }
	return lines
end

-- What the status line has no room to say: every character on the account and
-- what each is carrying.
function Purse.Ledger()
	local lines = {}

	local ledger = ns.db and ns.db.purse
	if ledger then
		local me = Purse.Mine()
		Sorted(ledger)
		for index = 1, #order do
			local who = order[index]
			-- Which row is yours is the name's job now. The figure beside it
			-- is coined, and a colour laid over that is a colour fighting the
			-- three the denominations already carry.
			lines[#lines + 1] = { who, ns.Coined(ledger[who], true),
				color = (who == me) and C.text or C.dim }
		end
		lines[#lines + 1] = { blank = true }
	end

	lines[#lines + 1] = { "Account", ns.Coined(Purse.Account(), true),
		color = C.heading }

	Session(lines)

	return {
		kind = "note",
		title = "The purse",
		lines = lines,
		hint = "A character is written down as you play it, so one you have not"
			.. " logged into since the addon arrived is missing from the list"
			.. " rather than counted as nothing.",
	}
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
-- Not PLAYER_LOGIN. See the note on `known` above: at login this client will
-- say you have a name and will not yet say you have any money.
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_MONEY")
-- The last write of a session. Without it a character you log out of richer
-- than you logged in is remembered at the figure it had at login, and the
-- account total is quietly stale until the next time you play them.
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event)
	local certain = event == "PLAYER_MONEY"

	-- The baseline, once. PLAYER_ENTERING_WORLD fires again at the end of every
	-- loading screen, and a baseline retaken at each one is a rate that starts
	-- over every time you zone into a dungeon.
	if not openedAt then
		Purse.Start(certain)
	end
	Purse.Note(certain)
end)
