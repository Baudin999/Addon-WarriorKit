-- The restricted environment
--
-- A secure snippet is the one part of this addon that reading cannot check.
-- It runs inside the client's restricted Lua, it is the only thing allowed to
-- move a protected frame in a fight, and until this file existed the harness
-- treated it as a string it kept for a section to read back. Two bugs walked
-- straight through that. UI/Placeable.lua's first drag called StartMoving from
-- a snippet, which does not exist in there, and every drag on the character
-- sheet ended in "attempt to call a nil value" out of RestrictedExecution. The
-- section then moved the frame itself with SetPoint and called that a drag, so
-- the harness had certified a mechanism neither half of which had run.
--
-- So the snippets run here. Not as ordinary Lua, which is what the state driver
-- stub in 05-quests.lua used to do and is a different lie: ordinary Lua reaches
-- _G, reaches every method on the frame, and reaches the PascalCase no-op in
-- 01-widgets.lua that answers any call at all. A snippet that ran under that
-- would swallow the StartMoving bug in silence.
--
-- What runs instead is the body compiled with loadstring and set to an
-- environment carrying two things and nothing else: the small library the
-- client puts in a managed environment, and frame handles. A handle is not the
-- frame. It answers the methods the restricted environment carries, it refuses
-- everything else by name, and the frames it hands back are handles in their
-- turn, so a snippet cannot climb out through GetParent into the real widget.
--
-- **What this proves and what it does not.** It proves what the snippet does:
-- which attributes it reads, which frames it walks, and what it leaves behind.
-- It proves a snippet reaching for a call the restricted environment does not
-- have, which is the bug above and the reason the file exists. It does not
-- prove the client's own parser accepts the body, and it cannot: the taint
-- rules and the bytecode filter are the client's, and nothing outside the game
-- carries them. Every caller in the addon still probes for the template and
-- falls back, and CanPage and CanRelease still report which path came up.
--
-- The environment is kept per handler frame and lives as long as the frame,
-- which is the client's own arrangement and is load bearing: Charge/Icon.lua
-- calls Execute once to put `button` in scope and then reads that name from a
-- state snippet that runs minutes later.

local H = ...

local Region = H.Region

--------------------------------------------------------------------------
-- Handles
--------------------------------------------------------------------------

-- The methods a frame handle carries, forwarded to the frame underneath.
--
-- This is the subset of the restricted environment's widget API that this
-- harness models. It is not the whole of what the client offers, and the two
-- lists below are the difference: KNOWN names calls the restricted environment
-- really has and this stub does not model, so a snippet that reaches one is
-- told the stub is short rather than told the client is. Anything in neither
-- list is the StartMoving case and is told so.
local CARRIED = {
	GetName = true, GetObjectType = true, GetID = true,
	GetAttribute = true, SetAttribute = true,
	GetFrameRef = true, SetFrameRef = true,
	Show = true, Hide = true, IsShown = true, IsVisible = true,
	GetParent = true,
	SetPoint = true, ClearAllPoints = true, GetPoint = true,
	GetNumPoints = true, SetAllPoints = true,
	GetWidth = true, GetHeight = true, SetWidth = true, SetHeight = true,
	GetScale = true, SetScale = true, GetAlpha = true, SetAlpha = true,
	GetEffectiveScale = true,
	GetFrameLevel = true, SetFrameLevel = true,
	GetFrameStrata = true, SetFrameStrata = true,
	Raise = true, Lower = true,
	GetLeft = true, GetRight = true, GetTop = true, GetBottom = true,
	GetCenter = true,
	ClearBindings = true, SetBindingClick = true,
}

-- Calls the restricted environment carries that nothing here models. Named
-- rather than left to fall through, because "the stub is short" and "the client
-- refuses this" are opposite answers and a snippet author has to be able to
-- tell them apart.
local KNOWN = {
	Run = true, RunFor = true, CallMethod = true, ChildUpdate = true,
	RegisterAutoHide = true, GetChildren = true, GetNumChildren = true,
	SetBindingSpell = true, SetBindingItem = true, SetBindingMacro = true,
	SetBinding = true, ClearBinding = true, IsProtected = true,
	SetParent = true, IsUnderMouse = true,
}

-- Methods whose answer is a frame, and which therefore have to answer a handle.
-- A snippet given the real widget could call anything on it and the whole of
-- this file would be decoration.
local ANSWERS_FRAME = { GetFrameRef = true, GetParent = true }

-- Both directions of the same pairing. Weak keys, so a frame a section drops
-- takes its handle with it.
local frameOf = setmetatable({}, { __mode = "k" })
local handleOf = setmetatable({}, { __mode = "k" })

