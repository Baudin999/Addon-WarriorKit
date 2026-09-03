local ADDON, ns = ...

local Attic = {}
ns.Attic = Attic

--------------------------------------------------------------------------
-- Where a Blizzard frame goes when this addon draws it instead
--
-- One frame, hidden at birth, that nothing can ever show. Every frame this
-- addon replaces is re-parented into it. A frame whose parent is hidden is not
-- drawn, whatever anybody calls on the frame itself, because visibility in this
-- client is a property of the parent chain rather than of a field on the frame.
--
-- That is the whole point, and it is a different guarantee from the one
-- ns.Strip makes.
--
-- ns.Strip puts a region's own Hide where its Show was, so the client's update
-- code calling Show cannot put it back. It is the right tool for a texture and
-- it has one hole that has now cost two bugs: `SetShown` is resolved in C and
-- never reads the Lua field, so every FrameXML path written as
-- `frame:SetShown(true)` walks straight past it. UnitFrames/Blizzard.lua already
-- knew this and had a hook on the raid manager for exactly that reason, which is
-- a patch on one frame for a hole every frame has. `FCF_` uses SetShown on the
-- chat window, which is why `/logout` put the client's chat back on the screen,
-- and the cast bar mixin uses it on the target's bar, which is why there were
-- two cast bars for one cast with the switch on.
--
-- So the frames go somewhere the client cannot reach rather than being argued
-- with one method at a time. Show, SetShown, SetAlpha, a fade, an animation and
-- a layout pass all lose against a hidden parent, and none of them has to be
-- predicted in advance. That is what makes this the mechanism and ns.Strip the
-- second layer: both are applied, and only one of them can be defeated.
--
-- **Art does not come here.** A texture or a font string is a region of the
-- frame it was created on, and moving one would take it out of that frame's draw
-- order rather than off the screen. The three parts that strip a Blizzard region
-- one texture at a time, the nameplates, the bar art and the unit frame skin,
-- keep ns.Strip and are unaffected by this file.
--
-- **A secure action button does not come here either.** Buttons/Blizzard.lua
-- hides those with `statehidden` and Hide, and says in its own header why: the
-- client's bar controller calls methods on them from a call stack that goes on
-- to perform protected actions, and an addon's frame in that chain is a taint.
-- Nothing in this file is reached from that path.
--
-- **The one call that undoes a cage is hooked.** Only an explicit SetParent by
-- somebody else can take a frame out of this room, so every frame that comes in
-- gets a hook on that call and goes straight back on the same frame it was
-- moved. Show is hooked beside it, because that is the other handle anybody
-- reaches for and a Show on a caged frame is a frame whose own flag disagrees
-- with the picture.
--
-- **And everything held is swept anyway.** Attic.Sweep walks what the room holds
-- and puts back anything whose parent has drifted. It is the answer to the
-- client this addon has not met: a frame that would not take a hook, a build
-- where hooksecurefunc is not there at all. The hook makes it almost always find
-- nothing, which is what lets UnitFrames/Blizzard.lua run the clock at a fifth
-- of the rate it used to.
--------------------------------------------------------------------------

-- What this room will not take. Everything else the client makes is a frame of
-- some kind, and listing the two that are not is shorter and ages better than
-- listing the twenty that are: a client that grows a new frame type gets caged
-- correctly, and a client that grows a new art type is the failure this list
-- would have to be edited for anyway.
local ART = {
	Texture = true, FontString = true, Line = true, MaskTexture = true,
	Animation = true, AnimationGroup = true,
}

local ROOM = "WarriorKitAttic"

-- The room, once there has been something to put in it. nil is "not asked yet",
-- false is "this client would not make one", and the frame is the frame.
local room

-- What the attic holds, and the parent each frame had before it came here, so
-- the switch that turns off hands back exactly what it took. False rather than
-- nil for a frame that had no parent at all, because nil is the key's absence
-- and that is the question Attic.Held answers.
local home = {}
local held = 0

local function Room()
	if room ~= nil then
		return room or nil
	end
	room = false
	if type(CreateFrame) ~= "function" then
		return nil
	end
	local ok, made = pcall(CreateFrame, "Frame", ROOM, UIParent)
	if not ok or type(made) ~= "table" then
		return nil
	end
	made:Hide()
	-- Both, and the second is the one that matters. A room somebody shows is a
	-- room with nothing in it, and the call that would do it by accident is the
	-- same SetShown this file exists because of.
	made.Show = made.Hide
	made.SetShown = made.Hide
	room = made
	return made
end

-- The room itself, for the harness and for `/wk hide probe`. Handed out rather
-- than answered about, because what is being checked is which frame a caged
-- frame's parent is, and a boolean this file computed is a boolean this file
-- could compute wrongly and still agree with itself.
function Attic.Frame()
	return Room()
end

-- Whether this client will cage anything at all. Read by the probe, because a
-- client with no CreateFrame degrades to ns.Strip alone and that is worth
-- seeing as a fact rather than as a switch that did not work.
function Attic.Available()
	return Room() ~= nil
end

