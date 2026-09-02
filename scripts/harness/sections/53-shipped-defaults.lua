-- Back to the shipped defaults
--
-- ApplyDefaults fills in a setting that is missing and leaves one that is
-- present alone, which is right for a setting arriving in an update and wrong
-- for a release that moves a default. The player who has run the addon longest
-- is the one whose account file has a number written against every key, so it
-- is the one that never sees a new layout. This is the way back, and it is the
-- only control in the addon that throws away every setting at once.
--
-- What is asserted, in the order it is written:
--
--   That a default handed out for writing is a table nobody else is holding.
--   Eight resets used to write an anchor out longhand for exactly this reason
--   and every one of the eight had gone stale; DefaultCopy is what replaced
--   them, so the aliasing it exists to prevent is checked both ways, on the
--   copy itself and on a restore that follows a drag.
--
--   That every feature's own reset hook writes the registered default and not
--   a literal beside it. Run from a clean slate, `/wk reset` must move nothing
--   at all, and the moment any reset carries its own copy of a number this
--   fails with that part named by the count.
--
--   That the count is the count. Move settings, and DefaultsMoved says how
--   many; restore, and it says none and returns the same figure.
--
--   That the records survive. Every key in Core's KEPT list is something the
--   addon wrote down rather than something anybody chose, and a reset that
--   deleted a gold ledger or a group would be a reset nobody presses twice.
--
--   And both surfaces that reach it. The typed word reports on its own and
--   only writes on `yes`; the button on the Settings page arms on the first
--   press, does it on the second, and disarms when the window is shut. Neither
--   applies anything itself, so the run that proves the work happened is a
--   count of how many times the interface was asked to build again.

local H = ...
local ns, check, state = H.ns, H.check, H.state
local window = H.carry.window

----------------------------------------------------------------------
-- A default handed out for writing
----------------------------------------------------------------------

local shipped = ns.DefaultFor("swingPoint")
local copy = ns.DefaultCopy("swingPoint")
check(copy ~= shipped, "DefaultCopy handed back the registered table itself")
check(#copy == #shipped and copy[5] == shipped[5],
	"DefaultCopy handed back a table that is not the default")
copy[5] = 12345
check(shipped[5] ~= 12345, "writing through a copy reached the registered default")

check(ns.DefaultCopy("swingWidth") == ns.DefaultFor("swingWidth"),
	"DefaultCopy changed a number on the way through")
check(ns.DefaultCopy("nothing registers this") == nil,
	"DefaultCopy invented a default for a key nobody registered")

----------------------------------------------------------------------
-- Every reset writes the registered default
----------------------------------------------------------------------

-- From a clean slate, because the sections above have moved a great deal and
-- what is being asked here is about the reset hooks rather than about them.
ns.RestoreDefaults()
check(ns.DefaultsMoved() == 0,
	("a restore left %d setting off its default"):format(ns.DefaultsMoved()))

-- The gate the eight longhand anchors would have failed. A reset hook that
-- carries its own copy of a number writes a value that is not the registered
-- one, and from a clean slate that is the only way this count can move.
ns.Each("reset")
check(ns.DefaultsMoved() == 0,
	("a reset moved %d setting off the value it is registered with, so a reset"
		.. " hook is writing a literal of its own"):format(ns.DefaultsMoved()))

----------------------------------------------------------------------
-- The count
----------------------------------------------------------------------

ns.db.swingWidth = 200
ns.db.panelZoom = 2
ns.db.markBinds.skull = "F9"
check(ns.DefaultsMoved() == 3,
	("three settings moved and DefaultsMoved says %d"):format(ns.DefaultsMoved()))

-- A table compared shallowly in both directions, because a key added to one is
-- as much a change as a key whose value moved.
ns.db.markBinds.star = "F9"
check(ns.DefaultsMoved() == 3,
	"a mark bound that the default does not carry read as a fourth change")
ns.db.markBinds.star = nil

check(ns.RestoreDefaults() == 3,
	"the restore did not report the three it put back")
check(ns.DefaultsMoved() == 0, "the restore left something off its default")
check(ns.db.markBinds.skull == ns.DefaultFor("markBinds").skull,
	"the restore left a mark on the key it was dragged to")
check(ns.RestoreDefaults() == 0, "a second restore claimed to write something")

-- The whole reason DefaultCopy exists, end to end: restore, drag the anchor
-- the restore just wrote, and restore again. With the registered table handed
-- out rather than a copy, the drag reaches the default and the second restore
-- puts back wherever it was dragged to.
ns.db.swingPoint[5] = -400
check(ns.DefaultFor("swingPoint")[5] ~= -400,
	"a drag after a restore wrote through to the registered default")
ns.RestoreDefaults()
check(ns.db.swingPoint[5] == ns.DefaultFor("swingPoint")[5],
	("the second restore put the bars at %s, and the addon ships them at %s")
		:format(tostring(ns.db.swingPoint[5]), tostring(ns.DefaultFor("swingPoint")[5])))

----------------------------------------------------------------------
-- What it leaves alone
----------------------------------------------------------------------

