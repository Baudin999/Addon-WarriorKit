local ADDON, ns = ...

local Field = {}
ns.ChatField = Field

local UI = ns.UI
local C = UI.Color

--------------------------------------------------------------------------
-- The line you type in, which is the client's own
--
-- This window does not build a field. It borrows the client's, strips the art
-- off it, and anchors it into the footer. Everything a player sees is ours and
-- the frame underneath is Blizzard's, which is the whole point.
--
-- **Why, in one paragraph.** `/logout` ends in Logout(), and the client refuses
-- Logout() from any call stack an addon has been in. A field of our own puts a
-- function of ours in that stack: the client dispatches the key press into our
-- OnEnterPressed, our handler calls the client's parser, and the protected call
-- at the end of it is dropped. Blizzard's field has its OnEnterPressed set in
-- XML, so the press goes from the keyboard into Blizzard code with nothing of
-- ours between, and the command runs. There is no way to fake that from a field
-- we made, which is why the version before this ran protected commands off a
-- secure button and asked the player to press enter twice.
--
-- Prat is where this arrangement is taken from and it has shipped for fifteen
-- years without a /logout bug, because it never had one to fix: the only two
-- edit boxes in it are for copying chat and for search, and the line you send
-- from is always ChatFrame1EditBox. It hides the three border textures, fades
-- the focus glow, sets a font, and anchors the frame wherever it likes.
--
-- **The one rule.** Nothing here calls SetScript on the client's field. Every
-- script it has is Blizzard's and has to stay Blizzard's, or the press that
-- reaches OnEnterPressed is running our replacement and we are back where we
-- started. HookScript chains under what is already there and is safe, and it is
-- the only way this file touches a handler.
--
-- **What we are allowed to write.** The text and the attributes. Both are read
-- back out of C rather than out of a Lua table, so writing them from here does
-- not taint what the client later reads, and Prat's own history module writes
-- the text from an arrow key hook for exactly this reason. Nothing in this file
-- writes a field on the frame or a global of FrameXML's.
--
-- **Who opens it.** The client, off its own OPENCHAT and OPENCHATSLASH keys.
-- This window used to take both keys onto buttons of its own and open the field
-- from a script; that is gone, because a key the client owns end to end is one
-- less thing between the press and the command. ChatWindow.Focus still opens
-- the field from a click on a name, and that path is ours, which is fine: it is
-- for whispering somebody, not for logging out.
--------------------------------------------------------------------------

-- The three border textures and the focus glow, by the names FrameXML gives
-- them. Probed rather than assumed, because the glow is only on the clients
-- that grew it and a missing one has to cost that texture rather than the
-- field.
local SKIN = { "Left", "Right", "Mid" }
local GLOW = { "focusLeft", "focusRight", "focusMid" }

-- Every field we have dressed, and what it was anchored to before we moved it.
-- One entry per numbered chat window rather than one for the first, because
-- which field the client opens is ChatEdit_ChooseBoxForSend's answer and not
-- ours: a player whose last active window was the second one gets the second
-- one's field, and a field we never dressed would come up in Blizzard's art at
-- the bottom of the screen.
local dressed, home = {}, {}

-- Whether the fields are sitting in our footer right now, and the frame they
-- are sitting in. Held so that a field dressed after the window was laid out
-- lands in the right place, which is the case a client with ten chat windows
-- reaches the first time somebody opens the tenth.
local anchored, footer

-- Set to true while a field is being filled in, so the write does not come back
-- round through the hook that asked for it.
local filling = false

-- True from the moment a field takes the focus until the moment it has been
-- filled in. See Opened below: it is the flag that lets one SetText through and
-- no more.
local waiting = false

--------------------------------------------------------------------------
-- What the window wants to know
--
-- Assigned by Chat/Window.lua at build, in the shape ns.Voice.OnChange is
-- assigned, and left nil the rest of the time. A field is dressed whether or
-- not anybody is listening, because the client can open one before the window
-- has been built and a field in Blizzard's art in the middle of our footer is
-- worse than one nobody is painting round.
--------------------------------------------------------------------------

-- What to put in an empty line, called with the field. Returns true if it wrote
-- something, which is what stops the fill happening twice.
Field.OnFill = nil

-- The cursor arriving or leaving, called with true or false. The window draws
-- the rectangle round the line on this and hides the sentence in it.
Field.OnLight = nil

-- The text moving, called with what is in the field. The window shows and hides
-- the sentence behind it on this.
Field.OnType = nil

-- Tab, which steps the window to the next room. Under the client's own handler
-- rather than instead of it, because the client cycles the field's chat type on
-- this key and taking the script away to stop that would take OnEnterPressed's
-- neighbour with it.
Field.OnTab = nil

--------------------------------------------------------------------------

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, answer = pcall(fn, ...)
	return ok and answer or nil
end

