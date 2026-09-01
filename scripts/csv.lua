-- Reading what wago.tools exported.
--
--   local CSV = dofile("scripts/csv.lua")
--
-- Shared by the two bake scripts, which both take Blizzard's own tables as CSV
-- and one of which also takes the community listfile as JSON. Not part of the
-- addon and never loaded by a client: this runs on a laptop, once, when the
-- dungeon list changes.
--
-- Its own file because both bakes read the same exports the same way, and the
-- CSV they read is not quite the format anybody's library assumes: a field may
-- hold commas and doubled quotes, and a table like Map holds whole paragraphs
-- of quoted description with line breaks stripped, so a split on commas takes
-- the wrong number of columns on exactly the rows that matter.

local CSV = {}

function CSV.Read(path)
	local handle = io.open(path, "r")
	if not handle then
		return nil, ("cannot read %s"):format(path)
	end
	local text = handle:read("*a")
	handle:close()
	return text
end

-- One line of CSV, as fields. Quoted fields hold commas and doubled quotes,
-- which is the only thing about the format worth writing code for.
function CSV.Fields(line)
	local out, at = {}, 1
	while at <= #line + 1 do
		local field
		if line:sub(at, at) == '"' then
			local close = at + 1
			while true do
				local stop = line:find('"', close, true)
				if not stop then
					stop = #line
				end
				if line:sub(stop + 1, stop + 1) == '"' then
					close = stop + 2
				else
					field = line:sub(at + 1, stop - 1):gsub('""', '"')
					at = stop + 2
					break
				end
			end
		else
			local stop = line:find(",", at, true) or (#line + 1)
			field = line:sub(at, stop - 1)
			at = stop + 1
		end
		out[#out + 1] = field
	end
	return out
end

-- A whole export, as rows keyed on the column names in its first line.
function CSV.Rows(path)
	local text, why = CSV.Read(path)
	if not text then
		return nil, why
	end
	local head, out = nil, {}
	for line in text:gmatch("[^\r\n]+") do
		local fields = CSV.Fields(line)
		if not head then
			head = fields
		else
			local row = {}
			for index, name in ipairs(head) do
				row[name] = fields[index]
			end
			out[#out + 1] = row
		end
	end
	if not head then
		return nil, ("%s is empty"):format(path)
	end
	return out
end

-- The listfile, as a file id to the path it is filed under. It arrives as one
-- long JSON object of id to name and it is read as pairs rather than parsed,
-- because that is the whole of its shape.
function CSV.Listing(path)
	local text, why = CSV.Read(path)
	if not text then
		return nil, why
	end
	local out, held = {}, 0
	for id, name in text:gmatch('"(%d+)":"(.-)"') do
		out[id] = name:gsub("\\/", "/")
		held = held + 1
	end
	if held == 0 then
		return nil, ("%s named no files"):format(path)
	end
	return out
end

return CSV
