# Desk Pets (working title)

An idle game that lives on your desktop. A pet hangs out on your screen while you work or
play; you keep it fed and happy, it earns coins in the background, and you spend coins on
packs that hatch new pets and rare variants.

## Core loop

1. **Care** - hunger, happiness and health drop over time; feed, pet and check up on your
   pet. Neglect can lead to complications you have to treat.
2. **Earn** - coins trickle in while the game runs; pets go on adventures (risky, rewarding)
   and errands (safe idle jobs) for coins, parts and boxes.
3. **Open packs** - coins buy packs that hatch random pets from part combinations, with
   rarities.
4. **Collect** - a collection book of every pet and variant found.
5. **Trade (later)** - players trade pets, e.g. through the Steam Inventory / Community
   Market.

## Pets from parts

Pets are assembled from layered parts instead of drawn one by one:
body shape x colour palette x pattern x eyes x accessory. A few dozen drawings give
thousands of combinations, and rarity comes from rare parts (shiny palettes, glitch
patterns, tiny crowns).

## Ground rules

- Packs are earned by playing, never bought with real money (loot-box regulations).
- The pet must never get in the way: it is a transparent, click-through overlay.
- Pixel art, nearest-neighbour filtering (set in project settings).

## Layout

- `scenes/` - Godot scenes
- `scripts/` - GDScript
- `art/parts/` - pet part sprites (bodies, palettes, patterns, accessories)
- `data/` - pet part and rarity definitions
- `docs/` - design notes

## Running

Open the folder in Godot 4.7 (`godot -e .`) or run it with `godot .`.
