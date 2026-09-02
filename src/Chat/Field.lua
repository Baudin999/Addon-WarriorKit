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

-- Where the client now thinks the line is going, called with the channel, the
-- person when that channel is a whisper, and whether the client aimed the line
-- there itself rather than the player typing the slash.
--
-- That last one is what separates Whisper on the unit menu from `/w Ari` half
-- typed. The window opens a conversation on the first and must not on the
-- second.
--
-- This is the only way to see that the player has changed channel by hand.
-- Typing `/p ` into this frame does not leave `/p ` in it: the client's own
-- OnTextChanged reads the slash, writes the channel onto two attributes of the
-- frame and takes the slash back out. So the text says nothing a moment later
-- and the attributes say everything, and the window follows them into the room
-- that channel belongs to.
Field.OnChannel = nil

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
-- Which channel the line is on
--
-- Read back off the frame rather than off the text, for the reason
-- Field.OnChannel says: the slash is gone by the time anything of ours runs.
--
-- Both spellings of the target, because the client keeps two. A whisper is
-- addressed through `tellTarget` and a numbered channel through
-- `channelTarget`, and reading only the second gives every whisper a nil name,
-- which is a room nobody can be sent to.
--------------------------------------------------------------------------

local function Channel(box)
	local kind = box:GetAttribute("chatType")
	local target = box:GetAttribute("tellTarget") or box:GetAttribute("channelTarget")
	return type(kind) == "string" and kind or nil,
		(type(target) == "string" and target ~= "") and target or nil
end

-- The pair as one string, for the comparisons that only ask whether it has
-- moved.
local function Key(box)
	local kind, target = Channel(box)
	return tostring(kind) .. "/" .. tostring(target)
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
--
-- **And a write that emptied the line on its way to a channel of its own is
-- skipped too, which is the whisper this flag used to eat.** Whisper on the
-- unit menu is ChatFrameUtil.SendTell, and what that does is put `/w Aria ` in
-- the field a frame after the field took the focus. The client's parser reads
-- it, sets the channel to a whisper addressed to her, and then writes the rest
-- of the line back, which is the empty string. That empty string looks exactly
-- like the blanking above: a write nobody typed, into a line with nothing left
-- in it, while the flag is up. So the room's slash went in over it and the
-- whisper became whatever the room was, which from Say is a sentence about
-- your evening said out loud to a city.
--
-- The two are told apart by the channel rather than by the text, because the
-- channel is the thing that differs: a blanking leaves it where our own fill
-- put it, and this leaves it somewhere else. Somewhere else means somebody
-- meant it, and the line is left alone. Moved below runs a moment later off
-- the same write and walks the window into that person's room.
--------------------------------------------------------------------------

-- Where the last fill left the channel, which is what "somewhere else" is
-- measured against. Written after the call rather than before, because the
-- client parses the slash out of the line inside our own SetText and the
-- channel we want recorded is the one that parse arrived at.
local filled

local function Fill(box)
	if filling or type(Field.OnFill) ~= "function" then
		return false
	end
	filling = true
	local ok, wrote = pcall(Field.OnFill, box)
	filling = false
	filled = Key(box)
	return ok and wrote and true or false
end

-- Set on the one write above that turned out to be the client aiming the line
-- somewhere itself, and read by Moved a moment later off the same write. It is
-- the difference between a channel that was chosen for you and one that arrived
-- a letter at a time while you typed, and the window wants to know: a whisper
-- picked off a menu is a conversation to open, and half a name in a line being
-- typed is not.
local pointed = false

local function Opened(box, userInput)
	if userInput or filling or not waiting then
		return
	end
	if (box:GetText() or "") ~= "" then
		return
	end
	waiting = false
	if Key(box) ~= filled then
		pointed = true
		return
	end
	Fill(box)
end

-- What each field was last seen on, so a keystroke that does not move the
-- channel costs one string compare rather than a trip into the window.
local channel = {}

local function Moved(box)
	-- Taken and dropped in the same breath, whatever this call decides. It is
	-- about the write being handled right now and a flag left standing would be
	-- read by the next one.
	local meant = pointed
	pointed = false
	local kind, target = Channel(box)
	local key = Key(box)
	if channel[box] == key then
		return false
	end
	channel[box] = key
	-- Not while we are the ones writing. Filling the line in with the room's own
	-- slash moves the channel to the room the window is already in, and calling
	-- out on that would be the window telling itself where it is.
	if filling or not kind then
		return false
	end
	Call(Field.OnChannel, kind, target, meant)
	return true
end

--------------------------------------------------------------------------
-- Dressing one field
--------------------------------------------------------------------------

