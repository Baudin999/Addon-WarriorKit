local ADDON, ns = ...

local Progress = {}
ns.Progress = Progress

--------------------------------------------------------------------------
-- How far along you are, asked of the client
--
-- Two readings and one clock, and nothing in here draws. Progress/Rails.lua is
-- the picture; this is every call the part makes to the game, which is the same
-- seam Quests/Client.lua and Mail/Send.lua draw and is drawn here for the usual
-- reason: the two clients disagree about which of these calls exists, and a
-- disagreement is easier to hold in one file than in the file that is also
-- placing textures.
--
-- **Experience.** Where you are in this level, what the level costs, and the
-- rested pool if there is one. Nil where there is no experience to draw at all,
-- which is three different states the bar treats as one: the level cap, a
-- character with experience switched off, and a client that will not say.
--
-- **The watched faction.** Whichever bar you put on the screen yourself, its
-- standing and where you are inside that standing's band. The client has
-- answered this two ways: a table out of C_Reputation on the newer builds and
-- five values out of GetWatchedFactionInfo on the older ones. Both are asked
-- for, in that order, because this addon ships for a backported client where
-- the answer is genuinely either.
--
-- **The clock is this file's own arithmetic and not the client's.** Nothing in
-- the game will tell you what you are earning an hour, so the tally here
-- watches every experience change and divides. It runs whether or not the bars
-- are drawn, because a rate that started counting when you opened the settings
-- window is a rate about the settings window.
--
-- The tally is per level and it is kept in this character's saved variables, so
-- the estimate is still there after a logout. Those are the same decision made
-- twice: a level is the span the estimate is about, and an hour of it spent
-- yesterday is an hour of evidence about the level you are on now. A level up
-- throws it away, because a rate carried into a level is a rate about the one
-- before it, which is the level that was cheaper.
--------------------------------------------------------------------------

-- The eight standings, in this addon's own English, used where the client has
-- no constant of its own. The client's own are localised and are preferred; a
-- client that names none of them still draws a word rather than a number.
local STANDING = {
	"hated", "hostile", "unfriendly", "neutral",
	"friendly", "honored", "revered", "exalted",
}

-- Which of the three reaction colours a standing draws in. The palette already
-- owns that scale, because a standing is what a faction thinks of you and
-- Color.reaction is exactly that question asked of one mob. Eight entries in
-- three colours rather than eight colours: the word is written on the rail, so
-- the fill only has to say which way it is going.
local BAND = {
	"hostile", "hostile", "hostile", "neutral",
	"friendly", "friendly", "friendly", "friendly",
}

-- How much of the level has to have been counted before an hourly rate means
-- anything. Under a minute the divisor is small enough that one kill reads as a
-- hundred thousand an hour.
local RATE_FLOOR = 60

-- One probed call. Missing and raising both come back nil, which is what every
-- reader below is written against. The same four lines as Quests/Client.lua's
-- and deliberately not shared with it: each one is written against its own
-- returns, and a prober in Core would be a call every part reaches through
-- rather than a seam each part draws.
local function Ask(name, ...)
	local fn = _G[name]
	if type(fn) ~= "function" then
		return nil
	end
	local held = { pcall(fn, ...) }
	if not held[1] then
		return nil
	end
	return unpack(held, 2)
end

local function Number(value)
	return type(value) == "number" and value or nil
end

--------------------------------------------------------------------------
-- Experience
--------------------------------------------------------------------------

-- What this client thinks the last level is, or nil where it will not say.
-- Asked of the call first and of the constant second, because a constant is a
-- global any addon can overwrite and the call is the client's own answer.
local function Ceiling()
	return Number(Ask("GetMaxPlayerLevel")) or Number(_G.MAX_PLAYER_LEVEL)
end

-- Whether there is no experience worth drawing. Three states, one answer,
-- because the rail does the same thing in all three: it is not there.
function Progress.Capped()
	if Ask("IsXPUserDisabled") then
		return true
	end
	local max = Number(Ask("UnitXPMax", "player"))
	if not max or max <= 0 then
		return true
	end
	local ceiling, level = Ceiling(), Number(Ask("UnitLevel", "player"))
	if ceiling and level and level >= ceiling then
		return true
	end
	return false
end

