local ADDON, ns = ...

-- The slash handler. It knows the words that belong to the addon as a whole and
-- nothing else. Every feature word is looked up in the registry, so this file
-- does not change when a feature gains a command.

local Command = {}
ns.Command = Command

-- The words Core answers itself. A feature that claimed one of these used to
-- lose in silence, because the dispatch below returned before the registry was
-- ever consulted: the interface part registered "ui" and every /wk ui command
-- opened the settings panel instead, which is how the Edit Mode capture spent a
-- release doing nothing. Claiming a reserved word is an error now.
local PANEL_WORDS = { panel = true, options = true, config = true }

local RESERVED = {
	status = true, help = true, lock = true, unlock = true, reset = true,
	defaults = true,
}
for word in pairs(PANEL_WORDS) do
	RESERVED[word] = true
end

-- Built at PLAYER_LOGIN, so both assertions below are a login error rather than
-- something that waits for the first command to be typed. Rebuilt never:
-- features register at file load and the set cannot change after.
local words

local function BuildWords()
	words = {}
	for _, feature in ipairs(ns.features) do
		for word, handler in pairs(feature.words or {}) do
			assert(not RESERVED[word],
				("%s claims the slash word %q, which Core answers itself")
					:format(feature.name, word))
			assert(words[word] == nil,
				("two features both claim the slash word %q"):format(word))
			words[word] = handler
		end
	end
end

local function Status()
	for _, feature in ipairs(ns.features) do
		if feature.status then
			ns.Print(feature.name .. ": " .. feature.status())
		end
	end
	ns.Print("frames " .. (ns.db.locked and "locked" or "unlocked") .. ".")
end

-- Every setting back to what the addon ships with. The one word in here that
-- cannot be undone, so it is the one that asks twice: on its own it reports
-- what would move, and only `defaults yes` writes.
--
-- ns.RestoreDefaults is where the argument for it lives, along with the list of
-- what it leaves alone and why. This is the typed half of the same thing the
-- Settings page draws two presses of.
local function Defaults(arg)
	local moved = ns.DefaultsMoved()
	if moved == 0 then
		ns.Print("every setting is already what the addon ships with.")
		return
	end

	local plural = moved == 1 and "" or "s"
	if arg:match("^(%S*)"):lower() ~= "yes" then
		ns.Print(("%d setting%s %s not what the addon ships with.")
			:format(moved, plural, moved == 1 and "is" or "are"))
		ns.Print("  /wk defaults yes puts them back and reloads the interface.")
		ns.Print("  Your groups, your mail favourites, your muted errors, the"
			.. " flasks you track and the gold ledger are records rather than"
			.. " settings and are left alone.")
		return
	end

	ns.Print(("%d setting%s back to the shipped answer. Reloading.")
		:format(ns.RestoreDefaults(), plural))
	ReloadUI()
end

local function Help()
	ns.Print("/wk on its own opens the panel. Everything in it has a command too:")
	ns.Print("  status, help, lock, unlock, reset, defaults")
	for _, feature in ipairs(ns.features) do
		for _, line in ipairs(feature.help or {}) do
			ns.Print("  " .. line)
		end
	end
end

local function Lock(locked)
	ns.db.locked = locked
	ns.Each("lock")
	ns.Print("frames " .. (locked and "locked." or "unlocked, drag them where you want them."))
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	BuildWords()
end)

SLASH_WARRIORKIT1 = "/wk"
SLASH_WARRIORKIT2 = "/warriorkit"
SlashCmdList.WARRIORKIT = function(input)
	if not words then
		BuildWords()
	end

	local rawCmd, rawArg = input:match("^%s*(%S*)%s*(.-)%s*$")
	local cmd, arg = rawCmd:lower(), rawArg:lower()

	if cmd == "" or PANEL_WORDS[cmd] then
		ns.Options.Toggle()
		return
	elseif cmd == "status" then
		Status()
		return
	elseif cmd == "help" then
		Help()
		return
	elseif cmd == "lock" then
		Lock(true)
	elseif cmd == "unlock" then
		Lock(false)
	elseif cmd == "reset" then
		ns.Each("reset")
		ns.Print("frames reset.")
	elseif cmd == "defaults" then
		Defaults(rawArg)
	elseif words[cmd] then
		words[cmd](arg, rawArg)
	else
		Help()
		Status()
	end

	-- Any command can move a setting the panel is showing.
	ns.Options.Refresh()
end

-- Shared by every feature that takes an on/off word, so "off" means off and
-- anything else means on, in one place rather than four.
function Command.Toggle(arg)
	return arg ~= "off"
end

-- Shared number parsing, so the range message reads the same everywhere.
--
-- Whole numbers only, and refused rather than rounded. Every caller is a pixel
-- count, a bar count or a zoom step, and all three sit on the pixel grid in
-- UI/Pixel.lua where a fraction puts every edge inside the frame onto a half
-- pixel. Rounding a typo into something that nearly works is the kind of help
-- that gets found six months later as a soft edge nobody can explain.
function Command.Number(value, low, high, what)
	local number = tonumber(value)
	if number and number == math.floor(number) and number >= low and number <= high then
		return number
	end
	ns.Print(("%s takes a whole number between %d and %d."):format(what, low, high))
	return nil
end

