-- A whole word or none of it
--
-- The middle column of a feed row was the one place in the addon where a string
-- and the room it had been given were never compared. A stream asks for a width
-- in units, UI/Feed.lua hands back half of what is left after the number at
-- most, and a font string given less than its string needs draws what fits and
-- drops the rest. Nothing errors and nothing is logged. The row reads as a mob
-- whose name stops mid-word.
--
-- Feeds/Combat.lua is the one that clips. It asks for 96 units and its widest
-- string, "from Plains Creeper", measures 131 in the shipped face at a row's
-- text size, so there is no width of that feed at which the column holds it:
-- the panel's ceiling of 520 units grants the whole 96 and 96 is not enough.
-- Feeds/Loot.lua does not clip, because item 86 sized its 48 units against the
-- widest quest count an objective can carry, which is 37.
--
-- Three claims, and not one of them can be read off the source.
--
-- **A note wider than its column is not drawn at all.** The string still
-- arrives and the row still holds it. What goes is a player being shown two
-- thirds of a name.
--
-- **One that fits is still drawn.** The rule is a comparison, and a comparison
-- written the wrong way round empties every middle column in the addon. That is
-- a feature going quiet in exactly the way this one is meant to, and from the
-- outside the two are the same screen.
--
-- **The answer moves with what the player did.** The column is the stream's ask
-- or half the free width, whichever is smaller, so the same note draws at one
-- feed width and goes at the next one down. And it is a measurement that
-- decides rather than a count of characters: one string at two text sizes comes
-- out on two sides of one column.
--
-- A file of its own because 31-feeds.lua is at the line ceiling every section
-- shares, and because this is the widget's rule rather than either feed's: both
-- streams are read here and the code under it is in UI/Feed.lua.
--
-- What this cannot prove: that the client's text engine measures what the
-- harness models. client/02-text.lua runs 0.53 em a glyph where Media/Sans.ttf
-- runs 0.481 over the addon's own strings, which is slack in the safe
-- direction, and every number in the prose above is the face's rather than the
-- model's.

local H = ...
local ns, fire, check = H.ns, H.fire, H.check
local guids, logArgs = H.guids, H.logArgs

local combatStream, lootStream = ns.CombatFeed.Stream(), ns.LootFeed.Stream()

-- The feed ships off and the switch is what builds the column, so it goes on
-- here and back to what it was at the foot of the file. 31-feeds.lua does the
-- same dance above and for the same reason.
local shippedCollect, shippedShown = ns.db.combatFeed, ns.db.combatFeedShown
local shippedWidth, shippedLoot = ns.db.combatFeedWidth, ns.db.lootFeedWidth
ns.db.combatFeed, ns.db.combatFeedShown = true, true
ns.Stream.Each("Apply")
ns.CombatFeed.Apply()

local combat = combatStream:Feed()
check(combat ~= nil, "turning the combat feed on built no column")

-- The sections above leave a player in the roster and this block is about what
-- was done to him, so the GUID is put back the way 31-feeds.lua puts it back:
-- through the event Core/CombatLog.lua reads it on.
guids.player = "Player-0-0000000f"
fire("PLAYER_ENTERING_WORLD")
ns.Unit.Roster.Build()
local me = _G.UnitGUID("player")
check(me ~= nil, "the player has no GUID, so nothing in the log is his")

local FRAME = 1 / 60

-- One swing on you, driven through the twenty-one values the client answers
-- with, and the row it landed on. The note on an incoming swing is the
-- preposition and the name of whatever swung, which is the longest thing this
-- feed ever writes into that column.
local function swing(name, amount)
	for index = 1, 21 do
		logArgs[index] = nil
	end
	logArgs[1] = GetTime()
	logArgs[2] = "SWING_DAMAGE"
	logArgs[4] = "Creature-77"
	logArgs[5] = name
	logArgs[8] = me
	logArgs[9] = "Baudin"
	logArgs[12] = amount
	fire("COMBAT_LOG_EVENT_UNFILTERED")
	local tick = combat.frame:GetScript("OnUpdate")
	if tick then
		tick(combat.frame, FRAME)
	end
	return combat:Row(1)
end

-- The feed at the width it ships at, which is where this was found.
combat:Clear()
local row = swing("Plains Creeper", 137)
check(combat:At(0).note == "from Plains Creeper",
	"the widest thing this feed says is not what arrived: "
		.. tostring(combat:At(0).note))
check(row.note:GetText() == "from Plains Creeper",
	"the string never reached the row, so what follows is about nothing: "
		.. tostring(row.note:GetText()))

local wide, room = row.note:GetStringWidth(), row.notemax
check(wide > room,
	("the note measures %.1f and the column is %.1f wide, so nothing here is clipping")
		:format(wide, room))
