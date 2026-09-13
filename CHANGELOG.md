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

### Fixed
- A default-settings merge/reset that assigned a nested settings table by
  reference instead of copying it, which would have let the first filter
  change permanently corrupt what "reset" restores.
