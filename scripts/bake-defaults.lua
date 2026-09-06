-- Reads a saved variables file and writes src/Core/Shipped.lua out of it.
--
-- Driven by ./scripts/bake-defaults.sh, which finds the file. Everything the
-- decision needs is in the addon rather than here: which settings exist, what
-- each one defaults to, and which of them are records the reset keeps. That is
-- why this loads the whole addon under the harness's stub client instead of
-- reading the feature files as text. A list of keys typed out here would be a
-- second registry, sitting a folder away from the first, wrong the day a
-- feature adds a setting.
--
--     lua5.1 scripts/bake-defaults.lua src path/to/WarriorKit.lua [character file]

local ROOT, SOURCE, CHARACTER = ...
assert(ROOT and SOURCE,
	"usage: bake-defaults.lua <addon root> <account saved variables> [character saved variables]")

local here = arg[0]:match("^(.*)[/\\]") or "."

--------------------------------------------------------------------------
-- The addon, as it ships
--
-- The stub client and the load order are the harness's, so a bake and a test
-- run are looking at the same addon. Only ADDON_LOADED is fired: the defaults
-- are all registered by then, and nothing below asks a question that logging
-- in would answer.
--------------------------------------------------------------------------

local function load(path)
	return assert(loadfile(here .. "/harness/" .. path))
end

local H = load("client/init.lua")("WARRIOR", load)
local ns = {}
H.ns, H.carry = ns, {}

-- Every file but the one this writes.
--
-- Skipped rather than loaded, and it is the whole of what makes a bake
-- repeatable. Loaded, the last capture is already merged over the registry by
-- the time the comparison runs, every setting in the file agrees with the
-- install it came from, nothing differs, and the bake writes an empty table
-- that quietly undoes itself. The question being asked is what the features
-- say, not what the last bake said.
local GENERATED = "Core/Shipped.lua"

for line in io.lines(ROOT .. "/WarriorKit.toc") do
	line = line:gsub("\r", ""):gsub("\\", "/")
	if line:match("^[A-Za-z].*%.lua$") and line ~= GENERATED then
		H.loading.file = line
		assert(loadfile(ROOT .. "/" .. line))("WarriorKit", ns)
		H.loading.file = "runtime"
	end
end

-- Over a copy of the list, for the reason the runner's fire does: a frame that
-- unregisters from inside its own handler shifts every frame after it down one.
local listeners = {}
for index, frame in ipairs(H.events.ADDON_LOADED or {}) do
	listeners[index] = frame
end
_G.WarriorKitDB, _G.WarriorKitCharDB = {}, {}
for _, frame in ipairs(listeners) do
	if frame.scripts.OnEvent then
		frame.scripts.OnEvent(frame, "ADDON_LOADED", "WarriorKit")
	end
end

-- ns.db and ns.dbc are the two registries with nothing saved over them and the
-- last capture left out, which is what the features on their own say a fresh
-- screen looks like.
local shipped, shippedChar = ns.db, ns.dbc
assert(type(shipped) == "table" and type(shippedChar) == "table",
	"the addon loaded and wrote no saved variables")
assert(type(ns.Restorable) == "function",
	"Core\\Core.lua exports no Restorable, and this cannot tell a setting from a record")

--------------------------------------------------------------------------
-- The capture
--------------------------------------------------------------------------

-- In an environment of its own, so a saved variables file cannot reach anything
-- real. It is a Lua file written by the client and edited by hand between
-- machines, and it is read as Lua rather than with a pattern for the same
-- reason bake-ui.sh reads one that way.
local chunk = assert(loadfile(SOURCE))
local env = {}
setfenv(chunk, env)
assert(pcall(chunk))

local live = env.WarriorKitDB
assert(type(live) == "table", "no WarriorKitDB in " .. SOURCE)

-- The character half, out of a second file, because the client keeps it under
-- the character rather than under the account. Optional: a capture of the
-- account on its own is the whole of what this did before the character was
-- read at all, and a bake with no character named still writes a file.
local liveChar = {}
if CHARACTER and CHARACTER ~= "" then
	local charChunk = assert(loadfile(CHARACTER))
	local charEnv = {}
	setfenv(charChunk, charEnv)
	assert(pcall(charChunk))
	liveChar = charEnv.WarriorKitCharDB
	assert(type(liveChar) == "table", "no WarriorKitCharDB in " .. CHARACTER)
