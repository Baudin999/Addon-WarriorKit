---
revision: 1
id: 01M20F4RPPNGCTNG2BY6B6CD3E
---

Gate. ./scripts/check.sh at zero across all thirteen class and spec runs, luacheck 0/0 over 269 files. The new harness section is 88-other-addons; it is last because it is the only one that changes what the client says is installed and because it fires PLAYER_LOGIN a second time, which is what the notice being said once is measured on. The addon list stub moved out of client/07-chat.lua into client/24-addons.lua: a file that owns the chat had no business being the one place that knew which addons were in memory.
