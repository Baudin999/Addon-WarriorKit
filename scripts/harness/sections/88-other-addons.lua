-- The notice about what else is running
--
-- Core/Replaced.lua is the one thing the addon says without being asked, and
-- everything that can go wrong with it is a state nobody would think to open
-- the game in. The run this suite does is the ordinary install: nothing on the
-- list is loaded, so nothing is said, and that is the first thing asserted
-- because it is the state nearly every player is in and the one where a false
-- positive is a window in front of somebody who has done nothing wrong.
--
-- Four more, and every one of them is a way a one-shot notice goes wrong.
--
-- It says what it found and only that. A notice naming an addon that is not
-- running is worse than no notice: the player goes looking for it, does not
-- find it, and stops believing the rest of the list.
--
-- It goes up once. The flag is written when the window appears rather than when
-- it is dismissed, so a player who presses Escape is not told again tomorrow.
-- That is the whole feature, and a version that wrote the flag in the button's
-- own handler passes every other check here.
--
-- The word brings it back. A notice that can only ever be seen once is a notice
-- nobody can re-read, and the flag being kept out of `/wk defaults` means the
-- word and the button on the page are the only two ways to it.
--
-- The two worth keeping are named in the sentence under the list. The one thing
-- the addon must not do is tell somebody to turn off Questie, which it reads.
--
-- Everything this section turns on is turned off again at the foot of the file,
-- because a client with a damage meter loaded is not the client the sections
-- below expect.

local H = ...
local ns, check = H.ns, H.check

local Replaced = ns.Replaced

check(Replaced ~= nil, "Core/Replaced.lua left nothing on ns")

-- What the run found before this section touched anything, which is the
-- ordinary install: an addon list with nothing on it but the client's own
-- load-on-demand Channels module.
check(#Replaced.Running() == 0,
	("the notice found %d addons in a client running none"):format(#Replaced.Running()))
check(Replaced.Words() == nil, "a client running nothing was given words to say")
check(ns.db.replacedTold == false,
	"the notice was marked as told on a login where there was nothing to tell")
check(_G.WarriorKitReplaced == nil,
	"the notice built its window on a login where it had nothing to say")

----------------------------------------------------------------------
-- What it says, once it has something to say
----------------------------------------------------------------------

local function running(...)
	for index = 1, select("#", ...) do
		H.addons[(select(index, ...))] = true
	end
	Replaced.Forget()
end

local function quiet()
	for name in pairs(H.addons) do
		if name ~= "Blizzard_Channels" then
			H.addons[name] = nil
		end
	end
	Replaced.Forget()
end

-- Three of the list, from three different parts of the screen, plus one addon
-- the list has never heard of and one it deliberately leaves alone. Auctionator
-- is the one that matters: Feeds/Auction.lua reads it for the price on a loot
-- row, so a notice that named it would be telling the player to turn off one of
-- this addon's own sources.
running("Baganator", "Details", "Plater", "Auctionator", "SomeAddonNobodyWrote")

local found = Replaced.Running()
check(#found == 3,
	("%d of the five addons loaded were recognised, and three are on the list")
		:format(#found))

local named = {}
for _, entry in ipairs(found) do
	named[entry.addon] = entry.draws
end
check(named.Baganator ~= nil, "Baganator is running and the notice did not name it")
check(named.Details ~= nil, "Details is running and the notice did not name it")
check(named.Plater ~= nil, "Plater is running and the notice did not name it")
check(named.Auctionator == nil,
	"the notice named Auctionator, which this addon reads prices out of")
check(named.SomeAddonNobodyWrote == nil,
	"the notice named an addon that is not on its list")

local words = Replaced.Words()
check(words ~= nil, "three addons are running and the notice had nothing to say")
if words then
	check(words:find("Baganator, your bags", 1, true) ~= nil,
		"the notice does not say what Baganator draws")
	check(words:find("Questie", 1, true) ~= nil,
		"the notice does not name Questie as one to keep")
	check(words:find("DialogueUI", 1, true) ~= nil,
		"the notice does not name DialogueUI as one to keep")
	check(words:find("SomeAddonNobodyWrote", 1, true) == nil,
		"the notice put an addon it does not know in front of the player")
end

check(Replaced.Describe():find("3 addons", 1, true) ~= nil,
	("the status line reads %q with three of them running"):format(Replaced.Describe()))

----------------------------------------------------------------------
-- Once, and once only
----------------------------------------------------------------------

check(Replaced.Told() == false, "the notice was told before it was ever shown")

local said = Replaced.Show()
check(said == words, "the window went up saying something other than the notice")
check(Replaced.Told() == true, "the notice went up and did not write down that it had")

local window = _G.WarriorKitReplaced
check(window ~= nil, "the notice was shown and built no window")
if window then
	check(window:IsShown(), "the notice's window was built and not shown")
	-- Escape, the close box and the button are all the same answer, because the
	-- flag is already written. This is the one that would have been missed.
	window:Hide()
	check(Replaced.Told() == true,
		"closing the notice without pressing the button unmarked it as told")
end

-- The login path, run again as tomorrow's login runs it: the flag is set, so
-- nothing happens. Driven through the event rather than by calling Show, which
-- is the half that decides whether a player is told twice.
H.fire("PLAYER_LOGIN")
check(window == nil or not window:IsShown(),
	"the notice came back on the next login after the player had been told")

-- And the word, which is the way back to it. It reports rather than asks, so
-- the window goes up again on a flag that is already written.
local slash = _G.SlashCmdList.WARRIORKIT
slash("replaces")
check(window ~= nil and window:IsShown(),
	"the replaces word did not put the notice back up")
if window then
	window:Hide()
end

----------------------------------------------------------------------
-- Put back
----------------------------------------------------------------------

quiet()
ns.db.replacedTold = ns.DefaultFor("replacedTold")

check(#Replaced.Running() == 0, "the section left an addon loaded behind it")

print(("addons  %d of five loaded recognised, notice said once and stayed down"
	.. " on the login after"):format(#found))
