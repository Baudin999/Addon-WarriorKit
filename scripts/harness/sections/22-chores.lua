-- The three chores
--
-- Two of these are conveniences and one of them can destroy what you own. The
-- container call the vendor part is built on sells a grey while a merchant
-- window is up and eats, equips or opens the same item when one is not, so the
-- assertions that carry the weight here are the negative ones: that a sweep
-- which loses its window moves nothing, that a green is still in the bag on the
-- last pass, and that the money that arrived is the money those two greys were
-- worth and not a copper more.

local H = ...
local state = H.state
local frames = H.frames
local events, constant, advance = H.events, H.constant, H.advance
local JUNK, refill, misused = H.JUNK, H.refill, H.misused
local GUILD, CORPSE, looted = H.GUILD, H.CORPSE, H.looted
local ns, fire, check = H.ns, H.fire, H.check
local sound = H.sound
local drawn = H.carry.drawn

local function lootedCount()
	local count = 0
	for _ in pairs(looted) do
		count = count + 1
	end
	return count
end

local function clearCorpse()
	for slot in pairs(looted) do
		looted[slot] = nil
	end
end

local function junkLeft()
	local count = 0
	for index = 1, #JUNK do
		if JUNK[index] then
			count = count + 1
		end
	end
	return count
end

_G.SetCVar("autoLootDefault", 1)

----------------------------------------------------------------------
-- Looting
----------------------------------------------------------------------

-- Solo, group loot, auto loot on: the whole corpse in one pass.
clearCorpse()
advance(1)
fire("LOOT_READY")
check(lootedCount() == 4, ("fast loot took %d of 4 slots"):format(lootedCount()))

-- LOOT_READY fires again as each slot clears, and a second pass over slots
-- the first one already took is at best wasted work.
clearCorpse()
fire("LOOT_READY")
check(lootedCount() == 0, "the loot throttle let a second burst straight through")

clearCorpse()
advance(1)
fire("LOOT_READY")
check(lootedCount() == 4, "the loot throttle never released")

-- Master loot, threshold 2. Slots 1 and 2 are under it and are taken; slots
-- 3 and 4 are the master looter's to assign, and taking one of those on
-- someone's behalf is the failure this guard exists for.
clearCorpse()
advance(1)
state.lootMethod = "master"
fire("LOOT_READY")
check(looted[1] and looted[2], "master loot skipped a slot under the threshold")
check(not looted[3] and not looted[4],
	"master loot took a slot the master looter has to hand out")
state.lootMethod = "group"

-- Off is unregistered, not a branch inside a handler the client still calls.
clearCorpse()
advance(1)
ns.db.fastLoot = false
ns.Loot.Apply()
check(#(events["LOOT_READY"] or {}) == 0,
	"fast loot off left the addon sitting on the loot path")
fire("LOOT_READY")
check(lootedCount() == 0, "fast loot off still emptied the corpse")
ns.db.fastLoot = true
ns.Loot.Apply()

----------------------------------------------------------------------
-- The vendor
----------------------------------------------------------------------

-- Four parts sit on the merchant: the sweep, the repair, the row of buttons the
-- bag window grows while a vendor is open, and the merchant window itself. All
-- four hold both edges of the session, so none of them can be told from the
-- others by what it listens to, and none is told apart by its place in the
-- list, which is only TOC order and would move the day the TOC does.
--
-- What tells them apart is the one thing that is still different about each.
-- Three of the four leave the list when their own setting goes off: selling,
-- the bag window and the merchant window. The repair does not, because it keeps
-- watching the session in order to know that one is open, so it is the one left
-- when the other three have been named. Each setting is flicked on its own,
-- with the one applier that owns that registration called and nothing else.
local function listening(frame, event)
	for _, f in ipairs(events[event] or {}) do
		if f == frame then
			return true
		end
	end
	return false
end

-- Two of the four are read again much further down, so those two are the file's
-- names and the rest of the walk is done inside a block of its own. A section is
-- one chunk, Lua caps a chunk at two hundred locals and scripts/check.sh holds
-- this file to forty, which is the pressure that keeps a section from becoming a
-- pile of scratch names.
local vendorFrame, repairFrame

