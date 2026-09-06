-- The widget model
--
-- Region, and the two constructors every other file builds frames with. This
-- file is loaded first and everything under client/ reads what it leaves on H.

local H = ...

local frames, events = {}, {}

-- Everything the chat and voice stubs record, in one table rather than one
-- local each. Seven separate names would be seven things for 07-chat.lua and
-- 29-social.lua to ask for by name and seven things to keep in step; the table
-- is one. What is in here is written by the stubs further down and read by
-- those two files.
--
--   insertStrict  which spelling of the insert mode this client will take
--   groupSize     how many the party tokens go up to
--   filters       event -> the filters FrameXML's list is holding
--   sent          every SendChatMessage, in order
--   slash         every line handed to the client's own parser
--   classByGuid   what GetPlayerInfoByGUID answers
--   voice         the voice service: its channels, and every call made to it
local chat = {
	insertStrict = nil,
	groupSize = 0,
	filters = {},
	sent = {},
	slash = {},
	classByGuid = {},
	voice = { calls = {}, channels = {}, enabled = true, loggedIn = true, active = nil },
}
local loading = { file = "?" }

-- Handlers the client alone fires.
--
-- A section used to reach a drag by calling grip.scripts.OnDragStart(grip) and
-- then moving the frame itself with SetPoint. That is not a drag. It skips
-- RegisterForDrag, so a grip the client would never deliver to passes; it skips
-- the hit test, so a grip buried under the page passes; and it skips the
-- snippet that does the real move, so both halves of a secure drag go
-- untested. The character sheet shipped with all three wrong and this file said
-- nothing, twice.
--
-- So these nine are wrapped at SetScript and the wrapper refuses a call that
-- did not come from the client's own delivery. The real function is kept beside
-- it and 22-mouse.lua is what reaches it: a section names a point on the screen
-- and the stub works out which frame would get the press, the way the client
-- does. Everything else, OnUpdate and OnEvent and the two hover scripts among
-- them, is stored as it arrives.
local DELIVERED = {
	OnClick = true, PreClick = true, PostClick = true,
	OnDragStart = true, OnDragStop = true, OnReceiveDrag = true,
	OnMouseDown = true, OnMouseUp = true, OnMouseWheel = true,
}

-- How deep inside a delivery we are. A count rather than a flag, because a
-- handler may click another button and that press is still the client's.
local input = { depth = 0 }

-- Which frame was made first. The draw order inside one strata and one level is
-- the order the frames were made in, later on top, and the hit test needs it to
-- break a tie the way the client breaks one.
local serial = 0

local Region = {}
Region.__index = Region

-- Any PascalCase key is a method the client would have. Anything else is data
-- and has to answer nil, or code probing a frame for a region by name finds a
-- function where it expected a texture.
setmetatable(Region, { __index = function(_, key)
	if key:match("^%u") then
		return function() end
	end
	return nil
end })

-- The object type is data the addon branches on rather than a method it calls
-- for effect, so it cannot fall through to the no-op above. Both walks in
-- Skin.lua turn on it: a texture is hidden, a frame is recursed into, and
-- everything else, which is a status bar or an aura button, is left alone.
local TYPES = {
	frame = "Frame", texture = "Texture", fontstring = "FontString",
	statusbar = "StatusBar", button = "Button", font = "Font",
}