end

local function Same(held, want)
	if type(held) ~= "table" or type(want) ~= "table" then
		return held == want
	end
	for at, value in pairs(want) do
		if not Same(held[at], value) then
			return false
		end
	end
	for at in pairs(held) do
		if want[at] == nil then
			return false
		end
	end
	return true
end

-- The three settings a capture must not carry, and why.
--
-- Each of them is an override on a plan that lives in code. Buttons\\Which.lua
-- holds where each action bar sits, how many rows it is and whether it is
-- cloned; the saved variables hold only the answers a drag or a stepper gave
-- that differ from it, and every one of those three features reads an absent
-- entry as "the plan". Shipping the overrides would say every bar on a fresh
-- install has been dragged, leave `bars where` printing "(dragged)" against a
-- position nobody has touched, and turn the button that puts the bars back to
-- the plan into a button that puts them back to a capture of somebody else's.
--
-- A bar layout that should ship goes in the plan instead, which is what
-- `/wk bars where` prints it in the shape of.
--
-- The fourth is not an override but a number the client owns. barsDistance is
-- how far out a nameplate goes up, and UnitFrames\\Plates.lua asks the client
-- for its ceiling and writes the setting back down to it at every apply. A
-- capture taken in a session where the CVar would not answer carries whatever
-- was typed against that wall, and shipping it would ship a default the addon
-- corrects on the first frame and a reset that never lands on itself.
local PLANNED = {
	barPoints = true,
	barLook = true,
	barsShown = true,
	barsDistance = true,
}

-- What goes in the file: every setting the capture answers differently from the
-- code, and nothing else.
--
-- Four kinds are stepped over, and each is skipped rather than reported. A
-- record the reset keeps is not a default and never was. An override on the bar
-- plan belongs in the plan, for the reason above. A key the capture holds that
-- no feature registers is a setting this addon dropped, and every saved
-- variables file that has been through an upgrade has some. A setting the
-- capture agrees with is what a bake is trying to produce.
local carried, skipped, dropped = {}, 0, 0
for key, value in pairs(live) do
	if shipped[key] == nil then
		dropped = dropped + 1
	elseif PLANNED[key] or not ns.Restorable(key) then
		skipped = skipped + 1
	elseif type(value) ~= type(shipped[key]) then
		error(("%s holds %q as a %s and its feature registers a %s")
			:format(SOURCE, key, type(value), type(shipped[key])))
	elseif not Same(value, shipped[key]) then
		carried[key] = value
	end
end

--------------------------------------------------------------------------
-- The character half
--
-- Two rules, and between them they answer every key on a character today.
--
-- Only a scalar. Every table under the character is either a note of what
-- happened while you played or a list keyed by something this character has:
-- the cooldown row is keyed by spell id, the mouseover binds name spells, the
-- bar loadout is a list of them, an ad-hoc bar carries the buttons you put on
-- it. Shipping any of those hands a fresh character somebody else's spells, and
-- a rule that says so is worth more than a list naming the eleven of them,
-- because the twelfth arrives with the next feature.
--
-- And not a record, which the scalars need naming for, because a number is a
-- number whether somebody chose it or the addon counted it.
--------------------------------------------------------------------------

local CHAR_RECORD = {
	-- Where the damage breakdown starts counting from and what it has counted.
	-- The second is a table and would go anyway; the first is the clock reading
	-- it was reset at, which means nothing on another character.
	breakdownSince = true,

	-- Experience earned, the level it was earned at, and the seconds played
	-- behind the progress bar. All three are the meter itself.
	progressEarned = true,
	progressLevel = true,
	progressSeconds = true,

	-- Whether the bar loadout has already put its spells on this character
	-- once. A latch the feature sets on itself, and a fresh character has to
	-- come up with it false or the seeding never runs.
	barsSpellsSeeded = true,
	loadoutsSeeded = true,

	-- What the client's own soft targeting CVar held before the addon wrote to
	-- it, and the stamp on the last action bar backup. Both are notes of what
	-- to put back, the same kind as the nameplate CVars on the account.
	softPrior = true,
	layoutStamp = true,

	-- How many times this character has respecced and when it was last said out
	-- loud. A count of what happened, not a number anybody chose.
	respecCount = true,
	respecQuoteAt = true,
}

