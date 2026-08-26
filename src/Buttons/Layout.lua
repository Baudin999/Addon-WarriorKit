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
-- The whole design is this table. Changing the loadout is editing data, not
-- code. Every cell is { kind, name } where kind is "spell" or "macro", or nil
-- for a slot the plan leaves alone.
--
-- Names are English because this install is enUS. A localised client needs
-- the names swapping, which is the one thing in this file that is not
-- locale-proof.
--------------------------------------------------------------------------

local function Spell(name)
	return { kind = "spell", name = name }
end

local function Macro(name)
	return { kind = "macro", name = name }
end

-- Macros the plan needs. Created per character, prefixed so Restore can find
-- exactly what was made and delete nothing else.
Layout.MACROS = {
	{
		name = "WK Taunt",
		body = "#showtooltip\n/cast [stance:1] Mocking Blow; [@mouseover,harm,nodead] Taunt; Taunt",
	},
	{
		name = "WK Bash",
		body = "#showtooltip\n/cast [@mouseover,harm,nodead] Shield Bash; Shield Bash",
	},
	{
		name = "WK Pummel",
		body = "#showtooltip\n/cast [@mouseover,harm,nodead] Pummel; Pummel",
	},
	{
		name = "WK Sunder",
		body = "#showtooltip\n/startattack\n/cast [@mouseover,harm,nodead] Sunder Armor; Sunder Armor",
	},
	{
		name = "WK Strike",
		body = "#showtooltip\n/startattack\n/cast Heroic Strike",
	},
}

-- Bar 1, paged by stance. Same finger, same job, in every stance.
-- index 1 to 12 is the physical slot, which on this install is E Q Z X C V F 1 2 3 4 5.
Layout.BAR1 = {
	{ role = "rage dump",   battle = Macro("WK Strike"),        defensive = Macro("WK Strike"),           berserker = Macro("WK Strike") },
	{ role = "aoe dump",    battle = Spell("Cleave"),           defensive = Spell("Cleave"),              berserker = Spell("Cleave") },
	{ role = "builder",     battle = Spell("Rend"),             defensive = Macro("WK Sunder"),           berserker = Spell("Whirlwind") },
	{ role = "proc window", battle = Spell("Overpower"),        defensive = Spell("Revenge"),             berserker = Spell("Intercept") },
	{ role = "aoe hit",     battle = Spell("Thunder Clap"),     defensive = Spell("Thunder Clap"),        berserker = Spell("Berserker Rage") },
	{ role = "snare",       battle = Spell("Hamstring"),        defensive = Spell("Hamstring"),           berserker = Spell("Hamstring") },
	{ role = "interrupt",   battle = Macro("WK Bash"),          defensive = Macro("WK Bash"),             berserker = Macro("WK Pummel") },
	{ role = "execute",     battle = Spell("Execute"),          defensive = Spell("Execute"),             berserker = Spell("Execute") },
	{ role = "rage",        battle = Spell("Bloodrage"),        defensive = Spell("Bloodrage"),           berserker = Spell("Bloodrage") },
	{ role = "pull it back", battle = Macro("WK Taunt"),        defensive = Macro("WK Taunt"),            berserker = Spell("Challenging Shout") },
	{ role = "mitigation",  battle = Spell("Spell Reflection"), defensive = Spell("Shield Block"),        berserker = Spell("Recklessness") },
	{ role = "shout",       battle = Spell("Battle Shout"),     defensive = Spell("Demoralizing Shout"),  berserker = Spell("Battle Shout") },
}

-- Bar 2, the shift layer. Does not page, which is the point of it.
Layout.BAR2 = {
	Spell("Shield Wall"),
	Spell("Last Stand"),
	Spell("Battle Shout"),
	Spell("Demoralizing Shout"),
	Spell("Commanding Shout"),
	Spell("Intimidating Shout"),
	Spell("Disarm"),
	nil, -- healing potion, yours to drag, the addon will not guess an item
	nil, -- healthstone or bandage, same
	Spell("Battle Stance"),
	Spell("Defensive Stance"),
	Spell("Berserker Stance"),
}

local STANCES = { "battle", "defensive", "berserker" }

--------------------------------------------------------------------------
-- Can this client do it
--
-- Nothing installed here calls the action-writing API unguarded, so unlike
-- the rest of the addon these are not confirmed to exist. Details references
-- all of them but only inside luaserver.lua, which is a language-server stub
-- rather than running code, so it proves nothing. Probe instead of assume,
-- the same way BuildBinder probes for RegisterStateDriver.
--------------------------------------------------------------------------

local NEEDED = {
	"PickupSpell", "PickupMacro", "PlaceAction", "PickupAction",
	"ClearCursor", "GetCursorInfo", "GetActionInfo",
}

