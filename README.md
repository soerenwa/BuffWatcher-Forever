# BuffWatcher Forever

A small, clean buff tracker for **World of Warcraft: Forever**. One look tells you whether you are Well Fed, have your Campfire buff, your Sleeping Bag XP bonus and every class buff your party can give you.

## Features

- **Food, Campfire and Sleeping Bag rows.** White means active, red means missing. The Sleeping Bag row turns orange when less than an hour is left, so you know the bag can be used again.
- **Stats at a glance.** Each active buff shows what it gives, read from its tooltip, for example `25 Str, 10 Sta` or `3% XP, 1h 12m left`.
- **Green panel** when all your buffs are up.
- **Sleeping Bag timer.** While you lie in the bag, a bar counts down to the next Well-Rested refresh.
- **Party Buffs row** (party only, not in raids). It checks Fortitude, Mark of the Wild, Arcane Intellect, one Blessing per Paladin and Battle Shout. Battle Shout counts for melee only, including Druids in Cat or Bear Form.
- **Party grid.** Shows who in your party has which buff. Hover a cell for the time left. A check turns orange when less than 20% of a buff's duration is left.
- **Campfire overlap.** Camp objects don't stack with the matching class buff, and the class buff is always stronger. Campfire stats that are already covered are shown in grey.
- **Warnings.** A chat message and a sound play when a buff runs out, plus an optional chat warning a few minutes before.
- **Header bar** with the party grid, options, a horizontal/vertical layout switch and a lock.
- **Three styles:** *Forever* (matches the client's unit frames), *Modern* (dark with purple accents) and *Classic* (Blizzard tooltip look).

## Usage

- Drag the panel to move it, unless it is locked.
- Use the buttons in the header bar, or type `/bw` (or `/buffwatcher`) to open the options.

### Options

- Lock panel
- Horizontal layout
- Warning sound and chat
- Hide when all buffs are fine
- Show Sleeping Bag at max level (hidden at max level by default, since the XP bonus does nothing there)
- Style: Forever, Modern or Classic
- Scale
- Warning time before a buff runs out
- Reset position

## Good to know

- WoW Forever does not let addons read buffs during combat. BuffWatcher keeps the last known state, counts down from it and updates again right after combat.
- Party members who are offline or out of range show `?` in the grid.
- Buff names are matched in English (enUS client).

## Compatibility

World of Warcraft: Forever (Interface 16001).

## Feedback

Bugs and ideas: [GitHub issues](https://github.com/soerenwa/BuffWatcher-Forever/issues)
