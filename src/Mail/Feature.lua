local ADDON, ns = ...

-- Everything Core and the panel need to know about the mail window. Who.lua,
-- Draft.lua, Send.lua, Inbox.lua, Blizzard.lua and Window.lua hold the
-- behaviour, and this is the only file in the folder that names anything
-- outside it.
--
-- Two of those names are the whole reason this file is more than a registration.
-- Mail/Who.lua answers what a recipient is and deliberately holds no list of
-- its own for two of the three answers, because both lists already exist in
-- other parts: the characters on your account are Feeds/Purse.lua's ledger, and
-- the people who matter to you are Chat/People.lua's groups. Copying either one
-- would be a second list to keep in step, so the tests are registered here and
-- Who.lua never learns the name of either file.

local function SetMail(value)
	ns.db.mail = value
	if not value then
		ns.MailWindow.Hide()
	end
	ns.MailBlizzard.Apply()
end

local function SetHide(value)
	ns.db.mailHideBlizz = value
	ns.MailBlizzard.Apply()
end

local function SetBags(value)
	ns.db.mailBags = value
	ns.MailBags.Apply()
end

local function SetWarn(value)
	ns.db.mailWarn = value
	ns.MailWindow.Paint()
end

--------------------------------------------------------------------------
-- The slash word
--
-- One word with a handful of answers, which is the shape `errors` already has.
-- The sub-words are tried first and an on or an off falls through to the
-- switch, so `/wk mail off` and `/wk mail fav Aria` are the same word.
--------------------------------------------------------------------------

local function Favourites()
	local list = ns.MailWho.Favourites()
	if #list == 0 then
		ns.Print("no favourites. Type /wk mail fav <name> to add one.")
		return
	end
	for _, name in ipairs(list) do
		ns.Print(("  %-16s %s"):format(name, ns.MailWho.Say(name)))
	end
end

local function MailWord(arg, rawArg)
	local word, rest = arg:match("^(%S*)%s*(.-)$")
	local raw = rawArg:match("^%S*%s*(.-)%s*$") or ""

	if word == "fav" then
		local at, why = ns.MailWho.Add(raw)
		ns.Print(at and (raw .. " is a favourite now.") or (why .. "."))
	elseif word == "unfav" then
		local ok, why = ns.MailWho.Remove(raw)
		ns.Print(ok and (raw .. " is off the list.") or (why .. "."))
	elseif word == "favs" or word == "list" then
		Favourites()
	elseif word == "warn" then
		SetWarn(ns.Command.Toggle(rest))
		ns.Print("the warning band " .. (ns.db.mailWarn and "asks twice" or "only colours") .. ".")
	elseif word == "hide" then
		SetHide(ns.Command.Toggle(rest))
		ns.Print("Blizzard's mail window is " .. ns.MailBlizzard.Describe() .. ".")
	elseif word == "bags" then
		SetBags(ns.Command.Toggle(rest))
		ns.Print("a right click in the bags puts a stack " .. ns.MailBags.Describe() .. ".")
	elseif word == "on" or word == "off" then
		SetMail(word == "on")
		ns.Print("the mail window is " .. (ns.db.mail and "on" or "off") .. ".")
	else
		-- No argument opens it, which only means anything at a mailbox. Said
		-- rather than silently doing nothing, because "I typed it and nothing
		-- happened" is the report this refusal exists to prevent.
		if not ns.MailWindow.Built() then
			ns.Print("stand at a mailbox and the window opens itself.")
			return
		end
		ns.MailWindow.Toggle()
	end
end

--------------------------------------------------------------------------

