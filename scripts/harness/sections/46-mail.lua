-- The mail part
--
-- Six questions no amount of reading Mail/ will answer.
--
-- Does a name resolve to the right one of three. That is the whole feature in
-- one call, and the two ways it can be wrong look identical in the source: a
-- test that answers yes to everything paints the window green and warns about
-- nothing, and one that answers no to everything paints it red and warns about
-- your own bank alt until you stop reading the band.
--
-- Does more than twelve attachments become more than one mail, with the right
-- twelve in the first one. The client's form has twelve slots and fills from the
-- bags, so an addon that got this wrong would send twelve and quietly drop the
-- rest, which looks exactly like a successful send from the outside.
--
-- Does the subject write itself, per mail rather than per send. Mail two of
-- three is named after what is in mail two, and a split subject that fitted its
-- own suffix rather than being cut by the server at sixty four.
--
-- Does the send wait for the server. The state machine exists because a loop
-- would fill one form three times in one frame; a stub that answered
-- synchronously would never produce the shape it is written against, so the
-- success here is delivered by hand.
--
-- Does a refusal stop the rest. A mail the server would not take has left its
-- attachments on the form, and posting the next one on top of them would send
-- somebody else's items to this recipient.
--
-- And does the sweep count down. Taking a message renumbers the inbox, and a
-- sweep walking upwards skips every other message while reporting that it took
-- them all.

local H = ...
local ns, fire, check, mail = H.ns, H.fire, H.check, H.mail
local CARRIED, ITEMS = H.CARRIED, H.ITEMS

local Who, Draft, Send = ns.MailWho, ns.MailDraft, ns.MailSend
local Inbox, Window = ns.MailInbox, ns.MailWindow

local GOLD = 10000
local ALT, FRIEND, STRANGER = "Bankalt", "Aria", "Nobodyatall"

----------------------------------------------------------------------
-- Who a name is
----------------------------------------------------------------------

-- The three lists the answer comes off, filled the way the game fills them. The
-- ledger is Feeds/Purse.lua's and holds every character on the account; the
-- friends list is the client's; the group is Chat/People.lua's. Mail/Who.lua
-- names none of the three and Mail/Feature.lua registered two of them, which is
-- the seam being tested as much as the answer is.
ns.db.purse[ALT .. "-Elsewhere"] = 12 * GOLD
mail.friends[1] = FRIEND
Who.Rescan()

check(Who.Of(ALT) == Who.ALT,
	("%s is on the account ledger and reads as %s"):format(ALT, Who.Of(ALT)))
check(Who.Of(FRIEND) == Who.FRIEND,
	("%s is on the friends list and reads as %s"):format(FRIEND, Who.Of(FRIEND)))
check(Who.Of(STRANGER) == Who.STRANGER,
	("%s is on no list at all and reads as %s"):format(STRANGER, Who.Of(STRANGER)))
check(Who.Of(UnitName("player")) == Who.ALT, "mailing yourself reads as a stranger")

-- The realm suffix comes off and the case is flattened, which is the whole of
-- why the ledger's "Bankalt-Elsewhere" answered to "Bankalt" above.
check(Who.Of(ALT:lower() .. "-Somewhereelse") == Who.ALT,
	"a name typed in lower case with another realm on it missed the ledger")

-- A group of the addon's own is the second friend test, and it is the one that
-- had to be registered rather than called: Mail/Who.lua may not name
-- Chat/People.lua and does not.
local group = ns.People.AddGroup("Family")
ns.People.Add(group, "Wifey")
check(Who.Of("Wifey") == Who.FRIEND,
	("somebody in one of your groups reads as %s"):format(Who.Of("Wifey")))

-- Three colours, and no two of them the same. The window is unreadable if any
-- pair collides and every other check here would still pass.
local alt, friend, stranger = Who.Color(Who.ALT), Who.Color(Who.FRIEND), Who.Color(Who.STRANGER)
check(alt ~= friend and friend ~= stranger and alt ~= stranger,
	"two of the three relations are drawn in the same colour")
check(alt[2] > alt[1] and alt[2] > alt[3], "one of your own is not drawn green")
check(stranger[1] > stranger[2] and stranger[1] > stranger[3], "a stranger is not drawn red")

----------------------------------------------------------------------
-- The favourites
----------------------------------------------------------------------

check(Who.Count() == 0, "the favourites did not ship empty")
check(Who.Add(ALT) == 1, "the first favourite would not go on")
check(Who.Add(ALT) == nil, "the same name went on the list twice")
check(Who.Favourite(ALT:lower()), "a favourite is not found by a name in lower case")
check(Who.Remove(STRANGER) == false, "a name that is not on the list was removed anyway")

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

