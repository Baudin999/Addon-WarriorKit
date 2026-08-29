-- The tooltip, as a part rather than as a box
--
-- Every other section that touches a tooltip does it through the thing that
-- opened one: a feed row, a nag square, an action square. That is the right way
-- round and it is why the schema is asserted there rather than here. What none
-- of them can see is the part itself.
--
--   The bands. A tooltip is a head, a body, what everything else in the addon
--   has to say, and a hint, always in that order, with air between two bands
--   that both have something in them and nowhere else. Every caller used to
--   decide that for itself and no two agreed, which is a defect visible only
--   with two boxes on screen one after the other and invisible in every file.
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
	check(Box.IsShown(), "a subject with a title, two facts and a hint opened nothing")
	check(Box.Owner() == owner, "the tooltip is not anchored to the thing it describes")
	check(#said == 5, ("five lines were described and %d were drawn"):format(#said))
	check(said[1] == "A title", "the title is not the first line: " .. tostring(said[1]))

	-- The one shape the loot feed and the cooldown row disagreed about. The
	-- title already has a hairline under it and the air either side of that, so
	-- a spacer on top of it is two separators doing one job.
	check(said[2] == "A fact",
		"there is air between the title and the body, and the hairline is already there: "
			.. tostring(said[2]))
	check(said[3] == "Label", "the paired line did not follow the plain one: " .. tostring(said[3]))
	check(said[4] == "", "the hint is not spaced off the body it follows")
	check(said[5] == "Press it.", "the hint is not the last line: " .. tostring(said[5]))

	-- A caller with nothing in one band gets no air where that band would be.
	-- A title and a hint and nothing between them is two lines: the air belongs
	-- between the bands under the head, and the head has its hairline.
	Tip.Open(owner, { kind = "note", title = "Alone", hint = "Type it." })
	said = drawn()
	check(#said == 2, ("a title and a hint drew %d lines rather than two"):format(#said))
	check(said[2] == "Type it.",
		"a band with nothing in it left its air behind: " .. tostring(said[2]))

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
		hint = "Press it.",
		probe = "here",
	})
	said = drawn()
	check(#said == 6, ("the source's line did not land: %d lines"):format(#said))
	check(said[2] == "A fact" and said[4] == "Probe",
		"a source wrote into the body rather than after it: " .. table.concat(said, " / "))
	check(said[3] == "" and said[5] == "",
		"the source's band is not spaced off the two it sits between")
	check(said[6] == "Press it.", "a source displaced the hint from the end")

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

	check(Box.Docked(), "the box does not dock out of the box, and that is where the game puts one")

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
	check(Box.SetDocked(false), "turning the dock off reported that nothing moved")
	Tip.Open(owner, { kind = "note", title = "Beside it", lines = { { "A fact" } } })
	check(pixels(box, "GetLeft") >= pixels(owner, "GetRight"),
		"undocked, the box did not open beside the thing it describes")
	check(pixels(screen, "GetRight") - pixels(box, "GetRight") > 13 * scale + 1,
		"undocked, the box still landed in the corner")

	check(Box.SetDocked(true), "turning the dock back on reported that nothing moved")
	check(Box.SetDocked(true) == false, "docking a box that is already docked moved it anyway")
	check(math.abs((pixels(screen, "GetRight") - pixels(box, "GetRight")) - 13 * scale) < 1,
		"a box that was up when the switch flipped stayed where it was")

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
	Box.Close()

	print(("tips   %d bands, %d sources hooked in, %s")
		:format(3, #Tip.Sources(), ns.UI.Scan.Describe()))
end
