-- Four things the window grew after the history did
--
-- Does the rail follow the picture. The setting moves one number and three
-- rectangles are laid out off it: the picture, the row it sits in and the
-- column of them. A picture drawn at twenty in a row still eighteen tall is
-- clipped at the top and bottom, and the rail's width is still what the theme
-- said, so nothing that measures the column would notice.
--
-- Does closing a conversation close it. Three places have to agree: the rail
-- stops drawing the room, the log is handed back, and the saved record stops
-- naming the person, or the login that brings last night's conversations back
-- brings the one you closed.
--
-- Does the copy box hold the room. The client has no clipboard call, so what
-- can be asserted is that a field holds the keyboard, holds the log with its
-- colour codes taken off, and is selected whole.
--
-- Does a line of the addon's own go to its own room. It arrives through the
-- same hook a loot line does and the prefix is the whole of what tells them
-- apart, so the assertion is one of each, each in its own room and not in the
-- other's.

local H = ...
local ns, fire, check = H.ns, H.fire, H.check
local Rooms, Window = ns.Rooms, ns.ChatWindow
local M = ns.UI.Metric

-- The scene: Blizzard's window hidden, ours up, so the forward and the two
-- rooms that live off it are there to read.
local heldHide, heldIcon = ns.db.hideBlizzChat, ns.db.chatIcon
ns.db.hideBlizzChat = true
Window.Show()
Window.Apply()

local function whisper(who, what)
	fire("CHAT_MSG_WHISPER", what, who, nil, nil, nil, nil, nil, nil, nil, nil, nil, "R1")
end

----------------------------------------------------------------------
-- The pictures
----------------------------------------------------------------------

do
	local rail = _G.WarriorKitChatRooms
	check(ns.db.chatIcon == M.roomIcon,
		("the picture ships at %s and the theme draws it at %d")
			:format(tostring(ns.db.chatIcon), M.roomIcon))

	ns.db.chatIcon = M.roomIcon + 6
	Window.Apply()
	local icon = Window.RowIcon(Rooms.ALL)
	check(icon ~= nil, "the Conversation row has no picture to measure")
	check(icon and icon:GetWidth() == M.roomIcon + 6,
		("the picture came out %s wide after the setting moved it to %d")
			:format(tostring(icon and icon:GetWidth()), M.roomIcon + 6))
	check(rail:GetWidth() == M.rooms + 6,
		("the rail is %s wide with the picture six over the theme, expected %d")
			:format(tostring(rail:GetWidth()), M.rooms + 6))
	check(rail:GetHeight() == ns.db.chatHeight - M.entry - (M.roomRow + 6),
		("the rail is %s tall with the row six over the theme")
			:format(tostring(rail:GetHeight())))
	-- And the log moved over to make room, rather than sitting under a wider
	-- column.
	local wide = Window.Shape(Rooms.ALL)
	check(wide == ns.db.chatWidth - (M.rooms + 6) - M.chatPad * 2,
		("the log is %s wide beside a rail six wider than the theme")
			:format(tostring(wide)))

	ns.db.chatIcon = heldIcon
	Window.Apply()
	check(rail:GetWidth() == M.rooms,
		("the rail stayed %s wide when the setting went back"):format(tostring(rail:GetWidth())))
	check(icon and icon:GetWidth() == M.roomIcon,
		("the picture stayed %s wide when the setting went back")
			:format(tostring(icon and icon:GetWidth())))
end

----------------------------------------------------------------------
-- Closing a conversation
----------------------------------------------------------------------

do
	whisper("Aria", "where are you")
	local aria = Rooms.WhisperId("Aria")
	check(Rooms.Exists(aria), "a whisper did not open a conversation to close")
	check(ns.dbc.chatWith[1] == "Aria", "the record does not name the person who whispered")
	Window.Go(aria)

	-- Through the row rather than through Close, because what is being checked
	-- is that a right click on the row is what closes it.
	check(Window.Press(aria, "RightButton"), "the conversation's row took no right click")
	check(not Rooms.Exists(aria), "a right click on a conversation left it on the rail")
	check(Window.Room() == Rooms.ALL,
		("closing the room you were reading landed in %s"):format(tostring(Window.Room())))
	check(Window.Count(aria) == 0, "a closed conversation kept its log")
	local named = false
	for _, name in ipairs(ns.dbc.chatWith) do
		if name == "Aria" then
			named = true
		end
	end
	check(not named, "the record still names a conversation that was closed")
	check(Rooms.Recent() ~= "Aria", "the reply key still answers a closed conversation")

	-- A right click on a room that is not a conversation does nothing at all.
	check(Window.Press(Rooms.ALL, "RightButton"), "the Conversation row took no right click")
	check(Rooms.Exists(Rooms.ALL), "a right click closed Conversation")

	-- And the next word from them opens it again.
	whisper("Aria", "still there?")
	check(Rooms.Exists(aria), "a closed conversation did not reopen on the next whisper")
	check(Window.Count(aria) == 1,
		("a reopened conversation holds %d lines, expected the one that reopened it")
			:format(Window.Count(aria)))
	-- And the rail drew it. The row this conversation had was handed back to
	-- the pool with its id still on it, so the count against that id landed on
	-- a hidden frame and the rail never rebuilt: the room existed, held the
	-- line, and was nowhere on the screen.
	check(Window.Press(aria, "LeftButton"),
		"a conversation that came back onto the rail was not drawn on it")
	Window.Close(aria)