fire("MAIL_SHOW")

check(_G.WarriorKitMail ~= nil, "no mail window was built at the mailbox")
check(Window.Shown(), "the window says it is not open at a mailbox")
check(_G.WarriorKitMailFavourites:GetWidth() > 0,
	"the favourites column came out at no width")
check(Window.Rail() > 0, "a row of the favourites column came out at no width")
check(Window.Favourites() == Who.Count() + 1,
	("%d rows for %d favourites, and the last is the one that adds"):format(
		Window.Favourites(), Who.Count()))

-- The three columns, which have to add up to the window with the two pads and
-- the gutter between the last two. This is the one arithmetic error on the page
-- that every other assertion here would survive: a compose column carved out of
-- a wrong width draws over the favourites or off the right edge, and the frames
-- would still answer every question about their contents correctly.
local parts = Window.Parts()
local M = ns.UI.Metric
local spent = parts.rail:GetWidth() + parts.target:GetWidth() + parts.block:GetWidth()
	+ M.pad * 2 + M.gutter
check(spent == 640, ("the three columns and their gaps come to %d in a %d window")
	:format(spent, 640))
check(parts.target:GetWidth() > parts.block:GetWidth() / 2,
	("the target column came out %d wide against a %d attachment block, which is not a column")
		:format(parts.target:GetWidth(), parts.block:GetWidth()))

-- And six squares fit the block they are laid out in. One pixel short draws
-- five and leaves the sixth off the edge, which is a thing nothing in the
-- window would report.
local slot, gap, columns = Window.Block()
check(columns * slot + (columns - 1) * gap == parts.block:GetWidth(),
	("%d squares of %d with %d between them do not fill a %d block")
		:format(columns, slot, gap, parts.block:GetWidth()))
check(parts.grid:GetWidth() == parts.block:GetWidth(),
	("the attachment grid is %d wide inside a %d block")
		:format(parts.grid:GetWidth(), parts.block:GetWidth()))

-- Blizzard's own window is moved rather than hidden, because hiding it is what
-- closes the mailbox. Shown is the half that matters: everything the addon
-- sends goes through a frame that has to still be up.
check(_G.MailFrame:IsShown(), "Blizzard's mail frame was hidden, which closes the mailbox")
check(ns.MailBlizzard.Parked(), "Blizzard's mail frame was left where it was")

----------------------------------------------------------------------
-- What the subject writes itself as
----------------------------------------------------------------------

Draft.SetTo(ALT)
Draft.SetMoney(5 * GOLD)
check(Draft.SubjectFor(1) == "money",
	("a mail carrying only coin is titled %q"):format(Draft.SubjectFor(1)))

Draft.SetMoney(0)
check(Draft.Attach(H.itemLink("Chipped Boar Tusk")) == 1, "the first attachment would not go on")
check(Draft.SubjectFor(1) == "Chipped Boar Tusk",
	("a mail carrying one item is titled %q"):format(Draft.SubjectFor(1)))

check(Draft.Attach(H.itemLink("Tattered Cloth")) == 2, "the second attachment would not go on")
check(Draft.SubjectFor(1) == "Chipped Boar Tusk and 1 more",
	("a mail carrying two items is titled %q"):format(Draft.SubjectFor(1)))

-- What you typed always wins, and nothing the addon would have written appears
-- anywhere near it.
Draft.SetSubject("for the bank")
check(Draft.SubjectFor(1) == "for the bank",
	("a subject you typed came out as %q"):format(Draft.SubjectFor(1)))
Draft.SetSubject("")
Draft.Empty()

----------------------------------------------------------------------
-- More than one mail
--
-- Twenty stacks of the same item, dropped one at a time the way the window
-- drops them, so each one has to find its own bag slot. The bag is filled here
-- rather than borrowed, because every other section counts what is in the three
-- it already uses.
----------------------------------------------------------------------

ITEMS["Copper Ore"] = { id = 4001, classId = 7, quality = 1, price = 90 }
CARRIED[3] = {}
for slot = 1, 20 do
	CARRIED[3][slot] = "Copper Ore"
end

local ore = H.itemLink("Copper Ore")
for _ = 1, 20 do
	Draft.Attach(ore)
end
check(Draft.Held() == 20,
	("%d of twenty identical stacks went on, so two of them found the same slot")
		:format(Draft.Held()))
check(Draft.Attach(ore) == nil, "a twenty first stack went on with only twenty in the bag")