-- How many chat windows this client has. The same guard Chat/Blizzard.lua uses
-- and for its reason: the count is the client's, a whisper can raise it, and
-- ten is the answer on every client this addon ships for.
local function Windows()
	local count = _G.NUM_CHAT_WINDOWS
	if type(count) ~= "number" or count < 1 then
		return 10
	end
	return count
end

--------------------------------------------------------------------------
-- Opening
--
-- The client's own OPENCHAT does three things in this order: it picks a field,
-- it activates it, and then it writes the text the key asked for. Enter asks
-- for an empty line and the slash key asks for "/". That last write is the
-- problem this section exists to solve: anything we put in the field while it
-- was activating is gone by the time the player sees it.
--
-- So the room's slash is written twice and the flag below is what makes that
-- safe. The focus arriving sets it and fills the line. If the client then
-- blanks what we wrote, the blanking is a change, the change raises
-- OnTextChanged, and the hook fills the line again and drops the flag. If the
-- client blanks nothing, the flag comes down when the focus goes.
--
-- Nothing else can get through it. A write the player made carries the client's
-- own userInput argument and is skipped on that alone; a write of ours is
-- skipped on `filling`; a write that leaves anything at all in the line is
-- skipped because the line is not empty, which is how the slash key keeps its
-- "/" and how a line you came back to keeps what you had typed.
--------------------------------------------------------------------------

local function Fill(box)
	if filling or type(Field.OnFill) ~= "function" then
		return false
	end
	filling = true
	local ok, wrote = pcall(Field.OnFill, box)
	filling = false
	return ok and wrote and true or false
end

local function Opened(box, userInput)
	if userInput or filling or not waiting then
		return
	end
	if (box:GetText() or "") ~= "" then
		return
	end
	waiting = false
	Fill(box)
end

--------------------------------------------------------------------------
-- Dressing one field
--------------------------------------------------------------------------

-- The art off, in the order Prat takes it off: the three border pieces hidden
-- outright, and the focus glow faded rather than hidden, because on the clients
-- that have it the client shows those three itself every time the field takes
-- the focus and a hidden one would come straight back.
local function Strip(box, name)
	for _, part in ipairs(SKIN) do
		local piece = _G[name .. part]
		if type(piece) == "table" and type(piece.Hide) == "function" then
			piece:Hide()
		end
	end
	for _, part in ipairs(GLOW) do
		local piece = box[part]
		if type(piece) == "table" and type(piece.SetAlpha) == "function" then
			piece:SetAlpha(0)
		end
	end
end

