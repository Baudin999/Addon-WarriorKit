-- The line the client owns
--
-- Three questions, and none of them can be answered by reading Chat/.
--
-- Whose frame do the characters go into. `/logout` ends in Logout(), and the
-- client refuses Logout() from any call stack an addon has been in. A field of
-- the addon's own puts a function of the addon's in that stack, so the press
-- that finished the line came back as a red line naming WarriorKit rather than
-- as a character logging out, and no arrangement of secure buttons and override
-- bindings ever got that down to one press. The fix was to stop building a
-- field. This section reads back that the window types into ChatFrame1EditBox
-- and that its OnEnterPressed is still the one the client set.
--
-- Whose keys open it. Both chat keys were the window's for a while, bound onto
-- buttons of its own so that enter opened the line down here rather than the
-- invisible one behind it. That is what cost the first press: a key bound to a
-- button of ours opens the line from a script of ours. Nothing is bound now,
-- and the readback is that nothing is.
--
-- Does the room's slash survive the open. The client activates the field and
-- then writes what the key asked for, which for enter is an empty string, so
-- anything written while the field was activating is blanked a moment later.
-- Chat/Field.lua writes it again off the blanking. From a chair the two
-- versions are one line that reads `/p ` and one that reads nothing at all.
--
-- Split out of 29-social.lua for the reason 41-voice.lua was: the social part
-- is the rooms and what you read in them, this is the field underneath, and the
-- two together were over the eight hundred line budget.

local H = ...
local chat = H.chat
local ns, check = H.ns, H.check

local Window, Field = ns.ChatWindow, ns.ChatField

----------------------------------------------------------------------
-- The frame
----------------------------------------------------------------------

local heldBlizz = ns.db.hideBlizzChat
ns.db.hideBlizzChat = true
Window.Show()
Window.Apply()

local line = Window.Entry()
check(line ~= nil, "there is no line to type in at all")
check(line:GetName() == "ChatFrame1EditBox",
	("the window types into %q rather than into the client's own line")
		:format(tostring(line and line:GetName())))

-- Nothing of the addon's on the one handler that matters. The client sets
-- OnEnterPressed in XML and a press runs it with nothing of ours between; an
-- addon that replaced it would be back where this whole section started, and
-- the only trace of the difference is which function is on the frame.
--
-- The stub in client/07-chat.lua is what set this one, so the check is that the
-- addon left it alone rather than that it exists.
local pressed = line:GetScript("OnEnterPressed")
check(type(pressed) == "function", "the client's own enter handler is gone off the line")
Field.Adopt()
check(line:GetScript("OnEnterPressed") == pressed,
	"dressing the line a second time replaced the client's own enter handler")

-- Every field the client has, not the first. Which one a press opens is
-- ChatEdit_ChooseBoxForSend's answer, and a field the addon never dressed comes
-- up in Blizzard's art in the middle of a window drawn without any.
check(Field.Count() == _G.NUM_CHAT_WINDOWS,
	("%d of the client's %d lines were dressed")
		:format(Field.Count(), _G.NUM_CHAT_WINDOWS))
check(not _G.ChatFrame2EditBoxLeft:IsShown(),
	"the second window's line kept the client's own border")

----------------------------------------------------------------------
-- The style
--
-- The client writes its own font, colour and inset over the addon's every time
-- ChatEdit_UpdateHeader runs, which is on activation and on every change of
-- channel. So this is not a check that the style was applied. It is a check
-- that it was applied last, after the client had been at it, which is the only
-- version of it anybody sees.
----------------------------------------------------------------------

local UI, C = ns.UI, ns.UI.Color

_G.ChatEdit_DeactivateChat(line)
_G.ChatFrame_OpenChat("")

local ours = UI.Font(ns.db.chatFont, UI.FLAT)
check(line:GetFontObject() == ours,
	"the line you type in is drawn in the client's own font rather than the addon's")

