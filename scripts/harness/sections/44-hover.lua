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
	return button:GetAttribute("macrotext-" .. index)
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

check(macro(1) == "/cast [@mouseover,harm,nodead] Rend",
	("the enemy binding carries %q"):format(tostring(macro(1))))
check(bound("SHIFT-BUTTON3") == "CLICK WarriorKitHoverButton:1",
	("SHIFT-BUTTON3 reads back as %q"):format(bound("SHIFT-BUTTON3")))
check(Cast.Holding(1), "the binding layer took the key and the part says it did not")

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
check(macro(2) == "/cast [@mouseover,help,nodead] Thunder Clap",
	("the friendly binding carries %q"):format(tostring(macro(2))))

check(bind(3, "spell", "any", "CTRL-BUTTON4"),
	"binding a key that lands on anything was refused")
check(macro(3) == "/cast [@mouseover,exists,nodead] Battle Shout",
	("the anything binding carries %q"):format(tostring(macro(3))))

-- An item is /use and never /cast, because the client has two verbs and one of
-- them does nothing at all with an item's name.
Hover.Hold(Hover.Carry("item", 1001, H.itemLink("Bloodspiller")))
ns.db.hoverWho = "enemy"
check(Hover.Bind("CTRL-BUTTON5"), "binding an item was refused")
check(macro(4) == "/use [@mouseover,harm,nodead] Bloodspiller",
	("the item binding carries %q"):format(tostring(macro(4))))

--------------------------------------------------------------------------
-- The fallback
--
-- Off by default and it stays off for everything above, because a key that
-- quietly hits your target when you meant to hover something is the one wrong
-- answer this feature can give without saying anything.
--------------------------------------------------------------------------

check(ns.db.hoverFallback == false, "the target fallback shipped switched on")
ns.db.hoverFallback = true
Hover.Changed()
check(macro(1) == "/cast [@mouseover,harm,nodead][harm,nodead] Rend",
	("with the fallback on the enemy binding carries %q"):format(tostring(macro(1))))
ns.db.hoverFallback = false
Hover.Changed()

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
check(macro(4) == nil, "a suffix left over from before the removal still carries a macro")
check(macro(2) == "/cast [@mouseover,exists,nodead] Battle Shout",
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
check(bound("SHIFT-BUTTON3") == "CLICK WarriorKitHoverButton:1",
	"the keys already up were dropped when combat refused a rewrite")

inCombat = false
H.fire("PLAYER_REGEN_ENABLED")
check(bound("SHIFT-BUTTON3") == "CLICK WarriorKitHoverButton:1",
	"the deferred change never landed when the fight ended")
_G.InCombatLockdown = realLockdown

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
check(bound("SHIFT-BUTTON3") == "CLICK WarriorKitHoverButton:1",
	"the part was switched back on and the keys did not come back")

check(Hover.Clear() == 3, "clearing did not report the number it took off")
check(sheet:IsShown() == false, "the list is up with nothing bound")

print(("hover  %s"):format(Hover.Describe()))
