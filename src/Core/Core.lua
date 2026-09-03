local ADDON, ns = ...

ns.version = "1.9"

-- Core knows nothing about any feature. It holds the saved variables, the API
-- shims, the two drawing helpers every part uses, and the one registry every
-- feature signs into. Adding an eighth part to the addon must not require
-- editing this file.

--------------------------------------------------------------------------
-- The registry
--
-- Each part calls ns.Register once, from its Feature.lua, and
-- hands over everything Core or the panel could want from it. Nothing else in
-- the addon reaches across parts to find out what exists.
--
--   name          the word that heads its slash help and its status line
--   order         a whole number, unique across the addon: where this part's
--                 tabs sit inside whichever group they named, and where its
--                 line sits in /wk status
--   defaults      merged into ns.db, the account-wide saved variables
--   charDefaults  merged into ns.dbc, this character's saved variables
--   switch        { key, label, available } the one boolean that decides
--                 whether this part puts anything on your screen
--   words         slash words this part answers to, word = function(arg, raw)
--   help          lines printed by /wk help
--   status        function returning one line for /wk status
--   lock          function applying ns.db.locked to this part's frames
--   reset         function putting this part's frames back where they started
--   panel         function(ui) building this part's sections of the panel
--   zooms         { { key, label, apply } } one entry per screen this part
--                 draws that can be sized on its own. key is the account
--                 setting holding the number, label is what the zoom page
--                 calls that screen, and apply is called after the number
--                 changes. A part with one screen registers one entry; the
--                 unit frames register several, because a party list and a
--                 nameplate are two screens by every measure but the folder
--                 they live in. window = true says this screen is one of the
--                 windows that shared uiSize before it was split, which is the
--                 only thing the one migration reads
--   showing       function(open) the options window opened or closed. For a
--                 part that draws something on the screen to say which of its
--                 rows the page is on, and has to stop when the page is gone
--
-- Every field except name is optional. A part with no frames has no lock.
--
-- order is whole and unique because it used to be neither. Two parts sat on 8
-- and a third on 7.6, so where they came out was whatever table.sort felt like
-- on the day, and the only way to find out was to open the window. A collision
-- is a login error now.
--
-- switch is the one boolean the panel draws itself, at the top of the part's
-- first page, and the rail reads to say which groups are doing something. It
-- exists because eleven parts each wrote their own check box for the same idea
-- and no two of them worded it the same way. available is optional and says the
-- part is not built on this character at all, which is Charge on a class whose
-- file named no openers. A part that answers no there opens no page and takes
-- no row on Start here: the switch is not greyed, it is not there.
--
-- Two scopes, because they are two different questions. A preference is yours
-- and belongs to the account. A record of what was in your action bars before
-- the loadout overwrote them belongs to the character whose bars they were,
-- and storing it account-wide is how one character's backup ends up written
-- over another character's bars.
--------------------------------------------------------------------------

ns.features = {}

local defaults = {
	locked = true,

	-- Where each window was last dropped, by frame name. Empty when the addon
	-- ships, because a window nobody has moved opens in the middle of the
	-- screen, and one entry per window you have dragged after that.
	--
	-- One setting for all of them rather than one per window. A window is not a
	-- preference anybody words differently: every one of them wants the same
	-- five-field anchor written down under a name it already has, and the
	-- alternative was seven keys named mapPoint, mailPoint, questPoint and so
	-- on, seven defaults, and a key to add every time the addon grows a window.
	-- ns.Remember below is the whole of what reads and writes it.
	windowSpots = {},
}

local charDefaults = {}

-- Settings that shipped and were then dropped. A key no feature registers is
-- never read again, but saved variables are written back whole at every logout,
-- so it sits in the file forever looking like a setting. Named here with what
-- dropped them, cleared once at load, and asserted against below so a key
-- cannot be retired and registered at the same time.
local RETIRED = {
	-- 1.2: buffRacial was the switch on the racial nag while the racial was a
	-- half of the row rather than an entry on it. It is an entry now, switched
	-- and dragged the way the others are, under buffWatch.racial on the
	-- character; an account-wide boolean for one character's racial was the
	-- wrong scope in the first place.
	buffRacial = true,

	-- 1.2: the aim reticle, replaced by softAuto driving SoftTargetEnemy off
	-- combat rather than drawing a box around what it resolved to.
	softIcon = true,
	softIconSize = true,

	-- 1.2: the breakdown ranked by damage, casts or hits off a chip on its
	-- window. The other two rankings were answers to a question that table does
	-- not ask, and a ranking by press count puts Battle Shout above Mortal
	-- Strike. It never shipped, but a reload while it existed wrote the key.
	breakdownSort = true,

	-- 1.2: markKeys was a boolean for one edit before the marking keys became
	-- one setting per mark in markBinds. It never shipped, but a reload while it
	-- existed wrote it, and ApplyDefaults keeps whatever it finds, so a boolean
	-- would still be sitting where a table is now indexed.
	markKeys = true,

	-- 1.2: the distance between the player and target blocks, back when the two
	-- were anchored a fixed distance apart. The target's facing edge is the
	-- player's reflected in the middle of the screen now, so the corridor is
	-- twice the player's distance from the centre and there is no number to
	-- choose. Retired rather than left to sit unread, because a setting nothing
	-- reads is a setting somebody will try to change.
	skinGap = true,

	-- 1.2: whether the chat window was left open, written by a cross at the
	-- foot of its rail. The cross is gone: it took the conversation off the
	-- screen in one press and wrote that down, so the window stayed gone across
	-- reloads and the way back was a slash word you had to know. The way to be
	-- rid of the window is the chat setting, and this key has to be wiped or a
	-- player who pressed the cross once would never see the window again.
	chatShown = true,

	-- 1.9: one switch for the client's own aura row, which meant a different
	-- thing depending on what the skin was doing. It is four switches now, one
	-- per thing you can see twice, and each says what it does on its own line.
	blizzAuras = true,

	-- 1.9: how many squares each aura row drew, shipped at eight. Eight is one
	-- line of the block the addon ships, so a raid's worth of buffs stopped at
	-- the end of the line and the ninth was not on the screen. A row draws
	-- every aura the client reports now and wraps away from the block, which
	-- is what the row could always do and the cap never let it. Retired rather
	-- than left, because a saved eight would cap the row again on the next
	-- login for anyone who had ever reloaded with it.
	skinAuraDebuffs = true,
	skinAuraBuffs = true,

	-- 1.9: a boolean for whether a hover's box docked in the corner, back when
	-- the corner and beside were the only two places it could go. There are
	-- three now and the third is a marker you drag, so the setting is the word
	-- tipPlace. A boolean left sitting there would be read by nothing and would
	-- still be what a player who had turned the dock off found in their file.
	tipDock = true,

	-- 1.9: the party and the raid were one list out of one secure header, so
	-- one place on the screen, one block size and one set of columns served
	-- both. They are two frames now, each with its own header and its own
	-- settings, and these four are what the single one used to read.
	--
	-- partyPoint is the one that has to be wiped rather than carried. A list is
	-- anchored by its middle now, whatever corner a drag ends on, because that
	-- is the only anchor a list can fill outward from; the numbers under the old
	-- name were whichever corner the client last left the frame on, and reading
	-- those as a middle would put the frames somewhere nobody chose. The new
	-- name is partyMiddle and it says which of the two it is.
	partyPoint = true,
	partyOrder = true,
	partyRaidColumns = true,
	partyRaidPerColumn = true,
}

-- A key lives in exactly one scope. Checking both tables on every insert is
-- what stops a setting being account-wide in one release and per-character in
-- the next without anyone noticing.
local function Claim(into, source)
	for key, value in pairs(source or {}) do
		assert(defaults[key] == nil and charDefaults[key] == nil,
			("two features both define the setting %q"):format(key))
		assert(not RETIRED[key],
			("%q is in the retired list and would be wiped at every load"):format(key))
		into[key] = value
	end
end

local taken = {}
local zoomKeys = {}

