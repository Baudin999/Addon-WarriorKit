---
revision: 1
id: 01M20JBHJBWZ1MMSS9KZ27E9XK
---

Landed at 7eb19be.

Cause. The class gate was in Wanted() at Charge/SoftTarget.lua:72, and the refusal was written twice more in Charge/Feature.lua, at Refuse() and at the panel's early return. Dropping only the first would have written the CVar on a mage with no way to see it or turn it off.

Fix. Charge/SoftTarget.lua -> Targeting/Aim.lua, ns.SoftTarget -> ns.Aim, and Wanted() gates on ns.db.softAuto alone. Describe() lost its Charge.Available branch. The saved keys kept their names so no value was lost and nothing needed retiring. Targeting/Feature.lua took the setting, the section under Fighting, /wk aim on|off and the status line. Charge kept SoftUnit, SoftTargetState and softProven, and its token reading moved into the marker section.

Gate. check.sh exit 0, 0 warnings and 0 errors in 269 files, harness ok. 21-which-class.lua now asserts SoftTargetEnemy == "3" on every class rather than (CHARGE and "3" or "0"), and the charge part's class page count came down from 5 to 4. Ran as both WARRIOR and MAGE.
