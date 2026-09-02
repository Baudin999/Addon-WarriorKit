-- The functions a ticker can reach, derived rather than typed.
--
-- scripts/check.sh bans an unguarded widget write and an allocation on any code
-- path a frame handler reaches, and to do that it needs the set of functions
-- that are on one. That set used to be two hundred lines of `File.lua:Function`
-- written out by hand at the top of check.sh, and a hand-written transitive
-- closure has one failure mode that matters: a hot function grows a new callee,
-- nobody adds it to the list, and the guard scan comes quietly off that code.
-- Nothing fails. The list is still green. It is just smaller than the truth.
--
-- So the list is computed here instead, from the roots out. A root is the named
-- function handed to ns.UI.Ticker or to SetScript("OnUpdate", ...), which is why
-- check.sh refuses an anonymous one in either position: a closure with no name
-- is a root this file cannot name and a body the guard scan cannot find.
--
-- The walk is a lexer over the text rather than a parse, for the reason
-- shape.lua is: both clients ship Lua 5.1 and the addon's own shapes are
-- regular. It resolves three kinds of call and deliberately over-approximates
-- the third:
--
--   Local.Fn()      a call on a module table, matched to `function Local.Fn(`
--                   wherever it is defined. ns.Alias.Fn() is the same function
--                   under its export name, and the two spellings rarely agree:
--                   Meter/Threat.lua defines ThreatMeter.Update and hands it out
--                   as ns.MeterThreat. So `ns.Alias = Local` is read out of every
--                   file first and the alias translated back before the lookup.
--   Fn()            a bare name, matched to `local function Fn(` in the same
--                   file only, which is what Lua scoping says it can be. An
--                   unmatched bare name is a client API and is not ours to walk.
--   obj:Method()    matched to every `function X:Method(` in the same file,
--                   because the receiver's type is not knowable from the text
--                   and a file is the smallest honest guess at it.
--
-- One edge the text cannot carry at all is a function stored in a table field
-- and called back through it: Feeds/Loot.lua hands ns.Purse.Line to a stream as
-- `onStatus` and the stream's tick calls `stream.onStatus()`. Following that
-- would mean resolving field assignments, which is the walk that reaches
-- everything. So it is declared instead. A `-- hot: <reason>` comment on the
-- line above a definition seeds it as a root, the reason is required, and the
-- declaration sits at the function it is about rather than in a list somewhere
-- else.
--
-- Over-approximating pulls extra functions into the closure, and that direction
-- is the safe one: a function scanned that no ticker reaches costs a guard
-- nobody needed, and a function missed costs the defect this rule exists to
-- catch. It is only safe while the closure stays smaller than the addon. Walked
-- at its loosest it reached twelve hundred of the two thousand functions here
-- and reported thirteen hundred violations, which is not a gate, it is a list.
--
-- One edge did that on its own: a builder that defines twenty click handlers
-- inside itself was handing all twenty to whatever reached the builder. A
-- closure passed to SetScript("OnClick") is not on a tick path, so calls are
-- read at the function's own depth and the nested bodies are skipped. A closure
-- called through a table field is unfollowable either way and is what the
-- `-- unguarded:` exemption is for.
--
--   lua5.1 ../scripts/hot.lua <dir>
--
-- Prints one `File.lua:Function` per line, sorted, for check.sh to scan.
--
--   lua5.1 ../scripts/hot.lua --markers <dir>
--
-- Prints one `kind File.lua Function` per marker instead, sorted. check.sh
-- holds an allow-list against that, one entry per marked function, and the two
-- have to agree; reading them out of here rather than grepping for the comment
-- again means there is one implementation of what a marker is and where it
-- sits.

local function Slurp(path)
	local handle = io.open(path, "r")
	if not handle then return nil end
	local text = handle:read("*a")
	handle:close()
	return text
end

