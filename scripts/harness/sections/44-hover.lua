-- Mouseover casting
--
-- Six questions, and the first one is the whole feature.
--
-- Does a spell dropped on the slot come back as a spell. This client answers a
-- dragged spell with a spellbook index and the book it came out of, which is
-- one of three shapes Hover/Hover.lua is prepared for, and the reading it lands
-- on decides whether the binding casts Rend or casts nothing. The stub carries
-- that shape and no fourth-slot spell id, so the path asserted here is the path
-- this client is on rather than the one a newer build would take.
--
-- Does the filter reach the macro. Enemy, friend and anything are three macro
-- conditionals and nothing else, so the assertion is on the string the button
-- is actually carrying rather than on a flag beside it.
--
-- Does a key land on the binding layer. Every part of this addon that takes a
-- key reads GetBindingAction back rather than believing its own call, and the
-- suffix is what tells one binding from another, so the readback has to name
-- the index.
--
-- Is the macro written under the name the client looks it up by. This is the
-- one that shipped wrong. The attributes were `type-1` and `macrotext-1`, a
-- secure button reads `<modifiers>type1`, and every key bound, read back
-- correctly and cast nothing. The wildcard prefix is the half that matters
-- most: a mouseover key carries a modifier, the modifier is read off the
-- keyboard at the moment of the press, and `*type1` is the only name that
-- answers whatever is held down.
--
-- Can a binding be changed rather than only made and deleted. The page draws a
-- row per binding and every column of it writes straight through, so the spell,
-- the key and the filter each have a writer and each has to refuse in the same
-- words the first press did.
--
-- Is a removed binding gone from both places. The list is the easy half. The
-- attribute on the button is the half that leaks: a macro left on a suffix a
-- later binding lands on is a key casting the spell you deleted.
--
-- Does combat defer rather than error. Attributes and override bindings are
-- both refused under lockdown, so a change made in a fight has to be held and
-- applied when the fight ends.
--
-- And does the list on screen say what is bound. It is the only thing about
-- this feature a player can see, so a row that draws the wrong key or the wrong
-- colour is the feature failing quietly.

local H = ...
local ns, check = H.ns, H.check

local Hover, Cast, Sheet = ns.Hover, ns.HoverCast, ns.HoverSheet
local button = _G.WarriorKitHoverButton

local function macro(index)
	return Cast.Macro(index)
end

-- One attribute off the button, under the full name the client looks it up by,
-- built the same way here as it is written there. Every assertion about what a
-- binding carries goes through this, because the name is half of what can be
-- wrong: an action under a name nothing asks for reads back perfectly from every
-- other angle.
--
-- Two pieces of punctuation and the client owns both. `*` is the modifier
-- wildcard, and the dash is what the client puts in front of a click name that
-- is not one of the five it answers with a bare number. So the action for the
-- click called `wk1` is `*type-wk1`, and `*type1` is a name nothing ever asks
-- for.
local function attr(what, name)
	return button:GetAttribute(("*%s-%s"):format(what, name))
end

local function bound(key)
	return _G.GetBindingAction(key, true)
end

-- Fill the slot and press a key, which is the whole gesture the page is built
-- around. Written once here because every case below starts with it.
local function bind(index, book, who, key)
	Hover.Hold(Hover.Carry("spell", index, book))
	ns.db.hoverWho = who
	return Hover.Bind(key)
end