ns.Register({
	name = "mail",
	order = 22,

	switch = {
		key = "mail",
		label = "the mail window",
		apply = function(value) SetMail(value) end,
	},

	zooms = {
		{ key = "mailZoom", label = "Mail", window = true },
	},

	defaults = {
		-- 1.3, and it was 1.25 when every window in the addon shared one number.
		-- A tenth is the step now and 1.25 is not on one, so a default that
		-- stayed there would be a value the page cannot reach and the reset
		-- cannot restore. A window at 1 is a window you lean in to read on the
		-- panel most people are playing on, and the screen height already
		-- doubles this where a panel is tall enough to need it.
		mailZoom = 1.3,

		-- On. A part whose whole argument is that the window it replaces cannot
		-- tell your bank alt from a stranger does not ship switched off, and
		-- everything it does is reversible in one press.
		mail = true,

		-- Blizzard's own goes out of the way, for the same reason. Moved rather
		-- than hidden, and Mail/Blizzard.lua carries the reason: hiding that
		-- frame is what closes the mailbox.
		mailHideBlizz = true,

		-- Whether a mail with value on it going to somebody not on your list
		-- takes two presses as well as turning the band red. The colour is not
		-- a setting and never will be; this is the extra press, and somebody
		-- who moves gold between eight alts every evening should be able to
		-- turn it off without losing the colour that says which alt.
		mailWarn = true,

		-- Whether a right click in the bags puts a stack on the letter, which
		-- is what the client's own mail window does and the only way anybody
		-- attaches twelve of anything. Mail/Bags.lua carries what it costs: the
		-- client's own handler is taken over while the window is open, so this
		-- is the switch that says do not.
		mailBags = true,

		-- The list itself. Account-wide, because who you mail is a fact about
		-- you rather than about the character you are standing in, and typing
		-- the same four names on every alt is exactly the chore this removes.
		-- The bank alt ships in it; a name you do not have is a name the
		-- colouring never matches and the picker offers once.
		mailFavourites = { "konew" },
	},

	words = {
		mail = MailWord,
	},

	help = {
		"mail, open the window you are standing at a mailbox for",
		"mail on|off, the addon's mail window instead of the client's",
		"mail hide on|off, move Blizzard's own window out of the way",
		"mail bags on|off, right click a stack in your bags to attach it",
		"mail fav|unfav <name>, the quick list down the left of the window",
		"mail favs, what is on that list and who each of them is",
		"mail warn on|off, whether a stranger takes two presses as well as red",
	},

	status = function()
		return ("%s; %s; %s; a right click in the bags puts a stack %s; Blizzard's %s"):format(
			ns.MailWindow.Describe(), ns.MailWho.Describe(),
			ns.MailInbox.Describe(), ns.MailBags.Describe(),
			ns.MailBlizzard.Describe())
	end,

	panel = function(ui)
		ui.Section("Mail", "Chores")
		ui.Lede("A mail window of the addon's own: a quick list of who you mail, a colour saying who they are before you press send, and more than twelve attachments.")
		ui.Check("open the addon's mail window at a mailbox",
			function() return ns.db.mail end,
			SetMail)
		ui.Hint("Green for a character on your own account, blue for a friend or somebody in one of your groups, red for a name the addon has never seen.")
		ui.Check("move Blizzard's own mail window out of the way",
			function() return ns.db.mailHideBlizz end,
			SetHide)
		ui.Hint("Moved rather than hidden: hiding that frame tells the server you walked away from the mailbox, so it is parked off the screen at no opacity.")
		ui.Check("right click a stack in your bags to put it on the letter",
			function() return ns.db.mailBags end,
			SetBags)
		ui.Hint("The bag click is taken over while this window is open and given back when it closes. Shift, ctrl and the left button are never taken.")
		ui.Check("ask twice before value goes to somebody not on the list",
			function() return ns.db.mailWarn end,
			SetWarn)
		ui.Hint("The band is red either way. This is whether the send button also has to be pressed a second time.")
		ui.Reading("favourites", ns.MailWho.Describe)
		ui.Reading("a right click in the bags", ns.MailBags.Describe)
		ui.Reading("your mailbox", ns.MailInbox.Describe)
		ui.Reading("the last send", ns.MailSend.Describe)
		ui.Reading("Blizzard's window", ns.MailBlizzard.Describe)
	end,
})

--------------------------------------------------------------------------

-- The two lists that already exist, handed to Mail/Who.lua as tests rather than
-- copied into it. Both take a normalised key, which is what Who.Key answers and
-- what People.Key answers for the same name.
ns.MailWho.AlsoAlt(function(key)
	return ns.Purse.Knows(key)
end)

ns.MailWho.Also(function(key)
	return ns.People.Match(key) ~= nil
end)
