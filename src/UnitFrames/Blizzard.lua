local ADDON, ns = ...

local Blizz = {}
ns.BlizzHide = Blizz

--------------------------------------------------------------------------
-- The client's own frames, one switch each
--
-- Everything in here answers one question: this addon draws X, so should the
-- client's X still be on the screen? Every answer is a switch with the same
-- shape and the same default, and the whole point is that there is nothing
-- clever behind any of them. A player who can see two copies of one aura
-- should be able to find the line that says "hide Blizzard's buffs" and press
-- it, without knowing that the skin is on, that a sweep exists, or that the
-- two clients this addon runs on disagree about where a debuff lives.
--
-- It used to be one setting that meant something different depending on what
-- the skin was doing. That was the bug: a switch whose effect you cannot
-- predict from its label is not a switch, and the honest fix was more of them
-- rather than a cleverer one.
--
-- **A switch here holds or it says so.** That is the second rewrite of this
-- file and the reason for it is worth writing down, because the first version
-- was correct and still failed twice in game.
--
-- It hid each frame once, at login, by putting the frame's own Hide where its
-- Show was, and then remembered that it had. Both halves were wrong. Replacing
-- Show does nothing about SetShown, which is resolved in C and never reads the
-- Lua field, so every FrameXML path written that way walked past it: `FCF_` uses
-- it on the chat window, which is why `/logout` put the client's chat back, and
-- the cast bar mixin uses it on the target's bar, which is why the target had
-- two cast bars with the switch on. And because the file remembered, one frame
-- that got past it stayed past it for the rest of the session.
--
-- So neither half survives. Core/Attic.lua re-parents the frame into a frame
-- that is hidden and can never be shown, which no call on the frame itself can
-- undo, and this file verifies rather than remembers: every pass re-resolves
-- every name, re-reads what is actually on the screen, and puts back anything
-- that moved. The pass runs at login, when a switch moves, when combat drops
-- and once a second forever. The raid manager used to have a hook of its own for
-- exactly this and does not need one now, which is the shape of the fix: one
-- mechanism instead of a patch per frame that somebody noticed.
--
-- Two handles take a row off the screen and this file holds one of them. A
-- frame goes down here; the buttons inside a frame nobody can hide go down one
-- name at a time in UnitFrames/Auras.lua, off the same switch and through the
-- same attic. The target's rows are the second kind, because every icon in them
-- is a child of TargetFrame and nothing else, and hiding TargetFrame is hiding
-- the target.
--------------------------------------------------------------------------

-- Every switch, in the order the panel and `/wk hide` walk them.
--
--   key    the setting, and every one of them is a plain boolean that means
--          exactly what its label says
--   word   what `/wk hide` calls it
--   label  the panel's line, and the sentence the slash word prints back
--   hint   the one thing about this switch a label cannot hold, where there is
--          one. Seven of the ten have a catch and the other three do not, and a
--          line of reassurance under a switch that has nothing to warn about
--          is how a page teaches you to stop reading the hints
local SWITCHES = {
	{ key = "hideBlizzBuffs", word = "buffs", label = "Blizzard's buffs",
		hint = "Right click to cancel a buff goes with them. Cancelling one is a call an addon is not allowed to make." },
	{ key = "hideBlizzDebuffs", word = "debuffs", label = "Blizzard's debuffs" },
	{ key = "hideBlizzTargetAuras", word = "target",
		label = "Blizzard's target buffs and debuffs",
		hint = "These have no frame of their own, so this one needs the target frame skinned to reach them." },
	{ key = "hideBlizzTargetCast", word = "cast",
		label = "Blizzard's target cast bar",
		hint = "The cast is drawn on the enemy bar instead, in the second chamber of the box." },
	{ key = "hideBlizzPlayerCast", word = "playercast",
		label = "Blizzard's own cast bar",
		hint = "Read this one with our cast bar switch. Both off is the one combination that leaves you no cast bar at all." },
	{ key = "hideBlizzParty", word = "party", label = "Blizzard's party frames" },
	-- One of the two switches in this list whose frames are not named in FRAMES
	-- below, the character sheet being the other.
	-- Hiding the client's chat window is twenty five names, a forward of
	-- everything that window would have drawn so none of it is lost, and a
	-- coupling to whether ours is open at all, which is a file rather than a
	-- row: Chat/Blizzard.lua, registered through Blizz.Also.
	{ key = "hideBlizzChat", word = "chat", label = "Blizzard's chat window",
		hint = "Everything it would have drawn goes to the System room in ours, and the enter key comes with it." },
	{ key = "hideBlizzRaid", word = "raid", label = "Blizzard's raid frames" },
	{ key = "hideBlizzXP", word = "xp",
		label = "Blizzard's experience and reputation bars",
		hint = "Progress/Rails.lua draws both instead. Its default is the bottom edge of the screen, which is roughly where these two were." },
	-- The second switch in this list whose frames are not in FRAMES below, and
	-- it is a file for the reason the chat window's is: the C key has to come
	-- with the window, and a key swap is not a row in a table. Character
	-- /Blizzard.lua registers through Blizz.Also.
	{ key = "hideBlizzCharacter", word = "character",
		label = "Blizzard's character sheet",
		hint = "The C key opens this addon's instead, on the page you asked for. Your pet's sheet and the honour tab are the two pages it does not draw, so untick this if you want either." },
}

