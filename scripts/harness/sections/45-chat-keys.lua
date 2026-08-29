-- The keys the client will only take from itself
--
-- Three questions, and none of them can be answered by reading Chat/.
--
-- Does a command the client refuses from us get run at all. /logout ends in
-- Logout(), Logout() is protected, and a line handed to the client's parser
-- arrives there on a stack this addon has been in, which comes back as a red
-- line naming WarriorKit rather than as a character logging out. The way
-- through is a secure button carrying the line as its macrotext under the
-- enter key, and the only thing that proves it is the readback: which button
-- the key is on, and what that button is carrying.
--
-- Does it run on the press that typed it. This took two presses for a long
-- time, because the key was loaded on the enter that finished the line and the
-- press that loads a key is not the press that runs it. The field loads the
-- key while you are still typing instead, so the answer here is about the
-- state of the key with the line still in the field and no enter pressed yet.
--
-- The half that went wrong is the order. The field empties itself the moment
-- it is told the line is finished, emptying is a text change like any other,
-- and read plainly it says the field no longer holds a line that needs the
-- key. So the key went back to the window out from under the press that was
-- about to run it, which is one press that does nothing and worse than the two
-- it replaced. That is what Window.Enter is here to reach.
--
-- And does a refusal say which refusal it is. There are three, a fight, a
-- client with no override bindings and a key somebody else holds, they need
-- three different things from the player, and one "it did not work" for all of
-- them is the sentence that sent this bug round twice.
--
-- Split out of 29-social.lua for the reason 41-voice.lua was: the social part
-- is the rooms and what you read in them, this is the binding layer, and the
-- two together were over the eight hundred line budget.

local H = ...
local chat = H.chat
local ns, check = H.ns, H.check

local Compose, Window = ns.Compose, ns.ChatWindow

-- /logout is not the addon's to run. It ends in Logout(), which is
-- protected, and a line handed to the client's parser arrives there on a
-- stack this addon has been in, which the client refuses with a red line
-- naming the addon. So it goes onto a secure button under the enter key and
-- the next press is the client's own work.
local handed = #chat.slash
local said = Window.Count(Window.Room())
Window.Send("/logout")
check(#chat.slash == handed,
	"/logout went to the client's parser, where it comes back as a blocked action")
check(Compose.Armed() == "/logout",
	("the enter key was loaded with %s"):format(tostring(Compose.Armed())))
check(_G.GetBindingAction("ENTER", true) == "CLICK WarriorKitChatSecureButton:LeftButton",
	("enter is on %q"):format(tostring(_G.GetBindingAction("ENTER", true))))
check(_G.WarriorKitChatSecureButton:GetAttribute("macrotext") == "/logout",
	"the button was armed with something other than the line typed")

-- The edge and the attribute that names it, checked as a pair, because apart
-- they are a key that binds, reads back bound, dispatches its click and runs
-- nothing. That is this addon's most expensive bug and it has now cost two
-- files: Buttons/Bars.lua found it on the squares and Hover/Cast.lua found it
-- again on the mouseover keys. Both edges against an unset attribute is the
-- shape it wears, so the gate is on both halves rather than on either.
--
-- Asserted as agreement rather than as a value, the way 44-hover.lua holds the
-- same rule, so it keeps holding if this button is ever moved to the other edge.
local clicks = _G.WarriorKitChatSecureButton:GetRegisteredClicks() or {}
local keyDown = _G.WarriorKitChatSecureButton:GetAttribute("useOnKeyDown")
check(keyDown ~= nil, "the edge a bound key fires on is unset, so it is the client's guess")
check((keyDown and true or false) == (clicks.AnyDown and true or false),
	"the edge the button answers and the edge a key is dispatched on disagree")
-- And it is the press, because that is the edge this client delivers. The
-- release was tried, on the reasoning that the press that finishes the line
-- belongs to the field and the release does not, and the client does not agree.
-- The cost of finding that out is why the edge is asserted by name here as well
-- as by agreement above.
check(clicks.AnyDown and not clicks.AnyUp,
	"the line is on the release, which is the edge this client does not deliver")

-- The empty line says what the key is holding, and that is the whole point
-- of the sentence: ns.Print writes to Blizzard's window, every player using
-- this window has hidden Blizzard's window, and the hint landed in the
-- System room while the player sat looking at the field. From the field it
-- looked like a key press that did nothing.
check(Window.Ghost() == "press enter again and /logout goes",
	("the empty line reads %q"):format(tostring(Window.Ghost())))
