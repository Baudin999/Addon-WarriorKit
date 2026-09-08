---
revision: 1
id: 01M20BBX449PX4NZACS1QK4EE6
---

Landed at b86ad9b, check.sh at 0 warnings / 0 errors and the harness green.

Quests/Where.lua: RETURN is now the pair RETURN, WAITING = "complete", "incomplete", and FromFinisher picks between them once per quest rather than per spawn. Finished(quest) is a pcall on quest:IsComplete() and takes 1 for done; false is the answer to every other case including the call being absent.

Fixture: carrying.currentQuestlog[102].IsComplete is a method over a local, and H.questFinish(state) is the switch. Deliberate -- both marks are drawable states and a stub fixed at one leaves the other untested. 47-quest-map.lua asserts grey at 0, flips to 1, asserts gold, and flips back so the sections after it read the log as they always did.

Note line in Quests/Window.lua says "grey until the quest is done" now.

Ratchet: 05-quests.lua went 830 -> 835 with the incomplete icon and the ceiling from the last commit was 832, which does not go up. Trimmed the icon table's comment from six paragraphs to four, which it wanted anyway, and lowered the ceiling to 830 in the same commit.
