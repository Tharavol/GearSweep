# Changelog

All notable changes to GearSweep are documented in this file.

## [Unreleased]

### Added
- Project scaffolding: `.toc`, core init, options panel skeleton, and slash
  command dispatch (`/gearsweep`, alias `/gs`).
- CI: luacheck, an offline test suite, and packager dry-run verification.
- Scanner.lua: enumerates equipment across bags and every purchased bank
  tab (character bank and Warband Bank), discovered dynamically via
  `C_Bank` rather than hardcoded bag IDs.
- Classify.lua: identifies current-season vs. previous-season/expansion
  gear and Adventurer-tier items from the tooltip's upgrade-track data,
  Blizzard's own "usable" flag, and spec-relevance from the tooltip's
  "Best in Slot" annotation.
- Confirmed the bank-open hook (`BANKFRAME_OPENED`) and the item
  withdrawal mechanism (bag/bank slots share one pickup/place API).
- Disenchant sweep window (`/gs`, or `/gearsweep`): filter by quality, slot,
  item level range, and Adventurer-tier/previous-season inclusion; a
  scrollable results list with per-item checkboxes; "Pull Selected" moves
  every checked item into your bags.
- Upgrade.lua: classifies equipment as usable by the current character
  (class/armor/weapon proficiency, reusing the same tooltip "usable" signal
  as Classify.lua), spec-appropriate, and actually higher item level than
  what's currently equipped in that slot (the lower of the two equipped
  items for dual-slot rings/trinkets), then auto-selects the single highest
  item-level candidate per slot - rings and trinkets: top two distinct
  items; two-hand weapons and one-hand+offhand pairs are scored as a set so
  both never get pre-checked together.
- A Mode toggle (Disenchant / Upgrade) on the sweep window: Upgrade mode
  drives the same results list and "Pull Selected" action from
  upgrade-candidate classification instead, pre-checking only the
  best-per-slot picks while leaving every other usable candidate visible
  and selectable.
- `/gs debug slots` and `/gs debug upgrades` (#28): print current item
  level in every equipment slot, and the items Upgrade mode currently
  selects alongside the equipped item level each was compared against -
  diagnostics for tracking down why Upgrade mode's candidate set doesn't
  match expectations against real, live gear.
- Collapsible Quality/Slot/Season-Tier filter sections (#32): click a
  section's header to collapse or expand it, freeing space for the
  results list. Collapsed state persists between sessions, per section.
- Results list rows now show the real item tooltip on hover - including
  Blizzard's automatic equipped-item comparison pane - exactly as if the
  item were being hovered directly in bags/bank (#33).
- `/gs debug item <name>` (#35): finds an item in bags/bank by
  case-insensitive substring and dumps its raw tooltip data (plain text
  plus every structured C_TooltipInfo line's type/usable/leftText)
  alongside IsUsable's verdict - for diagnosing class/armor/weapon
  proficiency misses without guessing at tooltip structure again.

### Fixed
- A default-settings merge/reset that assigned a nested settings table by
  reference instead of copying it, which would have let the first filter
  change permanently corrupt what "reset" restores.
- A crash opening the sweep window: anonymous checkboxes have no frame
  name to look up their label text through.
- A crash rendering results: `C_Item.GetItemQualityColor` returns plain
  r/g/b numbers on this client, not a color table.
- The Slot filter's last two rows overlapping the Season/Tier section -
  the layout now computes each section's height instead of guessing the
  gap between sections.
- `Scanner.lua` read `hyperlink` from `GetItemInfo`'s return value instead
  of the container slot's own link, which can silently point at a
  differently-itemized cached copy of the item (missing this instance's
  actual upgrade-track bonus IDs).
- Upgrade mode listed items with no regard for what's actually equipped
  (e.g. item level ~100-141 quest rewards, against item level 238 equipped
  gear) - "usable" and "spec-appropriate" alone don't mean "better than
  what you're wearing."
- The sweep window didn't close on Escape like other standard windows
  (#29): now registered with `UISpecialFrames`.
- The sweep window's frame layer was mixed with bag/bank container frames
  instead of consistently on top (#30): with bags and the Warband Bank
  open, it rendered interleaved with them, with other addons' UI showing
  through in the gaps. Now uses an explicit "HIGH" strata and toplevel,
  matching those windows.
- Upgrade mode showed disenchant-eligible junk (ilvl 14-141 items against
  ilvl 238 equipped gear) alongside real upgrades (#31): a `X and Y or Z`
  expression in UI.lua's mode dispatch fell through to the disenchant gate
  whenever the upgrade gate returned false, the common case, instead of
  correctly excluding the item.
- Collapsing a filter section overlapped the next section's header (#34):
  RelayoutFrame only advanced past a section's own header row when
  expanded (via the first checkbox row sharing it); collapsed sections
  never accounted for that row on their own.
- Upgrade mode suggested items the character's class can't equip at all
  (e.g. a shield on a Mage) (#35): confirmed live that the item's tooltip
  carried no class/armor/weapon proficiency signal whatsoever - the
  tooltip-based `IsUsable` check this relied on genuinely had no data to
  work with. Now also gated on `C_Item.IsUsableItem`, the actual Blizzard
  API for this, confirmed live to correctly report the mismatch.
