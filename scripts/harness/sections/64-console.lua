-- The console
--
-- One claim: a chunk of Lua handed to the runner comes back as the lines it
-- printed, in order, with print put back afterwards whether the chunk ran,
-- raised or never parsed. Everything else on the page is a button that calls
-- the runner, and 16-options-window.lua already walks the page.
--
-- **print is borrowed, and the borrow has to end.** The runner swaps the
-- global out for the length of the chunk. A chunk that raises is the case
-- where a swap written naively stays swapped, and every print in the client
-- after that would vanish into a table nobody reads. So the raise is the case
-- checked hardest here.

local H = ...
local ns, check = H.ns, H.check
local Console = ns.Console

local held = _G.print

local lines, ok = Console.Run('print("a", 1) print("b")')
check(ok and #lines == 2 and lines[1] == "a  1" and lines[2] == "b",
	"two prints came back as two lines, the words two spaces apart")
check(_G.print == held, "print is the client's own again after a run")

lines, ok = Console.Run("return 2 + 2")
check(ok and lines[1] == "returned  4", "what a chunk returns is a line")

lines, ok = Console.Run("local x = 1")
check(ok and lines[1] == "ran, and printed nothing", "a silent chunk says it was silent")

lines, ok = Console.Run("nonsense(")
check(not ok and lines[1]:find("error", 1, true) == 1,
	"a chunk that does not parse is an error line rather than a raise")

lines, ok = Console.Run('print("before") error("boom")')
check(not ok and lines[1] == "before" and lines[2]:find("boom", 1, true) ~= nil,
	"a chunk that raises keeps what it printed first and ends on the message")
check(_G.print == held, "and print is the client's own again after the raise")

----------------------------------------------------------------------
-- The probe, and the word
----------------------------------------------------------------------

local probe = Console.Probe("xp")
check(probe ~= nil, "there is a probe called xp")
lines, ok = Console.Run(probe.code)
local level, cap
for index = 1, #lines do
	if lines[index]:find("^level  62") then
		level = true
	elseif lines[index]:find("^GetMaxPlayerLevel  70") then
		cap = true
	end
end
check(ok and level and cap, "the xp probe names the level and the cap the client answers")

-- Every probe runs on the stub without raising. A probe is written against the
-- client and read back on it, and this is the one place a typo in one is seen
-- before somebody presses the button.
for index = 1, #Console.PROBES do
	local each, ran = Console.Run(Console.PROBES[index].code)
	check(ran, ("the probe %s raised: %s"):format(Console.PROBES[index].name, each[#each]))
end

local chat = _G.DEFAULT_CHAT_FRAME.AddMessage
local heard = {}
_G.DEFAULT_CHAT_FRAME.AddMessage = function(_, text)
	heard[#heard + 1] = tostring(text)
end
local function say(input)
	heard = {}
	_G.SlashCmdList.WARRIORKIT(input)
end
local function said(what)
	for index = 1, #heard do
		if heard[index]:find(what, 1, true) then
			return true
		end
	end
	return false
end

say("console xp")
check(said("level  62"), "console xp prints the probe's lines to chat")
say("console run print(7 * 6)")
check(said("42"), "console run takes the line raw and prints what it printed")
say("console run")
check(said("takes a line of Lua"), "console run with nothing after it says so")
say("console nothing")
check(said("no probe called"), "a word that is not run and not a probe is refused by name")
_G.DEFAULT_CHAT_FRAME.AddMessage = chat

check(ns.Options.Find("run it") >= 1, "the run button is findable by its label")
check(ns.Options.Find("the lines to run") >= 1, "the box is findable by its label")

print(("console %d probes, a raise leaves print alone, %d lines from the xp probe")
	:format(#Console.PROBES, #lines))
