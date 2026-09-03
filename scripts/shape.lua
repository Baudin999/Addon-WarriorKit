-- What shape the code is in, measured per function rather than per file.
--
-- This replaces a per-file line ceiling. A line count says how much there is
-- and nothing about whether it can be read, and the only move it rewards is
-- cutting a file in half, which changes no function and no dependency. Two
-- things happened under the old gate and both are the reason this one exists:
-- one agent hit the ceiling and raised the number, and another took a split it
-- had not gone looking for. Neither wrote a better function.
--
-- So the three numbers here are the ones that survive a file being cut in half,
-- because each is a property of a function and not of a file.
--
--   length      a function you cannot see the ends of at once. The reader
--               holds the top in their head while reading the bottom, and
--               that is the cost, whatever file it lives in.
--   depth       how many conditions are true at the deepest point. Depth is
--               how many of them the reader is carrying.
--   branches    the decisions in one function. Every one is a path, and the
--               paths multiply while the tests do not.
--
-- Both clients ship Lua 5.1, so the scan is a lexer rather than a parser: it
-- walks the text once, skipping strings and comments, and counts the block
-- keywords. That is enough to be exact about all three, because Lua closes
-- every block with `end` or `until` and there is no `}` to guess at.
--
--   lua5.1 ../scripts/shape.lua <file> [file...]
--
-- Prints one line per violation and exits 1 if there were any.

-- The three numbers, set at what the code measures today. Every function in
-- the addon is under them, so nothing new may be worse than the worst thing
-- that already exists, and the entries below are what stands between these and
-- numbers worth having.
local FUNCTION_LINES = 100
local NESTING = 4
local BRANCHES = 30

-- Every function allowed past one of the three, with the number it measures
-- today and why. Three rules hold this list honest.
--
-- An entry needs a reason. An exemption nobody explained is the invisible debt
-- the file ceiling used to hide, so a missing `why` fails like a violation.
--
-- An entry names one function, not a file. Cutting the file in half moves
-- nothing here, which is the whole point of measuring functions.
--
-- An entry ratchets, in both directions and by two files. A function that
-- measures under its own number fails here, so an improvement cannot be spent
-- quietly on room to grow again. A number that goes up fails in
-- scripts/ratchet.lua, which reads the committed copy of this file and refuses
-- the edit that raises a ceiling to meet the function that just cleared it.
-- This file cannot catch that one: an entry raised to exactly what the code now
-- measures is an entry this scan agrees with.
--
-- The reasons fall into three kinds and it is worth seeing them as kinds: a
-- builder that places every region of one widget in one pass, a combat log
-- dispatch with one branch per event, and a walk over something the client
-- indexes in two dimensions. Only the first is a shape anybody would defend,
-- which is what makes this list a work list.
--
-- There was a fourth, the slash dispatcher with one branch per word, and it is
-- gone. Two entries carried it, and both retired when the words became a table
-- walked by ns.Command.Word rather than a chain of ifs. That is what this list
-- is for: an entry comes off it because the shape it excused stopped existing.
local ALLOWED = {
	{ path = "./UnitFrames/EnemyBars.lua", fn = "LayoutWidget", own = 168,
	  why = "places every region of one nameplate widget in one pass" },
	{ path = "./UnitFrames/Block.lua", fn = "Block.Place", own = 195,
	  why = "places every region of one block in one pass" },
	{ path = "./UI/Widgets.lua", fn = "UI.Kit", own = 119,
	  why = "the kit's own body, one closure per control, returned as a table" },
	{ path = "./UI/Ability.lua", fn = "Ability.New", own = 123,
	  why = "builds one ability square and every region on it" },
	{ path = "./Breakdown/Breakdown.lua", fn = "Breakdown.OnLog", branches = 37,
	  why = "combat log dispatch, one branch per event the record counts" },
	{ path = "./Feeds/Combat.lua", fn = "CombatFeed.OnLog", branches = 33,
	  why = "combat log dispatch, one branch per event the feed draws" },
	{ path = "./Comfort/Vendor.lua", fn = "Sweep", depth = 5,
	  why = "walks every bag and every slot in it" },
	{ path = "./Buttons/Ranks.lua", fn = "HighestRanks", depth = 5,
	  why = "walks every spell tab and every spell on it" },
	{ path = "./Comfort/Errors.lua", fn = "Names", depth = 5,
	  why = "walks the global table for the client's error constants" },
}

