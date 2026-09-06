-- Reading Lua without parsing it.
--
-- Both clients ship Lua 5.1 and both gates over src/ ask the same small
-- question of a file: where are the identifiers, and which of them are real
-- rather than words inside a comment or a string. That is a lexer, not a
-- parser. Lua closes every block with `end` or `until` and there is no `}` to
-- guess at, so a single pass over the text is exact for anything counted in
-- keywords.
--
-- It lived in scripts/shape.lua until scripts/trees.lua wanted the same pass.
-- Two copies of a tokeniser is the defect a second copy always is: the first
-- time one of them learns about a long bracket and the other does not, the two
-- gates disagree about what the file says and only one of them is right.
--
-- Skipping comments is not fussiness here, it is the whole reliability of
-- trees.lua. This codebase writes long headers that name other files' symbols
-- in prose, and `ns.CharReadout` appears in three sentences that no code runs.
-- A grep counts those. This does not.
--
-- Loaded as a sibling of the script that wants it:
--
--   local Words = dofile((arg[0]:gsub("[^/\\]+$", "words.lua")))

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

-- The word tokens of a file, in order, each with the line it sits on and the
-- byte it starts at. The position is what lets a caller go back to the text for
-- something the token stream has dropped: shape.lua reads the dotted name after
-- a `function`, trees.lua reads the `.Symbol` after an `ns`.
return function(text)
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