-- Every texture under the frame, gone.
--
-- Walked rather than named, and walked down rather than across. Prat names the
-- three border pieces and the three focus glows, which is six names against one
-- client. This addon ships for two and the pieces differ between them, so the
-- walk finds whatever is actually there.
--
-- **Down through the children as well, which is what the first version of this
-- missed.** The border came back on a live client because the art is not
-- always laid on the field itself: newer FrameXML wraps it in a child frame,
-- and a walk over the field's own regions finds nothing to hide and reports
-- success. So this recurses, and a texture at any depth under the field is
-- Blizzard's art by definition, because nothing in this addon puts one there.
--
-- Faded as well as hidden, and the pair is not belt and braces. FrameXML shows
-- the focus pieces again every time the field takes the focus, so a hidden one
-- comes straight back; alpha survives that and Hide is what stops the ones the
-- client never touches again from being drawn at all.
local function Bare(frame, depth)
	local gone = 0
	if type(frame.GetRegions) == "function" then
		for _, piece in ipairs({ frame:GetRegions() }) do
			if type(piece) == "table" and type(piece.GetObjectType) == "function"
				and piece:GetObjectType() == "Texture" then
				piece:SetAlpha(0)
				piece:Hide()
				gone = gone + 1
			end
		end
	end
	if depth > 0 and type(frame.GetChildren) == "function" then
		for _, kid in ipairs({ frame:GetChildren() }) do
			if type(kid) == "table" then
				gone = gone + Bare(kid, depth - 1)
			end
		end
	end
	return gone
end

-- How many pieces the last strip took off, for the status line. It is the one
-- number that tells a field the walk stripped from a field the walk could not
-- see into, and those two look identical from a chair: one is a bare line and
-- the other is a line in Blizzard's border.
local stripped = 0

-- Three deep, which is the field, the frame the art is wrapped in and the
-- pieces inside that. Deeper is a walk over frames that are somebody else's
-- business and shallower is the border this file already failed to remove once.
local DEPTH = 3

local function Strip(box, name)
	local gone = Bare(box, DEPTH)

	-- The backdrop, which is art without being a texture the walk can reach.
	-- Present only where the field carries the mixin, which is why it is
	-- probed and pcalled like every other client call in this file.
	if type(box.SetBackdrop) == "function" then
		pcall(box.SetBackdrop, box, nil)
	end

	-- The named pieces last, and only as the fallback for a client whose
	-- GetRegions answers nothing. This is the shape of every other client probe
	-- in this file: ask, and name only what the asking could not find.
	if gone == 0 then
		for _, part in ipairs(SKIN) do
			local piece = _G[name .. part]
			if type(piece) == "table" and type(piece.Hide) == "function" then
				piece:SetAlpha(0)
				piece:Hide()
				gone = gone + 1
			end
		end
		for _, part in ipairs(GLOW) do
			local piece = box[part]
			if type(piece) == "table" and type(piece.SetAlpha) == "function" then
				piece:SetAlpha(0)
				gone = gone + 1
			end
		end
	end

	stripped = gone
	return gone
end

-- The word in front of the line saying where it is going, and the punctuation
-- after it. FrameXML's, written by ChatEdit_UpdateHeader, and the reason this
-- window no longer needs a label of its own beside the field.
--
-- Typing `/p ` into this frame does not leave `/p ` in it. The client's own
-- OnTextChanged parses the line, reads the channel off the slash, sets the
-- field's chat type from it and takes the slash back out. What is left on the
-- screen is this word. So the room's slash is still what decides where the line
-- goes, exactly as the window has always claimed, and the header is that claim
-- read back in the client's own hand rather than a second piece of state.
local function Header(box, name)
	return box.header or _G[name .. "Header"], _G[name .. "HeaderSuffix"]
end

--------------------------------------------------------------------------
-- Making it look like the rest of the addon
--
-- Applied at dressing and again every time the client has been at it, which is
-- more often than it sounds. ChatEdit_UpdateHeader runs on activation and on
-- every change of channel, and it writes three things this file has an opinion
-- about: the font on the header, the colour of the text you are typing, and the
-- inset that keeps that text clear of the header. All three are Blizzard's
-- numbers against Blizzard's art, and against a window drawn without any they
-- read as a chat line from a different program sitting in ours.
--
-- So the hooks below re-apply it rather than setting it once. A style written
-- at login and never again is a field that looks right until the first time you
-- whisper somebody.
--------------------------------------------------------------------------

-- The size the log is drawn at, so the line you type matches the lines you
-- read. Held rather than passed, because the restyle happens inside a script
-- hook that has no idea what the setting says.
local size = 12

-- The gap either side of the text, which is the addon's own margin rather than
-- FrameXML's fifteen. Four is what every other inset in the chat window is.
local PAD = 4

