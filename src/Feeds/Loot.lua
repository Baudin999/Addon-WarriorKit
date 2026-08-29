local ADDON, ns = ...

local LootFeed = {}
ns.LootFeed = LootFeed

local C = ns.UI.Color

--------------------------------------------------------------------------
-- What dropped
--
-- Every item that reaches you, as a row: the icon, the name in the item's own
-- quality colour, and how many of it there were.
--
-- **Why this reads chat rather than the loot window.** The obvious source is
-- the loot window itself, and it is the wrong one twice over. Comfort/Loot.lua
-- empties a corpse at LOOT_READY before the window is ever drawn, so on this
-- addon's own default there is no window to read; and a window says what is on
-- the corpse rather than what ended up in your bags, which for a group is a
-- different list. CHAT_MSG_LOOT is the server telling you what you actually
-- got, it fires for a quest reward and a crafted item as well as a corpse, and
-- it is the only source that is right in all of those cases.
--
-- **Why the sentences are built rather than typed.** The message is a localised
-- format string with the link poked into it, and the client hands the addon the
-- same format strings it used. Turning LOOT_ITEM_SELF_MULTIPLE into a pattern
-- means a German client is read by German rules without this file knowing a
-- word of German. Typing "You receive loot:" here would be an addon that works
-- on one locale and silently captures nothing on the rest.
--
-- Nothing here is on a ticker. An item drops when it drops.
--------------------------------------------------------------------------

-- The quality palette, which lives in UI/Theme.lua.
--
-- It was written here and moved when the quest log's reward column became its
-- second reader. The tables are the same tables, which matters: every guard in
-- UI/Feed.lua compares a colour by table identity, so a palette read fresh out
-- of the client on each row would fail every one of those guards and repaint a
-- colour that had not changed. Taken into a local at load, the same as the
-- palette and the metrics above it.
local QUALITY = ns.UI.Quality

-- The number of qualities the chips and the filter know about, which is the
-- five the game grades an item on. Six and seven exist and are the heirloom and
-- the artifact, neither of which drops on this client; anything at that end of
-- the scale is drawn in its own colour above and filtered with the epics.
local QUALITIES = 4

-- What class the client files a quest item under. Comfort/Clutter.lua reads the
-- same number off the same call and says so in its own header; this is the
-- second reader, and the two are deliberately not sharing a constant, because
-- one of them scanning your bags and the other reading a loot message are not
-- one decision.
local QUEST_CLASS = 12

-- The ring round a quest item's icon, and the chip that says whether those
-- items are drawn.
--
-- Orange rather than the heading gold beside it. Gold is what the coin rows are
-- and what the account's own accent is, and a quest marker in that colour is a
-- marker you have to work out. This is the only orange in the addon.
local QUEST = { 0.98, 0.55, 0.15 }

-- The three letters the glyph face draws the chips' marks on. A gem for the
-- thing that grades an item, the quest bang, and a stack of coins. Named rather
-- than written at the call site because scripts/bake-glyphs.sh is what decides
-- which letter carries which mark, and a literal `*` sitting in a table would
-- give nobody reading this file a way to find that out.
local GEM, BANG, COINS = "*", "!", "$"

-- What the client calls each quality in its own language. ITEM_QUALITY0_DESC
-- and its siblings are the strings the client's own tooltips use, so a player
-- reading "Uncommon" on a chip reads the same word the item does; the English
-- list behind them is for a client that carries neither.
--
-- Here rather than in Feeds/Feature.lua, where it was, because the chips over
-- the rows name a quality and the panel page names the same quality, and the
-- two of them reading different tables is how one ends up saying "Poor" while
-- the other says "Grey".
local QUALITY_WORDS = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic" }

function ns.QualityWord(quality)
	local named = _G["ITEM_QUALITY" .. quality .. "_DESC"]
	return (type(named) == "string" and named) or QUALITY_WORDS[quality] or tostring(quality)
end

local COIN = "Interface\\Icons\\INV_Misc_Coin_01"