local EXEMPT = {}
for _, entry in ipairs(ALLOWED) do
	EXEMPT[entry.path .. "\0" .. entry.fn] = entry
end

-- The keywords that open a block, and the two that close one. `then` and the
-- `do` of a `for` or a `while` are not openers: they finish a header whose
-- keyword already opened the block. A bare `do` is an opener, which is why the
-- distinction has to be tracked rather than assumed.
local OPENS = {
	["function"] = true, ["if"] = true, ["for"] = true,
	["while"] = true, ["repeat"] = true,
}

-- What counts as a decision. `and` and `or` are in because a condition with
-- four of them is four paths whatever it looks like on one line, and leaving
-- them out is how a long boolean hides from a branch count.
local BRANCHY = {
	["if"] = true, ["elseif"] = true, ["for"] = true, ["while"] = true,
	["repeat"] = true, ["and"] = true, ["or"] = true,
}

-- Read the file whole. The addon's largest is under 60 KB.
local function Slurp(path)
	local handle = io.open(path, "r")
	if not handle then return nil end
	local text = handle:read("*a")
	handle:close()
	return text
end

-- Where a long bracket ends: [[ ]], [=[ ]=] and so on, used by both long
-- strings and long comments. Returns the position after the closing bracket,
-- or nil when the file ends first, which luacheck reports better than this.
local function LongBracket(text, start)
	local level = text:match("^%[(=*)%[", start)
	if not level then return nil end
	local close = "]" .. level .. "]"
	local from = text:find(close, start + #level + 2, true)
	if not from then return nil end
	return from + #close
end

-- The word tokens of a file, in order, each with the line it sits on.
-- Comments, strings and everything that is not an identifier are dropped,
-- because the three measurements only ever ask about keywords.
local function Words(text)
	local out, line, i, n = {}, 1, 1, #text
	while i <= n do
		local c = text:sub(i, i)
		if c == "\n" then
			line = line + 1
			i = i + 1
		elseif text:sub(i, i + 1) == "--" then
			local after = LongBracket(text, i + 2)
			if after then
				for _ in text:sub(i, after - 1):gmatch("\n") do line = line + 1 end
				i = after
			else
				i = (text:find("\n", i, true) or n + 1)
			end
		elseif c == "[" and text:match("^%[=*%[", i) then
			local after = LongBracket(text, i)
			if not after then return out end
			for _ in text:sub(i, after - 1):gmatch("\n") do line = line + 1 end
			i = after
		elseif c == "'" or c == '"' then
			local j = i + 1
			while j <= n do
				local d = text:sub(j, j)
				if d == "\\" then
					j = j + 2
				elseif d == c or d == "\n" then
					break
				else
					j = j + 1
				end
			end
			i = j + 1
		else
			local word, after = text:match("^([%a_][%w_]*)()", i)
			if word then
				out[#out + 1] = { word = word, line = line, pos = i }
				i = after
			else
				i = i + 1
			end
		end
	end
	return out
end

-- The name a function reports itself under. Lua names a function four ways.
-- Three of them put a dotted chain straight after the keyword and the fourth
-- assigns an anonymous one, so the text on both sides of the keyword is read
-- rather than the token stream, which has already dropped the dots. A name is
-- for the error message only; an anonymous function is measured like any other.
local function NameAt(text, pos, line)
	local named = text:match("^function%s*([%a_][%w_%.:]*)", pos)
	if named and named ~= "" then return named end
	local before = text:sub(math.max(1, pos - 80), pos - 1)
	local assigned = before:match("([%a_][%w_%.:]*)%s*=%s*$")
	if assigned then return assigned end
	return ("anonymous at line %d"):format(line)
end

-- One pass over one file. The stack holds every open block; a function frame
-- carries the three counters, and every token is charged to the innermost
-- function frame on the stack.
local function Measure(path, text)
	local words, found = Words(text), {}
	local stack, functions = {}, {}

	local function Innermost()
		for at = #stack, 1, -1 do
			if stack[at].fn then return stack[at] end
		end
		return nil
	end

	for index = 1, #words do
		local word, line = words[index].word, words[index].line
		local inner = Innermost()

		if inner and BRANCHY[word] then
			inner.branches = inner.branches + 1
		end

		if word == "do" then
			local top = stack[#stack]
			if top and top.pending then
				top.pending = nil
			else
				stack[#stack + 1] = {}
			end
		elseif OPENS[word] then
			local frame = { pending = (word == "for" or word == "while") or nil }
			if word == "function" then
				frame.fn = true
				frame.name = NameAt(text, words[index].pos, line)
				frame.line = line
				frame.branches = 1
				frame.depth = 0
				frame.nested = 0
				frame.base = #stack + 1
				functions[#functions + 1] = frame
			end
			stack[#stack + 1] = frame
		elseif word == "end" or word == "until" then
			local frame = stack[#stack]
			if frame then
				if frame.fn then
					frame.lines = line - frame.line + 1
					-- A function whose body is other functions reads as a
					-- list, not as a thousand lines, so the nested spans come
					-- off the parent's own count. Without this the gate is
					-- satisfied by wrapping code in a factory, which is the
					-- move the old line ceiling rewarded.
					stack[#stack] = nil
					local host = Innermost()
					if host then host.nested = host.nested + frame.lines end
					frame.own = frame.lines - frame.nested
				else
					stack[#stack] = nil
				end
			end
		end

		-- Depth is measured after the token, so the block a keyword opens is
		-- counted from inside it rather than from the line it starts on.
		local host = Innermost()
		if host then
			local depth = #stack - host.base
			if depth > host.depth then host.depth = depth end
		end
	end

	for _, frame in ipairs(functions) do
		local exempt = EXEMPT[path .. "\0" .. frame.name]
		if exempt and not exempt.why then
			found[#found + 1] = ("%s: %s is allow-listed with no reason given")
				:format(path, frame.name)
			exempt = nil
		end

		local measured = {
			own = frame.own or frame.lines or 0,
			depth = frame.depth,
			branches = frame.branches,
		}
		local gate = { own = FUNCTION_LINES, depth = NESTING, branches = BRANCHES }
		local says = {
			own = "is %d lines of its own, over %d",
			depth = "nests %d deep, over %d",
			branches = "takes %d branches, over %d",
		}

		for _, what in ipairs({ "own", "depth", "branches" }) do
			local ceiling = exempt and exempt[what]
			if ceiling then
				if measured[what] > ceiling then
					found[#found + 1] = ("%s:%d %s " .. says[what])
						:format(path, frame.line, frame.name, measured[what], ceiling)
				elseif measured[what] < ceiling then
					found[#found + 1] = ("%s:%d %s is down to %d and its entry still says %d: lower it")
						:format(path, frame.line, frame.name, measured[what], ceiling)
				end
			elseif measured[what] > gate[what] then
				found[#found + 1] = ("%s:%d %s " .. says[what])
					:format(path, frame.line, frame.name, measured[what], gate[what])
			end
		end
	end

	return found, functions
end

local paths = { ... }
local report = os.getenv("SHAPE_REPORT")
local failures, counted, worst = {}, 0, { lines = 0, depth = 0, branches = 0 }
local every = {}

for _, path in ipairs(paths) do
	local text = Slurp(path)
	if text then
		local found, functions = Measure(path, text)
		for _, one in ipairs(found) do failures[#failures + 1] = one end
		for _, frame in ipairs(functions) do
			counted = counted + 1
			frame.path = path
			every[#every + 1] = frame
			if (frame.own or 0) > worst.lines then worst.lines = frame.own end
			if frame.depth > worst.depth then worst.depth = frame.depth end
			if frame.branches > worst.branches then worst.branches = frame.branches end
		end
	end
end

-- A readout for setting the numbers, which is the only way to set them at what
-- the code measures rather than at what sounded round.
if report then
	table.sort(every, function(a, b)
		return (a[report] or 0) > (b[report] or 0)
	end)
	for at = 1, #every do
		local frame = every[at]
		print(("%5d  %s:%d %s"):format(frame[report] or 0, frame.path,
			frame.line, frame.name))
	end
	os.exit(0)
end

if #failures > 0 then
	for _, one in ipairs(failures) do print(one) end
	print(("shape FAIL: %d of %d functions"):format(#failures, counted))
	os.exit(1)
end

print(("shape  %d functions, worst is %d lines, %d deep, %d branches; gates are %d, %d, %d")
	:format(counted, worst.lines, worst.depth, worst.branches,
		FUNCTION_LINES, NESTING, BRANCHES))
os.exit(0)
