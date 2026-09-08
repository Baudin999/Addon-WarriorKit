local ADDON, ns = ...

local Replaced = {}
ns.Replaced = Replaced

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- What else is running that this addon already draws
--
-- Said once, on the first login where there is something to say, and never
-- again.
--
-- **This addon is not a set of parts.** It draws the bags, the bars, the unit
-- frames, the nameplates, the meters, the chat window, the map, the character
-- sheet and the minimap, and it draws every one of them over the client's own.
-- A player who arrives here from a folder of twelve addons gets two of each: two
-- bag windows, two damage meters, two sets of nameplates, and whichever loaded
-- last is the one on top. Nothing in the game says so. Both addons work
-- perfectly, the screen is a mess, and the player's reading of that is that this
-- addon is broken.
--
-- So the addon says it, in words, on the one login where it can be sure the
-- player is looking. It is a notice and not a question: nothing is disabled,
-- nothing is changed, and the two lists below are the whole of what it knows.
--
-- **The list is folder names and nothing cleverer.** ns.AddOnRunning asks the
-- client whether a folder is loaded, which is exactly "is this running", and a
-- name that is not on the list is not mentioned. A pattern over the addon list
-- would catch more and would also tell somebody to turn off an addon this one
-- has never heard of, which is worse than saying nothing. An addon that is
-- installed and switched off reads as absent, which is the state the notice is
-- trying to reach.
--
-- **Two addons are named as worth keeping, and they are named because they do
-- something this one does not.** Questie is the quest database: the turn-in map
-- under a quest, the drop rate under a wanted item and the reason on a clutter
-- card all come from it, and the TOC declares it as an optional dependency.
-- DialogueUI is the quest text itself. Everything else this addon draws.
--
-- **The flag is a record, not a preference.** It says the player has been told,
-- which is a thing that happened rather than a number anybody chose, so it is
-- in Core/Core.lua's KEPT list and `/wk defaults` steps over it. The two ways
-- back to the notice are the word and the button on the page.
--------------------------------------------------------------------------

