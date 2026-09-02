-- What a word table does with a word
--
-- ns.Command.Word is one runner behind about a hundred slash words, and every
-- one of them used to be four lines written out by hand: parse the value, write
-- ns.db.<key>, call the module's Apply, print a sentence. One runner is worth
-- having and is also one place for all hundred of them to go wrong at once, so
-- the four steps are asserted here rather than trusted.
--
-- The half that matters is the refusal. A dispatcher that prints the range and
-- writes the number anyway looks right from the outside: the message is there,
-- the setting moved, and nobody reads the number back. Every kind the runner
-- knows is driven twice here, once with a value it takes and once with one it
-- does not, and the second is checked on the setting rather than on the words.
--
-- Nothing here is a feature. The words are picked because each is the plainest
-- example of one kind the runner parses, and what is asserted is the runner's
-- behaviour, not the swing timer's.

local H = ...
local ns, check = H.ns, H.check

local slash = _G.SlashCmdList.WARRIORKIT

local chat = _G.DEFAULT_CHAT_FRAME.AddMessage
local heard = {}
_G.DEFAULT_CHAT_FRAME.AddMessage = function(_, text)
	heard[#heard + 1] = tostring(text)
end

local function say(input)
	heard = {}
	slash(input)
end

local function said(what)
	for index = 1, #heard do
		if heard[index]:find(what, 1, true) then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- A number, taken and refused
--
-- The swing bars, because their range is two constants in their own file and
-- neither end of it is a number the client can move.
----------------------------------------------------------------------

say("swing width 200")
check(ns.db.swingWidth == 200, "a width in range was written")
check(said("200 pixels wide"), "and said, in the sentence the entry carries")

say("swing width 9000")
check(ns.db.swingWidth == 200, "a width out of range left the setting alone")
check(said("swing width takes a whole number between"),
	"and refused by naming the word and the range")

say("swing width 200.5")
check(ns.db.swingWidth == 200, "a fractional width was refused rather than rounded")

say("swing width")
check(ns.db.swingWidth == 200, "the word with no value at all wrote nothing")

----------------------------------------------------------------------
-- A switch, and the word that is not one
----------------------------------------------------------------------

say("swing off")
check(ns.db.swing == false, "the bare word reached the on|off entry")
check(said("swing timer off"), "and said which way it went")

say("swing on")
check(ns.db.swing == true, "and back on again")

-- Not a word in the table, so it is the value of the bare switch rather than a
-- refusal. This is the fall-through every dispatcher in the addon has, and the
-- one shape a table makes easy to lose.
say("swing sideways")
check(ns.db.swing == true, "an unknown word is read as the on|off value, not refused")

----------------------------------------------------------------------
-- A named set
--
-- The enemy bars' mode, which is three words and nothing else. The refusal has
-- to name the set: a message that says only "that is not a mode" is a message
-- you cannot act on without reading the source.
----------------------------------------------------------------------

local mode = ns.db.barsMode

say("bars mode list")
check(ns.db.barsMode == "list", "a word in the set was written")

say("bars mode sideways")
check(ns.db.barsMode == "list", "a word outside the set left the setting alone")
check(said("bars mode takes auto, plates or list."),
	"and refused by listing every word the set holds")

slash("bars mode " .. mode)

----------------------------------------------------------------------
-- A range the owning file computes
--
-- The aura square reads its ends off UnitFrames/Auras.lua rather than carrying
-- a copy, so this is the assertion that a range written as a function is called
-- at the command rather than read once at load.
----------------------------------------------------------------------

local low, high = ns.FrameAuras.SizeRange()

say("skin aura " .. low)
check(ns.db.skinAuraSize == low, "the low end of a computed range was taken")

say("skin aura " .. (high + 1))
check(ns.db.skinAuraSize == low, "one past the high end was refused")
check(said(("between %d and %d"):format(low, high)),
	"and the refusal quoted the range the owning file answered with")

----------------------------------------------------------------------
-- The two words that are not settings
--
-- `show` answers and writes nothing, and a `run` entry is handed the rest of
-- the line rather than a parsed value.
----------------------------------------------------------------------

local width = ns.db.swingWidth

say("swing show")
check(ns.db.swingWidth == width, "show wrote nothing")
check(said("swing timer"), "and answered with the part's own description")

say("cast reset")
check(said("back under the swing timer"), "a run entry ran")

_G.DEFAULT_CHAT_FRAME.AddMessage = chat

print(("words  %d px wide refused at 9000, %s mode, aura %d to %d, %d lines heard")
	:format(ns.db.swingWidth, ns.db.barsMode, low, high, #heard))