-- And the sentence is in the room the line was typed in rather than in the
-- System room, which is the same argument one line further out.
check(Window.Count(Window.Room()) == said + 1,
	("the handover put %d lines in the room the line was typed in")
		:format(Window.Count(Window.Room()) - said))

-- Coming back to the field is a change of mind, and the window gets enter
-- back. A key left loaded is a key that no longer opens the chat line.
Window.Focus()
check(Compose.Armed() == nil, "coming back to the field left the enter key loaded")
-- What enter carries afterwards is the window's business and depends on
-- whether it has taken Blizzard's chat over, which it has not here. What
-- matters is that it is no longer the secure button, because a key still on
-- that one is a key that runs a line nobody typed.
check(_G.GetBindingAction("ENTER", true) ~= "CLICK WarriorKitChatSecureButton:LeftButton",
	"enter was left on the secure button after the line was called off")
check(Window.Ghost() ~= nil and Window.Ghost():find("press enter again", 1, true) == nil,
	("the empty line still reads %q after the line was called off")
		:format(tostring(Window.Ghost())))

-- /exit is nobody's command in this client, so the button carries /quit.
-- A button loaded with the word the player typed would reach a slash list
-- with no such entry and do nothing at all, which looks from the field
-- exactly like the bug this whole arrangement is for.
Window.Send("/exit")
check(Compose.Armed() == "/quit",
	("/exit loaded the key with %s rather than the client's own word for it")
		:format(tostring(Compose.Armed())))
check(_G.WarriorKitChatSecureButton:GetAttribute("macrotext") == "/quit",
	"the button was armed with something other than /quit")
Window.Focus()

-- Loading the key while you type.
--
-- It is still two presses. The button runs on the down edge, the down edge of
-- a press aimed at a field with the focus belongs to the field, and there is no
-- third edge to hand the client. What this buys is that the second press is
-- certain: arming on the enter meant the binding did not exist yet when the key
-- went down, so which press ran the line depended on when the client re-read
-- the binding set.
--
-- What is asserted is therefore the state of the key with the word typed and no
-- enter pressed, which is the whole of what the harness can see. Whether the
-- client then runs the macro is a question for the game.
Window.Type("/logout")
check(Compose.Armed() == "/logout",
	("typing the word loaded the key with %s before any enter was pressed")
		:format(tostring(Compose.Armed())))
check(_G.GetBindingAction("ENTER", true) == "CLICK WarriorKitChatSecureButton:LeftButton",
	("enter is on %q with the line still in the field")
		:format(tostring(_G.GetBindingAction("ENTER", true))))
-- And it is on the key the chat line is on rather than on enter by name, so a
-- player who moved OPENCHAT gets the key they moved it to. Everything else the
-- field sees is untouched, because a field that put a line under every key
-- would be a field where typing "1" logs you out.
check(Compose.ArmedOn("ENTER"), "the line went somewhere other than the chat key")
check(not Compose.ArmedOn("1"), "a character key was left carrying the line")

-- Typing on past the word hands the key straight back, because a key still
-- loaded with a line nobody is going to send is a key that no longer opens
-- the chat line.
Window.Type("/logou")
check(Compose.Armed() == nil,
	("a half typed word left the key holding %s"):format(tostring(Compose.Armed())))
check(_G.GetBindingAction("ENTER", true) ~= "CLICK WarriorKitChatSecureButton:LeftButton",
	"enter was left on the secure button after the word was typed past")

-- What comes after the word goes on the button with it. A line loaded with
-- the command and none of its argument is a /target that targets nothing,
-- which from the field looks exactly like a key press that did nothing.
Window.Type("/target Aria")
check(Compose.Armed() == "/target Aria",
	("the key was loaded with %s rather than the whole line")
		:format(tostring(Compose.Armed())))
check(_G.WarriorKitChatSecureButton:GetAttribute("macrotext") == "/target Aria",
	"the button carries something other than the line in the field")

-- The translation happens while you type too, and it keeps what was typed
-- after the word for the same reason.
Window.Type("/exit")
check(Compose.Armed() == "/quit",
	("/exit loaded the key with %s while it was being typed")
		:format(tostring(Compose.Armed())))

-- An ordinary line never takes the key. Every character of every message
-- goes through the same handler, and one that armed on any of them would be
-- an enter that logs you out instead of saying hello.
Window.Type("/p hello")
check(Compose.Armed() == nil,
	("a chat line loaded the key with %s"):format(tostring(Compose.Armed())))
