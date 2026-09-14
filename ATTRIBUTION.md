# Attribution

GearSweep does not vendor any third-party code, but one data table was
cross-referenced against a third-party source rather than derived from
memory, to avoid getting it subtly wrong.

## Class armor/weapon proficiency table (Classify.lua)

The per-class unusable-armor-subclass/unusable-weapon-subclass tables in
`Classify.lua` (used to detect things like "a Mage can't equip a shield",
`#35`) were cross-referenced against the **Unfit-1.0** library:

- Author: João Cardoso
- License: GNU General Public License v3.0
- Source: embedded in several popular addons (Bagnon, AdiBags, and
  others); see https://www.curseforge.com/wow/addons/unfit

No code from Unfit-1.0 is included in GearSweep - the proficiency data
(which classes can't use which armor/weapon subclasses) was reimplemented
in GearSweep's own table format and code style, since no live WoW API
exposes this for Warband Bank items (confirmed live: neither the item
tooltip nor `C_Item.IsUsableItem` carries this signal for such items).