local function Style(box, name)
	Strip(box, name)
	-- Shadowed for the reason UI/Log.lua is: Strip has just taken every piece
	-- of art off this field, so the line you are typing is drawn straight onto
	-- the world, and the log above it is too. The role for text over ground the
	-- addon did not paint is a shadow.
	box:SetFontObject(UI.Font(size, UI.SHADOW))
	-- The theme's own colour, and not the channel colour the client writes here.
	--
	-- ChatEdit_UpdateHeader paints the text you are typing in the channel's own
	-- colour, so a whisper is typed in pink and a party line in blue. That is
	-- Blizzard's window saying something the header beside it already says, and
	-- in this window it is the one string on the screen that is not the same
	-- colour as the sentence above it. The header keeps the channel colour,
	-- because a word is where a colour like that belongs.
	box:SetTextColor(C.text[1], C.text[2], C.text[3])
	-- The client's own cap on one line of chat. Set here as well as by FrameXML
	-- because a longer line is refused whole by the server, and it is better to
	-- stop the typing than to lose the sentence.
	box:SetMaxLetters(255)

	local header, suffix = Header(box, name)
	local width = 0
	for _, part in ipairs({ header, suffix }) do
		if type(part) == "table" and type(part.SetFontObject) == "function" then
			part:SetFontObject(UI.Font(size, UI.SHADOW))
			if part:IsShown() then
				-- GetStringWidth rather than GetWidth, because the face has
				-- just changed under it. A font string measures what it draws
				-- as soon as it is asked; its frame width is last frame's
				-- layout, so reading that here insets the line by the width of
				-- the word in Blizzard's font rather than in ours.
				local wide = type(part.GetStringWidth) == "function"
					and part:GetStringWidth() or nil
				width = width + (wide or part:GetWidth() or 0)
			end
		end
	end
	-- The header off our own margin rather than FrameXML's, and the text after
	-- it by the same margin again. Written here rather than left to the client
	-- because ChatEdit_UpdateHeader derives its inset from the header's width in
	-- Blizzard's font, and the header is in ours now.
	if type(header) == "table" and type(header.ClearAllPoints) == "function" then
		header:ClearAllPoints()
		header:SetPoint("LEFT", box, "LEFT", PAD, 0)
	end
	if type(box.SetTextInsets) == "function" then
		box:SetTextInsets(PAD + width + (width > 0 and PAD or 0), PAD, 0, 0)
	end
end

-- What the field was last styled against, so the restyle on every keystroke is
-- a comparison rather than a dozen setters. The channel is what moves the
-- header, and the header is what moves everything else.
local styled = {}

-- And the client having been at it since, which the channel alone cannot see.
--
-- ChatEdit_UpdateHeader is the last thing the client's parser does, after the
-- slash has been read out of the line and after every hook of ours has run, and
-- what it writes is Blizzard's font, Blizzard's channel colour and Blizzard's
-- inset. A restyle that only fires when the channel moved skips that, because
-- the channel it moved to is the one the room was already on: the line comes up
-- in the addon's own hand the first time it is opened and in FrameXML's every
-- time after.
--
-- The font is the tell and it is one table lookup and one compare. Everything
-- Style writes is written in the same breath as the font, so a field wearing
-- ours is a field the client has not touched since.
local function Restyle(box, name)
	local kind, target = Channel(box)
	local key = ("%s/%s/%s"):format(tostring(kind), tostring(target), tostring(size))
	if styled[box] == key and box:GetFontObject() == UI.Font(size, UI.SHADOW) then
		return false
	end
	styled[box] = key
	Style(box, name)
	return true
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

	Style(box, name)

	-- HookScript on all four, never SetScript. The client's own handlers stay
	-- first and ours run under them, which is the difference between painting a
	-- field and replacing the one path that can still log you out.
	--
	-- Running under them is also what makes the restyle work at all: by the time
	-- one of these fires, ChatEdit_UpdateHeader has already written Blizzard's
	-- font and colour over ours, and the last word is the one that shows.
	box:HookScript("OnEditFocusGained", function(self)
		waiting = true
		Style(self, name)
		Call(Field.OnLight, true)
		Fill(self)
	end)
	box:HookScript("OnEditFocusLost", function()
		waiting = false
		Call(Field.OnLight, false)
	end)
	box:HookScript("OnTextChanged", function(self, userInput)
		Opened(self, userInput)
		-- The channel can move on a keystroke, because typing `/g ` is how you
		-- move it, and the header changes width with it. A comparison rather
		-- than a restyle, so an ordinary character costs one string compare.
		Restyle(self, name)
		Moved(self)
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

-- The size the log is drawn at. A setting, so the line you type stays the size
-- of the lines you read: a field that stays at twelve while the log goes to
-- eighteen is the one part of the window that did not take it.
function Field.Font(points)
	if type(points) == "number" and points > 0 then
		size = points
	end
	for box in pairs(dressed) do
		styled[box] = nil
		Style(box, box.GetName and box:GetName() or "")
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
	-- The strip count is here rather than left out because it is the one number
	-- that separates a bare line from a line still in Blizzard's border, and
	-- those two are the same sentence from anywhere but the screen. Nothing
	-- stripped on a live client means the walk could not see the art.
	return ("the client's own line, in the footer, %d dressed, %d pieces of its art off")
		:format(count, stripped)
end
