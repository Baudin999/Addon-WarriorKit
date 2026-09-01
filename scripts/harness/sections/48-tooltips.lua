-- The tooltip, as a part rather than as a box
--
-- Every other section that touches a tooltip does it through the thing that
-- opened one: a feed row, a nag square, an action square. That is the right way
-- round and it is why the schema is asserted there rather than here. What none
-- of them can see is the part itself.
--
--   The bands. A tooltip is a head, a body and what everything else in the
--   addon has to say, always in that order, with air between two bands that
--   both have something in them and nowhere else. Every caller used to decide
--   that for itself and no two agreed, which is a defect visible only with two
--   boxes on screen one after the other and invisible in every file.
--
--   There is no fourth band and there is a check that says so. `hint` was one
--   blue line at the bottom of every box naming the switch that silences the
--   thing, and by twenty five call sites it was furniture. A caller that still
--   passes one gets nothing drawn for it, which is what the check asserts:
--   dropping the band without dropping the field would have left a quiet
--   difference between the call sites that had been cleaned up and the ones
--   that had not.
--
--   The hook. A part registers a source once at load and its line lands on
--   every tooltip about that kind of thing, wherever in the addon the thing was
--   hovered. That claim cannot be made from inside the feed that used to own
--   the line.
--
--   The client's own words. UI/Scan.lua points a hidden GameTooltip at an item
--   and reads the font strings back, because the stats are computed inside the
--   game and no API hands them over. Both outcomes are here: a link the client
--   answers about, and one it raises on, which is what somebody typing an item
--   name by hand produces.

local H = ...
local ns, check = H.ns, H.check

