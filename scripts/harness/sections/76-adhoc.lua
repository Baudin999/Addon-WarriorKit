-- Ad hoc bars
--
-- A bar you made yourself is a list, a key and a frame, and this section
-- asserts the seams between the three: that a bar added to the list gets a
-- frame that starts hidden and a key button carrying the snippet that shows
-- it; that what the cursor was holding lands on the square as the attribute a
-- press would cast; that a key is read back off the binding layer rather than
-- trusted; that a fight defers the whole apply; that deleting a bar moves the
-- bar under it, key and all, onto a different frame; and that a square on a
-- shown bar is drawn on the tick.
--
-- What this cannot prove: that the restricted environment shows a secure
-- frame off a click snippet, or hides one off a wrapped OnClick. Both are
-- recorded here as strings and never run, which is the limit the state driver
-- stub already states. Those two answers are a key press in game.

local H = ...
local ns, fire, check = H.ns, H.fire, H.check

local AdHoc, Bars = ns.AdHoc, ns.AdHocBars

local function frame(index)
	return _G[("WarriorKitAdHoc%d"):format(index)]
end

local function key(index)
	return _G[Bars.KeyName(index)]
end

local function square(index, at)
	return _G[Bars.ButtonName(index, at)]
end

local function bound(combo)
	return _G.GetBindingAction(combo, true)
end

local function holds(index)
	return ("CLICK %s:LeftButton"):format(Bars.KeyName(index))
end

check(ns.db.adhoc == true, "ad hoc bars did not ship switched on")
check(AdHoc.Count() == 0, "a fresh character started with a bar")
check(frame(1) == nil, "a frame was built before any bar asked for one")

--------------------------------------------------------------------------
-- A bar, its frame and its key
--------------------------------------------------------------------------

local trade = AdHoc.Add("trade")
check(trade == 1, "the first bar was not bar 1")
check(AdHoc.Get(1).name == "trade", "the bar did not keep its name")
check(AdHoc.Shown() == 1, "the page did not turn to the bar just added")

local f = frame(1)
check(f ~= nil, "adding a bar built no frame")
check(f ~= nil and f:IsShown() == false, "a new bar was on the screen before its key was pressed")

local k = key(1)
check(k ~= nil, "adding a bar built no key button")
check(k ~= nil and type(k:GetAttribute("_onclick")) == "string"
	and k:GetAttribute("_onclick"):find("Show", 1, true) ~= nil,
	"the key button carries no snippet that shows the bar")
check(k ~= nil and k:GetFrameRef("bar") == f, "the snippet was handed the wrong frame")
check(k ~= nil and k:GetRegisteredClicks().AnyDown == true and k:GetRegisteredClicks().AnyUp == true,
	"the key button is not registered on both edges, so letting the key go would not put the bar away")
check(k ~= nil and k:GetAttribute("_onclick"):find("down", 1, true) ~= nil
	and k:GetAttribute("_onclick"):find("Hide", 1, true) ~= nil,
	"the key snippet does not read the edge of the press, so the key toggles instead of holding")

local s1 = square(1, 1)
check(s1 ~= nil and s1.secure == true, "a square is not a secure button")
check(s1 ~= nil and s1:GetRegisteredClicks().AnyUp == true and s1:GetAttribute("useOnKeyDown") == false,
	"a square's two edges disagree")
check(s1 ~= nil and s1.wraps ~= nil and s1.wraps.OnClick ~= nil
	and s1.wraps.OnClick.header == f
	and tostring(s1.wraps.OnClick.post):find("Hide", 1, true) ~= nil,
	"a square's OnClick is not wrapped by the bar with a snippet that hides it")
check(Bars.CanClose(1) == true, "the bar does not report that it can close after a press")

local entry = Bars.Entry(1)
check(entry ~= nil and entry.count == 1, "an empty bar did not draw the one square a drop lands on")
check(s1 ~= nil and s1:IsShown() == true and square(1, 2):IsShown() == false,
	"an empty bar shows the wrong squares")
check(s1 ~= nil and s1:GetAttribute("type") == nil, "an empty square carries a type, so a press would do something")
check(f ~= nil and f:GetAttribute("wk-close") == true, "a new bar does not close after a press")

--------------------------------------------------------------------------
-- What lands on a square
--------------------------------------------------------------------------

_G.WarriorKitCarrySpell(1, "spell")
local rend, why = AdHoc.Carry(_G.GetCursorInfo())
check(rend ~= nil and rend.kind == "spell" and rend.name == "Rend" and rend.icon ~= nil,
	("a spell off the book read as %s"):format(tostring(rend and rend.name or why)))
_G.ClearCursor()