-- Level, how far into it you are, what it costs, and the rested pool. Nil for
-- the whole reading rather than zeroes: a character at the cap has no bar, and
-- a bar drawn at zero of zero is a different claim.
--
-- The rested pool is nil rather than zero when there is none, for the same
-- reason. Zero rested is a fact about a character who has spent it and nil is
-- a client that does not carry the call.
function Progress.Experience()
	if Progress.Capped() then
		return nil
	end
	local value = Number(Ask("UnitXP", "player"))
	local max = Number(Ask("UnitXPMax", "player"))
	if not value or not max or max <= 0 then
		return nil
	end
	local rested = Number(Ask("GetXPExhaustion"))
	if rested and rested <= 0 then
		rested = nil
	end
	return Number(Ask("UnitLevel", "player")) or 0, value, max, rested
end

--------------------------------------------------------------------------
-- The watched faction
--------------------------------------------------------------------------

-- The newer clients' answer, which is one table.
local function WatchedTable()
	local api = _G.C_Reputation
	if type(api) ~= "table" or type(api.GetWatchedFactionData) ~= "function" then
		return nil
	end
	local ok, data = pcall(api.GetWatchedFactionData)
	if not ok or type(data) ~= "table" or not data.name then
		return nil
	end
	return data.name, Number(data.reaction), Number(data.currentStanding),
		Number(data.currentReactionThreshold), Number(data.nextReactionThreshold)
end

-- The older clients' answer, which is five values in a fixed order.
local function WatchedValues()
	local name, standing, low, high, value = Ask("GetWatchedFactionInfo")
	if type(name) ~= "string" or name == "" then
		return nil
	end
	return name, Number(standing), Number(value), Number(low), Number(high)
end

-- The bar you put on the screen yourself: its name, its standing, and where you
-- are inside that standing's own band rather than inside the whole reputation
-- scale. Nil where nothing is watched, which is most characters most of the
-- time and is why the rail is allowed not to be there.
--
-- Both shapes are folded to the same five numbers here, so nothing downstream
-- has to know which client it is running on. A band the client answers as
-- zero wide, which is exalted on every build, comes back with a max of zero and
-- the rail draws it full.
function Progress.Faction()
	local name, standing, value, low, high = WatchedTable()
	if not name then
		name, standing, value, low, high = WatchedValues()
	end
	if not name or not standing then
		return nil
	end
	value, low, high = value or 0, low or 0, high or 0
	local span = high - low
	if span < 0 then
		span = 0
	end
	local into = value - low
	if into < 0 then
		into = 0
	end
	return name, standing, into, span
end

-- What the client calls a standing, in the player's own language, or this
-- addon's word for it where the client carries no such constant.
function Progress.Standing(id)
	if type(id) ~= "number" or id < 1 or id > #STANDING then
		return "unknown"
	end
	local label = _G["FACTION_STANDING_LABEL" .. id]
	if type(label) == "string" and label ~= "" then
		return label
	end
	return STANDING[id]
end

-- Which of the three reaction fills a standing draws in.
function Progress.Band(id)
	if type(id) ~= "number" or id < 1 or id > #BAND then
		return "neutral"
	end
	return BAND[id]
end

--------------------------------------------------------------------------
-- The clock
--
-- Everything below is this file's own arithmetic. It is not on a ticker: it
-- moves when the client says your experience moved and at no other time.
--
-- Two numbers and a mark. What this character has earned at the level it is on
-- and how long it has been earning it are in ns.dbc, which is what makes them
-- survive a logout; the mark is the last time they were written and is not, and
-- cannot be, saved. GetTime counts from when the client started, so a mark
-- carried across a session would be a stretch of time measured against another
-- machine's stopwatch.
--------------------------------------------------------------------------

-- The most one gap between two readings is allowed to add. Nothing fires while
-- you are parked in a city, so an evening spent there arrives as one enormous
-- interval, and counted whole it is an hour of nothing earned dividing into a
-- figure you are reading to decide whether to keep going. Five minutes is
-- longer than any gap in a session actually spent earning, so the cap is only
-- ever reached by a break.
local IDLE_CEILING = 300

-- When the totals were last written. Nil until the first reading of a session.
local mark

-- The last experience reading, so the next one is a difference.
local last

-- Nil before ADDON_LOADED has merged the saved variables, which is a state the
-- login order makes reachable: this file registers PLAYER_LOGIN and the merge
-- is what runs before it.
local function Held()
	return ns.dbc
end

-- The stretch since the last write, added to the level's total and capped.
local function Fold(now)
	local db = Held()
	if db and mark then
		db.progressSeconds = db.progressSeconds + math.min(now - mark, IDLE_CEILING)
	end
	mark = now
end

-- Back to nothing, for the level you are on now.
local function Restart(db, level, now)
	db.progressLevel = level
	db.progressEarned, db.progressSeconds = 0, 0
	mark = now