function ns.Register(feature)
	assert(type(feature) == "table" and type(feature.name) == "string",
		"a feature must register a table with a name")
	assert(type(feature.order) == "number" and feature.order == math.floor(feature.order),
		("%s registered the order %s, and an order is a whole number")
			:format(feature.name, tostring(feature.order)))
	assert(not taken[feature.order],
		("%s and %s both registered the order %d")
			:format(feature.name, tostring(taken[feature.order]), feature.order))
	taken[feature.order] = feature.name

	if feature.switch then
		assert(type(feature.switch.key) == "string" and type(feature.switch.label) == "string",
			("%s registered a switch with no key or no label"):format(feature.name))
		assert(type((feature.defaults or {})[feature.switch.key]) == "boolean",
			("%s says its switch is %q and no boolean of that name is in its defaults")
				:format(feature.name, feature.switch.key))
	end

	-- Held to the same contract as switch and for the same reason: a zoom whose
	-- key is not in the part's own defaults is a row on the zoom page that reads
	-- nil, writes a number nothing merges, and is gone again next login.
	for _, zoom in ipairs(feature.zooms or {}) do
		assert(type(zoom.key) == "string" and type(zoom.label) == "string",
			("%s registered a zoom with no key or no label"):format(feature.name))
		assert(type((feature.defaults or {})[zoom.key]) == "number",
			("%s says a zoom is %q and no number of that name is in its defaults")
				:format(feature.name, zoom.key))
		assert(not zoomKeys[zoom.key],
			("%s and %s both registered the zoom %q")
				:format(feature.name, tostring(zoomKeys[zoom.key]), zoom.key))
		zoomKeys[zoom.key] = feature.name
	end

	Claim(defaults, feature.defaults)
	Claim(charDefaults, feature.charDefaults)

	ns.features[#ns.features + 1] = feature
	table.sort(ns.features, function(a, b)
		return a.order < b.order
	end)
	return feature
end

-- Walks the registry so callers never name a feature. Used by lock, reset and
-- anything else that has to reach every part at once.
function ns.Each(hook, ...)
	for _, feature in ipairs(ns.features) do
		if feature[hook] then
			feature[hook](...)
		end
	end
end

--------------------------------------------------------------------------
-- How big one screen is drawn
--
-- Every part of the addon that puts a frame on the screen sizes it on its own.
-- There used to be two answers to this and they disagreed: the HUD parts each
-- kept a key, and every window in the addon shared one number called uiSize, so
-- shrinking the map to fit beside the quest log shrank the quest log with it.
--
-- The screen's own contribution is still shared, because it is not a
-- preference. A 4K panel halves the size of every metric the addon is drawn in
-- and doubling it back is arithmetic, not taste. What the player chose
-- multiplies on top of that, per screen, which is the whole of the change.
--------------------------------------------------------------------------

-- The zoom one screen is drawn at, screen contribution included. Handed to
-- UI.Window and to UI.Rezoom as a number, or as a closure over this for a frame
-- that has to ask again after the grid moves.
function ns.Zoom(key)
	local chosen = ns.UI.ZoomSnap(ns.db and ns.db[key] or 1)
	return ns.UI.ScreenZoom() * chosen
end

-- Every registered screen, in feature order, so the zoom page can list them
-- without naming a single feature. Flat rather than grouped: the page draws one
-- row per screen and the part it came from is already in the label.
function ns.Zooms()
	local out = {}
	for _, feature in ipairs(ns.features) do
		for _, zoom in ipairs(feature.zooms or {}) do
			out[#out + 1] = zoom
		end
	end
	return out
end

-- Nameplate frames are restricted regions on this client. A positional
-- measurement on one raises rather than returning nil, and a ticker that does
-- it once a frame buys "too many errors, disable addons" in about a minute.
-- Size, scale, strata and level do answer, but every measurement of a frame
-- the addon does not own goes through here so a client that restricts more of
-- them degrades to a nil answer instead of a screenful of errors.
function ns.Measure(frame, method)
	if not frame or type(frame[method]) ~= "function" then
		return nil
	end
	local ok, value = pcall(frame[method], frame)
	if ok then
		return value
	end
	return nil
end

--------------------------------------------------------------------------
-- Hiding what the addon does not own
--
-- Blizzard's own update code turns its regions back on, so hiding one is not
-- enough: its Show method is replaced with Hide first, and put back on the way
-- out. Both halves refuse while a protected region is in lockdown and say so by
-- returning false, so the caller can finish the job at PLAYER_REGEN_ENABLED
-- rather than eating a lockdown error.
--
-- Lives here because three parts strip Blizzard regions, the enemy bars, the
-- artwork part and the frame skin, and none of them is allowed to reach into
-- another.
--------------------------------------------------------------------------

-- Whether a region refuses to be touched right now. Shared rather than local
-- because three parts ask it: the enemy bars strip nameplate regions, the
-- artwork part strips bar art, and the frame skin moves the regions of a
-- secure unit button, and all three queue the refusal for PLAYER_REGEN_ENABLED
-- rather than eating a lockdown error.
function ns.Blocked(region)
	return region and region.IsProtected and region:IsProtected() and InCombatLockdown()
end

function ns.Strip(region)
	if not region or region.wkStripped then
		return true
	end
	if ns.Blocked(region) then
		return false
	end
	region.wkStripped = true
	region.wkShow = region.Show
	region.Show = region.Hide
	region:Hide()
	return true
end

function ns.Unstrip(region)
	if not region or not region.wkStripped then
		return true
	end
	if ns.Blocked(region) then
		return false
	end
	region.Show = region.wkShow
	region.wkShow = nil
	region.wkStripped = nil
	region:Show()
	return true
end

-- What every line the addon says starts with. Named rather than written into
-- the call, because Chat/Feed.lua reads it back: with Blizzard's window hidden,
-- everything that window would have drawn comes round through one hook, and
-- the prefix is the only thing that tells a line of ours from a loot line. A
-- second spelling of it anywhere would be a room that quietly stopped filling.
ns.SIGNATURE = "|cff40c0f0WarriorKit|r: "

-- cold: ns.Print writes one line into the chat frame, which is the addon telling you something and never a tick
function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(ns.SIGNATURE .. msg)
end

--------------------------------------------------------------------------
-- Drawing
--
-- ns.Fill, ns.Pixel, ns.EdgeSize, ns.Outline and ns.Recolor live in UI/Draw.lua
-- and UI/Pixel.lua, which load between this file and Core/Panel.lua. They were
-- here until the pixel grid arrived and turned twenty lines into a layer with
-- its own scale arithmetic, resolution watcher and font cache. The names on ns
-- are unchanged, so nothing that draws had to move with them.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Which client this is
--
-- The addon ships one TOC per flavour and runs on both: 20506 is TBC
-- Anniversary, 11509 is Classic Era. Read the interface number rather than a
-- product string, because the number is what the TOC already declares and it
-- is what actually gates the API surface. Anything under 20000 is vanilla.
--------------------------------------------------------------------------

ns.interface = select(4, GetBuildInfo()) or 0
ns.vanilla = ns.interface > 0 and ns.interface < 20000

--------------------------------------------------------------------------
-- Which class this is
--
-- Not here. ns.Class in Class\Class.lua owns the question and the registry of
-- what each class brought with it, and Class\<name>.lua holds the facts. Core
-- knew it was a warrior addon for as long as this file answered that question,
-- which is exactly the coupling the registry above exists to refuse.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- API shims
--
-- 2.5.6 still has the old globals, but the C_Spell namespace is what newer
-- builds keep. Resolve once here so the modules never care which one exists.
--------------------------------------------------------------------------

local C_Spell = _G.C_Spell

-- Register an event filtered to one unit, on a client that can filter.
--
-- RegisterUnitEvent is the client saying "only call me about this unit", and
-- the ones that have it hand a UNIT_AURA handler a handful of events a fight
-- instead of every aura on every mob on the screen. A client without it has
-- one call and the handler has to check the token itself, which is why every
-- caller of this still reads the unit off the payload.
--
-- Six files wrote this two-branch registration out by hand before it moved
-- here, and each one wrote the comment above it too.
function ns.RegisterUnitEvent(frame, event, unit)
	if type(frame.RegisterUnitEvent) == "function" then
		frame:RegisterUnitEvent(event, unit)
	else
		frame:RegisterEvent(event)
	end
end

-- Vanilla has no threat API. Nothing in that client computes threat, which is
-- why every Classic threat meter parses the combat log instead. Resolved once
-- so a caller asks a question rather than calling a nil five times a second.
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation

function ns.HasThreat()
	return type(UnitDetailedThreatSituation) == "function"
end

-- isTanking, status, scaled percent. Nil all the way down on a client without
-- the API, which is a different answer from "no threat on this mob" and the
-- caller has to tell them apart, so ask ns.HasThreat first.
function ns.Threat(source, unit)
	if type(UnitDetailedThreatSituation) ~= "function" then
		return nil
	end
	return UnitDetailedThreatSituation(source, unit)
end

--------------------------------------------------------------------------
-- Incoming heals
--
-- What every heal in flight on a unit adds up to. It is the number that says
-- whether a health bar is about to fill itself or whether the only thing
-- coming is your own cooldown, and it is the one thing a warrior frame cannot
-- work out by looking at health.
--
-- Both clients register UnitGetIncomingHeals and both fire
-- UNIT_HEAL_PREDICTION, so this is a client API rather than the combat log
-- estimate every Classic healing addon has to build for itself. Probed all the
-- same, because nothing installed here calls it and that is the bar the rest of
-- this section is held to.
--------------------------------------------------------------------------

local UnitGetIncomingHeals = _G.UnitGetIncomingHeals

function ns.HasHealPrediction()
	return type(UnitGetIncomingHeals) == "function"
end

-- Nil where the client has no prediction at all, 0 where it has it and nothing
-- is on the way. The caller has to tell those apart the way it does with
-- threat: one is a feature that cannot run, the other is a quiet moment.
function ns.IncomingHeals(unit)
	if type(UnitGetIncomingHeals) ~= "function" then
		return nil
	end
	local amount = UnitGetIncomingHeals(unit)
	return type(amount) == "number" and amount or 0
end

--------------------------------------------------------------------------
-- What a unit is casting
--
-- The one thing an enemy nameplate says that health and threat do not: there
-- is a window open right now, and Pummel or Shield Bash closes it. Replacing
-- the plate took that away, which is the whole reason this is here.
--
-- Two calls, because the client has two and a unit is doing at most one of
-- them. UnitCastingInfo counts up to a finish, UnitChannelInfo counts down from
-- a start, and this asks for a cast and falls back to a channel so every caller
-- gets one answer with a flag saying which it was.
--
-- Confirmed rather than remembered, on the bar every other shim in this file is
-- held to. Details is installed on the Era client and its framework used to
-- route both of these through LibClassicCasterino, which is the combat log
-- estimator every vanilla cast bar was built on because vanilla answered only
-- for you. That branch is switched off in `Libs/DF/externals.lua` under the
-- comment "disable this for now, as it appears to be working now through API
-- changes", and what it falls back to is UnitCastingInfo and UnitChannelInfo
-- called unguarded. So both clients answer for a unit that is not you. Probed
-- all the same, because nothing installed here proves it for 2.5.6 and a
-- feature that silently draws nothing is the failure this addon keeps hitting.
--
-- The returns are read positionally, which is the thing this file exists to do
-- once rather than in a feature. Both calls open with name, text, texture,
-- start, finish, isTradeSkill. After that they differ by one slot: a cast
-- carries a castID and a channel does not, so notInterruptible is the eighth
-- return of one and the seventh of the other. Neither slot is trusted to hold
-- it. What comes back is type checked, the way ns.Upkeep.EnchantShape counts
-- the stride between two weapon enchants rather than assuming it, and a client
-- that puts something else there is a client that does not say.
--------------------------------------------------------------------------

local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo

-- The cast half only, because that is the half a feature cannot do without.
-- The channel call is probed separately inside ns.CastingInfo: a client that
-- answered one and not the other would draw every cast and miss every channel,
-- which is most of the feature rather than none of it, and is not a reason to
-- report the whole thing absent.
function ns.HasCastInfo()
	return type(UnitCastingInfo) == "function"
end

-- nil until a cast has been read, false once one has been read and the client
-- left that slot empty, true once one has come back with the flag in it.
-- Reported and never inferred, the same as EnemyBars.CameraState: "this client
-- does not say" and "nothing has said yet" are two different answers and the
-- second one is not a claim.
local immuneKnown

function ns.CastImmuneKnown()
	return immuneKnown
end

-- The spell's name, when it started and when it ends in GetTime seconds,
-- whether it is a channel, and whether the client says it cannot be
-- interrupted. Nil for a unit doing neither, which is nearly every unit nearly
-- always, so the miss costs one call and one comparison.
--
-- The times come back in milliseconds on both calls and are divided here, for
-- the reason ns.SpellCastTime divides: a caller counting the client's
-- milliseconds against a GetTime in seconds draws a bar that is full from the
-- first frame and nothing about it looks wrong.
function ns.CastingInfo(unit)
	if type(UnitCastingInfo) ~= "function" then
		return nil
	end

	local channel = false
	local name, _, _, startMS, endMS, _, _, immune = UnitCastingInfo(unit)
	if not name and type(UnitChannelInfo) == "function" then
		channel = true
		name, _, _, startMS, endMS, _, immune = UnitChannelInfo(unit)
	end
	if not name or not startMS or not endMS then
		return nil
	end

	if type(immune) == "boolean" then
		immuneKnown = true
	else
		immune = nil
		if immuneKnown == nil then
			immuneKnown = false
		end
	end

	return name, startMS / 1000, endMS / 1000, channel, immune
end

--------------------------------------------------------------------------
-- Levels
--
-- What a mob is worth is a level question, and the client answers it in two
-- pieces: how far below you a mob can be and still pay XP, and whether it is
-- an elite. Resolved here with the other shims so the bars ask a question
-- rather than probe a global five times a second per mob.
--------------------------------------------------------------------------

local GetQuestGreenRange = _G.GetQuestGreenRange
local UnitClassification = _G.UnitClassification
local UnitIsTapDenied = _G.UnitIsTapDenied

-- How many levels below yours a mob can be and still pay XP. Questie calls
-- GetQuestGreenRange("player") unguarded on both clients, which is what proves
-- it is here, and the build that takes no argument ignores the one it is
-- handed. Nil rather than a guessed number when it is missing: a guess would
-- write "no XP" over a mob that still pays, and a wrong answer is worse than
-- none.
function ns.GreenRange()
	if type(GetQuestGreenRange) ~= "function" then
		return nil
	end
	local range = GetQuestGreenRange("player")
	return type(range) == "number" and range or nil
end

-- "worldboss", "rareelite", "elite", "rare", "normal" or "trivial", and nil on
-- a client without it. Nothing installed here calls UnitClassification, so it
-- is probed rather than trusted the way the confirmed APIs are. Losing it
-- costs the elite marker and leaves the level itself intact.
function ns.Classification(unit)
	if type(UnitClassification) ~= "function" then
		return nil
	end
	return UnitClassification(unit)
end

-- Whether somebody else got there first. A mob another player or group tagged
-- pays you no XP and no loot however high its level reads, which is the second
-- half of "is this kill worth anything" and the half no colour on this addon's
-- bars has ever carried.
--
-- Probed rather than trusted: it is Blizzard's own TargetFrame test on both
-- live clients, but nothing installed here calls it, so it takes the same road
-- as UnitClassification above. Nil rather than false when it is missing, so a
-- caller can tell "not tapped" from "cannot say" and refuse to write "worth
-- nothing" on a mob it never asked about.
function ns.TapDenied(unit)
	if type(UnitIsTapDenied) ~= "function" then
		return nil
	end
	return UnitIsTapDenied(unit) == true
end

function ns.SpellName(spell)
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spell)
		return info and info.name
	end
	return (_G.GetSpellInfo(spell))
end

-- The same answer, held after the first time the client gives one.
--
-- ns.SpellName goes through C_Spell.GetSpellInfo where that exists, and that
-- call builds a table to put the string in. The action bars ask what a square
-- is holding on every square on every tick, so asked directly it is twenty-four
-- throwaway tables ten times a second, which is the shape check.sh's allocation
-- gate exists to refuse. Asked through here it allocates once per spell the
-- bars have ever held and never again.
--
-- A spell id names one spell forever, so there is nothing to invalidate. What
-- it holds is the client's own name in the language the client is running in,
-- which is what every match in this addon compares against another of the same.
--
-- A client that has not answered is not written down. A nil held here before
-- the spell data arrived would be the answer for the rest of the session, which
-- is the same bug Buttons/Reaction.lua's own memo guards against and the reason
-- both guard on nil rather than on false.
local nameOf = {}

function ns.SpellNameHeld(spell)
	local held = nameOf[spell]
	if held then
		return held
	end
	local name = ns.SpellName(spell)
	if name then
		nameOf[spell] = name
	end
	return name
end

-- How long the client says that spell takes to cast, in seconds. Zero for an
-- instant, and zero where the client will not say, because every caller of
-- this branches the same way on a nil and the branch is worth writing once.
--
-- The client counts in milliseconds on both sides of the shim. It is the
-- fourth return of the old global and the castTime field of the new table, and
-- the fourth return is the reason this exists at all: a select(4) sitting in a
-- feature file is a positional read of an API the addon otherwise never reads
-- positionally.
function ns.SpellCastTime(spell)
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spell)
		return (info and info.castTime or 0) / 1000
	end
	local castTime = select(4, _G.GetSpellInfo(spell))
	return (castTime or 0) / 1000