-- What the client draws where an item's icon should be and cannot say which.
-- Named rather than left nil, because a texture of nil is a blank square and a
-- question mark is the client's own way of saying it does not know yet.
local UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"

--------------------------------------------------------------------------
-- Turning a format string into a pattern
--
-- The client's loot messages are `%s` and `%d` in a localised sentence. Every
-- magic character is escaped first, which turns each `%s` into `%%s`, and then
-- the two placeholders are put back as captures.
--
-- Nil for a format string this client does not carry, which is how the table
-- below can name messages that exist on one flavour and not the other without
-- either of them raising.
--------------------------------------------------------------------------

local function Pattern(format)
	if type(format) ~= "string" then
		return nil
	end
	local body = format:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
	body = body:gsub("%%%%s", "(.+)")
	body = body:gsub("%%%%d", "(%%d+)")
	return "^" .. body .. "$"
end

-- The loot sentences, most specific first.
--
-- Order is the whole correctness of this table. "You receive loot: %s." matches
-- the multiple form too, because the link is followed by "x4" and `(.+)` will
-- happily swallow it, so every counted sentence has to be tried before its
-- uncounted twin. Getting that the wrong way round gives a feed where every
-- stack of eight silk cloth is one item called "Silk Clothx8".
--
--   mine     the sentence is about you, so there is no name in front of it
--   counted  it carries a stack size after the link
local RULES = {
	{ format = "LOOT_ITEM_SELF_MULTIPLE", mine = true, counted = true },
	{ format = "LOOT_ITEM_PUSHED_SELF_MULTIPLE", mine = true, counted = true },
	{ format = "LOOT_ITEM_CREATED_SELF_MULTIPLE", mine = true, counted = true },
	{ format = "LOOT_ITEM_SELF", mine = true },
	{ format = "LOOT_ITEM_PUSHED_SELF", mine = true },
	{ format = "LOOT_ITEM_CREATED_SELF", mine = true },
	{ format = "LOOT_ITEM_MULTIPLE", counted = true },
	{ format = "LOOT_ITEM_PUSHED_MULTIPLE", counted = true },
	{ format = "LOOT_ITEM_CREATED_MULTIPLE", counted = true },
	{ format = "LOOT_ITEM" },
	{ format = "LOOT_ITEM_PUSHED" },
	{ format = "LOOT_ITEM_CREATED" },
}

-- The two ways the server tells you about coin. Everyone else's coin is not
-- reported at all in a sentence this can read, which is the client's decision
-- rather than this file's.
local MONEY = { "YOU_LOOT_MONEY", "LOOT_MONEY_SPLIT" }

local built = false

local function Build()
	if built then
		return
	end
	built = true
	for _, rule in ipairs(RULES) do
		rule.pattern = Pattern(_G[rule.format])
	end
	for index, name in ipairs(MONEY) do
		MONEY[index] = { format = name, pattern = Pattern(_G[name]) }
	end
end

--------------------------------------------------------------------------
-- Reading one message
--------------------------------------------------------------------------