check(ns.db.hover == true, "mouseover casting did not ship switched on")
check(#Hover.List() == 0, "a fresh character started with something bound")
check(button ~= nil, "the secure button every hover key presses was never built")

--------------------------------------------------------------------------
-- What the cursor is carrying
--------------------------------------------------------------------------

local pick = Hover.Carry("spell", 1, "spell")
check(pick ~= nil and pick.name == "Rend",
	("a spell dragged off the book read as %s"):format(tostring(pick and pick.name)))
check(pick ~= nil and pick.kind == "spell" and pick.icon ~= nil,
	"the pick came back with no icon, so the list on screen would draw nothing")

-- The book is asked for the name, not the id. Index 2 is Thunder Clap in the
-- stub's book and GetSpellInfo(2) is "Spell2", so a reading that fell through
-- to the id would say so here.
local second = Hover.Carry("spell", 2, "spell")
check(second ~= nil and second.name == "Thunder Clap",
	("the second book entry read as %s, which is the spell id talking")
		:format(tostring(second and second.name)))

local item = Hover.Carry("item", 1001, H.itemLink("Bloodspiller"))
check(item ~= nil and item.name == "Bloodspiller" and item.kind == "item",
	"an item dropped on the slot did not come back as an item")

local refused, why = Hover.Carry("macro", 3)
check(refused == nil and type(why) == "string",
	"a macro on the cursor was accepted, and there is nothing to cast it by name")

--------------------------------------------------------------------------
-- Binding
--------------------------------------------------------------------------

Hover.Hold(nil)
local ok, said = Hover.Bind("SHIFT-BUTTON3")
check(not ok and said:find("slot") ~= nil,
	("a key was taken with an empty slot: %s"):format(tostring(said)))

Hover.Hold(Hover.Carry("spell", 1, "spell"))
ok, said = Hover.Bind("BUTTON1")
check(not ok and said:find("modifier") ~= nil,
	("plain left click was accepted: %s"):format(tostring(said)))

ok, said = bind(1, "spell", "enemy", "SHIFT-BUTTON3")
check(ok, ("binding Rend was refused: %s"):format(tostring(said)))
check(#Hover.List() == 1, "the binding did not reach the list")
check(Hover.Held() == nil, "the slot still holds the spell after the key was pressed")

check(macro(1) == "spell Rend on mouseover",
	("the enemy binding carries %q"):format(tostring(macro(1))))
check(bound("SHIFT-BUTTON3") == "CLICK WarriorKitHoverButton:wk1",
	("SHIFT-BUTTON3 reads back as %q"):format(bound("SHIFT-BUTTON3")))
check(Cast.Holding(1), "the binding layer took the key and the part says it did not")

-- The names, not only the values, and this is the assertion the whole feature
-- turns on. A press arrives carrying whatever modifiers are held, so the client
-- asks for `shift-type1` first and falls back to `*type1`; an action under any
-- other name reads back perfectly from every angle and casts nothing.
--
-- The filter is a second name rather than a conditional. `harmbutton1` says the
-- click becomes `enemy1` when the thing under the cursor can be attacked, and the
-- action lives only there. A press on a friend arrives as `1`, finds no type, and
-- does nothing. So the assertion is that suffix 1 is empty and suffix enemy1 is
-- not: an action left on the plain name would fire on anything at all.
check(attr("harmbutton", "wk1") == "enemywk1",
	("the enemy filter remaps to %q"):format(tostring(attr("harmbutton", "wk1"))))
check(attr("type", "enemywk1") == "spell" and attr("spell", "enemywk1") == "Rend",
	("the action under enemywk1 is %q %q")
		:format(tostring(attr("type", "enemywk1")), tostring(attr("spell", "enemywk1"))))
check(attr("unit", "wk1") == "mouseover" and attr("unit", "enemywk1") == "mouseover",
	"the filter has no unit to ask about, so it can never remap")
check(attr("type", "wk1") == nil,
	"an action on the unfiltered name fires on whatever is under the cursor")

-- Never macro text. It is set here by insecure code, and macro text set by
-- insecure code and run off a keypress is what the secure system exists to
-- refuse: the handler reads it, declines it and says nothing. That is how this
-- shipped, and every reading an addon can take of it came back correct.
check(attr("macrotext", "wk1") == nil and attr("macrotext", "enemywk1") == nil,
	"the button carries macro text, which the client will not run from here")
-- The two names nothing ever asks for, and the second of them is what this
-- shipped as. `*type1` is the click called LeftButton, which is not the click
-- this button is ever sent; `type-wk1` answers only with no modifier held, and
-- a mouseover key always carries one.
check(button:GetAttribute("*type1") == nil and button:GetAttribute("type-wk1") == nil,
	"the action is written under a name the press never asks for")

-- The other half of the press. A click that matches no registration is dropped
-- before any script runs, and which edge a key bound with SetOverrideBindingClick
-- is dispatched on is the useOnKeyDown attribute. Buttons/Bars.lua found out what
-- it costs to let those two disagree: forty eight squares that drew, lit and
-- counted down, and cast nothing under the key.
--
-- Asserted as agreement rather than as a value, which is how 05-action-bars.lua
-- holds the same rule, so it keeps holding if the edge is ever changed.
local clicks = button:GetRegisteredClicks() or {}
local keyDown = button:GetAttribute("useOnKeyDown")
check(keyDown ~= nil, "the edge a bound key fires on is unset, so it is the client's guess")
check((keyDown and true or false) == (clicks.AnyDown and true or false),
	"the edge the button answers and the edge a key is dispatched on disagree")

-- One key, one binding. The second one wins silently on the client, which is
-- why it is refused here rather than reported afterwards.
ok, said = bind(2, "spell", "friend", "SHIFT-BUTTON3")
check(not ok and said:find("Rend") ~= nil,
	("a second binding took a key Rend already had: %s"):format(tostring(said)))

--------------------------------------------------------------------------
-- The filter
--------------------------------------------------------------------------

check(bind(2, "spell", "friend", "ALT-BUTTON3"),
	"binding a friendly key was refused")
check(macro(2) == "spell Thunder Clap on mouseover",
	("the friendly binding carries %q"):format(tostring(macro(2))))
check(attr("helpbutton", "wk2") == "friendwk2" and attr("spell", "friendwk2") == "Thunder Clap",
	"the friendly filter does not remap to a name of its own")

check(bind(3, "spell", "any", "CTRL-BUTTON4"),
	"binding a key that lands on anything was refused")
check(macro(3) == "spell Battle Shout on mouseover",
	("the anything binding carries %q"):format(tostring(macro(3))))
-- No remap, because there is nothing to filter. The action sits on the plain
-- name, which is the one case where that is right.
check(attr("type", "wk3") == "spell" and attr("spell", "wk3") == "Battle Shout",
	"a key that lands on anything must carry its action on the unfiltered name")
check(attr("helpbutton", "wk3") == nil and attr("harmbutton", "wk3") == nil,
	"a key that lands on anything remapped itself out of reach")

-- An item is /use and never /cast, because the client has two verbs and one of
-- them does nothing at all with an item's name.
Hover.Hold(Hover.Carry("item", 1001, H.itemLink("Bloodspiller")))
ns.db.hoverWho = "enemy"
check(Hover.Bind("CTRL-BUTTON5"), "binding an item was refused")
check(macro(4) == "item Bloodspiller on mouseover",
	("the item binding carries %q"):format(tostring(macro(4))))
check(attr("type", "enemywk4") == "item" and attr("item", "enemywk4") == "Bloodspiller",
	"an item is carried under its own verb, and a spell name would do nothing")

--------------------------------------------------------------------------
-- Changing one that is already there
--
-- Three writers, one per column of the row. Each is asserted on the macro the
-- button carries rather than on the list, because the list is the easy half and
-- a change that never reached the button is a row that says one thing and casts
-- another.
--------------------------------------------------------------------------

check(Hover.Retarget(1, "friend"), "the filter on a bound key would not change")
check(attr("helpbutton", "wk1") == "friendwk1" and attr("spell", "friendwk1") == "Rend",
	"after retargeting the key does not carry its action under the new filter")
-- The old filter's names, which is the half a rewrite leaves behind. A key that
-- moved from enemy to friend and kept `typeenemy1` casts on both.
check(attr("harmbutton", "wk1") == nil and attr("type", "enemywk1") == nil,
	"the filter it was on is still on the button and the key now fires on either")
check(Hover.Retarget(1, "enemy"), "putting the filter back was refused")

check(Hover.Respell(1, Hover.Carry("spell", 2, "spell")),
	"the spell on a bound key would not change")
check(macro(1) == "spell Thunder Clap on mouseover",
	("after the spell changed, the first binding carries %q"):format(tostring(macro(1))))
check(Hover.Respell(1, Hover.Carry("spell", 1, "spell")), "putting the spell back was refused")

-- A row keeps its own key. Refusing it would mean pressing the key a row
-- already has could not confirm it, which is the one press somebody makes by
-- accident and the one that must do nothing rather than complain.
check(Hover.Rebind(1, "SHIFT-BUTTON3"), "a row would not be rebound to the key it already has")

local moved, refused_why = Hover.Rebind(1, "ALT-BUTTON3")
check(not moved and refused_why:find("Thunder Clap") ~= nil,
	("a row took a key its neighbour holds: %s"):format(tostring(refused_why)))

check(Hover.Rebind(1, "CTRL-BUTTON1"), "a modified left click was refused as a new key")
check(bound("CTRL-BUTTON1") == "CLICK WarriorKitHoverButton:wk1",
	("the rebound key reads back as %q"):format(bound("CTRL-BUTTON1")))
check(bound("SHIFT-BUTTON3") == "", "the key the row moved off is still on the binding layer")
check(Hover.Rebind(1, "SHIFT-BUTTON3"), "moving the row back was refused")

moved, refused_why = Hover.Rebind(1, "BUTTON1")
check(not moved and refused_why:find("modifier") ~= nil,
	("a bound row took plain left click: %s"):format(tostring(refused_why)))

--------------------------------------------------------------------------
-- The list on screen
--------------------------------------------------------------------------

local sheet = _G.WarriorKitHoverSheet
check(sheet ~= nil and sheet:IsShown(), "the list is off with four keys bound")
check(Sheet.Shown() == 4, ("the list draws %d rows for four keys"):format(Sheet.Shown()))

local row = Sheet.Row(1)
check(row.key:GetText() == "SHIFT-BUTTON3",
	("the first row reads %q"):format(tostring(row.key:GetText())))
check(row.name:GetText() == "Rend",
	("the first row names %q"):format(tostring(row.name:GetText())))

local function tone(index)
	local r, g, b = Sheet.Row(index).key:GetTextColor()
	return ("%.2f %.2f %.2f"):format(r, g, b)
end
local function said_as(color)
	return ("%.2f %.2f %.2f"):format(color[1], color[2], color[3])
end
local C = ns.UI.Color
check(tone(1) == said_as(C.loss),
	("an enemy key is drawn %s, expected the red"):format(tone(1)))
check(tone(2) == said_as(C.tick),
	("a friendly key is drawn %s, expected the green"):format(tone(2)))
check(tone(3) == said_as(C.dim),
	("a key that lands on anything is drawn %s, expected the grey"):format(tone(3)))

check(Sheet.Row(5):IsShown() == false, "an unbound row is still on screen")

ns.db.hoverSheet = false
Sheet.Rebuild()
check(sheet:IsShown() == false, "the list stayed up with its setting off")
ns.db.hoverSheet = true
Sheet.Rebuild()

--------------------------------------------------------------------------
-- Taking one off
--------------------------------------------------------------------------

check(Hover.Remove(2) == "Thunder Clap", "removing the friendly key named the wrong spell")
check(#Hover.List() == 3, "the list is the wrong length after a removal")
check(bound("ALT-BUTTON3") == "", "the removed key is still on the binding layer")
check(macro(4) == nil, "a suffix left over from before the removal still carries an action")
check(attr("type", "enemywk4") == nil and attr("item", "enemywk4") == nil,
	"the removed row's attributes are still on the button under its old name")
check(macro(2) == "spell Battle Shout on mouseover",
	("after the removal suffix 2 carries %q"):format(tostring(macro(2))))
check(Sheet.Shown() == 3, "the list on screen did not shrink with the binding")

--------------------------------------------------------------------------
-- Combat
--------------------------------------------------------------------------

local realLockdown = _G.InCombatLockdown
local inCombat = false
_G.InCombatLockdown = function() return inCombat end

inCombat = true
check(Cast.Apply() == false, "a change in combat was not deferred")
check(Cast.Describe():find("combat") ~= nil,
	("in combat the keys read %q"):format(Cast.Describe()))
check(bound("SHIFT-BUTTON3") == "CLICK WarriorKitHoverButton:wk1",
	"the keys already up were dropped when combat refused a rewrite")

inCombat = false
H.fire("PLAYER_REGEN_ENABLED")
check(bound("SHIFT-BUTTON3") == "CLICK WarriorKitHoverButton:wk1",
	"the deferred change never landed when the fight ended")
_G.InCombatLockdown = realLockdown

--------------------------------------------------------------------------
-- The debug log
--
-- Gated because it is the instrument, and an instrument that errors is worse
-- than no instrument at all. It shipped calling two functions on ns.Hover that
-- were never written, so the first press with the log on threw rather than
-- saying anything, and the one question the log exists to answer went unasked.
--
-- The press is driven through the script the log installs rather than around it,
-- so what is asserted is the path a real click takes.
--------------------------------------------------------------------------

local first = Hover.List()[1]
check(#Hover.Forms(first) == 2,
	("the filter is offered to the parser in %d spellings, and there are two")
		:format(#Hover.Forms(first)))
local asked, knows = pcall(Hover.Understands, Hover.Forms(first)[1], first.name)
check(asked, "asking the client's parser about a form threw")
check(knows == nil or type(knows) == "boolean",
	("the parser probe answered %s, which is neither a verdict nor a refusal")
		:format(tostring(knows)))

ns.db.hoverDebug = true
Cast.Watch()
local trace = button:GetScript("PostClick")
check(trace ~= nil, "the log is on and nothing is watching the button")
check(pcall(trace, button, "wk1", true), "a press with the log on threw instead of saying what it found")
check(pcall(trace, button, "LeftButton", true),
	"a click under a name no binding owns threw instead of being ignored")
ns.db.hoverDebug = false
Cast.Watch()
check(button:GetScript("PostClick") == nil,
	"the log is off and a script is still in the click path, which taints the cast")

--------------------------------------------------------------------------
-- The switch
--------------------------------------------------------------------------

ns.db.hover = false
Hover.Changed()
check(bound("SHIFT-BUTTON3") == "",
	"the part was switched off and the keys stayed on the binding layer")
check(sheet:IsShown() == false, "the part was switched off and the list stayed up")
ns.db.hover = true
Hover.Changed()
check(bound("SHIFT-BUTTON3") == "CLICK WarriorKitHoverButton:wk1",
	"the part was switched back on and the keys did not come back")

check(Hover.Clear() == 3, "clearing did not report the number it took off")
check(sheet:IsShown() == false, "the list is up with nothing bound")

--------------------------------------------------------------------------
-- The page
--
-- The gesture the page is built around is drop, then press, and this is the
-- one part of it the model cannot see. A key is taken by the box only while
-- the box is listening, and the box used to start listening on a click that
-- nothing on the page asked for: the moment the slot was full the row read
-- "press a key", the key was pressed, and it went to whatever it was already
-- bound to. Every binding after the first was made that way in the game and
-- none of them landed.
--
-- So the drop arms the box, a key pressed with no click in between is the
-- binding, and a click on the box that is already listening keeps it
-- listening rather than cancelling, because that click is the one a player
-- who learned the old way still makes.
--------------------------------------------------------------------------

local UI = ns.UI
ns.Options.Open("Mouseover casting")

local draft
for _, entry in ipairs(ns.Options.Indexed()) do
	if entry.label == "a new key" then
		draft = entry.widget
	end
end
check(draft ~= nil and draft.square ~= nil and draft.key ~= nil,
	"the page has no row to make a new key on")

-- Every row on the page, the empty one and the twelve saved ones under it.
-- Walked off the frame tree rather than read off the index, because a saved
-- row carries no label and the index lists labelled controls only.
local rows = {}
local function collect(frame)
	if frame.key and frame.square and frame.who then
		rows[#rows + 1] = frame
	end
	for _, kid in ipairs(frame.children or {}) do
		collect(kid)
	end
end
if draft then
	local top = draft
	while top.parent do
		top = top.parent
	end
	collect(top)
end
check(#rows == ns.Hover.MAX + 1,
	("the page has %d rows and should have %d"):format(#rows, ns.Hover.MAX + 1))

-- A press, the way the client delivers one: to every shown box that has the
-- keyboard, the last one made first, stopping at the first whose handler did
-- not pass it on. The modifier arrives as a key of its own first, then the key
-- with the modifier held. Handing the key to the listening box directly is how
-- this section passed while every key after the first died in the game: the
-- saved row it had just made was asked first and ate it.
local function deliver(key)
	for index = #rows, 1, -1 do
		local box = rows[index].key
		if box:IsVisible() and box:IsKeyboardEnabled() then
			box.scripts.OnKeyDown(box, key)
			if not box:GetPropagateKeyboardInput() then
				return box
			end
		end
	end
	return nil
end
local function press(_, key)
	deliver("LSHIFT")
	_G.WarriorKitShift(true)
	local took = deliver(key)
	_G.WarriorKitShift(false)
	return took
end

local function drop(index)
	_G.WarriorKitCarrySpell(index, "spell")
	draft.square.button:Click("LeftButton")
end

if draft then
	drop(1)
	check(Hover.Held() ~= nil and Hover.Held().name == "Rend",
		"a spell dropped on the empty row did not fill its slot")
	check(UI.Capturing() == draft.key,
		"the slot is full and the box beside it is not listening for the key")
	check(press(draft.key, "F") == draft.key,
		"the first key did not stop at the empty row's box")
	check(#Hover.List() == 1 and Hover.List()[1].key == "SHIFT-F",
		"a key pressed straight after the drop was not taken")
	check(rows[2]:IsVisible() and rows[2].key:IsKeyboardEnabled() == false,
		"the saved row is up and its box is on the keyboard")
	check(Hover.Held() == nil and UI.Capturing() == nil,
		"the slot or the box is still armed after the key was taken")

	-- The second one, which is the one that never landed in the game. A click
	-- on the listening box in between, because that is the click the first
	-- binding taught.
	drop(2)
	check(UI.Capturing() == draft.key, "the second drop did not arm the box")
	draft.key:Click("LeftButton")
	check(UI.Capturing() == draft.key,
		"a click on the box that was already listening cancelled it")
	check(press(draft.key, "G") == draft.key,
		"the second key stopped at a box that was not listening")
	check(#Hover.List() == 2 and Hover.List()[2].key == "SHIFT-G",
		("the second key did not land: %d bound"):format(#Hover.List()))
	check(Cast.Holding(1) and Cast.Holding(2),
		"two keys are in the list and the binding layer does not hold both")

	-- Cancelling is still there for a drop made by mistake: a right click, and
	-- the row then says a click is needed rather than promising a key.
	drop(3)
	draft.key:Click("RightButton")
	check(UI.Capturing() == nil, "a plain right click did not cancel the capture")
	check(draft.key.text:GetText():find("click") ~= nil,
		("with the capture cancelled the box reads %q"):format(tostring(draft.key.text:GetText())))
	Hover.Hold(nil)
	Hover.Clear()
	ns.Options.Refresh()
end

print(("hover  %s"):format(Hover.Describe()))