-- Every addon this one draws over, and what of it draws over them. The phrase
-- is the second half of a sentence beginning with the addon's name, so it reads
-- "Bagnon, your bags".
--
-- Ordered by what does the job here rather than alphabetically, because the
-- window prints the list as it stands and a player reading it is checking off
-- parts of their screen rather than looking a name up.
--
-- What is deliberately not on it is as much of the list as what is. An addon
-- this one reads is not replaced by it: Auctionator, RECrystallize and the
-- other scanners in Feeds/Auction.lua are where the price on a loot row comes
-- from, and telling somebody to turn one off would take a number out of this
-- addon's own tooltip. Nor is an addon that does something this one has no
-- answer for, however much of the screen it covers: WeakAuras, OPie and the
-- boss timers are all absent for that reason.
local REPLACED = {
	-- The bag window, the piles it sorts into and the free count along the
	-- bottom.
	{ addon = "Bagnon", draws = "your bags" },
	{ addon = "Combuctor", draws = "your bags" },
	{ addon = "ArkInventory", draws = "your bags" },
	{ addon = "AdiBags", draws = "your bags" },
	{ addon = "Baggins", draws = "your bags" },
	{ addon = "OneBag3", draws = "your bags" },
	{ addon = "Baganator", draws = "your bags" },
	{ addon = "Syndicator", draws = "your bags" },
	{ addon = "BetterBags", draws = "your bags" },
	{ addon = "Inventorian", draws = "your bags" },
	{ addon = "Sorted", draws = "your bags" },
	{ addon = "TBag", draws = "your bags" },
	{ addon = "BaudBag", draws = "your bags" },

	-- The action bars, the loadouts and the keys on them.
	{ addon = "Bartender4", draws = "your action bars" },
	{ addon = "Dominos", draws = "your action bars" },
	{ addon = "Bongos", draws = "your action bars" },
	{ addon = "Macaroon", draws = "your action bars" },

	-- The whole screen, the same as this one.
	{ addon = "ElvUI", draws = "the whole interface" },
	{ addon = "Tukui", draws = "the whole interface" },

	-- The player and target blocks, and the cast bar under them.
	{ addon = "XPerl", draws = "the player and target frames" },
	{ addon = "ZPerl", draws = "the player and target frames" },
	{ addon = "ShadowedUnitFrames", draws = "the player and target frames" },
	{ addon = "PitBull4", draws = "the player and target frames" },
	{ addon = "LunaUnitFrames", draws = "the player and target frames" },
	{ addon = "Quartz", draws = "the cast bar" },

	-- The party and raid blocks, ordered by role.
	{ addon = "Grid", draws = "the party and raid frames" },
	{ addon = "Grid2", draws = "the party and raid frames" },
	{ addon = "VuhDo", draws = "the party and raid frames" },
	{ addon = "HealBot", draws = "the party and raid frames" },

	-- The threat-coloured enemy bars.
	{ addon = "Plater", draws = "the enemy nameplates" },
	{ addon = "TidyPlates", draws = "the enemy nameplates" },
	{ addon = "ThreatPlates", draws = "the enemy nameplates" },
	{ addon = "NeatPlates", draws = "the enemy nameplates" },
	{ addon = "KuiNameplates", draws = "the enemy nameplates" },

	-- The damage, healing and threat meters, and the breakdown behind a row.
	{ addon = "Details", draws = "the damage meter" },
	{ addon = "Recount", draws = "the damage meter" },
	{ addon = "Skada", draws = "the damage meter" },
	{ addon = "DPSMate", draws = "the damage meter" },
	{ addon = "TinyDPS", draws = "the damage meter" },
	{ addon = "Omen", draws = "the threat meter" },
	{ addon = "KLHThreatMeter", draws = "the threat meter" },

	-- The numbers that fly off a blow.
	{ addon = "MikScrollingBattleText", draws = "the floating combat numbers" },
	{ addon = "Parrot", draws = "the floating combat numbers" },
	{ addon = "xCT_Plus", draws = "the floating combat numbers" },
	{ addon = "sct", draws = "the floating combat numbers" },

	-- The chat window, with a room per conversation.
	{ addon = "Prat-3.0", draws = "the chat window" },
	{ addon = "Chatter", draws = "the chat window" },
	{ addon = "WIM", draws = "the whisper windows" },

	-- The square minimap and the square that collects the buttons round it.
	{ addon = "SexyMap", draws = "the minimap" },
	{ addon = "MinimapButtonBag", draws = "the minimap buttons" },
	{ addon = "MBB", draws = "the minimap buttons" },

	-- The addon's own tooltip, on everything it draws and on the world.
	{ addon = "TipTac", draws = "the tooltips" },
	{ addon = "TinyTip", draws = "the tooltips" },

	-- The rest of the windows, one addon each.
	{ addon = "Narcissus", draws = "the character sheet" },
	{ addon = "Postal", draws = "the mail window" },
	{ addon = "AdventureGuideClassic", draws = "the dungeon log" },
	{ addon = "Clique", draws = "casting on what the mouse is over" },

	-- The bar of readouts along the top, which is a dozen of this addon's own
	-- numbers in one place: the clock, the purse, the bag count, the experience
	-- rail, the repair bill and the frame cost.
	{ addon = "Titan", draws = "the readouts along the top" },
}

-- The two worth keeping, and why each is not on the list above.
local KEEP = "Questie is worth keeping and this addon reads it: the turn-in map,"
	.. " the drop rates and the party's progress all come out of it. DialogueUI"
	.. " is worth keeping for the quest text. Nothing else here needs an addon."

local OPENING = "WarriorKit is not a set of parts. It draws the whole"
	.. " interface, and it draws it over the client's own: your bags, your bars,"
	.. " your frames, your meters, your chat, your map and your character sheet."

local ASKING = "These are running, and this addon already draws what they draw:"

local CLOSING = "Two of everything is what you have until you turn them off."

--------------------------------------------------------------------------
-- What is running
--------------------------------------------------------------------------

-- Held rather than asked again, because the answer cannot move. Every addon on
-- the list above is loaded at login or is not loaded at all: none of them is
-- load on demand, and the client has no way to start one mid-session.
local running

