# GearSweep

A World of Warcraft addon that helps clear out gear from your bank and
Warband Bank: pull items suitable for disenchanting (Adventurer-tier and/or
previous-season gear), and pull items that are upgrades for your character's
class and specialization.

Under active development. See the [milestones](../../milestones) and
[issues](../../issues) for the current plan and status.

## Planned features

- Opens automatically when you visit the bank/Warband Bank, or via
  `/gearsweep` (alias `/gs`).
- Filter by item level, slot, quality, and season/tier (current season vs.
  Adventurer-tier / previous seasons).
- Disenchant mode: surfaces Uncommon/Rare/Epic equipment that's obsolete,
  ignoring non-gear whites like shirts and tabards.
- Upgrade mode: surfaces equipment your character can use and that's
  appropriate for your current specialization, auto-selecting the highest
  item level per slot.
- One button to pull everything selected into your bags. GearSweep never
  disenchants or equips anything on its own.

## Slash Commands

| Command | Description |
|---|---|
| `/gearsweep` or `/gs` | Opens the GearSweep options panel (also: `options`, `config`, `gui`). |
| `/gs debug [on\|off]` | Toggles or sets diagnostic messages. |
| `/gs status` | Shows current settings. |
| `/gs version` | Shows the addon version. |
| `/gs reset` | Restores settings to defaults. |
| `/gs help` | Lists all commands. |

## Configuration

Open the options panel with `/gs` (or via the standard WoW AddOns options
menu). Only diagnostic logging is configurable so far; filter and mode
options land as disenchant and upgrade mode are implemented (see
[milestones](../../milestones)).

## License

MIT - see [LICENSE](LICENSE).
