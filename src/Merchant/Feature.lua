local ADDON, ns = ...

-- Everything Core and the panel need to know about the merchant window.
-- Stock.lua, Rows.lua, Window.lua and Blizzard.lua hold the behaviour, and this
-- is the only file in the folder that names anything outside it.

local function SetMerchant(value)
	ns.db.merchant = value
	if not value then
		ns.MerchantWindow.Hide()
	end
	ns.MerchantWindow.Apply()
	ns.MerchantBlizzard.Apply()
end

local function SetHide(value)
	ns.db.merchantHideBlizz = value
	ns.MerchantBlizzard.Apply()
end

--------------------------------------------------------------------------
-- The slash word
--------------------------------------------------------------------------

local function MerchantWord(arg, rawArg)
	local word, rest = arg:match("^(%S*)%s*(.-)$")

	if word == "hide" then
		SetHide(ns.Command.Toggle(rest))
		ns.Print("the client's merchant window is " .. ns.MerchantBlizzard.Describe() .. ".")
	elseif word == "stock" then
		ns.Print(ns.Stock.Describe() .. ".")
	elseif word == "sold" then
		-- Read before it is described, unlike stock above. The rack is scanned
		-- every time the window draws and this one is only scanned when it is
		-- on top, so asking in chat with the rack showing would answer with
		-- whatever the last vendor was holding.
		ns.Buyback.Read()
		ns.Print(ns.Buyback.Describe() .. ".")
	elseif word == "on" or word == "off" then
		SetMerchant(word == "on")
		ns.Options.Refresh()
		ns.Print("the merchant window is " .. (ns.db.merchant and "on" or "off") .. ".")
	elseif word == "" then
		ns.Print(ns.MerchantWindow.Describe() .. ".")
	else
		ns.Print("merchant takes on, off, hide, stock or sold.")
	end
	-- rawArg is the untouched line, which this word has no use for: every
	-- sub-word above takes a switch or nothing. Named so the signature matches
	-- every other word in the addon.
	return rawArg
end

--------------------------------------------------------------------------

ns.Register({
	name = "merchant",
	order = 30,

	switch = {
		key = "merchant",
		label = "the merchant window",
		apply = function(value) SetMerchant(value) end,
	},

	defaults = {
		-- On. Everything it replaces is one tick box away.
		merchant = true,

		-- The client's own window, moved off the side of the screen while ours
		-- is up. It may not be hidden and it may not be caged: both end the
		-- session, and Blizzard.lua carries that argument in full.
		merchantHideBlizz = true,
	},

	words = {
		merchant = MerchantWord,
	},

	help = {
		"merchant on|off, the whole rack in one window instead of ten at a time",
		"merchant hide on|off, move the client's own merchant window off the screen",
		"merchant stock, what the vendor in front of you has",
		"merchant sold, what is on the buyback rack",
	},

	status = function()
		return ("%s; the client's %s")
			:format(ns.MerchantWindow.Describe(), ns.MerchantBlizzard.Describe())
	end,

	panel = function(ui)
		ui.Section("Merchant", "Chores")
		ui.Lede("Everything the vendor has in one window, in the same piles as your bags, with the price on every line. The client shows ten at a time behind an arrow.")
		ui.Check("the addon's merchant window",
			function() return ns.db.merchant end,
			SetMerchant)
		ui.Hint("It opens at a vendor and closes when you walk away. A click buys one of what he sells it in: one flask, or one stack of two hundred arrows. The tab at the top is the last twelve things you sold.")
		ui.Check("move the client's merchant window aside",
			function() return ns.db.merchantHideBlizz end,
			SetHide)
		ui.Hint("Moved rather than hidden. Hiding that frame is what ends the conversation with the vendor, so it is parked off the side of the screen and closing this window walks away.")
		ui.Reading("this window", ns.MerchantWindow.Describe)
		ui.Reading("the rack", ns.Stock.Describe)
		ui.Reading("what you sold", ns.Buyback.Describe)
		ui.Reading("the rows", ns.MerchantRows.Describe)
		ui.Reading("the client's window", ns.MerchantBlizzard.Describe)
	end,
})
