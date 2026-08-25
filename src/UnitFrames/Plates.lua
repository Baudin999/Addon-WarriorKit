local ADDON, ns = ...

local Plates = {}
ns.Plates = Plates

--------------------------------------------------------------------------
-- Where the client puts a nameplate
--
-- Bars piling on top of each other when two mobs stand together is not a
-- drawing bug and no amount of care in the widget fixes it. The client decides
-- where a plate goes, and it decides using two things this addon can reach and
-- one it cannot.
--
-- The one it cannot is the world. Plates follow mobs, and mobs stand where they
-- stand.
--
-- The two it can:
--
--   nameplateMotion   0 lets plates overlap freely, 1 makes the driver push
--                     them apart. On 0 there is no avoidance to tune and no
--                     setting below changes anything, which is why this is the
--                     first thing the part takes.
--   the plate's size  the driver spaces plates by how big it thinks a plate is,
--                     and it thinks a plate is Blizzard's nameplate. Ours is
--                     twice the height of that, with a level tag hanging off
--                     the left edge, so two plates the driver has cleanly
--                     separated are two bars that are not.
--
-- SetNamePlateEnemySize tells it the real figure. Where that call is missing,
-- nameplateOverlapV multiplies the height the driver uses instead, which gets
-- the spacing right and leaves the click target alone.
--
-- Sizing the plate does move the click target with it: a taller plate takes the
-- mouse over more of the screen, which is more room to click a mob and more of
-- a camera drag swallowed. That trade is the one `bars camera` and `bars
-- clickthrough` already manage, and it is why this is one setting the player
-- turns off rather than something the part does quietly.
--
-- All three are the player's, borrowed. Turning the setting off puts back what
-- was there, the same way Charge/SoftTarget.lua hands SoftTargetEnemy back.
--------------------------------------------------------------------------

local STACKING = "1"
local FLAT = "0"

local footprintWidth, footprintHeight -- what a bar actually occupies, in UIParent units
local naturalWidth, naturalHeight     -- what a plate measured before we touched it
local sizeApplied, overlapApplied
local pending
local warned

local function Read(cvar)
	if type(GetCVar) ~= "function" then
		return nil
	end
	local ok, value = pcall(GetCVar, cvar)
	return ok and value or nil
end

-- pcalled for the reason SoftTarget pcalls: a CVar the client marks protected
-- refuses in combat, and a refusal is a deferral rather than an error on screen.
local function Write(cvar, value)
	if type(SetCVar) ~= "function" then
		return false
	end
	return (pcall(SetCVar, cvar, value))
end

-- Taken the first time the addon touches a CVar and never again, so turning the
-- setting off puts back what was actually there rather than a guess. Empty is
-- the sentinel for "not remembered yet"; these CVars only ever answer a number
-- as a string. Account scoped, both of them, so the memory is too.
local function Remember(key, cvar)
	if not ns.db or ns.db[key] ~= "" then
		return
	end
	ns.db[key] = Read(cvar) or ""
end

--------------------------------------------------------------------------

-- Measured off the first plate the client puts up, before anything here has
-- written to it. Not saved: a resolution change or another addon moves it, and
-- a remembered figure from last session would be spacing this one.
function Plates.Measure(plate)
	if naturalHeight or not plate then
		return
	end
	local width = ns.Measure(plate, "GetWidth")
	local height = ns.Measure(plate, "GetHeight")
	if width and height and width > 0 and height > 0 then
		naturalWidth, naturalHeight = width, height
		Plates.Apply()
	end
end

-- What one bar occupies, in UIParent's units, handed over by whoever draws it.
-- Comes in as pixels off the grid, so the caller converts; this file does no
-- scale arithmetic of its own.
function Plates.SetFootprint(width, height)
	if footprintWidth == width and footprintHeight == height then
		return false
	end
	footprintWidth, footprintHeight = width, height
	Plates.Apply()
	return true
end