local carriedChar, skippedChar = {}, 0
for key, value in pairs(liveChar) do
	if shippedChar[key] == nil or type(value) == "table" or CHAR_RECORD[key] then
		skippedChar = skippedChar + 1
	elseif type(value) ~= type(shippedChar[key]) then
		error(("%s holds %q as a %s and its feature registers a %s")
			:format(CHARACTER, key, type(value), type(shippedChar[key])))
	elseif value ~= shippedChar[key] then
		carriedChar[key] = value
	end
end

--------------------------------------------------------------------------
-- Writing it out
--
-- Deterministic on purpose, the way bake-ui.sh is: keys sorted, so re-baking an
-- unchanged screen produces a byte identical file and the diff stays readable.
--------------------------------------------------------------------------

local KEYWORDS = {
	["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
	["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
	["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
	["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true,
	["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
	["while"] = true,
}

local function order(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		return ta < tb
	end
	if ta == "number" or ta == "string" then
		return a < b
	end
	return tostring(a) < tostring(b)
end

local function name(key)
	if type(key) == "string" and not KEYWORDS[key]
		and key:match("^[A-Za-z_][A-Za-z0-9_]*$") then
		return key
	end
	if type(key) == "number" then
		return ("[%.14g]"):format(key)
	end
	return ("[%q]"):format(tostring(key))
end

local serialize

-- An anchor comes back on one line, because five fields wrapped over five lines
-- is a screen of file for a window nobody is reading about. Everything else
-- wraps, because a bar's record is read.
local function flat(value)
	if #value == 0 then
		return nil
	end
	local out = {}
	for index = 1, #value do
		local held = value[index]
		if type(held) == "table" then
			return nil
		end
		out[index] = serialize(held, "")
	end
	return "{ " .. table.concat(out, ", ") .. " }"
end

function serialize(value, indent)
	local kind = type(value)
	if kind == "string" then
		return ("%q"):format(value)
	elseif kind == "number" then
		return ("%.14g"):format(value)
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind ~= "table" then
		error("a setting cannot hold a " .. kind)
	end

	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	if #keys == 0 then
		return "{}"
	end
	if #keys == #value then
		local line = flat(value)
		if line then
			return line
		end
	end
	table.sort(keys, order)

	local inner = indent .. "\t"
	local out = { "{" }
	for _, key in ipairs(keys) do
		out[#out + 1] = ("%s%s = %s,")
			:format(inner, name(key), serialize(value[key], inner))
	end
	out[#out + 1] = indent .. "}"
	return table.concat(out, "\n")
end

local function sorted(held)
	local keys = {}
	for key in pairs(held) do
		keys[#keys + 1] = key
	end
	table.sort(keys, order)
	return keys
end

local keys, charKeys = sorted(carried), sorted(carriedChar)

local target = ROOT .. "/Core/Shipped.lua"
local file = assert(io.open(target, "w"))
file:write("local ADDON, ns = ...\n\n")
file:write("-- Generated by ./scripts/bake-defaults.sh. Do not hand edit: set the addon up\n")
file:write("-- in game the way it should ship, /reload so the client writes its saved\n")
file:write("-- variables, then run ./scripts/bake-defaults.sh to rewrite this file.\n")
file:write("--\n")
file:write("-- One entry per setting that screen answers differently from the feature that\n")
file:write("-- owns it, the account's in the first table and the character's in the second.\n")
file:write("-- Core\\Core.lua merges them over the two registries at load and checks every\n")
file:write("-- key against them; the header there says why this is a capture rather than an\n")
file:write("-- edited literal per setting.\n")

local function block(field, list, held)
	file:write("\n")
	if #list == 0 then
		file:write(("%s = {}\n"):format(field))
		return
	end
	file:write(("%s = {\n"):format(field))
	for _, key in ipairs(list) do
		file:write(("\t%s = %s,\n"):format(name(key), serialize(held[key], "\t")))
	end
	file:write("}\n")
end

block("ns.Shipped", keys, carried)
block("ns.ShippedChar", charKeys, carriedChar)
file:close()

io.write(("baked %d account and %d character settings into %s"
	.. " (%d records kept, %d retired keys ignored, %d character keys stepped over)\n")
	:format(#keys, #charKeys, target, skipped, dropped, skippedChar))