do
	local Tip, Box = ns.Tip, ns.UI.Tooltip
	local owner = CreateFrame("Frame", nil, _G.UIParent)
	owner:SetSize(30, 30)
	owner:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)

	-- Every line of the last thing drawn, left side only, as one string per
	-- line. Read off the box rather than off Tip.Build, because what is being
	-- asserted is the order things landed in on screen.
	local function drawn()
		local lines = {}
		for index = 1, Box.Lines() do
			lines[index] = Box.Text(index) or ""
		end
		return lines
	end

	------------------------------------------------------------------
	-- The bands
	------------------------------------------------------------------

	Tip.Open(owner, {
		kind = "note",
		title = "A title",
		lines = { { "A fact" }, { "Label", "value" } },
		hint = "Press it.",
	})

	local said = drawn()
	check(Box.IsShown(), "a subject with a title and two facts opened nothing")
	check(Box.Owner() == owner, "the tooltip is not anchored to the thing it describes")
	check(#said == 3, ("three lines were described and %d were drawn"):format(#said))
	check(said[1] == "A title", "the title is not the first line: " .. tostring(said[1]))

	-- The one shape the loot feed and the cooldown row disagreed about. The
	-- title already has a hairline under it and the air either side of that, so
	-- a spacer on top of it is two separators doing one job.
	check(said[2] == "A fact",
		"there is air between the title and the body, and the hairline is already there: "
			.. tostring(said[2]))
	check(said[3] == "Label", "the paired line did not follow the plain one: " .. tostring(said[3]))

	-- And the band that is gone. The subject above carried a hint and the box
	-- drew three lines, so nothing was written for it and no air was left where
	-- it used to sit.
	Tip.Open(owner, { kind = "note", title = "Alone", hint = "Type it." })
	said = drawn()
	check(#said == 1, ("a title and a hint drew %d lines rather than one"):format(#said))
	check(said[1] == "Alone",
		"the hint band is gone and something was still drawn for it: " .. tostring(said[1]))

	------------------------------------------------------------------
	-- Nothing to say draws nothing
	--
	-- The answer to a row whose entry has gone and to a nag square with
	-- nothing to nag about. Without the refusal the last hover's sentence
	-- stays on screen pointing at this one.
	------------------------------------------------------------------

	check(Tip.Build({ kind = "note" }) == nil, "an empty subject described a box anyway")
	check(Tip.Build({ kind = "gibberish", title = "x" }) == nil,
		"a subject of a kind nothing registered against was described anyway")
	check(Tip.Open(owner, nil) == false, "a hover handed nothing still opened")
	check(not Box.IsShown(), "a hover handed nothing left the last one on screen")

	------------------------------------------------------------------
	-- The hook
	------------------------------------------------------------------

	local shipped = #Tip.Sources()
	check(shipped >= 1,
		"nothing in the addon hooks into the tooltips, so the registry is a registry of nothing")

	Tip.Source({
		name = "harness probe",
		kind = "note",
		band = "extra",
		order = 9901,
		-- Only for a subject that asked for it, because this stays registered
		-- for the rest of the run and a source that answered every note would
		-- be rewriting every tooltip after this line.
		fill = function(subject)
			if not subject.probe then
				return nil
			end
			return { { "Probe", subject.probe } }
		end,
	})
	check(#Tip.Sources() == shipped + 1, "registering a source did not add one")

	Tip.Open(owner, {
		kind = "note",
		title = "A title",
		lines = { { "A fact" } },
		probe = "here",
	})
	said = drawn()
	check(#said == 4, ("the source's line did not land: %d lines"):format(#said))
	check(said[2] == "A fact" and said[4] == "Probe",
		"a source wrote into the body rather than after it: " .. table.concat(said, " / "))
	check(said[3] == "",
		"the source's band is not spaced off the body above it")

	-- A source that answers nothing costs nothing. The same subject without
	-- the field the probe reads draws exactly what it drew before the source
	-- existed.
	Tip.Open(owner, { kind = "note", title = "A title", lines = { { "A fact" } } })
	check(#drawn() == 2, "a source with nothing to say still took a line")

	-- A source registered against every kind. One line hooked onto everything
	-- the addon can describe, which is what "*" is for and is the only reason a
	-- part would want it: a fact that is true of a thing whatever kind of thing
	-- it is. Guarded on a field for the reason the probe above is.
	Tip.Source({
		name = "harness everything",
		kind = "*",
		band = "body",
		order = 9902,
		fill = function(subject)
			return subject.probe and { { "Everywhere" } } or nil
		end,
	})

	Tip.Open(owner, { kind = "note", title = "A title", probe = "here" })
	said = drawn()
	check(said[2] == "Everywhere",
		"a source registered for every kind said nothing about a note: "
			.. table.concat(said, " / "))

	Tip.Open(owner, { kind = "item", link = "Aegis", title = "Aegis", probe = "here" })
	said = drawn()
	check(said[2] == "Everywhere",
		"a source registered for every kind said nothing about an item: "
			.. table.concat(said, " / "))

	-- What a source may not do. Registering into the head would let one part
	-- retitle another part's tooltip, and two sources at one number in one band
	-- are drawn in whatever order the TOC happens to load them in.
	local titled = pcall(Tip.Source, { name = "retitle", kind = "note",
		band = "head", order = 1, fill = function() end })
	check(not titled, "a source was allowed to register into the head band")

	local collided, why = pcall(Tip.Source, { name = "collision", kind = "note",
		band = "extra", order = 9901, fill = function() end })
	check(not collided, "two sources took the same order in one band")
	check(type(why) == "string" and why:find("harness probe", 1, true) ~= nil,
		"the collision does not name the source it collided with: " .. tostring(why))

	------------------------------------------------------------------
	-- Where the box opens
	--
	-- Docked out of the box, in the corner the client keeps its own tooltip in,
	-- and beside the owner once the setting says beside. The corner is read off
	-- the client's own two clearances, so what is asserted is the arithmetic
	-- rather than a pair of numbers: the gap on the right is the thirteen units
	-- the client's default anchor adds, the gap underneath is the clearance it
	-- keeps for the bags, and both are measured in screen pixels because the
	-- box sits on the addon's grid at a scale of its own and a comparison that
	-- skipped that scale would pass against a box docked to the wrong number.
	--
	-- The stub stands UIParent up with no size at all, so the corner is the
	-- origin and both gaps would be the same number as every other frame's.
	-- This gives the screen a size for the length of the claim and hands it
	-- straight back, the way 49-world-hover.lua does for the side the box
	-- picks: a size left behind moves the mirror line 15-skin-fit.lua measures
	-- its blocks against.
	------------------------------------------------------------------

	local function pixels(region, method)
		return ns.Measure(region, method) * region:GetEffectiveScale()
	end

	check(Box.Place() == Box.DOCK,
		"the box does not dock out of the box, and that is where the game puts one")

	local screen = _G.UIParent
	screen:SetSize(2560, 1440)
	local scale = screen:GetEffectiveScale()

	Tip.Open(owner, { kind = "note", title = "In the corner", lines = { { "A fact" } } })
	local box = Box.Frame()
	check(math.abs((pixels(screen, "GetRight") - pixels(box, "GetRight")) - 13 * scale) < 1,
		("the docked box sits %s pixels off the right edge rather than thirteen units")
			:format(tostring(pixels(screen, "GetRight") - pixels(box, "GetRight"))))
	check(math.abs((pixels(box, "GetBottom") - pixels(screen, "GetBottom")) - 70 * scale) < 1,
		("the docked box sits %s pixels off the bottom rather than clear of the bags")
			:format(tostring(pixels(box, "GetBottom") - pixels(screen, "GetBottom"))))

	-- The owner is at the centre of the screen, so a box beside it is nowhere
	-- near the corner. Both claims are made about the same hover, because what
	-- the switch changes is where one box goes and nothing else.
	check(Box.SetPlace(Box.BESIDE), "turning the dock off reported that nothing moved")
	Tip.Open(owner, { kind = "note", title = "Beside it", lines = { { "A fact" } } })
	check(pixels(box, "GetLeft") >= pixels(owner, "GetRight"),
		"undocked, the box did not open beside the thing it describes")
	check(pixels(screen, "GetRight") - pixels(box, "GetRight") > 13 * scale + 1,
		"undocked, the box still landed in the corner")

	check(Box.SetPlace(Box.DOCK), "turning the dock back on reported that nothing moved")
	check(Box.SetPlace(Box.DOCK) == false, "docking a box that is already docked moved it anyway")
	check(Box.SetPlace("gibberish") == false and Box.Place() == Box.DOCK,
		"a word the box does not know moved it somewhere rather than leaving it in the corner")
	check(math.abs((pixels(screen, "GetRight") - pixels(box, "GetRight")) - 13 * scale) < 1,
		"a box that was up when the switch flipped stayed where it was")

	------------------------------------------------------------------
	-- The placement a hover names for itself
	--
	-- The setting answers one question: where does a box go when there is
	-- nothing on screen to put it beside. A creature in the world, a row of
	-- text in a feed. It is the wrong question for a box about an object you
	-- are pointing at, and every one of those hovers says so at the call site:
	-- an aura icon, an action square, a worn piece on the character panel, an
	-- attachment slot in the mail. The box there is that object's label.
	--
	-- The setting is on the corner for all three claims below, because what is
	-- being asserted is that it does not get a vote.
	------------------------------------------------------------------

	Tip.Open(owner, { kind = "note", title = "On the square", lines = { { "A fact" } } },
		nil, Box.BESIDE)
	check(pixels(box, "GetLeft") >= pixels(owner, "GetRight"),
		"a hover that asked for its box beside it was docked into the corner anyway")
	check(Box.Placed() == Box.BESIDE,
		("the box reports it went %s rather than beside the thing it describes")
			:format(tostring(Box.Placed())))

	-- And the hover after it, which asked for nothing, is back in the corner.
	-- Without this the override is a fourth way to change the setting: the box
	-- would keep the last word it was handed and every ordinary hover for the
	-- rest of the session would follow the last bag square you looked at.
	Tip.Open(owner, { kind = "note", title = "In the corner", lines = { { "A fact" } } })
	check(math.abs((pixels(screen, "GetRight") - pixels(box, "GetRight")) - 13 * scale) < 1,
		"an ordinary hover took the placement the hover before it had asked for")
	check(Box.Placed() == Box.DOCK,
		"a hover that named no placement did not fall back to the setting")

	-- A word the box does not know is the setting, not nowhere. Same answer
	-- SetPlace gives one, and for a nearer reason: this one comes off a call
	-- site rather than out of an account file, and a typo there should cost a
	-- tooltip in the wrong corner rather than a tooltip that never opens.
	Tip.Open(owner, { kind = "note", title = "Gibberish", lines = { { "A fact" } } },
		nil, "sideways")
	check(math.abs((pixels(screen, "GetRight") - pixels(box, "GetRight")) - 13 * scale) < 1,
		"a placement the box does not know put it somewhere rather than where the setting says")

	screen:SetSize(0, 0)

	------------------------------------------------------------------
	-- The client's own words, in the addon's box
	------------------------------------------------------------------

	local link = _G.WarriorKitItemLink("Aegis")
	H.tooltips.item[link] = {
		{ "Aegis", nil, { 0, 1, 0 } },
		{ "Binds when picked up" },
		{ "Requires level 60", "Shield" },
	}

	-- The title is deliberately wrong. What the client says wins, and a caller
	-- that had it right either way would not prove that.
	Tip.Open(owner, { kind = "item", link = link, title = "not this" })
	said = drawn()
	check(said[1] == "Aegis",
		"the client's own first line is not the title: " .. tostring(said[1]))
	check(said[3] == "Requires level 60",
		"the client's third line is missing: " .. tostring(said[3]))
	local _, side = Box.Text(3)
	check(side == "Shield", "the right hand side of a scanned line was dropped: " .. tostring(side))
	check(ns.UI.Scan.Describe():find("addon's chrome", 1, true) ~= nil,
		"the scanner does not report that it is working: " .. ns.UI.Scan.Describe())

	-- The vendor and auction lines, on an item that never went near the loot
	-- feed. That is the whole of what moving them into a source bought: the
	-- feed knew what a drop was worth and nothing else in the addon did.
	Tip.Open(owner, { kind = "item", link = link, price = 4500, count = 3 })
	said = drawn()
	local worth = false
	for index = 1, #said do
		if said[index] == "Vendor" then
			worth = true
		end
	end
	check(worth, "an item hovered outside the loot feed says nothing about what it is worth")

	-- A link somebody typed by hand. The client raises on one rather than
	-- coming back empty, which is why every setter in UI/Scan.lua is pcalled,
	-- and the caller's own title has to stand where that happens.
	check(ns.UI.Scan.Read("item", "Aegis") == nil, "a malformed link came back with text on it")
	Tip.Open(owner, { kind = "item", link = "Aegis", title = "Aegis" })
	check(Box.Text(1) == "Aegis",
		"a malformed link did not fall back to the name: " .. tostring(Box.Text(1)))

	-- A spell nobody is carrying, which is the kind the nag row reads with and
	-- the one kind here whose subject is at no place at all. There is no aura
	-- index for an aura that is not on you, and the id is the only handle left.
	H.tooltips.spell[20572] = {
		{ "Blood Fury" },
		{ "Increases attack power. Lasts 15 sec." },
	}
	check(ns.UI.Scan.Ready("spell"), "the scanner will not ask this client about a spell id")
	Tip.Open(owner, { kind = "spell", spell = 20572, title = "not this" })
	check(Box.Text(1) == "Blood Fury",
		"a spell id did not read the client's own name: " .. tostring(Box.Text(1)))

	-- The client that has no setter for it, which is every one before Wrath and
	-- is the reason the caller keeps writing a title it usually never draws.
	--
	-- Written false rather than nil, because a frame here answers a no-op
	-- function for any PascalCase key it has never heard of and nil would fall
	-- straight through to that. False is a value the frame has, and it is what
	-- both guards in UI/Scan.lua actually read: not whether the key is there but
	-- whether it is a function.
	local scanner = _G["WarriorKitTooltipScan"]
	local setter = scanner and rawget(scanner, "SetSpellByID")
	check(type(setter) == "function", "the scanner never built a tooltip to ask with")
	scanner.SetSpellByID = false
	check(ns.UI.Scan.Ready("spell") == false,
		"a client with no setter for a spell id was reported ready anyway")
	check(ns.UI.Scan.Read("spell", 20572) == nil, "a missing setter answered text")
	Tip.Open(owner, { kind = "spell", spell = 20572, title = "Blood Fury" })
	check(Box.Text(1) == "Blood Fury",
		"an older client lost the name the caller knew: " .. tostring(Box.Text(1)))
	scanner.SetSpellByID = setter
	H.tooltips.spell[20572] = nil

	H.tooltips.item[link] = nil
	Box.Close(true)

	------------------------------------------------------------------
	-- What you are wearing, beside what you are pointing at
	--
	-- Shift held over a piece of gear is how anybody has decided whether a drop
	-- is an upgrade since the day this game shipped, and it went quiet the
	-- moment the addon started drawing its own box: the client's comparison
	-- lives inside GameTooltip, in two more parchments it fills from its own
	-- OnUpdate, and none of it is reachable from a box somebody else drew.
	--
	-- Five claims, and the fifth is the one no hover can make on its own.
	--
	--   Off without the key. A comparison is a fact about what you are holding
	--   down, not about the item, and a box that always carried one would be
	--   two boxes on every bag square.
	--   One slot, one box; two slots, two. A ring is either finger and a
	--   comparison against one of them is the wrong finger half the time.
	--   A slot with nothing in it draws nothing, because an empty finger is the
	--   absence of a comparison rather than one worth reading.
	--   Nothing you can wear gets none at all.
	--   The key alone redraws the box. The pointer has not moved and no OnEnter
	--   is coming, so ns.Tip.Again is the whole of the gesture and it is the
	--   half that cannot be reached by hovering.
	------------------------------------------------------------------

	-- Two pieces this character is not wearing, because the hovered item and the
	-- worn one have to be different objects. A link is the whole item down to
	-- its enchant, so hovering the helmet already on your head is one object
	-- seen twice and is dropped on purpose; a fixture that reused the worn
	-- link would be asserting that case while claiming to assert this one.
	H.ITEMS["Helm of the Second"] = { id = 4101, classId = 4,
		equip = "INVTYPE_HEAD", icon = "Interface\\Icons\\Helm", quality = 3 }
	H.ITEMS["Ring of the Second"] = { id = 4102, classId = 4,
		equip = "INVTYPE_FINGER", icon = "Interface\\Icons\\Ring", quality = 3 }
	H.ITEMS["Band of the Third"] = { id = 4103, classId = 4,
		equip = "INVTYPE_FINGER", icon = "Interface\\Icons\\Ring", quality = 3 }

	local helm = _G.WarriorKitItemLink("Helm of the Second")
	local ring = _G.WarriorKitItemLink("Ring of the Second")
	local cloth = _G.WarriorKitItemLink("Linen Cloth")

	-- What the client says about the two pieces already on: the compare box is
	-- built from the same scan every other item hover is, so a worn slot the
	-- client has nothing to say about draws nothing at all.
	H.tooltips.inventory[H.tooltipKey("player", 1)] = {
		{ "Lionheart Helm" }, { "Head, Plate" },
	}
	H.tooltips.inventory[H.tooltipKey("player", 11)] = {
		{ "Band of the Eternal" }, { "Finger" },
	}
	H.tooltips.item[helm] = { { "Helm of the Second" }, { "Head, Plate" } }
	H.tooltips.item[ring] = { { "Ring of the Second" }, { "Finger" } }
	H.tooltips.item[cloth] = { { "Linen Cloth" } }

	_G.WarriorKitShift(false)
	Tip.Open(owner, { kind = "item", link = helm })
	check(Box.Alongside() == 0,
		("a hover with no key held opened %d boxes beside it")
			:format(Box.Alongside()))
	check(Box.Frame(2) == nil, "a box nobody asked for was handed out anyway")

	-- One worn helmet, one box, and it is the worn one rather than the hovered
	-- one. Both are called something different on purpose: a compare box that
	-- echoed the item under the cursor would pass an assertion that only read
	-- the count.
	_G.WarriorKitShift(true)
	Tip.Open(owner, { kind = "item", link = helm })
	check(Box.Alongside() == 1,
		("shift over a helmet opened %d boxes beside it rather than one")
			:format(Box.Alongside()))
	check(Box.Text(1) == "Helm of the Second",
		"the main box stopped describing the thing under the cursor: "
			.. tostring(Box.Text(1)))
	check(Box.Text(1, 2) == "Lionheart Helm",
		"the box beside it does not name the helmet you are wearing: "
			.. tostring(Box.Text(1, 2)))
	check(Box.IsShown(2), "the compare box was drawn and never shown")

	-- Docked, so the main box is in the bottom right corner and there is no room
	-- on that side. The comparison goes the other way or it goes off the screen.
	check(Box.Place() == Box.DOCK, "the scene is not set: the box is not docked")
	check(ns.Measure(Box.Frame(2), "GetRight") <= ns.Measure(Box.Frame(), "GetLeft") + 1,
		"the compare box did not open clear of the left edge of the box it belongs to")

	-- The second ring is empty, so a ring still opens one box rather than two.
	-- This is the claim that says the empty slot is skipped rather than drawn.
	Tip.Open(owner, { kind = "item", link = ring })
	check(Box.Alongside() == 1,
		("a ring with one finger filled opened %d boxes"):format(Box.Alongside()))

	-- Fill the other finger and it is two, which is the whole reason
	-- Gear.Replaces answers a list.
	H.worn[12] = _G.WarriorKitItemLink("Band of the Third")
	H.tooltips.inventory[H.tooltipKey("player", 12)] = {
		{ "Band of the Third" }, { "Finger" },
	}
	Tip.Open(owner, { kind = "item", link = ring })
	check(Box.Alongside() == 2,
		("a ring with both fingers filled opened %d boxes rather than two")
			:format(Box.Alongside()))
	check(Box.Text(1, 3) == "Band of the Third",
		"the second compare box does not name the second ring: "
			.. tostring(Box.Text(1, 3)))
	check(Box.Text(1, 4) == nil, "a third box was handed out for a second ring")

	-- Nothing you can put on gets nothing, whatever is held down.
	Tip.Open(owner, { kind = "item", link = cloth })
	check(Box.Alongside() == 0,
		("shift over a stack of cloth opened %d boxes"):format(Box.Alongside()))

	-- The one hander, which is the only equip location whose answer depends on
	-- something other than the item. Both hands where the client says you may
	-- hold two, the main hand alone where it says you may not, and both again
	-- where it has no such call: that last one is the fallback and it is the
	-- generous way round on purpose, because a comparison nobody wanted is a
	-- box you ignore and one that never appears is a feature that looks broken.
	H.ITEMS["Blade of the Second"] = { id = 4104, classId = 2,
		equip = "INVTYPE_WEAPON", icon = "Interface\\Icons\\Sword", quality = 3 }
	local blade = _G.WarriorKitItemLink("Blade of the Second")
	local dual = _G.CanDualWield

	_G.CanDualWield = function() return true end
	check(#ns.Gear.Replaces(blade) == 2,
		("a one hander offered %d hands to a character who dual wields")
			:format(#ns.Gear.Replaces(blade)))

	_G.CanDualWield = function() return false end
	local one = ns.Gear.Replaces(blade)
	check(#one == 1 and one[1] == ns.Gear.MAINHAND,
		"a one hander was offered an off hand this character cannot fill")

	_G.CanDualWield = nil
	check(#ns.Gear.Replaces(blade) == 2,
		"a client with no such call refused the hand rather than offering it")
	_G.CanDualWield = dual

	local shield = ns.Gear.Replaces(_G.WarriorKitItemLink("Aegis"))
	check(#shield == 1 and shield[1] == ns.Gear.OFFHAND,
		"a shield went somewhere other than the off hand alone")
	check(#ns.Gear.Replaces(_G.WarriorKitItemLink("Arcanite Reaper")) == 1,
		"a two hander was offered an off hand three expansions early")
	check(ns.Gear.Replaces(cloth) == nil, "a stack of cloth was given a slot to go in")

	-- And the gesture itself: the box is already up, the pointer has not moved,
	-- and the key is the only thing that changed.
	_G.WarriorKitShift(false)
	Tip.Open(owner, { kind = "item", link = helm })
	check(Box.Alongside() == 0, "the scene is not set: something is already beside the box")
	_G.WarriorKitShift(true)
	H.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	check(Box.Alongside() == 1,
		"pressing shift over an open box did not open the comparison")
	check(Box.Text(1) == "Helm of the Second",
		"redrawing the box lost the thing it was about: " .. tostring(Box.Text(1)))

	_G.WarriorKitShift(false)
	H.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
	check(Box.Alongside() == 0, "letting shift go left the comparison on screen")

	-- The switch, which is the addon's own and is not the key. Off, the key does
	-- nothing at all; the client's own alwaysCompareItems is the answer for a
	-- player who wants it without holding anything.
	_G.WarriorKitShift(true)
	check(ns.Settings.SetCompare(false) == false, "turning the comparison off did not take")
	Tip.Open(owner, { kind = "item", link = helm })
	check(Box.Alongside() == 0, "the comparison is switched off and still opened a box")
	ns.Settings.SetCompare(true)
	Tip.Open(owner, { kind = "item", link = helm })
	check(Box.Alongside() == 1, "turning the comparison back on did not bring it back")
	_G.WarriorKitShift(false)

	H.worn[12] = nil
	H.tooltips.inventory[H.tooltipKey("player", 1)] = nil
	H.tooltips.inventory[H.tooltipKey("player", 11)] = nil
	H.tooltips.inventory[H.tooltipKey("player", 12)] = nil
	H.tooltips.item[helm], H.tooltips.item[ring], H.tooltips.item[cloth] = nil, nil, nil
	Box.Close(true)

	------------------------------------------------------------------
	-- How long it stays
	--
	-- Leaving a thing starts a countdown; it does not take the box down. Every
	-- hoverable thing in this addon is small and most of them sit in a column,
	-- so the pointer crosses two on the way to the one you meant and a box that
	-- closed on each of them is a box you never finish reading.
	--
	-- Three claims and the third is the one that makes the first two safe:
	-- hovering anything else replaces the box on the spot, whatever is left of
	-- the clock. A linger that made the next hover wait would be worse than no
	-- linger at all.
	------------------------------------------------------------------

	check(Box.Linger() == 1,
		("the shipped linger is %s seconds and the addon ships one"):format(tostring(Box.Linger())))

	Tip.Open(owner, { kind = "note", title = "Staying", lines = { { "A fact" } } })
	Tip.Close()
	check(Box.IsShown(), "the box went the instant the pointer left")
	check(Box.Text(1) == "Staying", "the lingering box is not the one that was up")
	check(Box.Owner() == nil,
		"the box still claims an owner it is no longer anchored to anything by")

	-- Half the clock is not the clock.
	Box.Sweep(0.5)
	check(Box.IsShown(), "half a second in, the box had already gone")
	Box.Sweep(0.6)
	check(not Box.IsShown(), "the countdown ran out and the box stayed up")

	-- Replaced at once, with most of a second still on the clock.
	Tip.Open(owner, { kind = "note", title = "First", lines = { { "A fact" } } })
	Tip.Close()
	Box.Sweep(0.1)
	Tip.Open(owner, { kind = "note", title = "Second", lines = { { "A fact" } } })
	check(Box.Text(1) == "Second",
		"a second hover did not replace the box that was counting down: "
			.. tostring(Box.Text(1)))
	check(Box.Lingering() == 0, "the new box is counting down on the old box's clock")
	Box.Sweep(2)
	check(Box.IsShown(), "the box the pointer is still on was taken down by the last clock")

	-- And a hover that describes nothing takes a lingering box with it, rather
	-- than leaving the last one on screen for another second pointing at
	-- something it is not about.
	Tip.Close()
	check(Box.IsShown(), "the scene is not set: nothing is lingering")
	check(Tip.Open(owner, nil) == false, "a hover handed nothing still opened")
	check(not Box.IsShown(), "a hover with nothing to say left the last box lingering")

	-- Zero is a real answer, and it is the client's own behaviour.
	check(Box.SetLinger(0), "turning the linger off reported that nothing moved")
	Tip.Open(owner, { kind = "note", title = "Gone", lines = { { "A fact" } } })
	Tip.Close()
	check(not Box.IsShown(), "with the linger at zero the box still held")

	-- Clamped rather than refused, because the number arrives from an account
	-- file somebody may have edited.
	local lingerLow, lingerHigh = Box.LingerRange()
	Box.SetLinger(9999)
	check(Box.Linger() == lingerHigh,
		("a linger past the ceiling landed on %s"):format(tostring(Box.Linger())))
	Box.SetLinger(-5)
	check(Box.Linger() == lingerLow,
		("a linger under the floor landed on %s"):format(tostring(Box.Linger())))
	Box.SetLinger(1)

	------------------------------------------------------------------
	-- How big it reads
	--
	-- One number, and the title takes it plus the pixel that separates the two,
	-- so the pair stays a pair at every setting. Read off the font strings the
	-- client ended up with rather than off the setting, because a size SetFont
	-- refused would come back nil and draw an empty box, which is a defect this
	-- addon has shipped once already.
	------------------------------------------------------------------

	local M = ns.UI.Metric
	check(Box.Font() == M.font,
		("the shipped tooltip body is %s and the addon's body is %d")
			:format(tostring(Box.Font()), M.font))

	Tip.Open(owner, { kind = "note", title = "Sized", lines = { { "A fact" } } })
	check(Box.Size(1) == M.heading and Box.Size(2) == M.font,
		("the shipped box drew %s over %s")
			:format(tostring(Box.Size(1)), tostring(Box.Size(2))))

	check(Box.SetFont(16), "moving the text size reported that nothing moved")
	check(Box.SetFont(16) == false, "setting the size it already had moved it anyway")
	Tip.Open(owner, { kind = "note", title = "Sized", lines = { { "A fact" } } })
	check(Box.Size(2) == 16,
		("the body was asked for 16 and drew %s"):format(tostring(Box.Size(2))))
	check(Box.Size(1) == 16 + (M.heading - M.font),
		("the title did not move with the body: %s"):format(tostring(Box.Size(1))))

	local fontLow, fontHigh = Box.FontRange()
	Box.SetFont(999)
	check(Box.Font() == fontHigh,
		("a size past the ceiling landed on %s"):format(tostring(Box.Font())))
	Box.SetFont(1)
	check(Box.Font() == fontLow,
		("a size under the floor landed on %s"):format(tostring(Box.Font())))
	Box.SetFont(M.font)

	------------------------------------------------------------------
	-- The marker
	--
	-- The third placement, and the only one that can put the box where you
	-- actually look. Which corner of the box lands on the marker is read off
	-- which quarter of the screen the marker is in, so the box always grows away
	-- from the nearest edge: a single fixed corner would be a marker you cannot
	-- use in three quarters of the screen.
	--
	-- The screen is given a size for the length of the claim and handed back,
	-- the same way the dock section above does it.
	------------------------------------------------------------------

	local anchor = ns.Settings.AnchorFrame()
	check(anchor ~= nil, "the addon builds no marker for the box to hang off")

	screen:SetSize(2560, 1440)
	Box.SetPlace(Box.ANCHOR)

	anchor:ClearAllPoints()
	anchor:SetPoint("BOTTOMLEFT", screen, "BOTTOMLEFT", 100, 100)
	Tip.Open(owner, { kind = "note", title = "On the marker", lines = { { "A fact" } } })
	check(math.abs(pixels(box, "GetLeft") - pixels(anchor, "GetLeft")) < 1,
		"the box did not take the marker's left edge in the bottom left of the screen")
	check(math.abs(pixels(box, "GetBottom") - pixels(anchor, "GetBottom")) < 1,
		"the box did not grow up from a marker sitting near the bottom edge")

	anchor:ClearAllPoints()
	anchor:SetPoint("BOTTOMLEFT", screen, "BOTTOMLEFT", 2400, 1300)
	Tip.Open(owner, { kind = "note", title = "On the marker", lines = { { "A fact" } } })
	check(math.abs(pixels(box, "GetRight") - pixels(anchor, "GetRight")) < 1,
		"the box did not take the marker's right edge in the top right of the screen")
	check(math.abs(pixels(box, "GetTop") - pixels(anchor, "GetTop")) < 1,
		"the box did not grow down from a marker sitting near the top edge")

	-- A placement with nothing to place against falls back to the corner rather
	-- than to nowhere, which is the state a client that refused the frame would
	-- leave the addon in.
	Box.SetAnchor(nil)
	Tip.Open(owner, { kind = "note", title = "No marker", lines = { { "A fact" } } })
	check(math.abs((pixels(screen, "GetRight") - pixels(box, "GetRight")) - 13 * scale) < 1,
		"the anchor placement with no marker did not fall back to the corner")

	Box.SetAnchor(anchor)
	Box.SetPlace(Box.DOCK)
	ns.Settings.ApplyAnchor()
	screen:SetSize(0, 0)
	Box.Close(true)

	print(("tips   %d bands, %d sources hooked in, %s")
		:format(3, #Tip.Sources(), ns.UI.Scan.Describe()))
	print(("tips   %s after you look away, body %d px and title %d px, %s")
		:format(ns.Settings.LingerLabel(Box.Linger()), Box.Font(),
			Box.Font() + (M.heading - M.font), ns.Settings.DescribePlace()))
	print("tips   " .. ns.Compare.Describe())
end
