# Desk Pets - design

Living document. Decisions are marked **Decided**, ideas still being weighed are marked **Open**.

## Pitch

An idle collecting game that lives on your desktop. Pull loot boxes, collect pets built from
random parts in rare variations, and chase an extremely rare pet over months. One pet walks on
your windows while you work; behind it, a swarm of thousands goes down into dungeons to fund your
next pulls. Not all of them come back.

Paid game on Steam. All loot boxes and gambling use in-game currency only; nothing is ever sold
for real money.

## Pillars

1. **Collect (the heart).** Opening boxes has to feel like opening trading card packs: the
   reveal, the glow, the rare pull. The collection book and its variations are the long chase.
   (Inspiration: TCG Card Shop Simulator - foils, ghost foils, the urge to open one more.)
2. **Care (active, one pet).** The pet on your desktop, and hands-on activities for when you
   focus on the game.
3. **Dungeons (idle, the swarm).** No thinking needed, time-gated, scales from one pet to
   hundreds of thousands. Produces the loot that feeds the other two pillars.

Visually non-intrusive: the game is a small pinned home panel plus a pet that can walk on top of
your windows. It hides when something is fullscreen.

## Theme

**Decided.** On the outside, a cute pastel collect-a-desktop-pet game. In reality, you're sending
troops off to be killed. The mask slips slowly as you progress.

- **Never graphic.** No blood or gore, nothing shown. Target around PEGI 12 (the simulated
  gambling likely sets that floor anyway). The darkness lives in small things an adult notices and
  a kid reads as innocent: wording, implication, odd details.
- **Progress drives it.** Early game is pure cute: open boxes, collect pets, care for one on your
  desktop. Deeper dungeons and later bosses slowly bring in desaturated palettes, colder wording
  and stranger pet behaviour.
- **The arc:** early on you open cute pets. Late game you send hundreds into a dungeon to find
  the one part that makes your favourite cat perfect.
- **Plushie logic** (**Open**): parts are sewn on with stitches and button eyes, so grafting reads
  as crafting.
- **Examples:** "send on an adventure" becomes "send", then "7 came home"; lost pets get a quiet
  star in the book; the perfect pet watches the others a bit too long.

## Core loop

```
 open boxes ──> new pets, parts, gear ──> collection book
      ^                                        │
      │                                        v
   coins, boxes <──  dungeons   <── gear up, craft, risk your best pets
```

- **Active play advances faster than idling** (target roughly 3-5x). Checking in is always
  rewarded, never required. **Decided**
- **Pets are only lost by choice** - by sending them into a dungeon or betting them on a risk
  option. Not checking in never costs you a pet. **Decided**
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
- **Stats** - e.g. power, luck, speed, used in dungeons. Rolled in a range set by rarity.

Rarity tiers: common, uncommon, rare, epic, legendary, mythic. A pet's overall rarity comes from
its parts and finish together.

**Open:** how many parts per slot at launch; whether trait count grows with rarity.

## Loot boxes

- Bought with coins, found in dungeons, given as check-in rewards. Never sold for money.
  **Decided**
- Different box types have different odds (starter box, part-focused boxes, boss boxes).
- The odds are always visible in game.
- **Opening one box** (the first hours are all about this moment, so it gets a real ritual).
  **Decided**
  1. A sealed card pack lands. You rip the strip off the top along the tear line.
  2. Light comes out and climbs the tiers one at a time with a pause between each
     (grey → green → blue → purple → gold → pink) and stops at the real rarity. Every step adds
     an effect layer on top of the ones before (glow, sparkles, beams, rotating beams + dim,
     fountain + pack shake, shockwave + screen shake), so rare pulls look nothing like common
     ones. Pauses are short at low tiers and long at high ones. It never shows higher than the
     real rarity.
  3. You pull the pet out of the pack by dragging it up, as slowly or quickly as you like.
  4. Pulls of 1% or rarer (judged by the odds of the box you opened) come out behind a blocker
     (sparkly mist) that you drag around to peek at parts, then flick away.
  5. Celebration scaled by rarity (Vampire Survivors chest style, but a card pack), then the finish as a second
     surprise ("...and it's HOLO!"), then the card with NEW stamps on first-time parts.
  - Space or double-click skips to the result. Settings: reveal speed, skip single reveals, skip
    the rare ritual. All timings and per-tier effects live in `data/reveal.json`.
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

## Dungeons (idle side)

- **Decided:** the spine of progression. Runs continue while the game is closed and act as a time
  gate.
- You send pets down; some come back with loot and some don't. Sending them is the choice that
  risks them. Deeper floors pay better and fewer come home.
- Scale: 1 pet → a few with gear → 10 → hundreds → 100k+.
- Loot: coins, food, XP, loot boxes, gear, body parts.
- **Body parts are the late-game chase:** a rare part found deep down gets grafted onto your
  favourite pet (see Theme). Mass pets are sacrificable scaling; the real chase is a couple of
  extremely good pets you've built up for a long time. They lead runs and give big bonuses.
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
- **Grafting** - move a part from one pet onto another; the donor doesn't come back.

## Gear

- Bought or gambled (boxes), also dropped in dungeons.
- Equipped on pets for dungeon runs. **Open:** slots, and whether gear can be crafted.

## Economy (first numbers, to be tuned)

- Coins: passive trickle while running, a bigger share from dungeons and active play.
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
2. Dungeons: foraging first, then raids. (moved ahead of care: it's where the theme starts)
3. Care: the desktop pet uses your chosen pet; buffs and check-in rewards.
4. Risk and crafting.
5. Activities: junkyard, NPC trading.
6. Real art, Windows port, Steam.
