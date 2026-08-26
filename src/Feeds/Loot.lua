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

-- The quality palette, as tables this file owns.
--
-- ITEM_QUALITY_COLORS is the client's and would do for the numbers, but every
-- guard in UI/Feed.lua compares a colour by table identity, so a palette read
-- fresh out of the client on each row would fail every one of those guards and
-- repaint a colour that had not changed. These are stable references, which is
-- the same reason Unit/Color.lua owns its own tables.
--
-- The numbers are the client's where it will say and the game's well known ones
-- where it will not, so a client with no ITEM_QUALITY_COLORS draws the right
-- colours rather than eight greys.
local QUALITY = {
	[0] = { 0.62, 0.62, 0.62 },
	[1] = { 1.00, 1.00, 1.00 },
	[2] = { 0.12, 1.00, 0.00 },
	[3] = { 0.00, 0.44, 0.87 },
	[4] = { 0.64, 0.21, 0.93 },
	[5] = { 1.00, 0.50, 0.00 },
	[6] = { 0.90, 0.80, 0.50 },
	[7] = { 0.00, 0.80, 1.00 },
}

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
-- The tooltip
--
-- The item's own text where the client will hand it over, which is the whole
-- reason UI/Tooltip.lua carries a scanner, and the item's name in its quality
-- colour where it will not. Either way the two facts the feed knows and the
-- item does not, when it landed and who it went to, are added underneath.
--------------------------------------------------------------------------

-- When an entry happened, on the wall clock.
--
-- GetTime counts from when the client started, which is the right clock to
-- record on and an unreadable one to show, so the difference between then and
-- now is taken off the current time of day. Built here rather than stored on
-- the entry because this runs on a hover and Feed:Push runs on a drop: one of
-- those can afford a string and the other is on the path a raid drives.
local function Clock(at)
	if not at then
		return "?"
	end
	return date("%H:%M:%S", time() - (GetTime() - at))
end

local function Fill(entry, tip)
	if not (entry.link and tip.Item(entry.link)) then
		tip.Title(entry.name or "?", entry.color)
	end

	tip.Blank()
	tip.Pair("Looted", Clock(entry.at))
	if (entry.count or 1) > 1 then
		tip.Pair("Stack", tostring(entry.count))
	end
	if entry.who then
		tip.Pair("Went to", entry.who)
	end
	tip.Hint("Scroll the feed for what dropped before this. /wk feed loot for the rest.")
end

--------------------------------------------------------------------------

local stream = ns.Stream.New({
	prefix = "lootFeed",
	name = "WarriorKitLootFeed",
	title = "Loot",
	empty = "nothing yet",
	onTooltip = Fill,
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
	local defaults = ns.Stream.Defaults("lootFeed",
		{ "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -20, 180 })

	-- Yours only. Everyone else's drops are the thing that makes the client's
	-- own loot spam unreadable in a raid, and a feed that reproduced it would
	-- have replaced one unreadable column with a prettier one.
	defaults.lootFeedGroup = false

	-- Everything, including the grey vendor trash, because on this addon's own
	-- defaults Comfort/Vendor.lua sells that trash for you and the feed is the
	-- only place you will ever see what it was.
	defaults.lootFeedQuality = 0

	defaults.lootFeedMoney = true
	return defaults
end

--------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------

local seen, dropped = 0, 0

local function AddItem(who, link, count)
	local quality = ns.ItemValue(link)
	if quality and quality < ns.db.lootFeedQuality then
		dropped = dropped + 1
		return false
	end

	local name, icon = ns.ItemInfo(link)
	local color = QUALITY[quality or 1] or QUALITY[1]

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
	if not ns.db.lootFeed or not ns.db.lootFeedMoney or type(text) ~= "string" then
		return false
	end
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
	if dropped > 0 then
		line = line .. (", %d under the quality floor"):format(dropped)
	end
	return line
end

-- What has ever reached the feed and what the quality floor turned away, for
-- the panel and for scripts/harness.lua.
function LootFeed.Counts()
	return seen, dropped
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
