local ADDON, ns = ...

local LootLine = {}
ns.LootLine = LootLine

--------------------------------------------------------------------------
-- Reading the server's loot sentences
--
-- CHAT_MSG_LOOT and CHAT_MSG_MONEY arrive as one localised sentence with a
-- link poked into it. This turns one into who got what and how many, and hands
-- back nothing at all for a line that is not loot.
--
-- **The sentences are built, never typed.** The client hands the addon the same
-- format strings it used to write the message, so LOOT_ITEM_SELF_MULTIPLE
-- becomes a pattern and a German client is read by German rules without a word
-- of German anywhere in this addon. Typing "You receive loot:" here would be a
-- feature that works on one locale and silently captures nothing on the rest.
--
-- **It is in Core because two parts now ask.** This was Feeds/Loot.lua's
-- private knowledge until Bags/Session.lua needed the same answer about the
-- same message, and a part may not name a file outside its own tree. It is the
-- shape Core/Piles.lua already has, and it left Bags/Bags.lua for exactly this
-- reason one release earlier: a shared file that wraps a client API, owns no
-- setting and draws nothing.
--
-- The two readers want different halves and that is fine. The feed draws every
-- line including other people's, because watching what the group is picking up
-- is what a loot feed is for. The bag session records only your own, because a
-- pile in your bags cannot hold somebody else's sword.
--------------------------------------------------------------------------

-- The loot sentences, most specific first.
--
-- Order is the whole correctness of this table. "You receive loot: %s." matches
-- the multiple form too, because the link is followed by "x4" and `(.+)` will
-- happily swallow it, so every counted sentence has to be tried before its
-- uncounted twin. Getting that the wrong way round gives a reader where every
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

-- The three denominations the coin phrase inside those two is written in, and
-- what one of each is worth in copper.
--
-- Built from the client's own amount strings for the same reason the sentences
-- above are: GOLD_AMOUNT is "%d Gold" here and something else on a German
-- client, and a reader that types either counts nothing on the other. The
-- phrase joins as many of them as the coin needed, "12 Silver, 39 Copper", and
-- the comma between them is the client's business rather than this file's.
local COIN = {
	{ format = "GOLD_AMOUNT", worth = 10000 },
	{ format = "SILVER_AMOUNT", worth = 100 },
	{ format = "COPPER_AMOUNT", worth = 1 },
}

--------------------------------------------------------------------------
-- Turning a format string into a pattern
--
-- The client's loot messages are `%s` and `%d` in a localised sentence. Every
-- magic character is escaped first, which turns each `%s` into `%%s`, and then
-- the two placeholders are put back as captures.
--
-- Nil for a format string this client does not carry, which is how the table
-- above can name messages that exist on one flavour and not the other without
-- either of them raising.
--
-- `loose` leaves the anchors off, because a denomination is one clause inside a
-- longer phrase rather than the whole of a line. Anchoring "%d Copper" would
-- read the copper off a coin phrase that was only copper and nothing off one
-- that had silver in front of it.
--------------------------------------------------------------------------

local function Pattern(format, loose)
	if type(format) ~= "string" then
		return nil
	end
	local body = format:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
	body = body:gsub("%%%%s", "(.+)")
	body = body:gsub("%%%%d", "(%%d+)")
	if loose then
		return body
	end
	return "^" .. body .. "$"
end

local built = false

-- The patterns, built once on the first line anybody reads.
--
-- Lazily rather than at login, and that is a change from where this code came
-- from. Feeds/Loot.lua built them in its own PLAYER_LOGIN handler because the
-- format strings are FrameXML's and are not all in place while the addon's
-- files are still loading. That reasoning is right and the login hook was one
-- way to satisfy it; doing it on first use satisfies it too, and it cannot be
-- got wrong by a second reader that forgets to ask. The first loot message of
-- an evening is a long way after login either way.
function LootLine.Build()
	if built then
		return false
	end
	built = true
	for _, rule in ipairs(RULES) do
		rule.pattern = Pattern(_G[rule.format])
	end
	for index, name in ipairs(MONEY) do
		MONEY[index] = { format = name, pattern = Pattern(_G[name]) }
	end
	for _, coin in ipairs(COIN) do
		coin.pattern = Pattern(_G[coin.format], true)
	end
	return true