local r, g, b = line:GetTextColor()
check(r == C.text[1] and g == C.text[2] and b == C.text[3],
	("the line you type in is %s rather than the addon's own text colour")
		:format(table.concat({ tostring(r), tostring(g), tostring(b) }, ", ")))

-- The header is the word FrameXML draws where the slash you typed used to be,
-- and it is the one string here that keeps the channel's own colour. What it
-- does not keep is the client's font.
local header = _G.ChatFrame1EditBoxHeader
check(header:GetFontObject() == ours,
	"the word in front of the line is drawn in the client's own font")
local _, headerAt, _, headerX = header:GetPoint(1)
check(headerAt == line and headerX == 4,
	("the word in front of the line sits %s px in, on the client's own margin")
		:format(tostring(headerX)))

-- And the text clears it by the addon's own margin rather than FrameXML's
-- fifteen, which is what a line of Blizzard's art needed and ours does not.
local inset = line:GetTextInsets()
check(inset == 4 + header:GetWidth() + 6 + 4,
	("the line starts %s px in, expected the header and two margins")
		:format(tostring(inset)))

-- Blizzard's art off, and off by a walk rather than by a list of names. Every
-- texture on the frame, because the pieces differ between the two clients this
-- addon ships for and a name that is right on one is nothing on the other.
for _, name in ipairs({ "ChatFrame1EditBoxLeft", "ChatFrame1EditBoxRight",
	"ChatFrame1EditBoxMid" }) do
	check(not _G[name]:IsShown() and _G[name]:GetAlpha() == 0,
		("%s is still drawn round the line"):format(name))
end
check(line.focusLeft:GetAlpha() == 0,
	"the client's focus glow is still drawn round the line")

-- Now move the channel, which is what makes this worth a section of its own:
-- the client repaints on the way through and the addon has to have the last
-- word every time rather than once at login.
line:SetAttribute("chatType", "WHISPER")
_G.ChatEdit_UpdateHeader(line)
_G.ChatEdit_DeactivateChat(line)
_G.ChatFrame_OpenChat("")
check(line:GetFontObject() == ours,
	"changing channel gave the line the client's font back")
local wr, wg, wb = line:GetTextColor()
check(wr == C.text[1] and wg == C.text[2] and wb == C.text[3],
	"changing channel painted the line you type in the channel's colour")
check(header:GetFontObject() == ours,
	"changing channel gave the header the client's font back")
line:SetAttribute("chatType", "SAY")
_G.ChatEdit_DeactivateChat(line)

----------------------------------------------------------------------
-- The keys
--
-- Neither of them is the window's. This is the assertion that the fix is still
-- the fix: a binding here is a script of ours back in the path, whatever else
-- reads correctly.
----------------------------------------------------------------------

check(_G.GetBindingAction("ENTER", true) == "",
	("the enter key is bound to %q"):format(_G.GetBindingAction("ENTER", true)))
check(_G.GetBindingAction("NUMPADENTER", true) == "",
	("the numpad enter key is bound to %q"):format(_G.GetBindingAction("NUMPADENTER", true)))
check(_G.GetBindingAction("/", true) == "",
	("the slash key is bound to %q"):format(_G.GetBindingAction("/", true)))
check(_G.WarriorKitChatSecureButton == nil,
	"the secure button the line used to be run off is still being built")
check(_G.WarriorKitChatEnterButton == nil,
	"the button the enter key used to be bound onto is still being built")

----------------------------------------------------------------------
-- Opening it
----------------------------------------------------------------------

-- The client's own enter key, in the order FrameXML runs it: pick the field,
-- activate it, then write what the key asked for. That last write is an empty
-- string and it lands after the focus, so a room prefix written on the focus
-- alone is gone by the time anybody sees the line.
--
-- Shut first, because the client only activates a field that is not already
-- active, and a section that inherited an open line would be reading the last
-- line opened rather than this one.
_G.ChatEdit_DeactivateChat(line)
Window.Go(ns.Rooms.ALL)
_G.ChatFrame_OpenChat("")
check(Window.Line() == "/s ",
	("enter left the line reading %q, expected \"/s \""):format(Window.Line()))
