local ADDON, ns = ...

-- Thanking a stranger who buffs you.
--
-- Somebody you have never met walks past, puts a Fortitude on you and keeps
-- going. The whisper back costs two letters and about four seconds, and the
-- four seconds are why it usually does not get sent: you are mid-pull, or the
-- name has already scrolled off the screen by the time you have a hand free.
-- This part sends it.
--
-- Strangers only, and that is the whole point of the filter. In a party or a
-- raid the buffs are the arrangement rather than a kindness, and an addon that
-- whispered "ty" at the priest forty times a night would be a nuisance to one
-- of the two people it was meant to be polite to.
--
-- The combat log is the source, the way it is for the swing timer and the
-- reaction windows, because it is the only place the client says who cast the
-- aura at the moment it lands. UnitAura names a caster too, but only as a unit
-- token, and a stranger who buffed you in passing is not your target, is not
-- your focus and has no token at all a second later.
--
-- This part owns no frame and draws nothing, so nothing here is on a ticker.

local Thanks = {}
ns.Thanks = Thanks

local readLog = _G.CombatLogGetCurrentEventInfo

-- How long the same person stays thanked, in seconds. Ten minutes.
--
-- A paladin who blesses you, sees the blessing fall off and blesses you again
-- has done one kind thing, not two, and two whispers inside a minute reads as a
-- macro rather than as manners. Long enough to cover a re-buff; short enough
-- that the stranger who tops you up again on the way back through an hour later
-- is thanked again, because that one is a second kindness.
local COOLDOWN = 600

-- Player GUIDs are strings under this prefix on both of the clients the addon
-- ships for. Matching on it rather than on the combat log's flag word keeps
-- this file off `bit` and off the COMBATLOG_OBJECT_ constants, and it answers
-- the question that is actually being asked: a pet, a totem and a mob are all
-- things you do not whisper, and none of them is a Player.
local PLAYER = "Player-"

local frame
local playerGUID

-- name to when they were last thanked, on the client's own clock. One short
-- string per stranger who has buffed you since login, which is a handful a
-- session in a city and none at all in a dungeon.
local thanked = {}

-- How many have gone out since login, which is the only thing the panel and the
-- slash word have to report. A count rather than a list: the list is above and
-- it is nobody's business but this file's.
local sent = 0

-- The word itself, trimmed, or nil for a setting somebody has emptied. An empty
-- field is a real answer and it means send nothing: it is how you switch the
-- part off without losing the word you had.
local function Word()
	local word = ns.db.thankWord
	if type(word) ~= "string" then
		return nil
	end
	word = word:gsub("^%s+", ""):gsub("%s+$", "")
	return word ~= "" and word or nil
end

local function OnLog()
	local _, subevent, hideCaster, sourceGUID, sourceName, _, _, destGUID,
		_, _, _, _, _, _, auraType = readLog()

	-- Cheapest test first, and it is the one that throws nearly every line
	-- away: the log carries the whole pack, both sides of the duel by the
	-- mailbox and the other party fighting next door, and almost none of it
	-- lands on you.
	if not playerGUID or destGUID ~= playerGUID
		or subevent ~= "SPELL_AURA_APPLIED" then
		return
	end
	if auraType ~= "BUFF" or hideCaster then
		return
	end
	if not sourceGUID or sourceGUID == playerGUID
		or sourceGUID:sub(1, #PLAYER) ~= PLAYER then
		return
	end
	if not sourceName or sourceName == "" then
		return
	end

	-- One of yours. Roster is rebuilt on the roster event rather than scanned
	-- here, so this is a table lookup and not eighty unit queries.
	if ns.Unit.Roster.UnitFor(sourceGUID) then
		return
	end

	local now = GetTime()
	local last = thanked[sourceName]
	if last and now - last < COOLDOWN then
		return
	end

	local word = Word()
	if not word or type(_G.SendChatMessage) ~= "function" then
		return
	end

	thanked[sourceName] = now
	sent = sent + 1
	_G.SendChatMessage(word, "WHISPER", nil, sourceName)
end

-- Registered and unregistered rather than left on with a branch inside, so the
-- setting off means the addon is not reading the combat log at all. That is
-- worth more here than it is on the loot path: this is the busiest event in the
-- game and the part that reads it does nothing at all most nights.
function Thanks.Apply()
	if type(readLog) ~= "function" then
		return
	end
	if not frame then
		frame = CreateFrame("Frame")
		frame:SetScript("OnEvent", OnLog)
	end
	if ns.db.thankStrangers then
		frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	else
		frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
end

function Thanks.Describe()
	if type(readLog) ~= "function" then
		return "this client has no combat log to read the caster from"
	end
	if not ns.db.thankStrangers then
		return "off, nobody is whispered"
	end
	local word = Word()
	if not word then
		return "on with an empty word, so nothing goes out"
	end
	if sent == 0 then
		return ("on, %s, nobody yet"):format(word)
	end
	return ("on, %s, %d sent since login"):format(word, sent)
end

-- What has gone out, for the panel's own reading. Kept beside Describe rather
-- than folded into it because the panel has room for the number on its own line
-- and the slash word does not.
function Thanks.Sent()
	return sent
end

-- The GUID is read again at every entry to the world, the way the swing timer
-- reads it, because it is the one value the whole filter turns on and a login
-- that answered nil would leave this part reading the log and thanking nobody
-- for the rest of the session.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function()
	playerGUID = UnitGUID("player")
	Thanks.Apply()
end)