end

-- One reading folded into the level's tally.
--
-- The branch is the level up, and it is written against both sides of it
-- because the client answers the two halves in either order: the level the
-- client reports has moved, or it has not moved yet and the experience went
-- down instead. Whichever arrives first starts the new level's tally, and the
-- other one arriving a moment later starts it again over a few seconds nobody
-- can read.
local function Sample()
	local db = Held()
	local value = Number(Ask("UnitXP", "player"))
	if not db or not value then
		return
	end
	local level, now = Number(Ask("UnitLevel", "player")) or 0, GetTime()
	if level ~= db.progressLevel or (last and value < last) then
		Restart(db, level, now)
	else
		Fold(now)
		if last then
			db.progressEarned = db.progressEarned + (value - last)
		end
	end
	last = value
end

-- How long this level has been counted for, in seconds, including the stretch
-- since the last reading. That stretch is capped the same way Fold caps it, so
-- an estimate read while you stand still decays for five minutes and then stops
-- rather than falling forever.
function Progress.Elapsed()
	local db = Held()
	if not db then
		return 0
	end
	local held = db.progressSeconds
	if mark then
		held = held + math.min(GetTime() - mark, IDLE_CEILING)
	end
	return held
end

-- What this level has earned so far.
function Progress.Gained()
	local db = Held()
	return db and db.progressEarned or 0
end

-- Experience an hour, or nil where there is not enough of the level counted to
-- divide by.
function Progress.Rate()
	local elapsed, gained = Progress.Elapsed(), Progress.Gained()
	if elapsed < RATE_FLOOR or gained <= 0 then
		return nil
	end
	return gained / elapsed * 3600
end

-- Seconds to the next level at what you have been earning on this one, or nil
-- where there is no rate to work it out from.
function Progress.Eta()
	local rate = Progress.Rate()
	if not rate then
		return nil
	end
	local _, value, max = Progress.Experience()
	if not value then
		return nil
	end
	return (max - value) / rate * 3600
end

-- Seconds as the coarsest true thing, which for a level is hours and minutes.
-- Under a minute it says so rather than rounding to zero.
function Progress.Clock(seconds)
	seconds = math.floor(tonumber(seconds) or 0)
	if seconds < 60 then
		return "under a minute"
	end
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if hours > 0 then
		return ("%dh %dm"):format(hours, minutes)
	end
	return ("%dm"):format(minutes)
end

--------------------------------------------------------------------------
-- Who wants telling
--
-- A part says once that it wants to hear about a change, and hears about every
-- one of them. One list rather than Rails.lua registering the events itself,
-- because the accumulator above has to run whether or not anything is drawn and
-- two frames watching the same five events is two answers to keep in step.
--------------------------------------------------------------------------

local watchers = {}

function Progress.OnChange(fn)
	watchers[#watchers + 1] = fn
	return #watchers
end

local function Announce()
	for index = 1, #watchers do
		watchers[index]()
	end
end

-- One line for /wk status and for the panel.
function Progress.Describe()
	local level, value, max, rested = Progress.Experience()
	local parts
	if not level then
		parts = "no experience to draw"
	else
		parts = ("level %d, %d%% of the way to %d"):format(level,
			max > 0 and math.floor(value / max * 100) or 0, level + 1)
		if rested then
			parts = parts .. (", %s rested"):format(ns.Thousands(math.floor(rested)))
		end
		local eta = Progress.Eta()
		if eta then
			parts = parts .. (", %s at this level's rate"):format(Progress.Clock(eta))
		end
	end
	local name, standing = Progress.Faction()
	if not name then
		return parts .. "; no faction watched"
	end
	return ("%s; %s at %s"):format(parts, name, Progress.Standing(standing))
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
-- The five that move one of the two readings. Registered through pcall for the
-- reason every optional event in this addon is: a name one of these clients has
-- never heard of refuses the registration rather than raising at load.
for _, event in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
	"UPDATE_FACTION", "PLAYER_UPDATE_RESTING" }) do
	pcall(events.RegisterEvent, events, event)
end

-- The last write of a session. Without it the stretch between the last kill and
-- the door is missing from the divisor, and a character logged out mid level
-- comes back with an estimate built on the minutes it happened to be looking at
-- when something died.
events:RegisterEvent("PLAYER_LOGOUT")

events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGOUT" then
		Fold(GetTime())
		return
	end
	Sample()
	if event ~= "PLAYER_LOGIN" then
		Announce()
	end
end)
