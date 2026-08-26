local ADDON, ns = ...

-- The red text in the middle of the screen, filtered by a list you build.
--
-- A warrior generates more of this than anyone. Charge, Intercept and
-- Intervene are all positional, the charge button in this addon aims by camera
-- and so misses on purpose, and every miss costs a line of red text across the
-- middle of the screen. "You are too far away" is not news to the person who
-- just pressed the button, and while it is up it hides the one message that
-- would have been.
--
-- Two rules shape the file.
--
--   Nothing is muted that you did not tick. The list ships empty. A filter
--   that guesses which errors you can live without is a filter that eats the
--   one you needed, so the panel shows what has actually come past this
--   session and you choose from that.
--
--   The list is account-wide. It lives in ns.db, not ns.dbc, so the twenty
--   ticks you made on your warrior are already made when you log in as
--   anything else. There is nothing character-shaped about "I do not need to
--   be told I am facing the wrong way".

local Errors = {}
ns.Errors = Errors

-- How many rows the panel offers. The list is a fixed pool built once at login
-- and shown a row at a time, the same shape the debuff list on the enemy bars
-- has, so this is a real ceiling rather than a page size.
local ROWS = 14

-- What a filtered message is keyed by, when the client can be made to say.
--
-- Two prefixes cover the error frame. ERR_ is the client's own refusals and
-- SPELL_FAILED_ is the server's, and between them they are every line that
-- reaches UIErrorsFrame from a press.
local PREFIXES = { "ERR_", "SPELL_FAILED_" }

--------------------------------------------------------------------------
-- The key
--
-- A muted entry is stored under the name of the global that holds its text,
-- ERR_BADATTACKPOS rather than "You are too far away!". Two reasons, and the
-- second is the one that matters here.
--
-- A name survives a locale. A list built on a German client still means
-- something on an English one, and a client patch that rewords a message does
-- not quietly unmute it.
--
-- A name is also stable across characters, which is the whole point of the
-- list living in the account file. The text is stored beside it only so the
-- panel has something to print, and is never what the lookup turns on.
--
-- Messages built from a format string are the exception and fall back to their
-- own text. "You must be at least level %d" prints a different line every
-- time, so there is no one text to index it by and no honest way to mute it
-- once for all levels. Those are rare, none of them is the spam this file
-- exists for, and the fallback still mutes the exact line you ticked.
--------------------------------------------------------------------------

local names