end

function ns.SpellTexture(spell)
	if C_Spell and C_Spell.GetSpellTexture then
		return C_Spell.GetSpellTexture(spell)
	end
	return _G.GetSpellTexture(spell)
end

-- The same path, held after the first time the client gives one.
--
-- ns.SpellNameHeld above holds a name for the reason the action bars ask for
-- one on every square on every tick. This holds a path for the reason the
-- combat feed asks for one on every hit you deal or take: in a pull that is a
-- lookup into the client's spell data a few dozen times a second, and the
-- answer for a given spell was decided when the client shipped.
--
-- The same guard on nil as the name cache, and the same reason. A spell asked
-- about before the client has the data for it answers nothing, and a nothing
-- written down here would be the icon for the rest of the session.
local iconOf = {}

function ns.SpellTextureHeld(spell)
	local held = iconOf[spell]
	if held then
		return held
	end
	local path = ns.SpellTexture(spell)
	if path then
		iconOf[spell] = path
	end
	return path
end

function ns.SpellCooldown(spell)
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(spell)
		if not info then
			return 0, 0, true
		end
		return info.startTime, info.duration, info.isEnabled
	end
	local start, duration, enabled = _G.GetSpellCooldown(spell)
	return start or 0, duration or 0, enabled ~= 0
end

-- Put a spell on the cursor, and say whether it went.
--
-- PickupSpell has taken more than one shape across clients: it answers to a
-- name on one and to an id on the other, and nothing installed on this machine
-- proves which 2.5.6 is. So both are tried, cheapest first, and the cursor is
-- read back rather than trusted. A pickup that came up empty and was believed
-- is the bug this shape exists to make impossible: whatever the cursor was
-- holding before then gets dropped wherever the caller drops it.
--
-- Buttons/Layout.lua wraps this in a probe that names which call a client is
-- missing, because a loadout that cannot be written has to say why. A caller
-- that only wants the picture under the cursor asks here.
function ns.CarrySpell(spell)
	if type(_G.PickupSpell) ~= "function" or type(_G.GetCursorInfo) ~= "function"
		or type(_G.ClearCursor) ~= "function" then
		return false
	end

	ClearCursor()
	if pcall(PickupSpell, spell) and GetCursorInfo() then
		return true
	end

	-- The other spelling of the same spell. An id for a name and a name for an
	-- id, so a client that takes only one of the two is still answered.
	local other
	if type(spell) == "number" then
		other = ns.SpellName(spell)
	else
		other = select(7, _G.GetSpellInfo(spell))
	end

	ClearCursor()
	if other and pcall(PickupSpell, other) and GetCursorInfo() then
		return true
	end

	ClearCursor()
	return false
end

-- Which spell is on the cursor, as an id, off the three values GetCursorInfo
-- hands back after the kind.
--
-- Three readings, the same three Hover/Hover.lua takes for a name and for the
-- same reason: this client answers a dragged spell with a spellbook index and
-- the book it came out of, newer builds put the id in a fourth slot, and
-- nothing installed on this machine proves which of those 2.5.6 hands back.
--
-- The book reading goes through GetSpellBookItemInfo, which is where
-- Buttons/Ranks.lua reads its own ids from. The bare first value is tried last
-- and only where the second is not a book: a spellbook index is a small number
-- and every small number names some spell, so that reading taken first would
-- put Charge on a row for anything dragged out of the top of the book.
--
-- Here rather than in the page that first wrote it, because the cooldown row
-- and the buff row both take a spell off the cursor and a third copy of three
-- guarded readings is the shape a probe takes on the way to being everywhere.
function ns.SpellIdOnCursor(a, b, c)
	if type(c) == "number" and ns.SpellName(c) then
		return c
	end

	if type(a) == "number" and type(b) == "string"
		and type(_G.GetSpellBookItemInfo) == "function" then
		local ok, kind, id = pcall(_G.GetSpellBookItemInfo, a, b)
		if ok and kind == "SPELL" and type(id) == "number" then
			return id
		end
	end

	if type(a) == "number" and type(b) ~= "string" and ns.SpellName(a) then
		return a
	end
	return nil
end

-- The frame the client says the cursor is over, and the name of the call that
-- answered it.
--
-- Two names, because this client is a hybrid and neither can be assumed.
-- GetMouseFocus is the call every client from vanilla to Dragonflight had;
-- GetMouseFoci replaced it and answers the whole stack under the cursor,
-- topmost first. Buttons/Trace.lua found that out the expensive way: its first
-- live run printed every gesture and never once named a frame, which from the
-- chat frame looks exactly like a cursor that touched nothing rather than a
-- client with no such call.
--
-- The name comes back as well as the frame, because a part that cannot get an
-- answer has to be able to say which call it is missing rather than going
-- quiet. Cooldowns/Panel.lua is the second caller and it is not a diagnostic: a
-- square whose contents will not go on the cursor is dropped wherever the
-- button came up, and this is the only thing that says where that was.
function ns.MouseFocus()
	if type(_G.GetMouseFocus) == "function" then
		return GetMouseFocus(), "GetMouseFocus"
	end
	if type(_G.GetMouseFoci) == "function" then
		local stack = GetMouseFoci()
		if type(stack) == "table" then
			return stack[1], "GetMouseFoci"
		end
		return stack, "GetMouseFoci"
	end
	return nil, nil
end

-- Returns usable, and whether the block is rage rather than anything else.
function ns.SpellUsable(spell)
	if C_Spell and C_Spell.IsSpellUsable then
		return C_Spell.IsSpellUsable(spell)
	end
	return _G.IsUsableSpell(spell)
end

-- Whether a spell is aimed at an enemy, or nil for a client that cannot say.
--
-- The one fact IsUsableAction does not hold. It knows your mana, your stance
-- and your gear and nothing about the target, so a Flame Shock in an inn with
-- nothing selected reads as pressable. Buttons/Slot.lua asks this of a macro's
-- spell for the reason it asks ns.SpellUsable of one, and asks the slot's own
-- call for a plain spell. Nil rather than false where neither call exists,
-- because "cannot say" must not grey a square and "not harmful" must not
-- either, and only one of those is a fact about the spell.
function ns.SpellHarmful(spell)
	if C_Spell and C_Spell.IsSpellHarmful then
		return C_Spell.IsSpellHarmful(spell)
	end
	if type(_G.IsHarmfulSpell) == "function" then
		return _G.IsHarmfulSpell(spell)
	end
	return nil
end

-- One of your own buffs, by slot, as the name alone.
--
-- UnitAura is asked first and C_UnitAuras second, which is the opposite way
-- round from the spell shims above and is deliberate: the old call hands back a
-- string and the new one hands back a table it built to put the string in.
-- Every caller of this wants the string. Where only the new call exists the
-- table is made and dropped, which is the cost of that client.
--
-- Nil at the first empty slot, which is how both callers know to stop walking.
-- Buffs/Upkeep.lua asks what is missing and Cooldowns/Cooldowns.lua asks which
-- burst window is open, and both walk the same list for the same string.
function ns.BuffName(unit, index)
	if type(_G.UnitAura) == "function" then
		return (_G.UnitAura(unit, index, "HELPFUL"))
	end
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		local aura = C_UnitAuras.GetBuffDataByIndex(unit, index)
		return aura and aura.name
	end
	return nil
end