-- What each switch takes down, and what it takes to take it down.
--
-- `needs` is a list rather than a single key because one frame on the older
-- clients holds both of your rows. BuffFrame is your buffs and your debuffs
-- together on 2.5.6, so it may only go down when both switches are on;
-- whichever of the two is on alone is served by the sweep in
-- UnitFrames/Auras.lua, which works a button at a time and can tell them apart.
--
-- `names` is a list for the same reason and one more. DebuffFrame is the newer
-- clients splitting BuffFrame in two; it is not on 2.5.6 at all, and a name this
-- client does not carry costs one lookup against nil. That split is what put a
-- debuff back on the screen under a row already drawing it: hiding BuffFrame
-- took the buffs and left the debuffs exactly where they were. Your own cast bar
-- is two names for the same reason, CastingBarFrame on 2.5.6 and
-- PlayerCastingBarFrame on the clients this Edit Mode was backported from.
--
-- `keys` is the answer to the failure a list of names cannot cover, which is a
-- client that renamed the global. FrameXML declares these frames with a
-- parentKey, and the key outlives the global name across builds far more often
-- than the other way round, so the target's cast bar is looked for as
-- TargetFrameSpellBar and as whatever TargetFrame.spellbar is, and a client that
-- answers to either gets its bar taken down. Both resolving to the same frame
-- costs one extra table lookup and nothing else: the attic is idempotent.
--
-- One key, not several, and that is a rule rather than an accident. A key is
-- read straight off a frame this addon does not own, so a guess that lands on
-- the wrong field hides something nobody asked to hide, which is a worse failure
-- than the one the list exists to fix. `spellbar` is what FrameXML declares the
-- target's cast bar under and is the only one written from the source. Anything
-- else goes in after `/wk hide probe` has said ON SCREEN against a name and
-- somebody has read the key off the client.
--
-- The target's auras name no frame here on purpose. Every icon in those two
-- rows is a child of TargetFrame, so there is nothing between the buttons and
-- the frame you are targeting with, and the sweep in UnitFrames/Auras.lua is the
-- only handle.
local FRAMES = {
	{ needs = { "hideBlizzBuffs", "hideBlizzDebuffs" }, names = { "BuffFrame" } },
	{ needs = { "hideBlizzBuffs" }, names = { "TemporaryEnchantFrame" } },
	{ needs = { "hideBlizzDebuffs" }, names = { "DebuffFrame" } },
	{ needs = { "hideBlizzTargetCast" }, names = { "TargetFrameSpellBar" },
		keys = { { owner = "TargetFrame", key = "spellbar" } },
		mute = { "AdjustPosition" } },
	{ needs = { "hideBlizzPlayerCast" },
		names = { "CastingBarFrame", "PlayerCastingBarFrame" } },
	-- Six names for the party, and the four everybody knows are the four this
	-- client may not be drawing. PartyMemberFrame1 through 4 are the old frames,
	-- one per party index. A client with raid style party frames draws the party
	-- through a compact container instead and leaves those four hidden on its
	-- own, so the switch reports every name it knows as down while the party is
	-- still on the screen, which is the one failure a list of names has and the
	-- only fix for it is the missing name. CompactPartyFrame is that container
	-- where the client has it and PartyFrame is what both hang off on the builds
	-- that carry one, so the party goes down whichever of the two is drawing it.
	{ needs = { "hideBlizzParty" }, names = { "PartyMemberFrame1",
		"PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
		"CompactPartyFrame", "PartyFrame" } },
	{ needs = { "hideBlizzRaid" },
		names = { "CompactRaidFrameContainer", "CompactRaidFrameManager" } },
	-- Five names for two bars, and every one of them is a client disagreeing
	-- with the others about who owns them. 2.5.6 draws the pair as
	-- MainMenuExpBar with ReputationWatchBar under it and swaps the first for
	-- MainMenuBarMaxLevelBar at the cap; the builds this Edit Mode was
	-- backported from put both inside StatusTrackingBarManager. ExhaustionTick
	-- is the rested marker, which is a child of the experience bar on the
	-- clients that have it and is named here anyway, because the attic is
	-- idempotent and a name this client does not carry costs one lookup.
	{ needs = { "hideBlizzXP" }, names = { "MainMenuExpBar", "ReputationWatchBar",
		"MainMenuBarMaxLevelBar", "StatusTrackingBarManager", "ExhaustionTick" } },
}

