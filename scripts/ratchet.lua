-- Which way the numbers in the gates are allowed to move.
--
-- scripts/shape.lua and scripts/check.sh both hold ceilings, and both say in
-- their own comments that those ceilings are ratchets: a number sits at what
-- the code measures today, an improvement lowers it in the same commit, and
-- growth fails rather than passing unremarked. Both enforce half of that. A
-- function that measures under its own entry fails until the entry comes down,
-- so an improvement cannot be spent quietly on room to grow again. Nothing
-- enforced the other half. A function that grew past its entry could have the
-- entry edited upward instead, and every scan went green.
--
-- That is not hypothetical and it is not rare. The header of shape.lua says the
-- per-file line ceiling was replaced because "one change hit the ceiling and
-- raised the number", and `59b36ce` then raised BarsWord from 97 lines and 37
-- branches to 101 and 38, inside the file that tells the story. A ceiling that
-- can be raised by the change it blocks is not a gate, it is a formality.
--
-- A raise is only visible against history, so this reads the committed copy of
-- each watched file and compares it to the one on disk:
--
--   lua5.1 scripts/ratchet.lua <label> <committed> <working>
--
-- Prints one line per number that went up and exits 1 if there were any.
--
-- Three moves stay legal. Lowering a number is the point. Deleting an entry is
-- an exemption given back. Adding one is a function or a file that did not
-- exist on the list before, and the check that belongs to a new entry belongs to
-- the file that holds it: shape.lua refuses an entry with no reason written on
-- it, and check.sh refuses one that names no file, carries no reason or claims a
-- marker the code does not have. The move this refuses is the one that reads as
-- progress and is not: the same key, higher.
--
-- Deleting an entry and re-adding it higher is the obvious way around, and it
-- does not work. The commit that deletes it leaves a function over the gate
-- with no exemption, and shape.lua fails on that before this ever runs.

local label, before, after = ...
if not (label and before and after) then
	io.stderr:write("usage: ratchet.lua <label> <committed> <working>\n")
	os.exit(2)
end

local function Read(path)
	local handle, err = io.open(path, "r")
	if not handle then
		io.stderr:write("ratchet: cannot read " .. tostring(err) .. "\n")
		os.exit(2)
	end
	local text = handle:read("*a")
	handle:close()
	return text
end

-- Every ceiling a watched file declares, as a name and a number. Four shapes,
-- which is the two syntaxes each of the two files writes, and all four are run
-- over both files: a pattern that matches nothing costs nothing, and a file
-- that grows the other one's shape is covered the day it does.
--
-- An allow-list entry is keyed by its list as well as its path. Nothing needed
-- that while there were two lists and they named different trees; there are
-- seven now, four of them over src/, and the same file appearing on two of them
-- is ordinary rather than exotic.
local function Ceilings(text)
	local found = {}

	-- Which allow-list the entry below belongs to, so two lists naming the same
	-- file are two ceilings rather than one. They are keyed on the path alone
	-- otherwise, and check.sh now holds seven such lists: the two harness
	-- budgets, the two markers, the two line exemptions and the ticker frames. A
	-- path on two of them would leave whichever came second watching the first
	-- one's number, which is a ratchet that reads as green while the ceiling
	-- under it moves.
	local scope = nil

	-- Walked a line at a time rather than swept with a newline on each end
	-- of the pattern. Three of these declarations sit on consecutive lines,
	-- and a sweep whose match ends in the newline the next one opens with
	-- reads every second one. It found FUNCTION_LINES and BRANCHES and left
	-- NESTING unwatched, which is a gate with a hole in the shape of the
	-- thing it was written to catch.
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		-- shape.lua's three, and check.sh's two. `local NESTING = 4` and
		-- `HARNESS_LINE_LIMIT=800` are one declaration in two languages.
		local name, value = line:match("^local ([A-Z_]+) = (%d+)$")
		if not name then
			name, value = line:match("^([A-Z_]+)=(%d+)$")
		end
		if not name then
			-- check.sh's allow-lists, one exemption per line as a path,
			-- a ceiling and a reason. Matched on the path ending in
			-- .lua so a sentence in a comment cannot look like an entry,
			-- and qualified by the list it was found in.
			local open = line:match('^([A-Z_]+)="$')
			if open then
				scope = open
			elseif line == '"' then
				scope = nil
			end
			name, value = line:match("^([%w%-%_/%.]+%.lua):(%d+):")
			if name and scope then name = scope .. " " .. name end
		end
		if name then
			found[name] = tonumber(value)
		end
	end

	-- shape.lua's allow-list. Scoped to the table rather than swept for
	-- braces, because the file is full of them and only these carry a
	-- ceiling. One entry names one function and may hold up to three
	-- numbers, so each dimension is its own key: a length that comes down
	-- while a branch count goes up is a raise and has to read as one.
	local head = text:find("local ALLOWED = ", 1, true)
	if head then
		local block = text:match("%b{}", head)
		if block then
			-- Inside the braces, not including them. Swept whole, the
			-- first balanced match is the table itself, and one entry
			-- comes back wearing three other entries' numbers.
			for entry in block:sub(2, -2):gmatch("%b{}") do
				local path = entry:match('path%s*=%s*"([^"]*)"')
				local fn = entry:match('fn%s*=%s*"([^"]*)"')
				if path and fn then
					for _, what in ipairs({ "own", "depth", "branches" }) do
						local value = entry:match(what .. "%s*=%s*(%d+)")
						if value then
							found[path .. " " .. fn .. " " .. what] = tonumber(value)
						end
					end
				end
			end
		end
	end

	return found
end

local was, now = Ceilings(Read(before)), Ceilings(Read(after))

local raised = {}
for name, old in pairs(was) do
	local new = now[name]
	if new and new > old then
		raised[#raised + 1] = { name = name, old = old, new = new }
	end
end
table.sort(raised, function(a, b) return a.name < b.name end)

for _, entry in ipairs(raised) do
	print(("%s: %s was %d and is now %d. A ceiling ratchets down; fix the code or delete the rule.")
		:format(label, entry.name, entry.old, entry.new))
end

os.exit(#raised > 0 and 1 or 0)