-- Whether this is a thing the room can take. ns.Measure rather than a direct
-- call, because a restricted region raises on the question rather than
-- answering it, and an unknown answer is "leave it alone".
function Attic.Cageable(frame)
	if type(frame) ~= "table" or type(frame.SetParent) ~= "function"
		or type(frame.GetParent) ~= "function" then
		return false
	end
	local kind = ns.Measure(frame, "GetObjectType")
	return kind ~= nil and not ART[kind]
end

function Attic.Held(frame)
	return home[frame] ~= nil
end

-- This file's own re-parents, which the hooks below must not answer for.
--
-- Attic.Give hands a frame back before it clears the record, so without this the
-- hook would read the release as a foreign SetParent and put the frame the
-- switch just turned off straight back in the room.
local moving = false

local function Reparent(frame, parent)
	moving = true
	local ok = pcall(frame.SetParent, frame, parent)
	moving = false
	return ok
end

-- What the sweep was, on the frame it happens rather than a second later.
--
-- Written to do exactly what Attic.Vanish does, because Vanish is what put the
-- frame here: the parent back, and the frame hidden if the flag came on. A frame
-- this file has already handed back is left alone, which is what the home lookup
-- says.
local function Recage(frame)
	if moving or home[frame] == nil then
		return
	end
	Attic.Take(frame)
	if frame:IsShown() and not ns.Blocked(frame) then
		frame:Hide()
	end
end

-- Both hooks on one frame, once, on the way in.
--
-- hooksecurefunc rather than a replacement of the method, so the client's own
-- call still runs and nothing downstream of it changes. Probed and pcalled: it
-- is a global this addon does not own and a frame may refuse the write, and
-- either way the sweep is still there.
--
-- SetParent is the one that holds. Show is the second handle and it is worth
-- less than it looks: ns.Strip has usually already put the frame's Hide in that
-- field, and SetShown is resolved in C and reads no Lua field at all. It is here
-- for the frame a combat lockdown refused the strip on, which is the one caged
-- frame whose Show is still its own.
local function Watch(frame)
	if frame.wkCaged or type(_G.hooksecurefunc) ~= "function" then
		return
	end
	frame.wkCaged = true
	pcall(_G.hooksecurefunc, frame, "SetParent", Recage)
	pcall(_G.hooksecurefunc, frame, "Show", Recage)
end

function Attic.Count()
	return held
end

-- One frame into the room. True when there is nothing left to do, which
-- includes a client that cannot cage and an object that is not a frame: neither
-- is a refusal and neither gets better by being retried. False is combat
-- refusing a protected frame, and that is the caller's signal to come back at
-- PLAYER_REGEN_ENABLED.
--
-- The parent is compared on every call rather than trusted, because a frame the
-- client re-parented back is a frame on the screen and the record here would say
-- otherwise.
function Attic.Take(frame)
	local attic = Room()
	if not attic or not Attic.Cageable(frame) then
		return true
	end
	if frame:GetParent() == attic then
		return true
	end
	if ns.Blocked(frame) then
		return false
	end
	local was = home[frame]
	if was == nil then
		was = frame:GetParent() or false
	end
	if not Reparent(frame, attic) then
		return false
	end
	Watch(frame)
	if home[frame] == nil then
		home[frame] = was
		held = held + 1
	end
	return true
end

-- And back where it was found. A frame this file never took is left alone, so
-- turning a switch off gives back exactly what turning it on cost.
function Attic.Give(frame)
	local was = home[frame]
	if was == nil then
		return true
	end
	if ns.Blocked(frame) then
		return false
	end
	if not Reparent(frame, was or nil) then
		return false
	end
	home[frame] = nil
	held = held - 1
	return true
end

-- One frame off the screen, by both handles.
--
-- The cage is what holds. ns.Strip is kept over it for the frame this client
-- will not let us cage and for the client that has no attic at all, and the Hide
-- is what makes IsShown agree with what is on the screen, which is the question
-- every probe and every test in this addon asks.
function Attic.Vanish(frame)
	local stripped = ns.Strip(frame)
	local caged = Attic.Take(frame)
	if frame and type(frame.IsShown) == "function" and frame:IsShown()
		and not ns.Blocked(frame) then
		frame:Hide()
	end
	return stripped and caged
end

-- And the reverse, in the reverse order: the parent first, so the Show that
-- ns.Unstrip ends with lands on a frame that is already back where it belongs.
function Attic.Return(frame)
	local given = Attic.Give(frame)
	return ns.Unstrip(frame) and given
end

-- Everything the room holds, checked against what is actually on the screen.
--
-- The hook above answers the same call on the frame it happens, so this walk now
-- runs behind it rather than instead of it, and it almost never finds anything.
-- It stays because the hook is the thing that could be missing: a build with no
-- hooksecurefunc, a frame that refused the write, a frame taken before the
-- global existed. Believing the hook is the shape of claim this file has already
-- been wrong about twice.
--
-- Cheap by construction: one comparison per frame held, and a write only where
-- the comparison failed.
function Attic.Sweep()
	local attic = Room()
	if not attic then
		return true
	end
	local complete = true
	for frame in pairs(home) do
		if frame:GetParent() ~= attic and not Attic.Take(frame) then
			complete = false
		end
	end
	return complete
end
