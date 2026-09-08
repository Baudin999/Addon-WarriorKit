---
revision: 1
id: 01M20K8R89MA4N1HHW572RVAHX
---

Landed at d23d3f8.

Cause. SoftTargetForce was never written. It is the CVar that makes the soft target the real target, its client default is 1, so owning SoftTargetEnemy alone read as working on a default client and as broken elsewhere. On top of that the combat split wrote SoftTargetEnemy to 0 at PLAYER_REGEN_DISABLED, which took the forced target with it one second into every fight.

Fix. Aim.lua owns OWNED, a list of {cvar, value}, writes SoftTargetEnemy=3 then SoftTargetForce=1, reads each back, and has no combat branch at all. MatchLocked defaults to 1 and is the client's own answer to the camera wandering, so the split had nothing left to justify it. REGEN_DISABLED unregistered; REGEN_ENABLED kept as the refused-write retry. softPrior -> aimPrior as a table keyed by CVar name, softPrior added to RETIRED.

Gate. check.sh exit 0, 0 warnings and 0 errors in 269 files, harness green on every class it runs. Diffed the log against the previous green run: the only changes are the intended status wording and one font string count.

Watch for. The line ceiling on harness/client/02-text.lua is 776 and the file is at it, so the seeding for this went in the section rather than the stub. Do not raise that number to make room.