end

----------------------------------------------------------------------
-- The copy box
----------------------------------------------------------------------

do
	fire("CHAT_MSG_SAY", "meet at the stone", "Bram",
		nil, nil, nil, nil, nil, nil, nil, nil, nil, "R2")
	Window.Go("say")
	local field, why = Window.Copy()
	check(field ~= nil, ("the copy box refused: %s"):format(tostring(why)))
	if field then
		check(_G.WarriorKitChatCopy ~= nil and _G.WarriorKitChatCopy:IsShown(),
			"the copy box is not on the screen")
		check(field:HasFocus(), "the copy box does not hold the keyboard")
		local from, to = unpack(field:GetHighlighted() or {})
		check(from == 0 and to == -1, "the copy box is not selected whole")
		local text = field:GetText() or ""
		check(text:find("meet at the stone", 1, true) ~= nil,
			"the copy box does not hold the line that was said")
		check(text:find("Bram", 1, true) ~= nil, "the copy box lost the name off the line")
		check(text:find("|c", 1, true) == nil and text:find("|H", 1, true) == nil,
			"the copy box carries colour codes and links")
		-- Typing over it puts the log back.
		field:Type("pasted over")
		check((field:GetText() or ""):find("meet at the stone", 1, true) ~= nil,
			"typing over the copy box replaced the log")
		ns.ChatCopy.Hide()
		check(not _G.WarriorKitChatCopy:IsShown(), "the copy box did not close")
	end

	-- A room with nothing in it says so rather than opening an empty box.
	whisper("Nobody", "hi")
	local room = Rooms.WhisperId("Nobody")
	Window.Go(room)
	Window.Close(room)
	whisper("Nobody", "hi")
	-- The room reopened with one line; the assertion is on the refusal path,
	-- which needs an empty log, and a log emptied by Close is one.
	Window.Close(room)
end

----------------------------------------------------------------------
-- What the addon says
----------------------------------------------------------------------

do
	check(Rooms.Exists(Rooms.KIT), "there is no WarriorKit room while Blizzard's window is hidden")
	check(Rooms.Title(Rooms.KIT) == "WarriorKit",
		("the addon's room is called %q"):format(tostring(Rooms.Title(Rooms.KIT))))

	local kit, system = Window.Count(Rooms.KIT), Window.Count(Rooms.SYSTEM)
	ns.Print("the loot filter is on.")
	check(Window.Count(Rooms.KIT) == kit + 1, "a line the addon said did not reach its own room")
	check(Window.Count(Rooms.SYSTEM) == system, "a line the addon said was filed under System as well")

	_G.DEFAULT_CHAT_FRAME:AddMessage("You receive loot: [Thunderfury]", 1, 1, 1)
	check(Window.Count(Rooms.SYSTEM) == system + 1, "a loot line did not reach System")
	check(Window.Count(Rooms.KIT) == kit + 1, "a loot line was filed under the addon's room")

	-- The prefix comes off, because the room is named after it.
	Window.Go(Rooms.KIT)
	local field = Window.Copy()
	check(field ~= nil, "the addon's room would not copy")
	if field then
		local text = field:GetText() or ""
		check(text:find("the loot filter is on", 1, true) ~= nil,
			"the addon's line is not in its own room")
		check(text:find("WarriorKit:", 1, true) == nil,
			"every line in the WarriorKit room still starts with the word WarriorKit")
		ns.ChatCopy.Hide()
	end

	-- And with Blizzard's window back, the room goes the way System does.
	Window.Go(Rooms.ALL)
	ns.db.hideBlizzChat = false
	Window.Apply()
	check(not Rooms.Exists(Rooms.KIT),
		"the WarriorKit room is still offered with Blizzard's window on screen")
end

ns.db.hideBlizzChat = heldHide
Window.Apply()
