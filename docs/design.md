# Desk Pets - design

Living document. Decisions are marked **Decided**, ideas still being weighed are marked **Open**.

## Pitch

An idle collecting game that lives on your desktop. Pull loot boxes, collect pets built from
random parts in rare variations, and chase an extremely rare pet over months. One pet walks on
your windows while you work; behind it, a swarm of thousands runs expeditions that fund your next
pulls.

Paid game on Steam. All loot boxes and gambling use in-game currency only; nothing is ever sold
for real money.

## Pillars

1. **Collect (the heart).** Opening boxes has to feel like opening trading card packs: the
   reveal, the glow, the rare pull. The collection book and its variations are the long chase.
   (Inspiration: TCG Card Shop Simulator - foils, ghost foils, the urge to open one more.)
2. **Care (active, one pet).** The pet on your desktop, and hands-on activities for when you
   focus on the game.
3. **Expeditions (idle, the swarm).** No thinking needed, time-gated, scales from one pet to
   hundreds of thousands. Produces the loot that feeds the other two pillars.

Visually non-intrusive: the game is a small pinned home panel plus a pet that can walk on top of
your windows. It hides when something is fullscreen.

## Core loop

```
 open boxes ──> new pets, parts, gear ──> collection book
      ^                                        │
      │                                        v
   coins, boxes <── expeditions <── gear up, craft, risk your best pets
```

- **Active play advances faster than idling** (target roughly 3-5x). Checking in is always
  rewarded, never required. **Decided**
- **Pets are only lost by choice** - by betting them on a risk option. Not checking in never
  costs you a pet. **Decided**
- Idle rewards pile up while the game is closed and are collected on the next check-in, capped
  (around a day) so checking in once or twice a day is worth it.

## Pets

A pet is built from **parts**, each rolled with a rarity:

| Part | Examples |
|---|---|
| Body | blob, cat, bunny, slime, robot |
| Palette | lilac, mint, peach, void, gold |
| Pattern | plain, spots, stripes, stars, circuit |
| Eyes | round, sleepy, sparkle, x-eyes |
| Accessory | none, bow, crown, halo, headphones |

On top of the parts, every pet rolls:

- **Finish** - the "foil" layer, shown on the pet itself:
  normal → shiny → holo → ghost → glitch → prismatic (rarer each step).
- **Traits** - personality; changes behaviour on the desktop and gives modifiers
  (e.g. *greedy*: more coins, *brave*: better at bosses, *lazy*: naps more).
- **Stats** - e.g. power, luck, speed, used on expeditions. Rolled in a range set by rarity.

Rarity tiers: common, uncommon, rare, epic, legendary, mythic. A pet's overall rarity comes from
its parts and finish together.

**Open:** how many parts per slot at launch; whether trait count grows with rarity.

## Loot boxes

- Bought with coins, found on expeditions, given as check-in rewards. Never sold for money.
  **Decided**
- Different box types have different odds (starter box, part-focused boxes, boss boxes).
- The odds are always visible in game.
- Reveal: a card-style opening with a glow colour hinting at rarity and a longer pause before
  rare pulls.
- Mass open for large piles, with a summary that highlights the best pulls.

## Collection book

- Tracks every part discovered, and every finish seen for each body.
- Shows how many of each you've pulled, with undiscovered entries as silhouettes.
- Owned pets: the list of pets you have, sortable by rarity, finish and stats.
- **Open:** completion rewards (per page, per body, per finish set).

## Care (active side)

- The desktop pet: walks on your windows, reacts to pats, can be parked at home.
- Needs (hunger, mood) are opportunities, not threats: caring gives temporary buffs
  (e.g. well fed = +50% coins for 2 hours).
- Activities for when you're focused on the game: junkyard digging for parts, trading with NPCs,
  crafting. **Open:** exact list and order.
- Desktop events while the pet is out: finding coins on window edges, catching falling things,
  rare visitors.

## Expeditions (idle side)

- **Decided:** the spine of progression. They run while the game is closed and act as a time gate.
- Scale: 1 pet → a few with gear → 10 → hundreds → 100k+.
- Loot: coins, food, XP, loot boxes, gear, body parts.
- Mass pets are sacrificable scaling. The real chase is a couple of extremely good pets you've
  built up for a long time; they lead expeditions and give big bonuses.
- Suggested structure (**Open**):
  - **Foraging** - each pet runs its own trip and brings its own loot. More pets = more rolls.
  - **Raids** - all pets pooled as one force against a boss. Bosses gate progression, and the
    rarest parts and finishes only drop from them.

## Risk and crafting

All opt-in, with odds shown before confirming:

- **Double or nothing** - a glitch treat either upgrades a pet (part, trait, stats or finish) or
  loses it.
- **Fusion** - sacrifice pets to roll a new one, with better odds from rarer inputs.
- **Reroll** - reroll one part or trait; it can come out worse.
- **Crafting** - improve a pet or build gear from loot, with a chance to fail.
- **Risky expeditions** - better loot, a chance the pet doesn't return.

## Gear

- Bought or gambled (boxes), also dropped by expeditions.
- Equipped on pets for expeditions. **Open:** slots, and whether gear can be crafted.

## Economy (first numbers, to be tuned)

- Coins: passive trickle while running, a bigger share from expeditions and active play.
- Starter box cost around a few minutes of active play.
- Idle cap: about 24 h of rewards.

## Legal and rating notes

- Paid game, in-game currency only. **Decided**
- Trading pets on the Steam Market could make boxes count as loot boxes under Belgian/Dutch rules.
  **Open:** no trading, player-to-player only, or region locks.
- Simulated gambling: Australia rates it R18+ (since 2024). Check other regions before the store
  page.

## Platform

- Developed on Linux/Hyprland first, then Windows. Steam release (GodotSteam later).
- Window detection sits behind `scripts/platform/window_source.gd`, one backend per platform.

## Build order

1. **Core: boxes and collection** - rolling pets from parts, opening boxes, the collection book,
   placeholder colours instead of art. (current)
2. Care: the desktop pet uses your chosen pet; buffs and check-in rewards.
3. Expeditions: foraging first, then raids.
4. Risk and crafting.
5. Activities: junkyard, NPC trading.
6. Real art, Windows port, Steam.