check(not Compose.ArmedOn("ENTER"), "enter was left carrying a line on an ordinary message")
Window.Type("")

-- The down edge of the press, and what the field must not do on it. The field
-- empties and gives the focus up the moment it is told the line is finished,
-- and emptying is a text change like any other: read plainly it says the field
-- no longer holds a line that needs the key, and the key goes back to the
-- window out from under the press that was about to run it. Which is a key the
-- log says is loaded, a readback that agrees, and an enter that does nothing.
--
-- That shipped, and it shipped because the field worked out whether to hold on
-- by comparing its own text against the line on the key. The two can differ by
-- a space. So the field holds on for the whole handler now, unconditionally,
-- and this is checked with a line the field never armed as well as with one it
-- did, because the comparison is exactly what stopped being trusted.
--
-- The focus going is the other half and it is not decoration. The bindings
-- underneath a field that has the focus do not fire at all, so the up edge only
-- reaches the button because the down edge let the field go.
Window.Focus()
Window.Type("/logout")
Window.Enter()
check(Compose.Armed() == "/logout",
	("the press left the key holding %s"):format(tostring(Compose.Armed())))
check(_G.GetBindingAction("ENTER", true) == "CLICK WarriorKitChatSecureButton:LeftButton",
	("enter is on %q after the field emptied itself")
		:format(tostring(_G.GetBindingAction("ENTER", true))))
check(Window.Line() == "",
	("the field still reads %q after the line was finished"):format(Window.Line()))

-- And the focus going late, which is how the client reports it and is what took
-- the key back with the press still in the air. The log said loaded and then
-- handed back, one line under the other, with no press between them.
Window.Blur()
check(Compose.Armed() == "/logout",
	("the focus going after the press left the key holding %s")
		:format(tostring(Compose.Armed())))
check(_G.GetBindingAction("ENTER", true) == "CLICK WarriorKitChatSecureButton:LeftButton",
	("enter is on %q once the focus has gone")
		:format(tostring(_G.GetBindingAction("ENTER", true))))
-- And the same on a line the field did not put there itself. Handover loads the
-- key from inside the press rather than before it, so the field has no text to
-- compare against and the old reading came back false here too.
Window.Focus()
Window.Type("")
Window.Send("/logout")
check(Compose.Armed() == "/logout", "the handover did not load the key")
Window.Enter()
Window.Blur()
check(Compose.Armed() == "/logout",
	("the press left the key holding %s after a handover")
		:format(tostring(Compose.Armed())))

-- And the line goes when the client runs it.
_G.WarriorKitChatSecureButton:Click("LeftButton", true)
check(Compose.Armed() == nil, "the line ran and the enter key was left loaded")
Window.Focus()
Window.Type("")

-- The log, driven rather than read.
--
-- It is an instrument in the click path and in the typing path, which is the
-- two places in this addon where an instrument has already broken what it was
-- measuring once. So the word that turns it on is run here as a player runs it,
-- and every line it writes is written with it on. A debug switch that throws is
-- a debug switch that costs you the evening you turned it on to save.
_G.SlashCmdList.WARRIORKIT("chat debug on")
check(ns.db.chatDebug == true,
	("the word left the log %s"):format(tostring(ns.db.chatDebug)))
check(Window.Shown(), "turning the log on closed the chat window")

Window.Focus()
Window.Type("/logout")
check(Compose.Armed() == "/logout", "nothing was loaded with the log on")
Window.Enter()
check(Compose.Armed() == "/logout", "the press with the log on left the key empty")
_G.WarriorKitChatSecureButton:Click("LeftButton", true)
check(Compose.Armed() == nil, "the press with the log on left the key loaded")
check(Window.Shown(), "a press with the log on closed the chat window")

_G.SlashCmdList.WARRIORKIT("chat debug off")
check(ns.db.chatDebug == false,
	("the word left the log %s"):format(tostring(ns.db.chatDebug)))
check(Window.Shown(), "turning the log off closed the chat window")
Window.Focus()
Window.Type("")

-- A refusal says which refusal it is. There are three, they need three
-- different things from the player, and one "it did not work" for all of
-- them is the sentence that sent this bug round twice.
local wasCombat = _G.InCombatLockdown
_G.InCombatLockdown = function() return true end
local told = Window.Count(Window.Room())
Window.Send("/logout")
check(Compose.Armed() == nil, "a key was loaded in combat, which the client refuses")
check(Window.Count(Window.Room()) == told + 1,
	"a refusal in combat said nothing in the room the line was typed in")