-- The item link out of whatever the sentence captured. The capture is already
-- the whole link in every rule above, so this is a check rather than a search:
-- a chunk with no item hyperlink in it is a sentence that matched by accident
-- and must not become a row.
local function Link(chunk)
	if type(chunk) ~= "string" or not chunk:find("|Hitem:", 1, true) then
		return nil
	end
	return (chunk:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Who, what and how many, or nil for a line that is not loot.
local function Read(text)
	for _, rule in ipairs(RULES) do
		if rule.pattern then
			local a, b, c = text:match(rule.pattern)
			if a then
				if rule.mine then
					local link = Link(a)
					if link then
						return nil, link, tonumber(rule.counted and b or 1) or 1
					end
				else
					local link = Link(b)
					if link then
						return a, link, tonumber(rule.counted and c or 1) or 1
					end
				end
			end
		end
	end
	return nil, nil, nil
end


--------------------------------------------------------------------------
-- What the column shows
--
-- Six chips over the rows: one per quality, and one for coin. Each is on or
-- off, each says which of them it is by its colour, and between them they are
-- the whole of what is drawn.
--
-- **The feed records everything either way.** There was a quality floor here
-- and it worked at the door: an item under it never became a row and could not
-- be got back by changing your mind. That is the wrong end to filter at for a
-- window whose whole job is answering "what did I just get", and it was also
-- the second control doing this job, which is one more than a feature should
-- have. It is gone. Everything that drops is written down, the chips decide
-- what you are looking at, and turning one back on brings its history with it.
--
-- **A quest item is not a quality.** It is white, the same white as a stack of
-- linen, so it gets a ring round its icon rather than a colour of its own, and
-- its chip is an override rather than a seventh tier: on, a quest item is drawn
-- whatever its own quality chip says. That is the combination that makes the
-- feed useful while questing, which is turning the whites off and still seeing
-- the five wolf livers you need.
--
-- The five qualities are one saved number rather than five saved booleans. A
-- table of five would be five keys the defaults have to backfill and five
-- things a reset has to walk; a bitmask is one of each, and nothing outside
-- this pair of functions ever sees it.
--------------------------------------------------------------------------

local function Lit(quality)
	return math.floor(ns.db.lootFeedShow / 2 ^ quality) % 2 == 1
end

local function Light(quality, on)
	if Lit(quality) == (on and true or false) then
		return false
	end
	local flag = 2 ^ quality
	ns.db.lootFeedShow = on and (ns.db.lootFeedShow + flag) or (ns.db.lootFeedShow - flag)
	return true
end

-- Handed out, because the panel puts the same six switches on a page and the
-- two have to be the same switch. A second copy of this arithmetic behind a
-- check box is a check box that disagrees with the chip beside it.
function LootFeed.Lit(quality)
	return Lit(quality)
end

function LootFeed.Light(quality, on)
	return Light(quality, on)
end

-- Whether one entry is drawn. This is the function UI/Feed.lua walks the ring
-- with, so it reads settings and asks the entry, and does no work of its own.
local function Passes(entry)
	if entry.money then
		return ns.db.lootFeedMoney and true or false
	end
	if entry.quest and ns.db.lootFeedQuest then
		return true
	end
	return Lit(math.min(entry.quality or 1, QUALITIES))
end

-- The chips, in the order they are drawn: the quality ramp read left to right,
-- then a break, then the two that are not a quality.
local function Chips()
	local chips = {}
	for quality = 0, QUALITIES do
		chips[#chips + 1] = {
			color = QUALITY[quality],
			mark = GEM,
			-- A function rather than a string, because the word is the client's
			-- and its global is not reliably in place while this file is still
			-- loading. Built on the hover, which is a moment and can afford it.
			tip = function()
				return ("%s items. Click to take them off the column; the feed"
					.. " goes on recording them either way.")
					:format(ns.QualityWord(quality))
			end,
			get = function() return Lit(quality) end,
			set = function(on) Light(quality, on) end,
		}
	end

	chips[#chips + 1] = { gap = true }

	chips[#chips + 1] = {
		color = QUEST,
		mark = BANG,
		tip = "Quest items, whatever their own quality chip says. They are the"
			.. " rows with a ring round the icon.",
		get = function() return ns.db.lootFeedQuest end,
		set = function(on) ns.db.lootFeedQuest = on end,
	}
	chips[#chips + 1] = {
		color = C.heading,
		mark = COINS,
		tip = "Coin. Off, what you picked up is still in the purse along the"
			.. " bottom and out of the column.",
		get = function() return ns.db.lootFeedMoney end,
		set = function(on) ns.db.lootFeedMoney = on end,
	}
	return chips
end

--------------------------------------------------------------------------
-- The tooltip
--
-- The item's own text where the client will hand it over, which is the whole
-- reason UI/Scan.lua exists, and the item's name in its quality colour where it
-- will not. Either way the facts the feed knows and the item does not go
-- underneath.
--
-- What the item is worth is not here. It is Feeds/Worth.lua, registered against
-- every item hovered anywhere in the addon, because a mail attachment and a
-- link in chat deserve the same two lines a loot row gets. The one thing this
-- file still has to say about the money is the price it recorded when the item
-- dropped, handed over on the subject: the client answers about something in
-- your bags and goes quiet about one you have already sold.
--------------------------------------------------------------------------

local function Fill(entry)
	local lines = {}

	if entry.quest then
		lines[#lines + 1] = { "Quest item", color = QUEST }
	end
	lines[#lines + 1] = { "Looted", ns.Stream.Clock(entry.at) }
	if (entry.count or 1) > 1 then
		lines[#lines + 1] = { "Stack", tostring(entry.count) }
	end
	if entry.who then
		lines[#lines + 1] = { "Went to", entry.who }
	end

	return {
		kind = "item",
		link = entry.link,
		title = entry.name or "?",
		color = entry.color,
		count = entry.count,
		price = entry.price,
		lines = lines,
		hint = "Scroll the feed for what dropped before this."
			.. " /wk feed loot for the rest.",
	}
end

--------------------------------------------------------------------------

local stream = ns.Stream.New({
	prefix = "lootFeed",
	name = "WarriorKitLootFeed",
	title = "Loot",
	empty = "nothing yet",
	onTooltip = Fill,
	chips = Chips(),
	filter = Passes,
	-- The strip along the bottom, which is Feeds/Purse.lua's three numbers. It
	-- is on this feed and not on the combat one because this is the window
	-- already answering "what did I just get", and gold was the part of that
	-- answer a list of rows could not give: coin gets a row when it drops and
	-- the row scrolls away, and what you want an hour later is the total and
	-- the slope.
	onStatus = ns.Purse.Line,
	onStatusTooltip = ns.Purse.Ledger,
})

function LootFeed.Stream()
	return stream
end

-- Everything this part registers, which is the six a stream owns plus the three
-- that are about loot rather than about a column on a screen.
--
-- Bottom right, above the bags and clear of the meters, which sit left of
-- centre. That is where the client's own loot text goes past and it is where
-- your eye already is when something dies.
function LootFeed.Defaults()
	-- No word over it and no line round it, which is the third argument. The
	-- rows are an icon, a name in the item's own quality colour and a count,
	-- with the same quality colours as chips over them; there is nothing about
	-- that column the word "Loot" adds, and the edge was a window frame round
	-- something that is not a window.
	local defaults = ns.Stream.Defaults("lootFeed",
		{ "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -20, 180 }, false)

	-- Yours only. Everyone else's drops are the thing that makes the client's
	-- own loot spam unreadable in a raid, and a feed that reproduced it would
	-- have replaced one unreadable column with a prettier one.
	defaults.lootFeedGroup = false

	-- Every quality lit, greys included, because Comfort/Vendor.lua sells that
	-- trash for you on this addon's own defaults and the feed is the only place
	-- you will ever see what it was. Five bits, one per quality, and the
	-- arithmetic that reads them is at the top of this file.
	defaults.lootFeedShow = 2 ^ (QUALITIES + 1) - 1

	-- Quest items through whatever their quality chip says, because the reason
	-- to turn the whites off is the linen and the reason not to is the wolf
	-- liver, and this is the switch that has both.
	defaults.lootFeedQuest = true

	defaults.lootFeedMoney = true

	-- The status strip's, folded in here rather than registered on their own.
	-- Feeds/Feature.lua merges one table per stream and the strip belongs to
	-- this one, so this is where its keys reach the account file.
	for key, value in pairs(ns.Purse.Defaults()) do
		defaults[key] = value
	end
	return defaults
end

--------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------

local seen = 0

local function AddItem(who, link, count)
	local quality, price = ns.ItemValue(link)
	local name, icon = ns.ItemInfo(link)
	local color = QUALITY[quality or 1] or QUALITY[1]

	-- The class the client files it under, which is the only thing that tells a
	-- quest item from a white one. Read here rather than on the hover, because
	-- a tooltip that asked would be asking about an item that may have left
	-- your bags an hour ago, and this is one lookup on a path a drop drives.
	local _, class = ns.ItemKind(link)

	local entry = stream:Feed():Entry()
	entry.icon = icon or UNKNOWN
	entry.name = name or link
	entry.amount = "x" .. count
	entry.color = color
	entry.stripe = color
	entry.tone = C.text
	entry.link = link
	entry.count = count
	entry.who = who
	-- The three the filter and the row read. Quality is what the chips grade it
	-- by, quest is the ring round the icon and the chip that overrides them, and
	-- the price is the vendor's, kept because the client will answer for an item
	-- in your bags and go quiet about one you sold.
	entry.quality = quality
	entry.quest = (class == QUEST_CLASS) or nil
	entry.ring = entry.quest and QUEST or nil
	entry.price = price
	stream:Feed():Push()

	seen = seen + 1
	return true
end

local function AddMoney(text)
	for _, rule in ipairs(MONEY) do
		if rule.pattern then
			local phrase = text:match(rule.pattern)
			if phrase then
				local entry = stream:Feed():Entry()
				entry.icon = COIN
				-- The phrase is the client's own coin text, which already reads
				-- "12 Silver, 39 Copper" in whatever language this client is.
				-- It goes in the name rather than the number because it is
				-- three words and the number column is one.
				entry.name = phrase
				entry.amount = ""
				entry.color = C.heading
				entry.stripe = C.heading
				entry.money = true
				stream:Feed():Push()
				seen = seen + 1
				return true
			end
		end
	end
	return false
end

function LootFeed.OnLoot(text)
	if not ns.db.lootFeed or type(text) ~= "string" then
		return false
	end

	local who, link, count = Read(text)
	if not link then
		return false
	end
	if who and not ns.db.lootFeedGroup then
		return false
	end
	return AddItem(who, link, count)
end

function LootFeed.OnMoney(text)
	if not ns.db.lootFeed or type(text) ~= "string" then
		return false
	end
	-- The coin chip is not consulted here. It decides whether a coin row is
	-- drawn, the same as every other chip, and a capture that read it would put
	-- the setting back at the door this file spent its filter getting away from.
	return AddMoney(text)
end

--------------------------------------------------------------------------

-- How many of the loot sentences this client actually carries.
--
-- Worth a line in /wk status rather than assumed, because a locale that spells
-- one of them differently, or a flavour that does not have the crafted form at
-- all, is a feed that quietly misses a third of what drops. A number here is
-- the difference between finding that in a second and never finding it.
function LootFeed.Rules()
	local live = 0
	for _, rule in ipairs(RULES) do
		if rule.pattern then
			live = live + 1
		end
	end
	return live, #RULES
end

function LootFeed.Describe()
	if not ns.db.lootFeed then
		return "off"
	end

	local line = stream:Describe()
	local live, total = LootFeed.Rules()
	if live < total then
		line = line .. (", and this client carries %d of the %d loot messages")
			:format(live, total)
	end
	return line
end

-- What has ever reached the feed, for the panel and for scripts/harness.lua.
--
-- One number rather than the two it was. The second was what a quality floor
-- turned away at the door, and there is no door any more: everything that drops
-- is recorded and the chips decide what is drawn, which is a number the feed
-- itself already carries and puts in its own tally.
function LootFeed.Counts()
	return seen
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHAT_MSG_LOOT")
events:RegisterEvent("CHAT_MSG_MONEY")
events:SetScript("OnEvent", function(_, event, text)
	if event == "PLAYER_LOGIN" then
		-- The format strings are FrameXML's and are not all in place while the
		-- addon's own files are still loading, so the patterns are built at
		-- login rather than at the top of this file.
		Build()
		return
	end
	if event == "CHAT_MSG_LOOT" then
		LootFeed.OnLoot(text)
	else
		LootFeed.OnMoney(text)
	end
end)
