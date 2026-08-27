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
	local self = setmetatable({
		kind = kind, parent = parent, name = name, scripts = {}, shown = true,
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
	return self
end

-- A frame's own textures and font strings answer GetRegions; its child frames
-- answer GetChildren. Both walks in Skin.lua need the two kept apart, because
-- one is what gets hidden and the other is what gets recursed into.
local function child(kind, parent, name)
	local self = region(kind, parent, name)
	if kind == "texture" or kind == "fontstring" then
		parent.regions[#parent.regions + 1] = self
	else
		parent.children[#parent.children + 1] = self
	end
	return self
end

function Region:GetObjectType() return TYPES[self.kind] or "Frame" end
function Region:GetRegions() return unpack(self.regions) end
function Region:GetChildren() return unpack(self.children) end
function Region:GetName() return self.name end

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
function Region:SetScript(name, fn) self.scripts[name] = fn end
function Region:GetScript(name) return self.scripts[name] end
function Region:SetSize(w, h) self.width, self.height = w, h end
function Region:SetWidth(w) self.width = w end
function Region:SetHeight(h) self.height = h end
function Region:GetWidth() return self.width end
function Region:GetHeight() return self.height end

H.frames, H.events, H.chat = frames, events, chat
H.loading, H.Region, H.region = loading, Region, region
H.child = child