_G.InCombatLockdown = wasCombat

-- And the same word typed anywhere else in the game, because /exit is a
-- slash command of the addon's own rather than a spelling the chat field
-- knows. The handler cannot call Quit() itself: it is our function, and a
-- protected call refuses our call stack the same way /logout's does.
_G.SlashCmdList.WARRIORKITEXIT("")
check(Compose.Armed() == "/quit",
	("/exit typed outside the window loaded the key with %s")
		:format(tostring(Compose.Armed())))
Window.Focus()

-- And again with Blizzard's window hidden, which is the arrangement every
-- player who uses this window is in and the one the two claims collide in.
-- The window is already holding enter here, so arming it is one owner
-- taking a key off another, and a run that only ever tested the free key
-- tested the case nobody is in.
local heldBlizz = ns.db.hideBlizzChat
ns.db.hideBlizzChat = true
Window.Keys()
check(_G.GetBindingAction("ENTER", true) == "CLICK WarriorKitChatEnterButton:LeftButton",
	"the window did not have the enter key to give up")
Window.Send("/logout")
check(Compose.Armed() == "/logout",
	("the enter key was loaded with %s while the window held it")
		:format(tostring(Compose.Armed())))
check(_G.GetBindingAction("ENTER", true) == "CLICK WarriorKitChatSecureButton:LeftButton",
	("enter is on %q with the window's own claim underneath")
		:format(tostring(_G.GetBindingAction("ENTER", true))))
-- The window's claim is gone rather than sitting under the new one. Two
-- owners on one key is the client's arrangement to resolve and not ours,
-- and the way not to depend on it is to leave one.
check(_G.GetBindingAction("NUMPADENTER", true)
	== "CLICK WarriorKitChatSecureButton:LeftButton",
	("the second enter key is on %q")
		:format(tostring(_G.GetBindingAction("NUMPADENTER", true))))

-- The line ran, so the button hands the key straight back and the window is
-- holding both of them again.
_G.WarriorKitChatSecureButton:Click("LeftButton", true)
check(Compose.Armed() == nil, "the line ran and the enter key was left loaded")
check(_G.GetBindingAction("ENTER", true) == "CLICK WarriorKitChatEnterButton:LeftButton",
	("enter came back as %q rather than the window's own button")
		:format(tostring(_G.GetBindingAction("ENTER", true))))
-- A player who moved the chat key off enter. The line has to land on the key
-- they moved it to, and the only way to find out which key that is is to ask
-- the client after the window has given it back: while the window's own
-- claim is on the key, the key carries the window and not OPENCHAT, and
-- asking then answers nothing and falls through to the literal enter.
local wasChat = _G.WarriorKitBindings.OPENCHAT
_G.WarriorKitBindings.OPENCHAT = { "F12" }
Window.Keys()
check(_G.GetBindingAction("F12", true) == "CLICK WarriorKitChatEnterButton:LeftButton",
	"the window did not follow the chat key to where the player moved it")
Window.Send("/logout")
check(_G.GetBindingAction("F12", true) == "CLICK WarriorKitChatSecureButton:LeftButton",
	("the line went onto %q rather than onto the key the chat line is on")
		:format(tostring(_G.GetBindingAction("F12", true))))
check(_G.GetBindingAction("ENTER", true) == "",
	("enter was armed as well, and it carries %q")
		:format(tostring(_G.GetBindingAction("ENTER", true))))
_G.WarriorKitChatSecureButton:Click("LeftButton", true)
_G.WarriorKitBindings.OPENCHAT = wasChat

ns.db.hideBlizzChat = heldBlizz
Window.Keys()

-- The client's own list and ours, unioned rather than one replacing the other.
-- /follow is the client's alone and /petattack is ours alone, and both have to
-- come back as a line for the key, or a word one side names has been dropped.
check(Compose.Secure("/follow Bob") == "/follow Bob",
	"a word only the client's IsSecureCmd names did not take the key")
check(Compose.Secure("/petattack") == "/petattack",
	"a word only our own list names did not take the key")
check(Compose.Secure("/dance") == nil,
	"a word neither side names took the key it does not need")
-- The alias is asked ahead of the client, because the client has never heard
-- of /exit and would answer no about the one line that needs the key most.
check(Compose.Secure("/exit") == "/quit",
	"/exit did not come back as the client's own word for leaving")

print(("chatkey the client's own IsSecureCmd over %d words of our own, loaded onto the chat key while you type and run on the down edge of a press the field is not holding")
	:format(Compose.Words()))
