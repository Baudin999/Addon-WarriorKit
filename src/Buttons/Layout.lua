local ADDON, ns = ...

local Layout = {}
ns.Layout = Layout

-- Fills the action bars with a warrior loadout and can put back exactly what
-- was there before. Two jobs are deliberately not done here:
--
--   Keybindings. Nothing in this file calls SetBinding or SaveBindings. The
--   bar 1 and bar 2 keys are already bound in the binding set, so the loadout
--   only has to write the slots those keys point at. That keeps the README's
--   rule about never touching a saved binding intact.
--
--   Frame positions. Where the bars sit is Edit Mode's job, and driving the
--   Edit Mode manager from an addon is a much larger and much more fragile
--   thing than writing action slots. Layout in this file means what is in the
--   slots, not where the bar is.
--
-- Nothing here is reachable in combat. PlaceAction is protected, and unlike
-- the charge button there is no reason to queue a bar rewrite for when combat
-- drops, so it refuses instead.

--------------------------------------------------------------------------
-- The plan
--
-- Not here. What goes in which slot is a fact about your class and lives in
-- Class/<yours>.lua as `loadout`. This file is the mechanism: which action
-- slots the bars drive, how to put a spell in one, and how to hand back exactly
-- what was there before. None of that changes with the class.
--
-- A plan is four fields.
--
--   pages   the page keys, in the order the `stance:` macro conditional counts
--           them. One key for a class that does not page bar 1 at all, which is
--           most of them.
--   single  which page to write when the plan has several and the client is not
--           paging: no stance, or a bar the client will not tell us about.
--   macros  what has to exist before the plan can be placed. Created per
--           character, prefixed so Restore finds exactly what was made.
--   bar1    twelve rows, one per physical key, each with a cell per page. The
--           row is the job that key does and the cells are how that job is done
--           on each page, which is what makes them one row.
--   bar2    twelve cells, the shift layer, which does not page.
--
-- Nil for a class nobody has written a plan for. Nil is the whole gate:
-- CanApply refuses, Buttons/Feature.lua opens no page, and nothing is ever
-- written to a bar it could not fill.
--
-- Read on demand rather than held at load, because the class is not reliably
-- known while the files load.
--------------------------------------------------------------------------

function Layout.Plan()
	return ns.Class.Of("loadout")
end

--------------------------------------------------------------------------
-- Can this client do it
--
-- Nothing installed here calls the action-writing API unguarded, so unlike
-- the rest of the addon these are not confirmed to exist. Details references
-- all of them but only inside luaserver.lua, which is a language-server stub
-- rather than running code, so it proves nothing. Probe instead of assume,
-- the same way BuildBinder probes for RegisterStateDriver.
--------------------------------------------------------------------------

-- Two lists, because there are two sizes of job here and they need different
-- amounts of the client.
--
-- Moving one slot onto another needs two calls. That is what a drag from
-- Buttons/Bars.lua is, and holding it to the whole list below would refuse a
-- gesture over five functions it never touches.
--
-- Composing a loadout needs the rest: it picks spells and macros up by name,
-- reads back what a slot ended up holding, and puts the cursor down when it is
-- finished. Everything in CARRY as well, which is why CanWrite is CanCarry plus
-- this rather than a list of its own.
local CARRY = { "PickupAction", "PlaceAction" }
local COMPOSE = {
	"PickupSpell", "PickupMacro", "ClearCursor", "GetCursorInfo", "GetActionInfo",
}

-- nil until asked, then true or a reason string. One each, because a client
-- with the two and not the five is a real client and answers yes to one
-- question and no to the other.
local carrying, composing

local function Absent(list)
	for _, name in ipairs(list) do
		if type(_G[name]) ~= "function" then
			return name .. " is missing on this client"
		end
	end
	return true
end

