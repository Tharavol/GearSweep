# GearSweep

A World of Warcraft addon that helps clear out gear from your bank and
Warband Bank: pull items suitable for disenchanting (Adventurer-tier and/or
previous-season gear), and pull items that are upgrades for your character's
class and specialization.

Under active development. See the [milestones](../../milestones) and
[issues](../../issues) for the current plan and status.

## Features

- **Disenchant mode**: filters your bags and every bank tab (character bank
  and Warband Bank) for Uncommon/Rare/Epic equipment that's Adventurer-tier
  and/or from a previous season, ignoring non-gear whites like shirts and
  tabards. Filter further by quality, slot, item level range, and whether
  Adventurer-tier and previous-season gear are included independently.
  "Pull Selected" moves every checked item into your bags - GearSweep never
  disenchants anything on its own.
- **Upgrade mode**: switch the sweep window to Upgrade to filter your bags
  and bank for equipment your character can actually use - checked against
  class/armor/weapon proficiency and Blizzard's own "Best in Slot"
  spec-relevance signal - that's also a higher item level than what's
  currently equipped in that slot (or your average equipped item level, for
  a slot that's never been filled), then pre-checks the single highest item
  level candidate per slot (rings and trinkets: top two, since both are
  dual-slot; two-hand weapons and one-hand+offhand pairs never both get
  pre-checked - whichever has the higher average item level, comparing
  against whatever's currently equipped, wins). Uncheck a pre-selected
  pick or check a runner-up before pulling.
- **Auto-open**: opens the sweep window automatically when you visit your
  bank or Warband Bank. On by default; turn it off in the settings panel
  or with `/gs autoopen off`.

## Slash Commands

| Command | Description |
|---|---|
| `/gearsweep` or `/gs` | Opens the sweep window. |
| `/gs options` | Opens the settings panel (also: `config`, `gui`). |
| `/gs autoopen [on\|off]` | Toggles or sets auto-open on visiting the bank. |
| `/gs debug [on\|off]` | Toggles or sets diagnostic messages. |
| `/gs debug slots` | Prints current item level in every equipment slot. |
| `/gs debug upgrades` | Prints the items Upgrade mode currently selects, and the equipped item level each was compared against. |
| `/gs debug item <name>` | Prints an item's raw tooltip data (by case-insensitive substring match, bags/bank first, then equipped). |
| `/gs status` | Shows current settings. |
| `/gs version` | Shows the addon version. |
| `/gs reset` | Restores settings to defaults. |
| `/gs help` | Lists all commands. |

## Configuration

The sweep window (`/gs`) has a Mode toggle (Disenchant / Upgrade) plus filter
controls - quality, slot, and item level range are shared by both modes;
Adventurer-tier/previous-season toggles only apply to Disenchant. Click a
filter section's header to collapse or expand it and free up room for the
results list; collapsed state persists per section. All filter values
persist between sessions, independently per mode. Hover a result row for
the item's real tooltip, including the equipped-item comparison pane.

The settings panel (`/gs options`, or the standard WoW AddOns options menu)
holds the two toggles that don't belong to either mode: auto-open on
visiting the bank, and diagnostic (debug) logging. With debug logging on,
scanning, classification results, and pull actions print extra detail to
help track down a wrong classification without needing to reproduce it from
scratch.

## License

GPL-3.0-or-later - see [LICENSE](LICENSE). See
[ATTRIBUTION.md](ATTRIBUTION.md) for a third-party data source
cross-referenced (not vendored) in Classify.lua.