do
	local before = {}
	for _, f in ipairs(events["MERCHANT_SHOW"] or {}) do
		before[#before + 1] = f
	end
	check(#before == 4,
		("%d parts are on MERCHANT_SHOW, the sweep, the repair, the bag row and the merchant window make 4")
			:format(#before))

	-- One setting off, one applier called, and whichever frame left the list is
	-- the one that setting owns. The setting goes straight back afterwards,
	-- because every section below this one is written against a scene with all
	-- four of them on.
	local function dropped(held, setting, apply)
		local was = ns.db[setting]
		ns.db[setting] = false
		apply()
		local gone, kept = nil, {}
		for _, f in ipairs(held) do
			if listening(f, "MERCHANT_SHOW") then
				kept[#kept + 1] = f
			else
				gone = f
			end
		end
		ns.db[setting] = was
		apply()
		return gone, kept
	end

	local bagFrame, merchantFrame, left
	vendorFrame, left = dropped(before, "sellTrash", ns.Vendor.Apply)
	bagFrame, left = dropped(left, "bags", ns.BagsMerchant.Apply)
	merchantFrame, left = dropped(left, "merchant", ns.MerchantWindow.Apply)
	repairFrame = left[1]

	check(vendorFrame ~= nil, "selling off took nothing off MERCHANT_SHOW")
	check(bagFrame ~= nil,
		"switching the bag window off left its merchant row listening for a vendor")
	check(merchantFrame ~= nil,
		"switching the merchant window off left it listening for a vendor")
	check(repairFrame ~= nil and #left == 1,
		("the other three were named and %d frames were left for the repair"):format(#left))
	check(listening(bagFrame, "MERCHANT_SHOW") and listening(bagFrame, "MERCHANT_CLOSED"),
		"switching the bag window back on did not put its merchant row back on both edges")
	check(listening(merchantFrame, "MERCHANT_SHOW")
		and listening(merchantFrame, "MERCHANT_CLOSED"),
		"switching the merchant window back on did not put it back on both edges")
	check(listening(vendorFrame, "MERCHANT_CLOSED"),
		"the sweep is not listening for the window shutting")
	check(listening(repairFrame, "MERCHANT_CLOSED"),
		"the repair is not listening for the window shutting")
end

-- The sale's own tick, asked for by the ns.Perf slot it is timed under rather
-- than found by the frame it hangs off: it hangs off ns.UI.Forever with every
-- other tick that outlives a window, and the frame this part registers its
-- merchant events on carries no script. Looked up per pass because the sweep
-- stops its own tick when it runs out of things to sell.
local function sweep()
	local ticks = 0
	while ns.Vendor.Running() and ticks < 60 do
		local tick = ns.UI.Ticking("vendor")
		if not tick then
			break
		end
		tick:Beat(0.2)
		ticks = ticks + 1
	end
	return ticks
end

-- The one that matters. A sale that starts and then loses its window has to
-- touch nothing at all, because with the window shut every sale is a use.
refill()
_G.MerchantFrame:Show()
fire("MERCHANT_SHOW")
_G.MerchantFrame:Hide()
sweep()
check(junkLeft() == 4, "the sweep emptied the bag with the merchant window shut")
check(misused == 0, "something in the bags was used rather than sold")

-- And the sale itself. Two greys a vendor pays for go, the grey it will not
-- pay for stays, and so does the green.
refill()
local before = _G.GetMoney()
_G.MerchantFrame:Show()
fire("MERCHANT_SHOW")
check(ns.Vendor.Running(), "the merchant opened and no sweep started")

local ticks = sweep()
local sale = _G.GetMoney() - before
check(not ns.Vendor.Running(), "the sweep never stopped on its own")
check(sale == 47 + 12, ("the vendor paid %d for two greys worth 59"):format(sale))
check(junkLeft() == 2,
	("%d left in the bag; the worthless grey and the green make 2"):format(junkLeft()))
check(misused == 0, "the sale used something instead of selling it")

-- Shift is the override, the same key that already means "let me do this
-- myself" everywhere else at a merchant.
refill()
_G.MerchantFrame:Show()
-- Through the stub's own switch rather than by replacing the call. Replaced,
-- the reader stays replaced for every section after this one, and the bars'
-- own lock is shift too: 38-bar-look asked for a key that had been a constant
-- false since this line ran.
_G.WarriorKitShift(true)
fire("MERCHANT_SHOW")
check(not ns.Vendor.Running(), "shift did not hold the sale off")
_G.WarriorKitShift(false)

ns.db.sellTrash = false
ns.Vendor.Apply()
check(not listening(vendorFrame, "MERCHANT_SHOW"),
	"selling off left the addon sitting on the merchant")
ns.db.sellTrash = true
ns.Vendor.Apply()
_G.MerchantFrame:Hide()

----------------------------------------------------------------------
-- The repair
--
-- One call and no ticker, so what is asserted is not that it finished but
-- that the right purse paid. Every branch below ends with somebody out of
-- pocket by exactly the bill, or with the bill still standing.
----------------------------------------------------------------------

local function damage(amount)
	state.repairBill = amount
	state.paidBy = nil
end

-- Nothing damaged is not a refusal, and it must not print as one.
state.purse = 500
damage(0)
_G.MerchantFrame:Show()
fire("MERCHANT_SHOW")
check(ns.Repair.Run() == 0, "an undamaged warrior was not reported as undamaged")

-- Your own money, which is the ordinary case: no guild bank in reach.
GUILD.allowed = false
damage(120)
state.purse = 500
fire("MERCHANT_SHOW")
check(state.repairBill == 0, "opening a merchant left the gear damaged")
check(state.purse == 380, ("the repair cost 120 and the purse moved by %d"):format(500 - state.purse))
check(state.paidBy == "you", "the repair was not billed to the player")

-- A purse that cannot cover it is left alone. Half a repair is not a thing
-- the client offers and a purse emptied to nothing is worse than broken mail.
damage(400)
state.purse = 100
fire("MERCHANT_SHOW")
check(state.repairBill == 400, "a repair went through on a purse that could not cover it")
check(state.purse == 100, "money left a purse that could not cover the repair")

-- Guild funds first where the guild allows it, and the purse untouched.
GUILD.allowed, GUILD.limit, GUILD.held, GUILD.spent = true, 1000, 1000, 0
damage(400)
state.purse = 100
fire("MERCHANT_SHOW")
check(state.repairBill == 0, "the guild bank was in reach and the gear stayed damaged")
check(GUILD.spent == 400, ("the guild paid %d of a 400 bill"):format(GUILD.spent))
check(state.purse == 100, "the guild paid and the purse moved as well")

-- An unlimited rank answers -1, which is a sentinel and not an amount. Read
-- as an amount it is the smallest allowance there is and every repair falls
-- through to your own gold.
GUILD.allowed, GUILD.limit, GUILD.held, GUILD.spent = true, -1, 1000, 0
damage(400)
state.purse = 1000
fire("MERCHANT_SHOW")
check(GUILD.spent == 400, "an unlimited withdraw allowance was read as no allowance")
check(state.purse == 1000, "an unlimited rank still paid out of the player's purse")

-- A rank allowed to withdraw less than the bill falls back to your gold
-- rather than trying the guild and walking away.
GUILD.allowed, GUILD.limit, GUILD.held, GUILD.spent = true, 50, 1000, 0
damage(400)
state.purse = 1000
fire("MERCHANT_SHOW")
check(GUILD.spent == 0, "the guild paid past the rank's withdraw limit")
check(state.purse == 600, ("the purse should have covered the 400; it moved %d"):format(1000 - state.purse))
check(state.repairBill == 0, "a rank under the limit left the gear damaged")

-- And a guild that says yes and then refuses. The addon has to notice the
-- bill is still standing and pay it itself.
GUILD.allowed, GUILD.limit, GUILD.held, GUILD.spent = true, 1000, 0, 0
damage(400)
state.purse = 1000
fire("MERCHANT_SHOW")
check(state.repairBill == 0, "the guild refused and nothing paid the bill")
check(state.purse == 600, "the guild refused and the fall-through never happened")
GUILD.allowed = false

-- A merchant who does not mend is a refusal with a reason, not a repair.
state.repairsMerchant = false
damage(400)
state.purse = 1000
fire("MERCHANT_SHOW")
check(state.repairBill == 400, "a merchant who does not repair repaired anyway")
check(select(2, ns.Repair.Run()) == "this merchant does not repair",
	"the refusal did not say why")
state.repairsMerchant = true

-- Shift holds it off, the same key that holds the sale off.
damage(400)
state.purse = 1000
_G.WarriorKitShift(true)
fire("MERCHANT_SHOW")
check(state.repairBill == 400, "shift did not hold the repair off")
_G.WarriorKitShift(false)

-- Off is a branch inside the handler, and deliberately not an unregister.
-- The repair keeps both edges of the merchant window whatever the setting
-- says, because what it learns from them is whether a merchant is open, and
-- `/wk repair` and the panel's button both need that answer with the
-- automatic repair turned off.
ns.db.autoRepair = false
ns.Repair.Apply()
check(listening(repairFrame, "MERCHANT_SHOW"),
	"repair off stopped the addon watching the merchant open")
fire("MERCHANT_SHOW")
check(state.repairBill == 400, "repair off still paid the merchant")
check(ns.Repair.Cost() == 400,
	"repair off left the manual repair unable to see the merchant")
ns.db.autoRepair = true
ns.Repair.Apply()

-- The regression, and the reason this file grew a merchant that can be open
-- with its window shut. MERCHANT_SHOW is the server opening a session, not
-- the client finishing the window: the panel defers behind another panel,
-- and a client that loads MerchantFrame on demand has no frame to ask at
-- all. The repair gated on MerchantFrame:IsShown() and so did nothing at
-- every vendor, in silence, because OnEvent swallows refusals.
fire("MERCHANT_CLOSED")
damage(400)
state.purse = 1000
_G.MerchantFrame:Hide()
fire("MERCHANT_SHOW")
check(state.repairBill == 0, "the window was not up yet and the repair gave up")
check(state.purse == 600, "a repair with the window not yet drawn never paid")

-- And the far edge. With the session closed there is no merchant to quote
-- against, whatever any frame on screen says.
fire("MERCHANT_CLOSED")
check(ns.Repair.Cost() == nil, "the merchant closed and the repair still quoted")
check(select(2, ns.Repair.Run()) == "no merchant window is open",
	"a repair with no merchant open did not say so")
_G.MerchantFrame:Show()
fire("MERCHANT_SHOW")

-- The worst piece, not the first one and not an average. A ring answers
-- nothing and must not count as a piece at zero.
damage(0)
local worst, counted = ns.Repair.Durability()
check(counted == 3, ("%d slots answered durability, three wear"):format(counted))
check(worst ~= nil and math.floor(worst + 0.5) == 12,
	"the worst piece is at 12%% and the scan did not say so")

fire("MERCHANT_CLOSED")
_G.MerchantFrame:Hide()

----------------------------------------------------------------------
-- The camera
----------------------------------------------------------------------

ns.db.maxZoom = true
ns.Camera.Apply()
check(ns.Camera.Current() == 4, "max zoom never reached the CVar")

-- Off hands the CVar back at whatever this client calls its default. With no
-- GetCVarDefault, which is the client the fallback exists for, that is the
-- documented 1.9.
ns.db.maxZoom = false
ns.Camera.Apply()
check(ns.Camera.Current() == 1.9, "turning max zoom off did not hand the CVar back")

-- And where the client does state a default, that is the number used.
_G.GetCVarDefault = function() return "2.4" end
ns.Camera.Apply()
check(ns.Camera.Current() == 2.4, "the client's own default was ignored")
_G.GetCVarDefault = nil

ns.db.maxZoom = true
ns.Camera.Apply()

----------------------------------------------------------------------
-- The fanfare
--
-- The part is five seconds of a sound file and one event, so what is worth
-- asserting is the three ways it can be wrong in silence: the wrong file, a
-- second copy of it over the first, and a client that answered something the
-- addon read as a refusal when it was not one.
----------------------------------------------------------------------

do
	local SNIPPET = "Interface\\AddOns\\WarriorKit\\Media\\BestAround.mp3"

	local function heard()
		return #sound.played
	end

	ns.db.levelFanfare = true
	ns.Fanfare.Apply()

	local before = heard()
	advance(60)
	fire("PLAYER_LEVEL_UP")
	check(heard() == before + 1, "levelling up played nothing")
	check(sound.played[heard()].path == SNIPPET,
		("the fanfare handed the client %s"):format(tostring(sound.played[heard()].path)))
	check(sound.played[heard()].channel == "Master",
		"the fanfare went out on the sound effects slider rather than the master one")

	-- Two levels off one turn-in. The client fires the event once a level and the
	-- second one lands in the same frame as the first, so the throttle is the only
	-- thing between you and two copies of the same five seconds a frame apart.
	before = heard()
	fire("PLAYER_LEVEL_UP")
	check(heard() == before, "a second level in the same breath started the clip again")

	-- And past the end of the clip it plays again, because the throttle is the
	-- length of the song and not a rule about how often you may level.
	advance(6)
	fire("PLAYER_LEVEL_UP")
	check(heard() == before + 1, "the throttle never released")

	-- Off is unregistered, not a branch inside a handler the client still calls.
	ns.db.levelFanfare = false
	ns.Fanfare.Apply()
	before = heard()
	advance(60)
	fire("PLAYER_LEVEL_UP")
	check(heard() == before, "the fanfare played with the setting off")
	check(ns.Fanfare.Describe():match("^off"), "off does not describe itself as off")

	-- A press ignores the switch, the same as `/wk repair` does. This is the whole
	-- of how anybody decides whether they want the setting on.
	check(ns.Fanfare.Play(), "the press refused to play with the setting off")
	check(heard() == before + 1, "the press played nothing")

	-- A refused call. The client answers nil rather than raising, and a fanfare
	-- that did not sound has to say so: it is otherwise indistinguishable from
	-- a setting somebody forgot they turned off.
	--
	-- The client gives one answer for two causes. A file that is not in Media
	-- and a channel that is muted both come back as this, and the addon does
	-- not ship the file, so absent is the likelier of the two and neither is
	-- guessed at. The reading names both.
	sound.willPlay = false
	advance(60)
	local played, why = ns.Fanfare.Play()
	check(not played, "a refused call reported as played")
	check(why == "the file is not in Media, or the master volume is down",
		("a refused call reported %q"):format(tostring(why)))

	-- And the build that answers nothing at all, which is the one the return
	-- counting exists for. Read positionally, its silence is a refusal, and every
	-- fanfare that played perfectly well would be reported as one that did not.
	sound.willPlay = "silent"
	advance(60)
	check(ns.Fanfare.Play(), "a client that returns nothing was read as a muted channel")
	sound.willPlay = true

	-- A client with no PlaySoundFile at all loses the fanfare and nothing else.
	local play = _G.PlaySoundFile
	_G.PlaySoundFile = nil
	advance(60)
	check(not ns.Fanfare.Play(), "the fanfare played on a client with nothing to play it")
	check(ns.Fanfare.Describe():match("PlaySoundFile"),
		"a client that cannot play it does not say so")
	_G.PlaySoundFile = play

	ns.db.levelFanfare = true
	ns.Fanfare.Apply()
end

----------------------------------------------------------------------
-- The error filter
--
-- One replaced method, and everything below is asked of the screen rather
-- than of the list. What is asserted is which lines drew.
----------------------------------------------------------------------

check(ns.Errors.Installed(), "the filter never got in front of UIErrorsFrame")

local function shout(text)
	_G.UIErrorsFrame:AddMessage(text)
end
local function lastDrawn()
	local drawn = _G.UIErrorsFrame.drawn
	return drawn[#drawn]
end
local function drewCount()
	return #_G.UIErrorsFrame.drawn
end

-- Nothing is muted until something is ticked, and that is the shipping
-- state. A filter that is on and eats a message out of the box is the
-- failure this default exists to prevent.
check(ns.db.errorFilter, "the error filter did not ship on")
check(ns.Errors.Count() == 0, "the muted list did not ship empty")
shout(_G.ERR_BADATTACKPOS)
check(lastDrawn() == _G.ERR_BADATTACKPOS, "an unmuted error did not reach the screen")

-- The key is the name of the global, not the text. This is what makes a
-- list built on one client mean the same thing on another, and what makes
-- it worth saving account-wide at all.
check(ns.Errors.Key(_G.ERR_BADATTACKPOS) == "ERR_BADATTACKPOS",
	"the message did not resolve to the constant that holds it")
check(ns.Errors.Key("something no constant holds") == "something no constant holds",
	"an unknown message did not fall back to its own text")
check(ns.Errors.Key(("You must be at least level %d."):format(14))
	== "You must be at least level 14.",
	"a format-string message resolved to a name it cannot share with its siblings")

-- Muted, and the screen stops getting it. The control keeps arriving in
-- the same breath.
ns.Errors.Mute("ERR_BADATTACKPOS", _G.ERR_BADATTACKPOS)
local before = drewCount()
shout(_G.ERR_BADATTACKPOS)
check(drewCount() == before, "a muted error still drew")
shout(_G.ERR_ABILITY_COOLDOWN)
check(lastDrawn() == _G.ERR_ABILITY_COOLDOWN,
	"muting one message took an unrelated one with it")

-- The switch is not the list. Off passes everything and keeps the ticks,
-- which is why turning it off and on again is not a way to lose them.
ns.db.errorFilter = false
shout(_G.ERR_BADATTACKPOS)
check(lastDrawn() == _G.ERR_BADATTACKPOS, "the filter off still swallowed a message")
check(ns.Errors.Count() == 1, "turning the filter off emptied the list")
ns.db.errorFilter = true

-- Untick and it comes back.
ns.Errors.Unmute("ERR_BADATTACKPOS")
shout(_G.ERR_BADATTACKPOS)
check(lastDrawn() == _G.ERR_BADATTACKPOS, "unmuting did not put the message back")

-- The list the panel draws. Everything that has come past this session is
-- in it whether or not it is muted, because you cannot tick what you cannot
-- see, and what is muted sorts to the top.
local rows = ns.Errors.Rows()
local heard = {}
for _, entry in ipairs(rows) do
	heard[entry.key] = entry.text
end
check(heard["ERR_BADATTACKPOS"] == _G.ERR_BADATTACKPOS,
	"a message that came past this session is not offered to tick")
check(heard["ERR_ABILITY_COOLDOWN"] == _G.ERR_ABILITY_COOLDOWN,
	"the control never reached the list either")

ns.Errors.Mute("ERR_ABILITY_COOLDOWN", _G.ERR_ABILITY_COOLDOWN)
check(ns.Errors.Rows()[1].key == "ERR_ABILITY_COOLDOWN",
	"a muted entry did not sort to the top of the list")
ns.Errors.Unmute("ERR_ABILITY_COOLDOWN")

-- The one preset, and the only thing in the addon that mutes without a tick
-- on a row. It is a press, and every name it carries is resolved through
-- _G, so a client missing one of them mutes the rest.
local added = ns.Errors.SilencePositional()
check(added == 3, ("%d of the positional set exist on this stub, three do"):format(added))
check(ns.Errors.Muted("ERR_BADATTACKFACING"), "the preset missed the facing message")
check(ns.Errors.Muted("SPELL_FAILED_UNIT_NOT_INFRONT"),
	"the preset missed the server's version of the same refusal")
shout(_G.ERR_BADATTACKFACING)
check(lastDrawn() ~= _G.ERR_BADATTACKFACING, "the preset ticked a row and drew anyway")

-- The list is the account's, not the character's. This is the whole reason
-- it is in ns.db, and a rename that moved it would pass every assertion
-- above and silently reset itself on the next character.
check(ns.db.errorMuted ~= nil, "the muted list is not in the account table")
check(ns.dbc.errorMuted == nil, "the muted list is in the character table")

local muted = ns.Errors.Count()
check(ns.Errors.Clear() == muted, "clearing did not report what it cleared")
check(ns.Errors.Count() == 0, "clearing left something muted")
shout(_G.ERR_BADATTACKFACING)
check(lastDrawn() == _G.ERR_BADATTACKFACING, "clearing did not put the messages back")

print(("chores corpse of %d in one pass, vendor paid %s over %d passes for 2 of 4 slots, repair %s, camera %s, fanfare %d played, errors %s over %d drawn")
	:format(#CORPSE, _G.GetCoinText(sale), ticks, ns.Repair.Describe(),
		ns.Camera.Describe(), #sound.played, ns.Errors.Describe(), drewCount()))

----------------------------------------------------------------------
-- Thanking a stranger
----------------------------------------------------------------------

-- The assertions that carry the weight here are the negative ones, the way
-- they are for the vendor above. This part sends a whisper to somebody who is
-- not in the group and has not agreed to hear from the addon, so what matters
-- is every line it refuses: the mob, the pet, your own aura, the debuff, the
-- person you are grouped with, and the second buff from somebody already
-- thanked.
--
-- The ten minute expiry is not asserted. GetTime is one clock shared by every
-- section and moving it six hundred seconds here would move it for the purse
-- and the feeds as well. What is asserted instead is the half of the throttle
-- that can be proved without touching the clock: that it holds against a
-- repeat, and that it is per person rather than one gate over everybody.
do
	local guids, chat, group, logArgs = H.guids, H.chat, H.group, H.logArgs
	local ME = "Player-0-00000c01"
	local MAGE, PRIEST = "Player-0-00000c02", "Player-0-00000c03"

	local function buffLine(source, name, dest, auraType, subevent)
		for index = 1, 21 do
			logArgs[index] = nil
		end
		logArgs[1] = _G.GetTime()
		logArgs[2] = subevent or "SPELL_AURA_APPLIED"
		logArgs[4] = source
		logArgs[5] = name
		logArgs[8] = dest
		logArgs[12] = 1459
		logArgs[15] = auraType or "BUFF"
		fire("COMBAT_LOG_EVENT_UNFILTERED")
	end

	-- Nothing goes out in the frame the buff lands in. The whisper waits one
	-- to three seconds, so every count below is read after the clock has been
	-- moved past the longest of those and the part's own ticker has run.
	-- The queue's tick, looked up rather than held, because it is armed on the
	-- first whisper queued and stops itself the moment the queue empties.
	local function deliver()
		advance(4)
		local tick = ns.UI.Ticking("thanks")
		if tick then
			tick:Beat(4)
		end
	end

	local function sentCount()
		return #chat.sent
	end

	local function last()
		return chat.sent[#chat.sent] or {}
	end

	guids.player = ME
	fire("PLAYER_ENTERING_WORLD")
	for index = #chat.sent, 1, -1 do
		chat.sent[index] = nil
	end

	-- The replay first. Coming out of a loading screen the client hands back
	-- every buff you are already carrying as a fresh application, caster and
	-- all, and thanking those people thanks them for something they did before
	-- you logged out.
	buffLine(MAGE, "Arcanist", ME)
	deliver()
	check(sentCount() == 0,
		("a login replay whispered %d people"):format(sentCount()))
	advance(5)

	buffLine(MAGE, "Arcanist", ME)
	check(sentCount() == 0, "the whisper went out in the same frame as the buff")
	deliver()
	check(sentCount() == 1, ("a stranger's buff sent %d whispers, one is right"):format(sentCount()))
	-- The word off the setting rather than typed. What it says is the shipped
	-- screen's business and it is a capture; what this line is about is that
	-- the thanks that went out is the one the setting holds.
	check(last().text == ns.db.thankWord,
		("the whisper said %q and the setting holds %q")
			:format(tostring(last().text), tostring(ns.db.thankWord)))
	check(last().kind == "WHISPER" and last().target == "Arcanist",
		("the thank you went out as %s to %s"):format(tostring(last().kind), tostring(last().target)))

	-- A second buff from the same person inside the window. One kindness.
	buffLine(MAGE, "Arcanist", ME)
	deliver()
	check(sentCount() == 1, "the same stranger was thanked twice for one visit")

	-- Somebody else, in the same window. The throttle is per person, and a
	-- single gate over everybody would swallow this one.
	buffLine(PRIEST, "Healgood", ME)
	deliver()
	check(sentCount() == 2, "the throttle held against a second stranger as well as the first")

	-- Everything the filter is for. None of these is a stranger being kind.
	buffLine("Creature-0-00000c04", "Water Elemental", ME)
	buffLine("Pet-0-00000c05", "Snapjaw", ME)
	buffLine(ME, "You", ME)
	buffLine(PRIEST, "Healgood", "Creature-0-00000c06")
	buffLine(MAGE, "Arcanist", ME, "DEBUFF")
	buffLine(MAGE, "Arcanist", ME, "BUFF", "SPELL_AURA_REMOVED")
	deliver()
	check(sentCount() == 2, ("%d whispers went to something that is not a stranger's buff")
		:format(sentCount() - 2))

	-- One of yours. In a group the buffs are the arrangement, and this is the
	-- assertion the whole part turns on.
	group.Set({ { name = "Buffbot", class = "PRIEST", token = "party1" } })
	fire("GROUP_ROSTER_UPDATE")
	buffLine(guids.party1, "Buffbot", ME)
	deliver()
	check(sentCount() == 2, "somebody in the party was whispered a thank you")
	group.Forget()
	fire("GROUP_ROSTER_UPDATE")

	-- An emptied word is a real answer and it means send nothing, which is how
	-- the part is silenced without losing the word you had.
	ns.db.thankWord = "   "
	buffLine("Player-0-00000c07", "Shaman", ME)
	deliver()
	check(sentCount() == 2, "an empty word still sent a whisper")
	check(ns.db.thankWord == "   ", "the empty word was overwritten rather than kept")
	ns.db.thankWord = "ty"

	-- Off is unsubscribed, not a branch inside a handler that is still being
	-- called. This is the busiest event in the game and the setting off has to
	-- take this part off it entirely. Counted on ns.CombatLog rather than on
	-- the client's own registration list, because six parts share one frame
	-- now: what the client holds is asserted in 24-combat-log, where the last
	-- reader leaving is the thing under test.
	local readers = ns.CombatLog.Count()
	ns.db.thankStrangers = false
	ns.Thanks.Apply()
	check(ns.CombatLog.Count() == readers - 1,
		("thanks off left %d parts on the combat log and %d were on it")
			:format(ns.CombatLog.Count(), readers))
	buffLine("Player-0-00000c08", "Druid", ME)
	deliver()
	check(sentCount() == 2, "thanks off still whispered somebody")

	ns.db.thankStrangers = true
	ns.Thanks.Apply()
	check(ns.CombatLog.Count() == readers,
		"thanks back on did not put the part back on the combat log")
	buffLine("Player-0-00000c08", "Druid", ME)
	deliver()
	check(sentCount() == 3, "thanks back on sent nothing")

	print(("chores thanks %s, %d whispers over the run"):format(ns.Thanks.Describe(), sentCount()))

	-- Left as it was found. Every section after this one sets its own player
	-- and its own roster, and a stale unit list is the kind of fixture that
	-- makes another section fail for something that is not in it.
	guids.player = nil
	fire("GROUP_ROSTER_UPDATE")
end