end

--------------------------------------------------------------------------
-- Reading one message
--------------------------------------------------------------------------

-- The item link out of whatever the sentence captured. The capture is already
-- the whole link in every rule above, so this is a check rather than a search:
-- a chunk with no item hyperlink in it is a sentence that matched by accident
-- and must not be reported as loot.
local function Link(chunk)
	if type(chunk) ~= "string" or not chunk:find("|Hitem:", 1, true) then
		return nil
	end
	return (chunk:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- One rule against one line.
--
-- False where the rule did not match, and false too where it matched something
-- with no item link in it, which is the same answer as far as the caller is
-- concerned: keep trying the rules under this one.
--
-- Its own function rather than the innermost two branches of the walk below.
-- Together they nested five deep and sat on scripts/shape.lua's allow-list for
-- it, which is a nesting gate exempting the one function that most wanted the
-- split. Pulled apart on the move into Core and the exemption deleted with it.
local function Against(rule, text)
	local a, b, c = text:match(rule.pattern)
	if not a then
		return false
	end
	if rule.mine then
		local link = Link(a)
		if not link then
			return false
		end
		return true, nil, link, tonumber(rule.counted and b or 1) or 1
	end
	local link = Link(b)
	if not link then
		return false
	end
	return true, a, link, tonumber(rule.counted and c or 1) or 1
end

-- Who, what and how many, or nothing at all for a line that is not loot.
--
-- `who` is nil when the sentence is about you, which is the one distinction
-- every caller cares about and is why it is the first return rather than a
-- flag somebody has to remember to check.
function LootLine.Read(text)
	if type(text) ~= "string" then
		return nil, nil, nil
	end
	LootLine.Build()
	for _, rule in ipairs(RULES) do
		if rule.pattern then
			local matched, who, link, count = Against(rule, text)
			if matched then
				return who, link, count
			end
		end
	end
	return nil, nil, nil
end

-- The coin phrase as a number, by reading each denomination back out of it
-- with the string the client wrote it with.
--
-- Nil rather than nought where no denomination matched, because the two are
-- different answers: nought is a phrase that really said nothing, and nil is a
-- client whose amount strings are not in place or a locale this got wrong. A
-- caller adding pickups up has to be able to tell them apart, or it adds
-- nought to a running total and reports a sum that is short.
local function Copper(phrase)
	local sum, read = 0, false
	for _, coin in ipairs(COIN) do
		local amount = coin.pattern and phrase:match(coin.pattern)
		if amount then
			sum = sum + tonumber(amount) * coin.worth
			read = true
		end
	end
	return read and sum or nil
end

-- The client's own coin text out of a money line, which already reads "12
-- Silver, 39 Copper" in whatever language this client is, and what that comes
-- to in copper. Nothing at all for a line that is not about coin.
--
-- Both, rather than the phrase alone, because the phrase is what a row says and
-- the number is what two of them add up to. The feed wants the sentence for one
-- pickup and the sum for three.
function LootLine.Money(text)
	if type(text) ~= "string" then
		return nil, nil
	end
	LootLine.Build()
	for _, rule in ipairs(MONEY) do
		if rule.pattern then
			local phrase = text:match(rule.pattern)
			if phrase then
				return phrase, Copper(phrase)
			end
		end
	end
	return nil, nil
end

-- How many of the sentences this client actually carries. The loot feed reports
-- it, because a client missing half of them captures less rather than raising,
-- and a number that quietly drops is the only way anybody would find out.
function LootLine.Rules()
	LootLine.Build()
	local held = 0
	for _, rule in ipairs(RULES) do
		if rule.pattern then
			held = held + 1
		end
	end
	return held, #RULES
end