check(Draft.Mails() == 2, ("twenty attachments came to %d mails"):format(Draft.Mails()))
check(#Draft.Batch(1) == 12, ("the first mail holds %d"):format(#Draft.Batch(1)))
check(#Draft.Batch(2) == 8, ("the second mail holds %d"):format(#Draft.Batch(2)))

-- The split numbers the parts, and the number survives the sixty four character
-- cut rather than being the thing the server takes off.
Draft.SetSubject(("x"):rep(64))
local titled = Draft.SubjectFor(2)
check(#titled <= 64, ("a split subject came out %d characters long"):format(#titled))
check(titled:sub(-6) == " (2/3)" or titled:sub(-6) == " (2/2)",
	("the second part of a split is titled %q"):format(titled))
Draft.SetSubject("")

----------------------------------------------------------------------
-- The warning
----------------------------------------------------------------------

Draft.SetTo(ALT)
check(not Draft.Risky(), "a favourite carrying twenty items was called risky")
Draft.SetTo(STRANGER)
check(Draft.Risky(), "twenty items to a name on no list was not called risky")

-- A favourite who is a stranger by relation is still not risky, which is the
-- distinction the whole setting turns on: the list is what you curated and the
-- relation is what the client could work out.
Who.Add(STRANGER)
check(not Draft.Risky(), "a favourite the addon has never heard of was still called risky")
Who.Remove(STRANGER)

-- And a letter with only words on it goes anywhere without a second thought.
Draft.Empty()
Draft.SetBody("hello")
check(not Draft.Risky(), "a letter with nothing on it but words asked to be confirmed")
Draft.SetBody("")

----------------------------------------------------------------------
-- The send
----------------------------------------------------------------------

Draft.SetTo(ALT)
for _ = 1, 20 do
	Draft.Attach(ore)
end
Draft.SetMoney(3 * GOLD)
H.state.purse = 400 * GOLD

local ok, why = Send.Start()
check(ok, "the send would not start: " .. tostring(why))
check(Send.Running(), "the send says it is not running with a mail in flight")
check(#mail.sent == 1, ("%d mails went out in one frame"):format(#mail.sent))
check(#mail.sent[1].items == 12,
	("the first mail carried %d items"):format(#mail.sent[1].items))
check(mail.sent[1].money == 3 * GOLD,
	("the coin went on mail one as %d"):format(mail.sent[1].money))
check(mail.sent[1].to == ALT, "the first mail went to " .. tostring(mail.sent[1].to))

mail.deliver()
check(#mail.sent == 2, "the second mail did not follow the first one's success")
check(#mail.sent[2].items == 8,
	("the second mail carried %d items"):format(#mail.sent[2].items))
check(mail.sent[2].money == 0,
	("coin went on the second mail as well, %d of it"):format(mail.sent[2].money))

mail.deliver()
check(not Send.Running(), "the send is still running after the last mail landed")
local done, total = Send.Progress()
check(done == 2 and total == 2, ("the send finished at %d of %d"):format(done, total))
check(Draft.Held() == 0, "a finished send left its attachments on the draft")

----------------------------------------------------------------------
-- The two presses
--
-- The gate the whole window exists for, and it lives between two presses of one
-- button. Driven through Window.Press rather than through Send.Start, because
-- Send.Start is the thing the gate stands in front of and calling it directly
-- would step over the gate while reporting that a send works.
----------------------------------------------------------------------

for slot = 1, 20 do
	CARRIED[3][slot] = "Copper Ore"
end
for _ = 1, 12 do
	Draft.Attach(ore)
end
Draft.SetTo(STRANGER)
Window.Paint()

local title, said = Window.Band()
check(title:find(STRANGER, 1, true) ~= nil,
	("the band says %q with a stranger on the mail"):format(tostring(title)))
check(said:find("12 items", 1, true) ~= nil,
	("the band does not say what is riding on the letter: %q"):format(tostring(said)))

local held = #mail.sent
check(Window.Press(), "the first press on a risky send did not arm the button")
check(#mail.sent == held, "the first press on a risky send posted a mail")
check(select(2, Window.Band()):find("Press send again", 1, true) ~= nil,
	"an armed band does not say that a second press sends")

-- And anything you change disarms it, because the thing you changed is the
-- thing the warning was about. Typed into the field rather than set on the
-- draft, because the field is what a person changes and the field is what
-- carries the disarm.
parts.to.edit:SetText(ALT)
parts.to.edit:SetText(STRANGER)
check(Window.Press(), "changing the recipient left the button armed")
check(Window.Press() == false and #mail.sent > held,
	"the second press did not send")
while Send.Running() do
	mail.deliver()
end
Draft.Clear()

-- A favourite goes on one press, which is the other half of the same rule.
Draft.SetTo(ALT)
Draft.SetMoney(1 * GOLD)
held = #mail.sent
check(Window.Press() == false, "a mail to a favourite armed instead of sending")
check(#mail.sent == held + 1, "a mail to a favourite did not go on one press")
while Send.Running() do
	mail.deliver()
end

----------------------------------------------------------------------
-- The fields and the draft agree
--
-- Both directions, because they are two different bugs. A field that does not
-- reach the draft sends the wrong thing; a draft that does not reach the field
-- leaves the subject you typed on screen under a mail that has already gone,
-- and the next send picks it back up.
----------------------------------------------------------------------

parts.subject.edit:SetText("for the bank")
check(Draft.Subject() == "for the bank",
	("typing in the subject field left the draft saying %q"):format(Draft.Subject()))

Draft.SetMoney(2 * GOLD + 50 * 100)
Window.Paint()
check(parts.subject.edit:GetText() == "for the bank", "a repaint wiped the subject field")

Draft.Clear()
Window.Paint()
check(parts.subject.edit:GetText() == "",
	("a cleared draft left %q in the subject field"):format(parts.subject.edit:GetText()))

----------------------------------------------------------------------
-- A refusal
----------------------------------------------------------------------

for slot = 1, 20 do
	CARRIED[3][slot] = "Copper Ore"
end
for _ = 1, 20 do
	Draft.Attach(ore)
end
Draft.SetTo(ALT)

local before = #mail.sent
mail.refuse(true)
Send.Start()
mail.deliver()
check(not Send.Running(), "a refused mail did not stop the rest of the send")
check(#mail.sent == before + 1,
	("%d mails went out after the first was refused"):format(#mail.sent - before))
check(Draft.Held() == 20, "a refused send emptied the draft anyway")
mail.refuse(false)
Draft.Clear()

----------------------------------------------------------------------
-- The inbox
--
-- Three messages, and the sweep has to take all three. Taking the last one
-- first is what makes that possible: the client renumbers on every take, so a
-- sweep that walked upwards would take one, three, and report three taken.
----------------------------------------------------------------------

CARRIED[3] = {}
for slot = 1, 12 do
	CARRIED[3][slot] = false
end

mail.inbox[1] = { sender = ALT, subject = "ore", money = 0, items = { "Copper Ore", "Copper Ore" } }
mail.inbox[2] = { sender = FRIEND, subject = "a hello", money = 2 * GOLD, items = {} }
mail.inbox[3] = { sender = STRANGER, subject = "auction", money = 0, items = { "Linen Cloth" } }
fire("MAIL_INBOX_UPDATE")

check(Inbox.Count() == 3, ("%d messages in a mailbox of three"):format(Inbox.Count()))

-- The inbox is not drawn while you are looking at the send page, because
-- rebuilding it asks the client for every attachment on every message and Paint
-- runs on every keystroke in the recipient field. So the tab has to be chosen
-- before there is anything to count, which is also what a person does.
check(Window.Tab() == 1, "the window did not open on the send page")
check(Window.Letters() == 0, "the inbox was rebuilt while the send page was up")

Window.Tab(2)
check(Window.Page(2) and not Window.Page(1),
	"choosing the inbox tab left both pages showing or neither")
check(Window.Letters() == 3,
	("the window drew %d rows for three messages"):format(Window.Letters()))

local rows = Inbox.Rows()
check(rows[1].sender == ALT and Who.Of(rows[1].sender) == Who.ALT,
	"the message from your own alt is not coloured as one")
check(#rows[1].attachments == 2,
	("the first message lists %d attachments"):format(#rows[1].attachments))

local purse = H.state.purse
Inbox.Sweep()
check(Inbox.Count() == 0,
	("%d messages were left behind by a sweep of three"):format(Inbox.Count()))
check(H.state.purse == purse + 2 * GOLD,
	("the sweep collected %d of the two gold waiting"):format(H.state.purse - purse))
check(not Inbox.Sweeping(), "the sweep says it is still going with an empty mailbox")

----------------------------------------------------------------------
-- Walking away
----------------------------------------------------------------------

fire("MAIL_CLOSED")
check(not Window.Shown(), "the window stayed up after the mailbox closed")
check(not ns.MailBlizzard.Parked(),
	"Blizzard's mail window was left parked off screen with ours closed")

print(("mail   %s, %d favourites, %d sent this run; band %s; Blizzard's %s")
	:format(Window.Describe(), Who.Count(), #mail.sent,
		Who.Say(ALT), ns.MailBlizzard.Describe()))
