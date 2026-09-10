---
revision: 4
id: 01M25AMYXABSYF4QDD8FH7BC9A
---

Cause. UI/Scan.lua called SetOwner on its hidden GameTooltip once, in Frame. A hidden GameTooltip drops its owner and an unowned one writes nothing, so once the client hid the scanner NumLines stayed at 0 for the session: every hover showed its title only and Bags/Bags.lua read every bound item as unbound. The harness stub never lost an owner, so the path passed there.  Fix. d428655. Ask calls SetOwner(UIParent, "ANCHOR_NONE") before every question, as TitanRepair does before each read.  Gate. 11-tooltip.lua clears the owner on Hide and answers nothing from an unowned setter; 48-tooltips.lua hides the scanner and requires the next bag hover to read Aegis and Soulbound. check.sh 0 warnings, 0 errors; pre-commit hook green. Not yet seen in the client: which client call hides the scanner on a new item is inferred, not observed.
