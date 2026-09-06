local ADDON, ns = ...

local Skin = {}
ns.FrameSkin = Skin

-- The player frame, the target frame and target of target, drawn by this
-- addon: flat fills, one pixel edges, a square portrait, and the class colour
-- on the gauge and on the frame around it.
--
-- They are our own frames. For a long time they were Blizzard's three frames
-- wearing this look, because a frame drawn from scratch would have to earn
-- back the click, the menu and the cast bar, and would fight the Edit Mode
-- layout the addon carried for a client that turned out not to have Edit Mode
-- at all. That left three frames nobody could move. UnitFrames/Group.lua had
-- already shown the shape of the answer: a secure unit button of ours carries
-- the click and the menu through two attributes, the client's unit watch puts
-- it up and down with the unit, and UI.Placeable drags it the way every other
-- piece of this HUD is dragged. Blizzard's own three go to the attic through
-- the switch in Core/BlizzHide.lua, like every other frame this addon
-- replaces.
--
-- Three files behind this one, each with one subject:
--
--   UnitFrames/Block.lua is the geometry: the square, the two bars, the four
--   strings, the badges, and where the three blocks hang off each other.
--
--   UnitFrames/Paint.lua is the tick: given a block that already exists, read
--   the unit and write what changed.
--
--   UnitFrames/Auras.lua is the two aura rows on each of the first two.
--
-- What is left is this file, and it is the part rather than any of the three.
-- Building the three frames, whether each one is wanted, showing and hiding
-- them in the order that survives combat, placing them, and what the slash
-- commands and the panel are told. It owns the entry list, so it is the only
-- file that can answer which block a link or a perch hangs off, and it hands
-- that answer to Block rather than letting Block go looking.
--
-- It also owns when a block is drawn. Unit events mark a block and the pass
-- draws what is marked; see the note over WATCHED for which and why they are
-- safe to trust on this client.

local Block = ns.FrameBlock
local Paint = ns.FramePaint

-- How often the three blocks are looked at, and how often they are read off the
-- client from the top.
--
-- The client already says when a unit's health, power, auras or connection
-- move, so a frame is marked by Watched below and this pass draws what is
-- marked. What it costs when nothing has happened is the walk.
--
-- The reading behind it is what no event on the list carries: an incoming
-- heal, a mob somebody else has tagged, and target of target, which has no
-- event stream of its own on this client beyond UNIT_TARGET on its host.
local REFRESH = 0.2
local VERIFY = 1

-- Target of target against the other two. It is a glance, not a frame you
-- read, so it is the one that has to stay out of the way.
local TOT_SCALE = 0.62

-- The client's unit watch, taken at load. It is the one mechanism that can put
-- a secure frame up and take it down in a fight: RegisterUnitWatch hands the
-- frame to a secure state driver that shows it while its unit exists, and
-- nothing an addon calls in combat can do that. Blizzard_RestrictedAddOnEnvironment
-- /SecureStateDriver.lua declares both on this client. A client without them
-- falls to Reveal below, which shows and hides out of combat only.
local RegisterUnitWatch = _G.RegisterUnitWatch
local UnregisterUnitWatch = _G.UnregisterUnitWatch

--------------------------------------------------------------------------
-- The three frames
--
-- key      the setting, the slash word and the panel line
-- unit     the token the button targets and the block reads
-- mirror   the gauge sits left of the portrait rather than right of it
-- scale    this frame's share of the height and width settings
-- badges   which state icons the block carries, out of Block's three
-- global   the anchor's name, which is the rectangle you drag and the one
--          every measurement in Block is taken in. Named so a block that
--          lands wrong can be measured from a macro or a harness
-- button   the secure unit button's name, for the same reason
-- title    what the frame is called while it is being placed
-- point    the setting its own corner is written to, for the two you drag
-- watch    the button goes up and down with the unit rather than staying up
-- beside   the key of the frame this one hangs off sideways, gauge edge to
--          gauge edge, while the link is on
-- under    the key of the frame this one is parked beneath
--------------------------------------------------------------------------