local methods = {}

local function handle(frame)
	if frame == nil or type(frame) ~= "table" then
		return frame
	end
	local given = handleOf[frame]
	if given then
		return given
	end
	given = setmetatable({}, {
		__index = function(_, key)
			if CARRIED[key] then
				return methods[key]
			end
			if KNOWN[key] then
				error(("the restricted environment has %s and this stub does not model it")
					:format(tostring(key)), 3)
			end
			error(("the restricted environment has no %s"):format(tostring(key)), 3)
		end,
		__newindex = function()
			error("a snippet may not write a field on a frame handle", 2)
		end,
	})
	frameOf[given] = frame
	handleOf[frame] = given
	return given
end

-- One forwarder per name in CARRIED, built once.
--
-- Handles go in as handles and come back as handles. A snippet holds nothing
-- else, so SetPoint against a reference it was given has to take one, and
-- GetParent has to answer one.
local function forward(name)
	return function(given, ...)
		local frame = frameOf[given]
		if not frame then
			error(("%s was called on something that is not a frame handle")
				:format(name), 2)
		end
		local count = select("#", ...)
		local args = { ... }
		for index = 1, count do
			local arg = args[index]
			if type(arg) == "table" and frameOf[arg] then
				args[index] = frameOf[arg]
			end
		end
		if ANSWERS_FRAME[name] then
			return handle(frame[name](frame, unpack(args, 1, count)))
		end
		return frame[name](frame, unpack(args, 1, count))
	end
end

for name in pairs(CARRIED) do
	methods[name] = forward(name)
end

-- The one call in CARRIED that is not a plain forward. The client's own
-- SetBindingClick takes a handle where the Lua call takes a name, and the
-- override layer 05-quests.lua models is keyed by name, so this is where the
-- two meet. `priority` is the first argument and is the client's; it is read
-- and dropped, because the stub has one binding layer rather than two.
methods.SetBindingClick = function(given, _, key, button, suffix)
	local frame = frameOf[given]
	if not frame then
		error("SetBindingClick was called on something that is not a frame handle", 2)
	end
	local target = frameOf[button] or button
	local name = type(target) == "table" and target:GetName() or target
	if type(name) ~= "string" then
		error("SetBindingClick was given a button with no name", 2)
	end
	return _G.SetOverrideBindingClick(frame, true, key, name, suffix or "LeftButton")
end

methods.ClearBindings = function(given)
	local frame = frameOf[given]
	if not frame then
		error("ClearBindings was called on something that is not a frame handle", 2)
	end
	return _G.ClearOverrideBindings(frame)
end

--------------------------------------------------------------------------
-- The environment
--------------------------------------------------------------------------

-- What a managed environment carries besides the handles.
--
-- Short on purpose. The client's own list is longer, and a snippet in this
-- addon uses none of the rest: what is here is what the six snippets under src/
-- actually reach for plus the two string calls anybody writing a seventh would
-- reach for first. A name that is missing errors at the point of the call with
-- the name in it, which is the same answer the client gives and is the failure
-- this whole file exists to make reachable.
--
-- No _G, no loadstring, no pcall, no CreateFrame, and no debug. Those are the
-- doors the restricted environment closes, and a sandbox that left one open
-- would let a snippet do from here what it cannot do in the game.
local LIBRARY = {
	type = type, tonumber = tonumber, tostring = tostring,
	select = select, unpack = unpack, next = next,
	pairs = pairs, ipairs = ipairs, error = error, assert = assert,
	format = string.format, strsub = string.sub, strlower = string.lower,
	strupper = string.upper, strfind = string.find, strmatch = string.match,
	gsub = string.gsub, strlen = string.len, strrep = string.rep,
	tinsert = table.insert, tremove = table.remove, wipe = function(t)
		for key in pairs(t) do t[key] = nil end
		return t
	end,
	floor = math.floor, ceil = math.ceil, abs = math.abs,
	min = math.min, max = math.max,
	math = { floor = math.floor, ceil = math.ceil, abs = math.abs,
		min = math.min, max = math.max, huge = math.huge },
}

-- One environment per handler frame, kept for as long as the frame is. The
-- client keeps a managed environment the same way and Charge/Icon.lua depends
-- on it: Execute puts `button` in scope once and a state snippet reads that
-- name minutes later.
local environments = setmetatable({}, { __mode = "k" })

local function environment(frame)
	local env = environments[frame]
	if env then
		return env
	end
	env = setmetatable({}, { __index = LIBRARY })
	env.self = handle(frame)
	env.owner = env.self
	environments[frame] = env
	return env
