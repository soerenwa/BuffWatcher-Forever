# BuffWatcher Forever

**Never pull without your buffs again.** BuffWatcher is a small, clean buff tracker for **World of Warcraft: Forever**. One look tells you whether you are Well Fed, have your Campfire buff, your Sleeping Bag XP bonus and every class buff your party can give you.

White means active, red means missing. When everything is up, the panel turns green.

---

## What it tracks

### Food, Campfire and Sleeping Bag
- **Well Fed:** shows what your food gives, read from the tooltip, for example `25 Str, 10 Sta`.
- **Camp Benefits:** shows every stat from your campfire. Stats that a class buff already covers are shown in grey, since camp objects don't stack with the matching class buff.
- **Sleeping Bag:** shows your XP bonus and the time left. The row turns orange when less than an hour is left, so you know the bag can be used again. While you lie in the bag, a bar counts down to the next Well-Rested refresh. At max level the row is hidden by default, since the XP bonus does nothing there.

### Party Buffs
In a party (not in raids), BuffWatcher checks the class buffs your group can actually give you:

- **Fortitude** (Priest)
- **Mark of the Wild** (Druid)
- **Arcane Intellect** (Mage, only for classes that use mana)
- **One Blessing per Paladin**
- **Battle Shout** (Warrior, melee only, including Druids in Cat or Bear Form)

If nobody in your party can cast a buff, it isn't shown, so you are never nagged about buffs you can't get.

### Party Grid
Open the grid from the header bar to see **who in your party has which buff**. Hover a cell to see the time left. A check turns orange when less than 20% of a buff's duration is left, so you know who needs a rebuff.

---

## Warnings
- A **chat message and a sound** play when a buff runs out.
- An optional **early warning** in chat a few minutes before a buff ends (0 to 30 minutes, default 5).

## Three styles
- **Forever:** matches the client's own unit frames.
- **Modern:** dark panels with purple accents.
- **Classic:** the familiar Blizzard tooltip look.

## Options
Click the buttons in the header bar or type **/bw** (or **/buffwatcher**).

- Lock the panel
- Horizontal or vertical layout
- Warning sound and chat on or off
- Hide the panel when all buffs are fine
- Show the Sleeping Bag at max level
- Style and scale
- Warning time before a buff runs out
- Reset position

---

## Good to know
- **Combat:** WoW Forever does not let addons read buffs during combat. BuffWatcher keeps the last known state, counts down from it and updates again right after combat.
- Party members who are offline or out of range show `?` in the grid.
- Buff names are matched in English, so BuffWatcher works with the **English (enUS) client**.

## Feedback
Found a bug or have an idea? Open an issue on [GitHub](https://github.com/soerenwa/BuffWatcher-Forever/issues).