-- Named rather than repeated, because Layout.Describe tests two of them by
-- value to decide whether a refusal is worth reporting as unavailability or as
-- something that will clear on its own. Two copies of a sentence is one typo
-- away from that test never matching again.
--
-- These two are the only refusals in this file that clear on their own, and
-- every other one is tested before them. That order is what makes the test
-- above sound: a refusal that is not one of these two is still there after the
-- fight, and Describe may say so. Reached in the other order, a permanent
-- refusal wears a transient sentence for as long as the fight lasts and
-- Describe carries on past it into the state that refused.
Layout.BUSY_COMBAT = "you are in combat"
Layout.BUSY_CURSOR = "put down what you are holding first"
function Layout.Refusal()
	return ("there is no bar loadout written for a %s yet"):format(ns.Class.Label())
end

-- Whether the cursor may be picked up or put down at all: the API is here and
-- combat is not. Says nothing about what the cursor is holding, which is the
-- whole reason it is split out of Layout.CanWrite below.
--
-- Buttons/Bars.lua drags a spell onto a square through this. That gesture
-- happens with something already on the cursor, which is the exact state
-- CanWrite refuses, so a drop asking CanWrite would be told to put down the
-- thing it is in the middle of putting down.
function Layout.CanCarry()
	if carrying == nil then
		carrying = Absent(CARRY)
	end
	if carrying ~= true then
		return false, carrying
	end
	if InCombatLockdown() then
		return false, Layout.BUSY_COMBAT
	end
	return true
end

-- Whether an action slot can be written at all: the API is here, combat is
-- not, and the cursor is empty. Says nothing about what is worth writing, so
-- Ranks uses this one. Moving a slot up to the best rank you know is the same
-- job in every class.
function Layout.CanWrite()
	-- Before CanCarry rather than after it, because CanCarry ends on combat.
	-- A client with no PickupSpell answered "you are in combat" for the length
	-- of every fight, which reads as a client that will be able to do this in
	-- a minute and never will.
	if composing == nil then
		composing = Absent(COMPOSE)
	end
	if composing ~= true then
		return false, composing
	end
	local can, why = Layout.CanCarry()
	if not can then
		return false, why
	end
	if GetCursorInfo() then
		return false, Layout.BUSY_CURSOR
	end
	return true
end

-- The loadout on top of that. Every spell in a plan is a spell of that class,
-- so running someone else's would fill the bars with things they cannot cast
-- and take a backup only that character can put back. A class with no plan
-- refuses here rather than anywhere further in.
--
-- The plan is asked for first because it is the one refusal here that no amount
-- of waiting fixes. Asked last, a hunter in combat was refused with "you are in
-- combat", Describe read that as a wait and went on to page a plan that was
-- never written, and /wk status errored on the length of a nil.
function Layout.CanApply()
	if not Layout.Plan() then
		return false, Layout.Refusal()
	end
	return Layout.CanWrite()
end

--------------------------------------------------------------------------
-- Which slots
--
-- The slot a bar button writes to is read off the button rather than worked
-- out from a table of page numbers. ActionButton1.action already holds the
-- answer for whichever stance you are standing in, so one observation plus
-- the 12 slot stride covers the other two.
--------------------------------------------------------------------------

-- Exported rather than local because Buttons/Bars.lua reads the same field off
-- the same buttons to find out which slots a bar it is cloning drives, and two
-- copies of a four line reader is two places for the 120 slot bound to drift.
function Layout.SlotOf(name)
	local button = _G[name]
	local action = button and button.action
	if type(action) == "number" and action >= 1 and action <= 120 then
		return action
	end
	return nil
end

-- How many pages bar 1 has beyond the one it starts on. Three, which is what
-- the `stance:` conditional counts to on both of these clients and what
-- Buttons/Bars.lua's page macro is written against. It is a fact about the
-- client's bonus bar and not about any class: a warrior reaches all three and a
-- druid reaches them with different names on.
Layout.PAGES = 3