check(not row.note:IsShown(),
	("a note of %.1f is drawn in a column of %.1f, so the row ends mid-word")
		:format(wide, room))

-- The other half of the sentence, and the one that makes this a fault in the
-- number rather than in the feed: the widest the panel allows grants the whole
-- ask and the ask is too small.
ns.db.combatFeedWidth = 520
combatStream:Apply()
check(row.notemax == combatStream.note,
	("the widest feed the panel allows gives the column %.1f of the %d units the stream asks for")
		:format(row.notemax, combatStream.note))
check(not row.note:IsShown(),
	("the note measures %.1f and the whole ask is %d, and it drew anyway")
		:format(wide, combatStream.note))

-- A note that fits. Everything above passes on a rule that hid the column and
-- never looked at it, and this is the assertion that tells those apart.
ns.db.combatFeedWidth = shippedWidth
combatStream:Apply()
combat:Clear()
row = swing("Boar", 24)
check(row.note:GetText() == "from Boar",
	"the short note did not reach the row: " .. tostring(row.note:GetText()))
check(row.note:GetStringWidth() <= row.notemax,
	("a four letter mob measures %.1f in a column of %.1f, so this proves nothing")
		:format(row.note:GetStringWidth(), row.notemax))
check(row.note:IsShown(),
	"a note that fits its column is not drawn, so every middle column in the addon is empty")

-- The same note at the narrowest feed the panel allows. Nothing about the
-- string changed and the answer has to, which is the whole reason the rule is
-- in Feed:Resize rather than a shorter phrase in Feeds/Combat.lua.
ns.db.combatFeedWidth = 200
combatStream:Apply()
check(row.note:GetStringWidth() > row.notemax,
	("the narrowest feed still holds the note at %.1f in %.1f, so this proves nothing")
		:format(row.note:GetStringWidth(), row.notemax))
check(not row.note:IsShown(),
	"the note a wide feed held is still drawn at the narrow end, where it does not fit")

ns.db.combatFeedWidth = shippedWidth
combatStream:Apply()
check(row.note:IsShown(),
	"the note did not come back when the feed was given its width again")

-- And at a second text size, which is the half a width sweep cannot say. A rule
-- that counted characters against a constant passes everything above and fails
-- here: the string is the one that was drawn a moment ago.
do
	local path, size, flags = row.note:GetFont()
	check(size ~= nil, "the row's note carries no font, so there is no size to move")

	row.note:SetFont(path, size + 6, flags)
	combatStream:Apply()
	check(not row.note:IsShown(),
		("the same note at %d pixels measures %.1f in a column of %.1f and drew anyway")
			:format(size + 6, row.note:GetStringWidth(), row.notemax))

	row.note:SetFont(path, size, flags)
	combatStream:Apply()
	check(row.note:IsShown(),
		("the note did not come back at %d pixels, where it measures %.1f in %.1f")
			:format(size, row.note:GetStringWidth(), row.notemax))
end

----------------------------------------------------------------------
-- The feed that does not clip
--
-- Item 86 cut the loot feed's phrase to a quest count and sized the column
-- against the widest count an objective can carry, and this is the claim the
-- two have to keep agreeing on. The count is measured on the combat row's own
-- string rather than on a ruler this section invented, because both rows are
-- built by UI/Feed.lua at one size in one face and a second ruler is a second
-- thing to keep true.
--
-- Both ends of the loot feed's own width, because the column is 48 at the top
-- and 41 at the panel's floor, and 41 is the number item 86 said a four digit
-- count still fits in.
----------------------------------------------------------------------

do
	local loot = lootStream:Feed()
	local ruler, held = row.note, row.note:GetText()
	ruler:SetText("0/100")
	local widest = ruler:GetStringWidth()
	ruler:SetText(held)

	check(widest <= loot:Row(1).notemax,
		("the widest quest count measures %.1f and the loot column is %.1f")
			:format(widest, loot:Row(1).notemax))

	ns.db.lootFeedWidth = 200
	lootStream:Apply()
	check(widest <= loot:Row(1).notemax,
		("dragged to the panel's floor the loot column is %.1f and the count is %.1f")
			:format(loot:Row(1).notemax, widest))

	ns.db.lootFeedWidth = shippedLoot
	lootStream:Apply()
end

-- The combat feed back to shipping off, and the collection with it, so the
-- sections below read the client the addon hands a player.
combat:Clear()
ns.db.combatFeed, ns.db.combatFeedShown = shippedCollect, shippedShown
ns.Stream.Each("Apply")
ns.CombatFeed.Apply()

print(("note   the combat feed asks for %d units, gets %d at the width it ships at"
	.. " and its widest string wants more than either; the loot feed's %d holds its count")
	:format(combatStream.note, row.notemax, lootStream.note))