-- Built once, on the first message through the hook rather than at load,
-- because at load the client is still filling _G and another addon's strings
-- would be missing from it.
--
-- Where two constants carry the same text, the alphabetically first name wins.
-- pairs() has no order, and a key that came out ERR_A one session and ERR_B
-- the next is a mute that stops matching for no reason anybody could see.
local function Names()
	if names then
		return names
	end
	names = {}
	for key, value in pairs(_G) do
		if type(key) == "string" and type(value) == "string" and value ~= ""
			and not value:find("%%") then
			for _, prefix in ipairs(PREFIXES) do
				if key:sub(1, #prefix) == prefix then
					if not names[value] or key < names[value] then
						names[value] = key
					end
					break
				end
			end
		end
	end
	return names
end

-- The key a message is filed under, and the text to print for it.
function Errors.Key(text)
	if type(text) ~= "string" or text == "" then
		return nil
	end
	return Names()[text] or text
end

-- The other direction, for a key read back out of the saved list. A name
-- resolves to whatever this client says that constant is now; anything else is
-- already its own text.
local function Text(key, stored)
	local value = _G[key]
	if type(value) == "string" and value ~= "" then
		return value
	end
	return stored or key
end

--------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------

function Errors.Muted(key)
	return key ~= nil and ns.db.errorMuted[key] ~= nil
end

function Errors.Mute(key, text)
	if key then
		ns.db.errorMuted[key] = text or key
	end
end

function Errors.Unmute(key)
	if key then
		ns.db.errorMuted[key] = nil
	end
end

function Errors.Count()
	local count = 0
	for _ in pairs(ns.db.errorMuted) do
		count = count + 1
	end
	return count
end

--------------------------------------------------------------------------
-- What has come past
--
-- Session only, and deliberately not saved. The list of things you have muted
-- is a preference; the list of things that happened to you this evening is
-- not, and a saved one would fill the panel with the fights you had last week.
--------------------------------------------------------------------------

local seen, order = {}, {}

local function Saw(key)
	if seen[key] then
		return
	end
	seen[key] = true
	table.insert(order, 1, key)
	-- Bounded, because a format-string message keys on its own text and a
	-- levelling character can produce a new one of those every few minutes.
	if #order > ROWS * 2 then
		local dropped = table.remove(order)
		seen[dropped] = nil
	end
end

-- What the panel draws, and the only ordering decision in the file. Muted
-- entries first and alphabetically, so a tick you are looking for is where you
-- left it, then whatever has come past this session and is not muted, newest
-- first, so the error you just saw is at the top of the unticked half.
--
-- Allocates a table per call. It is called from a panel refresh and never from
-- a ticker, which is why it is allowed to.
function Errors.Rows()
	local rows, taken = {}, {}

	local keys = {}
	for key in pairs(ns.db.errorMuted) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		taken[key] = true
		rows[#rows + 1] = { key = key, text = Text(key, ns.db.errorMuted[key]) }
	end

	for _, key in ipairs(order) do
		if not taken[key] and #rows < ROWS then
			rows[#rows + 1] = { key = key, text = Text(key) }
		end
	end

	return rows
end

function Errors.RowLimit()
	return ROWS
end

--------------------------------------------------------------------------
-- The one press that is worth offering
--
-- Everything the charge button's aim costs you when it misses, and nothing
-- else. It is a press rather than a default because the file's first rule is
-- that nothing is muted you did not tick, and a button you pressed is a tick.
--
-- Every name is resolved through _G, so one this client does not have is a
-- skipped entry rather than an error, and the count comes back so the panel
-- can say what it actually managed.
--------------------------------------------------------------------------

local POSITIONAL = {
	"ERR_BADATTACKPOS",           -- you are too far away
	"ERR_BADATTACKFACING",        -- you are facing the wrong way
	"ERR_OUT_OF_RANGE",
	"SPELL_FAILED_OUT_OF_RANGE",
	"SPELL_FAILED_UNIT_NOT_INFRONT",
	"SPELL_FAILED_BAD_TARGETS",
	"SPELL_FAILED_NOTARGET",
	"SPELL_FAILED_TARGET_NOT_IN_LOS",
	"SPELL_FAILED_MOVING",
	"SPELL_FAILED_ROOTED",
	"SPELL_FAILED_TOO_CLOSE",
}

function Errors.SilencePositional()
	local added = 0
	for _, key in ipairs(POSITIONAL) do
		local text = _G[key]
		if type(text) == "string" and text ~= "" and not Errors.Muted(key) then
			Errors.Mute(key, text)
			added = added + 1
		end
	end
	return added
end

function Errors.Clear()
	local cleared = Errors.Count()
	for key in pairs(ns.db.errorMuted) do
		ns.db.errorMuted[key] = nil
	end
	return cleared
end

--------------------------------------------------------------------------
-- The hook
--
-- UIErrorsFrame is a message frame and nothing about it is protected, so its
-- AddMessage is replaced rather than post-hooked. A post-hook cannot stop a
-- message; only standing in front of the call can.
--
-- Installed once and never taken off. Turning the setting off makes the
-- wrapper pass everything through, which is what it does with an empty list
-- anyway. Putting the old method back would mean writing over whatever addon
-- hooked after this one, and a filter is not worth breaking somebody else's.
--------------------------------------------------------------------------

local hooked = false

local function Install()
	if hooked then
		return true
	end
	local frame = _G.UIErrorsFrame
	if not frame or type(frame.AddMessage) ~= "function" then
		return false
	end

	local original = frame.AddMessage
	frame.AddMessage = function(self, text, ...)
		local key = Errors.Key(text)
		if key then
			Saw(key)
			if ns.db and ns.db.errorFilter and Errors.Muted(key) then
				return
			end
		end
		return original(self, text, ...)
	end

	hooked = true
	return true
end

function Errors.Apply()
	if not ns.db then
		return
	end
	Install()
end

-- Whether the filter is standing where it needs to stand. Zero installed means
-- this client calls the error frame something else, which is the answer worth
-- seeing: the ticks are saved and doing nothing rather than the list being
-- empty.
function Errors.Installed()
	return hooked
end

function Errors.Describe()
	if not hooked then
		return "not installed, this client has no UIErrorsFrame to stand in front of"
	end
	if not ns.db.errorFilter then
		return "off, every error reaches the screen"
	end
	local count = Errors.Count()
	if count == 0 then
		return "on, nothing muted yet"
	end
	return ("on, %d message%s muted"):format(count, count == 1 and "" or "s")
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	Errors.Apply()
end)