-- Every buff on you, as a set of names, walked once per change rather than once
-- per reader.
--
-- Two parts ask this and both ask it on the same event. Buffs/Upkeep.lua asks
-- what is missing and Cooldowns/Cooldowns.lua asks which burst window is open,
-- and each walked forty slots of its own on every UNIT_AURA: eighty lookups to
-- read one list twice. Neither may call the other, and neither is the natural
-- owner of a list that is not about buffs it watches, so the walk is here with
-- the rest of the shims and the answer is a set the callers key into. What a
-- name means is still their business; this knows nothing but what is on you.
--
-- Walked on the first ask after an aura moved and read out of the table every
-- time after that. The frame below registers UNIT_AURA before any feature does,
-- because Core is the first file in both TOCs and the client hands an event to
-- its frames in the order they asked for it, so the mark is already set by the
-- time a feature's own handler runs.
--
-- Forty slots, which is the number every aura scan in the game stops at.
local BUFF_SLOTS = 40

local onMe = {}
local buffsMoved = true

function ns.MyBuffs()
	if not buffsMoved then
		return onMe
	end
	buffsMoved = false
	for name in pairs(onMe) do
		onMe[name] = nil
	end
	local index = 1
	while index <= BUFF_SLOTS do
		local name = ns.BuffName("player", index)
		if not name then
			break
		end
		onMe[name] = true
		index = index + 1
	end
	return onMe
end

local function BuffsMoved()
	buffsMoved = true
end

local auras = CreateFrame("Frame")
ns.RegisterUnitEvent(auras, "UNIT_AURA", "player")
auras:SetScript("OnEvent", BuffsMoved)

-- Returns 1 in range, 0 out of range, nil when the check does not apply.
function ns.SpellInRange(spell, unit)
	if C_Spell and C_Spell.IsSpellInRange then
		local inRange = C_Spell.IsSpellInRange(spell, unit)
		if inRange == nil then
			return nil
		end
		return inRange and 1 or 0
	end
	return _G.IsSpellInRange(spell, unit)
end

-- Whether a range answer definitely blocks. Takes what IsSpellInRange or
-- IsActionInRange handed back, which is 1, 0 or nil.
--
-- Only a definite 0 blocks. Both calls answer nil for a great many honest
-- reasons: the spell has no range, the unit cannot take it, the client has not
-- decided yet. Treating nil as out of range would pin every square in the
-- addon red, and treating it as in range silently would hide a client that
-- never answers at all, which is a real state on 2.5.6 and is worth knowing
-- once. So the nils are counted and the fortieth one says so, once, for the
-- session.
--
-- Shared rather than kept in whichever file needed it first. Charge/Charge.lua
-- had this counter and Buttons/Slot.lua needs the identical one, and two
-- copies means two thresholds and two chances to print the sentence twice.
local rangeAnswered, rangeSilent = false, 0
local RANGE_PATIENCE = 40

function ns.OutOfRange(answer)
	if answer == nil then
		rangeSilent = rangeSilent + 1
		if not rangeAnswered and rangeSilent == RANGE_PATIENCE then
			ns.Print("this client is not answering range checks, so out-of-range targets cannot be dimmed.")
		end
		return false
	end
	rangeAnswered = true
	return answer == 0
end

----------------------------------------------------------------------------
-- Questie
--
-- Every question this addon asks Questie goes through one door, and it is
-- here. Five files wrote that door out by hand, four of them character for
-- character, and one handed its copy back out as Where.Module so a sixth could
-- borrow it. Questie is not the client, so this is not an API shim: it is the
-- one place that knows another addon's loader by name.
--
-- The rule that keeps it one place is in scripts/check.sh. Outside this file,
-- naming QuestieLoader fails the gate.
--------------------------------------------------------------------------

-- One of Questie's modules, or nil, asked for by the calls you mean to make.
--
-- ImportModule hands back a fresh empty table for a name it has never heard of
-- rather than nil, so the module coming back proves nothing at all. What proves
-- it is the calls being on it, which is why they are arguments: ask for
-- QuestieDB and a table comes back on a client with no Questie, ask for
-- QuestieDB with QueryItemSingle on it and nil means what it says.
--
-- Functions only, deliberately. A data field like currentQuestlog is filled in
-- after login rather than at load, so refusing the module over one would report
-- a missing Questie for a quest log that is merely not built yet. A caller that
-- reads a field checks that field itself, next to the read.
--
-- Nothing is cached, for the reason EditMode.CanApply is not: the database is
-- compiled minutes after login and an answer taken too early would be wrong for
-- the rest of the session.
function ns.Questie(name, ...)
	local loader = _G.QuestieLoader
	if not loader or type(loader.ImportModule) ~= "function" then
		return nil
	end
	local ok, module = pcall(loader.ImportModule, loader, name)
	if not ok or type(module) ~= "table" then
		return nil
	end
	for i = 1, select("#", ...) do
		if type(module[(select(i, ...))]) ~= "function" then
			return nil
		end
	end
	return module
end

------------------------------------------------------------------------
-- Money
--
-- One number turned into the shortest true reading of it, which is the shape
-- ns.ItemInfo has: arithmetic over a client value, no state, no setting, and no
-- feature's name anywhere in it.
--
-- It was Feeds/Purse.lua's, private to the loot feed's status strip, until the
-- mail window needed to say what postage costs and what is riding on a letter.
-- A part may not name a file outside its own folder, and the two honest ways
-- out of that are a second formatter or this one; a second formatter is a
-- second set of rounding rules, and gold that reads two different ways in two
-- windows of the same addon is worse than either rule.
--
-- GetCoinText is the client's own and is not what this replaces. It answers
-- "1 Gold 20 Silver 5 Copper", which is forty glyphs where a status strip has
-- room for eight.
--------------------------------------------------------------------------

local GOLD, SILVER = 10000, 100

-- Past this the silver is noise. A five figure purse reading "12,405g 63s"
-- spends four glyphs on the part that changes when you buy a drink.
local COARSE = 100

-- 1234567 as 1,234,567. A loop rather than one pattern because Lua 5.1 has no
-- lookahead, so the groups have to go in from the right one pass at a time.
--
-- Called Thousands rather than Group, which is what it was called while it was
-- private to Feeds/Purse.lua. ns.Group is the party and raid block's namespace,
-- and a shared name has to be the name of what it does rather than the shortest
-- word that fits: the collision was silent, it made ns.Group a function for the
-- length of one file's load and a table afterwards, and the only symptom was
-- the gold-an-hour cell raising once a second.
local function Thousands(number)
	local text = tostring(number)
	local runs = 1
	while runs > 0 do
		text, runs = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	end
	return text
end

ns.Thousands = Thousands

-- Which denominations a number is worth writing in, as a flat run of amount and
-- letter, amount and letter.
--
-- The rounding is the decision and there are two ways of writing the answer
-- down, plain for a line of prose and coloured for a purse, so the decision is
-- made once here and the writing is somebody else's argument. Before this the
-- two would have been two functions with the same thresholds in both, which is
-- the drift ns.Coin was moved into Core to stop.
--
-- Short is gold alone once there is real gold, gold and silver under a hundred
-- where the silver is the part that moves, and the whole three when there is no
-- gold at all, which is the only time copper is worth a glyph.
--
-- Exact is all of it, and it is what a hover gets: the width is there, and the
-- copper is the digit that proves the figure is a real reading rather than a
-- rounded one. Silver and copper are padded to two digits so a column of them
-- lines up, which is the whole reason the column is readable at a glance.
--
-- Written into a scratch table rather than a fresh one, because the status
-- strip asks this every time a coin moves.
local coins = {}