-- A part whose frames need more than a name in the table above, and whose
-- switch still belongs on the same page as these.
--
-- The rule this bends is the one in the header: the next thing to hide should
-- be a line in FRAMES rather than a file. It holds for a frame that goes down
-- when a boolean says so, which is every entry above. It does not hold for the
-- client's chat window, where hiding without forwarding what that window draws
-- would delete the loot, the experience and every addon's output, so the hide
-- and the forward have to be one mechanism. It does not hold for the client's
-- character sheet either, where the C key has to end up opening this addon's
-- window and a key swap is not a row in a table. What stays here is the switch,
-- so there is still one page and one word for all of them.
--
-- An entry answers the same true or false Blizz.Apply does: false is work combat
-- refused, and it puts the whole pass on the retry.
local extra = {}

function Blizz.Also(apply)
	extra[#extra + 1] = apply
	return #extra
end

local function Asked(needs)
	for index = 1, #needs do
		if not ns.db[needs[index]] then
			return false
		end
	end
	return true
end

-- What a key entry held, while the frame it named is in the attic.
--
-- A caged frame is off the screen and the client is still driving it, and for
-- the target's cast bar that is not harmless. TargetFrame calls
-- `self.spellbar:AdjustPosition()` from three places, that function reads
-- `auraRows` off whatever the bar's parent is, and the attic is a plain frame
-- with no such field. One evening with the switch on and a target selected was
-- sixteen hundred Lua errors, one per pass of the target frame's OnUpdate, none
-- of them in this addon's files and all of them this addon's doing.
--
-- Every one of those three call sites is guarded by the key being there, which
-- is what makes clearing it the fix rather than a second patch: the client stops
-- reaching for a frame it can no longer see, instead of being handed an answer
-- that happens to keep it quiet. The cage and the strip both stay, because a key
-- is the handle FrameXML uses and Show is the handle everything else uses.
--
-- Keyed by the entry table rather than by the owner or the name. The entry is a
-- table that already exists and is unique to the pairing, so the lookup costs
-- nothing and building a key would allocate on a path that runs every second.
local stash = {}

-- Whether the frame this key entry names is out of the client's hands.
-- Public for the harness, which cannot ask the owner: the whole point is that
-- the owner no longer says.
function Blizz.Stashed(owner, key)
	for index = 1, #FRAMES do
		local keys = FRAMES[index].keys
		if keys then
			for slot = 1, #keys do
				if keys[slot].owner == owner and keys[slot].key == key then
					return stash[keys[slot]] ~= nil
				end
			end
		end
	end
	return false
end

-- One key entry moved, once the frame it names has gone where it is going.
--
-- Down on the way out and back on the way in, which is the whole of it. A
-- function rather than four more levels inside the walk below, because the walk
-- is already a loop inside a branch and this is a second question about the
-- same entry rather than a deeper part of the first.
--
-- An owner this client does not carry has no key to move, and the frame was
-- reached from the stash in that case anyway.
local function MoveKey(slot, owner, hiding)
	if type(owner) ~= "table" then
		return
	end
	if not hiding then
		if stash[slot] ~= nil then
			owner[slot.key] = stash[slot]
			stash[slot] = nil
		end
	elseif owner[slot.key] ~= nil then
		stash[slot] = owner[slot.key]
		owner[slot.key] = nil
	end
end

-- A method the caged frame calls on itself, silenced while it is up here.
--
-- Clearing TargetFrame.spellbar stops the three call sites TargetFrame owns. It
-- does not stop the fourth, which is the bar's own handler. A channel starting
-- on the target runs the cast bar's OnEvent, that handler calls
-- `self:AdjustPosition()` with no key in the way, AdjustPosition reads
-- `auraRows` off the bar's parent, and the parent is now the attic. One error
-- per cast rather than one per OnUpdate pass, which is why this one outlived
-- the key.
--
-- A no-op rather than an `auraRows` field on the room. The attic would then have
-- to answer for every field every caged frame's client code reads, guessed from
-- a FrameXML this addon cannot see, and a wrong guess is a frame laid out
-- against a number somebody invented. Saying nothing is the honest answer: the
-- bar is off the screen, where it thinks it sits does not matter until it comes
-- back, and coming back puts the client's own method back before anything asks.
--
-- The original is kept on the frame, the way ns.Strip keeps Show, so the state
-- can be read off the thing it was done to. False is "this client had no such
-- method", which unmuting has to hand back as nil rather than as false.
--
-- Only ever reached with a frame `act` has already accepted, so the combat check
-- ns.Strip makes has been made: a protected frame in a lockdown never gets here.
local function Nothing()
end

local function Mute(entry, frame, hiding)
	local names = entry.mute
	if not names then
		return
	end
	local kept = frame.wkMuted
	if hiding then
		if kept then
			return
		end
		kept = {}
		for index = 1, #names do
			local name = names[index]
			kept[name] = frame[name] or false
			frame[name] = Nothing
		end
		frame.wkMuted = kept
	elseif kept then
		for index = 1, #names do
			local name = names[index]
			frame[name] = kept[name] or nil
		end
		frame.wkMuted = nil
	end
end

-- Every frame one entry names, whichever way this client names it, handed to
-- `act`. `act` is ns.Attic.Vanish or ns.Attic.Return, passed by reference rather
-- than wrapped, because this runs on the second and a closure per pass is
-- garbage the collector has to walk later.
--
-- `hiding` says which of the two it is, because the key above has to move in
-- one direction on the way down and the other on the way back, and reading that
-- off the function would be reading it off the wrong thing.
--
-- A name this client does not carry is skipped and costs one lookup against
-- nil. A key whose owner is missing costs two.
local function Walk(entry, act, hiding)
	local complete = true
	local names = entry.names
	for index = 1, #names do
		local frame = _G[names[index]]
		if frame then
			if act(frame) then
				Mute(entry, frame, hiding)
			else
				complete = false
			end
		end
	end
	local keys = entry.keys
	if keys then
		for index = 1, #keys do
			local slot = keys[index]
			local owner = _G[slot.owner]
			local frame = type(owner) == "table" and owner[slot.key] or nil
			-- Taken from the stash once the key is gone, because the key is
			-- how this pass found the frame and the pass runs every second.
			if frame == nil then
				frame = stash[slot]
			end
			if type(frame) == "table" then
				if act(frame) then
					MoveKey(slot, owner, hiding)
					Mute(entry, frame, hiding)
				else
					complete = false
				end
			end
		end
	end
	return complete
end

-- Every frame put where its switches say it should be, read off the screen
-- rather than off a record of the last pass.
--
-- False where combat refused, which the retry below picks up: the target's cast
-- bar is a child of a secure unit button and is the one frame in the list that
-- can say no.
function Blizz.Apply()
	-- Tolerates being called before the saved variables exist, like every other
	-- Apply in the addon.
	if not ns.db then
		return true
	end
	local complete = true
	for index = 1, #FRAMES do
		local entry = FRAMES[index]
		local hiding = Asked(entry.needs)
		if not Walk(entry, hiding and ns.Attic.Vanish or ns.Attic.Return, hiding) then
			complete = false
		end
	end
	-- And everything already down, checked against where it actually is. A cage
	-- is undone by nothing but somebody else's SetParent, and this is the line
	-- that says so out loud rather than assuming it.
	if not ns.Attic.Sweep() then
		complete = false
	end
	for index = 1, #extra do
		if not extra[index]() then
			complete = false
		end
	end
	return complete
end

--------------------------------------------------------------------------
-- The clock
--
-- One hertz, forever, and it is not a workaround for a mechanism that does not
-- hold. The cage holds. What the second buys is the two things a cage cannot
-- answer for on its own: a frame the client had not built yet at the last pass,
-- which is every load-on-demand frame and every chat window a whisper opens, and
-- a frame somebody else re-parented, which nothing here is known to do and which
-- is exactly the kind of claim that has already been wrong twice.
--
-- So the guarantee this file makes is not "no path we thought of can show it".
-- It is "nothing the addon replaces stays on the screen for longer than a
-- second", and that one does not depend on having guessed the client's call
-- sites correctly.
--
-- The cost is a dozen global lookups and a parent comparison per frame held,
-- once a second, with a write only where a comparison failed. It is bracketed
-- like every other tick in the addon so the performance tab accounts for it
-- rather than leaving it as the one pass nobody can see.
--------------------------------------------------------------------------

local INTERVAL = 1.0
local elapsed = 0

local function Tick(_, delta)
	elapsed = elapsed + delta
	if elapsed < INTERVAL then
		return
	end
	elapsed = 0
	ns.Perf.Start("hide")
	Blizz.Apply()
	ns.Perf.Stop("hide")
end

-- The switches, for the panel and the slash word, so neither writes the list
-- out again and the two cannot drift.
function Blizz.Switches()
	return SWITCHES
end

-- The switch one word names, or nothing.
function Blizz.Find(word)
	for index = 1, #SWITCHES do
		if SWITCHES[index].word == word then
			return SWITCHES[index]
		end
	end
	return nil
end

-- How many of the names above this client actually carries. Zero is the answer
-- worth seeing: it says the client calls these frames something else, which is
-- a different thing from a switch that did not work.
function Blizz.Found()
	local found, of = 0, 0
	for index = 1, #FRAMES do
		local names = FRAMES[index].names
		for slot = 1, #names do
			of = of + 1
			if _G[names[slot]] then
				found = found + 1
			end
		end
	end
	return found, of
end

--------------------------------------------------------------------------
-- Saying what actually happened
--
-- `/wk hide probe` reports one line per name: whether this client has the frame,
-- whether the attic is holding it, and whether it is on the screen anyway. That
-- last column is the one worth having. Every bug this file has had looked
-- identical from the outside, a switch that was on with the frame still drawn,
-- and settling which of the three it was took a guess at FrameXML each time.
-- Now it takes one command.
--
-- Rows are built on demand, from the slash word only, which is why this is the
-- one function here that is allowed to allocate.
--------------------------------------------------------------------------

local function Row(rows, label, frame, wanted)
	local state
	if not frame then
		state = "this client has no such frame"
	elseif ns.Measure(frame, "IsVisible") then
		state = wanted and "ON SCREEN, and the switch says it should not be"
			or "on screen"
	elseif not wanted then
		state = "off screen, and the switch does not ask for that"
	elseif ns.Attic.Held(frame) then
		state = "hidden, in the attic"
	else
		state = "hidden, but not caged: this client refused the re-parent"
	end
	rows[#rows + 1] = ("  %s: %s"):format(label, state)
end

function Blizz.Probe()
	local rows = {}
	if not ns.Attic.Available() then
		rows[#rows + 1] = "  this client would not make the attic, so every frame below is held by ns.Strip alone"
	end
	for index = 1, #FRAMES do
		local entry = FRAMES[index]
		local wanted = Asked(entry.needs)
		for slot = 1, #entry.names do
			Row(rows, entry.names[slot], _G[entry.names[slot]], wanted)
		end
		local keys = entry.keys or {}
		for slot = 1, #keys do
			local owner = _G[keys[slot].owner]
			Row(rows, ("%s.%s"):format(keys[slot].owner, keys[slot].key),
				type(owner) == "table" and owner[keys[slot].key] or nil, wanted)
		end
	end
	return rows
end

function Blizz.Describe()
	local hidden = {}
	for index = 1, #SWITCHES do
		local switch = SWITCHES[index]
		if ns.db[switch.key] then
			hidden[#hidden + 1] = switch.word
		end
	end
	local found, of = Blizz.Found()
	if #hidden == 0 then
		return ("nothing of the client's hidden, %d of %d frames on this client")
			:format(found, of)
	end
	return ("hidden: %s; %d of %d frames on this client, %d held")
		:format(table.concat(hidden, ", "), found, of, ns.Attic.Count())
end

-- PLAYER_LOGIN starts the clock. PLAYER_REGEN_ENABLED is the retry every strip
-- in the addon uses, and here it only saves a pass its share of a second: the
-- tick would have reached the same work anyway, which is the difference between
-- this file and the one it replaced.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	Blizz.Apply()
	if event == "PLAYER_LOGIN" then
		events:SetScript("OnUpdate", Tick)
	end
end)