local probe -- nil until asked, then true or a reason string

-- Named rather than repeated, because Layout.Describe tests two of them by
-- value to decide whether a refusal is worth reporting as unavailability or as
-- something that will clear on its own. Two copies of a sentence is one typo
-- away from that test never matching again.
Layout.BUSY_COMBAT = "you are in combat"
Layout.BUSY_CURSOR = "put down what you are holding first"
Layout.NOT_WARRIOR = "this is a warrior loadout and you are not a warrior"

-- Whether an action slot can be written at all: the API is here, combat is
-- not, and the cursor is empty. Says nothing about what is worth writing, so
-- Ranks uses this one. Moving a slot up to the best rank you know is the same
-- job in every class.
function Layout.CanWrite()
	if probe == nil then
		probe = true
		for _, name in ipairs(NEEDED) do
			if type(_G[name]) ~= "function" then
				probe = name .. " is missing on this client"
				break
			end
		end
	end
	if probe ~= true then
		return false, probe
	end
	if InCombatLockdown() then
		return false, Layout.BUSY_COMBAT
	end
	if GetCursorInfo() then
		return false, Layout.BUSY_CURSOR
	end
	return true
end

-- The loadout on top of that. Every spell in BAR1 and BAR2 is a warrior spell,
-- so on anyone else this fills the bars with things they cannot cast and takes
-- a backup only that character can put back. ns.IsWarrior owns the question and
-- owns the reason it is not cached; the charge part asks the same one.
function Layout.CanApply()
	local can, why = Layout.CanWrite()
	if not can then
		return false, why
	end
	if not ns.IsWarrior() then
		return false, Layout.NOT_WARRIOR
	end
	return true
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

-- Returns a map of stance key to the slot its bar 1 button 1 writes to, or
-- nil plus a reason when this client does not page bar 1 by stance.
function Layout.Bar1Bases()
	local base = Layout.SlotOf("ActionButton1")
	if not base then
		return nil, "cannot read ActionButton1"
	end

	local form = GetShapeshiftForm and GetShapeshiftForm() or 0
	local offset = GetBonusBarOffset and GetBonusBarOffset() or 0
	if form < 1 or form > 3 or offset < 1 then
		return nil, "bar 1 is not paging by stance"
	end

	local bases = {}
	for index, key in ipairs(STANCES) do
		local slot = base + (index - form) * 12
		if slot < 1 or slot + 11 > 120 then
			return nil, "stance page " .. index .. " lands outside the action slots"
		end
		bases[key] = slot
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
local function TargetSlots()
	local slots = {}
	local bases = Layout.Bar1Bases()
	if bases then
		for _, key in ipairs(STANCES) do
			for index = 1, 12 do
				slots[#slots + 1] = bases[key] + index - 1
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
local function MissingMacros()
	local missing = 0
	for _, macro in ipairs(Layout.MACROS) do
		local index = GetMacroIndexByName and GetMacroIndexByName(macro.name) or 0
		if not index or index == 0 then
			missing = missing + 1
		end
	end
	return missing
end

local function EnsureMacros(report)
	for _, macro in ipairs(Layout.MACROS) do
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

	local slots = TargetSlots()
	if #slots == 0 then
		return false, "cannot work out which action slots the bars use"
	end

	-- Everything that can refuse has to refuse before the snapshot is taken.
	-- Recording a backup and then bailing would leave the addon believing a
	-- loadout was applied that never was.
	local missing = MissingMacros()
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
	EnsureMacros(report)

	local bases, paging = Layout.Bar1Bases()
	if bases then
		for _, key in ipairs(STANCES) do
			for index = 1, 12 do
				PlaceSpec(Layout.BAR1[index][key], bases[key] + index - 1, report)
			end
		end
	else
		-- No stance paging, so there is one page to fill and the tank set is
		-- the one worth having on it. TargetSlots guards this read, and so must
		-- this one: with the bar unreadable there is no slot to write to.
		local base = Layout.SlotOf("ActionButton1")
		if base then
			for index = 1, 12 do
				PlaceSpec(Layout.BAR1[index].defensive, base + index - 1, report)
			end
		end
		report.note = paging
	end

	local two = Layout.Bar2Base()
	if two then
		for index = 1, 12 do
			PlaceSpec(Layout.BAR2[index], two + index - 1, report)
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

function Layout.Describe()
	local can, why = Layout.CanApply()
	if not can and why ~= Layout.BUSY_COMBAT and why ~= Layout.BUSY_CURSOR then
		return "unavailable: " .. why
	end
	local bases, paging = Layout.Bar1Bases()
	if not bases then
		return "single page only: " .. (paging or "unknown")
	end
	return ("three stance pages from slot %d"):format(bases.battle)
end