local SPECS = {
	{
		key = "player", unit = "player", mirror = false, scale = 1,
		badges = { "state", "pvp" },
		global = "WarriorKitPlayerFrame", button = "WarriorKitPlayerButton",
		title = "WarriorKit player", point = "skinPlayerPoint",
	},
	{
		-- Mirrored, because the target frame sits on the right of the screen
		-- and its portrait has always been on the outside edge.
		key = "target", unit = "target", mirror = true, scale = 1,
		badges = { "marker", "pvp" }, beside = "player", watch = true,
		global = "WarriorKitTargetFrame", button = "WarriorKitTargetButton",
		title = "WarriorKit target", point = "skinTargetPoint",
	},
	{
		key = "tot", unit = "targettarget", mirror = false, scale = TOT_SCALE,
		badges = { "marker" }, under = "target", watch = true,
		global = "WarriorKitTargetOfTargetFrame",
		button = "WarriorKitTargetOfTargetButton",
	},
}

local entries = {}
local watchers = {}
local pending = false
local missing = false

--------------------------------------------------------------------------
-- What the client says has moved
--
-- The unit events Blizzard's own three frames register on this client, and
-- every one of them is something a block draws. UnitFrame.lua takes
-- UNIT_HEALTH, UNIT_MAXHEALTH, UNIT_POWER_UPDATE, UNIT_MAXPOWER,
-- UNIT_NAME_UPDATE and UNIT_PORTRAIT_UPDATE, PlayerFrame.lua takes UNIT_LEVEL
-- and UNIT_FACTION, TargetFrame.lua takes UNIT_AURA and PartyMemberFrame.lua
-- takes UNIT_CONNECTION. A frame that draws what the client's own frame draws
-- may listen to what the client's own frame listens to.
--
-- Marked rather than drawn, because a unit taking four hits between two frames
-- is four events and one block. The pass a fifth of a second later draws what
-- is marked, which is the rate this part has always redrawn at.
--
-- The unit is compared even though ns.RegisterUnitEvent asked the client to
-- filter, because a client without RegisterUnitEvent gets the plain
-- registration and hands over every unit it tracks.
local WATCHED = {
	"UNIT_AURA",
	"UNIT_HEALTH",
	"UNIT_MAXHEALTH",
	"UNIT_POWER_UPDATE",
	"UNIT_MAXPOWER",
	"UNIT_CONNECTION",
	"UNIT_NAME_UPDATE",
	"UNIT_LEVEL",
	"UNIT_FACTION",
	"UNIT_PORTRAIT_UPDATE",
	-- The one event that carries target of target: the host's target moved.
	-- Registered against every unit and acted on by the frame under it, which
	-- is why Touched marks the perched entry too.
	"UNIT_TARGET",
}

local function Touched(watch, event, unit)
	if unit ~= watch.unit then
		return
	end
	local entry = watch.entry
	entry.dirty = true
	if event == "UNIT_PORTRAIT_UPDATE" then
		entry.portraitDirty = true
	elseif event == "UNIT_TARGET" and entry.perch then
		entry.perch.dirty = true
	end
end

-- The news turned on with the block and off again with it. A frame nobody is
-- drawing has nothing to be told.
local function Listen(entry, on)
	if entry.listening == on then
		return
	end
	entry.listening = on
	for index = 1, #WATCHED do
		if on then
			ns.RegisterUnitEvent(entry.watch, WATCHED[index], entry.spec.unit)
		else
			entry.watch:UnregisterEvent(WATCHED[index])
		end
	end
end

--------------------------------------------------------------------------
-- The chain
--
-- The player block is placed by dragging it and nothing else is. The target
-- block hangs off the player block while the link is on and sits on a point
-- of its own while it is off, and target of target hangs off the target block
-- always. UnitFrames/Block.lua writes the anchors; what this file adds is the
-- only part of it that needs the list, which is which entry a spec's `beside`
-- or `under` names.
--------------------------------------------------------------------------