function Replaced.Running()
	if running then
		return running
	end
	running = {}
	for _, entry in ipairs(REPLACED) do
		if ns.AddOnRunning(entry.addon) then
			running[#running + 1] = entry
		end
	end
	return running
end

-- For the harness, which drives the client's addon list and then asks again.
-- Nothing in the addon calls it.
function Replaced.Forget()
	running = nil
end

-- The whole notice, or nil when there is nothing to say.
--
-- One string with the line breaks in it rather than a row per addon, because
-- the window draws it in one wrapped label and a stack of eleven labels would
-- be eleven frames to say what one says.
function Replaced.Words()
	local found = Replaced.Running()
	if #found == 0 then
		return nil
	end

	local lines = {}
	for index = 1, #found do
		lines[index] = ("%s, %s"):format(found[index].addon, found[index].draws)
	end

	return table.concat({
		OPENING, "", ASKING, "", table.concat(lines, "\n"), "", CLOSING, "", KEEP,
	}, "\n")
end

-- The status line and the reading on the page.
function Replaced.Describe()
	local found = Replaced.Running()
	if #found == 0 then
		return "nothing else running that this addon draws"
	end
	if #found == 1 then
		return found[1].addon .. " is running, and this addon draws " .. found[1].draws
	end
	return ("%d addons running that this addon draws"):format(#found)
end

-- Whether the player has been told.
function Replaced.Told()
	return ns.db.replacedTold == true
end

--------------------------------------------------------------------------
-- The notice
--
-- One window, built the first time there is anything to put in it and
-- repainted after that, which is the rule UI/Ask.lua's header gives: this
-- client cannot destroy a frame, so a window made per showing is a window
-- leaked per showing.
--
-- It is not a question and it has one button. There is nothing to refuse:
-- closing it any other way is the same as pressing the button, because the
-- flag is written when the notice goes up rather than when it comes down.
--------------------------------------------------------------------------

local WIDTH = 420

local window

local function Dismiss()
	if window then
		window:Hide()
	end
end

local function Build()
	if window then
		return window
	end

	window = UI.Window({
		name = "WarriorKitReplaced",
		title = "One interface, not two",
		width = WIDTH,
		height = M.title + M.footer + M.pad * 2 + M.row * 2,
		-- Over everything else the addon has up, and for the reason UI/Ask.lua
		-- is: a notice that opens behind the screen it is about is a notice
		-- nobody reads.
		strata = "FULLSCREEN_DIALOG",
	})

	window.words = UI.Label(window.content, M.font, C.text, "LEFT", UI.FLAT)
	window.words:SetPoint("TOPLEFT", M.pad, -M.pad)
	window.words:SetWidth(WIDTH - M.pad * 2)
	UI.Wrap(window.words, true)
	window.words:SetSpacing(2)

	window.accept = UI.Button(window.footer, {
		label = "got it",
		width = 92,
		onClick = Dismiss,
	})
	window.accept:SetPoint("RIGHT", 0, 0)

	return window
end

-- Put it up, and answer what it says so a caller can report it without keeping
-- its own copy. Nil when there is nothing running that this addon draws, which
-- is the state most installs are in and the state the login path checks for.
function Replaced.Show()
	local words = Replaced.Words()
	if not words then
		return nil
	end

	Build()
	ns.db.replacedTold = true

	window.words:SetText(words)
	window:Resize(WIDTH, M.title + M.footer + M.pad * 2
		+ UI.TextHeight(window.words, M.row))
	window:Show()
	return words
end

-- The one login it is said on. Every login after this one reads the flag and
-- does nothing at all, which is the whole of what the flag is for.
local function Login()
	if Replaced.Told() then
		return
	end
	Replaced.Show()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", Login)

--------------------------------------------------------------------------

ns.Register({
	name = "other addons",
	order = 38,

	defaults = {
		-- Whether the notice has been shown. Written the moment it goes up, so
		-- a player who closes it with Escape is not told twice.
		replacedTold = false,
	},

	-- The way back to a notice that is said once. It puts the window up rather
	-- than printing the list, because the list is nine lines on a bad install
	-- and nine lines in the chat window is where a sentence goes to be missed.
	-- What it prints is the one line the status word prints, so typing it on a
	-- clean install answers rather than doing nothing at all.
	words = {
		replaces = function()
			Replaced.Show()
			ns.Print(Replaced.Describe() .. ".")
		end,
	},

	help = {
		"replaces, what else is running that this addon already draws",
	},

	status = function()
		return Replaced.Describe()
	end,

	panel = function(ui)
		ui.Section("Other addons", "Under the hood")
		ui.Lede("This addon draws the whole interface. Anything else drawing one"
			.. " of the same windows draws it twice, and the notice at login says"
			.. " which.")
		ui.Reading("running", Replaced.Describe)
		ui.Action(function() return "show the notice again" end, Replaced.Show,
			function() return Replaced.Words() ~= nil end)
		ui.Hint("Questie and DialogueUI are the two worth keeping. This addon"
			.. " reads Questie for the turn-in maps and the drop rates.")
	end,
})