check(AdHoc.Put(1, 1, rend) == true, "the first spell would not go on the first square")
check(#AdHoc.Squares(1) == 1 and AdHoc.Squares(1)[1].name == "Rend", "the list did not take the spell")
check(s1:GetAttribute("type") == "spell" and s1:GetAttribute("spell") == "Rend",
	"the square was not armed with the spell by name")
check(Bars.Entry(1).count == 1 and square(1, 2):IsShown() == false,
	"a bar of one spell drew a second square")

_G.WarriorKitCarrySpell(2, "spell")
local clap = AdHoc.Carry(_G.GetCursorInfo())
_G.ClearCursor()
check(AdHoc.Put(1, 9, clap) == true, "a spell dropped past the end was refused")
check(#AdHoc.Squares(1) == 2 and AdHoc.Squares(1)[2].name == "Thunder Clap",
	"a drop past the end did not land on the next square")
check(Bars.Entry(1).count == 2, "two spells did not draw two squares")

do
	local item = AdHoc.Carry("item", 1001, H.itemLink("Bloodspiller"))
	check(item ~= nil and item.kind == "item" and item.id == 1001 and item.name == "Bloodspiller",
		"an item off a bag did not come back with its id and name")
	check(AdHoc.Put(1, 3, item) == true, "an item would not go on the bar")
	check(square(1, 3):GetAttribute("type") == "macro"
		and square(1, 3):GetAttribute("macrotext") == "/use Bloodspiller",
		"an item square does not carry a /use line")

	local refused, reason = AdHoc.Carry("macro", 3)
	check(refused == nil and type(reason) == "string",
		"a macro this client cannot name was accepted")

	local nothing, silence = AdHoc.Carry(nil)
	check(nothing == nil and silence == nil, "an empty cursor was answered with a sentence")

	-- Replacing, moving and taking away
	check(AdHoc.Put(1, 1, clap) == true and AdHoc.Squares(1)[1].name == "Thunder Clap",
		"a drop on a full square did not replace what was there")
	check(AdHoc.Move(1, 3, 1) == true and AdHoc.Squares(1)[1].name == "Bloodspiller"
		and AdHoc.Squares(1)[2].name == "Thunder Clap",
		"a move did not put the record where it was dragged")
	local taken = AdHoc.Take(1, 1)
	check(taken ~= nil and taken.name == "Bloodspiller" and #AdHoc.Squares(1) == 2
		and AdHoc.Squares(1)[1].name == "Thunder Clap",
		"taking a square away did not close the gap")
	check(square(1, 3):GetAttribute("type") == nil and square(1, 3):IsShown() == false,
		"the square past the end kept its old attribute")

	-- The width of a bar is a cap that says so
	for _ = 1, AdHoc.PER_BAR do
		AdHoc.Put(1, AdHoc.PER_BAR + 1, rend)
end
check(#AdHoc.Squares(1) == AdHoc.PER_BAR, "a bar took more squares than its width")
local over, full = AdHoc.Put(1, AdHoc.PER_BAR + 1, rend)
check(over == false and type(full) == "string", "the seventeenth square was dropped silently")
while #AdHoc.Squares(1) > 2 do
	AdHoc.Take(1, #AdHoc.Squares(1))
end

end

--------------------------------------------------------------------------
-- The shape and the closing rule
--------------------------------------------------------------------------

check(AdHoc.Columns(1) == AdHoc.COLUMNS and AdHoc.Get(1).columns == nil,
	"a bar nobody reshaped carries a columns field")
AdHoc.SetColumns(1, 2)
check(AdHoc.Columns(1) == 2 and AdHoc.Get(1).columns == 2, "the columns did not take")
AdHoc.SetColumns(1, AdHoc.COLUMNS)
check(AdHoc.Get(1).columns == nil, "setting the columns back to the default left a record")

AdHoc.SetCloses(1, false)
check(AdHoc.Closes(1) == false and f:GetAttribute("wk-close") == false,
	"a bar told to stay up still tells its snippet to hide it")
AdHoc.SetCloses(1, true)
check(AdHoc.Closes(1) == true and AdHoc.Get(1).close == nil,
	"the closing rule set back to the default left a record")

--------------------------------------------------------------------------
-- The key
--------------------------------------------------------------------------

do
	check(bound("T") ~= holds(1), "T was held before anyone bound it")
	local displaced, refusal = Bars.Bind(1, "T")
	check(displaced == "", ("binding T was refused: %s"):format(tostring(refusal)))
	check(bound("T") == holds(1), "T does not click the bar's key button")
	check(AdHoc.Get(1).key == "T" and AdHoc.Get(1).displaced == "", "the key was not written down")
	check(Bars.Describe(1) == "T", ("the bar describes its key as %s"):format(Bars.Describe(1)))

	local shadowed = Bars.Bind(1, "E")
	check(shadowed == "ACTIONBUTTON1", "taking a key off the action bar did not say what it displaced")
	check(bound("T") ~= holds(1) and bound("E") == holds(1), "rebinding left the old key held")

	local bare, bareWhy = Bars.Bind(1, "BUTTON1")
	check(bare == nil and type(bareWhy) == "string", "a bare mouse button was taken")
	check(bound("E") == holds(1), "a refused key cleared the key that was held")

	local totems = AdHoc.Add("totems")
	check(totems == 2 and frame(2) ~= nil and key(2) ~= nil, "a second bar built no frame")
	local twice, twiceWhy = Bars.Bind(2, "E")
	check(twice == nil and type(twiceWhy) == "string" and twiceWhy:find("trade", 1, true) ~= nil,
		"one key was taken by two bars")
	check(Bars.Bind(2, "SHIFT-T") == "", "a modified key was refused")
	check(bound("SHIFT-T") == holds(2), "the second bar's key does not click its own button")

	check(AdHoc.Find("totems") == 2 and AdHoc.Find("TRADE") == 1 and AdHoc.Find("2") == 2
		and AdHoc.Find("swords") == nil, "a bar is not found by name and by number")

end

--------------------------------------------------------------------------
-- The tick
--------------------------------------------------------------------------

do
	local tick = H.tick("adhoc")
	f:Show()
	tick:Beat(0.2)
	check(s1.shownTexture == AdHoc.Squares(1)[1].icon,
		"a square on a shown bar was not drawn with its record's picture")
	check(square(1, 2).shownTexture == AdHoc.Squares(1)[2].icon,
		"the second square on a shown bar was not drawn")
	f:Hide()

	local hidden = frame(2)
	local empty = square(2, 1)
	tick:Beat(0.2)
	check(empty.shownTexture == nil, "a square on a hidden bar was drawn")
	hidden:Show()
	tick:Beat(0.2)
	check(empty.shownLook ~= nil and empty.shownLook.blank == true,
		"the empty square on a shown bar was not drawn as empty")
	hidden:Hide()

end

--------------------------------------------------------------------------
-- A fight
--------------------------------------------------------------------------

do
	local realLockdown = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	check(AdHoc.Put(2, 1, rend) == true, "a drop in a fight was refused rather than held")
	check(Bars.Pending() == true, "a drop in a fight did not leave the apply pending")
	check(square(2, 1):GetAttribute("type") == nil, "a secure attribute was rewritten in combat")
	local fought, fightWhy = Bars.Bind(2, "Y")
	check(fought == nil and type(fightWhy) == "string", "a key was rebound in combat")
	_G.InCombatLockdown = realLockdown
	fire("PLAYER_REGEN_ENABLED")
	check(Bars.Pending() == false and square(2, 1):GetAttribute("spell") == "Rend",
		"the fight ending did not land the drop it had held")

end

--------------------------------------------------------------------------
-- Deleting the first bar moves the second
--------------------------------------------------------------------------

check(AdHoc.Remove(1) == true, "the first bar would not go")
check(AdHoc.Count() == 1 and AdHoc.Get(1).name == "totems", "the second bar did not move up")
check(bound("SHIFT-T") == holds(1), "the moved bar's key does not click the first key button")
check(bound("E") ~= holds(1) and bound("E") ~= holds(2), "the deleted bar's key is still held")
check(square(1, 1):GetAttribute("spell") == "Rend", "the moved bar's squares did not move with it")
check(frame(2):IsShown() == false, "the frame the deleted bar left behind is on the screen")

--------------------------------------------------------------------------
-- The switch
--------------------------------------------------------------------------

ns.db.adhoc = false
Bars.Apply()
check(bound("SHIFT-T") ~= holds(1), "a bar that is switched off still holds its key")
check(frame(1):IsShown() == false, "a bar that is switched off is on the screen")
check(Bars.Describe(1):find("off", 1, true) ~= nil, "the key is described as held while the bars are off")
ns.db.adhoc = true
Bars.Apply()
check(bound("SHIFT-T") == holds(1), "switching the bars back on did not take the key again")

--------------------------------------------------------------------------
-- Placing
--------------------------------------------------------------------------

AdHoc.Get(1).point = { "TOPLEFT", "UIParent", "TOPLEFT", 40, -40 }
Bars.Apply()
check(frame(1):GetAttribute("wk-point") == "TOPLEFT" and frame(1):GetAttribute("wk-x") == 40,
	"a saved anchor was not handed to the snippet that places the bar")
Bars.Reset()
check(AdHoc.Get(1).point == nil and frame(1):GetAttribute("wk-point") == "CENTER",
	"a reset did not put the bar back where it started")

--------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------

do
	ns.Options.Open("Ad hoc bars")
	ns.Options.Refresh()
	local first = ns.AdHocPanel.Square(1)
	check(first ~= nil and first.record ~= nil and first.record.name == "Rend",
		"the page's first square does not show the bar's first record")
	local next = ns.AdHocPanel.Square(2)
	check(next ~= nil and next.record == nil and next:IsShown() == true,
		"the page does not draw the empty square a drop lands on")
	check(ns.AdHocPanel.Square(3) ~= nil and ns.AdHocPanel.Square(3):IsShown() == false,
		"the page draws squares past the empty one")
	ns.Options.Hide()

end

--------------------------------------------------------------------------
-- The foot: nothing held, nothing on the screen
--------------------------------------------------------------------------

while AdHoc.Count() > 0 do
	AdHoc.Remove(AdHoc.Count())
end
check(bound("SHIFT-T") ~= holds(1) and bound("E") ~= holds(1), "a deleted bar left a key held")
_G.ClearCursor()