check(line:IsShown(), "the line was opened and not shown")

-- The slash key opens a line with a slash in it and no room prefix, because the
-- prefix would turn /dance into a sentence said out loud in party.
_G.ChatEdit_DeactivateChat(line)
_G.ChatFrame_OpenChat("/")
check(Window.Line() == "/",
	("the slash key opened the line with %q, expected \"/\""):format(Window.Line()))

-- A line you came back to keeps what you had typed. The fill is for an empty
-- field and a half typed sentence is not one.
_G.ChatEdit_DeactivateChat(line)
Window.Type("half a sentence")
_G.ChatFrame_OpenChat("half a sentence")
check(Window.Line() == "half a sentence",
	("coming back to a half typed line left it reading %q"):format(Window.Line()))
_G.ChatEdit_DeactivateChat(line)
Window.Type("")

-- With the prefix turned off the line opens empty, and the client's own sticky
-- channel is what decides where it goes. That is the setting doing what it
-- says rather than the fill failing.
local heldPrefix = ns.db.chatPrefix
ns.db.chatPrefix = false
_G.ChatFrame_OpenChat("")
check(Window.Line() == "",
	("the prefix is off and the line still opened reading %q"):format(Window.Line()))
_G.ChatEdit_DeactivateChat(line)
ns.db.chatPrefix = heldPrefix

----------------------------------------------------------------------
-- Sending
----------------------------------------------------------------------

-- A command the player typed goes to the client's parser off the client's own
-- handler, in one press, with nothing of the addon's in between. That is the
-- whole of the bug this window had and the whole of the fix.
local handed = #chat.slash
_G.ChatFrame_OpenChat("")
Window.Type("/logout")
Window.Enter()
check(#chat.slash == handed + 1,
	"the press did not hand the line to the client's parser at all")
check(chat.slash[#chat.slash] == "/logout",
	("the client's parser was handed %q"):format(tostring(chat.slash[#chat.slash])))
check(Window.Line() == "",
	("the line still reads %q after the press"):format(Window.Line()))

-- And nothing is left holding it afterwards. The version before this loaded the
-- command onto the enter key and needed a second press; a key still carrying
-- something here would be that version coming back.
check(_G.GetBindingAction("ENTER", true) == "",
	("the press left the enter key carrying %q")
		:format(_G.GetBindingAction("ENTER", true)))

-- An ordinary sentence still goes out as a sentence rather than to the parser.
local sent = #chat.sent
Window.Send("hello")
check(#chat.sent == sent + 1, "a plain line was not sent")
check(chat.sent[#chat.sent].kind == "SAY",
	("a plain line from Conversation went to %s")
		:format(tostring(chat.sent[#chat.sent].kind)))

----------------------------------------------------------------------
-- What the empty line says
----------------------------------------------------------------------

-- The room and what enter would do in it, and nothing about pressing enter
-- twice, because no command waits on a second press any more.
_G.ChatEdit_DeactivateChat(line)
check(Window.Ghost() == "Conversation, enter types /s",
	("the empty line reads %q"):format(tostring(Window.Ghost())))

----------------------------------------------------------------------
-- Putting it back
--
-- The field is the client's and it is on loan. A window that goes away with the
-- field still anchored inside it is a game with no way to type at all, which is
-- the one failure here worse than the one this section exists for.
----------------------------------------------------------------------

Window.Hide()
local point, relative = line:GetPoint(1)
check(relative == _G.UIParent,
	("the window closed and left the line anchored to %s")
		:format(tostring(relative and relative.name or relative)))
check(point == "BOTTOMLEFT",
	("the line went back to the screen by %q"):format(tostring(point)))

Window.Show()
Window.Apply()
local _, back = line:GetPoint(1)
check(back == Window.Field(),
	"opening the window again did not take the line back into the footer")

ns.db.hideBlizzChat = heldBlizz
Window.Apply()

print(("chatline the client's own %s, on the client's own keys, %d dressed")
	:format(tostring(line and line:GetName()), Field.Count()))