-- One of each kind in Core's KEPT list: a ledger, a list you curated, a note
-- of what the client held before the addon arrived, and the diagnostic the
-- chat window has to keep across a reload.
ns.db.purse["Nobody-Nowhere"] = 4200
ns.db.mailFavourites[#ns.db.mailFavourites + 1] = "someone"
ns.db.errorMuted.ERR_MADE_UP = "a message"
ns.db.buffExtra[#ns.db.buffExtra + 1] = 17038
ns.db.platesDistancePrior = "41"
ns.db.chargeKeyDisplaced = "MULTIACTIONBAR3BUTTON11"
ns.db.chatWhy = "the last build said this"

local kept = ns.RestoreDefaults()
check(kept == 0, ("a record read as %d moved setting(s)"):format(kept))
check(ns.db.purse["Nobody-Nowhere"] == 4200, "the reset emptied the gold ledger")
check(ns.db.mailFavourites[#ns.db.mailFavourites] == "someone",
	"the reset dropped a name off the mail favourites")
check(ns.db.errorMuted.ERR_MADE_UP == "a message", "the reset unmuted an error")
check(ns.db.buffExtra[#ns.db.buffExtra] == 17038, "the reset dropped a tracked flask")
check(ns.db.platesDistancePrior == "41",
	"the reset lost the note of what the nameplate CVar held")
check(ns.db.chargeKeyDisplaced == "MULTIACTIONBAR3BUTTON11",
	"the reset lost the note of what the charge key displaced")
check(ns.db.chatWhy == "the last build said this",
	"the reset lost what the last chat window build reported")

----------------------------------------------------------------------
-- The typed word
----------------------------------------------------------------------

local reloads = state.reloads

SlashCmdList.WARRIORKIT("defaults")
check(state.reloads == reloads, "the word on its own reloaded the interface")

ns.db.swingWidth = 200
SlashCmdList.WARRIORKIT("defaults")
check(ns.db.swingWidth == 200, "the word on its own wrote a setting back")
check(state.reloads == reloads, "the word on its own reloaded the interface")

SlashCmdList.WARRIORKIT("defaults YES")
check(ns.db.swingWidth == ns.DefaultFor("swingWidth"),
	"defaults yes did not put the setting back")
check(state.reloads == reloads + 1,
	("defaults yes asked for %d reloads, expected one"):format(state.reloads - reloads))

-- Nothing to do is said rather than done, because a reload is the most
-- expensive thing in the addon and there is no reason to pay it twice.
SlashCmdList.WARRIORKIT("defaults yes")
check(state.reloads == reloads + 1,
	"defaults yes reloaded with every setting already at its default")

----------------------------------------------------------------------
-- The button
----------------------------------------------------------------------

if window then
	ns.Options.Show()

	local button
	for _, entry in ipairs(window.indexed) do
		if entry.section.title == "Shipped defaults" and entry.widget.text then
			button = entry.widget
		end
	end
	check(button ~= nil, "the Settings page has no shipped defaults button")

	if button then
		local function press()
			button:GetScript("OnClick")(button)
		end

		-- Nothing moved, so the label says so rather than offering to do
		-- nothing, and a press is not the first half of anything.
		ns.Options.Refresh()
		check(button.text:GetText() == "already at the shipped answers",
			("with nothing moved the button reads %q"):format(tostring(button.text:GetText())))
		press()
		check(state.reloads == reloads + 1, "the button reloaded with nothing to put back")

		ns.db.swingWidth = 200
		ns.db.panelZoom = 2
		ns.Options.Refresh()
		check(button.text:GetText() == "back to the shipped answers",
			("with two settings moved the button reads %q"):format(tostring(button.text:GetText())))

		-- Armed, not done. This is the assertion the whole two press shape is
		-- for: the press that finds the button under a cursor that was reading
		-- something else must not be the press that writes.
		press()
		check(ns.db.swingWidth == 200, "the first press wrote the settings back")
		check(state.reloads == reloads + 1, "the first press reloaded the interface")
		check(button.text:GetText() == "press again to put them back and reload",
			("armed, the button reads %q"):format(tostring(button.text:GetText())))

		press()
		check(ns.db.swingWidth == ns.DefaultFor("swingWidth"),
			"the second press did not put the settings back")
		check(state.reloads == reloads + 2,
			("the second press asked for %d reloads, expected one")
				:format(state.reloads - reloads - 1))

		-- And the arm does not outlive the window it was made in.
		ns.db.swingWidth = 200
		ns.Options.Refresh()
		press()
		check(button.text:GetText() == "press again to put them back and reload",
			"the button did not arm")
		ns.Options.Hide()
		ns.Options.Show()
		ns.Options.Refresh()
		check(button.text:GetText() == "back to the shipped answers",
			("shutting the window left the button reading %q")
				:format(tostring(button.text:GetText())))
		press()
		check(ns.db.swingWidth == 200,
			"a press on a button the window shut disarmed wrote the settings back")

		ns.Options.Hide()
	end
end

ns.RestoreDefaults()

local restorable, records = ns.DefaultsShape()
print(("defaults %d settings restorable, %d records kept back, %d reloads asked for")
	:format(restorable, records, state.reloads))