-- Comments and strings blanked to spaces, newlines kept, so every character
-- position and line number in the result still matches the file on disk. A call
-- named inside a comment or a string is not a call.
local function Clean(text, keepStrings)
	local out, i, n = {}, 1, #text
	local function Blank(chunk)
		out[#out + 1] = (chunk:gsub("[^\n]", " "))
	end
	while i <= n do
		local c = text:sub(i, i)
		local long = text:match("^%-%-%[(=*)%[", i) or (c == "[" and text:match("^%[(=*)%[", i))
		if long then
			local close = "]" .. long .. "]"
			local from = text:find(close, i, true)
			local stop = from and (from + #close) or (n + 1)
			Blank(text:sub(i, stop - 1))
			i = stop
		elseif text:sub(i, i + 1) == "--" then
			local stop = text:find("\n", i, true) or (n + 1)
			Blank(text:sub(i, stop - 1))
			i = stop
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
			local stop = math.min(j + 1, n + 1)
			local chunk = text:sub(i, stop - 1)
			if keepStrings then out[#out + 1] = chunk else Blank(chunk) end
			i = stop
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
	return table.concat(out)
end

-- The top-level functions of one file, each with the span of its body. Only
-- top-level, because that is the unit check.sh's guard scan reads: it opens on
-- a `function` in the first column and closes on the `end` in the first column.
-- A closure nested inside one is part of that function's body here, which is
-- the same over-approximation the guard scan makes and for the same reason.
-- The top-level functions of one file, each with the span of its body.
--
-- Top level only, because that is the unit check.sh's guard scan reads: it opens
-- on a definition in the first column and closes on the `end` in the first
-- column. A closure nested inside one counts as part of that function's body
-- here, which is the same over-approximation the guard scan makes and for the
-- same reason.
local function Functions(clean)
	local found, open = {}, nil
	local at = 1
	while at <= #clean do
		local stop = clean:find("\n", at, true) or (#clean + 1)
		local line = clean:sub(at, stop - 1)
		local head = line:match("^function%s+[%a_][%w_%.:]*")
			or line:match("^local%s+function%s+[%a_][%w_%.:]*")
		if head then
			if open then open.to = at - 1 end
			-- The body starts past its own `function` keyword, or the nesting
			-- walk in Direct would open on the definition and blank the lot.
			open = {
				name = head:match("([%a_][%w_%.:]*)$"),
				from = at + #head,
			}
			found[#found + 1] = open
		elseif open and line:match("^end") then
			open.to = stop
			open = nil
		end
		at = stop + 1
	end
	if open then open.to = #clean end
	return found
end

-- `--markers` prints the markers instead of the closure, one
-- `kind file Function` per line, for check.sh to hold its two marker
-- allow-lists against. It is the same Markers() the walk reads, so the list in
-- check.sh and the walk can never disagree about what a marker says or which
-- function it sits on: there is one reader of that syntax and this is it.
local markersOnly = false
local args = {}
for _, value in ipairs(arg) do
	if value == "--markers" then markersOnly = true else args[#args + 1] = value end
end

local dir = args[1] or "."

-- Every .lua under the directory, path relative to it, as check.sh names them.
local files = {}
local pipe = io.popen(("find %q -name '*.lua' -type f | sort"):format(dir))
for line in pipe:lines() do
	files[#files + 1] = line:gsub("^" .. dir:gsub("(%W)", "%%%1") .. "/?", "")
end
pipe:close()

-- Two indexes over every definition in the addon. byDotted answers
-- `Local.Fn()`, byMethod answers `obj:Fn()`, and byLocal is per file because a
-- bare name is a local and locals do not cross files.
-- Every module's export name against the local it is defined under, read off
-- the one line each file ends its header with.
local locals = {}
for _, rel in ipairs(files) do
	local text = Slurp(dir .. "/" .. rel)
	for alias, name in (text or ""):gmatch("\nns%.([%w_]+)%s*=%s*([%w_]+)%s*\n") do
		locals[alias] = name
	end
end

-- The two markers a file may put above a definition, read off the file itself
-- because Clean has already blanked the comments they live in.
--
--   -- hot: <why>     seed this function as a root. For a function reached
--                     through a table field, which no walk over the text can
--                     follow.
--   -- cold: <why>    stop at this function. It is on a tick path and it does
--                     not run on every tick: the caller compares first, or it
--                     builds a widget that has just appeared. Its writes happen
--                     when something changed rather than on the tick that
--                     reached it, and the subtree under it is the rest of the
--                     same change and stops with it.
--
-- Both need a reason. A marker without one is the invisible debt this whole
-- file exists to stop, and it fails.
local function Markers(rel, text)
	local out, kind, why, complained = {}, nil, nil, false
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		local mark, reason = line:match("^%-%-%s*(hot):%s*(.*)")
		if not mark then mark, reason = line:match("^%-%-%s*(cold):%s*(.*)") end
		if mark then
			kind, why = mark, reason
		elseif kind then
			local name = line:match("^function%s+([%a_][%w_%.:]*)")
				or line:match("^local%s+function%s+([%a_][%w_%.:]*)")
			if name then
				out[name] = { kind = kind, why = why }
				kind = nil
			elseif not line:match("^%-%-") then
				-- The reason may run over several lines, so the marker holds
				-- until the definition or until anything that is not a comment
				-- says it was never on one.
				io.stderr:write(("%s: a %s: marker names no function\n"):format(rel, kind))
				complained = true
				kind = nil
			end
		end
	end
	for name, mark in pairs(out) do
		if mark.why:match("^%s*$") then
			io.stderr:write(("%s: %s carries a %s: marker with no reason\n")
				:format(rel, name, mark.kind))
			complained = true
		end
	end
	return out, complained
end

local byDotted, byMethod, byLocal, bodies, marks = {}, {}, {}, {}, {}
local bad = false
for _, rel in ipairs(files) do
	local text = Slurp(dir .. "/" .. rel)
	if text then
		local clean = Clean(text)
		local found, complained = Markers(rel, text)
		bad = bad or complained
		byLocal[rel] = {}
		for name, mark in pairs(found) do
			marks[rel .. ":" .. name] = mark
		end
		for _, fn in ipairs(Functions(clean)) do
			local key = rel .. ":" .. fn.name
			bodies[key] = clean:sub(fn.from, fn.to)
			if fn.name:find(":") then
				local tail = rel .. ":" .. fn.name:match(":([%w_]+)$")
				byMethod[tail] = byMethod[tail] or {}
				byMethod[tail][#byMethod[tail] + 1] = key
			elseif fn.name:find("%.") then
				byDotted[fn.name] = byDotted[fn.name] or {}
				byDotted[fn.name][#byDotted[fn.name] + 1] = key
			else
				byLocal[rel][fn.name] = key
			end
		end
	end
end

if markersOnly then
	local lines = {}
	for key, mark in pairs(marks) do
		local rel, name = key:match("^(.-):(.*)$")
		lines[#lines + 1] = ("%s %s %s"):format(mark.kind, rel, name)
	end
	table.sort(lines)
	for _, line in ipairs(lines) do print(line) end
	os.exit(bad and 1 or 0)
end

-- One function's own statements, with every closure defined inside it blanked.
--
-- Block keywords are counted rather than parsed, the way shape.lua counts them:
-- `for` and `while` finish their header with a `do` that opens nothing, so the
-- pending flag is what tells that `do` from a bare one.
local function Direct(body)
	local out, stack, pending = {}, {}, false
	local i, n = 1, #body
	local function Deep()
		for at = 1, #stack do
			if stack[at] == "fn" then return true end
		end
		return false
	end
	while i <= n do
		local word, after = body:match("^([%a_][%w_]*)()", i)
		if word then
			if word == "function" then
				stack[#stack + 1] = "fn"
			elseif word == "if" or word == "repeat" then
				stack[#stack + 1] = "block"
			elseif word == "for" or word == "while" then
				stack[#stack + 1] = "block"
				pending = true
			elseif word == "do" then
				if pending then pending = false else stack[#stack + 1] = "block" end
			elseif word == "end" or word == "until" then
				stack[#stack] = nil
			end
			out[#out + 1] = Deep() and (word:gsub(".", " ")) or word
			i = after
		else
			out[#out + 1] = Deep() and " " or body:sub(i, i)
			i = i + 1
		end
	end
	return table.concat(out)
end

-- What one function body calls, resolved to the keys above.
local function Calls(key)
	local rel = key:match("^(.-):")
	local body = Direct(bodies[key] or "")
	local out = {}
	local function Add(k) if k and k ~= key then out[k] = true end end

	for name in body:gmatch("([%a_][%w_%.]*)%s*%(") do
		if name:find("%.") then
			-- The last two segments are the call. ns.Perf.Start and Perf.Start
			-- are the same function under its export name and its local one.
			local prefix, tail = name:match("([%w_]+)%.([%w_]+)$")
			for _, k in ipairs(byDotted[prefix .. "." .. tail] or {}) do Add(k) end
			if locals[prefix] then
				for _, k in ipairs(byDotted[locals[prefix] .. "." .. tail] or {}) do Add(k) end
			end
			if prefix == "ns" then
				for _, k in ipairs(byDotted["ns." .. tail] or {}) do Add(k) end
			end
		else
			Add(byLocal[rel] and byLocal[rel][name])
		end
	end
	for tail in body:gmatch(":([%a_][%w_]*)%s*%(") do
		for _, k in ipairs(byMethod[rel .. ":" .. tail] or {}) do Add(k) end
	end
	return out
end

-- The roots: what a frame handler is actually set to. Both forms name a
-- function rather than opening a closure, which check.sh enforces separately.
local roots = {}
for key, mark in pairs(marks) do
	if mark.kind == "hot" then
		local rel, name = key:match("^(.-):(.*)$")
		roots[#roots + 1] = { rel = rel, name = name }
	end
end
for _, rel in ipairs(files) do
	local text = Slurp(dir .. "/" .. rel)
	if text then
		local clean = Clean(text, true)
		for name in clean:gmatch('SetScript%s*%(%s*"OnUpdate"%s*,%s*([%a_][%w_%.:]*)%s*%)') do
			-- Handing back the OnUpdate is how a tick stops, and nil is not a
			-- root.
			if name ~= "nil" then
				roots[#roots + 1] = { rel = rel, name = name }
			end
		end
		for at, call in clean:gmatch("()UI%.Ticker%s*(%b())") do
			-- The definition of UI.Ticker is not a call to it, and its own
			-- parameter list would otherwise read as a root.
			if clean:sub(at - 9, at - 1) ~= "function " then
				local last = call:match(",%s*([%a_][%w_%.:]*)%s*%)$")
				if last then roots[#roots + 1] = { rel = rel, name = last } end
			end
		end
	end
end

-- Breadth first from every root. A key reached twice is not walked twice.
local seen, queue = {}, {}
local function Take(key)
	if key and not seen[key] then
		seen[key] = true
		-- A function that declares itself cold is where the walk stops. It is
		-- not emitted and neither is anything only it reaches, which is the
		-- rest of the same change.
		if not (marks[key] and marks[key].kind == "cold") then
			queue[#queue + 1] = key
		end
	end
end

-- A root is seeded to the definition in the file that names it where there is
-- one, because nine files define Blizz.Apply and eight of them are somebody
-- else's. Failing that it seeds all of them, which is the safe direction.
local function Seed(rel, name)
	local hits
	if name:find("%.") then
		local prefix, tail = name:match("([%w_]+)%.([%w_]+)$")
		hits = byDotted[prefix .. "." .. tail]
			or byDotted[(locals[prefix] or "") .. "." .. tail]
			or byDotted["ns." .. tail]
	elseif byLocal[rel] and byLocal[rel][name] then
		hits = { byLocal[rel][name] }
	end
	if not hits or #hits == 0 then
		io.stderr:write(("hot.lua cannot find the handler %s names in %s\n"):format(name, rel))
		bad = true
		return
	end
	for _, key in ipairs(hits) do
		if key:match("^(.-):") == rel then
			Take(key)
			return
		end
	end
	for _, key in ipairs(hits) do Take(key) end
end

for _, root in ipairs(roots) do Seed(root.rel, root.name) end

local at = 1
while at <= #queue do
	local key = queue[at]
	at = at + 1
	for callee in pairs(Calls(key)) do
		Take(callee)
	end
end

local out = {}
for at = 1, #queue do out[#out + 1] = queue[at] end
table.sort(out)
for _, key in ipairs(out) do print(key) end

os.exit(bad and 1 or 0)