end

-- Whether the frame carries a secure handler at all.
--
-- The gate rather than a courtesy. An addon that writes _onclick on a frame
-- built from no template has written a snippet nothing will ever run, which
-- draws and hovers exactly like one that works, and is a bug this harness could
-- not see while every attribute was only a value in a table.
local function handler(frame)
	return type(frame.template) == "string"
		and frame.template:find("SecureHandler", 1, true) ~= nil
end

-- Compiled bodies, keyed by the string. The state driver runs the same body on
-- every stance change and Placeable's move snippet runs once a frame for the
-- length of a drag; compiling each time would make the harness measure the
-- compiler.
local compiled = {}

-- Run one body against one frame.
--
-- `named` is what the client puts in scope for that kind of snippet: `name` and
-- `value` for an attribute change, `button` and `down` for a click, `stateid`
-- and `newstate` for a state driver. They arrive as globals in the environment,
-- which is how every snippet in this addon reads them, and as varargs as well,
-- because the client passes both and a snippet written either way should run.
--
-- `as` swaps the handle bound to `self`. WrapScript is the caller that needs it:
-- a wrapped OnClick runs with the wrapped button as self and the header's
-- environment underneath.
local function run(frame, body, named, as)
	local chunk = compiled[body]
	if not chunk then
		chunk = assert(loadstring(body, "snippet"))
		compiled[body] = chunk
	end
	local env = environment(frame)
	local was = env.self
	if as then
		env.self = handle(as)
	end
	for index = 1, #named, 2 do
		env[named[index]] = named[index + 1]
	end
	setfenv(chunk, env)
	local ok, err = pcall(chunk, named[2], named[4])
	env.self = was
	if not ok then
		error(("snippet on %s: %s")
			:format(frame:GetName() or frame.template or "a frame", tostring(err)), 0)
	end
end

--------------------------------------------------------------------------
-- Where the client runs them
--------------------------------------------------------------------------

-- An attribute write, which is the whole of a secure drag. 02-text.lua calls
-- this after the value has landed and only when it changed, which is the
-- client's own rule and the reason UI/Placeable.lua counts its moves.
local function attribute(frame, name, value)
	if not handler(frame) then
		return false
	end
	local body = frame:GetAttribute("_onattributechanged")
	if type(body) ~= "string" then
		return false
	end
	run(frame, body, { "name", name, "value", value })
	return true
end

-- A press on a button built from SecureHandlerClickTemplate. 14-secure.lua
-- calls this where the template's own OnClick sits, which is after PreClick and
-- after the client's secure half, so a snippet and a macro on one button run in
-- the order the client runs them.
local function click(frame, button, down)
	if not handler(frame) then
		return false
	end
	local body = frame:GetAttribute("_onclick")
	if type(body) ~= "string" then
		return false
	end
	run(frame, body, { "button", button, "down", down })
	return true
end

-- The two halves of a wrapped script, which is the other way a snippet reaches
-- a click. The header owns the environment and the wrapped frame is self, which
-- is what lets AdHoc/Bars.lua's close snippet read the bar off GetParent.
local function wrapped(frame, script, half, button, down)
	local wrap = frame.wraps and frame.wraps[script]
	local body = wrap and wrap[half]
	if type(body) ~= "string" or body == "" then
		return false
	end
	run(wrap.header, body, { "button", button, "down", down }, frame)
	return true
end

-- A state driver delivering a transition, which 05-quests.lua used to run as
-- ordinary Lua.
local function state(frame, stateid, newstate)
	local body = frame:GetAttribute("_onstate-" .. stateid)
	if type(body) ~= "string" then
		return false
	end
	run(frame, body, { "stateid", stateid, "newstate", newstate })
	return true
end

-- Execute, which is how an addon seeds a managed environment before any of the
-- snippets above runs.
--
-- Real rather than the PascalCase no-op in 01-widgets.lua, and it refuses a
-- frame with no secure handler on it. Charge/Icon.lua probes for this method
-- before it uses one, and the no-op answered that probe on every frame in the
-- addon, so the probe was passing on clients that would have failed it.
function Region:Execute(body)
	if not handler(self) then
		error(("Execute was called on %s, which carries no secure handler")
			:format(self:GetName() or self.kind), 2)
	end
	run(self, body, {})
end

H.snippet = { Attribute = attribute, Click = click, Wrapped = wrapped,
	State = state, Run = run, Handle = handle, Frame = frameOf,
	Environment = environment, Handler = handler }
