local ADDON, ns = ...

-- Everything Core and the panel need to know about the socketing window.
-- Window.lua and Blizzard.lua hold the behaviour, and this is the only file in
-- the folder that names anything outside it.

local function SetSockets(value)
	ns.db.sockets = value
	if not value then
		ns.SocketWindow.Hide()
	end
	ns.SocketWindow.Apply()
	ns.SocketBlizzard.Apply()
end

local function SetHide(value)
	ns.db.socketsHideBlizz = value
	ns.SocketBlizzard.Apply()
end

--------------------------------------------------------------------------
-- The slash word
--------------------------------------------------------------------------

local function SocketWord(arg, rawArg)
	local word, rest = arg:match("^(%S*)%s*(.-)$")

	if word == "hide" then
		SetHide(ns.Command.Toggle(rest))
		ns.Print("the client's socketing window is " .. ns.SocketBlizzard.Describe() .. ".")
	elseif word == "gems" then
		local carried = ns.Sockets.Gems()
		if #carried == 0 then
			ns.Print("you are carrying no gem that goes in a hole.")
		else
			ns.Print(("you are carrying %d socketing gems:"):format(#carried))
			for index = 1, #carried do
				ns.Print("  " .. (carried[index].link or carried[index].name or "?"))
			end
		end
	elseif word == "on" or word == "off" then
		SetSockets(word == "on")
		ns.Options.Refresh()
		ns.Print("the socketing window is " .. (ns.db.sockets and "on" or "off") .. ".")
	elseif word == "" then
		ns.Print(ns.SocketWindow.Describe() .. ".")
	else
		ns.Print("sockets takes on, off, hide or gems.")
	end
	-- rawArg is the untouched line, which this word has no use for. Named so the
	-- signature matches every other word in the addon.
	return rawArg
end

--------------------------------------------------------------------------

ns.Register({
	name = "sockets",
	order = 37,

	switch = {
		key = "sockets",
		label = "the socketing window",
		says = "Shift-click a piece on the gear page and it opens on that piece's holes with every gem in your bags underneath. Click a hole, click a gem, and press apply. Nothing is spent until you do.",
		apply = function(value) SetSockets(value) end,
	},

	zooms = {
		{ key = "socketsZoom", label = "Sockets", window = true },
	},

	defaults = {
		-- The same 1.3 every window in the addon opens at.
		socketsZoom = 1.3,

		-- On. Everything it replaces is one tick box away, and on the client
		-- with no sockets in it nothing here ever registers an event.
		sockets = true,

		-- The client's own window, moved off the side of the screen while ours
		-- is up. It may not be hidden and it may not be caged: both end the
		-- session, and Blizzard.lua carries that argument in full.
		socketsHideBlizz = true,
	},

	words = {
		sockets = SocketWord,
	},

	help = {
		"sockets on|off, this addon's socketing window instead of the client's",
		"sockets hide on|off, move the client's own socketing window off the screen",
		"sockets gems, every gem in your bags that goes in a hole",
	},

	status = function()
		return ("%s; the client's %s")
			:format(ns.SocketWindow.Describe(), ns.SocketBlizzard.Describe())
	end,

	panel = function(ui)
		ui.Section("Sockets", "Windows")
		ui.Lede("The holes in one piece and every gem in your bags that fits one, on a page. Shift-click a piece on the gear page to open it.")
		ui.Check("move the client's socketing window aside",
			function() return ns.db.socketsHideBlizz end,
			SetHide)
		ui.Hint("Moved rather than hidden. Hiding that frame is what ends the socketing session, so it is parked off the side of the screen and closing this window ends it instead.")
		ui.Reading("this window", ns.SocketWindow.Describe)
		ui.Reading("the client's window", ns.SocketBlizzard.Describe)
	end,
})