-- The same refusal on a coarser ruler, for the one setting that is not a count
-- of anything: the UI size, which runs in quarters because a quarter is as fine
-- as a size control can be before the stops stop meaning anything.
--
-- Refused rather than rounded, for the reason above. The stops the panel offers
-- and the stops a macro can reach have to be the same set, or /wk uisize 1.3
-- silently becomes 1.25 and the next person to read the macro believes the
-- window is at 1.3.
function Command.Step(value, low, high, step, what)
	local number = tonumber(value)
	if number and number >= low and number <= high then
		local steps = (number - low) / step
		if math.abs(steps - math.floor(steps + 0.5)) < 1e-6 then
			return low + math.floor(steps + 0.5) * step
		end
	end
	ns.Print(("%s takes a number between %s and %s in steps of %s.")
		:format(what, tostring(low), tostring(high), tostring(step)))
	return nil
end

--------------------------------------------------------------------------
-- A word table, and the runner that walks it.
--
-- Thirty-odd branches in this addon were the same four steps: parse the value,
-- write `ns.db.<key>`, call the module's Apply, print a sentence. Written by
-- hand they read as a chain of ifs one word long each, and two of them sat on
-- the shape allow-list as "a slash dispatcher, one branch per word". Written as
-- a table they are data: the four steps live here once, and what a word decides
-- for itself is the closure it carries rather than another branch in a hundred
-- line function.
--
-- An entry is `{ "<word>", <kind>, key = "<db key>", say = function(new) end }`
-- and the kind is one of four:
--
--   number = { low, high }        a whole number in range, refused outside it
--   step   = { low, high, step }  the same on a coarser ruler
--   toggle = true                 on unless the value is "off"
--   choice = { "one", "two" }     one of a named set, refused with the set
--
-- A range the owning file already computes is written as a function returning
-- those same numbers, so no range is typed here that is written down there.
--
-- Anything none of the four describes carries `run` instead and stays a
-- function taking the value. That is the escape hatch and it is meant to be
-- used: a word that adds a spell to a list is not a setting, and dressing it as
-- one buys nothing.
--
-- `say` receives what was written and returns the sentence, or up to three of
-- them. Returning nothing says nothing.
--
-- The table itself carries `name`, which the range message reads with; `apply`,
-- which every entry that does not name its own uses, and which `apply = false`
-- on an entry says is not wanted for that word; `show`, what the bare word
-- prints; `otherwise`, the on|off toggle every one of these dispatchers ends
-- in; and `finally`, for the one that redraws after each word whichever it was.
--
-- `otherwise` is an entry when the unknown word is simply the on|off value, and
-- a function taking the word and the rest of the line when the part has more
-- lists to look the word up in first.

local function What(spec, entry)
	return entry.what or (spec.name .. " " .. entry[1])
end

local function Range(entry, which)
	local range = entry[which]
	if type(range) == "function" then
		return range()
	end
	return range[1], range[2], range[3]
end

-- "auto, plates or list", so the refusal names the set rather than the word
-- that was not in it.
local function Listed(set)
	if #set == 1 then
		return set[1]
	end
	return table.concat(set, ", ", 1, #set - 1) .. " or " .. set[#set]
end

local function Chosen(spec, entry, value)
	for _, word in ipairs(entry.choice) do
		if value == word then
			return value
		end
	end
	ns.Print(("%s takes %s."):format(What(spec, entry), Listed(entry.choice)))
	return nil
end

local function Said(say, new)
	if not say then
		return
	end
	local first, second, third = say(new)
	if first then ns.Print(first) end
	if second then ns.Print(second) end
	if third then ns.Print(third) end
end

local function Parse(spec, entry, value)
	if entry.toggle then
		return Command.Toggle(value)
	end
	if entry.choice then
		return Chosen(spec, entry, value)
	end
	if entry.step then
		local low, high, step = Range(entry, "step")
		return Command.Step(value, low, high, step, What(spec, entry))
	end
	local low, high = Range(entry, "number")
	return Command.Number(value, low, high, What(spec, entry))
end

-- Nothing is written when the value was refused, which is the half of a
-- dispatcher that is easy to get wrong by hand: printing the range and setting
-- the number anyway.
local function Take(spec, entry, value, rawValue)
	if entry.run then
		entry.run(value, rawValue)
		return
	end

	local new = Parse(spec, entry, value)
	if new == nil then
		return
	end

	if entry.key then
		ns.db[entry.key] = new
	end
	if entry.set then
		entry.set(new)
	end

	local apply = entry.apply
	if apply == nil then
		apply = spec.apply
	end
	if apply then
		apply(new)
	end
	Said(entry.say, new)
end

-- The zoom word, which seven parts have and all seven wrote out: the same
-- range off `ns.UI`, the same refusal message with their own word in front of
-- it, and one sentence with the number in it. The sentence is what differs, so
-- the sentence is the argument.
function Command.Zoom(key, sentence)
	return { "zoom", key = key,
		number = function() return ns.UI.ZOOM_LOW, ns.UI.ZOOM_HIGH end,
		say = function(zoom) return sentence:format(zoom) end }
end

function Command.Word(spec)
	local by = {}
	for _, entry in ipairs(spec) do
		assert(by[entry[1]] == nil,
			("%s claims the word %q twice"):format(spec.name, entry[1]))
		by[entry[1]] = entry
	end

	return function(arg, rawArg)
		local option, value = arg:match("^(%S*)%s*(.-)$")
		local _, rawValue = (rawArg or arg):match("^(%S*)%s*(.-)$")

		if spec.show and (option == "" or option == "show") then
			Said(spec.show)
		elseif by[option] then
			Take(spec, by[option], value, rawValue)
		elseif type(spec.otherwise) == "function" then
			spec.otherwise(option, value, rawValue)
		elseif spec.otherwise then
			Take(spec, spec.otherwise, option, option)
		end

		if spec.finally then
			spec.finally()
		end
	end
end
