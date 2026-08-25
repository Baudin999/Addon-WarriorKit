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

local function Help()
	ns.Print("/wk on its own opens the panel. Everything in it has a command too:")
	ns.Print("  status, help, lock, unlock, reset")
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