-- The field, once. Returns it either way, because every caller wants the frame
-- and only the first one wants the work.
local function Dress(box, name)
	if not box or dressed[box] then
		return box
	end
	dressed[box] = true

	-- Out from under the chat frame it belongs to, and the reason is
	-- Chat/Blizzard.lua: hiding the client's window re-parents ChatFrame1 into
	-- an attic frame that can never be shown, and a field left as its child
	-- goes with it. Moved to UIParent it cannot, whatever the attic does.
	--
	-- Never moved back. Putting it under a parent that is in the attic is the
	-- failure this line exists to stop, and the client places this frame by
	-- anchor rather than by parent, so nothing of Blizzard's needs the old one.
	if type(box.SetParent) == "function" and _G.UIParent then
		pcall(box.SetParent, box, _G.UIParent)
	end

	-- Where it was, so turning the chat part off puts it back on the screen
	-- somewhere a player can find it rather than inside a window that is gone.
	local points = {}
	if type(box.GetNumPoints) == "function" and type(box.GetPoint) == "function" then
		for index = 1, (box:GetNumPoints() or 0) do
			points[#points + 1] = { box:GetPoint(index) }
		end
	end
	home[box] = points

	Strip(box, name)

	-- HookScript on all three, never SetScript. The client's own handlers stay
	-- first and ours run under them, which is the difference between painting a
	-- field and replacing the one path that can still log you out.
	box:HookScript("OnEditFocusGained", function(self)
		waiting = true
		Call(Field.OnLight, true)
		Fill(self)
	end)
	box:HookScript("OnEditFocusLost", function()
		waiting = false
		Call(Field.OnLight, false)
	end)
	box:HookScript("OnTextChanged", function(self, userInput)
		Opened(self, userInput)
		Call(Field.OnType, self:GetText() or "")
	end)
	box:HookScript("OnTabPressed", function()
		Call(Field.OnTab)
	end)

	if anchored and footer then
		Field.Anchor(footer)
	end
	return box
end

--------------------------------------------------------------------------
-- The surface the window uses
--------------------------------------------------------------------------

-- Every field this client has, dressed. Called once at build and again
-- whenever the window is laid out, because the count is the client's and a
-- tenth window can appear in the middle of an evening.
function Field.Adopt()
	local made = 0
	for index = 1, Windows() do
		local name = ("ChatFrame%dEditBox"):format(index)
		local box = _G[name]
		if type(box) == "table" and type(box.HookScript) == "function" then
			if not dressed[box] then
				made = made + 1
			end
			Dress(box, name)
		end
	end
	return made
end

-- The field the client would send from. Its answer rather than ours, because
-- which one it is depends on the window the player last typed in and a guess
-- at the first would be wrong for anybody who has ever used a second tab.
function Field.Box()
	if type(_G.ChatEdit_ChooseBoxForSend) == "function" then
		local ok, box = pcall(_G.ChatEdit_ChooseBoxForSend)
		if ok and type(box) == "table" then
			return Dress(box, box.GetName and box:GetName() or "")
		end
	end
	local box = _G.ChatFrame1EditBox
	if type(box) ~= "table" then
		return nil
	end
	return Dress(box, "ChatFrame1EditBox")
end

-- The fields into our footer, filling it edge to edge. Called from the window's
-- layout, so a setting that moves or resizes the window moves the line in it.
--
-- Every field rather than the one that is up, because the one that is up is the
-- client's choice at the moment the key is pressed and laying out only the
-- current one leaves the next one at the bottom of the screen.
function Field.Anchor(frame)
	anchored, footer = true, frame
	if type(frame) ~= "table" then
		return false
	end
	for box in pairs(dressed) do
		box:ClearAllPoints()
		box:SetPoint("LEFT", frame, "LEFT", 3, 0)
		box:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
		box:SetHeight(frame:GetHeight() or UI.Metric.field)
		-- Above the window it is sitting in, because the window is drawn after
		-- it and a field behind its own background is a line you cannot read.
		if type(box.SetFrameStrata) == "function" and frame.GetFrameStrata then
			pcall(box.SetFrameStrata, box, frame:GetFrameStrata())
		end
		if type(box.SetFrameLevel) == "function" and frame.GetFrameLevel then
			pcall(box.SetFrameLevel, box, (frame:GetFrameLevel() or 0) + 5)
		end
	end
	return true
end

-- The font and colour the log is drawn in, so the line you type matches the
-- lines you read. Called from the layout for the same reason Place is: the
-- size is a setting and a field that stays at twelve while the log goes to
-- eighteen is the one part of the window that did not take it.
function Field.Font(size)
	for box in pairs(dressed) do
		box:SetFontObject(UI.Font(size, UI.FLAT))
		box:SetTextColor(C.text[1], C.text[2], C.text[3])
		-- The client's own cap on one line of chat. Set here as well as by
		-- FrameXML because a longer line is refused whole by the server, and it
		-- is better to stop the typing than to lose the sentence.
		box:SetMaxLetters(255)
	end
	return true
end

-- The fields back where the client had them. Called when the window goes away,
-- because a line anchored inside a frame that is not on the screen is a game
-- with no way to type in it, and that is a worse bug than an ugly field.
--
-- The parent is not restored, only the anchor. See Dress above.
function Field.Release()
	anchored, footer = false, nil
	for box, points in pairs(home) do
		box:ClearAllPoints()
		-- The bottom left of the screen is where FrameXML puts this frame, and
		-- it is the answer whenever the anchor we recorded cannot be trusted:
		-- a client that would not answer GetPoint, or one where the frame it
		-- named is the chat window Chat/Blizzard.lua has taken off the screen.
		-- An anchor onto a frame in the attic resolves to wherever the attic
		-- is, which is a line you can type in and cannot find.
		local usable = #points > 0
		for _, point in ipairs(points) do
			local relative = point[2]
			if relative and relative ~= _G.UIParent
				and type(relative.IsVisible) == "function" and not relative:IsVisible() then
				usable = false
			end
		end
		if not usable then
			box:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 16, 24)
		else
			for _, point in ipairs(points) do
				box:SetPoint(point[1], point[2] or _G.UIParent, point[3], point[4], point[5])
			end
		end
	end
	return true
end

-- Put the cursor in the field, the way the client's own chat key does.
--
-- Not the path a key press takes. The two chat keys are the client's and go
-- straight into FrameXML; this is for a click on a name in the log and for
-- `/wk chat`, where there is no key press to preserve and the line being opened
-- is a whisper rather than a command.
function Field.Open()
	local box = Field.Box()
	if not box then
		return false
	end
	if type(_G.ChatEdit_ActivateChat) == "function" then
		local ok = pcall(_G.ChatEdit_ActivateChat, box)
		if ok then
			return true
		end
	end
	box:Show()
	box:SetFocus()
	return true
end

-- How many fields have been dressed, for the status line. A count rather than
-- the table, because what is worth reading is whether the pass found any at
-- all: none is a client whose chat frames are named something else, and that is
-- a window with no line to type in.
function Field.Count()
	local count = 0
	for _ in pairs(dressed) do
		count = count + 1
	end
	return count
end

function Field.Describe()
	local count = Field.Count()
	if count == 0 then
		return "no line to type in: this client names its chat fields something else"
	end
	if not anchored then
		return ("%d of the client's own lines, left where the client had them"):format(count)
	end
	return ("the client's own line, in the footer, %d dressed"):format(count)
end
