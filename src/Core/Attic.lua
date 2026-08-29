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
-- **Everything held is checked once a second.** Attic.Sweep walks what the room
-- holds and puts back anything whose parent has drifted. Only an explicit
-- SetParent by somebody else can undo a cage, so the sweep almost never has work
-- to do, and it is what turns "no path we thought of can show it" into "nothing
-- stays on the screen for longer than a second". UnitFrames/Blizzard.lua owns
-- the clock.
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
	if not pcall(frame.SetParent, frame, attic) then
		return false
	end
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
	if not pcall(frame.SetParent, frame, was or nil) then
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
-- This is the line that makes the feature hold rather than merely be right at
-- login. A cage survives Show, SetShown, an alpha, a fade and a layout pass, and
-- the one call that undoes it is somebody else's SetParent. Nothing in the
-- client is known to make one on these frames, which is exactly the kind of
-- claim that has been wrong twice, so it is checked instead of believed.
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