-- The kind is lower cased on the way in, because there are two spellings of it
-- and they have to answer GetObjectType the same. This file builds Blizzard's
-- frames with the lower case names TYPES is keyed by; the addon builds its own
-- through CreateFrame, where the client's own spelling is "Button", "Frame",
-- "StatusBar". Left alone, TYPES missed on every frame the addon made and all
-- of them came back as "Frame", so a walk that asks a frame what it is could
-- not see anything this addon had built. That is not a small lie. It is
-- invisible to every test that does not walk the addon's own frames, and it
-- made the walk over the client's game menu unable to find the button we had
-- just put in it.
local function region(kind, parent, name)
	kind = kind:lower()
	serial = serial + 1
	local self = setmetatable({
		kind = kind, parent = parent, name = name, scripts = {}, shown = true,
		serial = serial, handlers = {},
		width = 0, height = 0, scale = 1, ignoreScale = false, frameLevel = 0,
		regions = {}, children = {}, colorWrites = 0,
		-- The slider and status bar fields, present on every region so the
		-- writes below never grow the table. A status bar's value is set on the
		-- enemy bars ticker and the churn gate measures that tick.
		value = 0, valueMin = nil, valueMax = nil, valueStep = nil,
	}, Region)
	if name then
		_G[name] = self
	end
	-- A frame's own textures and font strings answer GetRegions; its child
	-- frames answer GetChildren. Both walks in Skin.lua need the two kept
	-- apart, because one is what gets hidden and the other is what gets
	-- recursed into.
	--
	-- Filed here rather than in a second constructor beside this one, which is
	-- what the two used to be. A region made through that one was in its
	-- parent's list and a region made through this one was not, and the
	-- difference was invisible until a hit test walked the tree: Blizzard's own
	-- minimap is built here with UIParent as its parent, was in nobody's list,
	-- and the pointer could not find it. A frame with a parent is a child of
	-- it, and there was never a second answer to that.
	if parent then
		if kind == "texture" or kind == "fontstring" then
			parent.regions[#parent.regions + 1] = self
		else
			parent.children[#parent.children + 1] = self
		end
	end
	return self
end

local child = region

function Region:GetObjectType() return TYPES[self.kind] or "Frame" end
function Region:GetRegions() return unpack(self.regions) end
function Region:GetChildren() return unpack(self.children) end
function Region:GetName() return self.name end

-- The number a frame carries. Data rather than a call for effect, and it has to
-- be, because a bag button says which slot it is by its own id and which bag it
-- is in by its parent's. Left to the PascalCase no-op above, both answered nil
-- and a click on a bag slot would have landed nowhere while every assertion
-- about it still passed.
function Region:SetID(id) self.id = id end
function Region:GetID() return self.id or 0 end

-- The draw layer is data here, not a no-op, because the gauge is drawn as
-- three textures inside one of Blizzard's bars and which of them is on top is
-- decided by layer and sublevel alone. That ordering used to be decided by
-- frame level between two frames, the client did not keep the order this file
-- wrote, and the target's gauge came out at 28 percent of its own colour. A
-- stub that dropped the layer could not tell the fixed version from the broken
-- one.
function Region:CreateTexture(name, layer, _, sublevel)
	local texture = child("texture", self, name)
	texture.layer, texture.sublevel = layer or "ARTWORK", sublevel or 0
	return texture
end
function Region:SetDrawLayer(layer, sublevel)
	self.layer, self.sublevel = layer, sublevel or 0
end
function Region:GetDrawLayer() return self.layer, self.sublevel end

-- A mask, which is a real object here for one reason: the PascalCase no-op above
-- answers every unwritten method with a function returning nil, so a probe for
-- CreateMaskTexture passes and the call hands back nothing. UI.Clip indexes what
-- it gets back, and a stub that let that stay nil could not tell a client with
-- masks from a client without one.
--
-- Deliberately not put in the parent's regions list, where CreateTexture puts
-- what it makes. Both walks in Skin.lua and the font role report read that list,
-- and a mask is not art anybody hides, recolours or measures: it is the shape
-- another texture is cut to. Registering it there would have every region count
-- in this harness move on the day the gear page rounded its icons.
function Region:CreateMaskTexture(name)
	local mask = region("texture", self, name)
	mask.layer, mask.sublevel = "ARTWORK", 0
	mask.isMask = true
	return mask
end

-- Kept as a list rather than a flag, because a texture may carry more than one
-- and a section that asserts on the shape wants to see which.
function Region:AddMaskTexture(mask)
	self.masks = self.masks or {}
	self.masks[#self.masks + 1] = mask
end

-- The client's colour object, which is what the surviving form of SetGradient
-- takes. Four fields and the two readers, because that is every part of it the
-- addon or the stub below touches, and a table wearing more methods than that
-- would be this file claiming to know a shape it has not read.
function _G.CreateColor(r, g, b, a)
	local color = { r = r, g = g, b = b, a = a or 1 }
	function color:GetRGB() return self.r, self.g, self.b end
	function color:GetRGBA() return self.r, self.g, self.b, self.a end
	return color
end

-- A gradient, recorded rather than dropped on the PascalCase floor.
--
-- Dropping it would have been the usual harmless no-op and it is not, because a
-- wash is nothing but its gradient: the texture under it is flat white, so every
-- pixel a reader sees is the ramp, and a section without this could assert only
-- that some call had been made. A wash running the wrong way along a right hand
-- row draws perfectly and measures perfectly, and the direction read back here
-- is the one thing that tells it from a right one.
--
-- The colours are unpacked into numbers on the way in. What arrives is whatever
-- the caller built, and the assertion worth having is that the fields the client
-- reads are on it rather than that a table turned up.
--
-- Here and not beside SetColorTexture in 02-text.lua, which is where the rest of
-- a texture's colour lives. That file is at its own line ceiling, and this file
-- already owns what a texture is: it makes one, it makes the mask another is cut
-- to, and it is what every other client file builds on.
function Region:SetGradient(orientation, min, max)
	self.gradient = {
		orientation = orientation,
		min = { min.r, min.g, min.b, min.a },
		max = { max.r, max.g, max.b, max.a },
	}
end
function Region:GetGradient() return self.gradient end

-- Where the string was made, as the addon's own file and line.
--
-- A frame records loading.file, which is the TOC file that was being read when
-- it was created, and that answers "?" or "runtime" for everything built after
-- login, which is most of the strings in the addon: a feed row is made the
-- first time a feed has that many rows in it. A font string is the one region
-- whose creation site is worth keeping exactly, because 36-font-roles.lua
-- reports on strings rather than on frames and a report that says "runtime" 200
-- times names nothing anybody can go and fix.
-- Past UI/Text.lua, because every string in the addon is made by the two
-- constructors in that file and stopping at the first addon frame would name
-- the same three lines for all sixteen hundred of them. The site worth
-- reporting is the one that asked for a string, not the one that makes them.
local function madeAt()
	for level = 3, 12 do
		local info = debug.getinfo(level, "Sl")
		if not info or not info.short_src then
			break
		end
		local file = info.short_src:gsub("^.*/src/", ""):gsub("^%./", "")
			:gsub("^src/", "")
		-- A tail call leaves no frame of its own, and UI.Label ends in one, so
		-- the level that would name the caller reads "(tail call)" instead.
		-- Skipped rather than reported: the real site is further up.
		if not file:find("UI/Text%.lua$") and not file:find("tail call") then
			return ("%s:%d"):format(file, info.currentline or 0)
		end
	end
	return "?"
end

function Region:CreateFontString()
	local text = child("fontstring", self)
	text.madeAt = madeAt()
	return text
end

-- What a button draws between mouse down and mouse up. Modelled rather than
-- left to the PascalCase no-op above, for that no-op's usual reason: an addon
-- that never gave a button one and an addon that gave it one look identical to
-- a stub that swallows both, and the difference on screen is whether a click
-- has any answer at all. GetPushedTexture answering nil is also a real client
-- state, so the caller's guard on it has to be reachable from here.
function Region:SetPushedTexture(path)
	local texture = child("texture", self, nil)
	texture.layer, texture.sublevel = "OVERLAY", 0
	texture.texture = path
	self.pushedTexture = texture
end
function Region:GetPushedTexture() return self.pushedTexture end

-- The other two states, for the reason above and one of its own. A button
-- inheriting one of the client's templates arrives wearing them, the addon's
-- own squares take both off, and a getter that answers nil says the same thing
-- for a square that has been stripped and for a square still wearing Blizzard's
-- blue glow. Those are the two states this fixture exists to tell apart.
function Region:SetNormalTexture(path)
	local texture = child("texture", self, nil)
	texture.layer, texture.sublevel = "ARTWORK", 0
	texture.texture = path
	self.normalTexture = texture
end
function Region:GetNormalTexture() return self.normalTexture end

function Region:SetHighlightTexture(path)
	local texture = child("texture", self, nil)
	texture.layer, texture.sublevel = "HIGHLIGHT", 0
	texture.texture = path
	self.highlightTexture = texture
end
function Region:GetHighlightTexture() return self.highlightTexture end

-- How a texture is composited. Data, because the active tint on a square is
-- additive on purpose: laid over the art at ordinary blending it would be a
-- muddy rectangle rather than a glow, and nothing else could tell.
function Region:SetBlendMode(mode) self.blend = mode end
function Region:GetBlendMode() return self.blend end

-- The swipe. Recorded rather than swallowed, because whether a global cooldown
-- draws one is the whole difference between a bar that answers a key press and
-- one where pressing a rage dump changes no pixel on the screen, and a no-op
-- reads the same either way.
function Region:SetCooldown(start, duration)
	self.cdStart, self.cdDuration = start, duration
end

-- Which way the wedge runs. Recorded for the same reason the pair above is: an
-- aura sweep and a cooldown sweep are the same two numbers and opposite
-- pictures, and a square that fills as the buff runs out and one that empties
-- as it runs out are indistinguishable from the numbers alone.
function Region:SetReverse(on) self.cdReverse = on and true or false end
function Region:SetHideCountdownNumbers(on) self.cdNumbers = not on end
function Region:SetDrawEdge(on) self.cdEdge = on and true or false end
function Region:SetDrawBling(on) self.cdBling = on and true or false end
function Region:SetSwipeColor(r, g, b, a)
	self.cdColor = { r, g, b, a }
end
-- The handler as the frame's owner wrote it, past the wrapper the nine names
-- above wear. Both halves of SetScript and both halves of HookScript go through
-- this pair, so a hook on a delivered script chains the real functions and the
-- wrapper stays the only thing a caller can reach.
local function raw(self, name)
	if DELIVERED[name] then
		return self.handlers[name]
	end
	return self.scripts[name]
end

local function write(self, name, fn)
	if not DELIVERED[name] then
		self.scripts[name] = fn
		return
	end
	self.handlers[name] = fn
	if fn == nil then
		self.scripts[name] = nil
		return
	end
	self.scripts[name] = function(...)
		if input.depth == 0 then
			error(("%s on %s was called by hand. It is a handler the client "
				.. "delivers, so drive it through H.mouse and let the stub work "
				.. "out which frame the press lands on.")
				:format(name, self.name or self:GetObjectType()), 2)
		end
		return self.handlers[name](...)
	end
end

function Region:SetScript(name, fn) write(self, name, fn) end
function Region:GetScript(name) return self.scripts[name] end

-- Whether a frame takes the keyboard, and whether a key it took walks on.
-- Recorded rather than swallowed, and with the client's own defaults: the
-- keyboard is on until a frame turns it off, and a key stops at the first
-- frame whose handler did not say to pass it. Auctionator's KeyBinding.lua
-- runs on this client without ever calling EnableKeyboard and its OnKeyDown
-- fires, which is the first default; AceConfigDialog's popup has to say
-- SetPropagateKeyboardInput(true) for every key but Escape, which is the
-- second. 44-hover.lua delivers a press the way the client does, topmost
-- box first, and a box left on the keyboard while another was listening is
-- the box that ate every mouseover key after the first.
function Region:EnableKeyboard(on) self.keyboard = on and true or false end
function Region:IsKeyboardEnabled() return self.keyboard ~= false end
function Region:SetPropagateKeyboardInput(on) self.propagate = on and true or false end
function Region:GetPropagateKeyboardInput() return self.propagate == true end

-- A hook on a script, chained under whatever was there, the way the client
-- chains one.
--
-- Real, rather than the metatable's PascalCase no-op, because that no-op is the
-- whole of ctrl-click marking on a frame this addon did not build.
-- Marking/Marking.lua hooks OnMouseDown and nothing else, so a swallowed call
-- reads exactly like a frame that was hooked, and a party block that answers no
-- marks at all would pass every assertion in the suite.
function Region:HookScript(name, fn)
	local existing = raw(self, name)
	if not existing then
		write(self, name, fn)
		return
	end
	write(self, name, function(...)
		existing(...)
		fn(...)
	end)
end
-- Whether a button answers a press, with the client's own default: a button is
-- enabled until something disables it. Real rather than the metatable's
-- PascalCase no-op, because the no-op made a disabled button indistinguishable
-- from an enabled one, and the whole of "apply is off until a gem is waiting"
-- is that difference. Region:Press below refuses a press on a disabled button
-- the way the client does.
function Region:Enable() self.enabled = true end
function Region:Disable() self.enabled = false end
function Region:IsEnabled() return self.enabled ~= false end

-- Whether a texture is drawn in grey. Recorded rather than swallowed, for the
-- reason the keyboard flags above are: it is the whole of what UI.SlotPaint's
-- `dim` does, three windows pass it, and a no-op here reads exactly like a
-- window that never dimmed anything.
function Region:SetDesaturated(on) self.desaturated = on and true or false end
function Region:GetDesaturated() return self.desaturated == true end

function Region:SetSize(w, h) self.width, self.height = w, h end
function Region:SetWidth(w) self.width = w end
function Region:SetHeight(h) self.height = h end
function Region:GetWidth() return self.width end
function Region:GetHeight() return self.height end

H.input, H.raw = input, raw
H.frames, H.events, H.chat = frames, events, chat
H.loading, H.Region, H.region = loading, Region, region
H.child = child