local function Push(amount, letter)
	coins[#coins + 1] = tostring(amount)
	coins[#coins + 1] = letter
end

local function Parts(copper, exact)
	for index = #coins, 1, -1 do
		coins[index] = nil
	end

	local gold = math.floor(copper / GOLD)
	local silver = math.floor(copper % GOLD / SILVER)
	if exact then
		if gold > 0 then
			Push(Thousands(gold), "g")
		end
		Push(("%02d"):format(silver), "s")
		Push(("%02d"):format(copper % SILVER), "c")
	elseif gold >= COARSE then
		Push(Thousands(gold), "g")
	elseif gold > 0 then
		Push(gold, "g")
		Push(silver, "s")
	else
		Push(silver, "s")
		Push(copper % SILVER, "c")
	end
	return coins
end

-- One reading, in whichever hand `paint` writes.
--
-- The sign is carried rather than dropped: this formats a rate as well as a
-- purse, and an hour that cost you money has to read as one. It sits outside
-- the colour, because a minus in front of a gold figure is a fact about the
-- whole number and not about the gold.
local function Spell(copper, exact, paint)
	copper = math.floor(tonumber(copper) or 0)
	local sign = ""
	if copper < 0 then
		sign, copper = "-", -copper
	end

	local text = sign
	local written = Parts(copper, exact)
	for index = 1, #written, 2 do
		if index > 1 then
			text = text .. " "
		end
		text = text .. paint(written[index], written[index + 1]) -- allocates: one join per denomination in one reading, and every caller compares the copper figure before it asks for the words
	end
	return text
end

local function Plain(amount, letter)
	return amount .. letter
end

-- The three denominations in the coin colours the game itself uses, as escapes
-- rather than as one of UI/Theme.lua's tables: this is text inside a font
-- string, and Core sits under the interface layer rather than over it.
--
-- Colour is not decoration on a purse. "109g 07s 91c" in one colour has to be
-- read left to right before you know which part of it is the part you cared
-- about; in three, the gold is what your eye lands on and the rest is texture
-- you read only when you want it. Titan Panel has done this for fifteen years
-- and it is the only reason its purse looks alive next to a row of grey digits.
local COIN = {
	g = "|cffffd700",
	s = "|cffc7c7cf",
	c = "|cffeda55f",
}

local function Painted(amount, letter)
	return COIN[letter] .. amount .. letter .. "|r"
end

-- Copper as the shortest true thing, in one colour.
function ns.Coin(copper)
	return Spell(copper, false, Plain)
end

-- The same number with each denomination in its own colour, and with all three
-- of them when `exact` is asked for.
function ns.Coined(copper, exact)
	return Spell(copper, exact, Painted)
end

-- The same number as its three parts, for a window that puts a field under each
-- of them. The inverse is a multiply at the call site and needs nothing here.
function ns.Coins(copper)
	copper = math.max(0, math.floor(tonumber(copper) or 0))
	return math.floor(copper / GOLD),
		math.floor(copper % GOLD / SILVER),
		copper % SILVER
end

-- The same number written out in all three denominations, "0g 20s 0c". It is
-- the shape a field you type a floor into shows, because ns.Coin drops the
-- parts that are nought and ns.Coined colours them, and neither is what an
-- edit box wants under the cursor: a field that shows "20s" teaches nobody
-- that "1g 20s" is also an answer.
function ns.CoinSpelt(copper)
	local gold, silver, rest = ns.Coins(copper)
	return ("%dg %ds %dc"):format(gold, silver, rest)
end

-- The inverse. "0g 20s 0c", "1g 20s", "20s" and "1g5s" are all a sum, and a
-- bare number is copper, which is what ns.Coin prints for one. Nil for
-- anything that is not a sum of money, so a caller keeps the number it had
-- rather than writing nought over it because somebody typed a word.
function ns.Uncoin(text)
	if type(text) ~= "string" then
		return nil
	end
	local rest = (text:lower():gsub("%s+", ""))
	if rest == "" then
		return nil
	end
	if rest:match("^%d+$") then
		return tonumber(rest)
	end
	local total = 0
	for amount, letter in rest:gmatch("(%d+)([gsc])") do
		local unit = 1
		if letter == "g" then
			unit = GOLD
		elseif letter == "s" then
			unit = SILVER
		end
		total = total + tonumber(amount) * unit
	end
	if (rest:gsub("%d+[gsc]", "")) ~= "" then
		return nil
	end
	return total
end

ns.GOLD, ns.SILVER = GOLD, SILVER

--------------------------------------------------------------------------
-- Items
--
-- Two clients, two container APIs. Era backported C_Container and 2.5.6 may or
-- may not carry it, so both are probed and a client with neither answers empty
-- rather than erroring: a picker with nothing in it is a worse UI, not a
-- broken addon.
--------------------------------------------------------------------------

local C_Container = _G.C_Container

-- Newer builds moved the item lookups into C_Item and kept the old globals
-- working. Resolved here beside C_Container so ns.ItemValue asks one question
-- rather than probing two namespaces per bag slot per tick.
local C_Item = _G.C_Item

function ns.ContainerSlots(bag)
	if C_Container and C_Container.GetContainerNumSlots then
		return C_Container.GetContainerNumSlots(bag) or 0
	end
	if type(_G.GetContainerNumSlots) == "function" then
		return _G.GetContainerNumSlots(bag) or 0
	end
	return 0
end

function ns.ContainerItemLink(bag, slot)
	if C_Container and C_Container.GetContainerItemLink then
		return C_Container.GetContainerItemLink(bag, slot)
	end
	if type(_G.GetContainerItemLink) == "function" then
		return _G.GetContainerItemLink(bag, slot)
	end
	return nil
end

-- How many are in a bag slot and whether the client has it locked, which is
-- what a sale in flight looks like from the outside. Multiple returns rather
-- than a table, because the vendor sweep asks this once per slot per tick and
-- a table per slot is garbage the collector walks in the middle of a frame.
--
-- C_Container answers one table with named fields and the old global answers
-- eleven values in a fixed order; both are read here so no caller has to know
-- which client it is on.
function ns.ContainerItem(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if not info then
			return nil
		end
		return info.stackCount, info.isLocked
	end
	if type(_G.GetContainerItemInfo) == "function" then
		local _, count, locked = _G.GetContainerItemInfo(bag, slot)
		return count, locked
	end
	return nil
end

-- Use what is in a bag slot, which means whatever the window in front of you
-- says it means. At a merchant it sells it. With the send-mail pane flagged as
-- showing it attaches it to the letter. Anywhere else it eats, equips or opens
-- the thing, which is why every caller has to prove which of the three it is in
-- before it calls this. False where the client has neither API, so a caller can
-- say so rather than believe a sale or an attach happened.
function ns.UseContainerItem(bag, slot)
	if C_Container and C_Container.UseContainerItem then
		C_Container.UseContainerItem(bag, slot)
		return true
	end
	if type(_G.UseContainerItem) == "function" then
		_G.UseContainerItem(bag, slot)
		return true
	end
	return false
end

-- Put what is in a bag slot on the cursor. Two callers, and they want opposite
-- halves of it: the clutter window picks an item up so it can ask the cursor
-- what it is really holding before destroying it, and the bag window's stacking
-- sweep calls it twice, once on each of two slots, which is how the client is
-- asked to put two half stacks together. False where the client has neither API,
-- so a caller stops rather than carrying on to a delete it cannot aim or
-- counting a move that never happened.
function ns.PickupContainerItem(bag, slot)
	if C_Container and C_Container.PickupContainerItem then
		C_Container.PickupContainerItem(bag, slot)
		return true
	end
	if type(_G.PickupContainerItem) == "function" then
		_G.PickupContainerItem(bag, slot)
		return true
	end
	return false
end

-- Part of what is in a bag slot onto the cursor, and the rest left where it is.
-- One caller, and it is the one call in the addon that has to be exact about a
-- number rather than about a slot. What Comfort/Leftovers.lua destroys is the
-- count that arrived off a corpse, and the stack it arrived into is usually
-- holding what you were already carrying as well, so picking the slot up whole
-- would delete both. False where the client has neither API, so the caller
-- stops rather than reaching for a delete aimed at more than it meant.
function ns.SplitContainerItem(bag, slot, amount)
	if C_Container and C_Container.SplitContainerItem then
		C_Container.SplitContainerItem(bag, slot, amount)
		return true
	end
	if type(_G.SplitContainerItem) == "function" then
		_G.SplitContainerItem(bag, slot, amount)
		return true
	end
	return false
end

-- Whatever is on the cursor into the first bag with room for it. True once it
-- has landed, false while it is still on the cursor.
--
-- The client's own mechanism, not a search for a free slot. Dropping an item on
-- the backpack button on the bar is `PutItemInBackpack`, and on one of the four
-- bag buttons beside it is `PutItemInBag` with the bag's inventory id, which is
-- what the client's BackpackButton_OnClick and BagSlotButton_OnClick call and
-- therefore the call it is written to accept from a hardware click. Both leave
-- the item on the cursor when the bag has no room or will not take it, an
-- ammo pouch offered a sword, so each is followed by a look at the cursor and
-- the next bag is tried while it is still full. A free slot found by hand and
-- filled with PickupContainerItem would have to know the bag families itself.
--
-- Only ever an item. Money, a spell or a macro on the cursor is nothing a bag
-- takes, and the window's drop asks this before anything else so a click on
-- it with a spell in hand is a click on the window.
--
-- Every call is probed and pcalled, like every other loose global this file
-- reaches for: nothing installed here proves either exists on 2.5.6, and a bag
-- window with no way to swallow a drop is still a bag window.
function ns.Stow()
	if type(_G.GetCursorInfo) ~= "function" or _G.GetCursorInfo() ~= "item" then
		return false
	end
	if type(_G.PutItemInBackpack) == "function" then
		pcall(_G.PutItemInBackpack)
	end
	if not _G.GetCursorInfo() then
		return true
	end
	local numbered = C_Container and C_Container.ContainerIDToInventoryID
		or _G.ContainerIDToInventoryID
	if type(_G.PutItemInBag) ~= "function" or type(numbered) ~= "function" then
		return false
	end
	for bag = 1, _G.NUM_BAG_SLOTS or 4 do
		local ok, id = pcall(numbered, bag)
		if ok and id then
			pcall(_G.PutItemInBag, id)
		end
		if not _G.GetCursorInfo() then
			return true
		end
	end
	return false
end

-- Name, icon, equip location and the link's own colour code, for an item link.
--
-- The name and the colour are read out of the link rather than asked for,
-- because the link is text the client already handed over and needs no cache
-- behind it. GetItemInfo answers nil for an item the client has not cached
-- yet, which for something sitting in your own bags is rare and not
-- impossible, so GetItemInfoInstant is preferred where it exists: it reads the
-- client's own item database and cannot miss.
--
-- Both lookups go through C_Item first, the same as ns.ItemValue and
-- ns.ItemKind below. This function did not, and that was the loot feed drawing
-- a question mark on every row: the newer client moved the item lookups into
-- C_Item and took the loose globals away, so the icon came back nil while the
-- quality colour and the quest ring, which are the two functions underneath
-- this one, went on working. A missing global here is not a client that cannot
-- answer, it is a client that was asked in the wrong place.
--
-- The fallback is on the icon rather than the equip location. Both callers
-- that read the location can do without it and no caller can do without the
-- picture, and an item with nowhere to equip it answers "" rather than nil,
-- which is a value that reads as an answer and stopped the second lookup ever
-- running for a stack of cloth.
function ns.ItemInfo(link)
	if type(link) ~= "string" then
		return nil
	end

	local name = link:match("%[(.-)%]")
	local color = link:match("|c(%x%x%x%x%x%x%x%x)")
	local equip, icon

	local instant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
	if type(instant) == "function" then
		local _, _, _, loc, texture = instant(link)
		equip, icon = loc, texture
	end

	local cached = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if not icon and type(cached) == "function" then
		local _, _, _, _, _, _, _, _, loc, texture = cached(link)
		equip = equip or loc
		icon = texture
	end

	return name, icon, equip, color
end

-- The name of an item's use effect, or nil for an item that has none.
--
-- This is what tells a trinket you press from a trinket you wear. The client
-- answers a spell name for the first and nothing at all for the second, which
-- is a better test than a cooldown reading: a passive trinket with a proc on it
-- carries a cooldown too, and a square for a cooldown you cannot spend is a
-- square that says press me about nothing.
function ns.ItemSpell(link)
	if type(link) ~= "string" then
		return nil
	end
	local lookup = (C_Item and C_Item.GetItemSpell) or _G.GetItemSpell
	if type(lookup) ~= "function" then
		return nil
	end
	return (lookup(link))
end

-- What a worn item's own cooldown reads, by inventory slot, in the three values
-- ns.SpellCooldown answers in. Zeroes where the client has no such call, which
-- reads as ready and is the honest answer: an addon that cannot ask has nothing
-- to say about a trinket's cooldown.
--
-- Probed rather than trusted, the same as UnitRace in Buffs/Racials.lua.
-- Nothing installed here calls it unguarded and a nil call on a ticker is what
-- gets the whole addon offered up for disabling.
function ns.InventoryCooldown(slot)
	local lookup = _G.GetInventoryItemCooldown
	if type(lookup) ~= "function" then
		return 0, 0, false
	end
	local start, duration, enabled = lookup("player", slot)
	return start or 0, duration or 0, enabled ~= 0
end

-- Quality and what a vendor pays, for an item link. Quality is the number the
-- client grades an item on, 0 being the grey a vendor exists to take off you.
--
-- Nil where the client has not cached the item yet, and a caller has to treat
-- that as "do not know" rather than as zero. Selling on a guessed quality is
-- how something that is not trash ends up at a vendor, so the vendor sweep
-- leaves an item it cannot grade alone and asks again on its next pass, by
-- which point the client has answered.
function ns.ItemValue(link)
	if type(link) ~= "string" then
		return nil
	end

	local lookup = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if type(lookup) ~= "function" then
		return nil
	end

	local _, _, quality, _, _, _, _, _, _, _, sellPrice = lookup(link)
	if type(quality) ~= "number" then
		return nil
	end
	return quality, sellPrice or 0
end

-- What the item is worth as a number, which is the fourth thing GetItemInfo
-- answers and the only one of the four the two lookups above do not already
-- carry between them.
--
-- Beside ns.ItemValue rather than folded into it, because the two are asked at
-- different moments about different things. A sell price is read for every grey
-- in your bags on a vendor sweep; an item level is read for the eighteen things
-- you are wearing when a window opens. Adding a return to the other would make
-- every caller of it carry a value it has no use for.
--
-- Nil where the client has not cached the item, which is the same answer
-- ns.ItemValue gives and has to be treated the same way: an average taken over
-- a piece the client would not price is an average of the wrong number of
-- pieces.
function ns.ItemLevel(link)
	if type(link) ~= "string" then
		return nil
	end

	local lookup = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if type(lookup) ~= "function" then
		return nil
	end

	local _, _, _, level = lookup(link)
	if type(level) ~= "number" then
		return nil
	end
	return level
end

-- What level you have to be to put the thing on.
--
-- The fifth thing GetItemInfo answers, and the one number that says an item is
-- behind you rather than merely cheap. A level twenty green in the bags of a
-- level sixty two character is not going to be worn again, and no other value
-- the client hands back says so: the item level is close to it but is not the
-- same number, and quality says nothing at all.
--
-- Zero is a real answer and it is not nil: plenty of low items carry no
-- requirement. The caller has to read it beside the item level rather than on
-- its own, because a requirement of nought on something the client rates at
-- eighty is a thing you keep.
--
-- Nil is an item the client has not cached, which every caller in this addon
-- treats the same way ns.ItemValue's nil is treated: leave the item alone and
-- ask again on the next pass.
function ns.ItemNeeds(link)
	if type(link) ~= "string" then
		return nil
	end

	local lookup = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if type(lookup) ~= "function" then
		return nil
	end

	local needs = select(5, lookup(link))
	if type(needs) ~= "number" then
		return nil
	end
	return needs
end

-- How many of an item one bag slot will hold.
--
-- The eighth thing GetItemInfo answers, and the number the stacking sweep is
-- built on: a slot holding fewer than this is a partial stack and two partials
-- of the same item are one drag away from being one stack and some free space.
--
-- Beside ns.ItemLevel rather than folded into ns.ItemValue, for the reason that
-- one gives: the two are asked at different moments about different things, and
-- a sell price read for every grey in your bags does not want a stack size
-- riding along with it.
--
-- One is the answer for everything that does not stack, and nil is an item the
-- client has not cached, which the sweep has to treat as "ask again" rather
-- than as "does not stack". Guessing one there is a partial stack left behind
-- with nothing to say why.
function ns.ItemStack(link)
	if type(link) ~= "string" then
		return nil
	end

	local lookup = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if type(lookup) ~= "function" then
		return nil
	end

	local stack = select(8, lookup(link))
	if type(stack) ~= "number" then
		return nil
	end
	return stack
end

-- The item's id, and the class and subclass the client files it under. Class 12
-- is a quest item, which is the one the clutter scan turns on, and Baganator
-- categorises on the same number on this client.
--
-- GetItemInfoInstant rather than GetItemInfo, because this reads the client's
-- own item database and cannot miss the way a cache lookup can. That matters
-- here more than it does for a sell price: an item whose class came back nil
-- would be an item the scan silently never considered.
function ns.ItemKind(link)
	if type(link) ~= "string" then
		return nil
	end

	local lookup = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
	if type(lookup) ~= "function" then
		return nil
	end

	local itemId, _, _, _, _, classId, subClassId = lookup(link)
	if type(itemId) ~= "number" then
		return nil
	end
	return itemId, classId, subClassId
end

-- What a loot slot is holding: the word "item", "money" or "currency", and the
-- item's link where there is one.
--
-- GetLootSlotType is the client's own answer and it is not on every build this
-- addon ships to. Where it is missing the same fact is read off the link, which
-- both builds carry: a slot the client will hand no link for is the coins.
--
-- Here rather than in the part that asks, for the reason every other shim in
-- this file is here: which of the two calls a build answers is a fact about the
-- build and not about the feature, and a part does not probe the client for a
-- call it means to make.
local LOOT_MONEY, LOOT_CURRENCY = 2, 3

function ns.LootKind(slot)
	local read = _G.GetLootSlotLink
	local link = type(read) == "function" and read(slot) or nil

	local kind = _G.GetLootSlotType
	if type(kind) == "function" then
		local answer = kind(slot)
		if answer == LOOT_MONEY then
			return "money", nil
		end
		if answer == LOOT_CURRENCY then
			return "currency", link
		end
		return "item", link
	end

	return link and "item" or "money", link
end

--------------------------------------------------------------------------
-- The merchant
--
-- What the vendor in front of you has, asked once. Five calls, and the reason
-- they are here rather than in the part that draws them is the reason every
-- other shim in this file is here: a part may not probe the client for a call
-- it means to make, because the answer is a fact about the build and not about
-- the feature.
--
-- The one real difference between clients is in the returns of
-- GetMerchantItemInfo. Both clients this addon ships to answer seven values
-- with isUsable sixth and extendedCost seventh. A client that answers ten put
-- isPurchasable in at six and pushed the other two down one, so the count is
-- read rather than assumed and the caller gets the same seven either way.
--
-- `available` is handed back exactly as the client gives it, which means -1 for
-- a vendor with an endless supply. Turning that into a number would be this
-- file deciding what "how many are left" means, and the two windows that ask
-- want different things from it.
--------------------------------------------------------------------------

local function Merchandise(...)
	local name, icon, price, quantity, available = ...
	if select("#", ...) >= 10 then
		return name, icon, price, quantity, available, (select(7, ...)), (select(8, ...))
	end
	return name, icon, price, quantity, available, (select(6, ...)), (select(7, ...))
end

-- How many things this vendor has. Nought where the client has no such call
-- and nought where you are not standing at one, which read the same and should:
-- both mean there is nothing to draw.
function ns.MerchantCount()
	if type(_G.GetMerchantNumItems) ~= "function" then
		return 0
	end
	return _G.GetMerchantNumItems() or 0
end

-- One of them: name, icon, what it costs in copper, how many one purchase
-- gives you, how many are left, whether you can use it, and whether it wants
-- something other than money.
function ns.MerchantItem(index)
	if type(_G.GetMerchantItemInfo) ~= "function" then
		return nil
	end
	return Merchandise(_G.GetMerchantItemInfo(index))
end

function ns.MerchantItemLink(index)
	if type(_G.GetMerchantItemLink) ~= "function" then
		return nil
	end
	return _G.GetMerchantItemLink(index)
end

-- How many items one entry wants in payment, and what each of them is.
--
-- This is the badge vendor and the honour vendor: an entry whose extendedCost
-- flag is set is paid for in tokens rather than in gold, and the tokens are
-- read one at a time the way the client reads them.
function ns.MerchantCosts(index)
	if type(_G.GetMerchantItemCostInfo) ~= "function" then
		return 0
	end
	return _G.GetMerchantItemCostInfo(index) or 0
end

function ns.MerchantCost(index, which)
	if type(_G.GetMerchantItemCostItem) ~= "function" then
		return nil
	end
	return _G.GetMerchantItemCostItem(index, which)
end

-- The most of this the client will sell in one call.
--
-- Counted in items rather than in the vendor's own batches, which is the same
-- unit ns.BuyMerchant spends in: water sold five at a time with a stack of
-- twenty answers twenty, and that is four presses' worth bought at once.
--
-- Nil where the client has no such call, because "no answer" and "one" are
-- different facts and the window that asks wants to tell them apart: one means
-- the vendor sells this singly, and no answer means ask for a batch and leave
-- the rest alone.
function ns.MerchantMaxStack(index)
	if type(_G.GetMerchantItemMaxStack) ~= "function" then
		return nil
	end
	local stack = _G.GetMerchantItemMaxStack(index)
	if type(stack) ~= "number" or stack < 1 then
		return nil
	end
	return stack
end

-- How many of something you are carrying, counting every stack in every bag.
--
-- Here rather than beside the container calls above because there is one
-- caller and one reason: a badge vendor prices its rack in tokens, and whether
-- you can pay is a question about how many of the token you are holding. The
-- bank and the mailbox are counted too, on a client that has an answer for
-- them, which is the client's own behaviour and not something to correct: what
-- the number is for is "can I buy this", and the honest failure there is
-- optimistic rather than a row this window refuses to let you press.
function ns.ItemCount(link)
	if type(link) ~= "string" or type(_G.GetItemCount) ~= "function" then
		return 0
	end
	return _G.GetItemCount(link) or 0
end

-- Walk away from the vendor. The window this addon draws is the only thing on
-- the screen at that point, so closing it has to end the session as well: the
-- client's own frame is the one that would have, and it is parked off the side
-- of the screen where nothing can press its cross.
function ns.CloseMerchant()
	if type(_G.CloseMerchant) ~= "function" then
		return false
	end
	_G.CloseMerchant()
	return true
end

-- Buy that many. False where the client has neither the call nor a merchant
-- open, so a caller can say nothing happened rather than believe a purchase
-- went through.
--
-- The count is items and not batches, and getting that backwards is what this
-- comment is for. Both clients this addon ships to take the post-4.1 spelling:
-- BuyMerchantItem(index) with nothing after it buys one of the vendor's own
-- batches, and BuyMerchantItem(index, n) buys n items whatever the batch size
-- is. So asking for one at a vendor selling water five at a time buys one
-- water, not one stack, and a caller that wants the stack asks for five.
function ns.BuyMerchant(index, count)
	if type(_G.BuyMerchantItem) ~= "function" then
		return false
	end
	_G.BuyMerchantItem(index, count or 1)
	return true
end

-- Put one of the vendor's batches on the cursor, which is what the client's
-- own rack does on a left click. The client draws the icon under the pointer
-- and dropping it on a bag square buys it into that slot; no Lua here sees any
-- of that, which is the point. False where the client has no such call.
function ns.PickupMerchant(index)
	if type(_G.PickupMerchantItem) ~= "function" then
		return false
	end
	_G.PickupMerchantItem(index)
	return true
end

-- Whether the press being answered is asking for a number rather than for one
-- batch. SPLITSTACK is the client's own name for that gesture, shift by
-- default and rebindable in the key options, which is why the binding is
-- asked rather than the key.
function ns.Splitting()
	if type(_G.IsModifiedClick) == "function" then
		return _G.IsModifiedClick("SPLITSTACK") and true or false
	end
	return type(_G.IsShiftKeyDown) == "function" and _G.IsShiftKeyDown() and true or false
end

-- Hand a click on an item link to the client first. This is the call under
-- every item button Blizzard draws: shift with the chat box open links the
-- item into it, control opens the dressing room, and it answers true when it
-- took the press so the caller does nothing else with it.
function ns.LinkClick(link)
	if type(link) ~= "string" or type(_G.HandleModifiedItemClick) ~= "function" then
		return false
	end
	return _G.HandleModifiedItemClick(link) and true or false
end

--------------------------------------------------------------------------
-- The buyback rack
--
-- The other half of a merchant session. Everything you have sold this visit is
-- held for an hour at the price he paid you, and taking one back is the only
-- undo the game has for a sale. The addon has to draw it because the client's
-- own tab is behind the frame parked off the side of the screen.
--
-- The slots are not a list. GetNumBuybackItems answers the highest slot the
-- vendor is holding rather than how many things are in it, and a slot you have
-- already taken something out of answers nothing at all, so a caller walks the
-- range and skips what has no name.
--------------------------------------------------------------------------

function ns.BuybackCount()
	if type(_G.GetNumBuybackItems) ~= "function" then
		return 0
	end
	return _G.GetNumBuybackItems() or 0
end

-- One slot: name, icon, what it costs to take back, how many are in the stack,
-- how many the slot holds and whether your class can use it. The price is what
-- he paid you, which is why nothing here has to work it out.
function ns.BuybackItem(index)
	if type(_G.GetBuybackItemInfo) ~= "function" then
		return nil
	end
	return _G.GetBuybackItemInfo(index)
end

function ns.BuybackItemLink(index)
	if type(_G.GetBuybackItemLink) ~= "function" then
		return nil
	end
	return _G.GetBuybackItemLink(index)
end

-- Take one back. False where the client has no such call, so a caller can say
-- nothing happened rather than believe the item is on its way to a bag.
--
-- TakeBack rather than Buyback, which is what the call it wraps is called: the
-- rack itself is ns.Buyback over in Merchant/Buyback.lua, and two things one
-- letter apart on the same table is a crash the first time somebody calls the
-- wrong one.
function ns.TakeBack(index)
	if type(_G.BuybackItem) ~= "function" then
		return false
	end
	_G.BuybackItem(index)
	return true
end

--------------------------------------------------------------------------
-- The professions
--
-- Two windows, because this client has two of them. Every profession but
-- enchanting draws in the trade skill window and answers the GetTradeSkill
-- names; enchanting draws in the craft window and answers a parallel set of
-- names, and on Classic Era beast training draws there as well. Neither set
-- answers for the other's window, so both are shimmed and the caller walks
-- whichever one is open.
--
-- Here rather than in Comfort/Reagents.lua, which is the only caller, for the
-- reason the merchant block above gives: a part may not probe the client for a
-- call it means to make, because whether the call is there is a fact about the
-- build and not about the feature.
--
-- The one real difference between the two windows is where a row says what
-- kind of row it is, and it is the whole reason these are eleven functions
-- rather than a table of names. GetTradeSkillInfo answers name, type,
-- available, expanded. GetCraftInfo answers name, sub spell, type, available,
-- expanded, so the type is third and the expanded flag fifth. Both call a
-- category row "header" and neither says so anywhere but in that one slot, so
-- a caller reading the wrong position would take every category for a recipe
-- and every recipe for a category and would find no reagents at all, quietly.
-- The pair each window answers is normalised here to that type and that flag,
-- which is all a caller wants of a row.
--
-- Both windows are asked for their profession through the same guard. The
-- trade skill call answers the string "UNKNOWN" and three zeroes when no
-- window is open rather than answering nothing, and nothing says the craft
-- call is different, so UNKNOWN is read as no window on both sides. A caller
-- filing reagents under a profession called UNKNOWN would be a caller filing
-- them under a heading no rescan can ever find again.
--------------------------------------------------------------------------

-- Which profession the trade skill window is showing, or nil where none is.
-- The rank and the cap come back with the name and neither is read here.
function ns.TradeSkillName()
	if type(_G.GetTradeSkillLine) ~= "function" then
		return nil
	end
	local name = _G.GetTradeSkillLine()
	if type(name) ~= "string" or name == "" or name == "UNKNOWN" then
		return nil
	end
	return name
end

-- How many rows the trade skill window is listing, categories included.
function ns.TradeSkillCount()
	if type(_G.GetNumTradeSkills) ~= "function" then
		return 0
	end
	return _G.GetNumTradeSkills() or 0
end

-- One row: what kind it is, and whether it is opened out. "header" is a
-- category and everything else is a recipe. The flag only means anything on a
-- header, where false is a category whose recipes are not on the list at all.
function ns.TradeSkillRow(index)
	if type(_G.GetTradeSkillInfo) ~= "function" then
		return nil
	end
	local _, kind, _, expanded = _G.GetTradeSkillInfo(index)
	return kind, expanded and true or false
end

function ns.TradeSkillReagents(index)
	if type(_G.GetTradeSkillNumReagents) ~= "function" then
		return 0
	end
	return _G.GetTradeSkillNumReagents(index) or 0
end

function ns.TradeSkillReagent(index, which)
	if type(_G.GetTradeSkillReagentItemLink) ~= "function" then
		return nil
	end
	return _G.GetTradeSkillReagentItemLink(index, which)
end

-- Whether the window in front of you is somebody else's profession, opened
-- from a link they put in chat. It is their recipe list and their reagents,
-- and reading it as yours is how a warrior who has never mined ends up with
-- the whole of somebody's mining list on his loot filter.
--
-- Blizzard's own documentation puts this call in 2.5.5 and in Classic Era
-- 1.14.4, which is both clients this addon ships to, and it is still probed:
-- a client with no such call has no linked trade skills either, and false is
-- the honest answer there rather than a refusal to scan anything ever.
function ns.TradeSkillLinked()
	if type(_G.IsTradeSkillLinked) ~= "function" then
		return false
	end
	return _G.IsTradeSkillLinked() and true or false
end

-- The craft window's half, in the same order and with the same meanings.
function ns.CraftName()
	local lookup = _G.GetCraftDisplaySkillLine or _G.GetCraftSkillLine
	if type(lookup) ~= "function" then
		return nil
	end
	local name = lookup()
	if type(name) ~= "string" or name == "" or name == "UNKNOWN" then
		return nil
	end
	return name
end

function ns.CraftCount()
	if type(_G.GetNumCrafts) ~= "function" then
		return 0
	end
	return _G.GetNumCrafts() or 0
end

-- Third and fifth rather than second and fourth, which is the difference the
-- block header is about.
function ns.CraftRow(index)
	if type(_G.GetCraftInfo) ~= "function" then
		return nil
	end
	local _, _, kind, _, expanded = _G.GetCraftInfo(index)
	return kind, expanded and true or false
end

function ns.CraftReagents(index)
	if type(_G.GetCraftNumReagents) ~= "function" then
		return 0
	end
	return _G.GetCraftNumReagents(index) or 0
end

function ns.CraftReagent(index, which)
	if type(_G.GetCraftReagentItemLink) ~= "function" then
		return nil
	end
	return _G.GetCraftReagentItemLink(index, which)
end

-- Which creature a GUID belongs to, as the id the databases are keyed on.
--
-- The client hands GUIDs out everywhere and never hands out the number inside
-- one. The format is the client's own, six hyphenated fields before the id and
-- a spawn counter after it, and the leading word is what says whether there is
-- a creature behind the GUID at all: a player's has none, and a row asked about
-- one would come back as whatever number happened to be in that position.
--
-- Here rather than in a part, because two of them ask. The quest log's drop
-- ledger reads it off a loot window to say which corpse a hide came out of, and
-- the dungeon log's reads the same window to learn where a boss stands and what
-- came off it. Both had their own copy of these nine lines for exactly one
-- release.
function ns.CreatureId(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind ~= "Creature" and kind ~= "Vehicle" and kind ~= "Pet" then
		return nil
	end
	return tonumber(id)
end

-- The link on one slot of the loot window, or nothing where the slot is coin
-- or where this client has no such call.
--
-- Here for the reason ns.CreatureId is here, and the count is the same: three
-- parts ask. The quest log's drop ledger reads it to learn what came off a
-- creature, the dungeon log's reads it to learn what came off a boss, and
-- Comfort/Leftovers.lua reads it to tell an item from the coin it will not
-- destroy. All three had their own copy of the probe.
--
-- Nothing back is two answers wearing one shape and every caller wants the
-- same thing from both: a slot holding coin has no link, and a client with no
-- GetLootSlotLink has nothing to say about any slot. Neither is a reason to
-- guess at what the slot holds.
function ns.LootSlotLink(slot)
	local read = _G.GetLootSlotLink
	if type(read) ~= "function" then
		return nil
	end
	return read(slot)
end

--------------------------------------------------------------------------
-- The binding set moving under us
--
-- An override binding sits on top of the binding set rather than inside it,
-- and the client throws every override away each time it builds that set
-- again. It does that at Okay and at Cancel in the Key Bindings panel, at a
-- switch between the account's keys and this character's, and once during
-- login after PLAYER_LOGIN has already run.
--
-- That last one is the whole bug. A key taken at PLAYER_LOGIN was dropped a
-- moment later by a build nothing here was watching for, so every loadout key
-- was dead before the player could press it and rebinding it by hand was the
-- only thing that appeared to work. It appeared to work because a rebind is
-- the first take the client has not already thrown away.
--
-- So a key taken with SetOverrideBindingClick has to be taken again whenever
-- the set moves, and UPDATE_BINDINGS is what the client fires when it does.
-- Every file that takes one registers the pass that takes it again.
--
-- The pass waits a frame rather than running on the event, because putting a
-- key back fires UPDATE_BINDINGS itself and Buttons/Bars.lua answers that
-- event with a pass of its own. Running on the event would put this pass
-- inside every key that pass claims, a hundredfold for one binding change.
-- Waiting a frame collapses the whole storm into one run.
--
-- Nothing books a second pass from inside the first, because the latch below
-- turns the event away for as long as one is running. That is what makes every
-- key a pass puts back free rather than the start of the next pass.
--
-- One pass runs every registered take rather than only the one whose key
-- moved, because the event does not say which key that was and a take is a
-- handful of calls. A rebind is a function of no arguments that puts this
-- file's keys back, refuses in combat, and can be called at any time.
--------------------------------------------------------------------------

local rebinds = {}
local passing = false
local waiting = false
local bindings = CreateFrame("Frame")

function ns.Rebind(apply)
	assert(type(apply) == "function", "a rebind is a function")
	rebinds[#rebinds + 1] = apply
end

local function Run()
	for index = 1, #rebinds do
		rebinds[index]()
	end
end

local function Pass(self)
	self:SetScript("OnUpdate", nil) -- unguarded: the one-shot hands its own handler back

	-- Held rather than dropped. A binding call is refused under lockdown, and
	-- not every file that takes a key picks its own work back up when the
	-- fight ends; going through here means all of them do.
	if InCombatLockdown() then
		waiting = true
		return
	end
	waiting = false

	passing = true
	local ok, why = pcall(Run)
	passing = false
	if not ok then
		ns.Print(("a key could not be put back: %s"):format(tostring(why)))
	end
end

bindings:RegisterEvent("UPDATE_BINDINGS")
bindings:RegisterEvent("PLAYER_REGEN_ENABLED")
bindings:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if waiting then
			self:SetScript("OnUpdate", Pass)
		end
		return
	end
	-- Nothing to put back before the saved variables are merged, because every
	-- pass reads the key it holds out of ns.db or ns.dbc. PLAYER_LOGIN runs
	-- them all afterwards, so an event this early costs nothing to drop.
	if passing or not ns.dbc then
		return
	end
	self:SetScript("OnUpdate", Pass)
end)

-- The same pass, asked for by a part rather than by the client. Buttons/Bars.lua
-- calls it when its squares go up or down, because what a key presses
-- underneath is an answer another take wrote down. Turned away inside a pass
-- for the reason the event is, and dropped before the saved variables exist
-- for the same reason.
function ns.Retake()
	if passing or not ns.dbc then
		return
	end
	bindings:SetScript("OnUpdate", Pass)
end

--------------------------------------------------------------------------
-- Saved variables
--
-- ADDON_LOADED fires once every file in the TOC has run, so every feature has
-- already registered its defaults by the time this merges them.
--
-- Two tables. WarriorKitDB is the account's and reaches ns.db, WarriorKitCharDB
-- is this character's and reaches ns.dbc. Both are declared in the TOC and both
-- arrive at ADDON_LOADED, so no caller has to know which file its setting came
-- out of, only which name to read it from.
--------------------------------------------------------------------------

local function ApplyDefaults(db, from)
	for key, value in pairs(from) do
		if db[key] == nil then
			if type(value) == "table" then
				local copy = {}
				for i, v in pairs(value) do
					copy[i] = v
				end
				db[key] = copy
			else
				db[key] = value
			end
		end
	end
	return db
end

-- The registered default for one setting, so nothing repeats a literal that
-- already exists in a feature's defaults table.
--
-- For reading. Every write back into ns.db goes through DefaultCopy below,
-- because what this hands back is the registered table itself.
function ns.DefaultFor(key)
	if defaults[key] ~= nil then
		return defaults[key]
	end
	return charDefaults[key]
end

-- The same answer, in a table nobody else is holding.
--
-- An anchor is written through on every drag, so a restore that assigned the
-- registered table would hand the feature the defaults block to drag around,
-- and the next restore would put back wherever it was left. Eight resets
-- avoided that by writing the anchor out longhand instead, and every one of
-- the eight was still holding the position the addon shipped with two releases
-- ago. Nothing said so, because a literal cannot go stale out loud.
--
-- So this is the one way back into ns.db, whatever the default's type. A
-- scalar comes back untouched, which means no caller has to know which
-- defaults happen to be tables this month.
--
-- One level deep is all it copies, which is exactly as deep as a defaults
-- table goes: every table in one is a list of numbers or a map of flags.
function ns.DefaultCopy(key)
	local value = ns.DefaultFor(key)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for at, held in pairs(value) do
		copy[at] = held
	end
	return copy
end

--------------------------------------------------------------------------
-- Where you left a window
--
-- Seven windows in the addon are things you open, drag out of the way of
-- whatever you are reading, and open again tomorrow: the map, the quest log,
-- the mail, the character sheet, the breakdown, the clutter card and the
-- settings panel. Every one of them opened in the middle of the screen, every
-- session, however many times you had moved it. UI/Placeable.lua has always
-- had the drag; what it had nowhere to put was the answer.
--
-- One line per window, at the point the part has the window in its hand:
--
--   ns.Remember(window)
--
-- and the frame's own name is the key, because a window already has one and a
-- second identifier is a second thing to keep in step. Nothing about a spot is
-- a preference anybody words: it is five fields the drag hands over.
--
-- Two windows are deliberately not here. The chat window keeps its corner in a
-- setting of its own, because that one has a reset button pointing at it and a
-- default that says which corner a conversation belongs in. The question box
-- has no spot at all: it opens over whatever asked the question, and a modal
-- that appears wherever you last dragged one is a modal you have to go and
-- find.
--------------------------------------------------------------------------

-- Whether a saved anchor is one the client will take. A saved variables file is
-- edited by hand, carried between machines and written by whatever the addon
-- was two releases ago, and a bad anchor here is a Lua error at login on the
-- window that would have shown it.
local function Sane(spot)
	return type(spot) == "table"
		and type(spot[1]) == "string" and type(spot[3]) == "string"
		and type(spot[4]) == "number" and type(spot[5]) == "number"
end

-- Put the window back where it was, and write down where it goes next.
--
-- A window off the edge of a smaller screen than the one it was dragged on is
-- pulled back by SetClampedToScreen, which every placeable frame is built with.
function ns.Remember(window)
	local name = window.frame:GetName()
	assert(name, "a window with no name has nowhere to keep where you left it")

	local spot = ns.db.windowSpots[name]
	if Sane(spot) then
		window.place:Place(spot)
	end

	window.place:OnMoved(function(anchor)
		ns.db.windowSpots[name] = anchor
	end)
	return window
end

--------------------------------------------------------------------------
-- Back to what it ships as
--
-- One press that puts every setting in the account file back to the value the
-- addon ships with.
--
-- It exists because ApplyDefaults only fills in what is missing. That is the
-- right rule for a setting that arrives in an update and the wrong one for a
-- release that moves a default: an account file with a number already written
-- against every key never sees a new one, so the person who has been playing
-- the addon longest is the only person who never gets the layout it ships
-- with. Deleting the saved variables file is the answer that worked before
-- this, and it takes the gold ledger and your groups with it.
--------------------------------------------------------------------------

-- What the reset leaves alone, and why.
--
-- Every entry is a record rather than a preference. A default is the right
-- answer to "what should this setting be"; there is no right answer to "how
-- much gold was that alt carrying" or "what was this key bound to before we
-- took it", and writing one would be deleting the answer rather than restoring
-- it. Anything not named here is a setting and goes back.
--
-- Checked against the registry at load, below, so a key cannot be kept out of
-- the reset and then quietly dropped from the addon.
local KEPT = {
	-- The ledger: copper against every character you have played. The only
	-- copy of it, and not a number anybody chose.
	purse = true,

	-- How many corpses of each creature you have looted and how many of those
	-- carried a quest item. A count of what happened while you played, not a
	-- number anybody chose, and the only copy of it: wiping it does not restore
	-- a default, it throws away every drop chance the addon has measured.
	questDrops = true,

	-- The people you put in groups, and the counter their room keys come off.
	-- The counter goes with the list rather than on its own, because resetting
	-- it alone would hand a new group the key of a deleted one.
	groups = true,
	groupSeq = true,

	-- Two lists you curated, each with a word of its own for emptying it:
	-- `errors clear` and `mail unfav`. A button about the layout has no
	-- business deleting the alt you mail. The flask list was the third and is
	-- the character's now, which the reset never touches.
	errorMuted = true,
	mailFavourites = true,

	-- What three nameplate CVars held before the addon first wrote to them.
	-- Wiping one does not restore a default, it loses the only note of what to
	-- put back, and the next `bars stack off` hands the client a number it
	-- never had.
	platesMotionPrior = true,
	platesOverlapPrior = true,
	platesDistancePrior = true,

	-- What the charge key and the switch key were bound to before this addon
	-- took them, kept for the reason the three above are: the override is
	-- still ours and this is the only record of what is under it.
	chargeKeyDisplaced = true,
	switchKeyDisplaced = true,

	-- The staging area `./bake-ui.sh` reads the Edit Mode layout out of. A
	-- step in a build rather than a setting anybody sees.
	uiLayout = true,
	uiLayoutName = true,
	uiLayoutStamp = true,

	-- What the last attempt to build the chat window did. Chat/Window.lua's
	-- Note says why it has to survive a reload: the failure it reports is one
	-- where the window that would print it is the window that did not build.
	chatWhy = true,
}

-- Whether two saved values are the same setting. One level deep, for the
-- reason DefaultCopy is: a defaults table holds numbers, strings, flags, and
-- flat tables of those.
local function Same(held, want)
	if type(held) ~= "table" or type(want) ~= "table" then
		return held == want
	end
	for at, value in pairs(want) do
		if held[at] ~= value then
			return false
		end
	end
	for at in pairs(held) do
		if want[at] == nil then
			return false
		end
	end
	return true
end

-- Every account setting the reset is allowed to write, in no order, because
-- nothing downstream cares which order they go back in.
local function Restorable(key)
	return defaults[key] ~= nil and not KEPT[key]
end

-- How many settings the reset writes and how many records it steps over. For
-- the status line and for the harness, which prints the pair so the day one of
-- them moves without anybody meaning it, the number in the log moves with it.
function ns.DefaultsShape()
	local restorable, kept = 0, 0
	for key in pairs(defaults) do
		if KEPT[key] then
			kept = kept + 1
		else
			restorable = restorable + 1
		end
	end
	return restorable, kept
end

-- How many settings are not what the addon ships with. The panel reads it to
-- say so out loud and to grey the button when the answer is none, which is the
-- difference between a button that does nothing and a button that says there
-- is nothing to do.
function ns.DefaultsMoved()
	local moved = 0
	for key in pairs(defaults) do
		if Restorable(key) and not Same(ns.db[key], defaults[key]) then
			moved = moved + 1
		end
	end
	return moved
end

-- Write them all back. Returns how many actually moved, which is what the
-- caller prints; it does not apply anything, because the caller reloads.
function ns.RestoreDefaults()
	local moved = 0
	for key in pairs(defaults) do
		if Restorable(key) and not Same(ns.db[key], defaults[key]) then
			ns.db[key] = ns.DefaultCopy(key)
			moved = moved + 1
		end
	end
	return moved
end

-- A character that carried the loadout backup from before the split has it in
-- the account file, where it does not belong and where the next character to
-- apply the loadout would have inherited it. Move it once, then leave the
-- account table alone.
local function Retire()
	for key in pairs(RETIRED) do
		WarriorKitDB[key] = nil
		WarriorKitCharDB[key] = nil
	end
end

local function Migrate()
	for key in pairs(charDefaults) do
		if WarriorKitDB[key] ~= nil then
			if WarriorKitCharDB[key] == nil then
				WarriorKitCharDB[key] = WarriorKitDB[key]
			end
			WarriorKitDB[key] = nil
		end
	end
end

-- uiSize was one number for every window in the addon, and it is gone: each
-- screen carries its own now. A player who had dragged that slider gets the
-- number they chose written onto every window zoom still sitting at its
-- default, so the screen they log into is the screen they logged out of, and
-- the old key is dropped. A screen they had already sized on its own keeps what
-- they gave it.
--
-- Runs once, because the key it reads is deleted on the way out. Windows only:
-- the HUD parts each had their own zoom before this and none of them was ever
-- multiplied by uiSize.
local function MigrateZooms()
	local was = tonumber(WarriorKitDB.uiSize)
	WarriorKitDB.uiSize = nil
	if not was or was == 1 then
		return 0
	end
	local moved = 0
	for _, zoom in ipairs(ns.Zooms()) do
		if zoom.window and ns.db[zoom.key] == defaults[zoom.key] then
			ns.db[zoom.key] = ns.UI.ZoomSnap(was)
			moved = moved + 1
		end
	end
	return moved
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON then
		return
	end
	WarriorKitDB = WarriorKitDB or {}
	WarriorKitCharDB = WarriorKitCharDB or {}
	Retire()
	Migrate()
	ns.db = ApplyDefaults(WarriorKitDB, defaults)
	ns.dbc = ApplyDefaults(WarriorKitCharDB, charDefaults)
	MigrateZooms()

	-- Said here rather than beside the list, because every feature has
	-- registered by now and not one of them had when the list was written. A
	-- key kept out of the reset and then dropped from the addon is a comment
	-- explaining why the reset skips something that no longer exists.
	for key in pairs(KEPT) do
		assert(defaults[key] ~= nil,
			("%q is kept out of the reset and no feature registers it"):format(key))
	end
	self:UnregisterEvent("ADDON_LOADED")
end)