local function EntryFor(key)
	for _, entry in ipairs(entries) do
		if entry.spec.key == key then
			return entry
		end
	end
	return nil
end

local function Linked(entry)
	local host = EntryFor(entry.spec.beside)
	return host and ns.db.skinLink and entry.styled and host.styled and true or false, host
end

-- Where a block hangs, written on every pass. False where combat refused or a
-- host has not resolved a position yet, and the caller carries it to the next
-- pass.
local function Hang(entry)
	local spec = entry.spec
	local want, host = Linked(entry)
	if want then
		return Block.Link(entry, host)
	end
	entry.linked = false
	local under = EntryFor(spec.under)
	if under then
		return Block.Perch(entry, under)
	end
	if ns.Blocked(entry.frame) then
		return false
	end
	entry.place:Place(ns.db[spec.point])
	return true
end

-- Where a drag left a frame, from UI.Placeable's drop.
--
-- The player's corner is the setting. The target's is the setting too while
-- the link is off, and the level while it is on: the horizontal half of a
-- linked drop is thrown away, because the target's edge is the player's
-- reflected and the only place it can land is opposite wherever the player is.
-- Either way the chain is written again, so the frames under the one that
-- moved follow it on the same pass.
local function Dropped(entry, point)
	if entry.linked then
		Block.Landed(entry, EntryFor(entry.spec.beside))
	else
		ns.db[entry.spec.point] = point
	end
	Skin.Relayout()
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

-- The tooltip on a hover, which is the client's own for the unit. Hung by
-- hand rather than through ns.Tip.Hang, because Hang passes the right button
-- through to the camera and the right button is the menu here.
local function Hover(entry)
	local frame = entry.frame
	entry.subject = { kind = "unit", unit = entry.spec.unit }
	frame:SetScript("OnEnter", function(self)
		ns.Tip.Open(self, entry.subject)
	end)
	frame:SetScript("OnLeave", function()
		ns.Tip.Close()
	end)
end

-- One frame, built once at login. Nil where this client refuses the template,
-- in which case the part says so and draws nothing rather than drawing a
-- square that cannot be clicked.
local function Build(spec)
	local anchor = CreateFrame("Frame", spec.global, UIParent)
	ns.UI.Adopt(anchor)

	-- The one call in this file that names a Blizzard template. A client that
	-- does not carry it refuses the frame rather than raising, and everything
	-- below then answers that the part is not on this client.
	local ok, button = pcall(CreateFrame, "Button", spec.button, anchor,
		"SecureUnitButtonTemplate")
	if not ok or type(button) ~= "table" then
		anchor:Hide()
		return nil
	end

	-- The click and the menu, which are the two things a unit frame does that
	-- this addon cannot write. Left targets, right opens the client's own
	-- dropdown for whatever the unit turns out to be, and both are the
	-- attributes UnitFrames/Group.lua's tiles carry.
	button:SetAttribute("unit", spec.unit)
	button:SetAttribute("*type1", "target")
	button:SetAttribute("*type2", "togglemenu")
	button:RegisterForClicks("AnyUp")
	button:Hide()

	local entry = {
		spec = spec,
		anchor = anchor,
		frame = button,
		styled = false,
	}

	if spec.point then
		entry.place = ns.UI.Placeable(anchor, {
			name = spec.title,
			-- Refuses in combat: the anchor holds a secure button, and moving
			-- the frame a protected frame is parented to in a lockdown is
			-- what the client raises on.
			combat = false,
			moved = function(point)
				Dropped(entry, point)
			end,
		})
	end

	-- The frame the client's news about this unit lands on. One per entry
	-- rather than one shared, because the filtered registration is per unit
	-- and a shared frame would be handed every unit the client tracks.
	entry.watch = CreateFrame("Frame")
	entry.watch.entry = entry
	entry.watch.unit = spec.unit
	entry.watch:SetScript("OnEvent", Touched)

	Block.Build(entry)
	Hover(entry)
	for index = 1, #watchers do
		watchers[index](button)
	end
	return entry
