local ADDON, ns = ...

local Ranks = {}
ns.Ranks = Ranks

-- Puts the highest rank you know into every action slot still holding an older
-- one, and touches nothing else.
--
-- This is here so a plain spell on a bar can survive a trainer visit. The usual
-- fix is to wrap the ability in a macro, because `/cast Thunder Clap` with no
-- rank named always casts the best one. That costs a macro slot per ability,
-- and per character, and the slot then holds a macro rather than a spell, which
-- is a worse thing to hold. Rewriting the slot costs neither.
--
-- Deliberately narrow. Only slots holding a spell are looked at. A macro is
-- yours, its text is yours, and rewriting it is not this button's business.
-- Items, companions and equipment sets are left alone for the same reason.
--
-- Nothing here runs in combat, because PlaceAction is protected. A trainer
-- visit is not a fight, so it refuses rather than queuing the write for later
-- the way the charge button does.

local BOOK = "spell" -- BOOKTYPE_SPELL, written out so no global is needed

-- Every action slot, including the stance pages, which live above 72 and are
-- readable and writable whether or not the bar showing them is the one on
-- screen. A tank has three pages of bar 1 and only ever sees one at a time.
local SLOTS = 120

--------------------------------------------------------------------------
-- Can this client do it
--
-- Layout.CanApply already probes the cursor and action API and holds the
-- combat rule. This adds the spellbook half, which nothing else in the addon
-- reads, and keeps the two questions apart: reading the book needs neither a
-- free cursor nor a quiet moment, so the panel can count stale slots during a
-- fight even though the button is greyed.
--------------------------------------------------------------------------

local NEEDED = {
	"GetNumSpellTabs", "GetSpellTabInfo",
	"GetSpellBookItemInfo", "GetSpellBookItemName",
	"HasAction", "GetActionInfo", "GetSpellInfo",
}

local probe -- nil until asked, then true or a reason string

local function BookReadable()
	if probe == nil then
		probe = true
		for _, name in ipairs(NEEDED) do
			if type(_G[name]) ~= "function" then
				probe = name .. " is missing on this client"
				break
			end
		end
	end
	return probe == true
end

-- Layout.CanWrite rather than Layout.CanApply: this walks every slot and moves
-- whatever spell is in it up to your best rank, which is not a warrior job and
-- must not be gated on being one.
function Ranks.CanApply()
	if not BookReadable() then
		return false, probe
	end
	return ns.Layout.CanWrite()
end

--------------------------------------------------------------------------
-- What the best rank is
--
-- Read off the spellbook rather than by parsing the rank line under the icon.
-- That line is localised and the number in it is not always where you would
-- expect. Ranks of one spell sit in ascending order inside a tab, so the last
-- entry wearing a name is the best one you have, and that holds in every
-- locale.
--
-- FUTURESPELL entries are the greyed ranks the trainer has not sold you yet.
-- Taking one would put a spell on the bar you cannot cast, which is a worse
-- bug than the stale rank this file exists to fix.
--------------------------------------------------------------------------

local function HighestRanks()
	local best = {}
	for tab = 1, GetNumSpellTabs() do
		local _, _, offset, count = GetSpellTabInfo(tab)
		if type(offset) == "number" and type(count) == "number" then
			for index = offset + 1, offset + count do
				local kind, id = GetSpellBookItemInfo(index, BOOK)
				if kind == "SPELL" and id then
					local name = GetSpellBookItemName(index, BOOK)
					if name then
						best[name] = id
					end
				end
			end
		end
	end
	return best
end

--------------------------------------------------------------------------
-- What is stale
--
-- Cached, because the panel asks for the count on every refresh and a refresh
-- is every click anywhere in the window. Dropped whenever a slot moves or the
-- spellbook changes, which is the only two ways the answer can go out of date.
--------------------------------------------------------------------------

local cache

local function Scan()
	local best = HighestRanks()
	local stale = {}

	for slot = 1, SLOTS do
		if HasAction(slot) then
			local kind, id = GetActionInfo(slot)
			if kind == "spell" and id then
				local name = GetSpellInfo(id)
				local top = name and best[name]
				-- A rankless spell answers with the id already in the slot, so
				-- the inequality is what separates "no better rank exists"
				-- from "you are holding an old one".
				if top and top ~= id then
					stale[#stale + 1] = { slot = slot, from = id, to = top, name = name }
				end
			end
		end
	end

	return stale
end

function Ranks.Stale()
	if not cache then
		if not BookReadable() then
			return {}
		end
		local ok, list = pcall(Scan)
		cache = ok and list or {}
	end
	return cache
end

function Ranks.Forget()
	cache = nil
end

--------------------------------------------------------------------------
-- The write
--
-- PlaceAction swaps rather than overwrites, so the old rank lands back on the
-- cursor and has to be dropped or the next pickup inherits it. Same cursor
-- guard as Layout, for the same reason: a pickup that came up empty must never
-- reach PlaceAction, or the slot gets whatever was held last.
--------------------------------------------------------------------------

local function Replace(slot, id)
	ClearCursor()
	if not pcall(PickupSpell, id) or not GetCursorInfo() then
		ClearCursor()
		return false
	end
	PlaceAction(slot)
	ClearCursor()
	return true
end

function Ranks.Apply()
	local can, why = Ranks.CanApply()
	if not can then
		return false, why
	end

	local report = { moved = 0, failed = {} }

	for _, entry in ipairs(Ranks.Stale()) do
		-- Read the slot again. The cached list can be a click old, and writing
		-- a slot whose contents moved underneath would drop a spell on top of
		-- something the user just put there.
		local kind, id = GetActionInfo(entry.slot)
		if kind == "spell" and id == entry.from then
			if Replace(entry.slot, entry.to) then
				report.moved = report.moved + 1
			else
				report.failed[#report.failed + 1] = entry.name
			end
		end
	end

	Ranks.Forget()
	return true, report
end

function Ranks.Describe()
	local can, why = Ranks.CanApply()
	-- Both of these clear on their own and neither says anything about whether
	-- the feature works, so they are not worth reporting as unavailability.
	if not can and why ~= ns.Layout.BUSY_COMBAT and why ~= ns.Layout.BUSY_CURSOR then
		return "unavailable: " .. why
	end
	local count = #Ranks.Stale()
	if count == 0 then
		return "every spell on your bars is the best rank you know"
	end
	if count == 1 then
		return "1 slot is holding an older rank"
	end
	return count .. " slots are holding an older rank"
end

-- LEARNED_SPELL_IN_TAB fires at the trainer, ACTIONBAR_SLOT_CHANGED when
-- anything lands in a slot, and SPELLS_CHANGED covers login and everything
-- else of that shape. All any of them costs here is dropping a table.
--
-- Registered through pcall, which is the house pattern for an event a client
-- may not carry, because the comment that used to be here said all three were
-- vanilla-era and both clients had them and that was simply wrong. The 2.5.6
-- Anniversary client has no LEARNED_SPELL_IN_TAB, RegisterEvent raises on a
-- name it does not know, and the raise came out of a file loading rather than
-- out of anything anybody did, so it was one error at login every session with
-- nothing on screen to connect it to. SPELLS_CHANGED covers the trainer on a
-- client without it.
local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "LEARNED_SPELL_IN_TAB")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
events:SetScript("OnEvent", function()
	Ranks.Forget()
end)
