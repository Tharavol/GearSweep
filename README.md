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
- **Upgrade mode**: not yet implemented (see the
  [v0.4.0 milestone](../../milestone/4)).
- Auto-open on visiting the Warband Bank: not yet implemented (see the
  [v0.5.0 milestone](../../milestone/5)).

## Slash Commands

| Command | Description |
|---|---|
| `/gearsweep` or `/gs` | Opens the disenchant sweep window. |
| `/gs options` | Opens the settings panel (also: `config`, `gui`). |
| `/gs debug [on\|off]` | Toggles or sets diagnostic messages. |
| `/gs status` | Shows current settings. |
| `/gs version` | Shows the addon version. |
| `/gs reset` | Restores settings to defaults. |
| `/gs help` | Lists all commands. |

## Configuration

The sweep window (`/gs`) has its own filter controls - quality, slot, item
level range, and Adventurer-tier/previous-season toggles - which persist
between sessions. The settings panel (`/gs options`, or the standard WoW
AddOns options menu) currently only has diagnostic logging; an auto-open
toggle lands with [v0.5.0](../../milestone/5).

## License

MIT - see [LICENSE](LICENSE).
