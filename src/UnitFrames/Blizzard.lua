local ADDON, ns = ...

local Blizz = {}
ns.BlizzHide = Blizz

--------------------------------------------------------------------------
-- The client's own frames, one switch each
--
-- Everything in here answers one question: this addon draws X, so should the
-- client's X still be on the screen? Every answer is a switch with the same
-- shape and the same default, and the whole point is that there is nothing
-- clever behind any of them. A player who can see two copies of one aura
-- should be able to find the line that says "hide Blizzard's buffs" and press
-- it, without knowing that the skin is on, that a sweep exists, or that the
-- two clients this addon runs on disagree about where a debuff lives.
--
-- It used to be one setting that meant something different depending on what
-- the skin was doing. That was the bug: a switch whose effect you cannot
-- predict from its label is not a switch, and the honest fix was more of them
-- rather than a cleverer one.
--
-- Two handles take a row off the screen and this file holds one of them. A
-- frame goes down here; the buttons inside a frame nobody can hide go down one
-- name at a time in UnitFrames/Auras.lua, off the same switch. The target's
-- rows are the second kind, because every icon in them is a child of
-- TargetFrame and nothing else, and hiding TargetFrame is hiding the target.
--------------------------------------------------------------------------

-- Every switch, in the order the panel and `/wk hide` walk them.
--
--   key    the setting, and every one of them is a plain boolean that means
--          exactly what its label says
--   word   what `/wk hide` calls it
--   label  the panel's line, and the sentence the slash word prints back
--   hint   the one thing about this switch a label cannot hold, where there is
--          one. Three of the five have a catch and the other two do not, and a
--          line of reassurance under a switch that has nothing to warn about
--          is how a page teaches you to stop reading the hints
local SWITCHES = {
	{ key = "hideBlizzBuffs", word = "buffs", label = "Blizzard's buffs",
		hint = "Right click to cancel a buff goes with them. Cancelling one is a call an addon is not allowed to make." },
	{ key = "hideBlizzDebuffs", word = "debuffs", label = "Blizzard's debuffs" },
	{ key = "hideBlizzTargetAuras", word = "target",
		label = "Blizzard's target buffs and debuffs",
		hint = "These have no frame of their own, so this one needs the target frame skinned to reach them." },
	{ key = "hideBlizzTargetCast", word = "cast",
		label = "Blizzard's target cast bar",
		hint = "The cast is drawn on the enemy bar instead, in the second chamber of the box." },
	{ key = "hideBlizzPlayerCast", word = "playercast",
		label = "Blizzard's own cast bar",
		hint = "Read this one with our cast bar switch. Both off is the one combination that leaves you no cast bar at all." },
}

-- What each switch takes down, by name, and what it takes to take it down.
--
-- `needs` is a list rather than a single key because one frame on the older
-- clients holds both of your rows. BuffFrame is your buffs and your debuffs
-- together on 2.5.6, so it may only go down when both switches are on;
-- whichever of the two is on alone is served by the sweep in
-- UnitFrames/Auras.lua, which works a button at a time and can tell them apart.
--
-- DebuffFrame is the newer clients splitting that frame in two. It is not on
-- 2.5.6 at all, and a name this client does not carry costs one lookup against
-- nil, so both shapes sit in the list rather than the file asking which one is
-- running. That split is what put a debuff back on the screen under a row
-- already drawing it: hiding BuffFrame took the buffs and left the debuffs
-- exactly where they were.
--
-- The target's auras name no frame here on purpose. Every icon in those two
-- rows is a child of TargetFrame, so there is nothing between the buttons and
-- the frame you are targeting with, and the sweep is the only handle.
--
-- Your own cast bar is named twice for DebuffFrame's reason. 2.5.6 calls it
-- CastingBarFrame and the clients this Edit Mode was backported from call it
-- PlayerCastingBarFrame, and neither name is worth a branch when an absent one
-- costs a lookup against nil.
local FRAMES = {
	{ name = "BuffFrame", needs = { "hideBlizzBuffs", "hideBlizzDebuffs" } },
	{ name = "TemporaryEnchantFrame", needs = { "hideBlizzBuffs" } },
	{ name = "DebuffFrame", needs = { "hideBlizzDebuffs" } },
	{ name = "TargetFrameSpellBar", needs = { "hideBlizzTargetCast" } },
	{ name = "CastingBarFrame", needs = { "hideBlizzPlayerCast" } },
	{ name = "PlayerCastingBarFrame", needs = { "hideBlizzPlayerCast" } },
}

local pending = false

local function Asked(needs)
	for index = 1, #needs do
		if not ns.db[needs[index]] then
			return false
		end
	end
	return true
end

-- Every frame put where its switches say it should be. False where combat
-- refused, which the retry below picks up: TargetFrameSpellBar is a child of a
-- secure unit button and is the one frame in the list that can say no.
function Blizz.Apply()
	-- Tolerates being called before the saved variables exist, like every other
	-- Apply in the addon.
	if not ns.db then
		return
	end

	local complete = true
	for index = 1, #FRAMES do
		local entry = FRAMES[index]
		local frame = _G[entry.name]
		if frame then
			local done
			if Asked(entry.needs) then
				done = ns.Strip(frame)
			else
				done = ns.Unstrip(frame)
			end
			complete = complete and done
		end
	end
	pending = not complete
end

-- The switches, for the panel and the slash word, so neither writes the list
-- out again and the two cannot drift.
function Blizz.Switches()
	return SWITCHES
end

-- The switch one word names, or nothing.
function Blizz.Find(word)
	for index = 1, #SWITCHES do
		if SWITCHES[index].word == word then
			return SWITCHES[index]
		end
	end
	return nil
end

-- How many of the names above this client actually carries. Zero is the answer
-- worth seeing: it says the client calls these frames something else, which is
-- a different thing from a switch that did not work.
function Blizz.Found()
	local found = 0
	for index = 1, #FRAMES do
		if _G[FRAMES[index].name] then
			found = found + 1
		end
	end
	return found, #FRAMES
end

function Blizz.Describe()
	local hidden = {}
	for index = 1, #SWITCHES do
		local switch = SWITCHES[index]
		if ns.db[switch.key] then
			hidden[#hidden + 1] = switch.word
		end
	end
	local found, of = Blizz.Found()
	if #hidden == 0 then
		return ("nothing of the client's hidden, %d of %d frames on this client")
			:format(found, of)
	end
	return ("hidden: %s; %d of %d frames on this client")
		:format(table.concat(hidden, ", "), found, of)
end

-- PLAYER_REGEN_ENABLED is the retry every strip in the addon uses. It costs one
-- comparison against false when combat drops and nothing the rest of the time.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" or pending then
		Blizz.Apply()
	end
end)