end

--------------------------------------------------------------------------
-- Showing and hiding
--
-- The button goes up through the unit watch on the two frames that follow a
-- unit and through a plain Show on your own, and comes down the reverse way.
-- Both are protected calls on a secure button, so both ask ns.Blocked first
-- and a refusal is carried to the next PLAYER_REGEN_ENABLED.
--------------------------------------------------------------------------

local function Reveal(entry)
	local frame, spec = entry.frame, entry.spec
	if not spec.watch then
		frame:Show()
	elseif RegisterUnitWatch then
		RegisterUnitWatch(frame)
	else
		frame:SetShown(UnitExists(spec.unit))
	end
end

local function Conceal(entry)
	if entry.spec.watch and UnregisterUnitWatch then
		UnregisterUnitWatch(entry.frame)
	end
	entry.frame:Hide()
end

local function Style(entry)
	if entry.styled then
		return true
	end
	-- Everything here would go through in combat except the size and the
	-- show, and half a frame is worse than none, so the whole of it waits
	-- together.
	if not Block.Place(entry) then
		return false
	end
	entry.styled = true
	Paint.Forget(entry)
	entry.dirty = true
	Listen(entry, true)
	Reveal(entry)
	-- After entry.styled, because the rows only draw on a styled frame.
	return ns.FrameAuras.Style(entry)
end

local function Unstyle(entry)
	if not entry.styled then
		return true
	end
	if ns.Blocked(entry.frame) then
		return false
	end
	entry.styled = false
	Listen(entry, false)
	Conceal(entry)
	return ns.FrameAuras.Unstyle(entry)
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

-- Both halves have to agree: the part is on, and this frame has not been
-- turned off on its own.
function Skin.Wanted(key)
	return ns.db.skin and ns.db.skinFrames[key] ~= false
end

-- Puts every frame where the setting says it should be. Idempotent, and safe
-- to call before the saved variables exist, the same as every other part.
function Skin.Apply()
	if not ns.db or #entries == 0 then
		return
	end
	pending = false
	for _, entry in ipairs(entries) do
		local complete
		if Skin.Wanted(entry.spec.key) then
			complete = Style(entry)
		else
			complete = Unstyle(entry)
		end
		if not complete then
			pending = true
		end
	end
	-- After every frame has settled, not inside the loop above: where a frame
	-- hangs depends on whether the one it hangs off came up.
	for _, entry in ipairs(entries) do
		if not Hang(entry) then
			pending = true
		end
	end
	-- Painted here rather than left to the next tick, because up to a fifth of
	-- a second of a white gauge is exactly long enough to read as a bug.
	for _, entry in ipairs(entries) do
		Paint.Refresh(entry)
	end
end

-- Every block laid out again on the settings it has now, and hung again.
-- Sizing a secure button is what combat forbids, so a relayout that arrives
-- in lockdown is remembered rather than dropped: a resolution change comes
-- through here, and a block left on the old grid is the wrong size until
-- something else happens to move it.
function Skin.Relayout()
	if not ns.db or not ns.db.skin then
		return
	end
	for _, entry in ipairs(entries) do
		if entry.styled then
			if not Block.Place(entry) then
				pending = true
			end
		end
	end
	for _, entry in ipairs(entries) do
		if not Hang(entry) then
			pending = true
		end
	end
end