-- Returns whether there is nothing left owing, not whether it wrote. A client
-- with no such call and a plate nobody has measured yet are both settled: the
-- first will never be able to, and the second is retried by Measure and
-- SetFootprint rather than by the combat flush. Reporting either as unfinished
-- leaves pending set for the session and re-runs the whole apply on every
-- combat drop for nothing.
local function ApplySize()
	if not (C_NamePlate and C_NamePlate.SetNamePlateEnemySize) then
		return true
	end
	local width = footprintWidth or naturalWidth
	local height = footprintHeight or naturalHeight
	if not width or not height then
		return true
	end
	local ok = pcall(C_NamePlate.SetNamePlateEnemySize, width, height)
	if ok then
		sizeApplied = true
	end
	return ok
end

local function RestoreSize()
	if not sizeApplied or not (C_NamePlate and C_NamePlate.SetNamePlateEnemySize) then
		return true
	end
	if not naturalWidth or not naturalHeight then
		return true
	end
	local ok = pcall(C_NamePlate.SetNamePlateEnemySize, naturalWidth, naturalHeight)
	if ok then
		sizeApplied = false
	end
	return ok
end

-- Only on the fallback path. Where the size call took, the driver already knows
-- how tall a plate is and multiplying that again would space plates by twice
-- the bar; where it did not, this is the whole of the fix.
local function ApplyOverlap()
	if sizeApplied or not naturalHeight or not footprintHeight then
		return true
	end
	local wanted = footprintHeight / naturalHeight
	if wanted <= 1 then
		return true
	end
	Remember("platesOverlapPrior", "nameplateOverlapV")
	overlapApplied = true
	return Write("nameplateOverlapV", ("%.2f"):format(wanted))
end

local function RestoreOverlap()
	if not overlapApplied then
		return true
	end
	local prior = ns.db.platesOverlapPrior
	if prior == nil or prior == "" then
		overlapApplied = false
		return true
	end
	if Write("nameplateOverlapV", prior) then
		overlapApplied = false
		return true
	end
	return false
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

-- Put the client where the setting says it should be. Every write is allowed to
-- refuse, and a refusal sets pending rather than saying anything: combat is the
-- normal reason and PLAYER_REGEN_ENABLED runs the whole thing again.
function Plates.Apply()
	if not ns.db then
		return
	end

	local done = true
	if ns.db.barsStack and ns.db.bars then
		Remember("platesMotionPrior", "nameplateMotion")
		done = Write("nameplateMotion", STACKING) and done
		done = ApplySize() and done
		done = ApplyOverlap() and done
	else
		done = Plates.Restore() and done
	end

	pending = not done
end

-- Hand all three back. Called when the setting goes off, and at logout by
-- nothing at all: these are the player's CVars and a client that crashes leaves
-- them where we put them, which is why the prior is saved rather than held in a
-- local.
function Plates.Restore()
	local done = RestoreOverlap()
	done = RestoreSize() and done

	local prior = ns.db and ns.db.platesMotionPrior
	if prior and prior ~= "" then
		done = Write("nameplateMotion", prior) and done
	end
	return done
end

function Plates.Flush()
	if pending then
		Plates.Apply()
	end
end

-- Whether the client is actually stacking, which is not the same question as
-- whether the setting is on: the CVar can refuse, and it can be turned off in
-- Blizzard's own interface options behind our back.
function Plates.Stacking()
	return Read("nameplateMotion") == STACKING
end

function Plates.Describe()
	if not ns.db.barsStack then
		return "stacking is the client's own, untouched"
	end
	if not Plates.Stacking() then
		return "asked the client to stack plates and it is still on " .. FLAT
			.. ", so bars can still overlap"
	end
	if sizeApplied then
		return ("stacking, plates sized to the bar at %d by %d"):format(
			footprintWidth or 0, footprintHeight or 0)
	end
	if overlapApplied then
		return "stacking, spaced by nameplateOverlapV because this client has no SetNamePlateEnemySize"
	end
	return "stacking, and nothing has measured a plate yet"
end

-- Said once, because a player who has stacking off in Blizzard's options and
-- this setting on should be told which one is winning rather than left to
-- wonder why the bars still pile up.
function Plates.Warn()
	if warned or not ns.db.barsStack or not ns.db.bars or Plates.Stacking() then
		return
	end
	warned = true
	ns.Print("this client refused to stack nameplates, so bars will still overlap"
		.. " when mobs stand together. Nameplate motion is a Blizzard interface setting too.")
end
