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
  and bank for equipment your character can actually use - matching
  Blizzard's own class/armor/weapon proficiency and "Best in Slot"
  spec-relevance signals - that's also a higher item level than what's
  currently equipped in that slot, then pre-checks the single highest item
  level candidate per slot (rings and trinkets: top two, since both are
  dual-slot; two-hand weapons and one-hand+offhand pairs never both get
  pre-checked). Uncheck a pre-selected pick or check a runner-up before
  pulling.
- Auto-open on visiting the Warband Bank: not yet implemented (see the
  [v0.5.0 milestone](../../milestone/5)).

## Slash Commands

| Command | Description |
|---|---|
| `/gearsweep` or `/gs` | Opens the disenchant sweep window. |
| `/gs options` | Opens the settings panel (also: `config`, `gui`). |
| `/gs debug [on\|off]` | Toggles or sets diagnostic messages. |
| `/gs debug slots` | Prints current item level in every equipment slot. |
| `/gs debug upgrades` | Prints the items Upgrade mode currently selects, and the equipped item level each was compared against. |
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
the item's real tooltip, including the equipped-item comparison pane. The
settings panel (`/gs options`, or the standard WoW AddOns options menu)
currently only has diagnostic logging; an auto-open toggle lands with
[v0.5.0](../../milestone/5).

## License

MIT - see [LICENSE](LICENSE).