-- Locked is the normal state. Unlocked, the two anchors you can drag wear
-- their rim and their name and take the mouse, and the buttons inside them
-- stop taking it, because a secure button over the whole of the anchor would
-- otherwise swallow the drag. Out of combat only: EnableMouse is not a
-- protected call, but a frame that changes what it does with the mouse in the
-- middle of a pull is a frame that just ate a click.
function Skin.Lock()
	for _, entry in ipairs(entries) do
		if entry.place then
			local unlocked = not ns.db.locked
			entry.place:Lock(unlocked)
			if not InCombatLockdown() then
				entry.frame:EnableMouse(not unlocked)
			end
		end
	end
end

function Skin.Deferred()
	return pending
end

-- What to do to each button once it exists. It exists for ctrl-click
-- marking, which a behaviour file may not reach across for, and it is the
-- seam UnitFrames/Group.lua offers for the same reason.
function Skin.OnFrame(callback)
	watchers[#watchers + 1] = callback
end

-- One frame's own parts, for a macro and for the harness. Handed out for the
-- reason SwingGauges.Bar and PlayerCast.Bar are: what was drawn has to be
-- measurable, and the alternative is this file answering a dozen questions
-- about itself one at a time.
function Skin.Entry(key)
	return EntryFor(key)
end

-- What a level is allowed to be. One source for the slash command, the panel's
-- stepper and the clamp a dropped drag goes through, because three copies of a
-- range is three chances for a drag to store a number the command would have
-- refused.
function Skin.LinkRange()
	return Block.Range()
end

-- What the link is doing, which is not always what the setting asks for. It
-- needs both frames up, so this says which half is missing rather than leaving
-- the setting on and nothing drawn.
function Skin.DescribeLink()
	if not ns.db.skinLink then
		return "the target block sits on a point of its own, drag it where you like"
	end
	if not ns.db.skin then
		return "the link is on and waiting for the frames, which are off"
	end
	if not (Skin.Wanted("player") and Skin.Wanted("target")) then
		return "the link needs the player and target frames on, and one of them is off"
	end
	return ("the target block is the player block mirrored in the middle of the"
		.. " screen, %s"):format(ns.db.skinLevel == 0 and "both tops on one line"
			or ("%d pixels %s"):format(math.abs(ns.db.skinLevel),
				ns.db.skinLevel > 0 and "lower" or "higher"))
end

-- What the client actually answered, printed rather than guessed at. Every
-- number the layout is built from comes out here, so a block that lands in the
-- wrong place is one line of output rather than another round of inference.
function Skin.Probe()
	if missing then
		ns.Print("frames: this client refused SecureUnitButtonTemplate, so none of the three was built.")
		return
	end
	if #entries == 0 then
		ns.Print("frames: nothing built yet, the frames are made at login.")
		return
	end
	ns.Print(("frames: unit watch %s on this client."):format(
		RegisterUnitWatch and "answers" or "missing, so the target goes up and down out of combat only"))
	for _, entry in ipairs(entries) do
		ns.Print(("%s: %s, %s"):format(entry.spec.key,
			entry.styled and "up" or "down", Block.Probe(entry)))
	end
end

function Skin.Describe()
	if missing then
		return "this client refused the secure button template, so no frames were built"
	end
	if not ns.db.skin then
		return "our frames off"
	end
	local off = {}
	for _, entry in ipairs(entries) do
		if not Skin.Wanted(entry.spec.key) then
			off[#off + 1] = entry.spec.key
		end
	end
	local line = "our own player, target and target of target frames, " .. Skin.DescribeLink()
	if ns.db.skinHeals then
		line = line .. (ns.HasHealPrediction() and ", incoming heals on the gauge"
			or ", incoming heals asked for and this client has no prediction api")
	end
	if #off > 0 then
		line = line .. ", " .. table.concat(off, " and ") .. " left off"
	end
	-- Combat is the usual reason a pass did not finish, and it is not the only
	-- one: a link written before the client has resolved the player block's
	-- edge waits for a pass that can measure it.
	if pending then
		line = line .. (InCombatLockdown() and ", the rest follows when combat drops"
			or ", the rest follows on the next pass")
	end
	return line
end

--------------------------------------------------------------------------

-- When a pass over the three blocks happens. What one pass does is
-- UnitFrames/Paint.lua's; these two are the clocks and nothing else.
--
-- The marked ones, drawn. Whatever the client said about a unit since the last
-- pass is on the screen a fifth of a second later, which is the rate this part
-- has always redrawn at, and a unit nothing has happened to costs the walk.
local function Tick()
	for _, entry in ipairs(entries) do
		if entry.dirty then
			entry.dirty = false
			Paint.Refresh(entry)
		end
	end
end

-- And every block read off the client from the top, once a second, for what the
-- events do not carry: an incoming heal, a mob somebody else has tagged, and
-- whatever target of target did that its host did not say.
local function Read()
	for _, entry in ipairs(entries) do
		entry.dirty = false
		Paint.Refresh(entry)
	end
end

local function MarkAll()
	for _, entry in ipairs(entries) do
		entry.dirty = true
	end
end

-- The events that mark every block rather than one unit's. The four about you
-- are the badge on your own frame; a raid marker moving is anybody's; and a
-- target change is the one unit change no per-unit event carries, because
-- "target" and "targettarget" are both a different creature now and the client
-- fires nothing against either token to say so. All three are marked rather
-- than the two, because your own block draws nothing that moved and a pass
-- over it is a handful of comparisons that all hold.
local MARKS = {
	PLAYER_TARGET_CHANGED = true,
	PLAYER_UPDATE_RESTING = true,
	PLAYER_REGEN_DISABLED = true,
	PLAYER_ENTER_COMBAT = true,
	PLAYER_LEAVE_COMBAT = true,
	RAID_TARGET_UPDATE = true,
}

local events = CreateFrame("Frame")
local tick -- the refresh ticker, armed once, see below
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
for event in pairs(MARKS) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		for _, spec in ipairs(SPECS) do
			local entry = Build(spec)
			if entry then
				entries[#entries + 1] = entry
			else
				missing = true
			end
		end
		-- What target of target is parked under, so the host's UNIT_TARGET can
		-- mark it. Resolved once, here, because the list is complete now.
		for _, entry in ipairs(entries) do
			local host = EntryFor(entry.spec.under)
			if host then
				host.perch = entry
			end
		end
		Skin.Apply()
		Skin.Lock()

		-- Armed once. UI.Ticker appends and refuses a second tick of either name
		-- on this frame, so a branch that arms one has to be a branch that runs
		-- once.
		if not tick then
			tick = ns.UI.Ticker(ns.UI.Forever, REFRESH, "skin", Tick)
			ns.UI.Ticker(ns.UI.Forever, VERIFY, "skinread", Read)
		end
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		MarkAll()
		if pending then
			-- Apply finishes a style combat refused. Relayout finishes a
			-- re-anchor it refused, which Apply cannot: Style returns early on
			-- a frame that is already styled, so a block on the wrong grid
			-- would stay there.
			Skin.Apply()
			Skin.Relayout()
		end
		return
	end

	if MARKS[event] then
		MarkAll()
		if event == "PLAYER_TARGET_CHANGED" then
			-- A client with no unit watch has the target's button put up and
			-- down here, out of combat, which is the most it can do.
			for _, entry in ipairs(entries) do
				if entry.styled and entry.spec.watch and not RegisterUnitWatch
					and not ns.Blocked(entry.frame) then
					entry.frame:SetShown(UnitExists(entry.spec.unit))
				end
			end
		end
		return
	end

	-- PLAYER_ENTERING_WORLD: the world may have changed scale under the
	-- frames, so they are laid out again on what it says now.
	MarkAll()
	Skin.Relayout()
end)

-- A resolution change moves the grid under the whole block at once. Relayout
-- refuses in lockdown and PLAYER_REGEN_ENABLED picks it up, so a monitor
-- swapped mid pull is a block one fight out of date rather than an error.
ns.UI.OnRescale(function()
	Skin.Relayout()
end)
