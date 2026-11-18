# Changelog

## 1.14.1

**Raids**
- New **Flask / Elixir** row in raids. It replaces the Campfire row there and shows the stats of your flask or elixir.
- Recognizes the new Forever flasks (Natural Accuracy, Aggression, Precision, Swiftness) and elixirs like Grizzly, Owl, Whale, Cunning, Ferocity, Sages, the Cleric's Elixirs and Distilled Firewater. Defensive elixirs (Fortitude, Phalanx, Defense, Troll's Blood, Mageblood) don't count.
- **Raid Buffs:** the party buff row now works in raids too. Every Paladin in the raid counts, so with 2 Paladins you need 2 Blessings.
- Battle Shout only counts Warriors in your own raid group.
- The buff grid shows your raid group, with a Flask / Elixir column instead of Campfire.

**Campfire**
- **Campfire timer:** while you sit at a campfire, a bar under the Campfire row counts down until Camp Benefits arrives.
- No more "has run out" warning for the Campfire while you are in a raid.

**Other**
- Renamed from BuffWatch to **BuffWatcher Forever**. New slash command `/buffwatcher`, `/bw` still works.
- Settings start fresh because of the new name. If you used BuffWatch before, delete the old `BuffWatch` folder from `Interface\AddOns`.