-- Returns the slot each of bar 1's pages starts at, indexed by the number the
-- `stance:` conditional counts in, or nil plus a reason when this client is not
-- paging bar 1 at all.
--
-- Nothing about the loadout is read here, and that is the rule. Whether bar 1
-- re-points at another twelve slots is the client's business, and the clone in
-- Buttons/Bars.lua has to follow it whatever class you are, which is the same
-- "do not invent a slot space" this whole file is built on. A druid pages bar 1
-- and has no plan written for it; the clone still has to page.
function Layout.Bar1Bases()
	local base = Layout.SlotOf("ActionButton1")
	if not base then
		return nil, "cannot read ActionButton1"
	end

	local form = GetShapeshiftForm and GetShapeshiftForm() or 0
	local offset = GetBonusBarOffset and GetBonusBarOffset() or 0
	if form < 1 or form > Layout.PAGES or offset < 1 then
		return nil, "bar 1 is not paging by stance"
	end

	local bases = {}
	for index = 1, Layout.PAGES do
		local slot = base + (index - form) * 12
		if slot < 1 or slot + 11 > 120 then
			return nil, "stance page " .. index .. " lands outside the action slots"
		end
		bases[index] = slot
	end
	return bases
end

-- Which of the plan's pages go where, or nil plus a reason for a plan that
-- writes one page.
--
-- A plan writes every page or it writes one. Anything between would put the
-- same twelve spells on two of the three and leave the third holding whatever
-- was under it, which is a bar that looks filled and is not. So the pages are
-- taken only where the plan has a cell for each of the client's, and every
-- other case falls to plan.single on the twelve slots the bar is on now.
local function Paging(plan)
	local bases, why = Layout.Bar1Bases()
	if not bases then
		return nil, why
	end
	if #plan.pages ~= Layout.PAGES then
		return nil, ("this loadout has %d page and bar 1 has %d")
			:format(#plan.pages, Layout.PAGES)
	end
	return bases
end

function Layout.Bar2Base()
	return Layout.SlotOf("MultiBarBottomLeftButton1")
end

--------------------------------------------------------------------------
-- Cursor
--
-- Every write is guarded by GetCursorInfo. A pickup that came up empty must
-- never reach PlaceAction, or the slot gets whatever was on the cursor last.
--------------------------------------------------------------------------

-- PickupSpell has taken more than one shape across clients. Try the ones this
-- one might have, cheapest first, and report failure rather than guessing.
local function CursorSpell(name)
	ClearCursor()
	if pcall(PickupSpell, name) and GetCursorInfo() then
		return true
	end

	ClearCursor()
	local _, _, _, _, _, _, spellID = GetSpellInfo(name)
	if spellID and pcall(PickupSpell, spellID) and GetCursorInfo() then
		return true
	end

	ClearCursor()
	return false
end

local function CursorMacro(name)
	ClearCursor()
	local index = GetMacroIndexByName and GetMacroIndexByName(name) or 0
	if index and index > 0 and pcall(PickupMacro, index) and GetCursorInfo() then
		return true
	end
	ClearCursor()
	return false
end

local function CursorItem(id)
	ClearCursor()
	if pcall(PickupItem, id) and GetCursorInfo() then
		return true
	end
	ClearCursor()
	return false
end

local function ClearSlot(slot)
	ClearCursor()
	PickupAction(slot)
	ClearCursor()
end

--------------------------------------------------------------------------
-- Backup
--
-- Stored by stable identity, never by macro index, because indices shift the
-- moment a macro is created or deleted.
--------------------------------------------------------------------------

local function ReadSlot(slot)
	local kind, id = GetActionInfo(slot)
	if not kind then
		return { kind = "empty" }
	end
	if kind == "macro" then
		local name = GetMacroInfo and GetMacroInfo(id)
		if not name then
			return { kind = "unknown" }
		end
		return { kind = "macro", name = name }
	end
	if kind == "spell" or kind == "item" then
		return { kind = kind, id = id }
	end
	-- Companions, equipment sets and anything a later client adds. Restore
	-- leaves these alone rather than putting something wrong back.
	return { kind = "unknown" }
end

local function WriteSlot(entry, slot)
	if not entry or entry.kind == "unknown" then
		return false
	end
	if entry.kind == "empty" then
		ClearSlot(slot)
		return true
	end

	local ok = false
	if entry.kind == "spell" then
		ok = entry.id and CursorSpell(entry.id) or false
	elseif entry.kind == "item" then
		ok = entry.id and CursorItem(entry.id) or false
	elseif entry.kind == "macro" then
		ok = entry.name and CursorMacro(entry.name) or false
	end

	if ok and GetCursorInfo() then
		PlaceAction(slot)
		ClearCursor()
		return true
	end
	ClearCursor()
	return false
end

-- Every slot the plan is about to touch, so the snapshot covers exactly the
-- damage and no more.
local function TargetSlots(plan)
	local slots = {}
	local bases = Paging(plan)
	if bases then
		for page = 1, Layout.PAGES do
			for index = 1, 12 do
				slots[#slots + 1] = bases[page] + index - 1
			end
		end
	else
		local base = Layout.SlotOf("ActionButton1")
		if base then
			for index = 1, 12 do
				slots[#slots + 1] = base + index - 1
			end
		end
	end

	local two = Layout.Bar2Base()
	if two then
		for index = 1, 12 do
			slots[#slots + 1] = two + index - 1
		end
	end
	return slots
end

function Layout.HasBackup()
	local backup = ns.dbc and ns.dbc.layoutBackup
	return backup and next(backup) ~= nil
end

function Layout.BackupStamp()
	return (ns.dbc and ns.dbc.layoutStamp) or ""
end

--------------------------------------------------------------------------
-- Macros
--------------------------------------------------------------------------

local MACRO_ICON = 134400

-- Per character macro slots. 18 is what this client is expected to give; if it
-- turns out to be more, the only cost is refusing a little early.
local MACRO_CAP = 18

-- Returns how many of the plan's macros are missing, so Apply can check for
-- room before it creates any of them.
local function MissingMacros(plan)
	local missing = 0
	for _, macro in ipairs(plan.macros) do
		local index = GetMacroIndexByName and GetMacroIndexByName(macro.name) or 0
		if not index or index == 0 then
			missing = missing + 1
		end
	end
	return missing
end

local function EnsureMacros(plan, report)
	for _, macro in ipairs(plan.macros) do
		local index = GetMacroIndexByName and GetMacroIndexByName(macro.name) or 0
		if index and index > 0 then
			-- Ours already, so keep it in step with the plan.
			pcall(EditMacro, index, macro.name, MACRO_ICON, macro.body)
		else
			local ok, made = pcall(CreateMacro, macro.name, MACRO_ICON, macro.body, 1)
			if ok and made then
				local made_list = ns.dbc.layoutMacros
				made_list[#made_list + 1] = macro.name
			else
				report.macroFail = (report.macroFail or 0) + 1
			end
		end
	end
end

local function DropMacros()
	local made = ns.dbc.layoutMacros or {}
	for i = #made, 1, -1 do
		local index = GetMacroIndexByName and GetMacroIndexByName(made[i]) or 0
		if index and index > 0 then
			pcall(DeleteMacro, index)
		end
		made[i] = nil
	end
end

--------------------------------------------------------------------------
-- Apply and restore
--------------------------------------------------------------------------

local function PlaceSpec(spec, slot, report)
	if not spec then
		return
	end
	local ok = false
	if spec.kind == "spell" then
		ok = CursorSpell(spec.name)
	elseif spec.kind == "macro" then
		ok = CursorMacro(spec.name)
	end

	if ok and GetCursorInfo() then
		PlaceAction(slot)
		report.placed = report.placed + 1
	else
		report.skipped[#report.skipped + 1] = spec.name
	end
	ClearCursor()
end

function Layout.Apply()
	local can, why = Layout.CanApply()
	if not can then
		return false, why
	end

	local plan = Layout.Plan()
	local slots = TargetSlots(plan)
	if #slots == 0 then
		return false, "cannot work out which action slots the bars use"
	end

	-- Everything that can refuse has to refuse before the snapshot is taken.
	-- Recording a backup and then bailing would leave the addon believing a
	-- loadout was applied that never was.
	local missing = MissingMacros(plan)
	local room = MACRO_CAP - (GetNumMacros and select(2, GetNumMacros()) or 0)
	if missing > room then
		return false, ("needs %d character macro slots, %d free"):format(missing, room)
	end

	-- Taken once and kept. A second Apply on top of our own loadout must not
	-- bury the real bars under a snapshot of themselves.
	if not Layout.HasBackup() then
		local backup = {}
		for _, slot in ipairs(slots) do
			backup[tostring(slot)] = ReadSlot(slot)
		end
		ns.dbc.layoutBackup = backup
		ns.dbc.layoutStamp = date and date("%Y-%m-%d %H:%M") or "this session"
	end

	local report = { placed = 0, skipped = {} }
	EnsureMacros(plan, report)

	local bases, paging = Paging(plan)
	if bases then
		for page = 1, Layout.PAGES do
			local key = plan.pages[page]
			for index = 1, 12 do
				PlaceSpec(plan.bar1[index][key], bases[page] + index - 1, report)
			end
		end
	else
		-- The plan wanted pages and the client is not giving any, so there is one
		-- page to fill and the plan says which of its own is worth having when
		-- there is only one. TargetSlots guards this read, and so must this one:
		-- with the bar unreadable there is no slot to write to.
		local base = Layout.SlotOf("ActionButton1")
		if base then
			for index = 1, 12 do
				PlaceSpec(plan.bar1[index][plan.single], base + index - 1, report)
			end
		end
		report.note = paging
	end

	local two = Layout.Bar2Base()
	if two then
		for index = 1, 12 do
			PlaceSpec(plan.bar2[index], two + index - 1, report)
		end
	else
		report.note = "bottom left bar is off, so the shift layer was skipped"
	end

	return true, report
end

function Layout.Restore()
	local can, why = Layout.CanApply()
	if not can then
		return false, why
	end
	if not Layout.HasBackup() then
		return false, "nothing backed up, so there is nothing to put back"
	end

	local restored, failed = 0, 0
	for key, entry in pairs(ns.dbc.layoutBackup) do
		local slot = tonumber(key)
		if slot then
			if WriteSlot(entry, slot) then
				restored = restored + 1
			elseif entry.kind ~= "unknown" then
				failed = failed + 1
			end
		end
	end

	DropMacros()
	ns.dbc.layoutBackup = {}
	ns.dbc.layoutStamp = ""

	return true, { restored = restored, failed = failed }
end

-- What the bars would be filled from, for the panel and for /wk status. Called
-- in combat and with something on the cursor, because both are ordinary states
-- to read a status line in, so neither is reported as unavailability.
--
-- Past that line the plan exists. CanApply asks for it before it asks about
-- either of those two, so they are the only sentences that can come back with a
-- plan in hand, and the two tests are what says so.
function Layout.Describe()
	local can, why = Layout.CanApply()
	if not can and why ~= Layout.BUSY_COMBAT and why ~= Layout.BUSY_CURSOR then
		return "unavailable: " .. why
	end
	local plan = Layout.Plan()
	local bases, paging = Paging(plan)
	if not bases then
		local base = Layout.SlotOf("ActionButton1")
		return ("one page from slot %s: %s")
			:format(tostring(base or "?"), paging or "unknown")
	end
	return ("%d stance pages from slot %d"):format(Layout.PAGES, bases[1])
end
